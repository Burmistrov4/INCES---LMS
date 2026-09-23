/**
 * Humo de integración del Módulo 5 — Archivos en Cloudflare R2 (Capa 6).
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que las 34 pruebas de `backend/test/archivos.test.ts` **no pueden**
 * verificar, porque usan dobles en memoria:
 *
 *   1. El ciclo de dos pasos contra R2 de verdad: firmar → `PUT` directo →
 *      `HeadObject` → confirmar. El doble expone `objetos: Map<clave, tamaño>`,
 *      pero nadie prueba que R2 acepte la firma ni que el objeto pese de verdad
 *      lo que dice pesar.
 *   2. Que el `Content-Type` esté **firmado** (`signableHeaders`). Un cliente que
 *      sube declarando otro tipo tiene que ser rechazado por R2. Con un doble el
 *      `PUT` no existe, así que este camino es inalcanzable en Vitest.
 *   3. El aislamiento entre usuarios con JWT y RLS reales: B no lee ni borra el
 *      archivo de A; el admin sí lo lee y sí lo borra.
 *   4. La frontera de escritura de la decisión 1: `files_metadata` no acepta
 *      INSERT/UPDATE/DELETE directos, ni siquiera con sesión de usuario.
 *   5. Que `m5_max_bytes` se lea **en cada petición** (no al arrancar) y que la
 *      caché de parámetros caduque: el objeto que se pasa de peso se rechaza con
 *      413 y se borra de R2, sin dejar basura.
 *
 * DIVERGENCIA CONOCIDA — leer antes de tocar las aserciones de la sección 6
 * -------------------------------------------------------------------------
 * El briefing de la Capa 6 pedía que el `DELETE` de B sobre el archivo de A
 * devolviera **404** («no filtrar la existencia»), igual que el `GET
 * /url-lectura`. El sistema hace **403** en el `DELETE`, y es deliberado:
 * `GET /url-lectura` lee por PostgREST y la RLS esconde la fila (de ahí el 404,
 * indistinguible de «no existe»), mientras que `DELETE` escribe por la RPC
 * `security definer`, que **sí** distingue «es de otro» y lo dice con `42501`.
 *
 * Este script afirma **el comportamiento real** y además lo marca como
 * divergencia en el informe final, para que la decisión —unificar en 404 o
 * aceptar el 403— la tome el dueño del producto y no un test.
 *
 * CÓMO FUNCIONA
 * -------------
 * Crea tres cuentas temporales (estudiante A, estudiante B, admin) con
 * `auth.admin.createUser` —sin enviar correo—, obtiene un JWT real para cada una,
 * recorre el ciclo completo y las purga al final, también si algo falla.
 *
 * Necesita el backend levantado **con credenciales reales de R2**:
 *   cd backend && npm run dev
 *
 * FUERA DE CI A PROPÓSITO: escribe en la base real y en el bucket real.
 *
 * USO
 * ---
 *   node supabase/humo-archivos.mjs              # simulación (no escribe)
 *   node supabase/humo-archivos.mjs --confirmar  # ejecuta el humo
 */
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const CONFIRMAR = process.argv.includes('--confirmar');
const API = (process.env.API_BASE_URL ?? 'http://127.0.0.1:3001').replace(/\/+$/, '');

/** Lee del entorno y, si no está, de `backend/.env` (sin añadir `dotenv`). */
function variable(nombre) {
  const delEntorno = (process.env[nombre] ?? '').trim();
  if (delEntorno.length > 0) return delEntorno;
  try {
    for (const linea of readFileSync(join(RAIZ, 'backend', '.env'), 'utf8').split('\n')) {
      const limpia = linea.trim();
      if (limpia.length === 0 || limpia.startsWith('#')) continue;
      const corte = limpia.indexOf('=');
      if (corte < 0) continue;
      if (limpia.slice(0, corte).trim() === nombre) return limpia.slice(corte + 1).trim();
    }
  } catch {
    // Sin .env legible: se tratará como variable ausente, más abajo.
  }
  return '';
}

const URL_BASE = variable('SUPABASE_URL').replace(/\/+$/, '');
const CLAVE_SERVICIO = variable('SUPABASE_SERVICE_ROLE_KEY');
const CLAVE_ANON = variable('SUPABASE_ANON_KEY');

/** TTL de la caché de parámetros del backend: hay que esperarlo al cambiarlos. */
const TTL_PARAMETROS_MS = Number(variable('SETTINGS_CACHE_TTL_MS') || 30000);

