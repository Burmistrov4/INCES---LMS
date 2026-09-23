/**
 * Sonda de CORS del bucket R2.
 *
 * Responde a una pregunta que **ninguna prueba de la API puede responder**: ¿un
 * navegador puede subir y descargar contra R2, o lo bloquea el preflight?
 *
 * El motivo de que haga falta una sonda aparte es incómodo pero simple: el humo
 * (`supabase/humo-archivos.mjs`) y el arnés de Vitest hablan con R2 desde Node, y
 * **Node no aplica CORS**. Ahí el `PUT` prefirmado devuelve 200 con o sin política
 * de CORS, así que las 468 pruebas del backend pasan en verde mientras el
 * navegador rechaza la misma subida. Sólo el preflight (`OPTIONS`) dice la verdad,
 * y sólo el navegador lo emite. Esta sonda lo emite a mano.
 *
 * Firma la URL **exactamente como producción** (mismo `signableHeaders`,
 * `region: 'auto'`, `forcePathStyle`), porque una firma distinta daría un
 * preflight distinto y la medición no valdría.
 *
 * Uso:  npx tsx backend/scripts/probe-r2-cors.mts
 *
 * Códigos de salida:
 *   0  el preflight devuelve `Access-Control-Allow-Origin` para todos los orígenes
 *   1  falta la política de CORS (o no cubre algún origen) → el navegador bloquea
 *   2  faltan variables de entorno
 *   3  fallo inesperado
 *
 * No deja residuo: borra el objeto de sondeo antes de salir.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DeleteObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

// --- cargar backend/.env manualmente (mismo patrón que probe-r2.mts) ---
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

/** Los orígenes donde el frontend corre de verdad en desarrollo y en producción. */
const ORIGENES = [
  'http://localhost:8090',
  'http://127.0.0.1:8090',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
];

const cliente = new S3Client({
  region: 'auto',
  endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
  forcePathStyle: true,
});

const clave = `sondas/cors-${Date.now()}.pdf`;

/**
 * Las tres cabeceras que decide el preflight. Se leen crudas a propósito: si
 * `access-control-allow-origin` está ausente, el navegador bloquea la petición
 * aunque el servidor haya respondido 200, y "ausente" no se ve mirando el código
 * de estado.
 */
function cabecerasCors(r: Response): Record<string, string> {
  return {
    'access-control-allow-origin': r.headers.get('access-control-allow-origin') ?? '(AUSENTE)',
    'access-control-allow-methods': r.headers.get('access-control-allow-methods') ?? '(AUSENTE)',
    'access-control-allow-headers': r.headers.get('access-control-allow-headers') ?? '(AUSENTE)',
  };
}

async function main(): Promise<void> {
  console.log(`Cuenta:  ${accountId}`);
  console.log(`Bucket:   ${bucket}`);
  console.log(`Clave:    ${clave}\n`);

  // Firma idéntica a la de producción: el `Content-Type` va firmado, así que el
  // cliente está obligado a enviar exactamente éste (y el preflight debe
  // declararlo en `Access-Control-Request-Headers`).
  const urlPut = await getSignedUrl(
    cliente,
    new PutObjectCommand({ Bucket: bucket, Key: clave, ContentType: 'application/pdf' }),
    { expiresIn: 300, signableHeaders: new Set(['content-type']) },
  );

  console.log('  URL prefirmada de subida emitida (300 s, Content-Type firmado).');
  console.log(`  Host: ${new URL(urlPut).host}\n`);

  let bloqueados = 0;

  // --- 1) El preflight, que es lo que hace el navegador antes del PUT ---------
  for (const origen of ORIGENES) {
    console.log(`  --- PREFLIGHT (OPTIONS)  Origin: ${origen} ---`);

    const r = await fetch(urlPut, {
      method: 'OPTIONS',
      headers: {
        Origin: origen,
        'Access-Control-Request-Method': 'PUT',
        'Access-Control-Request-Headers': 'content-type',
      },
    });

    const cors = cabecerasCors(r);
    console.log(`    estado                        : ${r.status}`);
    for (const [k, v] of Object.entries(cors)) {
      console.log(`    ${k.padEnd(29)} : ${v}`);
    }

    if (cors['access-control-allow-origin'] === '(AUSENTE)') {
      bloqueados++;
      console.log('    => SIN CORS: el navegador BLOQUEARÍA la subida desde ese origen.');
    } else {
      console.log('    => con CORS: el navegador permite la subida desde ese origen.');
    }
    console.log('');
  }

  // --- 2) El PUT real, con Origin, para ver si R2 devuelve la cabecera --------
  console.log('  --- PUT real (con Origin), lo que el navegador intentaría después ---');
  const put = await fetch(urlPut, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/pdf', Origin: ORIGENES[0]! },
    body: new Uint8Array([0x25, 0x50, 0x44, 0x46]), // "%PDF"
  });
  const corsPut = cabecerasCors(put);
  console.log(`    estado                        : ${put.status}`);
  console.log(`    access-control-allow-origin   : ${corsPut['access-control-allow-origin']}`);
  console.log(
    '    Nota: que el PUT funcione desde Node NO prueba que funcione desde el',
  );
  console.log(
    '    navegador. Node no aplica CORS; el navegador sí. Decide el preflight.',
  );
  console.log('');

  // --- 3) Limpieza: la sonda no deja residuo ---------------------------------
  await cliente.send(new DeleteObjectCommand({ Bucket: bucket, Key: clave }));
  console.log('  Objeto de sondeo borrado.\n');

  if (bloqueados > 0) {
    console.log(
      `RESULTADO: CORS AUSENTE en ${bloqueados} de ${ORIGENES.length} orígenes.`,
    );
    console.log(
      'El frontend Web NO podrá subir ni descargar contra R2 hasta aplicar la',
    );
    console.log('política. Ver docs/CONFIGURACION_R2.md §2.');
    process.exit(1);
  }

  console.log('RESULTADO: CORS PRESENTE en todos los orígenes sondeados.');
}

main().catch((e) => {
  console.error('Fallo inesperado:', e);
  process.exit(3);
});
