# Contrato de API — Módulo 3 (Cuadrante, Horarios, Aulas y Guardias Docentes)

> **Estado (2026-09-15): el esquema está aplicado, verificado y corregido.** Las
> **10 migraciones están en el libro mayor**, `verificar-esquema.mjs` pasa
> **81/81** comprobaciones contra la nube y la batería de `supabase/tests` da
> **164 aserciones en verde**. Las rutas de este documento **todavía no existen**:
> son el trabajo del PASO 4. Este documento es el contrato que ese paso debe
> cumplir, no la descripción de algo ya construido.
>
> **Aviso importante:** durante la verificación del despliegue se encontró un
> fallo que dejaba el módulo **inoperable para cualquier usuario real** (las
> altas de guardia y de clase fallaban con `42501`). Está corregido y explicado
> en §10. Se cuenta porque el fallo no lo detectó la batería de pruebas, y el
> motivo por el que no lo detectó es una lección reutilizable.

Base: `/api/v1`. Todo error responde con la forma ya establecida:

```json
{ "error": { "codigo": "RESTRICCION_VIOLADA", "mensaje": "…", "detalles": { "contexto": "…" } } }
```

Los códigos son los de `backend/src/dominio/errores.ts` más **uno nuevo**
(`CHOQUE_DE_AGENDA`, §8). Este módulo no inventa ningún otro.

---

## 1. Rutas

### Administración — guardia `exigirAdmin()`, prefijo `/api/v1/admin`

| Método | Ruta | Qué hace |
| --- | --- | --- |
| `GET` | `/aulas` | Listado paginado de espacios |
| `POST` | `/aulas` | Registra un espacio |
| `PATCH` | `/aulas/:id` | `nombre`, `capacidad`, `esTaller`, `activa` |
| `GET` | `/periodos` | Catálogo de lapsos, con cuál es el vigente |
| `POST` | `/periodos` | Registra un lapso |
| `PATCH` | `/periodos/:id` | `nombre`, `fechaInicio`, `fechaFin`, `activo` |
| `PUT` | `/periodos/:id/vigente` | Declara ese lapso como el vigente |
| `GET` | `/guardias` | Listado paginado de guardias |
| `POST` | `/guardias` | Asigna una guardia |
| `PATCH` | `/guardias/:id` | Mueve o edita una guardia |
| `GET` | `/cuadrante` | **La rejilla maestra**: clases y guardias de un lapso |
| `POST` | `/cuadrante` | Coloca una clase en la rejilla |
| `PATCH` | `/cuadrante/:id` | Mueve o edita una clase |

### Lectura por rol — guardia `exigirSesion()`

| Método | Ruta | Quién | Qué devuelve |
| --- | --- | --- | --- |
| `GET` | `/api/v1/mi-horario` | docente, estudiante | Docente: sus clases **y** sus guardias. Estudiante: las clases de su sección. |

**Ninguna ruta borra.** Archivar es `activa: false`. `teacher_duties.classroom_id`
y `schedule_slots.classroom_id` están en `on delete restrict` precisamente para
que borrar un aula en uso no sea posible ni por accidente.

### Sobre `PUT /periodos/:id/vigente`

Se eligió `/periodos/:id/vigente` y no `/periodos/vigente` a propósito. La
segunda forma obliga a que el enrutador resuelva `vigente` contra el parámetro
`:id` del `PATCH` de al lado, y depende de la precedencia de segmento estático
sobre paramétrico. Funciona, pero es una dependencia invisible que se rompe el
día que alguien reorganice las rutas. Con `:id` delante, la ambigüedad no existe.

---

## 2. Tipos compartidos

