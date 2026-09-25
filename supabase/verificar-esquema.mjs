/**
 * Verificación independiente del esquema en la nube.
 *
 * `apply-migrations.mjs` informa de que las sentencias no fallaron. Eso no es lo
 * mismo que comprobar que el esquema quedó bien: un `create table if not exists`
 * sobre una tabla preexistente con otro diseño también "no falla". Este script
 * interroga el catálogo y responde a las preguntas que importan:
 *
 *   1. ¿Están TODAS las tablas esperadas? (la lista es la constante `esperadas`
 *      de más abajo; el total NO se escribe aquí a propósito — decía «17» cuando
 *      ya eran 22, que es justo el tipo de cifra que envejece sola)
 *   2. ¿Coinciden las columnas de `aspirantes` con el modelo Dart?
 *   3. ¿RLS activo en todas?
 *   4. ¿Existen los triggers que sostienen las invariantes (D8)?
 *   5. ¿Los módulos del cPanel están sembrados?
 *   6. ¿Sigue en pie la vista de compatibilidad `cursos` (D12) y están las
 *      tablas del currículo (M2)?
 *   7. ¿Está el Módulo 3 desplegado — aulas, períodos, guardias, cuadrante,
 *      sus vistas y sus triggers anti-colisión?
 *   8. ¿Está el Módulo 4 desplegado — RPC `security definer`, escritura directa
 *      revocada, `max_capacity` nullable, semilla de bids y trigger
 *      anti-duplicado?
 *   9. ¿Está el Módulo 5 desplegado — tabla `files_metadata` con RLS y escritura
 *      directa revocada, sus 3 RPC `security definer` y la semilla de límites?
 *  10. ¿Está el catálogo de campos de la planilla (M4) y, sobre todo, está su
 *      guardia de escritura? El catálogo sin la guardia es una validación que se
 *      puede esquivar escribiendo la columna por PostgREST con el token propio.
 *
 * Uso: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs
 */
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
const ref = (process.env.SUPABASE_PROJECT_REF ?? 'twdppwnxlnmxkiejbrei').trim();

// Las migraciones que EXISTEN en el repositorio, leídas del disco en vez de
// escritas a mano. Fijar el número aquí es exactamente lo que produjo D11: el
// documento decía 5 migraciones mientras el repositorio tenía otras. Ahora la
// cifra se deriva del sistema de archivos, así que no puede quedar obsoleta.
// La versión es el nombre del archivo sin `.sql` (igual que en el libro mayor).
const migracionesEnDisco = readdirSync(
  join(dirname(fileURLToPath(import.meta.url)), 'migrations'),
)
  .filter((f) => f.endsWith('.sql'))
  .map((f) => f.replace(/\.sql$/, ''))
  .sort();

if (token.length === 0) {
  console.error('Falta SUPABASE_ACCESS_TOKEN.');
  process.exit(1);
}

async function consultar(query) {
  const respuesta = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    throw new Error(`HTTP ${respuesta.status}: ${texto}`);
  }
  return texto.length > 0 ? JSON.parse(texto) : [];
}

let fallos = 0;

function comprobar(etiqueta, condicion, detalle) {
  const marca = condicion ? 'OK  ' : 'FALLA';
  if (!condicion) fallos += 1;
  console.log(`  [${marca}] ${etiqueta}${detalle ? ` — ${detalle}` : ''}`);
}

console.log('\n  1. Tablas y RLS\n');
const tablas = await consultar(
  "select tablename, rowsecurity from pg_tables where schemaname = 'public' order by tablename;",
);
// `schema_migrations` no la crea una migración: la crea el libro mayor de
// `apply-migrations.mjs` (deuda D10). Es nuestra, no andamiaje heredado, y por
// eso entra en la lista de esperadas en vez de saltar como sobrante.
const esperadas = [
  'academic_periods',
  'aspirantes',
  'auth_logs',
  'classrooms',
  'config_audit_log',
  'enrollments',
  'files_metadata',
  // El catálogo de campos de la planilla (M4, `202609240001`). Es configuración,
  // no datos de ejemplo: por eso lo siembra una migración y no `sembrar-datos`.
  'inscripcion_campos',
  // Las tres del Aula Virtual (M6). Las sembró `202609220001`, que hasta el
  // 2026-09-22 estaba sin aplicar en la nube: mientras tanto este control las
  // veía como «heredadas» y fallaba. No son andamiaje: son el módulo.
  'm6_anuncios',
  'm6_entregas',
  'm6_tareas',
  'profiles',
  'program_subjects',
  'programs',
  'schedule_slots',
  'schema_migrations',
  'sections',
  'subjects',
  'system_modules',
  'system_settings',
  'teacher_duties',
  'teacher_invitations',
];
// `cursos` YA NO es una tabla: `202609160001` la convirtió en una vista de
// compatibilidad sobre `programs` (deuda D12). Se comprueba aparte, en el
// bloque 6, porque `pg_tables` **no ve vistas**. Si algún día reapareciera aquí
// como tabla, sería una regresión silenciosa de D12 — y el bloque 6 la caza.
// Las tres vistas del Módulo 3 se comprueban en el bloque 7, con su
// `security_invoker` incluido, que es lo que impide que se conviertan en un
// agujero por el que un estudiante vería el cuadrante de todo el centro.
const vistasEsperadas = [
  'cursos',
  'v_cuadrante_clases',
  'v_cuadrante_guardias',
  'v_ocupacion_secciones',
  'v_periodo_vigente',
];
const presentes = tablas.map((t) => t.tablename);

