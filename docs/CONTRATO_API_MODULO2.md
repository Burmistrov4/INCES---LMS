# Contrato de API — Módulo 2 (Currículo y Pensum)

> **Estado:** diseño. Ninguna de estas rutas está implementada todavía, y la
> migración `202609150001_mod2_curriculo.sql` **no está aplicada** a la nube.
> Este documento es la especificación a implementar, no una descripción de lo
> que existe. Lo que existe está en `ESTADO_DEL_SISTEMA.md` §4.

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
usuario lo intente. `seccionesActivas` hoy devuelve `0` siempre, porque
`sections.program_id` no existe todavía (deuda D13). **La ruta se implementa con
el campo puesto a `0` y una nota**, no con un `TODO` que mienta.

**404 `PERFIL_INEXISTENTE`** si el `:id` no es UUID → **400 `PETICION_INVALIDA`**
(validador `esquemaRutaIdPrograma`, igual que `esquemaRutaIdPerfil`); si es UUID
y no existe → **404 `NO_ENCONTRADO`**.

---

## 5. `POST /api/v1/admin/programas` — el asistente

Una sola petición con todo. Es lo que permite que el constraint trigger diferido
valide el pensum al confirmar la transacción.

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

Reemplaza el pensum completo. **Es un reemplazo, no un parche**: el cliente manda
el estado final y el servidor calcula la diferencia. Un `PATCH` incremental
obligaría al cliente a saber qué borrar, y el cliente no debería tener esa
responsabilidad.

**Body** (`esquemaReemplazarPensum`):

```json
{ "pensum": [ { "materiaId": "3f2b…", "periodo": 2 } ] }
```

**En una transacción:** insertar lo nuevo, actualizar el `period_order` de lo que
cambió y borrar lo que ya no está. El borrado es la única operación del módulo
que necesita `DELETE` a nivel de tabla, y por eso `program_subjects` es la única
de las tres tablas con ese `GRANT`.

**Errores:**

| Código | HTTP | Cuándo |
| --- | --- | --- |
| `PETICION_INVALIDA` | 400 | Pensum vacío, materia repetida |
| `RESTRICCION_VIOLADA` | 400 | El reemplazo dejaría el programa activo sin materias |
| `PENSAM_*` | — | **Pendiente:** el 409 de la Regla 2 (secciones activas) necesita `sections.program_id` (D13). Hasta entonces la regla no se puede comprobar y la ruta no debe fingir que sí |

> **Nota de honestidad para el TEG.** Mientras D13 no se resuelva, esta ruta
> permite reordenar el pensum de un programa en uso. La regla está escrita en la
> migración y aquí, y su ausencia es una decisión registrada, no un olvido. La
> alternativa —implementar una comprobación que siempre devuelve `false`— sería
> peor: haría creer que la regla está activa.

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

/** Un pensum agrupado por período, con los períodos ordenados y sin huecos. */
export function agruparPensum(entradas: EntradaPensum[]): GrupoPensum[];

/**
 * Rechaza un pensum con materias repetidas. Devuelve el código repetido, no un
 * booleano: el mensaje de error tiene que nombrar la materia, no decir "error".
 */
export function materiaRepetida(entradas: EntradaPensum[]): string | null;

/**
 * Decide si el pensum se puede tocar. `seccionesActivas > 0` bloquea.
 * Hoy recibe siempre 0 porque sections.program_id no existe (D13): la función
 * se escribe y se prueba igual, para que el día que M3 llegue sólo cambie el
 * repositorio.
 */
export function pensumEditable(seccionesActivas: number): boolean;
```

`agruparPensum` se prueba con un caso que importa: períodos `[1, 2, 5]` deben
devolver **tres** grupos, no cinco con dos vacíos. Un `CURSO_LIBRE` con
`periodo: 1` devuelve un solo grupo.

---

## 10. Qué falta antes de implementar

1. **D12** — decidir si `programs` absorbe a `cursos`. Afecta al formulario
   público de inscripción y a `aspirantes.curso_seleccionado`.
2. **D13** — decidir el rediseño de `sections`. Sin `sections.program_id`, la
   Regla 2 no se puede implementar y la cabecera del cuadrante de M3 queda
   ambigua (una materia puede estar en varios programas).
3. **Aplicar la migración** y, en el mismo paso, añadir `programs`, `subjects` y
   `program_subjects` al arreglo `esperadas` de `verificar-esquema.mjs`.
4. **Declarar las 7 rutas** en la lista esperada de `test/openapi.test.ts`: el
   test obliga a que ninguna ruta quede sin documentar.
