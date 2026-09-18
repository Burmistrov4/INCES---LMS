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

## R-06 · Dos convenciones de período incompatibles — **RESUELTA (2026-09-15): el lapso vigente es `SA26-2`**

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

## R-12 · `academic_periods` convierte la divergencia silenciosa de R-06 en una violación ruidosa

**Gravedad: alta (la levanta). Refina R-06, no la cierra.**

R-06 describe el peor fallo posible: `sections.period_code` y
`system_settings.periodo_activo` son dos cadenas comparadas por igualdad exacta, y
si no coinciden **la Regla 2 nunca dispara y no avisa**.

El requisito de M3 pide `academic_periods` (`code`, `start_date`, `end_date`,
`is_active`). Eso da por fin un **registro** contra el que comparar:

- `sections.period_code` pasa a ser **FK** contra `academic_periods.code`. Ya no
  se puede crear una sección con un lapso inventado.
- Un **guarda** sobre `system_settings` rechaza un `periodo_activo` que no nombre
  un período registrado. Si alguien escribe `SA26-2` mientras el registro sólo
  tiene `2026-1`, **falla al guardar**, no dentro de seis meses.

**Lo que esto NO decide:** cuál es la nomenclatura. `academic_periods` hace que el
código sea **dato administrable**, pero el valor sigue siendo una decisión de
coordinación del INCES (¿`2026-1` o `SA26-2`?). Se siembra `2026-1` —el valor que
ya está en producción— para no romper nada, y el administrador renombra o añade
desde el panel cuando el centro decida.

> La diferencia importa: antes, elegir mal la convención producía un sistema que
> decía «todo bien» sin proteger nada. Ahora produce un error de guardado. Se
> cambia un fallo mudo por uno que se ve. **R-06 sigue abierta como decisión.**

---

## R-13 · Las colisiones cruzan DOS tablas, y una restricción `unique` no puede cubrirlo

**Gravedad: alta. Es el corazón del requisito 4.**

El requisito dice: *un docente o un aula NO pueden estar asignados a dos
clases/guardias distintas en el mismo bloque*. Léase con cuidado: la colisión es
**entre** `schedule_slots` y `teacher_duties`, no sólo dentro de cada tabla. Una
`unique` no puede abarcar dos tablas.

Además, en `schedule_slots` el período **no es una columna**: se deriva de
`sections.period_code`. Una `unique (teacher_id, day_of_week, block)` sería
**incorrecta**: bloquearía al mismo docente dando clase el mismo bloque en dos
lapsos distintos, que es legítimo (el cuadrante del lapso siguiente se planifica
mientras corre el actual).

**Resolución:** una única función `exigir_agenda_libre()` que consulta **las dos
tablas**, acotada por período, día y bloque; y dos triggers finos que la llaman.
Se descartan las `unique` a propósito:

- **Un solo camino de cumplimiento ⇒ un solo mensaje de error.** Con `unique` +
  trigger habría dos rutas y dos mensajes distintos para el mismo problema, y la
  traducción de errores del backend tendría que reconocer ambos.
- **La carrera se cubre con un cerrojo, no con la restricción.**
  `pg_advisory_xact_lock` sobre (período, día, bloque) serializa las escrituras
  que podrían chocar. Sin él, dos inserciones simultáneas podrían pasar las dos.

---

## R-14 · `profiles` sólo deja leer el perfil propio: el estudiante no vería el nombre del docente

**Gravedad: media. Rompe la vista del estudiante si no se resuelve.**

El backend no usa la `service_role` para datos personales: usa el **JWT del
llamante**, así que **RLS es la barrera real** (ver `infra/supabase.ts`, y es
deliberado). Consecuencia: la política `profiles_read_own` limita `SELECT` a la
fila propia, y una vista con `security_invoker` que una `profiles` para poner el
**nombre del docente** devolvería `NULL` para cualquier alumno.

Las salidas malas, descartadas:

- **Relajar `profiles` a `authenticated`.** RLS no filtra por columnas: expondría
  `cedula` y `email` de todo el mundo. No.
- **Vista `security_definer`.** Salta la RLS de las tablas base; un error en el
  `WHERE` deja el horario de todo el centro a la vista de un alumno.

**Resolución:** una función estrecha, `security definer`,
`nombre_para_mostrar(uuid)` que devuelve **sólo** `nombres || ' ' || apellidos` y
**sólo** si el destino tiene `rol in ('docente','admin')` y está activo. Nada de
cédula ni correo. El nombre de un docente es información institucional pública; su
cédula no.

---

## R-15 · Una guardia sin período vuelve la colisión imprecisa

**Gravedad: media.**

El requisito dice que las guardias son *independientes de si hay clase activa*.
Eso explica **por qué existen**, no que no pertenezcan a un lapso. Pero no declara
período para ellas.

Sin período, una guardia del lunes bloque 1 chocaría con una clase del lunes
bloque 1 **de cualquier lapso**, incluido uno futuro que aún no empieza.

**Resolución:** `teacher_duties.period_code` con FK a `academic_periods`. La
colisión se acota por período, igual que en `schedule_slots`. Es coherente con el
resto del modelo y permite planificar el lapso siguiente sin tocar el vigente.

---

## R-16 · «Turno mañana/tarde» y «bloque» son dos formas de decir lo mismo, y pueden contradecirse

**Gravedad: media.**

El requisito 3 habla de *turnos mañana/tarde* y el 4 de *día/bloque horario*. Si
se guardan como dos columnas independientes, nada impide un turno «MAÑANA» con
bloque 9 — un dato incoherente que nadie detecta hasta que el cuadrante se ve mal.

**Resolución:** `turno` es una **columna generada** a partir de `block`, mediante
una función inmutable `turno_de_bloque(block)` compartida por las dos tablas. No
se puede contradecir porque no se almacena: se deriva. Y si el centro mueve la
frontera entre mañana y tarde, se cambia en **un** sitio.

> Contrapartida honesta: el corte queda en el código (bloques 1–6 mañana, 7–12
> tarde) hasta que se decida. Si el centro necesita bloques con horas reales
> (`07:00–07:45`), el paso siguiente es una tabla `schedule_blocks` administrable.
> **No se decidió por cuenta propia**: se dejó el mecanismo, no la convención.

---

## R-17 · Las fechas reales del período no se inventan

**Gravedad: baja, pero es una regla de honestidad.**

`academic_periods` necesita `start_date` y `end_date`. El centro **no ha cargado
esas fechas** en ningún sitio del que yo pueda leerlas.

