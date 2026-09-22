# Arquitectura del Aula Virtual (Módulo 6)

> **Estado:** diseño cerrado; implementación en curso desde el 2026-09-22.
> **Autor:** equipo de ingeniería INCES-LMS.
> **Insumo:** [`docs/INVESTIGACION_AULA_VIRTUAL.md`](INVESTIGACION_AULA_VIRTUAL.md)
> (investigación del núcleo de Google Classroom, con fuentes citadas).
>
> Este documento **decide**. La investigación describe cómo lo hace Google; aquí
> se elige qué copiamos, qué adaptamos y qué descartamos, y por qué.

---

## 0. Resumen de decisiones

| # | Decisión | Alternativa descartada | Motivo |
|---|---|---|---|
| D-1 | **Un «curso» es una `sections` de M3.** No se crea tabla de cursos. | Tabla `m6_cursos` propia | Una sección ya implica programa, materia y lapso, y ya tiene roster (`enrollments`) y docentes (`schedule_slots`). Duplicarla crearía una segunda fuente de verdad que puede desviarse. |
| D-2 | **Tres tablas nuevas:** `m6_anuncios`, `m6_tareas`, `m6_entregas`. | Modelo único con `tipo` | Anuncio, tarea y entrega tienen ciclos de vida y permisos distintos. Un solo saco obligaría a media docena de `CHECK` por tipo. |
| D-3 | **Los adjuntos reutilizan `files_metadata` (M5) sin tocar su esquema.** | Tabla de adjuntos nueva | El reparto `TEACHER_GUIDE` / `TASK_SUBMISSION` que M5 ya tiene **es exactamente** el de Google (`CourseWork.materials` vs `StudentSubmission.attachments`). |
| D-4 | **Nada depende de un planificador.** La publicación programada se resuelve en la política RLS de lectura; «tardía» se escribe al entregar; «faltante» se deriva al leer. | `pg_cron` / cron de Actions | Cortes eléctricos y arquitectura dual. Es la misma lección que D9. |
| D-5 | **Escala 0–20**, con `CHECK`, no 0–100. | Escala 100 | Es la escala venezolana y la que el centro usa en actas. |
| D-6 | **Nota borrador ≠ nota asignada.** Dos columnas. | Una sola columna `nota` | Reproduce la garantía de Google: el alumno no ve nada hasta que el docente **devuelve**. |
| D-7 | **Los placeholders de entrega se crean al publicar**, uno por matrícula activa. | `LEFT JOIN` contra el roster al leer | Hace que «quién no ha entregado» sea una lectura directa y no un join contra una tabla que cambia. |
| D-8 | **La visibilidad cruzada de M5 se cierra aquí**, con políticas nuevas sobre `files_metadata`. | Dejarla abierta | Es la mitad de D17 que M5 no podía expresar: sin la tabla de tareas no hay nada que unir. |

### 0.1 Un conflicto de nomenclatura, dicho en voz alta

El catálogo de módulos (`202609120002_phase3_admin_core.sql`) **ya tiene
reservada la clave `m6_asistencia`** («Asistencia»), y `m7_calificaciones` y
`m8_pasantias` detrás. Es decir: **el número 6 estaba tomado por otro módulo**.

Se resuelve así, y conviene que quede escrito porque si no parece un descuido:

- El archivo se llama `202609220001_mod6_aula_virtual.sql` porque es el hueco que
  el roadmap le asignó a esta fase. **El nombre del archivo no crea la clave.**
- La clave del módulo es **`m6_aula_virtual`**, distinta de `m6_asistencia`. No
  se renombra `m6_asistencia`: la semilla dice explícitamente que las claves
  **nunca se renombran**, y renombrarla rompería cualquier referencia guardada.
- El **orden de menú** de `m6_aula_virtual` es **55**, entre M5 (50) y
  `m6_asistencia` (60), para que el aula aparezca junto a los archivos que usa.
- Asistencia sigue siendo su propia clave y su propio ciclo. Cuando se construya,
  no habrá que tocar nada de esto.

---

## 1. Qué se reutiliza, y por qué no se duplica

