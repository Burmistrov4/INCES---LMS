# Configuración de Cloudflare R2

> **Estado: nada de este documento está aplicado.** Son instrucciones listas para
> ejecutar. Las dos primeras (§2 y §3.4) son configuración de Cloudflare y
> requieren tu autorización explícita, porque son acciones hacia fuera sobre un
> servicio real (§6).
>
> Última medición contra el bucket real: **2026-09-18**.
> Este documento nace de la deuda **D9** y de un hallazgo que D9 no cubría: el
> bucket no tiene política de CORS, así que **el frontend Web no puede subir ni
> descargar nada** aunque el backend esté en verde.

---

## 0. Por qué existe este documento

D9 pedía una cosa concreta: una regla de ciclo de vida en el bucket, porque una
URL `PUT` prefirmada **no admite `content-length-range`** y por tanto el tope de
10 MB sólo se puede comprobar *después* de que los bytes estén en R2.

Al ir a escribirla se midió el bucket en lugar de suponerlo, y aparecieron dos
cosas que cambian el trabajo:

1. **No hay política de CORS.** Un navegador no puede usar las URLs prefirmadas.
   Esto bloquea la Capa 7 entera (el gestor documental en Flutter Web) y **ninguna
   de las 468 pruebas del backend puede detectarlo**, porque todas hablan con R2
   desde Node y Node no aplica CORS. Ver §2.
2. **La fuga de D9 no es teórica: hay un huérfano real en el bucket.** Ver §3.1.
   Un objeto de 15 B bajo `m5_archivos/`, con **cero filas** en `files_metadata` y
   cuyo dueño ya no existe en `auth.users`. Lo dejó la sonda de CORS de la sesión
   anterior; se ha borrado al escribir este documento, pero es la demostración
   exacta del agujero.

---

## 1. El bucket

| Dato | Valor | De dónde sale |
|---|---|---|
| Cuenta | `c2722758a39bd150eeeaf747827db47c` | `CLOUDFLARE_ACCOUNT_ID` |
| Bucket | `inces-lms-media` | `R2_BUCKET` |
| Endpoint S3 | `https://c2722758a39bd150eeeaf747827db47c.r2.cloudflarestorage.com` | derivado de la cuenta |
| Cliente | `region: 'auto'`, `forcePathStyle: true` | `backend/src/infra/r2_service.ts` |
| Prefijo de las claves | `m5_archivos/<propietarioId>/<AAAA>/<MM>/<uuid>.<ext>` | `prefijoDeArchivo` + `construirClave` (`backend/src/dominio/almacenamiento.ts`) |
| Credenciales | `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` en `backend/.env` | — |

### ⚠️ Wrangler NO usa esas credenciales

`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` son claves **S3**, válidas para el SDK
de AWS. `wrangler` no las entiende: necesita un **token de API de Cloudflare** con
permiso de R2 (`CLOUDFLARE_API_TOKEN`) o un `npx wrangler login` interactivo.

Si ejecutas los comandos de §2.4 o §3.4 tal cual, sin ese token, el error será de
autenticación y **no** un problema de la configuración. Alternativa sin CLI: el
panel de Cloudflare (§2.4 y §3.4 incluyen la ruta del panel para cada caso).

---

## 2. CORS — el bloqueante que ninguna prueba detecta

### 2.1 La medición

`Content-Type: application/pdf` **no** es un tipo seguro para CORS (los únicos
exentos son `application/x-www-form-urlencoded`, `multipart/form-data` y
`text/plain`). Por eso el navegador **obliga** a un preflight `OPTIONS` antes del
`PUT`, y sin respuesta de CORS no llega a enviarlo.

Medición real del 2026-09-18, con una URL firmada exactamente como la firma
producción (`signableHeaders: new Set(['content-type'])`, 300 s):

| Origen | Preflight `OPTIONS` | `Access-Control-Allow-Origin` | `PUT` desde Node |
|---|---|---|---|
| `http://localhost:8080` | **403** | **(ausente)** | 200 |
| `http://127.0.0.1:8080` | **403** | **(ausente)** | 200 |

La cabecera `Access-Control-Allow-Methods` y `Access-Control-Allow-Headers`
también faltan en ambos casos.

> **Conclusión:** el navegador bloquearía la subida desde los dos orígenes de
> desarrollo. El `PUT` que devuelve **200** desde Node no contradice nada: Node no
> aplica CORS. **La respuesta al preflight es la que decide**, y sólo el navegador
> la emite.

La documentación de Cloudflare lo dice con estas palabras: *«Without a CORS
policy, browser-based uploads and downloads using presigned URLs will fail, even
though the presigned URL itself is valid»*.