**Resolución:** las dos columnas son **anulables** y el período sembrado
(`2026-1`) nace **sin fechas**. Inventarlas —«el lapso 2026-1 va de enero a
junio»— sería fabricar dato institucional y presentarlo como cargado. El
administrador las completa desde el panel. Se añade un `check` que exige
`end_date > start_date` **cuando ambas están presentes**.

---

## R-18 · «Aula/zona»: las zonas no son aulas

**Gravedad: baja. Es de vocabulario.**

El requisito 3 asigna la guardia a *un aula/zona* (`classrooms.id`), pero el
requisito 1 describe `classrooms` como registro de **aulas y talleres**, con
`capacity` e `is_workshop`. Una zona (patio, pasillo, entrada) no es ninguna de
las dos.

**Resolución:** no se inventa una segunda tabla. Una zona se registra como fila de
`classrooms` con `capacity = 0` e `is_workshop = false`, y su nombre lo dice
(«Patio central»). Se mantiene **un solo concepto de espacio**, que es lo que hace
que el trigger de colisión sea uniforme: si hubiera dos tablas de espacios, la
colisión habría que comprobarla en cuatro sitios en vez de dos.

---

## R-19 · «Período activo» significa dos cosas distintas a la vez

**Gravedad: media. Es de diseño, y se resuelve nombrando las dos.**

Al añadir `academic_periods.is_active` quedaron **dos** campos que responden a la
pregunta «¿cuál es el período activo?»: la columna `is_active` del lapso y el
parámetro `system_settings.periodo_activo` (que ya existía, y que R-12 acaba de
atar al catálogo). Dos fuentes de verdad para lo mismo es exactamente la clase de
divergencia que R-12 fue a eliminar, reapareciendo un nivel más arriba.

**No son lo mismo, y ése es el caso real del centro:** al cerrar un lapso se
prepara el siguiente mientras el vigente sigue dictándose. Puede haber varios
lapsos **abiertos** y sólo uno **vigente**.

**Resolución:** se separan por nombre y por camino.

| Concepto | Campo | Significado |
| --- | --- | --- |
| Abierto | `academic_periods.is_active` | Se puede planificar en él |
| Vigente | `system_settings.periodo_activo` | La UI lo muestra por defecto |

El vigente se mueve por **una sola ruta** (`PUT /api/v1/admin/periodos/:id/vigente`)
y no por `PATCH /periodos/:id`, para que no haya dos caminos que cambien lo mismo.
Y sigue en pie la guarda de R-12: el vigente **tiene** que existir en el catálogo.

Si el INCES decide que sólo necesita uno de los dos conceptos, se puede retirar
`is_active` sin tocar código de aplicación: nadie lo usa para decidir nada.

---

## R-20 · Un trigger `security invoker` que llama a una función revocada: el módulo entero inoperable

**Gravedad: crítica. Estuvo aplicado en producción hasta que se corrigió.**

No es una contradicción del enunciado, sino un fallo propio, y se documenta aquí
porque es el más grave de todo el proyecto hasta ahora.

La migración `202609180001` declaró los dos envoltorios de trigger como
`security invoker` y a la vez revocó el `EXECUTE` de `exigir_agenda_libre()` a
`authenticated`. Con `invoker`, el envoltorio corre con los privilegios del
llamante, que no tiene `EXECUTE` sobre la función delegada. Comprobado contra la
nube:

```
ERROR: 42501: permission denied for function exigir_agenda_libre
CONTEXT: PL/pgSQL function teacher_duties_exigir_agenda() line 9 at PERFORM
```

**Toda alta de guardia o de clase fallaba**, y la protección anti-colisión ni
llegaba a evaluarse. El módulo era inoperable para cualquier usuario real.

**Por qué no lo vio una batería de 156 aserciones en verde:** las pruebas del
trigger escribían como el **dueño** de las tablas (`postgres`), y el dueño se
salta la comprobación de privilegios de función. El caso probado no era el caso
de producción. Es la misma trampa ya documentada con los repositorios en memoria:
**un doble que corre con más permisos que el usuario real no prueba al usuario
real.**

**Resolución** (`202609180002`): los envoltorios pasan a `security definer` con
`set search_path` fijo. No amplía lo que el llamante puede escribir —la RLS se
evalúa aparte y el envoltorio no devuelve dato alguno— y no es invocable a mano,
porque PostgreSQL no permite llamar directamente a una función que devuelve
`trigger`. La función delegada **sigue revocada**: la puerta es el trigger.
No se «arregló» concediendo `EXECUTE` a `authenticated`, que también habría
funcionado pero habría vuelto la función un oráculo de la agenda ajena.

**Lo que quedó para que no vuelva:** la sección 14.8 de `supabase/tests` escribe
como `authenticated` con claims de admin (falla si el envoltorio vuelve a
`invoker`), `verificar-esquema.mjs` comprueba `prosecdef` contra la nube, y se
demostró el fail-first de las cuatro aserciones nuevas.

> **Nota que casi engaña a la propia prueba:** «el trigger sigue protegiendo»
> **pasaba** con el fallo presente, porque sólo exigía *algún* error y recibía
> `42501` en lugar de `23514`. Por eso la aserción siguiente comprueba el
> **código**. Una prueba que acepta cualquier error no prueba la regla: prueba
> que algo se rompió.

---

## R-21 · El nombre del docente llega vacío al cuadrante: `nombre_para_mostrar()` devuelve NULL — **RESUELTA (2026-09-15)**

**Encontrado el 2026-09-15** por `supabase/humo-cuadrante.mjs`, el humo real de
M3. **No lo podía ver ninguna prueba con dobles**, y ninguna de las 341 del
backend lo ve: el doble en memoria devuelve `'Carlos Rondón'` porque el *fixture*
tiene nombre.

### Qué pasa

`v_cuadrante_clases.teacher_name` sale **NULL** para un docente real. La columna
del docente en el cuadrante —y el nombre del profesor en el horario del
estudiante— quedan en blanco.

### Por qué, con la cadena entera

1. `profiles.nombres` y `apellidos` son `text not null`, **sin valor por
   defecto**.
2. `handle_new_user()` inserta `coalesce(v_nombres, '')`, y `v_nombres` sale de
   `raw_user_meta_data ->> 'nombres'`. **Sin metadatos, guarda `''`** — cadena
   vacía, no NULL.
3. El único canal que crea docentes es la invitación, y
   `crearUsuarioDocente(email, password)` llama a
   `auth.admin.createUser({ email, password, email_confirm: true })`
   **sin `user_metadata`**. `POST /auth/activar` sólo acepta `token` y
   `password` (`esquemaActivarCuenta`), y **no existe ninguna ruta que fije
   `nombres`/`apellidos`**.
