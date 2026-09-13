/**
 * Prueba de humo contra la API real y la base de datos real en la nube.
 *
 * Las 127 pruebas de `vitest` corren contra dobles en memoria: demuestran que la
 * lógica es correcta, no que el despliegue funcione. Un esquema mal migrado, una
 * política RLS que no deja leer, una clave secreta sin permisos o un CORS mal
 * puesto pasan las 127 y rompen en producción.
 *
 * Esta prueba cierra ese hueco: habla con el proceso que está escuchando en
 * localhost, que a su vez habla con Supabase. Si algo de la cadena está mal, sale
 * aquí.
 *
 * Cómo consigue una sesión sin depender de que alguien confirme un correo:
 * usa la Auth Admin API con la clave secreta para **generar un enlace de acceso
 * directo** (`generate_link`), lo canjea en `/auth/v1/verify` y obtiene un JWT
 * de verdad. Ese token lo firma GoTrue con el secreto del proyecto, así que
 * ejercita exactamente la misma verificación de firma que usaría un alumno.
 *
 * Uso: node backend/test-humo.mjs
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const API = process.env.API_BASE_URL ?? 'http://127.0.0.1:3000';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL ?? 'lorenzoroca11@hotmail.com';

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
      if (limpia.slice(0, corte).trim() === nombre) return limpia.slice(corte + 1).trim();
    }
  } catch {
    /* sin archivo */
  }
  return '';
}

const url = variable('SUPABASE_URL').replace(/\/+$/, '');
const anon = variable('SUPABASE_ANON_KEY');
const secreta = variable('SUPABASE_SERVICE_ROLE_KEY');

let pasos = 0;
let fallos = 0;

function comprobar(etiqueta, condicion, detalle) {
  pasos += 1;
  if (!condicion) fallos += 1;
  const marca = condicion ? 'OK  ' : 'FALLA';
  console.log(`  [${marca}] ${etiqueta}${detalle !== undefined ? ` — ${detalle}` : ''}`);
}

async function pedir(ruta, opciones = {}) {
  const respuesta = await fetch(`${API}${ruta}`, opciones);
  const texto = await respuesta.text();
  let cuerpo = null;
  try {
    cuerpo = texto.length > 0 ? JSON.parse(texto) : null;
  } catch {
    cuerpo = texto;
  }
  return { estado: respuesta.status, cuerpo };
}

console.log('\n================  PRUEBA DE HUMO CONTRA LA NUBE  ================\n');
console.log(`  API      : ${API}`);
console.log(`  Supabase : ${url}`);
console.log(`  Admin    : ${ADMIN_EMAIL}\n`);

// --- 0. Precondiciones ------------------------------------------------------
if (!url || !anon || !secreta) {
  console.error('  Faltan SUPABASE_URL, SUPABASE_ANON_KEY o SUPABASE_SERVICE_ROLE_KEY.\n');
  process.exit(1);
}

// --- 1. La API está viva ----------------------------------------------------
console.log('  1. Sondas de salud\n');
{
  const salud = await pedir('/salud');
  comprobar('/salud responde 200', salud.estado === 200, `HTTP ${salud.estado}`);
  comprobar('/salud reporta estado ok', salud.cuerpo?.estado === 'ok', salud.cuerpo?.estado);

  const profundo = await pedir('/salud/profundo');
  comprobar(
    '/salud/profundo llega a la base real',
    profundo.estado === 200 && profundo.cuerpo?.baseDeDatos === 'ok',
    `HTTP ${profundo.estado} · baseDeDatos=${profundo.cuerpo?.baseDeDatos}`,
  );
}

// --- 2. Una petición sin sesión debe rebotar --------------------------------
console.log('\n  2. Sin sesión la API cierra la puerta\n');
{
  const sinToken = await pedir('/api/v1/yo');
  comprobar('GET /api/v1/yo sin token → 401', sinToken.estado === 401, `HTTP ${sinToken.estado}`);

  const tokenFalso = await pedir('/api/v1/yo', {
    headers: { Authorization: 'Bearer eyJhbGciOiJIUzI1NiJ9.falso.firma' },
  });
  comprobar(
    'GET /api/v1/yo con token falsificado → 401',
    tokenFalso.estado === 401,
    `HTTP ${tokenFalso.estado}`,
  );
}

