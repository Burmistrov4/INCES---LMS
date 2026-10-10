// TEMPORAL — frontera RLS de E-2, con DOS IDENTIDADES SEPARADAS.
//
// La causa de los tres fallos anteriores: una sola función servía dos patrones:
//   service-role:  apikey: <SERVICE_KEY>  +  Bearer <SERVICE_KEY>
//   usuario:       apikey: <ANON_KEY>     +  Bearer <JWT del usuario>
// Al arreglar uno se rompía el otro. Aquí son DOS funciones, y el instrumento
// ABORTA si una precondición falla — el anterior siguió con JWT vacío y reportó
// 401 como si fueran resultados.

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const U = env.SUPABASE_URL, K = env.SUPABASE_SERVICE_ROLE_KEY, ANON = env.SUPABASE_ANON_KEY ?? K;
const PAT = env.SUPABASE_ACCESS_TOKEN;
const REF = U.replace(/^https:\/\//, '').split('.')[0];
const m = Date.now(), CLAVE = 'PruebaE2-2026!';
const ahora = () => new Date().toISOString();

const srv = (ruta, op = {}) => fetch(U + ruta, { ...op, headers: {
  apikey: K, Authorization: `Bearer ${K}`, 'Content-Type': 'application/json',
  Prefer: 'return=representation', ...(op.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

const restCon = (jwt) => (ruta, op = {}) => fetch(U + ruta, { ...op, headers: {
  apikey: ANON, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json',
  Prefer: 'return=representation', ...(op.headers ?? {}) } })
  .then(async (r) => ({ e: r.status, c: await r.json().catch(() => null) }));

async function sql(consulta) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${PAT}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: consulta }) });
  return { e: r.status, c: await r.json().catch(() => null) };
}

async function tok(correo) {
  const r = await fetch(U + '/auth/v1/token?grant_type=password', { method: 'POST', headers: {
    apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: correo, password: CLAVE }) });
  const c = await r.json().catch(() => null);
  if (!c?.access_token) throw new Error(`PRECONDICIÓN: sin token para ${correo}: ${r.status} ${JSON.stringify(c).slice(0,160)}`);
  return c.access_token;
}

const prog = (await srv('/rest/v1/programs?select=id&limit=1')).c?.[0]?.id;
if (!prog) throw new Error('PRECONDICIÓN: no hay ningún programa');

const auth = [], fichas = [];
async function crear(correo, rol) {
  const r = await srv('/auth/v1/admin/users', { method: 'POST',
    body: JSON.stringify({ email: correo, password: CLAVE, email_confirm: true }) });
  if (!r.c?.id) throw new Error(`PRECONDICIÓN: no creé ${correo}: ${r.e} ${JSON.stringify(r.c).slice(0,160)}`);
  auth.push(r.c.id);
  if (rol !== 'estudiante') await srv(`/rest/v1/profiles?id=eq.${r.c.id}`, { method: 'PATCH',
    body: JSON.stringify({ rol, active: true }) });
  return r.c.id;
}
async function ficha(uid, suf) {
  const r = await srv('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
    user_id: uid, cedula: '4' + String(m).slice(-5) + suf, nombres: 'F', apellidos: 'E2',
    program_id: prog, fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412',
    email: `ff${m}${suf}@semilla.invalid`, direccion: 'x', nivel_educativo: 'SECUNDARIO',
    discapacidad: false, requires_legal_tutor: false, datos_planilla: {},
  }) });
  if (!r.c?.[0]?.id) throw new Error(`PRECONDICIÓN: no creé la ficha ${suf}: ${r.e} ${JSON.stringify(r.c).slice(0,160)}`);
  fichas.push(r.c[0].id); return r.c[0].id;
}

const uAdm = await crear(`x-adm-${m}@semilla.invalid`, 'admin');
const adm = restCon(await tok(`x-adm-${m}@semilla.invalid`));

