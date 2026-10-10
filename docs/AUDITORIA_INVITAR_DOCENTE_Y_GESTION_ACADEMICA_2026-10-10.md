# Auditoría — «Invitar docente» y gestión académica (Usuarios/Roles, Pensum, Períodos)

> Sesión del **2026-10-10**. Base: `main` en `18aef35` («docs: document production
> deployment runbook»). Este informe es de **diagnóstico + una corrección local de
> bajo riesgo**. No se aplicaron migraciones, no se publicó nada, no se hizo commit.

---

## 0. Corrección de premisa (medida, no supuesta)

El encargo describe el backend como **Python/FastAPI**. **Eso es falso.** El backend
real es **Node/TypeScript con Fastify 5 + Zod** (ESM), en `backend/`:

- `backend/package.json` → `"fastify": "^5.2.1"`, `"type": "module"`, `vitest`, `tsc`.
- No existe `requirements.txt`, `pyproject.toml` ni ningún `.py`.

El resto de la premisa **sí** coincide: repo `github.com/Burmistrov4/inces-lms`,
rama `main`, Render para el backend y Cloudflare Pages para el frontend
(`render.yaml` en la raíz). La nota de la memoria del proyecto que decía «cPanel»
está **desactualizada**; el destino de producción hoy es Render.

---

## A. Estado inicial

| Comprobación | Resultado medido |
|---|---|
| Ruta | `C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT` |
| Rama | `main` |
| HEAD | `18aef35` (coincide con `origin/main`) |
| `git status --short` | **14 entradas, todas sin rastrear** — sin conflictos, sin modificaciones ajenas |
| Sin rastrear | `.wrangler/`, `backend/server-e2.err`, y 11 `e2e/tests/_*.spec.ts` de diagnóstico |

No se tocó ninguno de los archivos sin rastrear (son deliberados, según el propio repo).

### Producción (medida hoy, no supuesta)

| Endpoint | Resultado |
|---|---|
| `GET https://inces-lms-api.onrender.com/salud` | **HTTP 200** · `{"estado":"ok","version":"0.1.0"}` · 658 ms |
| `GET https://inces-lms.pages.dev/` | **HTTP 200** · 435 ms |
| `OPTIONS /api/v1/admin/usuarios/invitaciones` (preflight CORS desde `inces-lms.pages.dev`) | **HTTP 204** |

El endpoint de invitaciones **existe y responde en producción**.

---

## B. Incidencia A — «Invitar docente» no hace nada

### Cadena real (leída, no supuesta)

```
CpanelUsuariosRolesPanel.build
  └─ ListView
       └─ ExpansionTile(title: 'Invitar docente')      ← el «botón»
            └─ Padding → CpanelInvitacionesPanel()
                 └─ ListView   ← (antes) altura NO acotada aquí
```

- `lib/screens/admin/cpanel_usuarios_roles_panel.dart:498` — el «botón» es un
  `ExpansionTile`, no un `FilledButton`. Al pulsarlo **despliega** el formulario.
- `lib/screens/admin/cpanel_invitaciones_panel.dart` — formulario completo
  (nombres, apellidos, correo, validación, «Enviar invitación», listado, renovar,
  anular).
- `InvitacionRepository` valida; `BackendInvitacionGateway` llama a
  **`POST /api/v1/admin/usuarios/invitaciones`** con el JWT de sesión.
- Backend `backend/src/http/rutas/admin.ts:276` — misma ruta, bajo
  `exigirAdmin()`. **La URL del frontend coincide con la del backend.**

**Conclusión: el cableado es correcto de punta a punta.** El fallo no está en el
endpoint, ni en el token, ni en la validación.

### Causa raíz (alta confianza, alineada con el historial del propio proyecto)

`CpanelInvitacionesPanel.build` devolvía un **`ListView` con `shrinkWrap: false`**,
y ese panel se monta **dentro de `ExpansionTile.children`**, que Flutter compone
como una `Column` de **altura NO acotada**. Un `ListView` no acotado lanza
**«Vertical viewport was given unbounded height»** al desplegar el acordeón. En
`--release` esa excepción se pinta como un recuadro gris: **el usuario pulsa y «no
pasa nada».**

Evidencia de que **éste es el patrón que este proyecto ya pagó**: el doc de
`ContenidoSeccion` (`lib/widgets/andamiaje.dart:720`) dice literalmente que un
`ListView` bajo altura infinita «revienta con "incoming height constraints are
unbounded"», que **tres paneles del cPanel** lo hacían, y que *«abrirlos en la
aplicación real lanzaba una excepción de layout; las pruebas no lo veían porque los
montaban en el `body` acotado de un `Scaffold`»*.

