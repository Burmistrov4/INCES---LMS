# FASE 0.5 — Cierre de bloqueadores arquitectónicos

> **Fecha:** 2026-10-07 · **Commit base:** `f53a3ac` · **Naturaleza:** auditoría + cierre medido de E1/E2.
> **Actualización:** el bloque E y el defecto E1 del workflow sí fueron corregidos y verificados; no se ha implementado `jefe_cfs`, Landing, RLS ni cambios de navegación.
>
> Cada bloque cierra con **evidencia**, `NO VERIFICADO` o `DECISIÓN PENDIENTE`.
> **No hay «cerrado por inferencia».**

---

## BLOQUE A — Jefe del CFS

### Evidencia

```sql
check (rol in ('admin', 'docente', 'estudiante'))   -- 202609100001_init.sql:17
```

**`grep -rn "jefe|JEFE" supabase/migrations/*.sql` → 0 coincidencias.** El rol **no existe**: ni en el esquema, ni en el backend, ni en Flutter.

**Y `is_admin()` es la única guardia de rol administrativo** — todas las rutas de administración pasan por ella.

### Hallazgo

**No hay nada que reasignar: `jefe_cfs` no le quita capacidades a nadie porque no existe.** La pregunta real **no es «qué le quito al admin»** sino **«qué necesita un jefe de centro que hoy nadie tiene»**.

### Matriz propuesta — **[PROPUESTA]**

| Capacidad | admin | **jefe_cfs** | docente | estudiante |
|---|:---:|:---:|:---:|:---:|
| Ver inscripciones del centro | ✅ | ✅ | ❌ | ❌ |
| Ver planillas de aspirantes | ✅ | ✅ | ❌ | ❌ |
| **Observar** una planilla | ✅ | ✅ | ❌ | ❌ |
| **Aprobar** una planilla | ✅ | ✅ | ❌ | ❌ |
| Gestionar el catálogo de campos | ✅ | ❌ | ❌ | ❌ |
| Gestionar usuarios y roles | ✅ | ❌ | ❌ | ❌ |
| Gestionar programas y secciones | ✅ | ❌ | ❌ | ❌ |
| Ver su propia planilla | — | — | — | ✅ |
| Aula Virtual (sus secciones) | ✅ | ❌ | ✅ | ✅ |

**El criterio que la sostiene:** **el jefe del CFS es el responsable académico del centro, no el administrador del sistema.** Supervisa el trámite de inscripción —**ve, observa, aprueba**— y **no toca la configuración**: ni el catálogo, ni los usuarios, ni los programas.

**Y eso es exactamente lo que pediste: `jefe_cfs` NO es superadmin.** Si lo fuera, **el rol no aportaría nada** — sería un segundo nombre para `admin`.

### Decisión recomendada

**Crear `jefe_cfs` como un valor más del `check`, con `is_jefe_o_admin()` propia** — **no reutilizando `is_admin()`**. Razón: si compartiera la función, **las políticas no distinguirían los dos roles**, y entonces **el rol no sería una entidad de autorización real**.

**La persona no se hardcodea** ✓ — `profiles.rol` es una columna; asignar o revocar es un `UPDATE`.

### NO implementar todavía

Nada de este bloque. **Falta confirmar la matriz** — y es `DECISIÓN PENDIENTE` del propietario.

---

## BLOQUE B — Sesión pública / académica

### Evidencia

**No hay `GoRouter` ni `routerConfig`** — cero coincidencias. La navegación es **imperativa**: `main.dart` monta un `AuthGate` que decide qué mostrar según la sesión.

**Archivos:** `core/gateways/auth_gateway.dart` · `main.dart` · `screens/landing_page.dart` · `screens/login_screen.dart`.

### Hallazgo

**El portal público y el académico comparten el mismo árbol de widgets, y `AuthGate` decide cuál se ve según si hay sesión.** La landing tiene botones que llevan a login y a inscripción.

**Consecuencia:** **no hay dos portales: hay uno con dos vistas.** Y eso **no es un defecto** — es una decisión, y funciona.

### Contrato recomendado — **[PROPUESTA]**

```
Sin sesión:
  /            → landing pública (oferta real, sin autenticar)
  /inscripcion → formulario público (el aspirante NO tiene cuenta todavía)

Con sesión:
  /panel       → dashboard según rol
  /aula        → Aula Virtual

Regla: la landing NUNCA exige sesión.
Regla: la inscripción pública NO exige sesión — es el orden que respeta ADR-007
       (autenticarse primero abriría una cuenta sin planilla).
```