// --- 3. Conseguir una sesión real del administrador -------------------------
console.log('\n  3. Sesión real del administrador\n');
let tokenAcceso = null;
{
  const enlace = await fetch(`${url}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: {
      apikey: secreta,
      Authorization: `Bearer ${secreta}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ type: 'magiclink', email: ADMIN_EMAIL }),
  });
  const cuerpoEnlace = await enlace.json();
  if (!enlace.ok) {
    console.error(`  ✗ No se pudo generar el enlace: HTTP ${enlace.status}`, cuerpoEnlace);
    process.exit(1);
  }

  // `generate_link` devuelve un `hashed_token` que se canjea con el endpoint
  // verify. Esta es la vía que documenta Supabase para probar sin depender del
  // correo: el token viaja firmado por GoTrue igual que en un acceso normal.
  const hashed = cuerpoEnlace.hashed_token;
  comprobar('enlace de acceso generado', Boolean(hashed), `tipo=${cuerpoEnlace.action_link ? 'ok' : '?'}`);

  const canje = await fetch(`${url}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: hashed }),
  });
  const sesion = await canje.json();
  if (!canje.ok) {
    console.error(`  ✗ El canje falló: HTTP ${canje.status}`, sesion);
    process.exit(1);
  }
  tokenAcceso = sesion.access_token;
  comprobar('token de acceso obtenido', typeof tokenAcceso === 'string' && tokenAcceso.length > 100);
  comprobar(
    'el token es de verdad del proyecto (iss coincide)',
    JSON.parse(Buffer.from(tokenAcceso.split('.')[1], 'base64url').toString()).iss === `${url}/auth/v1`,
  );
}

const sesion = {
  Authorization: `Bearer ${tokenAcceso}`,
  'Content-Type': 'application/json',
};

// --- 4. La API reconoce al administrador ------------------------------------
console.log('\n  4. La API resuelve la identidad contra la base real\n');
{
  const yo = await pedir('/api/v1/yo', { headers: sesion });
  comprobar('GET /api/v1/yo → 200', yo.estado === 200, `HTTP ${yo.estado}`);
  comprobar('el correo coincide', yo.cuerpo?.perfil?.email === ADMIN_EMAIL, yo.cuerpo?.perfil?.email);
  comprobar('el rol es admin (leído de profiles)', yo.cuerpo?.rol === 'admin', yo.cuerpo?.rol);
}

// --- 5. Los módulos llegan desde system_modules -----------------------------
console.log('\n  5. Lectura de system_modules en la nube\n');
{
  const modulos = await pedir('/api/v1/modulos', { headers: sesion });
  comprobar('GET /api/v1/modulos → 200', modulos.estado === 200, `HTTP ${modulos.estado}`);
  const lista = modulos.cuerpo?.modulos ?? [];
  comprobar('llegan módulos', lista.length > 0, `${lista.length} visibles para admin`);
  const cp = await pedir('/api/v1/admin/modulos', { headers: sesion });
  comprobar('GET /api/v1/admin/modulos → 200', cp.estado === 200, `HTTP ${cp.estado}`);
  const todos = cp.cuerpo?.modulos ?? [];
  comprobar('el panel ve los 9 módulos', todos.length === 9, `${todos.length}`);
  comprobar(
    'm5_archivos existe y está apagado (R2 sin credenciales)',
    todos.some((m) => m.clave === 'm5_archivos' && m.habilitado === false),
  );
}

// --- 6. La barrera del último admin está viva también en la nube ------------
console.log('\n  6. Invariante D8 en la base real\n');
{
  const degradar = await pedir(
    '/api/v1/admin/usuarios/00000000-0000-0000-0000-000000000000/rol',
    {
      method: 'PATCH',
      headers: sesion,
      body: JSON.stringify({ rol: 'estudiante' }),
    },
  );
  comprobar(
    'degradar a un usuario inexistente → 404 (no 500)',
    degradar.estado === 404,
    `HTTP ${degradar.estado} · ${degradar.cuerpo?.error?.codigo}`,
  );

  // El atajo `/me` no existe: el id del llamante ya viaja en la sesión. Antes
  // este caso devolvía un 500 con un error crudo de Postgres (`22P02 … "me"`).
  const atajo = await pedir('/api/v1/admin/usuarios/me/rol', {
    method: 'PATCH',
    headers: sesion,
    body: JSON.stringify({ rol: 'estudiante' }),
  });
  comprobar(
    'un id que no es UUID → 400 (no 500 de Postgres)',
    atajo.estado === 400,
    `HTTP ${atajo.estado} · ${atajo.cuerpo?.error?.codigo}`,
  );

  const autoDegradar = await pedir('/api/v1/admin/usuarios/me/rol', {
    method: 'PATCH',
    headers: sesion,
    body: JSON.stringify({ rol: 'estudiante' }),
  });
  // Si algún día se admite `/me`, debe ser un 409 de negocio, nunca un 500.
  comprobar(
    'autodegradarse no da 200 ni 500',
    autoDegradar.estado !== 200 && autoDegradar.estado < 500,
    `HTTP ${autoDegradar.estado}`,
  );

  const propiaId = JSON.parse(
    Buffer.from(tokenAcceso.split('.')[1], 'base64url').toString(),
  ).sub;
  const autoReal = await pedir(`/api/v1/admin/usuarios/${propiaId}/rol`, {
    method: 'PATCH',
    headers: sesion,
    body: JSON.stringify({ rol: 'estudiante' }),
  });
  comprobar(
    'PATCH con el UUID propio → 409 AUTO_DEGRADACION',
    autoReal.estado === 409 && autoReal.cuerpo?.error?.codigo === 'AUTO_DEGRADACION',
    `HTTP ${autoReal.estado} · ${autoReal.cuerpo?.error?.codigo}`,
  );

  const sigueAdmin = await pedir('/api/v1/yo', { headers: sesion });
  comprobar(
    'el administrador sigue siendo admin tras los intentos',
    sigueAdmin.cuerpo?.rol === 'admin',
    sigueAdmin.cuerpo?.rol,
  );
}

// --- 7. CORS ----------------------------------------------------------------
console.log('\n  7. CORS y cabeceras de seguridad\n');
{
  const preflight = await fetch(`${API}/api/v1/yo`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'http://localhost:8080',
      'Access-Control-Request-Method': 'GET',
    },
  });
  comprobar(
    'preflight desde el origen de Flutter Web está permitido',
    preflight.status === 204 || preflight.status === 200,
    `HTTP ${preflight.status}`,
  );

  const respuesta = await fetch(`${API}/salud`);
  comprobar(
    'Helmet pone x-content-type-options',
    respuesta.headers.get('x-content-type-options') === 'nosniff',
    respuesta.headers.get('x-content-type-options') ?? 'ausente',
  );

  const desconocido = await fetch(`${API}/api/v1/yo`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'http://sitio-malicioso.example',
      'Access-Control-Request-Method': 'GET',
    },
  });
  const permitido = desconocido.headers.get('access-control-allow-origin');
  comprobar(
    'un origen no autorizado no recibe permiso CORS',
    permitido !== 'http://sitio-malicioso.example',
    permitido ?? 'sin cabecera (correcto)',
  );
}

console.log(`\n================  ${pasos - fallos}/${pasos} comprobaciones OK  ================\n`);
if (fallos > 0) {
  console.log(`  ✗ ${fallos} fallaron. La cadena API → Supabase tiene un problema.\n`);
  process.exit(1);
}
console.log('  ✓ La API habla con Supabase en la nube de extremo a extremo.\n');
