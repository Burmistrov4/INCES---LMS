-- ===========================================================================
--  Módulo 5 — Archivos (R2): ENCENDER EL MÓDULO
-- ===========================================================================
--  Qué hace
--  --------
--  Pone `system_modules.habilitado = true` en la fila `m5_archivos`, y sólo eso.
--
--  Por qué existe como migración y no como un `update` a mano
--  ----------------------------------------------------------
--  Por la misma razón que `202609200002` hizo lo propio con M4: el libro mayor
--  (`schema_migrations`) es lo que permite responder «¿qué está aplicado en
--  producción?» sin adivinar. Un `update` suelto por la consola de Supabase deja
--  el estado real indistinguible del estado del repositorio, que es el defecto
--  que produjo D11.
--
--  POR QUÉ EL NOMBRE ES `202609210002` Y NO `202609190001`
--  ------------------------------------------------------
--  El orden de aplicación es **lexicográfico**, así que el nombre es la
--  posición. Dos motivos para no usar la fecha de hoy:
--
--    * `202609190001` **ya está tomado** por `mod4_inscripciones.sql`. Dos
--      archivos con la misma versión rompen el libro mayor, que usa `version`
--      como clave.
--    * Cualquier fecha anterior a `20260921` aplicaría esta migración **antes**
--      que `202609210001_mod5_archivos.sql`, es decir, antes de que la fila
--      `m5_archivos` exista — si existiera. El `raise exception` de abajo lo
--      atraparía, pero el nombre correcto evita el problema en vez de detectarlo.
--
--  Se sigue el precedente de M4 (`202609200001` + `202609200002`): el mismo día
--  del módulo, con `002` para el encendido. La bandera se enciende **después**
--  de que la tabla, las RPC y la semilla de límites estén puestas.
--
--  OJO CON LOS NOMBRES DE COLUMNA
--  ------------------------------
--  La tabla `system_modules` **no** tiene `id` ni `is_enabled`:
--
--      clave        text      -- 'm5_archivos'
--      habilitado   boolean   -- la bandera
--
--  Un `update system_modules set is_enabled = true where id = '...'` falla con
--  `42703` (columna inexistente). Se deja escrito porque es el error que se
--  comete de memoria.
--
--  Qué NO hace
--  -----------
--  No toca `roles_permitidos`, que sigue en `'{}'` (lista vacía = visible para
--  todos los roles: el estudiante sube sus entregas y el docente sus guías, y
--  los dos necesitan el módulo). No toca el orden ni el icono. No toca
--  `m5_max_bytes` ni `m5_max_archivos_por_entidad`, que ya sembró `202609210001`.
--  No enciende `habilitar_sistema_bids`, que es de M4 y sigue APAGADO por
--  decisión de producto.
--
--  Efecto sobre la API
--  -------------------
--  **Ahora sí hace algo, y es el cambio de fondo de este ciclo.** Hasta hoy
--  ninguna ruta del backend comprobaba la bandera del módulo: `exigirModulo()`
--  existía en `src/http/plugins/modulos.ts` y no lo usaba nadie, así que apagar
--  `m5_archivos` desde el cPanel sólo lo ocultaba del menú —el frontend no es
--  una barrera de seguridad—. Con este ciclo las cinco rutas de
--  `src/http/rutas/archivos.ts` llevan la guardia, y la bandera pasa a ser lo
--  que dice ser: un interruptor con efecto real.
--
--  Consecuencia práctica, para que no sorprenda: apagar el módulo desde el panel
--  hace que las cinco rutas respondan **403 `MODULO_DESHABILITADO`** dentro del
--  TTL de la caché de módulos. Y si la fila no existiera, el error sería **404
--  `MODULO_DESCONOCIDO`** y no 403 — `comprobarModulo` distingue «no está
--  registrado» de «está apagado», y confundirlos manda a buscar el problema al
--  sitio equivocado.
--
--  Nota sobre la asimetría: M1–M4 siguen sin guardia, así que su interruptor
--  continúa siendo decorativo. Es deuda conocida y deliberada, no un descuido:
--  M5 es el primer módulo cuyo apagado se puede probar de extremo a extremo, y
--  generalizar la guardia a los otros cuatro es un ciclo propio.
-- ===========================================================================

do $$
declare
  v_afectadas int;
begin
  update public.system_modules
     set habilitado = true
   where clave = 'm5_archivos';

  get diagnostics v_afectadas = row_count;

  -- Si la fila no existe, el `update` no habría hecho nada y el módulo seguiría
  -- apagado sin que nadie se enterara — peor aún: con la guardia ya puesta en las
  -- rutas, la API respondería 404 MODULO_DESCONOCIDO a todo el módulo y el
  -- síntoma aparecería como «M5 no funciona», no como «falta una migración».
  -- Fallar aquí convierte ese silencio en un error que nombra la causa.
  if v_afectadas = 0 then
    raise exception
      'No se encontró la fila m5_archivos en system_modules. '
      'Falta aplicar la semilla de 202609120002_phase3_admin_core.sql.'
      using errcode = '23514';
  end if;
end $$;

-- El comentario de `202609200002` decía, con razón, que la API NO comprobaba
-- esta bandera y que `exigirModulo()` estaba definido y sin usar. Con las rutas
-- de M5 ya guardadas, ese texto es falso y una nota que dice «no se puede»
-- envejece igual de mal que una cifra. Se reescribe para que describa el estado
-- real, incluida la parte que sigue siendo cierta: la guardia sólo está en M5.
comment on table public.system_modules is
  'Interruptores de los módulos del sistema. `habilitado` los enciende y apaga desde el Administrador Maestro; `roles_permitidos` vacío significa visible para todos los roles. La API comprueba esta bandera con `exigirModulo()` en las rutas del módulo 5 (archivos), que responden 403 MODULO_DESHABILITADO al apagarlo; en M1–M4 la bandera todavía la respeta sólo el frontend.';