/** Aspirante nuevo con su v1 ENVIADA creada POR ÉL. */
async function nuevo(suf) {
  const u = await crear(`x-a${suf}-${m}@semilla.invalid`, 'estudiante');
  const j = await tok(`x-a${suf}-${m}@semilla.invalid`);
  const f = await ficha(u, suf);
  const r = await restCon(j)('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: f, numero: 1, estado: 'ENVIADA', datos_snapshot: { s: suf } }) });
  if (!r.c?.[0]?.id) throw new Error(`PRECONDICIÓN: el aspirante no creó ENVIADA: ${r.e} ${JSON.stringify(r.c).slice(0,160)}`);
  return { f, v: r.c[0].id, j };
}
const leer = async (id) => (await srv(`/rest/v1/planilla_versiones?id=eq.${id}&select=id,estado,numero,approved_by,aprobada_at`)).c?.[0];
const paso = (v, extra) => adm(`/rest/v1/planilla_versiones?id=eq.${v}`, { method: 'PATCH', body: JSON.stringify(extra) });
const observar = (v) => adm(`/rest/v1/planilla_versiones?id=eq.${v}`, { method: 'PATCH', body: JSON.stringify({ estado: 'OBSERVADA' }) });

console.log('\n########## O5 · ENVIADA → APROBADA ##########');
{
  const { v } = await nuevo('5');
  const a = await leer(v);
  const r = await paso(v, { estado: 'APROBADA', aprobada_at: ahora(), approved_by: uAdm });
  const d = await leer(v);
  console.log(`  HTTP ${r.e}   ${a.estado} -> ${d.estado}   approved_by=${d.approved_by ? 'sí' : 'no'}   ${d.estado === 'APROBADA' ? 'OK' : 'INESPERADO'}`);
}

console.log('\n########## O6 · REENVIADA → APROBADA ##########');
{
  const { f, v, j } = await nuevo('6');
  await observar(v);
  const v2 = (await restCon(j)('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: f, numero: 2, estado: 'REENVIADA', datos_snapshot: { s: '6b' } }) })).c?.[0]?.id;
  const a = await leer(v2);
  const r = await paso(v2, { estado: 'APROBADA', aprobada_at: ahora(), approved_by: uAdm });
  const d = await leer(v2);
  console.log(`  HTTP ${r.e}   ${a?.estado} -> ${d?.estado}   ${d?.estado === 'APROBADA' ? 'OK' : 'INESPERADO'}`);
}

console.log('\n########## O7 · OBSERVADA → APROBADA (prohibida) ##########');
{
  const { v } = await nuevo('7');
  await observar(v);
  const a = await leer(v);
  const r = await paso(v, { estado: 'APROBADA', aprobada_at: ahora(), approved_by: uAdm });
  const d = await leer(v);
  console.log(`  HTTP ${r.e}   ${a.estado} -> ${d.estado}   ${d.estado === 'OBSERVADA' ? 'OK (quedó igual)' : 'INESPERADO'}`);
}

console.log('\n########## R5 · ENVIADA → OBSERVADA con campos de aprobación ##########');
{
  const { v } = await nuevo('8');
  const r = await paso(v, { estado: 'OBSERVADA', aprobada_at: ahora(), approved_by: uAdm });
  const d = await leer(v);
  console.log(`  HTTP ${r.e}   estado=${d.estado}   approved_by=${d.approved_by ?? 'null'}   aprobada_at=${d.aprobada_at ?? 'null'}   ${d.approved_by ? 'BYPASS: fabricó aprobación' : 'OK'}`);
}

console.log('\n########## R6 · OBSERVADA → REENVIADA con campos de aprobación ##########');
{
  const { f, v, j } = await nuevo('9');
  await observar(v);
  const v2 = (await restCon(j)('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: f, numero: 2, estado: 'REENVIADA', datos_snapshot: { s: '9b' } }) })).c?.[0]?.id;
  const r = await paso(v2, { estado: 'APROBADA', aprobada_at: ahora(), approved_by: uAdm });
  const d = await leer(v2);
  console.log(`  HTTP ${r.e}   estado=${d?.estado}   approved_by=${d?.approved_by ?? 'null'}   ${d?.approved_by ? 'OK (aprobación legítima)' : 'sin aprobación'}`);
}

console.log('\n########## OBSERVACIONES · INSERT del admin ##########');
{
  const e1 = await nuevo('o1');
  const e2 = await nuevo('o2'); await observar(e2.v);
  const e3 = await nuevo('o3'); await paso(e3.v, { estado: 'APROBADA', aprobada_at: ahora(), approved_by: uAdm });
  for (const [etq, v] of [['ENVIADA', e1.v], ['OBSERVADA', e2.v], ['APROBADA', e3.v]]) {
    const r = await adm('/rest/v1/planilla_observaciones', { method: 'POST', body: JSON.stringify({
      version_id: v, observada_por: uAdm, motivo: `prueba ${etq}` }) });
    const creada = r.c?.[0]?.id;
    console.log(`  versión ${etq.padEnd(10)} HTTP ${r.e}   ¿persistida? ${creada ? 'SÍ' : 'no'}`);
    if (creada) await srv(`/rest/v1/planilla_observaciones?id=eq.${creada}`, { method: 'DELETE' });
  }
}

console.log('\n########## CATÁLOGO pg_policies ##########');
{
  const r = await sql("select tablename, policyname, cmd, roles::text as roles, coalesce(qual,'-') as qual, coalesce(with_check,'-') as wc from pg_policies where schemaname='public' and tablename in ('planilla_versiones','planilla_observaciones') order by tablename, cmd");
  if (r.e >= 300) console.log(`  NO DISPONIBLE — HTTP ${r.e}. NO sustituyo el catálogo por inferencia.`);
  else for (const f of r.c) console.log(`  ${f.tablename} | ${f.cmd.padEnd(6)} | ${f.policyname}\n      USING: ${String(f.qual).slice(0,100)}\n      CHECK: ${String(f.wc).slice(0,100)}`);
}

console.log('\n########## LIMPIEZA ##########');
console.log(`  observaciones: ${(await srv('/rest/v1/planilla_observaciones?version_id=not.is.null', { method: 'DELETE' })).e}`);
for (const f of fichas) await srv(`/rest/v1/planilla_versiones?aspirante_id=eq.${f}`, { method: 'DELETE' });
for (const f of fichas) await srv(`/rest/v1/aspirantes?id=eq.${f}`, { method: 'DELETE' });
for (const a of auth) await srv(`/auth/v1/admin/users/${a}`, { method: 'DELETE' });
console.log(`  ${fichas.length} fichas · ${auth.length} cuentas`);
