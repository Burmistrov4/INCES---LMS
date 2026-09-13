/**
 * Verificación independiente del esquema en la nube.
 *
 * `apply-migrations.mjs` informa de que las sentencias no fallaron. Eso no es lo
 * mismo que comprobar que el esquema quedó bien: un `create table if not exists`
 * sobre una tabla preexistente con otro diseño también "no falla". Este script
 * interroga el catálogo y responde a las preguntas que importan:
 *
 *   1. ¿Están las 12 tablas esperadas?
 *   2. ¿Coinciden las columnas de `aspirantes` con el modelo Dart?
 *   3. ¿RLS activo en todas?
 *   4. ¿Existen los triggers que sostienen las invariantes (D8)?
 *   5. ¿Los módulos del cPanel están sembrados?
 *
 * Uso: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs
 */
const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
const ref = (process.env.SUPABASE_PROJECT_REF ?? 'twdppwnxlnmxkiejbrei').trim();

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
const esperadas = [
  'aspirantes',
  'auth_logs',
  'config_audit_log',
  'cursos',
  'enrollments',
  'profiles',
  'sections',
  'system_modules',
  'system_settings',
  'teacher_invitations',
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
const sobrantes = presentes.filter((t) => !esperadas.includes(t));
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
const cursos = await consultar('select count(*)::int as n from public.cursos;');
comprobar('cursos sembrados', cursos[0].n === 5, `${cursos[0].n} filas`);

console.log(
  `\n  ${fallos === 0 ? '✓ Esquema verificado sin fallos.' : `✗ ${fallos} comprobaciones fallidas.`}\n`,
);
process.exit(fallos === 0 ? 0 : 1);
