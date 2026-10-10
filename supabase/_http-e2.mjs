// TEMPORAL — integración JWT REAL contra las RUTAS HTTP del backend.
//
// Diferencia con `_frontera2.mjs`: allí las transiciones iban por PostgREST
// directo; aquí pasan por `/api/v1/...`, que es lo que un cliente real usa.
//
// Dos identidades, otra vez:
//   srv()          → apikey SERVICE + Bearer SERVICE   (sólo fixtures y verificación)
//   api(jwt, ...)  → al BACKEND, con el JWT del actor  (esto es lo que se mide)

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const U = env.SUPABASE_URL, K = env.SUPABASE_SERVICE_ROLE_KEY, ANON = env.SUPABASE_ANON_KEY ?? K;
const API = 'http://127.0.0.1:3001';
const m = Date.now(), CLAVE = 'PruebaE2-2026!';

const srv = (ruta, op = {}) => fetch(U + ruta, { ...op, headers: {
  apikey: K, Authorization: `Bearer ${K}`, 'Content-Type': 'application/json',
  Prefer: 'return=representation', ...(op.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

/** Contra el BACKEND, con el JWT del actor. */
const api = (jwt, ruta, op = {}) => fetch(API + ruta, { ...op, headers: {
  Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json', ...(op.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

async function tok(correo) {
  const r = await fetch(U + '/auth/v1/token?grant_type=password', { method: 'POST', headers: {
    apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: correo, password: CLAVE }) });
  const c = await r.json().catch(() => null);
  if (!c?.access_token) throw new Error(`PRECONDICIÓN: sin token para ${correo}: ${r.status}`);
  return c.access_token;
}

const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
if (salud !== 200) throw new Error(`PRECONDICIÓN: el backend no responde en ${API} (${salud})`);
const prog = (await srv('/rest/v1/programs?select=id&limit=1')).c?.[0]?.id;
if (!prog) throw new Error('PRECONDICIÓN: no hay programa');

const auth = [], fichas = [];
async function crear(correo, rol) {
  const r = await srv('/auth/v1/admin/users', { method: 'POST',
    body: JSON.stringify({ email: correo, password: CLAVE, email_confirm: true }) });
  if (!r.c?.id) throw new Error(`PRECONDICIÓN: no creé ${correo}`);
  auth.push(r.c.id);
  if (rol !== 'estudiante') await srv(`/rest/v1/profiles?id=eq.${r.c.id}`, { method: 'PATCH',
    body: JSON.stringify({ rol, active: true }) });
  return r.c.id;
}
async function ficha(uid, suf) {
  const r = await srv('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
    user_id: uid, cedula: '3' + String(m).slice(-5) + suf, nombres: 'H', apellidos: 'E2',
    program_id: prog, fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412',
    email: `fh${m}${suf}@semilla.invalid`, direccion: 'x', nivel_educativo: 'SECUNDARIO',
    discapacidad: false, requires_legal_tutor: false, datos_planilla: {},
  }) });
  if (!r.c?.[0]?.id) throw new Error(`PRECONDICIÓN: ficha ${suf}: ${r.e} ${JSON.stringify(r.c).slice(0,140)}`);
  fichas.push(r.c[0].id); return r.c[0].id;
}

const uAdm = await crear(`h-adm-${m}@semilla.invalid`, 'admin');
const jAdm = await tok(`h-adm-${m}@semilla.invalid`);
const uDoc = await crear(`h-doc-${m}@semilla.invalid`, 'docente');
const jDoc = await tok(`h-doc-${m}@semilla.invalid`);

const uA = await crear(`h-a-${m}@semilla.invalid`, 'estudiante');
const jA = await tok(`h-a-${m}@semilla.invalid`);
const fA = await ficha(uA, '1');
const uB = await crear(`h-b-${m}@semilla.invalid`, 'estudiante');
const jB = await tok(`h-b-${m}@semilla.invalid`);
const fB = await ficha(uB, '2');

const filas = [];
const anota = (caso, esperado, r, extra = '') => {
  filas.push({ caso, esperado, real: `${r.e} ${extra}`.trim(), ok: r.e === esperado });
  console.log(`  ${r.e === esperado ? 'PASS' : 'FALLA'}  ${caso.padEnd(24)} HTTP ${r.e} (esp. ${esperado})  ${extra}`);
};
const ver = async (id) => (await srv(`/rest/v1/planilla_versiones?id=eq.${id}&select=id,estado,numero,approved_by,aprobada_at,datos_snapshot`)).c?.[0];
const obsDe = async (id) => (await srv(`/rest/v1/planilla_observaciones?version_id=eq.${id}&select=id,observada_por,motivo`)).c ?? [];

// Datos completos: el catálogo exige los obligatorios.
const COMPLETA = { primer_nombre: 'ANA', primer_apellido: 'PRUEBA', cedula: '30000001',
  fecha_nac: '2000-01-01', sexo: 'F', estado_civil: 'SOLTERO', nacionalidad: 'V',
  estado: 'CARABOBO', municipio: 'VALENCIA', parroquia: 'LA ISABELICA', direccion: 'Calle 1',
  telefono: '04120000000', email: `c${m}@semilla.invalid`, nivel_educativo: 'SECUNDARIO' };

console.log('\n########## B1 · alumno envía ##########');
await srv(`/rest/v1/aspirantes?id=eq.${fA}`, { method: 'PATCH', body: JSON.stringify({ datos_planilla: COMPLETA }) });
const b1 = await api(jA, '/api/v1/yo/planilla/enviar', { method: 'POST' });
anota('B1 send', 200, b1, b1.c?.version?.estado ?? '');
const v1 = b1.c?.version?.id;

console.log('\n########## B2 · alumno lista ##########');
const b2 = await api(jA, '/api/v1/yo/planilla/versiones');
anota('B2 list', 200, b2, `n=${Array.isArray(b2.c?.versiones) ? b2.c.versiones.length : '?'}`);

console.log('\n########## B3 · admin observa ##########');
const b3 = await api(jAdm, `/api/v1/inscripcion/planilla/${v1}/observar`, { method: 'POST',
  body: JSON.stringify({ motivo: 'Corrija el dato indicado para continuar.' }) });
anota('B3 observe', 200, b3);
{
  const v = await ver(v1), o = await obsDe(v1);
  console.log(`      estado=${v?.estado}  observaciones=${o.length}  observada_por=${o[0]?.observada_por === uAdm ? 'ADMIN ✓' : o[0]?.observada_por}`);
}

console.log('\n########## B4 · alumno reenvía ##########');
await srv(`/rest/v1/aspirantes?id=eq.${fA}`, { method: 'PATCH', body: JSON.stringify({
  datos_planilla: { ...COMPLETA, direccion: 'Calle 42 (corregida)' } }) });
const b4 = await api(jA, '/api/v1/yo/planilla/reenviar', { method: 'POST' });
anota('B4 resend', 200, b4, b4.c?.version?.estado ?? '');
const v2 = b4.c?.version?.id;

console.log('\n########## B5 · admin aprueba ##########');
const b5 = await api(jAdm, `/api/v1/inscripcion/planilla/${v2}/aprobar`, { method: 'POST' });
anota('B5 approve', 200, b5);
{
  const v = await ver(v2);
  console.log(`      estado=${v?.estado}  approved_by=${v?.approved_by === uAdm ? 'ADMIN ✓' : v?.approved_by}  aprobada_at=${v?.aprobada_at ? 'sí ✓' : 'null'}`);
}

console.log('\n########## C · negativos ##########');
anota('B6 alumno observa', 403, await api(jA, `/api/v1/inscripcion/planilla/${v1}/observar`, { method: 'POST', body: JSON.stringify({ motivo: 'x' }) }));
anota('B7 docente observa', 403, await api(jDoc, `/api/v1/inscripcion/planilla/${v1}/observar`, { method: 'POST', body: JSON.stringify({ motivo: 'x' }) }));
anota('B10 alumno aprueba', 403, await api(jA, `/api/v1/inscripcion/planilla/${v1}/aprobar`, { method: 'POST' }));
anota('B8 observar no-ENVIADA', 409, await api(jAdm, `/api/v1/inscripcion/planilla/${v2}/observar`, { method: 'POST', body: JSON.stringify({ motivo: 'x' }) }));
anota('B9 motivo vacío', 422, await api(jAdm, `/api/v1/inscripcion/planilla/${v2}/observar`, { method: 'POST', body: JSON.stringify({ motivo: '   ' }) }));
anota('reenviar ENVIADA', 409, await api(jA, '/api/v1/yo/planilla/reenviar', { method: 'POST' }));
anota('B11 B ve solo lo suyo', 200, await api(jB, '/api/v1/yo/planilla/versiones'), 'n=0 esperado');
anota('E admin A/B mismatch', 403, await api(jAdm, '/api/v1/inscripcion/planilla/' + v1 + '/observar', { method: 'POST', body: JSON.stringify({ motivo: 'x' }) }));

console.log('\n########## B12 · DELETE administrativo ##########');
{
  const r = await srv(`/rest/v1/planilla_versiones?id=eq.${v1}`, { method: 'DELETE' });
  const sigue = await ver(v1);
  console.log(`  DELETE -> ${r.e}   ¿sigue existiendo? ${sigue ? 'SÍ (' + sigue.estado + ') ✓' : 'NO ✗'}`);
}

const fallos = filas.filter((f) => !f.ok);
console.log(`\n########## RESUMEN: ${filas.length - fallos.length}/${filas.length} ##########`);
for (const f of fallos) console.log(`  FALLA ${f.caso}: ${f.real} (esperaba ${f.esperado})`);

console.log('\n########## LIMPIEZA ##########');
for (const f of fichas) await srv(`/rest/v1/planilla_observaciones?version_id=in.(select id from planilla_versiones where aspirante_id=eq.${f})`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${f}`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/aspirantes?id=eq.${f}`, { method: 'DELETE' });
for (const a of auth) await srv(`/auth/v1/admin/users/${a}`, { method: 'DELETE' });
console.log(`  ${fichas.length} fichas · ${auth.length} cuentas`);
