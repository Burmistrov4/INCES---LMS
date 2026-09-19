/**
 * Barrido de subidas abandonadas de M5 (D9, la mitad que no es configuración).
 *
 * ── Por qué existe ───────────────────────────────────────────────────────────
 * El ciclo de dos pasos de M5 crea la fila `PENDING` **antes** de que el objeto
 * exista. Si el cliente sube y nunca confirma —cierra la pestaña, se le va la
 * conexión, abandona— quedan dos cosas: una fila `PENDING` para siempre y un
 * objeto en R2 que nadie reclama.
 *
 * Eso **no se puede tapar desde el bucket**: el ciclo de vida de R2 sólo filtra
 * por prefijo y no sabe nada de `files_metadata.estado`, así que una regla
 * `--expire-days` sobre `m5_archivos/` borraría también los archivos
 * `CONFIRMED`. Lo único que distingue una subida abandonada es la **fila**, y por
 * eso el barrido es código y no configuración. Ver `docs/CONFIGURACION_R2.md` §3.6.
 *
 * Este script es el «barrido de abandonados» que `rutas/archivos.ts:282` ya
 * nombraba sin que existiera.
 *
 * ── Qué NO puede hacer ───────────────────────────────────────────────────────
 * - **No arregla el caso del borrado de cuenta a posteriori.** Si se borra una
 *   cuenta, el `ON DELETE CASCADE` de `propietario_id` borra la fila y deja el
 *   objeto: desde la base ya no hay forma de saber que ese objeto era suyo. Por
 *   eso `supabase/eliminar-cuenta.mjs` borra los objetos **antes** que la cuenta.
 *   Lo que sí hace el modo `--huerfanos` es **encontrar** esos objetos después
 *   —listando el bucket en vez de la base—, aunque ya no sepa de quién eran.
 * - **No valida la autorización.** Escribe con la clave de servicio, que salta
 *   la RLS: es una herramienta de mantenimiento, no una ruta de usuario.
 *
 * ── Los dos modos ────────────────────────────────────────────────────────────
 * | modo | mira | encuentra |
 * |---|---|---|
 * | (por defecto) | la base | filas `PENDING` abandonadas (y su objeto) |
 * | `--revisar-borrados` | la base | filas `DELETED` con objeto residual |
 * | `--huerfanos` | **el bucket** | objetos sin ninguna fila que los referencie |
 *
 * Los dos primeros van de la fila al objeto; el tercero va del objeto a la fila.
 * Hacen falta los dos sentidos: una fila sin objeto se arregla desde la base,
 * pero un objeto sin fila sólo se ve listando el bucket.
 *
 * ── Uso ──────────────────────────────────────────────────────────────────────
 *   npx tsx backend/scripts/limpiar-pendientes.mts                    # simulación
 *   npx tsx backend/scripts/limpiar-pendientes.mts --confirmar        # barre
 *   npx tsx backend/scripts/limpiar-pendientes.mts --horas=1 --limite=50
 *   npx tsx backend/scripts/limpiar-pendientes.mts --revisar-borrados
 *   npx tsx backend/scripts/limpiar-pendientes.mts --huerfanos
 *   npx tsx backend/scripts/limpiar-pendientes.mts --huerfanos --prefijo=m5_archivos/
 *
 * Códigos de salida: 0 correcto · 1 hubo errores · 2 faltan variables · 3 inesperado
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DeleteObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  S3Client,
} from '@aws-sdk/client-s3';
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

// --- argumentos -------------------------------------------------------------
function numeroDe(nombre: string, porDefecto: number): number {
  const arg = process.argv.find((a) => a.startsWith(`--${nombre}=`));
  if (arg === undefined) return porDefecto;
  const valor = Number(arg.slice(nombre.length + 3));
  if (!Number.isFinite(valor) || valor <= 0) {
    console.error(`--${nombre} debe ser un número positivo.`);
    process.exit(2);
  }
  return valor;
}

/**
 * Horas de antigüedad para dar una fila por abandonada.
 *
 * La URL de subida vive **300 s** (`R2_PUT_TTL_SEGUNDOS`), así que cualquier
 * `PENDING` de más de una hora está abandonado con certeza. El defecto de 24 h es
 * deliberadamente holgado: barrer de más no se puede deshacer.
 */
