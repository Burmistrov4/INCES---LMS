# Briefing para el agente que implementa la Capa 4 del Módulo 5 (rutas HTTP de archivos)

> **Para quién es esto.** Para un agente de IA (o una persona) que llega **sin
> contexto** al proyecto. Léelo entero antes de tocar nada. Si algo de aquí
> contradice al código, **gana el código** — y avísalo.

> **Estado de partida (2026-09-18).** M5 tiene **Capa 0, 1 y 2 construidas y
> verdes**: dominio puro, migración `202609210001`, RPCs, semilla de parámetros y
> adaptador R2. Falta la **Capa 4 (rutas HTTP)** — este documento —, la **Capa 6
> (pruebas)** y la **Capa 7 (frontend)**.
>
> ~~El módulo `m5_archivos` está **apagado a propósito** y debe seguir así: su
> bandera se enciende cuando existan las rutas y la UI que la sostienen.~~
>
> **SUPERADO (2026-09-19).** La condición que este párrafo ponía se cumplió —ya
> existen las rutas y la UI—, así que la bandera se encendió
> (`202609210002_mod5_habilitar_modulo.sql`) **y** las cinco rutas llevan ya la
> guardia de módulo. Lo que sigue describe el plan de la Capa 4 y se conserva como
> registro; para el estado real, `ESTADO_DEL_SISTEMA.md`. **Antes de fiarte de
> §5, lee las cuatro correcciones que hay al final de esa sección.**

> ⚠️ **Ya ejecutado (2026-09-18, misma fecha).** La Capa 4 y su Capa 6 están
> construidas: `http/rutas/archivos.ts` (5 rutas), `test/archivos.test.ts` (34
> pruebas), `openapi.json` regenerado (47 rutas, 84 esquemas) y `npm run verify`
> limpio (468/468). **Este documento se conserva como registro del plan, no como
> trabajo pendiente.** Si vienes a implementarlo, mira primero el código: lo que
> sigue describe lo que se hizo y por qué. Lo único que queda abierto de M5 es la
> **Capa 7 (frontend)** y el **humo de archivos contra la nube**.

---

## 0. Lo primero: tres correcciones de rumbo

Este briefing **sustituye** a un borrador anterior que circulaba con siete errores
de hecho. Los tres que habrían costado trabajo real:

### 0.1 No existe una capa `aplicacion/`

El borrador pedía crear `backend/src/aplicacion/archivos.ts`. **Ese directorio no
existe y no debe existir.** La arquitectura es de **tres** capas, no cuatro:

```
backend/src/
├── dominio/     ← PURO. Sin red, sin Supabase, sin Fastify.
├── infra/       ← Implementaciones concretas (repos-supabase, r2_service…)
└── http/        ← Adaptadores HTTP (rutas, esquemas Zod, openapi)
```

La orquestación de una ruta vive **en la propia ruta** (`http/rutas/*.ts`), y la
persistencia detrás de un **puerto** (`dominio/puertos.ts`) implementado en
`infra/repos-supabase.ts`. Añadir `aplicacion/` sería una cuarta capa que ningún
otro módulo tiene.

**Dónde va cada cosa, entonces:**

| Pieza | Archivo |
|---|---|
| Rutas | `backend/src/http/rutas/archivos.ts` ← **el nuevo** |
| Esquemas Zod | sección «Módulo 5» de `backend/src/http/esquemas.ts` |
| Puertos | `PuertaArchivos` en `backend/src/dominio/puertos.ts` |
| Repositorio | `ArchivosSupabase` en `backend/src/infra/repos-supabase.ts` |
| Reglas puras | `backend/src/dominio/almacenamiento.ts` ← **ya existe** |
| Adaptador R2 | `backend/src/infra/r2_service.ts` ← **ya existe** |
| Inyección | `backend/src/http/dependencias.ts` |
| Registro | `backend/src/app.ts` |
| OpenAPI | `backend/src/http/openapi.ts` + `openapi.json` |
| Pruebas | `backend/test/archivos.test.ts` ← **el nuevo** |

### 0.2 El puerto de almacenamiento **no puede decir el tamaño**

El borrador pedía hacer `HeadObject` para leer el tamaño real. **El puerto no lo
permite.** Hoy expone exactamente esto (`dominio/puertos.ts`):

