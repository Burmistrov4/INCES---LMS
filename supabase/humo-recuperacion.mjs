/**
 * Humo de integración de la recuperación interna de contraseña (sin correo).
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que las pruebas del backend NO pueden verificar, porque usan dobles en
 * memoria: que el motor real (PostgREST + RLS + Fastify + GoTrue) se comporte
 * como el doble predijo. Recorrido completo, con una cuenta desechable:
 *
 *   1. Un administrador autorizado emite un código temporal para un usuario.
 *   2. El código se devuelve UNA sola vez y NO queda en claro en la base.
 *   3. Emitir un código nuevo anula el anterior (no hay dos válidos a la vez).
 *   4. El titular canjea el código y fija su PROPIA contraseña.
 *   5. La contraseña nueva entra; la vieja deja de entrar.
 *   6. Las sesiones previas quedan cerradas (el refresh token viejo muere).
 *   7. El código no se reutiliza, y un código inválido responde IGUAL que uno
 *      caducado o ya usado (sin enumeración).
 *   8. La auditoría registra el éxito sin guardar contraseñas ni códigos.
 *
 * AISLAMIENTO
 * -----------
 * Crea sus propias cuentas con el prefijo `humo-rec-*` y un dominio `.invalid`
 * (que nunca resuelve ni recibe correo), y las purga siempre —también si falla—
 * borrando por prefijo. No toca ninguna cuenta real ni datos compartidos.
 *
 * FUERA DE CI A PROPÓSITO: escribe en la base real. No lo pongas en un pipeline.
 *
 * USO
 * ---
 *   node supabase/humo-recuperacion.mjs              # simulación (no escribe)
 *   node supabase/humo-recuperacion.mjs --confirmar  # ejecuta el humo
 *   node supabase/humo-recuperacion.mjs --confirmar --limite   # + prueba del 429
 *
 * `--limite` deja la IP con el contador de intentos agotado 15 minutos (es el
 * efecto que mide). Por eso no va por defecto.
 *
 * La sección HTTP sólo corre si el backend responde en API_BASE_URL
 * (por defecto http://localhost:3001). La sección de RLS no necesita backend.
 */
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const CONFIRMAR = process.argv.includes('--confirmar');
const PROBAR_LIMITE = process.argv.includes('--limite');
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
 * Igual que `pedir`, pero contra Fastify (la API propia).
 *
 * **Sólo se declara `Content-Type: application/json` si hay cuerpo.** Un POST
 * sin cuerpo con esa cabecera dispara en Fastify `FST_ERR_CTP_EMPTY_JSON_BODY`
 * y la app lo traduce a 400 «El cuerpo debe ser JSON válido». El cliente Dart
 * (`ApiClient.post`) hace exactamente esta misma omisión; el arnés debe imitarlo
 * o mediría un fallo que el cliente real nunca provoca.
 */
async function api(ruta, { metodo = 'GET', cuerpo, token } = {}) {
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

const sha256 = (s) => createHash('sha256').update(s).digest('hex');
/** Misma normalización que `normalizarCodigo` del backend (sin guiones, mayúsculas). */
const normalizar = (c) => c.replace(/[\s-]/g, '').toUpperCase();

if (!URL_BASE || !CLAVE_SERVICIO || !CLAVE_ANON) {
  console.error('\n  Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY.');
  console.error('  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n');
  process.exit(1);
}

const marca = Date.now();
const CORREO_ADMIN = `humo-rec-admin-${marca}@ejemplo.invalid`;
const CORREO_OBJETIVO = `humo-rec-objetivo-${marca}@ejemplo.invalid`;
const CLAVE_ADMIN = `Humo!${randomBytes(12).toString('base64url')}`;
const CLAVE_VIEJA = `Vieja!${randomBytes(12).toString('base64url')}`;
const CLAVE_NUEVA = `Nueva!${randomBytes(12).toString('base64url')}`;

let idAdmin = null;
let idObjetivo = null;

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
  if (idObjetivo) await pedir(`/auth/v1/admin/users/${idObjetivo}`, { metodo: 'DELETE' });
  if (idAdmin) await pedir(`/auth/v1/admin/users/${idAdmin}`, { metodo: 'DELETE' });
  // Por prefijo, no por valor exacto: una corrida anterior puede dejar residuo.
  await pedir('/rest/v1/password_resets?select=id', { metodo: 'GET' }).catch(() => {});
  await pedir('/rest/v1/auth_logs?email=like.humo-rec*', { metodo: 'DELETE' });
  await pedir('/rest/v1/profiles?email=like.humo-rec*', { metodo: 'DELETE' });
}

