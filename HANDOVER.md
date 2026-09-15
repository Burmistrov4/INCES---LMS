# HANDOVER — INCES LMS

> Traspaso de mando generado el **2026-09-13**, revisado el **2026-09-14**,
> puesto al día el **2026-09-15** (Módulo 2 completo) y **actualizado el
> 2026-09-15 con el Módulo 3 completo**: esquema aplicado, verificado y
> **corregido** (un fallo que dejaba el módulo inoperable, ver §2.6) **y backend
> terminado** — las 14 rutas del contrato ya existen, están registradas en Fastify
> y documentadas en `openapi.json`. Todo lo que aparece aquí fue verificado contra
> el repositorio en el momento de redactarlo. Si algo de este documento
> contradice al código, **gana el código**: avísame y lo corrijo.

---

## ✅ Estado del repositorio: limpio y sincronizado

**Todo el trabajo está en GitHub.** El working tree está limpio y `main` coincide
exactamente con `origin/main`.

```
HEAD = origin/main
```

**Aquí no hay un SHA, a propósito.** Este documento viaja *dentro* del commit que
describe, así que cualquier hash escrito aquí nace ya obsoleto — el commit que lo
contiene lo mueve. Compruébalo tú:

```bash
git rev-list --left-right --count origin/main...HEAD   # debe dar: 0	0
git log --oneline -8                                   # los últimos commits
```

Los últimos commits, que sí son estables porque son anteriores a este archivo:

```
cb20d58  docs(handover): no escribir el SHA dentro del commit que describe
2f41720  docs(handover): sincronizar el traspaso con el modulo 3 y corregir la fecha
dfb0a8b  docs(modulo3): contrato de API y verificacion de esquema desplegado
d676907  fix(modulo3): los envoltorios de trigger anti-colision deben ser security definer
50aed06  feat(modulo3): esquema DDL de cuadrante, aulas, guardias y triggers anti-colision
3c62c53  docs(handover): modulo 2 aplicado, UI completa y humo real en verde
ec361ac  feat(modulo2): UI del asistente de curriculo y pensum
9291e9a  fix(modulo1): garantizar lectura de token desde uri fragment en activacion
```

> **Nota de proceso, para que no se repita.** El push estuvo bloqueado varias
> sesiones con `fatal: could not read Username for 'https://github.com': terminal
> prompts disabled`: el *credential helper* no devolvía credencial y no había
> `GITHUB_TOKEN` ni `~/.git-credentials`. **El diagnóstico era correcto pero la
> conclusión no:** no era un problema del repositorio ni del remoto, era del
> entorno de ejecución, y se resolvió fuera de él. Antes de declarar un push
> «imposible», comprueba si el entorno cambió: `GIT_TERMINAL_PROMPT=0 git push`
> falla rápido en vez de colgarse cinco minutos esperando una consola que no existe.

Nota de higiene: `.env`, `.env.json` y la carpeta de contexto están en
`.gitignore`, así que **ninguna credencial entró al commit**. `backend/.env.example`
sí se versiona a propósito (es la plantilla documentada, sin valores reales).
`.workbuddy-ai/` también está ignorado: la memoria del proyecto no viaja al repo.

### ✅ Migraciones de M2 y M3 aplicadas en la nube (verificado, no supuesto)

Las 10 migraciones están aplicadas. El libro mayor lo confirma:

```
$ SUPABASE_ACCESS_TOKEN=sbp_… node supabase/apply-migrations.mjs --check
  Proyecto : twdppwnxlnmxkiejbrei   (ACTIVE_HEALTHY, sa-east-1)
  Migraciones: 10

  aplicada   202609100001_init.sql
  aplicada   202609120001_phase1_onboarding.sql
  aplicada   202609120002_phase3_admin_core.sql
  aplicada   202609120003_proteger_ultimo_admin.sql
  aplicada   202609130001_invitaciones_docente.sql
  aplicada   202609150001_mod2_curriculo.sql
  aplicada   202609160001_resolucion_d12_d13.sql
  aplicada   202609170001_mod2_rpc_curriculo.sql
  aplicada   202609180001_mod3_cuadrante_aulas.sql
  aplicada   202609180002_mod3_trigger_agenda_definer.sql

  0 pendiente(s), 0 con deriva.
```

`node supabase/verificar-esquema.mjs` → **81/81 OK, 0 fallos** (comprobado el
2026-09-15). Incluye las aserciones de M2 (`cursos` es vista con
`security_invoker`, `programs.type`/`is_active`, `sections.program_id`, los dos
constraint triggers, las dos funciones del asistente) y **las de M3**: las 4
tablas nuevas con sus columnas, la FK `sections.period_code → academic_periods`,
el lapso vigente registrado, las 3 vistas con `security_invoker`, el `turno` como
columna generada, y —la más importante— **`prosecdef` de los dos envoltorios
anti-colisión debe ser `DEFINER`** (ver §2.6).

---

## 1. Resumen del Estado Actual del Código

### Suite de pruebas

| Suite | Resultado | Comando |
|---|---|---|
| Backend (vitest) | **333 / 333** en verde | `cd backend && npm test` |
| Flutter | **197 / 197** en verde | `flutter test` |
| SQL (pglite, PostgreSQL real) | **164 / 164** en verde · 10 migraciones | `cd supabase/tests && npm test` |

> **Corre `flutter test` ENTERO antes de commitear**, no sólo el archivo que
> tocaste. En el cierre de M2, correr los archivos sueltos daba verde y la suite
> completa destapó **6 fallos** (rótulos en mayúsculas que los tests buscaban en
> minúsculas, y un `hintText` que `find.text` también encuentra).

