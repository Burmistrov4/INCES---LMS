-- ===========================================================================
--  Módulo 4 — Inscripciones y Cupos: ENCENDER EL MÓDULO
-- ===========================================================================
--  Qué hace
--  --------
--  Pone `system_modules.habilitado = true` en la fila `m4_inscripciones`.
--
--  Por qué existe como migración y no como un `update` a mano
--  ----------------------------------------------------------
--  Porque el libro mayor (`schema_migrations`) es lo que permite responder «¿qué
--  está aplicado en producción?» sin adivinar. Un `update` suelto por la consola
--  de Supabase deja el estado real indistinguible del estado del repositorio, y
--  eso es exactamente el defecto que produjo D11 y que se repitió con
--  `202609130002` (cerrada en el repo, sin llegar nunca a la nube).
--
--  OJO CON LOS NOMBRES DE COLUMNA
--  ------------------------------
--  La tabla `system_modules` **no** tiene `id` ni `is_enabled`:
--
--      clave        text      -- 'm4_inscripciones'
--      habilitado   boolean   -- la bandera
--
--  Un `update system_modules set is_enabled = true where id = '...'` falla con
--  `42703` (columna inexistente). Se deja escrito porque es el error que se
--  comete de memoria y cuesta un ciclo de ida y vuelta descubrirlo.
--
--  Qué NO hace
--  -----------
--  No toca `roles_permitidos`, que sigue en `'{}'` (lista vacía = visible para
--  todos los roles). No toca el orden ni el icono. No enciende `habilitar_sistema_bids`:
--  el motor de bids sigue APAGADO por decisión de producto, y son dos cosas
--  distintas — una es «el módulo se puede usar», la otra es «se ofrecen asientos
--  con vencimiento en vez de promoción directa».
--
--  Efecto sobre la API
--  -------------------
--  **Ninguno, y conviene saberlo.** Ninguna ruta del backend comprueba la bandera
--  del módulo: `exigirModulo()` existe en `src/http/plugins/modulos.ts` pero no lo
--  usa nadie. Hoy la bandera la respeta el frontend, que oculta el ítem del menú.
--  Esta migración deja el estado coherente con lo que ya funciona; que la API
--  además lo imponga es una decisión de diseño aparte, no un efecto de esto.
-- ===========================================================================

do $$
declare
  v_afectadas int;
begin
  update public.system_modules
     set habilitado = true
   where clave = 'm4_inscripciones';

  get diagnostics v_afectadas = row_count;

  -- Si la fila no existe, el `update` no habría hecho nada y el módulo seguiría
  -- apagado sin que nadie se enterara. Fallar aquí convierte un silencio en un
  -- error que nombra la causa: falta la semilla de `202609120002`.
  if v_afectadas = 0 then
    raise exception
      'No se encontró la fila m4_inscripciones en system_modules. '
      'Falta aplicar la semilla de 202609120002_phase3_admin_core.sql.'
      using errcode = '23514';
  end if;
end $$;

comment on table public.system_modules is
  'Interruptores de los módulos del sistema. `habilitado` los enciende y apaga desde el Administrador Maestro; `roles_permitidos` vacío significa visible para todos los roles. Ojo: la API todavía NO comprueba esta bandera — hoy la respeta sólo el frontend (exigirModulo() está definido y sin usar).';