4. `nombre_para_mostrar()` hace
   `nullif(btrim(p.nombres || ' ' || p.apellidos), '')`. Con `'' || ' ' || ''`
   queda `' '`, `btrim` lo deja en `''` y el `nullif` lo convierte en **NULL**.

### Lo que NO es el fallo

- **La función está bien escrita.** El `nullif(btrim(…))` es precisamente lo que
  evita que la rejilla pinte un espacio en blanco en vez de nada. Se comprobó
  contra la base real: las columnas contienen `''`, no NULL, y la función las
  normaliza correctamente.
- **No es un problema de la RLS ni de `security_invoker`.** La vista resuelve el
  nombre en cuanto existe: el humo fija `nombres`/`apellidos` a un docente
  temporal y `teacher_name` sale `'Luisa Márquez'`. El aislamiento por rol
  también es correcto (el estudiante ve sus secciones y no puede leer
  `profiles`).

### Dónde está, entonces

**Aguas arriba: nadie captura el nombre del docente.** Es un hueco del **Módulo
1**, no del 3. M3 construyó la forma de mostrar el nombre (R-14) sobre un dato
que el canal de alta nunca llena.

### Opciones, y por qué no elijo ninguna

| Opción | Efecto | Quién decide |
| --- | --- | --- |
| **A.** Que la invitación (o la activación) pida nombres y apellidos | Arregla la causa. Toca la pantalla de invitación de M1, el `POST /admin/usuarios/invitaciones` y el esquema Zod | **Equipo** — es alcance de M1, no de M3 |
| **B.** Que `nombre_para_mostrar()` caiga al correo | Haría visible el nombre… y **filtraría el correo del docente a cualquier estudiante**, que es exactamente lo que R-14 evitó | Descartada por diseño |
| **C.** Que la interfaz muestre «Docente sin nombre» cuando es NULL | No arregla nada, pero deja de ser un hueco mudo | Equipo, y sólo como parche |

**Recomendación: A.** Es la única que arregla la causa, y el coste es un campo
más en un formulario que ya existe.

> **Lo que sí queda cerrado:** el humo comprueba las dos mitades —que el nombre
> se resuelve cuando existe, y que sin nombre sale NULL— así que el día que se
> implemente A, la segunda aserción falla y obliga a actualizarla. El defecto no
> puede volver a pasar inadvertido.

### Verificación

`node supabase/humo-cuadrante.mjs --confirmar` → **53/53**, con estas dos
comprobaciones entre ellas:

```
[OK  ] R-14: la vista resuelve el NOMBRE del docente cuando existe
[OK  ] R-21: un docente sin `nombres`/`apellidos` da `teacher_name` NULL
[OK  ] R-21: y sus columnas están VACÍAS (no NULL): `handle_new_user` inserta coalesce(…, '')
[OK  ] R-21: `nombre_para_mostrar` convierte ese vacío en NULL con nullif(btrim(…)) — la función está bien; el hueco está aguas arriba
```

---

## R-22 · El panel de M2 estaba construido, probado… e inalcanzable desde el menú

**Encontrado y resuelto el 2026-09-15** al revisar el frontend para planificar
M3. **No lo veía ninguna de las 197 pruebas de Flutter**, y la razón es la misma
que el proyecto ya documentó para los paneles: **se prueban donde no viven**.

### Qué pasa

`Programas Académicos` —la sección que abre el asistente de currículo de M2—
tiene `disponible: false` en el menú del cPanel:

- `lib/screens/admin_dashboard.dart:81`

Y `AndamiajeApp` **no envuelve en `InkWell`** un ítem no disponible:

```dart
// lib/widgets/andamiaje.dart:428-436
// Una sección sin construir no es pulsable: llegar a una pantalla vacía es
// peor que no poder entrar.
if (!item.disponible) return conTooltip;

return InkWell(onTap: onTap, …);
```

Consecuencia: el ítem se pinta atenuado, con el icono de obra y el tooltip
«pendiente de construir», y **el clic no llega nunca a `onSeleccionar`**. Como
`_seleccionada` sólo cambia por esa vía, el `case 'Programas Académicos'` del
`switch` (`admin_dashboard.dart:161-165`) es **código muerto**: el panel existe,
funciona y está probado, pero no hay forma de abrirlo desde la aplicación real.

### Por qué es un resto obsoleto, y no una decisión

El historial lo cierra:

| Commit | Qué hizo |
| --- | --- |
| `004923a` — *feat(modulo1)… y overhaul de UI* | **Añadió** el ítem con `disponible: false`. Entonces **M2 no existía**: la bandera era correcta |
| `ec361ac` — *feat(modulo2): UI del asistente de curriculo y pensum* | **Añadió** `CpanelProgramasPanel`, su `import` y el `case` del `switch`… **y no volteó la bandera** |

Es el mismo patrón que D11 («documentado ≠ desplegado»), un escalón más abajo:
**construido y probado ≠ alcanzable**.

### Por qué ninguna prueba lo vio

**Ninguna prueba monta `AdminDashboardScreen`.** Las 197 cubren los paneles
montándolos directamente dentro de `ContenidoSeccion` —que es lo correcto para
probar el layout, y es justo lo que destapó el crash de altura acotada— pero
**el cableado del menú queda sin cubrir**. `test/contenido_seccion_test.dart:206`
monta `CpanelProgramasPanel` a mano; nunca pasa por el dashboard que lo abre.

La lección no es «faltan pruebas de widget», es más fina: **probar el panel donde
vive no prueba que se pueda llegar a él.** Son dos contratos distintos, y sólo
uno estaba cubierto.

### Arreglo aplicado

1. **Quitada la bandera** `disponible: false` del ítem `Programas Académicos`
   (`admin_dashboard.dart`). Una línea.
2. **Añadida la prueba que faltaba** — `test/menu_alcanzable_test.dart`, 6 casos,
   y es la parte que importa. No se escribió como un espejo a mano (una lista de
   títulos copiada en la prueba sólo probaría que la copia coincide consigo
   misma): **lee `admin_dashboard.dart` como texto** y exige que las secciones
   disponibles y las ramas del `switch` **coincidan en las dos direcciones** —
   con rama y sin bandera es inalcanzable (R-22); sin rama y con bandera abre en
   blanco, que es peor que no poder entrar. Lleva **suelo explícito** (≥8
   secciones, ≥6 ramas) para que un analizador roto falle en vez de dar un verde
   hueco, y dos pruebas del propio analizador sobre un texto de forma conocida.
   Se completa con la **prueba del mecanismo** en `AndamiajeApp`: un ítem no
   disponible no tiene `InkWell` y su toque no llega a `onSeleccionar`.