### Compilación y linters

| Verificación | Estado |
|---|---|
| `npm run typecheck` (`tsc --noEmit`) | ✅ limpio |
| `npm run lint` (eslint) | ✅ limpio |
| `flutter analyze` | ✅ **No issues found!** |

> **Nota para el nuevo agente:** `flutter test` **SÍ funciona** en este entorno.
> Una nota antigua de la memoria decía que no, y era falsa: lo que está bloqueado
> es `flutter devices` / enumerar Chrome (lo impide `reg.exe`). No pierdas tiempo
> reintentando eso; simplemente no lances la app en Chrome desde aquí.

### Versiones confirmadas

- **Flutter 3.47.0** (stable) · **Dart 3.13.0**
- **Supabase** en la nube: `ACTIVE_HEALTHY`, región `sa-east-1`, **PostgreSQL 17.6**
- Node/TS con **Fastify 5**

### Últimas características integradas

**a) `GET /api/v1/admin/acceso`** — auditoría de accesos sobre `auth_logs`.
Paginada y con filtros por `estado` (`SUCCESS`/`FAILED`), `email` y `userId`.
Protegida por el `preHandler` `exigirAdmin()` del prefijo `/api/v1/admin`.

Archivos tocados: `dominio/puertos.ts`, `infra/repos-supabase.ts`,
`http/esquemas.ts`, `http/rutas/admin.ts`, `http/openapi.ts`.
`openapi.json` regenerado: **29 rutas, 62 esquemas** (incluidas las 14 de M3).

**Regla de oro de paginación (no la rompas):** el total se cuenta **primero** con
`{ head: true, count: 'exact' }`, y se devuelve página vacía si
`desplazamiento >= total`. Esto evita el **416 Range Not Satisfiable** de
PostgREST. `esRangoNoSatisfacible()` queda como red de seguridad. Copia el patrón
de `PerfilesSupabase.listar` / `AuditoriaAccesoSupabase.listar`.

**b) `CpanelAuditoriaAccesosPanel`** — panel Flutter con filtros, auto-refresh
cada 30 s y paginación. Si el auto-refresh falla, **conserva los últimos datos
buenos** y avisa; no vacía la lista.

**c) `.docx` conceptual ajustado a 3 roles** — la "Matriz de Roles Estrictos"
pasó de 4 a los 3 valores reales de Postgres. Ver sección 5.

**d) Módulo 2 completo** — currículo y pensum, de la base a la UI. Dos RPC
transaccionales, 7 rutas bajo `/api/v1/admin`, OpenAPI regenerado, y el asistente
de tres pasos en Flutter. Ver §2.5.

**e) Deep link de activación arreglado** — `initialRoute` con `?token=` descartaba
el token en silencio. Ver §2.4.

**f) Bug de layout pre-existente, silencioso y arreglado.** `ContenidoSeccion`
envolvía a su hijo en un `SingleChildScrollView`, dándole **altura infinita**:
`CpanelAuditoriaPanel` y `CpanelAuditoriaAccesosPanel` **crasheaban al abrirse en
la app real** (usan `Expanded`). Sus tests no lo veían porque montaban el panel en
el `body` acotado de un `Scaffold`, que **no es como se monta de verdad**.
Arreglado con `Flexible`, y hay una prueba nueva que los monta **dentro de
`ContenidoSeccion`** (`test/contenido_seccion_test.dart`).

**g) Módulo 3 backend completo** — las 14 rutas de cuadrante, aulas y guardias,
en el mismo reparto hexagonal que M2. Ver §2.6.

---

## 2. Pendientes Críticos Inmediatos (Next Steps)

### 2.1 Migración de la base real — ✅ YA APLICADA

`202609130001_invitaciones_docente.sql` **ya está aplicada** en
`twdppwnxlnmxkiejbrei`. Se crearon `teacher_invitations` y `auth_logs`, ambas con
**RLS activo**, y sus columnas coinciden exactamente con el contrato del backend:

```
auth_logs            : id, user_id, email, ip_address, estado, created_at
teacher_invitations  : id, email, token_hash, is_used, created_at, expires_at
```

`node supabase/verificar-esquema.mjs` → **43/43 sin fallos**.

> **El 32/32 que figuraba aquí era falso, y el script estaba en rojo.** Al añadir
> el libro mayor (`schema_migrations`) en D10, esa tabla no estaba en el arreglo
> `esperadas` del verificador, así que saltaba como «tabla heredada»: 40
> comprobaciones con 1 fallo. Arreglado, y añadida una sección que verifica el
> propio libro mayor. **Cada migración que crea tablas debe tocar
> `verificar-esquema.mjs` en el mismo paso.**

#### ✅ D10 resuelta: `apply-migrations.mjs` ya lleva libro mayor

**El footgun está erradicado.** Antes el script reaplicaba las 5 migraciones en
cada ejecución y se detenía al primer error; como 4 de los 5 archivos tienen
`create policy` / `create trigger` sin guarda, reejecutar sobre una base ya
migrada podía fallar a medio camino. Ahora hay un libro mayor:

```
public.schema_migrations (version PK, checksum, applied_at)
```

- Sólo se ejecutan los archivos **ausentes** del libro.
- Se guarda el **SHA-256** de cada archivo. Si uno ya aplicado cambia, se detecta
  **deriva** y el script **se niega a tocar la base** (`exit 1`, apto para CI).
