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
import { spawnSync } from 'node:child_process';
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
// Se le pregunta a `pg_constraint`, **no** a `information_schema`. El motivo
// importa: `information_schema` sólo muestra los objetos sobre los que el rol
// actual tiene privilegios, y el esquema `auth` pertenece a
// `supabase_auth_admin`. Una consulta a `information_schema` por las claves
// ajenas que apuntan a `auth.users` devuelve **cero filas**, y un cero se lee
// igual que "no hay nada". Medido el 2026-09-19: así se escapaban cuatro
// claves, una de ellas `enrollments.student_id` con CASCADE — es decir, borrar
// una cuenta de estudiante habría destruido sus matrículas en silencio, sin que
// el guard de §4 se disparara.
console.log('\n  Lo que referencia a esta cuenta:');

const fks = await sql(
  `select cl.relname as tabla,
          att.attname as columna,
          fnsp.nspname || '.' || fcl.relname as destino,
          case con.confdeltype
            when 'c' then 'CASCADE' when 'n' then 'SET NULL'
            when 'r' then 'RESTRICT' when 'd' then 'SET DEFAULT'
            else 'NO ACTION' end as al_borrar
   from pg_constraint con
   join pg_class cl       on cl.oid = con.conrelid
   join pg_namespace nsp  on nsp.oid = cl.relnamespace
   join pg_class fcl      on fcl.oid = con.confrelid
   join pg_namespace fnsp on fnsp.oid = fcl.relnamespace
   join pg_attribute att  on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
   where con.contype = 'f'
     and nsp.nspname = 'public'
     and (   (fnsp.nspname = 'public' and fcl.relname = 'profiles')
          or (fnsp.nspname = 'auth'   and fcl.relname = 'users'))
     and not (cl.relname = 'profiles' and att.attname = 'id')
   order by destino, tabla, columna`,
);

// `files_metadata` no bloquea: sus filas se borran a propósito (§4b), pero los
// objetos de R2 se borran antes.
const GESTIONADA = 'files_metadata';

let bloquean = 0;
let pierdenEnlace = 0;
let gestionadas = 0;
const bloqueantes = [];

for (const fk of fks) {
  const filas = await sql(
    `select count(*)::int as n from public.${fk.tabla}
     where ${fk.columna} = '${cuenta.id}'`,
  );
  const n = filas[0]?.n ?? 0;
  if (n === 0) continue;

  const etiqueta = `${fk.tabla}.${fk.columna}`.padEnd(34);
  const via = (fk.destino === 'auth.users' ? 'auth.users' : 'profiles').padEnd(11);

  if (fk.tabla === GESTIONADA) {
    gestionadas += n;
    console.log(`    ${etiqueta} ${via} ${fk.al_borrar.padEnd(9)} ${n} fila(s)  (se borran a propósito, §4b)`);
  } else if (fk.al_borrar === 'CASCADE') {
    bloquean += n;
    bloqueantes.push(fk);
    console.log(`    ${etiqueta} ${via} ${fk.al_borrar.padEnd(9)} ${n} fila(s)  ← BLOQUEA: las destruiría`);
  } else if (fk.al_borrar === 'RESTRICT' || fk.al_borrar === 'NO ACTION') {
    bloquean += n;
    bloqueantes.push(fk);
    console.log(`    ${etiqueta} ${via} ${fk.al_borrar.padEnd(9)} ${n} fila(s)  ← BLOQUEA: el borrado fallaría`);
  } else {
    pierdenEnlace += n;
    console.log(`    ${etiqueta} ${via} ${fk.al_borrar.padEnd(9)} ${n} fila(s)  (sobrevive, pierde el dueño)`);
  }
}

const referencias = bloquean;

if (bloquean === 0 && pierdenEnlace === 0 && gestionadas === 0) {
  console.log('    (nada la referencia: el borrado es limpio)');
} else if (bloquean === 0) {
  console.log('    (nada bloquea el borrado)');
}

