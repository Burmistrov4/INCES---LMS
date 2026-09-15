# Contrato de API — Módulo 2 (Currículo y Pensum)

> **Estado (2026-09-15):** el **esquema está aplicado y verificado** en la nube
> (8/8 migraciones en el libro mayor, 56/56 comprobaciones del esquema), y las
> **dos funciones transaccionales que sostienen el asistente están aplicadas y
> probadas contra el motor real** (`supabase/humo-curriculo.mjs`, 14/14). Las
> rutas HTTP de este documento están **en construcción**: el diseño está cerrado
> y verificado, los manejadores todavía no existen. Lo que existe está en
> `ESTADO_DEL_SISTEMA.md` §9–§11; el porqué de las funciones, en `REPORTE_ARIA.md`
> R-10.

Base: `/api/v1`. Todo error responde con la forma ya establecida:

```json
{ "error": { "codigo": "RESTRICCION_VIOLADA", "mensaje": "…", "detalles": { "contexto": "…" } } }
```

Los códigos de error son los de `backend/src/dominio/errores.ts`. Este módulo no
inventa ninguno nuevo.

---

## 1. Rutas

| Método | Ruta | Acceso | Qué hace |
| --- | --- | --- | --- |
| `GET` | `/api/v1/admin/programas` | admin | Lista paginada de programas |
| `GET` | `/api/v1/admin/programas/:id` | admin | Detalle con el pensum agrupado por período |
| `POST` | `/api/v1/admin/programas` | admin | **El asistente**: programa + pensum, atómico |
| `PATCH` | `/api/v1/admin/programas/:id` | admin | Metadatos: `name`, `requiresInternship`, `isActive` |
| `PATCH` | `/api/v1/admin/programas/:id/pensum` | admin | Reemplaza el pensum completo |
| `GET` | `/api/v1/admin/materias` | admin | Banco global de materias, paginado |
| `POST` | `/api/v1/admin/materias` | admin | Registra una materia en caliente |

**Ninguna ruta borra.** Archivar es `isActive: false`. Un `DELETE` sobre un
programa se llevaría por delante el histórico, y `program_subjects.subject_id`
está en `on delete restrict` precisamente para que borrar una materia en uso no
sea posible ni por accidente.

**Sobre la ruta del documento de arquitectura.** El documento pide
`POST /api/v1/programs/setup`. Aquí es `POST /api/v1/admin/programas`. Las rutas
de administración del proyecto ya viven bajo el prefijo `/api/v1/admin`, y ese
prefijo es el que aplica la guardia `exigirAdmin`: una ruta fuera de él no
tendría control de acceso. **El documento debe actualizarse**, o el TEG
documentará una ruta que no existe.

---

## 2. Tipos compartidos

```ts
export type TipoPrograma = 'CARRERA' | 'CURSO_LIBRE';

export interface Programa {
  id: string;                  // uuid
  codigo: string;              // varchar(12), MAYÚSCULAS/dígitos/guion
  nombre: string;              // varchar(100)
  tipo: TipoPrograma;
  requierePasantia: boolean;   // requires_internship
  activo: boolean;             // is_active
  creadoEn: string;            // ISO 8601
  actualizadoEn: string;
}

export interface Materia {
  id: string;
  codigo: string;
  nombre: string;
  horasAcademicas: number;     // > 0
  creadoEn: string;
  actualizadoEn: string;
}

export interface EntradaPensum {
  materiaId: string;
  periodo: number;             // >= 1
}

/** Una entrada del pensum ya agrupada, tal como la devuelve `GET /:id`. */
export interface GrupoPensum {
  periodo: number;
  materias: EntradaPensum[];
}
```

**Convención de nombres, y por qué importa.** La base de datos usa inglés
(`code`, `name`, `requires_internship`) porque así lo define el documento de
arquitectura. La API y Dart usan español (`codigo`, `nombre`,
`requierePasantia`). La traducción ocurre **en la capa de repositorio**, en un
único sitio, igual que ya se hace con `auth_logs` — donde el campo de dominio es
`createdAt` y el modelo Dart lo llama `creadoEn`. Confundir las dos capas es
exactamente el error que costó dos fallos falsos en el humo de M1.

