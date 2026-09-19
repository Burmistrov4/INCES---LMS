# HANDOVER — INCES LMS

> **⚠️ El titular que sigue está desactualizado, y se conserva por trazabilidad.**
> El estado vigente es **M5 cerrado en local** —Capa 7, bandera encendida y
> guardia `exigirModulo()`— **más el barrido expuesto como ruta de
> administración** (2026-09-19); M6–M8 son sólo diseño. Las cifras de las suites y
> el detalle de las deudas abiertas están en las entradas fechadas de más abajo y
> en `ESTADO_DEL_SISTEMA.md` §1, que es la fuente de verdad. **Ante cualquier
> discrepancia, gana el código.**

> **Módulo 4 (Inscripciones y Cupos) — Fases 1 y 2 CERRADAS.**
> **Fase 1 (esquema):** `202609190001_mod4_inscripciones.sql` aplicada, más
> `202609200001_mod4_reglas_ajuste.sql` que ajusta las reglas institucionales y
> `202609200002_mod4_habilitar_modulo.sql` que **enciende el módulo**.
> **Fase 2 (backend): CONSTRUIDA** — 14 rutas (3 de secciones + 5 de estudiante +
> 6 de administración), `reglas-inscripciones.ts`, `PuertaSecciones` y
> `PuertaInscripciones`, `SeccionesSupabase` e `InscripcionesSupabase`, esquemas
> Zod y OpenAPI. Backend **428/428**, SQL **223/223**, esquema **92/92**, libro
> mayor **15/15**, typecheck/lint/build limpios. **R2 FUNCIONA** (ciclo completo
> verificado). **Falta la Fase 3 (frontend) y el humo de la Fase 4.**
> Ver **§2.7**, **§2.8** y `docs/BRIEFING_BACKEND_MODULO4.md`.
>
> Traspaso de mando generado el **2026-09-13**, revisado el **2026-09-14**,
> puesto al día el **2026-09-15** (Módulo 2 completo) y **actualizado el
> 2026-09-15 con el Módulo 3 completo**: esquema aplicado, verificado y
> **corregido** (un fallo que dejaba el módulo inoperable, ver §2.6) **y backend
> terminado** — las 14 rutas del contrato ya existen, están registradas en Fastify
> y documentadas en `openapi.json`. Todo lo que aparece aquí fue verificado contra
> el repositorio en el momento de redactarlo. Si algo de este documento
> contradice al código, **gana el código**: avísame y lo corrijo.
>
> **Cierre de M3 (frontend) + R-06 + R-21 (2026-09-15, sesión autónoma de Aria):**
> el frontend de M3 quedó construido (`CuadranteGrid`, `MiHorarioPanel`, aulas,
> lapsos y guardias, con su cableado en los dashboards admin/docente); R-21 se
> cerró capturando `nombres`/`apellidos` en la invitación de docente y pasándolos a
> `user_metadata`; y R-06 se resolvió fijando `periodo_activo = "SA26-2"` y
> habilitando `m2_curriculo`/`m3_cuadrante` (migración `202609180003`). Backend
> 341/341, Flutter 307/307, SQL 165/165 (12 migraciones). La batería SQL
(`supabase/tests/validate.mjs`) se corrigió para reflejar el periodo `SA26-2` y los
módulos M2/M3 habilitados: 165 aserciones en verde contra PostgreSQL real (pglite).

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
git ls-remote origin refs/heads/main   # el SHA real en GitHub
git rev-parse HEAD                     # debe coincidir
git log --oneline -8                   # los últimos commits
```

> **Corrección (2026-09-18).** El comando que este documento recomendaba antes,
> `git rev-list --left-right --count origin/main...HEAD`, **falla en este entorno**
> con `ambiguous argument 'origin/main'`: **el ref de seguimiento remoto no
> persiste en disco**. `git fetch origin` reporta `[new branch] main ->
> origin/main`, pero `git show-ref` sigue mostrando sólo `refs/heads/main` y
> `.git/refs/remotes/` queda vacío. Es una rareza del entorno, no del repositorio.
> **La prueba que sí vale es `git ls-remote`**: consulta el SHA directamente al
> remoto y no depende de ningún ref local. Verificado el 2026-09-18 con
> `3691b2b`.

Los commits más recientes se consultan con `git log --oneline -8`. A partir del
2026-09-15 se sumaron, entre otros: el frontend de M3 (rejilla, Mi Horario,
aulas/lapsos/guardias), el cierre de **R-21** (nombres en la invitación de docente)
y la resolución de **R-06** (lapso `SA26-2` + módulos `m2`/`m3` habilitados); y el
2026-09-18, la **Fase 1 del Módulo 4** (motor de cupos, frontera de escritura
cerrada y el cierre de **R-23**). Este documento no repite los SHA a propósito: el
commit que lo contiene lo movería.

> **Nota de proceso, ya resuelta (2026-09-18).** El push estuvo bloqueado varias
> sesiones con `fatal: could not read Username for 'https://github.com': terminal
> prompts disabled`: el *credential helper* no devolvía credencial y no había
> `GITHUB_TOKEN` ni `~/.git-credentials`. **El diagnóstico era correcto pero la
> conclusión no:** no era un problema del repositorio ni del remoto, era del
> entorno de ejecución, y se resolvió fuera de él. El 2026-09-18 el push
> **funcionó sin tocar nada** (`200edf4..3691b2b main -> main`). Antes de declarar
> un push «imposible», comprueba si el entorno cambió: `GIT_TERMINAL_PROMPT=0 git
> push` falla rápido en vez de colgarse cinco minutos esperando una consola que no
> existe. **La lección generalizable: un fallo de credenciales puede ser del
> entorno y desaparecer solo — vuelve a intentarlo antes de diagnosticar el repo.**

Nota de higiene: `.env`, `.env.json` y la carpeta de contexto están en
`.gitignore`, así que **ninguna credencial entró al commit**. `backend/.env.example`
sí se versiona a propósito (es la plantilla documentada, sin valores reales).
`.workbuddy-ai/` también está ignorado: la memoria del proyecto no viaja al repo.

### ✅ Migraciones de M2, M3 y M4 aplicadas en la nube (verificado, no supuesto)

Las **13** migraciones están aplicadas. El libro mayor lo confirma:

```
$ SUPABASE_ACCESS_TOKEN=sbp_… node supabase/apply-migrations.mjs --check
  Proyecto : twdppwnxlnmxkiejbrei   (ACTIVE_HEALTHY, sa-east-1)
  Migraciones: 13

  aplicada   202609100001_init.sql
  aplicada   202609120001_phase1_onboarding.sql
  aplicada   202609120002_phase3_admin_core.sql
  aplicada   202609120003_proteger_ultimo_admin.sql
  aplicada   202609130001_invitaciones_docente.sql
  aplicada   202609130002_invitaciones_nombres.sql
  aplicada   202609150001_mod2_curriculo.sql
  aplicada   202609160001_resolucion_d12_d13.sql
  aplicada   202609170001_mod2_rpc_curriculo.sql
  aplicada   202609180001_mod3_cuadrante_aulas.sql
  aplicada   202609180002_mod3_trigger_agenda_definer.sql
  aplicada   202609180003_r06_periodo_sa26_2_y_modulos.sql
  aplicada   202609190001_mod4_inscripciones.sql
  aplicada   202609200001_mod4_reglas_ajuste.sql
  aplicada   202609200002_mod4_habilitar_modulo.sql

  0 pendiente(s), 0 con deriva.