| Pieza de Google | Equivalente INCES | ¿Tabla nueva? |
|---|---|---|
| `Course` | `sections` (M3) | **No** |
| Personas del curso (roster) | `enrollments` (M4) para alumnos; `schedule_slots.teacher_id` para docentes | **No** |
| Lapso / `gradingPeriodId` | `sections.period_code` → `academic_periods` (`SA26-2`) | **No** |
| `CourseWork.materials` | `files_metadata` con `entity_type='TEACHER_GUIDE'` | **No** |
| `StudentSubmission.attachments` | `files_metadata` con `entity_type='TASK_SUBMISSION'` | **No** |
| `CourseWork` | `m6_tareas` | **Sí** |
| `StudentSubmission` | `m6_entregas` | **Sí** |
| `Announcement` | `m6_anuncios` | **Sí** |

**La pestaña «Personas» no necesita tabla ni ruta nueva.** Es una vista sobre M3
y M4, que ya existen y ya tienen RLS. Construirla es trabajo de interfaz, no de
modelo.

---

## 2. Modelo de datos

### 2.1 `m6_anuncios` — el Tablón

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | |
| `seccion_id` | uuid FK → `sections(id)` on delete cascade | El anuncio pertenece a **una** sección. |
| `autor_id` | uuid FK → `profiles(id)` | Quién lo publica. |
| `titulo` | text | |
| `cuerpo` | text | |
| `estado` | text | `BORRADOR` \| `PUBLICADO` \| `ELIMINADO`. **`DEFAULT 'BORRADOR'`.** |
| `programado_para` | timestamptz NULL | Publicación diferida. Ver §4.1. |
| `publicado_en` | timestamptz NULL | Orden del feed. |
| `created_at`, `updated_at` | timestamptz | |

### 2.2 `m6_tareas` — Trabajo de clase

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | |
| `seccion_id` | uuid FK → `sections(id)` on delete cascade | |
| `creado_por` | uuid FK → `profiles(id)` | |
| `titulo`, `descripcion` | text | |
| `tipo` | text | `TAREA` \| `MATERIAL` \| `PREGUNTA`. Reproduce `workType` y la separación `CourseWork` / `CourseWorkMaterial`. |
| `puntos_maximos` | numeric(4,2) | `DEFAULT 20`, `CHECK (>= 0 AND <= 20)` **+ coherencia por tipo** (ver §2.5). |
| `fecha_limite` | timestamptz NULL | |
| `permitir_entrega_tardia` | boolean | `DEFAULT true` (comportamiento de Google). |
| `permite_edicion` | text | `MODIFIABLE_UNTIL_TURNED_IN` (defecto) \| `MODIFIABLE`. |
| `estado` | text | `BORRADOR` \| `PUBLICADO` \| `ELIMINADO`. **`DEFAULT 'BORRADOR'`.** |
| `programado_para` | timestamptz NULL | |
| `tema` | text NULL | Agrupación por texto, no tabla. |
| `orden` | integer | Orden manual dentro del tema. |
| `publicado_en` | timestamptz NULL | |
| `created_at`, `updated_at` | timestamptz | |

**`tipo='MATERIAL'` no genera entregas.** Es el `CourseWorkMaterial` de Google:
material de lectura, sin nota ni fecha límite. El `CHECK` de coherencia lo exige:
una tarea de tipo `MATERIAL` no puede tener `puntos_maximos` distintos de 0 ni
`fecha_limite` no nula.

#### 2.5 Por qué `puntos_maximos` son tres `CHECK` y no uno

Este documento pedía, en su primera versión, dos cosas incompatibles: un rango
`> 0` y, a la vez, que un `MATERIAL` tuviera `puntos_maximos = 0`. Un `MATERIAL`
no habría podido existir — el diseño tenía una contradicción que no se ve hasta
que se escribe la restricción. Se resuelve con tres, cada uno diciendo una cosa:

