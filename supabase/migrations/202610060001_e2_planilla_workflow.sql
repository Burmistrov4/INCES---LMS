-- ============================================================================
--  E-2 · Persistencia del workflow de la Planilla Oficial
-- ============================================================================
--
--  DOS TABLAS NUEVAS, NINGUNA COLUMNA NUEVA EN `aspirantes`.
--
--  `aspirantes.datos_planilla` sigue siendo la ficha VIVA y mutable. Una versión
--  es una FOTO: el estado pertenece a la versión, no a la ficha, porque v1 se
--  observó y v2 se aprobó — y eso no cabe en una columna.
--
--  `BORRADOR` NO es un estado de versión: es la AUSENCIA de versión. Así hay un
--  solo sitio diciendo el estado (la última versión); con un `BORRADOR`
--  almacenado habría dos fuentes y podrían contradecirse.
--
--  Y NO se crean versiones retroactivas: una versión afirma que en esa fecha el
--  aspirante envió esos datos, y fabricarla hacia atrás sería inventar un acto
--  administrativo que no ocurrió.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  1. Versiones
-- ---------------------------------------------------------------------------
create table if not exists public.planilla_versiones (
  id            uuid        primary key default gen_random_uuid(),

  -- La PK de la ficha, no `user_id`: el `id` de la ficha es estable aunque la
  -- cuenta de Auth se recreara.
  --
  -- `on delete restrict` y NO `cascade`: borrar una cuenta no debe destruir en
  -- silencio el historial de lo que se aprobó. Si alguien borra una ficha con
  -- versiones, quiere enterarse antes — `supabase/eliminar-cuenta.mjs` tendrá
  -- que tratarlo (ver la nota al final).
  aspirante_id  uuid        not null
                            references public.aspirantes(id) on delete restrict,

  numero        integer     not null check (numero > 0),

  -- `BORRADOR` no está aquí a propósito: ver la cabecera.
  estado        text        not null
                            check (estado in ('ENVIADA', 'OBSERVADA', 'REENVIADA', 'APROBADA')),

  -- La planilla congelada. Es lo que garantiza que el PDF de v1 siga diciendo lo
  -- mismo dentro de un año, aunque la ficha haya cambiado veinte veces.
  datos_snapshot jsonb      not null,

  -- **Y es la FECHA del PDF oficial**: la fecha de envío de la versión que se
  -- imprime. Congelada por definición — una versión no se reenvía, se crea otra.
  enviada_at    timestamptz not null default now(),

  aprobada_at   timestamptz,
  approved_by   uuid        references public.profiles(id) on delete restrict,

  created_at    timestamptz not null default now(),

  unique (aspirante_id, numero),

  -- Los DOS sentidos de la coherencia estado↔aprobación. El primero solo no
  -- bastaría: impediría una APROBADA sin fecha, pero no que una ENVIADA llevara
  -- `aprobada_at`.
  constraint planilla_versiones_aprobada_completa check (
    estado <> 'APROBADA'
    or (aprobada_at is not null and approved_by is not null)
  ),
  constraint planilla_versiones_no_aprobada_limpia check (
    estado = 'APROBADA'
    or (aprobada_at is null and approved_by is null)
  )
);

comment on table public.planilla_versiones is
  'Una fila por ENVÍO o REENVÍO de la planilla. Inmutable salvo la transición de estado. `BORRADOR` es la ausencia de fila.';

comment on column public.planilla_versiones.enviada_at is
  'Fecha de envío de ESTA versión. Es la FECHA que imprime el PDF oficial.';

create index if not exists planilla_versiones_aspirante_idx
  on public.planilla_versiones (aspirante_id, numero desc);

-- ---------------------------------------------------------------------------
--  2. Observaciones
-- ---------------------------------------------------------------------------
create table if not exists public.planilla_observaciones (
  id            uuid        primary key default gen_random_uuid(),

  -- `cascade` aquí sí: una observación sin su versión no significa nada. Es la
  -- única de las cuatro FK donde el borrado en cascada es correcto.
  version_id    uuid        not null
                            references public.planilla_versiones(id) on delete cascade,

  observada_por uuid        not null references public.profiles(id) on delete restrict,

  -- Obligatorio, y no vacío: el contrato exige que el aspirante sepa QUÉ corregir.
  motivo        text        not null check (btrim(motivo) <> ''),

  created_at    timestamptz not null default now()
);

comment on table public.planilla_observaciones is
  'Una fila por observación administrativa. NO se «resuelve»: se responde con una versión nueva, y el vínculo lo da la secuencia.';

create index if not exists planilla_observaciones_version_idx
  on public.planilla_observaciones (version_id);

