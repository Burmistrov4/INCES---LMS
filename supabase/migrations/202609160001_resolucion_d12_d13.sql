-- ============================================================================
--  INCES LMS — Resolución de D12 y D13
--  Archivo: 202609160001_resolucion_d12_d13.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  D12 — `cursos` (Fase 0) y `programs` (M2) eran el mismo concepto.
--        Los cinco cursos sembrados (Herrería, Oratoria, …) son exactamente
--        CURSO_LIBRE. Ahora `programs` es la única fuente de verdad y `cursos`
--        pasa a ser una vista de compatibilidad sobre ella.
--
--  D13 — `sections` de Fase 0 (`nombre`, `cupo_maximo`, `activa`) no era la que
--        exige el Módulo 3, y no tenía `program_id`, así que la Regla 2 de M2
--        era inimplementable y la cabecera del cuadrante
--        (`PERÍODO | ESPECIALIDAD | SECCIÓN`) quedaba ambigua: una materia
--        puede pertenecer a varios programas.
--
--  Y de paso implementa la **Regla 2** de M2 (inmutabilidad del pensum en uso),
--  que estaba escrita pero sin implementar precisamente por D13.
--
--
--  POR QUÉ ESTA MIGRACIÓN PUEDE SER AGRESIVA
--  -----------------------------------------
--  Verificado contra la base real el 2026-09-15, ANTES de escribir nada:
--
--      cursos       5 filas   (la semilla de Fase 0)
--      sections     0 filas
--      enrollments  0 filas
--      aspirantes   0 filas
--
--  `sections` no tiene una sola fila NI un solo consumidor en el código: sólo
--  aparece en la migración que la creó. Por eso se rediseña completa en vez de
--  dejar media tabla que M3 tendría que volver a tocar. Si tuviera filas, esto
--  habría que hacerlo por partes.
--
--  `cursos` sí tiene filas, y se migran ANTES de soltar la tabla. Nada
--  referencia `cursos.id` (los aspirantes guardan el NOMBRE, en texto libre) y
--  `aspirantes` está vacía, así que no hay riesgo de romper una referencia.
--
--
--  LA DECISIÓN DE D12: VISTA, NO TABLA
--  -----------------------------------
--  `cursos` podría haberse borrado y haber cambiado Flutter para que leyera
--  `programs`. Se optó por la vista por una razón concreta: el único consumidor
--  (`SupabaseService.cursosDisponibles()`, que alimenta el desplegable del
--  formulario público de inscripción) sigue funcionando SIN TOCAR UNA LÍNEA, y
--  el modelo de datos queda correcto igual. Borrar la tabla habría dejado la app
--  rota entre esta migración y el cambio en Flutter.
--
--  La vista NO duplica datos: es una proyección. `programs` es la única fuente
--  de verdad desde este momento.
--
--  Contrapartida asumida: un nombre que fue tabla y ahora es vista confunde a
--  quien no lo sepa. Por eso lleva `comment on view` explicando qué es y cómo se
--  retira. Cuando Flutter lea `programs` directamente, se borra la vista con
--  `drop view public.cursos;` y esto queda cerrado del todo.
--
--
--  DEUDA NUEVA QUE ESTA MIGRACIÓN DEJA ANOTADA
--  -------------------------------------------
--  `aspirantes.curso_seleccionado` es TEXTO LIBRE con el nombre del curso. Eso
--  significa que renombrar un programa rompe la referencia de los aspirantes que
--  lo eligieron. La corrección real es una columna `program_id` con FK, y toca
--  el formulario público. No se hace aquí porque `aspirantes` está vacía (no hay
--  nada que migrar) y porque cambiar el formulario es trabajo de M1, no de M2.
--  Queda registrado como D14 en ESTADO_DEL_SISTEMA.md.
-- ============================================================================


-- ============================================================================
--  PARTE 1 — D12: `programs` absorbe `cursos`
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1.1 Migrar los 5 cursos de Fase 0 a `programs` como CURSO_LIBRE
-- ---------------------------------------------------------------------------
--  Se conserva el `id` original a propósito: nada lo referencia hoy, pero
--  conservarlo elimina una clase entera de preguntas del tipo "¿por qué
--  cambiaron los identificadores?" y mantiene válido cualquier listado o captura
--  histórica que cite un curso por id.
--
--  Idempotente por dos vías: si el nombre ya existe no se duplica, y si el
--  código ya está tomado tampoco. Eso importa porque un administrador pudo haber
--  creado 'Oratoria' a mano desde el asistente antes de que esto corriera.
insert into public.programs (id, code, name, type, requires_internship, is_active)
select c.id, v.code, c.nombre, 'CURSO_LIBRE', false, c.activo
from public.cursos c
join (values
  ('Herrería',                            'CUR-HER-01'),
  ('Higiene y Manipulación de Alimentos', 'CUR-HIG-01'),
  ('Estética (cejas y pestañas)',         'CUR-EST-01'),
  ('Oratoria',                            'CUR-ORA-01'),
  ('Curso Introductorio (15-16 años)',    'CUR-INT-01')
) as v(nombre, code) on v.nombre = c.nombre
where not exists (
  select 1 from public.programs p where p.name = c.nombre
)
on conflict do nothing;