```ts
export type Turno = 'MAÑANA' | 'TARDE';

/** Un espacio físico o una zona del CFS. Ver §4. */
export interface Aula {
  id: string;
  nombre: string;          // name varchar(80), único
  capacidad: number;       // capacity, >= 0
  esTaller: boolean;       // is_workshop
  activa: boolean;         // is_active
  creadoEn: string;
  actualizadoEn: string;
}

export interface Periodo {
  id: string;
  codigo: string;              // code varchar(10), único
  nombre: string | null;       // name
  fechaInicio: string | null;  // start_date — ver §3, nulo a propósito
  fechaFin: string | null;     // end_date
  activo: boolean;             // is_active
  vigente: boolean;            // derivado: code == system_settings.periodo_activo
  creadoEn: string;
  actualizadoEn: string;
}

export interface Guardia {
  id: string;
  docenteId: string;       // teacher_id -> profiles.id
  aulaId: string;          // classroom_id -> classrooms.id
  periodo: string;         // period_code -> academic_periods.code
  dia: number;             // day_of_week, 1 = lunes … 6 = sábado
  bloque: number;          // block, 1..12
  turno: Turno;            // DERIVADO de bloque; no se envía, se recibe
  notas: string | null;
  activa: boolean;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * Una clase del cuadrante. Los cinco primeros campos son la tabla; el resto lo
 * aporta la vista `v_cuadrante_clases` y sólo está presente en las lecturas.
 */
export interface ClaseCuadrante {
  id: string;
  seccionId: string;
  docenteId: string;
  aulaId: string;
  dia: number;
  bloque: number;
  turno: Turno;
  activa: boolean;
  // --- enriquecido por la vista ---
  periodo: string;
  materia: string;
  seccion: string;
  aula: string;
  docente: string;         // vía `nombre_para_mostrar()` — ver §7
  creadoEn: string;
  actualizadoEn: string;
}
```

**Convención de nombres, otra vez.** La base usa inglés (`classroom_id`,
`day_of_week`) y la API y Dart usan español (`aulaId`, `dia`). La traducción
ocurre **en la capa de repositorio, en un único sitio**, como en M2. Confundir
las dos capas es el error que ya costó dos fallos falsos en el humo de M1.

**`turno` es derivado y sólo viaja de salida.** Es una columna
`generated always as (turno_de_bloque(block)) stored` (R-16). Mandarlo en un
`POST`/`PATCH` es un `400 PETICION_INVALIDA` por `.strict()`, y no un campo
ignorado en silencio: aceptar un turno que contradiga al bloque sería aceptar
una agenda que miente.

---

## 3. Períodos — `GET/POST /periodos`, `PATCH /periodos/:id`, `PUT /periodos/:id/vigente`

### Dos nociones de «activo», y por qué

Hay dos cosas distintas que en el lenguaje diario se llaman «el período activo»:

| Concepto | Dónde vive | Qué significa |
| --- | --- | --- |
| `academic_periods.is_active` | columna del lapso | «este lapso está **abierto**: se puede planificar en él» |
| `system_settings.periodo_activo` | parámetro del sistema | «este es el lapso **vigente**: lo que la UI muestra por defecto» |

Pueden ser varios abiertos y sólo uno vigente, y ése es el caso real: al cerrar
un lapso se prepara el siguiente mientras el vigente sigue siendo el que se está
dictando. Un solo campo no podría expresarlo.

`PUT /periodos/:id/vigente` es la **única** forma de mover el vigente: escribe
`system_settings.periodo_activo`. No se acepta por `PATCH /periodos/:id` para que
no haya dos caminos que cambien lo mismo por vías distintas.

Un trigger (`system_settings_periodo_registrado`) **rechaza** un `periodo_activo`
que no corresponda a un lapso registrado:

```
El período activo "%" no está registrado en el catálogo de lapsos. Créalo
primero: la Regla 2 compara este valor con la sección y, si no corresponde a
ningún lapso real, no protegería nada.
```

Es la materialización de **R-12**: hasta ahora `periodo_activo` era un texto
suelto que podía no corresponder a nada y nadie se enteraba. Ahora la divergencia
entre lo que dice el parámetro y lo que existe es imposible, no silenciosa.

### Las fechas son nulas a propósito (R-17)

`start_date` y `end_date` **son nullables y no se siembran**. El centro no ha
cargado las fechas reales del lapso `2026-1`, y **inventarlas habría sido
fabricar un dato institucional**. La restricción que sí existe es de coherencia:
`end_date > start_date` cuando ambas están.

La UI debe mostrar «sin fechas cargadas», no un rango inventado.

### `POST /periodos`

```json
{ "codigo": "2026-2", "nombre": "Lapso 2026-2", "fechaInicio": "2026-09-21", "fechaFin": "2027-02-13" }
```

