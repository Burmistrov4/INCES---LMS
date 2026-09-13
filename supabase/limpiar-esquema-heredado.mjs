/**
 * Limpieza del esquema heredado del editor SQL.
 *
 * El proyecto de Supabase se usó antes para prototipar un diseño distinto
 * (`cedula_pasaporte`, `cohortes`, `inscripciones`, enums `actividad_type` /
 * `entrega_status`). Esas tablas quedaron huérfanas: ningún archivo del repo las
 * menciona, están vacías, no tienen triggers ni funciones, y la tabla
 * `aspirantes` del prototipo CHOCA con la que define la migración 0001.
 *
 * Se eliminan para que las migraciones puedan aplicarse desde cero. Nada de
 * valor se pierde: no hay una sola fila.
 *
 * Uso: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/limpiar-esquema-heredado.mjs
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
  const cuerpo = await respuesta.text();
  if (!respuesta.ok) {
    throw new Error(`HTTP ${respuesta.status}: ${cuerpo}`);
  }
  return cuerpo.length > 0 ? JSON.parse(cuerpo) : null;
}

const sentencias = [
  'drop table if exists public.asistencias cascade;',
  'drop table if exists public.inscripciones cascade;',
  'drop table if exists public.actividades cascade;',
  'drop table if exists public.entregas cascade;',
  'drop table if exists public.cohortes cascade;',
  'drop table if exists public.aspirantes cascade;',
  'drop table if exists public.profiles cascade;',
  'drop table if exists public.sections cascade;',
  'drop table if exists public.enrollments cascade;',
  'drop table if exists public.cursos cascade;',
  'drop type if exists public.actividad_type cascade;',
  'drop type if exists public.entrega_status cascade;',
  'drop type if exists public.user_role cascade;',
];

for (const sentencia of sentencias) {
  process.stdout.write(`  ${sentencia}\n`);
  await consultar(sentencia);
}

// Comprobación honesta: "sin error" no es lo mismo que "sin tablas".
const quedan = await consultar(
  "select coalesce(string_agg(tablename, ', ' order by tablename), '(ninguna)') as tablas " +
    "from pg_tables where schemaname = 'public';",
);
const enums = await consultar(
  "select coalesce(string_agg(t.typname, ', ' order by t.typname), '(ninguno)') as enums " +
    'from pg_type t join pg_namespace n on n.oid = t.typnamespace ' +
    "where n.nspname = 'public';",
);

console.log('\n  Tablas restantes en public :', quedan?.[0]?.tablas);
console.log('  Tipos restantes en public  :', enums?.[0]?.enums, '\n');
