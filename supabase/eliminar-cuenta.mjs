/**
 * Elimina (o desactiva) una cuenta de la base de datos real, con inventario
 * previo de lo que la referencia.
 *
 * Existe porque borrar un usuario **no es un `delete` y ya**: `auth.users` y
 * `public.profiles` viven en esquemas distintos, y `profiles.id` es a la vez
 * la clave primaria del perfil y el `auth.uid()` de todas las políticas RLS.
 * Si se borra una mitad y no la otra quedan cuentas fantasma: un `profiles`
 * sin usuario al que pertenece (nadie puede entrar, pero aparece en listados y
 * en los recuentos de "último admin"), o un `auth.users` sin perfil (puede
 * entrar y el `AuthGate` no sabe a dónde mandarlo).
 *
 * Además comprueba la invariante D8 antes de tocar nada: el trigger
 * `proteger_ultimo_admin` impide degradar o borrar al último admin activo. Si
 * esta cuenta fuera la última, el `delete` fallaría — y el mensaje de error de
 * Postgres no explicaría por qué. Aquí se avisa antes.
 *
 * **Modo por defecto: simulación.** Hay que pasar `--confirmar` para escribir.
 * Borrar una cuenta es irreversible desde aquí: no hay papelera.
 *
 * Uso:
 *   node supabase/eliminar-cuenta.mjs correo@dominio.com              # inventario
 *   node supabase/eliminar-cuenta.mjs correo@dominio.com --confirmar  # borra
 *   node supabase/eliminar-cuenta.mjs correo@dominio.com --desactivar --confirmar
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');

/**
 * Lee una variable de entorno o, si no está, la busca en `backend/.env`.
 * Mismo criterio que el resto de scripts: sin `dotenv`, una dependencia menos.
 */
function variable(nombre) {
  const delEntorno = (process.env[nombre] ?? '').trim();
  if (delEntorno.length > 0) return delEntorno;

  try {
    const contenido = readFileSync(join(RAIZ, 'backend', '.env'), 'utf8');
    for (const linea of contenido.split('\n')) {
      const limpia = linea.trim();
      if (limpia.length === 0 || limpia.startsWith('#')) continue;
      const corte = limpia.indexOf('=');
      if (corte < 0) continue;
      if (limpia.slice(0, corte).trim() === nombre) {
        return limpia.slice(corte + 1).trim();
      }
    }
  } catch {
    // Sin archivo: se decide abajo con el mensaje de error.
  }
  return '';
}

const email = (process.argv[2] ?? '').trim().toLowerCase();
const confirmar = process.argv.includes('--confirmar');
const desactivarEnLugar = process.argv.includes('--desactivar');

const url = variable('SUPABASE_URL').replace(/\/+$/, '');
const secreta = variable('SUPABASE_SERVICE_ROLE_KEY');
const token = variable('SUPABASE_ACCESS_TOKEN');

if (email.length === 0 || !email.includes('@')) {
  console.error('\n  Uso: node supabase/eliminar-cuenta.mjs correo@dominio.com [--confirmar] [--desactivar]\n');
  process.exit(1);
}
if (url.length === 0) {
  console.error('\n  Falta SUPABASE_URL (en backend/.env o en el entorno).\n');
  process.exit(1);
}
if (token.length === 0) {
  console.error(
    '\n  Falta SUPABASE_ACCESS_TOKEN.\n\n' +
      '  Hace falta porque el borrado consulta el esquema `auth`, al que la API\n' +
      '  REST no llega (sólo expone `public`). Es el token PERSONAL de Supabase\n' +
      '  (empieza por sbp_), no la clave del proyecto.\n',
  );
  process.exit(1);
}

const REF = url.replace('https://', '').split('.')[0];

