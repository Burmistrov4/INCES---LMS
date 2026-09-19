/**
 * Borra de R2 todos los objetos de un usuario, **antes** de borrar su cuenta.
 *
 * ── Por qué existe ───────────────────────────────────────────────────────────
 * `files_metadata.propietario_id` tiene `ON DELETE CASCADE` contra `auth.users`.
 * Eso significa que borrar la cuenta **borra las filas y deja los objetos**: en
 * cuanto la fila desaparece ya no hay nada que relacione la clave de R2 con
 * nadie, así que el objeto queda ocupando sitio para siempre y **ni la base ni un
 * barrido pueden encontrarlo**. Es el único agujero de M5 que es irrecuperable a
 * posteriori, y ya se materializó una vez (un objeto huérfano real, medido el
 * 2026-09-18).
 *
 * El orden importa y no es negociable: **objetos primero, cuenta después.**
 *
 * ── Por qué es `.mjs` y no `.mts` ────────────────────────────────────────────
 * Porque `supabase/eliminar-cuenta.mjs` lo invoca con `node`, sin `npx` ni
 * transpilador. Y vive en `backend/scripts/` y no en `supabase/` porque necesita
 * el SDK de S3: los scripts de `supabase/` son deliberadamente libres de
 * dependencias (sólo `node:` y `fetch`).
 *
 * ── Qué NO hace ──────────────────────────────────────────────────────────────
 * No toca la base de datos: las filas las borra el `CASCADE` al borrar la cuenta.
 *
 * ── Uso ──────────────────────────────────────────────────────────────────────
 *   node backend/scripts/borrar-objetos-de-usuario.mjs --propietario=<uuid>
 *   node backend/scripts/borrar-objetos-de-usuario.mjs --propietario=<uuid> --confirmar
 *
 * Códigos de salida: 0 correcto · 1 hubo errores · 2 faltan variables o argumentos
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createClient } from '@supabase/supabase-js';

// --- cargar backend/.env manualmente (mismo patrón que las sondas de R2) ---
const AQUI = dirname(fileURLToPath(import.meta.url));
for (const linea of readFileSync(resolve(AQUI, '..', '.env'), 'utf8').split('\n')) {
  const t = linea.trim();
  if (!t || t.startsWith('#')) continue;
  const i = t.indexOf('=');
  if (i < 0) continue;
  const clave = t.slice(0, i).trim();
  let valor = t.slice(i + 1).trim();
  if (
    (valor.startsWith('"') && valor.endsWith('"')) ||
    (valor.startsWith("'") && valor.endsWith("'"))
  ) {
    valor = valor.slice(1, -1);
  }
  if (process.env[clave] === undefined) process.env[clave] = valor;
}

const necesarias = [
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'CLOUDFLARE_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET',
];
const faltan = necesarias.filter((k) => !process.env[k]);
if (faltan.length) {
  console.error('FALTAN VARIABLES:', faltan.join(', '));
  process.exit(2);
}

const argumento = process.argv.find((a) => a.startsWith('--propietario='));
const propietario = argumento === undefined ? '' : argumento.slice('--propietario='.length).trim();
const confirmar = process.argv.includes('--confirmar');

if (propietario.length === 0) {
  console.error(
    '\n  Falta --propietario=<uuid>.\n' +
      '  Es el id del usuario en auth.users, el mismo que hay en\n' +
      '  files_metadata.propietario_id.\n',
  );
  process.exit(2);
}

const bucket = process.env.R2_BUCKET;
const cliente = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
  forcePathStyle: true,
});

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } },
);

const { data, error } = await supabase
  .from('files_metadata')
  .select('id, r2_key, estado, tamano_bytes')
  .eq('propietario_id', propietario)
  .order('created_at', { ascending: true });

if (error) {
  console.error('Error leyendo files_metadata:', error.message);
  process.exit(1);
}

console.log(`\n  Propietario : ${propietario}`);
console.log(`  Bucket      : ${bucket}`);
console.log(`  Modo        : ${confirmar ? 'ESCRIBE' : 'SIMULACIÓN (no escribe)'}\n`);

if (data.length === 0) {
  console.log('  Sin archivos que borrar. Nada que hacer.\n');
  process.exit(0);
}

// Se borran TODOS los estados, no sólo CONFIRMED: un `PENDING` abandonado también
// es un objeto en el bucket, y un `DELETED` puede tener el objeto residual de un
// borrado que falló a medias.
console.log(`  ${data.length} objeto(s) en el bucket:\n`);

let borrados = 0;
let errores = 0;

for (const fila of data) {
  const tamano = fila.tamano_bytes === null ? 'sin tamaño sellado' : `${fila.tamano_bytes} B`;
  console.log(`    [${fila.estado}] ${tamano}`);
  console.log(`      ${fila.r2_key}`);

  if (!confirmar) continue;

  try {
    // Idempotente: borrar una clave que no existe no falla, así que no hay
    // carrera entre comprobar y borrar.
    await cliente.send(
      new DeleteObjectCommand({ Bucket: bucket, Key: fila.r2_key }),
    );
    borrados++;
    console.log('      → borrado');
  } catch (e) {
    errores++;
    console.log(`      → ERROR: ${e.message}`);
  }
}

console.log(
  `\n  Resumen: ${data.length} objeto(s), ` +
    `${confirmar ? `${borrados} borrado(s)` : '0 borrados (simulación)'}, ${errores} error(es).`,
);

if (!confirmar) {
  console.log(
    '\n  Para borrarlos de verdad:\n' +
      `    node backend/scripts/borrar-objetos-de-usuario.mjs --propietario=${propietario} --confirmar\n`,
  );
  process.exit(0);
}

if (errores > 0) {
  console.error(
    '\n  ATENCIÓN: hubo errores. NO borres la cuenta todavía: en cuanto el CASCADE\n' +
      '  elimine las filas, estos objetos serán imposibles de encontrar.\n',
  );
  process.exit(1);
}

console.log('\n  Objetos borrados. Ahora sí es seguro borrar la cuenta.\n');
