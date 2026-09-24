-- ============================================================================
--  INCES LMS — Módulo 4: catálogo de campos de la planilla de inscripción
--  Archivo: 202609240001_mod4_catalogo_inscripcion.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El cuello de botella real del CFS no es la cola de inscripciones: es que el
--  aspirante llena a mano una planilla de papel de ~39 campos y alguien la
--  vuelve a teclear en un Excel llamado «LISTA PARA LLAMAR» cuyas columnas se
--  llaman literalmente `Columna1`..`Columna4`. Este archivo pone la primera
--  pieza para que el aspirante escriba sus propios datos una sola vez.
--
--  Nada de esto es una decisión de UI: es la DECLARACIÓN DE LOS CAMPOS. La
--  pantalla pasa a ser un renderizador de esta tabla, y marcar un campo como
--  opcional deja de ser un cambio de código para ser un `update`.
--
--  LA DECISIÓN DE FONDO: UNA SOLA CLAVE `datos_planilla` (jsonb)
--  --------------------------------------------------------------
--  Se evaluaron tres caminos para meter ~39 campos en una tabla que hoy tiene
--  20 columnas planas. Los dos descartados, con su motivo, porque el motivo
--  importa más que la conclusión:
--
--    A) 22 columnas nuevas en `aspirantes` + 22 claves nuevas en el trigger.
--       Encaja con el diseño actual y es el camino «obvio». Se descarta porque
--       MATA EL OBJETIVO: cada campo que el CFS quiera añadir o cambiar exigiría
--       una migración, editar el trigger, editar `AspiranteModel` y editar el
--       formulario. Eso es lo contrario de «altamente customizable». Además las
--       tres tablas repetibles (familiares, otras formaciones, experiencias) no
--       se pueden expresar en columnas.
--
--    B) Escribir la planilla DESPUÉS del `signUp`, con una ruta del backend.
--       Es lo más limpio en capas y se descarta porque rompe ADR-007 («alta de
--       aspirante vía trigger atómico, no por inserts del cliente») y abre una
--       ventana en la que existe una cuenta SIN planilla: si el aspirante cierra
--       el navegador entre el `signUp` y el segundo POST queda un usuario
--       huérfano, y habría que construir un flujo de «reanudar inscripción».
--       Deuda evitable.
--
--    C) UNA clave nueva: `datos_planilla` (jsonb).  <-- este archivo
--       · El trigger sigue leyendo las 10 claves de identidad SIN CAMBIOS.
--       · Añade UNA lectura y UNA columna.
--       · Atomicidad intacta: ADR-007 se respeta.
--       · Campos nuevos = filas en `inscripcion_campos`. CERO migraciones.
--       · Las tablas repetibles y la rejilla de misiones caben como arrays.
--
--  POR QUÉ LA VALIDACIÓN TIENE QUE ESTAR EN SQL
--  --------------------------------------------
--  `raw_user_meta_data` lo controla el CLIENTE. El trigger lo escribe tal cual
--  en la columna. Sin una validación en la base, un cliente malicioso mete
--  cualquier JSON en `datos_planilla` — y esa columna es exactamente la que
--  después va a leer la exportación hacia HACER. La forma se valida contra el
--  catálogo con `validar_planilla()`, no en Dart.
--
--  LA ASIMETRÍA DELIBERADA QUE EVITA ROMPER LA APP EN PRODUCCIÓN
--  -------------------------------------------------------------
--  `validar_planilla()` se llama SÓLO SI el cliente mandó la clave
--  `datos_planilla`. Es decir:
--
--    * Un cliente viejo (el formulario actual, sin refactorizar) NO manda la
--      clave → no se valida nada → el registro sigue funcionando EXACTAMENTE
--      como hoy. Cero regresión.
--    * Un cliente nuevo (el formulario conducido por datos) SÍ la manda → se
--      valida contra el catálogo.
--
--  NO es un agujero: omitir la clave no salta ninguna obligación, deja la
--  planilla vacía, que es estrictamente mejor que el estado actual (hoy no hay
--  planilla en absoluto). Cuando el formulario nuevo esté desplegado y se
--  confirme que manda la clave siempre, una migración posterior podrá exigirla.
--  Se deja escrito para que quien lea esto no lo tome por un descuido.
--
--  OJO: `v_es_aspirante` ES UN FALLO SILENCIOSO
--  --------------------------------------------
--  Las 10 columnas `NOT NULL` de `aspirantes` son además la condición
--  `v_es_aspirante`: si falta una, la ficha NO se crea y NO hay error. Es
--  intencionado (un docente que se registre sin planilla no debe reventar), pero
--  significa que un aspirante con un campo mal escrito se queda sin ficha y sin
--  mensaje. `validar_planilla()` sólo cubre el bloque extendido; no se toca la
--  condición existente en este archivo.
--
--  QUÉ NO HACE ESTE ARCHIVO
--  ------------------------
--  * No toca las 17 claves que el trigger ya lee, ni las 10 condiciones de
--    `v_es_aspirante`, ni el `on conflict (user_id) do nothing`.
--  * No añade ninguna ruta al backend. El `signUp` sigue siendo la excepción
--    justificada a «Flutter→Fastify»: tiene que ocurrir en el cliente para
--    establecer la sesión, y la frontera es el trigger + la RLS (ADR-003).
--  * No refactoriza `aspirante_form_screen.dart`. Esta migración es inerte para
--    la app actual: añade una columna con default y una validación que hoy nadie
--    dispara.
--  * No siembra datos de demo. El catálogo es CONFIGURACIÓN, no datos de
--    ejemplo, y por eso vive en una migración y no en `sembrar-datos.mjs` —
--    igual que `system_modules` y `system_settings`.
--  * No crea la exportación a HACER. Pero `datos_planilla` se diseña para ella.
--
--  DEUDA QUE DEJA ABIERTA
--  ----------------------
--  * `aspirantes.mision_ribaras` (texto libre, del formulario actual) queda
--    DUPLICADA con el campo `misiones` del catálogo (rejilla de 20 casillas con
--    su «desde», que es lo que dice la planilla física). No se borra —hay datos
--    y una clave de metadata viva— pero hay que decidir cuál manda antes de
--    tocar el formulario. Se anota aquí para que no se descubra tarde.
--  * La contraseña NO está en el catálogo a propósito: no es un dato de la
--    planilla, es una credencial, y esta tabla es legible sin sesión.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PARTE 1 — El catálogo de campos
-- ---------------------------------------------------------------------------
-- Una fila por campo de la planilla. `orden` es global (no por grupo) para que
-- el renderizador pueda ordenar sin conocer los grupos, y `grupo` es el que
-- decide en qué paso del formulario cae cada campo.
create table if not exists public.inscripcion_campos (
  codigo       text        primary key,
  etiqueta     text        not null,
  grupo        text        not null,
  tipo         text        not null
    check (tipo in ('texto', 'email', 'numero', 'fecha', 'seleccion',
                    'multiseleccion', 'booleano', 'tabla', 'rejilla')),
  obligatorio  boolean     not null default false,
  orden        integer     not null default 0,
  -- `opciones` guarda la lista cerrada de un `seleccion`/`multiseleccion`, y la
  -- forma de las columnas de un `tabla` o los ítems de un `rejilla`. Se deja
  -- jsonb y no columnas aparte porque cada tipo necesita una forma distinta y
  -- forzarlos a un esquema común habría creado columnas nulas para todos.
  opciones     jsonb,
  -- `fuente` marca los campos cuyas opciones NO están en el catálogo sino que se
  -- consultan en vivo (hoy sólo 'programas': la oferta formativa cambia).
  -- Sin esto, `curso_seleccionado` habría necesitado su propio campo aparte.
  fuente       text,
  -- `condicion` expresa visibilidad condicional, p. ej.
  --   {"campo": "pueblo_indigena", "igual": true}
  -- El campo existe siempre en la base; la condición es de presentación.
  condicion    jsonb,
  ayuda        text,
  -- Vacío = aplica a toda la oferta formativa. Se deja preparado para cuando el
  -- CFS pida que un programa concreto no pregunte cierto campo.
  aplica_a     text[]      not null default '{}',
  activo       boolean     not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint inscripcion_campos_codigo_formato
    check (codigo ~ '^[a-z][a-z0-9_]*$')
);