for (const tabla of esperadas) {
  const encontrada = tablas.find((t) => t.tablename === tabla);
  comprobar(
    `tabla public.${tabla}`,
    Boolean(encontrada),
    encontrada ? (encontrada.rowsecurity ? 'RLS activo' : 'RLS APAGADO') : 'ausente',
  );
  if (encontrada && !encontrada.rowsecurity) fallos += 1;
}
// Las vistas se excluyen del control de sobrantes a propósito: el bloque 6 las
// verifica con una aserción propia y un mensaje más preciso que «sobrante».
const sobrantes = presentes.filter(
  (t) => !esperadas.includes(t) && !vistasEsperadas.includes(t),
);
comprobar('sin tablas heredadas', sobrantes.length === 0, sobrantes.join(', ') || 'ninguna');

console.log('\n  2. Columnas de public.aspirantes (contrato con AspiranteModel)\n');
const columnas = await consultar(
  "select column_name, data_type, is_nullable from information_schema.columns " +
    "where table_schema = 'public' and table_name = 'aspirantes' order by ordinal_position;",
);
const requeridas = [
  'id',
  'user_id',
  'nombres',
  'apellidos',
  'cedula',
  'fecha_nac',
  'sexo',
  'telefono',
  'email',
  'direccion',
  'nivel_educativo',
  // D14 (`202609250001`): sustituye a `curso_seleccionado`, que guardaba el
  // NOMBRE del curso en texto libre y quedaba huérfano al renombrar el programa.
  'program_id',
  'mision_ribaras',
  'discapacidad',
  'requires_legal_tutor',
  // La planilla extendida (`202609240001`). Va en jsonb y no en columnas para que
  // añadir un campo del CFS no exija una migración. El contrato con
  // `AspiranteModel` siguen siendo las 15 columnas de arriba.
  'datos_planilla',
];
for (const columna of requeridas) {
  comprobar(`columna aspirantes.${columna}`, columnas.some((c) => c.column_name === columna));
}

// D14 — la comprobación INVERSA. Que `program_id` exista no basta: si alguien
// volviera a añadir `curso_seleccionado`, el dato duplicado regresaría y
// renombrar un programa volvería a romper las fichas, sin que ninguna aserción
// de arriba se quejara.
comprobar(
  'aspirantes.curso_seleccionado ya NO existe (D14)',
  !columnas.some((c) => c.column_name === 'curso_seleccionado'),
  columnas.some((c) => c.column_name === 'curso_seleccionado') ? 'sigue ahí' : 'eliminada',
);

// D14 — que sea una FK de verdad, no un uuid suelto. Sin esto, cambiar
// `references` por un `text` pasaría el control de columnas y nada volvería a
// impedir una referencia a un programa inventado.
const colPrograma = columnas.find((c) => c.column_name === 'program_id');
comprobar(
  'aspirantes.program_id es uuid',
  colPrograma?.data_type === 'uuid',
  String(colPrograma?.data_type),
);
comprobar(
  'aspirantes.program_id es NOT NULL',
  colPrograma?.is_nullable === 'NO',
  String(colPrograma?.is_nullable),
);

const fkPrograma = await consultar(
  "select pg_get_constraintdef(c.oid) as definicion " +
    "from pg_constraint c join pg_class t on t.oid = c.conrelid " +
    "join pg_namespace n on n.oid = t.relnamespace " +
    "where n.nspname = 'public' and t.relname = 'aspirantes' " +
    "and c.contype = 'f' and c.conname = 'aspirantes_program_id_fkey';",
);
comprobar(
  'FK aspirantes.program_id → programs(id) ON DELETE RESTRICT',
  fkPrograma.length === 1 &&
    /programs\(id\)/.test(fkPrograma[0].definicion) &&
    /ON DELETE RESTRICT/i.test(fkPrograma[0].definicion),
  fkPrograma[0]?.definicion ?? 'ausente',
);

console.log('\n  3. Funciones y triggers (invariantes)\n');
const funciones = await consultar(
  "select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
    "where n.nspname = 'public' and p.proname in " +
    "('is_admin', 'handle_new_user', 'link_pending_aspirante', 'proteger_modulo_critico', " +
    "'proteger_ultimo_admin', 'set_updated_at', 'apply_aspirante_auth_fields', " +
    "'turno_de_bloque', 'dia_legible', 'exigir_agenda_libre', 'nombre_para_mostrar', " +
    "'validar_planilla', 'validar_planilla_guardada', " +
    "'resolver_programa_inscripcion');",
);
const nombresFunciones = funciones.map((f) => f.proname);
for (const fn of [
  'is_admin',
  'handle_new_user',
  'link_pending_aspirante',
  'proteger_modulo_critico',
  'proteger_ultimo_admin',
  'set_updated_at',
  'turno_de_bloque',
  'dia_legible',
  'exigir_agenda_libre',
  'nombre_para_mostrar',
  // M4 (`202609240001`): valida la forma de `datos_planilla` contra el catálogo.
  'validar_planilla',
  // M4 (`202609240002`): el envoltorio que hace que la validación no se pueda
  // esquivar escribiendo la columna por PostgREST con el token propio.
  'validar_planilla_guardada',
  // D14 (`202609250001`): resuelve el valor de `curso_seleccionado` a un
  // `programs.id`, exigiendo que exista, esté activo y sea CURSO_LIBRE.
  'resolver_programa_inscripcion',
]) {
  comprobar(`función public.${fn}()`, nombresFunciones.includes(fn));
}

