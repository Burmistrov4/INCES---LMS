# CONTRATO E-2 DEFINITIVO — Planilla Oficial INCES

> **Fase:** diseño funcional cerrado. **E-2 NO implementado.** Commit `f53a3ac`.
> **Cambios de producto: 0.**
>
> Cada regla lleva su clasificación, y **no se mezclan**:
>
> | Etiqueta | Significa |
> |---|---|
> | **[EVIDENCIA]** | leído del código, con archivo y línea |
> | **[DERIVABLE]** | la cadena estructural existe; sólo falta componerla |
> | **[PROPUESTA]** | diseño técnico coherente, **no respaldado por documentación académica** |
> | **[ACADÉMICA]** | **requiere decisión del equipo/INCES** — no se puede deducir del código |

---

## 1. LO CONFIRMADO — no volver a investigarlo

| Hecho | Evidencia |
|---|---|
| Seguridad negativa de Planilla | **CERRADA** — 10/10 estados HTTP correctos |
| IDOR | **NO REPRODUCIDO** — `?usuarioId=B` no altera la identidad |
| RLS | **NO PROBADA** — `exigirAdmin()` cortó antes; **no declararla medida** |
| Aula Virtual | **NO REPRODUCIDO** directamente |
| Renderer oficial | **aislado, 6/6 pruebas**, 0 imports, 0 rutas |
| Campos oficiales | **38/38 trazados** · misiones **20/20** · familia **8 × 5** |
| Máquina de estados | **NO EXISTE** · observaciones **NO** · versionado **NO** |
| Cadena académica | `auth.users → enrollments → sections → schedule_slots → classrooms` **[EVIDENCIA]** |
| PROYECTO | `aspirantes.program_id → programs` **[EVIDENCIA]** |

**No hace falta ninguna migración** para obtener HORARIO ni EIS. **La relación estudiante-sección ya existe** (`enrollments`, `init.sql:65-72`).

---

## 2. ACTORES Y PERMISOS

### 2.1 Capacidad técnica **hoy** — **[EVIDENCIA]**

| Actor | Puede |
|---|---|
| **Aspirante** | guardar su planilla (`PUT /yo/planilla`) · descargar la suya (`GET /yo/planilla/{pdf,xlsx}`) |
| **Admin** | descargar la de **cualquiera** (`/inscripcion/planilla/:id/{pdf,xlsx}`, `exigirAdmin` + RLS `admin_all`) |
| **Docente** | **nada** — cero coincidencias de UI ni ruta |

### 2.2 Autorización académica — **[ACADÉMICA]**

**[PROPUESTA]** y es la que recomiendo aprobar:

| Acción | Aspirante | Docente | Admin |
|---|:---:|:---:|:---:|
| Capturar/editar datos | ✅ en BORRADOR y OBSERVADA | ❌ | ❌ |
| Enviar | ✅ | ❌ | ❌ |
| Observar | ❌ | ❌ | ✅ |
| Aprobar | ❌ | ❌ | ✅ |
| Descargar oficial | ✅ (la suya) | ❌ | ✅ (cualquiera) |

**Por qué el docente queda fuera:** no hay **ninguna** evidencia de que intervenga, y añadirlo sería **inventar un rol**. **La planilla es un trámite entre el aspirante y administración.**

---

## 3. WORKFLOW DEFINITIVO — **[APROBADA]**

**No existe hoy** — es funcionalidad nueva. Lo de abajo es diseño, no hecho.

| Estado | Edita | Avanza | Observa | Aprueba | Descarga oficial |
|---|:---:|:---:|:---:|:---:|:---:|
| **BORRADOR** | aspirante | aspirante (enviar) | — | — | **no** |
| **ENVIADA** | 🔒 | admin (aprobar u observar) | admin | admin | **sí** |
| **OBSERVADA** | aspirante | aspirante (reenviar) | — | — | no |
| **REENVIADA** | 🔒 | admin | admin | admin | sí |
| **APROBADA** | 🔒 **definitiva** | — | — | — | **sí** |

