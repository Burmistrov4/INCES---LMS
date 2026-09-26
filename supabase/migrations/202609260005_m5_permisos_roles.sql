-- ===========================================================================
--  Módulo 5 — Archivos: la lista blanca de roles volvía el módulo INSERVIBLE
-- ===========================================================================
--  Qué hace
--  --------
--  Deja `system_modules.roles_permitidos = '{}'` (lista vacía) en la fila
--  `m5_archivos`. No toca `habilitado`, que sigue en `true`.
--
--  Por qué: un 403 que dejaba fuera a quien usa el módulo
--  -----------------------------------------------------
--  Medido el 2026-09-26 contra la nube (`select * from system_modules`):
--
--      clave          habilitado  roles_permitidos  updated_at
--      m5_archivos    true        ["admin"]         2026-09-22T17:43:58Z
--
--  La semilla de `202609120002` lo creó con `'{}'`, y `202609210002` —la
--  migración que ENCENDIÓ el módulo y le puso la guardia a sus rutas— dice de él,
--  literalmente:
--
--      «No toca `roles_permitidos`, que sigue en `'{}'` (lista vacía = visible
--       para todos los roles: el estudiante sube sus entregas y el docente sus
--       guías, y los dos necesitan el módulo).»
--
--  Y `backend/src/http/plugins/modulos.ts` usa esa columna como **lista blanca de
--  la API**, no sólo como filtro del menú:
--
--      if (modulo.rolesPermitidos.length > 0) {
--        if (rol === null || !modulo.rolesPermitidos.includes(rol)) {
--          throw ErrorApi.prohibido('MODULO_NO_AUTORIZADO', ...);
--        }
--      }
--
--  Las dos piezas juntas dejaban el módulo entero en 403 para quien de verdad lo
--  usa: el estudiante que sube su entrega (el gestor documental que el aula
--  virtual abre al pulsar una tarea) y el docente que sube su guía. Las seis
--  rutas de `rutas/archivos.ts` llevan `exigirModulo('m5_archivos')` desde el
--  2026-09-19, así que la guardia estaba y la lista blanca la volvía un rechazo.
--
--  El `updated_at` es la prueba de procedencia: **2026-09-22T17:43:58Z**, tres
--  días después de la semilla y uno después del encendido. Ninguna migración del
--  repositorio escribe esa columna para M5 —el libro mayor tiene las 26
--  aplicadas, 0 pendientes y 0 con deriva—, así que el valor se puso **a mano**,
--  desde el cPanel o la consola de Supabase. Es exactamente el defecto que D11
--  describe: un `update` suelto deja el estado real indistinguible del estado del
--  repositorio, y aquí además rompió un módulo sin que nada lo dijera.
--
--  Por qué esto no es «cambiar una decisión de producto»
--  -----------------------------------------------------
--  No se afloja una restricción que alguien quisiera: se **restaura el valor que
--  dos migraciones documentan como correcto** y que exige el contrato de M5
--  (`archivos.test.ts` ejercita el camino del alumno con su token). Con la lista
--  en `["admin"]` el módulo no puede cumplir su contrato: no es una opinión, es
--  un 403.
--
--  Qué NO hace
--  -----------
--  No enciende ni apaga el módulo. No toca `m7_asistencia`, que tiene su propia
--  lista (`['docente','admin']`) **sí registrada en el libro mayor**
--  (`202609260002`) y hoy es inofensiva porque sus rutas **no** llevan guardia de
--  módulo; queda anotada como trampa medida en `ESTADO_DEL_SISTEMA.md`, porque
--  ponerle la guardia tal cual daría 403 al estudiante en `/marcar` — que es
--  justamente quien marca.
-- ===========================================================================

do $$
declare
  v_afectadas int;
  v_roles text[];
  v_habilitado boolean;
begin
  update public.system_modules
     set roles_permitidos = '{}'::text[]
   where clave = 'm5_archivos';

  get diagnostics v_afectadas = row_count;

  -- Si la fila no existe, el `update` no habría hecho nada y el módulo seguiría
  -- con la lista blanca sin que nadie se enterara. Fallar aquí convierte un
  -- silencio en un error que nombra la causa: falta la semilla de `202609120002`.
  if v_afectadas = 0 then
    raise exception
      'No se encontró la fila m5_archivos en system_modules. '
      'Falta aplicar la semilla de 202609120002_phase3_admin_core.sql.'
      using errcode = '23514';
  end if;

  select roles_permitidos, habilitado
    into v_roles, v_habilitado
    from public.system_modules
   where clave = 'm5_archivos';

  -- Autocomprobación: la guardia necesita las DOS cosas a la vez. Si el módulo
  -- quedara apagado, las seis rutas responderían 403 MODULO_DESHABILITADO; si
  -- quedara con lista blanca, 403 MODULO_NO_AUTORIZADO para el alumno. Desde el
  -- cliente las dos se ven igual y significan cosas distintas, así que se
  -- comprueban por separado.
  if v_roles <> '{}'::text[] then
    raise exception
      'm5_archivos quedó con roles_permitidos = %, y debe quedar vacío.', v_roles
      using errcode = '23514';
  end if;

  if v_habilitado is not true then
    raise exception
      'm5_archivos quedó apagado; esta migración no debía tocar `habilitado`.'
      using errcode = '23514';
  end if;
end $$;

-- El comentario de la tabla lo reescribió `202609210002` diciendo que la guardia
-- sólo estaba en M5 y que en M1–M4 la bandera era decorativa. Las dos mitades
-- envejecieron: desde `addb2d4` (2026-09-26) M2, M3 y M4 también la llevan. Se
-- vuelve a escribir para que describa el estado real, y se le añade la lección de
-- esta migración, que es la que más caro costó.
comment on table public.system_modules is
  'Interruptores de los módulos del sistema. `habilitado` los enciende y apaga desde el Administrador Maestro; `roles_permitidos` vacío significa visible para todos los roles. **OJO: `roles_permitidos` no es sólo un filtro del menú** — `comprobarModulo()` lo usa como lista blanca de la API, así que una lista que excluya al rol que usa el módulo deja el módulo entero en 403 MODULO_NO_AUTORIZADO. Pasó con `m5_archivos` (lista `["admin"]` puesta a mano el 2026-09-22, con las seis rutas ya guardadas: el estudiante y el docente no podían subir nada); lo corrige `202609260005`. La API comprueba `habilitado` con `exigirModulo()` en las rutas de M2, M3, M4, M5 y M6; `m1_onboarding` y `rutas/secciones.ts` no la comprueban a propósito.';
