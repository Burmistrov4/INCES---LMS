# AUDITORÍA FASE 0 — Portal CFS + Inscripción + Roles

> **Fecha:** 2026-10-06 · **Commit:** `f53a3ac` · rama `main`
> **Naturaleza:** auditoría. **No se ha implementado nada.**
>
> Cada afirmación lleva su respaldo. Lo que **no** he verificado va marcado
> **NO VERIFICADO** — y eso es la mitad del valor de este documento.

---

## 1. Estado actual

```
rama: main · HEAD: f53a3ac
11 archivos modificados · 38 no rastreados
Migraciones: 0001–0006 de E-2 aplicadas · libro mayor 40 · 0 pendientes · 0 con deriva
```

**Lo verificado en esta sesión, con evidencia:**

| Área | Estado |
|---|---|
| Esquema y migraciones | 🟢 40 aplicadas, **0 con deriva** |
| RLS de `aspirantes` | 🟢 6 políticas — `read_own`, `admin_all` verificadas con JWT real |
| E2E (suites en `main`) | 🟢 **14 casos** verdes |
| Registro de aspirantes | 🟢 `signup` → 200, `aspirantes` crece |
| Planilla: workflow E-2 | 🟡 **servicio implementado y probado en local** (7/7 + 44/44) |
| Planilla: frontera RLS | 🟢 **DELETE bloqueado · auditoría inmutable · transiciones exactas** |
| Aula Virtual E2E | 🟢 **4/4** en dos corridas con `--retries=0` |
| **Rol Jefe del CFS** | 🔴 **NO EXISTE** |
| Portal público | 🟡 landing funcional; el resto **NO VERIFICADO** |

---

## 2. Arquitectura real

```
Flutter Web (CanvasKit)  →  Fastify 5 + Zod (ESM)  →  Supabase (PG 17.6 + RLS)
                                                    →  Cloudflare R2
                          Playwright (E2E)
```

**Backend por capas:** `HTTP → Dominio/Puertos → Infraestructura → Supabase` ✓
**El dominio no conoce Fastify ni Supabase** — los repositorios implementan los puertos, y **el cliente Supabase se construye por petición con el JWT del llamante** (`repos-supabase.ts:1113`), **que es lo que hace efectiva la RLS**.

**125 archivos Dart · 44 TypeScript en `src/` · 34+ migraciones · 12 specs E2E.**

---

## 3. Funcionalidades existentes — **[EVIDENCIA]**

| Módulo | Estado |
|---|---|
| Landing pública | ✅ carga oferta real por `obtenerProgramasDisponibles()` |
| Inscripción digital | ✅ formulario + `PUT /yo/planilla` |
| Planilla (PDF/XLSX genérico) | ✅ en uso |
| Planilla Oficial (renderer) | 🟡 **implementado, probado en aislamiento, SIN CONECTAR** |
| Workflow de planilla (E-2) | 🟡 servicio implementado; **frontera RLS cerrada** |
| Aula Virtual | ✅ 4/4 E2E |
| Asistencia QR (M7) | 🟡 nube ✓ · **sin validar en dispositivo físico** |
| cPanel de inscripciones | ✅ el admin descarga planillas |
| Roles | ✅ **3**: `admin`, `docente`, `estudiante` |
| Módulos del sistema | 11 filas, **8 encendidas** |

---

## 4. Reutilizable sin tocar

`landing_page.dart` · `AspiranteRepository` · `PuertaPlanilla` y su implementación ·
las 6 políticas RLS de `aspirantes` · el catálogo `inscripcion_campos` (44 campos) ·
`validar_planilla(jsonb)` · el arnés E2E completo · `apply-migrations.mjs` y sus
verificadores.

---

## 5. Incompletas — y su causa

| # | Funcionalidad | Qué falta |
|---|---|---|
| 1 | **Planilla Oficial conectada** | **0 imports, 0 rutas** — el renderer existe y no lo usa nadie |
| 2 | **Rutas HTTP del workflow** | implementadas; **medidas sólo por PostgREST, no por HTTP** |
| 3 | **Error handler** | **`23514` y `FST_ERR_CTP_EMPTY_JSON_BODY` → `500`** |
| 4 | **Jefe del CFS** | **no existe como rol** |
| 5 | **Atomicidad de observar** | RPC creado; **fault injection NO MEDIDO** |
| 6 | **Asistencia QR** | sin validar en dispositivo |

