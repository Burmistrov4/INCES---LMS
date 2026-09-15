-- 202609180003_r06_periodo_sa26_2_y_modulos.sql
-- ---------------------------------------------------------------------------
-- R-06 (refinada por R-12): se fija la nomenclatura del lapso vigente en
-- 'SA26-2' y se encienden los módulos M2 (Currículo y Pensum) y M3 (Cuadrante
-- y Horarios), que ya están construidos y verificados de extremo a extremo.
--
-- Orden de operaciones OBLIGATORIO:
--   1) Garantizar que 'SA26-2' existe en academic_periods ANTES de tocar
--      system_settings.periodo_activo. La guarda exigir_periodo_registrado()
--      (trigger BEFORE UPDATE/INSERT sobre system_settings) rechaza cualquier
--      periodo_activo que no nombre un lapso registrado; si la fila de
--      academic_periods no existe cuando se ejecuta el UPDATE, la migración
--      entera falla (R-06/R-12: convertir la divergencia silenciosa en error).
--   2) Insertar o renombrar academic_periods según corresponda.
--   3) Fijar periodo_activo = 'SA26-2' (ya garantizado en el paso anterior, en
--      la misma transacción).
--   4) Encender m2_curriculo y m3_cuadrante en system_modules.
-- ---------------------------------------------------------------------------

do $$
declare
  v_nuevo constant text := 'SA26-2';
  v_viejo constant text := '2026-1';
  v_hijos integer := 0;
begin
  -- 1) ¿El lapso vigente real ya está registrado?
  if exists (select 1 from public.academic_periods where code = v_nuevo) then
    update public.academic_periods set is_active = true where code = v_nuevo;
  else
    -- ¿Hay datos (secciones, guardias) que citan el código obsoleto?
    select count(*) into v_hijos
    from (
      select 1 from public.teacher_duties td where td.period_code = v_viejo
      union all
      select 1 from public.sections s where s.period_code = v_viejo
    ) q;

    if v_hijos > 0 then
      -- No se puede renombrar sin romper las FK: se inserta el vigente y se
      -- deja el viejo como histórico (is_active = false).
      insert into public.academic_periods (code, name, is_active)
      values (v_nuevo, 'Lapso SA26-2', true);
      update public.academic_periods set is_active = false where code = v_viejo;
    else
      -- Renombrar el sembrado para no duplicar la fila (es semilla, 0 hijos).
      update public.academic_periods
      set code = v_nuevo, name = 'Lapso SA26-2'
      where code = v_viejo;
    end if;
  end if;

  -- 2) Fijar el período activo. La guarda exige que 'SA26-2' ya exista: lo
  --    acabamos de garantizar en el paso anterior, dentro de la misma transacción.
  update public.system_settings
  set valor = to_jsonb(v_nuevo)
  where clave = 'periodo_activo';
end $$;

-- Encender M2 y M3: ambos módulos están construidos, verificados y deben quedar
-- disponibles desde el Administrador Maestro. m0_cpanel y m1_onboarding ya
-- nacieron habilitados; m4…m8 siguen apagados hasta que se construyan.
update public.system_modules
  set habilitado = true
  where clave in ('m2_curriculo', 'm3_cuadrante');
