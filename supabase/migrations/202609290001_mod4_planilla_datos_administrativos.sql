-- ============================================================================
--  INCES LMS — M4: el número de la planilla deja de ser el primer paso del
--                formulario y pasa a ser el último
--  Archivo: 202609290001_mod4_planilla_datos_administrativos.sql
--  Aplica con: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  El formulario de inscripción del aspirante abre con un paso llamado
--  «Cabecera» cuyo único campo es «N° preimpreso de la planilla». Es un dato que
--  el aspirante **no puede tener** si se inscribe desde su casa: el número lo
--  imprime el CFS en la planilla de papel. Preguntarlo en el primer paso pone el
--  papel por delante del trámite y contradice el objetivo del módulo —que
--  cualquiera se inscriba desde donde esté, sin ir a La Isabelica.
--
--  Este archivo mueve ese campo al final del formulario, a un grupo nuevo
--  «Datos administrativos», sin tocar una línea de Flutter.
--
--  POR QUÉ BASTA CON UNA MIGRACIÓN
--  -------------------------------
--  El Stepper de `lib/screens/aspirante_form_screen.dart` no tiene los pasos
--  escritos a mano: los construye desde el catálogo —`_grupos = catalogo.grupos`
--  (línea 182) y un `for` sobre esa lista (líneas 928-942)—, así que **un grupo
--  del catálogo es un paso**. Y `CatalogoInscripcion.grupos`
--  (`lib/models/inscripcion_campo.dart:384`) arma los grupos **recorriendo los
--  campos**, en orden de `orden`: un grupo sólo existe si tiene al menos un
--  campo. Por eso, al mudarse el único campo de «Cabecera», **el paso desaparece
--  solo** — no hay que borrarlo desde ningún sitio.
--
--  MEDIDO ANTES DE ESCRIBIRLO, NO DEDUCIDO
--  ---------------------------------------
--  Contra la base real, el 2026-09-29:
--
--      inscripcion_campos   44 campos activos, 13 obligatorios, 9 grupos
--
--        orden   10..  10    1 campo(s)  Cabecera
--        orden   20.. 200   19 campo(s)  Datos personales
--        orden  210.. 300   10 campo(s)  Ubicación y contacto
--        orden  310.. 310    1 campo(s)  Familiares
--        orden  320.. 320    1 campo(s)  Misiones
--        orden  330.. 360    4 campo(s)  Formación
--        orden  370.. 380    2 campo(s)  Formación complementaria
--        orden  390.. 430    5 campo(s)  Representante legal
--        orden  440.. 440    1 campo(s)  Propuesta formativa
--
--      numero_preimpreso → grupo 'Cabecera', orden 10, obligatorio false,
--                          activo true
--
--  El catálogo avanza de 10 en 10, así que el siguiente número «natural» sería
--  450. Se usa **900** a propósito: deja un hueco ancho para que los campos que
--  el CFS añada desde el panel —que llevan el `orden` que él escriba— no caigan
--  por accidente entre «Propuesta formativa» y este paso.
--
--  LO QUE NO SE TOCA, Y POR QUÉ
--  ----------------------------
--  · `obligatorio` sigue en `false`. Ya lo estaba, y es justo la condición para
--    que el registro no dependa del papel: `validar_planilla()` sólo exige los
--    campos `activo and obligatorio`, y el validador del formulario
--    (`campo_planilla.dart:257`) sólo devuelve «Campo obligatorio» cuando
--    `campo.obligatorio` es verdadero.
--  · `activo` sigue en `true`. **No se apaga**, aunque apagarlo pareciera la vía
--    corta para quitar el campo del formulario: el renderizador del PDF lee el
--    catálogo **activo** (`repos-supabase.ts:3331`) y la vista de exportación a
--    HACER proyecta `planilla_texto(datos_planilla, 'numero_preimpreso')`
--    (`202609250004_v_exportacion_hacer.sql:218`). Apagarlo lo borraría del PDF
--    emitido y de la exportación: se perdería el dato en vez de reubicarlo.
--  · La `etiqueta` no cambia («N° preimpreso de la planilla»). El dato sigue
--    llamándose igual; lo que cambia es dónde se pregunta.
--
--  NO HAY CORRELATIVO AUTOMÁTICO
--  -----------------------------
--  El sistema **no genera** un número de planilla cuando el campo va vacío: no
--  existe ninguna secuencia ni ningún `max()+1` para esto (medido: cero
--  coincidencias de `correlativ|nextval|auto-genera` en `supabase/`,
--  `backend/src/` y `lib/`). El valor sólo se guarda y lo pinta el PDF; si falta,
--  esa línea sale en blanco, igual que en la planilla de papel. Por eso el texto
--  de ayuda dice «si aún no tienes el número» y **no** promete un código
--  generado: prometerlo sería escribir una interfaz sobre un mecanismo que no
--  existe.
--
--  SEGURIDAD
--  ---------
--  Esta migración corre por la Management API como `postgres`, que no pasa por
--  RLS, y sólo escribe tres columnas de **una** fila. No crea ni cambia permisos,
--  políticas ni funciones: por eso el conteo de funciones y políticas del esquema
--  no varía y `ESTADO_DEL_SISTEMA.md` sólo tiene que subir el de migraciones.
-- ============================================================================

