# BLOQUE E — Auditoría del error handler

> **Fecha:** 2026-10-06 · **Naturaleza:** auditoría. **Producción sin modificar.**
> Separa **evidencia medida** · **causa raíz** · **propuesta** · **pendiente**.
> **Nada se declara cerrado por inferencia.**

---

## 0. Dos correcciones a mi informe anterior

**Corrección 1 — `backend/Dockerfile` SÍ EXISTE.** 1.585 bytes, 12 sep. **Mi Fase 0.5
dijo que no existía.** Miré la raíz del repositorio en vez de `backend/`. **Falso.**

```
Dockerfile:            EXISTE  (backend/Dockerfile)
docker-compose.yml:    EXISTE
render.yaml:           no existe
Procfile:              no existe
proveedor real:        NO VERIFICADO
```

**Corrección 2 — `23514` YA tiene traducción.** `traducir-error.ts:129` →
`RESTRICCION_VIOLADA`. **Y también `23502` (línea 117), `23505` (123), `23503` (137)
y `42501` (145).** **Mi afirmación de que estos códigos «no pasan por el traductor»
era incorrecta.** El problema **no es que falte una rama: es que la rama existente no
distingue el contexto.**

---

## 1. Evidencia medida

### 1.1 `errores.ts` — las ramas que existen

```
línea 19   ZodError                        →  ErrorApi.peticionInvalida()  →  400
línea 31   ErrorApi                        →  su propio `estado`
línea 44                                   →  ErrorApi.peticionInvalida()
línea 52   FST_ERR_CTP_INVALID_MEDIA_TYPE  →  ErrorApi.peticionInvalida()  →  400  ✓
línea 63                                   →  ErrorApi.interno()           →  500  ← el pozo
línea 70                                   →  ErrorApi.noEncontrado()
```

**La línea 52 es la clave, y es la prueba de que el patrón correcto ya se usó una
vez:** **`FST_ERR_CTP_INVALID_MEDIA_TYPE` sí tiene rama propia y da 400.**
**`FST_ERR_CTP_EMPTY_JSON_BODY` no la tiene** — y cae al pozo de la 63.

### 1.2 Los dos casos, medidos con HTTP real

**Caso 1 — cuerpo vacío:**

```
error:      FastifyError: Body cannot be empty when content-type is set to 'application/json'
code:       FST_ERR_CTP_EMPTY_JSON_BODY
statusCode: 400        ← Fastify ya lo clasifica como error del cliente
respuesta:  500        ← y el log dice "error no controlado"
```

**Caso 2 — transición ilegal E-2:**

```
origen:     el trigger `impedir_version_modificada` lanza 23514
respuesta:  500
```

### 1.3 El contraste que demuestra que el patrón funciona

**El servicio SÍ traduce bien cuando el error nace en el dominio:**

```
409  {"error":{"codigo":"PLANILLA_NO_OBSERVADA","mensaje":"La última versión…"}}
```

**Medido.** **El camino correcto existe, funciona, y lleva código de dominio.**
**Los errores de PostgreSQL y de Fastify no entran por ahí.**

---

## 2. Causa raíz

**No es «falta una rama para 23514».** Es **dónde se pierde el contexto semántico**:

```
PostgreSQL 23514  →  traducir-error.ts:129  →  RESTRICCION_VIOLADA  →  400
                        ↑
                   UNA sola traducción para TODOS los 23514
```

**`23514` es `check_violation`, y significa cosas distintas según qué constraint lo
lance.** Con **una sola traducción**, el sistema **no puede distinguir**:

- **una transición de workflow ilegal** → debería ser **409** (conflicto de estado)
- **una planilla incompleta al enviar** → debería ser **422** (entidad no procesable)
- **un `CHECK` de integridad interno** → **500** si es una condición que el cliente no provocó

**Y el caso de Fastify es más simple y más grave:** **`FST_ERR_CTP_EMPTY_JSON_BODY`
trae `statusCode: 400` en el propio error y el manejador lo ignora.** **Fastify ya
dijo que es del cliente; el manejador lo convierte en 500.**

