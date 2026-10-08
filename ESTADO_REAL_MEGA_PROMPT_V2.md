# ESTADO REAL DE INCES-LMS-PROJECT — MEGA PROMPT v2

> **Fecha:** 2026-10-05 · **Commit:** `f53a3ac` · **Rama:** `main`
> **Naturaleza:** auditoría. **No se ha modificado código de producción.**
>
> Todo lo marcado 🟢 tiene evidencia ejecutable. Lo marcado ❓ **no lo he
> verificado** y lo digo en vez de inferirlo. Las secciones que **no pude cubrir**
> van al final, en §8, con la razón.

---

## 1. ESTADO GIT — punto de partida

```
Rama:    main
Commit:  f53a3ac  docs(auditoria): cierre de trazabilidad de la planilla oficial
Anteriores: 3950e77 · 4e68bc5
```

**23 entradas locales sin commitear.** Clasificadas:

| Tipo | Archivos |
|---|---|
| **Documentos nuevos** | `AUTOPROMPT_PLANILLA.md` · `PLANILLA_OFICIAL_RENDERER_DISENO.md` |
| **Documentos modificados** | `AUDITORIA_PLANILLA.md` · `ESTADO_DEL_SISTEMA.md` |
| **Page Objects modificados** | `e2e/src/pages/FlutterApp.ts` · `AulaVirtualPage.ts` |
| **Spec sin seguimiento** | `e2e/tests/aula_virtual_ciclo.spec.ts` (**rojo**) |
| **Instrumentos de diagnóstico** | `_aislado_t2/t3/t4` · `_bisect` · `_cmp_sonda_spec` · `_diag_modal` · `_explorar_dialogos` · `_instrumentado_t4_objetivo` · `_monitor_t4.ps1` |

**Ninguno se ha borrado, reseteado ni stasheado.** Los instrumentos `_*` son
**evidencia histórica de las fases de diagnóstico** y se clasifican en §6.

---

## 2. INVENTARIO REAL

| Capa | Medida |
|---|---|
| Dart (frontend) | **125 archivos** |
| TypeScript (backend `src/`) | **44 archivos** |
| Migraciones SQL | **34** |
| Especificaciones E2E | **12** |
| Documentos `.md` en raíz | **13** |

| Suite de pruebas | Archivos |
|---|---|
| Backend (`.test.ts`) | **27** |
| Flutter (`*_test.dart`) | **66** |
| Playwright | **12** |

**Arquitectura real, verificada:** Flutter Web (CanvasKit) · Fastify 5 + TypeScript
+ Zod · Supabase (PostgreSQL 17.6 + RLS) · Cloudflare R2 · Playwright.

**Nota sobre el §6 del prompt:** no he encontrado referencias vivas a FastAPI,
Jinja2 ni HTMX en el código. **Si existen en documentación histórica, es
documentación desactualizada, no una migración incompleta** — pero **no lo he
barrido exhaustivamente**, así que queda ❓.

---

## 3. MATRIZ GLOBAL

| Área | Estado | Evidencia | Riesgo |
|---|---|---|---|
| **Esquema y migraciones** | 🟢 | 34 aplicadas, **0 pendientes, 0 con deriva** | bajo |
| **RLS y esquema** | 🟢 | `Supabase CI`: **530 aserciones, 0 fallidas** | bajo |
| **Backend (tipos + pruebas)** | 🟢 | `npm run verify` | bajo |
| **Tipos Dart** | 🟢 | `analizar-dart.mjs` → **207 archivos, sin errores ni avisos** | bajo |
| **E2E (suites en `main`)** | 🟢 | **14 casos verdes** en local y CI | bajo |
| **Registro de aspirantes** | 🟢 | `POST /auth/v1/signup` → 200 y `aspirantes` 0→1 | bajo |
| **Login con cédula** | 🟡 | RPC aplicada y cliente empujado · **sin prueba E2E** | medio |
| **Asistencia QR (M7)** | 🟡 | nube ✓ · **sin validación en dispositivo físico** | medio |
| **Aula Virtual — ciclo completo** | 🔴 | spec **rojo**: `Crear y publicar` no monta | **alto** |
| **Planilla oficial PDF** | 🔴 | **no implementada** — diseño y medición hechos | medio |
| **Workflow de planilla** | ❓ | **no auditado** | — |
| **Prácticas · Egreso · Certificados** | ❓ | **no auditados** | — |
| **Responsive** | ❓ | **no auditado** | — |
| **Performance** | ❓ | **no auditado** | — |

---

## 4. LO VERIFICADO, CON SU EVIDENCIA

### 4.1 Infraestructura — 🟢

