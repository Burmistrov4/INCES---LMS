# Configuración de Cloudflare R2

> **Estado: la política de CORS está APLICADA y verificada (2026-09-19)** — la
> Capa 7 ya puede hablar con R2 desde el navegador. El ciclo de vida también está
> aplicado, pero **no hacía falta**: R2 ya traía la regla por defecto (§3.4).
> El barrido de `PENDING` abandonados ya existe como **código** —script y ruta de
> administración, §3.6—; lo único que le falta es **quien lo ejecute solo**, y eso
> no es configuración de R2 ni la puede hacer `pg_cron` (§3.7). Ver §6 para el
> estado punto por punto.
>
> Última medición contra el bucket real: **2026-09-19**.
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

### ✅ RESUELTO el 2026-09-19

La política de §2.3 está **aplicada y verificada** contra el bucket real. La misma
sonda, antes y después:

| Origen | Preflight **antes** | Preflight **después** |
|---|---|---|
| `http://localhost:8080` | **403**, las tres cabeceras ausentes | **204** · `allow-origin: http://localhost:8080` · `allow-methods: GET, PUT` · `allow-headers: content-type` |
| `http://127.0.0.1:8080` | **403**, las tres cabeceras ausentes | **204** · las tres cabeceras presentes |

`npx tsx backend/scripts/probe-r2-cors.mts` → **exit 0**. Y el `PUT` real, que
antes respondía 200 *sin* `Access-Control-Allow-Origin`, ahora sí la trae.

Confirmación independiente por la API de Cloudflare: antes de aplicar,
`wrangler r2 bucket cors list` devolvía
`The CORS configuration does not exist. [code: 10059]`.

**El JSON aplicado está versionado en `docs/r2-cors.json`** (ya no hay que
copiarlo del documento). Los nombres canónicos que devuelve `cors list` son
`allowed_origins`, `allowed_methods`, `allowed_headers`, `exposed_headers` y
`max_age_seconds`; en el archivo de entrada de wrangler se escriben
`origins`/`methods`/`headers` dentro de `allowed`, más `maxAgeSeconds`.

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
      "http://localhost:8090",
      "http://127.0.0.1:8090",
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
        "origins": [
          "http://localhost:8090",
          "http://127.0.0.1:8090",
          "http://localhost:8080",
          "http://127.0.0.1:8080"
        ],
        "methods": ["GET", "PUT"],
        "headers": ["Content-Type"]
      },
      "maxAgeSeconds": 3600
    }
  ]
}
```

> Los dos formatos son distintos y la documentación de Cloudflare muestra ambos.
> Si `wrangler` rechaza el archivo, usa el panel: es la vía que acepta el formato
> completo sin ambigüedad.
>
> **La fuente de verdad es `docs/r2-cors.json`**, no este bloque: es el archivo
> que se aplicó de verdad y el que se le pasa a `wrangler`. Los dos JSON de aquí
> son su transcripción en los dos formatos. Si editas uno, edita el otro — o
> mejor, edita `r2-cors.json` y vuelve a aplicar. **Los orígenes `8090` están en
> la política aplicada y no son decorativos:** al mover el frontend a 8090, un
> JSON sin ellos reaplicado borraría el origen vivo y reintroduciría el fallo de
> §2.1 —el navegador bloqueando la subida—, que ya costó una sesión entera.
> El `8080` se conserva porque es el puerto alternativo de Apache y sigue siendo
> un origen de desarrollo legítimo.

### ⚠️ Son dos listas de CORS que no se conocen

`CORS_ORIGINS` en `backend/.env` (hoy
`http://localhost:8090,http://127.0.0.1:8090,http://localhost:3001,http://127.0.0.1:3001`)
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
| 2 | Subida multipart **abandonada** → partes sin objeto | **No** | **Sí** — y **ya estaba tapada sin saberlo**: R2 trae la regla por defecto en todo bucket (§3.4) | No |
| 3 | **Cuenta borrada** → la fila cae por `ON DELETE CASCADE` y el objeto queda | **No** | **Sí** | Sólo **a posteriori** y **sin dueño**: `--huerfanos` lo encuentra listando el bucket, pero ya no sabe de quién era |