---

## 3. Diseño propuesto — **[PROPUESTA, sin implementar]**

### 3.1 Principio: **el contexto viaja con el error, no se adivina del texto SQL**

**Adivinar el significado desde el mensaje de PostgreSQL es frágil** — un cambio de
redacción en un `raise` cambiaría el mapeo **sin que nada falle**. **La traducción
debe basarse en el contexto de la operación**, que el repositorio **ya conoce**:
`traducirError(error, 'observar la planilla')` — **el segundo argumento ya existe** y
**ya se usa** (`detalles.contexto` en el log medido).

### 3.2 Las dos ramas que faltan

**En `errores.ts`, antes del pozo de la línea 63:**

```
1. si el error trae `statusCode` y es 4xx  →  usarlo
     cubre TODOS los `FST_ERR_CTP_*`, no sólo el del cuerpo vacío
     y no hay que enumerarlos uno a uno

2. si el código PG es 23514  →  el mapeo lo decide el CONTEXTO
     no el código
```

**Por qué `statusCode` y no enumerar:** **`FST_ERR_CTP_EMPTY_JSON_BODY` no es el
único** — hay `INVALID_MEDIA_TYPE` (ya cubierto a mano), `BODY_LIMIT`,
`INVALID_CHARACTER`… **Enumerar uno a uno es una lista que envejece; usar el
`statusCode` que Fastify ya pone es una regla que no.**

### 3.3 El mapeo de `23514` por contexto

| Operación | `23514` de | HTTP | Código |
|---|---|---|---|
| `observarPlanilla` · `aprobarPlanilla` | transición del trigger | **409** | `TRANSICION_INVALIDA` |
| `enviarPlanilla` · `reenviarPlanilla` | `validar_planilla()` | **422** | `PLANILLA_INCOMPLETA` |
| cualquier otra | `CHECK` de integridad | **500** | `ERROR_BASE_DE_DATOS` |

**Y el punto que tu instrucción señala y con el que coincido:** **no convertir *todo*
`23514` en la misma respuesta.** **Un `422` legítimo convertido en `409` es peor que
el `500` actual** — porque **el `500` se nota y el `409` engaña.**

### 3.4 Alternativa que descarto, y por qué

**Traducir por el texto del mensaje** (`mensaje.includes('Transición de planilla no
permitida')`) — **es lo que hizo `_razonDeGotrue` en el registro y fue un error**:
comparaba subcadenas contra un cuerpo JSON **y acertaba por lo que el texto llevaba
dentro**. **Mismo antipatrón, mismo resultado.**

---

## 4. Archivos afectados

| Archivo | Cambio |
|---|---|
| `backend/src/http/plugins/errores.ts` | **2 ramas** antes del pozo: `statusCode` 4xx y `23514` por contexto |
| `backend/src/infra/traducir-error.ts` | **23514 deja de traducirse sola**: recibe el contexto |
| `backend/test/errores.test.ts` | **nuevo** — las seis pruebas del §5 |
| `backend/src/infra/repos-supabase.ts` | **no cambia** — ya pasa el contexto |

**El repositorio ya pasa el contexto** ✓ (`traducirError(error, 'observar la planilla')`).
**Eso es lo que hace la solución pequeña: la información ya está ahí.**

---

## 5. Matriz error → HTTP → código