```ts
export interface PuertaAlmacenamiento {
  urlDeSubida(peticion: PeticionUrlSubida): Promise<UrlFirmada>;
  urlDeDescarga(clave: string, nombreDescarga?: string): Promise<UrlFirmada>;
  existe(clave: string): Promise<boolean>;   // ← sólo sí/no. NO devuelve tamaño.
  eliminar(clave: string): Promise<void>;
}
```

`existe()` hace un `HeadObject` y **descarta el `ContentLength`** (`r2_service.ts`).
Sin ampliar el puerto, la regla de tamaño post-subida **no se puede implementar**:
no hay de dónde sacar el número.

**Primer cambio obligatorio**, antes de escribir ninguna ruta: sustituir `existe()`
por algo que devuelva el tamaño. Se propone:

```ts
/** Metadatos del objeto en el almacén. `null` si no existe. */
estadisticas(clave: string): Promise<{ tamanoBytes: number } | null>;
```

…implementado en `r2_service.ts` como un `HeadObjectCommand` que lee
`ContentLength` y devuelve `null` cuando el SDK responde `NotFound` (que hoy ya se
distingue con el set `NO_ENCONTRADO`). `existe()` puede quedarse como envoltorio de
`estadisticas(clave) !== null`, o retirarse si nadie más lo usa — **compruébalo
antes de borrarlo**, `existe()` se usa en el borrador del puerto y puede tener
llamantes.

### 0.3 `ErrorApi` no tiene fábrica de 413, y `validarTamano` lanza **400**

El borrador pide devolver `413 Payload Too Large`. Dos hechos:

1. `dominio/errores.ts` tiene fábricas para **401, 403, 404, 409, 410, 400, 500 y
   503**. No hay 413.
2. `dominio/almacenamiento.ts` → `validarTamano()` lanza
   **`ErrorApi.peticionInvalida` (400, `PETICION_INVALIDA`)** cuando el archivo se
   pasa, no un 413.

Es decir: si reutilizas `validarTamano` para la comprobación post-`HeadObject`
—que es el **único** sitio donde el tamaño real se conoce— obtendrás **400**, no
413. Hay que **decidir y unificar**, no dejar las dos cosas:

- **Opción A (recomendada):** 413 explícito. Añadir
  `ErrorApi.demasiadoGrande(mensaje, detalles)` → `413 / ARCHIVO_DEMASIADO_GRANDE`,
  y hacer que `validarTamano` lance **esa** en el caso de exceso (el 400 se queda
  para tamaño corrupto —negativo, `NaN`, `Infinity`—, que es lo que hoy ya
  distingue bien).
- **Opción B:** quedarse en 400 y borrar el 413 del contrato.

Si eliges A, **actualiza las pruebas de `r2.test.ts`** que hoy esperan
`/máximo permitido/` sobre un `ErrorApi` de 400 — comprueban el mensaje, así que
seguirán pasando, pero conviene añadir la aserción del estado.

---

## 1. Lo que ya está construido y NO hay que rehacer

### La migración — `supabase/migrations/202609210001_mod5_archivos.sql`

Tabla `files_metadata` con estas columnas y **estos `CHECK`** (el Zod debe
respetarlos, no inventarse un dominio más amplio):

| Columna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | |
| `propietario_id` | `uuid` → `auth.users(id)` | `on delete cascade` |
| `r2_key` | `text` **unique** | la construye el servidor |
| `nombre_original` | `text` | sólo para `Content-Disposition` |
| `tipo_contenido` | `text` | MIME canónico, derivado de la extensión |
| `tamano_bytes` | `bigint` **nullable** | `NULL` mientras `PENDING` |
| `entity_type` | `text` | `CHECK in ('TASK_SUBMISSION', 'TEACHER_GUIDE')` |
| `entidad_id` | `uuid` **nullable** | la entidad puede crearse después |
| `estado` | `text` | `CHECK in ('PENDING','CONFIRMED','DELETED')` |
| `created_at` / `confirmado_en` / `deleted_at` | `timestamptz` | |

**Escritura directa PROHIBIDA:** `revoke all … from anon, authenticated` y sólo
`grant select` a `authenticated`. Insertar/actualizar por PostgREST da `42501`.
Todo pasa por RPC. RLS: `files_metadata_read_own` y `files_metadata_admin_read`.