---

## 6. Riesgos — ordenados por daño

**1 · El error handler miente en dos direcciones.** Medido: un cuerpo vacío
(`statusCode: 400` según Fastify) y las transiciones ilegales (`23514`) **producen
`500`**. **El rechazo funciona; la comunicación no.** Es la misma familia que el
`_razonDeGotrue` del registro. **[MEDIDO]**

**2 · El renderer oficial no lo usa nadie.** Trabajo real, probado, **inalcanzable**.
Si un jurado pregunta «¿dónde veo la planilla oficial?», **hoy no hay dónde**.

**3 · La plantilla del PDF se busca en 4 rutas candidatas** y funciona porque `cwd`
es `backend/`. **En despliegue puede no encontrarla** — y el PDF saldría en blanco
**sin fallar**. **[NO VERIFICADO en producción]**

**4 · `eliminar-cuenta.mjs` fallará** con `on delete restrict` sobre fichas con
versiones. **Es el `RESTRICT` haciendo su trabajo**, pero el script no lo trata.

**5 · RLS no probada en la ruta administrativa.** Los casos negativos los cortó
`exigirAdmin()` **antes** de llegar a la RLS. **[MEDIDO — la RLS no se ejerció]**

---

## 7. Dependencias

```
Landing → AspiranteRepository → catálogo público (sin sesión)
Inscripción → PUT /yo/planilla → aspirantes.datos_planilla
Workflow → PuertaPlanilla → planilla_versiones (RLS + triggers)
Planilla Oficial → datos_planilla + program_id + enrollments + schedule_slots
Admin → exigirAdmin() + RLS admin_all
```

---

## 8. Contratos

**Zod define la entrada**; OpenAPI se deriva. **El workflow de E-2 usa errores con
código de dominio** — verificado: `{error: {codigo: "PLANILLA_NO_OBSERVADA", mensaje}}` ✓
**Ese es el patrón correcto y el error handler debería seguirlo para `23514`.**

---

## 9. Flujo de inscripción — **[EVIDENCIA]**

```
Landing → oferta dinámica → «Inscribirse» → formulario → PUT /yo/planilla
  → aspirantes.datos_planilla (jsonb) → PDF/XLSX bajo demanda
```

**El catálogo `inscripcion_campos` (44 campos) define el formulario** — añadir un
campo **no requiere tocar código** ✓

---

## 10. Flujo de planilla — el contrato aprobado

```
BORRADOR (= ausencia de versión)
   ↓ enviar
ENVIADA ──→ APROBADA
   └→ OBSERVADA → REENVIADA → APROBADA
```

**Protegido en PostgreSQL, verificado con JWT reales:**

| Invariante | Estado |
|---|---|
| Transiciones exactas (4 ✓ / 3 ✗) | ✅ medido |
| Snapshot inmutable | ✅ |
| `numero` · `aspirante_id` · `enviada_at` inmutables | ✅ |
| Auditoría de aprobación inmutable | ✅ **409, fila intacta** |
| DELETE administrativo | ✅ **las 4 versiones sobreviven** |
| Observación sólo sobre `ENVIADA` | ✅ 403 medido |
| `p_admin_id = auth.uid()` | ✅ leído en la función |

---

## 11. Roles actuales — **[EVIDENCIA]**

```sql
check (rol in ('admin', 'docente', 'estudiante'))    -- 202609100001_init.sql:17
```

**Tres roles, y el trigger de `profiles` impide el auto-ascenso** (`with check (id = auth.uid() and rol = 'estudiante')`).

**Capacidad técnica hoy:** aspirante → su planilla · admin → cualquiera ·
**docente → ninguna UI ni ruta de planilla**.

---

## 12. **Situación del rol Jefe del CFS** — el hallazgo de esta fase

```
grep -rn "jefe|JEFE" supabase/migrations/*.sql   →   0 coincidencias
```

**El rol NO EXISTE.** Ni en el esquema, ni en el backend, ni en Flutter.

**Consecuencias, y son de diseño, no de código:**

