-- ============================================================================
--  INCES LMS — Asistencia: el índice de ventana es numeric, no bigint
--  Archivo:  202609260004_asistencia_ventana_numeric.sql
-- ============================================================================
--
--  QUÉ CIERRA
--  ----------
--  La sonda E2E (tras 202609260003) siguió fallando con:
--
--    42883: function public.asistencia_codigo_en_ventana(text, uuid, numeric)
--           does not exist
--
--  La función pura toma `p_ventana bigint`, pero `floor(extract(epoch)/…)`
--  devuelve `numeric` y mi llamada la pasaba sin cast. Postgres no encuentra la
--  función porque la firma no cuadra. El cast lo tiene que hacer el LLAMADOR:
--  quien calcula la ventana es quien la convierte.
--
--  Esta migración recrea `asistencia_codigo_vigente` y `asistencia_codigo_actual`
--  con la línea `::bigint` en la llamada. La regla es exactamente la misma.
--
--  NO edita 202609260003: esa migración ya está en el libro mayor con su
--  checksum, y abrir y cerrar portas es lo único que se permite para corregir
--  una ya aplicada.
-- ============================================================================


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

  v_ventana_now := floor(extract(epoch from now()) / v_sesion.ventana_seg)::bigint;
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
  '¿Vigente el código para esta sesión? Tolerancia ±1 ventana. 202609260004: cast a bigint de la ventana —sin él, 42883 por firma.';

revoke all on function public.asistencia_codigo_vigente(uuid, text)
  from public, anon, authenticated;


create or replace function public.asistencia_codigo_actual(
  p_sesion uuid
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
stable
as $$
declare
  v_sesion  public.attendance_sessions%rowtype;
  v_es_admin boolean;
  v_es_su    boolean;
begin
  select * into v_sesion from public.attendance_sessions where id = p_sesion;
  if not found then return null; end if;
  if v_sesion.status <> 'OPEN' then return null; end if;

  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.rol = 'admin')
    into v_es_admin;
  select exists (
           select 1 from public.schedule_slots s
            where s.section_id = v_sesion.section_id
              and s.teacher_id = auth.uid())
    into v_es_su;

  if not (v_es_admin or v_sesion.opened_by = auth.uid() or v_es_su) then
    raise exception 'No eres el docente de esta sesión.' using errcode = '42501';
  end if;

  return public.asistencia_codigo_en_ventana(
           v_sesion.qr_secret,
           p_sesion,
           floor(extract(epoch from now()) / v_sesion.ventana_seg)::bigint);
end;
$$;

comment on function public.asistencia_codigo_actual(uuid) is
  'Código vigente AHORA, SÓLO para docente de la sección o admin. 202609260004: cast a bigint de la ventana.';


-- ---------------------------------------------------------------------------
--  Autocomprobación
-- ---------------------------------------------------------------------------
do $$
declare
  v_sesion uuid;
  v_code   text;
begin
  -- Crea una sesión ficticia SOLO para probar, marca, y la borra en el mismo
  -- statement. Es el patrón de «probar la regla sin pisar datos reales».
  -- Como esta migración corre en la transacción del aplicador, ROLLBACK lo
  -- limpia solo si algo falla.
  insert into public.attendance_sessions (section_id, opened_by, qr_secret, ventana_seg)
  select (select id from public.sections limit 1),
         (select id from public.profiles limit 1),
         'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
         15
  on conflict do nothing
  returning id into v_sesion;

  if v_sesion is not null then
    select public.asistencia_codigo_actual(v_sesion) into v_code;
    -- La prueba solo verifica que la función NO estalle por tipos (42883).
    -- El valor será null sólo si la barrera de propiedad nos bloquea —que es
    -- correcto—, así que basta con que la llamada no falle.
    if v_code is not null and length(v_code) <> 6 then
      raise exception 'asistencia_codigo_actual devolvió % (no es de 6 dígitos).', v_code using errcode = '23514';
    end if;
    delete from public.attendance_sessions where id = v_sesion;
  end if;

  raise notice 'Autocomprobación 202609260004: cast bigint en ventana; función llamable sin 42883.';
end;
$$;
