/**
 * Aplica la política de CORS del bucket R2 leyéndola de `docs/r2-cors.json`.
 *
 * **Por qué existe este script y no basta con `wrangler`.** `wrangler r2 bucket
 * cors put` no usa las credenciales S3 del `.env`: exige un token de API de
 * Cloudflare o un `wrangler login` interactivo. Las credenciales que el proyecto
 * tiene son las **S3** (`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`), que sí
 * firman `PutBucketCors`. Con este script, aplicar la política no depende de
 * ninguna credencial que no esté ya en `backend/.env`.
 *
 * El caso que lo motivó: el frente pasó de 8080 a 8090 (XAMPP ocupa el 8080) y
 * el bucket seguía autorizando sólo el origen viejo. El síntoma es traicionero:
 * desde Node el `PUT` prefirmado devuelve 200 igual, así que **ninguna prueba
 * del backend lo detecta**; lo bloquea el preflight del navegador, y eso sólo lo
 * ve `probe-r2-cors.mts`.
 *
 * Uso:  npx tsx backend/scripts/aplicar-cors-r2.mts
 *
 * Códigos de salida:
 *   0  política aplicada y releída
 *   2  faltan variables de entorno
 *   3  fallo inesperado (incluido «R2 rechazó la política»)
 *
 * Es idempotente: `PutBucketCors` reemplaza, no acumula.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  GetBucketCorsCommand,
  PutBucketCorsCommand,
  S3Client,
} from '@aws-sdk/client-s3';

// --- cargar backend/.env a mano (mismo patrón que probe-r2-cors.mts) ---------
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

/** El documento es la fuente: lo que se aplica es exactamente lo que está en git. */
const rutaPolitica = resolve(aqui, '..', '..', 'docs', 'r2-cors.json');
const politica = JSON.parse(readFileSync(rutaPolitica, 'utf8')) as {
  rules: Array<{
    allowed: { origins: string[]; methods: string[]; headers: string[] };
    maxAgeSeconds?: number;
  }>;
};

async function main(): Promise<void> {
  console.log(`Cuenta: ${accountId}`);
  console.log(`Bucket: ${bucket}`);
  console.log(`Origen: ${rutaPolitica}\n`);

  const reglas = politica.rules.map((r) => ({
    AllowedOrigins: r.allowed.origins,
    AllowedMethods: r.allowed.methods,
    AllowedHeaders: r.allowed.headers,
    MaxAgeSeconds: r.maxAgeSeconds ?? 3600,
  }));

  for (const r of reglas) {
    console.log(`  orígenes : ${r.AllowedOrigins.join(', ')}`);
    console.log(`  métodos  : ${r.AllowedMethods.join(', ')}`);
    console.log(`  cabeceras: ${r.AllowedHeaders.join(', ')}`);
  }
  console.log('');

  await cliente.send(new PutBucketCorsCommand({ Bucket: bucket, CORSConfiguration: { CORSRules: reglas } }));
  console.log('  PutBucketCors aceptado.');

  // No basta con que la escritura responda 200: se relee. Un 200 que no cambió
  // nada es indistinguible de un 200 que sí aplicó, y R2 no devuelve el cuerpo
  // de la política en la escritura.
  const releida = await cliente.send(new GetBucketCorsCommand({ Bucket: bucket }));
  const origenes = (releida.CORSRules ?? []).flatMap((r) => r.AllowedOrigins ?? []);
  console.log(`  GetBucketCors releído: ${origenes.join(', ')}\n`);

  const esperados = reglas.flatMap((r) => r.AllowedOrigins);
  const ausentes = esperados.filter((o) => !origenes.includes(o));
  if (ausentes.length > 0) {
    console.error(`RESULTADO: la política aplicada NO cubre: ${ausentes.join(', ')}`);
    process.exit(3);
  }

  console.log('RESULTADO: política de CORS aplicada y verificada por relectura.');
  console.log('Sigue con la sonda: npx tsx backend/scripts/probe-r2-cors.mts');
}

main().catch((e) => {
  console.error('Fallo inesperado:', e);
  process.exit(3);
});
