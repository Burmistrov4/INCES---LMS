// TEMPORAL — frontera RLS de E-2, DOS FASES.
//
// El instrumento anterior (6.3) creaba las versiones CON EL ADMIN, y eso es justo
// lo que `0003` prohíbe: daba 403 y no quedaba ninguna fila que borrar. Aquí:
//
//   FASE A · el ASPIRANTE crea por el camino permitido (JWT real)
//   FASE B · el ADMIN intenta borrar/transicionar sobre filas REALES (JWT real)
//
// Service-role sólo para cuentas, fichas y limpieza final.

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const U = env.SUPABASE_URL, K = env.SUPABASE_SERVICE_ROLE_KEY, ANON = env.SUPABASE_ANON_KEY ?? K;
const m = Date.now(), CLAVE = 'PruebaE2-2026!';
const ahora = () => new Date().toISOString();

const restCon = (jwt) => async (ruta, opciones = {}) => {
  const r = await fetch(U + ruta, { ...opciones, headers: {
    apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json',
    Prefer: 'return=representation', ...(opciones.headers ?? {}) } });
  return { e: r.status, c: await r.json().catch(() => null) };
};
const srv = async (ruta, opciones = {}) => {
  const r = await fetch(U + ruta, { ...opciones, headers: {
    apikey: K, Authorization: `Bearer ${K}`, 'Content-Type': 'application/json',
    Prefer: 'return=representation', ...(opciones.headers ?? {}) } });
  return { e: r.status, c: await r.json().catch(() => null) };
};

const prog = (await srv('/rest/v1/programs?select=id&limit=1')).c[0].id;
/** Auth SIEMPRE con la clave anonima: es lo que espera el endpoint de token. */
const tok = async (correo) => {
  const r = await fetch(U + '/auth/v1/token?grant_type=password', { method: 'POST', headers: {
    apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: correo, password: CLAVE }) });
  const c = await r.json().catch(() => null);
  // **Abortar si no hay token.** El instrumento anterior siguió adelante con JWT
  // vacio y reporto 401 como si fueran resultados: un instrumento que no comprueba
  // su propia precondicion miente.
  if (!c?.access_token) throw new Error(`sin token para ${correo}: ${r.status} ${JSON.stringify(c).slice(0,160)}`);
  return c.access_token;
};

const auth = [], fichas = [];
async function crear(correo, rol) {
  const r = await srv('/auth/v1/admin/users', { method: 'POST',
    body: JSON.stringify({ email: correo, password: CLAVE, email_confirm: true }) });
  const uid = r.c.id; auth.push(uid);
  if (rol !== 'estudiante') await srv(`/rest/v1/profiles?id=eq.${uid}`, { method: 'PATCH',
    body: JSON.stringify({ rol, active: true }) });
  return uid;
}
async function ficha(uid, suf) {
  const r = await srv('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
    user_id: uid, cedula: '5' + String(m).slice(-5) + suf, nombres: 'F', apellidos: 'E2',
    program_id: prog, fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412',
    email: `fe${m}${suf}@semilla.invalid`, direccion: 'x', nivel_educativo: 'SECUNDARIO',
    discapacidad: false, requires_legal_tutor: false, datos_planilla: {},
  }) });
  fichas.push(r.c[0].id); return r.c[0].id;
}

const jAsp = [], jAdm = [], jDoc = [];
const F = [];
console.log('\n########## FASE A · el ASPIRANTE crea por el workflow ##########');
const uidAdm = await crear(`f4-adm-${m}@semilla.invalid`, 'admin');
const uidDoc = await crear(`f4-doc-${m}@semilla.invalid`, 'docente');
jAdm.push(await tok(`f4-adm-${m}@semilla.invalid`));
jDoc.push(await tok(`f4-doc-${m}@semilla.invalid`));

// Cuatro fichas: una por estado a mantener.
for (let i = 1; i <= 4; i++) {
  const uid = await crear(`f4-asp${i}-${m}@semilla.invalid`, 'estudiante');
  jAsp.push(await tok(`f4-asp${i}-${m}@semilla.invalid`));
  F.push(await ficha(uid, String(i)));
}
const [fEnv, fObs, fRee, fApr] = F;

