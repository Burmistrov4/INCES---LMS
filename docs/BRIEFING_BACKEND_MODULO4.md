# Briefing para el agente que implementa la Fase 2 del Módulo 4

> **Para quién es esto.** Para un agente de IA (o una persona) que llega **sin
> contexto** al proyecto y va a escribir el backend del Módulo 4 (Inscripciones y
> Cupos). Léelo entero antes de tocar nada. Si algo de aquí contradice al código,
> **gana el código** — y avísalo.

---

## 0. Lo primero: dos correcciones de rumbo

### 0.1 La ruta del proyecto

```
C:\Users\Loro\Desktop\Cuarto Semestre\1. Servicio Comunitario\INCES-LMS-PROJECT
```

**No** es `adrialga-backend`. Ese es **otro proyecto distinto** (Node/Express con
`clientes.routes.ts`, `seniat.routes.ts`, `scraping.routes.ts`). Si tu exploración
del espacio de trabajo te devolvió eso, estabas mirando el directorio equivocado:
este proyecto vive en el escritorio, dentro de la carpeta del servicio comunitario.
El espacio de trabajo de la sesión (`WorkBuddy AI\2026-09-17-05-47-44`) está
**vacío** a propósito — el código no está ahí.

### 0.2 El stack

| Cosa | Es | **No** es |
|---|---|---|
| Framework HTTP | **Fastify 5** | ~~FastAPI~~ (no hay Python), ~~Express~~ |
| Lenguaje | **TypeScript** (ESM, `"type": "module"`, imports con `.js`) | — |
| Validación | **Zod** | — |
| Base de datos | **Supabase / PostgreSQL 17.6** (sa-east-1), vía `@supabase/supabase-js` | — |
| Pruebas | **Vitest** | — |
| Arquitectura | **Hexagonal**: `dominio/` (puro) + `infra/` (implementaciones) + `http/` (adaptadores) | — |

**FastAPI no aparece en ninguna parte del proyecto.** Si escribes Python, estás en
el proyecto equivocado.

---

## 1. Cómo está construido el backend (31 archivos)

```
backend/src/
├── app.ts                          # construye Fastify y REGISTRA LAS RUTAS
├── server.ts                       # arranque real (lee env, abre conexiones)
├── config/
│   └── env.ts                      # TODO se lee aquí, validado con Zod
├── dominio/                        # ← PURO. Sin red, sin Supabase, sin Fastify.
│   ├── tipos.ts                    # tipos compartidos (Programa, Aula, Periodo…)
│   ├── errores.ts                  # clase ErrorApi (estado + codigo + mensaje)
│   ├── puertos.ts                  # INTERFACES de los repositorios (549 líneas)
│   ├── reglas-admin.ts             # reglas de negocio como funciones puras
│   ├── reglas-curriculo.ts
│   ├── reglas-cuadrante.ts         # ← el ejemplo a copiar para M4
│   ├── reglas-invitaciones.ts
│   └── almacenamiento.ts           # puerto de R2 (M5)
├── infra/                          # ← IMPLEMENTACIONES concretas
│   ├── supabase.ts                 # cliente
│   ├── repos-supabase.ts           # implementa TODOS los puertos (2053 líneas)
│   ├── traducir-error.ts           # PostgreSQL/PostgREST → ErrorApi
│   ├── cache.ts, correo.ts, tokens.ts, r2_service.ts
├── http/                           # ← ADAPTADORES HTTP
│   ├── esquemas.ts                 # TODOS los esquemas Zod (694 líneas)
│   ├── openapi.ts                  # OpenAPI 3.1 generado desde Zod (1947 líneas)
│   ├── dependencias.ts             # lo que las rutas reciben inyectado
│   ├── plugins/
│   │   ├── autenticacion.ts        # resuelve request.usuario + exigirAdmin/exigirSesion
│   │   ├── errores.ts              # manejador global de errores
│   │   └── modulos.ts              # guardias de módulo encendido/apagado
│   └── rutas/
│       ├── salud.ts  yo.ts  auth.ts  admin.ts  curriculo.ts  cuadrante.ts
│       └── ← aquí va el nuevo: inscripciones.ts
└── tipos-fastify.d.ts              # aumenta FastifyRequest con usuario/repos
```

