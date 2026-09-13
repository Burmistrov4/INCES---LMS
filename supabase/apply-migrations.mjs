/**
 * Aplica las migraciones a un proyecto Supabase en la nube **sin conexión
 * directa a PostgreSQL**.
 *
 * ¿Por qué existe esto si está `supabase db push`?
 *
 * Porque `db push` abre una conexión TCP al host directo de la base de datos, y
 * en los proyectos nuevos ese host resuelve **sólo a IPv6**
 * (`db.<ref>.supabase.co` → registro AAAA, sin registro A). En una red sin
 * salida IPv6 la conexión muere con `ENETUNREACH` antes de enviar una sola
 * consulta. Eso es habitual en conexiones residenciales, así que no es un caso
 * exótico: es el caso normal de este proyecto.
 *
 * Esta vía usa la API de administración de Supabase por HTTPS, que sí resuelve
 * por IPv4, y por tanto funciona donde `db push` no puede.
 *
 * Uso:
 *   SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --check
 *   SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
 *
 * El token se crea en https://supabase.com/dashboard/account/tokens
 * No es la contraseña de la base de datos ni la clave `service_role`.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACIONES = join(AQUI, 'migrations');
const REF_POR_DEFECTO = 'twdppwnxlnmxkiejbrei';

const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
const ref = (process.env.SUPABASE_PROJECT_REF ?? REF_POR_DEFECTO).trim();
const soloComprobar = process.argv.includes('--check');

if (token.length === 0) {
  console.error(
    '\n  Falta SUPABASE_ACCESS_TOKEN.\n\n' +
      '  Créalo en https://supabase.com/dashboard/account/tokens y pásalo así:\n' +
      '    SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs\n\n' +
      '  No es la contraseña de la base de datos ni la clave service_role.\n',
  );
  process.exit(1);
}

async function api(ruta, opciones = {}) {
  const respuesta = await fetch(`https://api.supabase.com/v1${ruta}`, {
    ...opciones,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...opciones.headers,
    },
  });

  const texto = await respuesta.text();
  let cuerpo = null;
  try {
    cuerpo = texto.length > 0 ? JSON.parse(texto) : null;
  } catch {
    cuerpo = texto;
  }

  if (!respuesta.ok) {
    const detalle =
      typeof cuerpo === 'object' && cuerpo !== null
        ? (cuerpo.message ?? cuerpo.error ?? texto)
        : texto;
    throw new Error(`HTTP ${respuesta.status} en ${ruta}: ${detalle}`);
  }

  return cuerpo;
}

async function consultar(query) {
  return api(`/projects/${ref}/database/query`, {
    method: 'POST',
    body: JSON.stringify({ query }),
  });
}

const archivos = readdirSync(MIGRACIONES)
  .filter((n) => n.endsWith('.sql'))
  .sort();

console.log(`\n  Proyecto : ${ref}`);
console.log(`  Migraciones: ${archivos.length}\n`);

// Verifica el proyecto antes de tocar nada: así un token sin permisos o un ref
// equivocado se detecta en el primer paso, no a mitad de una migración.
let proyecto;
try {
  proyecto = await api(`/projects/${ref}`);
} catch (error) {
  console.error(`  ✗ No se pudo leer el proyecto: ${error.message}\n`);
  process.exit(1);
}

console.log(`  Proyecto  : ${proyecto.name} (${proyecto.region})`);
console.log(`  Estado    : ${proyecto.status}\n`);

if (soloComprobar) {
  for (const archivo of archivos) {
    console.log(`  · ${archivo}`);
  }
  console.log('\n  Modo --check: no se aplicó nada.\n');
  process.exit(0);
}

for (const archivo of archivos) {
  const sql = readFileSync(join(MIGRACIONES, archivo), 'utf8');
  process.stdout.write(`  → ${archivo} ... `);

  try {
    await consultar(sql);
    console.log('aplicada');
  } catch (error) {
    console.log('FALLÓ');
    console.error(`\n  ${error.message}\n`);
    process.exit(1);
  }
}

// Comprobación real de que las tablas quedaron donde deben: aplicar sin error
// no es lo mismo que haber aplicado.
try {
  const filas = await consultar(
    'select count(*)::int as modulos from public.system_modules;',
  );
  const modulos = Array.isArray(filas) ? filas[0]?.modulos : undefined;
  console.log(`\n  ✓ Verificado: ${modulos} módulos en system_modules.`);

  const tablas = await consultar(
    "select count(*)::int as n from information_schema.tables " +
      "where table_schema = 'public' and table_name in " +
      "('teacher_invitations', 'auth_logs');",
  );
  const nTablas = Array.isArray(tablas) ? tablas[0]?.n : undefined;
  if (nTablas !== 2) {
    throw new Error(
      `se esperaban 2 tablas nuevas (teacher_invitations, auth_logs) pero hay ${nTablas}.`,
    );
  }
  console.log('  ✓ Verificado: teacher_invitations y auth_logs existen.\n');
} catch (error) {
  console.error(
    `\n  ✗ Las migraciones se aplicaron pero la verificación falló: ${error.message}\n`,
  );
  process.exit(1);
}
