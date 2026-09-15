/**
 * Humo de integración del asistente de M2 (Currículo y Pensum).
 *
 * QUÉ VERIFICA
 * ------------
 * Lo que las 189 pruebas del backend NO pueden verificar, porque usan dobles en
 * memoria: que el motor real (PostgREST + los triggers de Postgres) se comporte
 * como el doble predijo.
 *
 *   1. `crear_programa_con_pensum` publica una CARRERA activa con su pensum en
 *      UNA sola llamada, y el constraint trigger diferido de la Regla 1 la
 *      acepta. Es la razón de ser de la función.
 *   2. **Atomicidad de verdad**: con el pensum vacío, la función falla y NO deja
 *      el programa. Un doble en memoria no puede demostrar esto.
 *   3. `reemplazar_pensum` calcula la diferencia sola: reordena, inserta y borra.
 *   4. La Regla 2 bloquea un reordenamiento cuando hay secciones activas, y deja
 *      el pensum intacto (la función se deshace entera).
 *
 * CÓMO FUNCIONA
 * -------------
 * Escribe en producción, así que exige `--confirmar`. Usa códigos con prefijo
 * `TMP` y purga todo lo que crea, también si falla a mitad.
 *
 * USO
 * ---
 *   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node supabase/humo-curriculo.mjs --confirmar
 *
 * No corre en CI: toca la base real. Es una herramienta de verificación manual,
 * igual que `humo-invitaciones.mjs`.
 */
const URL_BASE = (process.env.SUPABASE_URL ?? '').trim();
const CLAVE = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();
const CONFIRMAR = process.argv.includes('--confirmar');

if (!URL_BASE || !CLAVE) {
  console.error('\n  Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en el entorno.\n');
  process.exit(1);
}

if (!CONFIRMAR) {
  console.log(
    '\n  Simulación: este humo ESCRIBE en la base de datos (crea un programa y\n' +
      '  dos materias temporales, y los borra al final). Repite con --confirmar.\n',
  );
  process.exit(0);
}

const cabeceras = {
  apikey: CLAVE,
  Authorization: `Bearer ${CLAVE}`,
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
};

async function rest(ruta, opciones = {}) {
  const r = await fetch(`${URL_BASE}/rest/v1/${ruta}`, {
    ...opciones,
    headers: { ...cabeceras, ...(opciones.headers ?? {}) },
  });
  const texto = await r.text();
  return { ok: r.ok, status: r.status, cuerpo: texto.length > 0 ? JSON.parse(texto) : null };
}

let fallos = 0;
function comprobar(etiqueta, condicion, detalle) {
  if (!condicion) fallos += 1;
  console.log(`  [${condicion ? 'OK  ' : 'FALLA'}] ${etiqueta}${detalle ? ` — ${detalle}` : ''}`);
}

// `code` es varchar(12) en las dos tablas: el sufijo va pegado, sin guiones.
const SUF = Date.now().toString().slice(-6);
const COD_M1 = `TM1${SUF}`;
const COD_M2 = `TM2${SUF}`;
const COD_P1 = `TP1${SUF}`;
const COD_P2 = `TP2${SUF}`;

const creados = { materias: [], programas: [] };

