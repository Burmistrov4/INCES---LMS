# MEGA PROMPT PARA ANTIGRAVITY — CIERRE, VALIDACIÓN Y DESPLIEGUE REAL A PRODUCCIÓN HOY
## Proyecto: INCES-LMS-PROJECT
## Prioridad: presentar hoy — entrega segura, verificable y sin afirmar pruebas que no se hicieron

Actúa como ingeniero/a senior responsable de release, QA, seguridad, arquitectura y despliegue. Debes continuar sobre el estado REAL del repositorio en esta máquina. No asumas que este documento describe el estado actual: vuelve a inspeccionar git, archivos, scripts, configuración y servicios antes de ejecutar acciones. Objetivo: cerrar y publicar hoy la versión presentable del sistema en producción, incluyendo los cambios funcionales ya preparados (especialmente F2: descarga de planilla oficial), siempre que superen las puertas de calidad. No te limites a dar recomendaciones: ejecuta el trabajo que puedas, verifica cada paso y deja evidencia reproducible.

## 0. Reglas críticas e innegociables
1. Trabaja exclusivamente en `C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT`. No confundas este proyecto con Adrialga ni con el proyecto final de Python. La indicación “modo LOCAL” pertenece a otro proyecto; NO la apliques aquí.
2. Primero inspecciona el estado actual. No sobrescribas cambios del usuario ni de otro agente. No uses `git reset --hard`, `git clean -fd`, `checkout .`, `restore .`, borrados masivos ni limpiezas agresivas. No elimines archivos “no usados” sin demostrar que son prescindibles.
3. No imprimas, pegues en logs, commits, informes ni mensajes ningún secreto: tokens, claves privadas, contraseñas, JWTs, service-role keys, credenciales de usuarios, cookies, connection strings. Puedes verificar la presencia de variables sin mostrar sus valores. Nunca añadas secretos al repositorio.
4. No declares PASS por inferencia. Cada PASS debe corresponder a un comando o comprobación ejecutada y su salida. Separa claramente: verificado por ejecución, inspeccionado estáticamente, pendiente de credencial/tercero y no probado.
5. No inventes resultados, usuarios, registros de producción, URLs, despliegues, migraciones aplicadas ni validaciones manuales. Si no puedes acceder a una plataforma por falta de autenticación, documenta el bloqueo y prepara los pasos exactos, pero no finjas que desplegaste.
6. Se autoriza preparar commit, push y despliegue de los cambios de esta release para presentación hoy, pero únicamente después de cumplir las puertas de calidad descritas abajo. No publiques si hay secretos, fallos críticos, migraciones destructivas/no revisadas, regresiones P0/P1 o una diferencia de producción que no se pueda evaluar. Si hay bloqueo, conserva el trabajo y entrega el motivo exacto, sin destruir ni descartar nada.
7. No hagas cambios de esquema/DB en producción sin revisar cada migración pendiente, su orden, idempotencia, compatibilidad hacia atrás, impacto sobre datos y estrategia de recuperación. No ejecutes seed destructivo ni uses datos reales de aspirantes para pruebas. Nunca borres/modifiques información real para “probar”.
8. Evita cambios de alcance que arriesguen la presentación. Prioriza correcciones necesarias, confiabilidad, experiencia principal y evidencia. No emprendas un rediseño grande, migraciones de arquitectura o limpieza cosmética en el último momento.
9. Mantén al usuario informado con hitos concretos. No preguntes por permisos ya concedidos, pero solicita intervención solo cuando una credencial, MFA, aprobación de plataforma o decisión irreversible sea realmente necesaria.
10. No mates procesos o servicios que puedan estar usando el usuario/agente. No cambies configuración global de la máquina.