**Lo que hay que decidir:** si se adopta `GoRouter` o se conserva la navegación imperativa. **`DECISIÓN PENDIENTE`** — y **no hay evidencia de que la imperativa esté fallando**, así que **migrar sería un cambio sin problema demostrado**.

---

## BLOQUE C — Fuente de la oferta formativa

### Evidencia

```
landing_page.dart:59   →  _aspiranteRepo.obtenerProgramasDisponibles()
aspirante_repository.dart:44  →  Result.guard(() => _gateway.programasDisponibles())
                                   ↓
                              gateway → endpoint / RPC → programs
```

**Y medido contra la base:** los programas activos son **6, todos `type: 'CURSO_LIBRE'`** — Estética, Oratoria, Curso Introductorio, Herrería, Higiene y Manipulación de Alimentos, y Soldadura Básica [SEMILLA].

### Hallazgo

**La fuente de verdad es `public.programs`**, con `is_active` y `type`. **`CURSO_LIBRE` es un tipo de programa**, y **la oferta pública del CFS son los programas activos de ese tipo**.

**Y hay un dato que conviene mirar:** el catálogo tiene **`SEM-SOL-CL` — «Soldadura Básica [SEMILLA]»**, que es **el sembrado**. **El CFS Nacional de Soldadura tiene un programa de soldadura que parece de demostración.** **[NO VERIFICADO]** si es el programa real o un dato de prueba.

### Decisión recomendada

**`programs` es la fuente de verdad, y no hay que crear otra** ✓ — **la landing ya lee de ahí.** Falta **confirmar qué programas son reales y cuáles del sembrado**, y eso es `DECISIÓN PENDIENTE`.

---

## BLOQUE D — Despliegue real

### Evidencia

```
Dockerfile           →  EXISTE  (backend/Dockerfile, 1.585 b, 12 sep)
docker-compose.yml   →  EXISTE
render.yaml          →  NO existe
Procfile             →  NO existe
proveedor real       →  NO VERIFICADO
```

> **CORRECCIÓN (2026-10-06).** Aquí se dijo que `Dockerfile` **no existía**. **Es
> falso.** Miré la raíz del repositorio en vez de `backend/`. **Un `ls` mal dirigido
> produjo una afirmación sobre el despliegue** — y es el mismo error de fondo que
> recorre esta sesión: **concluir desde donde se miró, no desde donde está.**

**Y la documentación histórica menciona Render** — pero **no hay ningún archivo de configuración de despliegue en el repositorio.**

### Hallazgo

**No se puede determinar dónde corre el backend en producción con la evidencia del repositorio.**

```
DESPLIEGUE REAL: NO VERIFICADO
```

**Y esto tiene una consecuencia concreta y ya identificada:** el renderer oficial busca la plantilla del PDF en **cuatro rutas candidatas** y funciona en pruebas porque `cwd` es `backend/`. **Sin saber el entorno de despliegue, no se puede saber si la encontrará** — y **el fallo sería un PDF en blanco que no da error**.

### Decisión recomendada

**`DECISIÓN PENDIENTE` del propietario: ¿dónde corre?** Y hasta saberlo, **la resolución de la plantilla debería fallar ruidosamente en vez de silenciosamente** — pero eso **es una implementación, y no la hago aquí**.

---

## BLOQUE E — Error handler

### Evidencia

**Archivo:** `backend/src/http/plugins/errores.ts` — **el manejador global.**

**Dos casos medidos con HTTP real y una corrección ya aplicada:**

**1 · `FST_ERR_CTP_EMPTY_JSON_BODY` — CORREGIDO**

```
error original:  FastifyError: Body cannot be empty when content-type is set to 'application/json'
code:            FST_ERR_CTP_EMPTY_JSON_BODY
resultado final: HTTP 400 · PETICION_INVALIDA · "El cuerpo debe ser JSON válido."
```

La corrección mínima ya está en `backend/src/http/plugins/errores.ts`: la rama de Fastify cubre los códigos `FST_ERR_CTP_*`. `npm run build` terminó con código 0 y la medición HTTP posterior confirmó el `400`.

**2 · E1 `OBSERVADA → OBSERVADA` — CORREGIDO EN EL RPC**

El fallo real no era un `23514`: el RPC lanzaba `P0001` cuando el `UPDATE ... WHERE estado = 'ENVIADA'` afectaba 0 filas, y `traducirError()` lo convertía en `500 ERROR_BASE_DE_DATOS`. La capa de repositorio ya tenía el `409 TRANSICION_PLANILLA_INVALIDA`, pero era inalcanzable.

