# ESTADO DEL SISTEMA — INCES LMS

> **Documento puente vivo.** Describe el estado **real** del proyecto: lo que está
> construido, lo que está verificado y lo que falta. Se actualiza al cerrar cada
> fase. Si algo aquí contradice a otro archivo, manda este.
>
> **Última actualización:** 2026-09-13 · Fases 1, 2 y 3 cerradas. **Base de datos
> desplegada y verificada en la nube.** Primer administrador creado. API probada
> de extremo a extremo contra Supabase real. D6 (OpenAPI) resuelta. Repositorio
> publicado en GitHub.

---

## 1. Resumen ejecutivo

| Fase | Alcance | Estado |
| --- | --- | --- |
| **Fase 0** | Esquema base, RLS, roles, migraciones versionadas | ✅ Completa |
| **Fase 1** | Auth y onboarding atómico de aspirantes | ✅ Completa |
| **Fase 2** | API stateless Node/TypeScript + Docker | ✅ Completa |
| **Fase 3** | Núcleo del Administrador Maestro (cPanel) | ✅ Completa |
| **M5** | Almacenamiento R2 (servicio + puerto) | 🟡 Construido, sin credenciales |
| **D8** | Protección del último administrador activo | ✅ Completa |
| **D6** | OpenAPI 3.1 generado desde Zod | ✅ Completa |
| **Fase 4+** | M2 Currículo … M8 Pasantías | ⏳ Pendiente |

**Verificación al cierre de esta iteración**

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Sin problemas |
| `flutter test` | **88 / 88** en verde |
| Validador SQL contra PostgreSQL real | **49 / 49** aserciones en verde |
| **Migraciones aplicadas a la nube** | **4 / 4** aplicadas y verificadas |
| **Verificación independiente del esquema en la nube** | **30 / 30** comprobaciones |
| **Prueba de humo contra la nube real** | **24 / 24** comprobaciones |
| `npm run typecheck` (backend) | Sin errores |
| `npm run lint` (backend) | Sin errores |
| `npm test` (backend) | **138 / 138** en verde |
| `npm run build` (backend) | Compila sin errores |
| Documento OpenAPI | OpenAPI 3.1.0 · 11 rutas · 17 esquemas |
| Proyecto Supabase en la nube | `ACTIVE_HEALTHY` (región sa-east-1, PostgreSQL 17.6) |
| Repositorio GitHub | `Burmistrov4/INCES---LMS` (rama `main`) |

---

## 2. Estado de despliegue

### Lo que está desplegado

**La base de datos ya está aplicada y verificada.** Las cuatro migraciones se
aplicaron el 2026-09-13 contra el proyecto real `twdppwnxlnmxkiejbrei` y el
resultado se comprobó después, consultando el catálogo de PostgreSQL por
separado: 8 tablas con RLS activo, los 6 triggers y funciones que sostienen las
invariantes, 9 módulos sembrados, 8 parámetros y 5 cursos.

**La API está probada contra esa base.** No con dobles de prueba: con el proceso
real hablando con Supabase real, usando un token emitido por GoTrue y
verificando la firma contra el proyecto. 24 comprobaciones, incluidas las que
importan (el 401 sin sesión, el 409 de auto-degradación y el 400 de un id que no
es UUID).

**Hay una sola cuenta de administrador**, y es la real de Lorenzo:

| Correo | Estado | Nota |
| --- | --- | --- |
| `lorenzo-roca11@hotmail.com` | Confirmada, en uso | **La cuenta real de Lorenzo** (con guion), rol `admin`, `active = true` |

Esta cuenta nació de un error de diagnóstico que conviene tener presente: en una
captura apareció `lorenzo- roca11@hotmail.com` y se interpretó como error de dedo
cuando **era la dirección correcta**. La cuenta original se había creado sin
guion, y por eso Supabase no encontraba al usuario real al solicitar la
recuperación.

La cuenta sin guion (`lorenzoroca11@hotmail.com`) fue **eliminada** el
2026-09-13 con `supabase/eliminar-cuenta.mjs`, tras comprobar que ninguna tabla
la referenciaba. El script hace ese inventario antes de borrar y **se niega a
proceder** si encuentra referencias: `profiles.id` es el `auth.uid()` de todas
las políticas RLS, y borrarlo con filas apuntando a él dejaría registros colgando
de un usuario inexistente. También verifica D8 antes de intentarlo, para no
chocar con `proteger_ultimo_admin` y recibir un error de Postgres que no explica
nada.

> **Regla para el futuro:** un script que borra datos de producción se escribe
> primero en modo simulación, y no escribe hasta que se le pasa `--confirmar`.
> Borrar una cuenta no tiene papelera.

**Cómo se inicia sesión:** en el campo «Cédula o Correo» se escribe el **correo
completo**. `AuthService.iniciarSesion` detecta el `@` y salta la búsqueda por
cédula; si no hay `@`, busca la cédula y, al no encontrarla, responde con un
mensaje genérico a propósito (no revela si la cédula existe).

## Correo transaccional: resuelto con SMTP propio (Resend)

**Hallazgo con impacto directo en el TEG, y su resolución.** El proveedor de
correo por defecto de Supabase imponía tres limitaciones a la vez: los mensajes
salían de `no-reply@mail.app.supabase.io` (dominio genérico, marcado como spam
con frecuencia), el límite era de **2 correos por hora**, y las plantillas
**no se podían editar** — al intentarlo, la API respondía HTTP 400:

> *«Email template modification is not available for free tier projects using
> the default email provider. Please upgrade your plan or configure a custom
> SMTP provider.»*

Los tres síntomas parecían tres problemas («no llega», «sale en inglés», «sólo
llegan dos»). Eran **uno solo**: el proveedor por defecto. Haberlos atacado por
separado habría sido trabajo perdido.

**Estado actual: SMTP propio activo** vía Resend, aplicado con
`supabase/configurar-smtp.mjs` (relee la configuración tras escribirla; un `PATCH`
puede responder 200 sin aplicar nada). Las cinco plantillas están en español con
identidad institucional, aplicadas con `supabase/personalizar-plantillas.mjs`.

| Ajuste | Valor |
| --- | --- |
| `smtp_host` | `smtp.resend.com:465` |
| `smtp_user` | `resend` (la contraseña es la propia API key) |
| `smtp_admin_email` | `lorenzoroca333@gmail.com` — **el dueño de la cuenta de Resend** |
| `rate_limit_email_sent` | 30 (era 2) |

### Límite que sigue vigente, y que conviene no confundir con un fallo

**Sin un dominio verificado, Resend sólo entrega a la dirección del dueño de la
cuenta.** Cualquier envío a otro destinatario se rechaza:

```
403 validation_error — "You can only send testing emails to your own email
address (lorenzoroca333@gmail.com). To send emails to other recipients,
please verify a domain at resend.com/domains"
```

Esto afecta a **todo** el sistema mientras no exista dominio: un aspirante que se
inscriba con su correo no recibirá la confirmación, y un docente invitado tampoco.
No es un error de configuración — la configuración es correcta y el canal funciona
(probado contra la API de Resend: `200` con id de mensaje). Es un límite de la
cuenta.

**Consecuencia práctica:** todo el flujo de correo se puede probar hoy usando
`lorenzoroca333@gmail.com` como destinatario. Verificar un dominio es el paso
siguiente y desbloquea el uso real.

> **Lección de verificación, anotada en el TEG.** Configurar bien un canal no es
> lo mismo que el canal funcione. El `PATCH` de configuración respondió 200 y los
> cinco campos se releyeron correctos, y el primer correo dio 500 igual. Un 200 de
> escritura no es una prueba: hay que enviar algo de verdad y comprobar que llega.

También se descartó configurar el SMTP a mano en el panel: un cambio manual no
queda en el historial ni se puede revisar en un diff.

> No hay credenciales por defecto ni usuario semilla en el repositorio. La
> contraseña la fijó el propio Lorenzo y sólo él la conoce: no está escrita en
> ningún archivo del proyecto, ni debe estarlo.

### Cómo se aplicó, y por qué no con `supabase db push`

| Elemento | Estado |
| --- | --- |
| Proyecto Supabase `twdppwnxlnmxkiejbrei` | ✅ Creado, vivo, `ACTIVE_HEALTHY` |
| Clave publicable verificada contra la nube | ✅ Válida |
| Credenciales inyectadas en `backend/.env` y `.env.json` | ✅ Hecho |
| Migraciones aplicadas y verificadas | ✅ **Las 4** |
| Primer administrador creado | ✅ `lorenzo-roca11@hotmail.com` (rol `admin`) |
| API probada contra la nube real | ✅ 24 / 24 comprobaciones |
| API publicada | ❌ Pendiente (falta elegir host) |
| Frontend publicado | ❌ Pendiente (falta dominio propio) |

`supabase login` es **interactivo** (abre el navegador o pide el token por
consola), así que se usa `SUPABASE_ACCESS_TOKEN`, que es la variable que el
propio CLI acepta para entornos no interactivos.

### Hallazgo: la conexión directa no es alcanzable desde esta red

El host directo de la base de datos resuelve **sólo a IPv6**:

```
db.twdppwnxlnmxkiejbrei.supabase.co  →  2600:1f1e:c3:2701:7483:2adb:882e:2d67
```

Y no hay salida IPv6 en esta red: la conexión falla con `ENETUNREACH` antes de
enviar una sola consulta. Esto **no es un caso exótico**: es lo habitual en
conexiones residenciales, y afecta directamente a `supabase db push`, que abre
una conexión TCP a ese host.

Hay dos caminos, y el segundo es el que se usó:

| Vía | Requiere | ¿Funciona aquí? |
| --- | --- | --- |
| `supabase db push` (CLI oficial) | Token de acceso **y** contraseña de la base | ❌ Choca con IPv6 |
| `supabase/apply-migrations.mjs` (API de administración) | Sólo token de acceso | ✅ HTTPS por IPv4 |

```bash
# Comprobar sin aplicar nada
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --check

# Aplicar las 4 migraciones y verificar el resultado
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs

# Comprobar el esquema resultante contra el catálogo de PostgreSQL
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs
```

### Obstáculo encontrado: el proyecto traía un esquema heredado que chocaba

A la primera aplicación, la migración 0001 falló con
`42703 column "user_id" does not exist`. No era un error de la migración: el
proyecto de Supabase se había usado antes para prototipar **otro** diseño, desde
el editor SQL, y había dejado siete tablas huérfanas.

| Tabla heredada | Columnas que la delatan |
| --- | --- |
| `aspirantes` | `cedula_pasaporte`, `pueblo_indigena`, `tiene_diversidad_funcional` |
| `cursos` | `titulo`, `duracion_horas` |
| `cohortes` | `codigo_seccion`, `facilitador_id` |
| `inscripciones`, `actividades`, `entregas`, `asistencias` | Diseño sin relación con el actual |