try {
  // --- 0. Preparar admin y objetivo con JWT/sesión reales ------------------
  console.log('\n  0. Cuentas desechables (admin + objetivo)\n');

  const creadoAdmin = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: { email: CORREO_ADMIN, password: CLAVE_ADMIN, email_confirm: true },
  });
  idAdmin = creadoAdmin.datos?.id ?? null;
  comprobar('crear el admin temporal (sin enviar correo)', Boolean(idAdmin), `estado=${creadoAdmin.estado}`);

  const promovido = await pedir(`/rest/v1/profiles?id=eq.${idAdmin}`, {
    metodo: 'PATCH',
    cuerpo: { rol: 'admin' },
    extra: { Prefer: 'return=representation' },
  });
  comprobar('promoverlo a rol admin', promovido.datos?.[0]?.rol === 'admin', JSON.stringify(promovido.datos)?.slice(0, 120));

  const sesionAdmin = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    cuerpo: { email: CORREO_ADMIN, password: CLAVE_ADMIN },
  });
  const tokenAdmin = sesionAdmin.datos?.access_token ?? null;
  comprobar('el admin inicia sesión y obtiene JWT', Boolean(tokenAdmin), `estado=${sesionAdmin.estado}`);

  const creadoObjetivo = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: { email: CORREO_OBJETIVO, password: CLAVE_VIEJA, email_confirm: true },
  });
  idObjetivo = creadoObjetivo.datos?.id ?? null;
  comprobar('crear el usuario objetivo (cuenta desechable)', Boolean(idObjetivo), `estado=${creadoObjetivo.estado}`);

  // Sesión previa del objetivo con la contraseña VIEJA: su refresh token debe
  // morir cuando se restablezca la contraseña.
  const sesionVieja = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    cuerpo: { email: CORREO_OBJETIVO, password: CLAVE_VIEJA },
  });
  const refreshViejo = sesionVieja.datos?.refresh_token ?? null;
  comprobar('el objetivo abre una sesión con la contraseña vieja', Boolean(refreshViejo), `estado=${sesionVieja.estado}`);

  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  if (salud === null) {
    console.log('\n  [SKIP ] el backend no responde en ' + API);
    console.log('         levántalo con: cd backend && PORT=3001 npm run dev');
    throw new Error('BACKEND_APAGADO');
  }

  // --- 1. El admin emite el primer código ---------------------------------
  console.log('\n  1. El administrador emite un código de recuperación\n');

  const emisionA = await api(`/api/v1/admin/usuarios/${idObjetivo}/restablecer`, {
    metodo: 'POST', token: tokenAdmin,
  });
  const codigoA = emisionA.datos?.codigo ?? '';
  comprobar('POST /admin/usuarios/:id/restablecer responde 2xx', emisionA.estado < 300, `estado=${emisionA.estado} ${JSON.stringify(emisionA.datos)?.slice(0, 140)}`);
  comprobar('la respuesta trae el código una sola vez', codigoA.length >= 12, `codigo=${codigoA.length} chars`);
  comprobar('el código se marca como entrega manual (no se envió por correo)', emisionA.datos?.entrega === 'manual', String(emisionA.datos?.entrega));
  comprobar('el correo de la respuesta es el del objetivo', emisionA.datos?.email === CORREO_OBJETIVO, String(emisionA.datos?.email));

  // --- 2. En la base: hash, no claro --------------------------------------
  console.log('\n  2. Lo que quedó en la base (huella, no secreto)\n');

  const enBaseA = await pedir(`/rest/v1/password_resets?user_id=eq.${idObjetivo}&select=code_hash,used_at,revoked_at,created_by&order=created_at.desc`);
  const filaA = Array.isArray(enBaseA.datos) ? enBaseA.datos[0] : null;
  comprobar('el código en claro NO está en la base', filaA?.code_hash !== codigoA && filaA?.code_hash !== normalizar(codigoA), String(filaA?.code_hash).slice(0, 16));
  comprobar('se guarda el SHA-256 del código normalizado', filaA?.code_hash === sha256(normalizar(codigoA)), `esperado=${sha256(normalizar(codigoA)).slice(0, 16)}…`);
  comprobar('la fila arranca sin usar y sin revocar', filaA?.used_at === null && filaA?.revoked_at === null, JSON.stringify({ used: filaA?.used_at, rev: filaA?.revoked_at }));
  comprobar('queda registrado qué admin lo emitió', filaA?.created_by === idAdmin, String(filaA?.created_by));

  // --- 3. Emitir otro código anula el anterior ----------------------------
  console.log('\n  3. Emitir un código nuevo anula el anterior\n');

  const emisionB = await api(`/api/v1/admin/usuarios/${idObjetivo}/restablecer`, {
    metodo: 'POST', token: tokenAdmin,
  });
  const codigoB = emisionB.datos?.codigo ?? '';
  comprobar('el segundo código también se emite', codigoB.length >= 12, `codigo=${codigoB.length} chars`);

  const revocacionA = await pedir(`/rest/v1/password_resets?code_hash=eq.${sha256(normalizar(codigoA))}&select=revoked_at,used_at`);
  comprobar('el primer código quedó revocado', revocacionA.datos?.[0]?.revoked_at !== null, JSON.stringify(revocacionA.datos?.[0]));

  const canjeA = await api('/api/v1/auth/restablecer-codigo', {
    metodo: 'POST', cuerpo: { codigo: codigoA, password: CLAVE_NUEVA },
  });
  comprobar('el código anulado NO canjea (404)', canjeA.estado === 404, `estado=${canjeA.estado}`);

  // --- 4. Canje del código vigente ----------------------------------------
  console.log('\n  4. El titular canjea el código vigente y fija su contraseña\n');

  const canjeB = await api('/api/v1/auth/restablecer-codigo', {
    metodo: 'POST', cuerpo: { codigo: codigoB, password: CLAVE_NUEVA },
  });
  comprobar('POST /auth/restablecer-codigo responde 2xx', canjeB.estado < 300, `estado=${canjeB.estado} ${JSON.stringify(canjeB.datos)?.slice(0, 140)}`);
  comprobar('la respuesta identifica al titular por correo', canjeB.datos?.email === CORREO_OBJETIVO, String(canjeB.datos?.email));

  // --- 5. Entra la nueva, no entra la vieja -------------------------------
  console.log('\n  5. La contraseña nueva entra; la vieja no\n');

  const entraNueva = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST', clave: CLAVE_ANON,
    cuerpo: { email: CORREO_OBJETIVO, password: CLAVE_NUEVA },
  });
  comprobar('inicia sesión con la contraseña NUEVA', entraNueva.estado === 200 && Boolean(entraNueva.datos?.access_token), `estado=${entraNueva.estado}`);

  const entraVieja = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST', clave: CLAVE_ANON,
    cuerpo: { email: CORREO_OBJETIVO, password: CLAVE_VIEJA },
  });
  comprobar('la contraseña VIEJA ya no entra', entraVieja.estado >= 400, `estado=${entraVieja.estado}`);

  // --- 6. Las sesiones previas quedaron cerradas --------------------------
  console.log('\n  6. La sesión previa quedó cerrada (revocación)\n');

  const refrescoViejo = await pedir('/auth/v1/token?grant_type=refresh_token', {
    metodo: 'POST', clave: CLAVE_ANON, cuerpo: { refresh_token: refreshViejo },
  });
  comprobar('el refresh token previo ya NO sirve', refrescoViejo.estado >= 400, `estado=${refrescoViejo.estado}`);

  // --- 7. Un solo uso, y sin enumeración ----------------------------------
  console.log('\n  7. El código no se reutiliza; lo inválido responde igual\n');

  const reuso = await api('/api/v1/auth/restablecer-codigo', {
    metodo: 'POST', cuerpo: { codigo: codigoB, password: `Otra!${randomBytes(9).toString('base64url')}` },
  });
  comprobar('reutilizar el código canjeado se rechaza (404)', reuso.estado === 404, `estado=${reuso.estado}`);

  const inventado = await api('/api/v1/auth/restablecer-codigo', {
    metodo: 'POST', cuerpo: { codigo: 'ZZZZ-ZZZZ-ZZZZ', password: CLAVE_NUEVA },
  });
  comprobar('un código inventado responde 404 (mismo código de error)', inventado.estado === 404, `estado=${inventado.estado}`);
  comprobar(
    'el motivo del rechazo no revela si el código existía',
    inventado.datos?.codigo === reuso.datos?.codigo,
    `inventado=${inventado.datos?.codigo} reuso=${reuso.datos?.codigo}`,
  );

  // --- 8. Auditoría sin secretos ------------------------------------------
  console.log('\n  8. Auditoría del restablecimiento (sin contraseñas)\n');

  const trazas = await pedir(`/rest/v1/auth_logs?email=eq.${CORREO_OBJETIVO}&select=estado`);
  const exitos = (trazas.datos ?? []).filter((f) => f.estado === 'SUCCESS').length;
  comprobar('auth_logs registró el acceso exitoso', exitos >= 1, `SUCCESS=${exitos}`);

  // La tabla de códigos no debe contener ni la contraseña nueva ni el código
  // en claro. Se revisa el volcado completo de las filas de este usuario.
  const volcado = await pedir(`/rest/v1/password_resets?user_id=eq.${idObjetivo}&select=*`);
  const serializado = JSON.stringify(volcado.datos ?? []);
  comprobar('password_resets no contiene la contraseña nueva', !serializado.includes(CLAVE_NUEVA));
  comprobar('password_resets no contiene ningún código en claro', !serializado.includes(codigoA) && !serializado.includes(codigoB));

  // --- 9. Límite de intentos (opcional) -----------------------------------
  if (PROBAR_LIMITE) {
    console.log('\n  9. Límite de intentos por IP (--limite)\n');
    let vio429 = false;
    for (let i = 0; i < 25; i += 1) {
      const r = await api('/api/v1/auth/restablecer-codigo', {
        metodo: 'POST', cuerpo: { codigo: 'ZZZZ-ZZZZ-ZZZZ', password: CLAVE_NUEVA },
      });
      if (r.estado === 429) { vio429 = true; console.log(`         bloqueado en el intento ${i + 1}`); break; }
    }
    comprobar('el abuso repetido acaba en 429', vio429);
  }
} catch (error) {
  if (error?.message !== 'BACKEND_APAGADO') {
    fallos += 1;
    console.error(`\n  EXCEPCIÓN NO CONTROLADA: ${error?.message ?? error}`);
  }
} finally {
  console.log('\n  Purga...');
  await purgar();
  const residuoPerfiles = await pedir('/rest/v1/profiles?email=like.humo-rec*&select=id');
  const residuoTrazas = await pedir('/rest/v1/auth_logs?email=like.humo-rec*&select=id');
  const nPerfiles = Array.isArray(residuoPerfiles.datos) ? residuoPerfiles.datos.length : -1;
  const nTrazas = Array.isArray(residuoTrazas.datos) ? residuoTrazas.datos.length : -1;
  // Los códigos caen por la clave ajena al borrar el usuario; se comprueba que
  // no queda ninguno huérfano del objetivo.
  const residuoCodigos = idObjetivo
    ? await pedir(`/rest/v1/password_resets?user_id=eq.${idObjetivo}&select=id`)
    : { datos: [] };
  const nCodigos = Array.isArray(residuoCodigos.datos) ? residuoCodigos.datos.length : -1;

  console.log(`\n  Resultado: ${ok} OK / ${fallos} fallos`);
  console.log(
    `  Residuo en la base: perfiles=${nPerfiles} trazas=${nTrazas} codigos=${nCodigos} (debe ser 0, 0 y 0)`,
  );
  process.exit(fallos === 0 && nPerfiles === 0 && nTrazas === 0 && nCodigos === 0 ? 0 : 1);
}