3. **Comprobado que la prueba tiene dientes.** Con la bandera restaurada falla:

   ```
   Expected: Set:['Módulos del Sistema', …, 'Programas Académicos']
     Actual: Set:['Módulos del Sistema', …]
    Which: does not contain 'Programas Académicos'
   ```

   Una prueba que sólo se ha visto pasar sobre el código ya arreglado no prueba
   nada.

**Verificación:** `flutter analyze` limpio · **203/203** pruebas Flutter (antes
197).

> **M3 hereda el mismo riesgo, y la prueba ya lo vigila.** `Cuadrante y Horarios`
> (`admin_dashboard.dart:83-88`) y `Mi horario` (`docente_dashboard.dart:57-62`)
> son hoy marcadores `disponible: false`. Al construirlos hay que levantar la
> bandera, y el contrato de (2) falla si se olvida — en la primera dirección
> mientras no exista la rama, y en la segunda en cuanto exista. El docente
> todavía no está cubierto por el contrato (su `_contenido()` no usa `switch`);
> **hay que extenderlo cuando se construya `Mi horario`**.

> **Nota, del mismo paseo.** Los tres dashboards llevan el período **escrito a
> mano** (`'2026-1'` en `admin_dashboard.dart:110`, `docente_dashboard.dart:65`,
> `aspirante_dashboard.dart:103`). El comentario que lo justificaba decía «cuando
> se construya el módulo de currículo, el período pasará a ser una selección
> real». M2 ya está, y M3 acaba de añadir `academic_periods` con su `is_active` y
> la guarda `periodo_activo` (R-12, R-19): **el encabezado ya puede leer el
> período vigente de verdad** en lugar de repetir una constante.

---

## R-23 · `enrollments` dejaba que cualquier usuario se auto-inscribiera: el motor de cupos nacía decorativo

**Encontrado el 2026-09-18** al construir la Fase 1 (Esquema) del Módulo 4.
**Ninguna prueba lo habría visto**, porque el defecto no está en el código que se
escribió para M4: está en el que ya estaba desde la migración inicial, y **se
vuelve dañino precisamente cuando M4 existe**.

### Qué pasa

`202609100001_init.sql:225-229` creó una política que permite a **cualquier**
usuario autenticado insertar su propia fila de inscripción:

```sql
create policy enrollments_insert_own
on public.enrollments
for insert
to authenticated
with check (student_id = auth.uid());
```

Y su hermana, `enrollments_update_own` (`:231-236`), deja **editar la propia
fila** —incluida la columna `status`— con el mismo criterio. Con
`enrollments_delete_own` (`:238-242`) se puede además **borrar la fila**.

La condición `student_id = auth.uid()` es correcta en lo que dice: nadie toca la
fila de otro. El problema es lo que **no** dice: no dice nada sobre `status`,
sobre el cupo de la sección, sobre la cola, ni sobre la ventana de bids.

### Por qué importa

En Fase 0, M4 no existía y estas políticas eran un andamio razonable. Al entrar
M4, el sistema pasa a tener un **motor de cupos**: `cupo_efectivo()`,
`cupos_ocupados()`, la cola FIFO, el estado `WAITLISTED`, la ventana de 24 h de
`PENDING_BID`, el cerrojo por sección. Todo ese motor vive en RPC
`security definer`.

**Y el cliente no lo necesita.** Con `enrollments_insert_own` vigente, un
estudiante autenticado hace un `insert` directo vía PostgREST con
`status = 'ENROLLED'` y **entra a la sección que quiera, aunque esté llena, sin
pasar por ninguna RPC**. El motor de cupos queda como una capa de cortesía: se
puede ignorar por completo.

Es exactamente el patrón de R-20, un escalón antes: no un módulo inoperable, sino
un módulo **operable y eludible**. La frontera de seguridad que el proyecto
declaró en ADR-003 (la RLS es el único control, porque la publishable key viaja
al cliente) **no estaba cerrada**.

### El agravante que sólo se ve midiendo

La decisión de producto nº 2 de M4 es **conservar la fila en `DROPPED` como
historial**. `enrollments_delete_own` **permite borrarla**: el propio estudiante
puede destruir el registro que el sistema quiere preservar.

Y hay un privilegio peor, que ninguna política de RLS gobierna: medido contra la
nube, `anon` **y** `authenticated` tenían el `grant all` por defecto de Supabase
sobre la tabla, **incluido `TRUNCATE`**. `TRUNCATE` **no pasa por la RLS**: no hay
política que lo detenga. Una sola sentencia vacía la tabla de inscripciones.

### Arreglo aplicado

Parte 6 de `202609190001_mod4_inscripciones.sql`:

```sql
revoke all on public.enrollments from anon, authenticated;
grant select on public.enrollments to authenticated;

drop policy if exists enrollments_insert_own on public.enrollments;
drop policy if exists enrollments_update_own on public.enrollments;
drop policy if exists enrollments_delete_own on public.enrollments;
```

Toda escritura pasa ahora por las seis RPC `security definer`, que se
auto-autorizan con `auth.uid()` en su interior. `enrollments_admin_all` **sigue
declarada**, pero queda **inerte**: sin el `GRANT`, no hay privilegio que la RLS
pueda permitir.

### Verificación

Probado **contra producción y como rol real** (`set role authenticated` +
`request.jwt.claims`, en transacción con `rollback` — no como el dueño de la
tabla, que es justo la trampa de R-20):

| Operación | Resultado |
| --- | --- |
| `INSERT` directo | **42501** `permission denied for table enrollments` |
| `UPDATE` directo | **42501** |
| `DELETE` directo | **42501** |
| `SELECT` propio | funciona |
| `anon`, cualquier cosa | **42501** |

Y el módulo **sigue siendo operable**, que es la mitad que R-20 enseñó a no
olvidar: un **no-admin real** (`c05df98e-…`) llega a la lógica de negocio a
través de `solicitar_inscripcion` (**23514** «La sección … no existe»), mientras
que las RPC de administrador le devuelven **42501**. Es decir: la frontera cierra
al cliente **y** deja pasar al estudiante legítimo.

### La lección, que es la parte reutilizable

**Un `SQLSTATE` solo no identifica la causa.** El `42501` del `INSERT` lo produce
la **falta de GRANT**, no la política borrada. Si alguien devolviera el `GRANT`,
la política ya no está y la RLS volvería a dar `42501` — **el mismo código por
otro motivo**. Para probar el arreglo hay que comprobar **además** que el
privilegio no existe, no sólo que la operación falla. Es la lección de R-20 («no
basta con que dé *algún* error») aplicada al arreglo mismo.

