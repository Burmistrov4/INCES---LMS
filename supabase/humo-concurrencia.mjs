/**
 * Humo de CONCURRENCIA del Módulo 4 — el cerrojo de cupo, aislado y bajo estrés.
 *
 * QUÉ PRUEBA
 * ----------
 * UNA sola cosa, y la prueba N veces: que `pg_advisory_xact_lock` serializa la
 * decisión de cupo cuando dos solicitudes llegan EN EL MISMO INSTANTE por el
 * último asiento de una sección.
 *
 * `humo-inscripciones.mjs` ya dispara dos peticiones simultáneas, pero lo hace
 * como UNA fase dentro de un recorrido de siete; si esa fase sale roja, el
 * diagnóstico se mezcla con el de la cola, las ofertas y la reincorporación.
 * Este script existe para que el cerrojo tenga una prueba propia, repetible
 * (`--repeticiones=N`) y con un veredicto que no admite matices: **cero dobles
 * ventas en N carreras**.
 *
 * CÓMO SE CONSTRUYE EL CASO
 * -------------------------
 *   1. Se asegura que la sección tenga EXACTAMENTE UN asiento libre. No se
 *      supone: se LEE `cupoEfectivo`, `cuposOcupados` y `cuposDisponibles` de
 *      la ruta de ocupación del administrador y se comprueba que sean 1, 0 y 1.
 *      Si la sección no está así de limpia, la carrera no probaría nada.
 *   2. Dos estudiantes DISTINTOS —cédula distinta, correo distinto, JWT real
 *      distinto— construyen cada uno su solicitud válida para ESA sección.
 *   3. Los dos `fetch` se construyen en el MISMO tick (`Promise.all` sobre dos
 *      promesas ya creadas), así que salen a la vez de verdad y no uno detrás
 *      del otro. Si salieran en serie el humo pasaría siempre y no probaría nada.
 *   4. Se exige: exactamente un `ENROLLED` y exactamente un `WAITLISTED`, y que
 *      la BASE confirme un solo asiento vendido (`count(ENROLLED) === 1`).
 *
 * POR QUÉ ESTE SCRIPT **NO** ESPERA UN 409
 * ----------------------------------------
 * Porque el código dice que no lo hay, y el código gana.
 *
 *   · `backend/src/http/rutas/inscripciones.ts:99-105` responde SIEMPRE
 *     `201`, con el estado resultante en el cuerpo:
 *         return reply.status(201).send({ estado, mensaje });
 *     El comentario de esa misma línea lo explica: «201: se creó una
 *     inscripción, y el estado resultante dice si entró o quedó en la cola».
 *     Llenar la sección NO es un error: es la cola. Un 409 sería mentira.
 *   · `supabase/humo-inscripciones.mjs` ya certifica esa misma verdad
 *     (`comprobar('… las dos peticiones responden 201', rAlfa.estado === 201 &&
 *     rBeta.estado === 201)`).
 *
 * El 409 del proyecto existe, pero para OTRA cosa: choques de agenda
 * (`CHOQUE_DE_AGENDA`), registros duplicados (`REGISTRO_DUPLICADO`) y módulos
 * críticos. Un script que exigiera 409 aquí estaría rojo en su primera corrida
 * por un requisito mal medido, no por un fallo del cerrojo. **La prueba real de
 * la serialización es que no haya DOS `ENROLLED`**, y es lo que se mide.
 *
 * CÓMO FUNCIONA
 * -------------
 * Escribe en la base real, así que exige `--confirmar`. Crea un admin y dos
 * estudiantes —todo con sufijo del reloj— y lo purga TODO al final, también si
 * falla a mitad. Las credenciales se leen del entorno y, si no están, de
 * `backend/.env`. La URL del backend sale de `API_BASE_URL` y, si no está, del
 * `PORT` de `backend/.env` (3001 en este proyecto).
 *
 * NO toca `system_settings`. A diferencia de `humo-inscripciones.mjs` —que
 * enciende y apaga `habilitar_sistema_bids` para probar la promoción—, este humo
 * no depende de ese ajuste: la solicitud INICIAL de una inscripción nunca pasa
 * por bids (lo dice `solicitar_inscripcion`: «con hueco, directo a ENROLLED (los
 * bids sólo actúan al liberarse un cupo, no en la solicitud inicial)»). Un humo
 * que no necesita mutar un ajuste global no debe mutarlo.
 *
 * FUERA DE CI A PROPÓSITO: toca la base real. Es una herramienta de verificación
 * manual, como `humo-inscripciones.mjs` y `humo-cuadrante.mjs`.
 *
 * USO
 * ---
 *   node supabase/humo-concurrencia.mjs                     # simulación (no escribe)
 *   node supabase/humo-concurrencia.mjs --confirmar         # la prueba, 10 carreras
 *   node supabase/humo-concurrencia.mjs --confirmar --repeticiones=25
 */
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const CONFIRMAR = process.argv.includes('--confirmar');

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