```

> **Ojo con `202609130002`.** Estaba en el repo desde el 2026-09-15 —R-21 se
> cerró en código— pero **nunca había llegado a la nube**: se aplicó el
> 2026-09-18, junto con M4. *Cerrado en el repo* no es *aplicado en producción*.
> Antes de dar por bueno un arreglo, corre `--check`.

`node supabase/verificar-esquema.mjs` → **92/92 OK, 0 fallos** (comprobado el
2026-09-18 tras `202609200001`; venía de 89/89). Incluye las aserciones de M2 (`cursos` es vista con
`security_invoker`, `programs.type`/`is_active`, `sections.program_id`, los dos
constraint triggers, las dos funciones del asistente), **las de M3**: las 4
tablas nuevas con sus columnas, la FK `sections.period_code → academic_periods`,
el lapso vigente registrado, las 3 vistas con `security_invoker`, el `turno` como
columna generada, y —la más importante— **`prosecdef` de los dos envoltorios
anti-colisión debe ser `DEFINER`** (ver §2.6); y **las de M4** (bloque 8 nuevo):
las RPC como `DEFINER`, `authenticated` **sin** INSERT/UPDATE sobre `enrollments`,
`sections.max_capacity` anulable, el parámetro de bids sembrado, el trigger
anti-duplicado, la vista con `security_invoker`, **la ayuda `existe_oferta_vigente`
como `DEFINER` (con `authenticated` sí y `anon` no)** y **la columna
`oferta_vigente` de la vista**.

---

## 1. Resumen del Estado Actual del Código

### Suite de pruebas

| Suite | Resultado | Comando |
|---|---|---|
| Backend (vitest) | **428 / 428** en verde | `cd backend && npm test` |
| Flutter | **307 / 307** en verde — ⚠️ **última medición válida (2026-09-15)**; hoy **no re-ejecutable** en este entorno (ver la corrección más abajo) | `flutter test` |
| SQL (pglite, PostgreSQL real) | **223 / 223** en verde · 15 migraciones | `cd supabase/tests && npm test` |

**Humos contra la nube real** (necesitan `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`,
no el `sbp_`): currículo **15/15** (medido el 2026-09-18 — resuelve la discrepancia
14 vs 15: **gana 15**), invitaciones 17/17, cuadrante 53/53 (no re-ejecutados).
Se corren con `node --env-file-if-exists=backend/.env supabase/humo-*.mjs --confirmar`.

> **Corre `flutter test` ENTERO antes de commitear**, no sólo el archivo que
> tocaste. En el cierre de M2, correr los archivos sueltos daba verde y la suite
> completa destapó **6 fallos** (rótulos en mayúsculas que los tests buscaban en
> minúsculas, y un `hintText` que `find.text` también encuentra).

### Compilación y linters

| Verificación | Estado |
|---|---|
| `npm run typecheck` (`tsc --noEmit`) | ✅ limpio |
| `npm run lint` (eslint) | ✅ limpio |
| `flutter analyze` | ✅ **No issues found!** (re-verificado el 2026-09-18, 68 s) |

> **⚠️ Corrección (2026-09-18): `flutter test` NO funciona en este entorno.**
> Este documento afirmaba lo contrario y **era falso**. Las 21 pruebas fallan **al
> cargar** con `Unable to connect to flutter_tester process: WebSocketException:
> Invalid WebSocket upgrade request` — `flutter_tester` no abre su WebSocket de
> loopback. Comprobado **también fuera del sandbox**: mismo resultado, así que no
> es el aislamiento. Hay además un requisito previo: `flutter test` **exige**
> `PROGRAMFILES(X86)` en el entorno (Git Bash no la define; sin ella el error es
> `%PROGRAMFILES(X86)% environment variable not found`). Inyectándola, el WebSocket
> sigue fallando.
>
> **Por eso el 307/307 es la última medición válida (2026-09-15), no una medición
> de hoy.** No cites una cifra de Flutter como si la hubieras re-ejecutado. Lo que
> sí sigue bloqueado es `flutter devices` / enumerar Chrome (lo impide `reg.exe`):
> no lances la app en Chrome desde aquí.

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

**h) Módulo 4 — Fase 1 (esquema) desplegada y verificada.** El motor de cupos
vive **entero** en la base de datos: 6 RPC `security definer`, cola FIFO,
ventana de bids opcional, cerrojo por sección y frontera de escritura cerrada.
No hay backend ni frontend todavía. Ver §2.7.

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

> **Hay DOS listas de CORS, y no se hablan.** `CORS_ORIGINS` (backend/.env) decide
> si el navegador puede llamar a **la API**. La política del bucket de R2 decide si
> puede hacer `PUT`/`GET` contra **el bucket**. Son independientes: añadir un
> origen a una no lo añade a la otra, y el síntoma es idéntico en ambas —«bloqueado
> por CORS»—, así que se confunden con facilidad. Al desplegar, actualiza **las
> dos**. La del bucket está versionada en `docs/r2-cors.json` (D16, resuelta el
> 2026-09-19). Y recuerda que **ninguna prueba del backend puede detectar la del
> bucket**: Node no aplica CORS.

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
| pglite (PostgreSQL real, 12 migraciones) | **165 / 165** |
| Esquema en la nube (`verificar-esquema.mjs`) | **81 / 81**, 0 fallos |
| Backend (vitest) | **341 / 341** |
| Flutter | **307 / 307** |
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

#### Humo real del cuadrante: `supabase/humo-cuadrante.mjs` — **53/53**, sin residuo

```bash
node supabase/humo-cuadrante.mjs              # simulación (no escribe)
node supabase/humo-cuadrante.mjs --confirmar  # ejecuta (escribe y purga)
```

Escribe con el **JWT de un administrador real**, no con la service role key,
porque eso es lo que hace el backend. Cubre lo que un doble no puede: el
**mensaje real del trigger** con el día y el bloque ya interpolados, la
**colisión cruzada** clase-contra-guardia, que **el mismo hueco en otro lapso sí
se permite**, la sintaxis de PostgREST (incluido que **doblar los paréntesis del
`or(...)` sí lo rompe**), que **`PGRST116` existe de verdad** al parchear un id
ausente, y la **RLS por rol** a través de las vistas `security_invoker`.

Además, `test/reglas-cuadrante.test.ts` **lee la migración como texto** y
comprueba contra ella `turnoDeBloque`, `diaLegible` y `esChoqueDeAgenda`. Antes
esas pruebas copiaban el mensaje a mano —es decir, probaban que el detector
reconoce **la copia**, no el original—. Ahora, si alguien reescribe un `raise
exception` o mueve la frontera de turnos, falla. (Esa prueba ya destapó que hay
**cuatro** `raise exception`, no tres: faltaba el de «la sección no existe».)

#### ✅ R-21 — el nombre del docente llega vacío al cuadrante (RESUELTA: el canal de invitación captura nombres/apellidos)

El humo encontró un defecto real, y **no es de M3**:

`v_cuadrante_clases.teacher_name` sale **NULL** para cualquier docente de verdad,
así que la columna del docente en el cuadrante —y el nombre del profesor en el
horario del estudiante— quedan **en blanco**.

La cadena, verificada contra la base y contra el código:

1. `profiles.nombres` y `apellidos` son `text not null`, **sin valor por defecto**.
2. `handle_new_user()` inserta `coalesce(v_nombres, '')` desde
   `raw_user_meta_data`. **Sin metadatos guarda `''`.**
3. El único canal que crea docentes es la invitación, y
   `crearUsuarioDocente(email, password)` llama a `auth.admin.createUser`
   **sin `user_metadata`**. `POST /auth/activar` sólo acepta `token` y `password`.
   **No existe ninguna ruta que fije los nombres.**
4. `nombre_para_mostrar()` hace `nullif(btrim(nombres || ' ' || apellidos), '')`:
   con `'' || ' ' || ''` queda `' '` → `btrim` → `''` → **NULL**.

**La función está bien escrita** (ese `nullif(btrim(…))` es justo lo que evita
pintar un espacio en blanco). **El hueco está aguas arriba, en el Módulo 1:** M3
construyó la forma de mostrar el nombre (R-14) sobre un dato que el alta nunca
llena.

| Opción | Efecto | Quién decide |
|---|---|---|
| **A.** Que la invitación o la activación pidan nombres y apellidos | Arregla la causa. Toca la pantalla de invitación de M1 y su esquema Zod | **Equipo** (alcance de M1) |
| **B.** Que la función caiga al correo | Filtraría el correo del docente a cualquier estudiante — lo que R-14 evitó | Descartada |
| **C.** Que la interfaz diga «Docente sin nombre» | No arregla nada; sólo deja de ser un hueco mudo | Parche |

**Recomendación: A.** Detalle completo en `REPORTE_ARIA.md` **R-21**. El humo
comprueba las dos mitades (con nombre y sin nombre), así que el día que se
implemente A, la segunda aserción falla y obliga a actualizarla: el defecto no
puede volver a pasar inadvertido.

#### ✅ R-22 — el panel de M2 era inalcanzable desde el menú (resuelta)

Apareció al leer `admin_dashboard.dart` para planificar el frontend de M3.

`Programas Académicos` tenía `disponible: false`, y `AndamiajeApp` **no envuelve
en `InkWell`** un ítem no disponible. Así que su `case` en el `switch` del cPanel
era **código muerto**: el panel de M2, su asistente y su prueba existían, y
**ningún administrador podía abrirlos**. No era una decisión: la bandera la puso
`004923a` (M1), cuando M2 no existía, y `ec361ac` (UI de M2) añadió el panel sin
voltearla.

**Por qué no lo vio ninguna prueba:** ninguna montaba el dashboard. Los paneles se
prueban montados **donde viven** (dentro de `ContenidoSeccion`) —lo correcto para
el layout— y eso deja el **cableado del menú** sin cubrir. *Probar el panel donde
vive no prueba que se pueda llegar a él.*

**Arreglado:** la bandera fuera (una línea) + **`test/menu_alcanzable_test.dart`**
(6 casos). No es un espejo a mano: **lee el dashboard como texto** y exige que las
secciones disponibles y las ramas del `switch` coincidan **en las dos
direcciones** (con rama y sin bandera = inalcanzable; sin rama y con bandera =
abre en blanco), con suelo explícito para que un analizador roto no dé un verde
hueco. Se verificó que **tiene dientes**: con la bandera restaurada falla
nombrando la sección.

> **M3 hereda el riesgo.** `Cuadrante y Horarios` y `Mi horario` siguen siendo
> marcadores `disponible: false`: **hay que levantar la bandera al construirlos**,
> y el contrato del admin ya falla si se olvida. El dashboard del **docente** aún
> no está cubierto (su `_contenido()` no usa `switch`): extenderlo al construir
> `Mi horario`.

#### Deuda D6 cerrada del todo

`test/openapi.test.ts` ya **no coteja contra una lista escrita a mano**. Ahora
compara el documento contra el árbol **real** de Fastify en las dos direcciones,
leído con `printRoutes({ commonPrefix: false })` **después de
`await app.ready()`** — antes de eso las rutas montadas dentro de un
`app.register(...)` no aparecen y la comparación daría un **verde hueco** sobre
dos listas incompletas. Con la lista a mano, añadir una ruta y olvidar
documentarla pasaba inadvertido; ahora falla.

#### Lo que falta de M3

**El frontend**: construido en el cierre de M3 (PASO 1 del roadmap autónomo de Aria): rejilla del cuadrante (`CuadranteGrid`), Mi Horario, aulas, lapsos y guardias. No queda nada de M3.
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
| `academic_periods` | **1** | Sólo `SA26-2`, **leído de `system_settings` (fijado por la migración 202609180003)**, no escrito a mano |
| `enrollments` | **0** | El motor de M4 está desplegado pero **no tiene backend ni frontend**: nadie puede inscribirse todavía. Sembrar inscripciones sería inventarse matrícula |

Consecuencia que la UI tendrá que explicar: **mientras `classrooms` esté vacía el
cuadrante no se puede usar** —una clase sin aula no existe—, así que un
desplegable vacío sin mensaje hará pensar que la pantalla está rota.

Y las fechas del lapso (`start_date` / `end_date`) son **nulas**: el centro no las
ha cargado y no se inventan (R-17).

### 2.7 Módulo 4 — Inscripciones y Cupos: **esquema ✅ · backend ⏳ · frontend ⏳**

**Estado: Fase 1 (esquema) cerrada el 2026-09-18.** Migración
`202609190001_mod4_inscripciones.sql` (748 líneas) aplicada en la nube. `sha256`
= `e4688586f422f456cd297f5f417010b32d2d342b4a04823195ecd18878c05ce2`.

**El motor vive entero en la base de datos.** El cliente no escribe: sólo llama
RPC. Esto es lo que hay:

| Pieza | Qué hace |
|---|---|
| `sections.max_capacity` **anulable** | Era `NOT NULL DEFAULT 0`. Sin esto, la regla «si es nulo usa el global» **nunca disparaba** |
| `habilitar_sistema_bids` | Parámetro nuevo (boolean, privado). Arranca **apagado** |
| `cupo_efectivo(sección)` | `coalesce(max_capacity, cupo_maximo_por_seccion, 0)` |
| `cupos_ocupados(sección)` | Cuenta **sólo `ENROLLED`** (regla institucional: una solicitud `PENDING_BID` **no** reserva cupo) |
| `existe_oferta_vigente(sección)` | **El guardián que hace segura la regla anterior.** Devuelve `true` si hay un `PENDING_BID` **no vencido** (`bid_expires_at` nulo o futuro). Sin él, la regla «sólo cuenta `ENROLLED`» abre una **doble venta** — ver más abajo |
| Trigger `enrollments_seccion_unica_por_materia` | Un estudiante no puede tener dos secciones vivas de la misma materia en el lapso. Excluye `DROPPED` **y la propia fila** |
| 6 RPC `security definer` | `solicitar_inscripcion`, `aceptar_cupo`, `renunciar_cupo`, `promover_siguiente`, `expirar_ofertas_cupo` (idempotente, sin `pg_cron`), `reincorporar_inscripcion` |
| Cerrojo | `pg_advisory_xact_lock` **por sección**, no global |
| Vista `v_ocupacion_secciones` | `security_invoker` + funciones definer (una vista invoker que contara `enrollments` directo mostraría a cada alumno sólo su propia fila) |

**Frontera de seguridad — cerrada y probada contra producción.** Ver
`REPORTE_ARIA.md` **R-23**: `enrollments` nació con `enrollments_insert_own`, que
dejaba a **cualquier** autenticado auto-insertarse en `ENROLLED` y saltarse el
motor de cupos entero. Se revocó `INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER`
de **`anon` y `authenticated`**; queda sólo `SELECT` para `authenticated`. Probado
como rol real (`set role` + `request.jwt.claims`, en transacción con `rollback`):
`INSERT`/`UPDATE`/`DELETE` → **42501**; `SELECT` propio funciona; `anon` no lee ni
escribe. Y el módulo **sigue operable**: un no-admin real llega a la lógica por
`solicitar_inscripcion`.

**Las 4 decisiones de producto — RESUELTAS por Lorenzo el 2026-09-18** (migración
`202609200001_mod4_reglas_ajuste.sql`). Quedan aquí con el porqué, porque cada una
tiene una consecuencia que no es obvia:

1. `habilitar_sistema_bids` arranca **apagado**. → **Se mantiene apagado.** El
   ROADMAP llama a M4 «Motor de Bids», pero la bandera nace en `false` y se
   enciende desde administración cuando el CENATE lo pida.
2. `reincorporar_inscripcion` **exigía cupo libre**. → **Regla institucional: el
   Administrador PUEDE exceder la capacidad.** «Si el admin autoriza, el sistema
   obedece». Se **quitó** la comprobación de cupo del RPC (queda el chequeo de rol,
   el cerrojo y el trigger anti-acaparamiento). El exceso queda **deliberado y
   registrado**, no es un agujero: es una decisión de administración.
3. `cupos_ocupados` contaba `ENROLLED` **+ `PENDING_BID`**. → **Ahora cuenta sólo
   `ENROLLED`**: una solicitud pendiente **no** reserva cupo.
4. Con bids encendido, una solicitud con cupo libre **entra directo a `ENROLLED`**.
   → **Confirmado tal cual.**

> ### ⚠️ La regla 3, sola, causaba una doble venta
>
> Esto es lo más importante de esta migración. Si `PENDING_BID` deja de sumar al
> contador, el contador **dice que hay hueco mientras una oferta está en el aire**:
>
> ```
> cupo = 1 · A renuncia            → hueco libre (0/1)
> B es promovido (PENDING_BID)     → ocupados = 0  ← B no cuenta
> C entra directo (hay "hueco")    → ENROLLED      ← 1/1
> B acepta su oferta               → ENROLLED      ← 2/1
> ```
>
> **Dos personas en un asiento de uno.** Por eso `202609200001` añade
> `existe_oferta_vigente()` y la mete como puerta en **`solicitar_inscripcion`**
> (no entra directo si hay oferta viva) y en **`promover_siguiente_de_cola`** (no
> promueve si ya hay una oferta viva), y `aceptar_cupo` pasa a tomar el cerrojo
> por sección (ahora también mueve el contador). La vista expone
> `oferta_vigente` para que el frontend pueda mostrar «asiento comprometido».
> **Una oferta vencida no cuenta**: el asiento está genuinamente libre aunque el
> barrido (`expirar_ofertas_cupo`) no haya corrido todavía.
>
> El escenario está **probado**: `supabase/tests/validate.mjs` §17.5 reproduce la
> traza de arriba y verifica que C termina en `WAITLISTED`, no en `ENROLLED`.
>
> **Lección reutilizable:** cuando una regla de negocio cambia un **contador**,
> hay que preguntarse qué **invariante** sostenía ese contador. Aquí el contador
> hacía de cerrojo de facto. Quitarlo sin sustituirlo rompe la exclusión mutua.

**Resuelto también:** Lorenzo pidió añadir
`max_faltas_consecutivas_permitidas` a los parámetros, pero
**`max_faltas_consecutivas = 3` ya existía** (`202609120002:401`, categoría
`asistencia`). **Se usa la global existente**; no se creó el duplicado —sería un
segundo sitio con la misma verdad—. M4 lo consumirá desde ahí.

#### La Fase 2 del backend — CONSTRUIDA (2026-09-17)

**14 rutas nuevas**, en dos archivos y con los dos patrones de registro:

| Archivo | Rutas | Patrón |
|---|---|---|
| `src/http/rutas/secciones.ts` | `GET/POST /api/v1/admin/secciones`, `PATCH /api/v1/admin/secciones/:id` | **A** (bloque + `exigirAdmin`) |
| `src/http/rutas/inscripciones.ts` (estudiante) | `GET /api/v1/ofertas`, `GET /api/v1/mis-inscripciones`, `POST /api/v1/inscripciones`, `POST /api/v1/inscripciones/:id/aceptar`, `POST /api/v1/inscripciones/:id/renunciar` | **B** (ruta suelta + guardia por ruta) |
| `src/http/rutas/inscripciones.ts` (admin) | `GET /api/v1/admin/ocupacion`, `GET /api/v1/admin/secciones/:id/cola`, `GET /api/v1/admin/secciones/:id/inscripciones`, `POST /api/v1/admin/secciones/:id/promover`, `POST /api/v1/admin/inscripciones/reincorporar`, `POST /api/v1/admin/inscripciones/expirar` | **A** |

> **En `/api/v1/inscripciones/:id/...`, `:id` es el identificador de la SECCIÓN**,
> no el de la inscripción. Una inscripción no tiene identidad propia en la API: se
> identifica por el par (estudiante, sección), y el estudiante es el de la sesión.
> Las RPC reciben `p_section_id`.

**El CRUD de secciones resolvió el bloqueante.** Existía el riesgo de construir 12
rutas sobre una tabla que nadie podía llenar; ahora `sections` tiene
crear/listar/archivar. Va en su **propio archivo** y no dentro de `cuadrante.ts`:
una sección es el grupo de una materia en un lapso —lo que el estudiante elige— y
una clase es una franja de la semana —lo que el docente dicta—. Son ciclos de vida
distintos y mezclarlos habría dejado un módulo con dos responsabilidades.

**Ninguna operación borra una sección.** Archivar es `activa: false`, y no es una
convención: el `DELETE` está **revocado** en la base para `authenticated`
(comprobado con `has_table_privilege`). Tampoco se puede cambiar el programa, la
materia ni el lapso por `PATCH`: los tres forman la identidad
(`unique (period_code, subject_id, name)`) y cambiarlos convertiría la sección en
otra llevándose por delante el historial de inscripciones de su `id`.

**`promover_siguiente` devuelve `uuid`, no `text`** (medido con
`pg_get_function_arguments` contra la base, no copiado del `.sql`). Un `null` no es
un error: significa que no había a nadie a quien promover —cola vacía, sección
llena, o ya hay una oferta en el aire—. La ruta responde **200 con la explicación**,
no un 404.

#### Lo que falta de M4

- **Fase 3 (frontend)**: paneles de inscripción y ocupación.
- **Fase 4**: `humo-inscripciones.mjs` con `--confirmar` y purga. **Es el único
  sitio donde puede probarse la concurrencia real** (dos conexiones en paralelo):
  el cerrojo está diseñado para eso pero **no se ha visto funcionar bajo carga**.
- **Lo que sí se comprobó contra la nube** (no es PGlite): las **seis RPC son
  alcanzables por PostgREST con los nombres de parámetro reales** —se llamaron sin
  sesión y cada una llegó a su guardia con `42501`, que es lo esperado: sin
  `auth.uid()` no hay actor—. Eso descarta un `PGRST202` por nombre mal escrito, que
  era el riesgo real de la traducción a HTTP. La vista y `sections` se leen sin
  problema. **Lo que sigue sin ejercitarse end-to-end es GoTrue** (un JWT real
  atravesando PostgREST hasta la RPC), y eso le toca al humo de la Fase 4.

### 2.8 Almacenamiento — Cloudflare R2: ✅ **FUNCIONA**

> **Resuelto el 2026-09-17.** El token anterior tenía el `not_before` en el futuro
> (nació con el reloj de la máquina 12 h adelantado). El reloj se corrigió y
> Lorenzo emitió un token nuevo: **el ciclo completo subir → leer → borrar
> funciona**. Lo de abajo se conserva porque el diagnóstico costó lo suyo y las
> trampas siguen ahí — ver `REPORTE_ARIA.md` **R-24**.

**Lo que el código espera** (fuente: `backend/src/config/env.ts`, líneas 75-91 y
161-166). Son **cuatro** variables y **no** son las que suelen darse de memoria:

| Variable | Nota |
|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | El endpoint **se deriva** de aquí |
| `R2_ACCESS_KEY_ID` | |
| `R2_SECRET_ACCESS_KEY` | |
| `R2_BUCKET` | ⚠️ **`R2_BUCKET`**, no `R2_BUCKET_NAME` |

**No existe `R2_ENDPOINT_URL`.** El endpoint se construye como
`https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com`. Si se define
`R2_BUCKET_NAME` o `R2_ENDPOINT_URL`, el código **no las lee** y fallará como si
no hubiera configuración.

`configuracionR2()` devuelve `null` si **no hay ninguna** variable (modo
degradado), pero **lanza** si hay un juego parcial: *«una configuración a medias
no es un modo degradado: es un error de despliegue»*.

**Lo que ya está confirmado y no hay que volver a preguntar** (verificado en el
panel el 2026-09-18): el bucket `inces-lms-media` **existe**, está **vacío**
(0 B, «Your bucket is ready»), con acceso público **deshabilitado** (correcto:
todo va por URL prefirmada), en la cuenta `c2722758a39bd150eeeaf747827db47c`,
jurisdicción **default** (no EU/FedRAMP). **El nombre del bucket y la cuenta son
correctos.** Las cuatro variables están bien escritas en `backend/.env`
(git-ignorado, `.gitignore:10`).

**Causa raíz — medida, no inferida (ver `REPORTE_ARIA.md` R-24).** Son dos
problemas apilados, y **ninguno es el alcance del token**:

1. **El reloj de la máquina va ~12 h desviado** (sigue así: el reloj marca 06:15
   cuando son las 18:15). SigV4 firma con la hora local y R2 rechaza con
   `RequestTimeTooSkewed` toda firma fuera de 15 minutos. **El SDK de AWS corrige
   el desfase solo y reintenta**, así que ese error nunca se ve: se ve el
   resultado del reintento. Eso fue lo que disfrazó el diagnóstico.
2. **El token de R2 todavía no está vigente.** El endpoint `verify` de la API de
   Cloudflare devuelve sus metadatos:

   ```json
   {"id":"e558f9149000a6c0701c926a76c472a1","status":"active",
    "not_before":"2026-09-18T08:59:52Z","expires_on":"2026-11-30T16:00:00Z"}
   ```

   Ese `id` **es** el `R2_ACCESS_KEY_ID`. El token se creó mientras el reloj iba
   adelantado, así que su `not_before` quedó **en el futuro**, y el propio mensaje
   de Cloudflare lo dice: *«This API Token can not be used before 2026-09-18
   08:59:52+00»*. **R2 responde 403 `AccessDenied` a un token que existe y aún no
   puede usarse.**

**El control que lo destapó** (esto es lo que faltaba antes):

| Prueba | Resultado |
|---|---|
| Credenciales reales | **403** `AccessDenied` |
| **Access key ID inventado** | **401 `Unauthorized`** |
| Bucket inventado (credenciales reales) | 403 `AccessDenied` |

Que una clave inventada dé **401** y la real **403** prueba que R2 **sí** distingue
«la clave no existe» de «la clave no tiene permiso». La conclusión anterior —«la
firma es válida, luego es alcance»— **estaba sin medir y era falsa**.

> ⚠️ **No repitas ese atajo.** `AccessDenied` en R2 colapsa **tres** causas
> distintas: firma incorrecta, permiso insuficiente y **token no vigente**. El
> discriminador es el control con una credencial falsa, no el nombre del error.

**Estado al cierre (2026-09-17):**

| Comprobación | Resultado |
|---|---|
| Reloj de la máquina | ✅ Corregido — desfase de ~25 s contra el servidor (era 12 h) |
| `HeadBucket` | ✅ **HTTP 200** |
| `PutObject` | ✅ **HTTP 200** |
| `GetObject` | ✅ **HTTP 200** y el contenido coincide con lo subido |
| `ListObjectsV2` | ✅ **HTTP 200** |
| `DeleteObject` | ✅ **HTTP 204**, y la purga verificada (0 objetos restantes) |
| Vigencia del token (`verify`) | ✅ `status: active`, `not_before: 2026-09-17T22:55:28Z`, mensaje: *«This API Token is valid and active»* |

**Credenciales vigentes** en `backend/.env` (git-ignorado): `R2_ACCESS_KEY_ID`
`ff9e4647…`, bucket `inces-lms-media`, cuenta `c2722758a39bd150eeeaf747827db47c`.

> **El bucket sigue vacío a propósito.** La sonda de verificación sube y borra su
> propio objeto: no deja residuo. No hay nada que limpiar.

**Efecto colateral a recordar:** con el reloj desviado, las **URL prefirmadas** de
M5 se firman con una hora falsa y R2 las verá vencidas o demasiado futuras según el
signo. Es un fallo intermitente que no se reproduce en una máquina con la hora
bien — mejor arreglar el reloj antes de tocar M5.

> **Nota de seguridad:** el `R2_SECRET_ACCESS_KEY`, el token `cfat_…` y el
> `sbp_…` se pegaron en el chat. El `cfat_` ya no sirve. **Conviene rotar el
> secreto de R2 y el `sbp_`** cuando se cierre este punto.

---

## 3. Mapa de Documentos Vivos

| Documento | Qué es | Cuándo leerlo |
|---|---|---|
| **`ESTADO_DEL_SISTEMA.md`** | **Fuente de verdad.** Estado por fase, esquema, deudas D1–D13, recetas de arranque. **Ojo: se desincroniza solo** — verifica las cifras | **Primero, siempre** |
| `REPORTE_ARIA.md` | Contradicciones del enunciado y fallos propios, resueltos uno por uno (R-01…**R-23**) | Si algo del diseño te chirría |
| **`docs/CONTRATO_API_MODULO3.md`** | **El contrato de M3**: 14 rutas, tipos, errores, y por qué no hay un `unique` de colisión. **§10 explica el fallo `42501`** | **Antes de tocar nada de M3** |
| **`docs/BRIEFING_BACKEND_MODULO4.md`** | **Briefing de la Fase 2 de M4 para un agente que llega sin contexto**: stack real, patrón de rutas, RPC ya existentes con firmas medidas, y el bloqueante de `sections` | **Antes de escribir el backend de M4** |
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
| `temas/modulo4.md` | **M4**: la frontera de seguridad, el modelo, la máquina de estados, los códigos de error, las decisiones abiertas y lo que queda sin probar |
| `temas/infraestructura.md` | Supabase, R2, despliegue dual |
| `temas/interfaz.md` | Flutter, tema, componentes |
| `2026-09-11.md` … `18.md` | Logs diarios. El del 13 cierra el Módulo 1; el del **15** cierra el M3 (esquema, el fallo `42501`, el contrato y el backend); el del **17** despliega M3 en la nube; el del **18** cierra la Fase 1 de M4 |

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
   temas/modulo4.md -> todo lo de M4: frontera de seguridad, máquina de estados,
   códigos de error y lo que quedó sin probar.
4. docs/CONTRATO_API_MODULO3.md -> el contrato de M3 (ya implementado), y en
                                   su §10 el fallo que casi se cuela a produccion.
5. ROADMAP.md está DESACTUALIZADO: no lo uses como referencia de estado.
6. backend/.env.example tiene todas las variables explicadas.

ESTADO ACTUAL (verificado el 2026-09-18, no estimado)
-----------------------------------------------------
- Backend: 341/341 tests, typecheck y eslint limpios.
- Flutter: 307/307 tests (ULTIMA MEDICION VALIDA 2026-09-15: `flutter test` NO
  corre en este entorno, ver HANDOVER §1), `flutter analyze` sin incidencias.
- SQL: 212/212 aserciones en pglite, sobre las 13 migraciones.
- Esquema en la nube: 89/89 comprobaciones (verificar-esquema.mjs).
  Humo de invitacion: 17/17. Humo de curriculo: 14/14.
- HEAD en `main` = `origin/main` (comprueba con
  `git rev-list --left-right --count origin/main...HEAD` -> `0  0`). Working tree
  limpio. No se escribe el SHA: nace obsoleto, ver arriba.
- Modulo 1 completo y verificado de extremo a extremo contra la base real.
- Modulo 2 completo: base, backend y UI.
- Modulo 3 COMPLETO: esquema aplicado y corregido, backend completo (las 14 rutas
  del contrato existen y estan documentadas en openapi.json) y frontend
  construido (rejilla del cuadrante, Mi Horario, aulas, lapsos y guardias).
- Modulo 4: FASE 1 (ESQUEMA) APLICADA Y VERIFICADA, y ADEMAS AJUSTADA a las reglas
  institucionales (migracion 202609200001). El motor de cupos vive entero
  en la base: 6 RPC security definer, cola FIFO, bids opcionales (apagados),
  cerrojo por seccion y frontera de escritura cerrada (ver HANDOVER §2.7 y
  REPORTE_ARIA.md R-23). FALTAN backend y frontend. `m4_inscripciones` sigue
  APAGADO en system_modules: lo enciende la Fase 2.
- Modulos 5-8: solo diseno.
- Deudas abiertas: D7 (verificacion de tokens en cache). D9 (URL prefirmada de
  PUT sin limite de tamano) — **la mitad de codigo ya esta hecha** (2026-09-19):
  el barrido de `PENDING` abandonados que `rutas/archivos.ts:282` nombraba y que
  NO existia es `backend/scripts/limpiar-pendientes.mts` (tres modos: barrido,
  `--revisar-borrados` y `--huerfanos`), y `supabase/eliminar-cuenta.mjs` borra
  los objetos de R2 ANTES de la cuenta, negandose a borrarla si eso falla. Y desde
  el mismo dia el barrido es ademas una **RUTA DE ADMINISTRACION**:
  `POST /api/v1/admin/archivos/limpiar`, idempotente, con `exigirAdmin()` y la
  guardia de modulo, y **sin credenciales de R2 para quien la llama** — las tiene
  el backend. Lo unico que falta es **EL RELOJ**: nadie la pulsa sola, y el repo no
  tiene CI. **`pg_cron` NO puede sustituirlo** —corre dentro de PostgreSQL, que no
  habla con el bucket, asi que marcaria la fila y dejaria el objeto donde esta—,
  asi que la receta de la tarea programada esta escrita y **SIN REGISTRAR** en
  `devops/README.md` §4.2 (una tarea que borra objetos de produccion se activa con
  el dueño del sistema delante). El razonamiento completo, en
  `docs/CONFIGURACION_R2.md` §3.7. La parte de bucket resulto estar tapada de
  fabrica (R2 trae la regla de
  abortar multipart por defecto en todo prefijo; ver `docs/CONFIGURACION_R2.md`
  §3.4). Ojo: una regla `--expire-days` sobre `m5_archivos/` borraria los archivos
  CONFIRMED porque R2 solo filtra por prefijo. **OJO: la frase "latente, M5
  apagado" que habia aqui YA NO VALE** (2026-09-19): decia que `exigirModulo()`
  estaba definido y sin usar, y que por tanto la API servia M5 igual. Es cierto
  que era asi, y por eso estaba escrito; lo que cambio es que ya no lo es. Ver la
  entrada de M5 mas abajo.
- **D16 RESUELTA (2026-09-19)**: el bucket ya tiene politica de CORS, aplicada y
  verificada (el preflight pasa de 403 sin cabeceras a 204 con las tres; la sonda
  `backend/scripts/probe-r2-cors.mts` sale con exit 0). **Desbloquea la Capa 7 en
  Web.** Falta anadir el origen de produccion a la politica Y a `CORS_ORIGINS`
  (son listas independientes). Versionada en `docs/r2-cors.json`.
- **M5 CERRADO EN LOCAL (2026-09-19): la Capa 7, la bandera y la guardia.** Las
  tres cosas en el mismo ciclo:
  (1) **Capa 7 (UI)**: `lib/screens/gestor_documental_panel.dart` orquesta los
  tres pasos a mano —firmar en el backend, `PUT` directo a R2, confirmar— y esta
  montado en el panel del docente (`teacherGuide`) y en el del aspirante
  (`taskSubmission`), con 19 pruebas de widget. `flutter test` **387/387**.
  (2) **La bandera**: `202609210002_mod5_habilitar_modulo.sql` pone
  `habilitado = true`. NO se edito `202609210001` (el validador SHA-256 detecta
  deriva). El nombre NO es `202609190001` como decia el plan: esa version ya esta
  tomada por `mod4_inscripciones` y ademas ordenaria ANTES de `202609210001`, es
  decir antes de que exista la tabla que la fila necesita.
  (3) **La guardia**: las rutas de `rutas/archivos.ts` llevan ya
  `exigirModulo(deps.caches.modulos, 'm5_archivos')` — eran 5 y son **6** desde el
  2026-09-19, con el barrido. Ojo: `exigirModulo` es una
  FABRICA de **dos** argumentos (cache, clave), no un hook; el plan la pasaba con
  uno. Va SIEMPRE despues de `exigirSesion()` / `exigirAdmin()`: al reves, una
  peticion anonima recibiria 404/403 en vez del **401** que exige
  `openapi.test.ts`, que inyecta cada ruta documentada sin token.
  **M5 es ahora el unico modulo cuyo apagado tiene efecto en la API**; en M1-M4 la
  bandera sigue siendo decorativa a nivel de API. Es deuda conocida, no descuido.
- **PENDIENTE DE UNA PERSONA: aplicar `202609210002` a la nube.** Hasta entonces
  la nube tiene `m5_archivos` apagado y **dos verificadores daran 1 fallo cada
  uno** —`backend/test-humo.mjs` **23/24** y `supabase/verificar-esquema.mjs**
  **98/99**— porque su asercion ya exige el modulo encendido. **No es una
  regresion y no hay que bajar la asercion**: es la comprobacion funcionando.
  Aplicada la migracion, los dos vuelven a verde sin tocar nada.
