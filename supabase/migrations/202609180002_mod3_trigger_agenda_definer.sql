-- ============================================================================
-- MÓDULO 3 — CORRECCIÓN: los envoltorios de trigger deben ser `security definer`
-- ============================================================================
--
-- QUÉ ESTABA ROTO
-- ---------------
-- La migración `202609180001` dejó los dos envoltorios de trigger
-- (`teacher_duties_exigir_agenda` y `schedule_slots_exigir_agenda`) como
-- `security invoker`, y a la vez revocó el EXECUTE de
-- `public.exigir_agenda_libre()` a `public`, `anon` y `authenticated`.
--
-- Con `security invoker`, el envoltorio corre con los privilegios de quien
-- escribe. Y quien escribe es un `admin` autenticado, que **no** tiene EXECUTE
-- sobre la función delegada. Resultado: cualquier alta o edición de guardia o
-- de clase reventaba con
--
--     ERROR: 42501: permission denied for function exigir_agenda_libre
--     CONTEXT: PL/pgSQL function teacher_duties_exigir_agenda() line 9 at PERFORM
--
-- Es decir: el módulo entero era inoperable para un usuario real, y la
-- protección anti-colisión nunca llegaba a evaluarse.
--
-- POR QUÉ LA BATERÍA DE PRUEBAS NO LO VIO
-- ---------------------------------------
-- Porque las pruebas del trigger se ejecutaban como el **dueño** de las tablas
-- (`postgres`), y el dueño se salta la comprobación de privilegios de función.
-- Un doble que corre con más permisos que el usuario real no reproduce al
-- usuario real. La prueba que faltaba —y que ahora existe en la sección 14.8 de
-- `supabase/tests/validate.mjs`— escribe **como `authenticated` con los claims
-- de un admin**, que es exactamente lo que hace el backend con el JWT del
-- llamante.
--
-- LA CORRECCIÓN
-- -------------
-- Los envoltorios pasan a `security definer`. Así:
--
--   * La comprobación de EXECUTE de `exigir_agenda_libre()` se hace contra el
--     dueño (que sí lo tiene) y no contra el llamante.
--   * `exigir_agenda_libre()` ya era `security definer`, así que el chequeo
--     sigue viendo TODA la agenda y no sólo la del llamante. Con `invoker`, la
--     RLS de `teacher_duties` habría dejado ciego el chequeo para un docente.
--
-- `security definer` NO amplía lo que el llamante puede escribir: la RLS de la
-- tabla se evalúa aparte, en el ejecutor de la sentencia, y sigue exigiendo
-- `is_admin()`. El envoltorio sólo comprueba y no devuelve dato alguno.
-- Tampoco es invocable a mano: PostgreSQL no permite llamar directamente a una
-- función que devuelve `trigger`.
--
-- Se mantiene el `revoke` de `exigir_agenda_libre()`: la única puerta de entrada
-- es el trigger. `set search_path` sigue fijo, que en una función `definer` no es
-- opcional.
--
-- NO se toca `202609180001`: una migración ya aplicada no se edita nunca.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. Envoltorio de las guardias
-- ---------------------------------------------------------------------------
create or replace function public.teacher_duties_exigir_agenda()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Una guardia archivada no ocupa a nadie. Sin esta salida temprana, desactivar
  -- una guardia la seguiría bloqueando el hueco.
  if not new.is_active then
    return new;
  end if;

  perform public.exigir_agenda_libre(
    new.period_code,
    new.day_of_week,
    new.block,
    new.teacher_id,
    new.classroom_id,
    'teacher_duties',
    new.id
  );

  return new;
end;
$$;

comment on function public.teacher_duties_exigir_agenda() is
  'Trigger anti-colisión de las guardias. `security definer` a propósito: como `invoker` el llamante no tiene EXECUTE sobre la función delegada y el alta fallaba con 42501. Ver 202609180002.';


-- ---------------------------------------------------------------------------
-- 2. Envoltorio del cuadrante
-- ---------------------------------------------------------------------------
create or replace function public.schedule_slots_exigir_agenda()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo text;
begin
  if not new.is_active then
    return new;
  end if;

  -- El período no está en esta fila: se resuelve por la sección. Si la sección
  -- no existe, la FK lo habría impedido igualmente; se comprueba aquí para no
  -- llamar al chequeo con un período nulo, que lo dejaría ciego.
  select s.period_code into v_periodo
  from public.sections s
  where s.id = new.section_id;

  if v_periodo is null then
    raise exception 'La sección % no existe.', new.section_id
      using errcode = '23503';
  end if;

  perform public.exigir_agenda_libre(
    v_periodo,
    new.day_of_week,
    new.block,
    new.teacher_id,
    new.classroom_id,
    'schedule_slots',
    new.id
  );

  return new;
end;
$$;

comment on function public.schedule_slots_exigir_agenda() is
  'Trigger anti-colisión del cuadrante. `security definer` por la misma razón que el de las guardias: ver 202609180002.';


-- ---------------------------------------------------------------------------
-- 3. Recordatorio del límite
-- ---------------------------------------------------------------------------
-- La delegada sigue sin EXECUTE para nadie. Si algún día alguien "arregla" un
-- 42501 concediendo EXECUTE a `authenticated`, abriría dos puertas que no se
-- quieren abrir: consultar la agenda ajena como oráculo (¿está ocupado el
-- martes a las 8?) y tomar el `pg_advisory_xact_lock` a voluntad. El camino
-- correcto es el de arriba: `security definer` en el envoltorio.
revoke all on function public.exigir_agenda_libre(text, smallint, smallint, uuid, uuid, text, uuid)
  from public, anon, authenticated;
