# PROTOCOLO DE OPERACIÓN AUTÓNOMA PARA AGENTES AI — INCES LMS

## Propósito

Este documento es el contrato operativo para cualquier LLM/agent que retome el repositorio. Su objetivo es evitar que una ventana de contexto limitada obligue a reconstruir el historial.

## Orden de lectura obligatorio

1. `MEMORY.md` — estado compacto y siguiente acción.
2. `docs/AI_AGENT_OPERATING_PROTOCOL.md` — reglas de trabajo.
3. `PLAN_MAESTRO.md` — arquitectura/alcance.
4. `PLAN_CIERRE_100_FUNCIONAL_2026.md` — hitos y evidencia.
5. `docs/AUDITORIA_RENDIMIENTO_2026-10-08.md` — fase Performance.
6. `git status --short` — realidad del árbol, no asumir limpieza.
7. Sólo después inspeccionar código específico del hito.

## Regla de oro

**No confundir intención, código escrito, build local, test unitario, E2E, producción y despliegue.** Cada afirmación de cierre debe tener evidencia correspondiente.

Estados válidos de un hito:
- PENDIENTE
- EN INVESTIGACIÓN
- EN IMPLEMENTACIÓN
- BLOQUEADO
- VERIFICADO LOCAL
- VERIFICADO E2E
- VERIFICADO PRODUCCIÓN
- CERRADO

## Ciclo autónomo

Para cada hito:

1. Leer el estado y localizar el siguiente discriminador.
2. Inspeccionar el código real y contratos existentes.
3. Formular hipótesis pequeña y comprobable.
4. Medir antes de cambiar si es Performance.
5. Implementar el cambio mínimo que resuelva la causa.
6. Ejecutar la prueba más barata que pueda falsar la hipótesis.
7. Ejecutar regresión del área afectada.
8. Si falla, diagnosticar causa raíz; no maquillar tests.
9. Repetir hasta verde.
10. Actualizar documentación inmediatamente.
11. Registrar archivos modificados, comandos, resultados y deuda.
12. Avanzar al siguiente hito sin pedir permiso si no existe un bloqueo real.

## Qué significa «bloqueo real»

Sólo detenerse y pedir al usuario una intervención cuando:
- falta una credencial/permiso que sólo el usuario puede proporcionar;
- una acción irreversible/destructiva requiere autorización explícita;
- existe una decisión de producto que no puede inferirse de los documentos;
- la infraestructura externa exige autenticación interactiva no disponible;
- dos contratos oficiales se contradicen y no existe evidencia para resolverlos.

No detenerse por:
- un test fallido que puede investigarse;
- una ruta que requiere rastreo de código;
- un warning que puede clasificarse;
- un build lento;
- documentación incompleta;
- incertidumbre que pueda reducirse mediante inspección o medición.

## Seguridad

- Nunca imprimir secretos.
- Se pueden leer localmente para diagnosticar, pero nunca copiarlos a Markdown, logs públicos, commits, respuestas o prompts.
- No desactivar RLS para «hacer pasar» una prueba.
- No borrar datos reales ni datos E2E con SQL destructivo sin mecanismo documentado.
- No cambiar configuración global del Desktop Commander para ampliar acceso sólo para resolver un problema.
- No introducir claves de servicio en Flutter Web.

## Git / historial

**No asumir que el árbol está limpio.**

Antes de borrar cualquier archivo:
1. revisar `git status --short`;
2. clasificarlo como código, evidencia, documentación, probe temporal o artefacto;
3. comprobar si otro agente lo usa;
4. borrar sólo si es inequívocamente temporal.

No hacer `git clean -fd`, `reset --hard`, rebase destructivo ni borrar carpetas de contexto sin autorización.

Los commits/push no son necesarios para validar localmente. Mantener cambios locales cuando el objetivo de la sesión sea auditoría/implementación. Si el usuario exige preservar el estado sin push, respetarlo.

## Evidencia

Para cada cambio registrar:
- fecha/hora;
- hito;
- problema;
- evidencia previa;
- cambio;
- archivos;
- comando;
- resultado;
- regresión;
- estado;
- siguiente acción.

No registrar credenciales ni tokens.

## Performance

Siempre:
**baseline → hipótesis → cambio → medición posterior → regresión.**