comment on table public.inscripcion_campos is
  'Catálogo de campos de la planilla de inscripción del INCES. Es la fuente de verdad del formulario: la pantalla lo renderiza y el administrador marca obligatorio/opcional aquí, sin tocar código.';
comment on column public.inscripcion_campos.fuente is
  'Origen dinámico de las opciones (p. ej. ''programas''). NULL significa que las opciones están en `opciones`.';
comment on column public.inscripcion_campos.condicion is
  'Visibilidad condicional: {"campo": "<codigo>", "igual": <valor>}. Sólo afecta a la presentación.';
comment on column public.inscripcion_campos.aplica_a is
  'Códigos de programa a los que aplica. Array vacío = a toda la oferta formativa.';

drop trigger if exists inscripcion_campos_set_updated_at on public.inscripcion_campos;
create trigger inscripcion_campos_set_updated_at
  before update on public.inscripcion_campos
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
-- PARTE 2 — RLS
-- ---------------------------------------------------------------------------
-- El aspirante NO tiene sesión cuando el formulario se pinta: se está
-- registrando. Por eso el catálogo es legible por `anon`. Eso NO expone datos
-- personales — son definiciones de campo («Segundo nombre», «Estado civil»),
-- no respuestas de nadie. Es el mismo criterio que ya usa `system_settings` con
-- `es_publico`, y es una decisión de producto, no un descuido: un formulario
-- público no puede exigir autenticación para saber qué preguntar.
--
-- La escritura sí queda cerrada: sólo el admin edita el catálogo.
alter table public.inscripcion_campos enable row level security;