---

## 3. `GET /api/v1/admin/programas`

**Query** (`esquemaListadoProgramas`, `.strict()`):

| Campo | Tipo | Por defecto | Notas |
| --- | --- | --- | --- |
| `tipo` | `'CARRERA' \| 'CURSO_LIBRE'` | — | opcional |
| `activo` | `boolean` (coercionado) | — | opcional; ausente = todos |
| `busqueda` | `string` (1–100) | — | contra `codigo` y `nombre`, insensible a mayúsculas |
| `limite` | `number` 1–100 | `25` | |
| `desplazamiento` | `number` ≥ 0 | `0` | |

**200:**

```json
{
  "programas": [
    { "id": "…", "codigo": "SIST-01", "nombre": "Análisis de Sistemas",
      "tipo": "CARRERA", "requierePasantia": true, "activo": true,
      "totalMaterias": 32, "totalPeriodos": 6,
      "creadoEn": "2026-09-15T10:00:00.000Z", "actualizadoEn": "2026-09-15T10:00:00.000Z" }
  ],
  "total": 12, "limite": 25, "desplazamiento": 0
}
```

`totalMaterias` y `totalPeriodos` salen de la misma consulta que la página (un
`count` agregado en la vista de PostgREST), no de N+1 consultas: la pantalla
necesita saber si un programa está vacío para avisar antes de que el
administrador intente publicarlo.

**Paginación:** se cuenta el total **primero** (`head: true, count: 'exact'`) y
se devuelve página vacía si `desplazamiento >= total`. Es el patrón de
`PerfilesSupabase.listar`.

---

## 4. `GET /api/v1/admin/programas/:id`

**200:**

```json
{
  "programa": { "…": "…" },
  "pensum": [
    { "periodo": 1,
      "materias": [
        { "materiaId": "…", "codigo": "ALG-I", "nombre": "Algorítmica",
          "horasAcademicas": 96 }
      ] }
  ],
  "seccionesActivas": 0,
  "editable": true
}
```

`editable` es la materialización de la **Regla 2**: `false` cuando
`seccionesActivas > 0`, y la UI deshabilita el reordenamiento antes de que el
usuario lo intente, en vez de dejarlo chocar contra el `409`.

`seccionesActivas` cuenta las secciones **activas del período vigente**
(`system_settings.periodo_activo`) que apuntan a ese programa. Es un número real
desde que D13 añadió `sections.program_id`. Hasta entonces esta ruta tenía que
devolver `0` y decirlo por escrito: una comprobación que siempre devuelve `false`
haría creer que la regla estaba activa, que es peor que no tenerla.

**404 `PERFIL_INEXISTENTE`** si el `:id` no es UUID → **400 `PETICION_INVALIDA`**
(validador `esquemaRutaIdPrograma`, igual que `esquemaRutaIdPerfil`); si es UUID
y no existe → **404 `NO_ENCONTRADO`**.

---

## 5. `POST /api/v1/admin/programas` — el asistente

Una sola petición con todo, ejecutada por la función
**`public.crear_programa_con_pensum(...)`** dentro de **una sola transacción**.

### Por qué una función y no un insert anidado

PostgREST **no admite insertar un padre con sus hijos en la misma petición**. Se
comprobó contra la base real el 2026-09-15, no se supuso:

| Prueba | Resultado |
| --- | --- |
| `POST /programs` con `program_subjects: [...]` | `PGRST204: Could not find the 'program_subjects' column of 'programs' in the schema cache` |
| Lo mismo tras `notify pgrst, 'reload schema'` | Idéntico — **no era la caché** |
| `GET /programs?select=*,program_subjects(*)` | **HTTP 200** — la relación existe |

Es decir: **se puede leer anidado, pero no escribir anidado.** Y PostgREST no
expone transacciones entre peticiones: cada petición es su propia transacción.

Sin función, el asistente tendría que hacer tres llamadas —crear en borrador,
insertar el pensum, publicar—. Cada paso intermedio es un estado válido, así que
los triggers no se quejarían, pero **un fallo entre el segundo y el tercero deja
un programa a medio armar**, que es justo lo que este contrato quiere evitar.