const horas = numeroDe('horas', 24);

/** Tope de filas por ejecución. Un barrido enorme debe ser una decisión, no un accidente. */
const limite = numeroDe('limite', 500);

const confirmar = process.argv.includes('--confirmar');
const revisarBorrados = process.argv.includes('--revisar-borrados');
const buscarHuerfanos = process.argv.includes('--huerfanos');

/**
 * Prefijo del bucket que se recorre en el modo `--huerfanos`. Por defecto, todo:
 * un objeto sin fila es un objeto sin fila esté donde esté, y el bucket es
 * exclusivo de esta aplicación.
 */
const prefijo = (() => {
  const arg = process.argv.find((a) => a.startsWith('--prefijo='));
  return arg === undefined ? '' : arg.slice('--prefijo='.length);
})();

const bucket = process.env.R2_BUCKET!;
const clienteS3 = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID!,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
  },
  forcePathStyle: true,
});

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { persistSession: false } },
);

/** ¿Existe el objeto? `HeadObject` es la única forma de saberlo sin descargarlo. */
async function existeEnR2(clave: string): Promise<number | null> {
  try {
    const r = await clienteS3.send(
      new HeadObjectCommand({ Bucket: bucket, Key: clave }),
    );
    return r.ContentLength ?? 0;
  } catch {
    return null;
  }
}

let errores = 0;

async function barrer(): Promise<void> {
  const corte = new Date(Date.now() - horas * 3600_000).toISOString();

  console.log(`\n  Bucket   : ${bucket}`);
  console.log(`  Umbral   : PENDING creado antes de ${corte} (${horas} h)`);
  console.log(`  Modo     : ${confirmar ? 'ESCRIBE' : 'SIMULACIÓN (no escribe)'}`);
  console.log(`  Límite   : ${limite} fila(s) por ejecución\n`);

  const { data, error } = await supabase
    .from('files_metadata')
    .select('id, propietario_id, r2_key, nombre_original, created_at')
    .eq('estado', 'PENDING')
    .lt('created_at', corte)
    .order('created_at', { ascending: true })
    .limit(limite);

  if (error) {
    console.error('  Error leyendo files_metadata:', error.message);
    process.exit(1);
  }

  if (data.length === 0) {
    console.log('  No hay subidas abandonadas. Nada que hacer.\n');
    return;
  }

  console.log(`  ${data.length} subida(s) abandonada(s):\n`);

  let conObjeto = 0;
  let barridas = 0;

  for (const fila of data) {
    const tamano = await existeEnR2(fila.r2_key);
    const estadoObjeto =
      tamano === null ? 'sin objeto' : `objeto de ${tamano} B`;
    if (tamano !== null) conObjeto++;

    console.log(`    ${fila.created_at}  ${estadoObjeto}`);
    console.log(`      id      : ${fila.id}`);
    console.log(`      dueño   : ${fila.propietario_id}`);
    console.log(`      clave   : ${fila.r2_key}`);
    console.log(`      nombre  : ${fila.nombre_original}`);

    if (!confirmar) continue;

    // **Objeto primero, fila después**, igual que en el rechazo por tamaño de la
    // ruta: si fallara el borrado en R2, la fila sigue `PENDING` y la próxima
    // pasada la vuelve a encontrar. Al revés, la fila diría `DELETED` y el objeto
    // quedaría ocupando sitio sin que nadie lo sepa.
    try {
      // `DeleteObject` sobre una clave ausente no falla: es idempotente. Se llama
      // siempre para no dejar una carrera entre el `HeadObject` y el borrado.
      await clienteS3.send(
        new DeleteObjectCommand({ Bucket: bucket, Key: fila.r2_key }),
      );

      const { error: errorMarca } = await supabase
        .from('files_metadata')
        .update({ estado: 'DELETED', deleted_at: new Date().toISOString() })
        .eq('id', fila.id);

      if (errorMarca) throw new Error(errorMarca.message);

      barridas++;
      console.log('      → objeto borrado y fila marcada DELETED');
    } catch (e) {
      errores++;
      console.log(`      → ERROR: ${(e as Error).message}`);
    }
  }

  console.log(
    `\n  Resumen: ${data.length} candidata(s), ${conObjeto} con objeto en R2, ` +
      `${confirmar ? `${barridas} barrida(s)` : '0 escritas (simulación)'}, ${errores} error(es).`,
  );
  if (!confirmar) {
    console.log(
      '\n  Para barrer de verdad:\n' +
        `    npx tsx backend/scripts/limpiar-pendientes.mts --horas=${horas} --confirmar\n`,
    );
  }
}