```sql
check (puntos_maximos >= 0 and puntos_maximos <= 20),          -- el rango
check (tipo <> 'MATERIAL' or puntos_maximos = 0),              -- el material no se califica
check (tipo =  'MATERIAL' or puntos_maximos > 0)               -- lo calificable vale > 0
```

Un único `CHECK` no puede decir «mayor que cero salvo para `MATERIAL`» sin
repetir el tipo dentro de la expresión, y una condición con la misma cláusula
dos veces es una que se corrige en un sitio y no en el otro.

La comprobación está **además** en `m6_crear_tarea`, para devolver un mensaje
que se entienda («Un MATERIAL es de lectura: no lleva puntos ni fecha límite»)
en vez de un `violates check constraint m6_tareas_material_sin_nota` a secas.
Las dos capas no son redundancia: una da el mensaje, la otra garantiza que no
haya camino que las esquive —incluido un `insert` desde el editor SQL—.

#### 2.6 Un valor por defecto que contradecía al caso más común

`m6_crear_tarea` tenía `p_puntos_maximos default 20`. La consecuencia no se ve
hasta que alguien hace la llamada natural:

```sql
-- Un material de lectura no se califica, así que no se le pasan puntos.
select * from public.m6_crear_tarea(sec, 'Lectura', '', 'MATERIAL');
-- ERROR 23514: Un MATERIAL es de lectura: no lleva puntos ni fecha límite.
```

El argumento llegaba valiendo **20**, la comprobación de coherencia de `MATERIAL`
lo leía como «un material con puntos» y rechazaba. El valor por defecto
contradecía exactamente al caso para el que existía el tipo.

Se corrige con `default null`: «no me lo dijeron» pasa a distinguirse de «me
dijeron 20», y el 20 de negocio se aplica **dentro**, sólo a lo que sí se
califica (`case when tipo='MATERIAL' then 0 else coalesce(p_puntos_maximos, 20) end`).
Los dos `CHECK` de coherencia siguen ahí y el guardia sigue guardando: un
`MATERIAL` con puntos explícitos sigue siendo 400.

> **La lección, que es transferible:** un valor por defecto que contradice al
> caso más frecuente es **peor que no tenerlo**, porque el error aparece lejos
> de su causa. Y se detectó porque la puerta de verificación **no** convirtió el
> comportamiento en una aserción: congelarlo como contrato habría dejado el
> defecto escrito en piedra.

Los dos errores que la tabla habría dado como violación de `CHECK` se traducen
también a errores de negocio: `TAREA` con 0 → «Una tarea calificable debe valer
más de 0 puntos», y por encima de 20 → «La nota máxima no puede superar 20».

### 2.3 `m6_entregas` — StudentSubmission

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid PK | **Es el `entidad_id` de los archivos `TASK_SUBMISSION`.** |
| `tarea_id` | uuid FK → `m6_tareas(id)` on delete cascade | |
| `estudiante_id` | uuid FK → `profiles(id)` | |
| `estado` | text | `ASIGNADA` \| `ENTREGADA` \| `DEVUELTA` \| `RECLAMADA`. |
| `es_tardia` | boolean | `DEFAULT false`. Se escribe **al entregar** (§4.2). |
| `nota_borrador` | numeric(4,2) NULL | Visible **sólo** para el docente. |
| `nota_asignada` | numeric(4,2) NULL | Visible al alumno **sólo** en `DEVUELTA`. |
| `entregada_en`, `devuelta_en` | timestamptz NULL | |
| `created_at`, `updated_at` | timestamptz | |
| `UNIQUE (tarea_id, estudiante_id)` | | Un placeholder por alumno y tarea. |
| `CHECK (nota_asignada IS NULL OR nota_borrador IS NOT NULL)` | | No hay nota final sin borrador, igual que Google. |
| `CHECK (nota_borrador BETWEEN 0 AND 20)` / idem `nota_asignada` | | Escala 20. |

### 2.4 Diagrama