| Campo | Regla Zod |
| --- | --- |
| `codigo` | `string().trim().min(1).max(10).regex(/^[A-Za-z0-9][A-Za-z0-9-]{0,9}$/)` |
| `nombre` | `string().trim().min(1).max(120).optional()` |
| `fechaInicio` / `fechaFin` | `string().date().optional()` — ISO `YYYY-MM-DD` |

**201** con `{ "periodo": { … } }`. **409 `REGISTRO_DUPLICADO`** si el código ya
existe (`unique` sobre `code`).

> **R-06 sigue abierta y no la cierra este módulo.** La nomenclatura del lapso
> (`2026-1` en producción frente al `SA26-2` que usa la coordinación) es una
> decisión del INCES. Lo que el módulo garantiza es que **deja de estar
> incrustada en el código**: renombrar un lapso es un `PATCH`, y añadir otro es un
> `POST`. Lo sembrado es `2026-1`, el valor real que ya estaba en
> `system_settings`, leído de ahí y no escrito a mano.

---

## 4. Aulas — `GET/POST /aulas`, `PATCH /aulas/:id`

Un **único** concepto de espacio, con dos formas (R-18):

| Forma | Cómo se representa | Ejemplo |
| --- | --- | --- |
| Aula o taller | `capacidad > 0`, `esTaller` según sea | `Taller de Soldadura Cabina A`, `capacidad: 12`, `esTaller: true` |
| Zona de custodia | `capacidad: 0`, `esTaller: false` | `Pasillo de talleres`, `capacidad: 0` |

No hay una tabla `zones` aparte **a propósito**: la guardia anti-colisión vigila
**un solo sitio**. Con dos tablas habría que duplicar el chequeo y mantener las
dos copias de acuerdo, y el día que divergieran el resultado sería peor que no
tener ninguna —una colisión que pasa por un lado que nadie mira—.

`GET /aulas` — filtros `busqueda` (sobre `nombre`), `tipo` (`TALLER` \|
`ZONA` \| `AULA`), `activa`, `limite`, `desplazamiento`.

```json
{ "aulas": [ { "id": "…", "nombre": "Taller de Soldadura Cabina A",
               "capacidad": 12, "esTaller": true, "activa": true,
               "creadoEn": "…", "actualizadoEn": "…" } ],
  "total": 9, "limite": 25, "desplazamiento": 0 }
```

**No hay semilla de aulas, y es deliberado.** Sembrar `Taller de Soldadura
Cabina A` habría sido inventar el inventario del centro. El registro lo carga el
administrador; hasta entonces la lista sale vacía y **el cuadrante no se puede
usar**, porque una clase sin aula no existe. La UI debe decir eso en vez de
mostrar un desplegable vacío sin explicación.

**409 `REGISTRO_DUPLICADO`** si el nombre ya existe (`unique` sobre `name`).
**400 `PETICION_INVALIDA`** si `capacidad < 0` o el nombre está en blanco — las
dos tienen `check` en la base además de Zod.

---

## 5. Guardias — `GET/POST /guardias`, `PATCH /guardias/:id`

Una guardia es **una presencia**, no una clase: dice quién custodia qué espacio,
qué día y qué bloque, **independientemente de que haya clase**.

```json
{ "docenteId": "…", "aulaId": "…", "periodo": "2026-1",
  "dia": 1, "bloque": 1, "notas": "Apertura del taller" }
```

| Campo | Regla Zod |
| --- | --- |
| `docenteId` / `aulaId` | `string().uuid()` |
| `periodo` | `string().trim().min(1).max(10)` — debe existir en `academic_periods` |
| `dia` | `number().int().min(1).max(6)` |
| `bloque` | `number().int().min(1).max(12)` |
| `notas` | `string().trim().max(500).nullable().optional()` |

**201** con `{ "guardia": { … } }`, ya con el `turno` derivado.

**`periodo` es obligatorio, y no es un formalismo (R-15).** Sin período, una
guardia del lunes a primera hora chocaría con las clases de **cualquier** lapso:
el pasado, el vigente y el que se está planificando. El período es lo que acota
el chequeo a una agenda concreta.

**Filtros de `GET /guardias`:** `periodo`, `docenteId`, `aulaId`, `dia`, `bloque`,
`activa`, `limite`, `desplazamiento`.

**`PATCH` mueve una guardia.** Cambiar `dia` o `bloque` es un traslado: el
trigger se dispara y el propio registro queda excluido del chequeo (`not (origen
= 'teacher_duties' and id = p_id)`), así que mover una guardia sobre su propio
hueco no se rechaza a sí misma.

