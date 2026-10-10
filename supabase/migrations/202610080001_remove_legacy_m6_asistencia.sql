-- 202610080001 — Retirar el placeholder legado de asistencia
--
-- 202609120002 sembró m6_asistencia como reserva del catálogo.
-- La implementación real de asistencia fue creada posteriormente como
-- m7_asistencia (202609260002). Mantener ambas filas deja 11 módulos para un
-- catálogo funcional de 10 y hace que el cPanel muestre una capacidad muerta.
--
-- La clave m6_asistencia no tiene referencias funcionales actuales en API/UI;
-- las rutas y dashboards de asistencia usan m7_asistencia. Se elimina sólo la
-- fila de catálogo obsoleta. El trigger de auditoría conserva evidencia de la
-- eliminación en config_audit_log.

do $$
declare
  v_existe_m7 boolean;
begin
  select exists(select 1 from public.system_modules where clave = 'm7_asistencia')
    into v_existe_m7;

  if not v_existe_m7 then
    raise exception 'No se puede retirar m6_asistencia: m7_asistencia no existe.';
  end if;

  delete from public.system_modules
   where clave = 'm6_asistencia';

  if exists(select 1 from public.system_modules where clave = 'm6_asistencia') then
    raise exception 'm6_asistencia sigue presente después de la limpieza.';
  end if;
end;
$$;