/**
 * Segunda pasada, opcional: filas `DELETED` cuyo objeto sigue en R2.
 *
 * Es el caso «el borrado en R2 falló después de marcar la fila». En el camino
 * normal no ocurre —el borrado va primero— pero un fallo de red entre las dos
 * operaciones deja este residuo, y desde la base es invisible: la fila dice
 * `DELETED` y el objeto sigue ahí.
 */
async function revisarResiduales(): Promise<void> {
  console.log('\n  ── Revisando filas DELETED con objeto residual ──\n');

  const { data, error } = await supabase
    .from('files_metadata')
    .select('id, r2_key, deleted_at')
    .eq('estado', 'DELETED')
    .limit(limite);

  if (error) {
    console.error('  Error leyendo files_metadata:', error.message);
    process.exit(1);
  }

  let residuales = 0;
  for (const fila of data) {
    const tamano = await existeEnR2(fila.r2_key);
    if (tamano === null) continue;

    residuales++;
    console.log(`    RESIDUAL  ${fila.r2_key}  (${tamano} B)`);

    if (!confirmar) continue;
    try {
      await clienteS3.send(
        new DeleteObjectCommand({ Bucket: bucket, Key: fila.r2_key }),
      );
      console.log('      → objeto borrado');
    } catch (e) {
      errores++;
      console.log(`      → ERROR: ${(e as Error).message}`);
    }
  }

  console.log(
    `\n  ${data.length} fila(s) DELETED revisada(s), ${residuales} con objeto residual.`,
  );
}

/**
 * Tercera pasada, opcional: objetos del bucket que **ninguna fila** referencia.
 *
 * Es el único sentido en el que se puede mirar este problema. Las otras dos
 * pasadas parten de una fila y comprueban el objeto; aquí hay que partir del
 * bucket, porque el rastro que permitiría llegar desde la base es exactamente lo
 * que se perdió (el `CASCADE` borró la fila, o la fila nunca llegó a insertarse).
 *
 * ── La trampa: el hueco entre el PUT y la fila ───────────────────────────────
 * El ciclo de M5 es: presignar → `PUT` a R2 → confirmar (insertar la fila). Entre
 * el `PUT` y la fila hay un instante en el que el objeto **existe y no tiene
 * fila**: es una subida legítima en curso, no un huérfano. Borrar «todo objeto
 * sin fila» destruiría subidas en vuelo.
 *
 * Por eso se filtra por `LastModified` con el mismo umbral de horas que el
 * barrido. Con el defecto de 24 h no hay ambigüedad posible: la URL de subida
 * vive 300 s. Y un objeto sólo se considera huérfano si además es más viejo que
 * el corte, así que **no se toca nada recién subido**.
 */