### La regla de oro arquitectónica

**Las rutas no hablan con Supabase.** Hablan con un **puerto** (una interfaz de
`dominio/puertos.ts`). La implementación real vive en `infra/repos-supabase.ts`.
Por eso los tests montan la API completa **en memoria, sin red ni credenciales**.

`construirApp(env, deps)` recibe **todo** por parámetro: no lee `process.env`, no
importa singletons, no abre conexiones.

---

## 2. El patrón de una ruta (copia esto, no lo reinventes)

`backend/src/http/rutas/cuadrante.ts` es el modelo. Extracto real:

```ts
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { esquemaCrearAula, esquemaIdAula, /* … */ } from '../esquemas.js';
import { exigirAdmin, exigirSesion, reposDe } from '../plugins/autenticacion.js';

/** Envoltorios de `params`: Fastify tipa `params` como objeto y el esquema es del valor suelto. */
const esquemaRutaIdAula = z.object({ id: esquemaIdAula });

export function rutasCuadrante(app: FastifyInstance): void {
  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());   // ← la guardia, una sola vez

      admin.get('/aulas', async (request) => {
        const { busqueda, tipo, activa, limite, desplazamiento } =
          esquemaListadoAulas.parse(request.query);

        const { aulas, total } = await reposDe(request).cuadrante.listarAulas({
          busqueda, tipo, activa, limite, desplazamiento,
        });

        // El eco de la paginación se devuelve junto a las filas: la pantalla
        // pinta «1 a 25 de 9» sin conservar su propia copia de lo que pidió.
        return { aulas, total, limite, desplazamiento };
      });

      admin.post('/aulas', async (request, reply) => {
        const entrada = esquemaCrearAula.parse(request.body);
        const aula = await reposDe(request).cuadrante.crearAula(entrada);
        return reply.status(201).send({ aula });   // 201, no 200
      });

      admin.patch<{ Params: { id: string } }>('/aulas/:id', async (request) => {
        const { id } = esquemaRutaIdAula.parse(request.params);
        const cambios = esquemaActualizarAula.parse(request.body);
        const aula = await reposDe(request).cuadrante.actualizarAula(id, cambios);
        return { aula };
      });
    },
    { prefix: '/api/v1/admin' },
  );
}
```

### Las cinco piezas del patrón

1. **Una función exportada por módulo**, `rutasXxx(app: FastifyInstance)`.
2. **`admin.addHook('preHandler', exigirAdmin())`** dentro del registro — una sola
   vez para todas las rutas del bloque, no repetida en cada una.
3. **Zod parsea antes de tocar nada**: `request.query`, `request.body`,
   `request.params`. Los esquemas viven **todos** en `http/esquemas.ts`, no dentro
   del archivo de rutas (excepto los envoltorios de `params`).
4. **`reposDe(request).<puerto>.<metodo>(...)`** para acceder a los datos. Nunca
   `request.supabase`, nunca un import directo del repositorio.
5. **Devolver objetos planos**; Fastify serializa. `reply.status(201)` solo al
   crear.

### ⚠️ Hay DOS patrones de registro en el mismo archivo, y hacen falta los dos

`cuadrante.ts` usa **ambos**. Esto importa porque M4 necesita rutas de estudiante
(fuera de `/admin`) y de administración:

**Patrón A — bloque con prefijo** (rutas de administración, `cuadrante.ts:68`):