La función se declara **`security invoker`**, y eso no es un detalle: con
`security definer` correría con los privilegios de su dueño y **se saltaría la
RLS**, de modo que cualquier autenticado podría escribir programas. El relato
completo está en `ESTADO_DEL_SISTEMA.md` §11 y en `REPORTE_ARIA.md` R-10.

El repositorio llama a la función por `supabase.rpc('crear_programa_con_pensum',
{ … })` y **nunca hace un `insert` directo** sobre `programs` ni sobre
`program_subjects`: si lo hiciera, se saltaría la atomicidad que la función
existe para dar.

**Body** (`esquemaCrearPrograma`, `.strict()`):

```json
{
  "codigo": "SIST-01",
  "nombre": "Análisis de Sistemas",
  "tipo": "CARRERA",
  "requierePasantia": true,
  "publicar": true,
  "pensum": [
    { "materiaId": "3f2b…", "periodo": 1 },
    { "materiaId": "9c14…", "periodo": 1 },
    { "materiaId": "7ad0…", "periodo": 4 }
  ]
}
```

| Campo | Regla |
| --- | --- |
| `codigo` | `string().min(1).max(12).regex(/^[A-Z0-9][A-Z0-9-]{0,11}$/)` |
| `nombre` | `string().trim().min(1).max(100)` |
| `tipo` | `z.enum(['CARRERA', 'CURSO_LIBRE'])` |
| `requierePasantia` | `boolean().default(false)` |
| `publicar` | `boolean().default(false)` — decide el `is_active` inicial |
| `pensum` | `array().min(1)` — **al menos una materia**, ver abajo |
| `pensum[].periodo` | `number().int().min(1).default(1)` |
| `pensum[].materiaId` | `string().uuid()` |

**Dos validaciones en Zod, no en la base.** `pensum.min(1)` y la unicidad de
`materiaId` dentro del arreglo se comprueban en el esquema. La base tiene sus
propias restricciones (`unique (program_id, subject_id)`, el constraint trigger),
pero Zod da el mensaje antes de abrir una transacción y nombra el campo culpable.
Dos barreras: la misma decisión que con RLS.

**201:**

```json
{ "programa": { "…": "…" }, "pensum": [ { "periodo": 1, "materias": [ "…" ] } ] }
```

**Errores:**

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `PETICION_INVALIDA` | 400 | Fallo de Zod: código con formato inválido, pensum vacío, materia repetida |
| `REGISTRO_DUPLICADO` | 409 | `23505`: el código de programa o de materia ya existe |
| `REFERENCIA_INVALIDA` | 400 | `23503`: algún `materiaId` no existe en `subjects` |
| `RESTRICCION_VIOLADA` | 400 | `23514`: el constraint trigger diferido rechazó el pensum vacío |

> **`RESTRICCION_VIOLADA` en un `POST` con `pensum.min(1)` parece
> inalcanzable — y no lo es.** Zod sólo ve lo que llega; el trigger ve el estado
> de la tabla. Un `publicar: true` sobre un programa que ya existe con el pensum
> vacío entra por `PATCH`, no por aquí. Y si alguien escribe directo en la base,
> la regla sigue en pie. La barrera de Zod es comodidad; la de la base es la
> invariante.

---

## 6. `PATCH /api/v1/admin/programas/:id`

**Body** (`esquemaActualizarPrograma`, `.strict()`, todos opcionales pero al
menos uno):

```json
{ "nombre": "Análisis de Sistemas", "requierePasantia": false, "activo": true }
```

`codigo` y `tipo` **no se pueden cambiar**: son la identidad del programa, y
`sections` (M3) apuntará a él. Un código cambiado rompe cualquier documento
impreso que lo cite.

Publicar (`activo: true`) sobre un programa sin materias → **400
`RESTRICCION_VIOLADA`** desde el trigger diferido. Es el caso real que el
trigger existe para atrapar.

---

## 7. `PATCH /api/v1/admin/programas/:id/pensum`

