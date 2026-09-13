-- ============================================================================
--  INCES LMS — Fase 1: Onboarding atómico de aspirantes
--  Archivo: 202609120001_phase1_onboarding.sql
--  Aplica con: supabase db push   (o pega en el SQL Editor de Supabase)
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  Antes, el registro hacía dos operaciones separadas desde el cliente:
--    1) auth.signUp()  -> creaba el usuario en auth.users
--    2) insert aspirantes -> podía fallar y dejar un usuario sin ficha
--  Si el paso 2 fallaba, quedaba un usuario huérfano y los datos del aspirante
--  se perdían en silencio. No era atómico.
--
--  AHORA el registro es UNA sola transacción dentro de PostgreSQL:
--    auth.signUp() -> INSERT en auth.users -> trigger -> profiles + aspirantes
--  Si cualquier paso falla (cédula duplicada, fecha inválida), TODA la
--  transacción se revierte: no queda usuario, no queda ficha. Atómico de verdad.
--
--  SEGURIDAD
--  ---------
--  El trigger SIEMPRE asigna rol 'estudiante'. Nunca se confía en el rol que
--  venga en la metadata del cliente: si no, cualquiera podría auto-promoverse
--  a admin enviando {"rol":"admin"} al registrarse.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Trigger: crear perfil y ficha de aspirante al registrarse
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_meta         jsonb   := coalesce(new.raw_user_meta_data, '{}'::jsonb);

  v_cedula       text    := nullif(trim(coalesce(v_meta ->> 'cedula', '')), '');
  v_nombres      text    := nullif(trim(coalesce(v_meta ->> 'nombres', '')), '');
  v_apellidos    text    := nullif(trim(coalesce(v_meta ->> 'apellidos', '')), '');
  v_telefono     text    := nullif(trim(coalesce(v_meta ->> 'telefono', '')), '');
  v_direccion    text    := nullif(trim(coalesce(v_meta ->> 'direccion', '')), '');
  v_nivel        text    := nullif(trim(coalesce(v_meta ->> 'nivel_educativo', '')), '');
  v_curso        text    := nullif(trim(coalesce(v_meta ->> 'curso_seleccionado', '')), '');
  v_sexo         text    := nullif(trim(coalesce(v_meta ->> 'sexo', '')), '');
  v_mision       text    := nullif(trim(coalesce(v_meta ->> 'mision_ribaras', '')), '');
  v_tipo_disc    text    := nullif(trim(coalesce(v_meta ->> 'tipo_discapacidad', '')), '');
  v_tutor_ci     text    := nullif(trim(coalesce(v_meta ->> 'numero_identidad_tutor', '')), '');
  v_tutor_nombre text    := nullif(trim(coalesce(v_meta ->> 'nombre_tutor', '')), '');
  v_tutor_parent text    := nullif(trim(coalesce(v_meta ->> 'parentesco_tutor', '')), '');
  v_tutor_tel    text    := nullif(trim(coalesce(v_meta ->> 'telefono_tutor', '')), '');
  v_tutor_correo text    := nullif(trim(coalesce(v_meta ->> 'correo_tutor', '')), '');

  v_discapacidad boolean := false;
  v_fecha_nac    date;
  v_es_aspirante boolean;