/** Lee un argumento numérico con forma `--nombre=valor`. */
function argumento(nombre, porDefecto) {
  const encontrado = process.argv.find((a) => a.startsWith(`--${nombre}=`));
  if (!encontrado) return porDefecto;
  const valor = Number(encontrado.slice(nombre.length + 3));
  return Number.isFinite(valor) ? valor : porDefecto;
}

const URL_BASE = variable('SUPABASE_URL');
const CLAVE_SERVICIO = variable('SUPABASE_SERVICE_ROLE_KEY');
const CLAVE_ANON = variable('SUPABASE_ANON_KEY');
const API = (
  process.env.API_BASE_URL ?? `http://localhost:${variable('PORT') || '3001'}`
).replace(/\/+$/, '');

// Diez carreras es el valor por defecto: bastante para que una carrera perdida
// se note, poco para que el humo siga siendo algo que se corre sin pensar.
const REPETICIONES = Math.min(Math.max(argumento('repeticiones', 10), 1), 200);

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

/** Petición cruda a Supabase (REST o GoTrue): estado + cuerpo, sin lanzar por HTTP. */
async function pedir(ruta, { metodo = 'GET', cuerpo, clave, token, extra = {} } = {}) {
  const cabeceras = {
    apikey: clave ?? CLAVE_SERVICIO,
    'Content-Type': 'application/json',
    ...extra,
  };
  if (token) cabeceras.Authorization = `Bearer ${token}`;
  else if (clave ?? CLAVE_SERVICIO) cabeceras.Authorization = `Bearer ${clave ?? CLAVE_SERVICIO}`;

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

/**
 * Petición al backend. **Sólo lleva el JWT**: el backend resuelve la sesión con
 * él y no necesita la clave anónima, que es lo que hace el cliente Flutter.
 *
 * `Content-Type` se declara sólo si hay cuerpo: mandarlo con cuerpo vacío hace
 * que Fastify responda `FST_ERR_CTP_EMPTY_JSON_BODY`.
 */
async function api(ruta, { metodo = 'GET', token, cuerpo } = {}) {
  const cabeceras = {};
  if (token) cabeceras.Authorization = `Bearer ${token}`;

  const opciones = { method: metodo, headers: cabeceras };
  if (cuerpo !== undefined) {
    cabeceras['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(cuerpo);
  }

  const r = await fetch(`${API}${ruta}`, opciones);
  const texto = await r.text();
  let datos = null;
  try {
    datos = texto.length > 0 ? JSON.parse(texto) : null;
  } catch {
    datos = texto;
  }
  return { estado: r.status, datos };
}

if (!URL_BASE || !CLAVE_SERVICIO || !CLAVE_ANON) {
  console.error('\n  Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY.');
  console.error('  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n');
  process.exit(1);
}

const SUF = Date.now().toString().slice(-6);
const MARCA = Date.now();
const CLAVE = `Humo!${randomBytes(12).toString('base64url')}`;

const COD_MATERIA = `TSC${SUF}`;
const COD_PROGRAMA = `TPC${SUF}`;
// `sections.name` es varchar(5): dos letras + tres dígitos del reloj.
const NOMBRE_SECCION = `HC${SUF.slice(-3)}`;

// Cédulas distintas y correos distintos: dos identidades reales, no dos tokens
// del mismo usuario. Es lo que hace que la carrera sea una carrera.
const CEDULAS = {
  admin: `90${SUF}`,
  alfa: `91${SUF}`,
  beta: `92${SUF}`,
};
const CORREOS = {
  admin: `humo-conc-admin-${MARCA}@ejemplo.invalid`,
  alfa: `humo-conc-alfa-${MARCA}@ejemplo.invalid`,
  beta: `humo-conc-beta-${MARCA}@ejemplo.invalid`,
};

/** Todo lo que se crea, para purgarlo en orden inverso de dependencia. */
const creado = {
  usuarios: [],
  materia: null,
  programa: null,
  seccion: null,
};

console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Backend  : ${API}`);
console.log(`  Sufijo   : ${SUF}`);
console.log(`  Carreras : ${REPETICIONES}`);
console.log(`  Modo     : ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);

if (!CONFIRMAR) {
  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  console.log(`\n  Backend ${salud === null ? 'NO responde' : `responde ${salud}`}.`);
  console.log('  Simulación: este humo ESCRIBE en la base real (un admin, dos');
  console.log('  estudiantes, una materia, un programa y una sección de UN asiento)');
  console.log('  y lo borra al final.');
  console.log('  Repite con --confirmar.\n');
  process.exit(0);
}

/**
 * Crea un usuario sin enviar correo y le fija el rol. Devuelve su id.
 *
 * `user_metadata` lleva `cedula`, `nombres` y `apellidos`: es lo que
 * `handle_new_user` vuelca a `profiles`. Sin la cédula, los dos estudiantes
 * serían «anónimos» con el mismo perfil vacío y el humo perdería el punto de
 * que son personas distintas.
 */
async function crearUsuario(correo, rol, { cedula, nombres, apellidos }) {
  const alta = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: {
      email: correo,
      password: CLAVE,
      email_confirm: true,
      user_metadata: { cedula, nombres, apellidos },
    },
  });
  const id = alta.datos?.id ?? null;
  if (!id) throw new Error(`no se pudo crear ${correo}: ${JSON.stringify(alta.datos)}`);
  creado.usuarios.push(id);

  // `handle_new_user` lo deja como `estudiante`. Sólo el admin se promueve.
  if (rol !== 'estudiante') {
    const promovido = await pedir(`/rest/v1/profiles?id=eq.${id}`, {
      metodo: 'PATCH',
      cuerpo: { rol },
      extra: { Prefer: 'return=representation' },
    });
    if (promovido.datos?.[0]?.rol !== rol) {
      throw new Error(`no se pudo promover ${correo} a ${rol}: ${JSON.stringify(promovido.datos)}`);
    }
  }
  return id;
}

