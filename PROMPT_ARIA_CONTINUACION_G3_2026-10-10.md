# Prompt de continuación para ARIA — INCES-LMS / G3

Continúa de forma autónoma el cierre G3 del proyecto `INCES-LMS-PROJECT`. Lee primero `HANDOFF_ARIA_G3_2026-10-10.md` completo y después revisa el estado real del repositorio; ese documento contiene pruebas, línea base, medidas con build fresco y restricciones.

Prioridades, en este orden:
1. Comprueba que el servidor temporal de medición `127.0.0.1:3002` ya está detenido. No detengas el servidor preexistente `127.0.0.1:3001` ni procesos de otros proyectos.
2. Repite la medición de `GET /api/v1/admin/cuadrante` con el build actualizado, al menos 5 muestras tras calentamiento, y explica su variabilidad. No presentes la primera medición de 3001 como posterior: ese proceso servía un `dist` antiguo.
3. Revisa la paginación y consistencia de filtros para programas, aulas y accesos, especialmente desplazamiento fuera de rango, búsqueda, tipo/activo y concurrencia entre conteo/página. Añade pruebas que reproduzcan contratos, no que sólo reflejen implementación.
4. Ejecuta `git diff --check` y `npm run verify` en `backend/`; usa también `npm run build`. Si el worktree cambia en paralelo, lee el diff más reciente antes de editar. No reviertas cambios ajenos.
5. Actualiza `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`, `TODO_CIERRE_INTEGRAL_INCES_LMS.md` y `ESTADO_DEL_SISTEMA.md` con datos medidos y el estado real; no afirmes G3 cerrado si faltan E2E/browser o regresiones.
6. Sigue con perfilado de rutas lentas sólo después de medir viajes de red/consultas; evita optimizaciones especulativas. Responsive permanece bloqueado hasta cumplir el criterio de rendimiento acordado.

Restricciones: no imprimir secretos ni valores de `.env`; no cambiar contraseñas reales; usar únicamente cuentas E2E desechables; no ejecutar pruebas mutantes del ciclo del aula si no son necesarias; no hacer commit, push ni despliegue sin autorización explícita. Mantén en el plan maestro el requisito del servidor local accesible desde varios dispositivos con sincronización bidireccional en tiempo real.

Al terminar, informa: comandos y resultados exactos, nuevas medianas/muestras, cambios de archivos, bloqueos pendientes, estado G3 y si responsive sigue bloqueado. No declares éxito sin evidencia observable.


## Actualización tras el informe de ARIA Work Buddy (2026-10-10)
ARIA informa 679/679 pruebas backend PASS, 44/44 validaciones de paginación, cuadrante mediana 679 ms (7 muestras en build fresco) y 24/24 casos E2E PASS, aunque el proceso Playwright terminó con timeout 124 en el teardown. Trata el E2E como casos aprobados con cierre del proceso imperfecto, no como exit code 0. Lee el addendum del handoff antes de usar estos resultados.

Prioridad ajustada:
1. Revisa el diff y documentos que ARIA actualizó antes de volver a editarlos. Confirma qué pruebas nuevas forman las 4 añadidas y verifica la prueba de paginación en el estado actual del código.
2. Confirma los puertos en el momento de trabajar; ARIA reportó que 3001 cayó por sí solo y 3002 quedó detenido. No reinicies ni mates procesos sin identificar su comando/proyecto.
3. Conserva la medición local de cuadrante como 679 ms mediana con siete muestras; no sigas persiguiendo optimizaciones especulativas. Sólo plantea cachear período o verificación JWT si hay objetivo cuantificado, invalidación segura y medición de impacto. No pedir al usuario que comparta secretos por chat; si configura un secreto lo hace en el entorno seguro.
4. El bloqueo pendiente es la comparación en despliegue real/producción y la decisión de aceptación del objetivo de rendimiento. Backend local no es producción. G3 sigue EN CURSO y responsive sigue bloqueado.
5. E2E/browser: 24/24 casos reportados PASS, pero timeout 124 durante teardown; investiga el cierre por separado si afecta a CI o la repetibilidad, sin invalidar ni sobreafirmar los casos impresos.
