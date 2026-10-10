// TEMPORAL — verifica las cuatro transiciones del contrato EJERCIENDO el trigger.
//
// La autocomprobación de la migración no pudo hacerlo: una función de trigger no
// se puede llamar directamente (`0A000`). Aquí se ejerce con filas reales.

import { readFileSync } from 'node:fs';

const env = Object.fromEntries(
  readFileSync(new URL('../backend/.env', import.meta.url), 'utf8')
    .split('\n').filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const U = env.SUPABASE_URL, K = env.SUPABASE_SERVICE_ROLE_KEY;
const m = Date.now();

async function sb(ruta, opciones = {}) {
  const r = await fetch(U + ruta, { ...opciones, headers: {
    apikey: K, Authorization: `Bearer ${K}`, 'Content-Type': 'application/json',
    Prefer: 'return=representation', ...(opciones.headers ?? {}) } });
  return { estado: r.status, cuerpo: await r.json().catch(() => null) };
}

const prog = (await sb('/rest/v1/programs?select=id&limit=1')).cuerpo[0].id;
const auth = await sb('/auth/v1/admin/users', { method: 'POST',
  body: JSON.stringify({ email: `tr-${m}@semilla.invalid`, password: 'PruebaE2-2026!', email_confirm: true }) });
const uid = auth.cuerpo.id;
const ficha = (await sb('/rest/v1/aspirantes', { method: 'POST', body: JSON.stringify({
  user_id: uid, cedula: '7' + String(m).slice(-6), nombres: 'T', apellidos: 'T', program_id: prog,
  fecha_nac: '2000-01-01', sexo: 'F', telefono: '0412', email: `f${m}@semilla.invalid`,
  direccion: 'x', nivel_educativo: 'SECUNDARIO', discapacidad: false,
  requires_legal_tutor: false, datos_planilla: {},
}) })).cuerpo[0].id;

const crear = async (n, est, extra = {}) =>
  (await sb('/rest/v1/planilla_versiones', { method: 'POST', body: JSON.stringify({
    aspirante_id: ficha, numero: n, estado: est, datos_snapshot: {}, ...extra }) })).estado;
const mover = async (n, est, extra = {}) =>
  (await sb(`/rest/v1/planilla_versiones?aspirante_id=eq.${ficha}&numero=eq.${n}`,
    { method: 'PATCH', body: JSON.stringify({ estado: est, ...extra }) })).estado;

const ahora = new Date().toISOString();
console.log('\n########## TRANSICIONES ##########');
console.log(`  crear v1 ENVIADA          -> ${await crear(1, 'ENVIADA')}   (esperado 201)`);
console.log(`  ENVIADA   -> OBSERVADA    -> ${await mover(1, 'OBSERVADA')}   (esperado 200)  ✓ permitida`);
console.log(`  OBSERVADA -> APROBADA     -> ${await mover(1, 'APROBADA')}   (esperado 400)  ✗ prohibida`);
console.log(`  crear v2 REENVIADA        -> ${await crear(2, 'REENVIADA')}   (esperado 201)`);
console.log(`  REENVIADA -> OBSERVADA    -> ${await mover(2, 'OBSERVADA')}   (esperado 400)  ✗ LA QUE SE COLABA`);
console.log(`  REENVIADA -> APROBADA     -> ${await mover(2, 'APROBADA', { aprobada_at: ahora, approved_by: uid })}   (esperado 200)  ✓ permitida`);
console.log(`  APROBADA  -> OBSERVADA    -> ${await mover(2, 'OBSERVADA')}   (esperado 400)  ✗ terminal`);

console.log('\n########## LIMPIEZA ##########');
console.log(`  versiones: ${(await sb(`/rest/v1/planilla_versiones?aspirante_id=eq.${ficha}`, { method: 'DELETE' })).estado}`);
console.log(`  ficha:     ${(await sb(`/rest/v1/aspirantes?id=eq.${ficha}`, { method: 'DELETE' })).estado}`);
console.log(`  auth:      ${(await sb(`/auth/v1/admin/users/${uid}`, { method: 'DELETE' })).estado}`);

// NOTA DE NIVEL: este instrumento ejerce PostgREST/infraestructura directamente.
// Sus 400 no representan el contrato HTTP; para ese contrato usar _workflow-http-suite.mjs.