**Reglas:**

1. **`ENVIADA → APROBADA` directo** si el admin no observa ✓
2. **Al observar**, el admin **deja un motivo** (texto) y el aspirante lo ve
3. **En OBSERVADA vuelven a ser editables todos los campos del catálogo** — no sólo el observado: el aspirante puede descubrir otro error, y bloquearlo obligaría a observarlo otra vez
4. **APROBADA queda bloqueada para siempre.** Cambiarla exigiría una decisión explícita, **no prevista hoy**
5. **Se genera una versión al ENVIAR y al REENVIAR** — no en cada guardado
6. **El PDF oficial se genera desde ENVIADA en adelante.** **En BORRADOR no se genera**: un documento «oficial» de un borrador **no debería existir**
7. **Las versiones anteriores se conservan** — permiten demostrar qué se aprobó

---

## 4. FUENTES DE DATOS — matriz definitiva

| Campo | Fuente | Cadena | Estado | Decisión |
|---|---|---|---|---|
| **PROYECTO** | `programs` | `aspirantes.program_id → programs.code` | 🟡 **[DERIVABLE]** | **[APROBADA]** `programs.code` |
| **HORARIO** | `schedule_slots` | `aspirante → enrollments(ENROLLED) → sections → schedule_slots` | 🟡 **[DERIVABLE]** | formato (§5) |
| **EIS** | `classrooms` | `… → schedule_slots.classroom_id → classrooms.name` | 🟡 **[DERIVABLE]** | **[APROBADA]** `classrooms.name` representa EIS |
| **FECHA** | **ninguna** | — | 🔴 | **[APROBADA]** fecha de ENVÍO |
| **Identidad** | catálogo | `datos.primer_nombre ?? identidad ?? split(nombres)` | 🟢 | — |
| **Familia** | catálogo | `datos_planilla.familiares[]` | 🟢 | — |
| **Misiones** | catálogo | `datos_planilla.misiones` | 🟢 | — |

---

## 5. HORARIO — formato determinista

**Cadena [EVIDENCIA]:**
```
aspirantes.user_id → enrollments.student_id          (init.sql:65)
enrollments.status = 'ENROLLED'                       (init.sql:68)
enrollments.section_id → sections.id                  (init.sql:66)
sections.id → schedule_slots.section_id               (cuadrante:662)
schedule_slots.day_of_week (1..6) · block (1..12) · turno (generado)   (671-674)
```

**Reglas:**

1. **Sólo `ENROLLED` cuenta como matrícula activa.** `WAITLISTED`, `PENDING_BID` y `DROPPED` **no tienen horario** — no están cursando.
2. **Puede haber varios `schedule_slots`** → el campo es **multilínea**.
3. **Orden determinista:** `day_of_week` asc, luego `block` asc. **Sin esto, dos generaciones del mismo alumno podrían diferir.**
4. **Formato [PROPUESTA]:** `LUNES B1-B2` por línea, con el día en mayúsculas y el bloque abreviado `B<n>`.

**[ACADÉMICA]** — ¿es ese el formato que el INCES espera, o el papel admite texto libre?

---

## 6. ESPACIO INTEGRAL SOCIALISTA — **[ACADÉMICA]**

`schedule_slots.classroom_id → classrooms.name`, y `classrooms` se documenta como **«aula, taller o zona»** (`tipos.ts:274`).

**Técnicamente derivable ✓. Semánticamente NO demostrado.** Que «aula/taller/zona» **sea** el «ESPACIO INTEGRAL SOCIALISTA» del papel es **plausible** —el término es del vocabulario del INCES— pero **no hay documentación que lo afirme.**

**No propongo ninguna entidad nueva ni migración:** si la equivalencia se confirma, **la cadena ya sirve tal cual**.

