-- E1 follow-up: 0007 correctly stopped the invalid transition with RETURN,
-- but its RETURN QUERY omitted approved_by from the declared 9-column result.
-- This migration fixes only that result-shape defect. No historical migration
-- is edited.

create or replace function public.observar_planilla_atomico(
  p_version_id uuid,
  p_admin_id uuid,
  p_motivo text
)
returns table (
  id uuid,
  aspirante_id uuid,
  numero integer,
  estado text,
  datos_snapshot jsonb,
  enviada_at timestamptz,
  aprobada_at timestamptz,
  approved_by uuid,
  created_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_version public.planilla_versiones%rowtype;
begin
  if auth.uid() is null or p_admin_id is distinct from auth.uid() or not public.is_admin() then
    raise exception 'No autorizado para observar la planilla.'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de observación no puede estar vacío.'
      using errcode = '23514';
  end if;

  update public.planilla_versiones as pv
     set estado = 'OBSERVADA'
   where pv.id = p_version_id
     and pv.estado = 'ENVIADA'
  returning pv.* into v_version;

  if not found then
    return;
  end if;

  insert into public.planilla_observaciones (
    version_id,
    observada_por,
    motivo
  ) values (
    p_version_id,
    auth.uid(),
    btrim(p_motivo)
  );

  return query
  select
    v_version.id,
    v_version.aspirante_id,
    v_version.numero,
    v_version.estado,
    v_version.datos_snapshot,
    v_version.enviada_at,
    v_version.aprobada_at,
    v_version.approved_by,
    v_version.created_at;
end;
$$;

revoke all on function public.observar_planilla_atomico(uuid, uuid, text)
  from public, anon, authenticated;

grant execute on function public.observar_planilla_atomico(uuid, uuid, text)
  to authenticated;

comment on function public.observar_planilla_atomico(uuid, uuid, text) is
  'Transición ENVIADA->OBSERVADA y creación de su observación en una sola transacción. Exige JWT de admin y p_admin_id = auth.uid(); si la versión ya no está ENVIADA, retorna sin filas para que la capa de dominio traduzca el conflicto a 409.';

do $$
begin
  if not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'observar_planilla_atomico'
       and pg_get_function_identity_arguments(p.oid) = 'p_version_id uuid, p_admin_id uuid, p_motivo text'
  ) then
    raise exception 'No se creó observar_planilla_atomico.';
  end if;
end;
$$;