## 1. Reconocimiento inicial obligatorio
Desde la raíz del repo registra sin secretos:
- fecha/hora local de inicio;
- `git rev-parse --show-toplevel`, rama, HEAD, `git status --short`, `git diff --stat`, `git diff --cached --stat`;
- `git status --porcelain=v1` y listado de archivos no rastreados;
- `git remote -v` (redacta cualquier token embebido en URL);
- existencia de cambios de otros agentes, sin atribuirlos sin evidencia;
- versiones de Node, npm/pnpm/yarn si corresponde, Flutter/Dart, Git;
- README y documentación operativa: `PLAN_MAESTRO.md`, `ESTADO_DEL_SISTEMA.md`, `HANDOVER_CHAT_NUEVO.md`, `MEMORY.md`, planes de cierre y documentos de release existentes. Si un archivo no existe, no lo inventes como existente.
- estructura real frontend/backend, package manifests, scripts, archivos de despliegue, configuración Cloudflare Pages/Render/Supabase/R2 y workflows CI.
No vuelques contenido de archivos .env. Verifica solo nombres de variables requeridas y si están definidas, con salida enmascarada.

Antes de tocar código, crea un informe de estado inicial dentro de la carpeta de documentación que ya use el proyecto (si no existe, en raíz) con fecha/hora, commit base, estado Git y plan. Usa un nombre inequívoco como `RELEASE_AUDIT_YYYYMMDD_HHMM.md`. No incluyas secretos. No hagas commit de ese informe hasta decidir qué documentación forma parte de la entrega.

## 2. Entender el alcance real de esta release
Reconcilia documentación, código y estado Git actual. Determina:
- funcionalidades incluidas realmente en esta entrega;
- archivos modificados por cada funcionalidad;
- migraciones nuevas o pendientes;
- diferencias entre docs y código;
- qué versión está desplegada en cada entorno, si se puede comprobar;
- qué endpoints y módulos están afectados;
- riesgos de regresión.
Prioridad principal: que el sistema sea defendible y que las funciones críticas del flujo real funcionen; no marcar el sistema entero como “100% completo” si aún hay módulos no verificados.

## 3. F2 — descarga de planilla oficial: revisión profunda obligatoria
Inspecciona y prueba la implementación existente, no des por buenas las afirmaciones previas.

### Flutter/UI y servicio
- `lib/screens/aspirante_dashboard.dart`: botón `Key('descargar-planilla-oficial')`, estado loading, doble clic, errores y recuperación.
- `lib/services/planilla_pdf_service.dart`: `descargarPlanillaPropia()`, `descargarPlanillaDe(usuarioId)`, modelos de resultado, manejo de 404/401/403/5xx/timeout/bytes vacíos.
- Tests `test/aspirante_dashboard_descarga_test.dart` y `test/planilla_pdf_service_test.dart`.
- Confirma que se descarga como PDF real y que el nombre del archivo y MIME son correctos, sin simular una descarga exitosa cuando el servicio falla.
- Comprueba que no se filtra información personal ni se usa un ID controlado por el aspirante para descargar la planilla de otra persona.

### Backend y autorización
- Rutas reales para `/api/v1/yo/planilla/pdf` y `/api/v1/inscripcion/planilla/:usuarioId/pdf` (confirma dónde están registradas).
- Ruta propia: la identidad debe venir del usuario autenticado del servidor (`req.usuario.id` o equivalente), nunca de un ID suministrado por el cliente.
- Ruta administrativa: guard de admin efectivo en el middleware/orden de ejecución real; verifica que no exista un camino alternativo sin protección.
- Confirma respuestas 401 sin sesión, 403 para rol insuficiente, 404 para ficha inexistente, 200 con PDF válido y content-type/headers correctos; manejo 500/503 sin filtrar stack ni secretos.
- Agrega o completa pruebas HTTP de integración para: no autenticado, usuario aspirante accediendo a ruta admin, admin con acceso válido, aspirante descargando su propia planilla, usuario A intentando obtener PDF de B por la ruta propia, ficha inexistente, error de almacenamiento/generación y cabeceras de descarga. Usa mocks/fixtures; no uses datos personales reales.
- No consideres suficientes pruebas unitarias del generador para demostrar seguridad de las rutas.