comment on column public.programs.requires_internship is
  'Si es TRUE, M8 exige el aval del tutor industrial antes de declarar EGRESADO al estudiante. Los CURSO_LIBRE migrados de Fase 0 nacen en FALSE.';


-- ---------------------------------------------------------------------------
-- 1.2 `cursos` deja de ser tabla y pasa a ser vista de compatibilidad
-- ---------------------------------------------------------------------------
--  El orden importa: primero se migran los datos (1.1), sólo entonces se puede
--  soltar la tabla. Todo va en la misma transacción, así que no existe un
--  instante en el que los cursos vivan en los dos sitios ni en ninguno.
--
--  `security_invoker = true` es la pieza clave: hace que la RLS de `programs` se
--  evalúe con los permisos de QUIEN CONSULTA la vista, no con los del dueño. Sin
--  esto, la vista sería un agujero: `anon` vería todos los programas saltándose
--  `programs_read_activos`. Es el fallo clásico de las vistas en PostgreSQL.
--
--  Consecuencia del filtro `type = 'CURSO_LIBRE'` + la RLS de `programs`:
--    · anon          -> sólo cursos libres ACTIVOS (igual que antes)
--    · authenticated -> todos los cursos libres, activos o no
--  El segundo caso cambia respecto a `cursos_read_active`, que filtraba por
--  `activo` para todos. Es deliberado y es más correcto: un docente o un
--  administrador deben ver también lo que está en borrador. El único consumidor
--  real (`cursosDisponibles()`) consulta como `anon` desde el formulario
--  público, y esa ruta no cambia.
--
--  `cursos` puede estar en dos formas según de dónde venga la base: tabla (recién
--  migrada desde Fase 0) o vista (si este archivo se reaplicara). **Ni
--  `drop table if exists` ni `drop view if exists` sirven para las dos**: el
--  `if exists` perdona que el objeto no esté, no que sea del tipo equivocado
--  (`ERROR: "cursos" is not a view`). Por eso se mira `pg_class.relkind` y se
--  suelta lo que de verdad haya. Una migración destructiva tiene que poder
--  reaplicarse sin dejar la base en un estado raro.
do $$
declare
  v_tipo "char";
begin
  select c.relkind into v_tipo
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'cursos';

  if v_tipo = 'r' then
    execute 'drop table public.cursos';
  elsif v_tipo = 'v' then
    execute 'drop view public.cursos';
  end if;
end;
$$;

create view public.cursos
with (security_invoker = true)
as
select
  p.id,
  p.name       as nombre,
  p.is_active  as activo,
  p.created_at
from public.programs p
where p.type = 'CURSO_LIBRE';

comment on view public.cursos is
  'VISTA DE COMPATIBILIDAD, no una tabla. Proyecta los programas de tipo CURSO_LIBRE con los nombres de columna que tenía la tabla `cursos` de Fase 0, para no romper a sus consumidores mientras se migran. La fuente de verdad es `public.programs`. Se retira con `drop view public.cursos;` cuando `SupabaseService.cursosDisponibles()` lea `programs` directamente.';

-- Las vistas no heredan los privilegios por defecto de las tablas en `public`,
-- así que hay que conceder explícitamente. La RLS la sigue aplicando `programs`
-- gracias a `security_invoker`.
revoke all on public.cursos from anon, authenticated;
grant select on public.cursos to anon, authenticated;


-- ============================================================================
--  PARTE 2 — D13: `sections` rediseñada según el Módulo 3
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 2.1 Soltar el FK desde `enrollments`
-- ---------------------------------------------------------------------------
--  `enrollments.section_id` apunta a `sections(id)`. Hay que soltarlo antes de
--  recrear la tabla, y volver a crearlo después. `enrollments` tiene 0 filas,
--  así que no hay nada que reasignar.
alter table public.enrollments
  drop constraint if exists enrollments_section_id_fkey;


-- ---------------------------------------------------------------------------
-- 2.2 Recrear `sections` con el esquema del documento + `program_id`
-- ---------------------------------------------------------------------------
--  Se suelta y se recrea en vez de encadenar `rename column` + `add column` +
--  `drop column`: con la tabla vacía, una definición única y legible vale más
--  que un historial de parches que hay que reconstruir mentalmente. Sin
--  `cascade`, para que falle ruidosamente si algún día aparece una dependencia
--  inesperada en vez de arrastrarla en silencio.
drop table if exists public.sections;