// El resolutor lo llama `handle_new_user()`, que corre como `supabase_auth_admin`:
// sin SECURITY DEFINER no podría leer `programs` y el alta fallaría entera. Es un
// invariante, no un detalle de estilo.
const definerResolver = await consultar(
  "select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
    "where n.nspname = 'public' and p.proname = 'resolver_programa_inscripcion';",
);
comprobar(
  'resolver_programa_inscripcion() es SECURITY DEFINER',
  definerResolver[0]?.prosecdef === true,
  String(definerResolver[0]?.prosecdef),
);

const triggers = await consultar(
  "select t.tgname, c.relname from pg_trigger t join pg_class c on c.oid = t.tgrelid " +
    "join pg_namespace n on n.oid = c.relnamespace " +
    "where n.nspname = 'public' and not t.tgisinternal;",
);
const nombresTriggers = triggers.map((t) => t.tgname);
for (const trigger of [
  'system_modules_proteger_critico',
  'proteger_ultimo_admin',
  'profiles_set_updated_at',
  'system_settings_periodo_registrado',
  'teacher_duties_exigir_agenda',
  'schedule_slots_exigir_agenda',
  // M4 (`202609240002`): la guardia de escritura de `aspirantes.datos_planilla`.
  // Sin ella la validación era evitable en una petición HTTP (medido en la nube).
  'aspirantes_validar_planilla',
]) {
  comprobar(`trigger ${trigger}`, nombresTriggers.includes(trigger));
}

console.log('\n  4. Semillas del cPanel\n');
const modulos = await consultar(
  'select clave, habilitado, orden from public.system_modules order by orden;',
);
comprobar('módulos sembrados', modulos.length === 10, `${modulos.length} filas`);
comprobar(
  'm0_cpanel arranca habilitado',
  modulos.some((m) => m.clave === 'm0_cpanel' && m.habilitado === true),
);
// La semilla ORIGINAL (202609120002) encendía sólo dos módulos, pero las
// migraciones posteriores encienden `m2_curriculo`, `m3_cuadrante`,
// `m4_inscripciones` (202609200002), `m5_archivos` (202609210002) y
// `m6_aula_virtual` (202609220003) a propósito: están construidos y verificados
// de extremo a extremo. Exigir «sólo dos» quedaría obsoleto y marcaría como fallo
// un estado correcto. Se fija el estado real: m0…m6 encendidos y m7…m8 apagados
// hasta que se construyan (cada uno lo encenderá su propia migración cuando el
// dueño lo decida).
//
// Ojo al leer el reparto, porque es fácil atribuirlo mal:
// `202609210001_mod5_archivos.sql` **no** enciende esta bandera —crea la tabla,
// las RPC y los parámetros, y lo dice de forma explícita en su cabecera—. Quien
// la enciende es `202609210002_mod5_habilitar_modulo.sql`. Es la misma división
// que hizo M4: `202609200001` construye y `202609200002` enciende. Una versión
// anterior de este comentario afirmaba lo contrario y contradecía a la aserción
// que tiene justo debajo.
const habilitados = modulos
  .filter((m) => m.habilitado)
  .map((m) => m.clave)
  .sort();
comprobar(
  'm0…m6 habilitados y m7…m8 apagados',
  JSON.stringify(habilitados) ===
    JSON.stringify([
      'm0_cpanel',
      'm1_onboarding',
      'm2_curriculo',
      'm3_cuadrante',
      'm4_inscripciones',
      'm5_archivos',
      'm6_aula_virtual',
    ]) &&
    // La lista de APAGADOS es explícita, no un `m[7-8]_` por expresión regular.
    // La regular daba por hecho que todo lo apagado era M7 o M8, y `m6_asistencia`
    // —reservado por la semilla para la asistencia, todavía sin construir— la
    // rompió en cuanto el control se corrió contra una nube al día.
    JSON.stringify(
      modulos
        .filter((m) => !m.habilitado)
        .map((m) => m.clave)
        .sort(),
    ) === JSON.stringify(['m6_asistencia', 'm7_calificaciones', 'm8_pasantias']),
  `habilitados: ${habilitados.join(', ')}`,
);
const ajustes = await consultar('select count(*)::int as n from public.system_settings;');
comprobar('parámetros sembrados', ajustes[0].n > 0, `${ajustes[0].n} filas`);
// Esta consulta ahora pasa por la **vista** `cursos` (D12), no por una tabla.
// Sirve de cruce: si la vista proyecta los 5 cursos migrados, es que la
// absorción a `programs` conservó los datos.
const cursos = await consultar('select count(*)::int as n from public.cursos;');
comprobar('cursos sembrados (vía la vista de D12)', cursos[0].n === 5, `${cursos[0].n} filas`);