try {
  console.log('\n  1. Materias de apoyo\n');
  for (const [codigo, nombre] of [
    [COD_M1, 'Humo Alfa'],
    [COD_M2, 'Humo Beta'],
  ]) {
    const m = await rest('subjects', {
      method: 'POST',
      body: JSON.stringify({ code: codigo, name: nombre, academic_hours: 48 }),
    });
    if (!m.ok) throw new Error(`no se pudo crear la materia: ${JSON.stringify(m.cuerpo)}`);
    creados.materias.push(m.cuerpo[0].id);
  }
  const [idM1, idM2] = creados.materias;
  comprobar('dos materias creadas', creados.materias.length === 2);

  console.log('\n  2. El asistente: CARRERA activa + pensum en UNA llamada\n');
  const alta = await rest('rpc/crear_programa_con_pensum', {
    method: 'POST',
    body: JSON.stringify({
      p_code: COD_P1,
      p_name: 'Programa de humo',
      p_type: 'CARRERA',
      p_requires_internship: false,
      p_publicar: true,
      p_pensum: [{ materiaId: idM1, periodo: 1 }],
    }),
  });
  comprobar(
    'la función responde 200',
    alta.ok,
    alta.ok ? 'HTTP 200' : `HTTP ${alta.status}: ${JSON.stringify(alta.cuerpo)?.slice(0, 200)}`,
  );
  const idP1 = alta.cuerpo;
  if (idP1) creados.programas.push(idP1);

  const leido = await rest(`programs?id=eq.${idP1}&select=id,is_active`);
  comprobar('el programa nació ACTIVO', leido.cuerpo?.[0]?.is_active === true);
  const pensum = await rest(`program_subjects?program_id=eq.${idP1}&select=subject_id`);
  comprobar('el pensum se insertó en la misma llamada', pensum.cuerpo?.length === 1);

  console.log('\n  3. LA PRUEBA DE ATOMICIDAD: pensum vacío no debe dejar rastro\n');
  const vacio = await rest('rpc/crear_programa_con_pensum', {
    method: 'POST',
    body: JSON.stringify({
      p_code: COD_P2,
      p_name: 'Programa que debe desaparecer',
      p_type: 'CARRERA',
      p_requires_internship: false,
      p_publicar: true,
      p_pensum: [],
    }),
  });
  comprobar('la función rechaza el pensum vacío', !vacio.ok, `HTTP ${vacio.status}`);
  comprobar('el error es la Regla 1 (23514)', JSON.stringify(vacio.cuerpo ?? '').includes('23514'));

  const rastro = await rest(`programs?code=eq.${COD_P2}&select=id`);
  const quedo = Array.isArray(rastro.cuerpo) ? rastro.cuerpo.length : -1;
  comprobar(
    'ATOMICIDAD: no quedó el programa a medias',
    quedo === 0,
    quedo === 0 ? 'cero filas' : `quedaron ${quedo}`,
  );

  console.log('\n  4. Reemplazo del pensum: la diferencia se calcula sola\n');
  const reemplazo = await rest('rpc/reemplazar_pensum', {
    method: 'POST',
    body: JSON.stringify({
      p_program_id: idP1,
      p_pensum: [
        { materiaId: idM1, periodo: 3 },
        { materiaId: idM2, periodo: 1 },
      ],
    }),
  });
  comprobar('la función responde 200', reemplazo.ok, `HTTP ${reemplazo.status}`);

  const despues = await rest(`program_subjects?program_id=eq.${idP1}&select=subject_id,period_order`);
  const filas = despues.cuerpo ?? [];
  comprobar('quedan exactamente 2 materias', filas.length === 2, `${filas.length} fila(s)`);
  comprobar(
    'reordenó la que cambió (1 -> 3)',
    filas.find((f) => f.subject_id === idM1)?.period_order === 3,
  );
  comprobar('insertó la que faltaba', filas.some((f) => f.subject_id === idM2));

  console.log('\n  5. La Regla 2 a través de la función\n');
  const periodo = await rest('system_settings?clave=eq.periodo_activo&select=valor');
  const vigente = typeof periodo.cuerpo?.[0]?.valor === 'string' ? periodo.cuerpo[0].valor : null;
  if (!vigente) {
    comprobar('hay un período vigente declarado', false, 'sin período la Regla 2 no tiene contra qué comparar');
  } else {
    const seccion = await rest('sections', {
      method: 'POST',
      body: JSON.stringify({
        program_id: idP1,
        subject_id: idM2,
        period_code: vigente,
        name: 'H1',
        max_capacity: 20,
        is_active: true,
      }),
    });
    comprobar('se abrió una sección activa del período vigente', seccion.ok, `HTTP ${seccion.status}`);
    const idSeccion = seccion.cuerpo?.[0]?.id ?? null;

    const bloqueado = await rest('rpc/reemplazar_pensum', {
      method: 'POST',
      body: JSON.stringify({ p_program_id: idP1, p_pensum: [{ materiaId: idM2, periodo: 5 }] }),
    });
    comprobar('la Regla 2 bloquea el reordenamiento', !bloqueado.ok, `HTTP ${bloqueado.status}`);
    comprobar(
      'el bloqueo es la Regla 2 y no la Regla 1',
      JSON.stringify(bloqueado.cuerpo ?? '').includes('sección(es) activa(s)'),
      'mensaje reconocible',
    );

    const intacto = await rest(
      `program_subjects?program_id=eq.${idP1}&subject_id=eq.${idM2}&select=period_order`,
    );
    comprobar(
      'el período quedó INTACTO tras el bloqueo (la función se deshizo)',
      intacto.cuerpo?.[0]?.period_order === 1,
      `period_order = ${intacto.cuerpo?.[0]?.period_order}`,
    );

    if (idSeccion) await rest(`sections?id=eq.${idSeccion}`, { method: 'DELETE' });
  }

  console.log('\n  6. Limpieza\n');
} catch (error) {
  fallos += 1;
  console.error(`  [FALLA] excepción: ${error.message}`);
} finally {
  for (const id of creados.programas) {
    const b = await rest(`programs?id=eq.${id}`, { method: 'DELETE' });
    console.log(`  programa ${id.slice(0, 8)}… borrado: ${b.ok ? 'sí' : `NO (HTTP ${b.status})`}`);
  }
  for (const id of creados.materias) {
    const b = await rest(`subjects?id=eq.${id}`, { method: 'DELETE' });
    console.log(`  materia  ${id.slice(0, 8)}… borrada: ${b.ok ? 'sí' : `NO (HTTP ${b.status})`}`);
  }
  // Barrido por si un fallo a mitad dejó algo suelto.
  for (const patron of [`TP1${SUF}`, `TP2${SUF}`, `TM1${SUF}`, `TM2${SUF}`]) {
    const tabla = patron.startsWith('TP') ? 'programs' : 'subjects';
    await rest(`${tabla}?code=eq.${patron}`, { method: 'DELETE' });
  }

  console.log(
    `\n  ${fallos === 0 ? '✓ Humo superado.' : `✗ ${fallos} comprobación(es) fallida(s).`}\n`,
  );
  process.exit(fallos === 0 ? 0 : 1);
}