Ninguna herramienta sustituye a la otra. Y ojo con el caso 3: **existe hoy**.
`files_metadata.propietario_id` tiene `on delete cascade`, así que borrar la
cuenta borra la fila y deja el objeto en R2 **sin nada que lo referencie**. El
comentario de la propia migración dice *«el barrido del objeto en R2 lo hace el
backend»* — y el backend no lo hace. **Resuelto el 2026-09-19**:
`supabase/eliminar-cuenta.mjs` inventaría los objetos de la cuenta (§2b) y los
borra **antes** de borrarla (§4b), y `backend/scripts/limpiar-pendientes.mts
--huerfanos` encuentra a posteriori los que ya se quedaron sin fila. La base
sigue sin poder verlos; lo que se añadió es la herramienta que mira el bucket.

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

### 3.4 Regla A — abortar subidas multipart abandonadas *(`-- ya existía --`)*

> **⚠️ CORRECCIÓN del 2026-09-19: esta regla NO había que añadirla. R2 la crea por
> defecto en cada bucket.** Antes de tocar nada, `lifecycle list` devolvía:
>
> ```
> name:     Default Multipart Abort Rule
> enabled:  Yes
> prefix:   (all prefixes)
> action:   Abort incomplete multipart uploads after 7 days
> ```
>
> Es decir: **la fuga 2 de D9 ya estaba tapada** desde que se creó el bucket, y el
> apartado que sigue se escribió sin comprobarlo. Se conserva porque explica el
> *porqué* y porque **el peligro real es el contrario**: destruirla sin querer.
> Ver §3.4.1.

Una subida multipart que nunca se completó **no es contenido**: no hay objeto,
sólo partes sueltas que consumen cuota. No puede borrar un archivo confirmado
porque no hay ninguno incompleto. Por eso la regla es segura con cualquier
prefijo, y por eso el valor por defecto de R2 es razonable.

El estado final aplicado el 2026-09-19 (idéntico en efecto al de por defecto, con
un nombre que dice para qué está), versionado en **`docs/r2-lifecycle.json`**:

```bash
npx wrangler r2 bucket lifecycle set inces-lms-media --file docs/r2-lifecycle.json
npx wrangler r2 bucket lifecycle list inces-lms-media
```

```json
{
  "rules": [
    {
      "id": "abortar-multipart-abandonadas",
      "enabled": true,
      "conditions": { "prefix": "" },
      "abortMultipartUploadsTransition": {
        "condition": { "type": "Age", "maxAge": 604800 }
      }
    }
  ]
}
```

`maxAge` va en **segundos** (`604800` = 7 días), el campo es `enabled` (no
`status`), y **`prefix: ""` significa «todos los prefijos»**. La regla no tiene
`deleteObjectsTransition`: sólo aborta. Es deliberado.

#### 3.4.1 ⚠️ La trampa que sí existe: `lifecycle set` reemplaza TODAS las reglas

`set` no añade: **sustituye la configuración entera**. En esta misma sesión, al
aplicar la regla acotada a `m5_archivos/` se borró la de por defecto (que cubría
todos los prefijos) y el bucket quedó **peor** que como estaba — sin protección
para `sondas/` ni para cualquier prefijo futuro.

Reglas prácticas:

1. **Antes de cualquier `set`, `lifecycle list`.** Si hay reglas que no
   recuerdas, van a desaparecer.
2. **El archivo de `set` debe contener la configuración COMPLETA**, no sólo la
   regla nueva. Por eso `docs/r2-lifecycle.json` incluye la regla de multipart:
   es el estado deseado del bucket, no un parche.
3. Para añadir una regla sin tocar las demás existe `lifecycle add`, que es
   aditivo. `set` es para declarar el estado completo.
4. Y lo de siempre: **abortar multipart no borra objetos completos**, así que
   esta regla puede permitirse el lujo de cubrir todo el bucket. Una regla de
   `deleteObjectsTransition` **no** — ahí el prefijo es la única barrera que
   tienes (§3.3).

**Panel**: R2 → `inces-lms-media` → **Settings** → *Object lifecycle rules*.

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

1. ✅ **Hecho** (2026-09-19). Filas `estado = 'PENDING'` con `created_at` anterior
   a un umbral → borrar el objeto de R2 y marcar la fila `DELETED`.
   `backend/scripts/limpiar-pendientes.mts`, con `--revisar-borrados` para las
   filas `DELETED` cuyo objeto quedó residual.