console.log('\n  5. Libro mayor de migraciones (D10)\n');
const libro = await consultar(
  'select version, checksum from public.schema_migrations order by version;',
);
// El número de migraciones NO se escribe a mano: se compara el libro contra los
// archivos que hay en `supabase/migrations/`. Un conteo fijo se desincroniza en
// cuanto alguien añade una migración — que es la lección de D11.
const registradas = libro.map((m) => m.version).sort();
const sinRegistrar = migracionesEnDisco.filter((v) => !registradas.includes(v));
const sobran = registradas.filter((v) => !migracionesEnDisco.includes(v));
comprobar(
  'todas las migraciones del repositorio están registradas',
  sinRegistrar.length === 0,
  sinRegistrar.length > 0
    ? `SIN REGISTRAR: ${sinRegistrar.join(', ')}`
    : `${migracionesEnDisco.length} en disco, ${libro.length} registradas`,
);
comprobar(
  'el libro no tiene versiones que no existan en disco',
  sobran.length === 0,
  sobran.join(', ') || 'ninguna',
);
// Un checksum vacío o corto significaría que el libro se escribió a mano sin
// calcular la huella, y la detección de deriva quedaría desactivada en silencio.
comprobar(
  'todos los checksums tienen pinta de SHA-256',
  libro.every((m) => typeof m.checksum === 'string' && /^[0-9a-f]{64}$/.test(m.checksum)),
  libro.filter((m) => !/^[0-9a-f]{64}$/.test(m.checksum ?? '')).map((m) => m.version).join(', ') ||
    'ninguno sospechoso',
);

console.log('\n  6. M2: vista de compatibilidad y tablas del currículo\n');

// D12 — `cursos` debe ser una VISTA, no una tabla. `pg_tables` no ve vistas, así
// que se pregunta por `relkind = 'v'`. Si reapareciera como tabla, el bloque 1
// ya la habría marcado como sobrante; aquí se comprueba además que tiene
// `security_invoker` activo, que es lo que impide que la vista se convierta en
// un agujero de escalada: sin él corre con los privilegios de su dueño y `anon`
// vería cursos archivados que la RLS de `programs` esconde.
const relaciones = await consultar(
  'select c.relname, c.relkind, c.reloptions from pg_class c ' +
    "join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public';",
);
const relacionCursos = relaciones.find((r) => r.relname === 'cursos');
comprobar(
  'cursos existe y es una vista (relkind = v)',
  relacionCursos?.relkind === 'v',
  relacionCursos ? `relkind = ${relacionCursos.relkind}` : 'AUSENTE',
);
const opciones = (relacionCursos?.reloptions ?? []).join(',');
comprobar(
  'la vista usa security_invoker (sin ella anon vería lo que la RLS esconde)',
  opciones.includes('security_invoker=true') || opciones.includes('security_invoker=on'),
  opciones || 'SIN OPCIONES',
);

// M2 — no basta con que las tablas existan: se comprueban las columnas que el
// contrato de la API necesita, porque una tabla con el diseño equivocado
// también «existe».
const columnasDe = async (tabla) =>
  (
    await consultar(
      'select column_name from information_schema.columns ' +
        `where table_schema = 'public' and table_name = '${tabla}';`,
    )
  ).map((c) => c.column_name);

const colsPrograms = await columnasDe('programs');
comprobar(
  'programs tiene type e is_active (las dos que sostienen la Regla 1)',
  ['type', 'is_active'].every((c) => colsPrograms.includes(c)),
  colsPrograms.join(', '),
);
const colsPensum = await columnasDe('program_subjects');
comprobar(
  'program_subjects tiene program_id, subject_id y period_order',
  ['program_id', 'subject_id', 'period_order'].every((c) => colsPensum.includes(c)),
  colsPensum.join(', '),
);
const colsSections = await columnasDe('sections');
comprobar(
  'sections tiene program_id (la columna que añadió D13)',
  colsSections.includes('program_id'),
  colsSections.includes('program_id') ? 'presente' : 'AUSENTE',
);

// La Regla 2 vive en un trigger sobre la tabla, no sólo en una función suelta:
// si el trigger no está, la función existe pero no protege nada.
const triggerPensum = await consultar(
  'select t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid ' +
    "where c.relname = 'program_subjects' and not t.tgisinternal;",
);
comprobar(
  'trigger de la Regla 2 sobre program_subjects',
  triggerPensum.some((t) => t.tgname === 'program_subjects_proteger_en_uso'),
  triggerPensum.map((t) => t.tgname).join(', ') || 'ninguno',
);