La solución preserva la autoridad atómica del RPC: cuando no hay fila ENVIADA, la función hace `RETURN` sin insertar una observación y devuelve cero filas; el repositorio traduce ese resultado al `409` existente. Se aplicaron las migraciones nuevas `202610060007_e1_observar_estado_sin_error.sql` y `202610060008_e1_observar_estado_resultado_fix.sql`.

**Nota:** `0008` fue necesario porque la primera versión de `0007` omitió `approved_by` en su `RETURN QUERY`; el defecto fue detectado por la regresión HTTP (`42804`) y corregido mediante una migración posterior, sin editar migraciones aplicadas.

### Estado actual

El defecto específico de Fastify ya está corregido y medido. **No se hizo un mapeo global de `23514` a `409`**, porque eso mezclaría restricciones con semánticas distintas.

El caso E1 tampoco requirió modificar el traductor global: su causa era el `P0001` específico del RPC `observar_planilla_atomico`, y la corrección se hizo conservando el contrato `TRANSICION_PLANILLA_INVALIDA` que ya existía en el repositorio.

**Resultado del bloque E relevante para esta fase:**

- `FST_ERR_CTP_EMPTY_JSON_BODY` → **400 `PETICION_INVALIDA`** ✓
- `PLANILLA_INCOMPLETA` → **422** ✓
- `OBSERVADA → OBSERVADA` → **409 `TRANSICION_PLANILLA_INVALIDA`** ✓
- `23514` para motivo vacío → **400 `RESTRICCION_VIOLADA`** ✓

No se declara resuelto ningún otro mapeo global que no haya sido medido.

---

## BLOQUE F — Workflow HTTP

### Evidencia

**Rutas registradas y verificadas** (401 sin token, no 404): `POST /yo/planilla/enviar` · `POST /yo/planilla/reenviar` · `GET /yo/planilla/versiones` · `POST /inscripcion/planilla/:id/observar` · `/aprobar`.

**Regresión HTTP real ejecutada después de aplicar E1:**

```text
A1 · planilla incompleta        → 422 PLANILLA_INCOMPLETA              ✓
A4 · cuerpo JSON vacío          → 400 PETICION_INVALIDA                ✓
A3 · ENVIADA→OBSERVADA          → 200                                  ✓
E1 · OBSERVADA→OBSERVADA        → 409 TRANSICION_PLANILLA_INVALIDA     ✓
A3 · OBSERVADA→APROBADA         → 409 TRANSICION_PLANILLA_INVALIDA     ✓
A5 · ruta inexistente           → 404                                  ✓
A5 · sin token                  → 401                                  ✓
A5 · alumno→ruta admin          → 403 SOLO_ADMIN                       ✓
A5 · listar propias             → 200                                  ✓
```

Las pruebas crearon **2 fichas y 3 cuentas temporales** y la propia rutina confirmó la limpieza al finalizar. La ejecución terminó con **exit code 0**.

**ESTADO HTTP DEL WORKFLOW RELEVANTE A ESTA FASE: VERIFICADO ✓**

### Nota de alcance

Esto **no equivale a cerrar B1–B16 completo**. La regresión cubre los casos A1/A3/A4/A5 y E1 que estaban bloqueando esta fase; los escenarios adicionales del workflow que no fueron ejecutados aquí siguen siendo `NO VERIFICADO`.

El orden E → F fue correcto: primero se corrigió el manejo del cuerpo vacío y luego el RPC de observación, y finalmente se midió el contrato HTTP completo de esta frontera.

---

## BLOQUE G — Renderer oficial

### Evidencia

```
planilla-oficial-tipos.ts      130 líneas
planilla-oficial-valores.ts    307 líneas
planilla-oficial-pdf.ts        277 líneas
tests                          6/6 ✓
assets/planilla-oficial-template.pdf   EXISTE (561.475 b)
imports desde backend/src      0
rutas que lo invocan           0
```

### Hallazgo

**Implementado, probado y desconectado.** **Y un detalle que importa:** el contrato dice que **el PDF oficial se genera desde `planilla_versiones.datos_snapshot`** — **no desde `datos_planilla` vivo**. **[NO VERIFICADO]** si el renderer ya está preparado para recibir un snapshot o si lee la ficha viva.

### NO implementar todavía

**Conectar el renderer requiere:** resolver la ruta de la plantilla (bloque D) **y** decidir si lee snapshot o ficha viva. **Las dos están pendientes.**

---

## Orden recomendado de implementación

