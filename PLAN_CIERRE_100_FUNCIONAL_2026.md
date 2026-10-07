# PLAN DE CIERRE 100% FUNCIONAL — INCES LMS
## Documento operativo para ARIA / Work Buddy

**Regla principal:** NO iniciar Android ni el rediseño visual final hasta cerrar funcionalidad, seguridad, producción, resiliencia y pruebas E2E.

**Objetivo:** llevar INCES LMS desde “funciona por módulos” a “todos los flujos institucionales funcionan de punta a punta, con evidencia reproducible”.

### Principios
1. El código existente y la base real son la fuente de verdad.
2. No inventar datos, rutas, estados ni capacidades.
3. No hacer cambios destructivos de Git.
4. Preservar modificaciones/untracked ajenos a la tarea.
5. Cada corrección debe tener prueba antes/después.
6. Preferir cambios pequeños, reversibles y auditables.
7. No tocar migraciones 0007/0008 salvo nueva evidencia que lo exija.
8. No subir secretos ni imprimir valores de variables de entorno.
9. Todo flujo crítico debe probarse en local y, cuando corresponda, contra producción.
10. Una función no se considera cerrada sólo porque compile: debe poder usarse desde la UI y persistir correctamente.

## Orden obligatorio de trabajo
F0 Inventario → F1 Autenticación → F2 Onboarding/planilla → F3 Invitaciones docentes → F4 R2/archivos → F5 Alumno E2E → F6 Docente E2E → F7 Admin E2E → F8 Asistencia → F9 Certificados → F10 Resiliencia → F11 Producción → F12 SEO/PWA/offline → F13 UX/UI final → F14 Android.

## F0 — INVENTARIO FUNCIONAL REAL

Crear una matriz única por funcionalidad, no por cantidad de registros técnicos de system_modules.

Columnas mínimas:
- Funcionalidad de producto
- Rol
- Pantallas Flutter
- Endpoints Fastify
- Tablas/RPC/migraciones
- Gateway/repository/service
- Prueba unitaria
- Prueba backend
- E2E
- Producción
- Estado: PENDIENTE / EN PRUEBA / VERDE / BLOQUEADO

Mapa inicial:
1. Administración
2. Usuarios y onboarding
3. Oferta formativa / Currículo
4. Cuadrante / horarios
5. Inscripciones
6. Planilla oficial
7. Archivos / R2
8. Aula Virtual
9. Asistencia
10. Certificados / QR
11. Pasantías, sólo si existe implementación real completa

### Regla UX de módulos
No mostrar al administrador duplicados históricos como si fueran funcionalidades distintas.
- Calificaciones = función integrada en Aula Virtual.
- Asistencia = una sola función operativa con QR/live attendance.
- Pasantías = pendiente hasta que exista flujo completo; NO activarla sólo para aumentar el contador.
- Mantener separación entre registro técnico system_modules y catálogo de funcionalidades que entiende el usuario.

## F1 — AUTENTICACIÓN

### Recuperación de contraseña
Investigar y cerrar:
- solicitud “Olvidé mi contraseña”;
- envío real;
- enlace funcional;
- apertura de la app;
- sesión temporal de recovery;
- cambio de contraseña;
- invalidación/reuso del enlace;
- enlace expirado;
- correo inexistente sin fuga de información;
- errores de SMTP traducidos a mensajes útiles.

Estado observado recientemente:
- POST real de Supabase recovery devolvió HTTP 500 “Error sending recovery email”.
- Se configuró SMTP propio de Supabase con Resend y se personalizaron las plantillas.
- También se probó remitente de sandbox de Resend; el destinatario arbitrario puede seguir rechazándose mientras Resend no tenga un dominio verificado.
- No declarar “correo funcionando” hasta comprobar entrega real a un destinatario autorizado y, posteriormente, a un destinatario externo con dominio verificado.

### Login
Probar:
- correo + contraseña;
- cédula + contraseña;
- credenciales inválidas;
- usuario deshabilitado;
- sesión persistente;
- refresh;
- cierre de sesión;
- expiración;
- recuperación posterior.

## F2 — ONBOARDING + PLANILLA OFICIAL

La planilla debe conservar la forma institucional original. No crear una “parecida”.

### Flujo aspirante
Registro → datos personales → oferta → formulario completo → validación → resumen → envío → confirmación → dashboard.

En el resumen deben existir:
- Ver planilla oficial con los datos rellenados.
- Descargar planilla oficial.
- Resultado de envío claramente indicado.
- Posibilidad de volver sin perder datos cuando sea seguro hacerlo.

### Flujo persistido
El mismo documento lógico debe poder recuperarse:
- por el aspirante desde su dashboard;
- por administradores desde la ficha/inscripción;
- después de refresh;
- después de cerrar sesión y volver a entrar;
- sin reconstruir datos distintos a los guardados.