`public.aspirantes` era el problema real: la migración dice
`create table if not exists`, así que encontró una `aspirantes` que ya existía con
otro diseño y **no hizo nada**. Sin error. A partir de ahí, los `insert` y las
políticas de la migración apuntaban a columnas que no existían.

Se comprobó antes de tocar nada: **cero filas** en las siete tablas, cero
usuarios en `auth.users`, sin triggers, sin funciones y sin historial de
migraciones (`supabase_migrations.schema_migrations` no existía). Era andamiaje
abandonado, no datos. Su `aspirantes` además tenía una política RLS que permitía
a cualquier usuario autenticado leer y escribir todo (`auth.role() =
'authenticated'`), así que dejarla no era una opción neutral.

`supabase/limpiar-esquema-heredado.mjs` elimina ese andamiaje y comprueba que
`public` queda vacío antes de dar por hecho el trabajo. Después, las cuatro
migraciones aplicaron sin incidencias.

> **Nota para el TEG:** merece mención en la memoria que la tabla `aspirantes`
> del prototipo tenía RLS abierta a todo usuario autenticado. Es un ejemplo real
> y concreto de por qué las políticas se auditan: `create table if not exists`
> sobre un esquema preexistente no falla, simplemente ignora, y el fallo aparece
> mucho después y en otro sitio.

### Crear el primer administrador

No hay forma de crear el primer administrador desde la aplicación, y es
deliberado: el auto-registro nunca otorga rol (ADR-008) y el trigger
`handle_new_user()` fija `estudiante`. Si la app pudiera promoverse a sí misma,
cualquiera con la clave publicable —que viaja en el bundle del navegador— sería
administrador del INCES.

```bash
# Crea (o invita) la cuenta y la promueve. Requiere la clave SECRETA.
node supabase/crear-admin.mjs correo@dominio.com --dry-run   # simulacro
node supabase/crear-admin.mjs correo@dominio.com             # real
```

Guarda el rol en `profiles` con un `UPDATE`, para que dispare la auditoría y
`updated_at`, y **verifica el resultado contra la base** antes de darlo por
bueno: un `PATCH` que responde 200 no prueba que la fila quedara bien.

### Lo que está listo para desplegar

| Componente | Artefacto | Comando |
| --- | --- | --- |
| Base de datos | 4 migraciones SQL | ✅ Ya aplicadas a la nube |
| API | Imagen Docker multi-etapa | `docker compose up -d api` |
| Frontend | App Flutter | `flutter build web --release` |

### Pasos para publicar la API y el frontend

```bash
# 1. API en local (contra la base de la nube)
docker compose up -d api
curl http://localhost:3000/salud/profundo

# 2. Comprobación de extremo a extremo contra la nube real
node backend/test-humo.mjs

# 3. Frontend web
flutter build web --release --dart-define-from-file=.env.json
```


### Arquitectura dual

La misma imagen sirve para los dos escenarios, sin ramas ni parches:

- **Nube:** `docker compose up -d api`. Stateless, sin volúmenes, `read_only`,
  usuario sin privilegios, healthcheck. Escala a N réplicas sin sesiones
  pegajosas porque el estado vive en el JWT.
- **Local:** `docker compose --profile dev up` (recarga en caliente) contra
  `supabase start` en `http://host.docker.internal:54321`.

---

## 3. Esquema de base de datos

PostgreSQL sobre Supabase. **Relacional.** La migración a MongoDB se evaluó y se
**canceló** (ADR-006). No reintroducir.

### Tablas

| Tabla | Origen | Propósito |
| --- | --- | --- |
| `cursos` | Fase 0 | Catálogo de propuestas formativas |
| `profiles` | Fase 0 | Identidad y rol. Espejo de `auth.users` |
| `aspirantes` | Fase 0 | Ficha de inscripción del aspirante |
| `sections` | Fase 0 | Secciones con cupo (M3) |
| `enrollments` | Fase 0 | Matrículas y estados de cupo (M4) |
| `system_modules` | **Fase 3** | Interruptores de módulos del cPanel |
| `system_settings` | **Fase 3** | Parámetros operativos editables |
| `config_audit_log` | **Fase 3** | Auditoría append-only de la configuración |

### Funciones y triggers

| Objeto | Tipo | Qué hace |
| --- | --- | --- |
| `handle_new_user()` | Trigger en `auth.users` | Crea `profiles` + `aspirantes` **en una transacción**. Rol fijo `estudiante` |
| `precheck_aspirante(cedula, email)` | RPC | Devuelve `OK` / `CEDULA_DUPLICADA` / `EMAIL_DUPLICADO` / `EMAIL_INVALIDO` / `CEDULA_REQUERIDA` |
| `link_pending_aspirante()` | RPC | Repara fichas huérfanas del bug anterior |
| `is_admin()` | Función | Comprueba rol admin y `active`. Usada por las políticas RLS |
| `set_updated_at()` | Trigger | Sella `updated_at` |
| `set_updated_by()` | Trigger | Sella `updated_at` + `updated_by` en `system_settings` |
| `audit_config_change()` | Trigger | Escribe en `config_audit_log` cada cambio de módulo o parámetro |
| `proteger_modulo_critico()` | Trigger | **Cortacircuitos:** impide apagar o borrar `m0_cpanel` |
| `proteger_ultimo_admin()` | Trigger | **Cortacircuitos (D8):** impide degradar, desactivar o borrar al último administrador activo. Usa un bloqueo de transacción para cerrar la carrera entre dos degradaciones simultáneas |

