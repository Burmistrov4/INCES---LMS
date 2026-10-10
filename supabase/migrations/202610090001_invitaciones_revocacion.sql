-- ============================================================================
--  INCES LMS — Módulo 1: ciclo de vida completo de la invitación de docente
--  Archivo: 202610090001_invitaciones_revocacion.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  Hasta ahora una invitación sólo tenía dos finales: consumida (`is_used`) o
--  caducada (`expires_at`). Faltaban dos operaciones que el procedimiento
--  institucional necesita de verdad:
--
--    * REVOCAR una invitación que se emitió por error, que se entregó a la
--      persona equivocada o que hay que anular antes de que se use.
--    * RENOVAR: emitir una credencial nueva cuando la anterior se perdió o
--      caducó. Renovar es revocar la vieja y crear otra, para que **no queden
--      dos tokens válidos** apuntando a la misma cuenta.
--
--  DISEÑO
--  ------
--  * `revoked_at` es la marca de anulación; `revoked_by` guarda quién la anuló
--    (auditoría mínima). Ambas NULLABLES: una invitación normal no se revoca.
--  * NO se borra la fila al revocar. Un `delete` perdería la traza de que esa
--    invitación existió, y el administrador necesita ver "revocada" en el panel,
--    no que desaparezca.
--  * La regla de negocio (qué estado gana) vive en el backend, en
--    `estadoDeInvitacion`; la base sólo aporta el dato.
--  * NO se toca ninguna migración ya aplicada: esto es aditivo y nuevo.
--
--  ORDEN DE LOS ESTADOS (lo decide el backend, no la base)
--  ------------------------------------------------------
--  revocada > usada > expirada > válida. Una invitación revocada no "revive"
--  aunque después se marque usada, y una usada sigue siendo usada aunque además
--  haya caducado.
-- ============================================================================

alter table public.teacher_invitations
  add column if not exists revoked_at timestamptz,
  add column if not exists revoked_by uuid;

comment on column public.teacher_invitations.revoked_at is
  'Instante en que el administrador anuló la invitación. NULL = no revocada. Una invitación revocada no puede activarse.';
comment on column public.teacher_invitations.revoked_by is
  'Id del perfil que revocó la invitación. Auditoría mínima de la anulación.';

-- Índice de apoyo para el listado del cPanel, que ordena por creación y filtra
-- por estado. Parcial: sólo indexa lo que el panel consulta de verdad.
create index if not exists teacher_invitations_pendientes_idx
  on public.teacher_invitations (created_at desc)
  where is_used = false and revoked_at is null;
