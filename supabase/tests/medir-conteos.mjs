#!/usr/bin/env node
// ============================================================================
// medir-conteos.mjs — los números que ESTADO_DEL_SISTEMA.md promete "medidos"
// ============================================================================
//
// Por qué existe: un documento vivo se edita a mano mientras la realidad la
// edita la compilación. Cada cifra que ESTADO_DEL_SISTEMA.md afirma hay que
// volver a medirla o fecharla; copiarla hacia adelante es cómo un documento se
// vuelve confiadamente falso.
//
// Este script imprime los conteos directamente desde la fuente de verdad.
// Es de sólo lectura: no modifica nada. Ejecutar antes de tocar el documento.
//
//   node supabase/tests/medir-conteos.mjs
//
// Lo que NO puede medir (y por eso hay que fecharlo a mano): los verificadores
// que hablan con la nube (verificar-esquema.mjs, test-humo.mjs y los humos de
// integración) y el número de migraciones aplicadas en Supabase. Esos dependen
// de credenciales y del estado del despliegue, no del repositorio.

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// --- Migraciones del repositorio --------------------------------------------
const migraciones = readdirSync(join(raiz, 'supabase', 'migrations'))
  .filter((f) => f.endsWith('.sql'))
  .sort();
console.log('MIGRACIONES (repo):', migraciones.length);
console.log('  primera:', migraciones[0]);
console.log('  última :', migraciones.at(-1));

// --- OpenAPI -----------------------------------------------------------------
const openapi = JSON.parse(
  readFileSync(join(raiz, 'backend', 'openapi.json'), 'utf8'),
);
const rutas = Object.keys(openapi.paths ?? {});
let operaciones = 0;
for (const ruta of rutas) {
  operaciones += Object.keys(openapi.paths[ruta]).filter((m) =>
    ['get', 'post', 'put', 'patch', 'delete'].includes(m),
  ).length;
}
const esquemas = Object.keys(openapi.components?.schemas ?? {}).length;
console.log('OPENAPI: rutas', rutas.length, '· operaciones', operaciones, '· esquemas', esquemas);

// --- Módulos sembrados, según la semilla ------------------------------------
// Se leen de las migraciones: es la única fuente de verdad sin red.
const clavesModulo = new Set();
for (const archivo of migraciones) {
  const sql = readFileSync(join(raiz, 'supabase', 'migrations', archivo), 'utf8');
  for (const m of sql.matchAll(/insert into public\.system_modules[\s\S]*?values\s*([\s\S]*?);/gi)) {
    for (const fila of m[1].matchAll(/'((?:m\d)_[a-z_]+)'/g)) {
      clavesModulo.add(fila[1]);
    }
  }
}
console.log('MÓDULOS sembrados por las migraciones:', clavesModulo.size);
console.log(' ', [...clavesModulo].sort().join(', '));

console.log('\nLos totales de pruebas NO los mide este script: salen de los');
console.log('corredores. Ejecutar y copiar el resultado:');
console.log('  (backend)  cd backend && npm run verify');
console.log('  (flutter)  flutter test');
console.log('  (pglite)   cd supabase/tests && npm test');