### Políticas RLS

| Tabla | Lectura | Escritura |
| --- | --- | --- |
| `profiles` | El propio perfil; admin ve todo | El propio (sin cambiar rol); admin todo |
| `aspirantes` | El propio; admin todo | El propio; admin todo. **Sin inserción anónima** |
| `system_modules` | Cualquier autenticado | **Solo admin** |
| `system_settings` | Públicos: `anon` + autenticados. Privados: solo admin | **Solo admin** |
| `config_audit_log` | **Solo admin** | **Nadie.** Único camino: el trigger |
| `sections` / `enrollments` | Activas / el propio | Admin / el propio |

**Nota sobre `config_audit_log`:** la auditoría tiene dos barreras independientes.
RLS no tiene política de escritura **y** no hay `GRANT` de escritura. Aunque
alguien añadiera una política por error, seguiría sin poder escribir.

### Semilla de módulos

| Clave | Nombre | Estado inicial | Roles |
| --- | --- | --- | --- |
| `m0_cpanel` | Administrador Maestro | 🟢 activo | `admin` |
| `m1_onboarding` | Autenticación y Onboarding | 🟢 activo | todos |
| `m2_curriculo` | Currículo y Pensum | ⚪ inactivo | todos |
| `m3_cuadrante` | Cuadrante y Horarios | ⚪ inactivo | todos |
| `m4_inscripciones` | Inscripciones y Cupos | ⚪ inactivo | todos |
| `m5_archivos` | Almacenamiento (R2) | ⚪ inactivo | todos |
| `m6_asistencia` | Asistencia | ⚪ inactivo | todos |
| `m7_calificaciones` | Calificaciones | ⚪ inactivo | todos |
| `m8_pasantias` | Pasantías | ⚪ inactivo | todos |

**`m9` (Certificados/QR) no se siembra:** quedó descartado del alcance.

Solo están encendidos los módulos que **existen de verdad**. Encender los demás
haría que la UI prometiera pantallas que no están construidas.

### Semilla de parámetros

| Clave | Tipo | Público | Valor inicial |
| --- | --- | --- | --- |
| `inscripciones_abiertas` | boolean | ✅ | `true` |
| `periodo_activo` | string | ✅ | `"2026-1"` |
| `modo_mantenimiento` | boolean | ✅ | `false` |
| `max_faltas_consecutivas` | number | ❌ | `3` |
| `bid_ttl_horas` | number | ❌ | `24` |
| `enrollment_lock_days` | number | ❌ | `2` |
| `cupo_maximo_por_seccion` | number | ❌ | `25` |
| `r2_presign_ttl_minutos` | number | ❌ | `15` |

---

## 4. Superficie de la API

Base: `/api/v1`. Todo error responde con la misma forma:
`{ "error": { "codigo", "mensaje", "detalles"? } }`

| Método | Ruta | Acceso | Qué hace |
| --- | --- | --- | --- |
| `GET` | `/salud` | público | Liveness. No toca la base de datos |
| `GET` | `/salud/profundo` | público | Readiness. 503 si la base no responde |
| `GET` | `/openapi.json` | público | El contrato, generado desde Zod (D6) |
| `GET` | `/api/v1/yo` | sesión | Perfil, rol y **solo los módulos visibles** |
| `GET` | `/api/v1/modulos` | sesión | Catálogo filtrado por rol |
| `GET` | `/api/v1/admin/modulos` | admin | Todos los módulos, incluidos los apagados |
| `PATCH` | `/api/v1/admin/modulos/:clave` | admin | `habilitado`, `orden`, `rolesPermitidos` |
| `GET` | `/api/v1/admin/parametros` | admin | Todos los parámetros |
| `PATCH` | `/api/v1/admin/parametros/:clave` | admin | Cambia `valor` validando el `tipo` |
| `GET` | `/api/v1/admin/auditoria` | admin | Historial (`?limite=`, 1–200) |
| `PATCH` | `/api/v1/admin/usuarios/:id/rol` | admin | Cambia el rol de un usuario |

### El contrato se genera, no se escribe (D6, resuelta)

`GET /openapi.json` sirve un documento **OpenAPI 3.1** que se construye en cada
petición a partir de los esquemas Zod de `src/http/esquemas.ts`. El archivo
`backend/openapi.json` del repositorio es el mismo documento, escrito por
`npm run openapi`.

**Por qué generarlo y no escribirlo a mano.** Un `openapi.yaml` escrito a mano es
un segundo contrato. El primero son los esquemas Zod, que son los que validan de
verdad en tiempo de ejecución. El segundo empieza siendo idéntico y se separa en
la primera semana: alguien añade un campo a `esquemaCambioRol`, los tests pasan, y
el documento sigue anunciando el contrato viejo. El cliente generado a partir del
YAML deja de compilar contra la API real y nadie lo nota hasta que lo sufre un
usuario. Generándolo, el documento es una *proyección* del único contrato que
existe: la deriva es imposible por construcción.

