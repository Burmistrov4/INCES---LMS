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

const rutas = Object.entries(documento.paths ?? {});
console.log(`\n  ✓ openapi.json escrito (OpenAPI ${documento.openapi})`);
console.log(`    ${rutas.length} rutas:`);
// Se recorren las **entradas** y no las claves, volviendo a indexar
// `documento.paths[ruta]`: con `noUncheckedIndexedAccess` esa segunda lectura
// devuelve `PathItemObject | undefined`, y el guardia `?? {}` de arriba no cubre
// a la de abajo. Es el fallo que dejó este archivo sin comprobar durante meses,
// porque `scripts/` no estaba en el `include` de `tsconfig.json`.
for (const [ruta, operaciones] of rutas.sort(([a], [b]) =>
  a < b ? -1 : a > b ? 1 : 0,
)) {
  const metodos = Object.keys(operaciones)
    .map((m) => m.toUpperCase())
    .join(', ');
  console.log(`      ${metodos.padEnd(6)} ${ruta}`);
}
console.log(`    ${Object.keys(documento.components?.schemas ?? {}).length} esquemas\n`);
