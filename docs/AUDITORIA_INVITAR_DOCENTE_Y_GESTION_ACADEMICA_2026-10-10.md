# Auditoría — «Invitar docente», Usuarios/Roles y gestión académica

> Sesión del **2026-10-10**. Base inicial: `main` en `18aef35`. Estado final:
> `main` en **`ebc9661`**, **desplegado en producción**.
> Sin migraciones aplicadas. Sin secretos nuevos.

---

## 0. Corrección de premisa (medida, no supuesta)

El encargo describe el backend como **Python/FastAPI**. **Es falso.** El backend real es
**Node/TypeScript con Fastify 5 + Zod** (ESM), en `backend/` (`package.json` →
`"fastify": "^5.2.1"`, `"type": "module"`, `vitest`, `tsc`; no hay `requirements.txt`
ni ningún `.py`). El resto del encargo sí coincide: repo `github.com/Burmistrov4/inces-lms`,
`main`, Render + Cloudflare Pages (`render.yaml`). La memoria del proyecto decía «cPanel»;
**corregido**: el destino es Render.

---

## A. Estado inicial

| Comprobación | Resultado medido |
|---|---|
| Rama | `main` |
| HEAD inicial | `18aef35` (coincidía con `origin/main`) |
| `git status --short` | 14 entradas **sin rastrear**, sin conflictos ni modificaciones ajenas |
| Sin rastrear (intactos) | `.wrangler/`, `backend/server-e2.err`, 11 `e2e/tests/_*.spec.ts`, `e2e/_monitor_t4.ps1` |

Producción al empezar: Render `/salud` → **200**; Pages `/` → **200**; preflight CORS de
`/api/v1/admin/usuarios/invitaciones` → **204**. El despliegue de Pages en curso era
`75b77944`, construido desde `794e9f2` (5 h antes).

---

## B. Incidencia A — «Invitar docente» no hace nada · **CERRADO**

### La cadena estaba bien cableada

```
ExpansionTile('Invitar docente')            cpanel_usuarios_roles_panel.dart
  └─ CpanelInvitacionesPanel                (formulario + validación + listado)
       └─ InvitacionRepository              (valida correo/nombres)
            └─ BackendInvitacionGateway     POST /api/v1/admin/usuarios/invitaciones
                 └─ backend admin.ts:276    bajo exigirAdmin()
```

La URL del frontend coincide con la del backend. **No era el endpoint, ni el token, ni la
validación.**

### Causa raíz (confirmada por medición)

`CpanelInvitacionesPanel` enraizaba en un **`ListView` con `shrinkWrap: false`**, y se monta
dentro de `ExpansionTile.children`, que Flutter compone como una `Column` de **altura no
acotada**. Al desplegar el acordeón:

```
❌ test/cpanel_invitaciones_en_su_sitio_test.dart … (failed)
Vertical viewport was given unbounded height.
989 tests passed, 1 failed.
```

En `--release` esa excepción se pinta como un recuadro gris: el usuario pulsa y «no pasa nada».

### Corrección

Raíz → `Column(crossAxisAlignment: stretch, mainAxisSize: min)`, el contrato que el proyecto ya
usa para hijos de `ExpansionTile` (`_SeccionGrupo`, `cpanel_inscripcion_campos_panel.dart:369`).

### Prueba de regresión (escrita y **ejecutada**)

`test/cpanel_invitaciones_en_su_sitio_test.dart` monta `CpanelUsuariosRolesPanel` en su padre
real, comprueba que el formulario está visible **sin pulsar nada**, que el acordeón sigue
plegando/desplegando y que no hay excepción de layout.

### Contra-prueba (el test no es un verde vacío)

Se creó una rama con **solo la corrección revertida** (el test intacto) y se corrió CI:
**«Análisis estático» pasó y «Suite de pruebas» falló** con el error exacto predicho.
Con la corrección: **991/991 en verde**.

| Corrida | Contenido | Resultado |
|---|---|---|
| `38052066421` | fix + test (rama) | **success** |
| `38052467610` | **fix revertido** (contra-prueba) | **failure** — `Vertical viewport was given unbounded height` |
| `38053792905` | fix + test + guardia de ancho | **success** — `991 tests passed` |
| `38054401881` | `main` final | **success** |

---

## B.2 Regresión introducida y corregida (la cazó la CI)

Al mover la invitación arriba y arrancarla **desplegada**, el panel pasó a renderizarse dentro
de `CpanelUsuariosRolesPanel` a 375 px. Con los 16 px de padding a cada lado se quedaba en
**311 px** y el formulario **desbordaba 5 px**:

```
❌ barrido_responsive_test.dart: Usuarios y Roles · auditoría multi-ancho
Actual: FlutterError:<A RenderFlex overflowed by 5.0 pixels on the right.>
```

Corregido quitando el padding horizontal del hijo del acordeón (el panel vuelve a los 343 px
con los que está probado que cabe). Verificado: `capturados=0` y **991/991**.

**Lección:** mover un panel de sitio cambia el ancho que recibe. El barrido responsive lo
detectó porque monta el panel en su padre real.

---

## C. Usuarios y Roles — mejoras aplicadas

Ya existían (no se duplicó nada): invitación de docentes, cambio de rol con confirmación para
`admin`, y **protección del último administrador en dos capas** — `revisarCambioDeRol()` (función
pura, `backend/src/dominio/reglas-admin.ts`) **y** el trigger `proteger_ultimo_admin` de
PostgreSQL (`202609120003`), que cubre además la carrera entre degradaciones simultáneas.

Lo que se añadió:

1. **La invitación sube al principio y arranca desplegada** (`initiallyExpanded: true`). Un
   acordeón cerrado al final de una lista larga no dice qué contiene: era el otro fallo de
   descubribilidad.
2. **Nota explícita** de cómo incorporar un administrador (invitar → cambiar rol), y el subtítulo
   del acordeón lo repite.
3. **Guardia de una operación a la vez** (`_ocupado`) en cambio de rol y restablecimiento, con
   barra de progreso: un doble toque ya no dispara dos mutaciones.

Backend verificado (leído, no supuesto): `exigirAdmin()` en todas las rutas de `/api/v1/admin`,
más RLS en Postgres (ADR-003).

**Estado: CERRADO** en lo técnico. La **verificación funcional en navegador con cuenta real no se
hizo** (no hay credenciales de prueba disponibles; no se inventan).

---

## D. Programas y pensums — navegación aclarada

El modelo ya existe y no se tocó: `programs` / `subjects` / `program_subjects` (el pensum), con
el trigger diferido «una carrera activa no puede quedarse sin materias», la regla «pensum
bloqueado si hay secciones activas» y el asistente de 3 pasos.

Lo que se añadió: una **línea explícita** al principio del panel de Programas que dice dónde se
administra el pensum («Editar pensum», el lápiz). Antes sólo lo decía un `tooltip`, que se
explica al pasar el ratón.

**Estado: CERRADO** (cambio de descubribilidad). Verificación funcional en navegador: **NO
VERIFICADA** por falta de cuenta.

---

## E. Períodos, duración y caducidad — **NO implementado** (diseño entregado)

`academic_periods` sólo tiene `code`, `name`, `start_date`, `end_date` (anulables) e `is_active`
+ un `CHECK` de orden. **No hay** duración, estados, vencimiento ni historial de prórrogas.
`programs` no tiene duración.

El diseño completo —con las decisiones provisionales del usuario incorporadas— está en
**`docs/DISENO_PERIODOS_DURACION_Y_CADUCIDAD_2026-10-10.md`**: duración configurable por
programa, fechas efectivas por período, estados derivados, vencimiento sin borrado, prórrogas
con valor anterior/nuevo/actor/motivo, reapertura explícita, y reutilización de
`config_audit_log` (append-only) para el historial.

**Requiere una migración nueva → NO aplicada. Necesita autorización explícita.**

---

## F. Pruebas ejecutadas

| Qué | Cómo | Resultado |
|---|---|---|
| Análisis estático | `flutter analyze` (CI) | **No issues found** |
| Suite Flutter | `flutter test` (CI) | **991/991 passed** |
| Contra-prueba del fallo | CI con el fix revertido | **failure** con el error exacto |
| E2E Playwright | `e2e.yml` sobre `main` (`38054401910`) | **success** |
| Análisis local | `node devops/analizar-dart.mjs` | 223 archivos, sin errores/avisos/infos |

**`flutter test` y `flutter build web` NO corren en el sandbox local de Windows.** Medido: seis
intentos de build fallidos con `Target dart2js failed: ProcessException … CreateFile failed 231`
(`ERROR_PIPE_BUSY`). Está documentado en el propio `flutter_ci.yml` y en `e2e.yml`. La respuesta
correcta es CI, no insistir en local.

---

## G. Git

| Commit | Qué |
|---|---|
| `5f333fa` | `fix(admin): render teacher-invitation panel without bounded height` |
| `5789900` | `feat(admin): make user/role and pensum administration discoverable` |
| `baea835`, `6f84bdc`, `d23be18`, `635fe8b` | pruebas + corrección del desborde a 375 px |
| `e135960` | `ci: build the production web bundle in CI and validate it` |
| `ebc9661` | `docs: audit of the invitation fix and design for period duration/expiry` |

`HEAD == origin/main == ebc9661`. Ramas de trabajo `fix/invitar-docente-acordeon` y
`fix/cpanel-barrido-375` fusionadas y **eliminadas** (local y remoto). Los archivos sin rastrear
preexistentes quedaron **intactos**.

---

## H. Producción

| Componente | Estado verificado |
|---|---|
| Render `/salud` | **HTTP 200** · `{"estado":"ok"}` |
| Cloudflare Pages `/` | **HTTP 200** |
| Bundle público | 3 817 590 bytes · contiene `https://inces-lms-api.onrender.com` · **0** `localhost:3001` |
| Despliegue Pages | `af6b618b-b69a-49f5-a73c-977b6feeab7f` · **Production / main** |
| Migraciones | **ninguna aplicada** |
| Secretos | **ninguno creado** (se reutilizaron los de E2E) |

El bundle se compiló en CI con el flujo nuevo `web_bundle.yml` (Flutter 3.47.0, mismas
`--dart-define` de producción, validación §5.1 antes de publicar el artefacto) y se desplegó con
`wrangler pages deploy … --project-name=inces-lms --branch=main`.

**Verificación funcional en navegador de la versión publicada: NO REALIZADA** — requiere una
cuenta de prueba autorizada. Lo verificado es que la app carga, que el bundle es el correcto y
que el backend responde.

---

## I. Pendientes

1. **Bloque E (períodos/duración/caducidad)** — esperando autorización para la migración y las 5
   decisiones institucionales listadas en el diseño (§7 de ese documento).
2. **Verificación funcional en navegador** de «Invitar docente» y de la promoción de
   administradores en la versión publicada. Falta una cuenta de prueba autorizada.
3. **Deuda heredada** (no tocada esta sesión): SMTP real de Resend, validación de la cámara de
   `mobile_scanner` en dispositivo físico, D17 (lista de campos de HACER), rotación de cinco
   credenciales.