La QA lo comprobó con un **fail-first real**: neutralizó el `revoke` **en
memoria** —nunca tocó el archivo— y con la regla desactivada el `INSERT` directo
**pasó**. La aserción tiene dientes. El `sha256` de la migración es idéntico antes
y después:
`e4688586f422f456cd297f5f417010b32d2d342b4a04823195ecd18878c05ce2`.

**Verificación:** libro mayor 13/13 · `verificar-esquema.mjs` 89/89 · suite SQL
**212/212** (206 del arnés + 6 aserciones que añadió la QA para cerrar tres
huecos: `anon` no escribe, `anon` no lee, y **ni un admin escribe directo**).

> **Lo que queda sin probar, dicho sin adornos.** PGlite es Postgres real pero
> **no es Supabase**: no se ejercitó PostgREST ni GoTrue, así que la traducción de
> `42501` a un 403 en el backend **no está comprobada aquí** — corresponde a la
> Fase 2. Tampoco se probó **concurrencia real** (dos conexiones en paralelo): el
> cerrojo `pg_advisory_xact_lock` por sección está diseñado para eso, pero no se
> ha visto funcionar bajo carga. Ese es el trabajo del humo de la Fase 4, y es el
> único sitio donde puede probarse.

---

## R-24 · Diagnostiqué R2 con una inferencia que no medí: el token todavía no existía

**Qué pasó.** Al configurar Cloudflare R2 (Fase 2 de M4), la sonda contra el bucket
devolvió `AccessDenied` en todas las operaciones. Concluí —y lo dejé escrito en el
handover y en la memoria— que *«la firma es válida, así que el problema es de
alcance del token, no del cliente»*, y pedí a Lorenzo el nombre del bucket, el
alcance del token y la cuenta. **El diagnóstico era incorrecto y la petición
también.** Estuve a punto de mandarlo a revisar un panel que estaba bien.

**Qué pasaba de verdad.** Dos causas apiladas, ninguna de las cuales era el alcance
del token:

1. **El reloj de la máquina iba ~12 h desviado.** SigV4 firma con la hora local, y
   R2 rechaza cualquier firma fuera de la ventana de 15 minutos con
   `RequestTimeTooSkewed`. El SDK de AWS **corrige el desfase solo y reintenta**,
   así que ese error limpio nunca llegaba a la superficie: veía el resultado del
   reintento. El corrector automático convirtió un error claro en uno engañoso.
2. **El token de R2 no estaba vigente.** El endpoint `verify` de la API de
   Cloudflare devolvió los metadatos del propio token:

   ```json
   {"id":"e558f9149000a6c0701c926a76c472a1","status":"active",
    "not_before":"2026-09-18T08:59:52Z","expires_on":"2026-11-30T16:00:00Z"}
   ```
   y el mensaje explícito: *«This API Token can not be used before 2026-09-18
   08:59:52+00»*. Ese `id` **es** el `R2_ACCESS_KEY_ID`: el token nació mientras el
   reloj iba 12 h adelantado, así que su `not_before` quedó **en el futuro**. Al
   corregirse la fecha, el token pasó a estar «activo pero no vigente todavía».
   R2 responde **403 `AccessDenied`** a un token que existe y aún no puede usarse.

**La medición que lo destapó.** Un experimento de control, no una lectura:

| Prueba | Resultado |
|---|---|
| Credenciales reales | **403** `AccessDenied` |
| **Access key ID inventado** | **401 `Unauthorized`** |
| Bucket inventado (credenciales reales) | 403 `AccessDenied` |

Que una clave inventada dé **401** y la real **403** demuestra que R2 **sí**
distingue «esta clave no existe» de «esta clave no tiene permiso». Yo había
afirmado lo contrario **sin haberlo probado**: di por sentado que R2 se comportaba
como S3 y no lo verifiqué.

**Un tercer error propio, en la misma cadena.** Había concluido que el token `cfat_`
era **inválido**, porque `/user/tokens/verify` devolvía `1000 Invalid API Token`. No
era inválido: es un token **de cuenta**, y ese endpoint es el de tokens **de
usuario**. Contra `/accounts/{account_id}/tokens/verify` responde **HTTP 200**. Un
token correcto probado en la puerta equivocada parece roto — y encima me sirvió de
excusa para no poder desempatar el diagnóstico anterior. Dos inferencias no medidas
se apuntalaron mutuamente.

**La lección.** `AccessDenied` **no** significa por sí solo «la firma es válida, es
cuestión de alcance». R2 colapsa en el mismo 403 la firma incorrecta, el permiso
insuficiente **y el token aún no vigente** — tres causas con tres arreglos
distintos. El discriminador es el **experimento de control** (una credencial
deliberadamente falsa), no el nombre del error.

**Dos corolarios que generalizan:**

- **Antes de culpar al servicio remoto, mira el reloj.** Un desfase de 12 h rompe
  SigV4, y la corrección automática del SDK lo disfraza. Cuando una herramienta
  «se arregla sola» un error, hay que preguntarse qué está ocultando.
- **La vigencia es parte de la credencial.** `not_before` y `expires_on` se leen
  del propio token; inferir el estado de una credencial a partir de cómo falla es
  adivinar con pasos extra.

**Efecto colateral que hay que recordar:** con el reloj desviado, las **URL
prefirmadas** de M5 se firman con una hora falsa y R2 las verá vencidas (o
demasiado futuras) según el signo del desfase. Es exactamente el tipo de fallo
intermitente que no se reproduce en una máquina con la hora bien.

**Estado:** 🟢 **Resuelto — verificado en vivo el 2026-09-18.** La causa raíz era
la vigencia del token (`not_before: 2026-09-18T08:59:52Z`), no el alcance ni el
reloj (este último ya corregido a 24 s de desfase). Al 2026-09-18T12:30Z UTC esa
ventana ya había pasado, y una **sonda de ciclo completo** contra el bucket
`inces-lms-media` — `backend/scripts/probe-r2.mts`, con el **mismo `S3Client` que
producción** (`region:'auto'`, `forcePathStyle:true`, endpoint derivado de
`CLOUDFLARE_ACCOUNT_ID`) — devolvió:

```
HeadBucket 200 · PutObject 200 · GetObject 200 (contenido coincide)
ListObjectsV2 200 · DeleteObject 204   → bucket vacío tras la purga
```