```ts
app.register(
  async (admin) => {
    admin.addHook('preHandler', exigirAdmin());
    admin.get('/aulas', async (request) => { /* … */ });
    admin.post('/aulas', async (request, reply) => { /* … */ });
  },
  { prefix: '/api/v1/admin' },        // ← el prefijo va aquí, en el registro
);
```

**Patrón B — ruta suelta con la ruta completa inline** (lectura por rol,
`cuadrante.ts:273`; también `yo.ts:15`):

```ts
app.get('/api/v1/mi-horario', { preHandler: [exigirSesion()] }, async (request) => {
  const usuario = request.usuario;
  if (!usuario) throw ErrorApi.noAutorizado();
  // …
});
```

La diferencia no es cosmética: en el patrón A la guardia se aplica **una vez** al
bloque entero; en el B va **por ruta**, en el objeto de opciones. Un archivo puede
—y debe— tener las dos si sirve a roles distintos.

> **Para M4:** las rutas de estudiante (`/api/v1/ofertas`, `/api/v1/mis-inscripciones`,
> `/api/v1/inscripciones`) van con el **patrón B**; las de administración
> (`/api/v1/admin/ocupacion`, …) con el **patrón A**. En un mismo archivo
> `inscripciones.ts`.

### Registrar la ruta

En `app.ts`, importar y llamar. El orden actual es:

```ts
rutasSalud(app, depsRutas);
rutasYo(app, depsRutas);
rutasAdmin(app, depsRutas);
rutasCurriculo(app);
rutasCuadrante(app);
rutasAuth(app, depsRutas);
// ← añadir: rutasInscripciones(app);
```

`rutasCuadrante(app)` **no recibe dependencias** a propósito (no usa cachés ni
correo). Se declara sin parámetro en vez de aceptar uno vacío, para que se vea de
un vistazo que no necesita nada inyectado.

---

## 3. Las guardias y los errores

### Guardias (`http/plugins/autenticacion.ts`)

| Guardia | Qué exige | Error si falla |
|---|---|---|
| `exigirSesion()` | `request.usuario` no nulo | 401 `NO_AUTENTICADO` |
| `exigirAdmin()` | `usuario.rol === 'admin'` | 403 `SOLO_ADMIN` |

El plugin de autenticación corre en `onRequest`, **antes** que cualquier handler, y
deja `request.usuario` (o `null`) y `request.repos` (siempre, actuando como `anon`
si no hay token). **Un token inválido no es un error**: deja `usuario` en `null` y
son las guardias las que deciden.

> **Ojo, hay una trampa documentada:** un token válido cuyo perfil no exista asume
> rol `estudiante` (degradar es seguro; bloquear no). Y si el perfil tiene
> `activo = false` → 403 `CUENTA_INACTIVA`.

### Errores (`dominio/errores.ts`)

**Regla del proyecto: ningún fallo se convierte en `null` ni en lista vacía.** O
hay dato, o hay `ErrorApi` con código.

```ts
throw ErrorApi.prohibido('SOLO_ADMIN', 'Esta acción está reservada al Administrador Maestro.');
throw ErrorApi.conflicto('CHOQUE_DE_AGENDA', 'Ese docente ya tiene…', { detalles });
throw ErrorApi.noEncontrado('SECCION_INEXISTENTE', '…');
throw ErrorApi.peticionInvalida('…');
```

Cuerpo uniforme: `{ error: { codigo, mensaje, detalles? } }`. **El cliente solo
necesita leer `error.codigo`.**

### Traducción de PostgreSQL (`infra/traducir-error.ts`)

El repositorio **no** decide códigos HTTP: lanza, y `traducirError(error, contexto)`
los convierte.

| Código PG/PostgREST | → HTTP | Código de la API |
|---|---|---|
| `23505` | 409 | `REGISTRO_DUPLICADO` |
| `23514` | 400 | `RESTRICCION_VIOLADA` |
| `23503` | 400 | `REFERENCIA_INVALIDA` |
| `42501` | 403 | `PERMISO_DENEGADO` |
| `42P01` | 500 | `ESQUEMA_DESACTUALIZADO` |
| `PGRST116` | 404 | `NO_ENCONTRADO` |
| `PGRST301/302` | 401 | `NO_AUTENTICADO` |
| red (`fetch failed`, `ECONNREFUSED`…) | 503 | `SUPABASE_INALCANZABLE` |