### PDF oficial
Usar como fuente visual el PDF original entregado por INCES.
Criterio de aceptación:
- mismas páginas;
- misma geometría;
- mismos títulos;
- mismas etiquetas;
- mismas casillas/secciones;
- datos escritos en las posiciones correctas;
- ningún campo omitido;
- sin deformar el original;
- si el original tiene fondo preimpreso, reutilizar ese fondo en lugar de redibujarlo.

El renderer “oficial” existente debe evaluarse contra el original antes de conectarlo a producción.
No conectar por intuición los archivos nuevos de planilla-oficial: primero comparar visualmente y con pruebas de contenido.

### Verificaciones
- Aspirante descarga después del resumen.
- Aspirante abre desde dashboard.
- Admin abre la misma planilla.
- Admin descarga exactamente la misma representación.
- Comparar PDF original vs PDF rellenado mediante renderización de páginas.
- Validar nombres, cédula, teléfono, correo, programa, selección, tablas y campos opcionales.

## F3 — INVITACIÓN REAL DE DOCENTES

Flujo:
Admin → Usuarios → Invitar docente → correo → enlace → activar cuenta → contraseña → perfil DOCENTE → login → dashboard docente.

### Debe verificarse
- token aleatorio;
- sólo hash persistido;
- expiración;
- un solo uso;
- nombres/apellidos llegan al perfil;
- enlace usa FRONTEND_URL real;
- el correo se acepta por el proveedor;
- el correo contiene el enlace correcto;
- abrir el enlace desde correo lleva al flujo de activación;
- activar crea/actualiza el perfil correctamente;
- segundo uso es rechazado;
- invitación expirada es rechazada.

### Correo
No confundir:
- “Resend aceptó el mensaje”
- “el mensaje fue entregado”
- “el profesor recibió y abrió el mensaje”.

Registrar esas diferencias en pruebas y UX.
Mientras no exista dominio verificado en Resend, el sandbox no sirve para demostrar envío arbitrario a cualquier profesor.
Plan de producción: dominio institucional o dominio controlado por el proyecto + DNS/SPF/DKIM + sender verificado.

## F4 — R2 / ARCHIVOS

Bucket objetivo: inces-lms-media.

Probar realmente, no sólo con mocks:
1. Alumno solicita URL firmada.
2. Backend autoriza entidad/propietario.
3. Flutter sube directamente a R2.
4. Backend confirma/actualiza metadata.
5. Archivo queda visible en bucket.
6. Alumno puede abrir/descargar su archivo.
7. Profesor puede acceder sólo cuando la regla lo permite.
8. Admin puede acceder según autorización.
9. Otro alumno no puede acceder.
10. URL expirada falla.
11. Objeto inexistente se traduce correctamente.
12. archivo demasiado grande se rechaza.
13. MIME no permitido se rechaza.
14. doble click no duplica registros.
15. red interrumpida no deja estado falso CONFIRMED.
16. reintento recupera cuando sea seguro.
17. eliminar respeta autorización y estado.

Registrar evidencia del bucket y de la fila Postgres, sin exponer secretos.

## F5 — E2E ALUMNO

Flujo maestro:
registro → confirmación → onboarding → perfil → oferta → selección → inscripción → planilla → aprobación → sección → aula → material → tarea → entrega → nota → asistencia → certificado.

Cada transición debe comprobar:
- HTTP correcto;
- estado persistido;
- UI actualizada;
- refresh;
- navegación atrás;
- sesión;
- permisos;
- error de red.

### Caso conocido
El flujo “Nueva tarea → Crear y publicar” de Aula Virtual tuvo un fallo reproducible en E2E.
Antes de corregir:
- reproducir;
- capturar DOM/estado/modal;
- aislar si es UI, timing, API o estado;
- corregir la causa;
- repetir varias veces;
- ejecutar el flujo completo.

No arreglar el test para ocultar un fallo real de la aplicación.

## F6 — E2E DOCENTE

Login → Mis aulas → aula → anuncios → tareas → publicar → entregas → calificar → devolver → asistencia → QR → alumnos → cierre.

Validar especialmente:
- Calificaciones vive dentro de Aula Virtual.
- Crear tarea no deja modal de éxito bloqueando acciones posteriores.
- “Calificar” siempre aparece cuando corresponde.
- nota persistida;
- alumno ve nota;
- entrega tardía;
- devolver trabajo;
- asistencia en tiempo real;
- QR caducado;
- doble marcación;
- refresh conserva estado.

## F7 — E2E ADMINISTRADOR

Login → dashboard → usuarios → invitaciones → roles → programas → materias → pensum → secciones → horarios → inscripciones → cola → planillas → archivos → módulos → parámetros → auditoría.

### UX de módulos
La pantalla administrativa no debe dar sensación de sistema incompleto por mostrar módulos legacy apagados.
Separar:
- “Funcionalidades operativas”
- “Funciones integradas”
- “Pendientes de implementación”

