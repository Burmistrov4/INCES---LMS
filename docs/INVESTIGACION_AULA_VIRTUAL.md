# Investigación — El núcleo de Google Classroom (insumo del Módulo 6)

**Fecha:** 2026-09-22 · **Autor:** equipo de ingeniería INCES-LMS · **Alcance:** navegación, modelo de datos, reglas de negocio, flujo docente, adjuntos y UX del tablón. Fuente primaria: documentación oficial de la Google Classroom API y los Centros de Ayuda de Google. Fuente secundaria: CustomGuide (tutorial de navegación).

> **Nota de rigor:** este proyecto prohíbe afirmar cosas sin verificarlas. Todo lo que sigue está respaldado por una fuente citada al final. Lo que **no** pude verificar se declara explícitamente en la sección *«Lo que no pude verificar»*. No hay inferencias presentadas como hechos.

---

## TL;DR

1. Google Classroom modela el aula con **cuatro pestañas** (Novedades/Tablón, Trabajo de clase, Personas, Calificaciones) sobre un curso. La pieza central es una **máquina de estados de entrega** (`CREATED → TURNED_IN → RETURNED`, con `RECLAIMED_BY_STUDENT`) y la separación estricta entre **nota borrador** (`draftGrade`, solo docente) y **nota asignada** (`assignedGrade`, visible al estudiante al devolver).
2. La distinción que al INCES le importa —**materiales del docente vs. archivos del alumno**— está formalizada en la API: `CourseWork.materials` (adjuntos del docente, tipo `Material`) es un campo **distinto** de `StudentSubmission.assignmentSubmission.attachments` (adjuntos del alumno). Encaja 1:1 con el `entity_type` de M5 (`TEACHER_GUIDE` / `TASK_SUBMISSION`).
3. Google resuelve la publicación programada con un campo `scheduledTime` y un estado `DRAFT`; el estado `late` y el estado *faltante* son **derivables de `dueDate` vs. la fecha de entrega**, no dependen de un proceso que tenga que estar corriendo. Esto es directamente aprovechable en un entorno con cortes eléctricos.

---

## 1. Estructura de navegación de un curso

Un curso de Google Classroom se abre en una página con **cuatro pestañas** en la parte superior. (CustomGuide, *Google Classroom Navigation*.)

| Pestaña | Nombre en la API / concepto | Qué contiene exactamente |
|---|---|---|
| **Novedades** (Stream / Tablón) | `courses.announcements` + reflejo de `courseWork` | Lugar central de publicaciones y anuncios. Es un **feed cronológico**. Cuando se añade algo al Trabajo de clase, **también aparece aquí**. En el lado izquierdo hay un bloque **«Upcoming» (Próximas entregas)** con la lista de tareas y sus fechas límite próximas. |
| **Trabajo de clase** (Classwork) | `courses.courseWork` + `courses.courseWorkMaterials` + temas | Es donde el docente **crea** tareas, preguntas y materiales. Se organiza en **temas** (topics) que agrupan ítems del mismo tipo (p. ej. «clase», «tarea», «proyectos»). Aquí el orden se puede arrastrar manualmente (a diferencia del Tablón). |
| **Personas** (People) | `courses.students` / `courses.teachers` | Lista de la clase: todos los docentes, co-docentes y estudiantes. Desde aquí se añaden personas. |
| **Calificaciones** (Grades) | Gradebook | Ver, calificar y **devolver** tareas. Muestra la nota de cada estudiante y el **promedio de la clase**. |

