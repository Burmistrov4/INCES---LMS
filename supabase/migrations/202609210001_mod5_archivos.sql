-- ============================================================================
--  INCES LMS — Módulo 5: Archivos (Cloudflare R2)
--  Archivo: 202609210001_mod5_archivos.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  M5 guarda archivos pesados (material de apoyo, entregas) en Cloudflare R2.
--  El backend NUNCA mueve bytes: firma URLs (PUT para subir, GET para leer) y
--  R2 hace el transporte. Lo que la base aporta es la ÚNICA parte que no se
--  puede delegar al almacén: el METADATO —de quién es cada objeto, a qué
--  entidad pertenece y en qué estado está—, que es lo que permite autorizar
--  cada descarga y saber qué hay que limpiar.
--
--  El objeto en R2 y su fila aquí no nacen juntos (no hay transacción que
--  abarque los dos), así que la fila existe antes que el objeto, en estado
--  PENDING. Sólo cuando el backend comprueba con HeadObject que el objeto
--  llegó de verdad se confirma (CONFIRMED). Así un archivo a medias —subida
--  interrumpida— nunca cuenta como entregado, y queda visible como PENDING
--  para poder barrerlo.
--
--  DECISIONES (cerradas con el dueño del producto)
--  -----------------------------------------------
--  1. La escritura directa desde el cliente está PROHIBIDA (patrón de M4): la
--     clave publishable viaja al navegador (ADR-003), así que si se pudiera
--     insertar en `files_metadata` a mano, cualquiera podría registrarse como
--     propietario de un objeto que no subió, o marcar como confirmado lo que
--     no existe. Toda escritura pasa por RPC `security definer`.
--  2. El tamaño máximo (10 MB) y la cantidad máxima de archivos por entidad
--     (10) son PARÁMETROS configurables (`m5_max_bytes`,
--     `m5_max_archivos_por_entidad`), no constantes del código: el
--     administrador los cambia desde el panel sin desplegar. Aquí sólo se
--     siembran los valores por defecto.
--  3. El borrado es LÓGICO (`estado = 'DELETED'`, `deleted_at`): la fila se
--     conserva como historial y para poder reconciliar con R2. El objeto real
--     lo elimina el backend, que es quien tiene credenciales de R2.
--
--  `security definer` OBLIGA A AUTORIZAR A MANO (lección R-20)
--  -----------------------------------------------------------
--  Una función `definer` corre con los privilegios de su dueño y SE SALTA la
--  RLS de `files_metadata`. Por eso cada RPC hace su propia autorización con
--  `auth.uid()` (y `is_admin()` donde toca) y fija `search_path = public,
--  pg_temp`. La RLS ya no protege estas escrituras: lo hace la autorización
--  explícita de cada función. Conceder EXECUTE de más aquí abriría justo la
--  puerta que este archivo cierra.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — La tabla de metadatos
-- ---------------------------------------------------------------------------
create table if not exists public.files_metadata (
  id              uuid        primary key default gen_random_uuid(),
  propietario_id  uuid        not null references auth.users(id) on delete cascade,
  r2_key          text        not null unique,
  nombre_original text        not null,
  tipo_contenido  text        not null,
  tamano_bytes    bigint,
  entity_type     text        not null check (entity_type in ('TASK_SUBMISSION', 'TEACHER_GUIDE')),
  entidad_id      uuid,
  estado          text        not null default 'PENDING' check (estado in ('PENDING', 'CONFIRMED', 'DELETED')),
  created_at      timestamptz not null default now(),
  confirmado_en   timestamptz,
  deleted_at      timestamptz
);

comment on table public.files_metadata is
  'Metadatos de los objetos de M5 en Cloudflare R2. El backend firma URLs; aquí vive la propiedad, la entidad y el estado. Escritura sólo por RPC security definer.';
comment on column public.files_metadata.id is
  'Identificador del archivo. Se usa para confirmarlo o borrarlo sin exponer la clave de R2.';
comment on column public.files_metadata.propietario_id is
  'Usuario de auth dueño del archivo. ON DELETE CASCADE: al borrarse la cuenta, su rastro de metadatos desaparece; el barrido del objeto en R2 lo hace el backend.';
comment on column public.files_metadata.r2_key is
  'Clave del objeto en R2 (construida siempre por el servidor). UNIQUE: una clave no puede describir dos archivos.';
comment on column public.files_metadata.nombre_original is
  'Nombre legible que eligió el usuario. NO forma parte de la clave (ésta es un UUID); se aplica al descargar vía Content-Disposition.';
comment on column public.files_metadata.tipo_contenido is
  'Tipo MIME canónico, derivado de la extensión en el servidor. No se confía en el que declara el navegador.';
comment on column public.files_metadata.tamano_bytes is
  'Tamaño real del objeto, fijado al confirmar (lo aporta el HeadObject). NULL mientras está PENDING: una subida a medias no tiene tamaño.';
comment on column public.files_metadata.entity_type is
  'A qué clase de entidad pertenece el archivo: entrega de tarea o guía del docente.';
comment on column public.files_metadata.entidad_id is
  'Id de la entidad concreta (tarea o guía). Anulable: la entidad puede crearse después de subir el archivo.';