```
sections (M3)
 ├── enrollments (M4)  ──────────────► el roster: quién es alumno
 ├── schedule_slots (M3) ────────────► el docente: teacher_id
 ├── m6_anuncios        (Tablón)
 └── m6_tareas          (Trabajo de clase)
      ├── files_metadata: entity_type='TEACHER_GUIDE',   entidad_id = m6_tareas.id
      └── m6_entregas   (1 por alumno matriculado)
           ├── files_metadata: entity_type='TASK_SUBMISSION', entidad_id = m6_entregas.id
           └── nota_borrador → (al devolver) → nota_asignada
```

---

## 3. RLS: quién ve qué

**La frontera de autorización es la RLS, no la API** (ADR-003). Nada de esto se
comprueba en Node.

### 3.1 `m6_tareas`

| Actor | Ve |
|---|---|
| Docente de la sección (`schedule_slots.teacher_id = yo`) | Todo, incluidos borradores y programadas. |
| Alumno con `enrollments.status='ENROLLED'` en la sección | Sólo si `estado='PUBLICADO'` **o** (`estado='BORRADOR'` **y** `programado_para <= now()`). |
| Administrador | Todo. |
| Cualquier otro | Nada. |

### 3.2 `m6_entregas`

| Actor | Ve |
|---|---|
| El alumno dueño | Su fila. `nota_asignada` sólo si `estado='DEVUELTA'`. |
| Docente de la sección de la tarea | Todas las entregas de esa tarea, con `nota_borrador`. |
| Administrador | Todo. |

⚠️ **`nota_borrador` no se protege con RLS de columna, sino con vistas o con el
`SELECT` explícito del repositorio.** PostgreSQL sí admite `GRANT` por columna y
es la vía correcta: `grant select (id, tarea_id, estudiante_id, estado,
es_tardia, nota_asignada, ...) on public.m6_entregas to authenticated;` **sin**
incluir `nota_borrador`. La RPC del docente va por `security definer` y sí la lee.
Esto se verifica en `supabase/tests/` con un `select` como alumno que debe fallar
por privilegios.

### 3.3 `files_metadata` — la mitad de D17 que M5 no podía expresar

M5 dejó dos políticas: el propietario ve lo suyo, el administrador lo ve todo. Con
eso, **un docente no veía las entregas de sus alumnos** y un alumno no veía las
guías. No era un descuido de M5: `files_metadata.entidad_id` es un UUID **sin
tabla que lo respalde**, así que no había nada que unir. Ahora sí lo hay.

Se añaden tres políticas **en la migración de M6, nunca editando la de M5**:

| Política | Para | Condición |
|---|---|---|
| `files_metadata_docente_guia` | Docente lee las guías de sus tareas | `entity_type='TEACHER_GUIDE'` y `entidad_id` es una tarea de una sección que dicta |
| `files_metadata_docente_entrega` | Docente lee las entregas de sus alumnos | `entity_type='TASK_SUBMISSION'` y `entidad_id` es una entrega de una tarea de una sección que dicta |
| `files_metadata_estudiante_guia` | Alumno lee las guías que le tocan | `entity_type='TEACHER_GUIDE'` y la tarea está visible para él (§3.1) |

Las políticas son **aditivas**: PostgreSQL combina las políticas `SELECT` con
`OR`, así que las de M5 siguen valiendo y ninguna se debilita. La de
administrador sigue siendo la que lo abre todo.

> **Regla que se respeta:** una migración ya aplicada **no se edita nunca**. Las
> tres políticas van en `202609220001`, no dentro de `202609210001`.

---

## 4. Las cuatro decisiones que impone el entorno INCES

### 4.1 Publicación programada sin planificador

Google usa `state=DRAFT` + `scheduledTime` y un proceso que publica a esa hora.
Aquí **no puede haber ese proceso**: hay cortes eléctricos y arquitectura dual.

La visibilidad se decide **en la lectura**, dentro de la política RLS:

```sql
(estado = 'PUBLICADO')
or (estado = 'BORRADOR' and programado_para is not null and programado_para <= now())
```

El docente sigue viendo sus borradores porque tiene su propia política. **Cero
procesos en segundo plano, y el resultado es el mismo para el alumno.**

### 4.2 «Tardía» se escribe al entregar

