#!/usr/bin/env node
// ============================================================================
// vectores-codigo-qr.mjs — los VECTORES DORADOS del código de asistencia (M7)
// ============================================================================
//
// Por qué existe: el código que el docente proyecta en el QR se deriva **dos
// veces** —en `plpgsql` (`asistencia_codigo_en_ventana`, que es la autoridad,
// porque es lo que llama la política RLS) y en Dart (`AsistenciaService.codigoQr`,
// para que la pantalla rote sin red)—. Si las dos derivaciones discreparan, el QR
// que se proyecta no lo aceptaría la base y la asistencia se rompería **en
// silencio**: el alumno vería «no tienes permisos» sin que nadie sepa por qué.
//
// Este script genera los valores con **PostgreSQL de verdad** (PGlite) y los
// imprime como el literal de Dart que se pega en
// `test/asistencia_service_test.dart`. Postgres es la autoridad; Dart es quien
// tiene que reproducirla.
//
//   node supabase/tests/vectores-codigo-qr.mjs
//
// **Cuándo hay que volver a ejecutarlo:** si cambia `asistencia_codigo_en_ventana`
// (migración `202609260001_asistencia_qr.sql`) o `AsistenciaService.codigoQr`.
// Si la prueba de paridad se pone roja, este script dice cuál es el valor bueno —
// pero **no** decide quién tiene razón: eso es un cambio de protocolo y hay que
// mirarlo, no pegarlo.
//
// **No lo ejecuta CI.** Es una herramienta de mantenimiento, no una aserción: la
// aserción es la prueba de Flutter, que ya lleva los valores dentro.
//
// ---------------------------------------------------------------------------
// Medición registrada el 2026-09-27, para que no haya que repetirla para creerla
// ---------------------------------------------------------------------------
// Barrido de **500 ventanas consecutivas** comparando la derivación de Postgres
// con la de Dart (sonda `_probe-codigo-qr.mjs`, ya retirada):
//
//     Ventanas probadas: 500
//     Con el bit alto puesto (hex8 >= 0x80000000): 258
//     Discrepancias Dart vs Postgres: 0
//
// Las 258 del bit alto son el caso que importa: la hipótesis era que
// `('x' || hex8)::bit(32)::bigint` fuera **con signo** y devolviera un negativo,
// con lo que el `% 1000000` de Postgres daría un resto distinto al de Dart.
// **Refutada por medición:** `('x' || 'ffffffff')::bit(32)::bigint` = `4294967295`
// —el cast es SIN signo— y las 500 ventanas coincidieron. Las cuatro ventanas con
// el bit alto que busca `buscarVentanas` —más una que salió así por casualidad,
// la de 30 s— dejan ese caso fijado en la prueba, para que la próxima persona no
// tenga que volver a sospecharlo.

import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const db = new PGlite({ extensions: { pgcrypto } });

await db.exec(`
create extension if not exists pgcrypto;
create or replace function public.asistencia_codigo_en_ventana(
  p_secreto text, p_sesion uuid, p_ventana bigint
) returns text language plpgsql immutable as $$
declare v_hash text;
begin
  v_hash := substr(
    encode(digest(p_secreto || p_sesion::text || p_ventana::text, 'sha256'), 'hex'), 1, 8);
  return lpad((('x' || v_hash)::bit(32)::bigint % 1000000)::text, 6, '0');
end;
$$;
`);

const SECRETO = '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7';
const SESION = 'e5e5e5e5-0001-4001-8001-000000000001';

/** Busca ventanas con el bit alto puesto y sin él, para cubrir las dos ramas. */
async function buscarVentanas(secreto, sesion, cantidad) {
  const altas = [];
  const bajas = [];
  let ventana = 119_000_000n; // ~ ventana real de 2026 con 15 s

  while ((altas.length < cantidad || bajas.length < cantidad) && ventana < 119_002_000n) {
    const r = await db.query(
      'select public.asistencia_codigo_en_ventana($1, $2, $3) as c, encode(digest($1 || $2 || $3::text, \'sha256\'), \'hex\') as h',
      [secreto, sesion, ventana.toString()],
    );
    const hex8 = r.rows[0].h.slice(0, 8);
    const alta = parseInt(hex8, 16) >= 0x80000000;
    if (alta && altas.length < cantidad) altas.push(ventana);
    if (!alta && bajas.length < cantidad) bajas.push(ventana);
    ventana += 1n;
  }
  return { altas, bajas };
}

const { altas, bajas } = await buscarVentanas(SECRETO, SESION, 4);

const casos = [
  // Ventanas realistas de la sesión sembrada, con el bit bajo.
  ...bajas.map((v) => ({ secreto: SECRETO, sesion: SESION, ventanaSeg: 15, ventana: v })),
  // Y con el bit ALTO: el caso que distingue el cast con signo del sin signo.
  ...altas.map((v) => ({ secreto: SECRETO, sesion: SESION, ventanaSeg: 15, ventana: v })),
  // Otras ventanas de rotación: el docente puede abrir con 5, 30 o 120 s.
  { secreto: SECRETO, sesion: SESION, ventanaSeg: 5, ventana: 357_000_000n },
  { secreto: SECRETO, sesion: SESION, ventanaSeg: 30, ventana: 59_500_000n },
  { secreto: SECRETO, sesion: SESION, ventanaSeg: 120, ventana: 14_875_000n },
  // Otro secreto y otra sesión: la derivación no puede depender de los valores
  // sembrados.
  {
    secreto: 'ffffffffffffffffffffffffffffffffffffffff',
    sesion: '00000000-0000-4000-8000-000000000000',
    ventanaSeg: 15,
    ventana: 119_000_001n,
  },
  {
    secreto: '0000000000000000000000000000000000000000',
    sesion: 'abcdefab-1234-4567-89ab-cdefabcdefab',
    ventanaSeg: 15,
    ventana: 119_000_002n,
  },
];

const lineas = [];
for (const caso of casos) {
  const r = await db.query(
    'select public.asistencia_codigo_en_ventana($1, $2, $3) as c',
    [caso.secreto, caso.sesion, caso.ventana.toString()],
  );
  const codigo = r.rows[0].c;
  const instante = caso.ventana * BigInt(caso.ventanaSeg);
  lineas.push(
    `    (secreto: '${caso.secreto}', sesion: '${caso.sesion}', ` +
      `ventanaSeg: ${caso.ventanaSeg}, instanteSegundos: ${instante}, ` +
      `esperado: '${codigo}'),`,
  );
}

console.log('const vectoresDelQr = <({String secreto, String sesion, int ventanaSeg, int instanteSegundos, String esperado})>[');
for (const l of lineas) console.log(l);
console.log('];');

await db.close();
