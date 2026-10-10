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

/**
 * Petición a Fastify (la API propia). **Sólo declara `Content-Type: application/
 * json` si hay cuerpo**, igual que `ApiClient.post` del cliente Dart: un POST sin
 * cuerpo con esa cabecera dispara en Fastify `FST_ERR_CTP_EMPTY_JSON_BODY` y la
 * app lo traduce a 400. Imitar al cliente real evita medir un fallo inexistente.
 */
async function apiFastify(ruta, { metodo = 'GET', cuerpo, token } = {}) {
  const cabeceras = {};
  if (cuerpo !== undefined) cabeceras['Content-Type'] = 'application/json';
  if (token) cabeceras.Authorization = `Bearer ${token}`;
  const r = await fetch(`${API}${ruta}`, {
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
let idDocenteRenovado = null;

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
  if (idDocenteRenovado) await pedir(`/auth/v1/admin/users/${idDocenteRenovado}`, { metodo: 'DELETE' });
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

    // --- 5. Ciclo de vida: revocar y renovar ------------------------------
    // Lo que la prueba de arriba NO cubre: que una invitación anulada (por
    // revocación directa o por renovación) deje de activar cuentas, y que el
    // panel vea el estado coherente con lo que decide el endpoint de activación.
    console.log('\n  5. Ciclo de vida: revocar y renovar\n');

    const CORREO_REVOCADA = `humo-rev-${marca}@ejemplo.invalid`;
    const CORREO_RENOVADA = `humo-ren-${marca}@ejemplo.invalid`;

    /** Busca en el listado del panel la invitación de un correo. */
    const enListado = async (correo) => {
      const lista = await apiFastify('/api/v1/admin/usuarios/invitaciones?limite=200', { token: tokenAdmin });
      const filas = lista.datos?.invitaciones ?? [];
      return { estado: lista.estado, fila: filas.find((i) => i.email === correo) ?? null };
    };
    const tokenDe = (respuesta) => {
      const enlace = respuesta.datos?.enlaceActivacion ?? '';
      return enlace.includes('token=') ? enlace.split('token=')[1] : '';
    };

    // --- 5a. Revocar una invitación sin usar -------------------------------
    const creadaRev = await apiFastify('/api/v1/admin/usuarios/invitaciones', {
      metodo: 'POST', token: tokenAdmin,
      cuerpo: { email: CORREO_REVOCADA, nombres: 'Rev', apellidos: 'Ocada' },
    });
    const tokenRev = tokenDe(creadaRev);
    comprobar('crear una invitación para revocar', tokenRev.length > 0, `estado=${creadaRev.estado}`);

    const listadoRev = await enListado(CORREO_REVOCADA);
    comprobar('el listado del panel la muestra como «valida»', listadoRev.fila?.estado === 'valida', JSON.stringify(listadoRev.fila));
    comprobar(
      'el listado NO expone el hash del token',
      listadoRev.fila !== null && !('tokenHash' in listadoRev.fila) && !('token_hash' in listadoRev.fila),
      JSON.stringify(Object.keys(listadoRev.fila ?? {})),
    );

    const idRev = listadoRev.fila?.id;
    const revocada = await apiFastify(`/api/v1/admin/usuarios/invitaciones/${idRev}/revocar`, {
      metodo: 'POST', token: tokenAdmin,
    });
    comprobar('POST .../revocar responde 2xx', revocada.estado < 300, `estado=${revocada.estado}`);

    const listadoRev2 = await enListado(CORREO_REVOCADA);
    comprobar('tras revocar, el estado del panel pasa a «revocada»', listadoRev2.fila?.estado === 'revocada', String(listadoRev2.fila?.estado));

    const activarRevocada = await apiFastify('/api/v1/auth/activar', {
      metodo: 'POST', cuerpo: { token: tokenRev, password: CLAVE },
    });
    comprobar('un token revocado NO activa (403)', activarRevocada.estado === 403, `estado=${activarRevocada.estado}`);

    const perfilesRev = await pedir(`/rest/v1/profiles?email=eq.${CORREO_REVOCADA}&select=id`);
    comprobar('y NO creó ninguna cuenta', (perfilesRev.datos ?? []).length === 0, `perfiles=${(perfilesRev.datos ?? []).length}`);

    const revocarOtraVez = await apiFastify(`/api/v1/admin/usuarios/invitaciones/${idRev}/revocar`, {
      metodo: 'POST', token: tokenAdmin,
    });
    comprobar('revocar dos veces se rechaza (409, no idempotente silencioso)', revocarOtraVez.estado === 409, `estado=${revocarOtraVez.estado}`);

    // --- 5b. Renovar: la vieja muere, la nueva activa ----------------------
    const creadaRen = await apiFastify('/api/v1/admin/usuarios/invitaciones', {
      metodo: 'POST', token: tokenAdmin,
      cuerpo: { email: CORREO_RENOVADA, nombres: 'Ren', apellidos: 'Ovada' },
    });
    const tokenRenViejo = tokenDe(creadaRen);
    const listadoRen = await enListado(CORREO_RENOVADA);
    const idRen = listadoRen.fila?.id;

    const renovada = await apiFastify(`/api/v1/admin/usuarios/invitaciones/${idRen}/renovar`, {
      metodo: 'POST', token: tokenAdmin,
    });
    const tokenRenNuevo = tokenDe(renovada);
    comprobar('POST .../renovar responde 2xx', renovada.estado < 300, `estado=${renovada.estado}`);
    comprobar('renovar indica a quién reemplaza', renovada.datos?.reemplazaA === idRen, String(renovada.datos?.reemplazaA));

    const listadoRen2 = await enListado(CORREO_RENOVADA);
    // Tras renovar hay DOS filas para ese correo: la vieja (revocada) y la nueva
    // (válida). Se busca la vieja por su id, no por correo: `find` devolvería la
    // más reciente y mediría la fila equivocada.
    const filaViejaRen = (await apiFastify('/api/v1/admin/usuarios/invitaciones?limite=200', { token: tokenAdmin }))
      .datos?.invitaciones?.find((i) => i.id === idRen) ?? null;
    comprobar('tras renovar, la invitación vieja queda «revocada»', filaViejaRen?.estado === 'revocada', String(filaViejaRen?.estado));
    comprobar('y la nueva queda «valida»', listadoRen2.fila?.estado === 'valida', String(listadoRen2.fila?.estado));

    const activarRenViejo = await apiFastify('/api/v1/auth/activar', {
      metodo: 'POST', cuerpo: { token: tokenRenViejo, password: CLAVE },
    });
    comprobar('el token viejo tras renovar NO activa (403)', activarRenViejo.estado === 403, `estado=${activarRenViejo.estado}`);

    const activarRenNuevo = await apiFastify('/api/v1/auth/activar', {
      metodo: 'POST', cuerpo: { token: tokenRenNuevo, password: CLAVE },
    });
    comprobar('el token renovado SÍ activa (2xx)', activarRenNuevo.estado < 300, `estado=${activarRenNuevo.estado}`);
    comprobar('y crea el docente con el rol correcto', activarRenNuevo.datos?.perfil?.rol === 'docente', String(activarRenNuevo.datos?.perfil?.rol));
    idDocenteRenovado = activarRenNuevo.datos?.perfil?.id ?? null;
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
