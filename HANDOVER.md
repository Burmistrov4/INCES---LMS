# HANDOVER — INCES LMS

> Traspaso de mando generado el **2026-09-13**. Todo lo que aparece aquí fue
> verificado contra el repositorio en el momento de redactarlo. Si algo de este
> documento contradice al código, **gana el código**: avísame y lo corrijo.

---

## ⚠️ LEA ESTO PRIMERO: hay trabajo sin commitear

El último commit es `364d32b`. Desde entonces hay **29 archivos modificados y 23
rutas sin seguimiento** en la rama `main`. Eso incluye **todo el Módulo 1**
(invitación de docentes + auditoría de accesos) y el overhaul visual.

```
git status --short    # ver el alcance exacto antes de tocar nada
```

**No hagas `git checkout .`, `git stash` ni `git reset --hard` sin hablarlo con
Lorenzo.** Un solo comando destruiría semanas de trabajo. Si vas a hacer cambios
grandes, commitea primero el estado actual como punto de restauración.

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

### 2.1 Aplicar la migración a la base real — BLOQUEANTE

`supabase/migrations/202609130001_invitaciones_docente.sql` **existe pero NO está
aplicada**. Hasta que lo esté, el canal de invitación de docentes no funciona en
la nube y la auditoría devolverá páginas vacías (no es un bug del panel).

```bash
# 1) simulación, no escribe nada
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --check

# 2) aplicar de verdad
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
```

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

### 2.3 Alineación de puertos y `CORS_ORIGINS`

El backend escucha en **3000** por defecto (`PORT=3000`), que **colisiona con el
puerto de desarrollo de Flutter**. Arranque correcto:

```bash
# Backend  (elige 8080 u otro, pero sé coherente)
cd backend && PORT=8080 npm run dev

# Frontend — --web-port NO es opcional
flutter run -d chrome --web-port=8080 \
  --dart-define=API_BASE_URL=http://localhost:8080
```

> Sin `--web-port`, Flutter elige un puerto **efímero distinto en cada arranque**
> y el valor de `CORS_ORIGINS` queda obsoleto al segundo intento: el navegador
> bloquea la API con un error de CORS que parece un bug de backend y no lo es.

Valor actual en `.env.example`:

```
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080
```

`API_BASE_URL` se lee por `--dart-define`. Si no se pasa, el `ApiClient` lanza un
error explícito en lugar de fallar en silencio.

### 2.4 Humo real pendiente (lo ejecuta Lorenzo)

1. Aplicar la migración (2.1).
2. Invitar a `lorenzoroca333@gmail.com` desde el cPanel.
3. Copiar `enlaceActivacion` de la respuesta.
4. Abrir `http://localhost:8080/#/auth/activate?token=...`.
5. Fijar contraseña.
6. Confirmar en la base: `rol = 'docente'` e `is_used = true`.

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
- Módulo 1 completo (invitación de docentes + auditoría de accesos).
- Módulos 2-8: sólo diseño.
- Deudas abiertas: D9 (URL prefirmada de PUT sin límite de tamaño) y
  D10 (conexión directa sólo IPv6 -> usar supabase/apply-migrations.mjs).
- OJO: hay ~52 archivos entre modificados y sin seguimiento en la rama main.
  NO hagas git checkout/reset sin confirmar con Lorenzo.

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