- La fila del libro se inserta **en el mismo lote** que la migración: o quedan
  las dos cosas o ninguna. No hay estado a medias.

```bash
# diagnóstico: qué está aplicado, pendiente o con deriva (no escribe)
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --check

# aplicar sólo lo pendiente
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs

# registrar como aplicado SIN ejecutar (para bases con esquema ya montado)
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --adoptar

# verificación independiente del esquema
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs
```

Estado actual: **10/10 aplicadas**, `--check` → `0 pendiente(s), 0 con deriva`.

> **Regla nueva:** nunca edites una migración que ya corrió. Si el esquema debe
> cambiar, crea un archivo **nuevo**. Si editas uno aplicado, el script te lo dirá
> y no aplicará nada — es la protección funcionando, no un fallo.

> `--check` **sí** diagnostica de verdad ahora (antes sólo listaba archivos).

- El token se crea en `supabase.com/dashboard/account/tokens`.
- **No confundir** `SUPABASE_ACCESS_TOKEN` (Management API, prefijo `sbp_`) con
  `SUPABASE_SERVICE_ROLE_KEY`. No son intercambiables: la service role key da
  **401** contra la Management API.
- `supabase db push` **no funciona** (deuda D10: la conexión directa es sólo IPv6).
  Usa siempre el script de arriba.

Verificación posterior a aplicar: `node supabase/verificar-esquema.mjs`
(**81/81** comprobaciones; la línea base actual es **81/81**).

Estado del libro mayor al redactar esto: **10 aplicadas, 0 pendientes, 0 con
deriva** — las 10 migraciones de M1, M2 y M3 están en la nube (ver el bloque de
arriba).

### 2.2 Verificación de dominio en Resend — BLOQUEA el correo a terceros

SMTP propio **ya activo** vía Resend (`smtp.resend.com:465`, usuario `resend`,
contraseña = la API key). Pero:

> **Sin un dominio verificado, Resend sólo entrega a la dirección dueña de la
> cuenta** (`lorenzoroca333@gmail.com`). Cualquier otro destinatario se rechaza
> con **403** (`please verify a domain at resend.com/domains`).

Esto significa que el flujo de invitación **sólo se puede probar contra ese
buzón** hasta verificar un dominio en `resend.com/domains`. No es un fallo del
código: es un límite del proveedor.

Consecuencia práctica: para el humo real, invita a `lorenzoroca333@gmail.com`.

### 2.3 Reparto de puertos y `CORS_ORIGINS` — ✅ ALINEADO

**No los cruces.** El reparto canónico es:

```
backend  ->  3000   la API        (PORT, backend/.env)
Flutter  ->  8080   el navegador  (--web-port=8080, obligatorio)
```

```bash
# Backend
cd backend && npm run dev            # escucha en 3000

# Frontend — --web-port NO es opcional
flutter run -d chrome --web-port=8080 --dart-define-from-file=.env.json
```

`API_BASE_URL` vive en `.env.json` y vale `http://localhost:3000` — el puerto del
**backend**, porque es a quien el frontend llama.

> **Corrección de una versión anterior de este documento:** decía que el backend
> fuera en 8080 *y* el frontend en 8080. Eso es una colisión: el segundo en
> arrancar no encuentra puerto. El backend va en 3000.

`CORS_ORIGINS` autoriza el origen del **navegador**, es decir el del frontend
(8080). Poner ahí el puerto del backend no autoriza nada. Valor por defecto ya
corregido en `env.ts` y en `.env.example`:

```
CORS_ORIGINS=http://localhost:8080,http://127.0.0.1:8080
```

> Sin `--web-port`, Flutter elige un puerto **efímero distinto en cada arranque**
> y `CORS_ORIGINS` queda obsoleto al segundo intento: el navegador bloquea la API
> con un error que parece un bug de backend y no lo es.

**⚠️ En la máquina de Lorenzo el puerto 3000 lo ocupa otro proceso `node`**
(`C:\Program Files\nodejs\node.exe`, PID 16884, ajeno a este proyecto: responde
404 en `/salud`). Si no lo libera, el backend no arranca en 3000. Salidas: cerrar
ese proceso, o cambiar `PORT` y ajustar `API_BASE_URL` en `.env.json`. Los tres
valores (`PORT`, `API_BASE_URL`, `CORS_ORIGINS`) deben contar la misma historia.

### 2.4 Humo del canal de invitación — MITAD-API ✅ / MITAD-UI ⚠️ arreglada, sin navegador

**Mitad-API: VERIFICADA** contra la base real con `node supabase/humo-invitaciones.mjs
--confirmar` → **17/17 sin fallos**, cero residuo. Cubre lo que las pruebas con
dobles no podían cubrir:

- RLS de `teacher_invitations` y `auth_logs` con JWT reales: el admin ve, `anon`
  no ve, un `docente` no ve, y **nadie inserta trazas con rol `authenticated`**
  (no hay GRANT de INSERT, por diseño).
- HTTP completo: `POST /admin/usuarios/invitaciones` → `POST /auth/activar` →
  `perfil.rol = 'docente'`, `is_used = true`, traza SUCCESS en `auth_logs`.
- El token es de un solo uso: reutilizarlo se rechaza.
- El token en claro **no** queda en la base (sólo su SHA-256).

**Mitad-UI: el bug de lectura del token está ARREGLADO y cubierto, pero sigue sin
ejecutarse en un navegador real.**