Reemplaza el pensum completo, ejecutado por la función
**`public.reemplazar_pensum(...)`**. **Es un reemplazo, no un parche**: el cliente
manda el estado final y la función calcula la diferencia. Un `PATCH` incremental
obligaría al cliente a saber qué borrar, y el cliente no debería tener esa
responsabilidad.

**Body** (`esquemaReemplazarPensum`):

```json
{ "pensum": [ { "materiaId": "3f2b…", "periodo": 2 } ] }
```

**En una transacción**, la función hace tres cosas en este orden:

1. **Borra** lo que ya no está en el pensum nuevo.
2. **Reordena** lo que cambió de período.
3. **Inserta** lo nuevo.

El orden no cambia la atomicidad —un fallo lo deshace todo— pero sí cambia qué
error ve el administrador primero: el más explicativo, que es el del borrado.

Importa además por otra razón: el trigger de la Regla 2 está acotado a
`update of period_order, program_id or delete`. **Insertar no lo dispara**, porque
añadir una materia a un pensum en uso es legítimo; quitar o reordenar, sí. La
función respeta ese reparto en vez de borrar todo y volver a insertar, que
bloquearía hasta el guardado más inocente.

### La Regla 2 ya está activa: esto es lo que cambió

Hasta que D13 se resolvió, esta ruta no podía comprobar nada, porque la condición
dependía de `sections.program_id` y esa columna no existía. **Ya existe**, el
trigger está aplicado y la regla se cumple de verdad. La nota de honestidad que
antes decía «mientras D13 no se resuelva» ya no aplica: se cumplió.

Eso obliga a distinguir dos errores que la base lanza con el **mismo código**,
`23514`:

| Regla | Qué significa | HTTP | Código |
| --- | --- | --- | --- |
| Regla 1 | Los datos están mal: una carrera activa se quedaría sin materias | **400** | `RESTRICCION_VIOLADA` |
| Regla 2 | No es un dato inválido: hay un **conflicto con el estado actual** | **409** | `PENSUM_EN_USO` |

Se distinguen leyendo el mensaje del trigger (`esBloqueoPorPensumEnUso`), porque
cambiar el código de error habría exigido una migración nueva sobre triggers ya
aplicados, y **una migración aplicada no se edita nunca**. Una prueba ancla el
texto real copiado de la migración, y el humo contra la base comprueba que sigue
coincidiendo.

Si el mensaje cambiara y la detección fallara, el peor caso es un `400` en vez de
un `409`: **la operación se sigue bloqueando**, porque la invariante la impone el
trigger, no el traductor. El `409` existe para que el cliente pueda ofrecer
«archiva esas secciones primero» en vez de un error genérico.

**Errores:**

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `PETICION_INVALIDA` | 400 | Pensum vacío, materia repetida |
| `RESTRICCION_VIOLADA` | 400 | El reemplazo dejaría el programa activo sin materias (Regla 1) |
| `PENSUM_EN_USO` | 409 | Hay secciones activas del período vigente usando el programa (Regla 2) |
| `REFERENCIA_INVALIDA` | 400 | Algún `materiaId` no existe en `subjects` |

---

## 8. `GET /api/v1/admin/materias` y `POST /api/v1/admin/materias`

`GET` — mismo patrón de paginación. Filtros: `busqueda` (contra `codigo` y
`nombre`), `limite`, `desplazamiento`. Alimenta la columna izquierda del paso 2
del asistente, con buscador en tiempo real.

```json
{ "materias": [ { "id": "…", "codigo": "ALG-I", "nombre": "Algorítmica",
                  "horasAcademicas": 96, "creadoEn": "…", "actualizadoEn": "…" } ],
  "total": 84, "limite": 25, "desplazamiento": 0 }
```

`POST` — el modal «registrar materia en caliente» del paso 2:

```json
{ "codigo": "BD-II", "nombre": "Bases de Datos II", "horasAcademicas": 96 }
```

| Campo | Regla |
| --- | --- |
| `codigo` | `string().min(1).max(12).regex(/^[A-Z0-9][A-Z0-9-]{0,11}$/)` |
| `nombre` | `string().trim().min(1).max(100)` |
| `horasAcademicas` | `number().int().positive()` |

