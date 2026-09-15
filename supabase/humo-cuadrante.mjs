/**
 * Humo de integración del cuadrante de M3 (aulas, lapsos, guardias y rejilla).
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que las 333 pruebas del backend NO pueden verificar, porque usan dobles en
 * memoria: que el motor real (PostgREST + RLS de Postgres + los triggers
 * anti-colisión) se comporte como el doble predijo.
 *
 *   1. **El mensaje del trigger, de verdad.** El doble en memoria copia a mano
 *      los dos `raise exception` de la migración; sólo la base real demuestra
 *      que la copia es fiel y que `esChoqueDeAgenda` reconoce el texto con el
 *      día y el bloque ya interpolados.
 *   2. **La colisión cruzada**: una clase choca con una GUARDIA, que vive en
 *      otra tabla. Es el caso que ningún `unique` podría expresar.
 *   3. **El mismo hueco en otro lapso SÍ se permite** — la razón por la que un
 *      `unique (teacher_id, day_of_week, block)` habría estado mal.
 *   4. **La sintaxis de PostgREST**: el filtro de tipo (`is_workshop` +
 *      `capacity`) y el texto de búsqueda, que el doble no analiza.
 *   5. **`PGRST116` existe de verdad** al parchear un id ausente con
 *      `Accept: application/vnd.pgrst.object+json`. Si PostgREST devolviera otra
 *      cosa, la traducción a 404 nunca se dispararía.
 *   6. **`turno` es columna generada**: la calcula la base a partir del bloque.
 *   7. **La RLS por rol a través de las vistas `security_invoker`**: el
 *      estudiante ve las clases de SUS secciones y no las demás, no ve guardias,
 *      y aun así ve el NOMBRE del docente (el arreglo de R-14).
 *   8. **El guarda de `periodo_activo`**: declarar un lapso que no existe en el
 *      catálogo es un `23514`, no una divergencia silenciosa.
 *
 * CÓMO FUNCIONA
 * -------------
 * Escribe en producción, así que exige `--confirmar`. Crea usuarios, un lapso,
 * dos aulas, dos secciones y un programa temporales —con sufijo del reloj— y lo
 * purga TODO al final, también si falla a mitad.
 *
 * Escribe **con el JWT de un administrador real**, no con la service role key,
 * porque eso es lo que hace el backend: así se comprueban de paso las políticas
 * `*_admin_all` y el `with check`.
 *
 * FUERA DE CI A PROPÓSITO: toca la base real. Es una herramienta de verificación
 * manual, como `humo-invitaciones.mjs` y `humo-curriculo.mjs`.
 *
 * USO
 * ---
 *   node supabase/humo-cuadrante.mjs              # simulación (no escribe)
 *   node supabase/humo-cuadrante.mjs --confirmar  # ejecuta el humo
 *
 * Las credenciales se leen del entorno y, si no están, de `backend/.env`.
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

const URL_BASE = variable('SUPABASE_URL');
const CLAVE_SERVICIO = variable('SUPABASE_SERVICE_ROLE_KEY');
const CLAVE_ANON = variable('SUPABASE_ANON_KEY');

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

/** Petición cruda que devuelve estado + cuerpo, sin lanzar por códigos HTTP. */
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

/** Código de error de PostgREST o de Postgres, para aserciones precisas. */
const codigo = (respuesta) =>
  respuesta.datos?.code ?? respuesta.datos?.codigo ?? '';

/** Texto del error, venga como venga, para buscar el mensaje del trigger. */
const textoError = (respuesta) => JSON.stringify(respuesta.datos ?? '');

if (!URL_BASE || !CLAVE_SERVICIO || !CLAVE_ANON) {
  console.error('\n  Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY.');
  console.error('  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n');
  process.exit(1);
}

const SUF = Date.now().toString().slice(-6);
const COD_MATERIA = `TS${SUF}`;
const COD_PROGRAMA = `TP${SUF}`;
const COD_LAPSO = `TMP${SUF}`;
const NOMBRE_AULA_TALLER = `Humo taller ${SUF}`;
const NOMBRE_AULA_ZONA = `Humo zona ${SUF}`;
const SEC_A = `HA${SUF.slice(-3)}`;
const SEC_B = `HB${SUF.slice(-3)}`;