Había un fallo real y silencioso: `initialRoute: '/auth/activate?token=ABC'`
**descartaba el token sin decir nada**. Las rutas de `MaterialApp.routes` se
comparan por **igualdad exacta de cadena**, así que `?token=` no casaba con nada;
`Navigator.defaultGenerateInitialRoutes` partía la ruta por `/`, empujaba los
intermedios y, al no resolver el último, **tiraba la pila inicial entera** y caía
a `/`. El usuario habría visto el login en vez de la pantalla de activación.

Arreglado en `9291e9a`: `lib/core/navegacion.dart` (puro, sin depender de Flutter)
expone `analizarRuta` / `tokenDeUrl`, y `main.dart` usa `onGenerateRoute`. El
token se lee de `Uri.base.fragment`. Las 4 pruebas de
`test/deep_link_activacion_test.dart` montan la **`IncesLmsApp` real** con
`rutaInicial`, y se comprobó *fail-first*: revirtiendo sólo el router, 2 de las 4
fallan con el mensaje exacto de Flutter.

**Lo que falta y no se puede fingir:** abrir
`http://localhost:8080/#/auth/activate?token=…` en un **navegador de verdad**,
fijar la contraseña y llegar al panel. Este entorno **no puede lanzar Chrome**
(`reg.exe` lo bloquea) y la herramienta de navegador no soporta Windows, así que
esa comprobación queda para la máquina de Lorenzo. Montar la app real en una
prueba de widgets es lo más cerca que se pudo llegar desde aquí — **no es lo
mismo que un navegador**, y no se debe anotar como verificado en navegador.

> `correoEnviado` sale `false` en el humo, y **es lo esperado**: el remitente de
> Resend es no bloqueante por diseño (`{ entregado: false }` en vez de excepción),
> así que una invitación siempre se persiste y el enlace viaja en la respuesta.
> Ver 2.2.

#### ⚠️ `crear-admin.mjs` no sirve para un admin de prueba

Usa `inviteUserByEmail`, que exige entrega de correo. Sin dominio verificado en
Resend, cualquier dirección que no sea el buzón dueño devuelve
**`HTTP 500: Error sending invite email`**. Para crear un usuario con sesión,
usa `auth.admin.createUser` con `email_confirm: true` (lo que hace el humo), que
no envía nada.

```bash
node supabase/humo-invitaciones.mjs              # simulación
node supabase/humo-invitaciones.mjs --confirmar  # ejecuta
```

**Nota de arquitectura:** el enlace usa **hash strategy** (`/#/auth/activate`),
no path. Es deliberado: así el servidor siempre entrega `index.html` y no hace
falta un catch-all en el hosting. La pantalla lee el token de `Uri.base.fragment`.

---

### 2.5 Módulo 2 — aplicado: base, backend y UI completos

**Base aplicada.** `202609150001_mod2_curriculo.sql`,
`202609160001_resolucion_d12_d13.sql` y `202609170001_mod2_rpc_curriculo.sql`
están en la nube: **10/10 aplicadas, 0 deriva** (ver el bloque de arriba).

Tres tablas: `programs`, `subjects` (banco global) y `program_subjects` (pensum,
muchos-a-muchos). Además:

- **D12 resuelta:** `cursos` pasó a ser una **vista** `security_invoker` sobre
  `programs`, así los cinco cursos sembrados son `CURSO_LIBRE` sin migrar
  `aspirantes.curso_seleccionado` ni tocar el formulario público de inscripción
  (que lee `cursos` con `anon` y tiene respaldo local en
  `AspiranteRepository.cursosRespaldo`).
- **D13 resuelta:** `sections` ganó **`program_id`**. Sin él, la cabecera del
  cuadrante (`PERÍODO | ESPECIALIDAD | SECCIÓN`) quedaba ambigua —una materia
  puede pertenecer a varios programas, que es el punto del M2M— y la Regla 2 no
  se podía implementar.

Las dos reglas de negocio, **ya implementadas**:

- **Regla 1 — no existen carreras vacías.** Dos **constraint triggers diferidos**
  (`deferrable initially deferred`): `programs_exigir_pensum` en `programs`
  (after insert or update) y `program_subjects_exigir_pensum` en
  `program_subjects` (after delete or update), ambos sobre la misma función
  `exigir_pensum_de_programa()`. La comprobación corre al **confirmar** la
  transacción, no al insertar. Esa es exactamente la propiedad que hace
  compatible la regla con el `POST` consolidado del asistente de tres pasos: sin
  el diferido, las dos exigencias del documento se contradicen entre sí.
- **Regla 2 — inmutabilidad en uso.** `proteger_pensum_en_uso()` bloquea
  reordenar un pensum cuando hay secciones activas del período vigente.

**Las dos lanzan `23514`**, así que se distinguen por el **texto del mensaje**
(`esBloqueoPorPensumEnUso`). No es un descuido: los triggers ya aplicados son
inmutables, y **nunca se edita una migración ya corrida**.

**PostgREST no admite insert anidado de uno-a-muchos** (`PGRST204`; se comprobó
que no era la caché). Sí admite lectura anidada. Por eso las dos escrituras del
asistente son **RPC** —`crear_programa_con_pensum` y `reemplazar_pensum`—,
`security invoker` con `revoke from public, anon`. Ver `REPORTE_ARIA.md` R-10.

**Verificación real, no de dobles:**

| Qué | Resultado |
|---|---|
| pglite (PostgreSQL real, 10 migraciones) | **164 / 164** |
| Esquema en la nube (`verificar-esquema.mjs`) | **81 / 81**, 0 fallos |
| Backend (vitest) | **333 / 333** |
| Flutter | **197 / 197** |
| Humo de M2 contra la base real | **15 / 15**, purga completa |

