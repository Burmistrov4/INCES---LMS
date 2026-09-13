-- ============================================================================
--  INCES LMS — Fase 3: Núcleo del Administrador Maestro (cPanel)
--  Archivo: 202609120002_phase3_admin_core.sql
--  Aplica con: supabase db push   (o pega en el SQL Editor de Supabase)
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El "Poder Absoluto del Administrador Maestro" necesita tres cosas en la
--  base de datos, no sólo en la UI:
--
--    1) system_modules   -> qué módulos existen y cuáles están encendidos.
--    2) system_settings  -> parámetros operativos editables sin desplegar.
--    3) config_audit_log -> quién cambió qué y cuándo (append-only).
--
--  Sin (3) el poder del administrador sería un agujero negro: apagar el módulo
--  de asistencia el día del cierre de notas sería indetectable. La auditoría se
--  escribe por TRIGGER, no por el cliente: así no se puede omitir ni falsificar
--  desde la app, ni siquiera con la clave anónima.
--
--  DISEÑO
--  ------
--  * `system_modules.clave` es la clave estable que referencian la API y el
--    frontend (`m1_onboarding`, `m4_inscripciones`, ...). No se renombra.
--  * `roles_permitidos` vacío = todos los roles. Con valores = lista blanca.
--  * `system_settings.valor` es jsonb y va acompañado de `tipo`, para que la UI
--    sepa qué control pintar sin adivinar.
--  * `config_audit_log` es append-only: RLS sin política de INSERT/UPDATE/
--    DELETE, de modo que sólo el trigger (security definer) puede escribir.
--
--  CORTACIRCUITOS
--  --------------
--  `m0_cpanel` es el módulo que da acceso a este mismo panel. Si se pudiera
--  apagar o borrar, el administrador se dejaría fuera del sistema sin vuelta
--  atrás. Un trigger lo impide a nivel de base de datos.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Tabla: system_modules
-- ---------------------------------------------------------------------------
create table if not exists public.system_modules (
  clave            text        primary key,
  nombre           text        not null,
  descripcion      text,
  habilitado       boolean     not null default false,
  orden            integer     not null default 0,
  icono            text,
  roles_permitidos text[]      not null default '{}'::text[],
  categoria        text        not null default 'general',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint system_modules_clave_formato
    check (clave ~ '^[a-z][a-z0-9_]*$'),

  -- Evita que un typo deje un rol fuera de la lista blanca en silencio.
  constraint system_modules_roles_validos
    check (roles_permitidos <@ array['admin', 'docente', 'estudiante']::text[])
);

comment on table public.system_modules is
  'Módulos funcionales del sistema. `habilitado` es el interruptor maestro.';
comment on column public.system_modules.roles_permitidos is
  'Lista blanca de roles. Array vacío = visible para todos los roles.';
comment on column public.system_modules.clave is
  'Identificador estable (m1_onboarding, m4_inscripciones...). Nunca se renombra.';


-- ---------------------------------------------------------------------------
-- 2. Tabla: system_settings
-- ---------------------------------------------------------------------------
create table if not exists public.system_settings (
  clave       text        primary key,
  valor       jsonb,
  tipo        text        not null default 'string'
    check (tipo in ('number', 'boolean', 'string', 'json')),
  descripcion text,
  categoria   text        not null default 'general',
  es_publico  boolean     not null default false,
  updated_by  uuid        references auth.users(id) on delete set null,
  updated_at  timestamptz not null default now(),

  constraint system_settings_clave_formato
    check (clave ~ '^[a-z][a-z0-9_]*$')
);

comment on table public.system_settings is
  'Parámetros operativos editables desde el cPanel sin desplegar código.';
comment on column public.system_settings.es_publico is
  'Si es true, anon y cualquier autenticado pueden leerlo. Si no, sólo admin.';
comment on column public.system_settings.tipo is
  'Pista de UI: number | boolean | string | json. No valida el contenido.';