No optimizar por estética de código.
No cambiar renderer Flutter sólo porque WASM pesa.
No añadir cache client-side sin conocer invalidación.
No paginar una API que no tiene consumidor real.
No reemplazar `select('*')` sin verificar todos los campos consumidos.

## Flutter Web

- Los valores de `String.fromEnvironment` son de build-time.
- Builds E2E deben usar `--dart-define-from-file=.env.json`.
- El árbol semántico de Playwright tiene particularidades documentadas en `e2e/src/pages/FlutterApp.ts`.
- Un test E2E rojo puede ser infraestructura, build, datos, RLS, backend o UI. Determinar cuál antes de tocar código.

## Base de datos

- Migraciones nuevas con timestamp `YYYYMMDDNNN_*.sql`.
- No editar migraciones ya aplicadas.
- Preferir el contrato de la aplicación sobre SQL directo para operaciones de negocio.
- Los scripts de humo deben ser reproducibles y no destructivos.

## Documentación viva

Al finalizar una sesión:
- actualizar `MEMORY.md`;
- actualizar el documento de la fase;
- actualizar `PLAN_CIERRE_100_FUNCIONAL_2026.md` si la evidencia cambia el estado;
- actualizar `PLAN_MAESTRO.md` sólo si cambia arquitectura, alcance o secuencia;
- dejar una sección «Última sesión / siguiente discriminador».

## Regla anti-amnesia

Nunca escribir «continuar después» sin indicar exactamente:
- qué archivo;
- qué símbolo/ruta;
- qué medición falta;
- qué comando ejecutar;
- qué resultado cerraría el hito.

## Regla anti-alucinación

Si no se midió, decir «NO MEDIDO».
Si no se desplegó, decir «NO DESPLEGADO».
Si no pasó E2E, no decir «funciona».
Si un proveedor no está configurado, no decir «configurado».
Si existe evidencia contradictoria, conservar ambas hasta resolverla.

## Criterio de finalización del proyecto

El agente no declara «proyecto terminado» hasta comprobar, según corresponda:
1. funcionalidad;
2. seguridad/autorización;
3. datos/migraciones;
4. rendimiento;
5. responsive;
6. UX;
7. animaciones sin regresión;
8. Android;
9. E2E;
10. producción;
11. documentación/handover.

El objetivo es **cerrar el sistema**, no producir una lista de tareas.

## Estado actual conocido

- F1 recovery/email: DEFERIDA.
- Performance: ACTIVA.
- P-02: auditoría de payloads ejecutada; se corrigió `miFicha()` para proyección explícita.
- P-01: `web/_headers` preparado y helper creado; despliegue real aún pendiente.
- Responsive: NO INICIAR.


---

# 12. CONTRATO DE AUTONOMÍA CONTINUA — 2026-10-08

Este apartado prevalece como instrucción operativa para agentes que reciban este repositorio con el objetivo explícito de llevarlo hasta el cierre.

## 12.1 Regla de continuidad

**No detener el trabajo porque una tarea terminó.** Al cerrar un hito, el agente debe:

1. actualizar evidencia;
2. actualizar MEMORY.md;
3. recalcular el estado real de todos los hitos;
4. seleccionar automáticamente el siguiente hito desbloqueado de mayor prioridad;
5. ejecutarlo;
6. verificarlo;
7. documentarlo;
8. continuar.

No preguntar "¿continúo?", "¿qué hago ahora?" ni solicitar confirmación para trabajo reversible y técnicamente determinado.

La respuesta conversacional no es el mecanismo de continuidad. **El repositorio es el mecanismo de continuidad.**

## 12.2 Máquina de estados obligatoria

Cada hito debe existir en uno de estos estados:

`PENDIENTE → INVESTIGACIÓN → IMPLEMENTACIÓN → VERIFICACIÓN → CERRADO`

También puede entrar en:

`BLOQUEADO_HUMANO`

Un hito `BLOQUEADO_HUMANO` no autoriza a abandonar el proyecto. El agente debe:

- registrar exactamente qué falta;
- completar todos los subtrabajos independientes;
- avanzar a otros hitos no dependientes;
- preparar scripts/configuración/documentación para que el desbloqueo sea de una sola acción;
- volver a intentar el hito cuando el recurso esté disponible.

