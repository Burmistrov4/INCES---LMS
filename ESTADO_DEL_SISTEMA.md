# ESTADO DEL SISTEMA — INCES LMS

> **Documento puente vivo.** Describe el estado **real** del proyecto: lo que está
> construido, lo que está verificado y lo que falta. Se actualiza al cerrar cada
> fase. Si algo aquí contradice a otro archivo, manda este.
>
> **Última actualización:** 2026-09-15 · **Módulo 3 con esquema Y backend
> completos** (cuadrante, aulas, guardias docentes, triggers anti-colisión y las
> **14 rutas** de `docs/CONTRATO_API_MODULO3.md`). Módulo 1 cerrado y Módulo 2
> completo. **D10 resuelta** (libro mayor de migraciones con checksums). Puertos y
> CORS alineados. Repositorio publicado en GitHub.
>
> **Del Módulo 3 sólo falta el frontend.** Las 14 rutas ya existen, están
> registradas en Fastify y documentadas en `openapi.json` (el recuento pasó de
> **22** a **29 rutas** y de **40** a **62 esquemas**). `test/openapi.test.ts`
> compara ahora el documento contra las rutas **reales** en las dos direcciones,
> así que una ruta nueva sin documentar ya no puede pasar.
>
> ⚠️ **Nota sobre este documento.** Hasta 2026-09-14 arrastraba cifras viejas
> (138 tests backend, 88 Flutter, 11 rutas OpenAPI, 4 migraciones) mientras el
> código iba por 171 / 110 / 15 / 5. Se corrigió todo contra el código y contra la
> base real, y **volvió a corregirse el 2026-09-15** (341 backend / 197 Flutter /
> 164 SQL / 10 migraciones / 17 tablas). **Si vuelve a haber discrepancia, gana el
> código**: verifica antes de citar una cifra de aquí.

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
| **Módulo 1** | Invitación de docentes por token + auditoría de accesos (`auth_logs`) | ✅ Completa |
| **D10** | Conexión directa sólo IPv6 | ✅ Resuelta (libro mayor de migraciones) |
| **Módulo 2 (backend)** | Currículo y Pensum: repositorio, 7 rutas y traducción de errores | ✅ Completo |
| **Módulo 2 (frontend)** | Asistente de 3 pasos en Flutter | ✅ Completo |
| **Módulo 3 (esquema)** | Cuadrante, aulas, guardias: 4 tablas, 2 triggers anti-colisión, 3 vistas | ✅ **Aplicado y verificado** |
| **Módulo 3 (backend)** | Las 14 rutas de `CONTRATO_API_MODULO3.md` | ✅ **Completo** (PASO 4) |
| **Módulo 3 (frontend)** | Pantallas de aulas, lapsos, guardias y cuadrante | ⏳ Pendiente |
| **Fase 4+** | M4 Inscripciones … M8 Pasantías | ⏳ Pendiente |

**Verificación al cierre de esta iteración** — suites del **2026-09-15**;
migraciones de M3 aplicadas y verificadas el **2026-09-15**

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | Sin problemas |
| `flutter test` | **197 / 197** en verde |
| `npm test` (backend) | **341 / 341** en verde (16 archivos) |
| `npm run typecheck` (backend) | Sin errores |
| `npm run lint` (backend) | Sin errores |
| `npm run build` (backend) | Compila sin errores |
| Validador SQL contra PostgreSQL real (pglite) | **164 / 164** aserciones en verde (49 de M1 + 17 del diseño de M2 + 30 de D12/D13 + 14 de las funciones del asistente + 46 de M3 + 8 del camino real de M3) |
| **Migraciones en la nube** | **10 / 10** registradas en `schema_migrations` |
| **Verificación independiente del esquema en la nube** | **81 / 81** comprobaciones (`supabase/verificar-esquema.mjs`) |
| **Libro mayor de migraciones (D10)** | 10 versiones aplicadas con checksum SHA-256 válido |
| **Migraciones de M3 en la nube** | ✅ **Aplicadas** el 2026-09-15 — 17 tablas + 4 vistas, con RLS activo en las 17 (ver §3) |
| **Humo de integración del canal de invitación** | **17 / 17** (`supabase/humo-invitaciones.mjs`) |
| **Humo de integración del asistente de currículo** | **14 / 14** (`supabase/humo-curriculo.mjs`), incluida la atomicidad |
| **Humo de integración del cuadrante (M3)** | **53 / 53** (`supabase/humo-cuadrante.mjs`), sin residuo — incluidos el mensaje real del trigger, la colisión cruzada y la RLS por rol |
| **Sonda del camino real de M3 contra la nube** | ✅ Alta de guardia como `authenticated` real **OK**; colisión → `23514`; mismo bloque otro día → permitido |
| Humo anterior contra la nube (superficie previa a M1) | 24 / 24 comprobaciones |
| Documento OpenAPI | OpenAPI 3.1.0 · **29 rutas · 62 esquemas** (las 14 de M3 incluidas) |
| Proyecto Supabase en la nube | `ACTIVE_HEALTHY` (región sa-east-1, PostgreSQL 17.6) |
| Repositorio GitHub | `Burmistrov4/INCES---LMS` (rama `main`) |

> **Qué cubre el humo de invitación (17/17)** y qué no: verifica RLS con JWT
> reales (admin ve, `anon` no ve, un docente no ve, nadie inserta trazas a mano),
> el camino HTTP `invitar → activar → rol docente`, el token de un solo uso y que
> el token en claro no queda en la base. **No** cubre la pantalla de activación en
> un navegador real: eso sigue pendiente.

---

## 2. Estado de despliegue

### Lo que está desplegado

**La base de datos ya está aplicada y verificada.** Las diez migraciones se
aplicaron contra el proyecto real `twdppwnxlnmxkiejbrei` y el resultado se
comprobó después, consultando el catálogo de PostgreSQL por separado:
**17 tablas** con RLS activo **en las 17**, **4 vistas** (`cursos` de D12 más las
tres del Módulo 3), **20 funciones**, **22 triggers** y **38 políticas RLS**, más
9 módulos sembrados, 8 parámetros, 1 lapso (`2026-1`) y los 5 cursos — que desde
la migración de D12 viven dentro de `programs` como `CURSO_LIBRE`.

> **Estas cifras están medidas, no estimadas.** Salen de
> `supabase/verificar-esquema.mjs` (81/81) y de consultas directas al catálogo,
> hechas **después** de aplicar. Es la lección de D11: cuando una migración se
> aplica, se vuelve a contar en vez de confiar en lo que decía el documento.

**`classrooms`, `teacher_duties` y `schedule_slots` están vacías, y es lo
correcto.** No se sembró ni un aula ni una guardia: el inventario de espacios del
CFS es un dato institucional que **no se inventa** (R-18). Las tres tablas
existirán con 0 filas hasta que el administrador cargue el registro real, y
mientras tanto el cuadrante no se puede usar —una clase sin aula no existe—, cosa
que la UI tendrá que decir en vez de mostrar un desplegable vacío sin
explicación.

**El libro mayor de migraciones (D10) ya está en uso.** `schema_migrations`
guarda una fila por migración aplicada con su checksum SHA-256. Eso convierte
una operación ciega en una operación verificable: `apply-migrations.mjs` sabe
qué falta, y se niega a tocar la base si detecta que un archivo ya aplicado
cambió. **Corolario que hay que respetar: una migración ya corrida no se edita
nunca.** Se añade otra que la corrija.

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
| Migraciones aplicadas y verificadas | ✅ **Las 5** (registradas en `schema_migrations`) |
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
# Ver el estado del libro mayor sin tocar la base: qué está aplicado, qué falta
# y si algún archivo ya aplicado cambió (deriva).
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --check

# Aplicar SÓLO lo pendiente. Cada migración se registra en el libro mayor dentro
# de la misma transacción, así que no puede quedar aplicada sin registrar.
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs

# Registrar TODAS las pendientes como aplicadas SIN ejecutarlas. Es para una base
# que ya tiene el esquema pero nació antes de que existiera el libro mayor.
# Confírmalo antes con verificar-esquema.mjs.
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --adoptar