### Las tres RPC — nombres y parámetros exactos

```sql
registrar_archivo_pendiente(p_propietario uuid, p_r2_key text,
                            p_nombre_original text, p_tipo_contenido text,
                            p_entity_type text, p_entidad_id uuid)
                            returns public.files_metadata
confirmar_archivo(p_archivo_id uuid, p_tamano_bytes bigint)
                            returns public.files_metadata
marcar_archivo_borrado(p_archivo_id uuid)
                            returns public.files_metadata
```

Las tres son `security definer` y **autorizan solas con `auth.uid()`** (lección
R-20: al ser `definer`, la RLS ya no las protege). Errores: **`42501` → 403**
(no es tuyo, no hay sesión), **`23514` → 400** (no existe, no está `PENDING`, ya
estaba borrado).

`registrar_archivo_pendiente` admite que un **admin** registre a nombre de otro;
un usuario normal sólo a nombre propio.

### El dominio puro — `dominio/almacenamiento.ts`

Ya resuelto, con pruebas verdes. **Úsalo, no lo reescribas:**

- `TIPOS_PERMITIDOS` — 8 extensiones (`.pdf .jpg .jpeg .png .webp .docx .xlsx .pptx`).
- `TAMANO_MAXIMO_BYTES` = 10 MB — **valor por defecto**, no la verdad: el límite
  efectivo viene del parámetro.
- `TTL_SUBIDA_SEGUNDOS = 300`, `TTL_DESCARGA_SEGUNDOS = 900` — **también
  por defecto**, ver §3.4.
- `validarTamano(tamanoBytes, maximoBytes)` — el límite entra **por parámetro**.
- `prefijoDeArchivo(propietarioId, fecha)` → `m5_archivos/<uuid>/<año>/<mes>`.
- `construirClave(prefijo, nombreOriginal, generarId?)` → `<prefijo>/<uuid><ext>`.
- `normalizarPrefijo`, `extensionDe`, `tipoContenidoDe`, `validarClave`,
  `cabeceraDisposicion`.

**La decisión de seguridad del módulo vive aquí:** la clave del objeto la
construye **siempre el servidor**. Si la propusiera el cliente, la URL PUT
firmada sería una autorización para sobrescribir *cualquier* objeto del bucket.

### Los parámetros configurables

`m5_max_bytes` = `10485760` y `m5_max_archivos_por_entidad` = `10`, sembrados en
`system_settings` (`tipo: 'number'`, `es_publico: false`, categoría
`almacenamiento`). Se leen por `PuertaParametros.porClave()`, con el caché de
parámetros que ya existe. **El administrador los cambia desde el panel sin
desplegar** — por eso `validarTamano` recibe el límite por argumento.

> **Ojo con `m5_max_archivos_por_entidad`:** el borrador pedía validarlo, pero
> **no hay hoy ninguna forma de contarlos**. El puerto necesita un método nuevo
> (`contarPorEntidad(entityType, entidadId)`) apoyado en el índice
> `files_metadata_entidad_idx`, que ya existe. Sin él, la regla no se puede
> comprobar.

---

## 2. El patrón a copiar: `http/rutas/cuadrante.ts`

Es el modelo exacto: hexagonal, con los envoltorios de autenticación ya en uso.
**Léelo antes de escribir.** Lo esencial:

```ts
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorApi } from '../../dominio/errores.js';
import { esquemaCrearAula /* … */ } from '../esquemas.js';
import { exigirAdmin, exigirSesion, reposDe } from '../plugins/autenticacion.js';

export function rutasArchivos(app: FastifyInstance, deps: DependenciasRutas): void {
  // Bloque de administración: prefijo + guardia en un solo sitio.
  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());
      admin.delete<{ Params: { id: string } }>('/archivos/:id', async (request) => {
        const { id } = esquemaRutaIdArchivo.parse(request.params);
        // …
      });
    },
    { prefix: '/api/v1/admin' },
  );

  // Bloque con sesión: guardia por ruta.
  app.post('/api/v1/archivos/firmar-subida',
    { preHandler: [exigirSesion()] }, async (request, reply) => { /* … */ });
}
```

Reglas del proyecto que se ven en ese archivo y hay que respetar:

- **Los esquemas Zod viven en `http/esquemas.ts`**, no inline. `params` se envuelve
  (`z.object({ id: esquemaIdAula })`) porque el esquema es del valor suelto.
- **Importes con extensión `.js`** (ESM). `"type": "module"`.
- **Nada de `process.env` en una ruta**: todo entra por `deps`.
- **Nada de `catch (e) { return null; }`.** O hay dato, o hay `ErrorApi`.
- Un `id` inexistente **no se comprueba antes**: la escritura ya sabe fallar
  (PostgREST `PGRST116` → 404). Comprobar antes es una consulta de más.
- Los comentarios explican el **porqué**, no el qué. Es la norma del repositorio.

### 2.1 `DependenciasRutas` hay que ampliarlo

Hoy (`http/dependencias.ts`) tiene `version`, `caches`, `revisarBase`,
`reposAdmin`, `enviarCorreo`, `urlFrente`. **No hay almacenamiento.** Añade:

```ts
/** Almacenamiento pesado. `null` cuando R2 no está configurado (→ 503). */
almacenamiento: PuertaAlmacenamiento | null;
```

y en `app.ts`, dentro de `depsRutas`:

```ts
almacenamiento: crearAlmacenamiento(env),   // devuelve null si faltan las 4 variables
```

`crearAlmacenamiento(env)` **ya existe** (`infra/r2_service.ts`) y devuelve `null`
a propósito cuando R2 no está configurado, para que el backend arranque sin M5.
Quien consuma el puerto decide qué hacer con ese `null`: aquí, **503**.

`rutasArchivos(app, depsRutas)` — con dependencias, a diferencia de
`rutasCuadrante(app)`. Registra la llamada en `app.ts` junto a las demás.

---

## 3. Las cinco rutas

Son **cinco**, no cuatro: dos `DELETE` con ámbitos distintos.

### 3.1 `POST /api/v1/archivos/firmar-subida` · sesión

Flujo:

1. Zod valida `{ nombreOriginal, entityType, entidadId? }`.
2. `extensionDe(nombreOriginal)` + `tipoContenidoDe()` → tipo MIME **derivado de la
   extensión**, nunca del cliente. Si la extensión no está en `TIPOS_PERMITIDOS`,
   400.
3. Comprobar `m5_max_archivos_por_entidad` con `contarPorEntidad()` (§1).
4. `prefijoDeArchivo(usuario.id)` → `construirClave(prefijo, nombreOriginal)`.
5. RPC `registrar_archivo_pendiente(...)` con `p_propietario = usuario.id`,
   `p_r2_key = clave`, `p_tipo_contenido = mime`. Nace **`PENDING`**.
6. `deps.almacenamiento.urlDeSubida({ prefijo, nombreOriginal })` → URL PUT.

**Respuesta — corrige el borrador:** no basta `{ urlDeSubida }`. El cliente
**necesita el `id`** para llamar a `/confirmar`, y sólo lo obtiene aquí (la RPC lo
devuelve en la fila):

```json
{
  "archivo": { "id": "…", "r2Key": "…", "estado": "PENDING", … },
  "urlDeSubida": "https://…",
  "expiraEnSegundos": 300
}
```

**503** si `deps.almacenamiento === null` (`ErrorApi.servicioNoDisponible`).

> **Por qué la fila nace antes que el objeto.** No hay transacción que abarque R2 y
> PostgreSQL. Una fila `PENDING` huérfana es visible y barrible; un objeto en R2 sin
> fila sería un archivo fantasma que nadie puede autorizar ni limpiar.

### 3.2 `POST /api/v1/archivos/:id/confirmar` · sesión

1. `estadisticas(r2Key)` → ¿existe? ¿cuánto pesa?
2. Si **no existe**: el objeto nunca llegó (subida interrumpida). 404.
3. Leer `m5_max_bytes` y llamar a `validarTamano(tamanoReal, limite)`.
4. Si excede: `eliminar(r2Key)` → `marcar_archivo_borrado(id)` → **413** (o 400,
   según la decisión de §0.3). Se borra **primero** el objeto y **después** la fila:
   al revés, un fallo a mitad dejaría el objeto vivo sin metadato que lo describa.
5. Si está bien: RPC `confirmar_archivo(id, tamanoReal)` → `CONFIRMED`.