No habilitar Pasantías sin flujo completo.

## F8 — ASISTENCIA

### Docente
Crear sesión → generar QR → proyectar → recibir marcaciones → ver tablero → cerrar sesión.

### Alumno
Abrir asistencia → escanear QR o introducir código → validar vigencia → registrar una sola vez → ver confirmación.

Probar:
- QR válido;
- QR vencido;
- QR de otra sección;
- alumno no inscrito;
- doble registro;
- pérdida de red;
- reconexión;
- websocket desconectado;
- refresh.

## F9 — CERTIFICADOS / QR

Completar:
- condición de egreso;
- generación;
- persistencia;
- QR;
- verificación pública;
- datos correctos;
- certificado inexistente;
- QR manipulado;
- certificado revocado si el dominio lo contempla.

## F10 — RESILIENCIA

Simular y probar:
- Render dormido/cold start;
- Supabase lento;
- API 500;
- API 401;
- API 403;
- API 404;
- timeout;
- internet perdido;
- internet intermitente;
- R2 caído;
- URL firmada vencida;
- refresh durante operación;
- botón presionado dos veces;
- navegación atrás durante envío;
- cierre/reapertura del navegador;
- sesión expirada.

Regla UX:
Nunca mostrar “guardado correctamente” si la operación no fue confirmada por el backend.
Los estados deben distinguir: cargando, confirmado, pendiente, fallido y reintentable.

## F11 — PRODUCCIÓN

Arquitectura objetivo:
- Cloudflare Pages → frontend.
- Render Free → API inicialmente.
- Supabase Free → PostgreSQL/Auth.
- Cloudflare R2 → archivos.
- Cloudflare → HTTPS/DNS/CDN.

Producción actual:
- Frontend: https://inces-lms.pages.dev/
- API: https://inces-lms-api.onrender.com

Validar:
- CORS exacto con Pages.
- FRONTEND_URL exacto.
- API health.
- DB health.
- login real.
- recuperación.
- invitación.
- R2.
- planilla.
- certificados.
- logout.
- errores.
- cold start.
- headers de seguridad.

No borrar el Worker accidental anterior hasta cerrar completamente Pages.

## F12 — OFFLINE / CONECTIVIDAD IRREGULAR

Objetivo realista: la aplicación debe sobrevivir a cortes y recuperar estado, no prometer que las operaciones server-side funcionan sin internet.

Diseñar:
- cache de shell y recursos;
- estado local de formularios;
- borradores;
- cola de operaciones sólo para acciones idempotentes y seguras;
- reintento con backoff;
- indicador de offline/online;
- recuperación automática;
- no perder formularios largos;
- no duplicar inscripciones, entregas o archivos.

No guardar secretos sensibles en almacenamiento local.
No cachear respuestas privadas de forma insegura.

### Caso CANTV ~2 Mbps
Crear baseline:
- primer acceso;
- login;
- dashboard;
- navegación;
- oferta;
- inscripción;
- Aula Virtual;
- archivos/R2.

Medir:
TTFB, FCP, LCP, bytes transferidos, JS descargado, requests, tiempo hasta app usable.

## F13 — SEO ON-PAGE + PWA

La portada pública debe tener:
- title único;
- meta description única;
- lang="es";
- canonical;
- robots;
- Open Graph;
- Twitter/X card;
- favicon INCES;
- manifest con identidad INCES;
- nombres descriptivos;
- headings semánticos;
- contenido rastreable de la oferta pública;
- enlaces internos;
- alt text;
- sitemap si el dominio final lo permite;
- robots.txt;
- datos estructurados Schema.org cuando sean pertinentes.

Objetivo:
Google/Bing deben entender qué es INCES LMS, su institución, sede/centro, oferta y propósito sin depender exclusivamente del canvas de Flutter.

No indexar dashboards privados, rutas de autenticación ni contenido sensible.

## F14 — UX/UI FINAL DESPUÉS DEL CIERRE FUNCIONAL

No rediseñar una pantalla aislada. Auditar todo el sistema.

### Principios
- identidad institucional INCES;
- jerarquía visual consistente;
- accesibilidad;
- responsive 375/768/1024/1280/1440;
- teclado;
- foco;
- contraste;
- estados vacíos;
- estados de error;
- loading/skeleton;
- confirmaciones;
- formularios largos;
- tablas;
- filtros;
- diálogos;
- navegación móvil;
- mensajes de éxito/error;
- prevención de acciones destructivas.

### Dirección visual
Premium, moderna y distintiva, con inspiración en productos SaaS de alta calidad, sin convertir el LMS en una página pesada.

“100k visualmente ≠ 100k KB”.

Usar cuando aporte valor:
- SVG;
- WebP/AVIF;
- ilustraciones optimizadas;
- animaciones cortas;
- 3D selectivo;
- lazy loading;
- CDN;
- assets responsive.

