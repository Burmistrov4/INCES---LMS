# AUDITORÍA DE INVENTARIO — Módulo 4 y Planilla Dinámica

> **Fecha:** 2026-09-25 · **Tipo:** auditoría de lectura, sin cambios de código
> **Alcance:** `lib/screens/`, `lib/core/gateways/`, `lib/repositories/`, `lib/services/`,
> `lib/models/`, `supabase/migrations/`, `backend/src/http/`, y la planilla física en PDF.
> **Objetivo:** saber qué existe de verdad antes de construir el MVP, para no rehacer lo hecho.

**Método.** Lectura directa del código, no de la memoria del proyecto ni de los resúmenes.
La planilla física se extrajo del PDF con `pypdf` (1 página, 1917 caracteres) y se comparó
**campo a campo** contra la tabla `inscripcion_campos`. Todas las afirmaciones de este
informe llevan archivo y línea, o una medición. **Durante la auditoría no se modificó
ningún archivo.**

---

## 1. Inventario real

### 1.a Selección de ofertas del aspirante

- **`PanelOfertas`** — vive **dentro de** `lib/screens/aspirante_dashboard.dart:473`, no en
  un archivo propio. Lee `v_ocupacion_secciones` y respeta la regla de no-doble-venta **en
  la interfaz**: si `ofertaVigente == true`, el botón «Inscribirme» queda deshabilitado con
  la etiqueta «Asiento en asignación» **aunque `cuposDisponibles > 0`**.
- **`PanelMisInscripciones`** — mismo archivo, línea 685. Honra el ciclo de estados
  completo: `WAITLISTED` (posición en cola + renunciar), `PENDING_BID` (cuenta regresiva
  refrescada a 1 Hz + aceptar/renunciar), `ENROLLED` y `DROPPED`.
- **Cadena de datos:** `InscripcionesRepository` → `InscripcionGateway` → **Fastify**.
  Las rutas existen de verdad en `backend/src/http/openapi.ts`: `/api/v1/mis-inscripciones`,
  `/api/v1/inscripciones`, `/api/v1/inscripciones/{id}/aceptar`, `/renunciar`.
- **Matiz de vocabulario:** en esta pantalla el aspirante elige **asiento**, no curso. No hay
  catálogo de programas aquí; la oferta formativa se elige en el formulario de inscripción.

### 1.b Formulario dinámico y catálogo de campos

- **`AspiranteFormScreen`** (`lib/screens/aspirante_form_screen.dart`, **955 líneas**) — sí
  es un **renderizador puro**: un `Stepper` vertical con un paso por `grupo` del catálogo, en
  el orden que el catálogo declara. Alcanzable en la ruta `/inscripcion` (`lib/main.dart:41`)
  y desde `lib/screens/login_screen.dart:400`.
  Lo único que la pantalla sabe por su cuenta está justificado en el código: la contraseña
  (no es un dato de la planilla, es la credencial de la cuenta) y la regla de edad del
  representante legal (la columna `condicion` compara un campo contra otro, y aquí la
  condición es la edad).
- **`CpanelInscripcionCamposPanel`** (`lib/screens/admin/`, **954 líneas**) — la
  administración del catálogo.
- **Dos fronteras separadas a propósito** (`lib/core/gateways/planilla_admin_gateway.dart`):
  `PlanillaGateway` es la ruta **pública** (el aspirante sin cuenta, vía Fastify, sin token) y
  `PlanillaAdminGateway` es la **administrativa** (PostgREST directo, y su frontera de
  autorización es la RLS, ADR-003).
- **Catálogo en la nube:** **44 campos, 13 obligatorios, 9 grupos**.

### 1.c Cola FIFO y aprobaciones en el cPanel

- **`CpanelInscripcionesPanel`** — ocupación por sección y tres acciones: **Expirar ofertas**
  (idempotente), **Promover siguiente** y **Reincorporar**.
- **`ColaSeccionDialog`** — la cola FIFO **en modo lectura**: posición grande, orden de
  llegada calculado por la base, **sin ninguna acción**. Se abre con `mostrarColaDeSeccion()`.
- **`CpanelSeccionesPanel`** — alta y archivado de secciones (el archivado es reversible; no
  hay borrado, porque se llevaría el historial de inscripciones).
- Los tres están registrados en `admin_dashboard.dart` (líneas **196**, **201**, **206**).
  **Ninguna pantalla huérfana.**

---

## 2. Gap analysis hacia el MVP

### 2.1 ¿El catálogo permite marcar obligatorios/opcionales desde el cPanel hoy?

