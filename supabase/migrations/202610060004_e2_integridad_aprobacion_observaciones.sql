-- ============================================================================
-- E-2 · Integridad final de aprobación y observaciones
-- ============================================================================
--
-- Evidencia que justifica esta migración (Bloque 6.4, JWT reales):
--
--   R2/R3/R4: una fila APROBADA permitía modificar approved_by/aprobada_at.
--   O2:       OBSERVADA -> OBSERVADA devolvía 200 y dejaba la fila OBSERVADA.
--   OBSERVACIONES:
--             admin podía insertar observaciones sobre OBSERVADA y APROBADA.
--
-- No se modifican migraciones históricas 0001/0002/0003.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Una APROBADA queda completamente congelada.
-- ---------------------------------------------------------------------------
create or replace function public.impedir_version_modificada()
returns trigger
language plpgsql
as $$
declare
  v_permitida boolean;
begin
  -- El contenido histórico nunca cambia.
  if new.aspirante_id   is distinct from old.aspirante_id
     or new.numero         is distinct from old.numero
     or new.datos_snapshot is distinct from old.datos_snapshot
     or new.enviada_at     is distinct from old.enviada_at
     or new.created_at     is distinct from old.created_at then
    raise exception 'Una versión formalizada no puede alterar su contenido histórico'
      using errcode = '23514';
  end if;

  -- Una versión APROBADA es inmutable: ni estado ni auditoría de aprobación
  -- pueden cambiar después de aprobar.
  if old.estado = 'APROBADA' then
    if new.estado is distinct from old.estado
       or new.aprobada_at is distinct from old.aprobada_at
       or new.approved_by is distinct from old.approved_by then
      raise exception 'Una versión APROBADA es inmutable'
        using errcode = '23514';
    end if;
    return new;
  end if;

  -- OBSERVADA no puede ser "observada" nuevamente.
  if old.estado = 'OBSERVADA'
     and new.estado = 'OBSERVADA' then
    raise exception 'Una versión OBSERVADA debe reenviarse antes de otra observación'
      using errcode = '23514';
  end if;

  -- Las cuatro transiciones legales del contrato.
  if new.estado is distinct from old.estado then
    v_permitida :=
         (old.estado = 'ENVIADA'   and new.estado = 'OBSERVADA')
      or (old.estado = 'ENVIADA'   and new.estado = 'APROBADA')
      or (old.estado = 'OBSERVADA' and new.estado = 'REENVIADA')
      or (old.estado = 'REENVIADA' and new.estado = 'APROBADA');

    if not v_permitida then
      raise exception 'Transición de planilla no permitida: % → %', old.estado, new.estado
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.impedir_version_modificada() is
  'E-2: congela contenido histórico, enumera transiciones legales y hace APROBADA inmutable; impide OBSERVADA→OBSERVADA.';

-- ---------------------------------------------------------------------------
-- 2. Una observación sólo puede crearse sobre una versión ENVIADA.
-- ---------------------------------------------------------------------------
drop policy if exists observaciones_crear_admin on public.planilla_observaciones;

create policy observaciones_crear_admin
  on public.planilla_observaciones
  for insert
  to authenticated
  with check (
    public.is_admin()
    and exists (
      select 1
        from public.planilla_versiones v
       where v.id = version_id
         and v.estado = 'ENVIADA'
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Autocomprobación estructural.
-- ---------------------------------------------------------------------------
do $autocomprobacion$
declare
  v_trigger integer;
  v_obs_insert integer;
  v_forall integer;
begin
  select count(*) into v_trigger
    from information_schema.triggers
   where event_object_schema = 'public'
     and event_object_table = 'planilla_versiones'
     and trigger_name = 'planilla_versiones_inmutables';

  if v_trigger <> 1 then
    raise exception 'No se encontró exactamente el trigger planilla_versiones_inmutables';
  end if;

  select count(*) into v_obs_insert
    from pg_policies
   where schemaname = 'public'
     and tablename = 'planilla_observaciones'
     and policyname = 'observaciones_crear_admin'
     and cmd = 'INSERT';

  if v_obs_insert <> 1 then
    raise exception 'No quedó exactamente una política INSERT para observaciones_crear_admin';
  end if;

  select count(*) into v_forall
    from pg_policies
   where schemaname = 'public'
     and tablename in ('planilla_versiones', 'planilla_observaciones')
     and cmd = 'ALL';

  if v_forall <> 0 then
    raise exception 'Quedan % políticas FOR ALL en las tablas E-2', v_forall;
  end if;
end
$autocomprobacion$;