// Las dos funciones del asistente (202609170001). Aquí no basta con que
// existan: lo que hay que comprobar es que **no** son un agujero.
//
// `prosecdef` es `true` cuando la función es SECURITY DEFINER, es decir, cuando
// corre con los privilegios de su dueño. Una función DEFINER que escribe en
// `programs` se saltaría la RLS por completo: cualquier autenticado podría
// crear programas sin ser admin. Se declaran `security invoker` a propósito, y
// esta comprobación es la que impide que un cambio futuro lo rompa en silencio.
const funcionesRpc = await consultar(
  'select p.proname, p.prosecdef, ' +
    "has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede, " +
    "has_function_privilege('authenticated', p.oid, 'EXECUTE') as autenticado_puede " +
    'from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
    "where n.nspname = 'public' " +
    "and p.proname in ('crear_programa_con_pensum', 'reemplazar_pensum') " +
    'order by p.proname;',
);
comprobar(
  'las dos funciones del asistente existen',
  funcionesRpc.length === 2,
  funcionesRpc.map((f) => f.proname).join(', ') || 'ninguna',
);
comprobar(
  'son security INVOKER (con DEFINER se saltarían la RLS)',
  funcionesRpc.length > 0 && funcionesRpc.every((f) => f.prosecdef === false),
  funcionesRpc.map((f) => `${f.proname}=${f.prosecdef ? 'DEFINER' : 'invoker'}`).join(', '),
);
comprobar(
  'anon NO puede ejecutar las funciones del asistente',
  funcionesRpc.length > 0 && funcionesRpc.every((f) => f.anon_puede === false),
  funcionesRpc.map((f) => `${f.proname}=${f.anon_puede ? 'PUEDE' : 'no'}`).join(', '),
);
comprobar(
  'authenticated sí puede ejecutarlas (la RLS decide si es admin)',
  funcionesRpc.length > 0 && funcionesRpc.every((f) => f.autenticado_puede === true),
  funcionesRpc.map((f) => `${f.proname}=${f.autenticado_puede ? 'sí' : 'NO'}`).join(', '),
);

console.log('\n  7. M3: aulas, períodos, guardias y cuadrante\n');

// Las cuatro tablas nuevas. No basta con que existan: se comprueban las
// columnas que el contrato de la API necesita, porque una tabla con el diseño
// equivocado también «existe».
const colsPeriodos = await columnasDe('academic_periods');
comprobar(
  'academic_periods tiene code, start_date, end_date e is_active',
  ['code', 'start_date', 'end_date', 'is_active'].every((c) => colsPeriodos.includes(c)),
  colsPeriodos.join(', '),
);
const colsAulas = await columnasDe('classrooms');
comprobar(
  'classrooms tiene name, capacity e is_workshop',
  ['name', 'capacity', 'is_workshop'].every((c) => colsAulas.includes(c)),
  colsAulas.join(', '),
);
const colsGuardias = await columnasDe('teacher_duties');
comprobar(
  'teacher_duties tiene teacher_id, classroom_id, period_code, day_of_week y block',
  ['teacher_id', 'classroom_id', 'period_code', 'day_of_week', 'block'].every((c) =>
    colsGuardias.includes(c),
  ),
  colsGuardias.join(', '),
);
const colsCuadrante = await columnasDe('schedule_slots');
comprobar(
  'schedule_slots tiene section_id, teacher_id, classroom_id, day_of_week y block',
  ['section_id', 'teacher_id', 'classroom_id', 'day_of_week', 'block'].every((c) =>
    colsCuadrante.includes(c),
  ),
  colsCuadrante.join(', '),
);

// R-16 — `turno` es derivado. Si dejara de ser una columna generada se podría
// insertar un turno que contradiga al bloque, y la agenda mostraría mentiras.
const generadas = await consultar(
  "select table_name, column_name from information_schema.columns " +
    "where table_schema = 'public' and is_generated = 'ALWAYS' " +
    "and table_name in ('teacher_duties', 'schedule_slots');",
);
for (const tabla of ['teacher_duties', 'schedule_slots']) {
  comprobar(
    `${tabla}.turno es una columna generada`,
    generadas.some((g) => g.table_name === tabla && g.column_name === 'turno'),
    generadas
      .filter((g) => g.table_name === tabla)
      .map((g) => g.column_name)
      .join(', ') || 'ninguna',
  );
}

// R-12 — `sections.period_code` dejó de ser texto libre: ahora apunta al
// catálogo de períodos. Es lo que convierte la divergencia silenciosa de R-06 en
// una violación ruidosa.
const fkPeriodo = await consultar(
  'select 1 as ok from information_schema.table_constraints tc ' +
    'join information_schema.constraint_column_usage ccu ' +
    'on ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema ' +
    "where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public' " +
    "and tc.table_name = 'sections' and ccu.table_name = 'academic_periods';",
);
comprobar(
  'sections.period_code apunta a academic_periods (R-12)',
  fkPeriodo.length === 1,
  fkPeriodo.length === 1 ? 'FK presente' : 'AUSENTE',
);

// El período activo de `system_settings` tiene que existir en el catálogo, que
// es justo lo que vigila el trigger `system_settings_periodo_registrado`.
const sembrado = await consultar(
  'select ap.code, ap.is_active from public.academic_periods ap ' +
    "join public.system_settings ss on ss.clave = 'periodo_activo' " +
    "where ap.code = (ss.valor #>> '{}');",
);
comprobar(
  'el período vigente está registrado en academic_periods',
  sembrado.length === 1,
  sembrado.length === 1 ? `${sembrado[0].code} (activo=${sembrado[0].is_active})` : 'SIN REGISTRAR',
);

