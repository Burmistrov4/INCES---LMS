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

## R-21 · El nombre del docente llega vacío al cuadrante: `nombre_para_mostrar()` devuelve NULL

**Encontrado el 2026-09-15** por `supabase/humo-cuadrante.mjs`, el humo real de
M3. **No lo podía ver ninguna prueba con dobles**, y ninguna de las 333 del
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
| R-12 | `periodo_activo` podía divergir en silencio (refina R-06) | `academic_periods` + FK + guarda | ✅ Resuelta (la nomenclatura sigue pendiente) |
| R-13 | La colisión cruza `schedule_slots` y `teacher_duties` | Un trigger compartido + cerrojo | ✅ Resuelta |
| R-14 | RLS de `profiles` no deja ver el nombre del docente | Función estrecha `nombre_para_mostrar()` | ✅ Resuelta |
| R-15 | Una guardia sin período hace imprecisa la colisión | `teacher_duties.period_code` | ✅ Resuelta |
| R-16 | «Turno» y «bloque» podían contradecirse | `turno` generado desde `block` | ✅ Resuelta (frontera provisional) |
| R-17 | Las fechas del período no se conocen | Anulables; las carga el centro | ✅ Resuelta |
| R-18 | «Aula/zona»: una zona no es un aula | Una zona es una fila de `classrooms` | ✅ Resuelta |
| R-19 | «Período activo» significa dos cosas | `is_active` (abierto) vs `periodo_activo` (vigente) | ✅ Resuelta (se puede simplificar) |
| R-20 | Trigger `invoker` + función revocada: módulo inoperable | Envoltorios a `security definer` (migración 202609180002) | ✅ Resuelta y verificada |
| R-21 | El nombre del docente llega vacío al cuadrante: `nombre_para_mostrar()` devuelve NULL | La función está bien; **el canal de invitación nunca captura los nombres** | 🔴 **DECISIÓN PENDIENTE** (alcance de M1) |