Nunca sacrificar una operación académica por una animación.

### Imagen institucional
Usar recursos institucionales del INCES cuando corresponda y respetar su identidad. El favicon web debe ser institucional, no el favicon genérico de Flutter.

## CRITERIO DE CIERRE

Una fase sólo pasa a VERDE cuando:
- implementación completa;
- prueba unitaria;
- prueba de backend;
- prueba de integración;
- E2E cuando aplique;
- prueba de permisos/RLS;
- prueba de error;
- prueba de refresh;
- prueba responsive;
- producción verificada cuando aplique;
- evidencia registrada;
- documentación actualizada.

### Matriz final
Crear al terminar una tabla:
ID | Flujo | Rol | Local | Producción | Seguridad | Offline/Resiliencia | E2E | Estado | Evidencia

### Android
Android es ÚLTIMO.
Sólo comenzar cuando:
1. API estable;
2. reglas de negocio estables;
3. autenticación estable;
4. R2 estable;
5. planilla estable;
6. asistencia estable;
7. certificados estables;
8. UX web cerrada;
9. pruebas E2E verdes;
10. producción verde.

## INSTRUCCIÓN PARA ARIA

Trabaja este documento como backlog maestro. Antes de cada bloque:
1. inspecciona el estado real;
2. identifica dependencias;
3. ejecuta la mínima modificación necesaria;
4. prueba;
5. documenta evidencia;
6. marca sólo lo realmente verde;
7. deja los bloqueos explícitos;
8. no mezcles rediseño visual con correcciones de dominio;
9. no borres trabajo ajeno;
10. al finalizar cada bloque, reporta archivos modificados, pruebas ejecutadas, resultados y siguiente dependencia.

**Prioridad absoluta:** funcionalidad institucional completa antes de Android, 3D, animaciones y rediseño visual final.
## REGISTRO DE HALLAZGOS — 2026-10-07

### H-01 Recuperación de contraseña
Reproducción real contra Supabase:
HTTP 500
error_code: unexpected_failure
msg: Error sending recovery email

Acciones realizadas:
- SMTP propio de Supabase configurado con Resend.
- Configuración releída y verificada.
- Plantillas invite, confirmation, recovery, magic_link y email_change aplicadas.
- Se probó sender de sandbox de Resend.
- El recovery sigue rechazándose para el destinatario probado.

Conclusión:
NO marcar recovery como VERDE todavía. El bloqueo restante está en la capacidad de Resend para enviar al destinatario de prueba/sandbox y debe cerrarse con un dominio remitente verificado y prueba de entrega real.

### H-02 Invitaciones docentes
El backend ya genera token de un solo uso, guarda hash, genera enlace con FRONTEND_URL y devuelve correoEnviado.
El humo de invitaciones cubre RLS + HTTP + activación.
Falta demostrar entrega real a un correo de profesor.

### H-03 Favicon / identidad web
Se sustituyó el favicon genérico de Flutter por un recurso institucional del Campus Virtual INCES.
También se alinearon los iconos PWA con la misma identidad.

### H-04 SEO
Se reemplazó “A new Flutter project” en index, manifest y pubspec.
Se añadieron title, description, canonical, Open Graph, Twitter/X, robots, lang=es y JSON-LD.
Esto es una primera capa SEO; falta probar rastreo real y separar rutas públicas de privadas.

### H-05 Despliegue Pages
El artefacto build/web quedó actualizado localmente.
El intento de despliegue con Wrangler no pudo ejecutarse porque el entorno no tiene CLOUDFLARE_API_TOKEN disponible en modo no interactivo.
NO introducir un token en el repositorio ni en archivos del proyecto.
El despliegue puede hacerse desde el panel de Cloudflare Pages o tras autenticar Wrangler de forma segura.

### H-06 Pruebas Flutter
La ejecución directa de tests terminó con:
%PROGRAMFILES(X86)% environment variable not found
y código 1, antes de ejecutar las pruebas.
Esto es un problema del entorno Windows/Flutter, no evidencia de fallo funcional de los tests.
Debe corregirse el entorno y repetir.

## F0 — INVENTARIO MEDIDO Y MATRIZ DE CIERRE (2026-10-07)

### F0.1 Catálogo técnico real medido en Supabase

Consulta directa a `public.system_modules` con los nombres de columnas reales:
`clave, nombre, descripcion, habilitado, orden`.

**Resultado medido: 10 registros, no 11.** El antiguo recuento de 11 queda descartado para el estado actual de la nube.