`confirmar_archivo` sólo acepta `PENDING`. Reconfirmar o resucitar un `DELETED` da
`23514` → 400. Es deliberado: son estados terminales.

> **Por qué el límite se comprueba aquí y no antes.** Una URL PUT prefirmada **no
> admite `content-length-range`**: el servidor no puede imponer el tamaño en el
> momento de firmar. El tamaño real sólo se conoce con el `HeadObject` posterior.
> La validación "previa" que pedía el borrador es **imposible** con este diseño, y
> el código ya lo dice en `almacenamiento.ts`.

### 3.3 `GET /api/v1/archivos/:id/url-lectura` · sesión

**Corrige el borrador:** usaba `GET /api/v1/archivos/firmar-lectura?archivoId=`.
La convención del proyecto es **paramétrico** para identificadores — compárala con
`PUT /api/v1/admin/periodos/:id/vigente` y el porqué que el propio `cuadrante.ts`
documenta (evitar que un segmento estático dependa de la precedencia sobre `:id`).

Flujo: leer la fila → comprobar que `estado = 'CONFIRMED'` (un `PENDING` no tiene
objeto que leer) → `urlDeDescarga(r2Key, nombreOriginal)`. El `nombreOriginal`
alimenta el `Content-Disposition` (`cabeceraDisposicion` ya emite las dos formas,
ASCII y RFC 5987, para que «Constancia José.pdf» no pierda los acentos).

**Autorización:** propietario **o** administrador. La fila llega ya filtrada por la
RLS (`files_metadata_read_own` / `files_metadata_admin_read`), así que si no la ve,
es 404 — **no** 403: revelar «existe pero no es tuya» filtra información. El
borrador pedía un 403 explícito para cross-user; **respétalo sólo si el contrato
del proyecto lo exige**, y mira cómo lo resuelve M4 antes de decidir.

### 3.4 Los TTL **no son constantes: son configurables**

El borrador fija 300 s y 900 s como si fueran ley. Son **valores por defecto**:

- `R2_PUT_TTL_SEGUNDOS` / `R2_GET_TTL_SEGUNDOS` en el entorno (`config/env.ts`),
  con `TTL_SUBIDA_SEGUNDOS` / `TTL_DESCARGA_SEGUNDOS` como `default`.
- Existe además el parámetro `r2_presign_ttl_minutos` (15) en `system_settings`.

La ruta **no debe escribir literales**: usa `expiraEnSegundos` que devuelve
`UrlFirmada`, que es el valor realmente usado al firmar. Si escribes `300` a mano,
el día que alguien cambie la variable de entorno la respuesta mentirá.

### 3.5 Los dos `DELETE`

- `DELETE /api/v1/archivos/:id` — sesión. Propietario.
- `DELETE /api/v1/admin/archivos/:id` — `exigirAdmin()`. Administrador.

Ambas: RPC `marcar_archivo_borrado(id)` (**borrado lógico**, `estado = 'DELETED'`,
`deleted_at`) y luego `eliminar(r2Key)`.

**El orden importa y es el inverso al de §3.2.** Aquí primero el metadato y luego el
objeto: si el borrado en R2 falla, queda una fila `DELETED` con un objeto huérfano
—recuperable, auditable, barrible—; al revés quedaría una fila `CONFIRMED` apuntando
a un objeto que ya no existe, y el usuario vería un archivo roto sin explicación.

La autorización la hace la RPC (`42501` → 403 si el archivo es de otro y no eres
admin). **No la dupliques en la ruta**: dos copias de la misma regla se desvían.

---

## 4. Pruebas (Capa 6)

### 4.1 El marco real: **Vitest**, no supertest

El borrador pedía `supertest`. **No está en `devDependencies` y no se usa en ningún
test del proyecto.** El patrón es Vitest + `app.inject()` de Fastify, montando la
API completa con el arnés en memoria:

```ts
import { describe, expect, it } from 'vitest';
import { crearArnés, TOKEN_ALUMNO, TOKEN_ADMIN } from './support/arnes.js';

const { app } = crearArnés();
const respuesta = await app.inject({
  method: 'POST', url: '/api/v1/archivos/firmar-subida',
  headers: { authorization: `Bearer ${TOKEN_ALUMNO}` }, payload: { /* … */ },
});
```

