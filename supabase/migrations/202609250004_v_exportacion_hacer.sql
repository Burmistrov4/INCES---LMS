-- ============================================================================
--  INCES LMS — Módulo 4: la vista de exportación hacia HACER
--  Archivo: 202609250004_v_exportacion_hacer.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  Hasta ahora la planilla de inscripción se capturaba pero **no se podía
--  sacar**. `AUDITORIA_M4.md` §2 lo midió: «Exportación a HACER: **No existe**».
--  El formulario ya guarda los 44 campos del catálogo en
--  `aspirantes.datos_planilla` (jsonb) y el trigger `handle_new_user()` mantiene
--  las columnas planas de identidad, pero no había ninguna superficie que
--  juntara las dos cosas con el contexto académico (sección, lapso, materia,
--  docente) que HACER necesita para saber **a qué se inscribió** el aspirante.
--  Esta vista es esa superficie.
--
--  LA PREGUNTA ABIERTA, DICHA EN VOZ ALTA
--  --------------------------------------
--  **No existe ninguna especificación de campos de HACER en este repositorio.**
--  Medido: la palabra «HACER» aparece sólo en comentarios que la nombran como
--  consumidor futuro (`202609240001:95`, `202609240002:31`, `tipos.ts:564`,
--  `repos-supabase.ts:579`, `aspirante_model.dart:51`). Ninguna lista de
--  columnas, ningún ejemplo de archivo, ninguna plantilla.
--
--  La auditoría fue explícita sobre el orden correcto: «lo de HACER es una fase
--  aparte que empieza **preguntando qué campos espera HACER**, no escribiendo
--  código». Esta migración **no finge que esa respuesta llegó**. Lo que hace es
--  lo único que se puede hacer sin ella y que no se tira después:
--
--    · expone el **contexto académico** que HACER no puede deducir de la
--      planilla (a qué sección, materia, programa y lapso pertenece cada fila);
--    · expone el **contrato de identidad** que `AspiranteModel` ya declara;
--    · expone la **planilla aplanada**, campo por campo;
--    · y deja `datos_planilla` crudo al final, para que nada se pierda.
--
--  Cuando llegue la especificación de HACER, el ajuste es **esta vista y sólo
--  esta vista**: renombrar, reordenar o filtrar columnas aquí. Ni el formulario
--  ni el catálogo ni el trigger se tocan. Ese es el motivo de que la traducción
--  a «el archivo que HACER espera» viva en una capa aparte (el serializador CSV
--  del cliente), y no incrustada en la base.
--
--  POR QUÉ UNA VISTA Y NO UNA RUTA EN FASTIFY
--  ------------------------------------------
--  La frontera de autorización es la RLS, no la API (ADR-003). `enrollments`,
--  `sections`, `profiles`, `programs` y `subjects` ya tienen políticas de
--  lectura que le dan al administrador todo y al estudiante lo suyo. Una ruta
--  Fastify sería una segunda copia de esa regla, y de las dos copias la que se
--  desvía siempre es la de fuera. Es el mismo razonamiento que
--  `SupabasePlanillaAdminGateway` documenta para el catálogo.
--
--  `security_invoker = true` NO es estilo: sin él la vista correría con los
--  privilegios de su dueño, saltaría la RLS y **cualquier usuario con sesión
--  podría descargar la nómina completa del centro** con su cédula, su teléfono
--  y su dirección. Con `security_invoker`, quien consulta ve exactamente lo que
--  la RLS le deja ver. La vista del cuadrante (`v_cuadrante_clases`) ya tomó esa
--  decisión por la misma razón.
--
--  LO QUE ESTA MIGRACIÓN NO HACE
--  -----------------------------
--  · No toca ninguna tabla, política, trigger ni parámetro existente.
--  · No cambia `aspirantes` ni `datos_planilla`.
--  · No escribe el CSV: eso es del cliente (formato, comillas, BOM).
--  · No decide el nombre del archivo ni su disposición de columnas definitiva:
--    eso es exactamente lo que la especificación de HACER tiene que decir.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — `planilla_texto`: un valor de la planilla, aplanado a texto
-- ---------------------------------------------------------------------------
--  El CSV es texto y `datos_planilla` es jsonb: hace falta un puente, y ese
--  puente es una función y no un `->>` suelto por tres razones medibles.
--
--  1. `->>` no basta para los tipos que el catálogo usa de verdad. Los 44 campos
--     se reparten en nueve tipos, y **dos de ellos son estructuras**: `tabla`
--     (`familiares`, `otras_formaciones`, `experiencias`) y `rejilla`
--     (`misiones`, `tipo_discapacidad`). `->>` sobre un arreglo devuelve el JSON
--     entero pegado —`["FISICA_MANO","NINGUNA"]`—, que en una celda de CSV es
--     ilegible y además arrastra comillas dobles que hay que escapar.
--  2. Una sola definición de «vacío». `validar_planilla()` ya decidió qué cuenta
--     como vacío (clave ausente, `null`, cadena en blanco, arreglo vacío, objeto
--     vacío). Si el aplanador tuviera su propia idea, la exportación y la
--     validación podrían discrepar sobre el mismo dato.
--  3. Se puede probar sola. Una función `immutable` que sólo mira sus argumentos
--     se comprueba con un `select` en la autocomprobación de esta migración y en
--     `validate.mjs`, sin montar una inscripción entera.
--
--  `immutable` y **no** `security definer`: no lee ninguna tabla, así que no hay
--  RLS que saltarse ni `search_path` que fijar. Es una función pura de dos
--  argumentos, y declararla como tal es lo que permite que el planificador la
--  evalúe sin miedo.
create or replace function public.planilla_texto(p_datos jsonb, p_clave text)
returns text
language sql
immutable
as $$
  select case
    -- Ausente, nulo explícito o sin planilla: los tres son «no hay dato».
    when p_datos is null
      or jsonb_typeof(p_datos) <> 'object'
      or p_clave is null
      or not (p_datos ? p_clave)
      or p_datos -> p_clave = 'null'::jsonb
    then null

    -- Cadena en blanco: misma decisión que `validar_planilla()`. Si allí no
    -- cuenta como respuesta, aquí no puede salir como celda con espacios.
    when jsonb_typeof(p_datos -> p_clave) = 'string'
    then nullif(btrim(p_datos ->> p_clave), '')

    -- Arreglo: se une con ' | '. Un `multiseleccion` sale legible
    -- («FISICA_MANO | NINGUNA») y una `tabla` deja cada fila como su JSON
    -- compacto, que es la única forma de meter una fila repetible en una celda
    -- sin inventar una convención de columnas que HACER no ha pedido.
    when jsonb_typeof(p_datos -> p_clave) = 'array'
    then nullif((
      select string_agg(
               case
                 when jsonb_typeof(e) = 'object' then e::text
                 else e #>> '{}'
               end,
               ' | '
             )
      from jsonb_array_elements(p_datos -> p_clave) as t(e)
    ), '')

    -- Objeto: se serializa compacto. El objeto VACÍO es «no hay dato», igual
    -- que en `validar_planilla()`, y no una celda que dice `{}`.
    when jsonb_typeof(p_datos -> p_clave) = 'object'
    then nullif(case when p_datos -> p_clave = '{}'::jsonb
                     then '' else (p_datos -> p_clave)::text end, '')

    -- Número y booleano: `->>` ya da el texto correcto ('true', '42').
    else p_datos ->> p_clave
  end;
