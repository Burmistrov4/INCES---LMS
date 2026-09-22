-- ============================================================================
-- M6 / Fase 4: encender el módulo m6_aula_virtual
-- ============================================================================
--
-- La migración 202609220001 sembró la clave con `habilitado = false` a
-- propósito: mientras no existiera el lado del docente (crear anuncio/tarea,
-- publicar, calificar/devolver), encender habría dejado un ítem de menú con un
-- bucle cojo detrás —el patrón de R-22. Con el Centro de Mando del Docente
-- construido y verificado (commit 495c1d2) y el servicio de contenido cableado
-- en producción (7bbcc46), el recorrido docente→alumno es demostrable de punta
-- a punta, así que se enciende.
--
-- No se toca la semilla de 001: la bandera vive en `system_modules.habilitado`
-- y es una fila, no una columna nueva. `update ... where clave =` es idempotente
-- y no choca con la semilla (`on conflict do nothing` de 001 no la revierte).

update public.system_modules
  set habilitado = true
  where clave = 'm6_aula_virtual';