comment on column public.files_metadata.estado is
  'Ciclo de vida: PENDING (fila creada, objeto sin confirmar) → CONFIRMED (objeto verificado) → DELETED (borrado lógico).';
comment on column public.files_metadata.created_at is
  'Cuándo se reservó la clave. Un PENDING antiguo es una subida abandonada que hay que barrer.';
comment on column public.files_metadata.confirmado_en is
  'Cuándo se verificó la existencia y el tamaño del objeto. NULL mientras está PENDING.';
comment on column public.files_metadata.deleted_at is
  'Cuándo se marcó como borrado (borrado lógico). NULL si sigue vivo.';


-- ---------------------------------------------------------------------------
--  PARTE 2 — Índices
-- ---------------------------------------------------------------------------
-- «Los archivos de este usuario, por estado»: es la consulta de la pantalla de
-- recursos y del barrido de PENDING abandonados.
create index if not exists files_metadata_propietario_estado_idx
  on public.files_metadata (propietario_id, estado);

-- «Los archivos de esta tarea/guía»: es cómo se listan los adjuntos de una
-- entidad. Sin este índice, cada apertura de una entrega recorrería la tabla.
create index if not exists files_metadata_entidad_idx
  on public.files_metadata (entity_type, entidad_id);


-- ---------------------------------------------------------------------------
--  PARTE 3 — RLS: lectura sí, escritura no
-- ---------------------------------------------------------------------------
alter table public.files_metadata enable row level security;

-- El propietario ve lo suyo.
drop policy if exists files_metadata_read_own on public.files_metadata;
create policy files_metadata_read_own
on public.files_metadata
for select
to authenticated
using (auth.uid() = propietario_id);

-- El administrador lo ve todo: es quien supervisa el material y limpia.
drop policy if exists files_metadata_admin_read on public.files_metadata;
create policy files_metadata_admin_read
on public.files_metadata
for select
to authenticated
using (public.is_admin());

-- Frontera de seguridad (decisión 1): se quita TODA escritura directa. Sin
-- esto, la RLS sería la única barrera y bastaría una política laxa para que un
-- cliente registrara filas a mano. Toda escritura pasa por las RPC de abajo.
revoke all on public.files_metadata from anon, authenticated;
grant select on public.files_metadata to authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 4 — RPCs de escritura
-- ---------------------------------------------------------------------------
--  Autorización uniforme: la RLS no actúa dentro de una función `definer`, así
--  que cada una comprueba `auth.uid()` e `is_admin()` por su cuenta. Los fallos
--  de autorización usan 42501 (→ 403, el mismo código que produce la RLS); los
--  de estado o inexistencia, 23514 (→ 400 con el mensaje tal cual).

-- ---------------------------------------------------------------------------
--  4.1 Reservar un archivo (PENDING) antes de subirlo
-- ---------------------------------------------------------------------------
create or replace function public.registrar_archivo_pendiente(
  p_propietario     uuid,
  p_r2_key          text,
  p_nombre_original text,
  p_tipo_contenido  text,
  p_entity_type     text,
  p_entidad_id      uuid
)
returns public.files_metadata
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_fila  public.files_metadata;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para registrar un archivo.'
      using errcode = '42501';
  end if;

  -- El propietario lo elige el llamante, pero no puede ser cualquiera: sólo se
  -- admite a uno mismo, salvo que sea un administrador registrando en nombre de
  -- otro. Sin esta comprobación, un usuario podría registrar archivos como si
  -- fueran de un tercero (y que a éste le aparecieran adjuntos que no subió).
  if v_actor <> p_propietario and not public.is_admin() then
    raise exception 'No puedes registrar un archivo a nombre de otro usuario.'
      using errcode = '42501';
  end if;

  insert into public.files_metadata (
    propietario_id, r2_key, nombre_original, tipo_contenido, entity_type, entidad_id
  ) values (
    p_propietario, p_r2_key, p_nombre_original, p_tipo_contenido, p_entity_type, p_entidad_id
  )
  returning * into v_fila;

  return v_fila;
end;
$$;

comment on function public.registrar_archivo_pendiente(uuid, text, text, text, text, uuid) is
  'Reserva un archivo en estado PENDING antes de subir el objeto a R2. Sólo el propio usuario o un admin. La clave la construye el servidor; su forma no se valida aquí (eso es dominio puro).';