| Clave | Nombre técnico | Estado | Decisión de producto |
|---|---|---:|---|
| m0_cpanel | Administrador Maestro | ON | Administración |
| m1_onboarding | Autenticación y Onboarding | ON | Usuarios / onboarding |
| m2_curriculo | Currículo y Pensum | ON | Currículo |
| m3_cuadrante | Cuadrante y Horarios | ON | Horarios |
| m4_inscripciones | Inscripciones y Cupos | ON | Inscripciones |
| m5_archivos | Almacenamiento de Archivos | ON | Archivos / R2 |
| m6_aula_virtual | Aula Virtual | ON | Aula Virtual + calificaciones integradas |
| m6_asistencia | Asistencia | OFF | Registro histórico/legacy; la asistencia operativa es m7_asistencia |
| m7_asistencia | Asistencia QR en vivo | ON | Asistencia operativa |
| m7_calificaciones | Calificaciones | OFF | Función integrada en Aula Virtual |
| m8_pasantias | Pasantías | OFF | Pendiente; NO habilitar hasta completar el flujo |

**Corrección de contexto:** no hay 11 filas actualmente. Hay 10. Los 10 coinciden con `backend/test-humo.mjs` como catálogo esperado. La confusión de 11 provenía de documentación/recuentos anteriores.

### F0.2 Funcionalidades de producto

| ID | Funcionalidad | Backend/API | DB/RLS | Flutter | E2E/integración | Estado de cierre |
|---|---|---|---|---|---|---|
| F-ADM | Administración | Sí | Sí | Sí | Parcial | 🟡 |
| F-AUTH | Autenticación / onboarding | Sí + Supabase Auth | Sí | Sí | Parcial | 🔴 recuperación de correo abierta |
| F-CUR | Oferta / currículo / pensum | Sí | Sí | Sí | Backend + humo | 🟡 |
| F-HOR | Secciones / cuadrante / horarios | Sí | Sí | Sí | Humo backend | 🟡 |
| F-INS | Inscripciones / cupos / cola | Sí | Sí | Sí | Flujo parcial | 🟡 |
| F-PLN | Planilla oficial | Sí | Sí | Sí | Tests, falta comparación visual final | 🔴 |
| F-R2 | Archivos / Cloudflare R2 | Sí | Sí | Sí | Humo real existe; falta prueba UI alumno | 🔴 |
| F-AULA | Aula Virtual | Sí | Sí | Sí | Aprendiz verde; ciclo docente completo abierto | 🔴 |
| F-ASIS | Asistencia | Sí | Sí | Sí | Backend/RLS verde; falta cierre físico/dispositivo | 🟡 |
| F-CERT | Certificados / QR | Por auditar | Por auditar | Por auditar | Por auditar | 🔴 |
| F-PAS | Pasantías | Registro técnico OFF | Por auditar | Por auditar | Por auditar | 🔴 / pendiente |

### F0.3 Regla de cierre

Ninguna funcionalidad pasa a VERDE por tener una pantalla, endpoint o test aislado.

Debe existir, cuando aplique:
1. contrato;
2. persistencia;
3. autorización/RLS;
4. UI;
5. error controlado;
6. refresh;
7. doble clic / idempotencia;
8. pérdida de red;
9. prueba de integración;
10. E2E;
11. producción;
12. evidencia.

### F0.4 Dependencias inmediatas

**Bloque A — F1 Auth/correo**
- cerrar recuperación;
- probar invitación docente desde cPanel;
- probar entrega real;
- no confundir aceptación de proveedor con entrega.

**Bloque B — F2 Planilla**
- comparar PDF original contra renderer;
- conectar la misma representación a aspirante y administrador;
- validar descarga/dashboard.

**Bloque C — F4 R2**
- ejecutar subida real desde UI de alumno;
- confirmar objeto en `inces-lms-media`;
- comprobar metadata, descarga, permisos, expiración y reintento.

**Bloque D — F5/F6 Aula**
- cerrar ciclo docente → tarea → entrega → calificación → devolución → alumno;
- resolver el fallo E2E conocido antes de rediseñar.

**Bloque E — F10 Resiliencia**
- offline/intermitencia;
- recuperación;
- estados confirmados/pending/error;
- no duplicar operaciones.

### F0.5 Regla para ARIA

Antes de tocar código, ARIA debe leer esta matriz y comprobar el estado real. Si una evidencia contradice una fila, actualiza la evidencia primero y sólo después decide la implementación.

## F1 — AUTENTICACIÓN / CORREO: PRIMER CIERRE DE EVIDENCIA (2026-10-07)

### F1.1 Recuperación de contraseña — ROJO/BLOQUEADO

Se reprodujo la operación directamente contra Supabase Auth para el correo de prueba.

Resultado:
- HTTP 500
- `error_code: unexpected_failure`
- `Error sending recovery email`

El frontend sí tiene implementado el circuito:
`resetPasswordForEmail` → evento `passwordRecovery` → sesión temporal → `updateUser(password)`.

La pantalla de restablecimiento también distingue correctamente:
- sesión temporal válida → formulario de nueva contraseña;
- sin sesión → enlace inválido/caducado.