-- ---------------------------------------------------------------------------
-- 3. Tabla: config_audit_log  (append-only)
-- ---------------------------------------------------------------------------
create table if not exists public.config_audit_log (
  id             uuid        primary key default gen_random_uuid(),
  tabla          text        not null,
  clave          text        not null,
  valor_anterior jsonb,
  valor_nuevo    jsonb,

  -- Se guarda el correo desnormalizado a propósito: si el administrador borra
  -- su cuenta, el rastro de auditoría debe sobrevivir. Un FK lo anularía.
  actor_id       uuid,
  usuario_email  text,
  created_at     timestamptz not null default now()
);

comment on table public.config_audit_log is
  'Registro inmutable de cambios de configuración. Escribe sólo el trigger.';
comment on column public.config_audit_log.usuario_email is
  'Correo desnormalizado: la auditoría sobrevive al borrado del usuario.';


-- ---------------------------------------------------------------------------
-- 4. Trigger: updated_at / updated_by
-- ---------------------------------------------------------------------------
drop trigger if exists system_modules_set_updated_at on public.system_modules;
create trigger system_modules_set_updated_at
before update on public.system_modules
for each row execute function public.set_updated_at();

-- Para settings usamos una variante que además sella quién editó.
-- `coalesce` conserva el autor anterior si el cambio viene del backend con
-- service_role (donde auth.uid() es null).
create or replace function public.set_updated_by()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.updated_by = coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;

drop trigger if exists system_settings_set_updated_by on public.system_settings;
create trigger system_settings_set_updated_by
before update on public.system_settings
for each row execute function public.set_updated_by();


-- ---------------------------------------------------------------------------
-- 5. Trigger de auditoría (la pieza clave del Poder Absoluto)
-- ---------------------------------------------------------------------------
create or replace function public.audit_config_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_clave text;
begin
  -- Ambas tablas auditadas tienen `clave`. Un solo trigger sirve para las dos.
  v_clave := case tg_op when 'DELETE' then old.clave else new.clave end;

  if v_actor is not null then
    select u.email into v_email from auth.users u where u.id = v_actor;
  end if;

  insert into public.config_audit_log (
    tabla, clave, valor_anterior, valor_nuevo, actor_id, usuario_email
  ) values (
    tg_table_name,
    v_clave,
    case tg_op when 'INSERT' then null else to_jsonb(old) end,
    case tg_op when 'DELETE' then null else to_jsonb(new) end,
    v_actor,
    -- Distinguimos "cambio humano" de "cambio de sistema" en la auditoría.
    coalesce(v_email, case when v_actor is null then 'sistema' else v_actor::text end)
  );

  return case tg_op when 'DELETE' then old else new end;
end;
$$;

comment on function public.audit_config_change() is
  'Registra en config_audit_log todo cambio de módulos o settings. Append-only.';

drop trigger if exists system_modules_audit on public.system_modules;
create trigger system_modules_audit
after insert or update or delete on public.system_modules
for each row execute function public.audit_config_change();

drop trigger if exists system_settings_audit on public.system_settings;
create trigger system_settings_audit
after insert or update or delete on public.system_settings
for each row execute function public.audit_config_change();


-- ---------------------------------------------------------------------------
-- 6. Cortacircuitos: no se puede apagar ni borrar el propio cPanel
-- ---------------------------------------------------------------------------
create or replace function public.proteger_modulo_critico()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    if old.clave = 'm0_cpanel' then
      raise exception
        'm0_cpanel no puede eliminarse: es el acceso al propio panel.'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if new.clave = 'm0_cpanel' and new.habilitado is false then
    raise exception
      'm0_cpanel no puede deshabilitarse: dejaría al administrador fuera del sistema.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.proteger_modulo_critico() is
  'Cortacircuitos: impide apagar o borrar m0_cpanel y perder el acceso al panel.';

drop trigger if exists system_modules_proteger_critico on public.system_modules;
create trigger system_modules_proteger_critico
before insert or update or delete on public.system_modules
for each row execute function public.proteger_modulo_critico();


