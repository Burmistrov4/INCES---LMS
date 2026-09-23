/**
 * Humo de integración del canal de invitación de docentes (Módulo 1).
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que las 171 pruebas del backend NO pueden verificar, porque usan dobles en
 * memoria: que el motor real (PostgREST + RLS de Postgres + Fastify) se comporte
 * como el doble predijo.
 *
 *   1. RLS de `teacher_invitations` y `auth_logs` con tokens de usuario reales:
 *      un admin ve y crea; un usuario NO admin no ve nada; nadie escribe trazas
 *      de acceso a mano (no hay GRANT de INSERT para `authenticated`).
 *   2. El camino HTTP completo: invitar -> activar -> rol DOCENTE.
 *
 * CÓMO FUNCIONA
 * -------------
 * Crea un admin temporal, lo promueve, entra con contraseña para obtener un JWT
 * real, ejecuta las comprobaciones y lo purga todo al final (también si falla).
 *
 * NO CREA EL ADMIN CON `crear-admin.mjs`: ese script usa `inviteUserByEmail`, que
 * exige entrega de correo, y sin dominio verificado en Resend la API responde
 * 500 "Error sending invite email" para cualquier dirección que no sea la dueña
 * del proyecto. Aquí se usa `auth.admin.createUser` con `email_confirm: true`,
 * que no envía nada — el mismo camino que usa la activación de docentes.
 *
 * FUERA DE CI A PROPÓSITO: escribe en la base real. No lo pongas en un pipeline.
 *
 * USO
 * ---
 *   node supabase/humo-invitaciones.mjs              # simulación (no escribe)
 *   node supabase/humo-invitaciones.mjs --confirmar  # ejecuta el humo
 *
 * La sección HTTP sólo corre si el backend responde en API_BASE_URL
 * (por defecto http://localhost:3001). La sección de RLS no necesita backend:
 * RLS la aplica PostgREST, no Fastify.
 */
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const CONFIRMAR = process.argv.includes('--confirmar');
const API = (process.env.API_BASE_URL ?? 'http://localhost:3001').replace(/\/+$/, '');

/** Lee del entorno y, si no está, de `backend/.env` (sin añadir `dotenv`). */
function variable(nombre) {
  const delEntorno = (process.env[nombre] ?? '').trim();
  if (delEntorno.length > 0) return delEntorno;
  try {
    for (const linea of readFileSync(join(RAIZ, 'backend', '.env'), 'utf8').split('\n')) {
      const limpia = linea.trim();
      if (limpia.length === 0 || limpia.startsWith('#')) continue;
      const corte = limpia.indexOf('=');
      if (corte < 0) continue;
      if (limpia.slice(0, corte).trim() === nombre) return limpia.slice(corte + 1).trim();
    }
  } catch {
    // Sin .env legible: se tratará como variable ausente, más abajo.
  }
  return '';
}

const URL_BASE = variable('SUPABASE_URL');
const CLAVE_SERVICIO = variable('SUPABASE_SERVICE_ROLE_KEY');
const CLAVE_ANON = variable('SUPABASE_ANON_KEY');

let ok = 0;
let fallos = 0;
const comprobar = (etiqueta, condicion, detalle = '') => {
  if (condicion) { ok += 1; console.log(`  [OK  ] ${etiqueta}`); }
  else { fallos += 1; console.log(`  [FALLA] ${etiqueta}${detalle ? ` — ${detalle}` : ''}`); }
};

