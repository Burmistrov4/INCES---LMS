-- ============================================================================
--  INCES LMS — Módulo 2: Currículo y Pensum (Planificación Académica)
--  Archivo: 202609150001_mod2_curriculo.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  Define la carga académica **teórica** del INCES: qué programas de formación
--  existen, qué materias los componen y en qué período va cada una. Todavía no
--  hay salones, horarios ni docentes: eso es M3.
--
--  Tres tablas:
--
--    1) programs         -> la oferta macro: carreras y cursos libres.
--    2) subjects         -> banco global de materias, compartido.
--    3) program_subjects -> el pensum: qué materia, en qué programa, en qué
--                           período. Es una relación muchos-a-muchos.
--
--  POR QUÉ LA TABLA PUENTE NO ES DECORACIÓN
--  ----------------------------------------
--  "Inglés Técnico" existe UNA vez en `subjects` y aparece en cinco pensums.
--  Duplicar la materia por programa es lo que después hace que las notas de dos
--  alumnos de la misma materia no sean comparables, y que corregir el nombre de
--  una asignatura obligue a tocar siete filas.
--
--
--  LAS DOS REGLAS DE NEGOCIO
--  -------------------------
--  REGLA 1 — No existen CARRERAS vacías.
--    Una CARRERA activa con cero materias es un error del administrativo, no un
--    estado válido. Se implementa con un **constraint trigger diferido**
--    (`deferrable initially deferred`): la comprobación corre al CONFIRMAR la
--    transacción, no al insertar cada fila.
--
--    Esa diferencia es la que permite que el asistente de tres pasos mande el
--    programa y su pensum en UNA sola petición y pase la validación, mientras
--    que un `insert into programs` suelto y sin materias falla. El documento de
--    arquitectura pide un POST consolidado al final del asistente: el diferido
--    es exactamente lo que hace compatibles las dos cosas.
--
--    Consecuencia asumida: no se puede crear un programa activo y añadirle
--    materias en una transacción POSTERIOR. Para reestructurar, se archiva el
--    programa y se clona — que es lo que el documento manda de todos modos.
--
--    **POR QUÉ SÓLO `CARRERA`.** El documento dice literalmente "no existen
--    carreras vacías", y un CURSO_LIBRE es otra cosa: un taller corto
--    ('Oratoria', 'Herrería') que puede no tener malla curricular. Si la regla
--    cubriera también a los cursos libres, la migración 202609160001 —que
--    absorbe los 5 cursos de Fase 0 dentro de `programs`— sería imposible de
--    aplicar: ningún curso libre podría quedar activo sin inventarle una
--    materia. La regla se acota a lo que el documento pide.
--
--  REGLA 2 — Inmutabilidad en uso.
--    No se puede cambiar el `period_order` de un pensum ni quitarle materias si
--    ya hay secciones activas del período vigente usando ese programa.
--
--    **SE IMPLEMENTA EN 202609160001**, que es donde existe `sections.program_id`
--    (deuda D13: el `sections` de Fase 0 no era el que M3 necesita).
--
--  DECISIONES DE DISEÑO, Y DE DÓNDE SALEN
--  --------------------------------------
--  * `type` es `text` + `check`, no un `enum` de Postgres. El documento pide
--    ENUM, pero la convención del proyecto ya está escrita en
--    `202609130001_invitaciones_docente.sql`: "No se usa un enum de Postgres
--    para no atarnos al dialecto". Se sigue la convención del código.
--
--  * `is_active` nace en `false`, no en `true`. El documento pone DEFAULT TRUE,
--    pero eso **contradice su propia Regla 1**: el programa nacería activo y sin
--    materias, así que todo `insert` fallaría. Nace en borrador; publicarlo
--    (ponerlo activo) es lo que dispara la validación.
--
--  * Las columnas van en inglés (`code`, `name`, `academic_hours`) porque así las
--    define el documento y porque la migración más reciente del proyecto
--    (`teacher_invitations`) ya usa inglés. Las tablas de Fase 0 usan español
--    (`nombre`, `activo`). La mezcla es real y está asumida.
--
--
--  AL APLICAR ESTA MIGRACIÓN, DOS COSAS OBLIGATORIAS
--  -------------------------------------------------
--  1. Añadir 'programs', 'subjects' y 'program_subjects' al arreglo `esperadas`
--     de `supabase/verificar-esquema.mjs`. Si no, ese script las reporta como
--     "tablas heredadas" y falla — es exactamente lo que pasó con
--     `schema_migrations`.
--  2. Resolver antes la deuda **D12**: `cursos` (Fase 0) y `programs` (M2) son
--     el mismo concepto. Los cinco cursos sembrados (Herrería, Oratoria, …) son
--     exactamente CURSO_LIBRE. Esta migración **no los toca**: absorberlos
--     implica migrar `aspirantes.curso_seleccionado` (texto libre) y el
--     formulario público de inscripción. Es una decisión consciente, no un
--     olvido. Ver ESTADO_DEL_SISTEMA.md §9.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tabla: programs (Programas de Formación)
-- ---------------------------------------------------------------------------
create table if not exists public.programs (
  id                  uuid        primary key default gen_random_uuid(),

  -- Código institucional (ej. 'CUR-SIST-01'). Se acota a 12 caracteres y a
  -- mayúsculas/dígitos/guion porque es un identificador que la gente teclea a
  -- mano en planillas y carteleras: si se admite texto libre, alguien guarda
  -- 'Análisis de Sistemas' aquí y el código deja de servir para identificar.
  code                varchar(12) not null unique
                        check (code ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),

  name                varchar(100) not null
                        check (btrim(name) <> ''),

  -- 'CARRERA' o 'CURSO_LIBRE'. Define la naturaleza y la duración del trayecto:
  -- sólo una carrera habilita la organización por semestres en el asistente.
  type                text        not null
                        check (type in ('CARRERA', 'CURSO_LIBRE')),

  -- El interruptor que M8 (Pasantías) lee: si es TRUE, ningún estudiante de este
  -- programa puede llegar a EGRESADO sin que M8 verifique sus evaluaciones de
  -- campo. Es la única conexión de M2 con M8, y por eso vive aquí y no en M8.
  requires_internship boolean     not null default false,

  -- Deshabilitar la oferta sin borrar históricos. Nace en FALSE a propósito:
  -- ver "DECISIONES DE DISEÑO" arriba.
  is_active           boolean     not null default false,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.programs is
  'Oferta formativa macro del INCES: carreras y cursos libres. Carga académica teórica, sin salones ni docentes (eso es M3).';
comment on column public.programs.code is
  'Código institucional corto (máx. 12). MAYÚSCULAS, dígitos y guion: es un identificador que se teclea a mano.';
comment on column public.programs.type is
  'CARRERA o CURSO_LIBRE. Sólo una CARRERA permite organizar el pensum por semestres.';
comment on column public.programs.requires_internship is
  'Si es TRUE, M8 exige el aval del tutor industrial antes de declarar EGRESADO al estudiante.';
comment on column public.programs.is_active is
  'Nace en FALSE (borrador). Publicar = ponerlo en TRUE, y eso dispara la validación de pensum no vacío.';


-- ---------------------------------------------------------------------------
-- 2. Tabla: subjects (Banco de Materias Global)
-- ---------------------------------------------------------------------------
create table if not exists public.subjects (
  id             uuid        primary key default gen_random_uuid(),

  code           varchar(12) not null unique
                   check (code ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),

  name           varchar(100) not null
                   check (btrim(name) <> ''),

  -- Carga horaria total exigida por el diseño curricular. El `> 0` no es
  -- decorativo: una materia de cero horas es un error de captura que después
  -- descuadra cualquier cálculo de carga académica.
  academic_hours integer     not null
                   check (academic_hours > 0),

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.subjects is
  'Banco global de materias. Una materia existe UNA vez y se comparte entre programas a través de program_subjects.';
comment on column public.subjects.academic_hours is
  'Carga horaria total de la asignatura. Debe ser > 0.';


-- ---------------------------------------------------------------------------
-- 3. Tabla: program_subjects (Estructura del Pensum)
-- ---------------------------------------------------------------------------
create table if not exists public.program_subjects (
  id           uuid        primary key default gen_random_uuid(),

  program_id   uuid        not null
                 references public.programs(id) on delete cascade,

  -- `on delete restrict`: una materia que está en un pensum no se puede borrar.
  -- Borrarla dejaría el pensum de un programa apuntando al vacío, y el
  -- estudiante que ya la cursó sin materia a la que asociar su nota.
  subject_id   uuid        not null
                 references public.subjects(id) on delete restrict,

  -- Semestre, trimestre o fase (1, 2, 3, 4…). Los CURSO_LIBRE usan siempre 1.
  period_order integer     not null default 1
                 check (period_order >= 1),

  created_at   timestamptz not null default now(),

  -- Una materia no puede estar dos veces en el mismo pensum. Sin esta
  -- restricción, el asistente puede dejar "Algorítmica" en el período 2 y en el
  -- 5 a la vez, y el pensum miente.
  constraint program_subjects_materia_unica unique (program_id, subject_id)
);

comment on table public.program_subjects is
  'Pensum: qué materia va en qué programa y en qué período. Tabla puente muchos-a-muchos.';
comment on column public.program_subjects.period_order is
  'Período lógico de la materia dentro del programa (1, 2, 3, 4…). Los CURSO_LIBRE usan 1.';


-- ---------------------------------------------------------------------------
-- 4. Regla 1 — No existen CARRERAS vacías (constraint trigger DIFERIDO)
-- ---------------------------------------------------------------------------
-- Diferido a propósito: la comprobación corre al confirmar la transacción, así
-- que el asistente puede insertar el programa y su pensum en el mismo lote y
-- pasar la validación. Ver el encabezado del archivo.
--
-- Sólo mira las CARRERA. Un CURSO_LIBRE puede no tener pensum: es un taller
-- corto, no un plan de estudios. Ver "LAS DOS REGLAS DE NEGOCIO" arriba.
create or replace function public.exigir_pensum_de_programa()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_programa uuid;
  v_activo   boolean;
  v_tipo     text;
  v_materias integer;
begin
  -- De qué programa hay que comprobar el pensum. La columna cambia de nombre
  -- según la tabla que disparó el trigger.
  if tg_table_name = 'programs' then
    v_programa := new.id;
  elsif tg_op = 'DELETE' then
    v_programa := old.program_id;
  else
    v_programa := new.program_id;
  end if;

  -- Si el programa ya no existe (se está borrando en esta misma transacción),
  -- no hay nada que exigirle. `not found` cubre ese caso.
  select is_active, type into v_activo, v_tipo
  from public.programs where id = v_programa;

  if not found or v_activo is not true or v_tipo <> 'CARRERA' then
    return null;
  end if;

  select count(*) into v_materias
  from public.program_subjects
  where program_id = v_programa;

  if v_materias = 0 then
    -- 23514 -> el backend lo traduce a RESTRICCION_VIOLADA (400), que es lo
    -- correcto: es un dato que no cumple una regla del sistema, no una caída.
    raise exception
      'Una carrera activa no puede quedarse sin materias. Añada al menos una al pensum o póngala en borrador (is_active = false).'
      using errcode = '23514';
  end if;

  return null;
end;
$$;

comment on function public.exigir_pensum_de_programa() is
  'Regla 1 de M2: un programa activo con cero materias es un error, no un estado válido. Constraint trigger diferido.';

-- Se dispara desde los dos lados: al publicar un programa, y al vaciarle el
-- pensum a un programa ya activo. Los dos caminos dejan el mismo estado inválido.
drop trigger if exists programs_exigir_pensum on public.programs;
create constraint trigger programs_exigir_pensum
after insert or update on public.programs
deferrable initially deferred
for each row execute function public.exigir_pensum_de_programa();

drop trigger if exists program_subjects_exigir_pensum on public.program_subjects;
create constraint trigger program_subjects_exigir_pensum
after delete or update on public.program_subjects
deferrable initially deferred
for each row execute function public.exigir_pensum_de_programa();


-- ---------------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------------
alter table public.programs         enable row level security;
alter table public.subjects         enable row level security;
alter table public.program_subjects enable row level security;

-- --- programs --------------------------------------------------------------
-- La oferta activa es pública: el formulario de inscripción del aspirante
-- necesita mostrar los programas, igual que hoy lee `cursos` con `anon`. Sólo lo
-- activo: un borrador no debe asomar en el formulario.
drop policy if exists programs_read_activos on public.programs;
create policy programs_read_activos
on public.programs
for select
to anon
using (is_active);

-- Cualquier autenticado ve la oferta completa, incluidos los borradores: el
-- docente necesita saber qué va a dictar y el estudiante qué le falta.
drop policy if exists programs_read_authenticated on public.programs;
create policy programs_read_authenticated
on public.programs
for select
to authenticated
using (true);

drop policy if exists programs_admin_write on public.programs;
create policy programs_admin_write
on public.programs
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- --- subjects --------------------------------------------------------------
-- El banco de materias NO es público: no aporta nada al formulario de
-- inscripción y expone la malla curricular completa.
drop policy if exists subjects_read_authenticated on public.subjects;
create policy subjects_read_authenticated
on public.subjects
for select
to authenticated
using (true);

drop policy if exists subjects_admin_write on public.subjects;
create policy subjects_admin_write
on public.subjects
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- --- program_subjects ------------------------------------------------------
drop policy if exists program_subjects_read_authenticated on public.program_subjects;
create policy program_subjects_read_authenticated
on public.program_subjects
for select
to authenticated
using (true);

drop policy if exists program_subjects_admin_write on public.program_subjects;
create policy program_subjects_admin_write
on public.program_subjects
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- ---------------------------------------------------------------------------
-- 6. Permisos a nivel de tabla (defensa en profundidad)
-- ---------------------------------------------------------------------------
--  Supabase concede privilegios por defecto sobre TABLA NUEVA en public a
--  anon/authenticated. Se revoca todo y se concede sólo lo necesario. La
--  service_role conserva sus privilegios por defecto y no se toca aquí.
revoke all on public.programs         from anon, authenticated;
revoke all on public.subjects         from anon, authenticated;
revoke all on public.program_subjects from anon, authenticated;

grant select on public.programs to anon;

-- Nada de DELETE sobre programs ni subjects: archivar es `is_active = false`, y
-- un borrado se llevaría por delante el histórico. El pensum sí necesita DELETE,
-- porque reemplazarlo implica quitar las materias que ya no van.
grant select, insert, update         on public.programs         to authenticated;
grant select, insert, update         on public.subjects         to authenticated;
grant select, insert, update, delete on public.program_subjects to authenticated;


-- ---------------------------------------------------------------------------
-- 7. Triggers de updated_at
-- ---------------------------------------------------------------------------
drop trigger if exists programs_set_updated_at on public.programs;
create trigger programs_set_updated_at
before update on public.programs
for each row execute function public.set_updated_at();

drop trigger if exists subjects_set_updated_at on public.subjects;
create trigger subjects_set_updated_at
before update on public.subjects
for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
-- 8. Índices de apoyo
-- ---------------------------------------------------------------------------
-- `program_subjects_materia_unica` ya indexa (program_id, subject_id), así que
-- las búsquedas "el pensum de este programa" están cubiertas. Falta el sentido
-- contrario: "en qué programas se dicta esta materia", que usa el selector de M3.
create index if not exists program_subjects_subject_id_idx
  on public.program_subjects (subject_id);

-- El listado del cPanel filtra por estado para separar borradores de publicados.
create index if not exists programs_is_active_idx
  on public.programs (is_active);
