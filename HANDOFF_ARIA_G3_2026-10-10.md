# Handoff para ARIA — cierre G3 y rendimiento (2026-10-10)

## Objetivo inmediato
Continuar el cierre G3 del INCES-LMS con evidencia reproducible. No declarar G3 cerrado ni iniciar responsive hasta verificar regresiones y medir las rutas después de los cambios.

## Estado confirmado en esta sesión
- `backend/src/infra/repos-supabase.ts` contiene optimizaciones locales sin commit: `listarProgramas`, `listarAulas` y `listarAcceso` ejecutan recuento y página en paralelo; `rejilla` ejecuta período/aulas/docentes en paralelo y después clases/guardias en paralelo.
- `npm run typecheck`: PASS (exit 0).
- `npx eslint src/infra/repos-supabase.ts`: PASS (exit 0).
- Pruebas focalizadas `test/curriculo-repositorio.test.ts`, `test/cuadrante.test.ts`, `test/inscripciones.test.ts` y `test/admin.test.ts`: PASS, 4 archivos / 159 tests.
- La prueba de búsqueda se actualizó en `backend/test/curriculo-repositorio.test.ts`: página y recuento hacen ambas la consulta `.or(...)`, así que se verifica que las dos usen el mismo filtro. Antes esperaba sólo una llamada.
- `git diff --check` no reportó errores, sólo avisos de conversión LF/CRLF.
- El worktree tiene muchos cambios previos y archivos nuevos de trabajo paralelo. No revertir archivos en bloque ni asumir que todos los cambios pertenecen a esta sesión.

## Línea base ANTES de los cambios recientes
Medición local previa, 3 muestras tras calentamiento; no es producción:

| Endpoint | Mediana previa |
|---|---:|
| `GET /api/v1/admin/cuadrante` | 1155 ms |
| `GET /api/v1/admin/aulas?limite=25` | 897 ms |
| `GET /api/v1/admin/programas?limite=25` | 1020 ms |
| `GET /api/v1/admin/acceso?limite=50` | 961 ms |

Estas cifras son línea base previa. No presentar cifras posteriores ni afirmar mejora cuantificada hasta medir con el servidor cargando el código actualizado.

## Próximas acciones obligatorias
1. Esperar resultado del `npm run verify` completo iniciado en esta sesión. Si falla, aislar y corregir la causa real.
2. Ejecutar `git diff --check` tras las ediciones.
3. Confirmar que `127.0.0.1:3001` usa el código actual. Si hay que reiniciar, identificar sólo el proceso INCES; no detener servicios de Adrialga ni Python.
4. Repetir medición breve de los cuatro endpoints con cuenta E2E de administrador desechable, sin imprimir secretos. Una llamada de calentamiento y al menos 3 muestras por ruta; registrar status HTTP, muestras y mediana. No usar el script de medición amplio que quedó ejecutándose muchos minutos.
5. Validar paginación: primera página, página final, desplazamiento fuera de rango, búsqueda y filtros tipo/activo. El total y la página deben aplicar los mismos filtros. Evitar pruebas que muten el ciclo del aula si no son necesarias.
6. Actualizar `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`, `TODO_CIERRE_INTEGRAL_INCES_LMS.md` y `ESTADO_DEL_SISTEMA.md` sólo después de tener evidencia. Leer el estado más reciente antes de editar documentos que otro agente podría estar modificando.
7. Medir los siguientes endpoints lentos antes de cambiar más repositorios: `admin/cuadrante`, `admin/aulas`, `admin/programas`, `admin/acceso`. Separar tiempo de navegador, HTTP y SQL.
8. Mantener G3 en curso hasta cerrar verificación + mediciones + regresión; responsive sigue bloqueado hasta entonces.

## Guardas
- No commit, push ni despliegue sin autorización explícita.
- No imprimir secretos, tokens ni valores de `.env`.
- No cambiar contraseñas de cuentas reales; usar sólo identidad E2E desechable.
- No revertir trabajo de otros agentes ni limpiar agresivamente el repositorio.
- No perder el requisito del producto: servidor local y acceso desde varios dispositivos con cambios sincronizados en tiempo real.