# Comprobar el esquema resultante contra el catálogo de PostgreSQL
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs
```

**Qué hace exactamente `apply-migrations.mjs`.** Ya no reaplica todo a ciegas:
lee `public.schema_migrations`, calcula el SHA-256 de cada archivo de
`supabase/migrations/` y decide archivo por archivo. Cuatro estados posibles:

| Estado | Significado | Qué hace |
| --- | --- | --- |
| `aplicada` | La versión está en el libro y el checksum coincide | No la toca |
| `pendiente` | La versión no está en el libro | La ejecuta y la registra |
| `deriva` | Está en el libro pero el archivo cambió | **Se niega a continuar** (`exit 1`) |
| `sin-libro` | No existe `public.schema_migrations` | La crea y trata todo como pendiente |

La deriva es la que justifica el diseño: editar una migración ya corrida
significa que la base real y el repositorio dejaron de coincidir, y el script
prefiere detenerse a adivinar. **Nunca editar una migración ya aplicada**: se
añade otra que la corrija.

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
| Base de datos | 5 migraciones SQL | ✅ Ya aplicadas a la nube |
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
| `programs` | **M2** | Oferta formativa: carreras (`CARRERA`) y cursos libres (`CURSO_LIBRE`). Absorbió a `cursos` (D12) |
| `subjects` | **M2** | Banco global de materias, compartido entre programas |
| `program_subjects` | **M2** | El pensum: qué materia va en qué programa y en qué período |
| `profiles` | Fase 0 | Identidad y rol. Espejo de `auth.users` |
| `aspirantes` | Fase 0 | Ficha de inscripción del aspirante |
| `sections` | Fase 0 → **M2** | Secciones abiertas. **Rediseñada en D13**: `program_id`, `subject_id`, `period_code`, `name`, `max_capacity` |
| `enrollments` | Fase 0 | Matrículas y estados de cupo (M4) |
| `system_modules` | **Fase 3** | Interruptores de módulos del cPanel |
| `system_settings` | **Fase 3** | Parámetros operativos editables |
| `config_audit_log` | **Fase 3** | Auditoría append-only de la configuración |
| `teacher_invitations` | **Módulo 1** | Invitaciones de docentes por token (se guarda el hash) |
| `auth_logs` | **Módulo 1** | Traza de acceso: IP, instante, `SUCCESS`/`FAILED` |
| `academic_periods` | **M3** | Catálogo de lapsos. `sections.period_code` apunta aquí (R-12), así que `periodo_activo` ya no puede divergir en silencio |
| `classrooms` | **M3** | Espacios del CFS: aulas, talleres **y zonas**. Una zona es una fila con `capacity = 0` (R-18). **Sin semilla a propósito** |
| `teacher_duties` | **M3** | Guardias de custodia: docente + espacio + día/bloque, con o sin clase. `turno` es derivado |
| `schedule_slots` | **M3** | El cuadrante: sección + docente + aula + día/bloque. El lapso se deriva de la sección |
| `schema_migrations` | **D10** | Libro mayor: versión, checksum SHA-256, `applied_at` |

### Vistas

| Vista | Origen | Propósito |
| --- | --- | --- |
| `cursos` | **D12** | **Vista de compatibilidad** sobre `programs` (`type = 'CURSO_LIBRE'`) con `security_invoker`. Existía como tabla desde Fase 0; se conservó para no romper el desplegable del formulario público de inscripción mientras Flutter siga leyendo `cursos`. Se retira con `drop view public.cursos;` cuando el cliente lea `programs` directamente |
| `v_cuadrante_clases` | **M3** | El cuadrante enriquecido: materia, sección, aula, día legible y nombre del docente. `security_invoker` |
| `v_cuadrante_guardias` | **M3** | Las guardias con su aula y su día legible. `security_invoker` |
| `v_periodo_vigente` | **M3** | El lapso cuyo `code` coincide con `system_settings.periodo_activo`. `security_invoker` |

> **Las tres vistas de M3 llevan `security_invoker`, y no es un detalle.** Sin
> él corren con los privilegios de su dueño y **se saltan la RLS de las tablas
> base**: un estudiante vería el cuadrante de todo el centro, que es justo el
> dato que las políticas existen para acotar. `verificar-esquema.mjs` comprueba
> las cuatro.

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
| `exigir_pensum_de_programa()` | **Constraint trigger diferido**, en `programs` **y** en `program_subjects` | **Regla 1 de M2:** una carrera `CARRERA` activa no puede quedarse sin materias. Es diferido a propósito: la comprobación corre al **confirmar la transacción**, y eso es lo que permite que el asistente cree el programa y su pensum de una vez. Los dos triggers cubren los dos caminos al mismo estado inválido: publicar un programa vacío, y vaciarle el pensum a uno ya publicado |
| `proteger_pensum_en_uso()` | Trigger en `program_subjects` | **Regla 2 de M2:** bloquea cambiar el `period_order` o quitar materias cuando hay secciones activas del período vigente usando ese programa. Falla abierto si no hay período declarado (guarda de integridad, no barrera) |
| `crear_programa_con_pensum(...)` | **RPC** (`security invoker`) | El asistente de M2: crea el programa y su pensum en **una sola transacción**. Existe porque PostgREST no admite insertar un padre con sus hijos en la misma petición (comprobado: `PGRST204`). Ver §11 |
| `reemplazar_pensum(...)` | **RPC** (`security invoker`) | Reemplazo transaccional del pensum: borra lo que sobra, reordena lo que cambia e inserta lo nuevo. La Regla 2 la aplican los triggers, no esta función |
| `turno_de_bloque(bloque)` | Función (`immutable`) | Bloque 1–6 → `MAÑANA`, 7–12 → `TARDE`. Existe para que `turno` sea una **columna generada** y no pueda contradecir al bloque (R-16). La frontera es provisional y vive en **un solo sitio** |
| `dia_legible(dia)` | Función (`immutable`) | 1 → `lunes` … 6 → `sábado`, para los mensajes de error y la vista del cuadrante |
| `exigir_agenda_libre(periodo, dia, bloque, docente, aula, origen, id)` | Función (`security definer`) | **El corazón de M3.** Comprueba que el docente **y** el espacio estén libres, mirando **las dos tablas** (`teacher_duties` y `schedule_slots`) con un `union all`. `definer` a propósito: con la RLS del llamante el chequeo sería ciego. Se serializa con `pg_advisory_xact_lock`. **Revocada a todos**: la única puerta son los triggers |
| `teacher_duties_exigir_agenda()` | Trigger en `teacher_duties` | Envoltorio fino: sale si la guardia está archivada y delega en `exigir_agenda_libre`. **`security definer`** — ver R-20 |
| `schedule_slots_exigir_agenda()` | Trigger en `schedule_slots` | Igual, resolviendo antes el lapso por la sección. **`security definer`** — ver R-20 |
| `exigir_periodo_registrado()` | Trigger en `system_settings` | Rechaza un `periodo_activo` que no exista en `academic_periods`. Es lo que convierte la divergencia silenciosa de R-06/R-12 en una violación ruidosa |
| `nombre_para_mostrar(uuid)` | Función (`security definer`, `stable`) | Devuelve el nombre de un docente/admin activo, y `NULL` para todo lo demás. Existe porque `profiles_read_own` impide al estudiante leer la fila del docente, y **relajar esa política expondría `cedula` y `email` de todo el centro** (RLS no es por columna). Ver R-14 |

### Políticas RLS

| Tabla | Lectura | Escritura |
| --- | --- | --- |
| `profiles` | El propio perfil; admin ve todo | El propio (sin cambiar rol); admin todo |
| `aspirantes` | El propio; admin todo | El propio; admin todo. **Sin inserción anónima** |
| `system_modules` | Cualquier autenticado | **Solo admin** |
| `system_settings` | Públicos: `anon` + autenticados. Privados: solo admin | **Solo admin** |
| `config_audit_log` | **Solo admin** | **Nadie.** Único camino: el trigger |
| `programs` | **Público**: `anon` ve las activas; los autenticados ven todo, incluidos los borradores | **Solo admin** |
| `subjects` | **Solo autenticados.** El banco de materias no es público | **Solo admin** |
| `program_subjects` | **Solo autenticados** | **Solo admin** |
| `sections` | Activas (`is_active`) para `anon` y autenticados | **Solo admin.** Sin `DELETE` para nadie: archivar es `is_active = false` |
| `enrollments` | El propio; admin todo | El propio; admin todo |
| `cursos` *(vista, no tabla)* | Hereda la RLS de `programs` gracias a `security_invoker`: `anon` sólo ve los cursos activos | — es una proyección; se escribe en `programs` |
| `teacher_invitations` | **Solo admin** | **Solo admin.** El servicio de activación usa `service_role` y no pasa por aquí |
| `auth_logs` | **Solo admin** | **Nadie.** Único camino: el backend con `service_role` |
| `schema_migrations` | **Nadie** (revocado a `anon` y `authenticated`) | **Nadie.** Sólo el script con token de administración |
| `academic_periods` | **Público**: `anon` + autenticados (el formulario de inscripción necesita saber el lapso) | **Solo admin** |
| `classrooms` | Autenticados. **`anon` no tiene ni el `GRANT`** | **Solo admin.** Sin `DELETE`: archivar es `is_active = false` |
| `teacher_duties` | El docente ve **solo las suyas**; `anon` no tiene `GRANT`; **el estudiante no tiene política ninguna** | **Solo admin** |
| `schedule_slots` | El docente ve las suyas; el estudiante ve **las de su sección** (vía `enrollments`); `anon` no tiene `GRANT` | **Solo admin** |
| `v_cuadrante_clases`, `v_cuadrante_guardias`, `v_periodo_vigente` *(vistas)* | Heredan la RLS de las tablas base gracias a `security_invoker` | — es una proyección |

> **«Sin política» no es lo mismo que «política que devuelve vacío».** Para un
> estudiante, `teacher_duties` no tiene ninguna política: es la diferencia entre
> una puerta cerrada con llave y una puerta pintada en la pared.
>
> Y `anon` recibe `42501 permission denied`, **no una lista vacía**. Es
> deliberado: una lista vacía sería indistinguible de «la política está mal
> escrita», y el formulario de inscripción no necesita la agenda. El rechazo
> explícito se distingue; el silencio no.

### El fallo de M3 que hay que conocer antes de tocar los triggers (R-20)

Los dos envoltorios de trigger del cuadrante (`teacher_duties_exigir_agenda` y
`schedule_slots_exigir_agenda`) son **`security definer`**, y **cambiarlos a
`invoker` deja el módulo entero inoperable**:

```
ERROR: 42501: permission denied for function exigir_agenda_libre
CONTEXT: PL/pgSQL function teacher_duties_exigir_agenda() line 9 at PERFORM
```

Estuvieron así en la migración `202609180001` y se corrigieron en
`202609180002`. El motivo es que `exigir_agenda_libre()` está **revocada a
propósito** para todos (la única puerta es el trigger), así que con `invoker` el
llamante no tiene `EXECUTE` y **toda alta de guardia o de clase falla**.

**Y no se detectó con 156 aserciones en verde**, porque las pruebas del trigger
escribían como el **dueño** de las tablas, que se salta la comprobación de
privilegios de función. Ver `REPORTE_ARIA.md` R-20 y
`docs/CONTRATO_API_MODULO3.md` §10.

Hay **tres** redes para que no vuelva: la sección 14.8 de `supabase/tests`
escribe como `authenticated` con claims de admin, `verificar-esquema.mjs`
comprueba `prosecdef` contra la nube, y se demostró el fail-first.

**Nota sobre `config_audit_log` y `auth_logs`:** las dos auditorías tienen dos
barreras independientes. RLS no tiene política de escritura **y** no hay `GRANT`
de escritura. Aunque alguien añadiera una política por error, seguiría sin poder
escribir. Hay una prueba en el humo de invitación que lo comprueba con un JWT de
administrador real: ni el admin puede insertar una traza a mano.

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
| `GET` | `/api/v1/admin/auditoria` | admin | Historial de configuración (`?limite=`, 1–200) |
| `GET` | `/api/v1/admin/acceso` | admin | Trazas de acceso (`?estado=`, `?email=`, `?userId=`, paginado) |
| `GET` | `/api/v1/admin/usuarios` | admin | Padrón de usuarios (`?rol=`, `?activo=`, `?busqueda=`, paginado) |
| `PATCH` | `/api/v1/admin/usuarios/:id/rol` | admin | Cambia el rol de un usuario |
| `POST` | `/api/v1/admin/usuarios/invitaciones` | admin | Invita a un docente: crea el token y devuelve el enlace |
| `POST` | `/api/v1/auth/activar` | **token de invitación** | El docente fija su contraseña y queda promovido a `docente` |

**Rutas de M2** (módulo 2, currículo y pensum — todas `admin`):

| Método | Ruta | Qué hace |
| --- | --- | --- |
| `GET` | `/api/v1/admin/programas` | Listado paginado, con `totalMaterias` y `totalPeriodos` en la misma consulta |
| `GET` | `/api/v1/admin/programas/:id` | Detalle con el pensum agrupado, `seccionesActivas` y `editable` |
| `POST` | `/api/v1/admin/programas` | **El asistente**: programa + pensum, atómico (201) |
| `PATCH` | `/api/v1/admin/programas/:id` | Metadatos: `nombre`, `requierePasantia`, `activo` |
| `PATCH` | `/api/v1/admin/programas/:id/pensum` | Reemplaza el pensum completo; la Regla 2 puede dar 409 |
| `GET` | `/api/v1/admin/materias` | Banco global de materias, paginado y con búsqueda |
| `POST` | `/api/v1/admin/materias` | Registra una materia en caliente (201) |

**Rutas de M3** (módulo 3, cuadrante, aulas y guardias — las trece primeras
`admin`, la última por rol):

| Método | Ruta | Qué hace |
| --- | --- | --- |
| `GET` | `/api/v1/admin/aulas` | Espacios del centro, paginados (`?tipo=`, `?activa=`, `?busqueda=`) |
| `POST` | `/api/v1/admin/aulas` | Registra un espacio (201) |
| `PATCH` | `/api/v1/admin/aulas/:id` | `nombre`, `capacidad`, `esTaller`, `activa`. **Archivar, no borrar** |
| `GET` | `/api/v1/admin/periodos` | Catálogo de lapsos, con cuál es el vigente |
| `POST` | `/api/v1/admin/periodos` | Registra un lapso, nace cerrado y no vigente (201) |
| `PATCH` | `/api/v1/admin/periodos/:id` | `nombre`, fechas, `activo`. El código no se toca |
| `PUT` | `/api/v1/admin/periodos/:id/vigente` | Declara ese lapso como el vigente |
| `GET` | `/api/v1/admin/guardias` | Guardias de custodia, paginadas (`?docenteId=`, `?dia=`, `?bloque=`…) |
| `POST` | `/api/v1/admin/guardias` | Asigna una guardia (201). Choque → **409 `CHOQUE_DE_AGENDA`** |
| `PATCH` | `/api/v1/admin/guardias/:id` | Mueve o edita una guardia. `activa: false` libera el hueco |
| `GET` | `/api/v1/admin/cuadrante` | **La rejilla maestra**: clases, guardias, aulas y docentes en una llamada |
| `POST` | `/api/v1/admin/cuadrante` | Coloca una clase (201). Choque → **409 `CHOQUE_DE_AGENDA`** |
| `PATCH` | `/api/v1/admin/cuadrante/:id` | Mueve o edita una clase |
| `GET` | `/api/v1/mi-horario` | **sesión** — Docente: sus clases **y** sus guardias. Estudiante: las de su sección. Un `admin` recibe 403 `PERFIL_SIN_ROL` |

**29 rutas en total**, contadas en el documento OpenAPI. Sólo las sondas de salud
y `/auth/activar` no exigen un JWT de sesión: `/auth/activar` va protegida por el
token de un solo uso, porque el docente todavía no tiene sesión cuando abre el
enlace. Por eso esa ruta consulta la base con `service_role`.

> **El choque de agenda no se comprueba en la API, se traduce.** Ninguna ruta
> pregunta «¿está libre?» antes de escribir: sería una carrera y, peor, una
> segunda copia de la regla que se desviaría de la del trigger. La API escribe,
> el trigger `exigir_agenda_libre()` decide y el repositorio convierte el `23514`
> en un 409 reutilizando **el mensaje del propio trigger** —que ya nombra el día
> y el bloque—. Ver `docs/CONTRATO_API_MODULO3.md` §8 y §9.

**Las dos escrituras de M2 no usan `insert`.** `POST /programas` y
`PATCH /programas/:id/pensum` van por las funciones `crear_programa_con_pensum` y
`reemplazar_pensum`, porque PostgREST no admite insertar un padre con sus hijos en
la misma petición ni expone transacciones entre peticiones. El repositorio nunca
escribe esas tablas directamente, y hay una prueba que lo comprueba contra un
cliente de Supabase falso: sin ella, cambiar la RPC por un `insert` habría dejado
la suite en verde y la atomicidad destruida. Ver §11 y `REPORTE_ARIA.md` R-10.

**Paginación: el patrón es contar primero.** Toda ruta de listado hace
`select count(*)` con `head: true` **antes** de pedir la página, y devuelve
`{ filas, total, limite, desplazamiento }`. Dos razones: el cliente pinta «1 a 25
de 340» sin una segunda consulta, y si el desplazamiento ya superó el total se
devuelve una página vacía sin pedirla. La red contra el `416` de PostgREST
(`esRangoNoSatisfacible()`) sigue en su sitio, pero conviene saber que **el 416
no se ha reproducido**: cinco sondeos con rangos fuera de límite devolvieron
siempre `200` con cero filas. La guarda de contar primero es correcta por sí
misma; su justificación escrita —«evita el 416»— está sin verificar.

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
| **El documento y la aplicación registran exactamente las mismas rutas, en las dos direcciones** | Una ruta documentada que no existe **y** una ruta registrada que nadie documentó. La versión anterior cotejaba contra una lista escrita a mano y sólo detectaba la primera: añadir una ruta y olvidar documentarla pasaba inadvertido. Se comparan contra el árbol real de Fastify, leído con `printRoutes()` **después de `await app.ready()`** — antes de eso, las rutas montadas dentro de un `app.register(...)` no aparecen y la comparación daría un verde hueco |
| Ninguna operación carece de 200 o de 401 cuando exige sesión | Un contrato sin respuesta de éxito no sirve para generar clientes |
| Las sondas de salud y `/openapi.json` son las únicas públicas | Una ruta que quedara pública por descuido no pasaría |
| Lo que sirve `/openapi.json` es idéntico a lo que genera el script | El archivo del repo no puede divergir de lo servido |
| `openapi.json` en disco está al día | Obliga a que el `diff` muestre el cambio de contrato |

```bash
npm run openapi                                   # regenerar el artefacto
curl -s http://localhost:3000/openapi.json | head # el mismo documento, en vivo
```

### Códigos de error

Todo error sale con la misma forma: `{ "error": { "codigo", "mensaje", "detalles"? } }`.
El cliente sólo necesita leer `error.codigo`; el `mensaje` es para el usuario y
`detalles` (con `contexto` y el mensaje técnico de Postgres) para el log.

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `NO_AUTENTICADO` | 401 | Sin token, token inválido o sesión vencida (`PGRST301`/`PGRST302`) |
| `CUENTA_INACTIVA` | 403 | Perfil con `active = false` |
| `SOLO_ADMIN` | 403 | Ruta de administración sin rol admin |
| `MODULO_DESHABILITADO` | 403 | El módulo está apagado en el cPanel |
| `MODULO_NO_AUTORIZADO` | 403 | El rol no está en la lista blanca del módulo |
| `PERMISO_DENEGADO` | 403 | RLS de PostgreSQL rechazó la operación (`42501`) |
| `MODULO_DESCONOCIDO` | 404 | La clave de módulo no existe |
| `PARAMETRO_DESCONOCIDO` | 404 | La clave de parámetro no existe |
| `PERFIL_INEXISTENTE` | 404 | El usuario cuyo rol se quiere cambiar no existe |
| `NO_ENCONTRADO` | 404 | PostgREST no encontró la fila (`PGRST116`) |
| `RUTA_NO_ENCONTRADA` | 404 | Ruta inexistente |
| `INVITACION_INVALIDA` | 404 | El token de invitación no corresponde a ninguna invitación. **Mensaje deliberadamente genérico** |
| `MODULO_CRITICO` | 409 | Intento de apagar `m0_cpanel` |
| `AUTO_DEGRADACION` | 409 | Un admin intenta quitarse su propio rol |
| `ULTIMO_ADMIN` | 409 | El cambio dejaría el sistema sin administradores activos |
| `INVITACION_YA_USADA` | 409 | El token de invitación ya se consumió |
| `REGISTRO_DUPLICADO` | 409 | Violación de unicidad (`23505`): correo ya registrado, código repetido, dos aulas con el mismo nombre |
| `PENSUM_EN_USO` | 409 | Regla 2 de M2: el programa ya tiene secciones activas del lapso vigente. **Se separa de `RESTRICCION_VIOLADA` por el texto del mensaje**, porque los dos triggers lanzan `23514` |
| `CHOQUE_DE_AGENDA` | 409 | **M3**: el docente o el espacio ya están ocupados en ese día y bloque. El mensaje se reutiliza **verbatim** del trigger, que ya nombra el día y el bloque |
| `PERFIL_SIN_ROL` | 403 | **M3**: `/api/v1/mi-horario` para un `admin`. No es un fallo —su rol no tiene horario— y por eso no es un 404 ni una lista vacía |
| `AULA_INEXISTENTE` | 404 | **M3**: el espacio que se quiere editar no existe |
| `PERIODO_INEXISTENTE` | 404 | **M3**: el lapso que se quiere editar o declarar vigente no existe |
| `GUARDIA_INEXISTENTE` | 404 | **M3**: la guardia que se quiere mover no existe |
| `CLASE_INEXISTENTE` | 404 | **M3**: la clase del cuadrante que se quiere mover no existe |
| `RECURSO_CADUCADO` | 410 | La invitación pasó sus 48 horas |
| `PETICION_INVALIDA` | 400 | Fallo de validación (Zod, UUID de ruta o tipo de parámetro) |
| `RESTRICCION_VIOLADA` | 400 | Un `check` de la base rechazó el dato (`23514`) |
| `REFERENCIA_INVALIDA` | 400 | La fila apunta a un registro que no existe (`23503`) |
| `ERROR_INTERNO` | 500 | Fallo no clasificado |
| `ERROR_BASE_DE_DATOS` | 500 | Error de Postgres sin traducción específica |
| `ESQUEMA_DESACTUALIZADO` | 500 | Falta aplicar una migración (`42P01`, tabla ausente) |
| `SUPABASE_INALCANZABLE` | 503 | No se pudo contactar con la base de datos |
| `SERVICIO_NO_DISPONIBLE` | 503 | `modo_mantenimiento` activo |
| `ARCHIVO_NO_ENCONTRADO` | 404 | El objeto no existe en R2 |
| `ALMACENAMIENTO_DENEGADO` | 403 | R2 rechazó las credenciales o el permiso |
| `ERROR_ALMACENAMIENTO` | 500 | Fallo de R2 no clasificado |

> **Por qué `INVITACION_INVALIDA` es un 404 y no un 400.** El token de una
> invitación inexistente y el de una invitación real no se distinguen desde
> fuera: el mismo código y el mismo mensaje para los dos. Un atacante no puede
> usar la API como oráculo para averiguar qué tokens existen. La distinción
> entre «no existe» (404) y «ya usada» (409) sí se hace, porque en ese punto el
> dueño legítimo del enlace necesita saber qué pasó.

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
| `lib/screens/admin/cpanel_auditoria_panel.dart` | ✅ | **Núcleo Fase 3**: auditoría de configuración |
| `lib/screens/admin/cpanel_auditoria_accesos_panel.dart` | ✅ | **Módulo 1**: trazas de acceso (`auth_logs`), con filtros y auto-refresco |
| `lib/screens/admin/cpanel_invitaciones_panel.dart` | ✅ | **Módulo 1**: invita docentes y muestra el enlace de activación |
| `lib/screens/activar_cuenta_screen.dart` | ✅ | **Módulo 1**: lee el token de `Uri.base.fragment` y fija la contraseña |
| `lib/screens/docente_dashboard.dart` | ✅ | Marcador con cierre de sesión real |
| `lib/screens/aspirante_dashboard.dart` | ✅ | Usa el repositorio, con estado de error y reintento |

> **Pendiente de la mitad de interfaz de M1:** que un navegador real abra
> `http://localhost:8080/#/auth/activate?token=…` y confirme que el token llega
> por el fragmento. El humo cubre la API; la pantalla no se ha abierto todavía.

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
| `src/http/rutas/` | `salud`, `yo`, `admin`, `auth`, `curriculo` |
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
| **D9** | Una URL prefirmada de `PUT` no puede imponer un tamaño máximo | ⏳ Pendiente (regla de ciclo de vida en R2). **Latente**: M5 está apagado sin credenciales. Resolver antes de M7 |
| **D10** | La conexión directa a la base es sólo IPv6 → `supabase db push` no funciona en redes IPv4 | ✅ **Resuelta** — `supabase/apply-migrations.mjs` con libro mayor (`public.schema_migrations`: version, checksum, applied_at). Sólo aplica lo ausente y detecta deriva por SHA-256 |
| **D11** | `ESTADO_DEL_SISTEMA.md` (este documento) arrastraba cifras viejas: 138 tests / 88 Flutter / 11 rutas / 4 migraciones frente a 171 / 110 / 15 / 5 reales | ✅ **Resuelta** — actualizado contra el código el 2026-09-14. *Y vuelto a actualizar el 2026-09-15: 341 / 197 / 29 / 10 reales (ver §7). La lección se cumplió dos veces: el documento se desincroniza solo.* |
| **D12** | `cursos` (Fase 0) y `programs` (M2) eran el mismo concepto: el catálogo de oferta formativa. Los 5 cursos sembrados son justo los `CURSO_LIBRE` que M2 modela | ✅ **Resuelta** — los 5 cursos se migraron a `programs` conservando id, nombre y estado; `cursos` pasó a ser una **vista de compatibilidad** (`security_invoker`) sobre `programs`. Una sola fuente de verdad, cero cambios en Flutter |
| **D13** | El `sections` de Fase 0 (`nombre`, `cupo_maximo`, `activa`) no era el que exige M3 (`period_code`, `subject_id`, `name`, `max_capacity`) y **no tenía `program_id`**, así que la cabecera del cuadrante era ambigua y la Regla 2 de M2 era inimplementable | ✅ **Resuelta** — `sections` rediseñada completa (0 filas, 0 consumidores: no había nada que conservar) + `program_id` + **Regla 2 implementada** como trigger. Ver §10 |
| **D14** | `aspirantes.curso_seleccionado` es **texto libre** con el nombre del curso: renombrar un programa rompe la referencia de los aspirantes que lo eligieron | ⏳ **Abierta** — la corrección es una columna `program_id` con FK, y toca el formulario público (M1). Sin urgencia: `aspirantes` tiene 0 filas |
| **D15** | Dos convenciones de período incompatibles: `system_settings.periodo_activo` = `"2026-1"` frente a los períodos del documento (`'SA26-2'`). La Regla 2 compara ambas cadenas, así que **nunca dispararía** | 🔴 **DECISIÓN PENDIENTE** — no se elige por cuenta propia: afecta a la nomenclatura institucional. Ver `REPORTE_ARIA.md` R-06 |

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