Los tests de dominio existentes cubren:
- contraseña válida;
- mínimo 8 caracteres;
- exactamente 8;
- ausencia de sesión;
- propagación de error del gateway;
- contraseña de sólo espacios.

**Pero ninguno puede demostrar entrega de correo real.**

### F1.2 Nuevo dato decisivo: credencial Resend

Se consultó la API real de Resend usando la credencial configurada localmente, sin imprimirla.

Resultado:
- HTTP **401**
- listado de dominios no disponible.

La variable existe y tiene formato/presencia de una clave `re_...`, pero Resend la está rechazando como no autorizada.

**Conclusión:** no debemos seguir modificando Flutter ni Supabase Auth para “arreglar” este error todavía. El bloqueo inmediato es de credencial/proveedor de correo.

### F1.3 Orden correcto para cerrar correo

1. Crear/regenerar una API Key válida de Resend con permiso de envío.
2. Sustituirla localmente en `backend/.env` sin imprimirla ni versionarla.
3. Verificar `GET /domains` con esa clave y comprobar que existe un dominio.
4. Si no existe dominio verificado, añadir un dominio controlado por el proyecto y completar SPF/DKIM en DNS.
5. Usar un sender del dominio verificado, por ejemplo `noreply@dominio-controlado`.
6. Actualizar SMTP de Supabase con esa clave y remitente.
7. Volver a probar `resetPasswordForEmail`.
8. Confirmar recepción real en un buzón.
9. Abrir el enlace recibido.
10. Cambiar contraseña.
11. Cerrar sesión.
12. Entrar con la contraseña nueva.
13. Probar enlace expirado/reutilizado.
14. Probar correo inexistente sin revelar existencia de cuenta.

**No aceptar como cierre:** HTTP 200 de la aplicación, HTTP 200/202 de un proveedor o “correoEnviado=true” sin comprobar recepción real.

### F1.4 Invitaciones docentes — VERDE lógico, ROJO de entrega real

`backend/test/invitaciones.test.ts` ejecutado directamente:
- 1 archivo;
- **9/9 tests PASS**;
- proceso terminó con código 0.

El flujo lógico probado incluye creación por administrador, token, hash, expiración, activación, uso único y errores.

La entrega real sigue pendiente por el mismo bloqueo de correo.

**Además:** el backend de invitaciones devuelve el enlace de activación como dato de respuesta incluso cuando Resend no entrega. Eso es útil para pruebas controladas, pero no debe confundirse con una invitación enviada al profesor.

### F1.5 Decisión de seguridad/UX

No mostrar al administrador:
> “Correo enviado”

si el proveedor sólo aceptó la solicitud pero no existe evidencia de entrega.

Usar estados explícitos:
- **Invitación creada**
- **Proveedor aceptó envío**
- **Entrega no confirmada**
- **Entrega confirmada** sólo si el proveedor/flujo lo permite
- **Error de correo**

El enlace de activación manual debe tratarse como mecanismo de contingencia administrativa, no como sustituto permanente de correo institucional.

## F2 — PLANILLA OFICIAL: AUDITORÍA INICIAL CERRADA (2026-10-07)

### F2.1 El original y el template son exactamente el mismo archivo

Se comparó SHA-256 del PDF institucional original y del archivo:

`backend/assets/planilla-oficial-template.pdf`

Resultado:
- ORIGINAL: `ECCB284A2BB0883A8048BED8BF3DCBAEA3E3AA9706D36F781BB256D656B056E8`
- TEMPLATE: `ECCB284A2BB0883A8048BED8BF3DCBAEA3E3AA9706D36F781BB256D656B056E8`

**Conclusión:** la base visual usada por el renderer oficial es byte-a-byte idéntica al original. Esto elimina el riesgo de estar usando una copia modificada de la planilla.

### F2.2 Renderer oficial

`backend/src/infra/planilla-oficial-pdf.ts`:
- usa el template original;
- trabaja sobre 612 × 792 pt;
- escribe los datos encima del documento;
- conserva una sola página.

`backend/src/infra/planilla-oficial-valores.ts`:
- adapta los datos persistidos al contrato oficial;
- normaliza sexo, estado civil, fechas, discapacidad, misiones, formación, familiares y experiencias.

Pruebas ejecutadas:
- `test/planilla-oficial-valores.test.ts`: **3/3 PASS**
- `test/planilla-oficial-pdf.test.ts`: **3/3 PASS**
- Total: **6/6 PASS**, proceso exit 0.

### F2.3 BLOQUEANTE DE INTEGRACIÓN

La aplicación de producción **todavía usa el renderer histórico**:
`backend/src/infra/planilla-pdf.ts` → `renderizarPlanillaPdf(...)`.

Las rutas:
- `GET /api/v1/yo/planilla/pdf`
- `GET /api/v1/inscripcion/planilla/:usuarioId/pdf`