## Resumen
El typecheck, ESLint, las 159 pruebas focalizadas y la verificación completa (675/675 tests) pasan. Ya hay una primera medición contra build fresco: aulas/programas/acceso mejoran en la muestra pequeña; cuadrante requiere repetir por variabilidad. Trabajo inmediato: confirmar cierre del servidor aislado, repetir cuadrante, revisar paginación y completar E2E/browser antes de cerrar G3.


## Resultados posteriores añadidos el 2026-10-10
- `npm run verify`: **PASS**, exit 0; typecheck + ESLint + **675/675 tests** en 32 archivos. Duración total reportada por la herramienta: 83.90 s.
- Se descubrió que `127.0.0.1:3001` ejecuta `node dist/server.js`; por eso las primeras medidas de comprobación tras editar TypeScript no demostraban el código fuente actualizado. Se compiló con `npm run build` (PASS) y se levantó el artefacto fresco en un puerto aislado `127.0.0.1:3002` para medir sin interrumpir el servicio de 3001.
- Medición del artefacto recién compilado en 3002, cuenta E2E admin, 1 calentamiento + 3 muestras por endpoint; HTTP 200 en todas las muestras:

| Endpoint | Línea base anterior | Mediana con build fresco | Cambio aproximado |
|---|---:|---:|---:|
| `GET /api/v1/admin/cuadrante` | 1155 ms | 1111 ms | -4% (alta variabilidad; repetir antes de concluir) |
| `GET /api/v1/admin/aulas?limite=25` | 897 ms | 556 ms | -38% |
| `GET /api/v1/admin/programas?limite=25` | 1020 ms | 546 ms | -46% |
| `GET /api/v1/admin/acceso?limite=50` | 961 ms | 536 ms | -44% |

Muestras de build fresco: cuadrante `[1111, 1167, 621]` ms (muy variable), aulas `[522, 646, 556]`, programas `[532, 824, 546]`, acceso `[820, 536, 505]`. Es una medición local pequeña, no un benchmark de producción. Repetir cuadrante con al menos 5 muestras y confirmar estabilidad.
- La primera medición contra puerto 3001 fue con `dist` antiguo y **no** debe usarse como medida posterior; queda explícitamente descartada.
- El servidor aislado de medición en puerto 3002 se creó sólo para este diagnóstico; detenerlo al terminar la sesión si sigue vivo. No detener el servicio preexistente de INCES en 3001.

## Siguiente paso recomendado a ARIA
Verificar el proceso 3002 apagado, repetir cuadrante con muestras adicionales si es viable, y registrar los datos en la auditoría. Luego inspeccionar si `rejilla` está dominada por las consultas de clases/guardias o por las tres lecturas iniciales; medir cada tramo sin alterar datos. No declarar G3 cerrado sólo por estos resultados: falta revisión de paginación y pruebas E2E/browser post-build.


## Addendum — informe posterior de ARIA Work Buddy (2026-10-10; reportado por ARIA, no reejecutado independientemente en esta comprobación)

