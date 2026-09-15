# HANDOVER — INCES LMS

> Traspaso de mando generado el **2026-09-13**. Todo lo que aparece aquí fue
> verificado contra el repositorio en el momento de redactarlo. Si algo de este
> documento contradice al código, **gana el código**: avísame y lo corrijo.

---

## ✅ Estado del repositorio: limpio y sincronizado

**Todo el trabajo está resguardado.** El working tree está limpio y `main`
coincide con `origin/main`.

```
commit 004923a85bab0c372f7b63956dccee5ad792d9db
Autor:  Burmistrov4 <lorenzoroca333@gmail.com>
Fecha:  2026-09-13 17:11:17 -0400
Asunto: feat(modulo1): flujo de invitaciones docente, auditoria de accesos auth_logs y overhaul de UI

55 archivos · +8.511 / −1.158
```

Commiteado y subido **después** de verificar en verde: backend 171/171 + typecheck
+ lint, Flutter 110/110 + `analyze`. Puedes trabajar con tranquilidad: ya no hay
nada sin commitear que un `git checkout` pueda destruir.

Nota de higiene: `.env`, `.env.json` y la carpeta de contexto están en
`.gitignore`, así que **ninguna credencial entró al commit**. `backend/.env.example`
sí se versiona a propósito (es la plantilla documentada, sin valores reales).

---

## 1. Resumen del Estado Actual del Código

### Suite de pruebas

| Suite | Resultado | Comando |
|---|---|---|
| Backend (vitest) | **171 / 171** en verde · 11 archivos | `cd backend && npm test` |
| Flutter | **110 / 110** en verde | `flutter test` |

Desglose backend: `admin.test.ts` (51), `r2` (24), `esquemas` (16), `modulos` (15),
`autenticacion` (12), `resiliencia` (11), `invitaciones` (9), `openapi` (9),
`env` (10), `reglas-admin` (10), `salud` (4).

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
`openapi.json` regenerado: **15 rutas, 24 esquemas**.

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

`node supabase/verificar-esquema.mjs` → **32/32 sin fallos**.

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

Estado actual: **5/5 adoptadas**, `--check` → `0 pendiente(s), 0 con deriva`.

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
(30 comprobaciones; la línea base actual es **30/30**).

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

### 2.4 Humo del canal de invitación — MITAD-API ✅ / MITAD-UI ⏳

**Mitad-API: VERIFICADA** contra la base real con `node supabase/humo-invitaciones.mjs
--confirmar` → **17/17 sin fallos**, cero residuo. Cubre lo que las 171 pruebas con
dobles no podían cubrir:

- RLS de `teacher_invitations` y `auth_logs` con JWT reales: el admin ve, `anon`
  no ve, un `docente` no ve, y **nadie inserta trazas con rol `authenticated`**
  (no hay GRANT de INSERT, por diseño).
- HTTP completo: `POST /admin/usuarios/invitaciones` → `POST /auth/activar` →
  `perfil.rol = 'docente'`, `is_used = true`, traza SUCCESS en `auth_logs`.
- El token es de un solo uso: reutilizarlo se rechaza.
- El token en claro **no** queda en la base (sólo su SHA-256).

**Mitad-UI: PENDIENTE.** Abrir `http://localhost:8080/#/auth/activate?token=...` en
el navegador, fijar la contraseña y comprobar que la pantalla lee el token de
`Uri.base.fragment`. Requiere la alineación de puertos de 2.3. Nunca se ha
ejecutado esa pantalla en un navegador real.

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

## 3. Mapa de Documentos Vivos

| Documento | Qué es | Cuándo leerlo |
|---|---|---|
| **`ESTADO_DEL_SISTEMA.md`** | **Fuente de verdad.** 758 líneas: estado por fase, deudas D1–D10, recetas de arranque | **Primero, siempre** |
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
| `temas/infraestructura.md` | Supabase, R2, despliegue dual |
| `temas/interfaz.md` | Flutter, tema, componentes |
| `2026-09-11.md` / `12` / `13` | Logs diarios. El del 13 detalla el cierre del Módulo 1 |

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
2. ESTADO_DEL_SISTEMA.md        -> fuente de verdad (758 líneas).
3. .workbuddy-ai/memory/MEMORY.md y temas/convenciones.md -> reglas y convenciones.
   convenciones.md es OBLIGATORIO antes de tocar cualquier archivo de código.
4. ROADMAP.md está DESACTUALIZADO: no lo uses como referencia de estado.
5. backend/.env.example tiene todas las variables explicadas.

ESTADO ACTUAL
-------------
- Backend: 171/171 tests, typecheck y eslint limpios.
- Flutter: 110/110 tests, `flutter analyze` sin incidencias.
- HEAD en `main` = `004923a`, idéntico a `origin/main`. Working tree limpio.
- Módulo 1 completo (invitación de docentes + auditoría de accesos).
- Módulos 2-8: sólo diseño.
- Deudas abiertas: D9 (URL prefirmada de PUT sin límite de tamaño) y
  D10 (conexión directa sólo IPv6 -> usar supabase/apply-migrations.mjs).
- Todo resguardado en el commit 004923a; `main` está limpio y sincronizado con
  `origin/main`. No hay trabajo pendiente de commitear.

TAREA INMEDIATA
---------------
Antes de escribir una línea de código, haz esto y repórtalo:
1. `git status --short` y `git log --oneline -5` para que confirmemos el punto
   de partida.
2. `cd backend && npm test` y `flutter test` para confirmar que heredas verde.
3. Lee HANDOVER.md sección 2 y dime cuál de los tres pendientes críticos
   atacamos primero: (a) aplicar la migración 202609130001 a la base real,
   (b) verificar el dominio en Resend, o (c) fijar puertos y CORS_ORIGINS.
   Recomiendo (a): bloquea todo lo demás.

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
