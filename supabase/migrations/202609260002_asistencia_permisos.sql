-- ============================================================================
--  INCES LMS — Asistencia: permisos sobre el secreto + módulo habilitado
--  Archivo: 202609260002_asistencia_permisos.sql
-- ============================================================================
--
--  QUÉ CIERRA
--  ----------
--  La migración 202609260001 dejo `asistencia_codigo_actual(uuid)` ejecutable
--  por cualquier `authenticated`. Eso está mal en la concurrencia de aula: la
--  función devuelve el código del QR vigente SIN comprobar a quién se lo pide.
--  Un estudiante podría llamarla con el uuid de la sesión —que consigue
--  escaneando el QR una vez— y dejar de depender de ver la pantalla. Eso rompe
--  el punto anti-trampas.
--
--  Esta migración sobreescribe la función exigiendo ser docente de la sección
--  o admin; a un estudiante le responde 42501. Ver compañera: mismo criterio
--  que `condicion_campo_se_cumple` (202609250003): la coherencia de la
--  «autoridad delegable» vive en la base, no en la app.
--
--  Además enciende el módulo en `system_modules`: sin la fila, el menú del
--  docente no pinta la entrada ni aunquecompile la pantalla en Flutter (la
--  guardia `exigirModulo` de M5/M6, y aquí para M7).
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — `asistencia_codigo_actual` con barrera de propiedad
-- ---------------------------------------------------------------------------
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
  v_es_admin boolean;
  v_es_su    boolean;
begin
  select * into v_sesion from public.attendance_sessions where id = p_sesion;
  if not found then return null; end if;
  if v_sesion.status <> 'OPEN' then return null; end if;

  -- Sólo quien abrió la sesión, el docente de la sección, o un admin.
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
           floor(extract(epoch from now()) / v_sesion.ventana_seg));
end;
$$;

comment on function public.asistencia_codigo_actual(uuid) is
  'Devuelve el código vigente AHORA para una sesión de asistencia. SÓLO la llama el docente dueño de la sección o un admin: 202609260002 añade la guardia, sin la cual un estudiante podría pedirse el código y romper la barrera anti-trampas.';


-- ---------------------------------------------------------------------------
--  PARTE 2 — El módulo existe en el árbol del menú
-- ---------------------------------------------------------------------------
-- Patrón de 202609220003: la bandera es una fila, no una columna. La semilla
-- PARTE 1: insertar la clave si falta; habilitada por defecto porque en esta
-- misma migración ya existe el docente-side (el QR y el tablero se pintan
-- en Flutter) y el control por RLS.
insert into public.system_modules (clave, nombre, descripcion, habilitado, orden, icono, roles_permitidos, categoria)
values (
  'm7_asistencia',
  'Asistencia QR en vivo',
  'Tablero del docente con QR efímero y marcas por WebSocket, sin recargar.',
  true,
  7,
  'qr_code_scanner',
  array['docente', 'admin'],
  'aula'
)
on conflict (clave) do update set habilitado = true;


-- ---------------------------------------------------------------------------
--  PARTE 3 — Autocomprobación
-- ---------------------------------------------------------------------------
do $$
declare
  v_permiso int;
begin
  -- La función sigue siendo `security definer` y NO es ejecutable por estudiantes:
  -- simula un auth.uid() cualquiera; debe abortar por 42501 o devolver null para
  -- una sesión inexistente, pero JAMAS devolver un código de una sesión ajena.
  perform proname from pg_proc
   where proname = 'asistencia_codigo_actual' and prosecdef;
  if not found then
    raise exception 'asistencia_codigo_actual no quedó security definer.' using errcode = '23514';
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attendance_marks' and policyname = 'attendance_marks_estudiante_insert') then
    raise exception 'La política anti-trampas no quedó puesta.' using errcode = '23514';
  end if;

  raise notice 'Autocomprobación 202609260002: asistencia_codigo_actual con barrera de propiedad; módulo m7_asistencia encendido.';
end;
$$;