drop policy if exists inscripcion_campos_lectura_publica on public.inscripcion_campos;
create policy inscripcion_campos_lectura_publica
  on public.inscripcion_campos
  for select
  to anon, authenticated
  using (activo);

drop policy if exists inscripcion_campos_admin_escritura on public.inscripcion_campos;
create policy inscripcion_campos_admin_escritura
  on public.inscripcion_campos
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Un admin tiene que poder ver también los campos DESACTIVADOS, si no el panel
-- de administración no puede reactivarlos: los vería desaparecer al apagarlos.
drop policy if exists inscripcion_campos_admin_lectura on public.inscripcion_campos;
create policy inscripcion_campos_admin_lectura
  on public.inscripcion_campos
  for select
  to authenticated
  using (public.is_admin());

-- Las políticas de SELECT se combinan con OR, así que el admin ve todo (activos
-- e inactivos) y el resto ve sólo los activos. No hay fuga: es aditivo.


-- ---------------------------------------------------------------------------
-- PARTE 3 — La columna que guarda la planilla
-- ---------------------------------------------------------------------------
-- `not null default '{}'` a propósito: las filas que ya existen (y las que cree
-- un cliente viejo) quedan con un objeto vacío, no con NULL. Así el renderizador
-- y la exportación no tienen que distinguir «sin planilla» de «planilla nula».
alter table public.aspirantes
  add column if not exists datos_planilla jsonb not null default '{}'::jsonb;

comment on column public.aspirantes.datos_planilla is
  'Planilla de inscripción extendida, con la forma del catálogo `inscripcion_campos`. Va aquí y no en columnas planas para que añadir un campo del CFS no exija una migración. Las 20 columnas de arriba siguen siendo el contrato de identidad con AspiranteModel.';


-- ---------------------------------------------------------------------------
-- PARTE 4 — validar_planilla()
-- ---------------------------------------------------------------------------
-- Valida la FORMA contra el catálogo: todo campo marcado `obligatorio` y activo
-- tiene que venir con un valor no vacío. No valida tipos ni formatos: de eso se
-- encargan Zod en el backend (cuando la escritura pasa por ahí) y el propio
-- formulario. Aquí sólo se impide lo que no puede colarse: una planilla
-- incompleta escrita directamente en la columna.
--
-- `security definer` es OBLIGATORIO, no estilo: el cliente que dispara el
-- trigger es `supabase_auth_admin` y no tiene por qué tener privilegios de
-- lectura sobre `inscripcion_campos` (que además sólo deja ver los activos).
-- Misma razón por la que `handle_new_user()` ya es definer.
--
-- Lo que cuenta como «vacío», y por qué no basta con `is null`:
--   · la clave ausente,
--   · un JSON `null` explícito,
--   · una cadena vacía o sólo espacios,
--   · un array vacío (una tabla repetible sin filas),
--   · un objeto vacío.
-- Sin los tres últimos casos, un cliente podría «cumplir» mandando `[]` en un
-- campo obligatorio y la obligación sería decorativa.
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
end;
$$;

comment on function public.validar_planilla(jsonb) is
  'Comprueba que la planilla traiga todos los campos marcados obligatorios en `inscripcion_campos`. Lanza 23514 nombrando los que faltan. Valida forma, no tipos.';