> El fallo 8 es el motivo por el que existe la prueba de humo. Las pruebas de
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
npm test              # 341 pruebas, incluidas las del módulo R2, las de OpenAPI y las de M3
npm run build

# --- Contra la infraestructura REAL (lo que no ve ninguna prueba anterior) ---
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs   # 81 comprobaciones
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs    # aplicar migraciones
node supabase/crear-admin.mjs correo@dominio.com                    # primer admin
node backend/test-humo.mjs                                          # 24 comprobaciones
node supabase/humo-invitaciones.mjs                                 # 17 comprobaciones (--confirmar escribe)
node supabase/humo-cuadrante.mjs --confirmar                        # 53 comprobaciones (escribe y purga)
```

### Las tres redes de seguridad, y qué cubre cada una

| Red | Qué demuestra | Qué NO puede ver |
| --- | --- | --- |
| `flutter test` (197) | La lógica del cliente | El SQL, la API, la red |
| `supabase/tests` (164) | Las migraciones sobre PostgreSQL real: RLS y triggers | La API, el despliegue |
| `npm test` (341) | La API completa sobre dobles en memoria | La base real, las credenciales |
| `verificar-esquema.mjs` (81) | Que el esquema **desplegado** es el esperado | El comportamiento de la API |
| `test-humo.mjs` (24) | La cadena entera: API → GoTrue → Postgres, en la nube | Casos que no se le ocurran a nadie |
| `humo-invitaciones.mjs` (17) | RLS con JWT reales y el ciclo invitar → activar | La pantalla de activación en un navegador |
| `humo-cuadrante.mjs` (53) | El mensaje REAL del trigger, la colisión que cruza dos tablas y la RLS de las vistas por rol | El frontend de M3 |

> **La red de `supabase/tests` tiene un punto ciego, y M3 lo demostró.** Corre
> como el **dueño** de las tablas, así que **no ve los problemas de privilegios**:
> el dueño se salta la comprobación de `EXECUTE` sobre funciones. Ese punto ciego
> dejó pasar un fallo que hacía inoperable el módulo entero (R-20). La sección
> 14.8 escribe ahora como `authenticated` con claims de admin para cubrirlo.
> **Si añades una prueba de trigger, pregúntate como qué rol está escribiendo.**

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
aplica el shim de Supabase y **las diez migraciones**, y ejecuta 164 aserciones
sobre el resultado: cortacircuitos, auditoría, idempotencia, RLS por rol,
integridad, las dos reglas de negocio de M2, la resolución de D12/D13
(la vista `cursos`, la `sections` rediseñada y el trigger de la Regla 2, probado
en las dos direcciones), y el Módulo 3 completo (aulas, lapsos, guardias,
cuadrante, los dos triggers anti-colisión en las dos direcciones —lo que debe
rechazar y lo que debe permitir—, el cruce guardia/clase, y la escritura **como
`authenticated` real**, que es lo que cubre el punto ciego de R-20).
**Las migraciones se validan aquí aunque el validador corra en PGlite**: el
validador las levanta en un PostgreSQL real y comprueba que los triggers hacen
lo que dicen hacer.

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
| Base de datos en la nube | ✅ Migrada y verificada (81/81) |
| Libro mayor de migraciones | ✅ 10/10 con checksum (D10 resuelta) |
| Primer administrador | ✅ `lorenzo-roca11@hotmail.com` con rol `admin` |
| Canal de invitación de docentes | ✅ Humo de extremo a extremo (17/17) |
| API contra la base real | ✅ 24/24 comprobaciones |
| Contrato OpenAPI 3.1 | ✅ Generado desde Zod, con 9 pruebas de coherencia |
| Repositorio en GitHub | ✅ `Burmistrov4/INCES---LMS` — `main` sincronizado con `origin/main`, verificado con `git ls-remote`. Árbol limpio |

> **Por qué aquí no hay un SHA.** Este documento viaja *dentro* del commit que
> describe, así que cualquier hash escrito en él nace ya obsoleto — es la misma
> trampa que produjo D11. La fuente real es `git ls-remote origin refs/heads/main`;
> cuando se necesita el SHA, se pregunta a git, no a este archivo.

**Lo que queda en su tejado, en orden:**

1. **Abrir la pantalla de activación en un navegador** con un token real
   (`http://localhost:8080/#/auth/activate?token=…`) y confirmar que lee el token
   del fragmento. Es la mitad de interfaz que el humo no cubre.