**201** con la materia creada. **409 `REGISTRO_DUPLICADO`** si el código ya
existe — la UI debe ofrecer seleccionar la existente en vez de mostrar sólo un
error, porque ése es el caso frecuente: la materia ya estaba en el banco.

---

## 9. Reglas de dominio, como funciones puras

Siguiendo `reglas-admin.ts` y `reglas-invitaciones.ts`: la decisión vive en una
función pura, probada sin montar HTTP ni repositorios.

```ts
// backend/src/dominio/reglas-curriculo.ts

/** Un pensum agrupado por período, con los períodos ordenados y sin grupos vacíos. */
export function agruparPensum(entradas: EntradaPensum[]): GrupoPensum[];

/**
 * Rechaza un pensum con materias repetidas. Devuelve el código repetido, no un
 * booleano: el mensaje de error tiene que nombrar la materia, no decir "error".
 */
export function materiaRepetida(entradas: EntradaPensum[]): string | null;

/**
 * Decide si el pensum se puede tocar. `seccionesActivas > 0` bloquea.
 * El número es real desde que D13 añadió `sections.program_id`; la función vive
 * aparte para que el repositorio sea lo único que cambie si la fuente de esa
 * cuenta cambia.
 */
export function pensumEditable(seccionesActivas: number): boolean;

/**
 * Distingue la Regla 2 de la Regla 1 dentro del mismo código `23514`, leyendo el
 * mensaje del trigger. Es la única función del módulo que mira un texto de la
 * base, y existe porque cambiar el código habría exigido una migración sobre
 * triggers ya aplicados, que son inmutables.
 */
export function esBloqueoPorPensumEnUso(mensaje: string): boolean;
```

`agruparPensum` se prueba con un caso que importa: períodos `[1, 2, 5]` deben
devolver **tres** grupos, no cinco con dos vacíos. Un `CURSO_LIBRE` con
`periodo: 1` devuelve un solo grupo.

`esBloqueoPorPensumEnUso` se prueba con el **texto literal del trigger copiado de
la migración**, no con uno inventado: si el mensaje de la base cambiara, esa
prueba es la que avisa. Y el humo contra la base real lo vuelve a comprobar.

---

## 10. Estado de los prerrequisitos

Los cuatro bloqueantes que este documento listaba **están resueltos**:

| # | Prerrequisito | Estado |
| --- | --- | --- |
| 1 | **D12** — decidir si `programs` absorbe a `cursos` | ✅ **Resuelto.** `programs` es la única fuente de verdad y `cursos` pasó a ser una vista de compatibilidad (`security_invoker`). Cero cambios en Flutter |
| 2 | **D13** — rediseñar `sections` | ✅ **Resuelto.** `sections` tiene `program_id`, y por eso la Regla 2 se pudo implementar como trigger |
| 3 | **Aplicar la migración** y añadir las tablas al verificador | ✅ **Resuelto.** 8/8 migraciones en el libro mayor y 56/56 comprobaciones del esquema |
| 4 | **Declarar las 7 rutas** en `test/openapi.test.ts` | ⏳ Se hace **junto con los manejadores**: ese test obliga a que ninguna ruta quede sin documentar, así que declararlas antes de que existan sería declarar rutas inventadas |

**Lo que falta, y en este orden:**

1. El repositorio `CurriculoSupabase`, que llama a las dos funciones por
   `supabase.rpc(...)` y traduce la Regla 2 con `esBloqueoPorPensumEnUso`.
2. Los siete manejadores bajo `/api/v1/admin/`.
3. Documentar las siete rutas en `src/http/openapi.ts` y regenerar el artefacto
   (`npm run openapi`).
4. Declarar las siete rutas en la lista esperada de `test/openapi.test.ts`.

Las dos funciones que sostienen el asistente **ya están aplicadas y probadas
contra el motor real**. `supabase/humo-curriculo.mjs` (14/14) demuestra las dos
cosas que ninguna prueba con dobles puede demostrar: que con el pensum vacío no
queda **ni el programa**, y que cuando la Regla 2 bloquea un reordenamiento el
pensum queda **intacto** — la función se deshace entera, no a medias.