**Fuentes:** [CustomGuide — Navigation](https://www.customguide.com/course/google-classroom/google-classroom-navigation), [CustomGuide — Post Announcement](https://www.customguide.com/course/google-classroom/post-announcement-in-google-classroom).

### 1.1 Tres tipos de ítem dentro de «Trabajo de clase»

La API distingue **tres recursos distintos** que en la UI comparten la pestaña:

| Recurso | ¿Se califica? | ¿Tiene fecha límite? | ¿Genera entregas? | Campos propios |
|---|---|---|---|---|
| `CourseWork` (tarea / pregunta) | Sí (`maxPoints`) | Sí (`dueDate`/`dueTime`) | Sí (`StudentSubmission`) | `workType`, `maxPoints`, `dueDate`, `dueTime`, `submissionModificationMode`, `gradeCategory`, `gradingPeriodId` |
| `CourseWorkMaterial` (material) | **No** | **No** | **No** | `title`, `description`, `materials`, `topicId` |
| `Announcement` (anuncio) | **No** | **No** | **No** | `text`, `materials`, `assigneeMode` (sin `topicId`) |

Los tres comparten: `state` (`DRAFT` por defecto / `PUBLISHED` / `DELETED`), `scheduledTime`, `assigneeMode`, `individualStudentsOptions`, `alternateLink` (solo poblado si `PUBLISHED`), `creationTime`, `updateTime`, `creatorUserId`.

**Fuentes:** [CourseWork](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWork), [CourseWorkMaterials](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWorkMaterials), [Announcements](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.announcements).

---

## 2. Modelo de datos conceptual

### 2.1 Relaciones

```
Course (sección)
 ├── Announcement        (texto + materiales)          → feed del Tablón
 ├── CourseWorkMaterial  (título + materiales)         → sin entregas
 └── CourseWork          (tarea / pregunta)            → 1..N StudentSubmission
       ├── materials[]   (adjuntos del DOCENTE)        → Material
       └── StudentSubmission (uno por estudiante, creado al publicar)
             └── assignmentSubmission.attachments[]   (adjuntos del ALUMNO)
```

### 2.2 Campos clave por recurso

**`CourseWork` (la tarea).**

| Campo | Tipo | Notas verificadas |
|---|---|---|
| `state` | enum | `DRAFT` (**por defecto**), `PUBLISHED`, `DELETED`. `DRAFT` solo lo ven docentes y administradores del dominio. |
| `workType` | enum | `ASSIGNMENT`, `SHORT_ANSWER_QUESTION`, `MULTIPLE_CHOICE_QUESTION`. **No se puede cambiar** tras crear. |
| `maxPoints` | number | Nota máxima. Si es **0 o no se especifica, la tarea es «no calificada»** (ungraded). Entero no negativo. |
| `dueDate` / `dueTime` | Date / TimeOfDay | **En UTC**. Si se especifica uno, debe especificarse el otro. |
| `scheduledTime` | timestamp | Momento en que se publicará automáticamente. |
| `materials[]` | Material[] | Máximo **20** ítems. Adjuntos del docente. |
| `submissionModificationMode` | enum | `MODIFIABLE_UNTIL_TURNED_IN` (**por defecto**) o `MODIFIABLE` (el alumno puede editar siempre). |
| `assigneeMode` | enum | `ALL_STUDENTS` (**por defecto**) o `INDIVIDUAL_STUDENTS`. |
| `individualStudentsOptions` | objeto | Solo si `assigneeMode = INDIVIDUAL_STUDENTS`. |
| `topicId` | string | Tema al que pertenece. |
| `gradeCategory` | GradeCategory | Categoría de nota (solo lectura). |
| `gradingPeriodId` | string | **Periodo de calificación** al que se asocia. Si no se indica al crear, se deduce de `dueDate` (o `scheduledTime`). Se puede forzar «sin periodo» con `""`. |

**`StudentSubmission` (la entrega).**

| Campo | Tipo | Notas verificadas |
|---|---|---|
| `state` | enum | `CREATED`, `TURNED_IN`, `RETURNED`, `RECLAIMED_BY_STUDENT`, `STUDENT_EDITED_AFTER_TURN_IN`. (Las no accedidas pueden figurar como `NEW`.) **Solo lectura.** |
| `late` | boolean | `true` si el alumno **no entregó antes de `dueDate`**. **Solo lectura.** |
| `draftGrade` | number | **Nota pendiente**, visible y modificable **solo por docentes**. |
| `assignedGrade` | number | **Nota final**. Solo la modifica el docente. No puede existir sin `draftGrade`. |
| `submissionHistory[]` | SubmissionHistory | Historial de estados (`StateHistory`) y de notas (`GradeHistory`, con `pointsEarned`, `maxPoints`, `actorUserId`). |
| `assignmentSubmission.attachments[]` | Material[] | **Adjuntos del alumno** (solo para `workType = ASSIGNMENT`). |
| `userId`, `courseWorkId`, `courseId` | string | Claves de la entrega. |

**Métodos del recurso `StudentSubmission`:** `get`, `list`, `modifyAttachments`, `patch`, `reclaim` (reclamar), `return` (devolver), `turnIn` (entregar).

**Fuentes:** [StudentSubmissions](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWork.studentSubmissions), [Guía de calificaciones](https://developers.google.com/workspace/classroom/guides/key-concepts/grades).

### 2.3 Los estados de entrega y su significado

| Estado | Significado | Quién lo provoca |
|---|---|---|
| `CREATED` | La entrega existe (placeholder). | El sistema, al **publicar** la tarea. |
| `TURNED_IN` | El alumno entregó el trabajo. | Alumno. |
| `RETURNED` | El docente **devolvió** el trabajo al alumno (con o sin nota). | Docente. |
| `RECLAIMED_BY_STUDENT` | El alumno **«des-entregó»** (unsubmit) y recupera el control del documento. | Alumno. |
| `STUDENT_EDITED_AFTER_TURN_IN` | El alumno editó después de entregar (documentado para preguntas). | Alumno. |

**Estados *derivados* (no son valores del enum, se calculan):**

| Estado derivado | Cómo se deriva |
|---|---|
| **Tardía** (`late`) | `late = true` cuando no se entregó antes de `dueDate`. Campo de solo lectura que **Google calcula**; el desarrollador no lo escribe. |
| **Faltante** (missing) | Las entregas no sometidas antes de `dueDate` se anotan como *missing* en el libro de calificaciones. También se pueden marcar a mano. |
| **Completada / Excusada** | El docente puede marcar una faltante como *completa* (se quita la nota borrador por defecto) o *excusada* (sale del cálculo del promedio). |

> ⚠️ **Advertencia textual de la documentación oficial:** «Los estados *complete*, *missing* y *excused* de `StudentSubmissions` **no son distinguibles en la API**». Google lo reconoce como limitación abierta. (Ver *Lo que no pude verificar*.)

---

## 3. Reglas de negocio clave

| Pregunta | Respuesta verificada | Fuente |
|---|---|---|
| ¿Puede un alumno entregar tarde? | **Sí, por defecto.** «Por defecto, la herramienta de tareas seguirá permitiendo entregas después de la fecha límite.» Si entrega tarde, la entrega queda marcada `late = true`. | Blog Workspace Updates 2023-07-27 |
| ¿Se puede impedir la entrega tardía? | **Sí.** Desde julio de 2023 el docente puede *desactivar las entregas después de la fecha límite*, por asignación. También puede cortar las entregas en cualquier momento (p. ej. al cerrar el periodo), aunque no haya fecha límite estricta. | Blog Workspace Updates 2023-07-27 |
| ¿Se puede **reabrir / reclamar** una entrega? | El alumno puede **«des-entregar»** (`RECLAIMED_BY_STUDENT`) y volver a tener el control. La API expone `reclaim` para hacerlo en nombre del alumno. | StudentSubmissions |
| ¿Qué pasa al **devolver** (return) una tarea? | «Los estudiantes **no pueden editar** ningún archivo adjunto a una tarea **hasta que usted la devuelva**.» Al devolver, se notifica a los alumnos (si tienen notificaciones activas) y se puede devolver **con o sin nota**, a **uno o varios** alumnos a la vez. Al devolver en la app, `assignedGrade` se fija automáticamente al valor actual de `draftGrade`. | Ayuda 6020294; Guía de calificaciones |
| ¿Cómo se calcula **«faltante»**? | Las entregas **no sometidas antes de `dueDate`** se anotan como *missing* en el libro de calificaciones. El docente también puede marcarlas a mano. Las faltantes reciben una **`draftGrade` automática cuyo valor por defecto es 0** (personalizable). | Guía de calificaciones |
| ¿Se puede publicar a una **hora programada**? | **Sí.** `CourseWork`, `Announcement` y `CourseWorkMaterial` tienen el campo `scheduledTime`. | Referencias de la API |
| ¿**Borradores** vs **publicados**? | Todo ítem nace en `state = DRAFT` (visible solo para docentes/administradores) y pasa a `PUBLISHED`. `alternateLink` solo existe cuando está `PUBLISHED`. | Referencias de la API |
| ¿Se puede calificar sin devolver? | Sí: el docente puede fijar `draftGrade` (solo visible para él). La nota se vuelve visible al alumno solo al **devolver**, momento en que se copia a `assignedGrade`. | Guía de calificaciones |
| ¿Cómo se calcula el **promedio** del curso? | Tres modos: **total de puntos**, **ponderado por categoría**, o **ninguno**. Con categorías ponderadas, si falta una categoría, Google **renormaliza** los pesos. | Guía de calificaciones |
| ¿Qué es un **periodo de calificación** (grading period)? | Rango de fechas («spring», «fall») que agrupa tareas. El promedio del periodo solo incluye entregas con vencimiento en el rango. `CourseWork.gradingPeriodId` lo identifica. | Guía de calificaciones |
| ¿Se puede asignar a **alumnos individuales**? | Sí: `assigneeMode = INDIVIDUAL_STUDENTS` + `individualStudentsOptions`. Por defecto es `ALL_STUDENTS`. | Referencia de la API |

**Semáforo visual del libro de calificaciones (códigos de color documentados):** **rojo** = trabajo faltante; **verde** = trabajo entregado o nota borrador; **negro** = trabajo devuelto.

**Fuentes:** [Ayuda — Grade & return an assignment (6020294)](https://support.google.com/edu/classroom/answer/6020294), [Guía de calificaciones](https://developers.google.com/workspace/classroom/guides/key-concepts/grades), [Workspace Updates 2023-07-27](https://workspaceupdates.googleblog.com/2023/07/disable-submissions-after-due-date-in-google-classroom.html).

---

## 4. Flujo de trabajo del docente

```
Crear tarea (borrador)  →  Asignar (a toda la clase o a alumnos)
   │                              │
   │                              ├─ Se crean StudentSubmissions placeholder
   │                              │  (uno por estudiante, aunque no interactúe)
   │                              └─ Aparece en Tablón + Trabajo de clase + Upcoming
   ▼
Alumno entrega (TURNED_IN)  →  ¿antes o después de dueDate? → late = true/false
   │
   ▼
Docente revisa quién entregó  →  Califica (draftGrade, solo docente)
   │
   ▼
Docente DEVUELVE (return)  →  assignedGrade := draftGrade
   │                          → notificación al alumno
   │                          → el alumno puede volver a editar adjuntos
   ▼
(Opcional) Alumno «des-entrega» (reclaim) y vuelve a entregar
```

**Puntos verificados del flujo:**

- **Crear y asignar:** al asignar `CourseWork`, se crean **entregas placeholder para cada estudiante**, incluso si el alumno nunca interactúa con la tarea.
- **Ver quién entregó:** el libro de calificaciones y la página *Student work* muestran el estado por color (rojo/verde/negro).
- **Calificar:** la nota se sincroniza entre la herramienta de calificación, la página *Grades* y la página *Student work*. Existe la función **«Grade all»** para calificar en lote.
- **Devolver:** se puede devolver con o sin nota, a uno o varios alumnos. El alumno no puede editar los adjuntos hasta que se le devuelve.
- **Historial:** la entrega guarda `submissionHistory` con la traza de estados y de cambios de nota (quién y cuándo).

**Fuente:** [Ayuda 6020294](https://support.google.com/edu/classroom/answer/6020294) + [Guía de calificaciones](https://developers.google.com/workspace/classroom/guides/key-concepts/grades).

---

## 5. Adjuntos: materiales del docente vs. archivos de la entrega

**Esta es la distinción crítica para el proyecto**, y Google la tiene formalizada en dos campos separados de dos recursos distintos.

| | **Adjunto del DOCENTE** | **Adjunto del ALUMNO** |
|---|---|---|
| Dónde vive | `CourseWork.materials[]` | `StudentSubmission.assignmentSubmission.attachments[]` |
| Tipo | `Material` | `Material` (mismo tipo, otro contenedor) |
| Quién lo sube | Docente | Alumno |
| Máximo | 20 ítems por tarea | No documentado en la referencia consultada |
| Cuándo existe | Al crear la tarea | Al entregar (`TURNED_IN`) |
| Quién lo edita | Docente | Alumno (hasta entregar; ver `submissionModificationMode`) |
| Equivalente en M5 | `entity_type = 'TEACHER_GUIDE'` | `entity_type = 'TASK_SUBMISSION'` |

### 5.1 El tipo `Material` (compartido por ambos contenedores)

`Material` es una **unión**: un adjunto es **una sola** de estas cosas:

| Campo | Tipo | Notas |
|---|---|---|
| `driveFile` | SharedDriveFile | Archivo de Drive. Trae `shareMode`: `VIEW`, `EDIT`, `STUDENT_COPY` (**por defecto `VIEW`**; `EDIT` y `STUDENT_COPY` solo válidos en `ASSIGNMENT`). |
| `youtubeVideo` | YouTubeVideo | Video de YouTube. |
| `link` | Link | Enlace genérico (al crearlo se «promueve» al tipo más adecuado si es posible). |
| `form` | Form | Formulario de Google. **Solo lectura.** |
| `gem` | GeminiGem | (nuevo) Solo lectura. |
| `notebook` | NotebookLmNotebook | (nuevo) Solo lectura. |

**`SharedDriveFile.shareMode`** importa para el INCES: `VIEW` (solo ver), `EDIT` (editar el mismo archivo) y **`STUDENT_COPY`** (cada alumno recibe **su propia copia** — el análogo a «entregar un archivo editable distinto por alumno»).

**Fuentes:** [Material](https://developers.google.com/workspace/classroom/reference/rest/v1/Material), [CourseWork](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWork), [StudentSubmissions](https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWork.studentSubmissions).

---

## 6. Buenas prácticas de UX para el Tablón

Lo verificado sobre cómo Google organiza el Tablón (Stream):

1. **El Tablón es un feed cronológico.** «Todo en el Stream de la clase está listado en **orden cronológico**», a diferencia de la página de Trabajo de clase, donde el orden se puede arrastrar manualmente. (CustomGuide.)
2. **Los ítems de Trabajo de clase se reflejan en el Tablón.** Al añadir algo al trabajo de clase, también aparece en el Stream. Es decir: el Tablón es una **vista agregada**, no un almacén aparte.
3. **Panel «Upcoming» (Próximas entregas).** En el lado izquierdo del Tablón se muestra la lista de tareas con **fechas límite próximas**. Este es el mecanismo de «destacar lo que vence».
4. **Anuncios con adjuntos.** Un anuncio puede llevar hasta 20 materiales (documentos, videos, enlaces), lo que lo vuelve un canal de comunicación, no solo texto.
5. **Semáforo de estados en el libro de calificaciones:** rojo (faltante), verde (entregado / nota borrador), negro (devuelto). El color es la señal primaria de urgencia.

> **No pude verificar** el algoritmo exacto de ordenamiento del bloque «Upcoming» (¿por fecha límite ascendente? ¿incluye tareas sin límite?) ni si el feed del Tablón ordena ascendente o descendente por fecha de publicación. CustomGuide solo confirma «orden cronológico». Lo dejo como recomendación de diseño, no como hecho copiado.

---

## Implicaciones para el modelo INCES

Traducción de cada hallazgo a una decisión concreta, respetando las tres restricciones del proyecto: **lapsos** (`academic_periods`, código tipo `SA26-2`), **cortes eléctricos** (nada depende de un planificador siempre activo) y **escala de 20 puntos**.

### I.1 Un «curso» = una sección (M3), no una tabla nueva

| Hallazgo Google | Recomendación INCES |
|---|---|
| `Course` contiene Announcements, CourseWork y Personas. | **No crear tabla de curso.** El curso del aula virtual **es** `secciones` (M3). Las cuatro pestañas son **sub-rutas** de la sección: `…/seccion/:id/tablon`, `/trabajo`, `/personas`, `/calificaciones`. |
| Personas = roster del curso. | La pestaña **Personas** no necesita tabla: se deriva de `enrollments` (M4, con cupos) para estudiantes y de `schedule_slots.teacher_id` para docentes. **Reusar M4; no duplicar.** |

### I.2 Tablas nuevas propuestas (prefijo `m6_`)

**`m6_tareas`** (equivale a `CourseWork`)

| Columna | Tipo | Origen del hallazgo |
|---|---|---|
| `id` | uuid PK | — |
| `seccion_id` | uuid FK → `secciones` | La tarea **cuelga de una sección concreta** (requisito INCES). |
| `lapso_id` | uuid FK → `academic_periods` | Análogo a `gradingPeriodId`. El lapso es derivable de la sección, pero **denormalizarlo** abarata el filtro del libro de calificaciones por lapso (`SA26-2`). |
| `titulo`, `descripcion` | text | `title`, `description`. |
| `tipo` | text/enum | `TAREA` \| `MATERIAL` \| `PREGUNTA` — reproduce `workType` y la separación `CourseWork` / `CourseWorkMaterial`. |
| `puntos_maximos` | numeric(4,2) | Análogo a `maxPoints`, pero con **CHECK (0 ≤ nota ≤ 20)** y `DEFAULT 20` (escala venezolana). |
| `fecha_limite` | timestamptz | `dueDate`/`dueTime`. **Guardar con zona horaria de Venezuela.** |
| `permitir_entrega_tardia` | boolean | Reproduce el interruptor de «desactivar entregas tras la fecha límite» (2023). `DEFAULT true` (comportamiento Google). |
| `permite_edicion` | text | `MODIFIABLE_UNTIL_TURNED_IN` (defecto) \| `MODIFIABLE` → `submissionModificationMode`. |
| `estado` | text | `BORRADOR` \| `PUBLICADO` \| `ELIMINADO` → `CourseWorkState`. **`DEFAULT 'BORRADOR'`** (igual que Google). |
| `programado_para` | timestamptz NULL | `scheduledTime`. |
| `tema` | text NULL | `topicId`. Recomendación: **empezar con una columna `tema` de texto + `orden` integer**, no una tabla de temas. Menos piezas, y el arrastre manual no es crítico. |
| `publicado_en` | timestamptz NULL | Para ordenar el Tablón. |
| `creado_por`, `created_at`, `updated_at` | — | Auditoría (`creatorUserId`, timestamps). |

**`m6_entregas`** (equivale a `StudentSubmission`)

| Columna | Tipo | Origen del hallazgo |
|---|---|---|
| `id` | uuid PK | — |
| `tarea_id` | uuid FK → `m6_tareas` | `courseWorkId`. |
| `estudiante_id` | uuid FK → perfiles | `userId`. |
| `estado` | text | `ASIGNADA` \| `ENTREGADA` \| `DEVUELTA` \| `RECLAMADA` → enum de `StudentSubmission`. |
| `es_tardia` | boolean | `late`. **Ver I.4: se calcula al entregar, no por un job.** |
| `nota_borrador` | numeric(4,2) NULL | `draftGrade` (solo docente). |
| `nota_asignada` | numeric(4,2) NULL | `assignedGrade` (visible al devolver). **CHECK (0 ≤ nota ≤ 20)**. |
| `entregada_en`, `devuelta_en` | timestamptz NULL | Trazabilidad. |
| `UNIQUE (tarea_id, estudiante_id)` | — | Un placeholder por estudiante y tarea. |

**Placeholders:** al publicar una tarea, un **RPC `security definer`** inserta una fila `m6_entregas` con `estado='ASIGNADA'` por cada `enrollment` activo de la sección. Esto reproduce el comportamiento verificado de Google (entregas placeholder creadas al asignar, aunque el alumno no interactúe). Así «quién no ha entregado» se lee sin `LEFT JOIN` contra el roster.

### I.3 Adjuntos: reusar M5 sin cambios de esquema

| Hallazgo Google | Recomendación INCES |
|---|---|
| `CourseWork.materials` ≠ `StudentSubmission.attachments` | Reusar `files_metadata` (M5) con: **`entity_type='TEACHER_GUIDE'`** + `entidad_id = m6_tareas.id` para los materiales del docente, y **`entity_type='TASK_SUBMISSION'`** + `entidad_id = m6_entregas.id` para los archivos del alumno. **La separación que ya existe en M5 es exactamente la de Google.** |
| `Material` es una unión (driveFile / youtubeVideo / link / form). | En INCES, M5 guarda **archivos** en R2. Para enlaces y videos, usar una columna `url_externa` NULL en una tabla ligera de adjuntos, **o** un `mime_type`/`tipo_adjunto` en `files_metadata`. Decidir según lo que ya permita M5; **no forzar todo a R2 si es un enlace.** |
| `shareMode` (`VIEW`/`EDIT`/`STUDENT_COPY`) | INCES no comparte archivos de Drive; **no aplica**. Documentar la omisión para no arrastrar complejidad inútil. |
| Máximo 20 materiales. | Aplicar un `CHECK` de conteo si se desea, o dejarlo sin límite. **No es crítico.** |

### I.4 Sin planificador: estados derivados en lectura (clave por los cortes eléctricos)

**Regla de oro:** ningún estado que el sistema deba «actualizar solo» depende de un cron. Todo se **deriva** o se **escribe en el momento de la acción del usuario**.

| Necesidad | Cómo lo hace Google | Recomendación INCES (sin scheduler) |
|---|---|---|
| **Publicación programada** | `state=DRAFT` + `scheduledTime`; la app lo publica a esa hora. | **No programar un job.** Guardar `estado='BORRADOR'` + `programado_para`. La **visibilidad** se decide en la **política RLS** de lectura: un estudiante ve la tarea si `estado='PUBLICADO'` **o** (`estado='BORRADOR'` **y** `programado_para <= now()`). El docente siempre ve sus borradores. **Cero procesos en segundo plano.** |
| **Marcar `late`** | Google lo calcula (campo de solo lectura). | **Escribirlo en el RPC de entrega**, en el instante en que el alumno entrega: `es_tardia := (now() > fecha_limite)`. Es una escritura atómica dentro de una transacción ya existente; no necesita job. |
| **Marcar «faltante»** | Google lo anota en el libro; `draftGrade` automática = 0. | **Derivar en lectura, no escribir.** `faltante = (estado='ASIGNADA' AND fecha_limite < now())`, expuesto por una **vista** o calculado en la consulta. **No auto-escribir 0**: es una escritura implícita que puede ser incorrecta y que el proyecto no debe afirmar sin verificación. El docente fija el 0 explícitamente si corresponde. |
| **Cierre de entregas** | `permitir_entrega_tardia = false` corta la entrega. | El RPC `m6_entregar_tarea` valida `now() <= fecha_limite OR permitir_entrega_tardia`; si no, responde error de negocio. **Sin job.** |

> Esto encaja con la regla del proyecto: la autorización y las reglas viven en RLS/RPC, y **nada depende de que un planificador esté corriendo** cuando hay corte eléctrico.

### I.5 Nota borrador vs. nota asignada (y la escala de 20)

| Hallazgo Google | Recomendación INCES |
|---|---|
| `draftGrade` (solo docente) → al devolver se copia a `assignedGrade` (visible). | Dos columnas: `nota_borrador` (visible solo al docente por RLS) y `nota_asignada` (visible al estudiante **solo** cuando `estado='DEVUELTA'`). El RPC `m6_devolver_entrega` hace `nota_asignada := nota_borrador` y `estado := 'DEVUELTA'`. |
| No puede haber `assignedGrade` sin `draftGrade`. | Reforzar con `CHECK (nota_asignada IS NULL OR nota_borrador IS NOT NULL)`. |
| `maxPoints` arbitrario; INCES califica **sobre 20**. | `puntos_maximos numeric DEFAULT 20 CHECK (puntos_maximos = 20 OR puntos_maximos <= 20)` y `CHECK (nota BETWEEN 0 AND puntos_maximos)`. **La escala es 20, no 100.** Si un lapso necesitara otra escala, se cambia el CHECK, no el diseño. |
| Promedio: total / ponderado / ninguno; renormaliza pesos. | Para el INCES: empezar con **promedio simple sobre 20** (suma de notas asignadas / cantidad de tareas calificadas). Ponderación por categoría queda **fuera de alcance** de M6 hasta que se pida. |

### I.6 Flujo docente → RPCs propuestos

| Paso del flujo Google | RPC INCES (`security definer`) | Efecto |
|---|---|---|
| Crear tarea (borrador) | `m6_crear_tarea(seccion_id, …)` | Inserta `m6_tareas` con `estado='BORRADOR'`. |
| Asignar / publicar | `m6_publicar_tarea(tarea_id)` | `estado='PUBLICADO'`, `publicado_en=now()`, e **inserta las entregas placeholder** por cada `enrollment` activo. |
| Alumno entrega | `m6_entregar_tarea(entrega_id, adjuntos…)` | `estado='ENTREGADA'`, `entregada_en=now()`, `es_tardia := now() > fecha_limite`; valida `permitir_entrega_tardia`. |
| Alumno des-entrega | `m6_reclamar_entrega(entrega_id)` | `estado='RECLAMADA'` (análogo a `RECLAIMED_BY_STUDENT`). |
| Docente califica | `m6_calificar_entrega(entrega_id, nota)` | `nota_borrador := nota` (0..20). |
| Docente devuelve | `m6_devolver_entrega(entrega_id)` | `nota_asignada := nota_borrador`, `estado='DEVUELTA'`, `devuelta_en=now()`. |

Todos los RPC verifican en su interior que el actor sea docente de la sección (o el alumno dueño), y las **lecturas** quedan cubiertas por RLS.

### I.7 Pestañas y UX del Tablón para el INCES

| Pestaña | Contenido en el INCES |
|---|---|
| **Tablón** | Feed **cronológico** (más reciente arriba) que agrega `m6_anuncios` + `m6_tareas` publicadas de la sección. Panel lateral **«Próximas entregas»**: tareas con `fecha_limite >= now()` de **las secciones donde el estudiante tiene `enrollment` activo**, ordenadas por `fecha_limite` **ascendente**. Primero lo vencido (faltante), luego lo que vence pronto. |
| **Trabajo de clase** | Lista de `m6_tareas` (tipo `TAREA`/`MATERIAL`/`PREGUNTA`), agrupadas por `tema` y ordenadas por `orden`. |
| **Personas** | Derivado de M4 (`enrollments`) + M3 (`schedule_slots.teacher_id`). Sin tabla nueva. |
| **Calificaciones** | Libro por sección y lapso: filas = estudiantes (enrollments), columnas = tareas, celdas = `nota_asignada` / «faltante» derivado. **Semáforo** rojo/verde/negro como Google. Promedio sobre 20. |

**Orden de prioridad visual del Tablón (recomendación, no hecho copiado de Google):** 1) vencidas/faltantes, 2) vencen en las próximas 48 h, 3) resto de próximas, 4) publicaciones recientes. El bloque «Upcoming» de Google confirma la idea de un panel de próximos vencimientos; el algoritmo exacto de orden no está documentado.

---

## Lo que no pude verificar

Se declara explícitamente para no arrastrar afirmaciones sin respaldo:

1. **El algoritmo exacto del bloque «Upcoming»** del Tablón (orden ascendente por fecha límite, inclusión de tareas sin límite, ventana temporal). CustomGuide solo confirma que muestra «fechas límite próximas».
2. **El sentido del orden del feed del Tablón** (si es estrictamente descendente por fecha). CustomGuide solo dice «orden cronológico».
3. **El texto y el comportamiento exactos del botón «reabrir» (reopen)** en la UI actual. La API sí documenta `reclaim` y `return`; la palabra «reopen» como acción de UI no la pude verificar en una fuente primaria. Por eso en las recomendaciones usé los estados de la API, no un botón «reabrir».
4. **Que los estados `complete`/`missing`/`excused` se puedan distinguir por API.** La propia documentación de Google dice que **no** se distinguen; es una limitación reconocida. Mi recomendación de **derivar** «faltante» en lectura esquiva esa limitación.
5. **Los máximos de adjuntos en una entrega de alumno.** Solo verifiqué el máximo de 20 para `materials` de `CourseWork`/`Announcement`/`CourseWorkMaterial`.
6. **Las escalas de calificación personalizadas (letras).** La documentación dice que esos ajustes y datos **no están disponibles en la API**.

---

## Fuentes

| # | Fuente | URL |
|---|---|---|
| 1 | CourseWork (referencia de la API) | https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWork |
| 2 | StudentSubmissions (referencia de la API) | https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWork.studentSubmissions |
| 3 | Announcements (referencia de la API) | https://developers.google.com/workspace/classroom/reference/rest/v1/courses.announcements |
| 4 | CourseWorkMaterials (referencia de la API) | https://developers.google.com/workspace/classroom/reference/rest/v1/courses.courseWorkMaterials |
| 5 | Material (referencia de la API) | https://developers.google.com/workspace/classroom/reference/rest/v1/Material |
| 6 | Guía de calificaciones (key concepts / grades) | https://developers.google.com/workspace/classroom/guides/key-concepts/grades |
| 7 | Centros de Ayuda — Grade & return an assignment | https://support.google.com/edu/classroom/answer/6020294 |
| 8 | Google Workspace Updates — Disable submissions after a due date (2023-07-27) | https://workspaceupdates.googleblog.com/2023/07/disable-submissions-after-due-date-in-google-classroom.html |
| 9 | CustomGuide — Google Classroom Navigation | https://www.customguide.com/course/google-classroom/google-classroom-navigation |
| 10 | CustomGuide — Post Announcement in Google Classroom | https://www.customguide.com/course/google-classroom/post-announcement-in-google-classroom |
