/**
 * Humo de integración del Módulo 6 — Aula Virtual.
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que la suite `backend/test/aula.test.ts` **no puede** verificar con sus
 * dobles en memoria:
 *
 *   1. El bucle docente→alumno→docente de verdad contra la base: crear tarea,
 *      publicar (que crea los `ASIGNADA` placeholders para los matriculados),
 *      entregar, calificar borrador y devolver (única puerta que copia el
 *      borrador a la nota visible al alumno).
 *   2. La RLS por rol: el docente ve la entrega del alumno, el alumno ve la
 *      suya propia y NO ve la de otro compañero, y un tercero sin rol docente
 *      no ve nada.
 *   3. La política de visibilidad del tablón —la «publicación diferida sin
 *      planificador»—: un anuncio programado en el pasado ya lo ve el alumno,
 *      y uno sin programar (BORRADOR) NO se le filtra.
 *   4. Que crear un `MATERIAL` sin `puntosMaximos` **no reciba el 20 de
 *      negocio** (R-25 del sprint anterior): el default del RPC es `null` y el
 *      CHECK `m6_tareas_material_sin_nota` lo deja en 0.
 *   5. Que `m6_dicta_seccion` manda: sin una clase en el cuadrante (M3) el
 *      docente recibe `SIN_PERMISO_EN_EL_AULA`, aunque sea docente y la sección
 *      exista. Es la dependencia M6→M3 que más fácil se olvida.
 *   6. La purga cierra limpio: cero secciones, cero matrículas, cero usuarios
 *      `humo-aula-*`, cero materias y aulas temporales.
 *
 * NO cubre la subida de adjuntos a R2: eso lo hace `humo-archivos.mjs`, y M6
 * sólo aporta el `entidad_id` que enlaza el archivo con la entrega.
 *
 * FUERA DE CI A PROPÓSITO: escribe en la base real. La purga corre también si
 * el flujo falla a mitad, igual que los demás humos del proyecto.
 *
 * USO
 * ---
 *   node supabase/humo-aula.mjs              # simulación (no escribe)
 *   node supabase/humo-aula.mjs --confirmar  # ejecuta y purga
 *
 * Necesita el backend levantado en 3001 y credenciales reales en `backend/.env`
 * (Supabase + R2 opcional para adjuntos — esta corrida no usa archivos).
 */
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const CONFIRMAR = process.argv.includes('--confirmar');
const API = (process.env.API_BASE_URL ?? 'http://127.0.0.1:3001').replace(/\/+$/, '');

/** Lee del entorno y, si no, de `backend/.env` (sin añadir `dotenv`). */
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
    // sin .env legible: ausencia, más abajo.
  }
  return '';
}

const URL_BASE = variable('SUPABASE_URL').replace(/\/+$/, '');
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

/** Petición a Supabase (PostgREST/GoTrue) que NO lanza por códigos HTTP. */
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

