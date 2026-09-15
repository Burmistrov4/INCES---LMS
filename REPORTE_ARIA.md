# REPORTE_ARIA — Contradicciones entre el documento y el código base

> Bitácora de contradicciones detectadas al ejecutar la hoja de ruta autónoma.
> **Regla aplicada: gana el código.** Cuando el documento de arquitectura pide
> algo que el código base contradice, se implementa lo que respeta el código y se
> anota aquí. Cuando no hay ganador obvio, se marca **DECISIÓN PENDIENTE** y no se
> elige por cuenta propia.

---

## R-01 · El documento no tiene `sections.program_id` — y sin él el Módulo 3 no cierra

**Gravedad: alta. Bloqueaba D13 y la Regla 2 de M2.**

El documento define la cabecera del cuadrante así:

```
PERÍODO: {sections.period_code} | ESPECIALIDAD: {programs.name} | SECCIÓN: {sections.name}
```

Pero la tabla `sections` del documento **sólo tiene `subject_id`**, ningún enlace
al programa. El camino `sections → subjects → program_subjects → programs` no
resuelve la especialidad: una materia puede pertenecer a **varios** programas, que
es exactamente el motivo por el que el pensum es muchos-a-muchos. 'Inglés Técnico'
está en cinco pensums; la cabecera no sabría cuál imprimir.

**Gana el código:** se añadió `sections.program_id` con FK y `on delete restrict`.