Y el hueco de cobertura es exactamente el mismo: `test/contenido_seccion_test.dart:190`
monta `CpanelInvitacionesPanel` **directamente en `ContenidoSeccion`** (acotado),
**no dentro del `ExpansionTile` donde vive**.

### Corrección aplicada (mínima, 3 líneas, sin reindentar)

`lib/screens/admin/cpanel_invitaciones_panel.dart`: la raíz pasa de
`ListView(padding: EdgeInsets.zero, children: […])` a
`Column(crossAxisAlignment: stretch, mainAxisSize: min, children: […])`.

Es el contrato que el proyecto ya usa para hijos de `ExpansionTile`: en
`cpanel_inscripcion_campos_panel.dart:369`, los hijos del `ExpansionTile`
(`_SeccionGrupo`) son widgets que crecen con el contenido, **nunca desplazables**.
El scroll lo pone el `ListView` de `CpanelUsuariosRolesPanel`, que es el padre real.

### Prueba de regresión añadida

`test/cpanel_invitaciones_en_su_sitio_test.dart` — monta `CpanelUsuariosRolesPanel`
en su padre real, **pulsa el acordeón** y exige `takeException() == null` y que
aparezca «Enviar invitación». Falla con el código viejo, pasa con el nuevo.

**Estado: EN PROGRESO** — la corrección está aplicada y type-checkeada, pero la
prueba **no se pudo ejecutar en local** (ver §F). Debe correr en CI para cerrar.

---

## C. Usuarios y Roles — qué existe ya

**Invitación de docentes: implementada** (formulario, validación, duplicados vía
`listarInvitaciones`, renovar/anular, enlace de activación de 48 h). El aviso dice
«Invitación creada. El enlace está listo para entregar» — **no** «enviada», porque
Resend no tiene dominio verificado; el enlace se muestra para reenviarlo a mano.

**Promoción de administradores: ya existe.** En la tabla de usuarios, el icono
«Cambiar rol» abre `_DialogoRol`; si el rol destino es `admin`, pide confirmación
explícita. Ruta: `PATCH /api/v1/admin/usuarios/:id/rol`.

**Protección del último administrador: ya existe, y por diseño en dos capas:**

1. `backend/src/dominio/reglas-admin.ts` → `revisarCambioDeRol()` (función pura,
   probada): rechaza la auto-degradación (`AUTO_DEGRADACION`) y el último admin
   (`ULTIMO_ADMIN`).
2. **Trigger `proteger_ultimo_admin` en PostgreSQL**
   (`supabase/migrations/202609120003_proteger_ultimo_admin.sql`), que cubre lo que
   la función no puede: la carrera entre dos degradaciones simultáneas y cualquier
   cambio por fuera de la API.

**Gap real de la Incidencia B:** es de **descubribilidad**, no de capacidad. El
usuario «no encuentra cómo añadir un administrador» porque la acción está dentro de
la columna «Acciones» de cada fila, sin un encabezado que lo anuncie. No hay
pestañas «Invitaciones pendientes» / «Historial de cambios de rol» separadas.
**Estado: NO VERIFICADO en UI real** (no se pudo abrir el navegador con sesión).

---

## D. Programas y pensums — qué existe ya

**Implementado y persistido** (más completo de lo que sugiere el encargo):

- **Modelo**: `programs` (código, nombre, tipo `CARRERA`/`CURSO_LIBRE`,
  `requires_internship`, `is_active`), `subjects` (banco global, `academic_hours`),
  `program_subjects` (**el pensum**: materia → programa → `period_order`).
- **Regla 1**: un programa `CARRERA` activo no puede quedarse sin materias —
  *constraint trigger diferido* `exigir_pensum_de_programa`.
- **Regla 2**: no se puede reordenar/quitar materias del pensum si hay secciones
  activas del período vigente usándolo (el panel lo muestra como «Pensum
  bloqueado: hay N secciones activas»).
- **UI**: `cpanel_programas_panel.dart` — «Nuevo programa», «Ver pensum», «Editar
  pensum», «Publicar»/«Archivar», validación «Un programa sin materias no se puede
  activar». Además hay un **asistente de 3 pasos** (`asistente_curriculo_screen.dart`)
  que crea programa + pensum en una sola operación.
- **API**: `backend/src/http/rutas/curriculo.ts` — `GET/POST/PATCH /programas`,
  `GET/POST /materias`, con `exigirAdmin()` **y** `exigirModulo('m2_curriculo')`.

**Gap real de la Incidencia C:** también de **descubribilidad/navegación**. La
pantalla se llama «Programas Académicos» (menú *Gestión académica*); el pensum se
edita desde el botón de cada fila. No hay una sección «Pensum» propia.
**Estado: NO VERIFICADO en UI real.**

---