const crearV = async (jwt, f, n, est) => {
  const user = restCon(jwt);
  const r = await user('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: f, numero: n, estado: est, datos_snapshot: { origen: n } }) });
  return r.c?.[0]?.id;
};
const leer = async (jwt, id) => {
  const user = restCon(jwt);
  return (await user(`/rest/v1/planilla_versiones?id=eq.${id}&select=id,estado,numero,approved_by,aprobada_at`)).c?.[0];
};
const trans = async (jwt, id, cuerpo) => {
  const user = restCon(jwt);
  return user(`/rest/v1/planilla_versiones?id=eq.${id}`, { method: 'PATCH', body: JSON.stringify(cuerpo) });
};

// ENVIADA
const vEnv = await crearV(jAsp[0], fEnv, 1, 'ENVIADA');
// OBSERVADA
const vObs = await crearV(jAsp[1], fObs, 1, 'ENVIADA');
await trans(jAdm[0], vObs, { estado: 'OBSERVADA' });
// REENVIADA
const vRee = await crearV(jAsp[2], fRee, 1, 'ENVIADA');
await trans(jAdm[0], vRee, { estado: 'OBSERVADA' });
const vRee2 = await crearV(jAsp[2], fRee, 2, 'REENVIADA');
// APROBADA
const vApr = await crearV(jAsp[3], fApr, 1, 'ENVIADA');
await trans(jAdm[0], vApr, { estado: 'APROBADA', aprobada_at: ahora(), approved_by: uidAdm });

console.log(`  v ENVIADA   ${vEnv}\n  v OBSERVADA ${vObs}\n  v REENVIADA ${vRee2}\n  v APROBADA  ${vApr}`);
for (const [n, v] of [['ENVIADA', vEnv], ['OBSERVADA', vObs], ['REENVIADA', vRee2], ['APROBADA', vApr]]) {
  const r = await leer(jAdm[0], v);
  console.log(`  verificado: ${n.padEnd(10)} -> ${r ? r.estado : '(NO EXISTE)'}`);
}

console.log('\n########## FASE B · el ADMIN intenta ##########');
console.log('--- DELETE ---');
for (const [id, n, v] of [['D1', 'ENVIADA', vEnv], ['D2', 'OBSERVADA', vObs], ['D3', 'REENVIADA', vRee2], ['D4', 'APROBADA', vApr]]) {
  const r = await restCon(jAdm[0])(`/rest/v1/planilla_versiones?id=eq.${v}`, { method: 'DELETE' });
  const sigue = await leer(jAdm[0], v);
  console.log(`  ${id} DELETE ${n.padEnd(10)} -> ${r.e}   ¿sigue existiendo? ${sigue ? 'SÍ (' + sigue.estado + ')' : 'NO'}`);
}

console.log('--- TRANSICIONES (O) ---');
const O = async (id, v, destino, esperado, extra = {}) => {
  const antes = await leer(jAdm[0], v);
  const r = await trans(jAdm[0], v, { estado: destino, ...extra });
  const desp = await leer(jAdm[0], v);
  console.log(`  ${id} ${antes?.estado} -> ${destino}: ${r.e}   persistido: ${desp?.estado}   ${desp?.estado === esperado ? 'OK' : 'INESPERADO'}`);
};
await O('O1', vEnv, 'OBSERVADA', 'OBSERVADA');
await O('O2', vObs, 'OBSERVADA', 'OBSERVADA');
await O('O3', vRee2, 'OBSERVADA', 'REENVIADA');
await O('O4', vApr, 'OBSERVADA', 'APROBADA');

console.log('--- AUDITORÍA DE APROBACIÓN (R) ---');
const R = async (id, v, extra) => {
  const antes = await leer(jAdm[0], v);
  const r = await trans(jAdm[0], v, extra);
  const desp = await leer(jAdm[0], v);
  const cambio = JSON.stringify(antes) !== JSON.stringify(desp);
  console.log(`  ${id} ${r.e}   ¿cambió la fila? ${cambio ? 'SÍ ← BYPASS' : 'no'}`);
  if (cambio) console.log(`      antes: ${JSON.stringify(antes)}\n      después: ${JSON.stringify(desp)}`);
};
await R('R1', vApr, { estado: 'APROBADA' });
await R('R2', vApr, { approved_by: uidDoc });
await R('R3', vApr, { aprobada_at: ahora() });
await R('R4', vApr, { approved_by: uidDoc, aprobada_at: ahora() });

console.log('\n########## FASE H · LIMPIEZA ##########');
console.log(`  observaciones: ${(await srv('/rest/v1/planilla_observaciones?version_id=not.is.null', { method: 'DELETE' })).e}`);
for (const f of fichas) console.log(`  versiones ficha: ${(await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${f}`, { method: 'DELETE' })).e}`);
for (const f of fichas) console.log(`  ficha: ${(await srv(`/rest/v1/aspirantes?id=eq.${f}`, { method: 'DELETE' })).e}`);
for (const a of auth) console.log(`  auth: ${(await srv(`/auth/v1/admin/users/${a}`, { method: 'DELETE' })).e}`);
