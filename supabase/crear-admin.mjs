/**
 * Promueve una cuenta a administrador en la base de datos real.
 *
 * Existe porque **no hay forma de crear el primer administrador desde la
 * aplicación**, y eso es deliberado: el auto-registro nunca otorga rol
 * (ADR-008) y el trigger `handle_new_user()` fija `estudiante` a propósito.
 * Si la app pudiera promoverse a sí misma, cualquiera con la clave publicable
 * —que viaja en el bundle del navegador— sería administrador del INCES.
 *
 * Así que el primer admin se crea fuera de la aplicación. Este script lo hace
 * en tres formas, y elige la primera que corresponda:
 *
 *   A) La cuenta ya existe en `auth.users` y ya tiene fila en `profiles`
 *      → sólo sube el rol.
 *   B) La cuenta nunca se registró
 *      → la invita por la Auth Admin API (crea el usuario y dispara el trigger
 *        `on_auth_user_created`, que es quien crea el perfil).
 *   C) La cuenta existe en Auth pero el perfil no (registro a medias)
 *      → la reconstruye aquí.
 *
 * Requiere la clave secreta, no la publicable: invitar usuarios es una
 * operación de administración. `SUPABASE_SERVICE_ROLE_KEY` vive sólo en
 * `backend/.env` y nunca debe salir de ahí.
 *
 * Uso:
 *   SUPABASE_URL=https://xxx.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxx \
 *   node supabase/crear-admin.mjs lorenzoroca11@hotmail.com
 *
 *   # Simulación, no escribe nada:
 *   ... node supabase/crear-admin.mjs lorenzoroca11@hotmail.com --dry-run
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');

/**
 * Lee una variable de entorno o, si no está, la busca en `backend/.env`.
 * Se evita `dotenv` a propósito: el backend ya usa `--env-file-if-exists` de
 * Node 22 y no queremos una dependencia más sólo para esto.
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
const simular = process.argv.includes('--dry-run');
const url = variable('SUPABASE_URL').replace(/\/+$/, '');
const secreta = variable('SUPABASE_SERVICE_ROLE_KEY');

if (email.length === 0 || !email.includes('@')) {
  console.error('\n  Uso: node supabase/crear-admin.mjs correo@dominio.com [--dry-run]\n');
  process.exit(1);
}
if (url.length === 0) {
  console.error('\n  Falta SUPABASE_URL (en backend/.env o en el entorno).\n');
  process.exit(1);
}
if (secreta.length === 0) {
  console.error(
    '\n  Falta SUPABASE_SERVICE_ROLE_KEY.\n\n' +
      '  Es la clave SECRETA, no la publicable. Panel de Supabase →\n' +
      '  Project Settings → API Keys → Secret keys. Ponla en backend/.env.\n' +
      '  Crear usuarios es una operación de administración: con la clave\n' +
      '  publicable daría 401, y si funcionara sería un agujero de seguridad.\n',
  );
  process.exit(1);
}

const cabeceras = {
  apikey: secreta,
  Authorization: `Bearer ${secreta}`,
  'Content-Type': 'application/json',
};

async function apiAdmin(ruta, opciones = {}) {
  const respuesta = await fetch(`${url}/auth/v1${ruta}`, {
    ...opciones,
    headers: { ...cabeceras, ...opciones.headers },
  });
  const texto = await respuesta.text();
  const cuerpo = texto.length > 0 ? JSON.parse(texto) : null;
  if (!respuesta.ok) {
    const detalle =
      cuerpo && typeof cuerpo === 'object'
        ? (cuerpo.msg ?? cuerpo.message ?? cuerpo.error_description ?? texto)
        : texto;
    throw new Error(`HTTP ${respuesta.status}: ${detalle}`);
  }
  return cuerpo;
}

/** Consulta PostgREST con la clave secreta: aquí sí se salta RLS, a propósito. */
async function rest(ruta, opciones = {}) {
  const respuesta = await fetch(`${url}/rest/v1${ruta}`, {
    ...opciones,
    headers: { ...cabeceras, Prefer: 'return=representation', ...opciones.headers },
  });
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    throw new Error(`HTTP ${respuesta.status}: ${texto}`);
  }
  return texto.length > 0 ? JSON.parse(texto) : null;
}