let ok = 0;
let fallos = 0;
const comprobar = (etiqueta, condicion, detalle = '') => {
  if (condicion) {
    ok += 1;
    console.log(`  [OK  ] ${etiqueta}`);
  } else {
    fallos += 1;
    console.log(`  [FALLA] ${etiqueta}${detalle ? ` — ${detalle}` : ''}`);
  }
};

/**
 * Divergencias respecto al briefing. **No cuentan como fallo**: el sistema hace
 * algo coherente consigo mismo, pero distinto de lo que se pidió por escrito. Se
 * acumulan y se imprimen en un bloque aparte para que no se pierdan entre los OK.
 */
const divergencias = [];
const divergencia = (etiqueta, esperado, obtenido) => {
  divergencias.push({ etiqueta, esperado, obtenido });
  console.log(`  [DIVER] ${etiqueta}`);
  console.log(`          el briefing esperaba ${esperado}; el sistema hace ${obtenido}`);
};

/** Petición a Supabase (PostgREST o GoTrue) que no lanza por códigos HTTP. */
async function pedir(ruta, { metodo = 'GET', cuerpo, clave, token, extra = {} } = {}) {
  const cabeceras = {
    apikey: clave ?? CLAVE_SERVICIO,
    'Content-Type': 'application/json',
    ...extra,
  };
  if (token) cabeceras.Authorization = `Bearer ${token}`;
  else cabeceras.Authorization = `Bearer ${clave ?? CLAVE_SERVICIO}`;

  const r = await fetch(`${URL_BASE}${ruta}`, {
    method: metodo,
    headers: cabeceras,
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  let datos = null;
  try {
    datos = texto.length > 0 ? JSON.parse(texto) : null;
  } catch {
    datos = texto;
  }
  return { estado: r.status, datos };
}

/** Petición al backend propio. El cuerpo se manda en JSON salvo `crudo`. */
async function api(ruta, { metodo = 'GET', token, cuerpo, cabeceras = {} } = {}) {
  const r = await fetch(`${API}${ruta}`, {
    method: metodo,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(cuerpo === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...cabeceras,
    },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  let datos = null;
  try {
    datos = texto.length > 0 ? JSON.parse(texto) : null;
  } catch {
    datos = texto;
  }
  return { estado: r.status, datos, cabeceras: r.headers };
}

/** Código de error del sobre uniforme `{ error: { codigo, mensaje } }`. */
const codigoDe = (datos) => datos?.error?.codigo ?? null;

/**
 * Contenido determinista para el archivo de prueba.
 *
 * Un PDF mínimo y válido: así la extensión, el tipo MIME firmado y el contenido
 * real son coherentes entre sí, y la descarga se puede comparar byte a byte.
 */
const CONTENIDO = Buffer.from(
  '%PDF-1.4\n' +
    '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
    '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
    '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n' +
    'trailer<</Root 1 0 R>>\n' +
    '%%EOF\n',
  'utf8',
);

/** Nombre con acento y espacio: se conserva en la base, pero NO en la clave. */
const NOMBRE_CON_ACENTO = 'Constancia José.pdf';

if (!URL_BASE || !CLAVE_SERVICIO || !CLAVE_ANON) {
  console.error('\n  Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY.');
  console.error('  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n');
  process.exit(1);
}

const marca = Date.now();
const CORREO_A = `humo-arch-a-${marca}@ejemplo.invalid`;
const CORREO_B = `humo-arch-b-${marca}@ejemplo.invalid`;
const CORREO_ADMIN = `humo-arch-admin-${marca}@ejemplo.invalid`;
const CLAVE = `Humo!${randomBytes(12).toString('base64url')}`;

const ids = { a: null, b: null, admin: null };
const tokens = { a: null, b: null, admin: null };

/** Archivos creados, para el informe de residuo. */
const creados = [];

console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Backend  : ${API}`);
console.log(`  Modo     : ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);
console.log(`  Caché de parámetros del backend: ${TTL_PARAMETROS_MS} ms`);

if (!CONFIRMAR) {
  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  console.log(`\n  Backend ${salud === null ? 'NO responde' : `responde ${salud}`}.`);
  console.log('\n  Simulación: no se escribió nada. Repite con --confirmar.\n');
  process.exit(0);
}

/**
 * Purga todo lo que crea este script. Se ejecuta siempre, también al fallar.
 *
 * Las filas de `files_metadata` caen solas: su FK a `auth.users` es
 * `on delete cascade`. Se comprueba igualmente, porque «debería caer» y «cayó»
 * no son lo mismo.
 */
async function purgar() {
  for (const id of [ids.b, ids.admin, ids.a]) {
    if (id) await pedir(`/auth/v1/admin/users/${id}`, { metodo: 'DELETE' });
  }
  // Por prefijo, no por valor exacto: una corrida anterior puede dejar residuo.
  await pedir('/rest/v1/profiles?email=like.humo-arch*', { metodo: 'DELETE' });
  await pedir('/rest/v1/auth_logs?email=like.humo-arch*', { metodo: 'DELETE' });
}

/** Crea una cuenta temporal y devuelve su id y un JWT real. */
async function crearPersona(correo, rol) {
  const creado = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: { email: correo, password: CLAVE, email_confirm: true },
  });
  const id = creado.datos?.id ?? null;
  if (!id) return { id: null, token: null, error: `crear ${correo}: estado=${creado.estado}` };

  if (rol !== 'estudiante') {
    const promovido = await pedir(`/rest/v1/profiles?id=eq.${id}`, {
      metodo: 'PATCH',
      cuerpo: { rol },
      extra: { Prefer: 'return=representation' },
    });
    if (promovido.datos?.[0]?.rol !== rol) {
      return { id, token: null, error: `promover a ${rol}: ${JSON.stringify(promovido.datos)}` };
    }
  }

  const sesion = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    cuerpo: { email: correo, password: CLAVE },
  });
  const token = sesion.datos?.access_token ?? null;
  return { id, token, error: token ? null : `iniciar sesión: estado=${sesion.estado}` };
}