Y **`desenvolver(respuesta, contexto)`** desempaqueta `{ data, error }` de
Supabase: es la única forma de obtener el dato, y lanza si hay error. Así ningún
repositorio puede ignorar `error` por descuido.

**Cuando un `23514` significa algo más específico que «dato inválido»**, se
distingue **por el texto del mensaje** en una función pura del dominio. Ejemplo ya
existente en `reglas-cuadrante.ts`:

```ts
export function esChoqueDeAgenda(mensaje: string): boolean {
  return /ya tiene una clase o guardia asignada|ya est[aá] ocupado el /i.test(mensaje);
}
```

Se escribe `est[aá]` para no depender del acento. Es la misma técnica que
`esBloqueoPorPensumEnUso` en M2. **M4 necesitará lo mismo** (ver §5).

---

## 4. Reglas de negocio como funciones puras

`dominio/reglas-cuadrante.ts` es el modelo a copiar. El porqué, textual del
archivo:

> Viven aquí y no dentro de los manejadores de ruta por la misma razón que
> `esBloqueoPorPensumEnUso` en M2: **una regla enterrada en un manejador sólo se
> prueba levantando HTTP y montando repositorios.** Como función pura se prueban
> todos los casos —incluidos los que la API casi nunca alcanza— sin montar nada.

**La barrera de verdad sigue estando en PostgreSQL** (checks, triggers, RPC). Lo
del dominio es la misma decisión tomada antes de abrir una transacción, para dar
un mensaje que nombre el problema en vez de un error de restricción genérico.

→ **Para M4: crear `dominio/reglas-inscripciones.ts`** con las reglas puras que se
puedan probar sin base de datos.

---

## 5. El Módulo 4 ya tiene el motor hecho — en la base, no en Node

**Esto es lo más importante para no duplicar trabajo.** Las migraciones
`202609190001` y `202609200001` ya dejaron el motor de cupos **entero dentro de
PostgreSQL**. El backend **no** implementa la lógica de cupos: **llama a las RPC**.

### Lo que existe y es invocable

> Firmas **medidas contra la base real** (`pg_get_function_arguments` /
> `pg_get_function_result`), no copiadas del `.sql`. Si el `.sql` y esto
> discrepan, **gana la base**.

| RPC | Firma | Devuelve | Guardia propia |
|---|---|---|---|
| `solicitar_inscripcion` | `(p_section_id uuid)` | `text` (estado resultante: `ENROLLED` \| `WAITLISTED`) | `auth.uid()` |
| `aceptar_cupo` | `(p_section_id uuid)` | `text` | `auth.uid()` + cerrojo |
| `renunciar_cupo` | `(p_section_id uuid)` | `text` | `auth.uid()` |
| `promover_siguiente` | `(p_section_id uuid)` | **`uuid`** (el id promovido, o `null` si no había a quién) | **`is_admin()`** |
| `expirar_ofertas_cupo` | `()` | `integer` (cuántas venció) | `authenticated` |
| `reincorporar_inscripcion` | `(p_student_id uuid, p_section_id uuid)` | `text` | **`is_admin()`** |

Funciones de apoyo (también invocables, `security definer`):
`cupo_efectivo(section_id) → integer`, `cupos_ocupados(section_id) → integer`,
`existe_oferta_vigente(section_id) → boolean`.

Interna, **revocada de todos** (no la llames desde el backend):
`promover_siguiente_de_cola(section_id) → uuid`.