```
1 · BLOQUE F — completar la medición HTTP del workflow
      La frontera crítica de esta fase ya está verificada para A1/A3/A4/A5/E1.
      Faltan únicamente los escenarios B1–B16 que no fueron ejecutados aquí.

2 · BLOQUE D — decidir el despliegue
      Desbloquea la plantilla del PDF. DECISIÓN PENDIENTE del propietario.

3 · BLOQUE A — jefe_cfs
      Requiere aprobar la matriz. DECISIÓN PENDIENTE.

4 · BLOQUE C — confirmar qué programas son reales
      DECISIÓN PENDIENTE.

5 · BLOQUE G — conectar el renderer
      Depende de D y de confirmar el contrato de snapshot.

6 · BLOQUE B — navegación
      Es el menos urgente: funciona, y no hay evidencia de que falle.
```

---

## Resumen de estados

| Bloque | Estado |
|---|---|
| A · jefe_cfs | **DECISIÓN PENDIENTE** — matriz propuesta, sin aprobar |
| B · sesión | **NO VERIFICADO** el detalle; propuesta sin implementar |
| C · oferta | ✅ fuente identificada (`programs`) · **DECISIÓN PENDIENTE** qué es real |
| D · despliegue | **NO VERIFICADO** — no hay config de despliegue en el repo |
| E · error handler | ✅ **CORREGIDO Y MEDIDO** — Fastify 400 + E1 409 verificados |
| F · workflow HTTP | 🟢 **VERIFICADO PARCIALMENTE** — A1/A3/A4/A5/E1 en verde; B1–B16 completo sigue pendiente |
| G · renderer | ✅ auditado — desconectado, y depende de D |

**Ningún bloque se declara cerrado por inferencia.** **E1 está cerrado por medición HTTP real.** F queda parcialmente verificado por alcance explícito: la regresión ejecutada cubre los casos que bloqueaban esta fase, no todo B1–B16.

---

## Lo que NO debe implementarse todavía

`jefe_cfs` · las políticas RLS de roles · el rediseño de la Landing · la conexión del
renderer oficial · la navegación con `GoRouter`. **No se debe hacer un mapeo global
de `23514` a `409`**: el caso de motivo vacío sigue correctamente en `400
RESTRICCION_VIOLADA`, y cualquier nuevo mapeo debe probarse por contexto.

---

## ACTUALIZACIÓN — FASE 0.6-A / CONSOLIDACIÓN HTTP · 2026-10-07

La medición posterior a este documento cerró los tres escenarios que faltaban en la frontera HTTP del workflow de planillas:

- **B3** · enviar sin ficha → **HTTP 404** ✓
- **B10** · aprobar `ENVIADA` → **HTTP 200**, estado `ENVIADA → APROBADA` ✓
- **B11** · aprobar `REENVIADA` → **HTTP 200**, ciclo `ENVIADA → OBSERVADA → REENVIADA → APROBADA` ✓

Con ello, **B1–B16 quedan medidos por HTTP: 16/16 PASS, 0 FAIL, 0 NO DEFINIDO**. Esta afirmación se limita al contrato HTTP del workflow de planillas; no implica que todos los demás bloques del proyecto estén cerrados.

### Instrumentación consolidada

Se creó `supabase/_workflow-http-suite.mjs`, que ejecuta secuencialmente los dos instrumentos HTTP existentes:

1. `_errores-http.mjs` — escenarios A1/A3/A4/A5 + E1.
2. `_b3-b10-b11.mjs` — B3/B10/B11.

`_b3-b10-b11.mjs` ahora devuelve `exit code 1` si alguno de sus tres casos falla. Las migraciones `0007`/`0008` no fueron modificadas.

### Distinción de niveles

`supabase/_probar-transiciones.mjs` queda explícitamente identificado como instrumento **PostgREST/infraestructura**, no como prueba del contrato HTTP. Sus 400 corresponden a ese nivel y no deben compararse directamente con los 409 del backend HTTP. Para validar el contrato de aplicación debe utilizarse `_workflow-http-suite.mjs`.

### E1/E2

La regresión posterior mantiene:

- cuerpo JSON vacío → **400 `PETICION_INVALIDA`** ✓
- `OBSERVADA → OBSERVADA` → **409 `TRANSICION_PLANILLA_INVALIDA`** ✓

La causa histórica de E1 fue `P0001` en el RPC, no `23514`; las migraciones `202610060007_e1_observar_estado_sin_error.sql` y `202610060008_e1_observar_estado_resultado_fix.sql` permanecen aplicadas y sin editar.

### Estado de esta consolidación

**CERRADO:** medición B1–B16 por HTTP · consolidación de ejecución en una suite · separación explícita HTTP/PostgREST · documentación actualizada.

**PENDIENTE:** decisiones de producto/arquitectura identificadas en los bloques A, B, C, D y G. `SEM-SOL-CL` continúa siendo una decisión de producto y el despliegue real continúa sin verificar.