/** Inicia sesión con contraseña y devuelve un JWT real. */
async function iniciarSesion(correo) {
  const sesion = await pedir('/auth/v1/token?grant_type=password', {
    metodo: 'POST',
    clave: CLAVE_ANON,
    cuerpo: { email: correo, password: CLAVE },
  });
  const token = sesion.datos?.access_token ?? null;
  if (!token) throw new Error(`sin JWT para ${correo}: ${JSON.stringify(sesion.datos)}`);
  return token;
}

/**
 * Vacía la sección y CONFIRMA que quedó vacía.
 *
 * Se hace con la service role key porque `enrollments` tiene la escritura
 * revocada para `authenticated` (R-23) — es justamente el cerrojo que este humo
 * valida, así que no se puede usar el camino normal para deshacer.
 */
async function limpiarInscripciones() {
  await pedir(`/rest/v1/enrollments?section_id=eq.${creado.seccion}`, { metodo: 'DELETE' });
  const quedan = await pedir(`/rest/v1/enrollments?section_id=eq.${creado.seccion}&select=id`);
  const n = Array.isArray(quedan.datos) ? quedan.datos.length : -1;
  return { ok: n === 0, quedan: n };
}

/** Fila de ocupación de la sección de prueba, leída por la ruta de administración. */
async function ocupacion(tokenAdmin, materiaId) {
  const r = await api(`/api/v1/admin/ocupacion?materiaId=${materiaId}&limite=100`, {
    token: tokenAdmin,
  });
  const fila = (r.datos?.secciones ?? []).find((s) => s.seccionId === creado.seccion) ?? null;
  return { fila, estado: r.estado };
}