### 2.2 Por qué las 468 pruebas pasan en verde

`supabase/humo-archivos.mjs` (52 aserciones) y `backend/test/archivos.test.ts`
hablan con R2 desde **Node**, y Node no aplica CORS: para él una URL prefirmada
funciona con política o sin ella. El único testigo válido es un preflight, y sólo
lo emite un navegador. Por eso se añadió una sonda que lo emite a mano:

```bash
npx tsx backend/scripts/probe-r2-cors.mts
```

Sale con código **1** mientras falte la política, y con **0** cuando esté bien.
No deja residuo. Ejecútala *después* de aplicar §2.4.

### 2.3 La política

Métodos: **sólo `GET` y `PUT`**, que son los dos que usan las URLs prefirmadas
(subida y descarga). `HEAD` no hace falta: el `HeadObject` de la confirmación lo
hace el backend desde Node, donde no hay CORS.

Cabeceras: **`Content-Type` es obligatoria.** La firma la incluye
(`signableHeaders`), así que el navegador está obligado a enviarla; si la política
no la permite, el preflight falla igual que si no hubiera política.

**Forma para el panel de Cloudflare** (pestaña JSON) y para la API S3:

```json
[
  {
    "AllowedOrigins": [
      "http://localhost:8080",
      "http://127.0.0.1:8080"
    ],
    "AllowedMethods": ["GET", "PUT"],
    "AllowedHeaders": ["Content-Type"],
    "MaxAgeSeconds": 3600
  }
]
```

**Forma para `wrangler`** (`{"rules":[{"allowed":{...}}]}`, en minúsculas):

```json
{
  "rules": [
    {
      "allowed": {
        "origins": ["http://localhost:8080", "http://127.0.0.1:8080"],
        "methods": ["GET", "PUT"],
        "headers": ["Content-Type"]
      }
    }
  ]
}
```

> Los dos formatos son distintos y la documentación de Cloudflare muestra ambos.
> Si `wrangler` rechaza el archivo, usa el panel: es la vía que acepta el formato
> completo sin ambigüedad.

### ⚠️ Son dos listas de CORS que no se conocen

`CORS_ORIGINS` en `backend/.env` (hoy
`http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080`)
gobierna **la API**. La política del bucket gobierna **R2**. Son independientes:
añadir un origen a una no lo añade a la otra. Cuando el frontend se despliegue
(Vercel / servidor local), **hay que añadir el origen de producción a las dos**.

### 2.4 Aplicarla

**Panel** (recomendado, no necesita token de API):
R2 object storage → `inces-lms-media` → **Settings** → *CORS Policy* → **Add CORS
policy** → pestaña **JSON** → pegar el primer JSON de §2.3 → **Save**.

**Wrangler**:

```bash
# 1) Escribe el JSON de §2.3 (forma wrangler) en cors.json
# 2) Aplícalo
npx wrangler r2 bucket cors set inces-lms-media --file cors.json
# 3) Compruébalo
npx wrangler r2 bucket cors list inces-lms-media
```

La propagación puede tardar **hasta 30 segundos**.

---

## 3. D9 — la regla de ciclo de vida

### 3.1 Qué es D9 exactamente

Una URL `PUT` prefirmada **no puede imponer un tamaño máximo**. El tope de 10 MB
sólo se comprueba al confirmar, con un `HeadObject` posterior. Eso deja tres fugas
**distintas**, y lo importante es que **necesitan herramientas distintas**:

| # | Fuga | ¿Se ve desde la base? | ¿La tapa el bucket? | ¿La tapa un barrido? |
|---|---|---|---|---|
| 1 | Se sube y **nunca se confirma** → objeto + fila `PENDING` | **Sí** (fila `PENDING`) | No | **Sí** |
| 2 | Subida multipart **abandonada** → partes sin objeto | **No** | **Sí** | No |
| 3 | **Cuenta borrada** → la fila cae por `ON DELETE CASCADE` y el objeto queda | **No** | **Sí** | **No** |

Ninguna herramienta sustituye a la otra. Y ojo con el caso 3: **existe hoy**.
`files_metadata.propietario_id` tiene `on delete cascade`, así que borrar la
cuenta borra la fila y deja el objeto en R2 **sin nada que lo referencie**. El
comentario de la propia migración dice *«el barrido del objeto en R2 lo hace el
backend»* — y el backend no lo hace. Tampoco `supabase/eliminar-cuenta.mjs`, que
no menciona R2 en ninguna línea.