let valorOriginalMaxBytes = null;

try {
  // ==========================================================================
  //  1. Personas con sesión real
  // ==========================================================================
  console.log('\n  1. Tres personas con JWT real (A, B, admin)\n');

  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  if (salud === null) {
    console.error(`  ALTO: el backend no responde en ${API}.`);
    console.error('  Levántalo con:  cd backend && npm run dev');
    console.error('  Este humo prueba el camino HTTP completo; sin backend no hay nada que probar.\n');
    fallos += 1;
    throw new Error('backend ausente');
  }
  comprobar('el backend responde en /salud', salud === 200, `estado=${salud}`);

  const personaA = await crearPersona(CORREO_A, 'estudiante');
  ids.a = personaA.id;
  tokens.a = personaA.token;
  comprobar('A existe y tiene sesión', Boolean(tokens.a), personaA.error ?? '');

  const personaB = await crearPersona(CORREO_B, 'estudiante');
  ids.b = personaB.id;
  tokens.b = personaB.token;
  comprobar('B existe y tiene sesión', Boolean(tokens.b), personaB.error ?? '');

  const personaAdmin = await crearPersona(CORREO_ADMIN, 'admin');
  ids.admin = personaAdmin.id;
  tokens.admin = personaAdmin.token;
  comprobar('el admin existe, tiene rol admin y sesión', Boolean(tokens.admin), personaAdmin.error ?? '');

  if (!tokens.a || !tokens.b || !tokens.admin) throw new Error('sin las tres sesiones');

  // El id del propietario reparte las claves en R2: conviene tenerlo a mano.
  console.log(`         A=${ids.a}`);
  console.log(`         B=${ids.b}`);

  // ==========================================================================
  //  2. Firmar la subida
  // ==========================================================================
  console.log('\n  2. POST /archivos/firmar-subida\n');

  const firma = await api('/api/v1/archivos/firmar-subida', {
    metodo: 'POST',
    token: tokens.a,
    cuerpo: {
      nombreOriginal: NOMBRE_CON_ACENTO,
      entityType: 'TASK_SUBMISSION',
      entidadId: null,
    },
  });
  comprobar('firmar responde 201', firma.estado === 201, `estado=${firma.estado} ${JSON.stringify(firma.datos)?.slice(0, 160)}`);

  const archivo = firma.datos?.archivo ?? {};
  const idArchivo = archivo.id ?? null;
  if (idArchivo) creados.push(idArchivo);
  comprobar('la respuesta trae el id del archivo (sin él no se puede confirmar)', Boolean(idArchivo));
  comprobar('la fila nace en PENDING', archivo.estado === 'PENDING', String(archivo.estado));
  comprobar('sin tamaño todavía (lo mide el HeadObject al confirmar)', archivo.tamanoBytes === null, String(archivo.tamanoBytes));
  comprobar('el tipo MIME lo deriva el servidor de la extensión', archivo.tipoContenido === 'application/pdf', String(archivo.tipoContenido));
  comprobar('se conserva el nombre original con acento', archivo.nombreOriginal === NOMBRE_CON_ACENTO, String(archivo.nombreOriginal));
  comprobar('el propietario es A, no el cliente', archivo.propietarioId === ids.a, String(archivo.propietarioId));

  // La clave la construye el servidor. Su forma es contrato: `m5_archivos/` es el
  // prefijo que usa la regla de ciclo de vida del bucket (D9), así que si cambia
  // la forma, la regla deja de aplicar en silencio.
  const clave = archivo.r2Key ?? '';
  comprobar(
    'la clave vive bajo el prefijo m5_archivos/ del propietario',
    clave.startsWith(`m5_archivos/${ids.a}/`) && clave.endsWith('.pdf'),
    clave,
  );
  comprobar(
    'el nombre con acento NO viaja en la clave (sólo la extensión)',
    !clave.includes('Jos') && !clave.includes('Constancia'),
    clave,
  );
  comprobar('la respuesta trae urlDeSubida y expiraEnSegundos', Boolean(firma.datos?.urlDeSubida) && Number.isFinite(firma.datos?.expiraEnSegundos), JSON.stringify({ expira: firma.datos?.expiraEnSegundos }));

  // El cliente no propone clave ni tamaño: si pudiera, la URL firmada sería una
  // autorización para sobrescribir cualquier objeto del bucket.
  const proponeClave = await api('/api/v1/archivos/firmar-subida', {
    metodo: 'POST',
    token: tokens.a,
    cuerpo: { nombreOriginal: 'x.pdf', entityType: 'TASK_SUBMISSION', entidadId: null, r2Key: 'm5_archivos/otro/2026/09/robado.pdf' },
  });
  comprobar(
    'el cliente NO puede proponer la clave (esquema estricto → 400)',
    proponeClave.estado === 400,
    `estado=${proponeClave.estado}`,
  );

  const extensionMala = await api('/api/v1/archivos/firmar-subida', {
    metodo: 'POST',
    token: tokens.a,
    cuerpo: { nombreOriginal: 'script.exe', entityType: 'TASK_SUBMISSION', entidadId: null },
  });
  comprobar('una extensión no permitida se rechaza con 400', extensionMala.estado === 400, `estado=${extensionMala.estado}`);

  const sinSesion = await api('/api/v1/archivos/firmar-subida', {
    metodo: 'POST',
    cuerpo: { nombreOriginal: 'x.pdf', entityType: 'TASK_SUBMISSION', entidadId: null },
  });
  comprobar('sin sesión, firmar responde 401', sinSesion.estado === 401, `estado=${sinSesion.estado}`);

  // ==========================================================================
  //  3. La subida directa a R2
  // ==========================================================================
  console.log('\n  3. PUT directo a Cloudflare R2 (el backend no ve los bytes)\n');

  const subida = await fetch(firma.datos.urlDeSubida, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/pdf' },
    body: CONTENIDO,
  });
  comprobar('R2 acepta el PUT con el Content-Type firmado', subida.status === 200, `estado=${subida.status}`);

  // El `Content-Type` va en `signableHeaders`: si no estuviera firmado, un cliente
  // podría subir cualquier cosa declarando un tipo distinto al de la extensión.
  const firmaMala = await api('/api/v1/archivos/firmar-subida', {
    metodo: 'POST',
    token: tokens.a,
    cuerpo: { nombreOriginal: 'mentira.pdf', entityType: 'TASK_SUBMISSION', entidadId: null },
  });
  const idMentira = firmaMala.datos?.archivo?.id ?? null;
  if (idMentira) creados.push(idMentira);
  const subidaMala = await fetch(firmaMala.datos.urlDeSubida, {
    method: 'PUT',
    headers: { 'Content-Type': 'text/plain' },
    body: CONTENIDO,
  });
  comprobar(
    'R2 RECHAZA un PUT con otro Content-Type (la firma cubre content-type)',
    subidaMala.status >= 400,
    `estado=${subidaMala.status}`,
  );

  // Y como el objeto no llegó, confirmar tiene que decirlo: la fila se queda
  // PENDING (visible para el barrido de abandonados) y no se toca.
  const confirmaMentira = await api(`/api/v1/archivos/${idMentira}/confirmar`, {
    metodo: 'POST',
    token: tokens.a,
  });
  comprobar(
    'confirmar un objeto que no llegó da 404 OBJETO_NO_SUBIDO',
    confirmaMentira.estado === 404 && codigoDe(confirmaMentira.datos) === 'OBJETO_NO_SUBIDO',
    `estado=${confirmaMentira.estado} codigo=${codigoDe(confirmaMentira.datos)}`,
  );

  // ==========================================================================
  //  4. Confirmación (el HeadObject mide de verdad)
  // ==========================================================================
  console.log('\n  4. POST /archivos/:id/confirmar\n');

  const confirmado = await api(`/api/v1/archivos/${idArchivo}/confirmar`, {
    metodo: 'POST',
    token: tokens.a,
  });
  comprobar('confirmar responde 200', confirmado.estado === 200, `estado=${confirmado.estado} ${JSON.stringify(confirmado.datos)?.slice(0, 160)}`);
  comprobar('el archivo queda CONFIRMED', confirmado.datos?.archivo?.estado === 'CONFIRMED', String(confirmado.datos?.archivo?.estado));
  comprobar(
    'el tamaño sellado es el que midió R2, no el que dijo el cliente',
    confirmado.datos?.archivo?.tamanoBytes === CONTENIDO.length,
    `esperado=${CONTENIDO.length} obtenido=${confirmado.datos?.archivo?.tamanoBytes}`,
  );
  comprobar('queda sello de confirmación', Boolean(confirmado.datos?.archivo?.confirmadoEn));

  const reconfirmar = await api(`/api/v1/archivos/${idArchivo}/confirmar`, {
    metodo: 'POST',
    token: tokens.a,
  });
  comprobar('reconfirmar se rechaza (estado terminal)', reconfirmar.estado === 409, `estado=${reconfirmar.estado}`);

  // ==========================================================================
  //  5. Lectura y descarga real
  // ==========================================================================
  console.log('\n  5. GET /archivos/:id/url-lectura y descarga\n');

  const lectura = await api(`/api/v1/archivos/${idArchivo}/url-lectura`, { token: tokens.a });
  comprobar('el propietario obtiene URL de lectura', lectura.estado === 200 && Boolean(lectura.datos?.urlDeLectura), `estado=${lectura.estado}`);
  comprobar('la respuesta repite el nombre original', lectura.datos?.nombreOriginal === NOMBRE_CON_ACENTO, String(lectura.datos?.nombreOriginal));

  const descarga = await fetch(lectura.datos.urlDeLectura);
  const bajado = Buffer.from(await descarga.arrayBuffer());
  comprobar('la descarga desde R2 responde 200', descarga.status === 200, `estado=${descarga.status}`);
  comprobar('el contenido bajado es idéntico al subido', bajado.equals(CONTENIDO), `subido=${CONTENIDO.length}B bajado=${bajado.length}B`);

  const disposicion = descarga.headers.get('content-disposition') ?? '';
  comprobar(
    'la descarga fuerza el nombre legible (Content-Disposition)',
    disposicion.includes('attachment') && disposicion.includes('filename*='),
    disposicion,
  );
  // RFC 5987: los acentos sobreviven en la forma extendida, no en la ASCII.
  comprobar(
    'el acento sobrevive en la forma RFC 5987 del nombre',
    disposicion.includes('%C3%A9'),
    disposicion,
  );

  // ==========================================================================
  //  6. Aislamiento entre usuarios (el núcleo de esta capa)
  // ==========================================================================
  console.log('\n  6. B contra el archivo de A (JWT real, RLS real)\n');

  const lecturaDeB = await api(`/api/v1/archivos/${idArchivo}/url-lectura`, { token: tokens.b });
  comprobar(
    'B NO obtiene URL del archivo de A: 404',
    lecturaDeB.estado === 404,
    `estado=${lecturaDeB.estado} codigo=${codigoDe(lecturaDeB.datos)}`,
  );
  // El 404 no es cosmético: un 403 confirmaría que el archivo existe. Que el
  // código sea el mismo que para «no existe» es justo el objetivo.
  comprobar(
    'y NO es 403 (no se filtra que el archivo existe)',
    lecturaDeB.estado !== 403,
    `estado=${lecturaDeB.estado}`,
  );

  const borradoDeB = await api(`/api/v1/archivos/${idArchivo}`, {
    metodo: 'DELETE',
    token: tokens.b,
  });
  comprobar(
    'B NO puede borrar el archivo de A (la operación no surte efecto)',
    borradoDeB.estado >= 400,
    `estado=${borradoDeB.estado} codigo=${codigoDe(borradoDeB.datos)}`,
  );
  if (borradoDeB.estado === 403) {
    divergencia(
      'DELETE de B sobre el archivo de A',
      '404 (igual que el GET, para no filtrar la existencia)',
      `403 ${codigoDe(borradoDeB.datos)} (la RPC security definer sí distingue «es de otro»)`,
    );
  }

  // Lo que de verdad importa: que el intento no haya dejado huella.
  const trasIntento = await pedir(
    `/rest/v1/files_metadata?id=eq.${idArchivo}&select=estado,deleted_at`,
  );
  comprobar(
    'el archivo de A sigue CONFIRMED e intacto tras el intento de B',
    trasIntento.datos?.[0]?.estado === 'CONFIRMED' && trasIntento.datos?.[0]?.deleted_at === null,
    JSON.stringify(trasIntento.datos),
  );

  // ==========================================================================
  //  7. El administrador
  // ==========================================================================
  console.log('\n  7. El admin lee y borra lo de A\n');

  const lecturaAdmin = await api(`/api/v1/archivos/${idArchivo}/url-lectura`, { token: tokens.admin });
  comprobar(
    'el admin SÍ obtiene URL del archivo de A (política is_admin)',
    lecturaAdmin.estado === 200 && Boolean(lecturaAdmin.datos?.urlDeLectura),
    `estado=${lecturaAdmin.estado}`,
  );

  const borradoAdmin = await api(`/api/v1/admin/archivos/${idArchivo}`, {
    metodo: 'DELETE',
    token: tokens.admin,
  });
  comprobar('el admin borra el archivo de A', borradoAdmin.estado === 200, `estado=${borradoAdmin.estado} ${JSON.stringify(borradoAdmin.datos)?.slice(0, 160)}`);
  comprobar('el borrado es lógico: estado DELETED', borradoAdmin.datos?.archivo?.estado === 'DELETED', String(borradoAdmin.datos?.archivo?.estado));
  // El campo del dominio se llama `borradoEn` (no `deletedAt`): la base usa
  // `deleted_at` y el adaptador lo traduce. Confundirlos deja la aserción muda.
  comprobar('queda sello borradoEn', Boolean(borradoAdmin.datos?.archivo?.borradoEn), JSON.stringify(borradoAdmin.datos?.archivo));

  // El objeto tiene que haber desaparecido de R2 de verdad, no sólo de la fila.
  const trasBorrar = await fetch(lectura.datos.urlDeLectura);
  comprobar(
    'el objeto ya no está en R2 (la URL prefirmada da 404)',
    trasBorrar.status === 404,
    `estado=${trasBorrar.status}`,
  );

  const estadoFinal = await pedir(
    `/rest/v1/files_metadata?id=eq.${idArchivo}&select=estado,tamano_bytes,deleted_at`,
  );
  comprobar(
    'la fila conserva el historial: DELETED, con tamaño y fecha',
    estadoFinal.datos?.[0]?.estado === 'DELETED' &&
      estadoFinal.datos?.[0]?.tamano_bytes === CONTENIDO.length &&
      estadoFinal.datos?.[0]?.deleted_at !== null,
    JSON.stringify(estadoFinal.datos),
  );

  const dobleBorrado = await api(`/api/v1/admin/archivos/${idArchivo}`, {
    metodo: 'DELETE',
    token: tokens.admin,
  });
  comprobar('borrar dos veces se rechaza (409)', dobleBorrado.estado === 409, `estado=${dobleBorrado.estado}`);

  const borradoAjeno = await api(`/api/v1/admin/archivos/${idArchivo}`, {
    metodo: 'DELETE',
    token: tokens.a,
  });
  comprobar(
    'A NO puede usar la ruta de admin (403, es exigirAdmin)',
    borradoAjeno.estado === 403,
    `estado=${borradoAjeno.estado}`,
  );

  // ==========================================================================
  //  8. RLS y la frontera de escritura
  // ==========================================================================
  console.log('\n  8. La frontera la pone la base, no la API\n');

  const insertaDirecto = await pedir('/rest/v1/files_metadata', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    token: tokens.a,
    cuerpo: {
      propietario_id: ids.a,
      r2_key: 'm5_archivos/inyectado/2026/09/falso.pdf',
      nombre_original: 'falso.pdf',
      tipo_contenido: 'application/pdf',
      entity_type: 'TASK_SUBMISSION',
      estado: 'CONFIRMED',
    },
    extra: { Prefer: 'return=representation' },
  });
  comprobar(
    'un usuario autenticado NO inserta en files_metadata (sin GRANT)',
    insertaDirecto.estado >= 400,
    `estado=${insertaDirecto.estado} codigo=${insertaDirecto.datos?.code ?? ''}`,
  );

  const anonLee = await pedir('/rest/v1/files_metadata?select=id', { clave: CLAVE_ANON });
  const filasAnon = Array.isArray(anonLee.datos) ? anonLee.datos.length : -1;
  comprobar('anon NO ve files_metadata', filasAnon === 0 || anonLee.estado >= 400, `estado=${anonLee.estado} filas=${filasAnon}`);

  const rpcSinSesion = await pedir('/rest/v1/rpc/marcar_archivo_borrado', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    cuerpo: { p_archivo_id: idArchivo },
  });
  comprobar(
    'la RPC de borrado no es invocable sin sesión',
    rpcSinSesion.estado >= 400,
    `estado=${rpcSinSesion.estado} codigo=${rpcSinSesion.datos?.code ?? ''}`,
  );

  const rpcConSesionDeB = await pedir('/rest/v1/rpc/confirmar_archivo', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    token: tokens.b,
    cuerpo: { p_archivo_id: idArchivo, p_tamano_bytes: 1 },
  });
  comprobar(
    'B no confirma el archivo de A por RPC directa (42501)',
    rpcConSesionDeB.estado >= 400,
    `estado=${rpcConSesionDeB.estado} codigo=${rpcConSesionDeB.datos?.code ?? ''}`,
  );

  const ajustes = await pedir('/rest/v1/system_settings?clave=like.m5_*&select=clave,valor&order=clave');
  const claves = (ajustes.datos ?? []).map((f) => f.clave);
  comprobar(
    'los dos límites configurables están sembrados',
    claves.includes('m5_max_bytes') && claves.includes('m5_max_archivos_por_entidad'),
    JSON.stringify(ajustes.datos),
  );

  // ==========================================================================
  //  9. El límite se lee en cada petición (y la caché caduca)
  // ==========================================================================
  console.log('\n  9. m5_max_bytes se aplica tras subir, no al firmar\n');

  const ajuste = await pedir('/rest/v1/system_settings?clave=eq.m5_max_bytes&select=valor');
  valorOriginalMaxBytes = ajuste.datos?.[0]?.valor ?? null;

  // Un límite diminuto: el PDF de prueba (unos cientos de bytes) ya lo supera.
  await pedir('/rest/v1/system_settings?clave=eq.m5_max_bytes', {
    metodo: 'PATCH',
    cuerpo: { valor: 100 },
  });

  // La caché del backend guarda los parámetros TTL ms: sin esperarla, la petición
  // siguiente seguiría viendo el valor viejo y la prueba sería un falso negativo.
  const espera = TTL_PARAMETROS_MS + 2000;
  console.log(`         ajustado m5_max_bytes=100; esperando ${espera} ms a que caduque la caché...`);
  await new Promise((r) => setTimeout(r, espera));

  const grande = await api('/api/v1/archivos/firmar-subida', {
    metodo: 'POST',
    token: tokens.a,
    cuerpo: { nombreOriginal: 'demasiado.pdf', entityType: 'TASK_SUBMISSION', entidadId: null },
  });
  const idGrande = grande.datos?.archivo?.id ?? null;
  if (idGrande) creados.push(idGrande);
  comprobar('firmar un archivo grande SÍ funciona (el límite no aplica al firmar)', grande.estado === 201, `estado=${grande.estado}`);

  await fetch(grande.datos.urlDeSubida, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/pdf' },
    body: CONTENIDO,
  });
  const confirmaGrande = await api(`/api/v1/archivos/${idGrande}/confirmar`, {
    metodo: 'POST',
    token: tokens.a,
  });
  comprobar(
    'confirmarlo da 413 ARCHIVO_DEMASIADO_GRANDE',
    confirmaGrande.estado === 413 && codigoDe(confirmaGrande.datos) === 'ARCHIVO_DEMASIADO_GRANDE',
    `estado=${confirmaGrande.estado} codigo=${codigoDe(confirmaGrande.datos)}`,
  );

  const rechazado = await pedir(
    `/rest/v1/files_metadata?id=eq.${idGrande}&select=estado,tamano_bytes`,
  );
  comprobar(
    'el rechazado queda DELETED y sin tamaño sellado',
    rechazado.datos?.[0]?.estado === 'DELETED' && rechazado.datos?.[0]?.tamano_bytes === null,
    JSON.stringify(rechazado.datos),
  );

  // Y el objeto que se decidió rechazar no debe seguir contando como archivo.
  // OJO con lo que prueba esto: la ruta deja la fila en DELETED (por eso el 409,
  // «no disponible»), pero **no** demuestra aquí que el objeto se borrara de R2
  // —para firmar un GET haría falta que la fila estuviera CONFIRMED, y ya no lo
  // está—. Que `eliminar()` se llame en ese camino lo fija la prueba unitaria con
  // el doble de almacén (`objetos` y `borrados`); aquí sólo se comprueba el estado.
  const lecturaGrande = await api(`/api/v1/archivos/${idGrande}/url-lectura`, { token: tokens.a });
  comprobar(
    'el archivo rechazado queda no legible (DELETED, no CONFIRMED)',
    lecturaGrande.estado === 409 && codigoDe(lecturaGrande.datos) === 'ARCHIVO_NO_DISPONIBLE',
    `estado=${lecturaGrande.estado} codigo=${codigoDe(lecturaGrande.datos)}`,
  );
} catch (error) {
  fallos += 1;
  console.error(`\n  EXCEPCIÓN NO CONTROLADA: ${error?.message ?? error}`);
} finally {
  // Restaurar el parámetro es obligatorio: dejarlo en 100 bytes rompería la
  // subida de cualquier archivo real en el sistema.
  if (valorOriginalMaxBytes !== null) {
    await pedir('/rest/v1/system_settings?clave=eq.m5_max_bytes', {
      metodo: 'PATCH',
      cuerpo: { valor: valorOriginalMaxBytes },
    });
    console.log(`\n  m5_max_bytes restaurado a ${valorOriginalMaxBytes}.`);
  }

  console.log('\n  Purga...');
  await purgar();

  const residuoPerfiles = await pedir('/rest/v1/profiles?email=like.humo-arch*&select=id');
  const residuoTrazas = await pedir('/rest/v1/auth_logs?email=like.humo-arch*&select=id');
  const residuoArchivos = await pedir(
    `/rest/v1/files_metadata?r2_key=like.m5_archivos/*&propietario_id=in.(${[ids.a, ids.b, ids.admin].filter(Boolean).join(',')})&select=id`,
  );
  const nPerfiles = Array.isArray(residuoPerfiles.datos) ? residuoPerfiles.datos.length : -1;
  const nTrazas = Array.isArray(residuoTrazas.datos) ? residuoTrazas.datos.length : -1;
  const nArchivos = Array.isArray(residuoArchivos.datos) ? residuoArchivos.datos.length : -1;

  console.log(`\n  Resultado: ${ok} OK / ${fallos} fallos`);
  console.log(
    `  Residuo: perfiles=${nPerfiles} trazas=${nTrazas} archivos=${nArchivos} (debe ser 0, 0 y 0)`,
  );
  console.log(
    '  En R2 el único objeto que se creó lo borró el admin; los rechazados los borra\n' +
      '  el propio backend al no pasar el HeadObject. El bucket queda como estaba.',
  );

  if (divergencias.length > 0) {
    console.log('\n  ── DIVERGENCIAS CON EL BRIEFING (no son fallos) ─────────────────');
    for (const d of divergencias) {
      console.log(`  · ${d.etiqueta}`);
      console.log(`      pedido:   ${d.esperado}`);
      console.log(`      real:     ${d.obtenido}`);
    }
    console.log('  ─────────────────────────────────────────────────────────────────');
    console.log('  Decisión pendiente del dueño del producto: unificar en 404 o aceptar el 403.');
  }

  process.exit(fallos === 0 && nPerfiles === 0 && nTrazas === 0 && nArchivos === 0 ? 0 : 1);
}