do $$
declare
  v_grupo_previo text;
  v_orden_previo integer;
  v_filas        integer;
  v_restantes    integer;
begin
  -- Precondición. Si el campo no está, esta migración no tiene nada que mover y
  -- hay que mirarlo a mano: darla por aplicada dejaría el formulario como estaba
  -- creyendo que se cambió. Se falla en voz alta en vez de no hacer nada.
  select grupo, orden
    into v_grupo_previo, v_orden_previo
    from public.inscripcion_campos
   where codigo = 'numero_preimpreso';

  if not found then
    raise exception
      'No existe el campo ''numero_preimpreso'' en public.inscripcion_campos: no hay nada que reubicar.'
      using errcode = '23514';
  end if;

  update public.inscripcion_campos
     set grupo = 'Datos administrativos',
         orden = 900,
         ayuda = 'Opcional. Dejar en blanco si aún no tienes el número de la planilla física.'
   where codigo = 'numero_preimpreso';

  get diagnostics v_filas = row_count;

  if v_filas <> 1 then
    raise exception
      'La reubicación tocó % fila(s) y tenía que tocar exactamente 1.', v_filas
      using errcode = '23514';
  end if;

  -- Postcondición. El paso «Cabecera» tiene que haberse quedado sin campos
  -- activos: eso es exactamente lo que hace que desaparezca del Stepper. Si
  -- quedara alguno, la migración no habría logrado lo que su título dice.
  select count(*)
    into v_restantes
    from public.inscripcion_campos
   where grupo = 'Cabecera'
     and activo;

  if v_restantes <> 0 then
    raise exception
      'El grupo ''Cabecera'' todavía tiene % campo(s) activo(s): el paso no desaparecería del formulario.',
      v_restantes
      using errcode = '23514';
  end if;

  raise notice
    'numero_preimpreso: grupo «%» (orden %) → «Datos administrativos» (orden 900). El paso «Cabecera» queda sin campos activos.',
    v_grupo_previo, v_orden_previo;
end $$;

-- NO se comprueba aquí «cuántos grupos hay en total». Sería una aserción contra
-- un número que este archivo no controla: si el CFS añadiera un campo a un grupo
-- nuevo entre la medición y la aplicación, la migración abortaría por un cambio
-- legítimo y sin relación con ella — y un fallo que no señala al culpable cuesta
-- una sesión de depuración. Las dos aserciones de arriba sí son de este archivo:
-- el campo existe, y se movió exactamente una fila.