**Lo que el generador no puede adivinar.** Zod valida las entradas, no las
salidas: el backend devuelve objetos literales. Los esquemas de respuesta se
declaran a mano en `src/http/openapi.ts`. Y el generador tampoco sabe qué rutas
registra Fastify. Las dos cosas las cubre `test/openapi.test.ts`:

| Se comprueba | Por qué |
| --- | --- |
| Cada ruta documentada existe y responde (401 si es protegida, 200 si es pública) | Un 404 significaría que se inventó |
| La lista de rutas coincide exactamente con la esperada | Añadir una ruta obliga a documentarla |
| Ninguna operación carece de 200 o de 401 cuando exige sesión | Un contrato sin respuesta de éxito no sirve para generar clientes |
| Las sondas de salud y `/openapi.json` son las únicas públicas | Una ruta que quedara pública por descuido no pasaría |
| Lo que sirve `/openapi.json` es idéntico a lo que genera el script | El archivo del repo no puede divergir de lo servido |
| `openapi.json` en disco está al día | Obliga a que el `diff` muestre el cambio de contrato |

```bash
npm run openapi                                   # regenerar el artefacto
curl -s http://localhost:3000/openapi.json | head # el mismo documento, en vivo
```

### Códigos de error

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `NO_AUTENTICADO` | 401 | Sin token o token inválido |
| `CUENTA_INACTIVA` | 403 | Perfil con `active = false` |
| `SOLO_ADMIN` | 403 | Ruta de administración sin rol admin |
| `MODULO_DESHABILITADO` | 403 | El módulo está apagado en el cPanel |
| `MODULO_NO_AUTORIZADO` | 403 | El rol no está en la lista blanca del módulo |
| `PERMISO_DENEGADO` | 403 | RLS de PostgreSQL rechazó la operación |
| `MODULO_DESCONOCIDO` | 404 | La clave de módulo no existe |
| `PARAMETRO_DESCONOCIDO` | 404 | La clave de parámetro no existe |
| `RUTA_NO_ENCONTRADA` | 404 | Ruta inexistente |
| `MODULO_CRITICO` | 409 | Intento de apagar `m0_cpanel` |
| `AUTO_DEGRADACION` | 409 | Un admin intenta quitarse su propio rol |
| `ULTIMO_ADMIN` | 409 | El cambio dejaría el sistema sin administradores activos |
| `PERFIL_INEXISTENTE` | 404 | El usuario cuyo rol se quiere cambiar no existe |
| `PETICION_INVALIDA` | 400 | Fallo de validación (Zod, UUID de ruta o tipo de parámetro) |
| `SUPABASE_INALCANZABLE` | 503 | No se pudo contactar con la base de datos |
| `SERVICIO_NO_DISPONIBLE` | 503 | `modo_mantenimiento` activo |
| `ARCHIVO_NO_ENCONTRADO` | 404 | El objeto no existe en R2 |
| `ALMACENAMIENTO_DENEGADO` | 403 | R2 rechazó las credenciales o el permiso |
| `ERROR_ALMACENAMIENTO` | 500 | Fallo de R2 no clasificado |

---

## 5. Módulos activos en el código

### Frontend (Flutter 3.47 / Dart 3.13)

| Ruta | Estado | Notas |
| --- | --- | --- |
| `lib/main.dart` | ✅ | `AuthGate` con `home:` y sin ruta `'/'` (la aserción de Flutter lo exige). Intercepta `passwordRecovery` |
| `lib/screens/login_screen.dart` | ✅ | Consume `Result`, con enlace a inscripción y **enlace de recuperación** |
| `lib/screens/restablecer_password_screen.dart` | ✅ | Define la contraseña nueva; explica el enlace caducado |
| `lib/screens/aspirante_form_screen.dart` | ✅ | Formulario con contraseña, estados de envío y validación |
| `lib/screens/registro_exitoso_screen.dart` | ✅ | Cubre los dos desenlaces (sesión / confirmar correo) |
| `lib/screens/admin_dashboard.dart` | ✅ | Menú lateral adaptativo (cajón por debajo de 900 px) |
| `lib/screens/admin/cpanel_modulos_panel.dart` | ✅ | **Núcleo Fase 3** |
| `lib/screens/admin/cpanel_parametros_panel.dart` | ✅ | **Núcleo Fase 3** |
| `lib/screens/admin/cpanel_auditoria_panel.dart` | ✅ | **Núcleo Fase 3** |
| `lib/screens/docente_dashboard.dart` | ✅ | Marcador con cierre de sesión real |
| `lib/screens/aspirante_dashboard.dart` | ✅ | Usa el repositorio, con estado de error y reintento |

### Backend (Node 22 / TypeScript 5.7 / Fastify 5)

| Ruta | Responsabilidad |
| --- | --- |
| `src/dominio/` | Tipos, errores y **puertos** (interfaces) |
| `src/config/env.ts` | Configuración validada con Zod al arrancar |
| `src/infra/supabase.ts` | Clientes: usuario (RLS), admin (service_role), anónimo |
| `src/infra/repos-supabase.ts` | Implementación de los puertos + normalización de filas |
| `src/infra/traducir-error.ts` | Códigos PostgreSQL → `ErrorApi` |
| `src/infra/cache.ts` | Caché TTL con anti-estampida |
| `src/http/plugins/autenticacion.ts` | Resuelve identidad; guardias `exigirSesion` / `exigirAdmin` |
| `src/http/plugins/modulos.ts` | Guardias de módulo y mantenimiento (lógica pura) |
| `src/http/plugins/errores.ts` | Cuerpo de error uniforme |
| `src/http/esquemas.ts` | Validación de entrada + coherencia de tipos |
| `src/http/rutas/` | `salud`, `yo`, `admin` |
| `src/app.ts` | Construye la app con todo inyectado |
| `src/server.ts` | Único punto que lee `process.env` |

