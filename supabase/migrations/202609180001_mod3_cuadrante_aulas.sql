-- ============================================================================
--  INCES LMS — Módulo 3: Cuadrante, Horarios, Aulas y Guardias Docentes
--  Archivo: 202609180001_mod3_cuadrante_aulas.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ AÑADE
--  ---------
--    · academic_periods  — los lapsos dejan de ser cadenas sueltas y pasan a
--                          ser un registro administrable.
--    · classrooms        — el registro físico de espacios del centro.
--    · teacher_duties    — guardias de custodia, lunes a sábado.
--    · schedule_slots    — el cuadrante: sección + docente + aula + día/bloque.
--    · vistas de lectura — el horario de cada rol, sin duplicar consultas.
--
--  Y resuelve R-12, R-13, R-14, R-15, R-16, R-17 y R-18 de REPORTE_ARIA.md.
--  Cada decisión está explicada donde se toma, no en un documento aparte.
--
--
--  ESTADO DE LA BASE ANTES DE ESTA MIGRACIÓN (medido el 2026-09-15)
--  ----------------------------------------------------------------
--      sections       0 filas      programs        5 filas
--      subjects       0 filas      enrollments     0 filas
--      profiles       2 filas      classrooms      (no existe)
--
--  Las cuatro tablas nacen vacías, así que no hay datos que migrar. Lo único
--  que ya existía y esta migración toca es:
--    · `sections.period_code`  -> se le añade una FK (0 filas, sin riesgo)
--    · `system_settings.periodo_activo` -> se le añade una guarda
--
--
--  POR QUÉ LA RLS ES LA BARRERA DE VERDAD (leer antes de tocar políticas)
--  --------------------------------------------------------------------
--  El backend NO usa la service_role para datos: usa el JWT del llamante
--  (`crearClienteDeUsuario` en `backend/src/infra/supabase.ts`), precisamente
--  para que Postgres aplique RLS aunque la API tuviera un fallo de autorización.
--  La service_role está reservada para verificar tokens y alimentar cachés.
--
--  Consecuencias que condicionan todo lo de abajo:
--    1. Las políticas de estas tablas SON el control de acceso. No hay una
--       segunda red debajo.
--    2. Las vistas de lectura van con `security_invoker = true`. Una vista
--       `security_definer` saltaría la RLS de las tablas base y un error en su
--       `where` dejaría el horario de todo el centro a la vista de un alumno.
--    3. El chequeo de colisiones SÍ tiene que saltarse la RLS — si no, sólo
--       vería las filas que el llamante puede leer y sería ciego justo cuando
--       más importa. Por eso `exigir_agenda_libre()` es `security definer`.
--       Es la única excepción, y está razonada en su sitio.
-- ============================================================================


-- ============================================================================
--  PARTE 0 — Utilidades de dominio
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0.1 `turno_de_bloque` — la única definición de «mañana» y «tarde»
-- ---------------------------------------------------------------------------
--  El requisito habla de «turnos mañana/tarde» para las guardias y de
--  «día/bloque horario» para el cuadrante. Si se guardaran como dos columnas
--  independientes, nada impediría un turno MAÑANA con bloque 9: un dato
--  incoherente que nadie ve hasta que el cuadrante se pinta mal.
--
--  Derivarlo en vez de almacenarlo elimina la posibilidad de contradicción. Y si
--  el centro mueve la frontera entre turnos, se cambia AQUÍ y las dos tablas
--  quedan coherentes solas.
--
--  `immutable` es obligatorio: PostgreSQL sólo admite expresiones inmutables en
--  una columna generada. La función no lee nada, así que lo es de verdad.
--
--  La frontera (1–6 mañana, 7–12 tarde) es PROVISIONAL: no se ha decidido en
--  coordinación. Cuando se decida, se cambia esta función y las columnas
--  generadas se recalculan. Ver R-16 en REPORTE_ARIA.md.
create or replace function public.turno_de_bloque(p_bloque smallint)
returns text
language sql
immutable
as $$
  select case when p_bloque <= 6 then 'MAÑANA' else 'TARDE' end;
$$;

comment on function public.turno_de_bloque(smallint) is
  'Turno (MAÑANA/TARDE) de un bloque horario. Única definición del corte entre turnos: `teacher_duties.turno` y `schedule_slots.turno` se derivan de aquí, así que no pueden contradecirse. El corte (1-6 / 7-12) es provisional.';