- **Correcciones al plan de este ciclo, por si se relee.** Eran **cuatro**
  aserciones desactualizadas a proposito, no tres: faltaba `backend/test-humo.mjs`.
  Y `supabase/tests/validate.mjs` tenia **dos** que cambiar, no una — la del estado
  inicial y la de **idempotencia**, que reaplica `202609210001` y ahora espera
  ENCENDIDO. El valor nuevo es el que ensena algo: reaplicar una migracion vieja
  **no puede deshacer** una posterior. Ademas `MODULOS_POR_DEFECTO` del arnes **no
  tenia** la fila `m5_archivos`: habia que AÑADIRLA, no ponerla en `true`, o la
  guardia habria devuelto 404 `MODULO_DESCONOCIDO` en vez de dejar pasar. Y el
  contrato OpenAPI necesitaba el `403` en **3 de las 5** rutas: era alcanzable y
  no estaba declarado.
- **Pruebas nuevas que dan sentido a la bandera** (`test/archivos.test.ts`, 34 ->
  36): una apaga el modulo y exige 403 `MODULO_DESHABILITADO` en las cinco rutas
  **sin efecto colateral** (ni fila reservada, ni objeto borrado); la otra, sin la
  fila del modulo, exige **404 `MODULO_DESCONOCIDO`**. Sin la primera, una guardia
  cableada a la clave equivocada habria pasado inadvertida, porque el modulo
  arranca encendido y todas las demas pruebas seguirian verdes.
