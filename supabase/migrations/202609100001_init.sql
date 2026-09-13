create extension if not exists pgcrypto;

create table if not exists public.cursos (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  cedula text unique,
  email text not null unique,
  nombres text not null,
  apellidos text not null,
  rol text not null default 'estudiante'
    check (rol in ('admin', 'docente', 'estudiante')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.aspirantes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  cedula text not null,
  nombres text not null,
  apellidos text not null,
  fecha_nac date not null,
  sexo text not null check (sexo in ('M', 'F', 'Otro')),
  telefono text not null,
  email text not null unique,
  direccion text not null,
  nivel_educativo text not null,
  curso_seleccionado text not null,
  mision_ribaras text,
  discapacidad boolean not null default false,
  tipo_discapacidad text,
  numero_identidad_tutor text,
  nombre_tutor text,
  parentesco_tutor text,
  telefono_tutor text,
  correo_tutor text,
  requires_legal_tutor boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint aspirantes_cedula_key unique (cedula),
  constraint aspirantes_user_id_key unique (user_id),
  constraint aspirantes_requires_tutor_key check (
    requires_legal_tutor = (fecha_nac > (current_date - interval '18 years')::date)
  )
);

create table if not exists public.sections (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  cupo_maximo integer not null default 0 check (cupo_maximo >= 0),
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  section_id uuid not null references public.sections(id) on delete cascade,
  status text not null default 'WAITLISTED'
    check (status in ('ENROLLED', 'WAITLISTED', 'PENDING_BID', 'DROPPED')),
  bid_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, section_id)
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists aspirantes_set_updated_at on public.aspirantes;
create trigger aspirantes_set_updated_at
before update on public.aspirantes
for each row execute function public.set_updated_at();

drop trigger if exists sections_set_updated_at on public.sections;
create trigger sections_set_updated_at
before update on public.sections
for each row execute function public.set_updated_at();

drop trigger if exists enrollments_set_updated_at on public.enrollments;
create trigger enrollments_set_updated_at
before update on public.enrollments
for each row execute function public.set_updated_at();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and rol = 'admin'
      and active
  );
$$;

alter table public.cursos enable row level security;
alter table public.profiles enable row level security;
alter table public.aspirantes enable row level security;
alter table public.sections enable row level security;
alter table public.enrollments enable row level security;

create policy cursos_read_active
on public.cursos
for select
to anon, authenticated
using (activo);

create policy profiles_read_own
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid() and rol = 'estudiante');

create policy profiles_admin_all
on public.profiles
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy aspirantes_read_own
on public.aspirantes
for select
to authenticated
using (user_id = auth.uid());

create policy aspirantes_insert_own
on public.aspirantes
for insert
to authenticated
with check (user_id = auth.uid());

create policy aspirantes_insert_public
on public.aspirantes
for insert
to anon
with check (
  user_id is null
  and cedula <> ''
  and nombres <> ''
  and apellidos <> ''
  and fecha_nac is not null
  and sexo in ('M', 'F', 'Otro')
  and telefono <> ''
  and position('@' in email) > 1
  and direccion <> ''
  and nivel_educativo <> ''
  and curso_seleccionado <> ''
  and requires_legal_tutor = (
    fecha_nac > (current_date - interval '18 years')::date
  )
);

create policy aspirantes_update_own
on public.aspirantes
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy aspirantes_delete_own
on public.aspirantes
for delete
to authenticated
using (user_id = auth.uid());

create policy aspirantes_admin_all
on public.aspirantes
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy sections_read_active
on public.sections
for select
to anon, authenticated
using (activa);

create policy sections_admin_all
on public.sections
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy enrollments_read_own
on public.enrollments
for select
to authenticated
using (student_id = auth.uid());

create policy enrollments_insert_own
on public.enrollments
for insert
to authenticated
with check (student_id = auth.uid());

create policy enrollments_update_own
on public.enrollments
for update
to authenticated
using (student_id = auth.uid())
with check (student_id = auth.uid());

create policy enrollments_delete_own
on public.enrollments
for delete
to authenticated
using (student_id = auth.uid());

create policy enrollments_admin_all
on public.enrollments
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

insert into public.cursos (nombre)
values
  ('Herrería'),
  ('Higiene y Manipulación de Alimentos'),
  ('Estética (cejas y pestañas)'),
  ('Oratoria'),
  ('Curso Introductorio (15-16 años)')
on conflict (nombre) do nothing;
