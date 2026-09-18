/**
 * Humo de integración del Módulo 4 (Inscripciones y cupos).
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que las 428 pruebas del backend NO pueden verificar, porque usan dobles en
 * memoria: que el motor real (PostgREST + el cerrojo de Postgres + Fastify) se
 * comporte como el doble predijo.
 *
 *   1. **EL CERROJO DE CONCURRENCIA, de verdad.** Dos `POST /api/v1/inscripciones`
 *      simultáneos contra una sección de capacidad 1. Sólo un doble puede fingir
 *      que dos peticiones llegan a la vez; aquí llegan. Si
 *      `pg_advisory_xact_lock` no serializara la decisión, las dos leerían
 *      «0 ocupados < 1 de cupo» y las dos entrarían a `ENROLLED`: dos personas
 *      en un asiento de uno.
 *
 *   2. **EL GUARDIÁN DE DOBLE VENTA.** Es el fallo que la regla institucional
 *      «una solicitud pendiente no reserva cupo» introduce por sí sola:
 *        capacidad 1 · A renuncia → hueco · se promueve a B (PENDING_BID)
 *        → `cupos_ocupados` = 0 (B no cuenta) → C entra directo a ENROLLED
 *        → B acepta → ENROLLED. DOS personas en un asiento de uno.
 *      `existe_oferta_vigente()` es la barrera, y aquí se comprueba que C queda
 *      en `WAITLISTED` aunque la vista diga «1 disponible».
 *
 *   3. **La vista puede decir «1 disponible» y NO ser inscribible.** Es el caso
 *      que obliga a la interfaz a mirar `ofertaVigente` y no `cuposDisponibles`.
 *      Se comprueban los dos campos a la vez, en el mismo instante.
 *
 *   4. **Las dos ramas de la promoción**, porque el proyecto corre con las dos:
 *      con `habilitar_sistema_bids = false` (el valor por defecto, y el que hay
 *      en producción) promover deja al siguiente DIRECTO en `ENROLLED`; con
 *      bids encendido lo deja en `PENDING_BID` con vencimiento, y hay una oferta
 *      que aceptar. Probar sólo una dejaría la otra sin cubrir.
 *
 *   5. **`expirar_ofertas_cupo` es idempotente y promueve en cascada.** Se fuerza
 *      el vencimiento, se barre, y la segunda llamada devuelve 0.
 *
 *   6. **Renunciar ya promueve, y eso cambia el panel del administrador.**
 *      `renunciar_cupo` llama a `promover_siguiente_de_cola` dentro de su propia
 *      transacción: cuando el administrador pulsa «Promover Siguiente» después de
 *      una baja, la promoción ya ocurrió y la RPC responde 200 con `promovida:
 *      null`. El botón no es el camino normal para mover la cola; su uso real es
 *      otro —**ampliar el cupo** y subir a mano a quien espera— y aquí se prueba
 *      ese caso, que es el único en el que tiene trabajo que hacer.
 *
 *   7. **La reincorporación EXCEDE la capacidad a propósito.** «Si el
 *      administrador autoriza, el sistema obedece»: se deja la sección llena y
 *      se reincorpora a un `DROPPED`, y `cupos_ocupados` queda por encima de
 *      `cupo_efectivo` sin que la vista devuelva un disponible negativo.
 *
 *   8. **El contrato HTTP que consumirá Flutter**: `posicionEnCola` de
 *      `mis-inscripciones` y `ofertaVigente` de `ofertas`, que son los dos
 *      campos sobre los que decide la interfaz. Y una trampa de transporte: las
 *      rutas POST sin cuerpo (`renunciar`, `aceptar`, `promover`, `expirar`)
 *      **no deben** llevar `Content-Type: application/json`, o Fastify responde
 *      `FST_ERR_CTP_EMPTY_JSON_BODY`.
 *
 * CÓMO FUNCIONA
 * -------------
 * Escribe en producción, así que exige `--confirmar`. Crea tres usuarios, una
 * materia, un programa y UNA sección de capacidad 1 —todo con sufijo del reloj—
 * y lo purga TODO al final, también si falla a mitad.
 *
 * Las fases comparten la misma sección y se limpian entre ellas. **No es un
 * descuido**: el trigger `enrollments_seccion_unica_por_materia` impide que un
 * estudiante tenga dos secciones vivas de la misma materia en el mismo lapso, así
 * que dejar inscripciones de una fase contaminaría la siguiente. Cada fase
 * arranca comprobando que la sección está vacía.
 *
 * `habilitar_sistema_bids` se enciende y se apaga según lo que pruebe cada fase.
 * El valor original se lee al empezar y se restaura en la purga, pase lo que pase.
 *
 * Las inscripciones se escriben **con el JWT real de cada estudiante** y a través
 * de la API, nunca con la service role key: la tabla tiene `INSERT`, `UPDATE`,
 * `DELETE` y `TRUNCATE` revocados para `authenticated` (R-23), y el objetivo es
 * justamente comprobar que el único camino —las RPC `security definer`— funciona.
 * La service role sólo se usa para preparar datos y para forzar un vencimiento.
 *
 * FUERA DE CI A PROPÓSITO: toca la base real. Es una herramienta de verificación
 * manual, como `humo-invitaciones.mjs`, `humo-curriculo.mjs` y `humo-cuadrante.mjs`.
 *
 * USO
 * ---
 *   node supabase/humo-inscripciones.mjs                    # simulación (no escribe)
 *   node supabase/humo-inscripciones.mjs --confirmar        # ejecuta el humo
 *   node supabase/humo-inscripciones.mjs --confirmar --repeticiones=5
 *
 * Las credenciales se leen del entorno y, si no están, de `backend/.env`. La URL
 * del backend sale de `API_BASE_URL` y, si no está, del `PORT` de `backend/.env`
 * (3000 en este proyecto, no el 8080 de los otros humos): el puerto cambió una vez
 * y el script no debería volver a romperse por eso.
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
  process.env.API_BASE_URL ?? `http://localhost:${variable('PORT') || '3000'}`
).replace(/\/+$/, '');

// Acotado a 9 porque el nombre de la sección es `varchar(5)` y sólo se usa para
// etiquetar la corrida; más repeticiones no caben sin cambiar el nombre.
const REPETICIONES = Math.min(Math.max(argumento('repeticiones', 3), 1), 9);

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
 * ⚠️ `Content-Type` se declara **sólo si hay cuerpo**. Varias rutas de M4 son
 * POST sin cuerpo (`renunciar`, `aceptar`, `promover`, `expirar`) y mandarles
 * `Content-Type: application/json` con el cuerpo vacío hace que Fastify responda
 * `FST_ERR_CTP_EMPTY_JSON_BODY` — un 500 que no tiene nada que ver con la lógica
 * de cupos. Es una trampa real para el cliente Flutter, no un detalle del humo.
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

const COD_MATERIA = `TS4${SUF}`;
const COD_PROGRAMA = `TP4${SUF}`;
// `sections.name` es varchar(5): dos letras de fase + tres dígitos del reloj.
const NOMBRE_SECCION = `HM${SUF.slice(-3)}`;

const CORREOS = {
  admin: `humo4-admin-${MARCA}@ejemplo.invalid`,
  alfa: `humo4-alfa-${MARCA}@ejemplo.invalid`,
  beta: `humo4-beta-${MARCA}@ejemplo.invalid`,
  gamma: `humo4-gamma-${MARCA}@ejemplo.invalid`,
};

/** Todo lo que se crea, para purgarlo en orden inverso de dependencia. */
const creado = {
  usuarios: [],
  materia: null,
  programa: null,
  seccion: null,
  bidsOriginal: null,
  periodo: null,
};