2. ~~Aplicar las dos migraciones de M2 a la nube~~ — **hecho** el 2026-09-15:
   el libro mayor marca 10/10 y la verificación independiente del esquema da 81/81.
3. **Mandar las credenciales de Cloudflare R2** cuando quiera encender M5. El
   módulo está construido y probado; sólo está apagado.
4. **Arrancar el frontend con puerto fijo** contra la nube:

   ```bash
   flutter run -d chrome --web-port=8080 --dart-define-from-file=.env.json
   ```

   El `--web-port=8080` no es opcional: sin él Flutter toma un puerto libre
   distinto en cada arranque y `CORS_ORIGINS` lo rechaza.

### Luego: M3 Cuadrante, y lo que queda por delante

1. ~~Decidir D12 y D13~~ — **hecho** el 2026-09-15. Ver §10.
2. ~~Aplicar las migraciones `202609150001` y `202609160001`~~ — **hecho** el
   2026-09-15, y `verificar-esquema.mjs` actualizado.
3. ~~Implementar las rutas de M2 (`/api/v1/admin/programas`, `/materias`)~~ —
   **hecho**: las 7 rutas existen, el repositorio llama a las dos funciones por
   `supabase.rpc(...)` y el contrato está en `docs/CONTRATO_API_MODULO2.md`.