> ⚠️ **`promover_siguiente` devuelve `uuid`, no un estado.** Un `null` no es un
> error: significa que no había nadie en la cola a quien promover. Decídelo
> explícitamente en el handler (¿200 con «nadie promovido» o 404?) — no lo dejes
> caer como un `null` silencioso.

### Las dos tablas que toca M4 (medidas contra la base)

**`enrollments`** — sólo lectura desde el backend; la escritura va por RPC.

```
id              uuid                       NOT NULL
student_id      uuid                       NOT NULL
section_id      uuid                       NOT NULL
status          text                       NOT NULL   -- ENROLLED|WAITLISTED|PENDING_BID|DROPPED
bid_expires_at  timestamptz                NULL       -- sólo si hay oferta viva
created_at      timestamptz                NOT NULL
updated_at      timestamptz                NOT NULL
```

`unique (student_id, section_id)`. El `unique` **se mantiene a propósito**: un
`DROPPED` conserva su fila como historial, y volver a entrar es una **excepción de
administración** (`reincorporar_inscripcion`), no una reinscripción libre.

**`sections`** — el catálogo sobre el que se inscribe. **Ver §7: hoy nadie puede
crear filas aquí.**

```
id            uuid            NOT NULL
program_id    uuid            NOT NULL
subject_id    uuid            NOT NULL
period_code   varchar         NOT NULL   -- FK → academic_periods
name          varchar         NOT NULL
max_capacity  integer         NULL       -- ← NULLABLE a propósito
is_active     boolean         NOT NULL
created_at    timestamptz     NOT NULL
updated_at    timestamptz     NOT NULL
```

> ⚠️ **`max_capacity = 0` NO significa «sin definir»: es una sección sin cupo.**
> Sólo `NULL` cae al global (`cupo_maximo_por_seccion`). La jerarquía la resuelve
> `cupo_efectivo()` = `coalesce(max_capacity, cupo_maximo_por_seccion, 0)`. La
> columna se hizo anulable precisamente porque era `NOT NULL DEFAULT 0` y el
> fallback **nunca disparaba**.

### La vista de ocupación

`v_ocupacion_secciones` es `security_invoker` y expone, por sección:

```
id, period_code, program_id, subject_id, name, is_active,
cupo_efectivo, cupos_ocupados, cupos_disponibles, oferta_vigente
```

`oferta_vigente` es **la columna que evita que la interfaz mienta**: dice si hay
una oferta de cupo viva (asiento comprometido) aunque `cupos_ocupados` no la
cuente.

### Las reglas institucionales vigentes (fijadas por el dueño del producto)

1. **Reincorporaciones:** `reincorporar_inscripcion` **puede exceder la capacidad**
   de la sección. «Si el admin autoriza, el sistema obedece.» La comprobación de
   cupo se quitó a propósito; quedan rol, cerrojo y anti-acaparamiento.
2. **Conteo de cupos:** `PENDING_BID` **no** reserva cupo. Solo `ENROLLED` suma.
3. **Faltas:** se usa el parámetro global `max_faltas_consecutivas` (default 3),
   categoría `asistencia`. **No crear tabla ni variable nueva.**
4. `habilitar_sistema_bids` (boolean, privado) arranca **apagado**.

### ⚠️ Por qué existe `existe_oferta_vigente()` — no la borres

La regla 2, sola, **vende dos veces el mismo asiento**. El contador hacía de
cerrojo de facto:

```
cupo = 1 · A renuncia          → hueco libre
B promovido (PENDING_BID)      → ocupados = 0   ← B ya no cuenta
C entra directo                → ENROLLED       ← 1/1
B acepta su oferta             → ENROLLED       ← 2/1  💥 dos en un asiento
```

Por eso la migración `202609200001` añadió la guarda y la metió como puerta en
`solicitar_inscripcion`, `promover_siguiente_de_cola` y `aceptar_cupo`. El
escenario está probado en `supabase/tests/validate.mjs` §17.5.

