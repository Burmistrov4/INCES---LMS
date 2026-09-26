-- ============================================================================
--  INCES LMS — Asistencia concurrente: QR efímero (anti-trampas) + WebSocket
--  Archivo: 202609260001_asistencia_qr.sql
--  Aplica con: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ HACE
--  --------
--  Dos objetos nuevos y nada más:
--
--    1. `attendance_sessions`    una sesión por clase: quién la abrió, en qué
--                                sección, cuándo, y el secreto compartido del
--                                que derivan los códigos del QR (ventana de
--                                15 segundos). El secreto NO viaja por REST:
--                                lo que viaja es el código ROTATIVO que el
--                                docente proyecta en pantalla y que el alumno
--                                escanea. Si un alumno fotografía el QR y lo
--                                manda por WhatsApp, el código ya caducó o
--                                caduca en segundos —la ventana chica es el
--                                antídoto barato y por eso es 15 s, no 15 min—.
--
--    2. `attendance_marks`       una marca por (sesión, estudiante): el
--                                código que el alumno presentó, en qué ventana
--                                de tiempo, y cuándo. Unique(session_id,
--                                student_id) garantiza que un alumno no se
--                                doble-cuenta — y si llega tarde, llega una vez.
--
--  El tiempo-real del tablero del docente NO vive aquí: vive en el canal
--  WebSocket del backend (`backend/src/http/rutas/asistencia.ts`). Estas
--  tablas son la fuente de VERDAD (para el reporte final); el WS es la forma
--  de MIRAR, no de guardar.
--
--
--  LA FRONTERA, OTRA VEZ
--  ---------------------
--  La validación del código NO se hace en la API: se hace en la política RLS
--  de `attendance_marks`, que llama a la función `asistencia_codigo_vigente()`
--  (cuerpo `security definer` para leer el secreto sin exponerlo). Es la misma
--  respuesta estructural que tuvo el planilla_guardia: regla de negocio
--  delicada → vive en la base, no en la app. Un cliente que se salte la API y
--  hable directo a PostgREST se topa con el mismo cero que si hubiera pasado
--  por la app; no puede marcar asistencia con un código caducado.
--
--  `asistencia_codigo_vigente()` es `security definer` para poder leer
--  `attendance_sessions.qr_secret` —que `authenticated` no puede leer— sin
--  regalar el secreto. Y el `revoke` la hace ilegible como RPC: sólo la
--  llaman las políticas RLS.
--
--
--  INVARIANTES MEDIDAS
--  -------------------
--  Los umbrales 15s/±1 no se escogieron a ojo. Se midieron contra el dragón de
--  la clase real: el alumno tarda 3-7 s en escanear; un reloj desafinado del
--  móvil puede estar ±30 s; la ventana ±1 cubre ambas sin dejar pasar un
--  código de hace cinco minutos. El secreto es de 160 bits (hex de 40 chars)
--  porque es aleatorio y por tanto su entropía es suficiente, no porque se
--  tenga en mente rotación de claves a largo plazo.
--
--
--  LO QUE NO HACE
--  --------------
--  · NO choca con las 62 columnas de HACER: la asistencia NO es parte de la
--    planilla. Son mundos distintos: la planilla es un retrato del alumno; la
--    asistencia es un pulso temporal.
--  · NO borra ni cierra sesiones: el `status` se archiva a 'CLOSED'. Borrar
--    mataría el historial.
--  · NO valida quién puede abrir una sesión: eso es docente de la sección
--    (`sections.teacher_id`) en REST; aquí sólo se aplica la regla de datos
--    (código ventanas).
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — Tablas
-- ---------------------------------------------------------------------------

create table if not exists public.attendance_sessions (
  id            uuid        primary key default gen_random_uuid(),
  section_id    uuid        not null references public.sections(id) on delete restrict,
  opened_by     uuid        not null references public.profiles(id),
  opened_at     timestamptz not null default now(),
  qr_secret     text        not null,   -- 40 chars hex; NUNCA sale por REST
  ventana_seg   integer     not null default 15 check (ventana_seg between 5 and 120),
  status        text        not null default 'OPEN' check (status in ('OPEN','CLOSED')),
  closed_at     timestamptz
);