| Error | Origen | HTTP | Código | Estado |
|---|---|---|---|---|
| Cuerpo JSON vacío | Fastify `FST_ERR_CTP_EMPTY_JSON_BODY` | **400** | `PETICION_INVALIDA` | ⚠️ hoy **500** |
| Media type inválido | Fastify `FST_ERR_CTP_INVALID_MEDIA_TYPE` | 400 | `PETICION_INVALIDA` | ✅ ya cubierto |
| Transición ilegal | trigger E-2, `23514` | **409** | `TRANSICION_INVALIDA` | ⚠️ hoy **500** |
| Planilla incompleta | `validar_planilla()`, `23514` | **422** | `PLANILLA_INCOMPLETA` | ⚠️ **NO MEDIDO** |
| `numero` duplicado | `UNIQUE`, `23505` | **409** | — | ✅ traducido (123) |
| `NOT NULL` | `23502` | 400 | — | ✅ traducido (117) |
| `FK` | `23503` | 400 | — | ✅ traducido (137) |
| `EXECUTE` revocado | `42501` | **403** | — | ✅ traducido (145) |
| Desconocido | — | **500** | `ERROR_INTERNO` | ✅ correcto |

**Tres filas están en ⚠️ y son el trabajo.** **Y una está `NO MEDIDO`: el `422` de la
planilla incompleta** — **no lo he provocado**, y **es justamente el caso que
justifica que `23514` no se pueda traducir en bloque.**

---

## 6. Pruebas necesarias — **[PENDIENTES]**

```
1. body JSON vacío              →  400        ← hoy 500, medido
2. transición ilegal E-2        →  409        ← hoy 500, medido
3. planilla incompleta enviar   →  422        ← NO MEDIDO
4. 23505 duplicado              →  409
5. 42501 sin permiso            →  403
6. error desconocido            →  500
```

**Las 3 y 4 y 5 no se han provocado.** **Y la 3 es la que decide el diseño:** si el
`23514` de `validar_planilla` **no se distingue del de la transición**, **el mapeo por
contexto es obligatorio** — y si se distinguen solos, **la solución es más pequeña
todavía.**

**Pruebas por HTTP real**, no unitarias: **el defecto está en el camino de la
petición**, y una prueba unitaria del manejador **no probaría que Fastify entrega el
error como se cree.**

---

## 7. Riesgos

**1 · Cambiar el manejador global toca TODOS los errores del backend.** Un mapeo mal
hecho **convierte errores internos en errores de cliente** — y **un `500` que se
vuelve `400` es peor que el `500`**: deja de alertar y **culpa al usuario**. **Por eso
la rama de `statusCode` debe aceptar sólo `4xx`**, nunca un `5xx` que venga del error.

**2 · `23514` por contexto exige que TODOS los llamadores pasen contexto.** Si alguno
no lo pasa, **cae al `500`** — que es **el comportamiento seguro**, y por eso el
`default` debe seguir siendo 500.

**3 · El orden importa:** `statusCode` **antes** de `23514`, porque **un error de
Fastify no trae código PG** y **uno de PostgreSQL no trae `statusCode`** — no se
solapan, pero el orden deja claro cuál manda.

---

## 8. Lo que NO debe implementarse todavía

**Nada de este bloque.** **Falta medir el caso 3** — el `422` de la planilla
incompleta — porque **es el que determina si el mapeo por contexto es necesario o
suficiente.**

**Y no se declara el Bloque E cerrado sin las pruebas HTTP reales del §6.**

---

## 9. Estado

| Pieza | Estado |
|---|---|
| Causa raíz | ✅ **localizada** — dos pozos distintos, uno por capa |
| `FST_ERR_CTP_EMPTY_JSON_BODY` | ✅ **medido** — `statusCode: 400` → respuesta `500` |
| `23514` de transición | ✅ **medido** — respuesta `500` |
| `23514` de planilla incompleta | **NO MEDIDO** |
| Traducción existente de `23514` | ✅ **existe** (`RESTRICCION_VIOLADA`) — **corrige mi informe** |
| `backend/Dockerfile` | ✅ **existe** — **corrige mi informe** |
| Propuesta | **[PROPUESTA]** — sin implementar |
| Pruebas | **[PENDIENTES]** |

**Y la síntesis, en una línea:** **el backend rechaza bien y comunica mal** — el
servicio traduce con código de dominio (`PLANILLA_NO_OBSERVADA`, 409 ✓), **y las dos
capas de abajo no llegan a ese camino.**