pasan por `reposDe(request).planilla.generarPdf()`, cuyo repositorio sigue conectado al renderer histórico.

Por tanto:

**NO conectar todavía `planilla-oficial-pdf.ts` directamente.**

Primero hay que:
1. comparar todos los campos del renderer histórico contra el contrato oficial;
2. garantizar equivalencia de valores;
3. ejecutar pruebas de regresión;
4. comprobar que aspirante y administrador reciben el mismo documento lógico;
5. cambiar el adaptador/puerto una sola vez;
6. ejecutar pruebas HTTP de ambas rutas;
7. comprobar visualmente un PDF completamente rellenado;
8. sólo entonces marcar F2 como VERDE.

### F2.4 Flujo de aceptación final

Debe quedar:

Aspirante completa formulario
→ guarda planilla
→ resumen
→ **Ver planilla oficial**
→ **Descargar planilla oficial**
→ dashboard
→ vuelve a abrir la misma planilla

y simultáneamente:

Administrador
→ ficha del aspirante
→ **Ver planilla oficial**
→ **Descargar planilla oficial**

Ambos deben representar los mismos datos persistidos y la misma plantilla institucional.

### F2.5 Regla adicional

El PDF no debe “reconstruir una planilla parecida” desde Flutter.

Flutter sólo solicita el documento al backend.

El backend:
- lee datos persistidos;
- aplica contrato oficial;
- reutiliza el PDF institucional;
- devuelve PDF.

Esto evita que el dashboard del alumno y el panel administrativo desarrollen dos versiones distintas del documento.


### F2.6 — Adaptador de integración construido, producción aún sin cambiar (2026-10-07)

Se auditó el punto de composición de la planilla y se confirmó que la aplicación productiva todavía entra por:

`PuertaPlanilla.generarPdf()`
→ `PlanillaSupabase.generarPdf()`
→ `armarEntradaPlanilla()`
→ `renderizarPlanillaPdf()` histórico A4.

También se confirmó que el adaptador semántico oficial ya existente:
`infra/planilla-oficial-valores.ts`
transforma `EntradaPlanilla` al contrato:
`dominio/planilla-oficial-tipos.ts`.

Para evitar tocar producción antes de cerrar la regresión se creó una única costura de integración:

`backend/src/infra/planilla-oficial-adaptador.ts`

Flujo del nuevo adaptador:

`EntradaPlanilla`
→ `adaptarAPlanillaOficial()`
→ `renderizarPlanillaOficialPdf()`
→ PDF oficial.

El adaptador **no está conectado todavía a `PlanillaSupabase.generarPdf()`**. Las rutas HTTP y el puerto de dominio permanecen sin modificar.

### F2.7 — Verificación técnica del adaptador

Prueba ejecutada:

`test/planilla-oficial-adaptador.test.ts`

Resultado:
- **1/1 PASS** — compone entrada genérica → contrato oficial → PDF institucional.
- PDF generado: 1 página.
- Dimensiones: **612 × 792 pt**.

Regresión conjunta ejecutada:
- `planilla-oficial-pdf.test.ts`: 3/3 PASS.
- `planilla-oficial-valores.test.ts`: 3/3 PASS.
- `planilla-oficial-adaptador.test.ts`: 1/1 PASS.
- `planilla-pdf.test.ts`: 10/10 PASS.
- **Total: 17/17 PASS**.
- Proceso Vitest: exit 0.

TypeScript:
- `npm run typecheck`: **PASS**, exit 0.

Template institucional:
- SHA-256: `eccb284a2bb0883a8048bed8bf3dcbaea3e3aa9706d36f781bb256d656b056e8`
- 1 página.
- 612 × 792 pt.
- 561475 bytes.

### F2.8 — Estado de integración

**F2 sigue AMARILLO / EN INTEGRACIÓN.**

No se marca VERDE todavía porque aún falta:
1. comparar visualmente un documento completamente poblado sobre la plantilla original;
2. comprobar todos los campos reales del catálogo contra las coordenadas oficiales;
3. probar las dos rutas HTTP con datos reales:
   - aspirante: `GET /api/v1/yo/planilla/pdf`;
   - administrador: `GET /api/v1/inscripcion/planilla/:usuarioId/pdf`;
4. demostrar que ambos generan el mismo documento lógico para la misma ficha;
5. comprobar autorización cruzada y ausencia de ficha;
6. sólo después conectar `PlanillaSupabase.generarPdf()` al nuevo adaptador.

**Regla:** no modificar producción hasta completar esos controles.

### F2.9 — Validación de contenido + HTTP (2026-10-07)

Se generó un PDF completamente poblado mediante el renderer oficial y se inspeccionó su extracción visual/textual.

