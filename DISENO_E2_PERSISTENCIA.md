# Diseño técnico de persistencia — E-2 Planilla Oficial

> **Bloque 3. NO implementado.** Ningún archivo creado, ninguna migración aplicada.
> Commit `f53a3ac`. Listo para que el bloque 4 escriba **una** migración sin tomar
> decisiones arquitectónicas.

---

## 1. Arquitectura elegida

**Dos tablas nuevas, ninguna columna nueva en `aspirantes`.**

```
aspirantes  (la ficha — datos_planilla mutable)
    │
    └──< planilla_versiones        (una fila por ENVÍO/REENVÍO — inmutable)
              │
              └──< planilla_observaciones   (una fila por observación)
```

**Por qué no una columna de estado en `aspirantes`:** **el estado pertenece a la
versión, no a la ficha.** v1 se observó y v2 se aprobó — **eso no cabe en una
columna**. Y el bloque 2 demostró que **tampoco dispararía el trigger**, así que la
decisión no es por el trigger: **es por el modelo.**

**Y `aspirantes.datos_planilla` sigue siendo la ficha viva**, mutable mientras el
estado lo permita. **La versión es una foto**, no la fuente.

---

## 2. `planilla_versiones`

| Columna | Tipo | Por qué |
|---|---|---|
| `id` | `uuid pk default gen_random_uuid()` | convención del proyecto |
| `aspirante_id` | `uuid not null references aspirantes(id)` | ver §7 |
| `numero` | `integer not null check (numero > 0)` | 1, 2, 3… **por aspirante** |
| `estado` | `text not null check (estado in ('ENVIADA','OBSERVADA','REENVIADA','APROBADA'))` | **`BORRADOR` NO es un estado de versión** — ver §4 |
| `datos_snapshot` | `jsonb not null` | la planilla **congelada** |
| `enviada_at` | `timestamptz not null default now()` | **y es la FECHA del PDF** ✓ |
| `aprobada_at` | `timestamptz` | nulo hasta aprobar |
| `approved_by` | `uuid references profiles(id)` | nulo hasta aprobar |
| `created_at` | `timestamptz not null default now()` | convención |

**Lo que NO se añade, y por qué:**

| Descartado | Motivo |
|---|---|
| `observada_at` / `reenviada_at` | **redundantes**: la observación tiene su `created_at`, y un reenvío **es una versión nueva** con su `enviada_at` |
| `approved_reason` | **la aprobación no necesita motivo** — observar sí. El motivo vive en `planilla_observaciones` |
| `created_by` | **es siempre el aspirante** — lo dice `aspirante_id` |
| `updated_at` | **una versión no se actualiza.** Si se actualizara, dejaría de ser una versión |
| `codigo_version` | **`(aspirante_id, numero)` ya identifica inequívocamente** |

**`numero` empieza en 1 y **no se reutiliza**: si v1 se observó, v2 es la siguiente aunque v1 quede cerrada.

---

## 3. `planilla_observaciones`

| Columna | Tipo | Por qué |
|---|---|---|
| `id` | `uuid pk default gen_random_uuid()` | convención |
| `version_id` | `uuid not null references planilla_versiones(id)` | **a qué versión se observó** |
| `observada_por` | `uuid not null references profiles(id)` | quién |
| `motivo` | `text not null check (btrim(motivo) <> '')` | **obligatorio** — el contrato lo exige |
| `created_at` | `timestamptz not null default now()` | cuándo |

**Descartado deliberadamente:** estado de la observación, quién la resolvió, fecha de
resolución. **Razón:** **una observación no se «resuelve» — se responde con una
versión nueva.** El vínculo ya está: v2 es posterior a v1 y existe porque v1 se
observó. **Añadir `resuelta_por` sería duplicar información que la secuencia ya da.**

---

## 4. Estados — y por qué `BORRADOR` no está en la tabla

```
BORRADOR   ← NO es un estado de versión: es la AUSENCIA de versión
   ↓ ENVIAR
ENVIADA    ← se crea la versión n
   ├────────────→ APROBADA
   └→ OBSERVADA
        ↓ REENVIAR
      REENVIADA   ← se crea la versión n+1
        ├────────→ APROBADA
        └→ OBSERVADA
```

**El estado de la planilla es el de su versión más reciente.** Si no hay versiones,
**está en BORRADOR** — y eso **no necesita almacenarse**.

**Ventaja, y es la razón de la decisión:** **un solo sitio dice el estado** — la
última versión. Con un `BORRADOR` almacenado habría **dos fuentes** (la columna y la
ausencia de versión) y **podrían contradecirse**.

**[DERIVABLE]** `estado_actual = SELECT estado FROM planilla_versiones WHERE
aspirante_id = ? ORDER BY numero DESC LIMIT 1` — o `'BORRADOR'` si no hay filas.

**Nótese que `OBSERVADA` y `REENVIADA` sí son estados de versión:** v1 quedó
`OBSERVADA` para siempre ✓ (es su historia), y v2 nace `REENVIADA` ✓.

---