$$;

comment on function public.planilla_texto(jsonb, text) is
  'Aplana un valor de `aspirantes.datos_planilla` a texto para la exportación: cadenas en blanco, arreglos vacíos y objetos vacíos salen como NULL, igual que en validar_planilla(); los arreglos se unen con " | ". `immutable` porque no lee tablas.';


-- ---------------------------------------------------------------------------
--  PARTE 2 — La vista
-- ---------------------------------------------------------------------------
--  Una fila por **inscripción con asiento confirmado** (`ENROLLED`). No es «una
--  fila por aspirante» a propósito: un aspirante puede estar matriculado en dos
--  secciones de materias distintas, y HACER necesita saber en cuál de las dos.
--  La cola (`WAITLISTED`), las ofertas vivas (`PENDING_BID`) y las bajas
--  (`DROPPED`) quedan fuera: no son nómina.
--
--  Las 15 columnas del catálogo que NO se repiten aquí son exactamente las que
--  ya expone `public.aspirantes` como contrato de identidad: `cedula`,
--  `fecha_nac`, `sexo`, `discapacidad`, `tipo_discapacidad`, `direccion`,
--  `telefono`, `email`, `nivel_educativo`, los cinco del representante y
--  `curso_seleccionado` (que hoy es `program_id`, expuesto como
--  `programa_codigo`/`programa_nombre`). Duplicarlas crearía dos columnas que
--  pueden discrepar, y en una exportación la que discrepa es siempre la que
--  alguien lee. Las 29 restantes **sólo existen en la planilla** y son
--  justamente «lo que hasta ahora se perdía».
--
--  ⚠️ LÍMITE CONOCIDO, Y ES UN LÍMITE REAL: las columnas de una vista son SQL
--  estático. Si el CFS añade un campo al catálogo desde el panel (que es
--  precisamente para lo que el catálogo existe), **esta vista no crece sola**.
--  Por eso `datos_planilla` viaja al final, sin aplanar: nada se pierde nunca, y
--  el campo nuevo es recuperable desde el CSV mientras se decide si merece
--  columna propia. Añadirle una columna es una migración de una línea.
create or replace view public.v_exportacion_hacer
with (security_invoker = true)
as
select
  -- --- Contexto académico: a qué se inscribió ------------------------------
  e.id                                  as inscripcion_id,
  e.section_id                          as seccion_id,
  s.period_code                         as lapso,
  s.name                                as seccion,
  s.is_active                           as seccion_activa,
  s.program_id                          as programa_id,
  p.code                                as programa_codigo,
  p.name                                as programa_nombre,
  s.subject_id                          as materia_id,
  su.code                               as materia_codigo,
  su.name                               as materia_nombre,
  -- El docente se resuelve con `nombre_para_mostrar` y no uniendo `profiles`
  -- a mano: esa función es `definer`, devuelve SÓLO el nombre de un docente o
  -- admin activo y no expone cédula ni correo (R-14). Una unión directa con
  -- `profiles` devolvería NULL para cualquier no-admin, porque
  -- `profiles_read_own` limita el SELECT a la fila propia.
  -- Se agregan los docentes distintos de los bloques activos: una sección puede
  -- tener clase con más de uno, y quedarse con el primero escondería al otro.
  td.docente                            as docente,
  e.status                              as estado,
  e.created_at                          as inscrito_en,

  -- --- Identidad: el contrato que `AspiranteModel` ya declara --------------
  a.id                                  as aspirante_id,
  a.cedula,
  a.nombres,
  a.apellidos,
  a.fecha_nac,
  a.sexo,
  a.telefono,
  a.email,
  a.direccion,
  a.nivel_educativo,
  a.discapacidad,
  a.tipo_discapacidad,
  a.numero_identidad_tutor,
  a.nombre_tutor,
  a.parentesco_tutor,
  a.telefono_tutor,
  a.correo_tutor,

  -- --- Planilla aplanada: los 29 campos que sólo viven en el jsonb ---------
  -- En el orden del catálogo (`inscripcion_campos.orden`), no en el orden en que
  -- se me ocurrieron: si alguien compara la vista contra el catálogo, los dos
  -- tienen que leerse en el mismo orden.
  public.planilla_texto(a.datos_planilla, 'numero_preimpreso')          as planilla_numero_preimpreso,
  public.planilla_texto(a.datos_planilla, 'primer_nombre')              as planilla_primer_nombre,
  public.planilla_texto(a.datos_planilla, 'segundo_nombre')             as planilla_segundo_nombre,
  public.planilla_texto(a.datos_planilla, 'primer_apellido')            as planilla_primer_apellido,
  public.planilla_texto(a.datos_planilla, 'segundo_apellido')           as planilla_segundo_apellido,
  public.planilla_texto(a.datos_planilla, 'nacionalidad')               as planilla_nacionalidad,
  public.planilla_texto(a.datos_planilla, 'estado_civil')               as planilla_estado_civil,
  public.planilla_texto(a.datos_planilla, 'pueblo_indigena')            as planilla_pueblo_indigena,
  public.planilla_texto(a.datos_planilla, 'pueblo_indigena_cual')       as planilla_pueblo_indigena_cual,
  public.planilla_texto(a.datos_planilla, 'deporte')                    as planilla_deporte,
  public.planilla_texto(a.datos_planilla, 'deporte_desde')              as planilla_deporte_desde,
  public.planilla_texto(a.datos_planilla, 'actividad_cultural')         as planilla_actividad_cultural,
  public.planilla_texto(a.datos_planilla, 'actividad_cultural_desde')   as planilla_actividad_cultural_desde,
  public.planilla_texto(a.datos_planilla, 'organizacion_social')        as planilla_organizacion_social,
  public.planilla_texto(a.datos_planilla, 'organizacion_social_desde')  as planilla_organizacion_social_desde,
  public.planilla_texto(a.datos_planilla, 'estado')                     as planilla_estado,
  public.planilla_texto(a.datos_planilla, 'municipio')                  as planilla_municipio,
  public.planilla_texto(a.datos_planilla, 'parroquia')                  as planilla_parroquia,
  public.planilla_texto(a.datos_planilla, 'comunidad')                  as planilla_comunidad,
  public.planilla_texto(a.datos_planilla, 'telefono_fijo')              as planilla_telefono_fijo,
  public.planilla_texto(a.datos_planilla, 'twitter')                    as planilla_twitter,
  public.planilla_texto(a.datos_planilla, 'facebook')                   as planilla_facebook,
  public.planilla_texto(a.datos_planilla, 'familiares')                 as planilla_familiares,
  public.planilla_texto(a.datos_planilla, 'misiones')                   as planilla_misiones,
  public.planilla_texto(a.datos_planilla, 'nivel_avance')               as planilla_nivel_avance,
  public.planilla_texto(a.datos_planilla, 'ultimo_anio')                as planilla_ultimo_anio,
  public.planilla_texto(a.datos_planilla, 'especialidad')               as planilla_especialidad,
  public.planilla_texto(a.datos_planilla, 'otras_formaciones')          as planilla_otras_formaciones,
  public.planilla_texto(a.datos_planilla, 'experiencias')               as planilla_experiencias,

  -- --- La red de seguridad -------------------------------------------------
  a.datos_planilla