---

## 7. FECHA — **DECISIÓN APROBADA**

> **CORRECCIÓN DE CLASIFICACIÓN.** En la versión anterior de este contrato, la
> regla «FECHA = fecha de envío» aparecía sin marcar. **El código NO demuestra esa
> semántica** — la demuestra el razonamiento sobre el papel. **Su clasificación
> correcta es `[ACADÉMICA]`, no `[EVIDENCIA]` ni `[DERIVABLE]`:** es una
> **propuesta que el equipo debe aprobar**, no un hecho que se haya medido.

### Qué significaría exactamente, si se aprueba

| Aspecto | Regla propuesta |
|---|---|
| **Significado** | la fecha en que el aspirante **formalizó** la planilla que se imprime |
| **Campo que la representa** | el timestamp del **envío** de la versión que se genera — **no existe hoy**; nacería con la máquina de estados |
| **Si se reenvía** | la fecha **cambia a la del último reenvío**, porque es la versión vigente la que se imprime |
| **Tras APROBAR** | **se congela**: la versión aprobada no se reenvía, así que su fecha no cambia |
| **Por qué es compatible con el papel** | el papel la sitúa en el encabezado junto a N.º PREIMPRESO y PROYECTO — la zona de lo que **se formaliza al presentar** el documento |

**Las otras dos candidatas razonables fallan por motivos concretos:** `created_at`
**es técnica** —mide cuándo se creó la ficha, no cuándo se presentó— y la fecha de
generación **haría que dos copias del mismo documento dijeran cosas distintas**,
que es exactamente lo que un documento oficial no debe hacer.

**Comparadas las cinco candidatas:**

| Candidata | Qué significa | ¿Es «FECHA» del papel? |
|---|---|---|
| `aspirantes.created_at` | cuándo se creó la ficha | **No** — es técnica, no académica |
| fecha de inscripción | **no existe como columna** | — |
| inicio del período | cuándo empieza el lapso | **No** — es del lapso, no del trámite |
| fecha de generación | cuándo se pidió el PDF | **No** — cambia en cada descarga |
| fecha de envío/aprobación | cuándo se formalizó | **Candidata fuerte** |

**El papel usa «FECHA» en el encabezado, junto a N.º PREIMPRESO y PROYECTO — es decir, en la zona de lo que se formaliza al presentar el documento.**

**[APROBADA] — decisión funcional cerrada:**

> **`FECHA` = la fecha de ENVÍO de la versión que se imprime.**
>
> **Por qué:** es la única que **representa un acto académico** —cuándo el aspirante presentó su planilla— y **es estable**: si se imprime dos veces la misma versión, sale la misma fecha. Las otras dos candidatas razonables fallan: `created_at` es técnica, y la de generación **haría que dos copias del mismo documento dijeran cosas distintas**.

**Y una consecuencia que conviene ver:** con esta regla, **`FECHA` no se puede generar en BORRADOR** — coherente con que el PDF oficial tampoco.

---

## 8. IDENTIDAD

**[EVIDENCIA]** `planilla-oficial-valores.ts:130-133`:

```
primerNombre  = datos.primer_nombre  ?? identidad.primer_nombre  ?? nombres.split(' ')[0]
segundoNombre = datos.segundo_nombre ?? identidad.segundo_nombre ?? nombres.split(' ').slice(1)
```

| Nivel | Qué es |
|---|---|
| **Canónica** | `datos_planilla` — el catálogo, **con los cuatro campos** |
| **Materializada** | `aspirantes.nombres` / `apellidos` |
| **Fallback** | **partir por espacios** |

**Riesgo real:** un nombre compuesto tipo `MARÍA JOSÉ` se parte como `MARÍA` + `JOSÉ` — **correcto por casualidad**. Pero `JUAN CARLOS MARÍA` daría `JUAN` + `CARLOS MARÍA`. **El fallback es aceptable sólo si el catálogo está relleno.**