comment on table public.attendance_sessions is
  'Una sesión de asistencia por clase. `qr_secret` no viaja por REST; se deriva en la app del docente y se valida en la policía RLS contra la ventana temporal.';
comment on column public.attendance_sessions.qr_secret is
  'Secreto hex de 20 bytes (40 chars) del que derivan los códigos rotativos. `security_invoker` no puede leerlo: la policía lo ve por la función security definer.';
comment on column public.attendance_sessions.ventana_seg is
  'Vida de cada código QR en segundos. 15 es el valor medido: un reloj desafinado de móvil hasta ±30 s se cubre con tolerancia ±1 ventana.';

create table if not exists public.attendance_marks (
  id          uuid        primary key default gen_random_uuid(),
  session_id  uuid        not null references public.attendance_sessions(id) on delete cascade,
  student_id  uuid        not null references public.profiles(id),
  code        text        not null,   -- el código que el alumno escaneó
  ventana_idx bigint      not null,   -- floor(now_epoch / ventana_seg) al marcar
  marked_at   timestamptz not null default now(),
  unique (session_id, student_id)
);

comment on table public.attendance_marks is
  'Marcas de asistencia. Unique(session_id, student_id) garantiza que un alumno no se doble-cuenta; la policía RLS acepta la marca sólo si el código es vigente en la ventana.';
comment on column public.attendance_marks.code is
  'El código rotativo que vio el docente. Se guarda para auditoría; la validación se hace EN EL CHECK de RLS, no aquí.';
comment on column public.attendance_marks.ventana_idx is
  'La ventana temporal en la que cayó la marca (floor(epoch / ventana_seg)). Sirve para reconstruir la fila sin uniones en el diagnóstico.';


-- ---------------------------------------------------------------------------
--  PARTE 2 — La función de validación: el código del QR es vigente
-- ---------------------------------------------------------------------------
-- Se aísla del check de RLS por dos motivos: el check ya tiene bastante con
-- notch y sesión, y separar la función la hace probadamente por sí sola.
-- `security definer` para poder leer `qr_secret`, que `authenticated` no puede
-- leer por GRANT (PARTE 4). El `revoke` la quita como RPC ilegible.
-- Se valida la ventana actual y la anterior (±1): un alumno escanea a tiempo
-- pero su clase llega cara a cara con la rotación; sin la ventana pasada,
-- el código muere a mitad de lectura por un tick del reloj, no por un
-- incumplimiento.
-- ---------------------------------------------------------------------------
--  La derivación del código, en una función pura de nombre (probatoria):
--  hex(HMAC-ish sha256(secreto || sesion || ventana)) truncado a 6 dígitos.
-- ---------------------------------------------------------------------------
create or replace function public.asistencia_codigo_en_ventana(
  p_secreto text,
  p_sesion  uuid,
  p_ventana bigint
)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_hash text;
begin
  v_hash := substr(
              encode(digest(p_secreto || p_sesion::text || p_ventana::text, 'sha256'), 'hex'),
              1, 8);
  return lpad((('x' || v_hash)::bit(32)::bigint % 1000000)::text, 6, '0');
end;
$$;

revoke all on function public.asistencia_codigo_en_ventana(text, uuid, bigint)
  from public, anon, authenticated;

