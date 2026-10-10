// TEMPORAL — mide B3, B10 y B11 por HTTP real.
//
// Los tres quedaron sin medir en la Fase 0.6. Ninguno necesita código nuevo: son
// escenarios del workflow con identidades y estados distintos.
//
//   B3  enviar SIN ficha            → el contrato dice 404 SIN_FICHA
//   B10 aprobar una ENVIADA         → el contrato dice 200 APROBADA
//   B11 aprobar una REENVIADA       → el contrato dice 200 APROBADA
//
// La planilla completa necesita los 13 obligatorios del catálogo — incluido
// `curso_seleccionado`, que la migración d14 quitó como COLUMNA y sigue siendo
// obligatorio en el CATÁLOGO. Sin él, el envío da 422 y B10/B11 no se miden.

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
const api = (jwt, ruta, o = {}) => fetch(API + ruta, { ...o, headers: {
  Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json', ...(o.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

async function tok(correo) {
  const r = await fetch(U + '/auth/v1/token?grant_type=password', { method: 'POST', headers: {
    apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: correo, password: CLAVE }) });
  const c = await r.json().catch(() => null);
  if (!c?.access_token) throw new Error(`PRECONDICIÓN: sin token ${correo}`);
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
async function ficha(uid, suf, completa) {
  const r = await srv('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
    user_id: uid, cedula: '1' + String(m).slice(-5) + suf, nombres: 'C', apellidos: 'Tres',
    program_id: prog, fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412',
    email: `ft${m}${suf}@semilla.invalid`, direccion: 'x', nivel_educativo: 'SECUNDARIO',
    discapacidad: false, requires_legal_tutor: false,
    datos_planilla: completa ? {
      primer_nombre: 'ANA', primer_apellido: 'PRUEBA', cedula: '1' + String(m).slice(-5) + suf,
      nacionalidad: 'V', fecha_nac: '2000-01-01', sexo: 'F', estado: 'CARABOBO',
      municipio: 'VALENCIA', direccion: 'Calle 1', telefono: '04120000000',
      email: `pl${m}${suf}@semilla.invalid`, nivel_educativo: 'SECUNDARIO',
      curso_seleccionado: prog,
    } : {},
  }) });
  if (!r.c?.[0]?.id) throw new Error(`PRECONDICIÓN: ficha ${suf}: ${r.e} ${JSON.stringify(r.c).slice(0,140)}`);
  fichas.push(r.c[0].id); return r.c[0].id;
}
const ver = async (id) => (await srv(`/rest/v1/planilla_versiones?id=eq.${id}&select=id,estado,numero`)).c?.[0];
const res = [];
const nota = (caso, esperado, r, extra) => {
  const ok = r.e === esperado;
  res.push({ caso, esperado, real: r.e, ok });
  console.log(`  ${ok ? 'PASS' : 'FALLA'}  ${caso.padEnd(34)} HTTP ${r.e} (esp. ${esperado})  ${extra ?? ''}`);
  if (!ok) console.log(`        codigo=${r.c?.error?.codigo ?? '-'}  mensaje=${String(r.c?.error?.mensaje ?? '').slice(0,90)}`);
};

const uAdm = await crear(`b-adm-${m}@semilla.invalid`, 'admin');
const jAdm = await tok(`b-adm-${m}@semilla.invalid`);

console.log('\n########## B3 · enviar SIN ficha ##########');
{
  const u = await crear(`b-sinf-${m}@semilla.invalid`, 'estudiante');
  const j = await tok(`b-sinf-${m}@semilla.invalid`);   // SIN ficha a propósito
  nota('B3 enviar sin ficha', 404, await api(j, '/api/v1/yo/planilla/enviar', { method: 'POST', body: '{}' }));
}

console.log('\n########## B10 · aprobar ENVIADA ##########');
{
  const u = await crear(`b-env-${m}@semilla.invalid`, 'estudiante');
  const j = await tok(`b-env-${m}@semilla.invalid`);
  await ficha(u, '1', true);
  const env = await api(j, '/api/v1/yo/planilla/enviar', { method: 'POST', body: '{}' });
  console.log(`  envío previo: HTTP ${env.e}  version=${env.c?.version?.id ? 'sí' : 'no'}`);
  if (!env.c?.version?.id) { console.log('  → sin versión, B10 no se puede medir'); }
  else {
    const v = env.c.version.id;
    const antes = (await ver(v))?.estado;
    const r = await api(jAdm, `/api/v1/inscripcion/planilla/${v}/aprobar`, { method: 'POST', body: '{}' });
    const d = await ver(v);
    nota('B10 aprobar ENVIADA', 200, r, `estado ${antes} → ${d?.estado}`);
  }
}

console.log('\n########## B11 · aprobar REENVIADA ##########');
{
  const u = await crear(`b-ree-${m}@semilla.invalid`, 'estudiante');
  const j = await tok(`b-ree-${m}@semilla.invalid`);
  const f = await ficha(u, '2', true);
  const env = await api(j, '/api/v1/yo/planilla/enviar', { method: 'POST', body: '{}' });
  const v1 = env.c?.version?.id;
  console.log(`  envío: HTTP ${env.e}  v1=${v1 ? 'sí' : 'no'}`);
  if (!v1) console.log('  → sin v1, B11 no se puede medir');
  else {
    const obs = await api(jAdm, `/api/v1/inscripcion/planilla/${v1}/observar`, { method: 'POST',
      body: JSON.stringify({ motivo: 'corregir' }) });
    console.log(`  observar: HTTP ${obs.e}  estado=${(await ver(v1))?.estado}`);
    const ree = await api(j, '/api/v1/yo/planilla/reenviar', { method: 'POST', body: '{}' });
    const v2 = ree.c?.version?.id;
    console.log(`  reenviar: HTTP ${ree.e}  v2=${v2 ? 'sí' : 'no'}  estado=${v2 ? (await ver(v2))?.estado : '-'}`);
    if (v2) {
      const antes = (await ver(v2))?.estado;
      const r = await api(jAdm, `/api/v1/inscripcion/planilla/${v2}/aprobar`, { method: 'POST', body: '{}' });
      const d = await ver(v2);
      nota('B11 aprobar REENVIADA', 200, r, `estado ${antes} → ${d?.estado}`);
    } else { console.log('  → sin v2, B11 no se puede medir'); }
  }
}

const fallos = res.filter((r) => !r.ok);
console.log(`\n########## TOTAL: ${res.length - fallos.length}/${res.length} PASS ##########`);

console.log('\n########## LIMPIEZA ##########');
for (const f of fichas) await srv(`/rest/v1/planilla_observaciones?version_id=in.(select id from planilla_versiones where aspirante_id=eq.${f})`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${f}`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/aspirantes?id=eq.${f}`, { method: 'DELETE' });
for (const a of auth) await srv(`/auth/v1/admin/users/${a}`, { method: 'DELETE' });
console.log(`  ${fichas.length} fichas · ${auth.length} cuentas`);

// Regresión: un fallo de cualquiera de B3/B10/B11 debe producir exit code != 0.
if (fallos.length) process.exitCode = 1;
