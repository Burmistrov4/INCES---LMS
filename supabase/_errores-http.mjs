// TEMPORAL — mide el camino REAL del error por HTTP.
//
// El punto decisivo: distinguir el `23514` de `validar_planilla()` del `23514` de
// una transición ilegal. Si el error trae información ESTRUCTURAL que los separa,
// el mapeo por contexto es innecesario; si no, es obligatorio.
//
// Dos identidades, otra vez: `srv()` (fixtures/verificación) y `api(jwt)` (el
// llamante). Aborta si una precondición falla.

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const U = env.SUPABASE_URL, K = env.SUPABASE_SERVICE_ROLE_KEY, ANON = env.SUPABASE_ANON_KEY ?? K;
const API = 'http://127.0.0.1:3001';
const m = Date.now(), CLAVE = 'PruebaE2-2026!';

const srv = (r, o = {}) => fetch(U + r, { ...o, headers: {
  apikey: K, Authorization: `Bearer ${K}`, 'Content-Type': 'application/json',
  Prefer: 'return=representation', ...(o.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

/** Contra el backend. `crudo` permite mandar un cuerpo sin parsear. */
const api = (jwt, ruta, o = {}) => fetch(API + ruta, { ...o, headers: {
  Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json', ...(o.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

async function tok(correo) {
  const r = await fetch(U + '/auth/v1/token?grant_type=password', { method: 'POST', headers: {
    apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: correo, password: CLAVE }) });
  const c = await r.json().catch(() => null);
  if (!c?.access_token) throw new Error(`PRECONDICIÓN: sin token ${correo}: ${r.status}`);
  return c.access_token;
}

const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
if (salud !== 200) throw new Error(`PRECONDICIÓN: backend no responde (${salud})`);
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
    user_id: uid, cedula: '2' + String(m).slice(-5) + suf, nombres: 'E', apellidos: 'Err',
    program_id: prog, fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412',
    email: `fe${m}${suf}@semilla.invalid`, direccion: 'x', nivel_educativo: 'SECUNDARIO',
    discapacidad: false, requires_legal_tutor: false, datos_planilla: {},
  }) });
  if (!r.c?.[0]?.id) throw new Error(`PRECONDICIÓN: ficha ${suf}: ${r.e} ${JSON.stringify(r.c).slice(0,140)}`);
  fichas.push(r.c[0].id); return r.c[0].id;
}
const muestra = (r) => JSON.stringify(r.c).slice(0, 320);

const uAdm = await crear(`e-adm-${m}@semilla.invalid`, 'admin');
const jAdm = await tok(`e-adm-${m}@semilla.invalid`);
const uA = await crear(`e-a-${m}@semilla.invalid`, 'estudiante');
const jA = await tok(`e-a-${m}@semilla.invalid`);
const fA = await ficha(uA, '1');
const uB = await crear(`e-b-${m}@semilla.invalid`, 'estudiante');
const jB = await tok(`e-b-${m}@semilla.invalid`);
const fB = await ficha(uB, '2');

console.log('\n########## A1 · PLANILLA INCOMPLETA (el caso que decide) ##########');
{
  const antes = (await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${fA}&select=id`)).c?.length ?? 0;
  const r = await api(jA, '/api/v1/yo/planilla/enviar', { method: 'POST', body: '{}' });
  const despues = (await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${fA}&select=id`)).c?.length ?? 0;
  console.log(`  HTTP ${r.e}`);
  console.log(`  codigo : ${r.c?.error?.codigo ?? '(sin codigo)'}`);
  console.log(`  mensaje: ${String(r.c?.error?.mensaje ?? '').slice(0, 160)}`);
  console.log(`  detalles: ${JSON.stringify(r.c?.error?.detalles ?? null).slice(0, 200)}`);
  console.log(`  versiones antes=${antes} despues=${despues}  ${despues === antes ? 'NO creó versión ✓' : 'CREÓ VERSIÓN ✗'}`);
}