### Almacenamiento pesado — Cloudflare R2 (módulo M5)

Construido y probado, **sin credenciales todavía**. Se activa solo cuando las
cuatro variables de R2 estén puestas.

| Archivo | Responsabilidad |
| --- | --- |
| `src/dominio/almacenamiento.ts` | Reglas puras: claves, extensiones, tipos MIME, `Content-Disposition` |
| `src/dominio/puertos.ts` | `PuertaAlmacenamiento` — el puerto, fuera de `Repositorios` |
| `src/infra/r2_service.ts` | Implementación sobre el SDK de S3 + traducción de errores |
| `test/r2.test.ts` | 24 pruebas, sin red |

**Dos ajustes que hacen que R2 funcione**, y ninguno es opcional: `region: 'auto'`
(R2 no tiene regiones) y `forcePathStyle: true` (R2 no soporta direccionamiento
virtual-host; sin esto el cliente resolvería un subdominio que no existe).

**Caducidades:** subida 5 minutos, descarga 15 minutos. Configurables por entorno.

#### La decisión de seguridad del módulo

**La clave del objeto la construye el servidor, nunca el cliente.** Una URL
prefirmada de subida es una autorización de escritura: si el cliente pudiera
proponer la clave, esa autorización alcanzaría a *cualquier* objeto del bucket, y
bastaría pedir una URL para `../../recursos/logo.png` para sobrescribir un recurso
del sistema. Por eso `nombreOriginal` sólo aporta la **extensión**; el nombre base
es un UUID generado en el servidor. Hay una prueba que lo verifica con
`../../../../recursos/logo.png`.

El tipo MIME también se deriva de la extensión y **se firma** en la URL. Sin
firmarlo, el SDK sólo firma `host` y el `Content-Type` del comando se descarta:
el cliente podría declarar cualquier tipo. Lo detectó una prueba, no una lectura.

**Limitación conocida:** una URL prefirmada de `PUT` no puede imponer un tamaño
máximo. El límite de 25 MB vive en el código (`TAMANO_MAXIMO_BYTES`) y debe
aplicarse también en el cliente y con una regla de ciclo de vida en R2.

### Protección del último administrador (D8)

El sistema no puede quedarse sin ningún administrador activo: sería quedarse sin
nadie capaz de gestionarlo, y sin forma de revertirlo desde la aplicación.

La barrera es un **trigger** (`proteger_ultimo_admin`), no una comprobación en la
API. La razón es que la API sólo ve una parte del problema:

| Camino | ¿Lo cubre la API? | ¿Lo cubre el trigger? |
| --- | --- | --- |
| Un admin se degrada a sí mismo | ✅ `AUTO_DEGRADACION` | ✅ |
| Desactivar al último admin (`active = false`) | ❌ no lo miraba | ✅ |
| Borrar al último admin | ❌ | ✅ |
| Dos admins degradándose **a la vez** | ❌ carrera | ✅ |
| Cambios desde el editor SQL o una migración | ❌ | ✅ |

La carrera merece explicación porque es el caso que justifica el diseño: si A
degrada a B y B degrada a A en el mismo instante, cada transacción ve al otro
todavía como administrador, ambas pasan, y el resultado son **cero**. El trigger
lo cierra con un bloqueo de transacción (`pg_advisory_xact_lock`) que serializa
esa sección, y que se toma **sólo** en el camino peligroso: editar el nombre de un
estudiante no paga ese coste.

La API espeja la regla en una **función pura** (`dominio/reglas-admin.ts`) para
dar un mensaje útil en vez de un error de restricción genérico. Es honesto decir
que el caso `ULTIMO_ADMIN` es inalcanzable por la API en su funcionamiento normal
—quien actúa es a su vez un administrador activo, así que siempre queda al menos
uno—, pero la regla se mantiene porque deja la invariante escrita en un solo
sitio y porque una ruta futura de desactivación de usuarios sí podría alcanzarla.

### Decisiones de diseño que sostienen todo lo demás

1. **Inyección por puertos.** `Repositorios` es una interfaz. La API entera se
   monta en memoria en los tests: sin red, sin Supabase, sin credenciales.
   Es la misma decisión que resolvió la deuda **D1** en Flutter.
2. **Ningún fallo se convierte en valor vacío.** `Result` + `AppException` en
   Dart; `ErrorApi` con código estable en la API. Hay tests que verifican que un
   fallo **no** se confunda con una lista vacía.
3. **El cliente nunca decide el rol.** El trigger lo fija en `estudiante`. Hay un
   test que comprueba que la metadata no lleva `rol`.
4. **RLS no es decorativo.** Los repositorios de cada petición viajan con el
   token del llamante, así que Postgres vuelve a comprobar lo que la API ya
   comprobó. Dos barreras, no una repetida.
5. **La autorización no depende de la UI.** El menú oculta módulos apagados, pero
   quien decide es la API y, detrás, RLS.

---

## 6. Deuda técnica