/** Consulta SQL por la Management API: HTTPS/IPv4, sin depender de IPv6. */
async function sql(query) {
  const respuesta = await fetch(
    `https://api.supabase.com/v1/projects/${REF}/database/query`,
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
  return texto.length > 0 ? JSON.parse(texto) : null;
}

const escapar = (v) => v.replace(/'/g, "''");

console.log(`\n  Proyecto : ${url}`);
console.log(`  Cuenta   : ${email}`);
console.log(`  Modo     : ${confirmar ? (desactivarEnLugar ? 'DESACTIVAR' : 'BORRAR') : 'SIMULACIÓN (no escribe)'}\n`);

// ── 1. Inventario ────────────────────────────────────────────────────────────
const cuentas = await sql(
  `select id, email, email_confirmed_at, last_sign_in_at, created_at
   from auth.users where lower(email) = lower('${escapar(email)}')`,
);

if (cuentas.length === 0) {
  console.log('  No existe ninguna cuenta con ese correo en auth.users. Nada que hacer.\n');
  process.exit(0);
}
if (cuentas.length > 1) {
  console.error(
    `  Hay ${cuentas.length} cuentas con ese correo en auth.users. Es un estado\n` +
      '  anómalo (el correo debería ser único). No se borra nada: revísalo a mano.\n',
  );
  console.table(cuentas);
  process.exit(1);
}

const cuenta = cuentas[0];
console.log('  En auth.users:');
console.log(`    id                : ${cuenta.id}`);
console.log(`    correo confirmado : ${cuenta.email_confirmed_at ?? 'NO'}`);
console.log(`    último ingreso    : ${cuenta.last_sign_in_at ?? 'nunca'}`);
console.log(`    creada            : ${cuenta.created_at}`);

const perfiles = await sql(
  `select id, email, rol, active, nombres, apellidos, cedula
   from public.profiles where id = '${cuenta.id}'`,
);
const perfil = perfiles[0];
console.log('\n  En public.profiles:');
if (!perfil) {
  console.log('    (sin fila de perfil — cuenta huérfana en el otro sentido)\n');
} else {
  console.log(`    rol    : ${perfil.rol}`);
  console.log(`    active : ${perfil.active}`);
  console.log(`    nombre : ${perfil.nombres ?? '—'} ${perfil.apellidos ?? '—'}`);
  console.log(`    cédula : ${perfil.cedula ?? '—'}`);
}

// ── 2. Qué la referencia ─────────────────────────────────────────────────────
console.log('\n  Lo que referencia a esta cuenta:');

const fks = await sql(
  `select tc.table_name, kcu.column_name
   from information_schema.table_constraints tc
   join information_schema.key_column_usage kcu
     on tc.constraint_name = kcu.constraint_name
   join information_schema.constraint_column_usage ccu
     on tc.constraint_name = ccu.constraint_name
   where tc.constraint_type = 'FOREIGN KEY'
     and ccu.table_name = 'profiles'
     and tc.table_schema = 'public'`,
);

let referencias = 0;
for (const fk of fks) {
  const filas = await sql(
    `select count(*)::int as n from public.${fk.table_name}
     where ${fk.column_name} = '${cuenta.id}'`,
  );
  const n = filas[0]?.n ?? 0;
  if (n > 0) {
    referencias += n;
    console.log(`    ${fk.table_name}.${fk.column_name}: ${n} fila(s)  ← BLOQUEA el borrado`);
  }
}
if (referencias === 0) {
  console.log('    (nada la referencia: el borrado es limpio)');
}

// ── 3. La barrera D8 ─────────────────────────────────────────────────────────
const admins = await sql(
  `select email, active from public.profiles where rol = 'admin' order by email`,
);
const adminsActivos = admins.filter((a) => a.active);

console.log(`\n  Administradores: ${adminsActivos.length} activo(s) de ${admins.length}`);
for (const a of admins) {
  console.log(`    ${a.active ? '●' : '○'} ${a.email}`);
}

const esUltimoAdmin =
  perfil?.rol === 'admin' && perfil.active && adminsActivos.length <= 1;
if (esUltimoAdmin) {
  console.error(
    '\n  ALTO: es el último administrador activo.\n' +
      '  El trigger `proteger_ultimo_admin` (D8) va a rechazar la operación, y hace\n' +
      '  bien: el sistema quedaría sin nadie capaz de abrirlo. Promueve otro admin\n' +
      '  primero.\n',
  );
  process.exit(1);
}

// ── 4. Ejecutar ──────────────────────────────────────────────────────────────
if (!confirmar) {
  console.log(
    `\n  SIMULACIÓN. Para ${desactivarEnLugar ? 'desactivar' : 'borrar'} de verdad:\n` +
      `    node supabase/eliminar-cuenta.mjs ${email}${desactivarEnLugar ? ' --desactivar' : ''} --confirmar\n`,
  );
  process.exit(0);
}

if (referencias > 0 && !desactivarEnLugar) {
  console.error(
    '\n  Hay referencias a esta cuenta. Borrarla exigiría borrarlas antes, y eso\n' +
      '  puede destruir historial real (actas, asistencias, entregas).\n' +
      '  Usa --desactivar: la cuenta deja de poder entrar y conserva el historial.\n',
  );
  process.exit(1);
}

if (desactivarEnLugar) {
  await sql(
    `update public.profiles set active = false where id = '${cuenta.id}'`,
  );
  console.log('\n  Cuenta desactivada. No puede entrar, el historial queda intacto.\n');
  process.exit(0);
}

// El perfil primero: si se borrara el usuario y fallara el perfil, quedaría un
// `profiles` colgado. Al revés, lo peor que queda es un usuario sin perfil, que
// el script puede reconstruir después.
await sql(`delete from public.profiles where id = '${cuenta.id}'`);
await sql(`delete from auth.users where id = '${cuenta.id}'`);

const quedan = await sql(
  `select count(*)::int as n from auth.users where lower(email) = lower('${escapar(email)}')`,
);

console.log('\n  Resultado:');
console.log(`    perfiles restantes con ese id : ${(await sql(`select count(*)::int as n from public.profiles where id = '${cuenta.id}'`))[0].n}`);
console.log(`    usuarios restantes con ese correo: ${quedan[0].n}`);
console.log(
  quedan[0].n === 0
    ? '\n  Cuenta eliminada por completo.\n'
    : '\n  ATENCIÓN: todavía queda algo. Revísalo antes de dar el borrado por bueno.\n',
);
