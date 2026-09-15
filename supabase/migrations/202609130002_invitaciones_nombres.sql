-- ============================================================================
--  INCES LMS — Módulo 1: capturar nombres y apellidos en la invitación (R-21)
--  Archivo: 202609130002_invitaciones_nombres.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El administrador invitaba a un docente aportando sólo el correo. El docente
--  activaba su cuenta, pero `profiles.nombres`/`profiles.apellidos` quedaban en
--  blanco, así que `nombre_para_mostrar()` devolvía NULL y el cuadrante y los
--  listados mostraban «Docente sin nombre» (R-21).
--
--  Ahora el administrador captura el nombre real al invitar. Se guarda en la
--  invitación; al activar, la cuenta se crea con ese nombre en
--  `user_metadata`, y `handle_new_user()` (202609120001) ya lo vuelca a
--  `profiles`. El hueco estaba aguas arriba del disparador, no en él.
--
--  DISEÑO
--  ------
--  * Columnas NULLABLES a propósito: la API las exige (Zod `.min(1)`), pero no
--    forzamos NOT NULL para no romper filas existentes ni el camino de activación
--    legacy. La regla de negocio vive en la API, igual que el resto.
--  * No se toca `handle_new_user()`: ya lee `nombres`/`apellidos` de
--    `raw_user_meta_data`. Sólo faltaba alimentar ese metadata desde la
--    invitación.
-- ============================================================================

alter table public.teacher_invitations
  add column if not exists nombres   text,
  add column if not exists apellidos text;

comment on column public.teacher_invitations.nombres is
  'Nombre(s) del docente invitado, capturado por el administrador. Al activar, va a user_metadata y de ahí a profiles (R-21).';
comment on column public.teacher_invitations.apellidos is
  'Apellido(s) del docente invitado, capturado por el administrador. Complementa nombres para nombre_para_mostrar() (R-21).';