`es_tardia := (now() > fecha_limite)`, dentro de la transacción del RPC de
entrega. No hay nada que calcular después, así que no hace falta nada que corra
después. Si `fecha_limite` es nula, nunca es tardía.

### 4.3 «Faltante» se deriva, no se escribe

`faltante = (estado = 'ASIGNADA' and fecha_limite < now())`.

**No se auto-escribe un 0 en `nota_borrador`.** Google lo hace, y aquí se
descarta a propósito: sería una escritura implícita que el sistema hace solo, en
nombre de un docente que no la pidió, y que además quedaría congelada —un alumno
que entrega tarde seguiría con el 0 puesto—. Se expone como columna calculada en
la vista del libro de calificaciones; el docente pone el 0 si corresponde.

### 4.4 Entrega tardía permitida o no

`m6_entregar_tarea` valida `now() <= fecha_limite or permitir_entrega_tardia`. Si
no, error de negocio (no un `CHECK`, porque depende del reloj y de una bandera de
la fila). Sin job.

---

## 5. RPCs (`security definer`)

Toda escritura con reglas va por RPC, como en M2/M4/M5. Cada una **autoriza sola
con `auth.uid()`**: al ser `definer`, la RLS no la protege (lección R-20).

| RPC | Quién | Efecto |
|---|---|---|
| `m6_crear_anuncio(seccion, titulo, cuerpo, programado_para)` | Docente de la sección | Inserta con `estado='BORRADOR'`. |
| `m6_crear_tarea(...)` | Docente de la sección | Inserta con `estado='BORRADOR'`. |
| `m6_publicar_tarea(tarea_id)` | Docente de la sección | `PUBLICADO` + `publicado_en` + **crea los placeholders** de entrega por cada matrícula `ENROLLED`. |
| `m6_entregar_tarea(entrega_id)` | El alumno dueño | `ENTREGADA`, `entregada_en`, `es_tardia`; valida §4.4. |
| `m6_reclamar_entrega(entrega_id)` | El alumno dueño | `RECLAMADA` (el «des-entregar» de Google). |
| `m6_calificar_entrega(entrega_id, nota)` | Docente de la sección | `nota_borrador := nota`. |
| `m6_devolver_entrega(entrega_id)` | Docente de la sección | `nota_asignada := nota_borrador`, `DEVUELTA`, `devuelta_en`. |
| `m6_entregas_de_tarea(tarea_id)` | Docente de la sección | **Lectura**: el libro de calificaciones, con `nota_borrador` y el `faltante` derivado. |

Son **ocho y no seis**. Las dos que el diseño no preveía son las que se
descubrieron al escribir la migración, y ninguna es cosmética:

- **`m6_crear_anuncio`** cierra la simetría con `m6_crear_tarea`. Sin ella, el
  tablón habría sido la única tabla del módulo con escritura directa, y una
  política de `INSERT` laxa dejaría a cualquiera publicar en el tablón de una
  sección ajena —o marcarse el anuncio como `PUBLICADO` de una vez, saltándose
  el borrador—.
- **`m6_entregas_de_tarea`** es la que hace posible la ruta del libro. Y su
  ausencia habría sido un fallo **silencioso**, no un error: el `GRANT` por
  columna le esconde `nota_borrador` a `authenticated`, así que un `SELECT`
  normal desde la ruta habría devuelto la columna en blanco y el docente habría
  calificado a ciegas sin que nada fallara. Ver §3.2.

**Las RPC devuelven columnas explícitas, nunca la fila entera.** No es estilo:
devolver `setof m6_entregas` arrastraría `nota_borrador` dentro del resultado, y
el `GRANT` por columna habría quedado decorativo —el alumno recibiría la nota
que se quiso esconder—. Por eso `m6_entregar_tarea` y `m6_reclamar_entrega`
declaran seis columnas, y `m6_calificar_entrega` y `m6_devolver_entrega` siete.

**Publicar es idempotente.** Volver a publicar no duplica placeholders: el
`unique (tarea_id, estudiante_id)` con `on conflict do nothing` lo garantiza. Un
botón que se puede pulsar dos veces no puede crear dos entregas.