-- ---------------------------------------------------------------------------
-- 0.2 `dia_legible` — para mensajes de error y para la interfaz
-- ---------------------------------------------------------------------------
--  Los mensajes del trigger anti-colisión dicen «el lunes en el bloque 3», no
--  «el día 1». Un mensaje que el usuario tiene que traducir mentalmente es un
--  mensaje a medias. La interfaz reutiliza la misma función en vez de mantener
--  su propia lista de días, que se desincronizaría.
create or replace function public.dia_legible(p_dia smallint)
returns text
language sql
immutable
as $$
  select case p_dia
    when 1 then 'lunes'
    when 2 then 'martes'
    when 3 then 'miércoles'
    when 4 then 'jueves'
    when 5 then 'viernes'
    when 6 then 'sábado'
    else 'día ' || p_dia::text
  end;
$$;

comment on function public.dia_legible(smallint) is
  'Nombre del día a partir de `day_of_week` (ISO: 1 = lunes … 6 = sábado). Se usa en los mensajes del trigger anti-colisión y en las vistas de lectura.';


-- ============================================================================
--  PARTE 1 — `academic_periods`: los lapsos dejan de ser cadenas sueltas
-- ============================================================================
--  Hasta ahora el período era texto libre en dos sitios que se comparaban entre
--  sí: `sections.period_code` y `system_settings.periodo_activo`. La Regla 2 de
--  M2 los compara por igualdad exacta, así que una diferencia de formato
--  (¿'2026-1' o 'SA26-2'?) hacía que la guarda NO disparara nunca y no avisara.
--  Ese es R-06, y es el peor tipo de fallo: una guarda que no guarda.
--
--  Con un registro, esa divergencia deja de ser silenciosa: `period_code` pasa a
--  ser una FK y `periodo_activo` tiene que nombrar un período real. Escribir un
--  lapso que no existe ahora FALLA AL GUARDAR.
--
--  Lo que esto NO decide es la nomenclatura. El código sigue siendo una decisión
--  de coordinación del INCES; lo que cambia es que equivocarse se ve.
create table public.academic_periods (
  id         uuid        primary key default gen_random_uuid(),

  -- El código es la identidad visible del lapso ('2026-1', 'SA26-2', …) y es lo
  -- que citan las secciones y los documentos impresos. Por eso es `unique` y por
  -- eso la FK de `sections` apunta AQUÍ y no a `id`: el código es el contrato,
  -- el `id` es fontanería.
  --
  -- Se admiten mayúsculas y minúsculas en el `check` a propósito. La convención
  -- del centro es mayúsculas, pero rechazar una minúscula aquí bloquearía toda
  -- la migración por una diferencia cosmética en un dato que ya existía. Lo que
  -- de verdad importa —que no haya espacios ni basura y que esté registrado— sí
  -- se comprueba.
  code       varchar(10) not null unique
               check (code ~ '^[A-Za-z0-9][A-Za-z0-9-]{0,9}$'),

  -- Etiqueta para humanos. Existe porque el código está en disputa (R-06): así
  -- el administrador puede escribir «Lapso 2026-1 (SA26-2)» sin tener que
  -- cambiar el código que citan los documentos.
  name       text,

  -- ANULABLES A PROPÓSITO. El centro no ha cargado las fechas reales en ningún
  -- sitio del que se puedan leer, e inventarlas —«el lapso va de enero a
  -- junio»— sería fabricar dato institucional y presentarlo como cargado. Las
  -- completa el administrador desde el panel.
  start_date date,
  end_date   date,

  is_active  boolean     not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Sólo se comprueba el orden cuando AMBAS fechas están. Con una sola —o con
  -- ninguna— no hay nada que ordenar, y `end_date > start_date` con un NULL da
  -- NULL, que un `check` considera satisfecho. Se escribe explícito para que la
  -- intención quede legible.
  constraint academic_periods_fechas_coherentes
    check (
      end_date is null or start_date is null or end_date > start_date
    )
);

comment on table public.academic_periods is
  'Registro de lapsos académicos. Da identidad al período: `sections.period_code` es FK contra `code`, así que no se puede abrir una sección en un lapso inexistente. Convierte la divergencia silenciosa de R-06 en un error de guardado.';
comment on column public.academic_periods.code is
  'Código del lapso. Es la identidad que citan las secciones y los documentos, por eso es el destino de la FK. La convención (AAAA-N o SA AAAA-N) sigue pendiente de decisión de coordinación; ver R-06 y R-12 en REPORTE_ARIA.md.';
comment on column public.academic_periods.start_date is
  'Inicio del lapso. Anulable: el centro aún no ha cargado las fechas reales y no se inventan.';
comment on column public.academic_periods.is_active is
  'El lapso está operativo. NO es lo mismo que «vigente»: el vigente para la Regla 2 de M2 es `system_settings.periodo_activo`. Ver la nota de coherencia más abajo.';