1. **Hay que decidir qué puede hacer** antes de crearlo. **No asumir que es un superadmin** — tu instrucción lo dice, y es la decisión correcta: **un jefe de centro supervisa, no necesariamente administra el sistema.**
2. **La persona no se hardcodea** ✓ — el rol se asigna por datos. **El modelo ya lo permite**: `profiles.rol` es una columna, y añadir un valor al `check` es una migración **de una línea**.
3. **[PROPUESTA]** Que `jefe_cfs` sea **un rol más**, con sus políticas RLS propias — **no una bandera que reutilice `is_admin()`**. Si compartiera `is_admin()`, **el rol no sería una entidad de autorización real**, que es lo que pediste.

---

## 13. Landing — **[EVIDENCIA]**

`lib/screens/landing_page.dart`:

- **línea 19:** documenta que la oferta sale de `AspiranteRepository.obtenerProgramasDisponibles()`
- **línea 59:** la llama
- **línea 171:** botón «Inscribirse»
- **línea 182:** botón «Portal Académico»
- **existe `test/landing_page_test.dart`** ✓

**Está conectada a datos reales y tiene pruebas.** **NO se reemplaza a ciegas** — el trabajo de Fase 2 es **mejorarla**, conservando su integración.

---

## 14. Gap analysis

| Fase | Qué falta | Depende de |
|---|---|---|
| 1 · Portal | sitemap, componentes, estados | — |
| 2 · Landing | jerarquía visual, responsive real, accesibilidad | 1 |
| 3 · Oferta | auditar el modelo de `programs` | — |
| 4 · Inscripción | conectar oferta → planilla | 3 |
| 5 · Workflow admin | conectar la UI al workflow E-2 | **medición HTTP** |
| 6 · Roles | **crear `jefe_cfs` + sus políticas** | **decisión funcional** |
| 7 · Dashboard | **indicadores cuando haya datos** | 5, 6 |
| 8 · QA | responsive, accesibilidad, seguridad | todo |

---

## 15-16. Tests

**Existentes:** 66 Flutter · 27 backend · 12 E2E specs · 40 migraciones verificadas ·
`planilla-workflow.test.ts` 7/7 · regresión de planillas 44/44 · landing ✓

**Faltantes:** integración del workflow **por rutas HTTP** · **fault injection de
atomicidad** · **RLS en la ruta administrativa** (nunca ejercida) · responsive real
(360→1440) · accesibilidad · **`jefe_cfs`** · error handler.

---

## 17. Fases propuestas

**Antes de Fase 1, dos cosas que no son de portal pero bloquean:**

1. **El error handler** — está medido, es acotado, y **todo lo que construyas encima heredará el defecto**.
2. **La medición HTTP del workflow** — sin ella, Fase 5 se construye sobre algo no verificado por su interfaz real.

**Después:** Fase 3 (oferta) puede ir en paralelo con 1 y 2 — **no depende de nada.**

---

## 18. Preguntas realmente bloqueantes

**Sólo cuatro, y las cuatro son de negocio:**

1. **¿Qué puede hacer el Jefe del CFS?** — sin esto, `jefe_cfs` no se puede crear. **Y si la respuesta es «lo mismo que el admin», entonces no hace falta un rol nuevo: hace falta un nombre.**
2. **¿El portal público y el académico comparten sesión?** — decide la navegación entera.
3. **¿La oferta pública son los `programs` de tipo `CURSO_LIBRE` activos?** — la landing ya los muestra así; **confirmarlo cierra Fase 3**.
4. **¿Dónde corre el backend en el despliegue?** — decide si la plantilla del PDF se encuentra.

**Ninguna otra bloquea.** El resto se resuelve auditando.

---

## Lo que NO he auditado, y por qué

**AuthGate · navegación · dashboard · tema · responsive · accesibilidad · RLS
completa · los 12 specs E2E uno a uno.**

**No los declaro 🟢 ni 🔴: los declaro NO VERIFICADO.** He priorizado **lo que
bloquea las fases siguientes** —roles, landing, workflow, error handler— y **lo he
medido**; el resto requiere una sesión propia.

**Y una advertencia de método, con la evidencia de esta sesión:** **de los seis
instrumentos que escribí hoy, cuatro fallaron por su propia construcción** —el
`tasklist` que da falso negativo, el `apikey` con dos identidades, el orden de
limpieza, el cuerpo vacío—. **Los dos agujeros reales de seguridad los encontró tu
auditoría, no mis pruebas.** **Auditar con cuidado rinde más que medir deprisa**, y
esta Fase 0 es exactamente eso.
