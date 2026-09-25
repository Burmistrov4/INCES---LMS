-- ============================================================================
--  INCES LMS — D14: `aspirantes.program_id` con clave foránea
--  Archivo: 202609250001_d14_aspirantes_program_fk.sql
--  Aplica con: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  D14 — `aspirantes.curso_seleccionado` guardaba el NOMBRE del curso en texto
--        libre. Renombrar un programa en M2 dejaba huérfanas las fichas que lo
--        habían elegido, sin error y sin aviso. Ahora la única referencia es
--        `program_id uuid REFERENCES public.programs(id)`, y el nombre se
--        resuelve por JOIN.
--
--  D14 NO ES NUEVA: `202609160001_resolucion_d12_d13.sql` (líneas 62-67) ya la
--  describía con estas mismas palabras y con esta misma solución, y decía por
--  qué se difería: `aspirantes` estaba vacía, así que el arreglo podía esperar a
--  que hubiera un motivo. Este archivo ejecuta esa decisión. No la reinventa.
--
--  Esta migración NO cierra D12 del todo: `public.cursos` sigue siendo la vista
--  de compatibilidad, y se retira en la fase en que Flutter lea `programs`
--  directamente. Ver "LO QUE ESTA MIGRACIÓN NO HACE".
--
--
--  MEDIDO ANTES DE ESCRIBIRLA, NO DEDUCIDO
--  ---------------------------------------
--  Contra la base real, el 2026-09-25:
--
--      aspirantes   0 filas
--      programs     6 filas  (1 CARRERA [SEMILLA] + 5 CURSO_LIBRE, todas activas)
--      cursos       VIEW (no tabla)
--      aspirantes   sin `program_id`; `curso_seleccionado` text NOT NULL
--      on_auth_user_created  AFTER INSERT ON auth.users → handle_new_user()
--
--  Con 0 filas, `ADD COLUMN ... NOT NULL` es directo: no hay backfill que hacer.
--  La PARTE 1 vuelve a comprobarlo dentro de la propia migración, para que el
--  día que esta premisa deje de ser cierta la migración **se niegue a correr**
--  en vez de rellenar en silencio con un valor inventado.
--
--
--  EL ÚNICO CAMINO DE ESCRITURA (por qué no se toca el backend)
--  -----------------------------------------------------------
--  La inscripción NO pasa por Fastify. Pasa por:
--
--      auth.signUp(data: metadata)
--        → auth.users.raw_user_meta_data
--        → trigger on_auth_user_created (AFTER INSERT)
--        → public.handle_new_user()
--        → insert into public.aspirantes
--
--  `backend/src` no menciona `curso_seleccionado` en ningún archivo y no inserta
--  en `aspirantes`: su única relación es `datos_planilla`, por `PUT /yo/planilla`.
--  Por eso D14 se resuelve aquí y no en Zod. Lo único que el backend tiene que
--  saber es que `23503` ya lo traduce a REFERENCIA_INVALIDA (`traducir-error.ts`),
--  y que `23502` (NOT NULL) sigue sin traducir.
--
--
--  LA DECISIÓN QUE NO ESTABA EN EL PLAN: RESOLUCIÓN TRANSITORIA
--  -----------------------------------------------------------
--  El formulario desplegado hoy manda el NOMBRE del curso. Si esta migración
--  exigiera un uuid sin más, el formulario público se rompería en el hueco entre
--  aplicarla y desplegar la Fase 2 — y lo haría de la peor forma posible: el
--  valor no resolvería, `v_es_aspirante` quedaría falso y **el aspirante vería
--  «registro exitoso» sin ficha**, que es exactamente el fallo silencioso que
--  este proyecto ya se comió una vez.
--
--  `resolver_programa_inscripcion()` acepta por tanto LOS DOS VOCABULARIOS:
--    · un uuid  → el nuevo, el que mandará la Fase 2;
--    · un nombre → el viejo, que resuelve contra `programs.name`.
--
--  Es transitorio y se retira cuando la Fase 2 esté desplegada. Está aquí y no
--  en el cliente a propósito: ADR-003 —la frontera de autorización es la RLS, no
--  la API— vale igual para la coherencia de los datos. Si la tolerancia viviera
--  en Dart, un cliente hecho a mano podría seguir mandando nombres para siempre.
--
--
--  POR QUÉ LA RESOLUCIÓN TAMBIÉN COMPRUEBA `is_active` Y `type`
--  -----------------------------------------------------------
--  `handle_new_user()` es `security definer`: **no pasa por RLS**. La política
--  `programs_read_activos` sólo limita a `anon`, así que dentro del trigger no
--  protege de nada. Si la comprobación no se hiciera explícitamente aquí, una
--  petición fabricada a mano podría inscribir a alguien en un programa en
--  borrador o en una CARRERA —que es justo lo que la Decisión 1 excluye de la
--  oferta pública de inscripción—. El desplegable filtrado en Flutter es
--  comodidad; la regla es esta.
--
--  Para relajar el filtro de `type` el día que el CFS abra carreras a la
--  inscripción pública, se edita esta función en una migración nueva. No se
--  toca el cliente.
--
--
--  LO QUE ESTA MIGRACIÓN NO HACE (a propósito)
--  -------------------------------------------
--  · **NO borra la vista `public.cursos`.** `SupabaseService.cursosDisponibles()`
--    (`lib/services/supabase_service.dart:227`, `_tablaCursos = 'cursos'`) la lee
--    para alimentar el desplegable del formulario público, y es su ÚNICO
--    consumidor. Borrarla aquí dejaría el formulario **sin opciones** hasta que
--    se despliegue la Fase 2. El propio `comment on view` de `202609160001` fija
--    el orden: «cuando `SupabaseService.cursosDisponibles()` lea `programs`
--    directamente, se borra la vista». Va en la fase de la vista, no en ésta.
--  · **NO renombra el código del catálogo.** `inscripcion_campos.codigo` sigue
--    siendo `curso_seleccionado`; lo que cambia es su VALOR (de nombre a uuid).
--    Renombrar el código arrastraría `sintetizarClavesPlanas`, el formulario y
--    cinco archivos de prueba, sin ganar nada que este comentario no arregle.
--  · **NO toca `202609240001` ni `202609240002`.** Una migración aplicada no se
--    edita nunca: el libro mayor detecta la deriva por checksum.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PARTE 1 — Guardia de la premisa
-- ---------------------------------------------------------------------------
-- La migración entera depende de que `aspirantes` esté vacía: `program_id` nace
-- NOT NULL y no hay forma de deducir el programa de una fila histórica (el
-- nombre guardado podría ya no existir, o ser ambiguo).
--
-- Un `ALTER TABLE ... ADD COLUMN ... NOT NULL` sobre una tabla con filas no falla
-- de forma obvia: si se añadiera con un DEFAULT, rellenaría todo de un valor
-- plausible y equivocado. Preferimos un error que diga qué pasó.
do $$
declare
  v_filas bigint;