4. ~~El asistente de tres pasos en Flutter~~ — **hecho**: es la parte de M2 que
   faltaba, y ya está con sus pruebas de widget.
5. ~~Aplicar el esquema de M3~~ — **hecho** el 2026-09-15
   (`202609180001` + la corrección `202609180002`). Ver §12.
6. ~~Implementar las 14 rutas de M3~~ — **hecho** el 2026-09-15. Las 14 rutas
   existen y están documentadas en `openapi.json` (29 rutas, 62 esquemas): las 13
   de administración bajo `/api/v1/admin` —`/aulas`, `/periodos`, `/guardias`,
   `/cuadrante`— más `/api/v1/mi-horario`. Incluye el código de error nuevo
   `CHOQUE_DE_AGENDA` (409) y la traducción del `23514` de colisión por el texto
   del mensaje. Ver `docs/CONTRATO_API_MODULO3.md`.
7. **El frontend de M3** — es lo único que falta del módulo: las pantallas de
   aulas, lapsos, guardias y la rejilla del cuadrante. El backend y el esquema no
   van a moverse, así que se puede construir contra el contrato sin esperar.
8. **Encender `m2_curriculo` y `m3_cuadrante` desde el cPanel** cuando sus
   pantallas existan. El interruptor ya funciona; lo que falta es lo que hay
   detrás.