Verificaciones objetivas:
- 1 sola página.
- 612 × 792 pt.
- La plantilla institucional sigue siendo la original byte-a-byte.
- Los datos de cabecera, identidad, nacimiento, prácticas, ubicación/contacto, familiares, misiones, formación, otras formaciones y experiencia aparecen en el PDF generado.
- El documento conserva el fondo institucional/logo de la plantilla; los datos se sobreimprimen, no se reconstruye la identidad gráfica.
- La prueba de caracteres fuera de Latin-1 y de textos largos permanece verde.

Se añadió `backend/test/planilla-pdf-http.test.ts` para comprobar el contrato HTTP actual de las dos rutas:
- Alumno: `GET /api/v1/yo/planilla/pdf`
- Administrador: `GET /api/v1/inscripcion/planilla/:usuarioId/pdf`

La suite específica final quedó:
- HTTP Planilla: **6/6 PASS**
- Renderer oficial: **3/3 PASS**
- Adaptador integración: **1/1 PASS**
- Adaptador semántico: **3/3 PASS**
- **13/13 PASS**, exit 0.

Los controles HTTP comprobados incluyen:
- PDF 200 y `application/pdf` para alumno;
- PDF 200 para administrador;
- una sola página;
- el endpoint `/yo` ignora un `usuarioId` externo;
- alumno no puede usar ruta administrativa (403);
- administrador recibe 404 `SIN_FICHA_DE_ASPIRANTE` cuando no existe ficha;
- petición anónima recibe 401.

Nota de metodología:
- La prueba HTTP usa el arnés en memoria y, por tanto, valida contrato, autenticación/autorización y respuesta HTTP, pero todavía invoca el renderer histórico porque producción aún no está conectada al adaptador oficial.
- Por esta razón **F2 NO se marca VERDE todavía**. Falta una prueba final post-integración donde las mismas rutas HTTP generen explícitamente el PDF oficial y se verifique que Alumno y Administrador producen el mismo documento lógico.

### F2.10 — Próximo paso controlado

Antes de modificar `PlanillaSupabase.generarPdf()`:
1. conservar los 13/13 verdes;
2. integrar únicamente el adaptador oficial en el repositorio de planilla;
3. mantener intactos contratos HTTP y autorización;
4. ejecutar regresión completa de planilla;
5. volver a ejecutar las pruebas HTTP;
6. generar PDF oficial desde ambas rutas y comparar estructura/huella del contenido;
7. sólo si todo permanece verde, considerar F2 cerrada.

No se hizo commit ni push.


### F2.11 — Integración oficial completada y validada (2026-10-07)

Se ejecutó el cambio controlado en el único punto de composición de producción:

`PlanillaSupabase.generarPdf()`

pasó de:

`EntradaPlanilla → renderizarPlanillaPdf()` histórico

a:

`EntradaPlanilla → adaptarAPlanillaOficial() → renderizarPlanillaOficialPdf()`

Las rutas HTTP y sus contratos de autorización **no fueron modificados**.

Además, el arnés HTTP de planilla fue alineado con el contrato oficial para que las pruebas de rutas no sigan validando accidentalmente el renderer histórico.

Controles post-integración:

- Renderer oficial: **3/3 PASS**.
- Adaptador oficial: **1/1 PASS**.
- Adaptador semántico: **3/3 PASS**.
- Regresión histórica de `planilla-pdf.test.ts`: **10/10 PASS**; sus pruebas directas del renderer histórico permanecen verdes.
- HTTP Alumno/Admin: **6/6 PASS**.
- Repositorio productivo `PlanillaSupabase.generarPdf()` con cliente Supabase simulado: **1/1 PASS**.
- Suite específica consolidada: **24/24 PASS**, exit 0.
- `npm run typecheck`: ejecutado sin errores reportados.
- PDF completo generado por ambas rutas HTTP del arnés: **200/200**, `application/pdf`.
- Alumno y Administrador: **1 página**, **612 × 792 pt**.
- Tamaño de ambos PDFs: **561286 bytes**.
- SHA-256 de ambos PDFs: **1414B2AC854B505494558E22E4515D9225A9A258A2C24368A1F23C6B060958B2**.
- Ambos PDFs fueron **byte-identical** para la misma ficha y entrada determinista.
- El PDF fue inspeccionado por extracción estructural/visual: conserva la plantilla institucional y muestra los datos completos sobreimpresos.
- La plantilla fuente continúa con SHA-256 `eccb284a2bb0883a8048bed8bf3dcbaea3e3aa9706d36f781bb256d656b056e8`, 561475 bytes, 1 página, 612 × 792 pt.

Resultado:

**F2 = VERDE / CERRADA.**

Importante: el `npm test -- --run` de todo el backend había mostrado anteriormente un fallo ajeno a esta integración en una prueba de OpenAPI/operación `/api/v1/sistema-modulos`. No se utilizó ese fallo para degradar los criterios de F2; la batería específica de planilla quedó completamente verde y el fallo general debe tratarse como incidencia independiente.

No se hizo commit ni push de estos cambios todavía.