## 5. Restricciones — qué va en PostgreSQL y qué en el servicio

**En PostgreSQL** (invariantes que **no deben poder violarse nunca**):

```sql
estado in ('ENVIADA','OBSERVADA','REENVIADA','APROBADA')
numero > 0
unique (aspirante_id, numero)
check (estado <> 'APROBADA' or (aprobada_at is not null and approved_by is not null))
check (estado =  'APROBADA' or (aprobada_at is null and approved_by is null))
```

**Ese par de `check` es la pieza clave:** **una versión APROBADA no puede quedar sin
aprobador ni fecha**, y **una no aprobada no puede tenerlos**. Son **dos**, no uno,
porque el primero solo **no impediría** que una `ENVIADA` llevara `aprobada_at`.

**En el servicio** (reglas de transición — dependen de la versión anterior):

```
BORRADOR → ENVIADA          (no hay versión previa, o la última está OBSERVADA)
ENVIADA  → APROBADA | OBSERVADA
REENVIADA→ APROBADA | OBSERVADA
APROBADA → (nada)
```

**Por qué no en PostgreSQL:** una transición depende de **leer la versión anterior**,
y expresarlo en un `check` exigiría una subconsulta — **imposible en un `check`**. Iría
en un trigger, y **un trigger de transición es más difícil de mantener que la
validación en el servicio**, donde ya viven las reglas de negocio.

**Excepción — y sí merece trigger:** la **inmutabilidad** (§8).

---

## 6. Claves foráneas

| FK | Referencia | Por qué |
|---|---|---|
| `planilla_versiones.aspirante_id` | `aspirantes(id)` | la PK, estable |
| `planilla_versiones.approved_by` | `profiles(id)` | **`profiles.id` es el uid de Auth** — verificado |
| `planilla_observaciones.version_id` | `planilla_versiones(id)` | |
| `planilla_observaciones.observada_por` | `profiles(id)` | |

**Índices:** `(aspirante_id, numero)` —lo cubre el `unique`— y `version_id` para las
observaciones.

---

## 7. Eliminación — **`RESTRICT`, no `CASCADE`**

| FK | Regla | Por qué |
|---|---|---|
| `planilla_versiones.aspirante_id` | **`RESTRICT`** | **Borrar una ficha no debe borrar en silencio el historial de lo que se aprobó.** Si alguien borra una cuenta, **quiere saber que hay versiones antes** |
| `planilla_observaciones.version_id` | **`CASCADE`** | una observación **sin** su versión no significa nada |

**Y hay una consecuencia operativa que conviene ver:** con `RESTRICT`, **el borrado
de una cuenta con versiones falla** — y ya existe `supabase/eliminar-cuenta.mjs`, que
tendría que tratar ese caso. **No es un problema: es la señal que se quiere.** Un
trámite académico aprobado **no debería desaparecer por borrar un usuario**.

---

## 8. Inmutabilidad — **sí necesita trigger**

**Una versión formalizada no puede modificarse.** Y la lógica de aplicación **no
basta**: un `UPDATE` directo por PostgREST —que es como escribe el admin (ADR-003)—
**la saltaría**.

```sql
create trigger planilla_versiones_inmutables
  before update on public.planilla_versiones
  for each row execute function public.impedir_version_modificada();
```

**La función permite UNA sola transición:** `ENVIADA`/`REENVIADA` → `APROBADA` u
`OBSERVADA`, con sus timestamps. **Cualquier otro cambio lanza excepción.**

**Por qué el trigger aquí y no en las transiciones (§5):** esto **no depende de leer
otra fila** — se comprueba contra la propia fila. **Un `check` no puede comparar
`OLD` con `NEW`; un trigger sí.**

**Y `datos_snapshot` es inmutable siempre:** aunque se apruebe, **el snapshot no
cambia**. Eso es lo que garantiza que **el PDF de v1 siga diciendo lo mismo dentro de
un año**.

---

## 9. RLS — diseño de políticas

**Convención del proyecto:** `is_admin()` existe y se usa en las políticas actuales.

### `planilla_versiones`

| Política | Rol | Regla |
|---|---|---|
| `versiones_leer_propias` | `authenticated` | `aspirante_id in (select id from aspirantes where user_id = auth.uid())` |
| `versiones_crear_propias` | `authenticated` | mismo filtro + `estado in ('ENVIADA','REENVIADA')` |
| `versiones_admin_all` | `authenticated` | `is_admin()` |
| **`versiones_no_aprobarse`** | — | **el aspirante NO puede poner `estado='APROBADA'`** — va **en el `with check`** del `crear_propias` |

**Ese último es el que impide el auto-ascenso:** sin él, **un aspirante podría
insertar una versión ya `APROBADA`** y saltarse el trámite.

### `planilla_observaciones`

| Política | Rol | Regla |
|---|---|---|
| `observaciones_leer_propias` | `authenticated` | la versión es suya |
| `observaciones_crear_admin` | `authenticated` | `is_admin()` — **el aspirante no observa** |