9. **Exponer las rutas de M5** recibiendo `PuertaAlmacenamiento` inyectado, y
   cerrar D9 con una regla de ciclo de vida en R2.
10. **Diseñar M6 (asistencia por QR)** según lo definido: el backend emite un JWT
   temporal de 5 minutos atado al `schedule_slot` de la sección; el docente
   muestra el QR; el alumno lo escanea y envía el token; el backend valida
   caducidad, cruza con `enrollments` y registra la asistencia. Tres faltas
   consecutivas disparan el motor de bids de M4. **No se implementa todavía**:
   el esquema de M3 ya existe, pero M4 (bids) no.
11. **Decidir R-06** (convención de período: `2026-1` frente a `SA26-2`). Ya no
   deja una guarda inerte —el catálogo `academic_periods`, la FK desde `sections`
   y el trigger de `periodo_activo` hacen imposible la divergencia silenciosa—,
   pero sí decide **cuántos lapsos** acaban existiendo: si la coordinación usa
   `SA26-2` mientras el parámetro dice `2026-1`, habrá dos lapso para lo mismo.
   Lo que cambió es que ahora eso se ve, en vez de pasar inadvertido.
   **No se elige unilateralmente: la decide el equipo.**

---

## 9. Módulo 2 — Currículo y Pensum: completo

**Estado: esquema aplicado a la nube, backend y frontend completos.** Son dos
archivos —`supabase/migrations/202609150001_mod2_curriculo.sql` (las tres tablas)
y `supabase/migrations/202609160001_resolucion_d12_d13.sql` (las deudas)—: el
validador de SQL los prueba en cada corrida, el esquema desplegado los tiene y
`verificar-esquema.mjs` lo comprueba de forma independiente. El contrato de sus
7 rutas está en `docs/CONTRATO_API_MODULO2.md` y el asistente de tres pasos en
Flutter ya está construido y probado.

### Las tres tablas

| Tabla | Papel |
| --- | --- |
| `programs` | La oferta macro: carreras y cursos libres |
| `subjects` | Banco global de materias, compartido entre programas |
| `program_subjects` | El pensum: qué materia va en qué programa y en qué período |

La tabla puente no es decoración: es lo que permite que Inglés Técnico exista
**una vez** y esté en cinco pensums. Duplicar la materia por programa es lo que
hace que después las notas de dos alumnos de la misma materia no sean
comparables.

### Las dos reglas de negocio, y cómo se hacen cumplir

**Regla 1 — no existen carreras vacías.** Un programa activo con cero materias es
un error del administrativo, no un estado válido. Se implementa con un
**constraint trigger diferido** (`exigir_pensum_no_vacio`): se declara
`deferrable initially deferred`, así que la comprobación corre **al confirmar la
transacción**, no al insertar cada fila. Esa diferencia es exactamente la que
permite que el asistente de tres pasos mande el programa y su pensum en **una
sola petición** y pase la validación, mientras que un `insert` suelto sin
materias falla. El documento pide un `POST` consolidado al final; el diferido es
lo que hace que las dos cosas sean compatibles.

**Regla 2 — inmutabilidad en uso.** No se puede cambiar el `period_order` de un
pensum ni quitarle materias si ya hay secciones activas del período vigente
usando ese programa. **Implementada** en `202609160001`, como trigger
`program_subjects_proteger_en_uso` sobre `program_subjects`. Dependía de
`sections.program_id`, que es justo lo que añadió D13; mientras esa columna no
existió, la regla no era escribible. Detalle en §10.

Una salvedad que hay que decir en voz alta: **la regla falla abierta si
`system_settings.periodo_activo` está vacío.** Es una guarda de integridad, no
una barrera de seguridad — la misma decisión que se tomó con el modo
mantenimiento (D5). Si el período no está declarado, no hay «período vigente»
contra el que comparar, y bloquear todo sería peor que dejar pasar un cambio que
el administrativo puede deshacer.

### Decisiones de diseño, y de dónde salen

| Decisión | Por qué |
| --- | --- |
| `text` + `check` en vez de `enum` de Postgres para `type` | Es la convención ya establecida del proyecto (`auth_logs.estado` lo dice por escrito: «no se usa un enum de Postgres para no atarnos al dialecto»). El documento pide `ENUM`; se sigue la convención del código |
| `is_active boolean not null default false` | El documento pone `DEFAULT TRUE`, pero eso **contradice su propia Regla 1**: un programa nace activo y sin materias, así que todo `insert` fallaría. Nace en borrador; publicarlo es lo que dispara la validación |
| Columnas en inglés (`code`, `name`, `academic_hours`) | El documento las define así y la migración más reciente del proyecto (`teacher_invitations`) ya usa inglés. Las tablas de Fase 0 usan español (`nombre`, `activo`): la mezcla es real y está asumida |
| El servidor construye el pensum en una transacción | Sin transacción, un fallo a mitad del asistente dejaría un programa a medio armar |

### Contrato de API propuesto

Sigue la convención del proyecto (`/api/v1/admin/…`, en español), no la ruta
literal del documento (`/api/v1/programs/setup`): las rutas de administración ya
viven bajo `/api/v1/admin` y ese prefijo es el que aplica `exigirAdmin`.

| Método | Ruta | Qué hace |
| --- | --- | --- |
| `GET` | `/api/v1/admin/programas` | Lista paginada (`?tipo=`, `?activo=`, `?busqueda=`) |
| `GET` | `/api/v1/admin/programas/:id` | Detalle con el pensum agrupado por período |
| `POST` | `/api/v1/admin/programas` | **El asistente**: programa + pensum en una transacción |
| `PATCH` | `/api/v1/admin/programas/:id` | Metadatos: `nombre`, `requires_internship`, `is_active` |
| `PATCH` | `/api/v1/admin/programas/:id/pensum` | Reemplaza el pensum. 409 si hay secciones activas (Regla 2) |
| `GET` | `/api/v1/admin/materias` | Banco global (`?busqueda=`, paginado) |
| `POST` | `/api/v1/admin/materias` | Registra una materia en caliente (el modal del paso 2) |

Ninguna ruta borra: archivar es `is_active = false`, para no romper históricos.
Las siete rutas quedan documentadas en OpenAPI por construcción, y
`test/openapi.test.ts` obliga a declararlas en la lista esperada.

### Deuda que este diseño abrió — y su cierre

Las dos deudas que este diseño destapó quedaron resueltas el 2026-09-15 en
`202609160001_resolucion_d12_d13.sql`. El relato completo está en §10; aquí sólo
queda el enlace:

- **D12 — `cursos` contra `programs`.** ✅ **Resuelta.** `programs` es la única
  fuente de verdad y `cursos` pasó a ser una vista de compatibilidad, para no
  dejar la app rota entre la migración y el cambio en Flutter.
- **D13 — `sections` no era la que M3 necesita.** ✅ **Resuelta.** Rediseñada
  completa, con `program_id`, y la Regla 2 implementada sobre ella.

Queda **D14** abierta (fila en §6): `aspirantes.curso_seleccionado` guarda el
nombre del curso como texto libre, así que renombrar un programa rompe la
referencia de quien lo eligió. La corrección es una columna `program_id` con FK
y toca el formulario público de M1; `aspirantes` tiene 0 filas, así que no
corre prisa.

---

## 10. Resolución de D12 y D13 (2026-09-15)

**Archivo: `supabase/migrations/202609160001_resolucion_d12_d13.sql`.**
Validado contra PostgreSQL real (pglite): aquella migración llevó la suite de 66
a **96** comprobaciones. **La suite siguió creciendo con M3 y hoy son 164** (ver
§7). Las contradicciones que aparecieron al cruzar el
documento de M2 con el código base están documentadas una por una en
`REPORTE_ARIA.md` (R-01 … R-09).

### Antes de escribir una línea: reconocimiento

Rediseñar `sections` y tocar `cursos` son operaciones destructivas, así que lo
primero fue **medir el daño real contra la base de la nube**, no suponerlo:

| Objeto | Filas | Conclusión |
| --- | --- | --- |
| `cursos` | 5 | Tiene datos: se migran **antes** de soltar la tabla |
| `sections` | 0 | Sin datos y **sin un solo consumidor en el código** |
| `enrollments` | 0 | Nada que reasignar al soltar el FK |
| `aspirantes` | 0 | El texto libre de `curso_seleccionado` no rompe nada hoy |

También se comprobó el nombre exacto del FK (`enrollments_section_id_fkey`) y que
ninguna vista dependiera de `sections`. Esa evidencia es la que justifica recrear
la tabla entera en vez de encadenar parches: con cero filas, una definición única
y legible vale más que un historial de `alter` que hay que reconstruir de memoria.