| Hecho | Evidencia |
|---|---|
| Migraciones | `apply-migrations.mjs --check` → **34 aplicadas, 0 pendientes, 0 con deriva** |
| Catálogo | 58 funciones / 52 políticas |
| Módulos | **11 filas, 8 encendidas** — apagadas `m6_asistencia`, `m7_calificaciones`, `m8_pasantias` |
| CI de esquema | **530 aserciones, 0 fallidas** |
| CI de Flutter | verde |
| E2E | **14 casos** — `export_csv` 10 · `stepper_inscripcion` 1 · `aula_virtual` 3 |

### 4.2 Arnés E2E — 🟢, con cinco trampas medidas

El bundle se descarga del artefacto `web-bundle` del CI porque **`flutter build web`
no arranca en este equipo** (`ERROR_PIPE_BUSY` 231).

**Cinco trampas, las cinco con su síntoma:** proxy que se come `127.0.0.1` ·
*safe-delete shim* · `CORS_ORIGINS` del backend manual · teardown que no vuelve ·
`tasklist /FI` con falso negativo desde Git Bash.

### 4.3 Dos hechos de CanvasKit — 🟢

- **`dispatchEvent('click')` no conmuta un `role="tab"`** — medido: 0 etiquetas nuevas vs **3** con `mouse.click` real.
- **La geometría del nodo semántico no es la del DOM** — `boundingBox()` → 0; centro de `nodos()` → 3.

### 4.4 Planilla oficial — auditoría cerrada, implementación no iniciada

| Hecho | Valor |
|---|---|
| Geometría | **612 × 792 pt · 1 página · rotación 0** |
| Las dos copias del PDF | **idénticas** — SHA-256 `eccb284a2bb0883a` |
| Etiquetas | **121 líneas** con `bbox` real |
| Líneas de escritura | **2155** horizontales |
| **Casillas `□`** | **glifos de texto, no rectángulos** — **0** rectángulos pequeños entre 433 drawings |
| Catálogo | **44 = 38 física + 6 sistema** |
| Familiares | **8 columnas físicas = 8 del catálogo** |
| Misiones | **20/20**, mismo orden, todas con «desde» |
| `mision_ribaras` | legacy — `aspirante_model.dart:178` |
| `numero_preimpreso` | catálogo ✓ · **captura NO VERIFICADA** |

**Único bloqueo de medición:** los **rectángulos de inserción**. Los `bbox` son de
las **etiquetas**; poner el dato ahí lo imprimiría **encima del rótulo**.

---

## 5. PRIORIDAD P0 — lo que el prompt pide atacar primero

| # | Tema | Estado | Qué falta exactamente |
|---|---|---|---|
| 1 | Git y protección del trabajo local | 🟢 | nada — 23 locales clasificados, sin destruir |
| 2 | Auditoría del renderer oficial | 🟢 | hecha; **falta medir rectángulos de inserción** |
| 3 | Workflow de planilla | ❓ | **no auditado** |
| 4 | Bloqueo de edición | ❓ | **no auditado** |
| 5 | Observaciones | ❓ | **no auditado** |
| 6 | Versionado | ❓ | **no auditado** |
| 7 | E2E de planilla | 🔴 | no existe |
| 8 | Aula Virtual E2E | 🔴 | **causa localizada**: el modal no monta si se pulsa con el árbol a medio montar (56 nodos monta, 39 no) |

**Sobre el 8 — y el prompt tiene razón en desconfiar de `flt-glass-pane`:**
`flt-glass-pane` **aparece en 8.049 s, sin un solo error de página ni de red.**
**Esa hipótesis está refutada por medición.** El bloqueo real es otro y está acotado.

---

## 6. ARCHIVOS EXPERIMENTALES — clasificación (§38)

| Archivo | Clasificación | Decisión |
|---|---|---|
| `_aislado_t2/t3/t4.spec.ts` | **Diagnóstico útil** | conservar hasta cerrar el bloqueo del aula |
| `_bisect.spec.ts` | **Diagnóstico útil** | ídem |
| `_cmp_sonda_spec.spec.ts` | **Diagnóstico útil** | ídem — es el comparador que encontró la causa |
| `_diag_modal.spec.ts` | **Diagnóstico útil** | ídem |
| `_explorar_dialogos.spec.ts` | **Evidencia histórica** | mide los modales del docente |
| `_instrumentado_t4_objetivo.spec.ts` | **Evidencia histórica** | del ciclo de teardown |
| `_monitor_t4.ps1` | **Artefacto obsoleto** | su instrumento dio falso negativo (`tasklist`) |

**Ninguno se borra sin autorización.** Los cinco «diagnóstico útil» **se convierten
en la base del arnés definitivo** cuando el aula cierre.

---

## 7. HALLAZGOS QUE NO SON TAREA DE ESTA FASE

Cosas que **deberían cambiarse en producción pero no son necesarias para cerrar la
auditoría**, y por eso **no las he tocado**:

1. **El renderer genérico sanea a Latin-1** y sustituye por `?` lo que no cabe (`planilla-pdf.ts:28-32`). En una planilla que se firma, **un `?` en un apellido es un problema legal**.
2. **El catálogo de `sexo` tiene 3 opciones; el papel tiene 2.** Si un aspirante elige la tercera, **la planilla no tiene dónde representarla**. Decisión de negocio.
3. **El `--limpiar` del sembrado no es incondicional** y **una limpieza detenida no deja el sistema como estaba**.
4. **`mision_ribaras` duplica en parte la rejilla `misiones`** — la migración dice *«hay que decidir cuál manda»*.

---

## 8. LO QUE **NO** HE AUDITADO — y por qué

El prompt pide 52 secciones. **Estas no las he cubierto**, y marcarlas 🟢 o 🔴 sin
medirlas sería exactamente lo que el §45 del prompt prohíbe:

| § | Área | Razón |
|---|---|---|
| 11 | **Seguridad negativa (IDOR, escalada)** | requiere ejercer la RLS con JWT reales; existe `probar-marca-nube.mjs` pero **no lo he ejecutado en esta sesión** |
| 19–22 | **Workflow, bloqueo, observaciones, versionado** | **no auditados** — no sé si existen |
| 24–26 | **Clases, asistencia, evaluaciones** | **no auditados** |
| 28–30 | **Prácticas, egreso, certificados/QR** | **no auditados** |
| 31 | **Administración** | parcial — sé que existe el cPanel de inscritos |
| 32 | **Responsive (375→1440)** | **no auditado** |
| 33 | **Performance** | **no auditado** |
| 35 | **E2E integral del ciclo de vida** | no existe |

**No los declaro pendientes ni completados: los declaro ❓ NO VERIFICADO.** Y hay
una razón de fondo: **el aula virtual está rojo**, y auditar los módulos que
dependen de ella antes de cerrarla daría estados que habría que rehacer.

---

## 9. BACKLOG PRIORIZADO

| ID | Tarea | Causa | Criterio de aceptación | Estado |
|---|---|---|---|---|
| **P0-1** | Cerrar el bloqueo del aula | se pulsa con el árbol a medio montar | `aula_virtual_ciclo` **verde, 2 corridas seguidas, `--retries=0`** | 🔴 |
| **P0-2** | Medir rectángulos de inserción | los `bbox` son de etiquetas | tabla de `x,y,w,h` por campo, **medida** | 🔴 |
| **P0-3** | Auditar workflow de planilla | no verificado | §19–22 del prompt respondidas | ❓ |
| **P1-1** | `PlanillaOficialData` + adaptador | contrato cerrado | interfaz + adaptador probado **sin PDF** | 🟡 diseño |
| **P1-2** | Renderer oficial | depende de P0-2 | PDF 612×792, 1 página, sin solape | 🔴 |
| **P1-3** | Prueba E2E del login con cédula | RPC sin ejercer | casos A–E del prompt anterior | 🟡 |
| **P2** | Seguridad negativa · responsive · performance | no auditados | medición, no opinión | ❓ |

---

## 10. BLOQUEOS REALES — solo los reales

1. **Los rectángulos de inserción no están medidos.** Sin ellos el renderer **no se puede escribir sin inventar coordenadas**. Las 2155 líneas **ya están extraídas**: es una corrida.
2. **El aula virtual está rojo.** La causa está acotada —**el modal no monta con el árbol a medio montar, 56 nodos monta y 39 no**— pero **no corregida**.
3. **Cuatro decisiones de negocio abiertas**, que ninguna medición resuelve: **el `Otro` de `sexo`** · **qué fecha es `FECHA`** · **quién captura el N.º PREIMPRESO** · **qué pasa con una misión 21**.

**No hay más.** No invento bloqueos.

---

## 11. SIGUIENTE ACCIÓN EXACTA

**No empiezo a programar** — el prompt lo prohíbe y coincido: el aula está rojo y
la planilla no tiene coordenadas de inserción.

**Propongo este bloque, en este orden:**

1. **Cerrar el aula (P0-1).** La causa está medida: esperar a que el árbol **deje de crecer** en vez de a que aparezca un rótulo. Cambio acotado a `abrirPestana`, validación `2×4/4` con `--retries=0`, y regresión de las tres suites.
2. **Medir los rectángulos de inserción (P0-2).** Emparejar cada etiqueta con su línea de escritura. **Una corrida con PyMuPDF.**
3. **Auditar el workflow de planilla (P0-3).** Buscar si existen estados, bloqueo, observaciones y versionado — **antes** de diseñarlos.

**Con eso, `PlanillaOficialData` y el renderer pasan a 🟢 y el backlog P1 se puede
atacar sin volver a investigar.**

**Y una advertencia sobre el alcance:** el prompt pide cubrir 52 secciones —
prácticas, egreso, certificados, responsive, performance, seguridad negativa. **Eso
no es una sesión.** Priorizarlo todo equivale a no priorizar nada; el §47 del propio
prompt pide un backlog dinámico, y el backlog de §9 es el que la evidencia sostiene
hoy.