create table public.sections (
  id           uuid        primary key default gen_random_uuid(),

  -- **La columna que el documento NO tiene y que hace falta.** La cabecera del
  -- cuadrante es `PERÍODO | ESPECIALIDAD | SECCIÓN`, y la especialidad es el
  -- programa. El documento sólo enlazaba `subject_id`, y como una materia puede
  -- pertenecer a varios programas (ese es el punto del M2M del pensum), la
  -- especialidad habría quedado ambigua. Además, sin esta columna la Regla 2 de
  -- M2 no se puede comprobar. Es D13.
  program_id   uuid        not null
                 references public.programs(id) on delete restrict,

  -- `on delete restrict` en las dos: una sección abierta es un compromiso con
  -- los alumnos matriculados. Ni la materia ni el programa se pueden borrar
  -- mientras exista.
  subject_id   uuid        not null
                 references public.subjects(id) on delete restrict,

  -- Lapso al que pertenece la sección (ej. '2026-1'). **Debe usar la MISMA
  -- convención que `system_settings.periodo_activo`**: la Regla 2 compara las
  -- dos cadenas y, si no coinciden, nunca dispara. Ver la nota al final del
  -- archivo.
  period_code  varchar(10) not null
                 check (btrim(period_code) <> ''),

  -- Identificador de la sección dentro del período (ej. 'SA', 'AS').
  name         varchar(5)  not null
                 check (btrim(name) <> ''),

  -- Hereda `cupo_maximo_por_seccion` del cPanel, editable por el administrador.
  max_capacity integer     not null default 0
                 check (max_capacity >= 0),

  is_active    boolean     not null default true,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- La misma materia no puede abrir dos secciones con el mismo nombre en el
  -- mismo período. Sí puede abrir tres con nombres distintos ('SA', 'SB', 'SC'),
  -- que es justo lo que el documento pide.
  constraint sections_identidad_unica unique (period_code, subject_id, name)
);

comment on table public.sections is
  'Secciones abiertas: el punto de encuentro entre la materia del pensum (M2) y el período académico vigente. Una materia puede abrirse varias veces en el mismo período con secciones independientes.';
comment on column public.sections.program_id is
  'Programa (especialidad) al que pertenece la sección. Añadido en D13: el documento sólo enlazaba la materia, y eso dejaba ambigua la especialidad cuando una materia está en varios pensums.';
comment on column public.sections.period_code is
  'Lapso de la sección. Debe usar la misma convención que system_settings.periodo_activo, porque la Regla 2 de M2 compara ambas cadenas.';

-- Devolver el FK a `enrollments`.
alter table public.enrollments
  add constraint enrollments_section_id_fkey
  foreign key (section_id) references public.sections(id) on delete cascade;


-- ---------------------------------------------------------------------------
-- 2.3 RLS, permisos y trigger de `sections`
-- ---------------------------------------------------------------------------
--  Al soltar la tabla se fueron con ella sus políticas, sus permisos y su
--  trigger de `updated_at`. Se recrean aquí, con las mismas reglas de antes.
alter table public.sections enable row level security;

drop policy if exists sections_read_active on public.sections;
create policy sections_read_active
on public.sections
for select
to anon, authenticated
using (is_active);

drop policy if exists sections_admin_all on public.sections;
create policy sections_admin_all
on public.sections
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Nada de DELETE: una sección se archiva con `is_active = false`. Borrarla se
-- llevaría por delante las matrículas en cascada, y una matrícula es un
-- compromiso con un alumno. Misma decisión que en `programs` y `subjects`.
revoke all on public.sections from anon, authenticated;
grant select                 on public.sections to anon;
grant select, insert, update on public.sections to authenticated;

drop trigger if exists sections_set_updated_at on public.sections;
create trigger sections_set_updated_at
before update on public.sections
for each row execute function public.set_updated_at();

-- El índice que necesita la Regla 2: "secciones activas de este programa en este
-- período". Parcial sobre `is_active` porque las archivadas no interesan y son
-- las que se acumulan con los años.
create index if not exists sections_programa_periodo_idx
  on public.sections (program_id, period_code)
  where is_active;

create index if not exists sections_subject_id_idx
  on public.sections (subject_id);