**Si vas a tocar algo del motor, lee `REPORTE_ARIA.md` R-23 y R-24 y
`temas/modulo4.md` §«La doble venta» antes.**

### La frontera de escritura: no la rompas

`enrollments` tiene **revocado** `INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER`
para `anon` **y** `authenticated`. Solo queda `SELECT` para `authenticated`.
**Toda escritura pasa por RPC.** Un `insert` directo desde el repositorio daría
`42501` → 403 `PERMISO_DENEGADO`.

Esto es **ADR-003**: la RLS es el único control de autorización porque la clave
publishable viaja al cliente. Si escribes directo, te saltas el motor.

---

## 6. Lo que hay que construir en la Fase 2

### 6.1 Superficie de rutas propuesta (12)

**Estudiante** — guardia `exigirSesion()`, prefijo `/api/v1`:

| Método | Ruta | Hace |
|---|---|---|
| `GET` | `/ofertas` | Catálogo de secciones con ocupación, desde `v_ocupacion_secciones`. Paginado, filtros por lapso/programa/materia, y «solo con cupo». |
| `GET` | `/mis-inscripciones` | Las propias, con `status` y `bid_expires_at` |
| `POST` | `/inscripciones` | `solicitar_inscripcion(section_id)` → devuelve el estado resultante |
| `POST` | `/inscripciones/:sectionId/aceptar` | `aceptar_cupo` |
| `POST` | `/inscripciones/:sectionId/renunciar` | `renunciar_cupo` |

**Administración** — guardia `exigirAdmin()`, prefijo `/api/v1/admin`:

| Método | Ruta | Hace |
|---|---|---|
| `GET` | `/ocupacion` | Panel de ocupación de todas las secciones (la vista, paginada) |
| `GET` | `/secciones/:id/cola` | La cola FIFO de una sección, ordenada por `created_at` |
| `POST` | `/secciones/:id/promover` | `promover_siguiente(section_id)` |
| `GET` | `/secciones/:id/inscripciones` | Quién está inscrito, con estado |
| `POST` | `/inscripciones/reincorporar` | `reincorporar_inscripcion(student_id, section_id)` |
| `POST` | `/inscripciones/expirar` | `expirar_ofertas_cupo()` → cuántas venció |
| `PATCH` | `/inscripciones/:id` | (opcional) forzar estado — decisión de producto, confirmar antes |

> **`expirar_ofertas_cupo` es idempotente y no usa `pg_cron` a propósito.** El
> proyecto tiene arquitectura dual (nube + servidor local) y cortes eléctricos en
> Venezuela: no se puede depender de un planificador concreto. La expone el
> backend como endpoint idempotente que cualquiera puede disparar.

### 6.2 Archivos a crear/modificar

| Archivo | Acción |
|---|---|
| `src/http/rutas/inscripciones.ts` | **Nuevo.** El archivo de rutas. |
| `src/dominio/reglas-inscripciones.ts` | **Nuevo.** Reglas puras (ver §6.3). |
| `src/dominio/puertos.ts` | Añadir `PuertaInscripciones` + tipos de entrada/salida + registrarla en `Repositorios` |
| `src/infra/repos-supabase.ts` | Implementar `PuertaInscripciones` |
| `src/http/esquemas.ts` | Añadir los esquemas Zod |
| `src/http/openapi.ts` | Documentar las rutas nuevas |
| `src/app.ts` | Importar y registrar `rutasInscripciones(app)` |
| `src/http/rutas/admin.ts` | **Encender `m4_inscripciones`** — ver §6.4 |

### 6.3 `reglas-inscripciones.ts` — qué poner

Funciones **puras** (sin I/O), probables sin base de datos:

- `puedeSolicitar(estadoActual | null)` — ¿el estado de esa fila permite pedir?
  (`ENROLLED`/`WAITLISTED`/`PENDING_BID` no; `DROPPED` sí, vía reincorporación).