-- ---------------------------------------------------------------------------
-- PARTE 5 — El trigger, con tres añadidos y nada más
-- ---------------------------------------------------------------------------
-- Se reescribe con `create or replace` copiando el cuerpo LITERAL de
-- `202609120001_phase1_onboarding.sql`. Ese archivo NO se toca: una migración ya
-- aplicada no se edita nunca, porque el libro mayor (`schema_migrations`)
-- detecta la deriva por checksum y se niega a continuar.
--
-- Los tres añadidos son exactamente:
--   1. una variable `v_planilla`,
--   2. la llamada a `validar_planilla()`, CONDICIONADA a que la clave venga,
--   3. `datos_planilla` en la lista de columnas y en la de valores del insert.
--
-- Todo lo demás —las 17 claves, las 10 condiciones, el parseo defensivo, el
-- cálculo de `requires_legal_tutor` en SQL— se copia sin cambiar una coma.
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
  v_curso        text    := nullif(trim(coalesce(v_meta ->> 'curso_seleccionado', '')), '');
  v_sexo         text    := nullif(trim(coalesce(v_meta ->> 'sexo', '')), '');
  v_mision       text    := nullif(trim(coalesce(v_meta ->> 'mision_ribaras', '')), '');
  v_tipo_disc    text    := nullif(trim(coalesce(v_meta ->> 'tipo_discapacidad', '')), '');
  v_tutor_ci     text    := nullif(trim(coalesce(v_meta ->> 'numero_identidad_tutor', '')), '');
  v_tutor_nombre text    := nullif(trim(coalesce(v_meta ->> 'nombre_tutor', '')), '');
  v_tutor_parent text    := nullif(trim(coalesce(v_meta ->> 'parentesco_tutor', '')), '');
  v_tutor_tel    text    := nullif(trim(coalesce(v_meta ->> 'telefono_tutor', '')), '');
  v_tutor_correo text    := nullif(trim(coalesce(v_meta ->> 'correo_tutor', '')), '');

  -- (1) AÑADIDO. La planilla extendida. `'{}'` si el cliente no la manda.
  v_planilla     jsonb   := coalesce(v_meta -> 'datos_planilla', '{}'::jsonb);

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
  v_es_aspirante := v_cedula       is not null
                and v_nombres      is not null
                and v_apellidos    is not null
                and v_fecha_nac    is not null
                and v_sexo         is not null
                and v_sexo         in ('M', 'F', 'Otro')
                and v_telefono     is not null
                and v_direccion    is not null
                and v_nivel        is not null
                and v_curso        is not null;

  if v_es_aspirante then
    -- (2) AÑADIDO. Sólo se valida si el cliente mandó la clave. Ver la cabecera:
    -- es lo que permite desplegar esta migración sin tocar el formulario actual.
    if v_meta ? 'datos_planilla' then
      perform public.validar_planilla(v_planilla);
    end if;

    insert into public.aspirantes (
      user_id, cedula, nombres, apellidos, fecha_nac, sexo, telefono, email,
      direccion, nivel_educativo, curso_seleccionado, mision_ribaras,
      discapacidad, tipo_discapacidad, numero_identidad_tutor, nombre_tutor,
      parentesco_tutor, telefono_tutor, correo_tutor, requires_legal_tutor,
      -- (3) AÑADIDO.
      datos_planilla
    ) values (
      new.id, v_cedula, v_nombres, v_apellidos, v_fecha_nac, v_sexo, v_telefono,
      new.email, v_direccion, v_nivel, v_curso, v_mision,
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
  'Crea profiles + aspirantes de forma atómica al registrarse. Rol fijo estudiante. Valida datos_planilla contra el catálogo sólo si el cliente manda esa clave (asimetría deliberada: no rompe al formulario viejo).';


-- ---------------------------------------------------------------------------
-- PARTE 6 — La semilla del catálogo
-- ---------------------------------------------------------------------------
-- Los 44 campos de la planilla física, transcritos de
-- `Anexos/PLANILLA DE INSCRIPCION INCES…pdf` (que tiene capa de texto, así que
-- esto no es una lectura a ojo de una foto).
--
-- CRITERIO DE `obligatorio`, que es la decisión que importa aquí:
-- se marca obligatorio lo que HOY ya exige `v_es_aspirante` (cédula, nombres,
-- apellidos, fecha de nacimiento, sexo, teléfono, dirección, nivel educativo,
-- curso) más `nacionalidad` (HACER la necesita para el formato de la cédula) y
-- `email` (es la cuenta). TODO LO DEMÁS VA OPCIONAL, aunque la planilla de papel
-- lo tenga impreso. Motivo: convertir en obligatorio un campo que el aspirante
-- puede no saber (una segunda nacionalidad, el teléfono fijo, la especialidad)
-- sólo produce datos basura («n/a», «no», un punto) y abandono del formulario.
-- El CFS puede subir cualquiera a obligatorio desde el panel sin tocar código:
-- esa es justamente la razón de que este catálogo exista.
--
-- `on conflict (codigo) do update` y no `do nothing`: así una corrección de
-- etiqueta u orden en un catálogo a medio sembrar converge. No hay trigger
-- BEFORE INSERT sobre esta tabla que pueda bloquear el camino de conflicto (la
-- trampa que sí tiene `enrollments`), sólo el de `updated_at`, que es BEFORE
-- UPDATE y no interviene en el INSERT.
--
-- ⚠️ EL MAPEO CON LAS CLAVES DEL TRIGGER NO ES 1 A 1 — leer antes de escribir el
--    formulario. El trigger lee 17 claves de `raw_user_meta_data` y 9 de ellas
--    son la condición `v_es_aspirante`. El catálogo NO usa los mismos códigos en
--    cuatro casos, a propósito, porque la planilla física pide el dato desglosado
--    y HACER lo quiere desglosado:
--
--      clave de metadata  |  código(s) del catálogo      |  por qué
--      -------------------+------------------------------+---------------------
--      nombres            |  primer_nombre               |  la planilla pide 1er
--                         |  + segundo_nombre            |  y 2do por separado
--      apellidos          |  primer_apellido             |
--                         |  + segundo_apellido          |
--      mision_ribaras     |  misiones (rejilla)          |  hoy es texto libre;
--                         |                              |  ver la deuda de abajo
--
--    Consecuencia que hay que respetar: **el formulario tiene que seguir
--    mandando `nombres` y `apellidos`** (concatenados) además de los desglosados.
--    Si sólo manda `primer_nombre`, el trigger deja `v_nombres` en NULL, la
--    condición `v_es_aspirante` falla y **la ficha no se crea — sin error**.
--    Es el fallo silencioso que ya documenta la cabecera de este archivo.
--
--    Los otros cinco códigos sí coinciden literalmente y no necesitan mapeo:
--    `cedula`, `fecha_nac`, `sexo`, `telefono`, `direccion`, `nivel_educativo`,
--    `curso_seleccionado`.
insert into public.inscripcion_campos
  (codigo, etiqueta, grupo, tipo, obligatorio, orden, opciones, fuente, condicion, ayuda)
values

-- --- Cabecera ---------------------------------------------------------------
-- El único campo de la cabecera que el aspirante puede aportar. Los demás
-- (FECHA, PROYECTO, ESPACIO INTEGRAL SOCIALISTA, HORARIO) los imprime el CFS y
-- en el sistema se derivan de la sección y del lapso, no se preguntan.
('numero_preimpreso', 'N° preimpreso de la planilla', 'Cabecera', 'texto',
 false, 10, null, null, null,
 'Número impreso en la planilla física. Sirve para emparejar el papel con el registro digital.'),

-- --- Datos personales -------------------------------------------------------
('primer_nombre', 'Primer nombre', 'Datos personales', 'texto', true, 20, null, null, null, null),
('segundo_nombre', 'Segundo nombre', 'Datos personales', 'texto', false, 30, null, null, null, null),
('primer_apellido', 'Primer apellido', 'Datos personales', 'texto', true, 40, null, null, null, null),
('segundo_apellido', 'Segundo apellido', 'Datos personales', 'texto', false, 50, null, null, null, null),
('cedula', 'Cédula de identidad o pasaporte', 'Datos personales', 'texto', true, 60, null, null, null,
 'Sólo números, sin puntos ni guiones.'),
('nacionalidad', 'Nacionalidad', 'Datos personales', 'seleccion', true, 70,
 '{"opciones":[{"valor":"V","etiqueta":"Venezolano/a"},{"valor":"E","etiqueta":"Extranjero/a"}]}'::jsonb,
 null, null, null),
('fecha_nac', 'Fecha de nacimiento', 'Datos personales', 'fecha', true, 80, null, null, null,
 'La edad se calcula sola y decide si hace falta representante legal.'),
('sexo', 'Sexo', 'Datos personales', 'seleccion', true, 90,
 '{"opciones":[{"valor":"F","etiqueta":"Femenino"},{"valor":"M","etiqueta":"Masculino"},{"valor":"Otro","etiqueta":"Otro"}]}'::jsonb,
 null, null, null),
('estado_civil', 'Estado civil', 'Datos personales', 'seleccion', false, 100,
 '{"opciones":[{"valor":"SOLTERO","etiqueta":"Soltero/a"},{"valor":"CASADO","etiqueta":"Casado/a"},{"valor":"DIVORCIADO","etiqueta":"Divorciado/a"},{"valor":"VIUDO","etiqueta":"Viudo/a"},{"valor":"CONCUBINATO","etiqueta":"Concubinato"}]}'::jsonb,
 null, null, null),
('pueblo_indigena', '¿Pertenece a un pueblo indígena?', 'Datos personales', 'booleano',
 false, 110, null, null, null, null),
('pueblo_indigena_cual', '¿A cuál pueblo indígena?', 'Datos personales', 'texto',
 false, 120, null, null, '{"campo":"pueblo_indigena","igual":true}'::jsonb, null),
-- `discapacidad` (booleano) y `tipo_discapacidad` son DOS campos y no uno porque
-- ya son dos columnas del contrato con `AspiranteModel`: el booleano decide y el
-- detalle acompaña. La planilla los presenta como seis casillas; el booleano es
-- «alguna marcada que no sea NINGUNA».
('discapacidad', '¿Tiene alguna diversidad funcional?', 'Datos personales', 'booleano',
 false, 130, null, null, null, null),
('tipo_discapacidad', 'Tipo de diversidad funcional', 'Datos personales', 'multiseleccion',
 false, 140,
 '{"opciones":[{"valor":"FISICA_MANO","etiqueta":"Física (mano)"},{"valor":"FISICA_PIERNAS","etiqueta":"Física (piernas)"},{"valor":"SENSORIAL_AUDITIVA","etiqueta":"Sensorial auditiva"},{"valor":"SENSORIAL_CEGUERA","etiqueta":"Sensorial (ceguera)"},{"valor":"DEBILIDAD_INTELECTUAL","etiqueta":"Debilidad intelectual"},{"valor":"NINGUNA","etiqueta":"Ninguna"}]}'::jsonb,
 null, '{"campo":"discapacidad","igual":true}'::jsonb, null),
('deporte', 'Deporte que practica', 'Datos personales', 'texto', false, 150, null, null, null, null),
('deporte_desde', 'Practica ese deporte desde', 'Datos personales', 'texto', false, 160, null, null, null,
 'Año o fecha aproximada; la planilla de papel no pide precisión.'),
('actividad_cultural', 'Actividad cultural que realiza', 'Datos personales', 'texto',
 false, 170, null, null, null, null),
('actividad_cultural_desde', 'Realiza esa actividad desde', 'Datos personales', 'texto',
 false, 180, null, null, null, null),
('organizacion_social', 'Organización social o política a la que pertenece', 'Datos personales', 'texto',
 false, 190, null, null, null, null),
('organizacion_social_desde', 'Pertenece a esa organización desde', 'Datos personales', 'texto',
 false, 200, null, null, null, null),

-- --- Ubicación y contacto ---------------------------------------------------
-- La planilla pide ESTADO / MUNICIPIO / PARROQUIA / COMUNIDAD por separado, y
-- `direccion` sólo para la calle y el número. Hoy el formulario mete todo eso en
-- un único campo de texto libre, que es lo que hace imposible exportar a HACER
-- sin volver a teclearlo.
('estado', 'Estado', 'Ubicación y contacto', 'seleccion', true, 210,
 '{"opciones":[
   {"valor":"AMAZONAS","etiqueta":"Amazonas"},{"valor":"ANZOATEGUI","etiqueta":"Anzoátegui"},
   {"valor":"APURE","etiqueta":"Apure"},{"valor":"ARAGUA","etiqueta":"Aragua"},
   {"valor":"BARINAS","etiqueta":"Barinas"},{"valor":"BOLIVAR","etiqueta":"Bolívar"},
   {"valor":"CARABOBO","etiqueta":"Carabobo"},{"valor":"COJEDES","etiqueta":"Cojedes"},
   {"valor":"DELTA_AMACURO","etiqueta":"Delta Amacuro"},{"valor":"DISTRITO_CAPITAL","etiqueta":"Distrito Capital"},
   {"valor":"FALCON","etiqueta":"Falcón"},{"valor":"GUARICO","etiqueta":"Guárico"},
   {"valor":"LA_GUAIRA","etiqueta":"La Guaira"},{"valor":"LARA","etiqueta":"Lara"},
   {"valor":"MERIDA","etiqueta":"Mérida"},{"valor":"MIRANDA","etiqueta":"Miranda"},
   {"valor":"MONAGAS","etiqueta":"Monagas"},{"valor":"NUEVA_ESPARTA","etiqueta":"Nueva Esparta"},
   {"valor":"PORTUGUESA","etiqueta":"Portuguesa"},{"valor":"SUCRE","etiqueta":"Sucre"},
   {"valor":"TACHIRA","etiqueta":"Táchira"},{"valor":"TRUJILLO","etiqueta":"Trujillo"},
   {"valor":"YARACUY","etiqueta":"Yaracuy"},{"valor":"ZULIA","etiqueta":"Zulia"}
 ]}'::jsonb, null, null, null),