**Archivar en vez de borrar:** `PATCH` con `activa: false`. El trigger **sale
antes de comprobar** cuando `is_active` es falso: una guardia archivada no ocupa
a nadie, y sin esa salida temprana desactivar una guardia seguiría bloqueando el
hueco que ya no usa.

---

## 6. Cuadrante — `GET/POST /cuadrante`, `PATCH /cuadrante/:id`

La rejilla maestra: sección + docente + aula + día/bloque.

```json
{ "seccionId": "…", "docenteId": "…", "aulaId": "…", "dia": 3, "bloque": 5 }
```

**El período no se manda: se deriva de la sección** (`sections.period_code`).
Aceptarlo del cliente abriría la puerta a una fila cuya sección pertenece al
lapso `2026-1` mientras la rejilla se dibuja en el `2026-2`, y el chequeo de
colisiones compararía peras con manzanas. El trigger lo resuelve así:

```sql
select s.period_code into v_periodo from public.sections s where s.id = new.section_id;
```

Si la sección no existiera, la FK lo impediría igualmente, pero se comprueba
explícitamente para no llamar al chequeo con un período nulo —que lo dejaría
ciego— y se lanza `23503` → **400 `REFERENCIA_INVALIDA`**.

### `GET /cuadrante` — la rejilla completa en una llamada

Filtros: `periodo` (por defecto, el vigente), `seccionId`, `docenteId`, `aulaId`,
`incluirInactivas` (por defecto `false`).

```json
{
  "periodo": "2026-1",
  "clases":  [ { "id": "…", "seccionId": "…", "docenteId": "…", "aulaId": "…",
                 "dia": 3, "bloque": 5, "turno": "MAÑANA", "activa": true,
                 "periodo": "2026-1", "materia": "Soldadura por Arco",
                 "seccion": "SC", "aula": "Taller de Soldadura Cabina A",
                 "docente": "Luis Márquez",
                 "creadoEn": "…", "actualizadoEn": "…" } ],
  "guardias": [ { "id": "…", "docenteId": "…", "aulaId": "…", "periodo": "2026-1",
                  "dia": 1, "bloque": 1, "turno": "MAÑANA",
                  "notas": null, "activa": true,
                  "creadoEn": "…", "actualizadoEn": "…" } ],
  "aulas": [ { "id": "…", "nombre": "…", "capacidad": 12, "esTaller": true,
               "activa": true, "creadoEn": "…", "actualizadoEn": "…" } ],
  "docentes": [ { "id": "…", "nombre": "Luis Márquez" } ]
}
```

**Las cuatro listas en una sola llamada, y no por comodidad.** La rejilla
necesita pintar las clases, las guardias, las columnas de aulas y las filas de
docentes **a la vez**: son las cuatro dimensiones de la misma rejilla. Con
cuatro peticiones, la pantalla puede quedar a medio pintar mostrando una guardia
junto a una clase que ya no existe, y el administrador no sabría si eso es un
choque real o una pantalla desactualizada. Una sola respuesta es coherente por
construcción.

`docentes` sale de un `select` filtrado a `rol in ('docente','admin') and active`
y **sólo proyecta `id` y nombre** — no la fila de `profiles`. La RLS de `profiles`
(`profiles_read_own`) impide al admin leer las filas ajenas, y **relajarla
expondría `cedula` y `email` de todo el centro**: RLS no es por columna, así que
abrir `profiles` para leer un nombre entrega la tabla entera. Por eso el nombre
se resuelve con `nombre_para_mostrar(uuid)` (§7).

---

## 7. `GET /api/v1/mi-horario` — docente y estudiante

Una sola ruta para los dos roles, porque el aislamiento ya lo garantiza la RLS y
lo único que cambia es qué filas sobreviven al filtro.

```json
{
  "rol": "docente",
  "periodo": "2026-1",
  "clases":   [ { "…": "…" } ],
  "guardias": [ { "…": "…" } ]
}
```

| Rol | `clases` | `guardias` |
| --- | --- | --- |
| `docente` | las suyas (`schedule_slots.teacher_id = auth.uid()`) | las suyas (`teacher_duties.teacher_id = auth.uid()`) |
| `estudiante` | las de **su sección**, vía `enrollments` | **siempre vacío** |
| `admin` | — | — |