**No hace falta emitir un token nuevo**: las credenciales actuales de
`backend/.env` autentican correctamente y el token sigue vigente hasta
`expires_on: 2026-11-30T16:00:00Z` (≈73 días). R2 queda desbloqueado para retomar
la integración de almacenamiento de **M5**. Nota: el efecto colateral de las
URL prefirmadas (§corolario) ya no aplica porque el reloj local está correcto.

---

## R-25 · Promover a mano SÍ funciona, pero la API responde 404: lee la inscripción por la clave equivocada

**Qué pasó.** El humo de la Fase 4 (`supabase/humo-inscripciones.mjs`) encontró que
el único camino que las 428 pruebas del backend no cubrían —el override manual de
promoción— **devuelve un 404 después de haber promovido de verdad**:

```
POST /api/v1/admin/secciones/:id/promover
→ 404 {"codigo":"NO_ENCONTRADO",
       "detalles":{"contexto":"leer la inscripción promovida"}}
```

El `UPDATE` que sube al estudiante de `WAITLISTED` a `ENROLLED` **se ejecuta**. Lo
que falla es la lectura que viene después, y el cliente nunca llega a ver el
resultado. Es un fallo parcial: el estado cambió y la respuesta dice que no.

**Por qué.** `promover_siguiente_de_cola` devuelve **el `student_id`**, no el `id`
de la fila. Medido sobre la base, no inferido:

```
=== promover_siguiente_de_cola(p_section_id uuid) -> uuid ===
   into v_id
   where id = v_id
   returning student_id into v_promovido;   ← devuelve el ESTUDIANTE
   return v_promovido;
```

El repositorio, en cambio, trata ese valor como la clave primaria de `enrollments`:

```ts
const id = typeof respuesta.data === 'string' ? respuesta.data : null;   // ← student_id
const fila = await this.cliente
  .from(TABLA_INSCRIPCIONES)
  .select(COLUMNAS_INSCRIPCION)
  .eq('id', id)      // ← busca por id de INSCRIPCIÓN
  .single();
```

Dos `uuid` distintos que nunca coinciden: `.single()` no encuentra fila, PostgREST
responde `PGRST116`, `traducirError` lo convierte en 404 y la promoción —que ya
ocurrió— se reporta como inexistente.

**Por qué no lo vieron las 428 pruebas.** El doble en memoria devuelve la
inscripción ya promovida, no un `student_id`: reproduce la *intención* de la RPC,
no su *contrato*. Es la misma clase de punto ciego que el humo de M3 documenta para
el mensaje del trigger — el doble copia a mano lo que la base hace de verdad, y
sólo la base puede desmentir la copia.

**Alcance.** Sólo afecta a la ruta de administración. La promoción automática
—`renunciar_cupo` llama a `promover_siguiente_de_cola` dentro de su transacción— no
pasa por el repositorio y **funciona bien**, que es por lo que el resto del humo
sale en verde. El botón «Promover Siguiente» del panel del administrador es lo
único roto, y lo está justo en el caso que lo justifica: ampliar el cupo y subir a
mano a quien espera.

**Arreglo aplicado (2026-09-18).** El repositorio ahora lee por la columna
correcta: `.eq('student_id', id).eq('section_id', seccionId)` sobre `enrollments`,
dentro de `InscripcionesSupabase.promover()` (`backend/src/infra/repos-supabase.ts`).
`seccionId` ya estaba en scope como parámetro del método; `(student_id, section_id)`
es único (regla anti-doble-inscripción), así que `.single()` sigue siendo seguro. No
se tocó la base ni ninguna migración: es un arreglo puro de la capa de repositorio. El
humo de la Fase 4 invirtió su bloque R-25 para certificar el 200 y
`promovida.estudianteId === idBeta`, y `npm run test` quedó en verde.

**Hallazgo secundario del mismo humo, ya documentado en el script:** `renunciar_cupo`
promueve al siguiente por su cuenta. «Promover Siguiente» **no** es el camino normal
para mover la cola tras una baja — cuando el administrador lo pulsa, la promoción ya
ocurrió y la RPC responde 200 con `promovida: null`. La interfaz no debe presentarlo
como si fuera necesario.

**Estado:** 🟢 Resuelta y verificada (2026-09-18). El repositorio lee por
`(student_id, section_id)`; `POST /api/v1/admin/secciones/:id/promover` devuelve 200
con la inscripción promovida. El humo de la Fase 4 certifica el arreglo en cada
corrida y la suite de 428 pruebas del backend está en verde.

---

## R-26 · Los POST sin cuerpo del Módulo 4 devolvían 500 (`FST_ERR_CTP_EMPTY_JSON_BODY`) por el encabezado `Content-Type`

**Encontrado y resuelto el 2026-09-18** al construir la Fase 3 (frontend de M4).
**No lo veía ninguna de las 428 pruebas del backend**, y la razón es estructural:
las rutas M4 de escritura sin cuerpo (`/renunciar`, `/aceptar`, `/promover`,
`/expirar`) se invocan desde el cliente Flutter, y **el backend no escribe un
cliente Flutter en su suite**.

### Qué pasa

Cuatro rutas de M4 (`renunciar_cupo`, `aceptar_cupo`, `promover_siguiente_de_cola`,
`expirar_ofertas`) son **POST sin cuerpo**: llevan la identidad en el JWT y la
sección en la ruta. El `ApiClient` de Flutter, sin embargo, declaraba
`Content-Type: application/json` en **todo** POST, cuerpo o no.

Fastify monta el parser JSON por content-type. Con `Content-Type: application/json`
y un cuerpo vacío, el parser de cuerpo de Fastify lanza
`FST_ERR_CTP_EMPTY_JSON_BODY` **antes** de llegar al handler, y la respuesta es un
**500** — no un 404 ni un 2xx. La operación nunca se ejecuta en la base.

```dart
// lib/core/network/api_client.dart (antes)
headers: {
  'Content-Type': 'application/json',   // ← siempre, aunque cuerpo == null
  if (token != null) 'Authorization': 'Bearer $token',
  ...
},
body: cuerpo == null ? null : jsonEncode(cuerpo),
```

El cliente dice «esto es JSON» y manda `null`; Fastify intenta parsear `null` como
JSON y estalla. El error es del **transporte**, no de la lógica de negocio: por eso
las 428 pruebas del backend (ninguna de las cuales hace un POST cuerpo-vacío con
ese encabezado desde un cliente real) salían en verde.

### Por qué no lo vieron las pruebas

El backend se ejercita con `supertest` / `fetch`, y esos clientes **no** añaden
`Content-Type: application/json` a un POST sin cuerpo. El único cliente que lo
hacía era `ApiClient` de Flutter, que **no** está en la suite del backend. Es la
misma clase de punto ciego que R-25: el doble copia la *intención* de la llamada,
no su *contrato de transporte*.