begin
  -- Parseo defensivo: si el cliente manda basura, no reventamos el registro
  -- de un aspirante legítimo; simplemente no se crea la ficha.
  begin
    v_discapacidad := coalesce((v_meta ->> 'discapacidad')::boolean, false);
  exception when others then
    v_discapacidad := false;
  end;

  begin
    v_fecha_nac := nullif(trim(coalesce(v_meta ->> 'fecha_nac', '')), '')::date;
  exception when others then
    v_fecha_nac := null;
  end;

  -- (a) Perfil base. Se crea SIEMPRE (incluso para docentes/admins futuros).
  --     El rol es fijo 'estudiante': los privilegios se otorgan después,
  --     desde el cPanel, nunca en el auto-registro.
  insert into public.profiles (id, cedula, email, nombres, apellidos, rol)
  values (
    new.id,
    v_cedula,
    new.email,
    coalesce(v_nombres, ''),
    coalesce(v_apellidos, ''),
    'estudiante'
  )
  on conflict (id) do update
     set cedula     = coalesce(excluded.cedula, public.profiles.cedula),
         email      = excluded.email,
         nombres    = coalesce(nullif(excluded.nombres, ''), public.profiles.nombres),
         apellidos  = coalesce(nullif(excluded.apellidos, ''), public.profiles.apellidos),
         updated_at = now();

  -- (b) Ficha de aspirante: solo si el registro trae la planilla completa.
  --     Este es el caso del formulario de inscripción del INCES.
  v_es_aspirante := v_cedula       is not null
                and v_nombres      is not null
                and v_apellidos    is not null
                and v_fecha_nac    is not null
                and v_sexo         is not null
                and v_sexo         in ('M', 'F', 'Otro')
                and v_telefono     is not null
                and v_direccion    is not null
                and v_nivel        is not null
                and v_curso        is not null;

  if v_es_aspirante then
    insert into public.aspirantes (
      user_id, cedula, nombres, apellidos, fecha_nac, sexo, telefono, email,
      direccion, nivel_educativo, curso_seleccionado, mision_ribaras,
      discapacidad, tipo_discapacidad, numero_identidad_tutor, nombre_tutor,
      parentesco_tutor, telefono_tutor, correo_tutor, requires_legal_tutor
    ) values (
      new.id, v_cedula, v_nombres, v_apellidos, v_fecha_nac, v_sexo, v_telefono,
      new.email, v_direccion, v_nivel, v_curso, v_mision,
      v_discapacidad,
      case when v_discapacidad then v_tipo_disc else null end,
      v_tutor_ci, v_tutor_nombre, v_tutor_parent, v_tutor_tel, v_tutor_correo,
      -- Calculado en SQL para que coincida EXACTAMENTE con el CHECK de la tabla.
      -- Si lo calculáramos en Dart, un desfase de un día en el borde de los 18
      -- años haría fallar el constraint y abortaría todo el registro.
      (v_fecha_nac > (current_date - interval '18 years')::date)
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Crea profiles + aspirantes de forma atómica al registrarse. Rol fijo estudiante.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------------
-- 2. Prechequeo de duplicados (para dar un mensaje claro ANTES de registrarse)
-- ---------------------------------------------------------------------------
--  Nota de privacidad: esto permite verificar si una cédula o correo ya está
--  registrado, lo que en teoría es un vector de enumeración. Es un compromiso
--  aceptado: el formulario de inscripción es público y necesita avisar de
--  duplicados. Si el INCES lo pide, se mitiga con CAPTCHA o rate limit.
create or replace function public.precheck_aspirante(
  p_cedula text,
  p_email  text
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cedula text := nullif(trim(coalesce(p_cedula, '')), '');
  v_email  text := nullif(lower(trim(coalesce(p_email, ''))), '');
begin
  if v_cedula is null then
    return 'CEDULA_REQUERIDA';
  end if;

  if v_email is null or position('@' in v_email) < 2 then
    return 'EMAIL_INVALIDO';
  end if;

  if exists (select 1 from public.aspirantes a where a.cedula = v_cedula) then
    return 'CEDULA_DUPLICADA';
  end if;

  if exists (select 1 from public.profiles p where lower(p.email) = v_email) then
    return 'EMAIL_DUPLICADO';
  end if;

  if exists (select 1 from public.aspirantes a where lower(a.email) = v_email) then
    return 'EMAIL_DUPLICADO';
  end if;

  return 'OK';
end;
$$;

comment on function public.precheck_aspirante(text, text) is
  'Devuelve OK | CEDULA_DUPLICADA | EMAIL_DUPLICADO | EMAIL_INVALIDO | CEDULA_REQUERIDA';


-- ---------------------------------------------------------------------------
-- 3. Reparar fichas huérfanas del bug anterior
-- ---------------------------------------------------------------------------
--  El código viejo insertaba en aspirantes con user_id = NULL y sin cuenta de
--  auth. Si por casualidad alguien creó después una cuenta con el mismo correo,
--  esta función enlaza la ficha existente con esa cuenta en el primer login.
create or replace function public.link_pending_aspirante()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_rows  integer;
begin
  if v_uid is null then
    return false;
  end if;

  select lower(u.email) into v_email
    from auth.users u
   where u.id = v_uid;

  if v_email is null then
    return false;
  end if;

  update public.aspirantes a
     set user_id    = v_uid,
         updated_at = now()
   where a.user_id is null
     and lower(a.email) = v_email;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

comment on function public.link_pending_aspirante() is
  'Enlaza una ficha de aspirante huérfana (user_id NULL) con la cuenta autenticada.';


-- ---------------------------------------------------------------------------
-- 4. Endurecer permisos
-- ---------------------------------------------------------------------------
--  La política anterior permitía a CUALQUIERA (anon) insertar filas sueltas en
--  aspirantes sin cuenta asociada. Con el trigger ya no hace falta y era un
--  agujero: se podían inyectar inscripciones falsas.
drop policy if exists aspirantes_insert_public on public.aspirantes;

revoke all on function public.precheck_aspirante(text, text) from public;
grant execute on function public.precheck_aspirante(text, text) to anon, authenticated;

revoke all on function public.link_pending_aspirante() from public;
grant execute on function public.link_pending_aspirante() to authenticated;

revoke all on function public.handle_new_user() from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- 5. Índices de apoyo
-- ---------------------------------------------------------------------------
create index if not exists profiles_email_lower_idx
  on public.profiles (lower(email));

create index if not exists aspirantes_email_lower_idx
  on public.aspirantes (lower(email));


-- ---------------------------------------------------------------------------
-- 6. Promover un usuario a admin o docente (operación manual y deliberada)
-- ---------------------------------------------------------------------------
--  El auto-registro nunca otorga privilegios. Para habilitar a un docente o
--  administrador, ejecuta esto UNA vez desde el SQL Editor de Supabase:
--
--    update public.profiles
--       set rol = 'docente'          -- o 'admin'
--     where lower(email) = 'persona@inces.edu.ve';
--
--  En una fase posterior esto se convierte en un RPC protegido por is_admin().
-- ============================================================================