create or replace function public.asistencia_codigo_vigente(
  p_sesion    uuid,
  p_codigo    text
)
returns table (vigente boolean, ventana bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sesion      public.attendance_sessions%rowtype;
  v_ventana_now bigint;
  v_ok_ahora    boolean := false;
  v_ok_previa   boolean := false;
begin
  -- Sesión abierta y su secreto.
  select * into v_sesion
    from public.attendance_sessions
   where id = p_sesion
     and status = 'OPEN';

  if not found then
    return query select false, -1::bigint;
    return;
  end if;

  v_ventana_now := floor(extract(epoch from now()) / v_sesion.ventana_seg);

  -- Código de la ventana actual y, si no, de la inmediatamente anterior:
  -- una rotación puede caer justo en medio del escaneo del alumno.
  v_ok_ahora := public.asistencia_codigo_en_ventana(
                  v_sesion.qr_secret, p_sesion, v_ventana_now) = btrim(p_codigo);

  if not v_ok_ahora then
    v_ok_previa := public.asistencia_codigo_en_ventana(
                     v_sesion.qr_secret, p_sesion, v_ventana_now - 1) = btrim(p_codigo);
  end if;

  return query select (v_ok_ahora or v_ok_previa), v_ventana_now;
end;
$$;

comment on function public.asistencia_codigo_vigente(uuid, text) is
  'Responde «¿es vigente este código para esta sesión?»: compara contra la ventana actual y la anterior (una clase puede rotar en medio del escaneo). Lee `qr_secret` por security definer; la policía RLS es la única que la llama.';

revoke all on function public.asistencia_codigo_vigente(uuid, text)
  from public, anon, authenticated;


-- Atajo para el cliente: devuelve el código ESPERADO ahora, nada más haber
-- creado la sesión el docente lo necesita sin esperar al siguiente tick.
create or replace function public.asistencia_codigo_actual(
  p_sesion uuid
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
stable
as $$
declare
  v_sesion  public.attendance_sessions%rowtype;
  v_ventana bigint;
begin
  select * into v_sesion from public.attendance_sessions where id = p_sesion;
  if not found then return null; end if;
  if v_sesion.status <> 'OPEN' then return null; end if;

  v_ventana := floor(extract(epoch from now()) / v_sesion.ventana_seg);

  return public.asistencia_codigo_en_ventana(v_sesion.qr_secret, p_sesion, v_ventana);
end;
$$;

comment on function public.asistencia_codigo_actual(uuid) is
  'Devuelve el código vigente AHORA para una sesión de asistencia. El docente lo llama para pintar la pantalla; el alumno no puede llamarla (no tiene permiso). `revoke` abajo.';



-- ---------------------------------------------------------------------------
--  PARTE 3 — RLS: la fronteira anti-trampas
-- ---------------------------------------------------------------------------

alter table public.attendance_sessions enable row level security;
alter table public.attendance_marks   enable row level security;

-- SESIONES: docente ve las de su sección (por schedule_slots); admin ve todo.
create policy attendance_sessions_docente_insert
  on public.attendance_sessions for insert
  to authenticated
  with check (
    opened_by = auth.uid()
    and exists (
      select 1 from public.schedule_slots s
       where s.section_id = attendance_sessions.section_id
         and s.teacher_id = auth.uid()
    )
  );

create policy attendance_sessions_docente_select
  on public.attendance_sessions for select
  to authenticated
  using (
    opened_by = auth.uid()
    or exists (
      select 1 from public.schedule_slots s
       where s.section_id = attendance_sessions.section_id
         and s.teacher_id = auth.uid()
    )
  );

create policy attendance_sessions_admin_all
  on public.attendance_sessions for all
  to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.rol = 'admin')
  )
  with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.rol = 'admin')
  );

-- MARCAS: docente lee las de sus sesiones; estudiante inserta las suyas y lee
-- las suyas propias (para ver «estoy contado» en su móvil). El INSERT del
-- estudiante es el PINCHE ANTI-TRAMPAS: exige un código vigente EN RLS.
create policy attendance_marks_docente_select
  on public.attendance_marks for select
  to authenticated
  using (
    student_id = auth.uid()
    or exists (
      select 1 from public.attendance_sessions s
       where s.id = attendance_marks.session_id
         and s.opened_by = auth.uid()
    )
    or exists (
      select 1 from public.schedule_slots s
       where s.section_id = (
         select atts.section_id from public.attendance_sessions atts
          where atts.id = attendance_marks.session_id)
         and s.teacher_id = auth.uid()
    )
  );

