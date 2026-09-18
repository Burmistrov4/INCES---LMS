/**
 * Sonda de verificación de Cloudflare R2 (R-24).
 *
 * Replica EXACTAMENTE el S3Client de producción (src/infra/r2_service.ts):
 *   · region: 'auto'        — R2 no tiene regiones; con otra cosa firma mal.
 *   · forcePathStyle: true  — R2 no soporta virtual-host; el cliente resolvería
 *     <bucket>.<cuenta>.r2.cloudflarestorage.com, que no existe.
 *   · endpoint derivado de CLOUDFLARE_ACCOUNT_ID.
 *
 * Recorre el ciclo HeadBucket → Put → Get → List → Delete y NO deja residuo:
 * borra su propio objeto. Es la prueba de fuego de "¿el token ya es utilizable?".
 *
 * Uso:  npx tsx backend/scripts/probe-r2.mts
 *       (carga backend/.env internamente; no depende de flags de arranque)
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  S3Client,
  HeadBucketCommand,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  DeleteObjectCommand,
} from '@aws-sdk/client-s3';

// --- cargar backend/.env manualmente (evita depender de flags del runner) ---
const aqui = dirname(fileURLToPath(import.meta.url));
const rutaEnv = resolve(aqui, '..', '.env');
for (const linea of readFileSync(rutaEnv, 'utf8').split('\n')) {
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
  'CLOUDFLARE_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET',
];
const faltan = necesarias.filter((k) => !process.env[k]);
if (faltan.length) {
  console.error('FALTAN VARIABLES R2:', faltan.join(', '));
  process.exit(2);
}

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID!;
const bucket = process.env.R2_BUCKET!;

const cliente = new S3Client({
  region: 'auto',
  endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
  forcePathStyle: true,
});

const clave = `sondas/verify-${Date.now()}.txt`;
const cuerpo = `probe ${new Date().toISOString()}`;

function ok(m: string): void {
  console.log(`  OK   ${m}`);
}
function mal(m: string, e: unknown): void {
  const name = (e as { name?: string })?.name ?? 'Error';
  const code = (e as { $metadata?: { httpStatusCode?: number } })?.$metadata
    ?.httpStatusCode;
  const msg = (e as { message?: string })?.message ?? String(e);
  console.log(`  FAIL ${m}  [${name}${code ? ' ' + code : ''}] ${msg}`);
}

async function principal(): Promise<void> {
  console.log(`Cuenta:  ${accountId}`);
  console.log(`Bucket:   ${bucket}`);
  console.log(
    `Endpoint: https://${accountId}.r2.cloudflarestorage.com  (forcePathStyle, region auto)\n`,
  );

  let fallos = 0;

  // 1) HeadBucket — ¿existe y tenemos acceso al bucket?
  try {
    const r = await cliente.send(new HeadBucketCommand({ Bucket: bucket }));
    ok(`HeadBucket            ${r.$metadata.httpStatusCode}`);
  } catch (e) {
    fallos++;
    mal('HeadBucket', e);
  }

  // 2) PutObject — escribir un objeto de prueba
  try {
    const r = await cliente.send(
      new PutObjectCommand({
        Bucket: bucket,
        Key: clave,
        Body: cuerpo,
        ContentType: 'text/plain',
      }),
    );
    ok(`PutObject             ${r.$metadata.httpStatusCode}`);
  } catch (e) {
    fallos++;
    mal('PutObject', e);
  }

  // 3) GetObject — leerlo y confirmar que el contenido coincide
  try {
    const r = await cliente.send(
      new GetObjectCommand({ Bucket: bucket, Key: clave }),
    );
    const txt = await r.Body?.transformToString();
    const igual = txt === cuerpo;
    ok(
      `GetObject             ${r.$metadata.httpStatusCode}  contenido=${igual ? 'coincide' : 'DISTINTO'}`,
    );
    if (!igual) fallos++;
  } catch (e) {
    fallos++;
    mal('GetObject', e);
  }

  // 4) ListObjectsV2 — listar dentro del prefijo de sondas
  try {
    const r = await cliente.send(
      new ListObjectsV2Command({ Bucket: bucket, Prefix: 'sondas/' }),
    );
    const n = r.Contents?.length ?? 0;
    ok(`ListObjectsV2        ${r.$metadata.httpStatusCode}  objetos=${n}`);
  } catch (e) {
    fallos++;
    mal('ListObjectsV2', e);
  }

  // 5) DeleteObject — purgar la sonda (no dejar residuo)
  try {
    const r = await cliente.send(
      new DeleteObjectCommand({ Bucket: bucket, Key: clave }),
    );
    ok(`DeleteObject          ${r.$metadata.httpStatusCode}`);
  } catch (e) {
    fallos++;
    mal('DeleteObject', e);
  }

  console.log('');
  if (fallos === 0) {
    console.log('RESULTADO: R2 UTILIZABLE — ciclo completo en verde.');
  } else {
    console.log(
      `RESULTADO: R2 NO UTILIZABLE — ${fallos} operación(es) fallida(s).`,
    );
    process.exit(1);
  }
}

principal().catch((e) => {
  console.error('Fallo inesperado:', e);
  process.exit(3);
});