> **Verificado el 2026-09-18:** `files_metadata` = **0 filas**; bucket con **1
> objeto** bajo `m5_archivos/`; su dueño **no existe** en `auth.users`. Es decir:
> un objeto huérfano que la base **no puede ver** y que ningún barrido puede
> encontrar. Era residuo de la sonda de CORS anterior y se ha borrado, pero el
> caso 3 queda demostrado en vivo.

### 3.2 Lo que ya está bien (y no hay que tocar)

Si el cliente **sí** confirma un archivo que se pasa del límite, la ruta borra el
objeto de R2 *y después* marca la fila (`backend/src/http/rutas/archivos.ts:298`),
y responde **413**. Es decir: **el caso 1 sólo ocurre si el cliente abandona sin
confirmar.** No hay nada que arreglar aquí.

### 3.3 ⚠️ La trampa: la regla que parece obvia y borra datos reales

R2 **sólo admite condiciones por prefijo**. No hay filtros por etiqueta ni por
sufijo, y sobre todo **R2 no sabe nada de `files_metadata.estado`**: el ciclo de
vida mira claves y edades, nunca la base de datos.

Como los archivos `PENDING` y los `CONFIRMED` comparten el prefijo
`m5_archivos/<propietario>/<AAAA>/<MM>/`, este comando —que es el que sale solo
al leer D9— **destruiría las entregas de los estudiantes**:

```bash
# ❌ NO EJECUTAR: borra TODOS los objetos de m5_archivos/ con más de 90 días,
#    incluidos los CONFIRMED. El ciclo de vida no distingue el estado.
npx wrangler r2 bucket lifecycle add inces-lms-media borrar-viejos m5_archivos/ --expire-days 90
```

No es un matiz: es la diferencia entre limpiar basura y perder el trabajo de un
semestre. **Cualquier `--expire-days` sobre `m5_archivos/` es incorrecto mientras
el prefijo no distinga el estado.**

### 3.4 Regla A — abortar subidas multipart abandonadas *(segura hoy)*

Es la única regla que se puede aplicar **ya y sin riesgo**. Una subida multipart
que nunca se completó **no es contenido**: no hay objeto, sólo partes sueltas que
consumen cuota. No puede borrar un archivo confirmado porque no hay ninguno
incompleto.

**Wrangler** (posición de los argumentos: `<bucket> [nombre] [prefijo]`):

```bash
npx wrangler r2 bucket lifecycle add inces-lms-media abortar-multipart-abandonadas m5_archivos/ --abort-multipart-days 7 --force
```

**JSON** (para `lifecycle set --file`, o como referencia de lo que queda escrito):

```json
{
  "rules": [
    {
      "id": "abortar-multipart-abandonadas",
      "enabled": true,
      "conditions": { "prefix": "m5_archivos/" },
      "abortMultipartUploadsTransition": {
        "condition": { "type": "Age", "maxAge": 604800 }
      }
    }
  ]
}
```

```bash
npx wrangler r2 bucket lifecycle set inces-lms-media --file lifecycle.json
npx wrangler r2 bucket lifecycle list inces-lms-media
```

`maxAge` va en **segundos** (`604800` = 7 días) y el campo es `enabled`, no
`status`. La regla no tiene `deleteObjectsTransition`: sólo aborta. Es deliberado.

**Panel**: R2 → `inces-lms-media` → **Settings** → *Object lifecycle rules* →
añadir regla con prefijo `m5_archivos/` y *Abort incomplete multipart uploads*
después de 7 días.

### 3.5 Regla B — expirar el tránsito de subidas sin confirmar *(necesita código)*

Para tapar el caso 1 con el bucket hace falta que **el estado se vea en la clave**,
y eso no es configuración: es un cambio en `prefijoDeArchivo`. La forma que lo
consigue:

```
m5_archivos/_pendientes/<propietarioId>/<AAAA>/<MM>/<uuid>.<ext>   ← se firma aquí
m5_archivos/<propietarioId>/<AAAA>/<MM>/<uuid>.<ext>               ← destino al confirmar
```

Al confirmar, el servidor **copia el objeto** (server-side copy de S3: los bytes
no pasan por el backend) y borra el de tránsito; al rechazar por tamaño, borra el
de tránsito como ya hace hoy. Con eso, la regla pasa a ser exacta:

```json
{
  "rules": [
    {
      "id": "expirar-transito-sin-confirmar",
      "enabled": true,
      "conditions": { "prefix": "m5_archivos/_pendientes/" },
      "deleteObjectsTransition": {
        "condition": { "type": "Age", "maxAge": 604800 }
      }
    }
  ]
}
```

```bash
npx wrangler r2 bucket lifecycle add inces-lms-media expirar-transito-sin-confirmar m5_archivos/_pendientes/ --expire-days 7 --force
```