('municipio', 'Municipio', 'Ubicación y contacto', 'texto', true, 220, null, null, null, null),
('parroquia', 'Parroquia', 'Ubicación y contacto', 'texto', false, 230, null, null, null, null),
('comunidad', 'Comunidad', 'Ubicación y contacto', 'texto', false, 240, null, null, null, null),
('direccion', 'Dirección de habitación', 'Ubicación y contacto', 'texto', true, 250, null, null, null,
 'Calle, avenida o vereda y número de casa.'),
('telefono', 'Teléfono celular', 'Ubicación y contacto', 'texto', true, 260, null, null, null, null),
('telefono_fijo', 'Teléfono fijo', 'Ubicación y contacto', 'texto', false, 270, null, null, null, null),
('email', 'Correo electrónico', 'Ubicación y contacto', 'email', true, 280, null, null, null,
 'Es el correo de la cuenta; ahí llega la confirmación.'),
('twitter', 'Twitter / X', 'Ubicación y contacto', 'texto', false, 290, null, null, null, null),
('facebook', 'Facebook', 'Ubicación y contacto', 'texto', false, 300, null, null, null, null),

-- --- Familiares (tabla repetible) -------------------------------------------
('familiares', 'Familiares', 'Familiares', 'tabla', false, 310,
 '{"columnas":[
   {"codigo":"cedula","etiqueta":"Cédula","tipo":"texto","obligatorio":true},
   {"codigo":"nombres","etiqueta":"Nombres","tipo":"texto","obligatorio":true},
   {"codigo":"apellidos","etiqueta":"Apellidos","tipo":"texto","obligatorio":true},
   {"codigo":"fecha_nac","etiqueta":"Fecha de nacimiento","tipo":"fecha","obligatorio":false},
   {"codigo":"genero","etiqueta":"Género","tipo":"seleccion","obligatorio":false,
    "opciones":[{"valor":"F","etiqueta":"Femenino"},{"valor":"M","etiqueta":"Masculino"}]},
   {"codigo":"parentesco","etiqueta":"Parentesco","tipo":"texto","obligatorio":true},
   {"codigo":"diversidad_funcional","etiqueta":"Diversidad funcional","tipo":"texto","obligatorio":false},
   {"codigo":"estado_civil","etiqueta":"Estado civil","tipo":"texto","obligatorio":false}
 ]}'::jsonb,
 null, null, 'Filas repetibles: la planilla de papel trae una tabla, no un campo.'),