### D12 — `cursos` pasa a ser una vista, no una tabla

`cursos` (Fase 0) y `programs` (M2) eran el mismo concepto: el catálogo de oferta
formativa. Los cinco cursos sembrados — Herrería, Higiene y Manipulación de
Alimentos, Estética (cejas y pestañas), Oratoria y el Curso Introductorio — son
exactamente `CURSO_LIBRE`, uno de los dos tipos que M2 modela.

La migración **conserva el `id`** de cada curso al insertarlo en `programs`, le
asigna un `code` determinista (`CUR-HER-01`, `CUR-HIG-01`, …) y es idempotente
(`not exists` + `on conflict do nothing`), así que correrla dos veces no duplica
nada.

En vez de borrar `cursos`, lo convierte en una **vista de compatibilidad**:

```sql
create view public.cursos with (security_invoker = true) as
select p.id, p.name as nombre, p.is_active as activo, p.created_at
from public.programs p where p.type = 'CURSO_LIBRE';
```

La vista no duplica datos: es una proyección, y `programs` es la única fuente de
verdad desde ahora. Se eligió la vista por una razón concreta: el único
consumidor — `SupabaseService.cursosDisponibles()`, que alimenta el desplegable
del formulario público de inscripción — **sigue funcionando sin tocar una línea
de Flutter**. Borrar la tabla habría dejado la app rota entre esta migración y el
cambio en el cliente.

Dos detalles que no son opcionales:

- **`security_invoker = true`.** Sin eso la vista corre con los privilegios de su
  dueño y se convierte en un agujero de escalada: `anon` vería cursos archivados.
  Con la opción activa, la RLS de `programs` se aplica a quien consulta. Hay una
  prueba que lo demuestra en las dos direcciones.
- **El `drop` es tolerante al tipo.** `drop view if exists` **no** perdona que
  `cursos` sea una tabla: `if exists` perdona la ausencia, no el tipo
  (`ERROR: "cursos" is not a view`, código 42809). Por eso el `drop` consulta
  `pg_class.relkind` y emite el `DROP` correcto según lo que encuentre, de modo
  que la migración sirve tanto en una base limpia (donde `cursos` es tabla) como
  en una ya migrada.

### D13 — `sections` rediseñada, y la Regla 2 por fin implementable

El `sections` de Fase 0 (`nombre`, `cupo_maximo`, `activa`) no era la sección que
M3 necesita y —lo grave— **no tenía `program_id`**. Sin esa columna pasaban dos
cosas: la cabecera del cuadrante (`PERÍODO | ESPECIALIDAD | SECCIÓN`) quedaba
ambigua, porque una materia puede pertenecer a varios programas (ese es el punto
del M2M del pensum), y la Regla 2 de M2 no era comprobable.

La tabla se recrea con `program_id` (NOT NULL, `on delete restrict`),
`subject_id` (`on delete restrict`), `period_code`, `name`, `max_capacity`,
`is_active`, y `unique (period_code, subject_id, name)` — la misma materia puede
abrir `SA`, `SB` y `SC` en el mismo período, pero no dos veces `SA`. Se
reconstruyen el FK desde `enrollments` (`on delete cascade`), la RLS, los
permisos (sin `DELETE` para nadie), el trigger de `updated_at` y un índice
parcial `sections_programa_periodo_idx`.

El `restrict` es deliberado en las dos referencias: una sección abierta es un
compromiso con los alumnos matriculados, así que ni la materia ni el programa se
borran mientras exista.

### La Regla 2, implementada como trigger

```sql
create trigger program_subjects_proteger_en_uso
before update of period_order, program_id or delete on public.program_subjects
for each row execute function public.proteger_pensum_en_uso();
```

El `of period_order, program_id` acota el trigger a los cambios que importan: un
guardado que no toca esas columnas no dispara nada. La función, por su parte:

- **Falla abierta** si no hay período vigente. Es una guarda de integridad, no una
  barrera de seguridad: sin período declarado no hay nada con qué comparar, y
  bloquear todo sería peor que dejar pasar un cambio reversible. Es la misma
  decisión que se tomó con el modo mantenimiento (D5).
- **Ignora las actualizaciones que no cambian nada** (`is not distinct from`), para
  no bloquear un guardado que reescribe los mismos valores.
- **Comprueba los dos lados** de un movimiento: `old.program_id` y
  `new.program_id`. Mover un pensum desde un programa en uso también se bloquea.
- **Falla ruidosamente** con `23514` y un mensaje que nombra el período y la vía
  de escape, en vez de devolver un error mudo.

### El conflicto de la Regla 1 que hubo que corregir

La Regla 1 («no existen carreras vacías») tal como estaba escrita habría
bloqueado los cinco cursos migrados: un `CURSO_LIBRE` es un taller corto que
puede no tener pensum. La corrección **acota la regla a `type = 'CARRERA'`**, y se
hizo en `202609150001` mientras ese archivo todavía estaba *pendiente* de
aplicar, es decir, sin violar la inmutabilidad de las migraciones ya corridas. Es
el tipo de cosa que sólo se ve cruzando el documento con los datos reales.

### Lo que queda en el tejado de Lorenzo: D15

**Dos convenciones de período incompatibles.** `system_settings.periodo_activo`
guarda `"2026-1"`, mientras que los ejemplos del documento usan `"SA26-2"`. La
Regla 2 compara las dos cadenas, así que **con la base como está hoy nunca
dispararía**: `'2026-1' <> 'SA26-2'`, y la guarda se considera fuera del período.

No se elige por cuenta propia: es nomenclatura institucional y afecta también a
`sections.period_code`. Está documentado como R-06 en `REPORTE_ARIA.md` y como
D15 en §6. Hasta que se decida, la Regla 2 está implementada pero inerte.

---

## 11. Por qué el asistente de M2 necesita funciones en la base

**Archivo: `supabase/migrations/202609170001_mod2_rpc_curriculo.sql`.** Aplicado
y verificado el 2026-09-15.

### El problema, encontrado midiendo y no suponiendo

El contrato de M2 pide que el asistente cree el programa y su pensum **en una
transacción**. La forma natural en PostgREST sería un *insert anidado*: mandar el
programa con sus materias dentro, en una sola petición.

**Se probó contra la base real, y no funciona.** Tres mediciones, en este orden:

| Qué se probó | Resultado |
| --- | --- |
| `POST /programs` con `program_subjects: [...]` | **`PGRST204: Could not find the 'program_subjects' column of 'programs' in the schema cache`** |
| Lo mismo tras `notify pgrst, 'reload schema'` | El mismo error: **no era la caché** |
| `GET /programs?select=*,program_subjects(*)` (lectura anidada) | **HTTP 200.** La relación existe y PostgREST la conoce |

Es decir: **se puede leer anidado, pero no escribir anidado.** Y PostgREST no
expone transacciones entre peticiones — cada petición es su propia transacción.

### Por qué no se resolvió con tres llamadas

La alternativa sin tocar la base era una secuencia: crear el programa en
borrador, insertar el pensum, publicar. Funciona, y cada paso intermedio es un
estado válido, así que los triggers no se quejan.

Se descartó por una razón concreta: **un fallo entre el paso 2 y el 3 deja un
programa a medio armar**, que es exactamente lo que el contrato quiere evitar. La
barrera de la base seguiría intacta —nunca se confirmaría un estado inválido—
pero el administrativo se encontraría un borrador con materias a medias y sin
explicación.

### La solución: dos funciones, una por operación

Se usa el mecanismo que el proyecto ya empleaba para la lógica que debe ser
atómica (`precheck_aspirante`, `link_pending_aspirante`): una función de
PostgreSQL llamada por PostgREST.

| Función | Qué hace |
| --- | --- |
| `crear_programa_con_pensum(...)` | Inserta el programa y recorre el pensum en un bucle. Devuelve el `id` |
| `reemplazar_pensum(...)` | Borra lo que sobra, reordena lo que cambió e inserta lo nuevo |

Las dos son **`security invoker`, y eso no es un detalle**: con `security
definer` correrían con los privilegios de su dueño y se saltarían la RLS, de modo
que cualquier usuario autenticado podría escribir programas. Con `invoker`, las
políticas de `programs` y `program_subjects` se aplican a quien llama. Hay cuatro
comprobaciones en `verificar-esquema.mjs` que lo vigilan, incluida la de que
`anon` **no** puede ejecutarlas.

Ninguna de las dos reimplementa las reglas de negocio: sólo ordenan las
escrituras para que los triggers las juzguen. Si la Regla 2 bloquea un
reordenamiento, el `raise` aborta la función entera y no queda nada a medias.