Un `admin` recibe **403 `PERFIL_SIN_ROL`**: su agenda no existe, y devolverle un
horario vacío haría creer que no tiene ninguna. Si quiere ver la rejilla, la ruta
es `/admin/cuadrante`.

### El nombre del docente, sin abrir `profiles` (R-14)

Un estudiante necesita ver **quién** dicta su clase, pero `profiles_read_own` le
impide leer la fila del docente. La solución no fue relajar la política —eso
expondría `cedula` y `email` de todos— sino una función estrecha:

```sql
public.nombre_para_mostrar(p_id uuid) returns text
-- security definer, stable; devuelve el nombre SÓLO si el perfil está activo y
-- su rol es docente o admin. De lo demás devuelve NULL.
```

`revoke all … from public, anon` y `grant execute … to authenticated`. No es una
puerta abierta: no acepta filtros, no devuelve filas, y para un perfil de
estudiante o inactivo devuelve `NULL`. Y hay una prueba que comprueba las **dos**
mitades: que el estudiante ve el nombre, y que sigue **sin** poder leer la fila.

---

## 8. Errores y traducción

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `PETICION_INVALIDA` | 400 | Zod: UUID mal formado, `dia` fuera de 1–6, `bloque` fuera de 1–12, `turno` enviado, campos desconocidos |
| `REFERENCIA_INVALIDA` | 400 | `23503`: el `docenteId`, `aulaId`, `seccionId` o `periodo` no existen |
| `REGISTRO_DUPLICADO` | 409 | `23505`: código de lapso o nombre de aula repetido |
| `RESTRICCION_VIOLADA` | 400 | `23514` sin mensaje de choque: datos que no cumplen una regla |
| **`CHOQUE_DE_AGENDA`** | **409** | `23514` **con** mensaje de choque: el docente o el espacio ya están ocupados en ese bloque |
| `PERMISO_DENEGADO` | 403 | `42501`: la RLS rechazó la escritura |
| `AULA_INEXISTENTE` / `GUARDIA_INEXISTENTE` / `CLASE_INEXISTENTE` | 404 | el `:id` no existe |

### `CHOQUE_DE_AGENDA`: el mismo `23514` que `RESTRICCION_VIOLADA`, y por qué se separan

Un choque de agenda **no es un dato inválido**: los datos están bien y el
**estado actual** es el que no admite la operación. Merece `409`, como
`PENSUM_EN_USO` en M2, porque la UI tiene que poder decir «ese docente ya está en
el taller a esa hora» y no un genérico «datos inválidos».

Pero el trigger lanza `23514`, igual que un `check` corriente, así que los dos
llegan con el **mismo código**. Se distinguen por el **texto del mensaje**, con
la misma técnica y por el mismo motivo que M2: cambiar el `errcode` exigiría una
migración sobre triggers ya aplicados, y **una migración aplicada no se edita
nunca**.

Los dos mensajes, copiados literalmente de la migración:

```
Ese docente ya tiene una clase o guardia asignada el % en el bloque %. Un docente
no puede estar en dos sitios a la vez.

Ese espacio ya está ocupado el % en el bloque %. Dos grupos no pueden compartir
el mismo sitio a la misma hora.
```

```ts
// backend/src/dominio/reglas-cuadrante.ts
export function esChoqueDeAgenda(mensaje: string): boolean;
```

Se prueba con el **texto literal copiado de la migración**, no con uno inventado:
si el mensaje de la base cambiara, esa prueba es la que avisa.

**Y si la detección fallara, el peor caso es un `400` en vez de un `409`.** La
operación **se sigue bloqueando**, porque la invariante la impone el trigger, no
el traductor. El `409` existe para que el cliente pueda ser útil, no para
proteger nada. Es exactamente el mismo reparto que en M2.

---

## 9. La colisión: por qué no hay un `unique`

Un `unique (teacher_id, day_of_week, block)` sería **incorrecto**, y conviene
dejar escrito por qué para que nadie lo «arregle»:

1. **La colisión cruza dos tablas.** Un docente no puede estar en una clase y en
   una guardia a la vez, y eso vive en `schedule_slots` **y** en
   `teacher_duties`. Ningún `unique` sobre una sola tabla puede expresarlo.