---

## 6. Contrato HTTP

Bajo `/api/v1/aula/`, con la guardia `exigirModulo(caches.modulos,
'm6_aula_virtual')` **en segundo lugar**, después de `exigirSesion()` — el orden
no es cosmético: al revés, una petición anónima recibiría 403/404 en vez del 401
que exige `openapi.test.ts`.

| Método | Ruta | Quién |
|---|---|---|
| GET | `/aula/secciones/:seccionId/tablon` | Cualquiera que vea la sección |
| POST | `/aula/secciones/:seccionId/anuncios` | Docente de la sección |
| GET | `/aula/secciones/:seccionId/trabajo` | Cualquiera que vea la sección |
| POST | `/aula/secciones/:seccionId/tareas` | Docente de la sección |
| POST | `/aula/tareas/:tareaId/publicar` | Docente de la sección |
| GET | `/aula/tareas/:tareaId/entregas` | Docente de la sección |
| GET | `/aula/mis-entregas` | Alumno |
| POST | `/aula/entregas/:entregaId/entregar` | Alumno dueño |
| POST | `/aula/entregas/:entregaId/calificar` | Docente de la sección |
| POST | `/aula/entregas/:entregaId/devolver` | Docente de la sección |

Las rutas **no repiten la autorización**: la hacen la RLS y las RPC. Repetirla
sería una segunda copia de la regla, y dos copias se desvían. La guardia de
módulo es la excepción, porque que el módulo esté encendido no lo sabe la base.

---

## 7. Fuera de alcance (deliberado)

| Descartado | Motivo |
|---|---|
| Ponderación por categorías y renormalización de pesos | El centro califica sobre 20 con promedio simple. Añadirlo sin que nadie lo pida es complejidad que hay que mantener y probar. |
| `shareMode` (`VIEW`/`EDIT`/`STUDENT_COPY`) de Drive | No compartimos archivos de Drive. Arrastrarlo sería copiar una solución a un problema que no tenemos. |
| Preguntas de opción múltiple / respuesta corta | `tipo='PREGUNTA'` queda como marcador; el motor de preguntas es un ciclo propio. |
| Notificaciones por correo | No hay proveedor configurado y el INCES no lo pidió. |
| Temas como tabla | Una columna `tema` de texto y un `orden` cubren el caso. El arrastre manual no es crítico. |
| Cierre de actas y boletines | Es M7 (`m7_calificaciones`), que ya tiene su hueco reservado. |

---

## 8. Trazabilidad: hallazgo → decisión

| Hallazgo de la investigación | Decisión |
|---|---|
| Cuatro pestañas sobre un curso | §1: el curso es la sección; Personas se deriva, no se modela |
| `CourseWork.materials` ≠ `StudentSubmission.attachments` | D-3: se reutiliza el reparto de M5 sin tocar su esquema |
| `state=DRAFT` por defecto + `scheduledTime` | §4.1: la visibilidad programada se resuelve en RLS |
| `late` es de sólo lectura y lo calcula el sistema | §4.2: se escribe al entregar, no con un job |
| *missing* no es distinguible por API (limitación de Google) | §4.3: se **deriva** en lectura, lo que esquiva la limitación |
| `draftGrade` → `assignedGrade` al devolver | D-6 + §2.3: dos columnas y un `CHECK` de dependencia |
| El alumno no edita adjuntos hasta que se le devuelve | §2.3: `RECLAMADA`/`DEVUELTA` gobiernan el ciclo |
| Placeholders creados al asignar | D-7 + §5: `m6_publicar_tarea` los crea |
| Tablón cronológico + panel «Upcoming» | §6: `/tablon` devuelve **sólo el feed**; lo pendiente se ve como el estado de cada entrega en su tarjeta, sin panel aparte |
| Semáforo rojo/verde/negro del libro | Se implementa en el libro de calificaciones, derivando el color del estado |

---

## 9. Verificación

