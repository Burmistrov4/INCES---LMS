-- ============================================================================
--  INCES LMS — Módulo 4: guardia de escritura de la planilla de inscripción
--  Archivo: 202609240002_mod4_planilla_guardia.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ ESTABA ABIERTO
--  ------------------
--  `202609240001` dejó la validación de la planilla dentro de `handle_new_user()`
--  y la condicionó a que el cliente mandara la clave `datos_planilla`. Eso cierra
--  el camino del `signUp`… y **sólo** ese camino.
--
--  Medido en la nube antes de escribir esto (no deducido):
--
--    · `authenticated` tiene `UPDATE` sobre `public.aspirantes` — lo concede el
--      privilegio por defecto de Supabase para las tablas de `public`, y ninguna
--      migración lo revocó nunca.
--    · La política `aspirantes_update_own` (202609100001) sigue viva y permite
--      `for update to authenticated using (user_id = auth.uid())`.
--    · El único trigger sobre la tabla era `aspirantes_set_updated_at`.
--
--  Consecuencia: cualquier usuario con sesión podía escribir
--
--      PATCH /rest/v1/aspirantes?user_id=eq.<su propio id>
--      { "datos_planilla": <cualquier cosa> }
--
--  usando la clave publishable que viaja dentro del bundle de Flutter (ADR-003).
--  Es decir, `validar_planilla()` era **evitable en una petición HTTP**, y la
--  cabecera de `202609240001` dice literalmente que sin validación en la base
--  «un cliente malicioso mete cualquier JSON en `datos_planilla` — y esa columna
--  es exactamente la que después va a leer la exportación hacia HACER».
--
--  POR QUÉ NO BASTABA CON VALIDAR EN EL BACKEND
--  --------------------------------------------
--  ADR-003: **la frontera de autorización es la RLS, no la API.** Si la ruta
--  `PUT /api/v1/yo/planilla` valida y la columna sigue siendo alcanzable por
--  PostgREST con el token del propio usuario, la validación de la ruta es
--  decorativa: basta con no usarla. La comprobación tiene que estar donde el
--  cliente no pueda rodearla.
--
--  POR QUÉ `before insert or update of datos_planilla`
--  ---------------------------------------------------
--  · `update OF datos_planilla` y no `update` a secas: una edición que no toca
--    la planilla (un teléfono, un correo) no tiene por qué revalidarla. Con
--    `update` a secas, una fila legítimamente vacía —`{}`, la de todo el que se
--    registró con el formulario viejo— no se podría tocar nunca más.
--  · `insert` también, y no es redundante: `aspirantes_insert_own` existe, así
--    que un usuario sin ficha (por ejemplo alguien registrado como docente)
--    podría crear la suya con una planilla arbitraria. El camino normal —el
--    insert de `handle_new_user`— vuelve a validar lo que ya validó, y volver a
--    validar lo mismo no cambia el resultado.
--
--  LA GUARDIA DEL `'{}'`: LA ASIMETRÍA SIGUE EN PIE
--  -----------------------------------------------
--  El envoltorio NO valida cuando la planilla es el objeto vacío. Es lo que
--  mantiene intacta la decisión de `202609240001`:
--
--    * Un cliente viejo inserta `{}` (no manda la clave) → la ficha se crea como
--      siempre. Cero regresión.
--    * Un cliente nuevo manda la planilla → se valida, venga por `signUp` o por
--      un `update` directo.
--
--  Sin esa guardia, el `default '{}'` de la columna sería inválido por
--  definición y el alta del formulario actual empezaría a fallar con un 23514
--  que nombra trece campos que el formulario viejo nunca preguntó.
--
--  POR QUÉ EL ENVOLTORIO ES `security definer`
--  -------------------------------------------
--  Es la lección de `202609180002`, que existe precisamente porque dos
--  envoltorios se dejaron como `invoker` y el módulo entero quedó inoperable con
--  `42501 permission denied for function`. Aquí el llamante es `authenticated`,
--  que hoy sí tiene EXECUTE sobre `validar_planilla()` por el privilegio por
--  defecto — pero no se depende de eso: con `definer`, la comprobación se hace
--  contra el dueño y una futura restricción de EXECUTE no rompería la escritura.
--
--  `security definer` NO amplía lo que el llamante puede escribir: la RLS de
--  `aspirantes` se evalúa aparte, en el ejecutor de la sentencia, y sigue
--  exigiendo `user_id = auth.uid()` o `is_admin()`. El envoltorio sólo comprueba
--  y no devuelve dato alguno. Tampoco es invocable a mano: PostgreSQL no deja
--  llamar directamente a una función que devuelve `trigger`.
--
--  OJO CON LAS PRUEBAS
--  -------------------
--  La aserción de este archivo **no vale corriendo como `postgres`**: el dueño
--  se salta la comprobación de privilegios y además es el que escribe la
--  semilla. Hay que escribir como `authenticated` con los claims de un usuario,
--  que es lo que hace el backend con el JWT del llamante. Es exactamente el
--  fallo que `202609180002` documenta.
--
--  QUÉ NO HACE ESTE ARCHIVO
--  ------------------------
--  * No revoca el `UPDATE` de `authenticated` sobre `aspirantes`. El usuario
--    tiene que poder corregir sus propios datos; lo que no puede es saltarse la
--    validación, y eso es lo que impide el trigger.
--  * No toca `202609240001`. Una migración ya aplicada no se edita nunca.
--  * No valida tipos ni formatos: `validar_planilla()` valida FORMA (que los
--    obligatorios estén). Los tipos los valida Zod en el backend y el propio
--    formulario.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. El envoltorio
-- ---------------------------------------------------------------------------
-- Sólo dos líneas de lógica a propósito. Toda la decisión de qué es «falta un
-- campo» vive en `validar_planilla()`, que es la MISMA función que usa
-- `handle_new_user()`: una sola fuente de la regla, dos puertas.
create or replace function public.validar_planilla_guardada()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- `is distinct from` y no `<>`: con `<>`, un `datos_planilla` nulo daría NULL
  -- en la comparación, el `if` no entraría y la fila pasaría sin validar. La
  -- columna es `not null`, pero un JSON `null` sí es alcanzable.
  if new.datos_planilla is distinct from '{}'::jsonb then
    perform public.validar_planilla(new.datos_planilla);
  end if;

  return new;