**El humo de M2 es la prueba que de verdad importa.** Se lanza con
`node supabase/humo-curriculo.mjs --confirmar` (escribe con códigos `TMP` y purga
todo, también si falla a mitad). Demuestra lo que un doble en memoria **no
puede**:

- `crear_programa_con_pensum` publica una CARRERA **activa** con su pensum en
  **una sola llamada**, y el trigger diferido la acepta.
- **Atomicidad de verdad:** con el pensum vacío la función falla con `23514` y
  **no deja el programa a medias** (cero filas).
- `reemplazar_pensum` calcula la diferencia sola: reordena, inserta y borra.
- La Regla 2 bloquea un reordenamiento con secciones activas y **el período queda
  intacto** (`period_order = 1`): la función se deshace entera.

**Desviaciones del documento, conscientes:**

- `type` es `text` + `check`, **no `enum`** de Postgres. La convención del
  proyecto ya está en la migración de M1: «no se usa un enum de Postgres para no
  atarnos al dialecto».
- `is_active` nace en **`false`**, no en `true`. El documento pone `DEFAULT TRUE`,
  pero eso contradice su propia Regla 1: el programa nacería activo y sin
  materias, así que todo `insert` fallaría.
- Las rutas van bajo `/api/v1/admin/…` (español, y ese prefijo es el que aplica
  `exigirAdmin`), no `/api/v1/programs/setup`. **Ya corregido** en
  `docs/CONTRATO_API_MODULO2.md` (`25f2369`), así que el TEG no documentará una
  ruta inexistente.

**Lo que queda de M2:** nada de base, backend ni UI. Sólo dos cosas que no se
pueden cerrar desde este entorno:

1. El **humo de UI en navegador real** (ver 2.4): este entorno no lanza Chrome.
2. La **convención de período** (R-06 / D15). `period_order` es un **número de
   orden**, y el nombre visible del período lo pone la UI; nadie ha decidido
   todavía si el centro numera 1…6 o usa otra cosa. **No se eligió por
   unilateralidad** — es una decisión del equipo.

---

### 2.6 Módulo 3 — esquema aplicado y corregido, **backend completo**; falta el frontend

**Base aplicada.** `202609180001_mod3_cuadrante_aulas.sql` (todo el diseño) y
`202609180002_mod3_trigger_agenda_definer.sql` (la corrección) están en la nube:
**10/10 aplicadas, 0 deriva**.

Cuatro tablas nuevas: `academic_periods` (el lapso deja de ser texto suelto),
`classrooms` (aulas, talleres **y zonas**, un solo concepto), `teacher_duties`
(guardias de custodia) y `schedule_slots` (el cuadrante). Tres vistas de lectura
con `security_invoker`. **La migración de corrección no es cosmética: sin ella el
módulo era inoperable.**

#### ⚠️ Lo que hay que saber antes de tocar los triggers

Los dos envoltorios anti-colisión **deben ser `security definer`**. Estuvieron
como `security invoker` en `202609180001`, y como `exigir_agenda_libre()` está
**revocada a propósito** para todos, el llamante no tenía `EXECUTE` y **toda alta
de guardia o de clase fallaba**:

```
ERROR: 42501: permission denied for function exigir_agenda_libre
CONTEXT: PL/pgSQL function teacher_duties_exigir_agenda() line 9 at PERFORM
```

**Y no lo vio una batería de 156 aserciones en verde**, porque las pruebas del
trigger escribían como el **dueño** de las tablas, y el dueño se salta la
comprobación de privilegios de función. **Si escribes una prueba de trigger,
pregúntate como qué rol está escribiendo.** Tres redes lo cubren ahora: la
sección 14.8 de `supabase/tests` escribe como `authenticated` con claims de
admin, `verificar-esquema.mjs` comprueba `prosecdef` contra la nube, y el
fail-first quedó demostrado. Ver `REPORTE_ARIA.md` **R-20** y
`docs/CONTRATO_API_MODULO3.md` **§10**.

#### La colisión: por qué no hay un `unique`

La regla cruza **dos tablas** (`teacher_duties` y `schedule_slots`), así que
ningún `unique` puede expresarla. Y en `schedule_slots` el lapso **no es una
columna** —se deriva de la sección—, de modo que
`unique (teacher_id, day_of_week, block)` **prohibiría** que el mismo docente
dictara el mismo bloque en dos lapsos distintos, que es justo planificar el
siguiente. La regla vive en una función compartida + dos triggers finos, y la
carrera entre dos administradores se cierra con `pg_advisory_xact_lock` por
`(lapso, día, bloque)`.

#### El backend (PASO 4, cerrado)

**Las 14 rutas existen** y están documentadas en `openapi.json`. Trece bajo
`/api/v1/admin` (`/aulas`, `/periodos`, `/guardias`, `/cuadrante`, con el
`preHandler` `exigirAdmin()`) más `GET /api/v1/mi-horario`, que exige sesión y
sirve a docente y estudiante desde la misma consulta. Un `admin` que llame a
`/mi-horario` recibe **403 `PERFIL_SIN_ROL`**: no es un fallo —su rol no tiene
horario— y devolverle una lista vacía le haría creer que no tiene clases.

Seis piezas, en el mismo reparto hexagonal que M2:

| Archivo | Qué contiene |
|---|---|
| `dominio/reglas-cuadrante.ts` | `turnoDeBloque`, `diaLegible`, `esChoqueDeAgenda`, `esFechaISO`, `rangoDeFechasValido` |
| `dominio/tipos.ts` | `Aula`, `Periodo`, `Guardia`, `ClaseCuadrante`, `DocenteResumen`, `RejillaCuadrante`, `MiHorario` |
| `dominio/puertos.ts` | `PuertaCuadrante`, 13 operaciones |
| `infra/repos-supabase.ts` | `CuadranteSupabase` |
| `http/esquemas.ts` | Los esquemas Zod de M3 |
| `http/rutas/cuadrante.ts` + `http/openapi.ts` | Las rutas y su documentación |

**Tres decisiones que conviene conocer antes de leer el código:**

1. **El puerto no tiene ninguna operación de «¿está libre?».** Preguntar antes de
   escribir sería una carrera y, peor, una segunda copia de la regla que se
   desviaría de la del trigger. La API escribe y **traduce** el `23514` a 409
   `CHOQUE_DE_AGENDA`, **reutilizando el mensaje del trigger verbatim**: el
   trigger ya nombra el día y el bloque, y reconstruir esa frase en TypeScript
   sería una segunda copia que se desincroniza sola.
2. **`turno` se lee de la base, no se recalcula.** Es una columna generada;
   `turnoDeBloque()` sólo actúa como respaldo. Así, mover la frontera de turnos
   (R-16) no puede hacer que el backend y la base digan cosas distintas.
3. **`GET /cuadrante` proyecta `docentes` de `profiles` y no usa
   `nombre_para_mostrar()`.** La función sigue siendo necesaria para el horario
   del **estudiante** (la RLS `profiles_read_own` le impediría resolver el
   nombre), pero un **administrador sí puede leer todos los perfiles**
   (`profiles_admin_all`), así que la ruta de administración proyecta sólo `id`,
   `nombres`, `apellidos`. Son dos problemas distintos y por eso conviven las dos
   soluciones.

**`crearClase`/`actualizarClase` escriben contra la tabla y releen de la vista.**
`v_cuadrante_clases` une cuatro tablas, así que no es auto-actualizable: el
`insert` va a `schedule_slots` y la respuesta se vuelve a leer de la vista, para
que lo que devuelve la API sea lo mismo que verá la rejilla.

**El doble en memoria del arnés reproduce el chequeo cruzado con los dos
mensajes verbatim de la migración**, así que `esChoqueDeAgenda` se ejercita
contra el texto real y no contra uno inventado. Las pruebas cubren los cuatro
cruces: docente-clase, docente-guardia, espacio-clase y espacio-guardia.

**101 pruebas nuevas:** `test/reglas-cuadrante.test.ts` (20),
`test/cuadrante.test.ts` (60) y los casos de M3 en `test/esquemas.test.ts`.

#### Deuda D6 cerrada del todo

`test/openapi.test.ts` ya **no coteja contra una lista escrita a mano**. Ahora
compara el documento contra el árbol **real** de Fastify en las dos direcciones,
leído con `printRoutes({ commonPrefix: false })` **después de
`await app.ready()`** — antes de eso las rutas montadas dentro de un
`app.register(...)` no aparecen y la comparación daría un **verde hueco** sobre
dos listas incompletas. Con la lista a mano, añadir una ruta y olvidar
documentarla pasaba inadvertido; ahora falla.

#### Lo que falta de M3

**El frontend**: pantallas de aulas, lapsos, guardias y la rejilla del cuadrante.
El esquema y las rutas no van a moverse, así que se puede construir contra
`docs/CONTRATO_API_MODULO3.md` sin esperar a nada.

El contrato incluye un código de error nuevo, **`CHOQUE_DE_AGENDA` (409)**,
separado de `RESTRICCION_VIOLADA` (400) por el texto del mensaje del trigger, con
el mismo criterio y el mismo motivo que `PENSUM_EN_USO` en M2.

#### Datos que están vacíos **a propósito** (no los «arregles» sembrando)

| Tabla | Filas | Por qué |
|---|---|---|
| `classrooms` | **0** | El inventario de espacios del CFS es un dato institucional. Sembrar «Taller de Soldadura Cabina A» habría sido **inventárselo** (R-18) |
| `teacher_duties` | **0** | Depende del inventario y del cuadrante real |
| `schedule_slots` | **0** | Ídem |
| `academic_periods` | **1** | Sólo `2026-1`, **leído de `system_settings`**, no escrito a mano |

Consecuencia que la UI tendrá que explicar: **mientras `classrooms` esté vacía el
cuadrante no se puede usar** —una clase sin aula no existe—, así que un
desplegable vacío sin mensaje hará pensar que la pantalla está rota.

Y las fechas del lapso (`start_date` / `end_date`) son **nulas**: el centro no las
ha cargado y no se inventan (R-17).

---

## 3. Mapa de Documentos Vivos