-- --- Misiones ---------------------------------------------------------------
-- Las 20 casillas de la planilla, cada una con su «desde». Es `rejilla` y no
-- `multiseleccion` porque cada ítem marcado lleva un valor propio.
('misiones', 'Misiones a las que pertenece', 'Misiones', 'rejilla', false, 320,
 '{"etiqueta_desde":"Desde","multiple":true,"items":[
   {"valor":"RIBAS","etiqueta":"Ribas"},{"valor":"MERCAL","etiqueta":"Mercal"},
   {"valor":"MADRES_DEL_BARRIO","etiqueta":"Madres del Barrio"},{"valor":"HABITAT","etiqueta":"Hábitat"},
   {"valor":"PIAR","etiqueta":"PIAR"},{"valor":"NEGRA_HIPOLITA","etiqueta":"Negra Hipólita"},
   {"valor":"BARRIO_ADENTRO","etiqueta":"Barrio Adentro"},{"valor":"MIRANDA","etiqueta":"Miranda"},
   {"valor":"IDENTIDAD","etiqueta":"Identidad"},{"valor":"CASA_DE_ALIMENTACION","etiqueta":"Casa de Alimentación"},
   {"valor":"GUAICAIPURO","etiqueta":"Guaicaipuro"},{"valor":"ROBINSON_I_Y_II","etiqueta":"Robinson I y II"},
   {"valor":"HIJOS_DE_VZLA","etiqueta":"Hijos de Venezuela"},{"valor":"SUCRE","etiqueta":"Sucre"},
   {"valor":"VUELVAN_CARAS","etiqueta":"Vuelvan Caras"},{"valor":"VUELVAN_CARAS_JOVENES","etiqueta":"Vuelvan Caras Jóvenes"},
   {"valor":"GM_VIVIENDA_VZLA","etiqueta":"Gran Misión Vivienda Venezuela"},{"valor":"GM_AGROVENEZUELA","etiqueta":"Gran Misión Agrovenezuela"},
   {"valor":"GM_SABER_Y_TRABAJO","etiqueta":"Gran Misión Saber y Trabajo"},{"valor":"NINGUNA","etiqueta":"Ninguna"}
 ]}'::jsonb,
 null, null,
 'OJO: duplica en parte a `aspirantes.mision_ribaras`, que es el campo de texto libre del formulario actual. Hay que decidir cuál manda antes de refactorizar la pantalla.'),