### Arreglo aplicado (2026-09-18)

`ApiClient.post`/`patch`/`put` declaran `Content-Type: application/json` **sólo si
hay cuerpo** (`if (cuerpo != null)`), en `lib/core/network/api_client.dart`
(Capa 1 de la Fase 3). Los POST sin cuerpo del M4 ya no llevan el encabezado y
Fastify no intenta parsear JSON vacío:

```dart
// lib/core/network/api_client.dart (ahora)
headers: {
  // Sólo se declara JSON si hay cuerpo. Un POST sin cuerpo con
  // `Content-Type: application/json` dispara en Fastify
  // `FST_ERR_CTP_EMPTY_JSON_BODY` (500), y es la trampa de las rutas
  // sin body del Módulo 4 (renunciar, aceptar, promover, expirar).
  if (cuerpo != null) 'Content-Type': 'application/json',
  if (token != null) 'Authorization': 'Bearer $token',
  ...?encabezadosExtra,
},
body: cuerpo == null ? null : jsonEncode(cuerpo),
```

No toca el backend ni la base: es un arreglo de la capa de transporte del cliente.
Las escrituras con cuerpo (`solicitar_inscripcion`, que sí lleva `seccionId` en el
body) siguen declarando JSON como antes.

### Verificación

`flutter analyze` limpio · `flutter test` **337/337 verde** (307 previas + 30
nuevas de M4; incl. `test/menu_alcanzable_test.dart`, que vigila el cableado R-22
del nuevo panel, y los tres archivos de prueba de widget/repository de M4) ·
`flutter build web --release` construye `build/web` sin advertencias. El camino se
certifica de punta a punta en la Fase 4 (humo real contra la API), no en la suite
del backend.

> **Nota para quien retoque `ApiClient`:** no «arregle» este arreglo añadiendo de
> nuevo el encabezado «para que quede uniforme». El 500 vuelve en cuanto el
> cliente anuncie JSON sobre un cuerpo vacío. Si una ruta nueva sin cuerpo necesita
> otro content-type, que lo pase por `encabezadosExtra`, no por el valor por
> defecto.

---

### Fase 3 (Frontend de M4) — entregada y verificada (2026-09-18)

La Fase 3 se construyó en tres capas, en el orden aprobado, respetando la
arquitectura hexagonal del proyecto y sin dumping masivo de código:

1. **Capa 1 · Datos.** `lib/models/inscripcion.dart`
   (`EstadoInscripcion`, `OcupacionSeccion`, `InscripcionDetallada`),
   `lib/core/gateways/inscripcion_gateway.dart` (interfaz),
   `lib/services/inscripcion_service.dart` (HTTP vía `ApiClient`),
   `lib/repositories/inscripcion_repository.dart` (`InscripcionesRepository` del
   estudiante y `AdminInscripcionesRepository` del admin, ambos en `Result<T>`).
   El contrato JSON es camelCase (`seccionId`, `ofertaVigente`, `posicionEnCola`,
   `estudianteId`, `ofertaVenceEn`) y se mapea desde el snake_case de la base en
   esta capa. **Incluye el arreglo de R-26** (`Content-Type` condicional).
2. **Capa 2 · UI del estudiante.** `lib/screens/aspirante_dashboard.dart` gana
   «Ofertas de cupos» (catálogo que **respeta `ofertaVigente`**: desactiva
   «Inscribirme» con «Asiento en asignación» aunque `cuposDisponibles > 0`, porque
   la doble venta se gestiona por la oferta, no por el contador) y «Mis
   inscripciones» (muestra `posicionEnCola` en `WAITLISTED`, y Renunciar / Aceptar
   cupo con cuenta atrás en vivo para `PENDING_BID`).
3. **Capa 3 · UI del administrador.** `lib/screens/admin/cpanel_inscripciones_panel.dart`
   con panel de ocupación (métricas + tabla), **Expirar ofertas**, **Reincorporar**
   (con aviso de exceder el cupo) y **Promover siguiente** por fila, documentado en
   la propia UI como override post-ampliación-de-cupo. Cableado en
   `admin_dashboard.dart` **R-22-seguro**: ítem `disponible: true` +
   `case 'Inscripciones y Cupos'` coincidente (la prueba `menu_alcanzable_test.dart`
   lo vigila).

**Validación:** `flutter analyze` → «No issues found!» · `flutter test` →
**337/337** (307 previas + 30 nuevas de M4) · `flutter build web --release` →
construye limpio.

#### Capa de pruebas de M4 (widget/repository) — añadida (2026-09-18)

La Fase 3 entregó el frontend, pero las pruebas de Flutter existentes sólo
alcanzaban el menú (R-22) y el humo de Node (R-25/26) no ejercitaba la lógica de
estado de los widgets. Esto dejaba abierta la brecha «construido ≠ probado» que el
propio proyecto documenta en R-20/R-26: **un menú alcanzable y una API que responde
no garantizan que el widget procese `ofertaVigente`, `posicionEnCola`, los estados
de botón ni las colas correctamente.** Se añadió la capa de pruebas en tres niveles,
con un doble inyectado (`FakeInscripcionGateway implements InscripcionGateway`) que
registra las llamadas para verificar el contrato de transporte, no sólo lo que pinta
la pantalla:

- **Capa 1 · Datos** — `test/inscripcion_repository_test.dart` (11 casos): los dos
  repositorios envuelven el gateway en `Result`; `promoverSiguiente` con cola vacía
  → `Failure` de `AppErrorType.validacion` (no de servidor); `expirarOfertas`
  idempotente (`[3, 0]` → primera 3, segunda 0).
- **Capa 2 · Estudiante** — `test/aspirante_inscripciones_test.dart` (13 casos):
  `PanelOfertas` gatilla `ofertaVigente` (botón «Asiento en asignación»
  deshabilitado aunque `cuposDisponibles > 0`; «Inscribirme» sólo si
  `!ofertaVigente && cuposDisponibles > 0`); `PanelMisInscripciones` cubre
  `WAITLISTED` (`Lugar N en la cola` / «En lista de espera»), `PENDING_BID`
  (Aceptar + Renunciar), `ENROLLED` («Tienes tu asiento confirmado en esta sección.»)
  y `DROPPED` (fila conservada como historial).
- **Capa 3 · Admin** — `test/cpanel_inscripciones_test.dart` (6 casos): métricas de
  ocupación, «Promover siguiente» (éxito y aviso de validación en cola vacía),
  «Expirar ofertas» y el diálogo «Reincorporar» (valida ids vacíos antes de llamar).