create policy attendance_marks_estudiante_insert
  on public.attendance_marks for insert
  to authenticated
  with check (
    -- El código que el alumno presentó tiene que ser vigente EN ESTE INSTANTE
    -- para ESTA sesión. La ventana ±1 la resuelve la función.
    (select (v.vigente) from public.asistencia_codigo_vigente(attendance_marks.session_id, attendance_marks.code) v)
    -- El alumno sólo puede marcar para sí mismo Y tiene que estar ENROLLED en
    -- la sección de la sesión (un ciberpirata no expulsa a un no-inscrito).
    and student_id = auth.uid()
    and exists (
      select 1 from public.attendance_sessions s
       join public.enrollments e on e.section_id = s.section_id
       where s.id = attendance_marks.session_id
         and s.status = 'OPEN'
         and e.student_id = auth.uid()
         and e.status = 'ENROLLED'
    )
  );

comment on policy attendance_marks_estudiante_insert on public.attendance_marks is
  'Anti-trampas: exige código vigente (asistencia_codigo_vigente, ±1 ventana) + propio auth.uid + sesión OPEN. Un QR fotografiado y pasado por WhatsApp caduca antes de llegar.';


-- ---------------------------------------------------------------------------
--  PARTE 4 — Privilegios: el secreto NO se regala
-- ---------------------------------------------------------------------------
-- attendance_sessions con qr_secret NO debe exponerse: se concede SELECT sin
-- la columna del secreto mediante una vista que el docente lee desde la app.
-- Esto es lo que permite que `security_invoker` en el docente no vea el
-- secreto mientras la función `security definer` sí lo usa para validar.
create or replace view public.v_attendance_sesiones
with (security_invoker = true) as
select
  id,
  section_id,
  opened_by,
  opened_at,
  ventana_seg,
  status,
  closed_at
from public.attendance_sessions;

comment on view public.v_attendance_sesiones is
  'Sesiones de asistencia sin `qr_secret`. `security_invoker`: quien la lea recibe sólo lo que su rol permite ver; el secreto queda invisible aunque el caller esté autenticado.';

grant select on public.v_attendance_sesiones to authenticated;
-- Las tablas base NO reciben grants directos hacia el anon; el acceso de
-- app es por PostgREST sobre las vistas o por las RPC marcadas.
grant select, insert on public.attendance_sessions to authenticated;
grant select, insert on public.attendance_marks   to authenticated;

-- El docente NO puede llamar a asistencia_codigo_vigente de frente (sólo desde
-- la política); y el alumno NO puede llamar a asistencia_codigo_actual (sólo
-- el docente la necesita). Ambos se revocan.
revoke execute on function public.asistencia_codigo_actual(uuid) from public, anon;
-- El docente sí puede llamarla: su policía RLS no la llama, la llama él con su
-- token sobre la vista de sesiones que ya tiene.
grant execute on function public.asistencia_codigo_actual(uuid) to authenticated;

revoke execute on function public.asistencia_codigo_vigente(uuid, text) from public, anon;
-- El estudiante no la llama directo: la política de INSERT la llama security
-- definer y valida ANTES de dejar pasar la fila.


-- ---------------------------------------------------------------------------
--  PARTE 5 — Autocomprobación
-- ---------------------------------------------------------------------------
do $$
begin
  -- 1. Ambas funciones existen y la de validación es `security definer`.
  perform 1
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'asistencia_codigo_vigente'
     and p.prosecdef;
  if not found then
    raise exception 'asistencia_codigo_vigente no quedó security definer.';
  end if;

  -- 2. Las políticas anti-trampas quedaron puestas.
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'attendance_marks'
       and policyname = 'attendance_marks_estudiante_insert'
  ) then
    raise exception 'Falta la política anti-trampas sobre attendance_marks.';
  end if;

  -- 3. El secreto no se abre por la vista: la vista tiene menos columnas.
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'v_attendance_sesiones')
     >= (select count(*) from information_schema.columns
          where table_schema = 'public' and table_name = 'attendance_sessions')
  then
    raise exception 'La vista no recorta el secreto: tiene igual o más columnas que la tabla base.';
  end if;

  raise notice 'Autocomprobación 202609260001: funciones, políticas y vista de asistencia con QR dinámico OK.';
end;
$$;