- **EL BARRIDO YA TIENE DISPARADOR (2026-09-19).** `POST
  /api/v1/admin/archivos/limpiar` expone el barrido de subidas abandonadas como
  ruta de administracion. Es **idempotente** —la segunda llamada devuelve
  `revisadas: 0`, porque la primera dejo las filas en `DELETED`— y **no necesita
  credenciales de R2** para quien la llama: las tiene el backend, que es el unico
  proceso con el SDK y las claves. Cuerpo opcional (`horas`, `limite`); sin el,
  barre lo de mas de 24 h hasta 500 filas. **`horas` no admite menos de 1**, y ese
  minimo NO vive en el esquema Zod sino en `dominio/almacenamiento.ts`
  (`validarHorasDeAbandono`), **compartido con el script**: el umbral es una
  consecuencia del TTL de 300 s de la URL de subida, no una preferencia, y con una
  copia en cada sitio la que se quedara corta borraria subidas en vuelo sin dar
  ningun error.
  **Orden objeto-primero** (al reves que el borrado normal, y por la misma razon
  simetrica): si falla R2, la fila sigue `PENDING` y la pasada siguiente la
  reencuentra. Las filas que fallan se cuentan, se registran y se devuelven en
  `idsFallidas`: el barrido no se aborta por una fila, pero tampoco calla. Un
  `ESTADO_DE_ARCHIVO` —otra pasada concurrente ya la marco— cuenta como **exito**,
  no como fallo: el estado al que se queria llegar ya esta puesto.