> **No ejecutar todavía.** Mientras `prefijoDeArchivo` siga devolviendo
> `m5_archivos/<propietario>/...`, el prefijo `m5_archivos/_pendientes/` está
> vacío y la regla no hace nada. Es inocua, pero inútil hasta el cambio de código.
> Ese cambio toca `r2Key` (que se guarda en la base) y el contrato de la Capa 7,
> así que va con migración y con la Capa 7 ya asentada — no en un turno nocturno.

### 3.6 Lo que el bucket no puede hacer: el barrido

Aunque la Regla B exista, **el ciclo de vida borra objetos, no filas**. Una fila
`PENDING` cuya subida se abandonó seguiría en la base para siempre, y el
comentario de la ruta ya la describe como *«un `PENDING` antiguo es una subida
abandonada que hay que barrer»*. Ese barrido **está prometido en tres sitios y no
existe**:

- `backend/src/http/rutas/archivos.ts:282`
- `backend/src/http/openapi.ts:2599`
- `supabase/migrations/202609210001_mod5_archivos.sql:89` y `:100`

El barrido es código, no configuración, y le corresponde esto:

1. Filas `estado = 'PENDING'` con `created_at` anterior a un umbral → borrar el
   objeto de R2 y marcar la fila `DELETED`.
2. Al borrar una cuenta, **borrar antes sus objetos** (`eliminar-cuenta.mjs` hoy
   no los mira). El `ON DELETE CASCADE` borra la fila y deja el objeto: es el caso
   3, y es el único que ni el barrido ni la base pueden detectar después.
3. Necesita un planificador. En capas gratuitas: cron de GitHub Actions, o
   `pg_cron` en Supabase.

---

## 4. Verificación

```bash
# 1) ¿Puede el navegador usar R2? (esto es lo que decide)
npx tsx backend/scripts/probe-r2-cors.mts
#    → exit 0 = hay CORS; exit 1 = el navegador bloquearía

# 2) ¿Existe la regla de ciclo de vida?
npx wrangler r2 bucket lifecycle list inces-lms-media

# 3) ¿Está la política de CORS puesta?
npx wrangler r2 bucket cors list inces-lms-media

# 4) ¿Sigue funcionando el ciclo completo contra R2?
npx tsx backend/scripts/probe-r2.mts
```

Y las redes de seguridad del proyecto, que **no** cubren nada de esto:

```bash
cd backend && npm run verify          # 468 pruebas; todas hablan con R2 desde Node
node supabase/humo-archivos.mjs --confirmar   # 52 aserciones; ídem
```

---

## 5. Lo que NO hay que ejecutar

| Comando | Por qué |
|---|---|
| `lifecycle add ... m5_archivos/ --expire-days <n>` | Borra también los archivos **CONFIRMED** (§3.3) |
| `lifecycle add ... --expire-days` sin prefijo | Afecta al bucket **entero**, incluidas las sondas y cualquier otro uso futuro |
| `lifecycle remove` sin `list` previo | Se lleva por delante reglas que no recuerdas |
| `wrangler r2 bucket cors delete inces-lms-media` | Deja el frontend Web sin poder subir ni descargar |
| `wrangler r2 bucket delete inces-lms-media` | Destruye los archivos de los estudiantes. **Nunca** |

---

## 6. Autorización

Nada de §2 y §3.4 está aplicado. Son acciones hacia fuera sobre un servicio real
del proyecto, así que **esperan tu visto bueno**:

- [ ] **§2.4 — política de CORS.** Bloquea la Capa 7 en el navegador. Es la que
      más urge y la de menor riesgo: sólo *permite*, no borra nada.
- [ ] **§3.4 — regla de abortar multipart.** Segura, sólo reclama espacio de
      subidas rotas. Necesita un token de API de Cloudflare o `wrangler login`.
- [ ] **§3.5 — Regla B.** Bloqueada por el cambio de `prefijoDeArchivo` (§3.5).
- [ ] **§3.6 — el barrido.** Código, no configuración. Es D9 de verdad.

---

## 7. Referencias

- Ciclo de vida (API, cuerpo exacto y unidades):
  <https://developers.cloudflare.com/api/resources/r2/subresources/buckets/subresources/lifecycle/methods/update/>
- CORS del bucket (formatos, `AllowedHeaders`, propagación):
  <https://developers.cloudflare.com/r2/buckets/cors/>
- URLs prefirmadas y CORS:
  <https://developers.cloudflare.com/r2/api/s3/presigned-urls/>
- Comandos de `wrangler` para R2:
  <https://developers.cloudflare.com/r2/reference/wrangler-commands/>