Doble compartido: `test/support/fake_inscripcion_gateway.dart`
(`ocupacionSeccionEjemplo`, `inscripcionDetalladaEjemplo`). Los paneles
`PanelOfertas`/`PanelMisInscripciones` se hicieron públicos (con `super.key`) para
poder inyectarles el repositorio fake.

> **Trampa de entorno resuelta al validar:** `flutter test` en este entorno
> devolvía `WebSocketException: Invalid WebSocket upgrade request` para **todos**
> los archivos (fallo de carga, no de aserción). Causa: las variables
> `http_proxy`/`https_proxy`/`HTTP_PROXY`/`HTTPS_PROXY` apuntan al proxy interno de
> WorkBuddy (`127.0.0.1:38232`), que intercepta el WebSocket de loopback que el
> runner abre a `flutter_tester`. **Solución:** correr `flutter test` con esas
> variables vacías (p. ej. un `.bat` que las borra antes de `flutter test`, ya
> limpiado). No es un defecto del código.

---

## Resumen

| ID | Contradicción | Resolución | Estado |
| --- | --- | --- | --- |
| R-01 | `sections` sin `program_id` | Se añadió la columna | ✅ Resuelta |
| R-02 | `is_active DEFAULT TRUE` vs Regla 1 | Nace en `false` | ✅ Resuelta |
| R-03 | Regla 1 decía "carreras", se aplicaba a todo | Acotada a `CARRERA` | ✅ Resuelta |
| R-04 | `ENUM` vs convención del proyecto | `text` + `check` | ✅ Resuelta |
| R-05 | Ruta fuera del prefijo con guardia | `/api/v1/admin/programas` | ✅ Resuelta (el documento debe actualizarse) |
| R-06 | Dos convenciones de período | `SA26-2` como lapso vigente; m2/m3 habilitados | ✅ **Resuelta (2026-09-15)** |
| R-07 | `curso_seleccionado` por nombre | Diferida a D14 | ⏳ Abierta, sin urgencia (0 filas) |
| R-08 | `sections` de Fase 0 era un stub | Rediseñada completa | ✅ Resuelta |
| R-09 | `cursos` vs `programs` (D12) | Vista de compatibilidad | ✅ Resuelta |
| R-10 | "Una transacción" que PostgREST no da | Dos funciones RPC | ✅ Resuelta |
| R-11 | El filtro `or` exige paréntesis | Los añade `supabase-js`; no se toca | ✅ Verificada |
| R-12 | `periodo_activo` podía divergir en silencio (refina R-06) | `academic_periods` + FK + guarda | ✅ Resuelta (la nomenclatura sigue pendiente) |
| R-13 | La colisión cruza `schedule_slots` y `teacher_duties` | Un trigger compartido + cerrojo | ✅ Resuelta |
| R-14 | RLS de `profiles` no deja ver el nombre del docente | Función estrecha `nombre_para_mostrar()` | ✅ Resuelta |
| R-15 | Una guardia sin período hace imprecisa la colisión | `teacher_duties.period_code` | ✅ Resuelta |
| R-16 | «Turno» y «bloque» podían contradecirse | `turno` generado desde `block` | ✅ Resuelta (frontera provisional) |
| R-17 | Las fechas del período no se conocen | Anulables; las carga el centro | ✅ Resuelta |
| R-18 | «Aula/zona»: una zona no es un aula | Una zona es una fila de `classrooms` | ✅ Resuelta |
| R-19 | «Período activo» significa dos cosas | `is_active` (abierto) vs `periodo_activo` (vigente) | ✅ Resuelta (se puede simplificar) |
| R-20 | Trigger `invoker` + función revocada: módulo inoperable | Envoltorios a `security definer` (migración 202609180002) | ✅ Resuelta y verificada |
| R-21 | El nombre del docente llega vacío al cuadrante: `nombre_para_mostrar()` devuelve NULL | La función está bien; **el canal de invitación ahora captura nombres/apellidos** y los pasa a `user_metadata` (migración 202609130002 + commit de R-21) | ✅ **Resuelta (2026-09-15)** |
| R-22 | El panel de M2 estaba construido y probado, pero su ítem del menú seguía deshabilitado: **inalcanzable** | Bandera obsoleta quitada + `test/menu_alcanzable_test.dart`, que lee el dashboard y exige que secciones y ramas coincidan | ✅ Resuelta y verificada (203/203) |
| R-23 | `enrollments_insert_own` dejaba a cualquier autenticado auto-inscribirse en `ENROLLED` y saltarse el motor de cupos; `DELETE`/`TRUNCATE` permitidos contradecían conservar `DROPPED` | Escrituras movidas a RPC `security definer` + `revoke` total de `anon` y `authenticated` (migración 202609190001, parte 6) | ✅ Resuelta y verificada en producción (212/212) |
| R-24 | Diagnostiqué el `AccessDenied` de R2 como «problema de alcance» **sin medirlo**: el reloj iba 12 h desviado (el SDK lo corregía en silencio) y el token tenía el `not_before` en el futuro | Causa raíz medida con un control (clave falsa → 401, clave real → 403) y con `verify` de la API de Cloudflare. El 2026-09-18 la ventana `not_before` (08:59:52Z) ya pasó y una sonda de ciclo completo contra `inces-lms-media` devolvió 200/200/200/200/204: **token vigente, sin reemitir** | 🟢 **Resuelta y verificada en vivo (2026-09-18)** |
| R-25 | `promover_siguiente` devuelve el `student_id`, pero el repositorio leía la inscripción con `.eq('id', …)`: la promoción **sí ocurría** y la API respondía **404** (medido en Fase 4) | Arreglo aplicado (2026-09-18): `InscripcionesSupabase.promover()` lee por `student_id` + `section_id` (no toca la base). Humo Fase 4 invirtió su bloque para certificar el 200 y `promovida.estudianteId === idBeta` | 🟢 **Resuelta y verificada (2026-09-18)** |
| R-26 | Los POST sin cuerpo del M4 anunciaban `Content-Type: application/json` y daban 500 (`FST_ERR_CTP_EMPTY_JSON_BODY`); ninguna de las 428 pruebas del backend lo veía porque no hay cliente Flutter en su suite | `ApiClient.post/patch/put` declara `Content-Type: application/json` **sólo si hay cuerpo** (Capa 1 de la Fase 3, `lib/core/network/api_client.dart`) | ✅ Resuelta y verificada (Fase 3 · 307/307 · build limpio) |
