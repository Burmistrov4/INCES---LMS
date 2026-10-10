// TEMPORAL — audita qué puede fabricar/borrar un ADMIN por PostgREST.
//
// El agujero que se busca es el mismo que el auto-ascenso del aspirante, pero del
// otro lado: si el admin puede INSERTAR una APROBADA o BORRAR el historial por
// PostgREST, el workflow no está garantizado por la BD.

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const U = env.SUPABASE_URL, K = env.SUPABASE_SERVICE_ROLE_KEY, ANON = env.SUPABASE_ANON_KEY ?? K;
const m = Date.now(), CLAVE = 'PruebaE2-2026!';

const srv = async (r, o = {}) => { const x = await fetch(U + r, { ...o, headers: {
  apikey: K, Authorization: `Bearer ${K}`, 'Content-Type': 'application/json',
  Prefer: 'return=representation', ...(o.headers ?? {}) } });
  return { e: x.status, c: await x.json().catch(() => null) }; };
/** Con el JWT del admin — esto es lo que prueba la RLS. */
const adm = async (jwt, r, o = {}) => { const x = await fetch(U + r, { ...o, headers: {
  apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json',
  Prefer: 'return=representation', ...(o.headers ?? {}) } });
  return { e: x.status, c: await x.json().catch(() => null) }; };

const prog = (await srv('/rest/v1/programs?select=id&limit=1')).c[0].id;
const aAsp = await srv('/auth/v1/admin/users', { method: 'POST', body: JSON.stringify({
  email: `by-asp-${m}@semilla.invalid`, password: CLAVE, email_confirm: true }) });
const aAdm = await srv('/auth/v1/admin/users', { method: 'POST', body: JSON.stringify({
  email: `by-adm-${m}@semilla.invalid`, password: CLAVE, email_confirm: true }) });
const uidAsp = aAsp.c.id, uidAdm = aAdm.c.id;
await srv(`/rest/v1/profiles?id=eq.${uidAdm}`, { method: 'PATCH', body: JSON.stringify({ rol: 'admin', active: true }) });

const ficha = (await srv('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
  user_id: uidAsp, cedula: '6' + String(m).slice(-6), nombres: 'B', apellidos: 'B', program_id: prog,
  fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412', email: `fb${m}@semilla.invalid`,
  direccion: 'x', nivel_educativo: 'SECUNDARIO', discapacidad: false,
  requires_legal_tutor: false, datos_planilla: {},
}) })).c[0].id;

const tok = async (c) => (await srv('/auth/v1/token?grant_type=password', { method: 'POST',
  headers: { apikey: ANON }, body: JSON.stringify({ email: c, password: CLAVE }) })).c.access_token;
const jAdm = await tok(`by-adm-${m}@semilla.invalid`);
const ahora = new Date().toISOString();

const ins = (n, est, extra = {}) => adm(jAdm, '/rest/v1/planilla_versiones', { method: 'POST',
  body: JSON.stringify({ aspirante_id: ficha, numero: n, estado: est, datos_snapshot: {}, ...extra }) });
const ver = async (n) => (await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${ficha}&numero=eq.${n}&select=id,estado`)).c;

const linea = (id, desc, r, esperado) => {
  const ok = r.e === esperado;
  console.log(`  ${ok ? 'PASS' : 'FALLA'}  ${id} ${desc} -> ${r.e} (esperado ${esperado})`);
  return ok;
};

console.log('\n########## 1. INSERT DIRECTO DEL ADMIN ##########');
linea('A1', 'INSERT ENVIADA            ', await ins(1, 'ENVIADA'), 201);
linea('A2', 'INSERT OBSERVADA          ', await ins(9, 'OBSERVADA'), 201);
linea('A3', 'INSERT REENVIADA          ', await ins(8, 'REENVIADA'), 201);
linea('A4', 'INSERT APROBADA completa  ', await ins(7, 'APROBADA', { aprobada_at: ahora, approved_by: uidAdm }), 201);
linea('A5', 'INSERT APROBADA incompleta', await ins(6, 'APROBADA'), 400);
linea('A6', 'INSERT numero arbitrario  ', await ins(99, 'ENVIADA'), 201);
linea('A7', 'INSERT REENVIADA como v1  ', await ins(50, 'REENVIADA'), 201);
linea('A8', 'INSERT v2 REENVIADA sin OBSERVADA', await ins(2, 'REENVIADA'), 201);

console.log('\n  --- filas realmente persistidas ---');
for (const n of [1, 9, 8, 7, 6, 99, 50, 2]) {
  const v = await ver(n);
  console.log(`    numero=${String(n).padEnd(3)} -> ${v.length ? v[0].estado : '(no existe)'}`);
}

console.log('\n########## 2. DELETE DEL HISTORIAL ##########');
for (const [id, n] of [['D1', 1], ['D2', 9], ['D3', 8], ['D4', 7]]) {
  const r = await adm(jAdm, `/rest/v1/planilla_versiones?aspirante_id=eq.${ficha}&numero=eq.${n}`, { method: 'DELETE' });
  const v = await ver(n);
  console.log(`  ${id} DELETE numero=${n} -> ${r.e}   ¿sigue existiendo? ${v.length ? 'SÍ' : 'NO'}`);
}

console.log('\n########## 3. OBSERVACIONES DEL ADMIN ##########');
const v1 = await ver(1);
if (v1.length) {
  const o = await adm(jAdm, '/rest/v1/planilla_observaciones', { method: 'POST', body: JSON.stringify({
    version_id: v1[0].id, observada_por: uidAdm, motivo: 'prueba' }) });
  console.log(`  O1 admin observa una ENVIADA -> ${o.e} (201 = permitido)`);
}

console.log('\n########## LIMPIEZA ##########');
console.log(`  versiones: ${(await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${ficha}`, { method: 'DELETE' })).e}`);
console.log(`  ficha:     ${(await srv(`/rest/v1/aspirantes?id=eq.${ficha}`, { method: 'DELETE' })).e}`);
console.log(`  auth asp:  ${(await srv(`/auth/v1/admin/users/${uidAsp}`, { method: 'DELETE' })).e}`);
console.log(`  auth adm:  ${(await srv(`/auth/v1/admin/users/${uidAdm}`, { method: 'DELETE' })).e}`);
