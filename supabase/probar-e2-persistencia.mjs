// TEMPORAL — batería de persistencia E-2. Bloque 5.
//
// Prioridad máxima: **un aspirante con JWT real NO puede insertar `APROBADA`.**
// Si eso falla, el diseño se cae y hay que parar.
//
// Distingue tres capas y NO las mezcla:
//   · RLS  → JWT real del actor (lo que un usuario puede hacer de verdad)
//   · CHECK/UNIQUE/TRIGGER → service-role (reglas de tabla, independientes de quién)
//
// Fixtures: A y B son aspirantes CON ficha y `program_id` (el esquema lo exige);
// el admin y el docente son cuentas con rol. Todo se borra al final.

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const URL_ = env.SUPABASE_URL, SRV = env.SUPABASE_SERVICE_ROLE_KEY;
const CLAVE = 'PruebaE2-2026!';
const marca = Date.now();

if (!URL_ || !SRV) { console.log('SIN MEDIR — faltan credenciales'); process.exit(0); }

const filas = [];
const anota = (id, actor, op, esperado, real, ok, capa) => {
  filas.push({ id, actor, op, esperado, real, ok, capa });
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${id} ${actor} · ${op} → ${real} (esperaba ${esperado}) [${capa}]`);
};

/** Con service-role. */
async function srv(ruta, opciones = {}) {
  const r = await fetch(`${URL_}${ruta}`, { ...opciones, headers: {
    apikey: SRV, Authorization: `Bearer ${SRV}`, 'Content-Type': 'application/json',
    Prefer: 'return=representation', ...(opciones.headers ?? {}) } });
  return { estado: r.status, cuerpo: await r.json().catch(() => null) };
}
/** Con el JWT de un actor — esto es lo que prueba la RLS. */
async function como(jwt, ruta, opciones = {}) {
  const r = await fetch(`${URL_}${ruta}`, { ...opciones, headers: {
    apikey: env.SUPABASE_ANON_KEY ?? SRV, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json',
    Prefer: 'return=representation', ...(opciones.headers ?? {}) } });
  return { estado: r.status, cuerpo: await r.json().catch(() => null) };
}

async function crearAuth(correo, rol) {
  const r = await srv('/auth/v1/admin/users', { method: 'POST',
    body: JSON.stringify({ email: correo, password: CLAVE, email_confirm: true }) });
  if (!r.cuerpo?.id) throw new Error(`crear ${correo}: ${r.estado}`);
  if (rol !== 'estudiante') {
    await srv(`/rest/v1/profiles?id=eq.${r.cuerpo.id}`, { method: 'PATCH',
      body: JSON.stringify({ rol, active: true }) });
  }
  return r.cuerpo.id;
}
async function entrar(correo) {
  const r = await srv('/auth/v1/token?grant_type=password', { method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY ?? SRV },
    body: JSON.stringify({ email: correo, password: CLAVE }) });
  if (!r.cuerpo?.access_token) throw new Error(`login ${correo}: ${r.estado}`);
  return r.cuerpo.access_token;
}

const creados = { auth: [], fichas: [], versiones: [] };
try {
  console.log('\n########## FIXTURES ##########');
  const prog = (await srv('/rest/v1/programs?select=id&limit=1')).cuerpo?.[0]?.id;
  if (!prog) throw new Error('no hay programa real');

  const cA = `e2-a-${marca}@semilla.invalid`, cB = `e2-b-${marca}@semilla.invalid`;
  const cAd = `e2-admin-${marca}@semilla.invalid`, cDo = `e2-doc-${marca}@semilla.invalid`;
  const idA = await crearAuth(cA, 'estudiante'); creados.auth.push(idA);
  const idB = await crearAuth(cB, 'estudiante'); creados.auth.push(idB);
  const idAd = await crearAuth(cAd, 'admin'); creados.auth.push(idAd);
  const idDo = await crearAuth(cDo, 'docente'); creados.auth.push(idDo);

  const ficha = async (uid, ced) => (await srv('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
    user_id: uid, cedula: ced, nombres: 'PRUEBA', apellidos: 'E2', program_id: prog,
    fecha_nac: '2000-01-01', sexo: 'F', telefono: '04120000000',
    email: `f${ced}@semilla.invalid`, direccion: 'x', nivel_educativo: 'SECUNDARIO',
    discapacidad: false, requires_legal_tutor: false, datos_planilla: {},
  }) })).cuerpo?.[0]?.id;

  const fA = await ficha(idA, `8${String(marca).slice(-6)}1`); creados.fichas.push(fA);
  const fB = await ficha(idB, `8${String(marca).slice(-6)}2`); creados.fichas.push(fB);

  const jA = await entrar(cA), jB = await entrar(cB), jAd = await entrar(cAd), jDo = await entrar(cDo);
  console.log(`  A=${fA}\n  B=${fB}\n  admin=${idAd} docente=${idDo}\n  JWT ×4 obtenidos`);

  const snap = { primer_nombre: 'PRUEBA', cedula: `8${String(marca).slice(-6)}1` };

  // ===== 1. AUTO-ASCENSO — la prueba que decide =====
  console.log('\n########## 1. AUTO-ASCENSO (JWT real) ##########');
  const asc = await como(jA, '/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fA, numero: 1, estado: 'APROBADA', datos_snapshot: snap }) });
  anota('P1', 'A', 'INSERT estado=APROBADA', 'rechazado', asc.estado, asc.estado >= 400, 'RLS');

  const env1 = await como(jA, '/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fA, numero: 1, estado: 'ENVIADA', datos_snapshot: snap }) });
  const v1 = env1.cuerpo?.[0]?.id; if (v1) creados.versiones.push(v1);
  anota('P2', 'A', 'INSERT estado=ENVIADA', 'permitido', env1.estado, env1.estado < 300, 'RLS');

  const paraB = await como(jA, '/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fB, numero: 1, estado: 'ENVIADA', datos_snapshot: snap }) });
  if (paraB.cuerpo?.[0]?.id) creados.versiones.push(paraB.cuerpo[0].id);
  anota('P3', 'A', 'INSERT para ficha de B', 'rechazado', paraB.estado, paraB.estado >= 400, 'RLS');

  const reen = await como(jA, '/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fA, numero: 2, estado: 'REENVIADA', datos_snapshot: snap }) });
  if (reen.cuerpo?.[0]?.id) creados.versiones.push(reen.cuerpo[0].id);
  anota('P4', 'A', 'INSERT numero=2 como REENVIADA sin v1 observada', 'documentar', reen.estado, true, 'BD (ver §6)');

  // ===== 2. TRANSICIONES POSITIVAS =====
  console.log('\n########## 2. TRANSICIONES POSITIVAS ##########');
  if (v1) {
    const obs = await como(jAd, `/rest/v1/planilla_versiones?id=eq.${v1}`, { method: 'PATCH',
      body: JSON.stringify({ estado: 'OBSERVADA' }) });
    anota('P5', 'admin', 'v1 ENVIADA→OBSERVADA', 'permitido', obs.estado, obs.estado < 300, 'RLS+trigger');

    const obs2 = await srv('/rest/v1/planilla_observaciones', { method: 'POST', body: JSON.stringify({
      version_id: v1, observada_por: idAd, motivo: 'Corregir la dirección' }) });
    anota('P6', 'admin(srv)', 'crear observación', 'permitido', obs2.estado, obs2.estado < 300, 'RLS');

    const ap = await como(jAd, `/rest/v1/planilla_versiones?id=eq.${v1}`, { method: 'PATCH',
      body: JSON.stringify({ estado: 'APROBADA', aprobada_at: new Date().toISOString(), approved_by: idAd }) });
    anota('P7', 'admin', 'OBSERVADA→APROBADA (no permitida)', 'rechazado', ap.estado, ap.estado >= 400, 'trigger');
  }

  // ===== 3. ACCESO CRUZADO =====
  console.log('\n########## 3. ACCESO CRUZADO (JWT real) ##########');
  const bVe = await como(jB, `/rest/v1/planilla_versiones?aspirante_id=eq.${fA}&select=id`, {});
  const nB = Array.isArray(bVe.cuerpo) ? bVe.cuerpo.length : -1;
  anota('P8', 'B', 'leer versiones de A', '0 filas', `${bVe.estado} · ${nB} filas`, bVe.estado < 300 && nB === 0, 'RLS');

  const doVe = await como(jDo, `/rest/v1/planilla_versiones?select=id`, {});
  const nDo = Array.isArray(doVe.cuerpo) ? doVe.cuerpo.length : -1;
  anota('P9', 'docente', 'leer versiones', '0 filas', `${doVe.estado} · ${nDo} filas`, doVe.estado < 300 && nDo === 0, 'RLS');

  const doObs = await como(jDo, '/rest/v1/planilla_observaciones', { method: 'POST', body: JSON.stringify({
    version_id: v1 ?? '00000000-0000-0000-0000-000000000000', observada_por: idDo, motivo: 'x' }) });
  anota('P10', 'docente', 'crear observación', 'rechazado', doObs.estado, doObs.estado >= 400, 'RLS');

  const aObs = await como(jA, '/rest/v1/planilla_observaciones', { method: 'POST', body: JSON.stringify({
    version_id: v1 ?? '00000000-0000-0000-0000-000000000000', observada_por: idA, motivo: 'x' }) });
  anota('P11', 'A', 'crear observación', 'rechazado', aObs.estado, aObs.estado >= 400, 'RLS');

  // ===== 4. CONSTRAINTS (service-role) =====
  console.log('\n########## 4. CONSTRAINTS (service-role) ##########');
  const c1 = await srv('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fA, numero: 1, estado: 'ENVIADA', datos_snapshot: snap }) });
  anota('C1', 'srv', 'numero duplicado', 'rechazado', c1.estado, c1.estado >= 400, 'UNIQUE');

  const c2 = await srv('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fB, numero: 9, estado: 'BORRADOR', datos_snapshot: snap }) });
  anota('C2', 'srv', 'estado=BORRADOR', 'rechazado', c2.estado, c2.estado >= 400, 'CHECK');

  const c3 = await srv('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fB, numero: 8, estado: 'APROBADA', datos_snapshot: snap }) });
  if (c3.cuerpo?.[0]?.id) creados.versiones.push(c3.cuerpo[0].id);
  anota('C3', 'srv', 'APROBADA sin aprobada_at/approved_by', 'rechazado', c3.estado, c3.estado >= 400, 'CHECK');

  const c4 = await srv('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: fB, numero: 7, estado: 'ENVIADA', datos_snapshot: snap,
    aprobada_at: new Date().toISOString() }) });
  if (c4.cuerpo?.[0]?.id) creados.versiones.push(c4.cuerpo[0].id);
  anota('C4', 'srv', 'ENVIADA con aprobada_at', 'rechazado', c4.estado, c4.estado >= 400, 'CHECK');

  if (v1) {
    const c5 = await srv(`/rest/v1/planilla_versiones?id=eq.${v1}`, { method: 'PATCH',
      body: JSON.stringify({ datos_snapshot: { hackeado: true } }) });
    anota('C5', 'srv', 'modificar datos_snapshot', 'rechazado', c5.estado, c5.estado >= 400, 'TRIGGER');
    const c6 = await srv(`/rest/v1/planilla_versiones?id=eq.${v1}`, { method: 'PATCH',
      body: JSON.stringify({ aspirante_id: fB }) });
    anota('C6', 'srv', 'modificar aspirante_id', 'rechazado', c6.estado, c6.estado >= 400, 'TRIGGER');
    const c7 = await srv(`/rest/v1/planilla_versiones?id=eq.${v1}`, { method: 'PATCH',
      body: JSON.stringify({ numero: 99 }) });
    anota('C7', 'srv', 'modificar numero', 'rechazado', c7.estado, c7.estado >= 400, 'TRIGGER');
  }

  const fallos = filas.filter((f) => !f.ok);
  console.log(`\n########## RESUMEN: ${filas.length - fallos.length}/${filas.length} PASS ##########`);
  for (const f of fallos) console.log(`  FAIL ${f.id}: ${f.op} → ${f.real} (esperaba ${f.esperado}) [${f.capa}]`);
} catch (e) {
  console.log(`\n########## SIN MEDIR ##########\n${String(e).slice(0, 400)}`);
} finally {
  console.log('\n########## LIMPIEZA ##########');
  for (const v of creados.versiones) {
    const r = await srv(`/rest/v1/planilla_versiones?id=eq.${v}`, { method: 'DELETE' });
    console.log(`  versión ${v}: ${r.estado}`);
  }
  for (const f of creados.fichas) {
    const r = await srv(`/rest/v1/aspirantes?id=eq.${f}`, { method: 'DELETE' });
    console.log(`  ficha ${f}: ${r.estado}${r.estado >= 400 ? '  ← RESTRICT: hay versiones' : ''}`);
  }
  for (const a of creados.auth) {
    const r = await srv(`/auth/v1/admin/users/${a}`, { method: 'DELETE' });
    console.log(`  auth ${a}: ${r.estado}`);
  }
}