| ID | Descripción | Estado |
| --- | --- | --- |
| **D1** | `SupabaseService` no era inyectable → camino de red sin tests | ✅ **Resuelta** |
| **D2** | Los dashboards hablaban con el singleton saltándose los repositorios | ✅ **Resuelta** |
| **D3** | No había validación de configuración al arrancar | ✅ **Resuelta** |
| **D4** | Los 5xx consumían la cuota de rate limit | ✅ **Resuelta** (`skipOnError`) |
| **D5** | El modo mantenimiento bloqueaba todo si fallaba la lectura del parámetro | ✅ **Resuelta** (falla abierto) |
| **D6** | Falta el contrato OpenAPI 3.1 | ✅ **Resuelta** (generado desde Zod + 9 pruebas de coherencia) |
| **D7** | No hay verificación de tokens en caché (una llamada a Auth por petición) | ⏳ Aceptada; medir antes de optimizar |
| **D8** | No se comprobaba que quedara **otro** administrador al degradar a uno | ✅ **Resuelta** (trigger + regla pura) |
| **D9** | Una URL prefirmada de `PUT` no puede imponer un tamaño máximo | ⏳ Pendiente (regla de ciclo de vida en R2) |
| **D10** | La conexión directa a la base es sólo IPv6 → `supabase db push` no funciona en redes IPv4 | 🟡 Mitigada con `supabase/apply-migrations.mjs` |

### Fallos reales corregidos en esta iteración

Los tres primeros se descubrieron **arrancando el binario compilado** contra una
URL de Supabase inexistente, no leyendo el código:

1. **Un fallo de red se reportaba como 500.** Supabase lo envuelve en
   `{ code: '', message: 'TypeError: fetch failed' }`; la comprobación de "¿es un
   error de Postgres?" aceptaba el código vacío. Ahora se comprueba primero el
   transporte → **503**.
2. **Una ruta inexistente devolvía 500 en vez de 404.** El guardián de
   mantenimiento corría en `onRequest` (antes del enrutado) y lanzaba.
3. **Una avería de la base de datos bloqueaba todo con un 503 que decía
   "mantenimiento".** El modo mantenimiento ahora **falla abierto**: no es un
   control de seguridad, y bloquear por no poder leer un parámetro oculta el
   problema real.
4. **`main.dart` no arrancaba en modo debug** (Fase 1): tenía `home:` y una ruta
   `'/'`, y Flutter lanza una aserción si coexisten.
5. **El tipo MIME de una subida no iba firmado.** El SDK de S3 firma sólo `host`
   por defecto, así que el `ContentType` del comando se descartaba y el cliente
   podía subir el objeto declarando cualquier tipo. Corregido firmando el
   encabezado con `signableHeaders`. Lo encontró una prueba: el comentario del
   código afirmaba justo lo contrario de lo que el SDK hacía.
6. **El `.env` no se cargaba nunca.** No había `dotenv` ni `--env-file`, así que
   el archivo se ignoraba por completo y el arranque fallaba diciendo «revisa el
   archivo .env» **con el `.env` correcto delante**. Corregido con el flag nativo
   de Node 22 `--env-file-if-exists`, que además tolera su ausencia dentro del
   contenedor, donde el entorno llega por `env_file` de Compose.
7. **Las variables opcionales vacías impedían arrancar.** `node --env-file`
   exporta `VACIA=` como **cadena vacía**, no como variable ausente, y `min(1)` la
   rechazaba: dejar el hueco de R2 sin rellenar —justo lo que indica la
   plantilla— tumbaba el backend. Corregido tratando la cadena vacía como
   ausente en las variables opcionales, manteniendo que una **obligatoria** vacía
   siga fallando y se nombre.

8. **Un identificador que no era UUID salía como 500 de base de datos.**
   Encontrado en la prueba de humo contra la nube. `PATCH
   /api/v1/admin/usuarios/me/rol` llegaba hasta Postgres, que respondía `22P02
   invalid input syntax for type uuid: "me"`, y la traducción de errores lo
   convertía en `500 ERROR_BASE_DE_DATOS`. Es decir: un error del cliente
   disfrazado de caída del servidor, con el administrador leyendo «ocurrió un
   error al acceder a los datos» cuando el problema era la URL. Ahora el `id` se
   valida como UUID **antes** de tocar la base → **400**, con dos pruebas de
   regresión. La prueba de humo se reforzó también: antes de este arreglo
   afirmaba «el estado no es 200», que pasaba con el 500 dentro.

9. **CORS sin el puerto del frontend.** `CORS_ORIGINS` listaba
   `localhost:3000` y `localhost:8080`, pero `flutter run` **sin `--web-port`**
   toma un puerto libre distinto en cada arranque (10443, 53211…). El frontend
   habla directo con Supabase —que tiene su propia CORS y sí lo aceptaba— así
   que la pantalla de login cargaba bien; el fallo aparecía después, en cada
   llamada a la API propia, con un error de CORS en la consola del navegador.
   Corregido por dos vías: el README fija `--web-port=8080` como obligatorio en
   desarrollo, y `CORS_ORIGINS` incluye también `127.0.0.1` (que para el
   navegador es un origen **distinto** de `localhost`).

> El fallo 8 es el motivo por el que existe la prueba de humo. Las 138 pruebas de
> `vitest` pasaban en verde con ese bug presente: corren contra dobles en memoria
> y nunca ven un id mal formado llegar a un motor real. Hay clases de fallo que
> sólo aparecen al hablar con la infraestructura de verdad.

---

## 7. Cómo se verifica todo