**[PROPUESTA]** En el documento oficial, **exigir los cuatro campos del catálogo** antes de generar, y **no depender del fallback**.

---

## 9. FAMILIA Y DIVERSIDAD — contratos

**Familia [EVIDENCIA]:** 8 categorías = 8 columnas físicas ✓ · **5 filas** · orden fijo del catálogo.

**[PROPUESTA]** Filas vacías **se imprimen vacías** (no se omiten — el papel tiene 5 líneas). Más de 5 → **se corta con aviso**, no se añade página.

**Diversidad funcional y estado civil [EVIDENCIA]:** **texto libre** en el modelo; **casillas tipificadas** en el papel.

**[PROPUESTA]** **Imprimir el texto junto a las casillas, sin marcarlas.** El dato no se pierde ni se falsea.

**[APROBADA]** se mantiene texto libre inicialmente; no se modifica el esquema.

---

## 10. OFICIAL vs GENÉRICA — **DECISIÓN: COEXISTIR** [APROBADA]

| | Genérico | Oficial |
|---|---|---|
| Resuelve | **exportación administrativa** | **documento de trámite** |
| Campo nuevo del catálogo | **aparece solo** | no tiene dónde ir |
| Usuario | administración | aspirante + admin |

**Justificación:** el genérico **está en uso** y tiene una propiedad documentada en su propia cabecera —*si el CFS añade un campo, la planilla lo trae sin tocar el archivo*—. **Sustituirlo tiraría trabajo que funciona y perdería esa propiedad.** Y si el oficial falla, **el genérico queda como salida**.

**Riesgo:** dos salidas confunden si no se rotulan. **[PROPUESTA]** Nombrarlas explícitamente: **«Planilla oficial»** y **«Exportar datos»**.

---

## 11. CONTRATO TÉCNICO E-2 — **[APROBADO]**

```
Actores:          aspirante (la suya) · admin (cualquiera) · docente NO
Precondiciones:   sesión · ficha de aspirante · estado ≥ ENVIADA
Estados:          BORRADOR → ENVIADA → {APROBADA | OBSERVADA → REENVIADA → …}
Permisos:         ver §3
Datos requeridos: datos_planilla + program_id + enrollments(ENROLLED) + schedule_slots
Fuentes:          ver §4
Derivaciones:     PROYECTO=programs · HORARIO=schedule_slots · EIS=classrooms · FECHA=envío
Validación:       los 4 nombres del catálogo presentes; ficha con program_id
Edición:          sólo en BORRADOR y OBSERVADA
Observación:      admin + motivo obligatorio
Aprobación:       admin
Versionado:       una versión por ENVÍO/REENVÍO; anteriores conservadas
PDF oficial:      desde ENVIADA; generado bajo demanda, NO almacenado
Renderer:         planilla-oficial-pdf.ts — SIN MODIFICAR
Template:         assets/planilla-oficial-template.pdf — resolver ruta en deploy
Errores:          404 SIN_FICHA · 403 sin rol · 409 estado no permite generar
Auditoría:        [APROBADA] approved_by · approved_at · versión aprobada · motivo/observación
Seguridad:        A no lee la de B (medido) · A no aprueba (propuesto)
Trazabilidad:     Frontend → Endpoint → Auth → Authz → Handler → Servicio →
                  Valores → Renderer → Template → PDF
Endpoints:        GET /api/v1/yo/planilla/oficial.pdf
                  GET /api/v1/inscripcion/planilla/:id/oficial.pdf
                  — mismo prefijo y guardia que los existentes
```

---

## 12. MATRIZ FINAL DE DECISIONES

