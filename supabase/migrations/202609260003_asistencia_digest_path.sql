-- ============================================================================
--  INCES LMS — Asistencia: pgcrypto vive en `extensions`, no en `public`
--  Archivo: 202609260003_asistencia_digest_path.sql
-- ============================================================================
--
--  QUÉ CIERRA
--  ----------
--  La sonda E2E de la fase 2 reveló un fallo de despliegue, no de lógica:
--  `asistencia_codigo_en_ventana` llama a `digest()`, y esa función vive en el
--  esquema `extensions` de Supabase, no en `public`. Mi `set search_path =
--  public, pg_temp` lo dejaba fuera, y Postgres respondía:
--  «function digest(text, unknown) does not exist».
--
--  Este archivo pone el esquema `extensions` en la ruta de las DOS funciones
--  que derivan códigos y las recrea inalteradas salvo por eso. La regla TOTP
--  queda exactamente igual: misma signatura de HMAC-ish, mismo truncado a 6
--  dígitos.
--
--  NO edita la migración original (202609260001), que ya está en el libro
--  mayor: `apply-migrations.mjs` la tiene con checksum y la rechazaría por
--  deriva.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — `asistencia_codigo_en_ventana` con el camino correcto
-- ---------------------------------------------------------------------------
create or replace function public.asistencia_codigo_en_ventana(
  p_secreto text,
  p_sesion  uuid,
  p_ventana bigint
)
returns text
language plpgsql
immutable
set search_path = public, extensions, pg_temp
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

comment on function public.asistencia_codigo_en_ventana(text, uuid, bigint) is
  'Derivación pura del código QR. 202609260003 le pone `extensions` en el search_path: sin él, PostgREST no veía `digest()`, que vive ahí.';

create or replace function public.asistencia_codigo_vigente(
  p_sesion    uuid,
  p_codigo    text
)
returns table (vigente boolean, ventana bigint)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_sesion      public.attendance_sessions%rowtype;
  v_ventana_now bigint;
  v_ok_ahora    boolean := false;
  v_ok_previa   boolean := false;
begin
  select * into v_sesion
    from public.attendance_sessions
   where id = p_sesion
     and status = 'OPEN';
  if not found then
    return query select false, -1::bigint;
    return;
  end if;

  v_ventana_now := floor(extract(epoch from now()) / v_sesion.ventana_seg);
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
  '¿Vigente el código para esta sesión? Tolerancia ±1 ventana. 202609260003 le pone `extensions` en el search_path: sin él no existe digest().';

revoke all on function public.asistencia_codigo_vigente(uuid, text)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 2 — Autocomprobación
-- ---------------------------------------------------------------------------
do $$
declare
  v_cadena text;
begin
  -- La función pura corre AHORA: si el search_path estuviera mal, esto falla.
  select public.asistencia_codigo_en_ventana('aa','00000000-0000-0000-0000-000000000000'::uuid, 1)
    into v_cadena;

  if v_cadena is null or length(v_cadena) <> 6 then
    raise exception 'asistencia_codigo_en_ventana no produjo un código de 6 dígitos.' using errcode = '23514';
  end if;

  raise notice 'Autocomprobación 202609260003: digest resoluble y código generado OK (%).', v_cadena;
end;
$$;