// Las tres vistas de lectura, con su `security_invoker`. Sin él correrían con
// los privilegios del dueño y un estudiante vería el cuadrante de todo el centro.
for (const vista of ['v_cuadrante_clases', 'v_cuadrante_guardias', 'v_periodo_vigente']) {
  const rel = relaciones.find((r) => r.relname === vista);
  const opc = (rel?.reloptions ?? []).join(',');
  comprobar(
    `${vista} existe, es vista y usa security_invoker`,
    rel?.relkind === 'v' &&
      (opc.includes('security_invoker=true') || opc.includes('security_invoker=on')),
    rel ? `relkind = ${rel.relkind}, opciones = ${opc || 'NINGUNA'}` : 'AUSENTE',
  );
}

// LA COMPROBACIÓN QUE FALTABA (migración 202609180002)
// Los dos envoltorios de trigger DEBEN ser `security definer`. Con `security
// invoker` corren con los privilegios del llamante, que no tiene EXECUTE sobre
// `exigir_agenda_libre()`, y **toda alta de guardia o de clase fallaba con
// 42501**: el módulo quedaba inoperable y la protección anti-colisión ni se
// evaluaba. No lo detectó la batería de pruebas porque escribía como el dueño de
// las tablas, y el dueño se salta la comprobación de privilegios de función.
// Esta aserción es lo que impide que la regresión vuelva en silencio.
const envoltorios = await consultar(
  'select p.proname, p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
    "where n.nspname = 'public' " +
    "and p.proname in ('teacher_duties_exigir_agenda', 'schedule_slots_exigir_agenda') " +
    'order by p.proname;',
);
comprobar(
  'los dos envoltorios anti-colisión son security DEFINER',
  envoltorios.length === 2 && envoltorios.every((f) => f.prosecdef === true),
  envoltorios.map((f) => `${f.proname}=${f.prosecdef ? 'DEFINER' : 'invoker'}`).join(', ') ||
    'AUSENTES',
);

// Y la puerta sigue cerrada: el envoltorio es la única entrada. Conceder EXECUTE
// a `authenticated` convertiría la función en un oráculo de la agenda ajena
// (¿está ocupado el jueves a las 9?) y en un grifo del `pg_advisory_xact_lock`.
const delegada = await consultar(
  "select p.prosecdef, has_function_privilege('authenticated', p.oid, 'EXECUTE') as puede " +
    'from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
    "where n.nspname = 'public' and p.proname = 'exigir_agenda_libre';",
);
comprobar(
  'exigir_agenda_libre es DEFINER y authenticated NO puede llamarla',
  delegada.length === 1 && delegada[0].prosecdef === true && delegada[0].puede === false,
  delegada.length === 1
    ? `${delegada[0].prosecdef ? 'DEFINER' : 'invoker'}, authenticated_puede=${delegada[0].puede}`
    : 'AUSENTE',
);

// Superficie de `anon`: sólo el catálogo de períodos es público. Aulas, guardias
// y cuadrante no lo son.
const anonSuperficie = await consultar(
  "select c.relname, has_table_privilege('anon', c.oid, 'SELECT') as puede " +
    'from pg_class c join pg_namespace n on n.oid = c.relnamespace ' +
    "where n.nspname = 'public' and c.relkind = 'r' " +
    "and c.relname in ('academic_periods', 'classrooms', 'teacher_duties', 'schedule_slots') " +
    'order by c.relname;',
);
comprobar(
  'anon sólo alcanza academic_periods, no las aulas ni la agenda',
  anonSuperficie.length === 4 &&
    anonSuperficie.every((t) => (t.relname === 'academic_periods') === t.puede),
  anonSuperficie.map((t) => `${t.relname}=${t.puede ? 'PUEDE' : 'no'}`).join(', '),
);

console.log('\n  8. M4: inscripciones, cupos y la frontera de escritura\n');

// El fallback al cupo global (decisión 5) sólo puede dispararse si
// `max_capacity` es nullable. Con `not null default 0`, el 0 taparía el
// parámetro y la jerarquía de cupo sería decorativa.
const capNullable = await consultar(
  "select is_nullable from information_schema.columns " +
    "where table_schema = 'public' and table_name = 'sections' and column_name = 'max_capacity';",
);
comprobar(
  'sections.max_capacity es nullable (si no, el fallback al cupo global no dispara)',
  capNullable[0]?.is_nullable === 'YES',
  capNullable[0]?.is_nullable ?? 'AUSENTE',
);

const bidsSeed = await consultar(
  "select tipo, es_publico from public.system_settings where clave = 'habilitar_sistema_bids';",
);
comprobar(
  'habilitar_sistema_bids está sembrado (boolean, privado)',
  bidsSeed.length === 1 && bidsSeed[0].tipo === 'boolean' && bidsSeed[0].es_publico === false,
  bidsSeed.length === 1 ? `tipo=${bidsSeed[0].tipo}, publico=${bidsSeed[0].es_publico}` : 'AUSENTE',
);