from public.enrollments e
  join public.sections s  on s.id  = e.section_id
  join public.programs p  on p.id  = s.program_id
  join public.subjects su on su.id = s.subject_id
  -- `left`: una inscripción cuyo aspirante se borró (`user_id` es `on delete set
  -- null`) sigue siendo una fila de nómina y no puede desaparecer del CSV por un
  -- join interno. Las columnas de identidad salen nulas y el contexto académico
  -- —que es lo que HACER usa para ubicar el cupo— se conserva.
  left join public.aspirantes a on a.user_id = e.student_id
  left join lateral (
    select string_agg(distinct public.nombre_para_mostrar(ss.teacher_id), ' / ')
             as docente
    from public.schedule_slots ss
    where ss.section_id = s.id
      and ss.is_active
  ) td on true
where e.status = 'ENROLLED';

comment on view public.v_exportacion_hacer is
  'Nómina lista para HACER: una fila por inscripción ENROLLED, con el contexto académico (sección, lapso, materia, programa, docente), el contrato de identidad de `aspirantes` y los 29 campos de `datos_planilla` que sólo viven en el jsonb, más `datos_planilla` crudo. `security_invoker`: la RLS decide qué filas ve cada rol, así que el administrador ve todo y cualquier otro sólo lo que ya podía leer. Las columnas de la planilla son estáticas: si el catálogo gana un campo, hay que añadirlo aquí en una migración.';