/** Petición cruda que devuelve estado + cuerpo, sin lanzar por códigos HTTP. */
async function pedir(ruta, { metodo = 'GET', cuerpo, clave, token, extra = {} } = {}) {
  const cabeceras = { apikey: clave ?? CLAVE_SERVICIO, 'Content-Type': 'application/json', ...extra };
  if (token) cabeceras.Authorization = `Bearer ${token}`;
  else if (clave ?? CLAVE_SERVICIO) cabeceras.Authorization = `Bearer ${clave ?? CLAVE_SERVICIO}`;

  const r = await fetch(`${URL_BASE}${ruta}`, {
    method: metodo,
    headers: cabeceras,
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  let datos = null;
  try { datos = texto.length > 0 ? JSON.parse(texto) : null; } catch { datos = texto; }
  return { estado: r.status, datos };
}

if (!URL_BASE || !CLAVE_SERVICIO || !CLAVE_ANON) {
  console.error('\n  Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY.');
  console.error('  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n');
  process.exit(1);
}

const marca = Date.now();
const CORREO_ADMIN = `humo-admin-${marca}@ejemplo.invalid`;
const CORREO_DOCENTE = `humo-docente-${marca}@ejemplo.invalid`;
const CLAVE = `Humo!${randomBytes(12).toString('base64url')}`;

let idAdmin = null;
let idDocente = null;

console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Backend  : ${API}`);
console.log(`  Modo     : ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);

if (!CONFIRMAR) {
  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  console.log(`\n  Backend ${salud === null ? 'NO responde' : `responde ${salud}`}.`);
  console.log('\n  Simulación: no se escribió nada. Repite con --confirmar.\n');
  process.exit(0);
}

/** Purga todo lo que cree este script. Se ejecuta siempre, también al fallar. */
async function purgar() {
  if (idDocente) await pedir(`/auth/v1/admin/users/${idDocente}`, { metodo: 'DELETE' });
  if (idAdmin) await pedir(`/auth/v1/admin/users/${idAdmin}`, { metodo: 'DELETE' });
  // Por prefijo, no por valor exacto: una corrida anterior puede dejar residuo.
  await pedir('/rest/v1/teacher_invitations?email=like.humo*', { metodo: 'DELETE' });
  await pedir('/rest/v1/auth_logs?email=like.humo*', { metodo: 'DELETE' });
  await pedir('/rest/v1/profiles?email=like.humo*', { metodo: 'DELETE' });
}

try {
  // --- 1. Admin temporal con JWT real --------------------------------------
  console.log('\n  1. Preparar un admin temporal con sesión real\n');

  const creado = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: { email: CORREO_ADMIN, password: CLAVE, email_confirm: true },
  });
  idAdmin = creado.datos?.id ?? null;
  comprobar('crear el admin temporal (sin enviar correo)', Boolean(idAdmin), `estado=${creado.estado}`);

  const promovido = await pedir(`/rest/v1/profiles?id=eq.${idAdmin}`, {
    metodo: 'PATCH',
    cuerpo: { rol: 'admin' },
    extra: { Prefer: 'return=representation' },
  });
  comprobar('promoverlo a rol admin', promovido.datos?.[0]?.rol === 'admin', JSON.stringify(promovido.datos)?.slice(0, 120));

  const sesion = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    cuerpo: { email: CORREO_ADMIN, password: CLAVE },
  });
  const tokenAdmin = sesion.datos?.access_token ?? null;
  comprobar('iniciar sesión y obtener JWT', Boolean(tokenAdmin), `estado=${sesion.estado}`);

  // --- 2. RLS contra PostgREST --------------------------------------------
  console.log('\n  2. RLS de teacher_invitations y auth_logs (tokens reales)\n');

  const comoAdmin = await pedir('/rest/v1/teacher_invitations?select=id&limit=1', {
    clave: CLAVE_ANON, token: tokenAdmin,
  });
  comprobar('el admin LEE teacher_invitations (política is_admin)', comoAdmin.estado === 200, `estado=${comoAdmin.estado}`);

  const comoAnon = await pedir('/rest/v1/teacher_invitations?select=id', { clave: CLAVE_ANON });
  const filasAnon = Array.isArray(comoAnon.datos) ? comoAnon.datos.length : -1;
  comprobar('anon NO ve invitaciones', filasAnon === 0 || comoAnon.estado >= 400, `estado=${comoAnon.estado} filas=${filasAnon}`);

  const insertarTraza = await pedir('/rest/v1/auth_logs', {
    metodo: 'POST', clave: CLAVE_ANON, token: tokenAdmin,
    cuerpo: { estado: 'SUCCESS', email: 'humo_intento_no_deberia_entrar@ejemplo.invalid' },
  });
  comprobar(
    'nadie INSERTA en auth_logs con rol authenticated (sin GRANT)',
    insertarTraza.estado >= 400,
    `estado=${insertarTraza.estado}`,
  );

  const leerTraza = await pedir('/rest/v1/auth_logs?select=id&limit=1', {
    clave: CLAVE_ANON, token: tokenAdmin,
  });
  comprobar('el admin LEE auth_logs (política is_admin)', leerTraza.estado === 200, `estado=${leerTraza.estado}`);

  // --- 3. Camino HTTP completo --------------------------------------------
  console.log('\n  3. HTTP end-to-end: invitar y activar\n');

  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  if (salud === null) {
    console.log('  [SKIP ] el backend no responde en ' + API);
    console.log('         levántalo con: cd backend && PORT=8080 npm run dev');
  } else {
    const invitacion = await fetch(`${API}/api/v1/admin/usuarios/invitaciones`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tokenAdmin}` },
      body: JSON.stringify({
        email: CORREO_DOCENTE,
        nombres: 'Docente',
        apellidos: 'De Prueba',
      }),
    }).then(async (r) => ({ estado: r.status, datos: await r.json().catch(() => null) }));

    comprobar('POST /admin/usuarios/invitaciones responde 2xx', invitacion.estado < 300, `estado=${invitacion.estado}`);

    const enlace = invitacion.datos?.enlaceActivacion ?? '';
    const token = enlace.includes('token=') ? enlace.split('token=')[1] : '';
    comprobar('la respuesta trae enlaceActivacion con token', token.length > 0);
    comprobar('el enlace usa hash strategy (#/auth/activate)', enlace.includes('/#/auth/activate'));
    console.log(`         correoEnviado=${invitacion.datos?.correoEnviado} (false es esperado: Resend sólo entrega al buzón dueño)`);

    const activado = await fetch(`${API}/api/v1/auth/activar`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, password: CLAVE }),
    }).then(async (r) => ({ estado: r.status, datos: await r.json().catch(() => null) }));

    comprobar('POST /auth/activar responde 2xx', activado.estado < 300, `estado=${activado.estado} ${JSON.stringify(activado.datos)?.slice(0, 140)}`);
    comprobar('el perfil queda con rol docente', activado.datos?.perfil?.rol === 'docente', String(activado.datos?.perfil?.rol));
    // R-21: el nombre capturado al invitar debe llegar a profiles, no quedar en blanco.
    comprobar(
      'el perfil recibe los nombres del docente (R-21)',
      !!activado.datos?.perfil?.nombres && activado.datos?.perfil?.nombres.length > 0,
      String(activado.datos?.perfil?.nombres),
    );
    idDocente = activado.datos?.perfil?.id ?? null;

    // Reutilizar el token debe fallar: es de un solo uso.
    const reuso = await fetch(`${API}/api/v1/auth/activar`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, password: CLAVE }),
    }).then((r) => r.status);
    comprobar('reutilizar el token se rechaza (un solo uso)', reuso >= 400, `estado=${reuso}`);

    // --- 4. Estado en la base, no sólo el 200 ----------------------------
    console.log('\n  4. Estado persistido en la base\n');

    const invit = await pedir(`/rest/v1/teacher_invitations?email=eq.${CORREO_DOCENTE}&select=is_used,token_hash,nombres,apellidos`);
    comprobar('is_used = true tras activar', invit.datos?.[0]?.is_used === true, JSON.stringify(invit.datos));
    comprobar('el token en claro NO está en la base', invit.datos?.[0]?.token_hash !== token);
    comprobar(
      'la invitación guardó los nombres capturados (R-21)',
      invit.datos?.[0]?.nombres === 'Docente' && invit.datos?.[0]?.apellidos === 'De Prueba',
      JSON.stringify(invit.datos?.[0]),
    );

    const trazas = await pedir(`/rest/v1/auth_logs?email=eq.${CORREO_DOCENTE}&select=estado`);
    const exitos = (trazas.datos ?? []).filter((f) => f.estado === 'SUCCESS').length;
    comprobar('auth_logs registró el acceso exitoso', exitos >= 1, `SUCCESS=${exitos}`);

    // Un no-admin no debe ver las invitaciones: RLS con un JWT de docente.
    const sesionDocente = await pedir('/auth/v1/token?grant_type=password', {
      metodo: 'POST', clave: CLAVE_ANON, cuerpo: { email: CORREO_DOCENTE, password: CLAVE },
    });
    const tokenDocente = sesionDocente.datos?.access_token;
    if (tokenDocente) {
      const comoDocente = await pedir('/rest/v1/teacher_invitations?select=id', {
        clave: CLAVE_ANON, token: tokenDocente,
      });
      const filas = Array.isArray(comoDocente.datos) ? comoDocente.datos.length : -1;
      comprobar('un docente NO ve invitaciones (RLS por is_admin)', filas === 0, `filas=${filas}`);
    }
  }
} catch (error) {
  fallos += 1;
  console.error(`\n  EXCEPCIÓN NO CONTROLADA: ${error?.message ?? error}`);
} finally {
  console.log('\n  Purga...');
  await purgar();
  const residuo = await pedir('/rest/v1/teacher_invitations?email=like.humo*&select=id');
  const residuoTrazas = await pedir('/rest/v1/auth_logs?email=like.humo*&select=id');
  const residuoPerfiles = await pedir('/rest/v1/profiles?email=like.humo*&select=id');
  const nResiduo = Array.isArray(residuo.datos) ? residuo.datos.length : -1;
  const nTrazas = Array.isArray(residuoTrazas.datos) ? residuoTrazas.datos.length : -1;
  const nPerfiles = Array.isArray(residuoPerfiles.datos) ? residuoPerfiles.datos.length : -1;
  console.log(`\n  Resultado: ${ok} OK / ${fallos} fallos`);
  console.log(
    `  Residuo en la base: invitaciones=${nResiduo} trazas=${nTrazas} perfiles=${nPerfiles} (debe ser 0, 0 y 0)`,
  );
  process.exit(
    fallos === 0 && nResiduo === 0 && nTrazas === 0 && nPerfiles === 0 ? 0 : 1,
  );
}