async function buscarObjetosHuerfanos(): Promise<void> {
  const corte = Date.now() - horas * 3600_000;

  console.log('\n  ── Objetos del bucket sin fila que los referencie ──\n');
  console.log(`  Prefijo  : ${prefijo === '' ? '(todo el bucket)' : prefijo}`);
  console.log(`  Umbral   : subidos antes de ${new Date(corte).toISOString()} (${horas} h)\n`);

  // 1) Todo el bucket, paginando: `ListObjectsV2` devuelve como mucho 1000 por
  //    página y no avisa de que faltan salvo por `IsTruncated`.
  const objetos: { clave: string; tamano: number; modificado: Date }[] = [];
  let token: string | undefined;
  do {
    const pagina = await clienteS3.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: prefijo === '' ? undefined : prefijo,
        ContinuationToken: token,
      }),
    );
    for (const o of pagina.Contents ?? []) {
      if (o.Key === undefined) continue;
      objetos.push({
        clave: o.Key,
        tamano: o.Size ?? 0,
        modificado: o.LastModified ?? new Date(0),
      });
    }
    token = pagina.IsTruncated === true ? pagina.NextContinuationToken : undefined;
  } while (token !== undefined);

  // 2) Todas las claves conocidas. Se pide sólo `r2_key` y se pagina, porque
  //    PostgREST corta en 1000 filas por defecto y un `select` truncado en
  //    silencio haría parecer huérfano a medio bucket.
  const conocidas = new Set<string>();
  const TANDA = 1000;
  for (let desde = 0; ; desde += TANDA) {
    const { data, error } = await supabase
      .from('files_metadata')
      .select('r2_key')
      .range(desde, desde + TANDA - 1);
    if (error) {
      console.error('  Error leyendo files_metadata:', error.message);
      process.exit(1);
    }
    for (const f of data) conocidas.add(f.r2_key as string);
    if (data.length < TANDA) break;
  }

  console.log(`  ${objetos.length} objeto(s) en el bucket, ${conocidas.size} clave(s) en la base.\n`);

  const candidatos = objetos.filter((o) => !conocidas.has(o.clave));
  const recientes = candidatos.filter((o) => o.modificado.getTime() >= corte);
  const huerfanos = candidatos.filter((o) => o.modificado.getTime() < corte);

  if (candidatos.length === 0) {
    console.log('  Sin objetos huérfanos.\n');
    return;
  }

  if (recientes.length > 0) {
    console.log(`  ${recientes.length} objeto(s) sin fila pero RECIENTES: se dejan en paz.`);
    console.log('  Puede ser una subida en curso (el `PUT` va antes que la fila).\n');
    for (const o of recientes) {
      console.log(`    (reciente) ${o.modificado.toISOString()}  ${o.tamano} B  ${o.clave}`);
    }
    console.log('');
  }

  if (huerfanos.length === 0) {
    console.log('  Ninguno supera el umbral: nada que borrar.\n');
    return;
  }

  console.log(`  ⚠ ${huerfanos.length} huérfano(s) — objeto sin fila y más viejo que el umbral:\n`);

  let borrados = 0;
  for (const o of huerfanos) {
    console.log(`    ${o.modificado.toISOString()}  ${o.tamano} B`);
    console.log(`      ${o.clave}`);

    if (!confirmar) continue;
    try {
      await clienteS3.send(new DeleteObjectCommand({ Bucket: bucket, Key: o.clave }));
      borrados++;
      console.log('      → borrado');
    } catch (e) {
      errores++;
      console.log(`      → ERROR: ${(e as Error).message}`);
    }
  }

  console.log(
    `\n  Resumen: ${huerfanos.length} huérfano(s), ` +
      `${confirmar ? `${borrados} borrado(s)` : '0 borrados (simulación)'}.`,
  );

  if (!confirmar) {
    console.log(
      '\n  Para borrarlos de verdad:\n' +
        `    npx tsx backend/scripts/limpiar-pendientes.mts --huerfanos --horas=${horas} --confirmar\n`,
    );
  }
}

async function principal(): Promise<void> {
  if (buscarHuerfanos) {
    await buscarObjetosHuerfanos();
  } else {
    await barrer();
    if (revisarBorrados) await revisarResiduales();
  }

  console.log('');
  if (errores > 0) {
    console.log(`RESULTADO: ${errores} error(es). Revísalos antes de dar el barrido por bueno.\n`);
    process.exit(1);
  }
  console.log('RESULTADO: barrido completado sin errores.\n');
}

principal().catch((e) => {
  console.error('Fallo inesperado:', e);
  process.exit(3);
});