| Documento | Qué es | Cuándo leerlo |
|---|---|---|
| **`ESTADO_DEL_SISTEMA.md`** | **Fuente de verdad.** Estado por fase, esquema, deudas D1–D13, recetas de arranque. **Ojo: se desincroniza solo** — verifica las cifras | **Primero, siempre** |
| `REPORTE_ARIA.md` | Contradicciones del enunciado y fallos propios, resueltos uno por uno (R-01…R-20) | Si algo del diseño te chirría |
| **`docs/CONTRATO_API_MODULO3.md`** | **El contrato de M3**: 14 rutas, tipos, errores, y por qué no hay un `unique` de colisión. **§10 explica el fallo `42501`** | **Antes de tocar nada de M3** |
| `docs/CONTRATO_API_MODULO2.md` | Contrato de M2 (currículo y pensum), ya implementado | Al tocar M2 |
| `ROADMAP.md` | ⚠️ **Desactualizado** — no lo tomes como referencia de estado | Sólo contexto histórico |
| `docs/PLAN_MAESTRO_STACK_DEFINITIVO.md` | El stack vigente, con sus ADR | Si dudas del stack |
| `README.md` | Arranque rápido (incluye `--web-port=8080`) | Al levantar el entorno |
| `backend/.env.example` | Todas las variables, comentadas una por una | Antes de tocar configuración |
| `backend/openapi.json` | Contrato de la API, generado | Al consumir el backend |
| `HANDOVER.md` | Este archivo | Al empezar la sesión |

### Memoria del proyecto — `.workbuddy-ai/memory/`

| Archivo | Contenido |
|---|---|
| `MEMORY.md` | Índice curado: identidad, stack, reglas de oro, estado |
| `temas/convenciones.md` | **Léelo antes de escribir código.** Convenciones, flujo de trabajo de Lorenzo, reglas de interfaz y contrato de layout de paneles |
| `temas/api-backend.md` | Backend, PostgREST, por qué los dobles en memoria engañan |
| `temas/modulo2.md` | M2: las dos reglas, las dos RPC y el cliente Flutter |
| `temas/modulo3.md` | **M3**: las 4 tablas, la colisión que cruza dos tablas, la RLS comprobada y el reparto del backend |
| `temas/infraestructura.md` | Supabase, R2, despliegue dual |
| `temas/interfaz.md` | Flutter, tema, componentes |
| `2026-09-11.md` … `15.md` | Logs diarios. El del 13 cierra el Módulo 1; el del **15** cierra el M3 (esquema, el fallo `42501`, el contrato y el backend) |

---

## 4. Prompt de Bootstrapping para el Nuevo Agente

> Copia y pega el bloque siguiente tal cual en la primera interacción de la nueva
> sesión.

```text
Eres el nuevo agente a cargo del proyecto INCES LMS. Toma el control.

CONTEXTO EJECUTIVO
------------------
Es un LMS a la medida para el CFS Nacional de Soldadura "Rafael Urdaneta"
(La Isabelica), desarrollado como Trabajo Especial de Grado (IUTEPI, Análisis
de Sistemas, 4º semestre, SA26-2). Tutor: Prof. Maglis Camacho.
Equipo: José Tarazón, Lorenzo Roca, Sleither Vásquez, Adrián Cedeño.
Objetivo declarado: superar a Google Classroom y ser 100% a la medida del INCES.

STACK (FIJADO, NO REABRIR)
--------------------------
- Flutter 3.47 (web) + Dart 3.13.
- Supabase: PostgreSQL 17.6 (región sa-east-1) + Auth.
- Backend Node/TypeScript con Fastify 5, STATELESS, arquitectura hexagonal
  (dominio/puertos + infra/implementaciones).
- Cloudflare R2 con URLs prefirmadas para almacenamiento pesado.
- Despliegue dual (local + nube) y Administrador Maestro con toggle de módulos.
- DESCARTADOS: MongoDB (ADR-006) y el M9 de Certificados/QR. No los propongas.
- Los roles son 3: admin, docente, estudiante. NO existe MASTER_ADMIN: el
  Administrador Maestro es una capacidad del rol admin, no un rol aparte.

DOCUMENTACIÓN VIVA (léela antes de escribir código)
---------------------------------------------------
1. HANDOVER.md                  -> estado y pendientes, en la raíz. EMPIEZA AQUÍ.
2. ESTADO_DEL_SISTEMA.md        -> fuente de verdad. OJO: se desincroniza solo,
                                   verifica las cifras contra el código.
3. .workbuddy-ai/memory/MEMORY.md y temas/convenciones.md -> reglas y convenciones.
   convenciones.md es OBLIGATORIO antes de tocar cualquier archivo de código.
4. docs/CONTRATO_API_MODULO3.md -> el contrato de lo que toca ahora (M3), y en
                                   su §10 el fallo que casi se cuela a produccion.
5. ROADMAP.md está DESACTUALIZADO: no lo uses como referencia de estado.
6. backend/.env.example tiene todas las variables explicadas.

ESTADO ACTUAL (verificado el 2026-09-15, no estimado)
-----------------------------------------------------
- Backend: 333/333 tests, typecheck y eslint limpios.
- Flutter: 197/197 tests, `flutter analyze` sin incidencias.
- SQL: 164/164 aserciones en pglite, sobre las 10 migraciones.
- Esquema en la nube: 81/81 comprobaciones (verificar-esquema.mjs).
  Humo de invitacion: 17/17. Humo de curriculo: 14/14.
- HEAD en `main` = `origin/main` (comprueba con
  `git rev-list --left-right --count origin/main...HEAD` -> `0  0`). Working tree
  limpio. No se escribe el SHA: nace obsoleto, ver arriba.
- Modulo 1 completo y verificado de extremo a extremo contra la base real.
- Modulo 2 completo: base, backend y UI.
- Modulo 3: ESQUEMA APLICADO Y CORREGIDO Y BACKEND COMPLETO (las 14 rutas del
  contrato existen y estan documentadas en openapi.json: 29 rutas, 62 esquemas).
  Falta solo el frontend. Su migracion de correccion no es cosmetica: sin ella
  toda alta de guardia o clase fallaba con 42501 (ver HANDOVER §2.6).
- Modulos 4-8: solo diseno.
- Deudas abiertas: D7 (verificacion de tokens en cache), D9 (URL prefirmada de
  PUT sin limite de tamano; latente, M5 apagado).
- Resueltas: D8, D10, D11, D12, D13.
- Decisiones que NO son tuyas: R-06 (nomenclatura del lapso, 2026-1 vs SA26-2),
  R-16 (frontera de turnos), R-17 (fechas del lapso), R-18 (inventario de aulas).
  Las cuatro se cambian sin tocar codigo: son datos, o una funcion de una linea.

LA TRAMPA QUE MAS CARO COSTO
----------------------------
Un trigger `security invoker` que llama a una funcion revocada deja el modulo
inoperable, y la suite NO lo ve si las pruebas escriben como el dueño de las
tablas (el dueño se salta la comprobacion de EXECUTE). Antes de escribir una
prueba de trigger: preguntate como que rol esta escribiendo. Detalle en
REPORTE_ARIA.md R-20.

TAREA INMEDIATA
---------------
Antes de escribir una línea de código, haz esto y repórtalo:
1. `git status --short` y `git log --oneline -5` para que confirmemos el punto
   de partida.
2. `cd backend && npm test`, `flutter test` y `cd supabase/tests && npm test`
   para confirmar que heredas verde (333 / 197 / 164).
3. Lee HANDOVER.md §2 y dime qué atacamos primero:
   (a) el frontend de M3 (aulas, lapsos, guardias y la rejilla del cuadrante:
       es lo único que falta del módulo, y el backend ya está),
   (b) verificar el dominio en Resend (desbloquea el correo a terceros), o
   (c) abrir la pantalla de activación en un navegador real (mitad-UI de M1).
   Recomiendo (a): cierra M3 entero.

REGLAS DE TRABAJO
-----------------
- Comenta y nombra identificadores en ESPAÑOL. Mensajes al usuario en español.
- Nunca escribas `catch (e) { return null; }`. Los errores se propagan o se
  traducen, nunca se silencian.
- Verificar un canal no es que "configure bien": hay que ENVIAR algo de verdad.
- Si una prueba falla, lee el error antes de tocarla: distingue una prueba
  desactualizada de un bug real.
- Sé diagnóstico, opinado y basado en evidencia. Si algo del handover no cuadra
  con el código, gana el código y dímelo.
```