// Las RPC de M4 son `security definer` por diseño: se saltan la RLS de
// `enrollments` y hacen su propia autorización con `auth.uid()`/`is_admin()`.
// Si alguna volviera a `invoker`, el motor de cupos quedaría ciego: la RLS le
// escondería las inscripciones de los demás y no podría contar la ocupación.
const rpcM4 = await consultar(
  'select p.proname, p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
    "where n.nspname = 'public' and p.proname in " +
    "('solicitar_inscripcion','aceptar_cupo','renunciar_cupo','promover_siguiente'," +
    "'expirar_ofertas_cupo','reincorporar_inscripcion') order by p.proname;",
);
comprobar(
  'existen las 6 RPC de la máquina de estados de M4',
  rpcM4.length === 6,
  rpcM4.map((f) => f.proname).join(', ') || 'ninguna',
);
comprobar(
  'las RPC de M4 son security DEFINER',
  rpcM4.length === 6 && rpcM4.every((f) => f.prosecdef === true),
  rpcM4.map((f) => `${f.proname}=${f.prosecdef ? 'DEFINER' : 'invoker'}`).join(', ') || 'AUSENTES',
);

// El helper del ajuste del 2026-09-18. Es lo que hace segura la regla «una
// oferta pendiente no reserva cupo»: como PENDING_BID ya no suma a
// `cupos_ocupados`, el contador por sí solo diría que hay hueco mientras una
// oferta está en el aire, y el mismo asiento se entregaría dos veces.
//
// SÍ necesita EXECUTE para `authenticated` aunque las RPC que lo usan sean
// `definer`: la vista `v_ocupacion_secciones` es `security_invoker`, así que la
// llamada dentro de su SELECT se evalúa con los privilegios de quien consulta.
const helperOferta = await consultar(
  'select p.prosecdef, ' +
    "has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_puede, " +
    "has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede " +
    'from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
    "where n.nspname = 'public' and p.proname = 'existe_oferta_vigente';",
);
comprobar(
  'existe_oferta_vigente existe y es security DEFINER',
  helperOferta.length === 1 && helperOferta[0].prosecdef === true,
  helperOferta.length === 1 ? `prosecdef=${helperOferta[0].prosecdef}` : 'AUSENTE',
);
comprobar(
  'authenticated SÍ ejecuta existe_oferta_vigente (la vista invoker lo necesita); anon NO',
  helperOferta[0]?.auth_puede === true && helperOferta[0]?.anon_puede === false,
  helperOferta[0]
    ? `authenticated=${helperOferta[0].auth_puede}, anon=${helperOferta[0].anon_puede}`
    : 'AUSENTE',
);

// LA aserción de la frontera: sin esto, `enrollments_insert_own` volvería a
// dejar al estudiante escribir su propia fila con ENROLLED y el motor sería
// decorativo. Es exactamente la regresión que esta fase cierra.
const escrituraEnroll = await consultar(
  "select has_table_privilege('authenticated','public.enrollments','INSERT') as i, " +
    "has_table_privilege('authenticated','public.enrollments','UPDATE') as u;",
);
comprobar(
  'authenticated NO tiene INSERT ni UPDATE directo sobre enrollments',
  escrituraEnroll.length === 1 && escrituraEnroll[0].i === false && escrituraEnroll[0].u === false,
  escrituraEnroll.length === 1 ? `INSERT=${escrituraEnroll[0].i}, UPDATE=${escrituraEnroll[0].u}` : 'AUSENTE',
);

const policiesEnroll = await consultar(
  "select policyname from pg_policies where schemaname = 'public' and tablename = 'enrollments' order by policyname;",
);
const nombresPoliticasEnroll = policiesEnroll.map((p) => p.policyname);
comprobar(
  'las políticas de escritura propias de enrollments ya no existen',
  !['enrollments_insert_own', 'enrollments_update_own', 'enrollments_delete_own'].some((p) =>
    nombresPoliticasEnroll.includes(p),
  ),
  nombresPoliticasEnroll.join(', ') || 'ninguna',
);

const triggerM4 = await consultar(
  "select t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid " +
    "where c.relname = 'enrollments' and not t.tgisinternal;",
);
comprobar(
  'existe el trigger anti-duplicado (estudiante, materia, lapso)',
  triggerM4.some((t) => t.tgname === 'enrollments_seccion_unica_por_materia'),
  triggerM4.map((t) => t.tgname).join(', ') || 'ninguno',
);

const vistaOcupacion = relaciones.find((r) => r.relname === 'v_ocupacion_secciones');
const opcionesOcupacion = (vistaOcupacion?.reloptions ?? []).join(',');
comprobar(
  'v_ocupacion_secciones existe, es vista y usa security_invoker',
  vistaOcupacion?.relkind === 'v' &&
    (opcionesOcupacion.includes('security_invoker=true') ||
      opcionesOcupacion.includes('security_invoker=on')),
  vistaOcupacion
    ? `relkind = ${vistaOcupacion.relkind}, opciones = ${opcionesOcupacion || 'NINGUNA'}`
    : 'AUSENTE',
);