-- ============================================================================
--  PARTE 3 — Regla 2 de M2: el pensum de un programa en uso no se toca
-- ============================================================================
--  "El sistema bloqueará cualquier intento de modificar la estructura de un
--  Pensum (period_order o eliminación de materias) si ya existen secciones
--  físicas activas en el período académico vigente utilizando dicho programa.
--  De requerirse un cambio drástico, el administrador deberá clonar el programa
--  y generar una nueva versión de pensum."  — documento de arquitectura
--
--  Va en la base y no sólo en la API por la misma razón que `proteger_ultimo_admin`
--  (D8): la API sólo ve una parte del problema. Un `update` desde el editor SQL,
--  un script de mantenimiento o una migración futura no pasan por ella.
create or replace function public.proteger_pensum_en_uso()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo     text;
  v_origen      uuid;
  v_destino     uuid;
  v_bloqueantes integer;
begin
  select (ss.valor #>> '{}') into v_periodo
  from public.system_settings ss
  where ss.clave = 'periodo_activo';

  -- Sin período vigente declarado no hay nada que proteger. **Falla abierto a
  -- propósito**: es una guarda de integridad sobre una acción de administración,
  -- no una barrera de seguridad, y bloquear la edición del pensum porque falta
  -- un parámetro ocultaría el problema real. Es la misma decisión que el modo
  -- mantenimiento (ver D5 en ESTADO_DEL_SISTEMA.md).
  if v_periodo is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  -- Un UPDATE que reescribe los MISMOS valores no es un cambio de estructura.
  -- Sin esto, guardar el formulario sin tocar nada fallaría, que es la clase de
  -- comportamiento que hace que la gente desconfíe del sistema.
  if tg_op = 'UPDATE'
     and new.period_order is not distinct from old.period_order
     and new.program_id   is not distinct from old.program_id then
    return new;
  end if;

  -- Programas cuyo pensum cambia con esta operación.
  if tg_op = 'DELETE' then
    -- Borrar la materia de un programa siempre es estructural.
    v_origen  := old.program_id;
    v_destino := null;
  elsif new.program_id is distinct from old.program_id then
    -- Mover una materia de un pensum a otro cambia LOS DOS. Comprobar sólo el
    -- destino dejaría el agujero de vaciar un programa en uso por la puerta de
    -- atrás.
    v_origen  := old.program_id;
    v_destino := new.program_id;
  else
    -- Mismo programa: reordenar la materia dentro del pensum.
    v_origen  := new.program_id;
    v_destino := null;
  end if;

  select count(*)::int into v_bloqueantes
  from public.sections s
  where s.is_active
    and s.period_code = v_periodo
    and s.program_id in (v_origen, v_destino);

  if v_bloqueantes > 0 then
    -- 23514 -> el backend lo traduce a RESTRICCION_VIOLADA (400). El mensaje
    -- nombra el período y la salida: sin la salida, el administrador sólo sabe
    -- que no puede, no qué hacer.
    raise exception
      'No se puede modificar el pensum: el programa tiene % sección(es) activa(s) en el período %. Archive esas secciones primero, o clone el programa y cree una versión nueva del pensum.',
      v_bloqueantes, v_periodo
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

comment on function public.proteger_pensum_en_uso() is
  'Regla 2 de M2: no se cambia la estructura del pensum de un programa que ya tiene secciones activas en el período vigente. Obliga a clonar el programa y versionar el pensum.';

-- `UPDATE OF period_order, program_id` en vez de `UPDATE` a secas: acota el
-- disparo a las columnas que de verdad son estructura. El `OR DELETE` cubre la
-- eliminación de materias.
drop trigger if exists program_subjects_proteger_en_uso on public.program_subjects;
create trigger program_subjects_proteger_en_uso
before update of period_order, program_id or delete on public.program_subjects
for each row execute function public.proteger_pensum_en_uso();


-- ============================================================================
--  NOTA PARA EL TEG: una contradicción del documento que hay que decidir
-- ============================================================================
--  `system_settings.periodo_activo` vale hoy `"2026-1"`.
--  El documento de arquitectura escribe los períodos de sección como
--  `'SA25-5'` y `'SA26-2'`.
--
--  Son dos convenciones distintas para el mismo concepto, y la Regla 2 las
--  compara por igualdad exacta. Si se deja así, la regla **nunca dispara** y
--  el sistema dirá que todo está bien mientras permite reordenar el pensum de
--  una carrera en curso. Ese es el peor fallo posible: una guarda que no guarda
--  y no avisa.
--
--  Hay que elegir UNA y usarla en los dos sitios. Las dos opciones son válidas:
--    (a) `AAAA-N`  -> '2026-1'   (lo que ya está en `system_settings`)
--    (b) `SA AAAA-N` -> 'SA26-2' (lo que dice el documento, y lo que usa el
--                                 propio centro: el equipo cursa SA26-2)
--  Está anotado en REPORTE_ARIA.md. Mientras no se decida, la Regla 2 funciona
--  correctamente en cuanto alguien cree una sección con el `period_code` igual
--  al `periodo_activo`; el problema es de convención, no de código.
-- ============================================================================