-- --- Formación --------------------------------------------------------------
('nivel_educativo', 'Nivel educativo', 'Formación', 'seleccion', true, 330,
 '{"opciones":[{"valor":"PRIMARIO","etiqueta":"Educación básica"},{"valor":"SECUNDARIO","etiqueta":"Educación media"},{"valor":"TECNICO","etiqueta":"Técnico"},{"valor":"UNIVERSITARIO","etiqueta":"Universitario"}]}'::jsonb,
 null, null, null),
('nivel_avance', 'Estado del avance del nivel educativo', 'Formación', 'seleccion', false, 340,
 '{"opciones":[{"valor":"CULMINO","etiqueta":"Culminó"},{"valor":"NO_COMPLETO","etiqueta":"No completo"},{"valor":"EN_PROGRESO","etiqueta":"En progreso"}]}'::jsonb,
 null, null, null),
('ultimo_anio', 'Último año cursado', 'Formación', 'texto', false, 350, null, null, null, null),
('especialidad', 'Especialidad', 'Formación', 'texto', false, 360, null, null, null, null),

-- --- Otras formaciones y experiencias ---------------------------------------
('otras_formaciones', 'Otras formaciones', 'Formación complementaria', 'tabla', false, 370,
 '{"columnas":[
   {"codigo":"formacion","etiqueta":"Formación","tipo":"texto","obligatorio":true},
   {"codigo":"institucion","etiqueta":"Institución","tipo":"texto","obligatorio":false},
   {"codigo":"horas","etiqueta":"Horas","tipo":"numero","obligatorio":false}
 ]}'::jsonb,
 null, null, null),