El arnés (`backend/test/support/arnes.ts`) ya trae `TOKEN_ADMIN`, `TOKEN_ALUMNO`,
`TOKEN_DOCENTE` y repositorios en memoria. **Habrá que ampliarlo** con:

- un doble de `PuertaArchivos` (con las tres RPC y `contarPorEntidad`), y
- un doble de `PuertaAlmacenamiento` **que registre las llamadas** (para poder
  afirmar «se llamó a `eliminar`»), más un interruptor para forzar
  `almacenamiento: null`.

> El doble de R2 **no existe** en `r2.test.ts`. Ese archivo prueba el adaptador
> **real** con credenciales falsas —firmar es local y no hay red—, que es otra
> cosa. No lo reutilices como doble: no lo es.

### 4.2 Lo que el arnés **sí** puede probar

- **401** sin cabecera `Authorization`.
- **503** con `almacenamiento: null` (R2 apagado).
- **400** por extensión no permitida y por `entityType` fuera del `CHECK`.
- **413/400** por exceso de tamaño, con el doble devolviendo un `ContentLength`
  grande — y la aserción de que **`eliminar` fue llamado** antes de marcar borrado.
- **404** al confirmar un archivo cuyo objeto no existe en el almacén.
- Que `firmar-subida` devuelve el **`id`** (el bug que este briefing previene).
- Que la clave sale del prefijo del **propietario** y no del cliente.

### 4.3 Lo que el arnés **NO** puede probar — y por qué importa

El borrador pedía verificar «403 cross-user» con dobles. **Con dobles no se prueba.**
Si `PuertaArchivos` es un doble en memoria, la autorización real —la que hace la RPC
con `auth.uid()`— **nunca se ejecuta**: el test afirmaría sobre el doble, no sobre
el sistema.

Es exactamente la lección que el proyecto ya pagó dos veces (R-20, R-23):

> **Comprobar COMO QUÉ ROL corre la prueba.** Probar un rechazo con un admin no
> prueba nada. Y una aserción que sólo exige «algún error» no prueba la regla:
> **verificar el CÓDIGO**, porque `42501` puede ser falta de `GRANT` *o* RLS.

La autorización cross-user pertenece al **humo contra la base real**, junto al resto
de M5 — no al suite de Vitest. Es la misma conclusión a la que llegó M4 con
`humo-inscripciones.mjs`: la concurrencia y la autorización real sólo se prueban
contra el sistema real.

### 4.4 OpenAPI

Añadir los 5 paths a `backend/src/http/openapi.ts` (hoy: 42 rutas / 79 esquemas) y
regenerar `openapi.json` con `npm run openapi`. Hay un test que compara el documento
con las rutas registradas: si se olvida, **falla**.

---

## 5. La bandera del módulo: ~~**no la enciendas**~~ → **encendida el 2026-09-19**

> **Sección conservada como registro; su instrucción está revocada.** El
> 2026-09-19 llegó el momento que describía: con la Capa 7 construida se encendió
> la bandera. Se deja escrita a propósito porque **contiene cuatro imprecisiones
> que costaron trabajo descubrir**, y quien relea el plan debería saberlo antes de
> fiarse de él.

`m5_archivos` debía seguir **apagado**. Tres aserciones lo fijaban, y las tres eran
pruebas **desactualizadas a propósito** hasta que la Capa 7 existiera:

| Archivo | Qué fija |
|---|---|
| `supabase/tests/validate.mjs` | `m5_archivos sigue apagado: su bandera se enciende con la Capa 4/7` |
| `supabase/verificar-esquema.mjs` | lo excluye de los módulos encendidos |
| `backend/test-humo.mjs` | `m5_archivos existe y está APAGADO (se enciende con la Capa 4/7)` |

Cuando llegó el momento, hubo que actualizar **las tres** — más la lista de
módulos encendidos de `verificar-esquema.mjs` — y usar
`update public.system_modules set habilitado = true where clave = 'm5_archivos'`.

**Lo que este plan decía mal, y conviene no repetir:**

1. **Eran cuatro aserciones, no tres.** Además de las tres de la tabla, hay una
   **cuarta** que no aparece en ninguna lista: la de **idempotencia** de
   `supabase/tests/validate.mjs`, la que reaplica `202609210001` y esperaba
   `false`. Corregir sólo las tres la deja fallando.