-- ---------------------------------------------------------------------------
--  3. Inmutabilidad
-- ---------------------------------------------------------------------------
--
--  **Por qué trigger y no un `check`:** esto compara `OLD` contra `NEW`, y un
--  `check` no puede hacerlo.
--
--  **Por qué no basta el servicio:** el administrador escribe por PostgREST
--  directo (ADR-003), así que un `UPDATE` se saltaría cualquier comprobación que
--  viva en Fastify. La garantía tiene que estar en la tabla.
create or replace function public.impedir_version_modificada()
returns trigger
language plpgsql
as $$
begin
  -- El contenido histórico no cambia NUNCA, ni al aprobar.
  if new.aspirante_id  is distinct from old.aspirante_id
     or new.numero        is distinct from old.numero
     or new.datos_snapshot is distinct from old.datos_snapshot
     or new.enviada_at    is distinct from old.enviada_at
     or new.created_at    is distinct from old.created_at then
    raise exception 'Una versión formalizada no puede alterar su contenido histórico'
      using errcode = '23514';
  end if;

  -- Y el estado sólo avanza por las transiciones del contrato.
  if new.estado is distinct from old.estado then
    if not (
         (old.estado in ('ENVIADA', 'REENVIADA') and new.estado in ('OBSERVADA', 'APROBADA'))
      or (old.estado = 'OBSERVADA' and new.estado = 'REENVIADA')
    ) then
      raise exception 'Transición de planilla no permitida: % → %', old.estado, new.estado
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.impedir_version_modificada() is
  'Congela el contenido de una versión y limita las transiciones de estado a las del contrato. Distingue «cambiar el estado permitido» de «alterar el contenido histórico».';

drop trigger if exists planilla_versiones_inmutables on public.planilla_versiones;
create trigger planilla_versiones_inmutables
  before update on public.planilla_versiones
  for each row execute function public.impedir_version_modificada();

-- ---------------------------------------------------------------------------
--  4. RLS
-- ---------------------------------------------------------------------------
alter table public.planilla_versiones      enable row level security;
alter table public.planilla_observaciones  enable row level security;

-- --- Versiones: el aspirante ve las suyas ---
drop policy if exists versiones_leer_propias on public.planilla_versiones;
create policy versiones_leer_propias
  on public.planilla_versiones for select to authenticated
  using (
    aspirante_id in (select id from public.aspirantes where user_id = auth.uid())
    or public.is_admin()
  );

-- --- Versiones: el aspirante crea las suyas, y SÓLO en estado de envío ---
--
-- **El `with check` es la pieza que impide el auto-ascenso.** Sin acotar el
-- estado, un aspirante podría insertar directamente una versión `APROBADA` por
-- PostgREST y saltarse el trámite entero. La política no confía en Fastify.
drop policy if exists versiones_crear_propias on public.planilla_versiones;
create policy versiones_crear_propias
  on public.planilla_versiones for insert to authenticated
  with check (
    estado in ('ENVIADA', 'REENVIADA')
    and aprobada_at is null
    and approved_by is null
    and aspirante_id in (select id from public.aspirantes where user_id = auth.uid())
  );

-- --- Versiones: el admin gestiona y transiciona ---
drop policy if exists versiones_admin_all on public.planilla_versiones;
create policy versiones_admin_all
  on public.planilla_versiones for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- --- Observaciones: el aspirante lee las de sus versiones ---
drop policy if exists observaciones_leer_propias on public.planilla_observaciones;
create policy observaciones_leer_propias
  on public.planilla_observaciones for select to authenticated
  using (
    public.is_admin()
    or version_id in (
      select v.id from public.planilla_versiones v
       where v.aspirante_id in (select id from public.aspirantes where user_id = auth.uid())
    )
  );

-- --- Observaciones: SÓLO el admin observa ---
drop policy if exists observaciones_crear_admin on public.planilla_observaciones;
create policy observaciones_crear_admin
  on public.planilla_observaciones for insert to authenticated
  with check (public.is_admin());

-- El docente NO recibe ninguna política: queda fuera por AUSENCIA de concesión,
-- que es la forma correcta de excluirlo — no con una política que lo niegue.

-- ---------------------------------------------------------------------------
--  5. Autocomprobación
-- ---------------------------------------------------------------------------
--
-- Un `create trigger` que no dispara porque el nombre de la columna está mal
-- escrito NO falla: simplemente nunca se ejecuta, y el síntoma aparece como «la
-- protección no protege» en producción. La migración `202609240002` ya verifica
-- su propio cableado por esta razón; aquí se hace lo mismo.
do $autocomprobacion$
declare
  v_tablas   integer;
  v_trigger  integer;
  v_politicas integer;
begin
  select count(*) into v_tablas
    from information_schema.tables
   where table_schema = 'public'
     and table_name in ('planilla_versiones', 'planilla_observaciones');
  if v_tablas <> 2 then
    raise exception 'Faltan tablas: se esperaban 2, hay %', v_tablas;
  end if;

  -- Que el trigger exista Y que apunte al evento correcto.
  select count(*) into v_trigger
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
   where c.relname = 'planilla_versiones'
     and t.tgname = 'planilla_versiones_inmutables'
     and not t.tgisinternal;
  if v_trigger <> 1 then
    raise exception 'El trigger de inmutabilidad no está cableado';
  end if;

  select count(*) into v_politicas
    from pg_policies
   where schemaname = 'public'
     and tablename in ('planilla_versiones', 'planilla_observaciones');
  if v_politicas < 5 then
    raise exception 'Faltan políticas RLS: se esperaban 5, hay %', v_politicas;
  end if;
end
$autocomprobacion$;

-- ---------------------------------------------------------------------------
--  6. Nota para el bloque siguiente
-- ---------------------------------------------------------------------------
--
-- `supabase/eliminar-cuenta.mjs` **fallará** al borrar una ficha con versiones:
-- es el `on delete restrict` haciendo su trabajo. **NO se modifica aquí** — el
-- script tendrá que decidir explícitamente qué hacer (avisar, o borrar las
-- versiones primero con una confirmación aparte). Un trámite aprobado no debería
-- desaparecer por borrar un usuario.