-- ---------------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------------
alter table public.system_modules   enable row level security;
alter table public.system_settings  enable row level security;
alter table public.config_audit_log enable row level security;

-- --- system_modules -------------------------------------------------------
-- Lectura: cualquier autenticado necesita saber qué módulos existen para
-- pintar su menú. Los `anon` no: el formulario público no muestra el menú.
drop policy if exists system_modules_read_authenticated on public.system_modules;
create policy system_modules_read_authenticated
on public.system_modules
for select
to authenticated
using (true);

drop policy if exists system_modules_admin_write on public.system_modules;
create policy system_modules_admin_write
on public.system_modules
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- --- system_settings ------------------------------------------------------
drop policy if exists system_settings_read_public on public.system_settings;
create policy system_settings_read_public
on public.system_settings
for select
to anon, authenticated
using (es_publico);

drop policy if exists system_settings_admin_all on public.system_settings;
create policy system_settings_admin_all
on public.system_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- --- config_audit_log -----------------------------------------------------
-- Sólo lectura para admin y SIN políticas de escritura: nadie puede insertar,
-- editar ni borrar a mano. El único camino de entrada es el trigger, que es
-- `security definer` y por tanto no está sujeto a RLS.
drop policy if exists config_audit_admin_read on public.config_audit_log;
create policy config_audit_admin_read
on public.config_audit_log
for select
to authenticated
using (public.is_admin());


-- ---------------------------------------------------------------------------
-- 8. Permisos a nivel de tabla
-- ---------------------------------------------------------------------------
--  OJO: Supabase concede privilegios por defecto sobre TODA tabla nueva en
--  `public` a anon/authenticated (ALTER DEFAULT PRIVILEGES). Si no se revocan,
--  una tabla tendría escritura concedida y RLS quedaría como única barrera.
--  Se revoca todo y se concede sólo lo necesario: defensa en profundidad.
revoke all on public.system_modules   from anon, authenticated;
revoke all on public.system_settings  from anon, authenticated;
revoke all on public.config_audit_log from anon, authenticated;

grant select on public.system_modules to authenticated;
grant insert, update, delete on public.system_modules to authenticated;

grant select on public.system_settings to anon, authenticated;
grant insert, update, delete on public.system_settings to authenticated;

-- Auditoría append-only de verdad: sólo lectura, y encima RLS no tiene
-- política de escritura. Dos barreras independientes.
grant select on public.config_audit_log to authenticated;

revoke all on function public.audit_config_change() from public, anon, authenticated;
revoke all on function public.proteger_modulo_critico() from public, anon, authenticated;
revoke all on function public.set_updated_by() from public, anon, authenticated;

-- Refuerzo de una dependencia de fases anteriores: las políticas RLS invocan
-- `public.is_admin()`, y la expresión de una política se evalúa con los
-- privilegios del rol que consulta. Sin EXECUTE, `authenticated` recibiría
-- "permission denied for function is_admin" en vez de una fila filtrada.
grant execute on function public.is_admin() to authenticated;


-- ---------------------------------------------------------------------------
-- 9. Índices de apoyo
-- ---------------------------------------------------------------------------
create index if not exists system_modules_habilitado_idx
  on public.system_modules (habilitado, orden);

create index if not exists config_audit_log_created_at_idx
  on public.config_audit_log (created_at desc);

create index if not exists config_audit_log_tabla_clave_idx
  on public.config_audit_log (tabla, clave);


-- ---------------------------------------------------------------------------
-- 10. Semilla
-- ---------------------------------------------------------------------------
--  Idempotente y NO destructiva: `do nothing` en conflicto. Reaplicar esta
--  migración nunca pisa los interruptores que el administrador ya movió.
--
--  Estado inicial honesto: sólo se encienden los módulos que existen de verdad.
--  m2..m8 arrancan apagados porque su código todavía no está construido.
--
--  `m0_cpanel` (este panel) y `m1_onboarding` (registro de aspirantes) van
--  encendidos. m9 (certificados/QR) quedó descartado: no se siembra.
insert into public.system_modules
  (clave, nombre, descripcion, habilitado, orden, icono, roles_permitidos, categoria)