begin
  select count(*) into v_filas from public.aspirantes;

  if v_filas > 0 then
    raise exception
      'D14: `aspirantes` tiene % filas y esta migración asume 0. '
      'Hay que decidir antes cómo se rellena `program_id` en las fichas '
      'históricas (¿por nombre? ¿a mano?) y escribir ese backfill. '
      'NO se ha modificado nada.', v_filas
      using errcode = '23514';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- PARTE 2 — El resolutor
-- ---------------------------------------------------------------------------
-- Una sola función, tres consumidores: `validar_planilla()` (la regla),
-- `handle_new_user()` (el alta) y `validar_planilla_guardada()` (la corrección
-- posterior). Es el mismo diseño que ya usan `validar_planilla()` y su envoltorio
-- —«una sola fuente de la regla, dos puertas»—, llevado a la resolución.
--
-- `stable` y no `volatile`: sólo lee. `security definer` porque la llama un
-- trigger que corre como `supabase_auth_admin`, que no tiene por qué poder leer
-- `programs`.
create or replace function public.resolver_programa_inscripcion(p_valor text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_texto  text := nullif(btrim(coalesce(p_valor, '')), '');
  v_uuid   uuid;
  v_id     uuid;
  v_cuantos int;
begin
  -- Ausente o vacío no es un error: es «este registro no trae propuesta
  -- formativa», que es el caso del alta de un docente o de un admin. Quien
  -- decide si eso impide crear la ficha es `handle_new_user()`, no esto.
  if v_texto is null then
    return null;
  end if;

  -- ---- (1) Vocabulario NUEVO: un uuid -------------------------------------
  begin
    v_uuid := v_texto::uuid;
  exception when invalid_text_representation then
    v_uuid := null;
  end;

  if v_uuid is not null then
    select p.id into v_id
      from public.programs p
     where p.id = v_uuid
       and p.is_active
       and p.type = 'CURSO_LIBRE';

    if v_id is not null then
      return v_id;
    end if;

    -- Distinguir «no existe» de «existe pero no es inscribible» importa: son dos
    -- errores distintos para quien los lee. El mensaje los separa.
    select count(*) into v_cuantos from public.programs p where p.id = v_uuid;

    if v_cuantos = 0 then
      raise exception
        'La propuesta formativa indicada no existe en la oferta formativa.'
        using errcode = '23503';
    end if;

    raise exception
      'La propuesta formativa indicada no está abierta a inscripción: sólo se '
      'puede elegir un curso de formación continua activo.'
      using errcode = '23503';
  end if;

  -- ---- (2) Vocabulario VIEJO: el nombre. TRANSITORIO ----------------------
  -- Vive aquí para que la migración pueda aplicarse ANTES de que el formulario
  -- nuevo esté desplegado. Se retira en la migración que siga al despliegue de
  -- la Fase 2 — ver la cabecera.
  --
  -- `programs.name` NO es único (sólo lo es `code`), así que un nombre puede
  -- estar repetido. Con dos coincidencias no se adivina: se rechaza y se dice
  -- por qué, en vez de elegir la primera y que la ficha apunte a un programa que
  -- el aspirante no eligió.
  select count(*) into v_cuantos
    from public.programs p
   where p.name = v_texto
     and p.is_active
     and p.type = 'CURSO_LIBRE';

  if v_cuantos > 1 then
    raise exception
      'Hay más de un curso llamado «%» en la oferta formativa, así que no se '
      'puede saber cuál se eligió. Renombra uno de los dos o inscribe con el '
      'identificador del curso.', v_texto
      using errcode = '23503';
  end if;

  if v_cuantos = 1 then
    select p.id into v_id
      from public.programs p
     where p.name = v_texto
       and p.is_active
       and p.type = 'CURSO_LIBRE';

    return v_id;
  end if;

  raise exception
    'La propuesta formativa «%» no existe en la oferta de formación continua, '
    'o no está activa.', v_texto
    using errcode = '23503';
end;
$$;

comment on function public.resolver_programa_inscripcion(text) is
  'Resuelve el valor de `curso_seleccionado` a un `programs.id`. Acepta un uuid (vocabulario nuevo) o un nombre exacto (vocabulario viejo, TRANSITORIO: se retira tras desplegar la Fase 2). Exige que el programa exista, esté activo y sea CURSO_LIBRE — comprobaciones que RLS no puede hacer dentro de un trigger security definer. Lanza 23503 con el motivo concreto.';

-- Sólo la llaman funciones `security definer` del propio esquema. Se cierra la
-- puerta a que un cliente la invoque por RPC: no filtra nada, pero exponer
-- funciones internas no tiene contrapartida.
revoke all on function public.resolver_programa_inscripcion(text)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- PARTE 3 — `validar_planilla()` aprende la regla
-- ---------------------------------------------------------------------------
-- Cuerpo copiado LITERAL de `202609240001` y ampliado con UN bloque al final.
-- Todo lo demás —qué cuenta como vacío, el `array_agg` de obligatorios, el
-- mensaje que nombra los campos— se copia sin cambiar una coma.
--
-- La regla vive aquí y no sólo en el insert porque esta función es la que
-- comparten las DOS puertas: el alta (`handle_new_user`) y la corrección
-- posterior (`validar_planilla_guardada`). Si estuviera en el insert, un
-- aspirante podría corregir su planilla más tarde y meter un programa inventado.
create or replace function public.validar_planilla(p_datos jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_faltan text[];
begin
  if p_datos is null then
    p_datos := '{}'::jsonb;
  end if;

  if jsonb_typeof(p_datos) <> 'object' then
    raise exception
      'La planilla tiene que ser un objeto JSON; llegó %.', jsonb_typeof(p_datos)
      using errcode = '23514';
  end if;

  select array_agg(c.codigo order by c.orden)
    into v_faltan
    from public.inscripcion_campos c
   where c.activo
     and c.obligatorio
     and (
          not (p_datos ? c.codigo)
       or p_datos -> c.codigo = 'null'::jsonb
       or (jsonb_typeof(p_datos -> c.codigo) = 'string'
           and btrim(p_datos ->> c.codigo) = '')
       or (jsonb_typeof(p_datos -> c.codigo) = 'array'
           and jsonb_array_length(p_datos -> c.codigo) = 0)
       or (jsonb_typeof(p_datos -> c.codigo) = 'object'
           and p_datos -> c.codigo = '{}'::jsonb)
     );

  if v_faltan is not null and array_length(v_faltan, 1) > 0 then
    -- El mensaje nombra los campos concretos, igual que hacen los triggers de
    -- M2, M3 y M4: un error que dice qué falta ahorra una sesión de depuración.
    raise exception
      'Faltan campos obligatorios en la planilla: %.', array_to_string(v_faltan, ', ')
      using errcode = '23514';
  end if;

  -- (D14) AÑADIDO. La propuesta formativa tiene que apuntar a un programa real.
  -- Sólo se comprueba si la clave viene: una planilla sin ella ya se ha rechazado
  -- arriba por obligatoria, y una planilla `'{}'` —el «sin planilla» del
  -- formulario viejo— no debe fallar aquí.
  if p_datos ? 'curso_seleccionado' then
    perform public.resolver_programa_inscripcion(p_datos ->> 'curso_seleccionado');
  end if;
end;
$$;

comment on function public.validar_planilla(jsonb) is
  'Comprueba que la planilla traiga todos los campos marcados obligatorios en `inscripcion_campos`, y (D14) que `curso_seleccionado` apunte a un programa inscribible. Lanza 23514 nombrando los campos que faltan, o 23503 si la referencia al programa no es válida.';


-- ---------------------------------------------------------------------------
-- PARTE 4 — `handle_new_user()` deriva la clave
-- ---------------------------------------------------------------------------
-- Cuerpo copiado LITERAL de `202609240001` con TRES cambios:
--
--   1. `v_curso text` → `v_programa uuid`, resuelto con el resolutor;
--   2. la condición `v_es_aspirante` mira `v_programa` en vez del texto;
--   3. el insert escribe `program_id` en vez de `curso_seleccionado`.
--
-- Las 17 claves, las 10 condiciones, el parseo defensivo y el cálculo de
-- `requires_legal_tutor` en SQL se copian sin cambiar una coma.
--
-- De dónde sale el valor, y por qué en ese orden: la planilla es el documento
-- canónico, así que manda `v_planilla ->> 'curso_seleccionado'`; la clave plana
-- es el respaldo del cliente viejo, que no manda `datos_planilla`. Es el mismo
-- orden que ya sigue el formulario, que sintetiza las claves planas DESDE la
-- planilla (`sintetizarClavesPlanas`).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_meta         jsonb   := coalesce(new.raw_user_meta_data, '{}'::jsonb);

  v_cedula       text    := nullif(trim(coalesce(v_meta ->> 'cedula', '')), '');
  v_nombres      text    := nullif(trim(coalesce(v_meta ->> 'nombres', '')), '');
  v_apellidos    text    := nullif(trim(coalesce(v_meta ->> 'apellidos', '')), '');
  v_telefono     text    := nullif(trim(coalesce(v_meta ->> 'telefono', '')), '');
  v_direccion    text    := nullif(trim(coalesce(v_meta ->> 'direccion', '')), '');
  v_nivel        text    := nullif(trim(coalesce(v_meta ->> 'nivel_educativo', '')), '');
  v_sexo         text    := nullif(trim(coalesce(v_meta ->> 'sexo', '')), '');
  v_mision       text    := nullif(trim(coalesce(v_meta ->> 'mision_ribaras', '')), '');
  v_tipo_disc    text    := nullif(trim(coalesce(v_meta ->> 'tipo_discapacidad', '')), '');
  v_tutor_ci     text    := nullif(trim(coalesce(v_meta ->> 'numero_identidad_tutor', '')), '');
  v_tutor_nombre text    := nullif(trim(coalesce(v_meta ->> 'nombre_tutor', '')), '');
  v_tutor_parent text    := nullif(trim(coalesce(v_meta ->> 'parentesco_tutor', '')), '');
  v_tutor_tel    text    := nullif(trim(coalesce(v_meta ->> 'telefono_tutor', '')), '');
  v_tutor_correo text    := nullif(trim(coalesce(v_meta ->> 'correo_tutor', '')), '');

  -- La planilla extendida. `'{}'` si el cliente no la manda.
  v_planilla     jsonb   := coalesce(v_meta -> 'datos_planilla', '{}'::jsonb);

  -- (D14) El programa. Se resuelve aquí y no en la lista de columnas para que el
  -- error se lance ANTES del insert: si el valor no vale, `resolver_...` lanza y
  -- la transacción entera del alta se deshace. Es lo correcto: la alternativa
  -- —dejar pasar el alta sin ficha— produce un usuario que ve «registro exitoso»
  -- y no existe como aspirante, sin que nadie se entere.
  v_programa     uuid;

  v_discapacidad boolean := false;
  v_fecha_nac    date;
  v_es_aspirante boolean;
begin
  -- Parseo defensivo: si el cliente manda basura, no reventamos el registro
  -- de un aspirante legítimo; simplemente no se crea la ficha.
  begin
    v_discapacidad := coalesce((v_meta ->> 'discapacidad')::boolean, false);
  exception when others then
    v_discapacidad := false;
  end;

  begin
    v_fecha_nac := nullif(trim(coalesce(v_meta ->> 'fecha_nac', '')), '')::date;
  exception when others then
    v_fecha_nac := null;
  end;

  v_programa := public.resolver_programa_inscripcion(
    coalesce(
      v_planilla ->> 'curso_seleccionado',
      v_meta     ->> 'curso_seleccionado'
    )
  );

  -- (a) Perfil base. Se crea SIEMPRE (incluso para docentes/admins futuros).
  --     El rol es fijo 'estudiante': los privilegios se otorgan después,
  --     desde el cPanel, nunca en el auto-registro.
  insert into public.profiles (id, cedula, email, nombres, apellidos, rol)
  values (
    new.id,
    v_cedula,
    new.email,
    coalesce(v_nombres, ''),
    coalesce(v_apellidos, ''),
    'estudiante'
  )
  on conflict (id) do update
     set cedula     = coalesce(excluded.cedula, public.profiles.cedula),
         email      = excluded.email,
         nombres    = coalesce(nullif(excluded.nombres, ''), public.profiles.nombres),
         apellidos  = coalesce(nullif(excluded.apellidos, ''), public.profiles.apellidos),
         updated_at = now();

  -- (b) Ficha de aspirante: solo si el registro trae la planilla completa.
  --     Este es el caso del formulario de inscripción del INCES.
  --     (D14) La última condición pasó de «trae un curso» a «trae un programa
  --     que existe»: el resolutor ya garantizó lo segundo.
  v_es_aspirante := v_cedula       is not null
                and v_nombres      is not null
                and v_apellidos    is not null
                and v_fecha_nac    is not null
                and v_sexo         is not null
                and v_sexo         in ('M', 'F', 'Otro')
                and v_telefono     is not null
                and v_direccion    is not null
                and v_nivel        is not null
                and v_programa     is not null;

  if v_es_aspirante then
    -- Sólo se valida si el cliente mandó la clave. Ver la cabecera de
    -- `202609240001`: es lo que permite desplegar sin tocar el formulario actual.
    if v_meta ? 'datos_planilla' then
      perform public.validar_planilla(v_planilla);
    end if;

    insert into public.aspirantes (
      user_id, cedula, nombres, apellidos, fecha_nac, sexo, telefono, email,
      direccion, nivel_educativo, program_id, mision_ribaras,
      discapacidad, tipo_discapacidad, numero_identidad_tutor, nombre_tutor,
      parentesco_tutor, telefono_tutor, correo_tutor, requires_legal_tutor,
      datos_planilla
    ) values (
      new.id, v_cedula, v_nombres, v_apellidos, v_fecha_nac, v_sexo, v_telefono,
      new.email, v_direccion, v_nivel, v_programa, v_mision,
      v_discapacidad,
      case when v_discapacidad then v_tipo_disc else null end,
      v_tutor_ci, v_tutor_nombre, v_tutor_parent, v_tutor_tel, v_tutor_correo,
      -- Calculado en SQL para que coincida EXACTAMENTE con el CHECK de la tabla.
      -- Si lo calculáramos en Dart, un desfase de un día en el borde de los 18
      -- años haría fallar el constraint y abortaría todo el registro.
      (v_fecha_nac > (current_date - interval '18 years')::date),
      v_planilla
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Crea profiles + aspirantes de forma atómica al registrarse. Rol fijo estudiante. (D14) Resuelve `program_id` desde `datos_planilla.curso_seleccionado` o desde la clave plana, y lanza si la referencia no es válida.';


-- ---------------------------------------------------------------------------
-- PARTE 5 — La guardia mantiene la clave en sincronía
-- ---------------------------------------------------------------------------
-- Sin esto quedaría un agujero por el lado de la corrección: un aspirante (o un
-- admin) puede reescribir `datos_planilla` por `PUT /yo/planilla`, y la planilla
-- lleva `curso_seleccionado`. Si `program_id` no se re-derivara, la columna
-- seguiría apuntando al curso viejo mientras el JSON dice otro: exactamente el
-- tipo de deriva que D14 existe para eliminar.
--
-- El trigger ya es `before insert or update of datos_planilla`, así que el
-- momento es el correcto y no hay que tocar el `create trigger` de
-- `202609240002`.
--
-- En INSERT sólo deriva si el llamante no trajo la clave: `handle_new_user()` sí
-- la trae, y volver a resolverla sería trabajo duplicado. La excepción importa
-- porque `aspirantes_insert_own` permite a un usuario insertar su propia ficha
-- por PostgREST.
create or replace function public.validar_planilla_guardada()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- (D14) La clave foránea se deriva de la planilla cuando ésta la menciona.
  if new.datos_planilla ? 'curso_seleccionado'
     and (tg_op = 'UPDATE' or new.program_id is null) then
    new.program_id := public.resolver_programa_inscripcion(
      new.datos_planilla ->> 'curso_seleccionado'
    );
  end if;

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
  'Envoltorio de trigger: (D14) deriva `program_id` desde `datos_planilla.curso_seleccionado` cuando la planilla lo menciona, y valida la planilla contra el catálogo salvo cuando es el objeto vacío (que es el «sin planilla» del formulario viejo). Cierra el camino de escritura directa por PostgREST.';


-- ---------------------------------------------------------------------------
-- PARTE 6 — El intercambio de columnas
-- ---------------------------------------------------------------------------
-- `on delete restrict` y no `cascade`: borrar un programa NO debe llevarse por
-- delante las inscripciones de la gente. `restrict` obliga a decidir antes
-- —desactivarlo con `is_active = false`, que es para lo que existe esa columna—
-- y convierte un borrado accidental en un error en vez de en una pérdida.
alter table public.aspirantes
  add column program_id uuid not null
    references public.programs(id) on delete restrict;

-- El nombre plano se va. A partir de aquí el nombre se resuelve por JOIN, y
-- renombrar un programa deja de tener consecuencias sobre las fichas.
alter table public.aspirantes
  drop column curso_seleccionado;

comment on column public.aspirantes.program_id is
  'D14: la propuesta formativa elegida. Única referencia al programa; el nombre se resuelve por JOIN con `programs`. Sustituye a `curso_seleccionado` (texto libre con el nombre), que se eliminó en `202609250001`.';

-- El catálogo no cambia de código, pero su ayuda sí puede ser más exacta ahora
-- que el valor es un identificador y no un nombre.
update public.inscripcion_campos
   set ayuda = 'Las opciones se consultan en vivo desde la oferta de formación '
               'continua (M2). Se guarda la referencia al curso, no su nombre: '
               'renombrarlo no afecta a las inscripciones ya hechas.'
 where codigo = 'curso_seleccionado';


-- ---------------------------------------------------------------------------
-- PARTE 7 — Comprobación de la propia migración
-- ---------------------------------------------------------------------------
-- Cada aserción corresponde a una forma concreta de que esto quede a medias sin
-- que nada falle:
--   · la columna existe pero sin FK      → nada impide un uuid inventado;
--   · la columna existe pero admite NULL → se cuela una ficha sin programa;
--   · `curso_seleccionado` sigue ahí     → el dato duplicado sigue vivo;
--   · el trigger se cayó                  → la validación deja de validar.
do $$
declare
  v_fk        text;
  v_nullable  text;
  v_vieja     int;
  v_trigger   text;
  v_resolutor int;
begin
  select pg_get_constraintdef(c.oid) into v_fk
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public'
     and t.relname = 'aspirantes'
     and c.contype = 'f'
     and c.conname = 'aspirantes_program_id_fkey';

  if v_fk is null or v_fk not like '%programs(id)%' or v_fk not like '%RESTRICT%' then
    raise exception
      'No quedó la clave foránea `aspirantes.program_id → programs(id) ON DELETE RESTRICT` (definición: %).', coalesce(v_fk, 'ausente')
      using errcode = '23514';
  end if;

  select is_nullable into v_nullable
    from information_schema.columns
   where table_schema = 'public' and table_name = 'aspirantes'
     and column_name = 'program_id';

  if v_nullable is distinct from 'NO' then
    raise exception
      '`aspirantes.program_id` quedó anulable (is_nullable = %). Una ficha sin programa es lo que D14 viene a impedir.', coalesce(v_nullable, 'columna ausente')
      using errcode = '23514';
  end if;

  select count(*) into v_vieja
    from information_schema.columns
   where table_schema = 'public' and table_name = 'aspirantes'
     and column_name = 'curso_seleccionado';

  if v_vieja > 0 then
    raise exception
      '`aspirantes.curso_seleccionado` sigue existiendo: el dato duplicado no se eliminó.'
      using errcode = '23514';
  end if;

  -- Un `create trigger` que no dispara porque el nombre de la columna está mal
  -- escrito no falla: simplemente nunca se ejecuta.
  select pg_get_triggerdef(t.oid) into v_trigger
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'aspirantes'
     and t.tgname = 'aspirantes_validar_planilla';

  if v_trigger is null or v_trigger not like '%datos_planilla%' then
    raise exception
      'El trigger `aspirantes_validar_planilla` no quedó cableado a `datos_planilla`.'
      using errcode = '23514';
  end if;

  select count(*) into v_resolutor
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'resolver_programa_inscripcion';

  if v_resolutor = 0 then
    raise exception 'No quedó la función `resolver_programa_inscripcion`.'
      using errcode = '23514';
  end if;
end;
$$;