2. **El período no está en `schedule_slots`.** Se deriva de la sección. Un
   `unique (teacher_id, day_of_week, block)` **prohibiría** que el mismo docente
   dictara el mismo bloque en dos lapsos distintos —que es planificar el
   siguiente, algo perfectamente legítimo—.

Por eso la regla vive en **una función compartida** y **dos triggers finos**:

```
public.exigir_agenda_libre(periodo, dia, bloque, docente, aula, origen, id)
   ├── teacher_duties_exigir_agenda()   → 'teacher_duties'
   └── schedule_slots_exigir_agenda()   → 'schedule_slots'
```

La función hace **dos** comprobaciones —docente y espacio— y cada una consulta
**las dos tablas** con un `union all`. El parámetro `origen`/`id` permite
actualizar una fila sobre su propio hueco sin que se rechace a sí misma.

### La carrera entre dos administradores

Dos peticiones simultáneas pueden pasar las dos por el `exists` antes de que
ninguna haya escrito. Se serializa con:

```sql
perform pg_advisory_xact_lock(hashtext(p_periodo || '|' || p_dia || '|' || p_bloque));
```

El cerrojo es **de transacción** (se libera solo al terminar) y está indexado por
`(período, día, bloque)`: sólo se serializan las escrituras que podrían chocar
entre sí. Dos guardias en bloques distintos no se esperan mutuamente.

**Un `unique` no habría necesitado nada de esto** —es una lección que conviene
tener presente—, pero un `unique` no puede expresar la regla real.

---

## 10. El fallo que encontró el despliegue, y por qué las pruebas no lo vieron

Vale la pena contarlo entero, porque es la lección más útil de este módulo.

### Qué pasó

La migración `202609180001` dejó los dos envoltorios de trigger como `security
invoker` y, a la vez, revocó el `EXECUTE` de `exigir_agenda_libre()` a `public`,
`anon` y `authenticated`. Con `security invoker` el envoltorio corre con los
privilegios de quien escribe —un `admin` autenticado— que **no** tiene `EXECUTE`
sobre la función delegada. Resultado, comprobado contra la nube:

```
ERROR: 42501: permission denied for function exigir_agenda_libre
CONTEXT: PL/pgSQL function teacher_duties_exigir_agenda() line 9 at PERFORM
```

**Toda alta de guardia o de clase fallaba.** El módulo era inoperable para
cualquier usuario real, y la protección anti-colisión ni se evaluaba.

### Por qué la batería de 164 aserciones no lo vio

Porque las pruebas del trigger escribían **como el dueño de las tablas**
(`postgres`), y **el dueño se salta la comprobación de privilegios de función**.
El caso pasaba por el camino que nunca ocurre en producción.

> Un doble que corre con más permisos que el usuario real no prueba al usuario
> real. Es la misma trampa que el proyecto ya documentó con los repositorios en
> memoria: un doble no reproduce el motor real.

### La corrección (`202609180002`)

Los dos envoltorios pasan a **`security definer`**, con `set search_path`
fijado (obligatorio en una función `definer`). Así la comprobación de `EXECUTE`
se hace contra el dueño, que sí lo tiene.

Esto **no amplía** lo que el llamante puede escribir:

- La RLS de la tabla se evalúa aparte, en el ejecutor de la sentencia, y sigue
  exigiendo `is_admin()`.
- El envoltorio sólo comprueba y **no devuelve dato alguno**.
- No es invocable a mano: PostgreSQL no permite llamar directamente a una
  función que devuelve `trigger`.
- La función delegada **sigue sin `EXECUTE` para nadie**. La puerta es el trigger.

Y no se «arregló» concediendo `EXECUTE` a `authenticated`, que también habría
funcionado: eso convertiría la función en un **oráculo de la agenda ajena**
(«¿está ocupado el jueves a las 9?») y en un grifo del `pg_advisory_xact_lock`.

### Lo que quedó para que no vuelva

1. **La sección 14.8 de `supabase/tests/validate.mjs`** escribe como lo hace el
   backend: rol `authenticated` con los claims de un admin. Si alguien devuelve
   los envoltorios a `invoker`, se cae.
2. **`verificar-esquema.mjs` comprueba `prosecdef`** de los dos envoltorios
   contra la nube. Es la aserción que hace imposible reintroducir la regresión en
   silencio.
