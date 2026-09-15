-- ============================================================================
--  INCES LMS — Módulo 2: las dos escrituras transaccionales del asistente
--  Archivo: 202609170001_mod2_rpc_curriculo.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  POR QUÉ ESTE ARCHIVO EXISTE (y no es un capricho)
--  -------------------------------------------------
--  El contrato de M2 (`docs/CONTRATO_API_MODULO2.md`) pide dos operaciones
--  atómicas:
--
--    · el asistente: programa + pensum en una sola petición, para que el
--      constraint trigger diferido de la Regla 1 vea el pensum al confirmar;
--    · el reemplazo del pensum: borrar lo que sobra, reordenar lo que cambia e
--      insertar lo nuevo, todo o nada.
--
--  Con PostgREST eso NO se puede hacer de forma declarativa. Se comprobó contra
--  la base real el 2026-09-15, no se supuso:
--
--    1. Un insert anidado (`POST /programs` con `program_subjects: [...]`)
--       responde **PGRST204: Could not find the 'program_subjects' column of
--       'programs' in the schema cache**. PostgREST 14.5 no admite insertar un
--       padre con sus hijos en la misma petición.
--    2. No es un problema de caché: tras `notify pgrst, 'reload schema'` el
--       error es idéntico.
--    3. La relación SÍ existe y PostgREST la conoce: la lectura anidada
--       (`GET /programs?select=*,program_subjects(*)`) responde 200.
--
--  Es decir: se puede leer anidado, pero no escribir anidado. Y PostgREST no
--  expone transacciones entre peticiones: cada petición es su propia
--  transacción. Sin una función, el asistente tendría que hacer tres llamadas
--  (crear en borrador → insertar pensum → publicar) y un fallo a mitad dejaría
--  un programa a medio armar, que es justo lo que el contrato quiere evitar.
--
--  La solución es la que ya usa el proyecto para la lógica que necesita ser
--  atómica (`precheck_aspirante`, `link_pending_aspirante`): una función en
--  PostgreSQL, llamada por PostgREST con `POST /rest/v1/rpc/<nombre>`.
--
--
--  `security invoker`, NO `security definer`
--  -----------------------------------------
--  Es la decisión más importante del archivo. Con `security definer` la función
--  correría con los privilegios de su dueño y **se saltaría la RLS**: cualquier
--  usuario autenticado podría escribir programas. Con `security invoker`, las
--  políticas de `programs` y `program_subjects` se aplican al llamante, que es
--  la segunda barrera del proyecto (la primera es `exigirAdmin` en la API).
--
--  `set search_path = public` acompaña a esto: sin él, un esquema en el
--  `search_path` del llamante podría secuestrar un nombre de tabla. Es la
--  recomendación de PostgreSQL para funciones que tocan datos.
--
--
--  LAS DOS REGLAS DE NEGOCIO SIGUEN VIVIENDO EN LOS TRIGGERS
--  ---------------------------------------------------------
--  Estas funciones NO reimplementan la Regla 1 ni la Regla 2: sólo ordenan las
--  escrituras para que los triggers las puedan juzgar. Si la Regla 2 bloquea un
--  reordenamiento, el `raise` del trigger aborta la función entera y no queda
--  nada a medias. Una sola fuente de verdad para cada invariante.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. El asistente: crear un programa con su pensum, todo o nada
-- ---------------------------------------------------------------------------
--  Devuelve el `id` del programa creado. El repositorio vuelve a leerlo después
--  para armar la respuesta: así esta función no duplica la forma del detalle y
--  no hay dos sitios que puedan divergir al añadir una columna.
--
--  `p_pensum` llega como jsonb con la forma `[{"materiaId": "…", "periodo": 1}]`.
--  Se usa jsonb y no un arreglo de tipos porque PostgREST pasa los argumentos
--  de una función como JSON, y un tipo compuesto obligaría a declararlo también
--  en la base y en el cliente.
--
--  Si `p_publicar` es `true`, el programa nace activo y el constraint trigger
--  diferido `programs_exigir_pensum` comprobará al confirmar que tiene materias.
--  Si el pensum viniera vacío, la función entera se deshace: no queda un
--  programa a medias.
create or replace function public.crear_programa_con_pensum(
  p_code                text,
  p_name                text,
  p_type                text,
  p_requires_internship boolean,
  p_publicar            boolean,
  p_pensum              jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_programa uuid;
  v_item     jsonb;
  v_materia  uuid;
  v_periodo  int;
begin
  -- El `type` no se valida aquí: lo hace el CHECK de la tabla. Duplicar la
  -- regla en la función sería un segundo sitio donde equivocarse.
  insert into public.programs (code, name, type, requires_internship, is_active)
  values (p_code, p_name, p_type, p_requires_internship, p_publicar)
  returning id into v_programa;

  -- Recorrer el arreglo con un bucle en vez de un `insert ... select` deja el
  -- error de una materia concreta apuntando a esa fila. Con una inserción
  -- masiva, un `23503` no diría cuál de las materias no existe.
  for v_item in select * from jsonb_array_elements(p_pensum)
  loop
    v_materia := (v_item ->> 'materiaId')::uuid;
    v_periodo := coalesce((v_item ->> 'periodo')::int, 1);

    insert into public.program_subjects (program_id, subject_id, period_order)
    values (v_programa, v_materia, v_periodo);
  end loop;

  return v_programa;
end;
$$;

comment on function public.crear_programa_con_pensum(text, text, text, boolean, boolean, jsonb) is
  'Asistente de M2: crea un programa y su pensum en una sola transacción. Existe porque PostgREST no admite insertar un padre con sus hijos en la misma petición (comprobado: PGRST204).';


-- ---------------------------------------------------------------------------
-- 2. Reemplazar el pensum completo, calculando la diferencia
-- ---------------------------------------------------------------------------
--  Es un REEMPLAZO, no un parche: el cliente manda el estado final y aquí se
--  calcula qué sobra, qué cambia y qué falta. El cliente no debería tener que
--  saber qué borrar.
--
--  El orden importa y no es casual:
--
--    1. Borrar lo que ya no está  → la Regla 2 lo bloquea si hay secciones
--                                   activas (quitar materias es estructural).
--    2. Reordenar lo que cambió   → la Regla 2 también. El `is distinct from`
--                                   evita que un guardado sin cambios reales
--                                   dispare el trigger y bloquee de más.
--    3. Insertar lo nuevo         → el trigger NO mira los insert: añadir una
--                                   materia a un pensum en uso es legítimo.
--
--  Dentro de una transacción el orden no cambia la atomicidad —un fallo lo
--  deshace todo—, pero sí cambia qué error ve el administrador primero: el más
--  explicativo, que es el borrado.
create or replace function public.reemplazar_pensum(
  p_program_id uuid,
  p_pensum     jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- 1. Fuera lo que ya no está en el pensum nuevo.
  delete from public.program_subjects ps
  where ps.program_id = p_program_id
    and not exists (
      select 1
      from jsonb_array_elements(p_pensum) as item
      where (item ->> 'materiaId')::uuid = ps.subject_id
    );

  -- 2. Reordenar sólo lo que de verdad cambió de período.
  update public.program_subjects ps
  set period_order = (item ->> 'periodo')::int
  from jsonb_array_elements(p_pensum) as item
  where ps.program_id = p_program_id
    and ps.subject_id = (item ->> 'materiaId')::uuid
    and ps.period_order is distinct from (item ->> 'periodo')::int;

  -- 3. Entra lo que falta.
  insert into public.program_subjects (program_id, subject_id, period_order)
  select p_program_id, (item ->> 'materiaId')::uuid, coalesce((item ->> 'periodo')::int, 1)
  from jsonb_array_elements(p_pensum) as item
  where not exists (
    select 1
    from public.program_subjects ps
    where ps.program_id = p_program_id
      and ps.subject_id = (item ->> 'materiaId')::uuid
  );
end;
$$;

comment on function public.reemplazar_pensum(uuid, jsonb) is
  'Reemplazo transaccional del pensum de M2: borra lo que sobra, reordena lo que cambia e inserta lo nuevo. La Regla 2 la aplican los triggers de program_subjects, no esta función.';


-- ---------------------------------------------------------------------------
-- 3. Permisos
-- ---------------------------------------------------------------------------
--  Sólo `authenticated`. La API exige rol `admin` antes de llegar aquí, y las
--  políticas RLS de las dos tablas lo vuelven a exigir dentro de la función
--  (`security invoker`). `anon` no tiene nada que hacer con estas funciones: la
--  oferta formativa se lee, no se escribe.
--
--  Se revoca de `public` explícitamente porque PostgreSQL concede EXECUTE a
--  PUBLIC por defecto en toda función nueva. Sin este `revoke`, la función
--  sería alcanzable por `anon` aunque las tablas no lo fueran.
revoke all on function public.crear_programa_con_pensum(text, text, text, boolean, boolean, jsonb) from public, anon;
revoke all on function public.reemplazar_pensum(uuid, jsonb) from public, anon;

grant execute on function public.crear_programa_con_pensum(text, text, text, boolean, boolean, jsonb) to authenticated;
grant execute on function public.reemplazar_pensum(uuid, jsonb) to authenticated;