console.log(`\n  Proyecto : ${url}`);
console.log(`  Cuenta   : ${email}`);
console.log(`  Modo     : ${simular ? 'SIMULACIÓN (no escribe)' : 'real'}\n`);

const filas = await rest(
  `/profiles?email=eq.${encodeURIComponent(email)}&select=id,email,rol,active`,
);
const perfil = Array.isArray(filas) ? filas[0] : undefined;

let idUsuario = perfil?.id ?? null;
let camino = 'A';

if (!perfil) {
  // Caso B: la cuenta no existe. Se invita. El correo lo confirma el propio
  // usuario; el perfil lo crea el trigger `on_auth_user_created`.
  console.log('  No hay perfil. Invitando la cuenta por la Auth Admin API…');
  camino = 'B';
  if (!simular) {
    const invitado = await apiAdmin('/invite', {
      method: 'POST',
      body: JSON.stringify({ email }),
    });
    idUsuario = invitado?.id ?? invitado?.user?.id ?? null;
    if (!idUsuario) {
      throw new Error('La invitación no devolvió un id de usuario.');
    }
    console.log(`  ✓ Invitación enviada. id = ${idUsuario}`);
  }
} else {
  idUsuario = perfil.id;
  console.log(`  Perfil encontrado. id = ${idUsuario} · rol actual = ${perfil.rol}`);
  if (perfil.rol === 'admin' && perfil.active) {
    console.log('\n  Ya es administrador activo. Nada que hacer.\n');
    process.exit(0);
  }
}

if (simular) {
  console.log(`\n  Camino ${camino}. En modo real pondría rol = admin, active = true.`);
  console.log('  Simulación: no se escribió nada.\n');
  process.exit(0);
}

// Si el perfil lo creó el trigger, puede tardar un instante en aparecer.
let perfilTrasInvitacion = null;
for (let intento = 0; intento < 10 && idUsuario; intento += 1) {
  const buscado = await rest(`/profiles?id=eq.${idUsuario}&select=id,email,rol,active`);
  perfilTrasInvitacion = Array.isArray(buscado) ? buscado[0] : undefined;
  if (perfilTrasInvitacion) break;
  await new Promise((r) => setTimeout(r, 300));
}

if (!perfilTrasInvitacion) {
  // Caso C: existe en Auth pero el trigger no dejó perfil. Se reconstruye.
  console.log('  Sin perfil tras la invitación. Reconstruyendo la fila…');
  await rest('/profiles', {
    method: 'POST',
    body: JSON.stringify({
      id: idUsuario,
      email,
      nombres: '',
      apellidos: '',
      rol: 'estudiante',
    }),
  });
}

// La promoción en sí. Se hace con UPDATE para que dispare la auditoría y los
// trigger de `updated_at`, y para que no choque con el trigger
// `proteger_ultimo_admin` (que sólo mira degradaciones, no ascensos).
await rest(`/profiles?id=eq.${idUsuario}`, {
  method: 'PATCH',
  body: JSON.stringify({ rol: 'admin', active: true }),
});

const verificacion = await rest(`/profiles?id=eq.${idUsuario}&select=id,email,rol,active`);
const resultado = Array.isArray(verificacion) ? verificacion[0] : null;

if (resultado?.rol === 'admin' && resultado?.active === true) {
  console.log('\n  ✓ Confirmado contra la base de datos:');
  console.log(`      id     = ${resultado.id}`);
  console.log(`      email  = ${resultado.email}`);
  console.log(`      rol    = ${resultado.rol}`);
  console.log(`      activo = ${resultado.active}\n`);
} else {
  console.error('\n  ✗ El UPDATE no dejó la fila como se esperaba:', resultado, '\n');
  process.exit(1);
}