// La columna que evita que el panel mienta: con PENDING_BID fuera del recuento,
// `cupos_disponibles` puede ser > 0 con una oferta en el aire. Sin
// `oferta_vigente`, la interfaz ofrecería un asiento que no puede dar.
const columnasOcupacion = await consultar(
  "select column_name from information_schema.columns " +
    "where table_schema = 'public' and table_name = 'v_ocupacion_secciones';",
);
const nombresOcupacion = columnasOcupacion.map((c) => c.column_name);
comprobar(
  'v_ocupacion_secciones declara oferta_vigente (si no, el panel ofrecería un asiento ya prometido)',
  nombresOcupacion.includes('oferta_vigente'),
  nombresOcupacion.join(', ') || 'AUSENTE',
);

console.log('\n  9. M5: archivos (R2), frontera de escritura y semilla de límites\n');

// La tabla de metadatos. No basta con que exista (el bloque 1 ya la comprueba y
// exige RLS): se verifican las columnas que sostienen el ciclo de vida, porque
// una tabla con el diseño equivocado también «existe».
const colsFiles = await columnasDe('files_metadata');
comprobar(
  'files_metadata tiene propietario_id, r2_key, estado, tamano_bytes y entity_type',
  ['propietario_id', 'r2_key', 'estado', 'tamano_bytes', 'entity_type'].every((c) =>
    colsFiles.includes(c),
  ),
  colsFiles.join(', '),
);

// La frontera (decisión 1): `authenticated` lee lo suyo pero NO escribe directo.
// Es la misma que M4: si el INSERT volviera a estar concedido, cualquiera podría
// registrarse como propietario de un objeto que no subió.
const permisosFiles = await consultar(
  "select has_table_privilege('authenticated','public.files_metadata','SELECT') as s, " +
    "has_table_privilege('authenticated','public.files_metadata','INSERT') as i, " +
    "has_table_privilege('authenticated','public.files_metadata','UPDATE') as u, " +
    "has_table_privilege('authenticated','public.files_metadata','DELETE') as d;",
);
comprobar(
  'authenticated lee files_metadata pero NO tiene INSERT/UPDATE/DELETE directos',
  permisosFiles.length === 1 &&
    permisosFiles[0].s === true &&
    permisosFiles[0].i === false &&
    permisosFiles[0].u === false &&
    permisosFiles[0].d === false,
  permisosFiles.length === 1
    ? `SELECT=${permisosFiles[0].s}, INSERT=${permisosFiles[0].i}, UPDATE=${permisosFiles[0].u}, DELETE=${permisosFiles[0].d}`
    : 'AUSENTE',
);

// Las 3 RPC de escritura: `security definer` (se saltan la RLS y autorizan solas
// con `auth.uid()`), ejecutables por `authenticated` y NO por `anon`.
const rpcM5 = await consultar(
  'select p.proname, p.prosecdef, ' +
    "has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede, " +
    "has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_puede " +
    'from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
    "where n.nspname = 'public' and p.proname in " +
    "('registrar_archivo_pendiente','confirmar_archivo','marcar_archivo_borrado') " +
    'order by p.proname;',
);
comprobar(
  'existen las 3 RPC de escritura de M5',
  rpcM5.length === 3,
  rpcM5.map((f) => f.proname).join(', ') || 'ninguna',
);
comprobar(
  'las 3 RPC de M5 son security DEFINER',
  rpcM5.length === 3 && rpcM5.every((f) => f.prosecdef === true),
  rpcM5.map((f) => `${f.proname}=${f.prosecdef ? 'DEFINER' : 'invoker'}`).join(', ') || 'AUSENTES',
);
comprobar(
  'anon NO puede ejecutar las RPC de M5; authenticated sí',
  rpcM5.length === 3 && rpcM5.every((f) => f.anon_puede === false && f.auth_puede === true),
  rpcM5.map((f) => `${f.proname}: anon=${f.anon_puede}, auth=${f.auth_puede}`).join(', ') || 'AUSENTES',
);

// La semilla de límites (decisión 2): valores por defecto que el administrador
// cambia desde el panel sin desplegar. Privados: son operativos, no del
// formulario público.
const limitesM5 = await consultar(
  "select clave, valor, tipo, es_publico from public.system_settings " +
    "where clave in ('m5_max_bytes','m5_max_archivos_por_entidad') order by clave;",
);
comprobar(
  'la semilla de límites de M5 está completa (10 MB y 10 archivos, number, privados)',
  limitesM5.length === 2 &&
    limitesM5.every((s) => s.tipo === 'number' && s.es_publico === false) &&
    limitesM5.find((s) => s.clave === 'm5_max_bytes')?.valor === 10485760 &&
    limitesM5.find((s) => s.clave === 'm5_max_archivos_por_entidad')?.valor === 10,
  limitesM5.map((s) => `${s.clave}=${JSON.stringify(s.valor)}`).join(', ') || 'AUSENTE',
);

console.log(
  `\n  ${fallos === 0 ? '✓ Esquema verificado sin fallos.' : `✗ ${fallos} comprobaciones fallidas.`}\n`,
);
process.exit(fallos === 0 ? 0 : 1);