3. Se demostró que las pruebas nuevas **fallan** con el fallo presente
   (fail-first): sin la corrección, las cuatro aserciones de 14.8 se caen con
   `42501`.

> **Detalle que casi engaña a la propia prueba:** «el trigger sigue protegiendo»
> **pasaba** con el fallo presente, porque sólo exigía *algún* error y recibía
> `42501` en vez de `23514`. Por eso la aserción siguiente comprueba el **código**
> y no la mera existencia de un error. Una prueba que acepta cualquier error no
> prueba la regla; prueba que algo se rompió.

---

## 11. RLS y vistas: dónde está la frontera de acceso

**El backend no usa `service_role` para datos.** Viaja con el JWT del llamante,
así que **la RLS es la frontera real**, no una red de seguridad por detrás de la
API. De ahí que cada política esté pensada como la única barrera:

| Tabla | `anon` | `docente` | `estudiante` | `admin` |
| --- | --- | --- | --- | --- |
| `academic_periods` | lee | lee | lee | todo |
| `classrooms` | **nada** | lee | lee | todo |
| `teacher_duties` | **nada** | **sólo las suyas** | **nada** | todo |
| `schedule_slots` | **nada** | **sólo las suyas** | **las de su sección** | todo |

`anon` no alcanza aulas ni agenda —ni siquiera el `GRANT`—, y recibe `42501`, no
una lista vacía. **Una lista vacía ocultaría un error de configuración**: el
formulario de inscripción no necesita la agenda, así que un «0 filas» sería
indistinguible de «la política está mal». El rechazo explícito se distingue.

Para un estudiante, «nada» en `teacher_duties` es **ausencia de política**: no se
escribió una política que devuelva vacío, no se escribió ninguna. Es la
diferencia entre una puerta cerrada con llave y una puerta pintada en la pared.

### Las tres vistas, y por qué `security_invoker`

`v_cuadrante_clases`, `v_cuadrante_guardias` y `v_periodo_vigente` se declaran
`with (security_invoker = true)`, igual que `cursos` desde D12. **Sin eso la vista
corre con los privilegios de su dueño y se salta la RLS de las tablas base**: un
estudiante vería el cuadrante de todo el centro, que es exactamente el dato que
las políticas existen para acotar. `verificar-esquema.mjs` comprueba el
`security_invoker` de las tres.

---

## 12. Estado del despliegue

| # | Elemento | Estado |
| --- | --- | --- |
| 1 | `academic_periods`, `classrooms`, `teacher_duties`, `schedule_slots` | ✅ Aplicadas, con RLS |
| 2 | `sections.period_code` → FK a `academic_periods` (R-12) | ✅ Aplicada |
| 3 | Trigger `system_settings_periodo_registrado` | ✅ Aplicado |
| 4 | `exigir_agenda_libre()` + 2 envoltorios + 2 triggers | ✅ Aplicados y **corregidos** (`202609180002`, §10) |
| 5 | `nombre_para_mostrar()` | ✅ Aplicada |
| 6 | 3 vistas con `security_invoker` | ✅ Aplicadas |
| 7 | Libro mayor de migraciones | ✅ **10/10**, sin deriva |
| 8 | `verificar-esquema.mjs` | ✅ **81/81** contra la nube |
| 9 | `supabase/tests` | ✅ **164** aserciones |
| 10 | Las 14 rutas de §1 | ⏳ **PASO 4** — pendientes |

**Lo que falta de M3:** el backend (PASO 4) y el frontend. El esquema no va a
moverse, así que ambos se pueden construir contra este contrato sin esperar.

### Decisiones abiertas, que no son mías

| Ref | Decisión | Quién |
| --- | --- | --- |
| **R-06** | Nomenclatura del lapso (`2026-1` vs `SA26-2`) | Coordinación del INCES. Ya no bloquea: es un `PATCH` |
| **R-16** | Frontera de turnos: bloque 1–6 mañana, 7–12 tarde | Coordinación. Provisional y en **una sola función** (`turno_de_bloque`) |
| **R-17** | Fechas reales del lapso | El centro. Nulas a propósito, no inventadas |
| **R-18** | Inventario real de aulas y zonas | El centro. Sin semilla a propósito |

Cambiar cualquiera de las cuatro **no exige tocar código**: son datos, o una
función de una línea.