2. ✅ **Hecho** (2026-09-19). Al borrar una cuenta, **borrar antes sus objetos**.
   El `ON DELETE CASCADE` borra la fila y deja el objeto: es el caso 3, el único
   que la base no puede detectar después. `supabase/eliminar-cuenta.mjs` lo hace
   en §2b (inventario) y §4b (borrado), y **se niega a borrar la cuenta si el
   borrado en R2 falla**.
3. ✅ **Hecho (el detector)** (2026-09-19). Objetos del bucket sin ninguna fila que
   los referencie: el único sentido que obliga a mirar el bucket en vez de la
   base. `limpiar-pendientes.mts --huerfanos`. Filtra por `LastModified` con el
   mismo umbral de horas, porque entre el `PUT` y el `INSERT` de la fila el objeto
   existe legítimamente sin fila — una subida en vuelo, no un huérfano.
4. ✅ **Hecho (el disparador)** (2026-09-19). `POST /api/v1/admin/archivos/limpiar`
   — el barrido como ruta de administración, idempotente y sin credenciales de R2
   para quien la llama. Ver §3.7.
5. ⬜ **Pendiente: el reloj.** El disparador existe; **nadie lo pulsa solo**. Hasta
   que haya una tarea programada, esto sigue corriendo sólo cuando alguien se
   acuerda — y el repo **no tiene CI**, así que no hay ningún planificador de
   facto que lo esté haciendo por otra vía. Ver §3.7 para las dos formas.

---

### 3.7 El disparador: qué puede y qué no puede ser el planificador

> **Corrección de un plan equivocado.** La primera redacción de esta sección
> ofrecía «cron de GitHub Actions **o `pg_cron` en Supabase**» como si fueran
> alternativas. No lo son: **`pg_cron` no puede hacer este trabajo, ni hoy ni
> configurado de otra forma.** Corre **dentro** de PostgreSQL, y PostgreSQL no
> habla con el bucket — no tiene las credenciales de R2 ni el SDK. Un `pg_cron`
> sólo podría marcar filas, y marcar una fila `DELETED` sin borrar su objeto es
> exactamente el residuo que el modo `--revisar-borrados` va a buscar después.
> La opción no estaba mal implementada: estaba mal enunciada.

El barrido necesita **dos cosas a la vez**: leer `files_metadata` y borrar objetos
de R2. Sólo un proceso con credenciales de R2 puede hacer la segunda. Hay dos, y
ninguno es un planificador:

| Proceso | Credencial que usa | Quién lo invoca |
|---|---|---|
| El backend | las suyas (ya las tiene) | cualquiera con **sesión de administrador** |
| `limpiar-pendientes.mts` | `SUPABASE_SERVICE_ROLE_KEY` + R2, de `backend/.env` | quien tenga la máquina |

**Las dos puertas hacen el mismo barrido**, y el umbral de abandono y su mínimo
salen de `backend/src/dominio/almacenamiento.ts` en los dos casos, así que no
pueden desviarse. La diferencia es qué más traen:

- **La ruta** (`POST /api/v1/admin/archivos/limpiar`) es la de la aplicación. No
  necesita repartir credenciales de R2: quien llama sólo presenta su sesión. Es la
  que puede usar el cPanel, y la única que existe en un despliegue en la nube
  donde nadie tiene la máquina. Hace sólo el barrido por defecto.
- **El script** es la del operador, y es la única con los modos forenses
  (`--revisar-borrados`, `--huerfanos`), que miran el bucket y no la base.

**Para una tarea programada, el script es el camino corto — y esto no es un
detalle de gusto.** La ruta exige un JWT de administrador, y un JWT de Supabase
**caduca** (una hora por defecto). Una tarea programada tendría que guardar la
contraseña de una persona para pedir uno nuevo en cada ejecución, y esa contraseña
no se puede rotar sin romper la tarea. El script no pide sesión de nadie: le basta
el `.env`, que ya está en la máquina y que además contiene la clave de servicio,
que es **más** poderosa que cualquier JWT de administrador. Guardar una contraseña
de persona para no usar una clave que ya está en disco sería cambiar seguridad por
nada.

La receta concreta —siguiendo el patrón de `devops/README.md` §4.1— está en
`devops/README.md` §4.2. **No está registrada**: una tarea que borra objetos de
producción sin que nadie la mire se activa a mano y con el dueño del sistema
delante.

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

