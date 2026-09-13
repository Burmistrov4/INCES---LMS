-- ============================================================================
--  INCES LMS — Módulo 1: Invitación de Docentes por Token
--  Archivo: 202609130001_invitaciones_docente.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El administrador del cPanel invita a un profesor introduciendo su correo.
--  El servidor genera un token de un solo uso, guarda SOLO su hash (nunca el
--  token en claro) y envía un enlace de activación. El profesor abre el enlace,
--  fija su contraseña y queda promovido a rol DOCENTE.
--
--  Dos tablas:
--
--    1) teacher_invitations  -> el token de invitación y su ciclo de vida.
--    2) auth_logs           -> traza de acceso (IP, instante, SUCCESS/FAILED),
--                               tal como lo exige el documento de arquitectura.
--
--  DISEÑO
--  ------
--  * `token_hash` es el SHA-256 del token: el token viaja por el enlace, pero en
--    la base sólo vive su huella. Un volcado de la tabla no filtra tokens válidos.
--  * `is_used` marca el consumo: un token usado no se puede reutilizar.
--  * `expires_at` caduca a las 48 horas exactas desde la generación.
--  * La promoción a DOCENTE NO vive aquí: la hace el endpoint de activación
--    actualizando `profiles.rol`, porque ese camino sí conoce la contraseña y el
--    usuario recién creado. Esta tabla sólo guarda la invitación.
--
--  CORTACIRCUITOS
--  --------------
--  El endpoint de activación valida a mano (regla pura en el backend) que el
--  token no esté usado y no haya caducado. La base de datos refuerza lo mismo
--  con un check, pero la regla de negocio vive en la API para poder dar mensajes
--  claros (INVITACION_YA_USADA / INVITACION_EXPIRADA) en vez de un error genérico.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tabla: teacher_invitations
-- ---------------------------------------------------------------------------
create table if not exists public.teacher_invitations (
  id          uuid        primary key default gen_random_uuid(),
  email       text        not null,
  token_hash  text        not null unique,
  is_used     boolean     not null default false,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,

  -- Una invitación no puede haber caducado antes de crearse. El endpoint fija
  -- expires_at = now() + 48h, pero el check evita un valor disparatado por error.
  constraint teacher_invitations_expira_despues
    check (expires_at > created_at)
);

comment on table public.teacher_invitations is
  'Invitaciones de docentes por token. Se guarda el hash del token, no el token.';
comment on column public.teacher_invitations.token_hash is
  'SHA-256 del token de un solo uso. El token en claro sólo viaja por el enlace.';
comment on column public.teacher_invitations.is_used is
  'Marca de consumo: un token usado no se reutiliza.';
comment on column public.teacher_invitations.expires_at is
  'Caduca a las 48 horas de la generación. Pasado este instante, la invitación no sirve.';


-- ---------------------------------------------------------------------------
-- 2. Tabla: auth_logs  (traza de acceso)
-- ---------------------------------------------------------------------------
create table if not exists public.auth_logs (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid,
  email       text,
  ip_address  text,
  estado      text        not null
                check (estado in ('SUCCESS', 'FAILED')),
  created_at  timestamptz not null default now()
);

comment on table public.auth_logs is
  'Registro de intentos de acceso (activación de invitaciones, login, etc.).';
comment on column public.auth_logs.estado is
  'SUCCESS o FAILED. No se usa un enum de Postgres para no atarnos al dialecto.';
comment on column public.auth_logs.ip_address is
  'Dirección IP del intento. text, no inet, para no complicar los clientes.';


-- ---------------------------------------------------------------------------
-- 3. RLS
-- ---------------------------------------------------------------------------
alter table public.teacher_invitations enable row level security;
alter table public.auth_logs           enable row level security;

-- --- teacher_invitations ----------------------------------------------------
-- Sólo el administrador (rol admin y activo) puede ver y crear invitaciones. El
-- servicio de activación usa la service_role key y por tanto ignora RLS, así que
-- esta política sólo cubre el camino del administrador.
drop policy if exists teacher_invitations_admin_all on public.teacher_invitations;
create policy teacher_invitations_admin_all
on public.teacher_invitations
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- --- auth_logs --------------------------------------------------------------
-- Sólo lectura para admin y SIN políticas de escritura: el único camino de
-- entrada es el backend con service_role (que no está sujeto a RLS). Nadie puede
-- insertar o borrar a mano una traza de acceso.
drop policy if exists auth_logs_admin_read on public.auth_logs;
create policy auth_logs_admin_read
on public.auth_logs
for select
to authenticated
using (public.is_admin());


-- ---------------------------------------------------------------------------
-- 4. Permisos a nivel de tabla (defensa en profundidad)
-- ---------------------------------------------------------------------------
--  Supabase concede privilegios por defecto sobre TABLA NUEVA en public a
--  anon/authenticated. Se revoca todo y se concede sólo lo necesario. La
--  service_role conserva sus privilegios por defecto y no se toca aquí.
revoke all on public.teacher_invitations from anon, authenticated;
revoke all on public.auth_logs           from anon, authenticated;

grant select, insert, update on public.teacher_invitations to authenticated;
grant select                 on public.auth_logs           to authenticated;

-- La política RLS invoca public.is_admin(); sin EXECUTE el rol authenticated
-- recibiría "permission denied for function is_admin" en vez de filas filtradas.
grant execute on function public.is_admin() to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Índices de apoyo
-- ---------------------------------------------------------------------------
create index if not exists teacher_invitations_token_hash_idx
  on public.teacher_invitations (token_hash);

create index if not exists teacher_invitations_email_idx
  on public.teacher_invitations (email);

create index if not exists auth_logs_created_at_idx
  on public.auth_logs (created_at desc);