| Decisión | Resultado | Estado |
|---|---|---|
| Actor generador | aspirante + admin; docente fuera | **[APROBADA]** |
| Workflow | 5 estados, `ENVIADA→APROBADA` directo | **[APROBADA]** |
| PROYECTO | `programs.code` | **[APROBADA]** |
| HORARIO | derivable; formato `LUNES B1-B2` | **[APROBADA]** |
| EIS | `classrooms.name` | **[APROBADA]** |
| **FECHA** | **fecha de ENVÍO** | **[APROBADA]** |
| Identidad | catálogo, 4 campos | **[EVIDENCIA]** |
| Familia | 8 × 5, orden fijo | **[EVIDENCIA]** |
| Diversidad / estado civil | texto libre, sin marcar casillas | **[APROBADA]** |
| Oficial vs genérica | **coexisten** | **[APROBADA]** |

---

## 13. RIESGOS RESIDUALES

1. **La ruta del template en despliegue** — 4 candidatas, funciona en tests por `cwd`. **Sin verificar en producción.**
2. **`aspirantes.user_id` siempre poblado** — si hubiera fichas sin él, **no tendrían horario**. **No verificado.**
3. **El fallback de nombres** — pérdida silenciosa con nombres compuestos si el catálogo está vacío.
4. **RLS no probada** — los casos negativos los cortó Fastify.

---

## 14. VEREDICTO

# E-2 LISTO PARA IMPLEMENTAR

Las seis decisiones funcionales pendientes quedan **APROBADAS expresamente por el equipo del proyecto** para el Classroom a medida del **CFG Nacional de Soldadura del INCES**.

| # | Decisión aprobada | Estado |
|---|---|---|
| 1 | **FECHA = fecha de ENVÍO** de la versión que se imprime | **APROBADA** |
| 2 | **PROYECTO = `programs.code`** | **APROBADA** |
| 3 | **EIS = `classrooms.name`** derivado del horario/matrícula | **APROBADA** |
| 4 | **Workflow:** `BORRADOR → ENVIADA → OBSERVADA → REENVIADA → APROBADA`, con `ENVIADA → APROBADA` directo cuando no hay observación | **APROBADA** |
| 5 | **Diversidad funcional y estado civil permanecen como texto libre** inicialmente; no se modifica el esquema por esta decisión | **APROBADA** |
| 6 | **Auditoría de aprobación:** `approved_by`, `approved_at`, versión aprobada y motivo/observación cuando corresponda | **APROBADA** |

### Reglas cerradas para E-2

- **Aspirante:** captura/edición en BORRADOR y OBSERVADA, envío/reenvío y descarga de su planilla oficial cuando el estado lo permita.
- **Admin:** observa, aprueba y descarga planillas de cualquier aspirante autorizado.
- **Docente:** queda fuera del flujo de Planilla Oficial; no se inventa una intervención que el modelo actual no sustenta.
- **HORARIO:** sólo matrículas `ENROLLED`, multilínea, ordenada por día y bloque.
- **PROYECTO:** `aspirantes.program_id → programs.code`.
- **EIS:** `schedule_slots.classroom_id → classrooms.name`.
- **FECHA:** fecha del envío de la versión vigente; queda congelada al aprobar.
- **PDF oficial:** coexistirá con la exportación genérica; no sustituirá el flujo administrativo existente.
- **Versionado:** una versión por ENVÍO/REENVÍO; las anteriores se conservan.
- **APROBADA:** queda bloqueada.

**Estado funcional:** cerrado.
**Estado técnico:** listo para implementación E-2.
**Implementación E-2:** todavía NO iniciada.

## 15. ESTADO

```
Cambios de producto: 0 · Migraciones: 0 · Endpoints: 0 · Frontend: 0 · Renderer: 0
Documento: CONTRATO_E2_PLANILLA_OFICIAL.md (esta edición)

rama: main...origin/main · HEAD: f53a3ac
modificados: 4 · no rastreados: 21
```

**Todo el trabajo local preservado.** Sin `reset`, `clean`, `restore` ni `stash`.

**STOP.** No se implementa E-2 sin autorización explícita.