- **Pruebas del barrido** (`test/archivos.test.ts`, 36 -> **44**). Ocho, y las
  importantes no son las que comprueban que barre sino las que comprueban que
  **no** barre: que no toca una `PENDING` reciente (barrerla destruiria una subida
  en vuelo), ni una `CONFIRMED`, ni una `DELETED`; que el tope corta **por lo mas
  viejo** y la pasada siguiente sigue por donde iba; y que un umbral de media hora
  da **400 sin tocar nada**. Las fechas de siembra son 2020 y 2999 a proposito: la
  ruta compara contra el reloj real, asi que una semilla cercana haria que la
  prueba dependiera del dia en que se ejecuta. **Verificado por mutacion**: dar
  vuelta al orden del puerto y bajar el minimo del umbral hacen fallar exactamente
  la prueba que les corresponde.
- **El barrido tambien se comparte con el script.** `limpiar-pendientes.mts` ya no
  lleva su propio `24`: importa `HORAS_ABANDONO_POR_DEFECTO` y
  `validarHorasDeAbandono` del dominio. Dos puertas al mismo barrido —ruta para el
  cPanel y la nube, script para el operador y los modos forenses— y una sola regla
  de umbral. Ver `docs/CONFIGURACION_R2.md` §3.7.
- **`scripts/` YA SE COMPRUEBA TIPOS.** Estaba fuera del `include` de
  `tsconfig.json`: `eslint` lo miraba, `tsc` no. Al meterlo aparecio **un error
  real** en `generar-openapi.mts` (`documento.paths[ruta]` es
  `PathItemObject | undefined` con `noUncheckedIndexedAccess`, y el `?? {}` de la
  linea de arriba no cubria esa lectura). Corregido recorriendo las entradas, con
  `openapi.json` byte a byte identico. **Si añades un script, ya esta cubierto.**