### Lo que el humo real demostró

Contra el PostgREST de la nube, no contra un doble:

- Una `CARRERA` **activa** con su pensum se crea en **una sola llamada**, y el
  constraint trigger diferido la acepta.
- Con el pensum vacío, la función falla con `23514` y **no deja ni el programa**.
  Esa es la atomicidad de verdad: un doble en memoria no la puede demostrar.
- `reemplazar_pensum` añade, reordena y borra calculando la diferencia sola.

### Una lección operativa que hay que recordar

Al crear tablas o funciones nuevas, **la caché de esquema de PostgREST no se
entera sola**. Durante el reconocimiento, el insert anidado falló en parte por
eso. Si una ruta nueva responde `PGRST204` o `404` sobre un objeto que existe,
antes de tocar el código: `notify pgrst, 'reload schema'`.

---

## 12. Módulo 3 — Cuadrante, aulas y guardias: esquema y backend

**Estado: esquema aplicado, verificado y corregido, y backend completo.** Falta
el frontend. Dos archivos de esquema
—`supabase/migrations/202609180001_mod3_cuadrante_aulas.sql` (todo el diseño) y
`supabase/migrations/202609180002_mod3_trigger_agenda_definer.sql` (la corrección
de R-20)—. El contrato completo de las 14 rutas está en
**`docs/CONTRATO_API_MODULO3.md`**, que es el documento que hay que leer antes de
tocar nada de este módulo.

### El backend (PASO 4, cerrado el 2026-09-15)

Seis piezas, en el mismo reparto hexagonal que M2:

| Pieza | Qué contiene |
| --- | --- |
| `dominio/reglas-cuadrante.ts` | Las reglas puras: `turnoDeBloque` (espejo de la función SQL), `diaLegible`, `esChoqueDeAgenda`, `esFechaISO`, `rangoDeFechasValido` |
| `dominio/tipos.ts` | `Aula`, `Periodo`, `Guardia`, `ClaseCuadrante`, `DocenteResumen`, `RejillaCuadrante`, `MiHorario`… |
| `dominio/puertos.ts` | `PuertaCuadrante`, con las 13 operaciones. **Sin ninguna de «¿está libre?»**: preguntar antes de escribir es una carrera y una segunda copia de la regla |
| `infra/repos-supabase.ts` | `CuadranteSupabase`. Escribe contra la tabla y **relee de la vista**; traduce el `23514` de colisión a `CHOQUE_DE_AGENDA` reutilizando el mensaje del trigger |
| `http/esquemas.ts` | Los esquemas Zod: día 1–6, bloque 1–12, código de lapso, fecha que existe, y el rechazo explícito de `turno` y `periodo` por ser derivados |
| `http/rutas/cuadrante.ts` | Las 14 rutas, y `http/openapi.ts` su documentación |

**Dos decisiones que conviene conocer antes de leer el código:**

1. **El `turno` se lee, no se recalcula.** Es una columna generada;
   `turnoDeBloque()` sólo actúa como respaldo. Así, mover la frontera de turnos
   (R-16) no puede hacer que el backend y la base digan cosas distintas.
2. **`GET /cuadrante` proyecta `docentes` de `profiles`, y no usa
   `nombre_para_mostrar()`.** La función sigue siendo necesaria para el horario
   del **estudiante** (§7 del contrato, R-14), pero un administrador sí puede
   leer todos los perfiles (`profiles_admin_all`), así que la ruta de
   administración lee sólo `id`, `nombres`, `apellidos`. Son dos problemas
   distintos y por eso conviven las dos soluciones.

**Pruebas nuevas: 101.** `test/reglas-cuadrante.test.ts` (20),
`test/cuadrante.test.ts` (60) y los casos de M3 en `test/esquemas.test.ts`. El
doble en memoria del arnés reproduce el chequeo cruzado con **los dos mensajes
verbatim de la migración**, así que `esChoqueDeAgenda` se ejercita de verdad y no
contra un texto inventado.

> **`test/openapi.test.ts` ya no coteja contra una lista escrita a mano.** Ahora
> compara el documento contra el árbol **real** de Fastify en las dos
> direcciones, leído con `printRoutes()` después de `await app.ready()` — antes
> de eso, las rutas montadas dentro de un `app.register(...)` no aparecen y la
> comparación daría un verde hueco. Esto cierra el punto ciego de D6: añadir una
> ruta y olvidar documentarla ahora falla.

### El humo real, y lo que encontró

`node supabase/humo-cuadrante.mjs --confirmar` → **53/53, sin residuo**. Escribe
con el **JWT de un administrador real** (no con la service role key), porque eso
es lo que hace el backend, así que comprueba de paso las políticas `*_admin_all`
y el `with check`. Cubre lo que un doble no puede: el mensaje real del trigger
con el día y el bloque interpolados, la colisión cruzada clase-contra-guardia,
que el mismo hueco en otro lapso sí se permite, la sintaxis de PostgREST
—incluido que doblar los paréntesis del `or(...)` **sí** lo rompe—, que
`PGRST116` existe de verdad al parchear un id ausente, y la RLS por rol a través
de las vistas `security_invoker`.

> **Encontró R-21: el nombre del docente llega vacío al cuadrante.** El canal de
> invitación nunca captura `nombres`/`apellidos`, así que `nombre_para_mostrar()`
> devuelve NULL y la columna del docente queda en blanco. La función está bien
> escrita; el hueco es del Módulo 1. **Decisión del equipo**, no técnica: ver
> `REPORTE_ARIA.md` **R-21** y `HANDOVER.md` §2.6.

Y por el otro lado, `backend/test/reglas-cuadrante.test.ts` **lee la migración
como texto** y comprueba contra ella `turnoDeBloque`, `diaLegible` y
`esChoqueDeAgenda`. Antes esas pruebas copiaban el mensaje a mano —probaban que
el detector reconoce **la copia**, no el original—. Ahora los dos lados no pueden
separarse en silencio.

### Las cuatro tablas y por qué cada una

| Tabla | Qué resuelve |
| --- | --- |
| `academic_periods` | El lapso deja de ser un texto suelto. `sections.period_code` pasa a ser **FK** contra él, así que la divergencia silenciosa de R-06 se vuelve imposible (R-12) |
| `classrooms` | Un **solo** concepto de espacio: aulas, talleres y zonas. Una zona es una fila con `capacity = 0` (R-18) |
| `teacher_duties` | La guardia de custodia: docente + espacio + día/bloque, con o sin clase. Lleva `period_code` obligatorio (R-15) |
| `schedule_slots` | El cuadrante: sección + docente + aula + día/bloque. El lapso **no** se guarda: se deriva de la sección |

### La colisión, que es el corazón del módulo

Un docente no puede estar en dos sitios a la vez, y un espacio no puede alojar
dos grupos a la misma hora. **Ningún `unique` puede expresar eso**, por dos
motivos: la colisión cruza **dos tablas** (`teacher_duties` y
`schedule_slots`), y en `schedule_slots` el lapso no es una columna —un
`unique (teacher_id, day_of_week, block)` **prohibiría** que el mismo docente
dictara el mismo bloque en dos lapsos distintos, que es planificar el siguiente—.

Por eso vive en **una función compartida** (`exigir_agenda_libre()`, que hace dos
comprobaciones y cada una consulta las dos tablas) y **dos triggers finos**. Dos
escrituras simultáneas se serializan con `pg_advisory_xact_lock` indexado por
`(lapso, día, bloque)`, para que sólo se esperen las que podrían chocar.

Los detalles completos —incluido el fallo `42501` que dejó el módulo inoperable y
cómo se corrigió, y por qué 156 aserciones en verde no lo vieron— están en
`REPORTE_ARIA.md` **R-20** y en `docs/CONTRATO_API_MODULO3.md` **§10**. **Es
lectura obligatoria antes de tocar esos triggers.**

### Lo que NO se inventó, y es deliberado

| Dato | Por qué está vacío |
| --- | --- |
| Aulas y zonas | El inventario del CFS es un dato institucional. **No se siembra** (R-18) |
| Guardias y clases | Dependen de las aulas y del cuadrante real |
| Fechas del lapso | El centro no las ha cargado. `start_date`/`end_date` son nulas **a propósito** (R-17) |
| Nombre del lapso | Sólo se sembró `2026-1`, **leído de `system_settings`**, no escrito a mano |

Mientras `classrooms` esté vacía, el cuadrante no se puede usar —una clase sin
aula no existe— y la UI tendrá que decirlo en vez de mostrar un desplegable vacío
sin explicación.