/** Cuántas filas hay en la sección en un estado dado, leído de la BASE. */
async function contarEstado(estado) {
  const r = await pedir(
    `/rest/v1/enrollments?section_id=eq.${creado.seccion}&status=eq.${estado}&select=id`,
  );
  return Array.isArray(r.datos) ? r.datos.length : -1;
}

/** Purga todo lo creado, en orden inverso de dependencia. Se corre siempre. */
async function purgar() {
  if (creado.seccion) {
    await pedir(`/rest/v1/enrollments?section_id=eq.${creado.seccion}`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/sections?id=eq.${creado.seccion}`, { metodo: 'DELETE' });
  }
  if (creado.programa) await pedir(`/rest/v1/programs?id=eq.${creado.programa}`, { metodo: 'DELETE' });
  if (creado.materia) await pedir(`/rest/v1/subjects?id=eq.${creado.materia}`, { metodo: 'DELETE' });
  for (const id of creado.usuarios) {
    await pedir(`/auth/v1/admin/users/${id}`, { metodo: 'DELETE' });
  }
  // Barrido por si un fallo a mitad dejó algo suelto.
  await pedir(`/rest/v1/sections?name=eq.${NOMBRE_SECCION}`, { metodo: 'DELETE' });
  await pedir(`/rest/v1/programs?code=eq.${COD_PROGRAMA}`, { metodo: 'DELETE' });
  await pedir(`/rest/v1/subjects?code=eq.${COD_MATERIA}`, { metodo: 'DELETE' });
  for (const correo of Object.values(CORREOS)) {
    await pedir(`/rest/v1/profiles?email=eq.${correo}`, { metodo: 'DELETE' });
  }
}

try {
  // --- 1. Identidades y datos base -------------------------------------------
  console.log('\n  1. Identidades, datos base y una sección de UN asiento\n');

  const idAdmin = await crearUsuario(CORREOS.admin, 'admin', {
    cedula: CEDULAS.admin,
    nombres: 'Humo',
    apellidos: 'Concurrencia',
  });
  const idAlfa = await crearUsuario(CORREOS.alfa, 'estudiante', {
    cedula: CEDULAS.alfa,
    nombres: 'Alfa',
    apellidos: 'Carrera',
  });
  const idBeta = await crearUsuario(CORREOS.beta, 'estudiante', {
    cedula: CEDULAS.beta,
    nombres: 'Beta',
    apellidos: 'Carrera',
  });
  comprobar('un admin y dos estudiantes temporales', Boolean(idAdmin && idAlfa && idBeta));
  comprobar('los dos estudiantes tienen CÉDULA distinta', CEDULAS.alfa !== CEDULAS.beta);

  const tokenAdmin = await iniciarSesion(CORREOS.admin);
  const tokenAlfa = await iniciarSesion(CORREOS.alfa);
  const tokenBeta = await iniciarSesion(CORREOS.beta);
  comprobar('tres JWT reales', Boolean(tokenAdmin && tokenAlfa && tokenBeta));
  comprobar(
    'los JWT de los dos estudiantes son distintos',
    tokenAlfa !== tokenBeta,
    'dos identidades distintas, no dos tokens del mismo usuario',
  );

  const ajuste = await pedir('/rest/v1/system_settings?clave=eq.periodo_activo&select=valor');
  const periodo = typeof ajuste.datos?.[0]?.valor === 'string' ? ajuste.datos[0].valor : null;
  comprobar('hay un lapso vigente declarado', Boolean(periodo), `valor=${periodo}`);

  const bids = await pedir('/rest/v1/system_settings?clave=eq.habilitar_sistema_bids&select=valor');
  console.log(
    `         habilitar_sistema_bids = ${bids.datos?.[0]?.valor} (irrelevante aquí: la ` +
      'solicitud inicial no pasa por bids)',
  );

  const materia = await pedir('/rest/v1/subjects', {
    metodo: 'POST',
    cuerpo: { code: COD_MATERIA, name: `Humo concurrencia materia ${SUF}`, academic_hours: 48 },
    extra: { Prefer: 'return=representation' },
  });
  creado.materia = materia.datos?.[0]?.id ?? null;
  comprobar('materia temporal creada', Boolean(creado.materia), `estado=${materia.estado}`);

  const programa = await pedir('/rest/v1/programs', {
    metodo: 'POST',
    cuerpo: { code: COD_PROGRAMA, name: `Humo concurrencia programa ${SUF}`, type: 'CARRERA', is_active: false },
    extra: { Prefer: 'return=representation' },
  });
  creado.programa = programa.datos?.[0]?.id ?? null;
  comprobar('programa temporal creado (inactivo, sin pensum)', Boolean(creado.programa), `estado=${programa.estado}`);

  const alta = await api('/api/v1/admin/secciones', {
    metodo: 'POST',
    token: tokenAdmin,
    cuerpo: {
      programaId: creado.programa,
      materiaId: creado.materia,
      periodo,
      nombre: NOMBRE_SECCION,
      cupoMaximo: 1,
    },
  });
  creado.seccion = alta.datos?.seccion?.id ?? null;
  comprobar(
    'el admin crea la sección de capacidad 1 por POST /admin/secciones',
    alta.estado === 201 && Boolean(creado.seccion),
    `estado=${alta.estado} ${JSON.stringify(alta.datos)?.slice(0, 200)}`,
  );

  // --- 2. La precondición: EXACTAMENTE un asiento libre -----------------------
  console.log('\n  2. La precondición — la sección tiene EXACTAMENTE un asiento libre\n');

  const ocupacionInicial = await ocupacion(tokenAdmin, creado.materia);
  comprobar(
    'cupoEfectivo = 1',
    ocupacionInicial.fila?.cupoEfectivo === 1,
    `cupoEfectivo=${ocupacionInicial.fila?.cupoEfectivo}`,
  );
  comprobar(
    'cuposOcupados = 0 (no se supone: se lee)',
    ocupacionInicial.fila?.cuposOcupados === 0,
    `cuposOcupados=${ocupacionInicial.fila?.cuposOcupados}`,
  );
  comprobar(
    'cuposDisponibles = 1',
    ocupacionInicial.fila?.cuposDisponibles === 1,
    `cuposDisponibles=${ocupacionInicial.fila?.cuposDisponibles}`,
  );
  comprobar(
    'no hay ninguna oferta viva que enturbie la carrera',
    ocupacionInicial.fila?.ofertaVigente === false,
    `ofertaVigente=${ocupacionInicial.fila?.ofertaVigente}`,
  );

  // --- 3. LA CARRERA ---------------------------------------------------------
  console.log('\n  3. LA CARRERA — dos POST /api/v1/inscripciones en el mismo tick\n');
  console.log('     Dos identidades distintas, un asiento. Sin pg_advisory_xact_lock');
  console.log('     los dos leerían «0 ocupados < 1 de cupo» y los dos entrarían a');
  console.log('     ENROLLED: dos personas en un asiento de uno.\n');

  let ganadosPorAlfa = 0;
  let doblesVentas = 0;
  let ambasEnrolled = 0;

  for (let i = 1; i <= REPETICIONES; i += 1) {
    const limpio = await limpiarInscripciones();
    if (!limpio.ok) {
      comprobar(`carrera ${i}: la sección arranca vacía`, false, `quedaron ${limpio.quedan} fila(s)`);
      continue;
    }

    // Los dos `fetch` se construyen en el MISMO tick, antes de que ninguno
    // espere: salen a la vez de verdad, no uno detrás del otro.
    const [rAlfa, rBeta] = await Promise.all([
      api('/api/v1/inscripciones', {
        metodo: 'POST',
        token: tokenAlfa,
        cuerpo: { seccionId: creado.seccion },
      }),
      api('/api/v1/inscripciones', {
        metodo: 'POST',
        token: tokenBeta,
        cuerpo: { seccionId: creado.seccion },
      }),
    ]);

    const eAlfa = rAlfa.datos?.estado ?? `HTTP ${rAlfa.estado}`;
    const eBeta = rBeta.datos?.estado ?? `HTTP ${rBeta.estado}`;
    const matriculados = await contarEstado('ENROLLED');

    if (eAlfa === 'ENROLLED') ganadosPorAlfa += 1;
    if (eAlfa === 'ENROLLED' && eBeta === 'ENROLLED') ambasEnrolled += 1;
    if (matriculados > 1) doblesVentas += 1;

    console.log(`     carrera ${i}: alfa=${eAlfa} beta=${eBeta} · ENROLLED en la base=${matriculados}`);

    // El contrato REAL: 201 en las dos, con el estado en el cuerpo. No es 409 —
    // ver la cabecera de este archivo.
    comprobar(
      `carrera ${i}: las dos peticiones responden 201`,
      rAlfa.estado === 201 && rBeta.estado === 201,
      `alfa=${rAlfa.estado} beta=${rBeta.estado}`,
    );
    comprobar(
      `carrera ${i}: exactamente un ENROLLED y un WAITLISTED`,
      [eAlfa, eBeta].sort().join('|') === 'ENROLLED|WAITLISTED',
      `alfa=${eAlfa} beta=${eBeta}`,
    );
    // LA ASERCIÓN QUE JUSTIFICA EL CERROJO.
    comprobar(
      `carrera ${i}: la BASE confirma UN solo asiento vendido`,
      matriculados === 1,
      `ENROLLED=${matriculados}`,
    );
  }

  // --- 4. El veredicto -------------------------------------------------------
  console.log('\n  4. El veredicto\n');
  comprobar(
    `en ${REPETICIONES} carrera(s) NUNCA hubo dos ENROLLED en el asiento`,
    doblesVentas === 0,
    `${doblesVentas} doble(s) venta(s)`,
  );
  comprobar(
    `en ${REPETICIONES} carrera(s) NUNCA las dos peticiones entraron a ENROLLED`,
    ambasEnrolled === 0,
    `${ambasEnrolled} carrera(s) con las dos dentro`,
  );
  // El ganador no tiene por qué ser siempre el mismo: si lo fuera, sospecharía
  // más de un orden de llegada impuesto por el cliente que del cerrojo.
  console.log(
    `         ganó alfa ${ganadosPorAlfa}/${REPETICIONES} veces (reparto esperado: aleatorio)`,
  );

  console.log('\n  5. Limpieza\n');
} catch (error) {
  fallos += 1;
  console.error(`  [FALLA] excepción: ${error?.message ?? error}`);
} finally {
  await purgar();

  // El residuo se comprueba, no se supone: una purga que falla en silencio deja
  // basura en producción y el humo diría «verde».
  const residuoPerfiles = await pedir('/rest/v1/profiles?email=like.humo-conc-*&select=id');
  const residuoSeccion = await pedir(`/rest/v1/sections?name=eq.${NOMBRE_SECCION}&select=id`);
  const residuoMateria = await pedir(`/rest/v1/subjects?code=eq.${COD_MATERIA}&select=id`);
  const residuoPrograma = await pedir(`/rest/v1/programs?code=eq.${COD_PROGRAMA}&select=id`);
  const nPerfiles = Array.isArray(residuoPerfiles.datos) ? residuoPerfiles.datos.length : -1;
  const nSeccion = Array.isArray(residuoSeccion.datos) ? residuoSeccion.datos.length : -1;
  const nMateria = Array.isArray(residuoMateria.datos) ? residuoMateria.datos.length : -1;
  const nPrograma = Array.isArray(residuoPrograma.datos) ? residuoPrograma.datos.length : -1;

  comprobar(
    'la purga no dejó residuo (perfiles, sección, materia, programa)',
    nPerfiles === 0 && nSeccion === 0 && nMateria === 0 && nPrograma === 0,
    `perfiles=${nPerfiles} sección=${nSeccion} materia=${nMateria} programa=${nPrograma}`,
  );

  console.log(
    `\n  ${fallos === 0 ? `✓ Cerrojo verificado — ${ok} comprobaciones en verde, ${REPETICIONES} carrera(s) sin doble venta.` : `✗ ${fallos} comprobación(es) fallida(s), ${ok} en verde.`}\n`,
  );
  process.exit(fallos === 0 ? 0 : 1);
}