- **Deriva corregida en `ESTADO_DEL_SISTEMA.md`**: la tabla decia **47 rutas / 84
  esquemas** y el contrato comprometido en `db5eef2` ya tenia **55 / 84**. Ahora
  **56 / 86**. La cifra de rutas llevaba varios ciclos sin actualizarse.
- CORRECCION M4 (2026-09-19): esta linea decia que `m4_inscripciones` seguia
  APAGADO y que faltaban backend y frontend. Es DERIVA. Verificado contra la base
  y el repo: `m4_inscripciones.habilitado = true`; existe
  `backend/src/http/rutas/inscripciones.ts`; y existen
  `lib/screens/admin/cpanel_inscripciones_panel.dart`, su gateway, servicio,
  repositorio y modelo. Comprueba el alcance real antes de reabrirlo.
- Resueltas: D8, D10, D11, D12, D13.
- Decisiones que NO son tuyas (R-06 ya resuelta: el lapso vigente es `SA26-2` y m2/m3 habilitados):
  R-16 (frontera de turnos), R-17 (fechas del lapso), R-18 (inventario de aulas).
  Las cuatro se cambian sin tocar codigo: son datos, o una funcion de una linea.
- Decisiones de PRODUCTO de M4: YA RESUELTAS por Lorenzo el 2026-09-18 e
  implementadas. No las reabras; lee §2.7 y el aviso de doble venta.
  (1) bids siguen apagados; (2) el admin SI puede exceder la capacidad en una
  reincorporacion; (3) `PENDING_BID` NO cuenta como ocupacion — y por eso existe
  `existe_oferta_vigente()`; (4) con cupo libre se entra directo a ENROLLED.
  El parametro de faltas: se usa el global `max_faltas_consecutivas = 3`, sin duplicar.