console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Backend  : ${API}`);
console.log(`  Sufijo   : ${SUF}`);
console.log(`  Carreras : ${REPETICIONES} (prueba de fuego)`);
console.log(`  Modo     : ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);

if (!CONFIRMAR) {
  const salud = await fetch(`${API}/salud`).then((r) => r.status).catch(() => null);
  console.log(`\n  Backend ${salud === null ? 'NO responde' : `responde ${salud}`}.`);
  console.log('  Simulación: este humo ESCRIBE en la base real (usuarios, materia,');
  console.log('  programa y una sección temporales) y lo borra al final.');
  console.log('  Repite con --confirmar.\n');
  process.exit(0);
}

/** Crea un usuario sin enviar correo y le fija el rol. Devuelve su id. */
async function crearUsuario(correo, rol) {
  const alta = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: { email: correo, password: CLAVE, email_confirm: true },
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

/** Enciende o apaga el sistema de bids. Devuelve si la escritura prosperó. */
async function fijarBids(valor) {
  const r = await pedir('/rest/v1/system_settings?clave=eq.habilitar_sistema_bids', {
    metodo: 'PATCH',
    cuerpo: { valor },
    extra: { Prefer: 'return=representation' },
  });
  return { ok: r.estado < 300 && r.datos?.[0]?.valor === valor, estado: r.estado };
}

/**
 * Vacía la sección de inscripciones y CONFIRMA que quedó vacía.
 *
 * Se hace con la service role key porque `enrollments` tiene la escritura
 * revocada para `authenticated` (R-23) — es exactamente el cerrojo que este humo
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
  return { fila, estado: r.estado, crudo: r.datos };
}

/** Estado de una inscripción concreta, leído de la base. */
async function estadoDe(estudianteId) {
  const r = await pedir(
    `/rest/v1/enrollments?section_id=eq.${creado.seccion}&student_id=eq.${estudianteId}&select=status,bid_expires_at`,
  );
  return r.datos?.[0] ?? null;
}

/** Cuántas filas hay en la sección en un estado dado. */
async function contarEstado(estado) {
  const r = await pedir(
    `/rest/v1/enrollments?section_id=eq.${creado.seccion}&status=eq.${estado}&select=id`,
  );
  return Array.isArray(r.datos) ? r.datos.length : -1;
}

/** Purga todo lo creado, en orden inverso de dependencia. Se corre siempre. */
async function purgar() {
  // Lo primero de todo: devolver el ajuste global a como estaba. Un humo que
  // deja el sistema de bids encendido cambia el comportamiento de producción.
  if (creado.bidsOriginal !== null) {
    await fijarBids(creado.bidsOriginal);
  }
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
  // --- 1. Identidades, datos base y la sección de un solo asiento ------------
  console.log('\n  1. Identidades, datos base y una sección de UN asiento\n');

  const idAdmin = await crearUsuario(CORREOS.admin, 'admin');
  const idAlfa = await crearUsuario(CORREOS.alfa, 'estudiante');
  const idBeta = await crearUsuario(CORREOS.beta, 'estudiante');
  const idGamma = await crearUsuario(CORREOS.gamma, 'estudiante');
  comprobar('un admin y tres estudiantes temporales', Boolean(idAdmin && idAlfa && idBeta && idGamma));

  const tokenAdmin = await iniciarSesion(CORREOS.admin);
  const tokenAlfa = await iniciarSesion(CORREOS.alfa);
  const tokenBeta = await iniciarSesion(CORREOS.beta);
  const tokenGamma = await iniciarSesion(CORREOS.gamma);
  comprobar('cuatro JWT reales', Boolean(tokenAdmin && tokenAlfa && tokenBeta && tokenGamma));

  const ajuste = await pedir('/rest/v1/system_settings?clave=eq.periodo_activo&select=valor');
  const periodo = typeof ajuste.datos?.[0]?.valor === 'string' ? ajuste.datos[0].valor : null;
  creado.periodo = periodo;
  comprobar('hay un lapso vigente declarado', Boolean(periodo), `valor=${periodo}`);

  // El ajuste se lee ANTES de tocarlo: la purga tiene que poder restaurarlo.
  const bids = await pedir('/rest/v1/system_settings?clave=eq.habilitar_sistema_bids&select=valor');
  creado.bidsOriginal = typeof bids.datos?.[0]?.valor === 'boolean' ? bids.datos[0].valor : false;
  console.log(`         habilitar_sistema_bids = ${creado.bidsOriginal} (se restaura al final)`);

  const materia = await pedir('/rest/v1/subjects', {
    metodo: 'POST',
    cuerpo: { code: COD_MATERIA, name: `Humo M4 materia ${SUF}`, academic_hours: 48 },
    extra: { Prefer: 'return=representation' },
  });
  creado.materia = materia.datos?.[0]?.id ?? null;
  comprobar('materia temporal creada', Boolean(creado.materia), `estado=${materia.estado}`);

  // Inactivo y sin pensum: la Regla 1 de M2 prohíbe un programa ACTIVO sin
  // pensum, y aquí no hace falta pensum para colgar una sección.
  const programa = await pedir('/rest/v1/programs', {
    metodo: 'POST',
    cuerpo: { code: COD_PROGRAMA, name: `Humo M4 programa ${SUF}`, type: 'CARRERA', is_active: false },
    extra: { Prefer: 'return=representation' },
  });
  creado.programa = programa.datos?.[0]?.id ?? null;
  comprobar('programa temporal creado (inactivo, sin pensum)', Boolean(creado.programa), `estado=${programa.estado}`);

  // La sección se crea por la ruta REAL de M4, no con la service role key: así el
  // humo cubre también el CRUD de secciones y su guardia de administrador.
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

  const ocupacionInicial = await ocupacion(tokenAdmin, creado.materia);
  comprobar(
    'la sección nace con 1 asiento y 0 ocupados',
    ocupacionInicial.fila?.cupoEfectivo === 1 && ocupacionInicial.fila?.cuposOcupados === 0,
    JSON.stringify(ocupacionInicial.fila)?.slice(0, 200),
  );

  // --- 2. LA PRUEBA DE FUEGO -------------------------------------------------
  console.log('\n  2. LA PRUEBA DE FUEGO — dos solicitudes simultáneas, un asiento\n');
  console.log('     Dos POST /api/v1/inscripciones disparados con Promise.all.');
  console.log('     Sin el cerrojo, los dos leerían «0 ocupados < 1 de cupo».');
  console.log('');

  let ganadosPorAlfa = 0;
  let doblesVentas = 0;

  for (let i = 1; i <= REPETICIONES; i += 1) {
    const limpio = await limpiarInscripciones();
    if (!limpio.ok) {
      comprobar(`repetición ${i}: la sección arranca vacía`, false, `quedaron ${limpio.quedan} fila(s)`);
      continue;
    }

    // `map` construye los dos `fetch` en el MISMO tick, antes de que ninguno
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
    if (matriculados > 1) doblesVentas += 1;

    console.log(
      `     ronda ${i}: alfa=${eAlfa} beta=${eBeta} · ENROLLED en la base=${matriculados}`,
    );

    comprobar(
      `ronda ${i}: las dos peticiones responden 201`,
      rAlfa.estado === 201 && rBeta.estado === 201,
      `alfa=${rAlfa.estado} beta=${rBeta.estado}`,
    );
    comprobar(
      `ronda ${i}: exactamente un ENROLLED y un WAITLISTED`,
      [eAlfa, eBeta].sort().join('|') === 'ENROLLED|WAITLISTED',
      `alfa=${eAlfa} beta=${eBeta}`,
    );
    comprobar(
      `ronda ${i}: la base confirma UN solo asiento vendido`,
      matriculados === 1,
      `ENROLLED=${matriculados}`,
    );
  }

  console.log('');
  comprobar(
    `en ${REPETICIONES} carrera(s) NUNCA hubo dos ENROLLED en el asiento`,
    doblesVentas === 0,
    `${doblesVentas} doble(s) venta(s)`,
  );
  // El ganador no tiene por qué ser siempre el mismo: si lo fuera, sospecharía
  // más de un orden de llegada impuesto por el cliente que del cerrojo.
  console.log(`         ganó alfa ${ganadosPorAlfa}/${REPETICIONES} veces (reparto esperado: aleatorio)`);

  // --- 3. El guardián de doble venta ----------------------------------------
  console.log('\n  3. EL GUARDIÁN DE DOBLE VENTA — el asiento prometido no se vende dos veces\n');

  const encendido = await fijarBids(true);
  comprobar('se enciende el sistema de bids para esta fase', encendido.ok, `estado=${encendido.estado}`);

  const limpio3 = await limpiarInscripciones();
  comprobar('la sección arranca vacía', limpio3.ok, `quedaron ${limpio3.quedan}`);

  const solicitudAlfa = await api('/api/v1/inscripciones', {
    metodo: 'POST', token: tokenAlfa, cuerpo: { seccionId: creado.seccion },
  });
  comprobar('alfa entra directo a ENROLLED (hay asiento libre)', solicitudAlfa.datos?.estado === 'ENROLLED', JSON.stringify(solicitudAlfa.datos));

  const solicitudBeta = await api('/api/v1/inscripciones', {
    metodo: 'POST', token: tokenBeta, cuerpo: { seccionId: creado.seccion },
  });
  comprobar('beta queda en WAITLISTED (la sección está llena)', solicitudBeta.datos?.estado === 'WAITLISTED', JSON.stringify(solicitudBeta.datos));

  const renunciaAlfa = await api(`/api/v1/inscripciones/${creado.seccion}/renunciar`, {
    metodo: 'POST', token: tokenAlfa,
  });
  comprobar('alfa renuncia y libera el asiento', renunciaAlfa.datos?.estado === 'DROPPED', JSON.stringify(renunciaAlfa.datos));

  // HALLAZGO: renunciar NO se limita a liberar el asiento. `renunciar_cupo` llama
  // a `promover_siguiente_de_cola` dentro de su propia transacción, así que la
  // promoción YA OCURRIÓ. «Promover Siguiente» en el panel del administrador no
  // es el camino normal para mover la cola, y la interfaz no debe presentarlo
  // como si lo fuera.
  const ofertaBeta = await estadoDe(idBeta);
  comprobar(
    'LA RENUNCIA YA PROMUEVE: beta recibe la oferta sin que nadie pulse nada',
    ofertaBeta?.status === 'PENDING_BID' && Boolean(ofertaBeta?.bid_expires_at),
    JSON.stringify(ofertaBeta),
  );

  const promocion = await api(`/api/v1/admin/secciones/${creado.seccion}/promover`, {
    metodo: 'POST', token: tokenAdmin,
  });
  comprobar(
    '«Promover Siguiente» es un override manual: aquí responde 200 con promovida=null',
    promocion.estado === 200 && promocion.datos?.promovida === null,
    `estado=${promocion.estado} ${JSON.stringify(promocion.datos)?.slice(0, 200)}`,
  );

  // LA ASERCIÓN QUE JUSTIFICA TODO EL MÓDULO. `cupos_ocupados` = 0 (la oferta no
  // reserva cupo, por regla institucional), así que sin el guardián gamma entraría
  // a ENROLLED y luego beta aceptaría: dos personas en un asiento de uno.
  const solicitudGamma = await api('/api/v1/inscripciones', {
    metodo: 'POST', token: tokenGamma, cuerpo: { seccionId: creado.seccion },
  });
  comprobar(
    'GAMMA NO entra directo: la oferta viva bloquea la vía directa (anti doble venta)',
    solicitudGamma.datos?.estado === 'WAITLISTED',
    `estado=${solicitudGamma.datos?.estado} — si fuera ENROLLED, la doble venta está abierta`,
  );
  comprobar(
    'y sigue habiendo UN solo ENROLLED y ninguna segunda oferta',
    (await contarEstado('ENROLLED')) === 0 && (await contarEstado('PENDING_BID')) === 1,
    `ENROLLED=${await contarEstado('ENROLLED')} PENDING_BID=${await contarEstado('PENDING_BID')}`,
  );

  // El caso que obliga a la interfaz a mirar `ofertaVigente` y no
  // `cuposDisponibles`: la vista dice «1 disponible» y ese asiento NO se puede dar.
  const ocupacionConOferta = await ocupacion(tokenAdmin, creado.materia);
  comprobar(
    'la vista dice «1 disponible» Y «ofertaVigente: true» a la vez',
    ocupacionConOferta.fila?.cuposDisponibles === 1 && ocupacionConOferta.fila?.ofertaVigente === true,
    JSON.stringify(ocupacionConOferta.fila)?.slice(0, 240),
  );
  comprobar(
    'la ocupación es 0 aunque haya una oferta viva (PENDING_BID no reserva cupo)',
    ocupacionConOferta.fila?.cuposOcupados === 0,
    `cuposOcupados=${ocupacionConOferta.fila?.cuposOcupados}`,
  );

  // --- 4. Aceptar la oferta --------------------------------------------------
  console.log('\n  4. Aceptar la oferta — el asiento pasa a estar ocupado\n');

  const aceptar = await api(`/api/v1/inscripciones/${creado.seccion}/aceptar`, {
    metodo: 'POST', token: tokenBeta,
  });
  comprobar('beta acepta y queda ENROLLED', aceptar.datos?.estado === 'ENROLLED', JSON.stringify(aceptar.datos));
  comprobar(
    'queda exactamente UN ENROLLED y ninguna oferta en el aire',
    (await contarEstado('ENROLLED')) === 1 && (await contarEstado('PENDING_BID')) === 0,
    `ENROLLED=${await contarEstado('ENROLLED')} PENDING_BID=${await contarEstado('PENDING_BID')}`,
  );

  const misBeta = await api('/api/v1/mis-inscripciones', { token: tokenBeta });
  const filaBeta = (misBeta.datos?.inscripciones ?? []).find((i) => i.seccionId === creado.seccion) ?? null;
  comprobar(
    'GET /mis-inscripciones devuelve el estado y el nombre de la sección',
    filaBeta?.estado === 'ENROLLED' && filaBeta?.seccionNombre === NOMBRE_SECCION,
    JSON.stringify(filaBeta)?.slice(0, 240),
  );

  // `posicionEnCola` es un campo que la pantalla del estudiante pinta tal cual.
  const misGamma = await api('/api/v1/mis-inscripciones', { token: tokenGamma });
  const filaGamma = (misGamma.datos?.inscripciones ?? []).find((i) => i.seccionId === creado.seccion) ?? null;
  comprobar(
    'gamma está en cola con posición 1 (el único WAITLISTED)',
    filaGamma?.estado === 'WAITLISTED' && filaGamma?.posicionEnCola === 1,
    JSON.stringify(filaGamma)?.slice(0, 240),
  );

  // --- 5. La otra rama: promoción directa (bids apagado, el valor de producción)
  console.log('\n  5. Promoción DIRECTA — con bids apagado, que es como corre producción\n');

  const apagado = await fijarBids(false);
  comprobar('se apaga el sistema de bids', apagado.ok, `estado=${apagado.estado}`);

  const limpio5 = await limpiarInscripciones();
  comprobar('la sección arranca vacía', limpio5.ok, `quedaron ${limpio5.quedan}`);

  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenAlfa, cuerpo: { seccionId: creado.seccion } });
  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenBeta, cuerpo: { seccionId: creado.seccion } });
  comprobar(
    'alfa ENROLLED y beta WAITLISTED, como antes',
    (await estadoDe(idAlfa))?.status === 'ENROLLED' && (await estadoDe(idBeta))?.status === 'WAITLISTED',
    `alfa=${(await estadoDe(idAlfa))?.status} beta=${(await estadoDe(idBeta))?.status}`,
  );

  await api(`/api/v1/inscripciones/${creado.seccion}/renunciar`, { metodo: 'POST', token: tokenAlfa });
  comprobar(
    'con bids apagado, la renuncia promueve a beta DIRECTO a ENROLLED (sin oferta que aceptar)',
    (await estadoDe(idBeta))?.status === 'ENROLLED' && (await contarEstado('PENDING_BID')) === 0,
    `beta=${(await estadoDe(idBeta))?.status} PENDING_BID=${await contarEstado('PENDING_BID')}`,
  );

  // Promover con la cola vacía no es un error: es 200 con la explicación.
  const promocionVacia = await api(`/api/v1/admin/secciones/${creado.seccion}/promover`, {
    metodo: 'POST', token: tokenAdmin,
  });
  comprobar(
    'promover sin nadie en cola es 200 con explicación, no un error',
    promocionVacia.estado === 200 && promocionVacia.datos?.promovida === null,
    `estado=${promocionVacia.estado} ${JSON.stringify(promocionVacia.datos)?.slice(0, 160)}`,
  );

  // --- El uso REAL del override manual: ampliar el cupo con gente esperando ---
  console.log('\n  5b. «Promover Siguiente» cuando de verdad hace falta\n');

  const limpio5b = await limpiarInscripciones();
  comprobar('la sección arranca vacía', limpio5b.ok, `quedaron ${limpio5b.quedan}`);

  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenAlfa, cuerpo: { seccionId: creado.seccion } });
  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenBeta, cuerpo: { seccionId: creado.seccion } });
  comprobar(
    'alfa ocupa el asiento y beta espera en la cola',
    (await estadoDe(idAlfa))?.status === 'ENROLLED' && (await estadoDe(idBeta))?.status === 'WAITLISTED',
    `alfa=${(await estadoDe(idAlfa))?.status} beta=${(await estadoDe(idBeta))?.status}`,
  );

  // Ampliar el cupo NO promueve a nadie por sí solo: es el administrador quien
  // decide a quién sube. Es el único caso en el que el botón tiene trabajo.
  const ampliar = await api(`/api/v1/admin/secciones/${creado.seccion}`, {
    metodo: 'PATCH', token: tokenAdmin, cuerpo: { cupoMaximo: 2 },
  });
  comprobar(
    'el admin amplía el cupo a 2 (ahora sobra un asiento)',
    ampliar.estado === 200 && ampliar.datos?.seccion?.cupoMaximo === 2,
    `estado=${ampliar.estado} ${JSON.stringify(ampliar.datos)?.slice(0, 200)}`,
  );
  comprobar(
    'beta SIGUE en la cola: ampliar el cupo no promueve a nadie',
    (await estadoDe(idBeta))?.status === 'WAITLISTED',
    `beta=${(await estadoDe(idBeta))?.status}`,
  );

  const override = await api(`/api/v1/admin/secciones/${creado.seccion}/promover`, {
    metodo: 'POST', token: tokenAdmin,
  });

  // --- R-25: el override promueve DE VERDAD y la API ahora responde 200 --------
  //  Este bloque certifica el ARREGLO de R-25 (ver `REPORTE_ARIA.md`). La RPC
  //  `promover_siguiente` devuelve el `student_id`, y el repositorio lo leía
  //  como si fuera el `id` de la inscripción (`.eq('id', …)` sobre `enrollments`),
  //  lo que producía un 404 pese a promover en la base. El arreglo lee por
  //  `(student_id, section_id)` y la API devuelve 200 con la inscripción.
  //
  //  Las 428 pruebas del backend no lo veían porque el doble en memoria devolvía
  //  la inscripción ya promovida —reproducía la intención de la RPC, no su
  //  contrato—. Sólo la base real desmiente la copia, y esto lo certifica.
  console.log('         ✓ R-25 (resuelto): el override promueve y la API responde 200');
  comprobar(
    'R-25: la promoción ocurre en la base (beta queda ENROLLED)',
    (await estadoDe(idBeta))?.status === 'ENROLLED',
    `beta=${(await estadoDe(idBeta))?.status}`,
  );
  comprobar(
    'R-25: y la API responde 200 (ya no el 404 «leer la inscripción promovida»)',
    override.estado === 200,
    `estado=${override.estado} ${JSON.stringify(override.datos)?.slice(0, 200)}`,
  );
  comprobar(
    'R-25: la respuesta 200 trae a beta promovido (promovida.estudianteId === idBeta)',
    override.datos?.promovida?.estudianteId === idBeta &&
      override.datos?.promovida?.estado === 'ENROLLED',
    `promovida=${JSON.stringify(override.datos?.promovida)?.slice(0, 200)}`,
  );

  // Se devuelve el cupo a 1: la fase de reincorporación necesita la sección llena
  // para poder demostrar que la excepción del administrador la EXCEDE.
  const devolverCupo = await api(`/api/v1/admin/secciones/${creado.seccion}`, {
    metodo: 'PATCH', token: tokenAdmin, cuerpo: { cupoMaximo: 1 },
  });
  comprobar(
    'se devuelve el cupo a 1 para las fases siguientes',
    devolverCupo.datos?.seccion?.cupoMaximo === 1,
    `estado=${devolverCupo.estado}`,
  );

  // --- 6. Expiración: el barrido es idempotente y promueve en cascada ---------
  console.log('\n  6. Expiración de ofertas — idempotente y con promoción en cascada\n');

  await fijarBids(true);
  const limpio6 = await limpiarInscripciones();
  comprobar('la sección arranca vacía', limpio6.ok, `quedaron ${limpio6.quedan}`);

  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenAlfa, cuerpo: { seccionId: creado.seccion } });
  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenBeta, cuerpo: { seccionId: creado.seccion } });
  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenGamma, cuerpo: { seccionId: creado.seccion } });
  await api(`/api/v1/inscripciones/${creado.seccion}/renunciar`, { metodo: 'POST', token: tokenAlfa });
  // Sin promover a mano: la renuncia ya dejó la oferta en manos de beta.
  comprobar(
    'beta tiene la oferta y gamma espera en la cola',
    (await estadoDe(idBeta))?.status === 'PENDING_BID' && (await estadoDe(idGamma))?.status === 'WAITLISTED',
    `beta=${(await estadoDe(idBeta))?.status} gamma=${(await estadoDe(idGamma))?.status}`,
  );

  // Se adelanta el reloj de la oferta en vez de esperar 24 h. La service role
  // puede escribir donde `authenticated` no: es preparación, no negocio.
  const vencida = await pedir(
    `/rest/v1/enrollments?section_id=eq.${creado.seccion}&student_id=eq.${idBeta}`,
    {
      metodo: 'PATCH',
      cuerpo: { bid_expires_at: new Date(Date.now() - 60_000).toISOString() },
      extra: { Prefer: 'return=representation' },
    },
  );
  comprobar('se fuerza el vencimiento de la oferta de beta', vencida.estado < 300, `estado=${vencida.estado}`);

  const barrido = await api('/api/v1/admin/inscripciones/expirar', { metodo: 'POST', token: tokenAdmin });
  comprobar('el barrido expira 1 oferta', barrido.datos?.vencidas === 1, JSON.stringify(barrido.datos)?.slice(0, 200));
  comprobar(
    'beta queda DROPPED y gamma asciende en cascada',
    (await estadoDe(idBeta))?.status === 'DROPPED' && (await estadoDe(idGamma))?.status === 'PENDING_BID',
    `beta=${(await estadoDe(idBeta))?.status} gamma=${(await estadoDe(idGamma))?.status}`,
  );

  const barrido2 = await api('/api/v1/admin/inscripciones/expirar', { metodo: 'POST', token: tokenAdmin });
  comprobar('la segunda pasada devuelve 0 (es idempotente)', barrido2.datos?.vencidas === 0, JSON.stringify(barrido2.datos)?.slice(0, 160));

  // --- 7. Reincorporación: el administrador PUEDE exceder la capacidad --------
  console.log('\n  7. Reincorporación — «si el admin autoriza, el sistema obedece»\n');

  await fijarBids(false);
  const limpio7 = await limpiarInscripciones();
  comprobar('la sección arranca vacía', limpio7.ok, `quedaron ${limpio7.quedan}`);

  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenAlfa, cuerpo: { seccionId: creado.seccion } });
  await api(`/api/v1/inscripciones/${creado.seccion}/renunciar`, { metodo: 'POST', token: tokenAlfa });
  await api('/api/v1/inscripciones', { metodo: 'POST', token: tokenBeta, cuerpo: { seccionId: creado.seccion } });
  comprobar(
    'alfa queda DROPPED y beta ocupa el único asiento',
    (await estadoDe(idAlfa))?.status === 'DROPPED' && (await estadoDe(idBeta))?.status === 'ENROLLED',
    `alfa=${(await estadoDe(idAlfa))?.status} beta=${(await estadoDe(idBeta))?.status}`,
  );

  const reincorporar = await api('/api/v1/admin/inscripciones/reincorporar', {
    metodo: 'POST',
    token: tokenAdmin,
    cuerpo: { estudianteId: idAlfa, seccionId: creado.seccion },
  });
  comprobar(
    'el admin reincorpora a alfa CON LA SECCIÓN LLENA',
    reincorporar.datos?.estado === 'ENROLLED',
    JSON.stringify(reincorporar.datos)?.slice(0, 200),
  );

  const ocupacionExcedida = await ocupacion(tokenAdmin, creado.materia);
  comprobar(
    'la ocupación supera el cupo: 2 ocupados en 1 asiento',
    ocupacionExcedida.fila?.cuposOcupados === 2 && ocupacionExcedida.fila?.cupoEfectivo === 1,
    JSON.stringify(ocupacionExcedida.fila)?.slice(0, 240),
  );
  comprobar(
    'y la vista NO devuelve un disponible negativo',
    ocupacionExcedida.fila?.cuposDisponibles === 0,
    `cuposDisponibles=${ocupacionExcedida.fila?.cuposDisponibles}`,
  );

  // La reincorporación no puede saltarse el anti-acaparamiento: la excepción es
  // sobre la capacidad, no sobre la equidad entre materias. Un estudiante sin
  // historial en la sección no se puede reincorporar.
  const sinHistorial = await api('/api/v1/admin/inscripciones/reincorporar', {
    metodo: 'POST',
    token: tokenAdmin,
    cuerpo: { estudianteId: idGamma, seccionId: creado.seccion },
  });
  comprobar(
    'reincorporar a quien nunca cursó la sección es 404 SIN_HISTORIAL_EN_SECCION',
    sinHistorial.estado === 404,
    `estado=${sinHistorial.estado} ${JSON.stringify(sinHistorial.datos)?.slice(0, 200)}`,
  );

  // --- 8. El catálogo de ofertas que verá el estudiante ----------------------
  console.log('\n  8. El catálogo de ofertas — el contrato que consumirá Flutter\n');

  const ofertas = await api(`/api/v1/ofertas?materiaId=${creado.materia}&limite=100`, {
    token: tokenGamma,
  });
  const oferta = (ofertas.datos?.secciones ?? []).find((s) => s.seccionId === creado.seccion) ?? null;
  comprobar(
    'GET /ofertas devuelve la sección con su ocupación',
    ofertas.estado === 200 && Boolean(oferta),
    `estado=${ofertas.estado} ${JSON.stringify(ofertas.datos)?.slice(0, 200)}`,
  );
  comprobar(
    'la oferta trae `ofertaVigente` además de `cuposDisponibles`',
    typeof oferta?.ofertaVigente === 'boolean' && typeof oferta?.cuposDisponibles === 'number',
    JSON.stringify(oferta)?.slice(0, 240),
  );

  console.log('\n  9. Limpieza\n');
} catch (error) {
  fallos += 1;
  console.error(`  [FALLA] excepción: ${error?.message ?? error}`);
} finally {
  await purgar();

  // El residuo se comprueba, no se supone: una purga que falla en silencio deja
  // basura en producción y el humo diría «verde».
  const residuoPerfiles = await pedir('/rest/v1/profiles?email=like.humo4-*&select=id');
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

  // Y el ajuste global tiene que haber vuelto a su sitio: dejarlo encendido
  // cambiaría el comportamiento de producción en silencio.
  const bidsFinal = await pedir('/rest/v1/system_settings?clave=eq.habilitar_sistema_bids&select=valor');
  comprobar(
    `habilitar_sistema_bids quedó como estaba (${creado.bidsOriginal})`,
    bidsFinal.datos?.[0]?.valor === creado.bidsOriginal,
    `quedó=${JSON.stringify(bidsFinal.datos?.[0]?.valor)}`,
  );

  console.log(
    `\n  ${fallos === 0 ? `✓ Humo superado — ${ok} comprobaciones en verde.` : `✗ ${fallos} comprobación(es) fallida(s), ${ok} en verde.`}\n`,
  );
  process.exit(fallos === 0 ? 0 : 1);
}
