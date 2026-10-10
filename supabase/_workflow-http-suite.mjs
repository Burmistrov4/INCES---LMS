// REGRESIÓN HTTP — suite consolidada del workflow de planillas.
// Ejecuta los dos instrumentos HTTP existentes sin duplicar su lógica.
// _errores-http.mjs: A1/A3/A4/A5 + E1.
// _b3-b10-b11.mjs: B3/B10/B11.
// El script falla si cualquiera de los instrumentos termina con exit code != 0.
// No mide PostgREST directamente: el contrato de esta suite es HTTP.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const dir = dirname(fileURLToPath(import.meta.url));
const instrumentos = ['_errores-http.mjs', '_b3-b10-b11.mjs'];
let fallos = 0;

for (const instrumento of instrumentos) {
  console.log(`\n========== SUITE · ${instrumento} ==========`);
  const r = spawnSync(process.execPath, [resolve(dir, instrumento)], {
    cwd: resolve(dir, '..'),
    stdio: 'inherit',
    windowsHide: false,
  });
  if (r.error) {
    console.error(`ERROR ejecutando ${instrumento}: ${r.error.message}`);
    fallos++;
  } else if (r.status !== 0) {
    console.error(`FALLA · ${instrumento} terminó con exit code ${r.status}`);
    fallos++;
  } else {
    console.log(`PASS · ${instrumento}`);
  }
}

console.log(`\n========== SUITE HTTP · ${fallos === 0 ? 'GREEN' : 'RED'} ==========`);
process.exitCode = fallos === 0 ? 0 : 1;