- BLOQUEANTE ABIERTO: Cloudflare R2 da `AccessDenied` porque el token aun no esta
  vigente (`not_before` unos 10 h en el futuro). El bucket y la cuenta SON
  correctos y el reloj ya se corrigio. Falta solo que Lorenzo emita un token nuevo.
  Ver §2.8 y REPORTE_ARIA.md R-24 antes de escribir la subida de archivos.

LA TRAMPA QUE MAS CARO COSTO
----------------------------
Un trigger `security invoker` que llama a una funcion revocada deja el modulo
inoperable, y la suite NO lo ve si las pruebas escriben como el dueño de las
tablas (el dueño se salta la comprobacion de EXECUTE). Antes de escribir una
prueba de trigger: preguntate como que rol esta escribiendo. Detalle en
REPORTE_ARIA.md R-20.

Y su hermana, en la frontera de escritura (R-23): un `SQLSTATE` solo NO identifica
la causa. El `42501` de un INSERT puede venir del GRANT que falta o de la politica
RLS, y son arreglos distintos. Comprueba que el privilegio no existe, no solo que
la operacion falla. Corolario: no basta con revocar la politica; hay que revocar
el GRANT, y Supabase concede `grant all` por defecto (incluido `TRUNCATE`, que la
RLS NO gobierna).