2. **`validate.mjs` tenía dos aserciones que cambiar**, no una: la del estado
   inicial **y** la de idempotencia. Y el valor nuevo de la segunda enseña algo:
   reaplicar una migración vieja **no puede deshacer** una posterior.
3. **La migración no puede llamarse `202609190001`.** El orden de aplicación es
   **lexicográfico** y esa versión **ya está tomada** por `mod4_inscripciones.sql`;
   además ordenaría antes de `202609210001`, o sea antes de que exista la tabla
   que la fila necesita. Se llama `202609210002_mod5_habilitar_modulo.sql`.
4. **El arnés de Vitest necesitaba una fila nueva, no un `true`.** La instrucción
   correcta es «**añade** `m5_archivos` a `MODULOS_POR_DEFECTO`»: la fila no
   existía, y sin ella la guardia devuelve **404 `MODULO_DESCONOCIDO`** —no 403—,
   así que las 34 pruebas de archivos habrían fallado por el motivo equivocado.

> **`exigirModulo()` existe en `http/plugins/modulos.ts` y no lo usa nadie.** Y
> aquí el plan daba un consejo que el 2026-09-19 se siguió **al revés, a
> propósito**: decía «no inventes una guardia de módulo para M5: romperías la
> coherencia con M1–M4». Se hizo exactamente eso, por decisión explícita del
> dueño del proyecto, porque **una bandera que nadie comprueba no es una barrera
> de seguridad: es un ítem de menú**. La asimetría con M1–M4 es real y se asume:
> M5 es el primer módulo cuyo apagado se puede probar de extremo a extremo.
>
> Dos detalles de la firma que cuestan un ciclo si se ignoran:
> `exigirModulo(cache, clave)` son **dos** argumentos y devuelve el `preHandler`
> (no es el hook); y va **después** de `exigirSesion()` / `exigirAdmin()`, porque
> al revés una petición anónima recibiría 404/403 en vez del 401 que le toca.

---

## 6. Antes de dar el trabajo por bueno

```bash
cd backend
npm run verify        # typecheck + lint + vitest
```

Y contra la nube, con `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (`sb_secret_…`;
el token `sbp_` da 401):

```bash
node --env-file-if-exists=backend/.env supabase/verificar-esquema.mjs
node --env-file-if-exists=backend/.env backend/test-humo.mjs --confirmar
```

**Pendiente heredado de la Capa 1:** estos dos no consta que se hayan ejecutado
desde que se aplicó `202609210001`. El bloque de `ESTADO_DEL_SISTEMA.md` que dice
«M5 suma a estas cifras: 1 tabla, 2 políticas, 3 funciones, 2 parámetros» está
escrito como **proyección** («suma»), mientras que las cifras de arriba se declaran
**medidas**. Conviene cerrar esa diferencia ejecutando los verificadores y
sustituyendo la proyección por el número real.

Y una comprobación barata antes de fiarse de una RPC nueva: **llamarla sin sesión
contra la nube**. Si llega a su guardia con `42501`, el nombre y los parámetros
resuelven; `PGRST202` significa que el nombre está mal escrito.

---

## 7. Resumen de los siete errores corregidos

| # | El borrador decía | La realidad |
|---|---|---|
| 1 | `backend/src/aplicacion/archivos.ts` | Esa capa no existe: `http/rutas/archivos.ts` |
| 2 | `HeadObject` para leer el tamaño | El puerto sólo da `boolean`: hay que ampliarlo |
| 3 | Devolver `413` | `ErrorApi` no tiene 413 y `validarTamano` lanza **400** |
| 4 | Respuesta `{ urlDeSubida }` | Falta el `id`, sin él no se puede confirmar |
| 5 | Validar `m5_max_archivos_por_entidad` | No hay forma de contarlos: falta el método |
| 6 | TTL fijos de 300 / 900 s | Son valores por defecto de entorno, configurables |
| 7 | Pruebas con `supertest` | Vitest + `app.inject()` + arnés en memoria |
| — | «4 rutas» | Son **5** (dos `DELETE`, propietario y admin) |
| — | 403 cross-user con dobles | Sólo se prueba contra la base real (R-20/R-23) |