- `ofertaVencida(bidExpiresAt, ahora)` — espejo del predicado SQL.
- `esSeccionLlena(ocupados, efectivo, ofertaVigente)` — **incluye la oferta viva**,
  para que el mensaje al usuario sea el mismo que aplica la base.
- `descripcionDeEstado(status)` — texto legible, para no repetirlo en la UI.
- Traductores de mensaje, como `esChoqueDeAgenda`: `esSeccionArchivada(mensaje)`,
  `esOfertaVencida(mensaje)`, `esYaInscrito(mensaje)`. **Copia los patrones de los
  `raise exception` de la migración** y escribe `[aeé]` para no depender del acento.

### 6.4 Encender el módulo

En `system_modules`, la fila es:

```
('m4_inscripciones', 'Inscripciones y Cupos',
 'Cola FIFO, ofertas de cupo con vencimiento y listas de espera.',
 false, 40, 'how_to_reg', '{}', 'academico')
```

`false` = **apagado**. Roles permitidos `'{}'` = visible para todos. Hay que
encenderlo (por migración nueva, **nunca editando una aplicada**).

> **Hallazgo que conviene saber:** `exigirModulo()` está **definido pero nunca
> usado** — ninguna ruta lo aplica hoy. Los módulos M2 y M3 funcionan sin que la
> API compruebe la bandera; la oculta el frontend. Si quieres que M4 sí la respete,
> es una decisión de diseño que hay que tomar explícitamente, no un descuido que se
> arregla de paso. **Pregúntalo antes de hacerlo.**

---

## 7. 🚨 Bloqueante: no existe forma de crear secciones

**Esto hay que resolverlo antes o en paralelo, o M4 no se puede usar de punta a
punta.**

- `sections` es la tabla central de M4: uno se inscribe **en una sección**.
- **No hay ninguna ruta, ni método de repositorio, ni esquema Zod para crear,
  listar o editar secciones.** Buscado en todo `backend/src/`: las únicas
  apariciones de `sections` son comentarios y textos de OpenAPI.
- Lo único que existe es un **contador**: `contarSeccionesActivas(programaId)`, que
  alimenta la Regla 2 de M2 (`pensumEditable`).
- En Flutter, `sections` se **lee** (cuadrante, pensum) pero no se administra.

Es decir: **hoy nadie puede crear una sección**, y sin secciones el motor de cupos
no tiene sobre qué operar. Hace falta un CRUD de secciones (o al menos
crear/listar/archivar) — probablemente encaja mejor en M3 (que ya es dueño de
aulas y períodos) que en M4, pero **es una decisión de diseño que hay que
consultar**, no tomar por cuenta propia.

---

## 8. Convenciones obligatorias

Del `HANDOVER.md` y de la práctica del proyecto:

- **Identificadores y comentarios en ESPAÑOL.** `listarAulas`, no `listRooms`.
  Mensajes al usuario en español. Rutas en español (`/aulas`, `/ocupacion`).
- **Nunca `catch (e) { return null; }`.** Los errores se propagan o se traducen,
  nunca se silencian.
- **Comentar el PORQUÉ, no el QUÉ.** Este código base está muy comentado, y los
  comentarios explican decisiones («esto va en `preValidation` y no en `onRequest`
  porque…»), no repiten el código.
- **Nunca editar una migración ya aplicada.** El libro mayor detecta la deriva por
  checksum SHA-256. Se corrige con una migración **nueva**.
- **Verificar, no afirmar.** Si dices que compila, compílalo.
- **Si una prueba falla, lee el error antes de tocarla**: distingue una prueba
  desactualizada de un bug real.
- **No preguntar «¿está libre?» antes de escribir.** Es una carrera y, peor, una
  segunda copia de la regla que se desviará. La guarda vive en la base; el trabajo
  de la API es **traducirla**.

---

## 9. Cómo verificar