### Plantilla PDF — riesgo conocido que debe resolverse
Se detectó en `backend/src/infra/planilla-oficial-pdf.ts` una posible ruta de fallback silencioso que produce una página PDF en blanco cuando no se encuentra/carga la plantilla institucional. Verifica el código y tests. Si la plantilla oficial es requisito, no devuelvas un PDF en blanco como si fuera válido:
- en producción debe fallar de forma explícita y controlada si el template requerido falta o está corrupto;
- no devolver contenido institucional falso ni degradar silenciosamente;
- log seguro con identificador/código, sin PII ni secretos;
- test para plantilla faltante/corrupta y test que confirme que el PDF final tiene una página, tamaño Letter 612×792 pt, campos/estructura esperados y no está en blanco.
- valida que `backend/assets/planilla-oficial-template.pdf` se incluya en el artefacto de producción (Render/build/docker si aplica). Comprueba hash si la documentación lo exige, pero no asumas que el hash prueba por sí solo autenticidad institucional.
- La validación física final puede quedar como “pendiente de validación institucional” si no es posible imprimir hoy; no la describas como validada.

## 4. Puertas de calidad — ejecutar comandos reales
Detecta los scripts correctos desde package manifests/README antes de ejecutarlos. No inventes scripts. Guarda logs resumidos fuera del repo o en la carpeta de evidencias ignorada por Git, sin secretos.

### Backend
- instala dependencias solo si es necesario y usa lockfile vigente;
- ejecuta lint, typecheck, tests unitarios, integración y build de producción disponibles;
- vuelve a ejecutar los tests específicos de planilla y las pruebas HTTP nuevas;
- verifica que no haya tests omitidos/skipped relevantes ni tests que pasan solo por mocks mientras el endpoint falla;
- revisa dependencias vulnerables con el mecanismo ya existente, sin actualizar paquetes mayores automáticamente.

### Flutter
- `flutter pub get` solo si lockfile/dependencias lo requieren;
- ejecuta `dart format --output=none --set-exit-if-changed` sobre el alcance apropiado;
- `flutter analyze` o el analizador oficial del repo;
- tests focalizados y suite completa disponible;
- `flutter build web --release` con los define/env correctos según la configuración documentada. No escribas secretos en la línea de comandos ni en logs.
- Verifica el artefacto `build/web`: existencia, tamaño razonable, rutas, assets, configuración base URL y ausencia de referencias accidentales a localhost/IP privada o secretos.
- Si hay un error conocido de Windows con `PROGRAMFILES(X86)`, se permite definir esa variable solo en el proceso hijo para ejecutar tests; no modifiques configuración global.

### CI y coherencia
- ejecuta checks automáticos existentes, revisión de formatos y migraciones;
- revisa `git diff --check`;
- inspecciona cambios completos de cada archivo sensible;
- confirma que el PDF template, assets y fuentes estén incluidos en build/runtime;
- verifica que las pruebas no estén modificadas para ocultar fallos reales.
No aceptes como prueba una salida antigua de otra sesión.

## 5. Auditoría de seguridad antes de publicar
Revisa, como mínimo:
- autorización y roles en rutas nuevas/modificadas;
- RLS de Supabase y políticas que afecten datos personales;
- CORS, cookies, JWT, headers, rate limits y manejo de errores en las rutas afectadas;
- no exposición de service role, tokens ni variables privadas en frontend/build;
- archivos .env, certificados, dumps, PDFs de personas reales o credenciales añadidos por error;
- logs sin PII innecesaria;
- dependencias nuevas;
- IDOR/BOLA en planillas y módulos administrativos;
- permisos de almacenamiento y cualquier URL pública firmada;
- no romper accesibilidad de descarga, teclado, loading y mensajes de error.
Si una ruta permite descargar el PDF de otra persona sin autorización, BLOQUEA el despliegue hasta corregir y probar.

## 6. Migraciones y datos
- Identifica todas las migraciones presentes en el working tree frente a producción, no solo el ledger local.
- Inspecciona el SQL de cada migración nueva/modificada y su efecto en tablas, funciones, triggers, policies y grants.
- Comprueba el estado remoto con herramientas existentes solo si ya hay autenticación; no muestres tokens ni dumps.
- No ejecutes `db reset`, drops, truncate, seed destructivo ni cambios de datos reales.
- Antes de aplicar cualquier migración remota, confirma que está pendiente, que se aplica en el orden correcto y que no se ha aplicado parcialmente.
- Para operaciones no reversibles, documenta snapshot/backup y plan de rollback. Si no se puede garantizar, bloquea DB deploy pero continúa con frontend/backend solo si son compatibles.
- No supongas que una migración está aplicada por el mero hecho de que el código exista.