**Docente: SIN políticas.** Queda fuera por ausencia de concesión, **que es la forma
correcta de excluirlo** — no por una política que lo niegue.

**[ACADÉMICA — resuelta]** El contrato aprobó que el docente queda fuera ✓.

---

## 10. Concurrencia — qué garantiza PostgreSQL

| Escenario | Garantía |
|---|---|
| **Doble clic en ENVIAR** | **`unique (aspirante_id, numero)`** — el segundo intento **falla**, no crea v2 |
| **Dos ENVÍOS simultáneos** | ídem: uno gana, el otro recibe violación de unicidad |
| **Dos admins aprobando** | **el trigger de inmutabilidad** — el segundo ve `OLD.estado = 'APROBADA'` y **falla** |
| **Aspirante editando mientras el admin aprueba** | **NO garantizado por la BD** — ver abajo |

**El último es el único que necesita el servicio:** el `PUT /yo/planilla` **debe
comprobar el estado antes de escribir**, y hay una **ventana** entre la comprobación
y el `UPDATE`. **Se cierra con una escritura condicional** —`update … where
aspirante_id = ? and (última versión no está APROBADA)`— o aceptando la ventana y
**validando al generar el PDF**.

**[PROPUESTA]** Para el primer incremento: **comprobar en el servicio y aceptar la
ventana**, documentándola. **Cerrarla del todo exige bloqueo pesimista**, y eso es
complejidad que **el volumen de un CFS no justifica**.

---

## 11. Compatibilidad con las planillas existentes

**La estrategia correcta es la que propones, y por una razón fuerte: no inventar
historia.**

```
Planillas ya guardadas  →  siguen siendo `datos_planilla` de la ficha
                        →  NO se les crea v1 retroactiva
Primer ENVÍO real       →  crea v1 con el estado actual de `datos_planilla`
```

**Por qué no generar una v1 falsa:** una versión **afirma que en esa fecha el
aspirante envió esos datos**. Crearla retroactivamente sería **fabricar un acto
administrativo que no ocurrió** — y en un documento que se firma, **eso no es un
detalle técnico**.

**Consecuencia:** habrá fichas **sin ninguna versión**, y **eso es correcto** —
significa «en BORRADOR, nunca enviada» ✓. **El §4 ya lo contempla.**

---

## 12. Migración propuesta — contenido conceptual

**Archivo:** `supabase/migrations/202610060001_e2_planilla_workflow.sql`

1. **Dos tablas** con las columnas y `check` de §2, §3, §5
2. **FKs** de §6 con las reglas de §7
3. **Índices:** el `unique` y `version_id`
4. **Trigger de inmutabilidad** de §8
5. **RLS:** `enable row level security` + las políticas de §9
6. **Autocomprobación**, siguiendo la convención del proyecto: verificar que las
   tablas existen, que el trigger está cableado **nombrando la tabla y el evento**, y
   que las políticas cubren los cuatro casos

**Sin trigger de transición** (§5) — las transiciones viven en el servicio.

**La autocomprobación es obligatoria aquí:** el proyecto ya tiene una migración
(`202609240002`) que **verifica su propio cableado** porque *«un `create trigger` que
no dispara porque el nombre de la columna está mal escrito no falla: simplemente
nunca se ejecuta»*. **El trigger de inmutabilidad tiene ese mismo riesgo.**

---

## 13. Archivos consultados

`rutas/yo.ts` · `rutas/planilla.ts` · `202609240002_mod4_planilla_guardia.sql` ·
`202609100001_init.sql` · `202609250001_d14_aspirantes_program_fk.sql` ·
`planilla-oficial-valores.ts` · `planilla-oficial-tipos.ts` · el esquema vivo de
`aspirantes` y `profiles` · `CONTRATO_E2_PLANILLA_OFICIAL.md`

## 14. Archivos modificados

**NINGUNO.**

## 15. Git

```
rama: main...origin/main · HEAD: f53a3ac · modificados: 4 · no rastreados: 21+1
```

Sin `reset`, `clean`, `restore` ni `stash`.

---

## 16. Riesgos

1. **`RESTRICT` romperá `eliminar-cuenta.mjs`** para fichas con versiones. **Es
   intencional**, pero hay que tratarlo en ese script.
2. **La ventana de concurrencia** del §10 — aceptada y documentada, no cerrada.
3. **`numero` bajo concurrencia** requiere que el servicio calcule `max(numero)+1`
   dentro de la transacción, o confiar en el `unique` y reintentar.
4. **El trigger de inmutabilidad puede bloquear una operación legítima** no prevista
   — hay que probar las **seis transiciones** del contrato antes de darlo por bueno.

## 17. Siguiente bloque

**Escribir la migración** — una sola, con lo de §12. **El diseño está cerrado: no
quedan decisiones arquitectónicas que tomar durante la implementación.**

**Y el bloque 4 debe empezar probando las seis transiciones del contrato** contra el
trigger de inmutabilidad, **porque es la pieza que más fácilmente bloquea algo
legítimo**.

**STOP.** No aplico la migración.