```bash
# Backend: 341 pruebas
cd backend && npm test
cd backend && npm run typecheck && npm run lint && npm run build

# SQL: 222 aserciones contra PostgreSQL real (PGlite)
cd supabase/tests && npm test

# Esquema en la nube: 92 comprobaciones
node --env-file-if-exists=backend/.env supabase/verificar-esquema.mjs

# Libro mayor de migraciones
node --env-file-if-exists=backend/.env supabase/apply-migrations.mjs --check

# Recuento del catálogo real
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/contar-catalogo.mjs
```

**Estado verde al cerrar la Fase 1:** backend **341/341** · SQL **222/222** ·
esquema **92/92** · libro mayor **14/14** sin deriva · `flutter analyze` limpio.

> ⚠️ **`flutter test` NO corre en este entorno.** Falla al *cargar* con
> `Unable to connect to flutter_tester process: WebSocketException`. Comprobado
> también fuera del sandbox, así que no es aislamiento. El 307/307 es la última
> medición válida (2026-09-15). **No cites una cifra de Flutter como si la hubieras
> re-ejecutado.** `flutter analyze` sí funciona.

### Antes de empezar: comprueba el reloj

```bash
date -u '+%Y-%m-%dT%H:%M:%SZ'
curl -s -I https://api.cloudflare.com/client/v4/ | grep -i '^date:'
```

Si hay desfase, avísalo **antes** de tocar nada firmado (R2, URLs prefirmadas). Un
desfase >15 min rompe SigV4 y **el SDK de AWS lo corrige en silencio**, ocultando el
error real. Ya pasó: ver `REPORTE_ARIA.md` **R-24**.

---

## 10. Dónde está el conocimiento del proyecto

| Documento | Qué es |
|---|---|
| **`ESTADO_DEL_SISTEMA.md`** | **Fuente de verdad.** Estado por fase, esquema, deudas. Ojo: se desincroniza solo — verifica las cifras |
| **`HANDOVER.md`** | Estado y pendientes. §2.7 es M4; **§2.8 es el bloqueo de R2**. **Empieza aquí** |
| **`docs/CONTRATO_API_MODULO3.md`** | El contrato de M3 (684 líneas): rutas, tipos, errores, y **§10 explica el fallo `42501`** |
| `docs/CONTRATO_API_MODULO2.md` | Contrato de M2, ya implementado |
| **`REPORTE_ARIA.md`** | Contradicciones y fallos propios, R-01…**R-24**. Si algo del diseño te chirría, mira aquí primero |
| `.workbuddy-ai/memory/temas/modulo4.md` | **M4**: la frontera, el modelo, la máquina de estados, la doble venta |
| `.workbuddy-ai/memory/temas/convenciones.md` | Convenciones de código. **Léelo antes de escribir** |
| `ROADMAP.md` | ⚠️ **Desactualizado.** No lo uses como referencia de estado |

**Existe un `docs/CONTRATO_API_MODULO3.md` pero todavía no un
`CONTRATO_API_MODULO4.md`.** El patrón del proyecto es **contrato primero, backend
después**. Escribirlo es un buen primer entregable de la Fase 2.

---

## 11. Resumen en cinco líneas

1. Fastify 5 + TypeScript + Zod + Supabase. **No FastAPI.** La ruta correcta está
   en el escritorio, no en `adrialga-backend`.
2. El patrón de rutas está en `http/rutas/cuadrante.ts`: función exportada,
   `addHook('preHandler', exigirAdmin())`, Zod, `reposDe(request).<puerto>`.
3. **El motor de cupos ya está en PostgreSQL.** El backend llama RPC, no
   reimplementa la lógica. No escribas `insert` sobre `enrollments`: da `42501`.
4. Las reglas institucionales están fijadas y el guardián
   `existe_oferta_vigente()` **no se toca** — evita una doble venta probada.
5. **Falta un CRUD de secciones** o M4 no sirve de punta a punta. Consúltalo.