-- ---------------------------------------------------------------------------
--  PARTE 3 — Permisos
-- ---------------------------------------------------------------------------
--  Las vistas no heredan los privilegios por defecto de las tablas, así que hay
--  que conceder explícitamente. Mismo criterio que `v_ocupacion_secciones`: sólo
--  lectura, y sólo para `authenticated` — un `anon` no tiene sesión, y la vista
--  es la nómina completa del centro.
revoke all on public.v_exportacion_hacer from anon, authenticated;
grant select on public.v_exportacion_hacer to authenticated;

--  `planilla_texto` SÍ necesita EXECUTE para `authenticated` aunque sea
--  `immutable`: la vista es `security_invoker`, así que la llamada dentro de su
--  SELECT se evalúa con los privilegios de quien consulta. Sin este grant, el
--  administrador recibiría `permission denied for function planilla_texto` al
--  abrir el CSV. Es el mismo detalle que `verificar-esquema.mjs` documenta para
--  `cupo_efectivo`.
revoke all on function public.planilla_texto(jsonb, text) from public, anon;
grant execute on function public.planilla_texto(jsonb, text) to authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 4 — Comprobación de la propia migración
-- ---------------------------------------------------------------------------
--  Una migración que crea una vista de 61 columnas y no comprueba nada deja el
--  error para el día en que alguien abre el CSV, y el síntoma aparecería como
--  «la exportación está rara», no como «falta una migración». Se comprueba aquí
--  y con errores que nombran la causa.
do $$
declare
  v_reloptions text;
  v_definicion text;
  v_columnas   int;
  v_faltan     text;
  v_vacio      text;