console.log('\n########## A4 · CUERPO JSON VACÍO ##########');
{
  const r = await fetch(`${API}/api/v1/yo/planilla/enviar`, { method: 'POST',
    headers: { Authorization: `Bearer ${jA}`, 'Content-Type': 'application/json' } });
  const c = await r.json().catch(() => null);
  // `fetch` crudo: el status es `r.status`, NO `r.e` — ese campo es de mis
  // envoltorios. Leerlo mal daba `undefined` y una medicion invalida.
  console.log(`  HTTP ${r.status}`);
  console.log(`  codigo : ${c?.error?.codigo ?? '(sin codigo)'}`);
  console.log(`  mensaje: ${String(c?.error?.mensaje ?? '').slice(0, 140)}`);
}

console.log('\n########## A3 · TRANSICIONES (HTTP real) ##########');
{
  // ENVIADA completa para poder transicionar.
  await srv(`/rest/v1/aspirantes?id=eq.${fB}`, { method: 'PATCH', body: JSON.stringify({
    datos_planilla: { primer_nombre: 'ANA', primer_apellido: 'PRUEBA', cedula: '29999999',
      fecha_nac: '2000-01-01', sexo: 'F', estado_civil: 'SOLTERO', nacionalidad: 'V',
      estado: 'CARABOBO', municipio: 'VALENCIA', parroquia: 'LA ISABELICA', direccion: 'Calle 1',
      telefono: '04120000000', email: `c${m}@semilla.invalid`, nivel_educativo: 'SECUNDARIO', curso_seleccionado: prog } }) });
  const envio = await api(jB, '/api/v1/yo/planilla/enviar', { method: 'POST', body: '{}' });
  const v = envio.c?.version?.id;
  console.log(`  envío previo: HTTP ${envio.e}  version=${v ? 'sí' : 'no'}`);
  if (!v) { console.log('  → sin versión, no puedo medir transiciones'); }
  else {
    const obs = (destino) => api(jAdm, `/api/v1/inscripcion/planilla/${v}/observar`, { method: 'POST',
      body: JSON.stringify({ motivo: 'prueba' }) });
    const apr = () => api(jAdm, `/api/v1/inscripcion/planilla/${v}/aprobar`, { method: 'POST', body: '{}' });
    const est = async () => (await srv(`/rest/v1/planilla_versiones?id=eq.${v}&select=estado`)).c?.[0]?.estado;

    const r1 = await obs();
    console.log(`  1 ENVIADA→OBSERVADA   HTTP ${r1.e}  (esp. 200)   estado=${await est()}`);
    const r2 = await obs();
    console.log(`  2 OBSERVADA→OBSERVADA HTTP ${r2.e}  (esp. 409)   estado=${await est()}   codigo=${r2.c?.error?.codigo ?? '-'}`);
    const r7 = await apr();
    console.log(`  7 OBSERVADA→APROBADA  HTTP ${r7.e}  (esp. 409)   estado=${await est()}   codigo=${r7.c?.error?.codigo ?? '-'}`);
  }
}

console.log('\n########## A5 · REGRESIÓN ##########');
{
  const r404 = await fetch(`${API}/api/v1/no-existe-esta-ruta`, { headers: { Authorization: `Bearer ${jA}` } });
  console.log(`  ruta inexistente          HTTP ${r404.status}  (esp. 404)`);
  const r401 = await fetch(`${API}/api/v1/yo/planilla/versiones`);
  console.log(`  sin token                 HTTP ${r401.status}  (esp. 401)`);
  const r403 = await api(jA, `/api/v1/inscripcion/planilla/${fB}/observar`, { method: 'POST',
    body: JSON.stringify({ motivo: 'x' }) });
  console.log(`  alumno → ruta admin       HTTP ${r403.e}  (esp. 403)  codigo=${r403.c?.error?.codigo ?? '-'}`);
  const rList = await api(jB, '/api/v1/yo/planilla/versiones');
  console.log(`  listar propias            HTTP ${rList.e}  (esp. 200)`);
}

console.log('\n########## LIMPIEZA ##########');
for (const f of fichas) await srv(`/rest/v1/planilla_observaciones?version_id=in.(select id from planilla_versiones where aspirante_id=eq.${f})`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${f}`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/aspirantes?id=eq.${f}`, { method: 'DELETE' });
for (const a of auth) await srv(`/auth/v1/admin/users/${a}`, { method: 'DELETE' });
console.log(`  ${fichas.length} fichas · ${auth.length} cuentas`);