## 7. Prueba E2E en navegador real
Usa la herramienta de navegador/E2E que el proyecto ya tenga configurada (Playwright u otra); no introduzcas una herramienta nueva a última hora si no es necesaria.
- Confirma login, rol, navegación, carga de dashboard, descargar planilla, creación/consulta del PDF, manejo de errores.
- Verifica el ciclo de negocio principal del alcance de release.
- Si hay credenciales E2E existentes, revisa que sean de prueba y que no sean credenciales de producción personales. No imprimas sus valores. No crees usuarios reales sin autorización.
- Si el E2E necesita un usuario/servicio/tercero no disponible, registra la prueba como bloqueada, no PASS.
- Revisa viewport de escritorio y móvil al menos para pantallas críticas.
- Conserva capturas/evidencias si el harness ya las produce, evitando PII.
- La prueba manual/automatizada debe confirmar que la descarga genera archivo PDF que abre, no solo que el endpoint responde 200.

## 8. Preparar release con alcance acotado
- Decide qué archivos pertenecen a esta entrega según evidencia y diffs; no añadas automáticamente los 50/36 u otros conteos históricos.
- No hagas `git add -A` sin revisar. Prepara staging explícito de los archivos de la release y documentación asociada. No incluyas logs, cachés, secretos, datos reales, artefactos temporales ni archivos de otra tarea.
- Revisa diff staged completo, `git diff --cached --check`, nombres de archivos y estado de secretos.
- Usa mensaje de commit claro con alcance INCES LMS/F2 y release de presentación, sin exagerar el grado de finalización.
- Antes de push, confirma rama remota, upstream, ausencia de conflictos y que el commit incluye solo archivos revisados. No fuerces push.
- Si la rama de producción es main, sigue el flujo real del repo; no asumas que Cloudflare/Render despliega desde main hasta confirmarlo.
- Si la plataforma hace deploy automático tras push, observa el deployment y espera a que termine; no declares publicado hasta estado exitoso.
- Si requiere CLI, usa comandos oficiales ya configurados. No reveles tokens ni copies secretos en el prompt, terminal, código o informe.
- No cambies dominios ni secretos de entorno durante esta entrega salvo que sea imprescindible y esté documentado.

## 9. Despliegue a producción — requerido hoy si todas las puertas pasan
Determina y verifica la topología real antes de desplegar:
- Frontend Flutter Web: plataforma/proyecto/branch de producción reales (p. ej. Cloudflare Pages si así está configurado).
- Backend: servicio y rama reales (p. ej. Render si así está configurado).
- Base de datos/Auth: Supabase project correcto y migraciones remotas pendientes.
- Almacenamiento/assets: rutas y configuración reales.
No adivines nombres de proyectos, IDs, URLs ni entornos a partir de recuerdos.

Orden de release:
1. Confirmar build/tests y security gates.
2. Confirmar migraciones pendientes y compatibilidad; aplicar únicamente las revisadas y necesarias, en orden, si existe autorización/credencial y plan de rollback.
3. Publicar backend antes que frontend si el frontend depende de los endpoints nuevos; verificar health/readiness y endpoint post-deploy.
4. Publicar frontend después de confirmar que el backend compatible está saludable.
5. Esperar al estado final del proveedor y registrar URL/identificador de deploy, hora y commit desplegado.
6. No exponer secretos en la evidencia ni en la salida final.
7. No marcar como producción algo que solo está en localhost, preview, build local o branch sin desplegar.

## 10. Smoke tests post-despliegue
Después del deploy real:
- GET health/readiness: estado correcto, versión/commit cuando exista;
- comprobar carga de frontend y recursos críticos sin errores JS;
- login de prueba si está permitido y no expone credenciales;
- confirmar que los endpoints están disponibles y los códigos HTTP correctos;
- verificar que la descarga de planilla produce PDF válido, MIME y filename correctos;
- confirmar autorización: no autenticado → 401; rol no permitido → 403; recurso ausente → 404, según el contrato real;
- verificar logs del servicio por errores de startup, assets no encontrados, crashes o 5xx;
- comprobar consola del navegador y responsive de la pantalla de entrega.
Nunca uses aspirantes reales ni descargues sus planillas para un smoke test. Si no se puede ejecutar un test por no tener un usuario de prueba seguro, informa exactamente qué quedó pendiente.

