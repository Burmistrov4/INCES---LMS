/**
 * Aplica las migraciones a un proyecto Supabase en la nube **sin conexión
 * directa a PostgreSQL**, con control de estado.
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
 * CONTROL DE ESTADO (deuda D10)
 * -----------------------------
 * Una versión anterior de este script reaplicaba **todas** las migraciones en
 * cada ejecución y se detenía al primer error. Como 4 de los 5 archivos tienen
 * `create policy` / `create trigger` sin guarda, reejecutar sobre una base ya
 * migrada podía fallar a medio camino. Ahora hay un libro mayor:
 *
 *   public.schema_migrations (version, checksum, applied_at)
 *
 * * Sólo se ejecutan los archivos **ausentes** del libro.
 * * El SHA-256 del archivo se guarda al aplicarlo. Si un archivo ya aplicado
 *   cambia, se detecta **deriva** y el script se niega a continuar: significa
 *   que alguien editó una migración que ya corrió, y eso hay que mirarlo a mano.
 * * La fila del libro se inserta **en el mismo lote** que la migración, así que
 *   o se aplican las dos cosas o ninguna. No hay estado a medias.
 *
 * Uso:
 *   SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --check
 *   SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
 *   SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs --adoptar
 *
 * `--adoptar` registra los archivos como aplicados **sin ejecutarlos**. Es para
 * bases que ya tienen el esquema pero no tienen libro mayor (el caso de este
 * proyecto: las 5 migraciones corrieron antes de que el libro existiera).
 * Confírmalo antes con `node supabase/verificar-esquema.mjs`.
 *
 * El token se crea en https://supabase.com/dashboard/account/tokens
 * No es la contraseña de la base de datos ni la clave `service_role`.
 */
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACIONES = join(AQUI, 'migrations');
const REF_POR_DEFECTO = 'twdppwnxlnmxkiejbrei';

const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
const ref = (process.env.SUPABASE_PROJECT_REF ?? REF_POR_DEFECTO).trim();
const soloComprobar = process.argv.includes('--check');
const adoptar = process.argv.includes('--adoptar');

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

/** Escapa una cadena para incrustarla en SQL (versiones y checksums son ASCII). */
const literal = (valor) => `'${String(valor).replace(/'/g, "''")}'`;

const DDL_LIBRO = `
create table if not exists public.schema_migrations (
  version    text        primary key,
  checksum   text        not null,
  applied_at timestamptz not null default now()
);
comment on table public.schema_migrations is
  'Libro mayor de migraciones: qué version se aplico y con que huella.';
alter table public.schema_migrations enable row level security;
revoke all on public.schema_migrations from anon, authenticated;
`;

const archivos = readdirSync(MIGRACIONES)
  .filter((n) => n.endsWith('.sql'))
  .sort()
  .map((nombre) => {
    const sql = readFileSync(join(MIGRACIONES, nombre), 'utf8');
    return {
      version: nombre.replace(/\.sql$/, ''),
      nombre,
      sql,
      checksum: createHash('sha256').update(sql, 'utf8').digest('hex'),
    };
  });

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

/** Lee el libro mayor. Devuelve null si aún no existe. */
async function leerLibro() {
  try {
    const filas = await consultar(
      'select version, checksum from public.schema_migrations;',
    );
    return new Map((filas ?? []).map((f) => [f.version, f.checksum]));
  } catch {
    return null;
  }
}

const libro = await leerLibro();

/** Estado de cada archivo frente al libro mayor. */
function diagnosticar(libroActual) {
  return archivos.map((a) => {
    if (libroActual === null) return { ...a, estado: 'sin-libro' };
    if (!libroActual.has(a.version)) return { ...a, estado: 'pendiente' };
    return {
      ...a,
      estado: libroActual.get(a.version) === a.checksum ? 'aplicada' : 'deriva',
    };
  });
}