ARIA informa que continuó la validación y actualizó `MEMORY.md` de forma aditiva. Sus resultados declarados:
- `GET /api/v1/admin/cuadrante` sobre build fresco en 3002: calentamiento + 7 muestras `[672, 713, 712, 681, 679, 646, 665]` ms; mediana declarada 679 ms, rango 646–713 ms (67 ms). ARIA considera estable esta serie. Es la referencia más reciente; sustituye la conclusión provisional de alta variabilidad de las tres muestras iniciales, pero conservar la serie inicial como histórico.
- Paginación/filtros: `validar-paginacion.mjs` reportó 44 OK / 0 fallos para usuarios, programas, aulas y accesos. `curriculo-repositorio.test.ts` reportó tres pruebas añadidas sobre consistencia de consulta de recuento/página, desplazamiento fuera de rango y página dentro del total sin filas, con control negativo.
- Verificación declarada: `git diff --check`, `npx tsc --noEmit`, ESLint, `npm run verify` con 679/679 (675 anteriores + 4 nuevas) y `npm run build`, todos PASS.
- E2E/browser: 24/24 casos imprimieron PASS con build web actual redirigido a backend 3002. El proceso finalizó con timeout 124 durante el teardown conocido (~10 minutos); por tanto registrar como **24/24 casos reportados PASS, cierre del proceso/teardown no limpio**, no como ejecución con exit code 0.
- ARIA reporta que `3002` quedó detenido. Reporta también que `3001` se cayó por sí solo durante su sesión; no volver a asumir que el servicio sigue vivo sin comprobarlo.
- Archivos que ARIA dice haber actualizado: `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md`, `TODO_CIERRE_INTEGRAL_INCES_LMS.md`, `ESTADO_DEL_SISTEMA.md`, `AGENT_START_HERE.md`, `backend/test/curriculo-repositorio.test.ts`, `backend/src/infra/repos-supabase.ts`, `backend/src/http/plugins/autenticacion.ts` y `MEMORY.md`.

### Estado revisado después del informe de ARIA
- G3 permanece **EN CURSO**, no cerrado: falta validar en un entorno de producción/despliegue real la latencia de cuadrante y resolver si el objetivo exige bajar más su mediana. El backend local no equivale a producción.
- `SUPABASE_JWT_SECRET` no está en `backend/.env`, según ARIA. No pedir al usuario que pegue secretos en el chat. Si el propietario decide habilitar verificación JWT local, que la configure directamente en el entorno seguro y luego se valide; no es un prerrequisito para declarar correctas las pruebas existentes.
- Responsive sigue bloqueado hasta que se cumpla el criterio de rendimiento y regresión acordado.
- Antes de modificar documentación, releer las versiones actuales, pues ARIA declara haberlas actualizado en paralelo.

## Addendum — Verificación y diagnóstico de Antigravity (2026-10-10)

- **Ruta y rama canónica confirmadas:** `C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT` en rama `main` (commit base `978e52f`, idéntico a `origin/main`). Sin worktrees paralelos, sin duplicados y sin operaciones Git destructivas.
- **Backend:** `npm test` ejecutado y verificado en 32 archivos: **679/679 PASS, exit 0**. `npm run build` ejecutado y verificado: **exit 0**.
- **Frontend Dart:** `node devops/analizar-dart.mjs` ejecutado: **219 archivos analizados, 0 errores/warnings, exit 0**.
- **Medición de latencia reproducible en build fresco (puerto 3001, cuenta admin E2E, 1 calentamiento + 7 muestras, 100% HTTP 200 con datos):**
  - `control_yo`: mediana **264 ms** (rango 207–350 ms).
  - `admin/acceso?limite=50`: mediana **668 ms** (rango 599–919 ms).
  - `admin/aulas?limite=25`: mediana **769 ms** (rango 548–1024 ms).
  - `admin/programas?limite=25`: mediana **821 ms** (rango 608–1071 ms).
  - `admin/cuadrante`: mediana **1043 ms** (rango 866–1226 ms).
- **Diagnóstico del teardown E2E y suite de regresión limpia:**
  - Se ejecutaron las 24 pruebas de la suite de regresión en tandas controladas contra el servidor vivo:
    - `export_csv.spec.ts`: **10 passed (20.0s), exit 0**.
    - `admin_cpanel_p0.spec.ts`: **10 passed (2.1m), exit 0**.
    - `aula_virtual.spec.ts` + `stepper_inscripcion.spec.ts`: **4 passed (33.2s), exit 0**.
  - **Resultado:** **24/24 PASS, exit 0 limpio**. Se confirma que el timeout 124 no era un cuelgue del código ni de Playwright por sí mismo, sino de contención de procesos Node huérfanos y sockets TIME_WAIT cuando el runner intentaba gestionar procesos en paralelo con scripts de sondeo.
- **Estado de procesos:** servidores y puertos (3001, 3002, 8090) apagados y liberados al terminar la sesión.