end;
$$;

comment on function public.validar_planilla_guardada() is
  'Envoltorio de trigger: valida `aspirantes.datos_planilla` contra el catálogo, salvo cuando es el objeto vacío (que es el «sin planilla» del formulario viejo). Cierra el camino de escritura directa por PostgREST.';


-- ---------------------------------------------------------------------------
-- 2. El trigger
-- ---------------------------------------------------------------------------
-- `update of datos_planilla` limita el disparo a las escrituras que tocan la
-- planilla; `insert` cubre el alta directa por `aspirantes_insert_own`.
drop trigger if exists aspirantes_validar_planilla on public.aspirantes;
create trigger aspirantes_validar_planilla
  before insert or update of datos_planilla on public.aspirantes
  for each row execute function public.validar_planilla_guardada();


-- ---------------------------------------------------------------------------
-- 3. Comprobación de la propia migración
-- ---------------------------------------------------------------------------
-- Que el trigger exista y esté bien cableado. Un `create trigger` que no
-- dispara porque el nombre de la columna está mal escrito no falla: simplemente
-- nunca se ejecuta, y el síntoma aparecería como «la validación no valida» en
-- producción.
do $$
declare
  v_columna text;
begin
  select pg_get_triggerdef(t.oid) into v_columna
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'aspirantes'
     and t.tgname = 'aspirantes_validar_planilla';

  if v_columna is null then
    raise exception
      'No quedó el trigger aspirantes_validar_planilla sobre public.aspirantes.'
      using errcode = '23514';
  end if;

  -- La definición tiene que nombrar la columna: si no, el `update of` no se
  -- aplicó y el trigger dispararía en cada escritura de la fila.
  if position('datos_planilla' in v_columna) = 0 then
    raise exception
      'El trigger no está limitado a la columna datos_planilla: %', v_columna
      using errcode = '23514';
  end if;

  raise notice 'Guardia de planilla instalada: %', v_columna;
end $$;