**Consecuencia colateral positiva:** la Regla 2 de M2 ("no se toca el pensum de un
programa en uso") era inimplementable sin esta columna. Ahora existe y está
implementada y probada.

---

## R-02 · `programs.is_active DEFAULT TRUE` contradice la Regla 1 del propio documento

**Gravedad: media. Se detectó antes de aplicar nada.**

El documento pide, en la misma página:

| Afirmación | Fuente |
| --- | --- |
| `is_active BOOLEAN DEFAULT TRUE` | tabla `programs` |
| "Un programa de formación no puede pasar a estado Publicado o Activo si la tabla `program_subjects` asociada tiene un conteo de registros igual a cero" | Regla 1 |

Con `DEFAULT TRUE`, todo `insert into programs` crea un programa **activo y sin
materias**, que es precisamente el estado que la Regla 1 prohíbe. Las dos
afirmaciones no pueden ser ciertas a la vez.

**Gana el código:** `is_active` nace en **`false`**. Publicar (ponerlo activo) es
lo que dispara la validación, y el asistente de tres pasos manda el programa y su
pensum en la misma transacción, así que nunca ve el estado intermedio.

---

## R-03 · La Regla 1 dice "carreras", no "programas"

**Gravedad: media. Habría hecho inaplicable la migración de D12.**

El documento titula la regla "No existen carreras vacías" y la explica con "no
existen carreras vacías". Se implementó inicialmente para **todo** programa activo.

Eso hace imposible absorber los 5 cursos de Fase 0: 'Oratoria' o 'Herrería' son
talleres cortos sin malla curricular, y el trigger diferido rechazaría cualquier
curso libre activo que no tuviera pensum. La migración `202609160001` no habría
podido aplicarse.

**Gana el documento, leído al pie de la letra:** la regla se acota a
`type = 'CARRERA'`. Un CURSO_LIBRE puede estar activo sin pensum. Está corregido
en `202609150001` (que todavía no estaba aplicada, así que no se violó la regla de
inmutabilidad) y hay dos aserciones que lo prueban: una carrera vacía **sigue**
bloqueada, un curso libre vacío **ya no**.

---

## R-04 · `ENUM` de PostgreSQL frente a la convención escrita del proyecto

**Gravedad: baja. Inconsistencia de estilo, no de comportamiento.**

El documento pide `type ENUM ('CARRERA','CURSO_LIBRE')`. La migración de M1 ya
dejó escrita la convención contraria:

> "No se usa un enum de Postgres para no atarnos al dialecto."
> — `202609130001_invitaciones_docente.sql`, columna `auth_logs.estado`

**Gana el código:** `text` + `check (type in (...))`. Es la convención que el
proyecto ya aplica en `profiles.rol`, `aspirantes.sexo` y `auth_logs.estado`.

---

## R-05 · La ruta del documento no puede llevar el control de acceso

**Gravedad: media. Rompía la autorización, no el estilo.**

El documento pide `POST /api/v1/programs/setup`. En el backend, la autorización de
administrador la aplica el **prefijo** `/api/v1/admin` (`preHandler: exigirAdmin`).
Una ruta fuera de ese prefijo no tendría guardia: sería un endpoint de escritura
sin control de acceso.

**Gana el código:** `POST /api/v1/admin/programas`. **El documento debe
actualizarse**, o el TEG documentará una ruta que no existe y sin protección.

---

## R-06 · Dos convenciones de período incompatibles — **DECISIÓN PENDIENTE**

**Gravedad: alta. Es una guarda que no guarda y no avisa.**

| Dónde | Valor | Fuente |
| --- | --- | --- |
| `system_settings.periodo_activo` | `"2026-1"` | semilla real, verificada en la nube |
| Período de sección | `'SA25-5'`, `'SA26-2'` | documento, tabla `sections` |

La Regla 2 compara `sections.period_code` con `periodo_activo` por **igualdad
exacta**. Con las dos convenciones actuales, la comparación **nunca es verdadera**,
la regla nunca dispara, y el sistema permitiría reordenar el pensum de una carrera
en curso sin decir nada. Es el peor fallo posible: una guarda silenciosa.

Hay que elegir una y usarla en los dos sitios:

- **(a)** `AAAA-N` → `2026-1`. Es lo que ya está en `system_settings`.
- **(b)** `SA AAAA-N` → `SA26-2`. Es lo que dice el documento y lo que usa el
  propio centro (el equipo cursa SA26-2).

**No se elige por cuenta propia**: afecta a la semilla de producción y a la
nomenclatura institucional, que es una decisión de coordinación del INCES.
**Pendiente de tu decisión.** Mientras tanto, la Regla 2 funciona correctamente en
cuanto alguien cree una sección con el `period_code` idéntico al `periodo_activo`;
el problema es de convención, no de código.

---

## R-07 · `aspirantes.curso_seleccionado` referencia el catálogo por nombre

**Gravedad: media. Previa a esta sesión, no introducida por ella.**

`aspirantes.curso_seleccionado` es `text` y guarda el **nombre** del curso
('Oratoria'). Renombrar un programa rompe la referencia de todos los aspirantes
que lo eligieron, sin aviso.

La corrección es una columna `program_id` con FK, y toca el formulario público de
inscripción (`AspiranteFormScreen`), el gateway (`cursosDisponibles()`) y
`AspiranteRepository.cursosRespaldo`.

**No se hizo aquí** porque `aspirantes` está vacía (0 filas, verificado): no hay
nada que migrar y no hay urgencia. Queda como **D14** en `ESTADO_DEL_SISTEMA.md`.
Es trabajo de M1, no de M2.

---

## R-08 · El `sections` de Fase 0 no era una sección

**Gravedad: baja (nadie lo consumía), pero explica D13.**

La tabla `sections` creada en Fase 0 tenía `nombre`, `cupo_maximo`, `activa`. Sin
`subject_id`, una "sección" no estaba atada a ninguna materia: no representaba
"la sección SA de Algorítmica en 2026-1", sino "un grupo con un cupo". Era un
marcador de posición, y su forma no tenía relación con la que exige M3.

Verificado antes de tocarla: **0 filas y 0 consumidores en el código** (sólo
aparecía en la migración que la creó). Por eso se rediseñó completa en vez de
dejar media tabla que M3 tendría que volver a tocar.

**Gana el documento**, porque aquí no había nada que conservar.

---

## R-09 · `cursos` (Fase 0) y `programs` (M2) eran el mismo concepto — D12

**Gravedad: alta. Era una fuente de verdad duplicada.**

Los 5 cursos sembrados en Fase 0 ('Herrería', 'Oratoria', 'Estética (cejas y
pestañas)', 'Higiene y Manipulación de Alimentos', 'Curso Introductorio (15-16
años)') son exactamente `CURSO_LIBRE`. Mantener las dos tablas significaba que el
catálogo del formulario público y el catálogo del asistente de M2 podían divergir
en silencio.

**Gana el código** (una sola fuente de verdad): los 5 cursos se migraron a
`programs` conservando `id`, nombre y estado, y `cursos` pasó a ser una **vista de
compatibilidad** sobre `programs` con `security_invoker`.

Se eligió vista y no borrado directo por una razón concreta: el único consumidor
(`SupabaseService.cursosDisponibles()`) sigue funcionando **sin tocar una línea de
Dart**, y la app no queda rota entre esta migración y su migración a `programs`.
La vista no duplica datos. Se retira con `drop view public.cursos;` cuando Flutter
lea `programs` directamente.

---

## R-10 · El contrato pide "una transacción" y PostgREST no puede darla

**Contradicción.** `docs/CONTRATO_API_MODULO2.md` §5 dice que el asistente
construye el pensum *en una transacción*, y §7 pide lo mismo para el reemplazo
del pensum. La arquitectura que se dio por supuesta es la de un servidor con
acceso a la base y control de transacciones.

**Lo que dice el código.** El backend no habla con PostgreSQL: habla con
PostgREST a través de `supabase-js`. Y PostgREST **no expone transacciones entre
peticiones**: cada petición es su propia transacción. La forma de conseguir
atomicidad dentro de una petición sería un *insert anidado*.

**La medición, que es lo que decide.** Se probó contra la base real:

| Prueba | Resultado |
| --- | --- |
| `POST /programs` con `program_subjects: [...]` | `PGRST204: Could not find the 'program_subjects' column of 'programs' in the schema cache` |
| Lo mismo tras `notify pgrst, 'reload schema'` | Idéntico — **no era la caché** |
| `GET /programs?select=*,program_subjects(*)` | **HTTP 200** — la relación existe y PostgREST la conoce |

Conclusión medida: **se puede leer anidado, pero no escribir anidado.**

**Resolución — gana el código.** Se implementaron las dos operaciones como
funciones de PostgreSQL (`crear_programa_con_pensum`, `reemplazar_pensum`) en
`supabase/migrations/202609170001_mod2_rpc_curriculo.sql`, llamadas por
PostgREST. Es el mecanismo que el proyecto **ya usaba** para la lógica que debe
ser atómica (`precheck_aspirante`, `link_pending_aspirante`), así que no
introduce una arquitectura nueva: aplica la existente.

Las dos funciones son `security invoker` a propósito: con `security definer` se
saltarían la RLS y cualquier autenticado podría escribir programas.

**Alternativa descartada, y por qué.** Sin tocar la base se podía hacer una
secuencia de tres llamadas (crear en borrador → insertar pensum → publicar). Cada
paso intermedio es un estado válido, así que los triggers no se quejan. Se
descartó porque **un fallo entre el segundo y el tercero deja un programa a medio
armar**, que es justo lo que el contrato quiere evitar. La barrera de la base
seguiría intacta, pero el administrativo se encontraría un borrador sin
explicación.

**Verificación.** Humo contra el PostgREST real: la `CARRERA` activa con pensum se
crea en una llamada; con el pensum vacío la función falla con `23514` y **no deja
ni el programa** — atomicidad demostrada, no argumentada.

**Consecuencia para el documento.** `docs/CONTRATO_API_MODULO2.md` §5, §7 y §10
siguen describiendo el diseño anterior a D13 y sin las funciones. Debe
actualizarse: la ruta existe, pero su implementación pasa por dos RPC.

| ID | Contradicción | Resolución | Estado |
| --- | --- | --- | --- |
| R-10 | El contrato pide una transacción; PostgREST no la puede dar | Dos funciones RPC | ✅ Resuelta (el documento debe actualizarse) |

---

## R-11 · El filtro `or` de PostgREST: una trampa medida, y una sonda que mintió

**No es una contradicción del documento.** Se registra aquí porque es el tipo de
hallazgo que, mal medido, se convierte en un «arreglo» que rompe producción.

PostgREST exige que el valor de `or` sea un árbol **entre paréntesis**:

```
or=(code.ilike."x",name.ilike."x")     -- 200
or=code.ilike."x",name.ilike."x"       -- 400 · 42703 column programs.orcode does not exist
```

Sin paréntesis, PostgREST concatena `or` con el nombre de la primera columna y
busca una columna llamada `orcode`. Eso fue exactamente lo que devolvió la
primera sonda que escribí, y por un momento parecía un bug de producción: el
mismo patrón lo usa el listado de usuarios desde el overhaul de M1.

**No lo era.** `supabase-js` envuelve el valor por dentro —
`PostgrestFilterBuilder.or()` hace `searchParams.append('or', `(${filters})`)` —
así que la URL que sale del repositorio **sí** lleva los paréntesis. El error
estaba en la sonda: construí la URL a mano, sin lo que añade el SDK, y medí una
petición que el código nunca envía.

| Prueba contra la base real | Resultado |
| --- | --- |
| `or=(code.ilike."her",name.ilike."her")` | **200** |
| `or=code.ilike."her",name.ilike."her"` | **400** `42703 column programs.orcode does not exist` |
| `or=(code.ilike."o,o",…)` — texto con coma | **200** |
| `or=(code.ilike."o""b",…)` — comilla doble escapada | **200** |
| `or=(code.ilike."a(b)",…)` — paréntesis en el texto | **200** |
| `or=((code.ilike."herr"))` — paréntesis doblados | **400** `PGRST100 unexpected "("` |

**Consecuencias, las dos escritas en el código:**

1. `filtroIlike` **no** debe añadir paréntesis. Si alguien los añadiera «para
   arreglarlo», el valor viajaría doblado y la consulta fallaría con `PGRST100`.
   Hay una prueba que fija el formato para que eso no pase inadvertido.
2. El escapado del texto (comillas dobles para volverlo literal, y duplicarlas
   dentro) **sí** estaba bien y ahora está medido con coma, comilla y paréntesis.

**Lección de método.** Una sonda vale lo que vale su fidelidad: si reconstruye a
mano lo que una librería construye, mide otra cosa. La comprobación correcta era
leer la implementación de `.or()` antes de dar por hecho el fallo.

---

## Resumen

| ID | Contradicción | Resolución | Estado |
| --- | --- | --- | --- |
| R-01 | `sections` sin `program_id` | Se añadió la columna | ✅ Resuelta |
| R-02 | `is_active DEFAULT TRUE` vs Regla 1 | Nace en `false` | ✅ Resuelta |
| R-03 | Regla 1 decía "carreras", se aplicaba a todo | Acotada a `CARRERA` | ✅ Resuelta |
| R-04 | `ENUM` vs convención del proyecto | `text` + `check` | ✅ Resuelta |
| R-05 | Ruta fuera del prefijo con guardia | `/api/v1/admin/programas` | ✅ Resuelta (el documento debe actualizarse) |
| R-06 | Dos convenciones de período | — | 🔴 **DECISIÓN PENDIENTE** |
| R-07 | `curso_seleccionado` por nombre | Diferida a D14 | ⏳ Abierta, sin urgencia (0 filas) |
| R-08 | `sections` de Fase 0 era un stub | Rediseñada completa | ✅ Resuelta |
| R-09 | `cursos` vs `programs` (D12) | Vista de compatibilidad | ✅ Resuelta |
| R-10 | "Una transacción" que PostgREST no da | Dos funciones RPC | ✅ Resuelta |
| R-11 | El filtro `or` exige paréntesis | Los añade `supabase-js`; no se toca | ✅ Verificada |