| Puerta | Comando |
|---|---|
| Migración contra PostgreSQL real | `cd supabase/tests && npm test` |
| Backend | `cd backend && npm run verify` |
| Contrato al día | `cd backend && npm run openapi` |
| Flutter | `flutter analyze && flutter test` (receta de dos piezas) |

**Obligatorio tras tocar la migración:** la suite de PGlite. Un `CHECK` o una
política RLS que no se prueba contra un motor real es una intención, no una
barrera.

---

## 10. Lo que cambió al escribir la migración

Este documento se escribió antes que el SQL. Al escribirlo aparecieron **tres
cosas que el diseño no había previsto**, y se anotan aquí en vez de dejarlas
sólo en el archivo `.sql`, porque un diseño que no registra sus correcciones
obliga a reconstruir la historia cada vez que alguien lo lee.

| # | Lo que decía el diseño | Lo que se hizo | Por qué |
|---|---|---|---|
| 1 | `puntos_maximos > 0` **y** un `MATERIAL` con 0 | Tres `CHECK` (§2.5) | Las dos condiciones juntas son insatisfacibles: un `MATERIAL` no podría existir. |
| 2 | Seis RPC, todas de escritura | Ocho, dos de ellas de lectura | Sin `m6_crear_anuncio` el tablón sería la única tabla con escritura directa; sin `m6_entregas_de_tarea` la ruta del libro devolvería `nota_borrador` en blanco **sin dar error** (§5). |
| 3 | Nada sobre la integridad de `entidad_id` | Un trigger en `files_metadata` | M6 es quien **da sentido** a `files_metadata.entidad_id`, así que M6 es quien debe impedir que apunte a cualquier cosa. |

### 10.1 El agujero que abre M6 y no M5

Hasta esta migración, `files_metadata.entidad_id` era un UUID **sin significado**:
no había tabla que lo respaldara. M5 no podía validarlo porque no había contra
qué. A partir de `m6_entregas` sí lo hay, y con el significado llega el riesgo:

- Un alumno podía subir un archivo con el `entidad_id` de la entrega de **otro
  compañero** —la RPC de M5 no lo mira y no se puede editar, ya está aplicada— y
  al docente le aparecería un archivo ajeno colgado de una entrega que no lo
  subió.
- Con `entity_type='TEACHER_GUIDE'`, un alumno podía colgar «material de apoyo»
  en la tarea de **toda la sección**.

Se cierra con el trigger `m6_validar_entidad_de_archivo` (PARTE 7.1 de la
migración): una `TASK_SUBMISSION` exige una entrega que exista y sea **de quien
sube el archivo**; una `TEACHER_GUIDE` exige una tarea que el usuario dicte (o
que sea administrador). `entidad_id` **NULL sigue permitido**: M5 lo admite a
propósito —la entidad puede crearse después de subir el archivo— y la pantalla
del estudiante sube material de apoyo sin atarlo a nada todavía.

Va en un trigger y no en la ruta por la razón de siempre: la ruta no es la
frontera (ADR-003), y un `insert` desde el editor SQL tampoco pasa por Node.

### 10.2 Lo que sigue sin resolverse, y se sabe

| Pendiente | Dónde se resolverá |
|---|---|
| Editar y eliminar anuncios y tareas (el diseño sólo tiene creación y publicación) | Ciclo propio; el `estado='ELIMINADO'` ya está previsto en las tablas |
| El motor de `tipo='PREGUNTA'` | Ciclo propio; hoy es un marcador |
| El libro de calificaciones **del alumno** (sus notas de todas las materias) | M7 (`m7_calificaciones`), que ya tiene su hueco |
| Encender `m6_aula_virtual` | `202609220002_mod6_habilitar_modulo.sql`, cuando exista la UI en Flutter |

**El módulo queda APAGADO a propósito.** Es la misma decisión que tomó M5: la
bandera se enciende cuando ya existen las rutas **y** la UI que las sostiene.
Al cerrar la fase 3 existen las rutas, pero el aula en Flutter todavía no, así
que encenderla dejaría un ítem de menú sin circuito detrás —el patrón de R-22—.
La suite de PGlite fija ese `false` para que encenderla sea una decisión y no un
descuido.