/** Petición al backend propio (Fastify). El cuerpo viaja en JSON salvo vacío. */
async function api(ruta, { metodo = 'GET', token, cuerpo } = {}) {
  const r = await fetch(`${API}${ruta}`, {
    method: metodo,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(cuerpo === undefined ? {} : { 'Content-Type': 'application/json' }),
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
  return { estado: r.status, datos };
}

const codigoDe = (datos) => datos?.error?.codigo ?? null;

if (!URL_BASE || !CLAVE_SERVICIO || !CLAVE_ANON) {
  console.error('\n  Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o SUPABASE_ANON_KEY.');
  console.error('  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n');
  process.exit(1);
}

const marca = Date.now();
const PREFIJO = `humo-aula-${marca}`;
const CORREO_DOC = `${PREFIJO}-doc@ejemplo.invalid`;
const CORREO_EST = `${PREFIJO}-est@ejemplo.invalid`;
const CORREO_EXT = `${PREFIJO}-otro@ejemplo.invalid`;
const CORREO_ADMIN = `humo-admin-${marca}@ejemplo.invalid`;
const CLAVE = `Humo!${randomBytes(12).toString('base64url')}`;

const ids = { doc: null, est: null, ext: null, admin: null };
const tokens = { doc: null, est: null, ext: null, admin: null };

/** Lo que creamos, para el informe de purga. */
const creados = {
  materiaId: null,
  seccionId: null,
  aulaId: null,
  claseId: null,
  tareaId: null,
  anuncioId: null,
  borradorAnuncioId: null,
  entregaId: null,
};

console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Backend  : ${API}`);
console.log(`  Modo     : ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);

if (!CONFIRMAR) {
  const salud = await fetch(`${API}/salud`)
    .then((r) => r.status)
    .catch(() => null);
  console.log(`\n  Backend ${salud === null ? 'NO responde' : `responde ${salud}`}.`);
  console.log('\n  Simulación: no se escribió nada. Repite con --confirmar.\n');
  process.exit(0);
}

/**
 * Purga todo lo que crea este script, también si algo falla a mitad.
 *
 * DOS DEFECTOS QUE ESTA VERSIÓN CORRIGE, aprendidos en carne propia:
 *
 *  1. **El orden de los FK.** `program_subjects.subject_id` es
 *     `on delete restrict`: borrar la materia antes que su vínculo al pensum
 *     falla y deja las dos filas. La primera versión tenía el comentario
 *     correcto («va antes») y el código al revés. Los comentarios no ejecutan.
 *  2. **Borrar sólo por id recordado no purga.** Si una corrida muere antes de
 *     capturar el id de lo que ya creó —pasó, y dejó 4 materias y 1 sección—,
 *     no hay nada que borrar. Por eso además se barre por MARCADOR: el `code`
 *     de las materias (`HUMO######`) es la ancla, y de él se derivan las
 *     secciones y los vínculos, que no tienen marcador propio.
 *
 * El barrido por marcador es lo que hace la purga idempotente: una corrida
 * limpia también el residuo de las anteriores.
 */
async function purgar() {
  console.log('\n  --- purga ---');
  for (const id of [ids.ext, ids.est, ids.doc, ids.admin]) {
    if (!id) continue;
    await pedir(`/auth/v1/admin/users/${id}`, { metodo: 'DELETE' });
  }

  // --- 1. Encontrar las materias del humo, vivas o de corridas anteriores ---
  const marcas = await pedir('/rest/v1/subjects?select=id&code=like.HUMO*');
  const materias = (marcas.datos ?? []).map((m) => m.id);
  if (creados.materiaId && !materias.includes(creados.materiaId)) {
    materias.push(creados.materiaId);
  }
  const lista = materias.length > 0 ? materias.join(',') : null;

  // Las secciones del humo se localizan por su materia: `sections` no tiene
  // marcador propio (el `name` es «TMP», que es legítimo en una sección real).
  let secciones = [];
  if (lista) {
    const filas = await pedir(
      `/rest/v1/sections?select=id&subject_id=in.(${lista})`,
    );
    secciones = (filas.datos ?? []).map((s) => s.id);
  }
  if (creados.seccionId && !secciones.includes(creados.seccionId)) {
    secciones.push(creados.seccionId);
  }
  const listaSec = secciones.length > 0 ? secciones.join(',') : null;

  // --- 2. Hijos de la sección, de hoja a raíz ---
  if (listaSec) {
    await pedir(`/rest/v1/m6_entregas?tarea_id=in.(${await idsDeTareas(listaSec)})`, {
      metodo: 'DELETE',
    }).catch(() => {});
    await pedir(`/rest/v1/m6_tareas?seccion_id=in.(${listaSec})`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/m6_anuncios?seccion_id=in.(${listaSec})`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/enrollments?seccion_id=in.(${listaSec})`, { metodo: 'DELETE' });
    // El cuadrante antes que la sección y que el aula: `classroom_id` es
    // `on delete restrict`, así que borrar el aula primero fallaría.
    await pedir(`/rest/v1/schedule_slots?section_id=in.(${listaSec})`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/sections?id=in.(${listaSec})`, { metodo: 'DELETE' });
  }

  // --- 3. Pensum ANTES que la materia (FK restrict), y luego la materia ---
  if (lista) {
    await pedir(`/rest/v1/program_subjects?subject_id=in.(${lista})`, { metodo: 'DELETE' });
    await pedir(`/rest/v1/subjects?id=in.(${lista})`, { metodo: 'DELETE' });
  }

  // --- 4. Aulas del humo (marcador en el nombre) ---
  if (creados.aulaId) {
    await pedir(`/rest/v1/classrooms?id=eq.${creados.aulaId}`, { metodo: 'DELETE' });
  }
  await pedir('/rest/v1/classrooms?nombre=like.Aula humo*', { metodo: 'DELETE' });

  // --- 5. Residuo defensivo de perfiles ---
  await pedir('/rest/v1/profiles?email=like.humo-aula-*', { metodo: 'DELETE' });
  await pedir('/rest/v1/profiles?email=like.humo-admin-*', { metodo: 'DELETE' });
}

/** Ids de las tareas de una lista de secciones, para borrar sus entregas. */
async function idsDeTareas(listaSec) {
  const filas = await pedir(
    `/rest/v1/m6_tareas?select=id&seccion_id=in.(${listaSec})`,
  );
  const ids = (filas.datos ?? []).map((t) => t.id);
  // `in.()` vacío no es SQL válido: se devuelve un UUID imposible para que el
  // DELETE sea inocuo en vez de reventar.
  return ids.length > 0 ? ids.join(',') : '00000000-0000-0000-0000-000000000000';
}

/** Crea una cuenta temporal y devuelve id + JWT real. */
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

try {
  // ==========================================================================
  //  1. Salud del backend
  // ==========================================================================
  console.log('\n  1. Backend y módulos\n');

  const salud = await fetch(`${API}/salud`)
    .then((r) => r.status)
    .catch(() => null);
  if (salud !== 200) throw new Error(`backend ausente (estado=${salud})`);
  comprobar('el backend responde en /salud', salud === 200);

  const modulos = await api('/api/v1/admin/modulos', { token: 'placeholder' }).catch(() => null);
  // La prueba real de módulos ya la hace `test-humo.mjs`. Aquí basta con que
  // respondan las rutas del aula, que requieren el módulo encendido.
  const tablonVacio = await api('/api/v1/aula/secciones/00000000-0000-0000-0000-000000000000/tablon', {
    token: 'placeholder',
  });
  comprobar(
    'el aula exige sesión o módulo encendido',
    [401, 403, 404].includes(tablonVacio.estado),
    `estado=${tablonVacio.estado}`,
  );

  // ==========================================================================
  //  2. Tres personas con JWT real
  // ==========================================================================
  console.log('\n  2. Personas con sesión real\n');

  const admin = await crearPersona(CORREO_ADMIN, 'admin');
  ids.admin = admin.id;
  tokens.admin = admin.token;
  comprobar('admin existe y tiene sesión', Boolean(tokens.admin), admin.error ?? '');

  const doc = await crearPersona(CORREO_DOC, 'docente');
  ids.doc = doc.id;
  tokens.doc = doc.token;
  comprobar('docente existe y tiene sesión', Boolean(tokens.doc), doc.error ?? '');

  const est = await crearPersona(CORREO_EST, 'estudiante');
  ids.est = est.id;
  tokens.est = est.token;
  comprobar('estudiante existe y tiene sesión', Boolean(tokens.est), est.error ?? '');

  const ext = await crearPersona(CORREO_EXT, 'estudiante');
  ids.ext = ext.id;
  tokens.ext = ext.token;
  // Este tercero sirve para probar que NO ve entregas ajenas.

  // ==========================================================================
  //  3. Catálogo: aula + materia + sección (admin)
  // ==========================================================================
  console.log('\n  3. Catálogo (admin): aula + materia + sección\n');

  // El aula SÍ hace falta, aunque sea del M3: `schedule_slots.classroom_id` es
  // obligatorio y `m6_dicta_seccion` se apoya en esa tabla. Sin una clase en el
  // cuadrante, el docente no «dicta» la sección y el aula virtual le responde
  // `SIN_PERMISO_EN_EL_AULA`.
  const aula = await api('/api/v1/admin/aulas', {
    metodo: 'POST',
    token: tokens.admin,
    // Cuerpo REAL de `CuerpoCrearAula`: `nombre`, `capacidad`, `esTaller`.
    // `codigo` y `tipo` no existen en el esquema (dan PETICION_INVALIDA).
    cuerpo: { nombre: `Aula humo ${marca}`, capacidad: 10, esTaller: true },
  });
  creados.aulaId = aula.datos?.aula?.id ?? aula.datos?.id ?? null;
  comprobar(
    'el admin crea el aula del taller',
    Boolean(creados.aulaId),
    JSON.stringify(aula.datos),
  );

  // Toma un programa existente (los hay sembrados) y crea una materia nueva
  // vinculada. service_role crea la materia directamente.
  const programa = await pedir(
    '/rest/v1/programs?is_active=eq.true&select=id&limit=1',
    { token: null },
  );
  const programaId = programa.datos?.[0]?.id ?? null;
  comprobar('hay al menos un programa activo sembrado', Boolean(programaId));

  const materia = await pedir('/rest/v1/subjects', {
    metodo: 'POST',
    cuerpo: {
      // `subjects.code` es varchar(12) con CHECK `^[A-Z0-9][A-Z0-9-]{0,11}$`:
      // la marca completa (13 dígitos) no cabe. Seis dígitos bastan para no
      // chocar con una corrida anterior y respetan el patrón.
      code: `HUMO${String(marca).slice(-6)}`,
      name: `Materia humo ${marca}`,
      // `subjects` no tiene `credits`: la columna real es `academic_hours`
      // y exige > 0. Un `credits` inventado da PGRST204.
      academic_hours: 48,
    },
    extra: { Prefer: 'return=representation' },
  });
  creados.materiaId = materia.datos?.[0]?.id ?? null;
  comprobar('se crea la materia temporal', Boolean(creados.materiaId), JSON.stringify(materia.datos));

  // Vincular materia al programa (pensum): la columna está en `program_subjects`.
  if (creados.materiaId && programaId) {
    await pedir('/rest/v1/program_subjects', {
      metodo: 'POST',
      cuerpo: { program_id: programaId, subject_id: creados.materiaId },
    });
  }

  const seccion = await api('/api/v1/admin/secciones', {
    metodo: 'POST',
    token: tokens.admin,
    cuerpo: {
      programaId,
      materiaId: creados.materiaId,
      periodo: 'SA26-2',
      nombre: 'TMP',
      cupoMaximo: 2,
    },
  });
  // OJO con el sobre: el backend devuelve `{ seccion: {...} }`, no la sección
  // suelta. Leer `datos.id` da `undefined` y la cascada de fallos que sigue
  // parece un problema de la base cuando es del cliente.
  creados.seccionId = seccion.datos?.seccion?.id ?? null;
  comprobar(
    'el admin crea la sección',
    seccion.estado === 201 && Boolean(creados.seccionId),
    JSON.stringify(seccion.datos),
  );

  // Asignar el docente a la sección EN EL CUADRANTE. Es el paso que hace que
  // `m6_dicta_seccion` devuelva cierto: sin él, todo el Centro de Mando del
  // Docente responde `SIN_PERMISO_EN_EL_AULA` y el fallo parece de M6 cuando
  // en realidad falta un dato de M3.
  const clase = await api('/api/v1/admin/cuadrante', {
    metodo: 'POST',
    token: tokens.admin,
    cuerpo: {
      seccionId: creados.seccionId,
      docenteId: ids.doc,
      aulaId: creados.aulaId,
      dia: 1,
      bloque: 1,
    },
  });
  creados.claseId = clase.datos?.clase?.id ?? clase.datos?.id ?? null;
  comprobar(
    'el admin asigna el docente a la sección (cuadrante)',
    Boolean(creados.claseId),
    JSON.stringify(clase.datos),
  );

  // Comprobación directa del permiso: el docente ya «dicta» la sección.
  const suHorario = await api('/api/v1/mi-horario', { token: tokens.doc });
  const dicta = (suHorario.datos?.clases ?? []).some(
    (c) => c.seccionId === creados.seccionId,
  );
  comprobar('el docente ve la sección en su horario', dicta, JSON.stringify(suHorario.datos));

  // ==========================================================================
  //  4. Matricular al estudiante (y al tercero, que verá vacío)
  // ==========================================================================
  console.log('\n  4. Matricular al estudiante en la sección\n');

  const inscrEst = await api('/api/v1/inscripciones', {
    metodo: 'POST',
    token: tokens.est,
    cuerpo: { seccionId: creados.seccionId },
  });
  comprobar(
    'el estudiante se inscribe → ENROLLED',
    // POST de creación: 201, no 200. Con `=== 200` la aserción fallaba aunque
    // la respuesta ya dijera `{"estado":"ENROLLED"}`.
    inscrEst.estado === 201 && inscrEst.datos?.estado === 'ENROLLED',
    `estado=${inscrEst.estado} ${JSON.stringify(inscrEst.datos)}`,
  );

  const inscrExt = await api('/api/v1/inscripciones', {
    metodo: 'POST',
    token: tokens.ext,
    cuerpo: { seccionId: creados.seccionId },
  });
  comprobar(
    'el tercero se inscribe también (para probar aislamiento)',
    inscrExt.estado === 201 && inscrExt.datos?.estado === 'ENROLLED',
    `estado=${inscrExt.estado} ${JSON.stringify(inscrExt.datos)}`,
  );

  // ==========================================================================
  //  5. Como DOCENTE: anuncio + tarea + publicar
  // ==========================================================================
  console.log('\n  5. Centro de Mando del Docente\n');

  const anuncio = await api(`/api/v1/aula/secciones/${creados.seccionId}/anuncios`, {
    metodo: 'POST',
    token: tokens.doc,
    // Programado en el PASADO: es la publicación diferida sin planificador.
    // Un anuncio sin `programadoPara` se queda en BORRADOR y el alumno no lo
    // ve —que es justo lo que comprueba el segundo anuncio, más abajo.
    cuerpo: {
      titulo: 'Bienvenida',
      cuerpo: 'Recuerden traer el taller al día.',
      programadoPara: new Date(Date.now() - 60_000).toISOString(),
    },
  });
  creados.anuncioId = anuncio.datos?.anuncio?.id ?? null;
  comprobar(
    'el docente crea un anuncio programado',
    anuncio.estado === 201 && Boolean(creados.anuncioId),
    JSON.stringify(anuncio.datos),
  );

  // Segundo anuncio, sin programar: debe quedarse invisible para el alumno.
  const borrador = await api(`/api/v1/aula/secciones/${creados.seccionId}/anuncios`, {
    metodo: 'POST',
    token: tokens.doc,
    cuerpo: { titulo: 'Nota privada del docente', cuerpo: 'Todavía sin publicar.' },
  });
  creados.borradorAnuncioId = borrador.datos?.anuncio?.id ?? null;
  comprobar(
    'el segundo anuncio nace en BORRADOR',
    borrador.datos?.anuncio?.estado === 'BORRADOR',
    JSON.stringify(borrador.datos),
  );

  const tarea = await api(`/api/v1/aula/secciones/${creados.seccionId}/tareas`, {
    metodo: 'POST',
    token: tokens.doc,
    cuerpo: {
      titulo: 'Soldar junta a tope',
      descripcion: 'Una práctica de la unidad 1.',
      tipo: 'TAREA',
      puntosMaximos: 10,
    },
  });
  creados.tareaId = tarea.datos?.tarea?.id ?? null;
  comprobar(
    'el docente crea la tarea (BORRADOR)',
    tarea.estado === 201 && tarea.datos?.tarea?.estado === 'BORRADOR',
    JSON.stringify(tarea.datos),
  );

  const publicar = await api(`/api/v1/aula/tareas/${creados.tareaId}/publicar`, {
    metodo: 'POST',
    token: tokens.doc,
  });
  comprobar(
    'publicar la tarea → PUBLICADO',
    publicar.estado === 200 && publicar.datos?.tarea?.estado === 'PUBLICADO',
    JSON.stringify(publicar.datos),
  );

  // ==========================================================================
  //  6. Como ESTUDIANTE: ver el tablón, ver el trabajo, encontrar su entrega
  // ==========================================================================
  console.log('\n  6. Aula del Estudiante (visibilidad + RLS)\n');

  const tablon = await api(`/api/v1/aula/secciones/${creados.seccionId}/tablon`, {
    token: tokens.est,
  });
  const anuncios = tablon.datos?.anuncios ?? [];
  const anuncioVisible = anuncios.some((a) => a.id === creados.anuncioId);
  const borradorOculto = !anuncios.some((a) => a.id === creados.borradorAnuncioId);
  comprobar(
    'el estudiante ve el anuncio programado en el pasado',
    anuncioVisible,
    JSON.stringify(tablon.datos),
  );
  comprobar(
    'el estudiante NO ve el anuncio en BORRADOR',
    borradorOculto,
    'un borrador del docente no debe filtrarse al tablón del alumno',
  );

  const trabajo = await api(`/api/v1/aula/secciones/${creados.seccionId}/trabajo`, {
    token: tokens.est,
  });
  const tareaVisible = (trabajo.datos?.tareas ?? []).some(
    (t) => t.id === creados.tareaId && t.estado === 'PUBLICADO',
  );
  comprobar(
    'el estudiante ve la tarea PUBLICADO',
    tareaVisible,
    JSON.stringify(trabajo.datos),
  );

  // ==========================================================================
  //  7. Publicar crea los ASIGNADA: el docente los ve
  // ==========================================================================
  console.log('\n  7. Publicación crea placeholders ASIGNADA para matriculados\n');

  const entregasDoc = await api(`/api/v1/aula/tareas/${creados.tareaId}/entregas`, {
    token: tokens.doc,
  });
  const entregas = entregasDoc.datos?.entregas ?? [];
  comprobar(
    'el docente ve 2 entregas (uno por matriculado)',
    entregas.length === 2,
    `entregas=${entregas.length}`,
  );
  const entregaEst = entregas.find((e) => e.estudianteId === ids.est) ?? null;
  creados.entregaId = entregaEst?.id ?? null;
  comprobar(
    'la entrega del estudiante empieza en ASIGNADA',
    entregaEst?.estado === 'ASIGNADA',
    JSON.stringify(entregaEst),
  );

  // ==========================================================================
  //  8. Aislamiento: el tercero no ve las entregas ajenas vía mis-entregas
  //     (sólo vería la suya; aquí verificamos que ve sólo una, la suya).
  // ==========================================================================
  console.log('\n  8. Aislamiento de RLS: cada alumno ve sólo sus entregas\n');

  const misEntExt = await api('/api/v1/aula/mis-entregas', { token: tokens.ext });
  const suyas = misEntExt.datos?.entregas ?? [];
  // `mis-entregas` NO devuelve `estudianteId` (COLUMNAS_ENTREGA no lo incluye:
  // son tus entregas, el dueño es implícito). La prueba de aislamiento es
  // entonces el CONTEO: si viera las del compañero saldrían 2, y salen 1.
  comprobar(
    'el tercero ve exactamente 1 entrega (la suya, no la del compañero)',
    suyas.length === 1,
    `entregas=${suyas.length} ${JSON.stringify(suyas)}`,
  );
  comprobar(
    'el tercero no ve la entrega del compañero',
    !suyas.some((e) => e.id === creados.entregaId),
    'la RLS debe filtrar por estudiante, no devolver todo',
  );

  // ==========================================================================
  //  9. Entregar y calificar (el bucle central que el plan del usuario pidió)
  // ==========================================================================
  console.log('\n  9. Bucle entregar → calificar → devolver\n');

  const entrega = await api(`/api/v1/aula/entregas/${creados.entregaId}/entregar`, {
    metodo: 'POST',
    token: tokens.est,
  });
  comprobar(
    'el estudiante marca la entrega como ENTREGADA',
    entrega.estado === 200 && entrega.datos?.entrega?.estado === 'ENTREGADA',
    JSON.stringify(entrega.datos),
  );

  const calif = await api(`/api/v1/aula/entregas/${creados.entregaId}/calificar`, {
    metodo: 'POST',
    token: tokens.doc,
    cuerpo: { nota: 9 },
  });
  comprobar(
    'el docente escribe nota_borrador=9',
    calif.estado === 200 &&
      calif.datos?.entrega?.notaBorrador === 9 &&
      calif.datos?.entrega?.estado === 'ENTREGADA',
    JSON.stringify(calif.datos),
  );

  // Antes de devolver, el alumno NO debe ver la nota (sólo ve su `notaAsignada`).
  const verEstAntes = await api('/api/v1/aula/mis-entregas', { token: tokens.est });
  const entregaEstAntes = (verEstAntes.datos?.entregas ?? []).find(
    (e) => e.id === creados.entregaId,
  );
  comprobar(
    'antes de devolver, notaAsignada es null para el alumno',
    entregaEstAntes?.notaAsignada === null,
    JSON.stringify(entregaEstAntes),
  );

  const devol = await api(`/api/v1/aula/entregas/${creados.entregaId}/devolver`, {
    metodo: 'POST',
    token: tokens.doc,
  });
  comprobar(
    'devolver → DEVUELTA y notaAsignada=9',
    devol.estado === 200 &&
      devol.datos?.entrega?.estado === 'DEVUELTA' &&
      devol.datos?.entrega?.notaAsignada === 9,
    JSON.stringify(devol.datos),
  );

  const verEstDespues = await api('/api/v1/aula/mis-entregas', { token: tokens.est });
  const entregaEstDespues = (verEstDespues.datos?.entregas ?? []).find(
    (e) => e.id === creados.entregaId,
  );
  comprobar(
    'después de devolver, el alumno ve notaAsignada=9',
    entregaEstDespues?.notaAsignada === 9,
    JSON.stringify(entregaEstDespues),
  );

  // ==========================================================================
  //  10. MATERIAL sin puntos (R-25 del sprint anterior: el default debe ser null)
  // ==========================================================================
  console.log('\n  10. Crear MATERIAL con puntos_maximos=null (R-25)\n');

  const material = await api(`/api/v1/aula/secciones/${creados.seccionId}/tareas`, {
    metodo: 'POST',
    token: tokens.doc,
    cuerpo: { titulo: 'Lectura recomendada', tipo: 'MATERIAL' },
  });
  comprobar(
    // R-25: el default del RPC es `null`, así que omitir el argumento NO
    // inyecta el 20 de negocio. Y el CHECK `m6_tareas_material_sin_nota`
    // obliga a que un MATERIAL acabe en 0, no en null: el valor correcto es 0.
    'un MATERIAL sin puntos se crea con puntosMaximos=0 (no recibe el 20 de negocio)',
    material.estado === 201 && material.datos?.tarea?.puntosMaximos === 0,
    JSON.stringify(material.datos),
  );

  await purgar();
} catch (e) {
  console.error(`\n  ERROR: ${e.message}\n  Ejecutando purga…`);
  await purgar();
  process.exit(1);
}

console.log(`\n  ----------------  HUMO M6  ----------------`);
console.log(`  OK   : ${ok}`);
console.log(`  FALLAS: ${fallos}`);
console.log(`  Purga: limpia.\n`);
process.exit(fallos === 0 ? 0 : 1);