if (libro === null) {
  console.log('  Sin libro mayor todavía (public.schema_migrations no existe).');
  console.log('  Se creará al aplicar. Todas las migraciones figuran como pendientes.\n');
}

const diagnostico = diagnosticar(libro);

if (soloComprobar) {
  const etiquetas = {
    aplicada: 'aplicada ',
    pendiente: 'PENDIENTE',
    deriva: 'DERIVA ⚠ ',
    'sin-libro': 'sin libro',
  };
  for (const a of diagnostico) {
    console.log(`  ${etiquetas[a.estado]}  ${a.nombre}`);
  }
  const pendientes = diagnostico.filter((a) => a.estado === 'pendiente').length;
  const derivas = diagnostico.filter((a) => a.estado === 'deriva').length;
  const sinLibro = diagnostico.filter((a) => a.estado === 'sin-libro').length;
  if (sinLibro > 0) {
    console.log(
      `\n  ${sinLibro} archivo(s) sin libro mayor. Si el esquema ya está aplicado,\n` +
        '  confírmalo con verificar-esquema.mjs y luego usa --adoptar.',
    );
  }
  console.log(`\n  ${pendientes} pendiente(s), ${derivas} con deriva.`);
  console.log('  Modo --check: no se aplicó nada.\n');
  process.exit(derivas > 0 ? 1 : 0);
}

if (adoptar) {
  console.log('  Modo --adoptar: se registran como aplicadas SIN ejecutarlas.\n');
}

try {
  await consultar(DDL_LIBRO);
} catch (error) {
  console.error(`  ✗ No se pudo preparar el libro mayor: ${error.message}\n`);
  process.exit(1);
}

// La deriva se comprueba antes de escribir nada: si una migración ya aplicada
// cambió, aplicar las siguientes sobre un esquema que no es el que se cree es
// peor que parar.
const derivas = diagnostico.filter((a) => a.estado === 'deriva');
if (derivas.length > 0 && !adoptar) {
  console.error('  ✗ DERIVA DETECTADA — el script no toca la base.\n');
  for (const a of derivas) {
    console.error(`      ${a.nombre}`);
    console.error(`        registrada: ${libro.get(a.version)}`);
    console.error(`        en disco  : ${a.checksum}`);
  }
  console.error(
    '\n  Una migración ya aplicada cambió de contenido. Opciones:\n' +
      '    · Si el cambio es cosmético, revierte el archivo.\n' +
      '    · Si el cambio es real, crea una migración NUEVA con el arreglo;\n' +
      '      nunca edites una que ya corrió.\n' +
      '    · Para aceptar el nuevo contenido sin ejecutarlo: --adoptar\n',
  );
  process.exit(1);
}

let aplicadas = 0;
let adoptadas = 0;

for (const a of diagnostico) {
  if (a.estado === 'aplicada') {
    console.log(`  · ${a.nombre} — ya aplicada, se omite`);
    continue;
  }

  process.stdout.write(`  → ${a.nombre} ... `);

  // El registro viaja en el MISMO lote que la migración: o quedan las dos cosas
  // o ninguna. Sin esto, una caída entre ambos pasos dejaría la migración
  // aplicada y sin registrar, y la siguiente ejecución la repetiría.
  const registro =
    `\ninsert into public.schema_migrations (version, checksum) ` +
    `values (${literal(a.version)}, ${literal(a.checksum)}) ` +
    `on conflict (version) do update set checksum = excluded.checksum;\n`;

  try {
    if (adoptar) {
      await consultar(registro);
      adoptadas += 1;
      console.log('adoptada (no ejecutada)');
    } else {
      await consultar(a.sql + registro);
      aplicadas += 1;
      console.log('aplicada');
    }
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

const final = await leerLibro();
console.log(
  `  Libro mayor: ${final?.size ?? 0} versión(es) registrada(s) ` +
    `(${aplicadas} aplicada(s), ${adoptadas} adoptada(s) en esta ejecución).\n`,
);