begin
  -- 1. La vista existe, es una vista y es `security_invoker`.
  select array_to_string(c.reloptions, ','), pg_get_viewdef(c.oid, true)
    into v_reloptions, v_definicion
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'v_exportacion_hacer'
    and c.relkind = 'v';

  if v_definicion is null then
    raise exception
      'La vista public.v_exportacion_hacer no quedó creada (o no es una vista).'
      using errcode = '42P01';
  end if;

  if v_reloptions is null or v_reloptions not like '%security_invoker=%' then
    raise exception
      'v_exportacion_hacer quedó SIN security_invoker: saltaría la RLS y cualquier sesión vería la nómina completa del centro.'
      using errcode = '23514';
  end if;

  -- 2. Filtra por ENROLLED. Si no, el CSV mezclaría la cola y las bajas con la
  --    nómina, que es el error que más caro se detecta (a mano, en HACER).
  if v_definicion not like '%ENROLLED%' then
    raise exception
      'v_exportacion_hacer no filtra por ENROLLED: exportaría la cola y las bajas como si fueran matrículas.'
      using errcode = '23514';
  end if;

  -- 3. Está aplanando la planilla: si `planilla_texto` no aparece en la
  --    definición, las columnas «planilla_*» serían otra cosa.
  if v_definicion not like '%planilla_texto%' then
    raise exception
      'v_exportacion_hacer no usa planilla_texto(): las columnas de la planilla no serían una extracción plana.'
      using errcode = '23514';
  end if;

  -- 4. Las 29 claves que la vista extrae EXISTEN en el catálogo. Esta es la
  --    comprobación que ata la vista a la medición: el catálogo está en la nube
  --    (44 filas) y la lista de columnas de arriba se escribió leyéndolo. Si
  --    alguien renombra o retira un código, esto lo dice con su nombre en vez de
  --    dejar una columna que devuelve NULL para siempre.
  select string_agg(cod, ', ' order by cod)
    into v_faltan
  from unnest(array[
    'actividad_cultural', 'actividad_cultural_desde', 'comunidad', 'deporte',
    'deporte_desde', 'especialidad', 'estado', 'estado_civil', 'experiencias',
    'facebook', 'familiares', 'misiones', 'municipio', 'nacionalidad',
    'nivel_avance', 'numero_preimpreso', 'organizacion_social',
    'organizacion_social_desde', 'otras_formaciones', 'parroquia',
    'primer_apellido', 'primer_nombre', 'pueblo_indigena',
    'pueblo_indigena_cual', 'segundo_apellido', 'segundo_nombre',
    'telefono_fijo', 'twitter', 'ultimo_anio'
  ]) as cod
  where not exists (
    select 1 from public.inscripcion_campos c where c.codigo = cod
  );

  if v_faltan is not null then
    raise exception
      'v_exportacion_hacer extrae códigos que no están en el catálogo de inscripción: %.',
      v_faltan
      using errcode = '23514';
  end if;

  -- 5. Cuenta de columnas. Se comprueba por umbral y no por igualdad exacta: la
  --    cifra exacta obligaría a editar esta migración cada vez que se añada una
  --    columna, que es justo lo que se quiere poder hacer sin ceremonia. El
  --    umbral caza el fallo real —que la vista haya quedado a medias—.
  select count(*) into v_columnas
  from information_schema.columns
  where table_schema = 'public' and table_name = 'v_exportacion_hacer';

  if v_columnas < 61 then
    raise exception
      'v_exportacion_hacer quedó con % columnas; se esperaban al menos 61.', v_columnas
      using errcode = '23514';
  end if;

  -- 6. `planilla_texto` se comporta. Se prueban los casos que la Parte 1
  --    documenta, incluido el que más importa: que un valor AUSENTE salga NULL y
  --    no la cadena 'null'.
  if public.planilla_texto('{"a":1}'::jsonb, 'no_existe') is not null then
    raise exception 'planilla_texto devolvió algo para una clave ausente.'
      using errcode = '23514';
  end if;

  if public.planilla_texto('{"a":null}'::jsonb, 'a') is not null then
    raise exception 'planilla_texto devolvió algo para un null explícito.'
      using errcode = '23514';
  end if;

  if public.planilla_texto('{"a":"   "}'::jsonb, 'a') is not null then
    raise exception 'planilla_texto devolvió espacios en blanco como si fueran dato.'
      using errcode = '23514';
  end if;

  if public.planilla_texto('{"a":[]}'::jsonb, 'a') is not null then
    raise exception 'planilla_texto devolvió algo para un arreglo vacío.'
      using errcode = '23514';
  end if;

  if public.planilla_texto('{"a":{}}'::jsonb, 'a') is not null then
    raise exception 'planilla_texto devolvió {} como si fuera dato.'
      using errcode = '23514';
  end if;

  if public.planilla_texto('{"a":["X","Y"]}'::jsonb, 'a') <> 'X | Y' then
    raise exception 'planilla_texto no une los arreglos con " | " (devolvió %).',
      public.planilla_texto('{"a":["X","Y"]}'::jsonb, 'a')
      using errcode = '23514';
  end if;

  if public.planilla_texto('{"a":true}'::jsonb, 'a') <> 'true' then
    raise exception 'planilla_texto no aplana un booleano a texto.'
      using errcode = '23514';
  end if;

  raise notice
    'v_exportacion_hacer lista: % columnas, filtrada por ENROLLED y con security_invoker.',
    v_columnas;
end $$;