Y una tercera, de diagnostico (R-24): **no inferir la causa del NOMBRE del error.**
`AccessDenied` en R2 colapsa tres causas distintas (firma incorrecta, permiso
insuficiente, token aun no vigente). El discriminador es un EXPERIMENTO DE CONTROL
—una credencial deliberadamente falsa—, no la lectura del codigo de error. Y antes
de culpar al servicio remoto, mira el reloj: un desfase de 12 h rompe SigV4 y el
SDK de AWS lo corrige en silencio, disfrazando el error real.

TAREA INMEDIATA
---------------
Antes de escribir una línea de código, haz esto y repórtalo:
0. **Comprueba el reloj**: `date -u` contra la cabecera `Date` de cualquier
   servidor (`curl -s -I https://api.cloudflare.com/client/v4/`). Si hay desfase,
   avisa ANTES de tocar nada firmado (R2, URL prefirmadas): un desfase >15 min
   rompe SigV4 y el SDK de AWS lo oculta corrigiéndolo solo. Ha pasado (R-24).
1. `git status --short` y `git log --oneline -5` para que confirmemos el punto
   de partida.
2. `cd backend && npm test` y `cd supabase/tests && npm test` para confirmar que
   heredas verde (341 / 222). **`flutter test` no corre en este entorno** (falla al
   cargar, WebSocket de `flutter_tester`): el 307/307 es la ultima medicion valida
   del 2026-09-15, no la re-ejecutes esperando verde. Usa `flutter analyze`, que si
   funciona.
3. Lee HANDOVER.md §2 y dime qué atacamos primero:
   (a) M4 Fase 2 — el backend de inscripciones (~10-12 rutas, puerto,
       repositorio, Zod, OpenAPI, y encender `m4_inscripciones`): el esquema ya
       está desplegado y verificado, así que es el siguiente paso natural,
   (b) desbloquear R2 (§2.8) para poder subir archivos,
   (c) verificar el dominio en Resend (desbloquea el correo a terceros), o
   (d) abrir la pantalla de activación en un navegador real (mitad-UI de M1).
   Recomiendo (a): las 4 decisiones de producto de §2.7 ya estan resueltas, asi
   que no hay nada que esperar. R2 (b) solo bloquea la subida de archivos, que no
   es de la Fase 2.

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