('experiencias', 'Experiencias empíricas', 'Formación complementaria', 'tabla', false, 380,
 '{"columnas":[
   {"codigo":"area","etiqueta":"Área del conocimiento","tipo":"texto","obligatorio":true},
   {"codigo":"tiempo_meses","etiqueta":"Tiempo (meses)","tipo":"numero","obligatorio":false},
   {"codigo":"portafolio","etiqueta":"¿Portafolio de evidencias?","tipo":"booleano","obligatorio":false},
   {"codigo":"enlace","etiqueta":"Enlace","tipo":"texto","obligatorio":false}
 ]}'::jsonb,
 null, null, null),

-- --- Representante legal ----------------------------------------------------
-- Condicional por edad: la planilla los pide sólo cuando el aspirante es menor.
-- La condición de edad no se expresa con `condicion` (que compara contra otro
-- campo) sino con `requires_legal_tutor`, que el trigger ya calcula en SQL.
('numero_identidad_tutor', 'Cédula del representante legal', 'Representante legal', 'texto',
 false, 390, null, null, null, null),
('nombre_tutor', 'Nombre completo del representante legal', 'Representante legal', 'texto',
 false, 400, null, null, null, null),
('parentesco_tutor', 'Parentesco', 'Representante legal', 'seleccion', false, 410,
 '{"opciones":[{"valor":"MADRE","etiqueta":"Madre"},{"valor":"PADRE","etiqueta":"Padre"},{"valor":"ABUELO","etiqueta":"Abuelo/a"},{"valor":"TIO","etiqueta":"Tío/a"},{"valor":"PADRINO","etiqueta":"Padrino/Madrina"},{"valor":"OTRO","etiqueta":"Otro"}]}'::jsonb,
 null, null, null),
('telefono_tutor', 'Teléfono del representante legal', 'Representante legal', 'texto',
 false, 420, null, null, null, null),
('correo_tutor', 'Correo del representante legal', 'Representante legal', 'email',
 false, 430, null, null, null, null),

-- --- Propuesta formativa ----------------------------------------------------
-- `fuente` y no `opciones`: la oferta formativa cambia y no puede quedar
-- congelada dentro del catálogo.
('curso_seleccionado', 'Propuesta formativa a cursar', 'Propuesta formativa', 'seleccion',
 true, 440, null, 'programas', null,
 'Las opciones se consultan en vivo desde la oferta formativa (M2).')
on conflict (codigo) do update
  set etiqueta    = excluded.etiqueta,
      grupo       = excluded.grupo,
      tipo        = excluded.tipo,
      obligatorio = excluded.obligatorio,
      orden       = excluded.orden,
      opciones    = excluded.opciones,
      fuente      = excluded.fuente,
      condicion   = excluded.condicion,
      ayuda       = excluded.ayuda,
      updated_at  = now();


-- ---------------------------------------------------------------------------
-- PARTE 7 — Comprobación de la propia semilla
-- ---------------------------------------------------------------------------
-- Una migración que siembra 44 filas y no comprueba nada deja el error para
-- después, y el síntoma aparecería como «el formulario está raro», no como
-- «falta una migración». Se comprueba aquí y con un error que nombra la causa.
do $$
declare
  v_total      int;
  v_obligatorios int;
  v_grupos     text;
begin
  select count(*),
         count(*) filter (where obligatorio),
         string_agg(distinct grupo, ', ' order by grupo)
    into v_total, v_obligatorios, v_grupos
    from public.inscripcion_campos;

  if v_total < 40 then
    raise exception
      'El catálogo de inscripción quedó con % campos; se esperaban al menos 40.', v_total
      using errcode = '23514';
  end if;

  -- Un catálogo sin ningún obligatorio haría que `validar_planilla()` fuera
  -- decorativa: pasaría siempre. Se comprueba que la obligación exista.
  if v_obligatorios = 0 then
    raise exception
      'Ningún campo quedó marcado obligatorio: validar_planilla() no validaría nada.'
      using errcode = '23514';
  end if;

  raise notice
    'Catálogo de inscripción sembrado: % campos (% obligatorios) en los grupos: %.',
    v_total, v_obligatorios, v_grupos;
end $$;
