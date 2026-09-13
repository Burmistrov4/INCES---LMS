-- ============================================================================
--  Shim mínimo del entorno Supabase para validar migraciones en local.
--  Archivo: supabase/tests/supabase_shim.sql
-- ============================================================================
--
--  NO es parte del producto: no se aplica a la base de datos real. Existe sólo
--  para poder ejecutar las migraciones contra un PostgreSQL limpio (PGlite) y
--  comprobar que aplican y que las políticas RLS hacen lo que dicen.
--
--  Replica lo mínimo que Supabase aporta de fábrica y que las migraciones dan
--  por supuesto:
--    * esquema `auth` con `auth.users` y `auth.uid()`
--    * roles `anon`, `authenticated`, `service_role`
--    * privilegios por defecto sobre tablas y funciones nuevas en `public`
-- ============================================================================

create extension if not exists pgcrypto;

create schema if not exists auth;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now()
);

-- Equivalente al `auth.uid()` de Supabase: lee el `sub` del JWT que Supabase
-- inyecta en `request.jwt.claims`.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    coalesce(
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
      nullif(current_setting('request.jwt.claim.sub', true), '')
    ),
    ''
  )::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth   to anon, authenticated, service_role;

grant select on auth.users to authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- CLAVE: Supabase concede privilegios amplios por defecto a toda tabla y
-- función nuevas en `public`. Se emula aquí a propósito, porque es justo lo que
-- hace que las migraciones deban REVOCAR explícitamente lo que no corresponda.
-- Sin esto, el test de "la auditoría no se puede escribir" daría un falso verde.
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
