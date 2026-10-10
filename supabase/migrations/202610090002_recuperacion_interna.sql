-- ============================================================================
--  INCES LMS — Recuperación interna de contraseña (sin correo externo)
--  Archivo: 202610090002_recuperacion_interna.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El restablecimiento de contraseña dependía del correo (Resend), que devuelve
--  HTTP 401 sin dominio verificado. La decisión de producto es que recuperar una
--  cuenta **no dependa de un proveedor de correo**: un administrador autorizado
--  verifica la identidad por el procedimiento institucional, emite un **código
--  temporal de un solo uso**, y la persona lo canjea para fijar su propia
--  contraseña. El administrador nunca ve ni elige la contraseña.
--
--  DISEÑO
--  ------
--  * `code_hash` es el SHA-256 del código. En la base vive sólo la huella: un
--    volcado de la tabla no entrega códigos utilizables.
--  * `used_at` marca el canje (un solo uso). `revoked_at` permite anular un
--    código emitido por error o reemplazado por uno nuevo.
--  * `created_by` guarda qué administrador lo emitió: auditoría mínima, sin
--    registrar jamás la contraseña.
--  * Caducidad corta (30 minutos): el código se entrega en mano o por canal
--    interno, así que no necesita vivir 48 horas como la invitación.
--  * La contraseña NO se guarda aquí ni en ninguna tabla del proyecto: la fija
--    el backend contra el proveedor de identidad (Supabase Auth) y se olvida.
--
--  REVOCACIÓN DE SESIONES
--  ----------------------
--  Cambiar la contraseña no invalida por sí solo los refresh tokens ya emitidos.
--  Para que un cambio de contraseña cierre las sesiones abiertas se expone una
--  función `security definer` que borra las sesiones del usuario, replicando lo
--  que hace GoTrue en su propio `signOut`. Es la única pieza que toca el esquema
--  `auth`, y su EXECUTE queda **revocado de PUBLIC, anon y authenticated**: sólo
--  el backend con service_role puede invocarla. Si no se revocara, cualquier
--  usuario con sesión podría cerrar las sesiones de cualquier otro.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tabla: password_resets
-- ---------------------------------------------------------------------------
create table if not exists public.password_resets (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users (id) on delete cascade,
  code_hash   text        not null unique,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  used_at     timestamptz,
  revoked_at  timestamptz,

  -- Un código no puede haber caducado antes de emitirse.
  constraint password_resets_expira_despues check (expires_at > created_at)
);

comment on table public.password_resets is
  'Códigos temporales de un solo uso para restablecer contraseña. Se guarda el hash del código, nunca el código ni la contraseña.';
comment on column public.password_resets.code_hash is
  'SHA-256 del código de recuperación. El código en claro se muestra una sola vez al administrador.';
comment on column public.password_resets.created_by is
  'Perfil del administrador que emitió el código. Auditoría mínima; no se registra la contraseña.';
comment on column public.password_resets.used_at is
  'Instante del canje. Un código canjeado no se reutiliza.';
comment on column public.password_resets.revoked_at is
  'Instante de anulación. Emitir un código nuevo revoca los anteriores no usados.';


-- ---------------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------------
alter table public.password_resets enable row level security;

-- Sólo lectura para el administrador, para que el cPanel pueda auditar. **Sin
-- política de escritura**: el único camino de entrada es el backend con
-- service_role, que no está sujeto a RLS. Nadie puede insertar, modificar ni
-- borrar un código a mano desde el cliente.
drop policy if exists password_resets_admin_read on public.password_resets;
create policy password_resets_admin_read
on public.password_resets
for select
to authenticated
using (public.is_admin());


-- ---------------------------------------------------------------------------
-- 3. Permisos a nivel de tabla (defensa en profundidad)
-- ---------------------------------------------------------------------------
revoke all on public.password_resets from anon, authenticated;
grant select on public.password_resets to authenticated;

create index if not exists password_resets_user_idx
  on public.password_resets (user_id, created_at desc);


-- ---------------------------------------------------------------------------
-- 4. Revocación de sesiones del usuario (security definer, sólo service_role)
-- ---------------------------------------------------------------------------
-- Replica lo que GoTrue hace en su signOut: borrar la sesión del usuario. El
-- borrado de `auth.sessions` arrastra los `refresh_tokens` por la clave ajena;
-- el `update` sobre `refresh_tokens` es defensa en profundidad por si esa
-- cascada no existiera en esta versión de GoTrue.
create or replace function public.revocar_sesiones_usuario(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  borradas integer := 0;
begin
  if p_user_id is null then
    return 0;
  end if;

  -- Sólo actúa si el esquema de GoTrue está donde se espera. Si una versión
  -- futura moviera las tablas, la función no revienta: devuelve 0 y el llamante
  -- lo registra como limitación en vez de tumbar el restablecimiento.
  if to_regclass('auth.sessions') is not null then
    delete from auth.sessions where user_id = p_user_id;
    get diagnostics borradas = row_count;
  end if;

  if to_regclass('auth.refresh_tokens') is not null then
    update auth.refresh_tokens
       set revoked = true
     where user_id = p_user_id::text
       and revoked = false;
  end if;

  return borradas;
end;
$$;

comment on function public.revocar_sesiones_usuario(uuid) is
  'Cierra todas las sesiones de un usuario borrando sus filas de auth.sessions. Sólo service_role puede ejecutarla. Devuelve cuántas sesiones borró.';

-- **El orden importa.** PostgreSQL concede EXECUTE a PUBLIC por defecto al crear
-- una función; revocar sólo de anon/authenticated NO quitaría ese permiso
-- heredado. Hay que revocarlo de PUBLIC y concederlo explícitamente a
-- service_role, o cualquier usuario con sesión podría cerrar la sesión de otro.
revoke all on function public.revocar_sesiones_usuario(uuid) from public, anon, authenticated;
grant execute on function public.revocar_sesiones_usuario(uuid) to service_role;