---

## 5. Anexo — Roles: la corrección documental

Antes de editar el `.docx` verifiqué la fuente. `supabase/migrations/202609100001_init.sql`:

```sql
rol text not null default 'estudiante'
  check (rol in ('admin', 'docente', 'estudiante')),
```

Y en `202609120002_phase3_admin_core.sql`:

```sql
check (roles_permitidos <@ array['admin', 'docente', 'estudiante']::text[])
```

Tres roles. Sin `MASTER_ADMIN`. El documento conceptual
(`INCES LMS PROJECT.docx`, fuera del repo) decía cuatro. Correcciones aplicadas:

| Antes | Después |
|---|---|
| `MASTER_ADMIN: Acceso total (base de datos, logs, ...)` | `admin: Acceso total a la plataforma (...). Es el único rol habilitado como Administrador Maestro (interruptor global de módulos).` |
| `ADMIN: Gestión operativa (...)` | *(viñeta eliminada — absorbida por `admin`)* |
| `DOCENTE:` | `docente:` |
| `ESTUDIANTE:` | `estudiante:` |
| `Matriz de Roles Estrictos:` | `Matriz de Roles Estrictos (3 roles activos en PostgreSQL):` |
| `privilegios administrativos (MASTER_ADMIN, ADMIN)` | `privilegios administrativos (admin)` |
| `usuario con rol ESTUDIANTE` | `usuario con rol estudiante` |

Quedan **cero** menciones de `MASTER_ADMIN` o `ADMIN` en mayúsculas. El concepto
de "Master Admin" que sobrevive en otras secciones del documento (Módulo 4, Módulo
5) es narrativo y se refiere a la **capacidad** de Administrador Maestro, no a un
rol de base de datos. No lo edité para no reescribir medio documento; si quieres,
ese es un buen primer encargo para el nuevo agente.

---

## 6. Anexo — Cómo editar el `.docx` (por si toca de nuevo)

La herramienta local se invoca así:

```bash
cd "<ruta>/skills/tencent-local-office-edit"
python edsdk.py call <herramienta> --json '{"file_id":"...","...":"..."}'
```

Trampas que ya mordieron una vez:

1. `get_pool_status` devuelve la **RUTA** como `file_id`. Ésa **no** sirve para
   los `doc_*`. Hay que llamar a `open_file` con `open_with_existing=true`, que
   devuelve el UUID real.
2. `doc_get_outline` devuelve `{"items":[]}` en este documento: **no tiene
   estilos de encabezado**. Para orientarse, mejor volcar el texto con `zipfile` +
   regex sobre `word/document.xml`.
3. Las coordenadas se obtienen con `doc_find` (`begin`/`end`) y **se editan de
   abajo hacia arriba**, porque cada escritura desplaza todo lo posterior.
4. `doc_replace_text` usa `ranges: [{begin, end}]`. Para borrar una viñeta,
   `doc_delete_paragraph` con el `idx` de cualquier punto de ella.

---

*Fin del traspaso. El estado es verde y el camino está marcado.*