## E. Períodos académicos, duración y caducidad — **aquí sí falta trabajo**

Esto es lo único del encargo que **no está implementado**:

- `academic_periods` tiene `code`, `name`, `start_date` (anulable), `end_date`
  (anulable), `is_active`. **No hay columna de duración.**
- La coherencia de fechas es un `CHECK` de tabla:
  `end_date is null or start_date is null or end_date > start_date`.
- `programs` **no tiene** `duración` ni unidad (solo `subjects.academic_hours`).
- **No existe** máquina de estados del lapso (borrador/programado/activo/cerrado/
  vencido/cancelado), ni **cálculo de vencimiento**, ni **historial de
  modificaciones de fechas / prórrogas**.
- El «vigente» **no** es una fecha: es `system_settings.periodo_activo`, declarado
  con `PUT /periodos/:id/vigente`. Las fechas son informativas hoy.

**Implicación:** implementar «duración configurable por programa» + «caducidad con
historial de prórrogas» **requiere una migración de esquema nueva**. Por la §10 del
encargo y la §2 del procedimiento de despliegue, **eso necesita autorización
explícita** antes de aplicarse a producción. La migración se puede *preparar* en el
repo; no aplicarla.

**Estado: NO INICIADO** (bloqueado por decisión, no por técnica).

---

## F. Pruebas — comandos ejecutados y resultado real

| Comando | Resultado |
|---|---|
| `flutter --no-version-check test --no-pub test/cpanel_invitaciones_en_su_sitio_test.dart` (×3) | **BLOQUEADO** — `CreateFile failed 231` (`ERROR_PIPE_BUSY`) |
| `node devops/analizar-dart.mjs` | **223 archivos · sin errores, avisos ni info** |

El `231` **no es del proyecto**: es el sandbox de esta sesión agotando su
presupuesto de creación de procesos. El volcado lo muestra nítido — muere al lanzar
`git.exe` (`checkFlutterVersionFreshness`) y el `hooks_runner` de assets nativos
(`objective_c`). Coincide exactamente con lo ya documentado en la memoria del
proyecto («es del sandbox, intermitente por agotamiento»).

**Consecuencia honesta:** la corrección de §B **no está demostrada en ejecución
local**. `flutter test` debe correr en CI para cerrarla. El type-check sí pasó.

---

## G. Git

- **Sin commits.** No se creó ninguno: el encargo pide trazabilidad y aún no hay
  evidencia de ejecución que respalde un commit funcional.
- **Modificados (sin commitear):** `lib/screens/admin/cpanel_invitaciones_panel.dart`.
- **Nuevos (sin rastrear):** `test/cpanel_invitaciones_en_su_sitio_test.dart`,
  `docs/AUDITORIA_INVITAR_DOCENTE_Y_GESTION_ACADEMICA_2026-10-10.md`.
- Sin rastrear **preexistentes, intactos:** `.wrangler/`, `backend/server-e2.err`,
  `e2e/tests/_*.spec.ts`.

---

## H. Producción

| Componente | Estado medido |
|---|---|
| Render `/salud` | **200** · ok |
| Cloudflare Pages `/` | **200** |
| CORS preflight invitaciones | **204** |
| Migraciones (según memoria, `apply-migrations.mjs --check`, 2026-10-09) | 46 aplicadas · 0 pendientes · 0 deriva — **NO re-verificado hoy** |

**No se publicó nada.** No se aplicaron migraciones.

---

## I. Pendientes y decisiones que requieren tu aprobación

1. **Ejecutar la prueba en CI** (o cuando el sandbox libere procesos) para cerrar la
   Incidencia A con evidencia de ejecución.
2. **Incidencia D (períodos/duración/caducidad)** — es la única que exige cambio de
   esquema. Decisiones que necesito de ti antes de escribir la migración:
   - ¿La **duración** se define por **programa** (p. ej. soldadura = 3 meses) o por
     **lapso**?
   - ¿El vencimiento **bloquea** inscripciones/edición o solo **avisa**?
   - ¿Una **prórroga** reabre el lapso, o se registra y el lapso sigue cerrado?
   - ¿Los estados (borrador/activo/cerrado/vencido) son los del dominio real, o
     basta con fechas + `is_active`?
3. **Incidencia B/C (descubribilidad)** — ¿quieres que reorganice la navegación
   (p. ej. «Invitaciones pendientes» e «Historial de roles» como apartados propios,
   y una ruta «Pensum» diferenciada), o preferís mejorar los rótulos dentro de las
   pantallas actuales?
4. **Verificación en UI real** — necesito una cuenta de prueba autorizada (o tu
   confirmación de que puedo usar una de las existentes) para reproducir en
   navegador. No invento credenciales ni toco cuentas reales.