-- ---------------------------------------------------------------------------
--  4.2 Confirmar un archivo (PENDING → CONFIRMED)
-- ---------------------------------------------------------------------------
create or replace function public.confirmar_archivo(
  p_archivo_id   uuid,
  p_tamano_bytes bigint
)
returns public.files_metadata
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_fila  public.files_metadata;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para confirmar un archivo.'
      using errcode = '42501';
  end if;

  select * into v_fila
  from public.files_metadata
  where id = p_archivo_id;

  if not found then
    raise exception 'El archivo % no existe.', p_archivo_id
      using errcode = '23514';
  end if;

  if v_fila.propietario_id <> v_actor and not public.is_admin() then
    raise exception 'No puedes confirmar un archivo que no es tuyo.'
      using errcode = '42501';
  end if;

  -- Sólo se confirma lo que está PENDING. Reconfirmar un CONFIRMED o resucitar
  -- un DELETED se rechaza explícitamente: son estados terminales, y un error
  -- claro es mejor que un UPDATE silencioso que reescriba un tamaño ya sellado.
  if v_fila.estado <> 'PENDING' then
    raise exception 'El archivo % no está pendiente (estado actual: %).', p_archivo_id, v_fila.estado
      using errcode = '23514';
  end if;

  update public.files_metadata
     set estado        = 'CONFIRMED',
         tamano_bytes  = p_tamano_bytes,
         confirmado_en = now()
   where id = p_archivo_id
  returning * into v_fila;

  return v_fila;
end;
$$;

comment on function public.confirmar_archivo(uuid, bigint) is
  'Confirma un archivo PENDING (PENDING→CONFIRMED) fijando el tamaño real que aporta el HeadObject. Sólo el propietario o un admin. La comprobación del límite de tamaño es del dominio, no de aquí.';


-- ---------------------------------------------------------------------------
--  4.3 Marcar un archivo como borrado (borrado lógico)
-- ---------------------------------------------------------------------------
create or replace function public.marcar_archivo_borrado(p_archivo_id uuid)
returns public.files_metadata
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_fila  public.files_metadata;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para borrar un archivo.'
      using errcode = '42501';
  end if;

  select * into v_fila
  from public.files_metadata
  where id = p_archivo_id;

  if not found then
    raise exception 'El archivo % no existe.', p_archivo_id
      using errcode = '23514';
  end if;

  if v_fila.propietario_id <> v_actor and not public.is_admin() then
    raise exception 'No puedes borrar un archivo que no es tuyo.'
      using errcode = '42501';
  end if;

  if v_fila.estado = 'DELETED' then
    raise exception 'El archivo % ya estaba borrado.', p_archivo_id
      using errcode = '23514';
  end if;

  update public.files_metadata
     set estado     = 'DELETED',
         deleted_at = now()
   where id = p_archivo_id
  returning * into v_fila;

  return v_fila;
end;
$$;

comment on function public.marcar_archivo_borrado(uuid) is
  'Borrado lógico de un archivo (→DELETED, deleted_at). Sólo el propietario o un admin. El objeto de R2 lo elimina el backend, que es quien tiene credenciales.';


-- ---------------------------------------------------------------------------
--  PARTE 5 — Semilla de los límites configurables
-- ---------------------------------------------------------------------------
--  Decisión 2. Mismo idioma que las semillas anteriores: idempotente y NO
--  destructiva (`on conflict do nothing`), para que reaplicar la migración no
--  pise el valor que el administrador ya ajustó desde el panel.
--
--  `tipo = 'number'` para que el cPanel pinte un control numérico; `es_publico
--  = false` porque son parámetros operativos, no información del formulario
--  público. Categoría `almacenamiento`, la misma que usa `r2_presign_ttl_minutos`.
insert into public.system_settings
  (clave, valor, tipo, descripcion, categoria, es_publico)
values
  ('m5_max_bytes', '10485760'::jsonb, 'number',
   'Tamaño máximo por archivo, en bytes (10 MB por defecto). El backend lo aplica tras subir, con HeadObject.',
   'almacenamiento', false),

  ('m5_max_archivos_por_entidad', '10'::jsonb, 'number',
   'Cantidad máxima de archivos que puede tener una misma entidad (tarea o guía).',
   'almacenamiento', false)
on conflict (clave) do nothing;


-- ---------------------------------------------------------------------------
--  PARTE 6 — Permisos de las funciones
-- ---------------------------------------------------------------------------
--  PostgreSQL concede EXECUTE a PUBLIC por defecto en toda función nueva: sin
--  el `revoke` explícito, `anon` podría llamar a las RPC. Se revoca de `public`
--  y `anon`, y se concede sólo a `authenticated` (quien tiene sesión; la
--  autorización fina la hace cada función con `auth.uid()` / `is_admin()`).
revoke all on function public.registrar_archivo_pendiente(uuid, text, text, text, text, uuid) from public, anon;
revoke all on function public.confirmar_archivo(uuid, bigint)                            from public, anon;
revoke all on function public.marcar_archivo_borrado(uuid)                               from public, anon;

grant execute on function public.registrar_archivo_pendiente(uuid, text, text, text, text, uuid) to authenticated;
grant execute on function public.confirmar_archivo(uuid, bigint)                            to authenticated;
grant execute on function public.marcar_archivo_borrado(uuid)                               to authenticated;


-- ---------------------------------------------------------------------------
--  NOTA — El módulo se deja APAGADO a propósito
-- ---------------------------------------------------------------------------
--  `m5_archivos` NO se enciende en esta migración. La bandera debe ser la
--  última pieza que encaja (igual que en M4): se habilita sólo cuando ya
--  existen las rutas de firmas (Capa 4) y la UI de Flutter (Capa 7) que lo
--  sostienen. Encenderlo antes dejaría un ítem de menú sin circuito detrás.
