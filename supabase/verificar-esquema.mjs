/**
 * Verificación independiente del esquema en la nube.
 *
 * `apply-migrations.mjs` informa de que las sentencias no fallaron. Eso no es lo
 * mismo que comprobar que el esquema quedó bien: un `create table if not exists`
 * sobre una tabla preexistente con otro diseño también "no falla". Este script
 * interroga el catálogo y responde a las preguntas que importan:
 *
 *   1. ¿Están las 13 tablas esperadas?
 *   2. ¿Coinciden las columnas de `aspirantes` con el modelo Dart?
 *   3. ¿RLS activo en todas?
 *   4. ¿Existen los triggers que sostienen las invariantes (D8)?
 *   5. ¿Los módulos del cPanel están sembrados?
 *   6. ¿Sigue en pie la vista de compatibilidad `cursos` (D12) y están las
 *      tablas del currículo (M2)?
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
  'aspirantes',
  'auth_logs',
  'config_audit_log',
  'enrollments',
  'profiles',
  'program_subjects',
  'programs',
  'schema_migrations',
  'sections',
  'subjects',
  'system_modules',
  'system_settings',
  'teacher_invitations',
];
// `cursos` YA NO es una tabla: `202609160001` la convirtió en una vista de
// compatibilidad sobre `programs` (deuda D12). Se comprueba aparte, en el
// bloque 6, porque `pg_tables` **no ve vistas**. Si algún día reapareciera aquí
// como tabla, sería una regresión silenciosa de D12 — y el bloque 6 la caza.
const vistasEsperadas = ['cursos'];
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
  "select column_name, data_type from information_schema.columns " +
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
  'curso_seleccionado',
  'mision_ribaras',
  'discapacidad',
  'requires_legal_tutor',
];
for (const columna of requeridas) {
  comprobar(`columna aspirantes.${columna}`, columnas.some((c) => c.column_name === columna));
}

console.log('\n  3. Funciones y triggers (invariantes)\n');
const funciones = await consultar(
  "select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
    "where n.nspname = 'public' and p.proname in " +
    "('is_admin', 'handle_new_user', 'link_pending_aspirante', 'proteger_modulo_critico', " +
    "'proteger_ultimo_admin', 'set_updated_at', 'apply_aspirante_auth_fields');",
);
const nombresFunciones = funciones.map((f) => f.proname);
for (const fn of [
  'is_admin',
  'handle_new_user',
  'link_pending_aspirante',
  'proteger_modulo_critico',
  'proteger_ultimo_admin',
  'set_updated_at',
]) {
  comprobar(`función public.${fn}()`, nombresFunciones.includes(fn));
}

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
]) {
  comprobar(`trigger ${trigger}`, nombresTriggers.includes(trigger));
}

console.log('\n  4. Semillas del cPanel\n');
const modulos = await consultar(
  'select clave, habilitado, orden from public.system_modules order by orden;',
);
comprobar('módulos sembrados', modulos.length === 9, `${modulos.length} filas`);
comprobar(
  'm0_cpanel arranca habilitado',
  modulos.some((m) => m.clave === 'm0_cpanel' && m.habilitado === true),
);
// La semilla enciende exactamente dos: el panel y el onboarding. El resto de
// módulos nace apagado y se enciende desde el cPanel.
comprobar(
  'sólo m0_cpanel y m1_onboarding habilitados',
  modulos.filter((m) => m.habilitado).length === 2 &&
    modulos
      .filter((m) => m.habilitado)
      .every((m) => ['m0_cpanel', 'm1_onboarding'].includes(m.clave)),
  modulos
    .filter((m) => m.habilitado)
    .map((m) => m.clave)
    .join(', '),
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

console.log(
  `\n  ${fallos === 0 ? '✓ Esquema verificado sin fallos.' : `✗ ${fallos} comprobaciones fallidas.`}\n`,
);
process.exit(fallos === 0 ? 0 : 1);