**Sí. Ya está construido.** El diálogo de edición tiene un `SwitchListTile` de «Obligatorio»
(`cpanel_inscripcion_campos_panel.dart:861`) y `PlanillaAdminGateway.actualizar` acepta
`obligatorio:` en su firma (`planilla_admin_gateway.dart:56-64`). Además se editan
`etiqueta`, `ayuda`, `grupo`, `activo` (interruptor en línea) y `orden` (intercambio con el
vecino del grupo).

**Corrección a la memoria del proyecto.** La memoria listaba como brecha *«formulario
conducido por datos con obligatoriedad configurable»*. **Esa brecha está cerrada** desde la
Entrega 5. Lo que **no** se edita: `codigo` y `tipo` (inmutables por diseño — la firma del
gateway no los acepta, así que no hay forma de mandarlos por descuido), `condicion`,
`aplica_a` y `opciones`.

### 2.2 ¿Los campos para la convergencia con HACER ya se capturan en `datos_planilla`?

**No se puede afirmar, y ésa es la respuesta honesta.** Lo medido:

- **No existe ninguna especificación de HACER en el repositorio.** La palabra aparece **3
  veces**, todas en comentarios que la nombran como consumidor futuro. No hay contrato de
  exportación.
- **No existe código de exportación.** Cero generadores de CSV/XLSX (`grep` sobre `lib/`,
  `backend/src/` y `backend/scripts/`).
- **Lo que sí se puede medir:** el catálogo es una transcripción **fiel** de la planilla
  física. Comparado campo a campo, cubre todo lo que la planilla pregunta.
- **Dos añadidos que la planilla NO tiene:** los 5 campos del representante legal
  (`numero_identidad_tutor`, `nombre_tutor`, `parentesco_tutor`, `telefono_tutor`,
  `correo_tutor`) y `curso_seleccionado`. Son requisitos del sistema, no transcripción.
- **Lo que falta de la planilla: la cabecera.** `FECHA`, `PROYECTO`, `ESPACIO INTEGRAL
  SOCIALISTA` y `HORARIO` no están capturados ni derivados. El comentario de
  `202609240001:471-474` dice que «se derivan de la sección y del lapso», pero **no hay
  código que los derive** y no viven en `datos_planilla`. Una exportación tendría que hacer
  JOIN con sección + programa + materia + horario.
- `EDAD` (que la planilla pide en años) sí es derivable de `fecha_nac`. `numero_preimpreso`
  sí está capturado.

**Conclusión:** el *dato* está casi todo; la *convergencia* es hoy un deseo, no un artefacto.
Antes de escribir una línea de exportación hace falta **la lista de campos que HACER espera**,
y eso es una pregunta para el CFS, no para el código.

### 2.3 Estado de cada pantalla de M4

| Pantalla | Estado |
| --- | --- |
| `PanelOfertas` / `PanelMisInscripciones` | Terminadas |
| `AspiranteFormScreen` | Terminada |
| `CpanelInscripcionCamposPanel` | Terminada |
| `CpanelSeccionesPanel` | Terminada, con entrada manual de IDs |
| `CpanelInscripcionesPanel` | Terminada en lo que muestra; **la reincorporación es inoperable** |
| `ColaSeccionDialog` | Terminada como **lectura**, sin acciones |
| Exportación a HACER | **No existe** |
| Editar perfil del aspirante | **No existe** |

---

## 3. Reporte de situación

### [CONSTRUIDO Y VERIFICADO]

- Flujo del aspirante completo y honesto: catálogo → formulario → `signUp` → trigger atómico
  → ficha.
- Oferta de cupos con la regla anti-doble-venta visible en la interfaz.
- Ciclo de estados de inscripción con cuenta regresiva.
- Administración del catálogo **sin tocar código**: obligatoriedad, etiqueta, ayuda, grupo,
  orden y encendido.
- Cola FIFO con posición calculada por la base.
- Las tres pantallas del cPanel alcanzables desde el menú.
- 44 campos y 13 obligatorios cargados en la nube.

### [PARCIAL / REQUIERE AJUSTE]

**1. Trampa de «obligatorio + condicional» — el hallazgo que más urgía.**
> **CERRADO el 2026-09-25** por `202609250003_fix_validar_planilla_condicionales.sql`
> (aplicada en la nube) y por el cambio de `cpanel_inscripcion_campos_panel.dart`.
> Se deja escrito el hallazgo **como se midió**, porque describe el estado del
> 2026-09-25 antes de la corrección: lo que envejeció es su vigencia, no su verdad.
> Verificación: `validate.mjs` **468/468** (+5 aserciones con control negativo),
> `verificar-esquema.mjs` sin fallos, y **sonda viva** armando la trampa a mano.

Es un fallo alcanzable con **un clic**, y el clic es la funcionalidad que se acaba de
entregar:

- El panel deja marcar `obligatorio` en **cualquier** campo, incluidos los condicionales
  (`pueblo_indigena_cual`, `tipo_discapacidad`). No hay guarda en el diálogo ni en
  `actualizar`.
- El formulario, si la condición no se cumple, **oculta el campo y no lo envía**
  (`aspirante_form_screen.dart:386-391`, `_construirPlanilla` filtra por `visibleCon`).
- `validar_planilla()` exige todo campo `activo and obligatorio` **sin mirar `condicion`**
  (`202609240001`, líneas 259-273).
- **Consecuencia:** el aspirante rellena los 9 pasos, el formulario valida en verde, y el
  registro **falla en el último paso** con `23514` nombrando un campo que **nunca vio**.
- **La base no lo impide:** la única restricción de la tabla es el formato de `codigo`
  (líneas 145-146). El aviso del propio panel describe el riesgo, pero nada lo bloquea.

**Cómo quedó cerrado (2026-09-25).** `validar_planilla()` evalúa ahora `condicion` contra
los datos enviados mediante `condicion_campo_se_cumple()`, que replica
`CondicionCampoInscripcion.seCumple` y `CampoInscripcion.obligatorioCon` de Dart — la
comparación de **dos lados** (`true`/`1` el mismo «sí», `false`/`0` el mismo «no») y una
clave ausente no cumple ninguna condición. El interruptor «Obligatorio» del panel queda
**deshabilitado** cuando el campo tiene condición. Medido antes de escribir: **0 de los 2
campos condicionales estaba obligatorio**, así que la trampa no estaba armada y el arreglo
no cambia ninguna inscripción real. Deuda anotada: un campo condicional **ya** obligatorio
en la base no se puede **desmarcar** desde el panel; hoy no existe ninguno.

**2. `aplica_a` es dato muerto.** La columna existe, el modelo Dart la lee, el panel la pinta
como insignia «Sólo N programas»… y **nada la hace cumplir**: no filtra en el backend, ni en
la base, ni en el formulario. Hoy no se puede editar y no afecta a nada.

**3. La reincorporación es inoperable por un humano.** `_DialogoReincorporar` pide «ID del
estudiante» e «ID de la sección» en crudo. El endpoint que daría la lista ya existe
(`/api/v1/admin/secciones/{id}/inscripciones`) y no se usa.

**4. No hay aprobación por persona.** «Promover siguiente» promueve **al primero de la cola**,
siempre. No se puede elegir a alguien concreto, y el diálogo de la cola —que sí muestra a las
personas— no tiene botones.

**5. Deriva documental menor.** El comentario en `202609240001:523-527` dice «hoy el
formulario mete todo eso en un único campo de texto libre» refiriéndose a la ubicación. El
catálogo ya tiene `estado`, `municipio`, `parroquia` y `comunidad` separados y el formulario
los pregunta así. El comentario describe el estado anterior.

### [MISSING / PENDIENTE]

- **Exportación a HACER** (y su especificación de campos).
- **Editar perfil** del aspirante.
- **Cabecera de la planilla** (PROYECTO / ESPACIO INTEGRAL SOCIALISTA / HORARIO / FECHA) sin
  capturar ni derivar.
- **Edición de `opciones`**, `condicion` y `aplica_a` desde el panel.
- **Arrastrar y soltar** para reordenar (hoy es intercambio con el vecino, que funciona).

---

## 4. Recomendación: la menor edición iterativa

> **EJECUTADA el 2026-09-25** (los dos puntos, en una sola entrega): migración
> `202609250003_fix_validar_planilla_condicionales.sql` **aplicada en la nube** y el
> interruptor deshabilitado en `cpanel_inscripcion_campos_panel.dart`. Lo que sigue es la
> recomendación **tal como se entregó**, no una tarea pendiente.

No es la exportación. Es cerrar la trampa, porque es lo único que puede **hacer fallar una
inscripción real**:

1. **Que la base y el formulario coincidan** (~10 líneas de SQL). En `validar_planilla()`,
   saltar los campos cuya `condicion` no se cumple **en el propio `p_datos`**. El payload ya
   está ahí; es evaluarlo. Sin esto, la obligación es una trampa.
2. **Que el panel no la cree** (~5 líneas de Dart). Deshabilitar el interruptor de
   «Obligatorio» cuando `campo.condicion != null`, con el motivo a la vista — que ya está
   escrito en el aviso del diálogo, sólo que hoy no se aplica.

Con esas dos cosas, el flujo completo —inscripción, cupo, cola, promoción— queda operativo de
punta a punta.

Lo de HACER es una fase aparte que empieza **preguntando qué campos espera HACER**, no
escribiendo código.

---

*Informe de auditoría. Ninguna afirmación aquí es una estimación: cada una lleva archivo y
línea, o una medición reproducible.*