// `auth_logs.user_id` apunta al usuario **sin clave ajena** (por convención), así
// que ninguna consulta de constraints lo va a encontrar. Se dice explícitamente
// para que su ausencia en la lista de arriba no se confunda con "no existe".
const logs = await sql(
  `select count(*)::int as n from public.auth_logs where user_id = '${cuenta.id}'`,
);
if ((logs[0]?.n ?? 0) > 0) {
  console.log(
    `    auth_logs.user_id                  (sin clave ajena)  ${logs[0].n} fila(s)  ` +
      '(sobrevive: es un registro de auditoría)',
  );
}

// ── 2b. Los objetos de R2 (M5) ───────────────────────────────────────────────
// Esto **no lo ve la consulta de claves ajenas de arriba**: `files_metadata`
// referencia `auth.users`, no `profiles`, y además tiene `ON DELETE CASCADE`. Es
// decir: no bloquea el borrado, y ése es justo el problema. Al caer la fila, el
// objeto de R2 se queda sin nada que lo referencie y ya no hay forma de
// encontrarlo. Hay que borrarlo **antes**.
const archivos = await sql(
  `select id, r2_key, estado, tamano_bytes
   from public.files_metadata
   where propietario_id = '${cuenta.id}'
   order by created_at`,
);

console.log('\n  Objetos en R2 (M5):');
if (archivos.length === 0) {
  console.log('    (ninguno)');
} else {
  for (const a of archivos) {
    const tamano = a.tamano_bytes === null ? 'sin sellar' : `${a.tamano_bytes} B`;
    console.log(`    [${a.estado}] ${tamano}  ${a.r2_key}`);
  }
  console.log(
    `\n    ${archivos.length} objeto(s). **El CASCADE borrará estas filas y dejará los\n` +
      '    objetos en el bucket, invisibles para siempre.** Se borran antes (§4).',
  );
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
  if (archivos.length > 0 && !desactivarEnLugar) {
    console.log(
      `  Además se borrarán los ${archivos.length} objeto(s) de R2 listados arriba\n` +
        '  —los objetos primero, la cuenta después—.\n',
    );
  }
  process.exit(0);
}

if (referencias > 0 && !desactivarEnLugar) {
  console.error(
    '\n  Hay referencias que el borrado destruiría o que lo harían fallar:\n' +
      bloqueantes
        .map((f) => `    · ${f.tabla}.${f.columna}  (${f.al_borrar} vía ${f.destino})`)
        .join('\n') +
      '\n\n  Borrarla exigiría borrarlas antes, y eso puede destruir historial real\n' +
      '  (matrículas, actas, asistencias, entregas).\n' +
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

// ── 4b. Los objetos de R2, ANTES que la cuenta ───────────────────────────────
// El orden no es negociable. Si se borrara la cuenta primero, el CASCADE haría
// desaparecer las filas de `files_metadata` y con ellas la única pista de qué
// claves hay en el bucket: los objetos quedarían ahí para siempre, sin dueño y
// sin forma de encontrarlos. Borrando primero, un fallo se ve a tiempo y la
// operación se puede repetir.
if (archivos.length > 0) {
  console.log('\n  Borrando los objetos de R2 (objetos primero, cuenta después)…');
  const resultado = spawnSync(
    process.execPath,
    [
      join(RAIZ, 'backend', 'scripts', 'borrar-objetos-de-usuario.mjs'),
      `--propietario=${cuenta.id}`,
      '--confirmar',
    ],
    { stdio: 'inherit' },
  );

  if (resultado.status !== 0) {
    console.error(
      '\n  ALTO: no se pudieron borrar los objetos de R2. NO se borra la cuenta.\n' +
        '  En cuanto el CASCADE elimine las filas, esos objetos quedarán sin dueño\n' +
        '  y sin forma de encontrarlos. Arréglalo y vuelve a intentarlo.\n',
    );
    process.exit(1);
  }
} else {
  console.log('\n  Sin objetos de R2 que borrar.');
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