## 12.3 Los únicos cuatro bloqueadores humanos permitidos

El agente sólo puede solicitar intervención humana cuando exista evidencia de uno de estos casos:

### H1 — Credencial externa que sólo el usuario puede proporcionar
Ejemplos:
- contraseña que no existe localmente;
- API key externa que debe ser entregada por el propietario;
- token personal de una cuenta externa;
- secreto de un dominio/servicio que no puede generarse legítimamente desde el entorno disponible.

**Antes de declararlo H1:** buscar credenciales ya autorizadas en variables de entorno, archivos locales permitidos, CI, configuración del proyecto y mecanismos existentes. Nunca imprimir el secreto.

El agente puede generar sus propias credenciales temporales para E2E cuando sea técnicamente posible y autorizado: usuarios de prueba, contraseñas aleatorias, datos sintéticos, tokens de prueba y fixtures. Debe etiquetarlos como temporales y registrar cómo revocarlos/limpiarlos.

### H2 — Autorización irreversible
Ejemplos:
- borrar datos reales;
- eliminar un proyecto/recurso cloud;
- rotación destructiva de credenciales;
- migración irreversible sobre datos reales sin rollback;
- publicar/eliminar algo que el usuario debe aprobar expresamente.

El agente debe preparar y verificar todo lo reversible antes de pedir esta autorización.

### H3 — Decisión de producto genuinamente ambigua
Sólo aplica cuando:
- existen al menos dos alternativas razonables;
- ninguna está determinada por código, documentación, datos, seguridad, UX establecida o precedentes del proyecto;
- la decisión cambia comportamiento visible o alcance.

No es H3 si una alternativa es claramente más consistente con el contrato existente.

### H4 — Infraestructura externa que exige login interactivo
Ejemplos:
- OAuth con interacción humana;
- MFA/2FA;
- CAPTCHA;
- aprobación física;
- dispositivo de confianza;
- navegador externo que exige intervención del propietario.

El agente debe preparar el proceso hasta el punto exacto del login y dejar una instrucción de una sola acción.

**Cualquier otro problema es trabajo del agente, no un motivo para detenerse.**

## 12.4 Política de credenciales E2E autónomas

El agente DEBE intentar primero crear o reutilizar credenciales temporales de prueba:

- usuarios sintéticos;
- contraseñas aleatorias;
- correos de prueba controlados;
- fixtures;
- registros aislados;
- datos con prefijo/namespace E2E;
- cuentas temporales del propio sistema cuando exista una API legítima para crearlas.

Debe preferir:
1. mecanismo oficial de la aplicación;
2. endpoint/admin tooling existente;
3. Supabase Auth/API autorizado localmente;
4. seed/fixture reproducible.

Nunca debe:
- inventar credenciales de terceros;
- intentar acceso no autorizado;
- saltarse MFA/CAPTCHA;
- reutilizar contraseñas personales;
- registrar secretos en Markdown;
- subir credenciales al repositorio.

Las credenciales temporales creadas por el agente deben tener un plan de limpieza. Si la limpieza automática no es segura, se documenta la deuda y se evita borrar datos reales.

## 12.5 Anti-parálisis

Si un comando falla:

1. conservar el error;
2. clasificarlo;
3. intentar una alternativa técnicamente equivalente;
4. inspeccionar documentación/código/configuración local;
5. reproducir en menor escala;
6. corregir causa;
7. reintentar;
8. registrar el resultado.

No convertir el primer error en un bloqueo.

Si una prueba es lenta:
- esperar;
- leer salida incremental;
- comprobar si el proceso sigue vivo;
- no duplicar procesos innecesariamente;
- continuar sólo cuando exista evidencia de terminación o bloqueo real.

Si una herramienta pierde contexto:
- reconstruir estado desde archivos;
- consultar git;
- inspeccionar procesos;
- continuar.

## 12.6 Presupuesto de reintentos

No repetir indefinidamente la misma acción idéntica.

Después de 2–3 intentos sustancialmente equivalentes:
- cambiar hipótesis;
- cambiar instrumento;
- reducir el caso;
- aislar la capa;
- buscar evidencia nueva.

Un bucle de reintentos sin nueva información es un fallo de metodología.