# 5) Las tres herramientas de limpieza (todas en simulación por defecto)
npx tsx backend/scripts/limpiar-pendientes.mts                    # filas PENDING abandonadas
npx tsx backend/scripts/limpiar-pendientes.mts --revisar-borrados # filas DELETED con objeto residual
npx tsx backend/scripts/limpiar-pendientes.mts --huerfanos        # objetos sin fila
node supabase/eliminar-cuenta.mjs correo@dominio.com              # inventario de una cuenta

# 6) El barrido por la API (idempotente; repetirlo no borra de más)
curl -sS -X POST "$API/api/v1/admin/archivos/limpiar" \
  -H "Authorization: Bearer $TOKEN_ADMIN" \
  -H 'Content-Type: application/json' -d '{}'
#    → {"revisadas":N,"barridas":M,"fallidas":0,"idsFallidas":[],"mensaje":"…"}
#    La segunda llamada devuelve revisadas:0 — es la propiedad que permite
#    programarla sin coordinación ninguna.
```

Y las redes de seguridad del proyecto, que **no** cubren nada de esto:

```bash
cd backend && npm run verify          # 468 pruebas; todas hablan con R2 desde Node
node supabase/humo-archivos.mjs --confirmar   # 52 aserciones; ídem
```

> **Por qué ninguna prueba del proyecto puede cubrir esto.** Node no aplica
> CORS: un `PUT` prefirmado da 200 con o sin política, así que el fallo del
> navegador es invisible desde el backend. Y los scripts de limpieza escriben con
> la clave de servicio, que salta la RLS: son mantenimiento, no rutas de usuario,
> y por eso no tienen pruebas automáticas — su verificación es la ejecución en
> simulación que se acaba de listar.

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

## 6. Estado de aplicación

Aplicado el **2026-09-19** con un token de API de Cloudflare (autorizado por
Lorenzo). **El token se usó sólo como variable de entorno: no está en ningún
archivo del repo.**

- [x] **§2.4 — política de CORS.** ✅ **APLICADA Y VERIFICADA.** Versionada en
      `docs/r2-cors.json`. La sonda sale con **exit 0** y el preflight pasa de 403
      a 204 con las tres cabeceras (§2.1). Esto **desbloquea la Capa 7 en Web**.
      Falta añadir el origen de producción cuando se despliegue.
- [x] **§3.4 — regla de abortar multipart.** ✅ Aplicada, pero **no era
      necesaria**: R2 ya la trae por defecto y cubre todos los prefijos. Ver la
      corrección y la trampa de `set` en §3.4 y §3.4.1. Versionada en
      `docs/r2-lifecycle.json`.
- [ ] **§3.5 — Regla B.** Bloqueada por el cambio de `prefijoDeArchivo` (§3.5).
      No ejecutar todavía.
- [x] **§3.6 — el barrido.** ✅ **Hecho** (2026-09-19). Código, no configuración:
      `backend/scripts/limpiar-pendientes.mts` (tres modos) y el borrado de
      objetos en `supabase/eliminar-cuenta.mjs` §2b + §4b. **Era D9 de verdad.**
- [x] **§3.6 punto 4 — el disparador.** ✅ **Hecho** (2026-09-19).
      `POST /api/v1/admin/archivos/limpiar`, idempotente, con `exigirAdmin()` y la
      guardia de módulo. Quien la llama **no necesita credenciales de R2**: las
      tiene el backend. Ver §3.7.
- [ ] **§3.6 punto 5 — el reloj.** El disparador existe; **nadie lo pulsa solo**.
      El repo **no tiene CI**, y `pg_cron` **no puede** hacer este trabajo (§3.7):
      corre dentro de PostgreSQL, que no habla con el bucket. La receta de la tarea
      programada está escrita y **sin registrar** en `devops/README.md` §4.2 — una
      tarea que borra objetos de producción se activa con el dueño del sistema
      delante. Es lo único que queda de D9.
- [ ] **Origen de producción en la política de CORS.** Cuando el frontend se
      despliegue (Vercel o servidor local), añadirlo a `docs/r2-cors.json`
      **y** a `CORS_ORIGINS` del backend: son listas independientes.

> **Higiene de credenciales:** el token de API se transmitió en texto plano. Hay
> que **borrarlo o rotarlo** en el panel de Cloudflare (My Profile → API Tokens)
> en cuanto no haga falta. Generar otro cuesta treinta segundos.

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