```bash
# --- Frontend ---
flutter analyze
flutter test

# --- Migraciones SQL (contra PostgreSQL real, sin Docker ni Supabase) ---
cd supabase/tests && npm install && npm test

# --- Backend ---
cd backend
npm run typecheck
npm run lint
npm test              # 138 pruebas, incluidas las del módulo R2 y las de OpenAPI
npm run build

# --- Contra la infraestructura REAL (lo que no ve ninguna prueba anterior) ---
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs   # 30 comprobaciones
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs    # aplicar migraciones
node supabase/crear-admin.mjs correo@dominio.com                    # primer admin
node backend/test-humo.mjs                                          # 24 comprobaciones
```

### Las tres redes de seguridad, y qué cubre cada una

| Red | Qué demuestra | Qué NO puede ver |
| --- | --- | --- |
| `flutter test` (88) | La lógica del cliente | El SQL, la API, la red |
| `supabase/tests` (49) | Las migraciones sobre PostgreSQL real: RLS y triggers | La API, el despliegue |
| `npm test` (138) | La API completa sobre dobles en memoria | La base real, las credenciales |
| `verificar-esquema.mjs` (30) | Que el esquema **desplegado** es el esperado | El comportamiento de la API |
| `test-humo.mjs` (24) | La cadena entera: API → GoTrue → Postgres, en la nube | Casos que no se le ocurran a nadie |

Las pruebas de R2 **no tocan la red**: firmar una URL es criptografía local. Por
eso se verifica el endpoint, la caducidad, los encabezados firmados y el rechazo
de claves manipuladas sin credenciales y sin conexión.

El frontend lee su configuración **en tiempo de compilación**, no de un `.env`:
`String.fromEnvironment()` se resuelve al compilar. El equivalente a `.env` es
`--dart-define-from-file=.env.json`:

```bash
flutter run --dart-define-from-file=.env.json
flutter build web --release --dart-define-from-file=.env.json
```

El validador de SQL merece una explicación: `flutter analyze` no ve el SQL, y un
error en una política RLS no rompe la compilación — rompe la seguridad, y se
descubre en producción. `supabase/tests/` levanta un PostgreSQL real (PGlite),
aplica el shim de Supabase y las cuatro migraciones, y ejecuta 49 aserciones sobre
el resultado: cortacircuitos, auditoría, idempotencia, RLS por rol e integridad.

### Lo que la prueba de humo comprueba

| Bloque | Qué verifica |
| --- | --- |
| Sondas | `/salud` responde y `/salud/profundo` **alcanza la base real** |
| Sin sesión | 401 sin token y con un token falsificado |
| Sesión real | Consigue un JWT de GoTrue y comprueba que su `iss` es el proyecto |
| Identidad | La API resuelve el correo y el rol desde `profiles` en la nube |
| Módulos | Los 9 llegan desde `system_modules`; el panel los ve todos |
| D8 | 404 con perfil inexistente, 400 con id no-UUID, 409 al auto-degradarse |
| CORS y Helmet | Preflight de Flutter Web permitido, origen ajeno rechazado |

Para conseguir la sesión sin depender de que alguien confirme un correo, usa la
Auth Admin API para generar un enlace de acceso y lo canjea en `/auth/v1/verify`.
El JWT resultante lo firma GoTrue con el secreto del proyecto, así que ejercita
**la misma verificación de firma** que usaría un alumno.

---

## 8. Siguiente paso

### Desbloqueado: la cadena completa funciona

| Elemento | Estado |
| --- | --- |
| Base de datos en la nube | ✅ Migrada y verificada (30/30) |
| Primer administrador | ✅ `lorenzo-roca11@hotmail.com` con rol `admin` |
| API contra la base real | ✅ 24/24 comprobaciones |
| Contrato OpenAPI 3.1 | ✅ Generado desde Zod, con 9 pruebas de coherencia |
| Repositorio en GitHub | ✅ `Burmistrov4/INCES---LMS` — `main` = `428b837`, verificado con `git ls-remote` |

**Lo que queda en su tejado, en orden:**

1. **Mandar las credenciales de Cloudflare R2** cuando quiera encender M5. El
   módulo está construido y probado; sólo está apagado.
2. **Arrancar el frontend con puerto fijo** contra la nube:

   ```bash
   flutter run -d chrome --web-port=8080 --dart-define-from-file=.env.json
   ```

   El `--web-port=8080` no es opcional: sin él Flutter toma un puerto libre
   distinto en cada arranque y `CORS_ORIGINS` lo rechaza. Ver «CORS» más abajo.

### Luego: Fase 4 — M2 Currículo y M3 Cuadrante

1. **Encender `m2_curriculo` desde el cPanel** cuando su API exista. El
   interruptor ya funciona; lo que falta es lo que hay detrás.
2. **Exponer las rutas de M5** recibiendo `PuertaAlmacenamiento` inyectado, y
   cerrar D9 con una regla de ciclo de vida en R2.
3. **Diseñar M6 (asistencia por QR)** según lo definido: el backend emite un JWT
   temporal de 5 minutos atado al `schedule_slot` de la sección; el docente
   muestra el QR; el alumno lo escanea y envía el token; el backend valida
   caducidad, cruza con `enrollments` y registra la asistencia. Tres faltas
   consecutivas disparan el motor de bids de M4. **No se implementa todavía**:
   depende de M3 (cuadrante) y M4 (bids), que aún no existen.