-- ---------------------------------------------------------------------------
-- 1.1 Sembrar el período que ya está activo en producción
-- ---------------------------------------------------------------------------
--  Se lee de `system_settings` en vez de escribir '2026-1' a mano: así el valor
--  sembrado es, por construcción, el mismo que ya usa la Regla 2. Si mañana esa
--  base tiene otro lapso activo, esto sigue siendo correcto sin tocar el archivo.
--
--  Sin esta fila, la guarda de 1.3 rechazaría el `periodo_activo` existente y la
--  FK de 1.2 dejaría el sistema sin ningún lapso válido.
insert into public.academic_periods (code, name, is_active)
select
  v.code,
  'Lapso ' || v.code,
  true
from (
  select (ss.valor #>> '{}') as code
  from public.system_settings ss
  where ss.clave = 'periodo_activo'
) v
where v.code is not null
  and btrim(v.code) <> ''
  and not exists (
    select 1 from public.academic_periods ap where ap.code = v.code
  );


-- ---------------------------------------------------------------------------
-- 1.2 `sections.period_code` pasa a ser una FK
-- ---------------------------------------------------------------------------
--  `on delete restrict`: un lapso con secciones no se borra. Borrarlo se llevaría
--  por delante el cuadrante, las matrículas y las notas de un lapso entero. Se
--  archiva con `is_active = false`.
--
--  `sections` tiene 0 filas, así que la FK no puede fallar al crearse. Si algún
--  día esta migración se reaplicara sobre una base con secciones, fallaría
--  ruidosamente por una sección cuyo lapso no esté registrado — que es
--  exactamente lo que se quiere saber.
alter table public.sections
  drop constraint if exists sections_period_code_fkey;

alter table public.sections
  add constraint sections_period_code_fkey
  foreign key (period_code) references public.academic_periods(code)
  on delete restrict;

-- El planificador necesita este índice para la FK y para la Regla 2, que filtra
-- por período. El que ya existía es (program_id, period_code): sirve para la
-- Regla 2 pero no para «todas las secciones de este lapso».
create index if not exists sections_period_code_idx
  on public.sections (period_code);


-- ---------------------------------------------------------------------------
-- 1.3 Guarda: el período activo tiene que existir
-- ---------------------------------------------------------------------------
--  Esta es la pieza que cierra R-06 de verdad. La Regla 2 compara
--  `sections.period_code` con `periodo_activo`; si el segundo nombra un lapso
--  que no existe, la comparación nunca es verdadera y la regla **no protege
--  nada sin decir nada**. Con esta guarda, ese estado es inalcanzable.
--
--  `security definer`: se dispara al escribir en `system_settings`, que es
--  sólo-admin, pero lee `academic_periods`, que es de lectura general. Definir
--  la seguridad aquí evita depender de que quien escriba pueda leer el registro.
create or replace function public.exigir_periodo_registrado()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
begin
  if new.clave is distinct from 'periodo_activo' then
    return new;
  end if;

  v_code := new.valor #>> '{}';

  -- Sin valor no hay nada que comprobar. Se permite dejarlo vacío para poder
  -- desactivar el concepto sin tener que borrar la fila.
  if v_code is null or btrim(v_code) = '' then
    return new;
  end if;

  if not exists (
    select 1 from public.academic_periods ap where ap.code = v_code
  ) then
    -- 23514 -> el backend lo traduce a RESTRICCION_VIOLADA (400). El mensaje
    -- nombra el valor y la salida: sin la salida, el administrador sólo sabe
    -- que no puede, no qué hacer.
    raise exception
      'El período activo "%" no está registrado en el catálogo de lapsos. Créalo primero: la Regla 2 compara este valor con la sección y, si no corresponde a ningún lapso real, no protegería nada.',
      v_code
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.exigir_periodo_registrado() is
  'Impide que `system_settings.periodo_activo` nombre un lapso inexistente. Sin esta guarda, la Regla 2 de M2 dejaría de proteger en silencio (R-06).';

drop trigger if exists system_settings_periodo_registrado on public.system_settings;
create trigger system_settings_periodo_registrado
before insert or update of valor on public.system_settings
for each row execute function public.exigir_periodo_registrado();


-- ---------------------------------------------------------------------------
-- 1.4 RLS y permisos de `academic_periods`
-- ---------------------------------------------------------------------------
alter table public.academic_periods enable row level security;

-- Lectura general, incluso para `anon`: el formulario público de inscripción
-- necesita saber qué lapso está abierto, y un lapso no es información sensible.
drop policy if exists academic_periods_read on public.academic_periods;
create policy academic_periods_read
on public.academic_periods
for select
to anon, authenticated
using (true);

drop policy if exists academic_periods_admin_all on public.academic_periods;
create policy academic_periods_admin_all
on public.academic_periods
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Nada de DELETE: un lapso se archiva con `is_active = false`. Misma decisión
-- que en `programs`, `subjects` y `sections`.
revoke all on public.academic_periods from anon, authenticated;
grant select                 on public.academic_periods to anon;
grant select, insert, update on public.academic_periods to authenticated;

drop trigger if exists academic_periods_set_updated_at on public.academic_periods;
create trigger academic_periods_set_updated_at
before update on public.academic_periods
for each row execute function public.set_updated_at();


-- ============================================================================
--  PARTE 2 — `classrooms`: el registro físico de espacios
-- ============================================================================
--  Incluye talleres y zonas. Una zona (patio, pasillo, entrada) se registra como
--  una fila con `capacity = 0` e `is_workshop = false`, y su nombre lo dice.
--
--  Es deliberado tener UNA sola tabla de espacios: el trigger anti-colisión
--  comprueba «este espacio está ocupado». Con dos tablas de espacios habría que
--  comprobarlo en cuatro sitios en vez de dos, y bastaría olvidar uno para que
--  la guarda dejara de guardar. Ver R-18.
create table public.classrooms (
  id          uuid        primary key default gen_random_uuid(),

  -- Único: dos espacios con el mismo nombre son un error de captura que después
  -- hace imposible saber a cuál se refería el cuadrante.
  name        varchar(80) not null unique
                check (btrim(name) <> ''),

  -- 0 es válido y significa «sin cupo declarado» (una zona, un pasillo). No es
  -- lo mismo que «desconocido», que sería NULL; por eso es `not null default 0`.
  capacity    integer     not null default 0
                check (capacity >= 0),

  is_workshop boolean     not null default false,
  is_active   boolean     not null default true,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.classrooms is
  'Registro físico de espacios del centro: aulas, talleres y zonas. Una zona es una fila con capacity = 0 e is_workshop = false.';
comment on column public.classrooms.capacity is
  'Cupo del espacio. 0 = sin cupo declarado (zonas, pasillos), que no es lo mismo que desconocido.';

-- Sin semilla. El registro físico del CFS lo carga el centro: inventar nombres
-- de aulas sería fabricar dato institucional. Misma regla que con las fechas de
-- los lapsos (R-17).

alter table public.classrooms enable row level security;

-- Sin `anon`: los espacios internos no le incumben al formulario público.
drop policy if exists classrooms_read_authenticated on public.classrooms;
create policy classrooms_read_authenticated
on public.classrooms
for select
to authenticated
using (true);

drop policy if exists classrooms_admin_all on public.classrooms;
create policy classrooms_admin_all
on public.classrooms
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on public.classrooms from anon, authenticated;
grant select, insert, update on public.classrooms to authenticated;

drop trigger if exists classrooms_set_updated_at on public.classrooms;
create trigger classrooms_set_updated_at
before update on public.classrooms
for each row execute function public.set_updated_at();


-- ============================================================================
--  PARTE 3 — El chequeo de colisiones, compartido por las dos tablas
-- ============================================================================
--  El requisito es: «un docente o un aula NO pueden estar asignados a dos
--  clases/guardias distintas en el mismo bloque de tiempo». Léase con cuidado:
--  la colisión es ENTRE `schedule_slots` y `teacher_duties`, no sólo dentro de
--  cada tabla. Una restricción `unique` no puede abarcar dos tablas.
--
--  POR QUÉ NO HAY `unique` ADEMÁS DEL TRIGGER
--  ------------------------------------------
--  En `schedule_slots` el período NO es una columna: se deriva de
--  `sections.period_code`. Una `unique (teacher_id, day_of_week, block)` sería
--  INCORRECTA, porque impediría al mismo docente dar clase el mismo bloque en
--  dos lapsos distintos — que es legítimo: el cuadrante del lapso siguiente se
--  planifica mientras corre el actual.
--
--  Duplicar `period_code` en `schedule_slots` para poder poner la `unique`
--  crearía una segunda fuente de verdad que puede desviarse de la sección, que
--  es justo el antipatrón que este proyecto evita en todas partes.
--
--  Así que se cumple por un solo camino —el trigger— a cambio de un mensaje de
--  error único y coherente. La carrera entre dos inserciones simultáneas se
--  cubre con un cerrojo, no con la restricción.
--
--  POR QUÉ ES `security definer`
--  -----------------------------
--  El chequeo tiene que ver TODA la agenda. Con `security invoker`, la RLS
--  escondería al llamante las filas de los demás docentes y la comprobación
--  sería ciega precisamente cuando hay algo que detectar. Es la única función
--  de esta migración que se salta la RLS, y se salta para poder proteger.
--  No devuelve datos: sólo levanta o no levanta.
create or replace function public.exigir_agenda_libre(
  p_periodo text,
  p_dia     smallint,
  p_bloque  smallint,
  p_docente uuid,
  p_aula    uuid,
  p_origen  text,
  p_id      uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dia text;
begin
  v_dia := public.dia_legible(p_dia);

  -- Cerrojo por (período, día, bloque). Es el alcance exacto en el que dos
  -- escrituras pueden chocar: sin él, dos peticiones simultáneas leerían «libre»
  -- las dos y las dos insertarían. El cerrojo se libera al terminar la
  -- transacción, no hay que soltarlo a mano.
  perform pg_advisory_xact_lock(
    hashtext(p_periodo || '|' || p_dia::text || '|' || p_bloque::text)
  );

  -- --- ¿Está ocupado el docente? ------------------------------------------
  -- Se miran LAS DOS tablas: una guardia y una clase se excluyen mutuamente.
  if exists (
    select 1
    from public.teacher_duties td
    where td.is_active
      and td.period_code = p_periodo
      and td.day_of_week = p_dia
      and td.block       = p_bloque
      and td.teacher_id  = p_docente
      and not (p_origen = 'teacher_duties' and td.id = p_id)

    union all

    select 1
    from public.schedule_slots ss
    join public.sections s on s.id = ss.section_id
    where ss.is_active
      and s.period_code  = p_periodo
      and ss.day_of_week = p_dia
      and ss.block       = p_bloque
      and ss.teacher_id  = p_docente
      and not (p_origen = 'schedule_slots' and ss.id = p_id)
  ) then
    raise exception
      'Ese docente ya tiene una clase o guardia asignada el % en el bloque %. Un docente no puede estar en dos sitios a la vez.',
      v_dia, p_bloque
      using errcode = '23514';
  end if;

  -- --- ¿Está ocupado el espacio? ------------------------------------------
  if exists (
    select 1
    from public.teacher_duties td
    where td.is_active
      and td.period_code  = p_periodo
      and td.day_of_week  = p_dia
      and td.block        = p_bloque
      and td.classroom_id = p_aula
      and not (p_origen = 'teacher_duties' and td.id = p_id)

    union all

    select 1
    from public.schedule_slots ss
    join public.sections s on s.id = ss.section_id
    where ss.is_active
      and s.period_code   = p_periodo
      and ss.day_of_week  = p_dia
      and ss.block        = p_bloque
      and ss.classroom_id = p_aula
      and not (p_origen = 'schedule_slots' and ss.id = p_id)
  ) then
    raise exception
      'Ese espacio ya está ocupado el % en el bloque %. Dos grupos no pueden compartir el mismo sitio a la misma hora.',
      v_dia, p_bloque
      using errcode = '23514';
  end if;
end;
$$;

comment on function public.exigir_agenda_libre(text, smallint, smallint, uuid, uuid, text, uuid) is
  'Comprueba que un docente y un espacio estén libres en (período, día, bloque), mirando TANTO schedule_slots COMO teacher_duties. `security definer` a propósito: con la RLS del llamante sería ciega. Se serializa con pg_advisory_xact_lock para que dos inserciones simultáneas no pasen las dos.';

-- Es interna: se llama desde los triggers, no desde el cliente.
revoke all on function public.exigir_agenda_libre(text, smallint, smallint, uuid, uuid, text, uuid)
  from public, anon, authenticated;


-- ============================================================================
--  PARTE 4 — `teacher_duties`: guardias de custodia
-- ============================================================================
--  Independientes de si hay clase: una guardia existe para que haya un docente
--  presente en una zona aunque su grupo esté en otra actividad. Por eso son su
--  propia tabla y no un tipo de `schedule_slots`.
create table public.teacher_duties (
  id           uuid     primary key default gen_random_uuid(),

  -- `on delete cascade`: una guardia sin docente no significa nada. Bloquear el
  -- borrado de la cuenta dejaría cuentas imposibles de eliminar. Para «ya no
  -- trabaja aquí pero quiero conservar el histórico» está `profiles.active`.
  teacher_id   uuid     not null
                 references public.profiles(id) on delete cascade,

  -- `on delete restrict`: un espacio con guardias asignadas no se borra. Se
  -- archiva con `is_active = false`.
  classroom_id uuid     not null
                 references public.classrooms(id) on delete restrict,

  -- R-15: la guardia SÍ pertenece a un lapso. Sin período, una guardia del lunes
  -- bloque 1 chocaría con una clase del lunes bloque 1 de cualquier lapso,
  -- incluido uno futuro que todavía no ha empezado.
  period_code  varchar(10) not null
                 references public.academic_periods(code) on delete restrict,

  -- ISO: 1 = lunes … 6 = sábado. El domingo (7) queda fuera a propósito: el
  -- requisito dice de lunes a sábado.
  day_of_week  smallint not null check (day_of_week between 1 and 6),

  -- Bloque horario. 12 es un techo holgado para turnos de mañana y tarde.
  block        smallint not null check (block between 1 and 12),

  -- Derivado, no almacenado: así no puede contradecir al bloque (R-16).
  turno        text generated always as (public.turno_de_bloque(block)) stored,

  notes        text,

  -- Archivar en vez de borrar, como todo lo demás.
  is_active    boolean  not null default true,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.teacher_duties is
  'Guardias de custodia: qué docente cubre qué espacio, qué día y qué bloque. Independientes de que haya clase. La colisión con las clases la vigila `exigir_agenda_libre()`.';
comment on column public.teacher_duties.turno is
  'MAÑANA/TARDE derivado de `block`. Columna generada: no se puede insertar ni contradecir.';
comment on column public.teacher_duties.period_code is
  'Lapso de la guardia. Necesario para acotar la colisión: sin él, una guardia chocaría con clases de cualquier lapso. Ver R-15.';

-- ---------------------------------------------------------------------------
-- 4.1 Trigger anti-colisión
-- ---------------------------------------------------------------------------
create or replace function public.teacher_duties_exigir_agenda()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  -- Una guardia archivada no ocupa a nadie. Sin esta salida temprana, desactivar
  -- una guardia la seguiría bloqueando el hueco.
  if not new.is_active then
    return new;
  end if;

  perform public.exigir_agenda_libre(
    new.period_code,
    new.day_of_week,
    new.block,
    new.teacher_id,
    new.classroom_id,
    'teacher_duties',
    new.id
  );

  return new;
end;
$$;

comment on function public.teacher_duties_exigir_agenda() is
  'Trigger anti-colisión de las guardias. Delega en `exigir_agenda_libre()`, que mira también las clases.';

-- `before insert or update`: el chequeo corre antes de escribir, así que un
-- choque no deja rastro.
drop trigger if exists teacher_duties_exigir_agenda on public.teacher_duties;
create trigger teacher_duties_exigir_agenda
before insert or update on public.teacher_duties
for each row execute function public.teacher_duties_exigir_agenda();

-- ---------------------------------------------------------------------------
-- 4.2 RLS, permisos e índices
-- ---------------------------------------------------------------------------
alter table public.teacher_duties enable row level security;

-- El docente ve SUS guardias. No las de los demás: el requisito pide «su
-- horario», y publicar la agenda completa de la plantilla a cualquier docente
-- es más de lo que nadie pidió.
drop policy if exists teacher_duties_read_own on public.teacher_duties;
create policy teacher_duties_read_own
on public.teacher_duties
for select
to authenticated
using (teacher_id = auth.uid());

drop policy if exists teacher_duties_admin_all on public.teacher_duties;
create policy teacher_duties_admin_all
on public.teacher_duties
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Sin política para `estudiante`: las guardias no son información del alumno.
-- La ausencia de política es la denegación, no un olvido.
revoke all on public.teacher_duties from anon, authenticated;
grant select, insert, update on public.teacher_duties to authenticated;

drop trigger if exists teacher_duties_set_updated_at on public.teacher_duties;
create trigger teacher_duties_set_updated_at
before update on public.teacher_duties
for each row execute function public.set_updated_at();

-- El índice que usa el trigger: «¿quién está ocupado en este período, día y
-- bloque?». Va primero por período porque es el filtro más selectivo.
create index if not exists teacher_duties_periodo_dia_bloque_idx
  on public.teacher_duties (period_code, day_of_week, block)
  where is_active;

-- El que usa la vista del docente: «mis guardias».
create index if not exists teacher_duties_teacher_idx
  on public.teacher_duties (teacher_id, period_code);


-- ============================================================================
--  PARTE 5 — `schedule_slots`: el cuadrante
-- ============================================================================
create table public.schedule_slots (
  id           uuid     primary key default gen_random_uuid(),

  -- La sección ya implica programa, materia y período. No se duplica ninguno:
  -- el período de una clase se lee de su sección. Duplicarlo aquí crearía una
  -- segunda fuente de verdad que puede desviarse.
  section_id   uuid     not null
                 references public.sections(id) on delete cascade,

  teacher_id   uuid     not null
                 references public.profiles(id) on delete cascade,

  classroom_id uuid     not null
                 references public.classrooms(id) on delete restrict,

  day_of_week  smallint not null check (day_of_week between 1 and 6),
  block        smallint not null check (block between 1 and 12),

  turno        text generated always as (public.turno_de_bloque(block)) stored,

  is_active    boolean  not null default true,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.schedule_slots is
  'El cuadrante: una clase es sección + docente + aula + día/bloque. El período no se guarda aquí porque lo implica la sección. Las colisiones las vigila `exigir_agenda_libre()`.';
comment on column public.schedule_slots.section_id is
  'Sección que se dicta. De aquí se deriva el período (sections.period_code) para el chequeo de colisiones.';

-- ---------------------------------------------------------------------------
-- 5.1 Trigger anti-colisión
-- ---------------------------------------------------------------------------
create or replace function public.schedule_slots_exigir_agenda()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_periodo text;
begin
  if not new.is_active then
    return new;
  end if;

  -- El período no está en esta fila: se resuelve por la sección. Si la sección
  -- no existe, la FK lo habría impedido igualmente; se comprueba aquí para no
  -- llamar al chequeo con un período nulo, que lo dejaría ciego.
  select s.period_code into v_periodo
  from public.sections s
  where s.id = new.section_id;

  if v_periodo is null then
    raise exception 'La sección % no existe.', new.section_id
      using errcode = '23503';
  end if;

  perform public.exigir_agenda_libre(
    v_periodo,
    new.day_of_week,
    new.block,
    new.teacher_id,
    new.classroom_id,
    'schedule_slots',
    new.id
  );

  return new;
end;
$$;

comment on function public.schedule_slots_exigir_agenda() is
  'Trigger anti-colisión del cuadrante. Resuelve el período por la sección y delega en `exigir_agenda_libre()`, que mira también las guardias.';

drop trigger if exists schedule_slots_exigir_agenda on public.schedule_slots;
create trigger schedule_slots_exigir_agenda
before insert or update on public.schedule_slots
for each row execute function public.schedule_slots_exigir_agenda();

-- ---------------------------------------------------------------------------
-- 5.2 RLS, permisos e índices
-- ---------------------------------------------------------------------------
alter table public.schedule_slots enable row level security;

-- El docente ve sus clases.
drop policy if exists schedule_slots_read_docente on public.schedule_slots;
create policy schedule_slots_read_docente
on public.schedule_slots
for select
to authenticated
using (teacher_id = auth.uid());

-- El estudiante ve las clases de las secciones en las que está matriculado.
-- `enrollments` ya tiene su propia política (`enrollments_read_own`), así que el
-- `exists` sólo alcanza las matrículas propias aunque no se filtrara aquí; se
-- filtra igual para que la intención sea legible y no dependa de la otra tabla.
drop policy if exists schedule_slots_read_estudiante on public.schedule_slots;
create policy schedule_slots_read_estudiante
on public.schedule_slots
for select
to authenticated
using (
  exists (
    select 1
    from public.enrollments e
    where e.section_id = schedule_slots.section_id
      and e.student_id = auth.uid()
  )
);

drop policy if exists schedule_slots_admin_all on public.schedule_slots;
create policy schedule_slots_admin_all
on public.schedule_slots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on public.schedule_slots from anon, authenticated;
grant select, insert, update on public.schedule_slots to authenticated;

drop trigger if exists schedule_slots_set_updated_at on public.schedule_slots;
create trigger schedule_slots_set_updated_at
before update on public.schedule_slots
for each row execute function public.set_updated_at();

-- Los tres índices que usa el trigger y las vistas. El de día/bloque no filtra
-- por período porque el período vive en `sections`; el join lo aporta.
create index if not exists schedule_slots_dia_bloque_idx
  on public.schedule_slots (day_of_week, block)
  where is_active;

create index if not exists schedule_slots_teacher_idx
  on public.schedule_slots (teacher_id);

create index if not exists schedule_slots_section_idx
  on public.schedule_slots (section_id);

create index if not exists schedule_slots_classroom_idx
  on public.schedule_slots (classroom_id);


-- ============================================================================
--  PARTE 6 — `nombre_para_mostrar`: resolver el nombre del docente sin abrir `profiles`
-- ============================================================================
--  La política `profiles_read_own` limita `SELECT` a la fila propia. Una vista
--  con `security_invoker` que una `profiles` para poner el nombre del docente
--  devolvería NULL para cualquier alumno: el horario saldría sin profesor.
--
--  Las salidas malas están descartadas en R-14. La buena es una función
--  estrecha: devuelve SÓLO el nombre, y SÓLO de quien tiene rol docente o admin
--  y está activo. Ni cédula ni correo.
--
--  El nombre de un docente es información institucional pública; su cédula no.
create or replace function public.nombre_para_mostrar(p_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select nullif(btrim(p.nombres || ' ' || p.apellidos), '')
  from public.profiles p
  where p.id = p_id
    and p.active
    and p.rol in ('docente', 'admin');
$$;

comment on function public.nombre_para_mostrar(uuid) is
  'Nombre para mostrar de un docente o administrador activo. Devuelve NULL para cualquier otro rol y para cuentas inactivas. Existe porque `profiles_read_own` impide que un estudiante lea la fila del docente, y las vistas de horario necesitan su nombre. No expone cédula ni correo (R-14).';

revoke all on function public.nombre_para_mostrar(uuid) from public, anon;
grant execute on function public.nombre_para_mostrar(uuid) to authenticated;


-- ============================================================================
--  PARTE 7 — Vistas de lectura por rol
-- ============================================================================
--  Las tres van con `security_invoker = true`, así que la RLS de las tablas base
--  decide qué filas ve cada quien. Una sola vista sirve a los tres roles: el
--  admin ve todo el cuadrante, el docente sólo sus clases y el estudiante las de
--  sus secciones. Sin duplicar la consulta ni la lógica de acceso.
--
--  `security_invoker` es obligatorio aquí: una vista `security_definer` saltaría
--  la RLS y un error en su `where` dejaría el horario completo del centro a la
--  vista de un alumno.

-- ---------------------------------------------------------------------------
-- 7.1 El cuadrante de clases, con todos los nombres resueltos
-- ---------------------------------------------------------------------------
create or replace view public.v_cuadrante_clases
with (security_invoker = true)
as
select
  ss.id,
  s.period_code,
  s.program_id,
  p.code as program_code,
  p.name as program_name,
  s.subject_id,
  su.code as subject_code,
  su.name as subject_name,
  ss.section_id,
  s.name as section_name,
  ss.teacher_id,
  public.nombre_para_mostrar(ss.teacher_id) as teacher_name,
  ss.classroom_id,
  c.name as classroom_name,
  c.is_workshop,
  ss.day_of_week,
  public.dia_legible(ss.day_of_week) as day_name,
  ss.block,
  ss.turno,
  ss.is_active
from public.schedule_slots ss
join public.sections   s  on s.id  = ss.section_id
join public.programs   p  on p.id  = s.program_id
join public.subjects   su on su.id = s.subject_id
join public.classrooms c  on c.id  = ss.classroom_id;

comment on view public.v_cuadrante_clases is
  'El cuadrante con los nombres resueltos. `security_invoker`: la RLS de schedule_slots decide qué filas ve cada rol — el admin todo, el docente sus clases, el estudiante las de sus secciones.';

revoke all on public.v_cuadrante_clases from anon, authenticated;
grant select on public.v_cuadrante_clases to authenticated;


-- ---------------------------------------------------------------------------
-- 7.2 Las guardias, con nombres resueltos
-- ---------------------------------------------------------------------------
create or replace view public.v_cuadrante_guardias
with (security_invoker = true)
as
select
  td.id,
  td.period_code,
  td.teacher_id,
  public.nombre_para_mostrar(td.teacher_id) as teacher_name,
  td.classroom_id,
  c.name as classroom_name,
  c.is_workshop,
  td.day_of_week,
  public.dia_legible(td.day_of_week) as day_name,
  td.block,
  td.turno,
  td.notes,
  td.is_active
from public.teacher_duties td
join public.classrooms c on c.id = td.classroom_id;

comment on view public.v_cuadrante_guardias is
  'Las guardias con los nombres resueltos. `security_invoker`: el docente ve las suyas y el admin todas. Un estudiante no ve ninguna, porque no hay política que se lo permita.';

revoke all on public.v_cuadrante_guardias from anon, authenticated;
grant select on public.v_cuadrante_guardias to authenticated;


-- ---------------------------------------------------------------------------
-- 7.3 El lapso vigente, en un solo sitio
-- ---------------------------------------------------------------------------
--  `periodo_activo` vive en `system_settings` como clave-valor. Esta vista lo
--  cruza con el registro para que la interfaz y la API tengan una sola forma de
--  preguntar «¿cuál es el lapso vigente y qué fechas tiene?», en vez de leer el
--  JSON de un parámetro cada una por su cuenta.
create or replace view public.v_periodo_vigente
with (security_invoker = true)
as
select
  ap.id,
  ap.code,
  ap.name,
  ap.start_date,
  ap.end_date,
  ap.is_active
from public.academic_periods ap
where ap.code = (
  select ss.valor #>> '{}'
  from public.system_settings ss
  where ss.clave = 'periodo_activo'
);

comment on view public.v_periodo_vigente is
  'El lapso vigente (el que nombra system_settings.periodo_activo), con sus fechas. Si `periodo_activo` no nombrara un lapso registrado, la vista devuelve cero filas — y la guarda `exigir_periodo_registrado()` impide que ese estado exista.';

revoke all on public.v_periodo_vigente from anon, authenticated;
grant select on public.v_periodo_vigente to anon, authenticated;


-- ============================================================================
--  NOTA FINAL — la convención de período sigue sin decidirse
-- ============================================================================
--  Esta migración hace imposible que `periodo_activo` y `sections.period_code`
--  diverjan EN SILENCIO: una FK y una guarda lo convierten en un error de
--  guardado. Eso es un cambio real y es lo que pedía R-12.
--
--  Lo que NO hace es elegir la nomenclatura. Sigue pendiente si el centro
--  escribe '2026-1' (lo que hay hoy en producción) o 'SA26-2' (lo que dice el
--  documento y usa el equipo). Es una decisión de coordinación del INCES, no
--  una decisión técnica, y se toma renombrando o añadiendo una fila en
--  `academic_periods` — sin tocar una línea de código.
--
--  Ver R-06 y R-12 en REPORTE_ARIA.md.
-- ============================================================================