## 11. Rollback y manejo de fallo
- Identifica el deployment anterior estable antes de publicar.
- Si el deploy falla, no ejecutes reintentos ciegos ni cambios de infraestructura improvisados.
- Si el smoke test revela regresión crítica, ejecuta rollback mediante el procedimiento oficial del proveedor solo si es inequívoco y disponible; registra el identificador del despliegue restaurado y vuelve a comprobar salud.
- Si DB migration no es reversible, no prometas rollback completo; describe el riesgo y evita frontend incompatible.
- Preserva cambios locales y evidencias; nunca borres trabajo para “dejar limpio”.
- Si el tiempo es insuficiente para una puerta crítica, prioriza un sistema estable antes que un despliegue inseguro. La fecha límite no justifica ocultar fallos.

## 12. Documentación y handover
Actualiza la documentación canónica existente, no crees una segunda verdad paralela:
- estado real por módulo;
- funcionalidad F2 y rutas;
- pruebas ejecutadas con comandos, hora, resultado y límites;
- build artefacto y checksum si es útil;
- migraciones revisadas/aplicadas/pendientes;
- commit SHA y rama publicados;
- proveedor, deployment ID/URL y hora (solo datos no sensibles);
- smoke tests post-deploy;
- limitaciones explícitas (incluida validación física institucional del PDF si sigue pendiente);
- instrucciones de rollback y próximos pasos.
Actualiza `ESTADO_DEL_SISTEMA.md` y `PLAN_MAESTRO.md` solo con hechos confirmados; respeta los nombres y convenciones que realmente existan. No declares P-01 cerrado salvo que el despliegue Cloudflare real y la verificación requerida hayan ocurrido. No declares performance/responsive cerrado sin evidencia.

## 13. Criterios de aceptación final
Solo declarar “RELEASE PUBLICADA Y VERIFICADA” si todo esto está respaldado:
- [ ] diff revisado y sin secretos
- [ ] backend tests/build/lint/typecheck pertinentes PASS
- [ ] Flutter analyze/tests/build pertinentes PASS
- [ ] pruebas HTTP de autorización y descarga PASS
- [ ] PDF plantilla validada, sin fallback en blanco silencioso
- [ ] migraciones remotas revisadas; ninguna aplicada sin control
- [ ] commit revisado y push no forzado
- [ ] proveedor confirma deploy de commit correcto
- [ ] smoke tests de producción PASS
- [ ] documentación actualizada con evidencia
Si algún punto crítico no se cumple, el estado final será “RELEASE BLOQUEADA” o “DEPLOY PARCIAL”, detallando exactamente qué sí se publicó y qué no. No maquilles el estado.

## 14. Informe final obligatorio para el usuario
Entrega un resumen de lectura rápida y un detalle técnico con:
1. estado final: publicada/verificada, parcial o bloqueada;
2. commit SHA, rama y archivos incluidos;
3. resultados de pruebas y comandos exactos;
4. URLs/IDs de despliegue reales y plataforma correspondiente;
5. estado de backend, frontend y DB por separado;
6. smoke tests con resultados;
7. fallos pendientes y riesgos conocidos;
8. rollback disponible y cómo hacerlo;
9. confirmación explícita de que no se imprimieron secretos y no se usaron datos personales reales;
10. checklist de presentación de hoy: login, navegación, roles, descarga de planilla, PDF abierto/legible, impresión/validación institucional pendiente si aplica.
No cierres con “todo listo” sin evidencia concreta.

## 15. Punto de partida de esta sesión
En una sesión previa se volvieron a ejecutar y dieron PASS:
- Backend: 4 suites focalizadas de planilla, 8/8 tests.
- Flutter: `test/aspirante_dashboard_descarga_test.dart` y `test/planilla_pdf_service_test.dart`, 12/12 tests.
Estos resultados son solo antecedentes. Vuelve a ejecutarlos sobre el estado actual antes de publicar. Se detectó además un posible fallback del generador que devuelve una página PDF en blanco si no encuentra la plantilla; confirma y corrige/testea si sigue presente. Git estaba muy modificado (último dato histórico: 50 tracked modified y 36 untracked), por tanto revisa cada archivo y no hagas staging indiscriminado.
