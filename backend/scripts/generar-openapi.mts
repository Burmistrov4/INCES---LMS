/**
 * Escribe `openapi.json` en disco a partir de los esquemas Zod (deuda D6).
 *
 * El archivo es un **artefacto**, no una fuente: se regenera, no se edita. Sirve
 * para tres cosas que no puede cubrir el endpoint en vivo:
 *   · que un revisor pueda leer el contrato en un `diff` del repositorio;
 *   · que una herramienta de CI pueda validarlo sin levantar el servidor;
 *   · que el frontend pueda generar tipos sin la API corriendo.
 *
 * Uso: npm run openapi
 */
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { construirDocumentoOpenApi } from '../src/http/openapi.js';

const AQUI = dirname(fileURLToPath(import.meta.url));
const DESTINO = join(AQUI, '..', 'openapi.json');

const documento = construirDocumentoOpenApi();

writeFileSync(DESTINO, `${JSON.stringify(documento, null, 2)}\n`, 'utf8');

const rutas = Object.keys(documento.paths ?? {});
console.log(`\n  ✓ openapi.json escrito (OpenAPI ${documento.openapi})`);
console.log(`    ${rutas.length} rutas:`);
for (const ruta of rutas.sort()) {
  const metodos = Object.keys(documento.paths[ruta])
    .map((m) => m.toUpperCase())
    .join(', ');
  console.log(`      ${metodos.padEnd(6)} ${ruta}`);
}
console.log(`    ${Object.keys(documento.components?.schemas ?? {}).length} esquemas\n`);