values
  ('m0_cpanel', 'Administrador Maestro',
   'Interruptores de módulos, parámetros del sistema y auditoría.',
   true,  0, 'tune',        array['admin'], 'nucleo'),

  ('m1_onboarding', 'Autenticación y Onboarding',
   'Registro de aspirantes, roles y control de acceso.',
   true,  10, 'badge',      '{}', 'nucleo'),

  ('m2_curriculo', 'Currículo y Pensum',
   'Programas, unidades curriculares, períodos y setup inicial.',
   false, 20, 'menu_book',  '{}', 'academico'),

  ('m3_cuadrante', 'Cuadrante y Horarios',
   'Secciones, aulas, bloques horarios y control anti-colisión.',
   false, 30, 'calendar_month', '{}', 'academico'),

  ('m4_inscripciones', 'Inscripciones y Cupos',
   'Cola FIFO, ofertas de cupo con vencimiento y listas de espera.',
   false, 40, 'how_to_reg', '{}', 'academico'),

  ('m5_archivos', 'Almacenamiento de Archivos',
   'Material de apoyo en Cloudflare R2 mediante URLs firmadas.',
   false, 50, 'folder_open', '{}', 'recursos'),

  ('m6_asistencia', 'Asistencia',
   'Registro de asistencia y expulsión automática por faltas consecutivas.',
   false, 60, 'fact_check', '{}', 'academico'),

  ('m7_calificaciones', 'Calificaciones',
   'Planes de evaluación, notas y cierre de actas.',
   false, 70, 'grading',    '{}', 'academico'),

  ('m8_pasantias', 'Pasantías',
   'Tutor industrial externo y evaluación sin cuenta institucional.',
   false, 80, 'work_outline', '{}', 'academico')
on conflict (clave) do nothing;

insert into public.system_settings
  (clave, valor, tipo, descripcion, categoria, es_publico)
values
  ('inscripciones_abiertas', 'true'::jsonb, 'boolean',
   'Si está activo, el formulario público acepta nuevas solicitudes.',
   'inscripciones', true),

  ('periodo_activo', '"2026-1"'::jsonb, 'string',
   'Período académico en curso. Se muestra en el formulario de inscripción.',
   'academico', true),

  ('modo_mantenimiento', 'false'::jsonb, 'boolean',
   'Si está activo, la API rechaza peticiones de todo rol que no sea admin.',
   'general', true),

  ('max_faltas_consecutivas', '3'::jsonb, 'number',
   'Faltas consecutivas que provocan la expulsión automática del participante.',
   'asistencia', false),

  ('bid_ttl_horas', '24'::jsonb, 'number',
   'Horas que un cupo ofertado permanece reservado antes de pasar al siguiente.',
   'inscripciones', false),

  ('enrollment_lock_days', '2'::jsonb, 'number',
   'Días que un cupo queda bloqueado tras una oferta no respondida.',
   'inscripciones', false),

  ('cupo_maximo_por_seccion', '25'::jsonb, 'number',
   'Cupo por defecto al crear una sección nueva.',
   'academico', false),

  ('r2_presign_ttl_minutos', '15'::jsonb, 'number',
   'Minutos de validez de una URL firmada de Cloudflare R2.',
   'almacenamiento', false)
on conflict (clave) do nothing;


-- ---------------------------------------------------------------------------
-- 11. Promover a un administrador (una sola vez, manual)
-- ---------------------------------------------------------------------------
--  El auto-registro nunca otorga privilegios. Para habilitar el primer admin,
--  ejecuta esto desde el SQL Editor de Supabase:
--
--    update public.profiles
--       set rol = 'admin'
--     where lower(email) = 'tu-correo@inces.edu.ve';
--
--  A partir de ahí, el cPanel puede gestionar todo lo demás.
-- ============================================================================