## 12.7 Trabajo paralelo seguro

Cuando dos tareas no comparten estado mutable crítico, el agente puede trabajar en paralelo.

Prioridad:
1. seguridad/funcionalidad;
2. bloqueadores de fase;
3. rendimiento;
4. responsive;
5. UX;
6. motion/3D;
7. Android;
8. documentación.

No paralelizar cambios que puedan sobrescribirse o producir migraciones incompatibles.

## 12.8 Gate de cada fase

No pasar de fase sólo porque "parece suficiente".

Cada fase debe tener:
- criterio de entrada;
- baseline;
- implementación;
- prueba específica;
- regresión;
- evidencia;
- criterio de salida;
- estado documentado.

Si una fase tiene un bloqueador humano, el agente puede avanzar con fases independientes, pero debe mantener el bloqueo registrado.

## 12.9 Auditoría de alcance antes de declarar terminado

Antes del cierre final, buscar activamente:
- TODO/FIXME;
- funciones stub;
- rutas sin consumidor;
- pantallas sin navegación;
- endpoints sin UI;
- UI sin endpoint;
- módulos OFF inesperados;
- errores silenciados;
- catch vacíos;
- flags de prueba;
- URLs localhost;
- credenciales hardcodeadas;
- datos de ejemplo visibles;
- textos "[SEMILLA]", "TODO", "TEST", "E2E" en UI productiva;
- builds que usan configuración incorrecta;
- workflows CI/CD incompletos;
- documentación contradictoria.

Cada hallazgo debe clasificarse como:
`CERRAR AHORA`, `FASE POSTERIOR`, `NO APLICA` o `BLOQUEADO_HUMANO`.

## 12.10 Cierre global

El proyecto sólo puede declararse **CERRADO** cuando el agente haya recorrido todas las fases aplicables y exista evidencia para:

- funcionalidad;
- autorización/RLS;
- persistencia/migraciones;
- archivos/R2;
- autenticación;
- rendimiento;
- responsive;
- UX/accesibilidad;
- animaciones/3D;
- Android;
- E2E;
- despliegue;
- smoke de producción;
- documentación;
- seguridad;
- ausencia de bloqueadores técnicos conocidos.

F1 correo puede permanecer fuera de la secuencia sólo mientras esté explícitamente DEFERIDA por el alcance vigente; si el objetivo de cierre final exige F1, el agente debe retomarla automáticamente.

## 12.11 Resumen final obligatorio

Si el proyecto llega al cierre, generar `docs/CIERRE_FINAL_<fecha>.md`.

Si queda cualquier intervención humana, generar `docs/BLOQUEADORES_HUMANOS_<fecha>.md` con:

- H1/H2/H3/H4;
- evidencia;
- qué intentó el agente;
- qué quedó terminado;
- qué acción humana exacta falta;
- cómo verificar que el bloqueo desapareció;
- siguiente comando;
- impacto real sobre el cierre.

**Nunca escribir simplemente "requiere intervención humana".**


---
# 13. CONTRATO REFORZADO DE AUTONOMÍA — 2026-10-08

La especificación completa se encuentra en:
docs/AI_AGENT_AUTONOMY_AND_ENVIRONMENT_RECOVERY.md

## Regla operativa
El agente trabaja sin supervisión hasta donde permitan las capacidades reales del entorno. No debe convertir limitaciones de una herramienta en limitaciones del proyecto.

## Recuperación
Ante una limitación:
1. cambiar instrumento;
2. reducir el caso;
3. bajar de capa;
4. inspeccionar artefactos propios;
5. usar ingeniería inversa del sistema propio;
6. crear un adaptador reversible si corresponde;
7. probar equivalencia;
8. documentar.

## Bloqueadores
Sólo H1, H2, H3 y H4 son bloqueadores humanos. Un bloqueo humano no detiene el resto del trabajo.

## Seguridad
La autonomía no autoriza a evadir autenticación, MFA, CAPTCHA, RLS, autorización ni controles de terceros. La ingeniería inversa se limita al sistema y artefactos propios y a interfaces legítimamente accesibles.

## Ausencia del propietario
No preguntar, no esperar y no finalizar después de un hito. Continuar con el siguiente trabajo deducible.