const marca = Date.now();
const CLAVE = `Humo!${randomBytes(12).toString('base64url')}`;
const CORREOS = {
  admin: `humo3-admin-${marca}@ejemplo.invalid`,
  docente1: `humo3-docente1-${marca}@ejemplo.invalid`,
  docente2: `humo3-docente2-${marca}@ejemplo.invalid`,
  estudiante: `humo3-alumno-${marca}@ejemplo.invalid`,
};

/** Todo lo que se crea, para purgarlo en orden inverso de dependencia. */
const creado = {
  usuarios: [],
  materia: null,
  programa: null,
  secciones: [],
  aulas: [],
  lapso: null,
  lapsoVigenteOriginal: null,
};

console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Sufijo   : ${SUF}`);
console.log(`  Modo     : ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);

if (!CONFIRMAR) {
  console.log('\n  Simulación: este humo ESCRIBE en la base real (usuarios, un lapso,');
  console.log('  aulas, secciones y clases temporales) y lo borra al final.');
  console.log('  Repite con --confirmar.\n');
  process.exit(0);
}

/** Crea un usuario sin enviar correo y le fija el rol. Devuelve su id. */
async function crearUsuario(correo, rol, nombre = null) {
  const alta = await pedir('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: { email: correo, password: CLAVE, email_confirm: true },
  });
  const id = alta.datos?.id ?? null;
  if (!id) throw new Error(`no se pudo crear ${correo}: ${JSON.stringify(alta.datos)}`);
  creado.usuarios.push(id);

  // El trigger `handle_new_user` lo deja como `estudiante`. Para los demás roles
  // se promueve aquí, igual que hace el canal de invitación.
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

  // El nombre se fija APARTE, y eso es justamente el hallazgo R-21: `createUser`
  // no lleva `user_metadata`, así que `handle_new_user` deja `nombres` y
  // `apellidos` en NULL y `nombre_para_mostrar()` devuelve NULL. Aquí se
  // rellenan para poder comprobar que la vista resuelve el nombre CUANDO existe.
  if (nombre) {
    const puesto = await pedir(`/rest/v1/profiles?id=eq.${id}`, {
      metodo: 'PATCH',
      cuerpo: { nombres: nombre[0], apellidos: nombre[1] },
    });
    if (puesto.estado >= 300) throw new Error(`no se pudo nombrar ${correo}: ${JSON.stringify(puesto.datos)}`);
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

/** Purga todo lo creado, en orden inverso de dependencia. Se corre siempre. */
async function purgar() {
  if (creado.lapsoVigenteOriginal !== null) {
    await pedir('/rest/v1/system_settings?clave=eq.periodo_activo', {
      metodo: 'PATCH',
      cuerpo: { valor: creado.lapsoVigenteOriginal },
    });
  }
  // Hijos primero: las dos columnas `classroom_id` están en `on delete restrict`.
  for (const id of creado.secciones) {
    await pedir(`/rest/v1/schedule_slots?section_id=eq.${id}`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/enrollments?section_id=eq.${id}`, { metodo: 'DELETE' });
  }
  for (const id of creado.usuarios) {
    await pedir(`/rest/v1/teacher_duties?teacher_id=eq.${id}`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/schedule_slots?teacher_id=eq.${id}`, { metodo: 'DELETE' });
  }
  for (const id of creado.secciones) {
    await pedir(`/rest/v1/sections?id=eq.${id}`, { metodo: 'DELETE' });
  }
  for (const id of creado.aulas) {
    await pedir(`/rest/v1/classrooms?id=eq.${id}`, { metodo: 'DELETE' });
  }
  if (creado.programa) await pedir(`/rest/v1/programs?id=eq.${creado.programa}`, { metodo: 'DELETE' });
  if (creado.materia) await pedir(`/rest/v1/subjects?id=eq.${creado.materia}`, { metodo: 'DELETE' });
  if (creado.lapso) await pedir(`/rest/v1/academic_periods?id=eq.${creado.lapso}`, { metodo: 'DELETE' });
  for (const id of creado.usuarios) {
    await pedir(`/auth/v1/admin/users/${id}`, { metodo: 'DELETE' });
  }
  // Barrido por si un fallo a mitad dejó algo suelto.
  await pedir(`/rest/v1/classrooms?name=like.Humo*${SUF}*`, { metodo: 'DELETE' });
  await pedir(`/rest/v1/academic_periods?code=eq.${COD_LAPSO}`, { metodo: 'DELETE' });
  await pedir(`/rest/v1/subjects?code=eq.${COD_MATERIA}`, { metodo: 'DELETE' });
  await pedir(`/rest/v1/programs?code=eq.${COD_PROGRAMA}`, { metodo: 'DELETE' });
  for (const correo of Object.values(CORREOS)) {
    await pedir(`/rest/v1/profiles?email=eq.${correo}`, { metodo: 'DELETE' });
  }
}

try {
  // --- 1. Identidades y datos base -----------------------------------------
  console.log('\n  1. Identidades temporales y datos base\n');

  const idAdmin = await crearUsuario(CORREOS.admin, 'admin');
  // El docente 1 se queda SIN nombre a propósito: es el estado en el que queda
  // todo docente creado por el canal real de invitación (hallazgo R-21, §7).
  const idDocente1 = await crearUsuario(CORREOS.docente1, 'docente');
  const idDocente2 = await crearUsuario(CORREOS.docente2, 'docente', ['Luisa', 'Márquez']);
  const idEstudiante = await crearUsuario(CORREOS.estudiante, 'estudiante');
  comprobar('cuatro usuarios temporales con su rol', Boolean(idAdmin && idDocente1 && idDocente2 && idEstudiante));

  const tokenAdmin = await iniciarSesion(CORREOS.admin);
  const tokenDocente1 = await iniciarSesion(CORREOS.docente1);
  const tokenEstudiante = await iniciarSesion(CORREOS.estudiante);
  comprobar('tres JWT reales (admin, docente, estudiante)', Boolean(tokenAdmin && tokenDocente1 && tokenEstudiante));

  // El lapso vigente ya existe y es el que usa `mi-horario`. Se lee antes de
  // tocar nada para poder restaurarlo.
  const ajuste = await pedir('/rest/v1/system_settings?clave=eq.periodo_activo&select=valor');
  const lapsoVigente = typeof ajuste.datos?.[0]?.valor === 'string' ? ajuste.datos[0].valor : null;
  creado.lapsoVigenteOriginal = lapsoVigente;
  comprobar('hay un lapso vigente declarado', Boolean(lapsoVigente), `valor=${lapsoVigente}`);

  const materia = await pedir('/rest/v1/subjects', {
    metodo: 'POST',
    cuerpo: { code: COD_MATERIA, name: `Humo materia ${SUF}`, academic_hours: 48 },
    extra: { Prefer: 'return=representation' },
  });
  creado.materia = materia.datos?.[0]?.id ?? null;
  comprobar('materia temporal creada', Boolean(creado.materia), `estado=${materia.estado}`);

  // `is_active: false` a propósito: la Regla 1 de M2 prohíbe un programa ACTIVO
  // sin pensum, y aquí no hace falta pensum para colgar una sección.
  const programa = await pedir('/rest/v1/programs', {
    metodo: 'POST',
    cuerpo: {
      code: COD_PROGRAMA,
      name: `Humo programa ${SUF}`,
      type: 'CARRERA',
      is_active: false,
    },
    extra: { Prefer: 'return=representation' },
  });
  creado.programa = programa.datos?.[0]?.id ?? null;
  comprobar('programa temporal creado (inactivo, sin pensum)', Boolean(creado.programa), `estado=${programa.estado}`);

  for (const [nombre, seccion] of [
    [SEC_A, 'A'],
    [SEC_B, 'B'],
  ]) {
    const fila = await pedir('/rest/v1/sections', {
      metodo: 'POST',
      cuerpo: {
        program_id: creado.programa,
        subject_id: creado.materia,
        period_code: lapsoVigente,
        name: nombre,
        max_capacity: 20,
        is_active: true,
      },
      extra: { Prefer: 'return=representation' },
    });
    const id = fila.datos?.[0]?.id ?? null;
    if (!id) throw new Error(`no se pudo crear la sección ${seccion}: ${JSON.stringify(fila.datos)}`);
    creado.secciones.push(id);
  }
  comprobar('dos secciones del lapso vigente', creado.secciones.length === 2);

  const matricula = await pedir('/rest/v1/enrollments', {
    metodo: 'POST',
    cuerpo: {
      student_id: idEstudiante,
      section_id: creado.secciones[0],
      status: 'ENROLLED',
    },
    extra: { Prefer: 'return=representation' },
  });
  comprobar('el estudiante queda matriculado sólo en la sección A', matricula.estado < 300, `estado=${matricula.estado}`);

  // --- 2. Aulas: la sintaxis de PostgREST que el doble no analiza ----------
  console.log('\n  2. Aulas — filtros de tipo y de texto contra PostgREST\n');

  for (const [nombre, esTaller, capacidad] of [
    [NOMBRE_AULA_TALLER, true, 12],
    [NOMBRE_AULA_ZONA, false, 0],
  ]) {
    const fila = await pedir('/rest/v1/classrooms', {
      metodo: 'POST',
      clave: CLAVE_ANON,
      token: tokenAdmin,
      cuerpo: { name: nombre, is_workshop: esTaller, capacity: capacidad },
      extra: { Prefer: 'return=representation' },
    });
    const id = fila.datos?.[0]?.id ?? null;
    if (!id) throw new Error(`no se pudo crear el aula ${nombre}: ${JSON.stringify(fila.datos)}`);
    creado.aulas.push(id);
  }
  comprobar('un administrador REAL crea dos aulas (RLS con with check)', creado.aulas.length === 2);

  // El filtro `tipo=TALLER` del repositorio: `is_workshop=eq.true`.
  const talleres = await pedir(
    `/rest/v1/classrooms?is_workshop=eq.true&name=like.*${SUF}*&select=id,name`,
    { clave: CLAVE_ANON, token: tokenAdmin },
  );
  comprobar(
    'el filtro «taller» devuelve sólo el taller',
    talleres.datos?.length === 1 && talleres.datos[0].name === NOMBRE_AULA_TALLER,
    `${talleres.datos?.length} fila(s)`,
  );

  // El filtro `tipo=ZONA`: `is_workshop=false` Y `capacity=0`.
  const zonas = await pedir(
    `/rest/v1/classrooms?is_workshop=eq.false&capacity=eq.0&name=like.*${SUF}*&select=id,name`,
    { clave: CLAVE_ANON, token: tokenAdmin },
  );
  comprobar(
    'el filtro «zona» exige capacidad 0',
    zonas.datos?.length === 1 && zonas.datos[0].name === NOMBRE_AULA_ZONA,
    `${zonas.datos?.length} fila(s)`,
  );

  // El filtro `tipo=AULA`: `is_workshop=false` Y `capacity>0`. Ninguna de las dos
  // aulas temporales lo cumple, así que debe venir vacío — y eso también prueba
  // que las tres ramas no se solapan.
  const aulasTeoricas = await pedir(
    `/rest/v1/classrooms?is_workshop=eq.false&capacity=gt.0&name=like.*${SUF}*&select=id`,
    { clave: CLAVE_ANON, token: tokenAdmin },
  );
  comprobar('el filtro «aula» no se solapa con taller ni con zona', aulasTeoricas.datos?.length === 0);

  // El texto de búsqueda tal como lo arma `filtroIlike`. Un paréntesis de más
  // daría `PGRST100 unexpected "("`, que es el fallo que el doble no vería.
  const busqueda = await pedir(
    `/rest/v1/classrooms?or=(name.ilike.*${SUF}*)&select=id`,
    { clave: CLAVE_ANON, token: tokenAdmin },
  );
  comprobar(
    'el `or(...)` del texto de búsqueda es sintaxis válida',
    busqueda.estado === 200 && busqueda.datos?.length === 2,
    `estado=${busqueda.estado} ${codigo(busqueda)}`,
  );

  const orRoto = await pedir(
    `/rest/v1/classrooms?or=((name.ilike.*${SUF}*))&select=id`,
    { clave: CLAVE_ANON, token: tokenAdmin },
  );
  comprobar(
    'doblar los paréntesis SÍ rompe PostgREST (por eso `filtroIlike` no los añade)',
    orRoto.estado >= 400,
    `estado=${orRoto.estado} ${codigo(orRoto)}`,
  );

  // --- 3. PATCH sobre un id ausente: PGRST116 de verdad -------------------
  console.log('\n  3. El 404 de escritura: PGRST116 existe de verdad\n');

  const ID_FANTASMA = 'ffffffff-0000-4000-8000-000000000000';
  const parche = await pedir(`/rest/v1/classrooms?id=eq.${ID_FANTASMA}`, {
    metodo: 'PATCH',
    clave: CLAVE_ANON,
    token: tokenAdmin,
    cuerpo: { name: 'Aula fantasma' },
    // Esto es lo que manda `maybeSingle()`: sin la cabecera, PostgREST responde
    // 200 con `[]` y el 404 nunca se dispararía.
    extra: { Accept: 'application/vnd.pgrst.object+json' },
  });
  comprobar(
    'parchear un id ausente da PGRST116 (el 404 del repositorio)',
    codigo(parche) === 'PGRST116',
    `estado=${parche.estado} code=${codigo(parche)}`,
  );

  // --- 4. El lapso vigente está guardado ----------------------------------
  console.log('\n  4. El guarda de `periodo_activo`\n');

  const lapso = await pedir('/rest/v1/academic_periods', {
    metodo: 'POST',
    cuerpo: { code: COD_LAPSO, name: `Humo lapso ${SUF}`, is_active: false },
    extra: { Prefer: 'return=representation' },
  });
  creado.lapso = lapso.datos?.[0]?.id ?? null;
  comprobar('lapso temporal creado', Boolean(creado.lapso), `estado=${lapso.estado}`);

  const inexistente = await pedir('/rest/v1/system_settings?clave=eq.periodo_activo', {
    metodo: 'PATCH',
    cuerpo: { valor: 'NO-EXISTE-9' },
  });
  comprobar(
    'declarar un lapso que no está en el catálogo es un 23514',
    codigo(inexistente) === '23514',
    `estado=${inexistente.estado} code=${codigo(inexistente)}`,
  );

  const mover = await pedir('/rest/v1/system_settings?clave=eq.periodo_activo', {
    metodo: 'PATCH',
    cuerpo: { valor: COD_LAPSO },
  });
  comprobar('declarar un lapso que SÍ existe funciona', mover.estado < 300, `estado=${mover.estado}`);
  const volver = await pedir('/rest/v1/system_settings?clave=eq.periodo_activo', {
    metodo: 'PATCH',
    cuerpo: { valor: lapsoVigente },
  });
  comprobar('y se puede devolver al lapso original', volver.estado < 300, `estado=${volver.estado}`);

  // --- 5. Guardias y el trigger anti-colisión -----------------------------
  console.log('\n  5. Guardias — el trigger anti-colisión, con el mensaje real\n');

  const altaGuardia = (cuerpo) =>
    pedir('/rest/v1/teacher_duties', {
      metodo: 'POST',
      clave: CLAVE_ANON,
      token: tokenAdmin,
      cuerpo,
      extra: { Prefer: 'return=representation' },
    });

  const guardia = await altaGuardia({
    teacher_id: idDocente1,
    classroom_id: creado.aulas[0],
    period_code: lapsoVigente,
    day_of_week: 1,
    block: 1,
  });
  comprobar('el administrador asigna una guardia del lunes al bloque 1', guardia.estado < 300, `estado=${guardia.estado} ${textoError(guardia).slice(0, 160)}`);
  comprobar(
    '`turno` es columna GENERADA: la base calculó MAÑANA desde el bloque 1',
    guardia.datos?.[0]?.turno === 'MAÑANA',
    `turno=${guardia.datos?.[0]?.turno}`,
  );
  const idGuardia = guardia.datos?.[0]?.id ?? null;

  // (a) El mismo docente en el mismo hueco.
  const choqueDocente = await altaGuardia({
    teacher_id: idDocente1,
    classroom_id: creado.aulas[1],
    period_code: lapsoVigente,
    day_of_week: 1,
    block: 1,
  });
  comprobar(
    'el mismo docente en el mismo hueco da 23514',
    codigo(choqueDocente) === '23514',
    `estado=${choqueDocente.estado} code=${codigo(choqueDocente)}`,
  );
  comprobar(
    'y el mensaje es el que `esChoqueDeAgenda` reconoce',
    /ya tiene una clase o guardia asignada el lunes en el bloque 1/i.test(textoError(choqueDocente)),
    textoError(choqueDocente).slice(0, 200),
  );

  // (b) El mismo espacio con OTRO docente.
  const choqueEspacio = await altaGuardia({
    teacher_id: idDocente2,
    classroom_id: creado.aulas[0],
    period_code: lapsoVigente,
    day_of_week: 1,
    block: 1,
  });
  comprobar(
    'el mismo espacio con otro docente da 23514',
    codigo(choqueEspacio) === '23514',
    `estado=${choqueEspacio.estado} code=${codigo(choqueEspacio)}`,
  );
  comprobar(
    'y el mensaje es el del ESPACIO, no el del docente',
    /ya est[aá] ocupado el lunes en el bloque 1/i.test(textoError(choqueEspacio)),
    textoError(choqueEspacio).slice(0, 200),
  );

  // (c) El mismo hueco en OTRO lapso: debe permitirse. Es la razón por la que un
  // `unique (teacher_id, day_of_week, block)` habría estado mal.
  const otroLapso = await altaGuardia({
    teacher_id: idDocente1,
    classroom_id: creado.aulas[0],
    period_code: COD_LAPSO,
    day_of_week: 1,
    block: 1,
  });
  comprobar(
    'el MISMO hueco en otro lapso sí se permite',
    otroLapso.estado < 300,
    `estado=${otroLapso.estado} ${textoError(otroLapso).slice(0, 160)}`,
  );

  // --- 6. La clase y la colisión CRUZADA (dos tablas) ---------------------
  console.log('\n  6. El cuadrante — la colisión que cruza las DOS tablas\n');

  const altaClase = (cuerpo) =>
    pedir('/rest/v1/schedule_slots', {
      metodo: 'POST',
      clave: CLAVE_ANON,
      token: tokenAdmin,
      cuerpo,
      extra: { Prefer: 'return=representation' },
    });

  const clase = await altaClase({
    section_id: creado.secciones[0],
    teacher_id: idDocente2,
    classroom_id: creado.aulas[1],
    day_of_week: 3,
    block: 8,
  });
  comprobar('el administrador coloca una clase (miércoles, bloque 8)', clase.estado < 300, `estado=${clase.estado} ${textoError(clase).slice(0, 160)}`);
  comprobar('`turno` de la clase: TARDE desde el bloque 8', clase.datos?.[0]?.turno === 'TARDE', `turno=${clase.datos?.[0]?.turno}`);

  // Una segunda clase, del docente 1, en la MISMA sección. Hace falta para que
  // «el docente ve sólo lo suyo» tenga algo que sí debe ver: con cero filas esa
  // aserción pasaría sin probar nada. Y sirve para R-21, porque el docente 1 no
  // tiene nombre.
  const claseDocente1 = await altaClase({
    section_id: creado.secciones[0],
    teacher_id: idDocente1,
    classroom_id: creado.aulas[0],
    day_of_week: 5,
    block: 4,
  });
  comprobar('se coloca una segunda clase, del docente 1 (viernes, bloque 4)', claseDocente1.estado < 300, `estado=${claseDocente1.estado} ${textoError(claseDocente1).slice(0, 160)}`);

  // (d) Una CLASE que choca con una GUARDIA. El `schedule_slot` no comparte
  // tabla con `teacher_duties`, así que ningún `unique` podría verlo.
  const claseContraGuardia = await altaClase({
    section_id: creado.secciones[0],
    teacher_id: idDocente1,
    classroom_id: creado.aulas[1],
    day_of_week: 1,
    block: 1,
  });
  comprobar(
    'LA COLISIÓN CRUZADA: una clase choca con una GUARDIA del mismo docente',
    codigo(claseContraGuardia) === '23514',
    `estado=${claseContraGuardia.estado} code=${codigo(claseContraGuardia)}`,
  );
  comprobar(
    'y el mensaje nombra al docente, no al espacio',
    /ya tiene una clase o guardia asignada el lunes en el bloque 1/i.test(textoError(claseContraGuardia)),
    textoError(claseContraGuardia).slice(0, 200),
  );

  // --- 7. La vista enriquecida, y la RLS por rol --------------------------
  console.log('\n  7. `v_cuadrante_clases` — la vista y la RLS por rol\n');

  const rejilla = await pedir(`/rest/v1/v_cuadrante_clases?section_id=eq.${creado.secciones[0]}&select=*`, {
    clave: CLAVE_ANON,
    token: tokenAdmin,
  });
  // Los nombres de columna de la vista son los del SQL (`subject_name`,
  // `section_name`, `classroom_name`, `teacher_name`), no los del dominio: la
  // traducción a `materia`/`seccion`/… la hace el repositorio. Confundirlos es
  // fácil y sólo se ve contra la base real.
  const filaConNombre = (rejilla.datos ?? []).find((f) => f.teacher_id === idDocente2) ?? null;
  comprobar('el administrador ve las clases en la vista', rejilla.datos?.length === 2, `${rejilla.datos?.length} fila(s)`);
  comprobar(
    'la vista trae el nombre de la materia',
    typeof filaConNombre?.subject_name === 'string' && filaConNombre.subject_name.length > 0,
    `subject_name=${filaConNombre?.subject_name}`,
  );
  comprobar('la vista trae el nombre de la sección', filaConNombre?.section_name === SEC_A, `section_name=${filaConNombre?.section_name}`);
  comprobar(
    'la vista trae el nombre del aula',
    typeof filaConNombre?.classroom_name === 'string' && filaConNombre.classroom_name.length > 0,
    `classroom_name=${filaConNombre?.classroom_name}`,
  );
  comprobar('la vista deriva el lapso desde la sección', filaConNombre?.period_code === lapsoVigente, `period_code=${filaConNombre?.period_code}`);
  comprobar(
    'la vista trae el día legible que usa la interfaz',
    filaConNombre?.day_name === 'miércoles',
    `day_name=${filaConNombre?.day_name}`,
  );
  // R-14: el nombre del docente se resuelve con `nombre_para_mostrar()`, que es
  // `security definer` precisamente para que un estudiante lo vea sin poder
  // abrir `profiles` (donde están `cedula` y `email` de todo el centro).
  comprobar(
    'R-14: la vista resuelve el NOMBRE del docente cuando existe',
    filaConNombre?.teacher_name === 'Luisa Márquez',
    `teacher_name=${filaConNombre?.teacher_name}`,
  );

  // --- R-21: el nombre del docente está VACÍO en el canal real --------------
  //  Este bloque documenta un defecto abierto, no lo esconde. Ver
  //  `REPORTE_ARIA.md` R-21.
  const filaSinNombre = (rejilla.datos ?? []).find((f) => f.teacher_id === idDocente1) ?? null;
  comprobar(
    'R-21: un docente sin `nombres`/`apellidos` da `teacher_name` NULL',
    filaSinNombre?.teacher_name === null,
    `teacher_name=${JSON.stringify(filaSinNombre?.teacher_name)}`,
  );
  const perfilDesnudo = await pedir(
    `/rest/v1/profiles?id=eq.${idDocente1}&select=nombres,apellidos,rol`,
    { clave: CLAVE_ANON, token: tokenAdmin },
  );
  comprobar(
    'R-21: y sus columnas están VACÍAS (no NULL): `handle_new_user` inserta coalesce(…, \'\')',
    perfilDesnudo.datos?.[0]?.nombres === '' && perfilDesnudo.datos?.[0]?.apellidos === '',
    JSON.stringify(perfilDesnudo.datos?.[0]),
  );
  comprobar(
    'R-21: `nombre_para_mostrar` convierte ese vacío en NULL con nullif(btrim(…)) — la función está bien; el hueco está aguas arriba',
    filaSinNombre?.teacher_name === null,
  );

  // La sección B no tiene clases todavía: se le pone una para que el aislamiento
  // del estudiante tenga algo que NO debe ver.
  const claseB = await altaClase({
    section_id: creado.secciones[1],
    teacher_id: idDocente2,
    classroom_id: creado.aulas[1],
    day_of_week: 4,
    block: 9,
  });
  comprobar('se coloca una clase en la sección B', claseB.estado < 300, `estado=${claseB.estado}`);

  const comoDocente = await pedir('/rest/v1/v_cuadrante_clases?select=section_id,teacher_id', {
    clave: CLAVE_ANON,
    token: tokenDocente1,
  });
  const filasDocente = Array.isArray(comoDocente.datos) ? comoDocente.datos : [];
  comprobar(
    'el docente ve SÓLO sus propias clases',
    filasDocente.length > 0 && filasDocente.every((f) => f.teacher_id === idDocente1),
    `${filasDocente.length} fila(s) — ${textoError(comoDocente).slice(0, 200)}`,
  );
  comprobar(
    'el docente no ve la clase de otro docente',
    !filasDocente.some((f) => f.teacher_id === idDocente2),
  );

  const comoEstudiante = await pedir('/rest/v1/v_cuadrante_clases?select=section_id,teacher_id,teacher_name', {
    clave: CLAVE_ANON,
    token: tokenEstudiante,
  });
  const filasAlumno = Array.isArray(comoEstudiante.datos) ? comoEstudiante.datos : [];
  comprobar(
    'el estudiante ve SÓLO las clases de su sección',
    filasAlumno.length === 2 && filasAlumno.every((f) => f.section_id === creado.secciones[0]),
    `${filasAlumno.length} fila(s) — estado=${comoEstudiante.estado} ${textoError(comoEstudiante).slice(0, 240)}`,
  );
  comprobar(
    'el estudiante NO ve la clase de la sección donde no está matriculado',
    !filasAlumno.some((f) => f.section_id === creado.secciones[1]),
  );
  comprobar(
    'y aun así ve el nombre del docente, sin poder abrir `profiles` (R-14)',
    filasAlumno.some((f) => f.teacher_name === 'Luisa Márquez'),
    JSON.stringify(filasAlumno.map((f) => f.teacher_name)),
  );
  const comoAlumnoPerfiles = await pedir(
    `/rest/v1/profiles?id=eq.${idDocente2}&select=nombres`,
    { clave: CLAVE_ANON, token: tokenEstudiante },
  );
  comprobar(
    'y NO puede leer `profiles` del docente: por eso hacía falta la función',
    (comoAlumnoPerfiles.datos?.length ?? -1) === 0 || comoAlumnoPerfiles.estado >= 400,
    `estado=${comoAlumnoPerfiles.estado} filas=${comoAlumnoPerfiles.datos?.length}`,
  );

  const guardiasAlumno = await pedir('/rest/v1/teacher_duties?select=id', {
    clave: CLAVE_ANON,
    token: tokenEstudiante,
  });
  comprobar(
    'el estudiante no ve NINGUNA guardia de custodia',
    (guardiasAlumno.datos?.length ?? -1) === 0 || guardiasAlumno.estado >= 400,
    `estado=${guardiasAlumno.estado} filas=${guardiasAlumno.datos?.length}`,
  );

  const guardiasDocente = await pedir('/rest/v1/teacher_duties?select=id,teacher_id', {
    clave: CLAVE_ANON,
    token: tokenDocente1,
  });
  comprobar(
    'el docente ve SÓLO sus propias guardias',
    (guardiasDocente.datos ?? []).every((g) => g.teacher_id === idDocente1),
    `${guardiasDocente.datos?.length} fila(s)`,
  );

  const comoAnon = await pedir('/rest/v1/v_cuadrante_clases?select=section_id', { clave: CLAVE_ANON });
  comprobar(
    '`anon` no ve el cuadrante de nadie',
    (comoAnon.datos?.length ?? -1) === 0 || comoAnon.estado >= 400,
    `estado=${comoAnon.estado} filas=${comoAnon.datos?.length}`,
  );

  // --- 8. Archivar libera el hueco ---------------------------------------
  console.log('\n  8. Archivar una guardia libera su hueco\n');

  if (idGuardia) {
    const archivar = await pedir(`/rest/v1/teacher_duties?id=eq.${idGuardia}`, {
      metodo: 'PATCH',
      clave: CLAVE_ANON,
      token: tokenAdmin,
      cuerpo: { is_active: false },
    });
    comprobar('la guardia se archiva con is_active = false', archivar.estado < 300, `estado=${archivar.estado}`);

    const reocupar = await altaGuardia({
      teacher_id: idDocente1,
      classroom_id: creado.aulas[0],
      period_code: lapsoVigente,
      day_of_week: 1,
      block: 1,
    });
    comprobar(
      'y el hueco que ocupaba queda libre',
      reocupar.estado < 300,
      `estado=${reocupar.estado} ${textoError(reocupar).slice(0, 160)}`,
    );
  }

  console.log('\n  9. Limpieza\n');
} catch (error) {
  fallos += 1;
  console.error(`  [FALLA] excepción: ${error.message}`);
} finally {
  await purgar();

  // El residuo se comprueba, no se supone: una purga que falla en silencio deja
  // basura en producción y el humo diría «verde».
  const residuoAulas = await pedir(`/rest/v1/classrooms?name=like.Humo*${SUF}*&select=id`);
  const residuoUsuarios = await pedir('/rest/v1/profiles?email=like.humo3-*&select=id');
  const residuoLapso = await pedir(`/rest/v1/academic_periods?code=eq.${COD_LAPSO}&select=id`);
  const residuoSecciones = await pedir(`/rest/v1/sections?name=like.H*${SUF.slice(-3)}*&select=id`);
  const limpio =
    (residuoAulas.datos?.length ?? -1) === 0 &&
    (residuoUsuarios.datos?.length ?? -1) === 0 &&
    (residuoLapso.datos?.length ?? -1) === 0 &&
    (residuoSecciones.datos?.length ?? -1) === 0;
  comprobar('la purga no dejó residuo (aulas, perfiles, lapso, secciones)', limpio);

  console.log(
    `\n  ${fallos === 0 ? `✓ Humo superado — ${ok} comprobaciones en verde.` : `✗ ${fallos} comprobación(es) fallida(s), ${ok} en verde.`}\n`,
  );
  process.exit(fallos === 0 ? 0 : 1);
}
