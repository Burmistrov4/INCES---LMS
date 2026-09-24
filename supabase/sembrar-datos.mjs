#!/usr/bin/env node
/**
 * sembrar-datos.mjs — datos semilla PERSISTENTES para M4 (Inscripciones) y
 * M6 (Aula Virtual).
 *
 * QUÉ DEJA SEMBRADO
 * -----------------
 * La jerarquía mínima que hace falta para que M4 y M6 tengan algo real que
 * mostrar, sin pasar por la interfaz:
 *
 *   1 CARRERA  ──▶ 3 materias en el pensum
 *   Lapso activo (se LEE de `system_settings`, no se inventa)
 *   2 aulas
 *   1 sección abierta en el lapso activo
 *   1 docente + 3 estudiantes (cuentas de Auth reales)
 *   3 matrículas ENROLLED
 *   Cuadrante: 2 clases del docente en esa sección
 *
 * POR QUÉ EL CUADRANTE NO ES OPCIONAL
 * -----------------------------------
 * M6 no pregunta «¿eres docente?»: pregunta «¿dictas ESTA sección?». La
 * respuesta sale de `m6_dicta_seccion()`, que lee `schedule_slots`. Sin una
 * clase en el cuadrante, el Centro de Mando del Docente responde
 * `SIN_PERMISO_EN_EL_AULA` aunque el docente exista y la sección exista. Es la
 * dependencia M6→M3 que más fácil se olvida, y deja un sembrado que parece
 * roto cuando en realidad está incompleto. Por eso el cuadrante va dentro.
 *
 * DIFERENCIA CON LOS `humo-*.mjs`
 * -------------------------------
 * Los humos **crean y purgan**: existen para verificar y no dejar rastro. Este
 * script **crea y deja**: los datos se quedan para que el sistema tenga con qué
 * demostrarse. Son dos contratos distintos y por eso no se reutiliza el archivo.
 *
 * Lo que SÍ se reutiliza es la disciplina:
 *   · Modo simulación por defecto. Escribir exige `--confirmar`.
 *   · Purga por MARCADOR, no por id recordado. Una corrida que muere a mitad no
 *     deja residuo que nadie sepa borrar.
 *   · Idempotencia por CLAVE NATURAL (código, nombre, correo): correrlo dos
 *     veces deja el mismo estado, no el doble de filas.
 *
 * DATO INVENTADO, DICHO EN VOZ ALTA
 * ---------------------------------
 * Las migraciones se niegan a sembrar aulas y fechas de lapso porque «inventar
 * nombres de aulas sería fabricar dato institucional» (ver 202609180001). Este
 * script sí inventa aulas, materias y el nombre de la carrera, porque es
 * exactamente lo que se le pidió. Para que ese dato no se confunda con el real:
 *
 *   · Los códigos llevan el prefijo `SEM-`.
 *   · Los nombres de aula llevan el sufijo `[SEMILLA]`.
 *   · Los correos son `@semilla.invalid` (`.invalid` es un TLD reservado por la
 *     RFC 2606: no puede existir de verdad, ni recibir correo por accidente).
 *   · No se inventan cédulas: `profiles.cedula` queda en NULL a propósito.
 *
 * Todo lo inventado vive en el bloque `SEMILLA` de más abajo. Cambiar los
 * nombres ahí es cambiar el sembrado entero.
 *
 * USO
 * ---
 *   node supabase/sembrar-datos.mjs                  # simulación (no escribe)
 *   node supabase/sembrar-datos.mjs --confirmar      # siembra
 *   node supabase/sembrar-datos.mjs --limpiar        # simula la limpieza
 *   node supabase/sembrar-datos.mjs --limpiar --confirmar   # borra el sembrado
 *
 * Lee credenciales de `backend/.env` si no vienen del entorno. Necesita la
 * clave SECRETA (`SUPABASE_SERVICE_ROLE_KEY`): crear usuarios es administración.
 * NO necesita el backend levantado: todo va por HTTPS contra Supabase.
 *
 * Códigos de salida: 0 correcto · 1 error · 2 faltan variables.
 */
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');

const CONFIRMAR = process.argv.includes('--confirmar');
const LIMPIAR = process.argv.includes('--limpiar');

if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log(
    '\n  Uso: node supabase/sembrar-datos.mjs [--confirmar] [--limpiar]\n\n' +
      '    (sin banderas)      simula el sembrado, no escribe\n' +
      '    --confirmar         escribe\n' +
      '    --limpiar           simula la limpieza del sembrado\n' +
      '    --limpiar --confirmar   borra todo lo sembrado\n\n' +
      '  Opcional: SEMILLA_PASSWORD=<clave> fija la contraseña de las cuentas\n' +
      '  sembradas en vez de generar una aleatoria por corrida.\n',
  );
  process.exit(0);
}

/** Lee del entorno y, si no, de `backend/.env` (sin añadir `dotenv`). */
function variable(nombre) {
  const delEntorno = (process.env[nombre] ?? '').trim();
  if (delEntorno.length > 0) return delEntorno;
  const archivo = join(RAIZ, 'backend', '.env');
  if (!existsSync(archivo)) return '';
  for (const linea of readFileSync(archivo, 'utf8').split('\n')) {
    const limpia = linea.trim();
    if (limpia.length === 0 || limpia.startsWith('#')) continue;
    const corte = limpia.indexOf('=');
    if (corte < 0) continue;
    if (limpia.slice(0, corte).trim() === nombre) return limpia.slice(corte + 1).trim();
  }
  return '';
}

const URL_BASE = variable('SUPABASE_URL').replace(/\/+$/, '');
const CLAVE = variable('SUPABASE_SERVICE_ROLE_KEY');
const CLAVE_ANON = variable('SUPABASE_ANON_KEY');

if (!URL_BASE || !CLAVE) {
  console.error(
    '\n  Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY.\n' +
      '  Están en backend/.env; este script los lee de ahí si no vienen del entorno.\n' +
      '  Es la clave SECRETA: crear usuarios con la publicable daría 401.\n',
  );
  process.exit(2);
}

// ============================================================================
//  EL SEMBRADO, EN UN SOLO SITIO
// ============================================================================
//  Todo lo que este script inventa vive aquí. Si el centro decide que la
//  carrera se llama de otra forma, se cambia esta línea y nada más.
// ============================================================================
const DOMINIO = '@semilla.invalid';
const PREFIJO = 'SEM-';

const SEMILLA = {
  // CARRERA, no CURSO_LIBRE: sólo una carrera exige pensum (Regla 1 de M2), y
  // es la que ejercita el camino completo de M2. Los 5 programas que ya existen
  // son todos CURSO_LIBRE, así que sin esto no hay ninguna carrera que probar.
  programa: {
    code: `${PREFIJO}AS-01`,
    name: 'Análisis de Sistemas [SEMILLA]',
    type: 'CARRERA',
    requires_internship: false,
  },

  // `academic_hours` y no `credits`: la columna real es ésa y exige > 0.
  // `period_order` es el semestre dentro del pensum.
  materias: [
    { code: `${PREFIJO}AS-PRG`, name: 'Programación I [SEMILLA]', academic_hours: 96, period_order: 1 },
    { code: `${PREFIJO}AS-BD`, name: 'Bases de Datos [SEMILLA]', academic_hours: 80, period_order: 2 },
    { code: `${PREFIJO}AS-ADS`, name: 'Análisis y Diseño de Sistemas [SEMILLA]', academic_hours: 72, period_order: 3 },
  ],

  // `classrooms` no tiene columna `codigo` ni `tipo` (dan PGRST204): el marcador
  // va en el `name`, que es además la clave natural única.
  aulas: [
    { name: 'Aula Teórica 1 [SEMILLA]', capacity: 30, is_workshop: false },
    { name: 'Taller de Soldadura 1 [SEMILLA]', capacity: 20, is_workshop: true },
  ],

  // `max_capacity` ≥ número de estudiantes: con 10 y 3 alumnos la sección queda
  // abierta y con holgura. Si fuera 2, la tercera matrícula sería WAITLISTED en
  // el flujo real y el sembrado diría una cosa y el sistema otra.
  seccion: {
    name: 'SA',
    max_capacity: 10,
    materiaCode: `${PREFIJO}AS-PRG`,
  },

  // Dos clases en el cuadrante, en días y bloques distintos: el trigger
  // anti-colisión rechazaría el mismo (día, bloque) para el mismo docente.
  cuadrante: [
    { day_of_week: 1, block: 1, aulaName: 'Taller de Soldadura 1 [SEMILLA]' },
    { day_of_week: 3, block: 2, aulaName: 'Aula Teórica 1 [SEMILLA]' },
  ],

  docente: { email: `docente${DOMINIO}`, nombres: 'Docente', apellidos: 'Semilla' },

  estudiantes: [
    { email: `estudiante1${DOMINIO}`, nombres: 'Estudiante', apellidos: 'Uno Semilla' },
    { email: `estudiante2${DOMINIO}`, nombres: 'Estudiante', apellidos: 'Dos Semilla' },
    { email: `estudiante3${DOMINIO}`, nombres: 'Estudiante', apellidos: 'Tres Semilla' },
  ],

  // Contenido mínimo de M6. La regla que decide el ESTADO de cada fila es:
  // «¿insertarla así deriva otras filas que no voy a crear?».
  //
  //   · Un ANUNCIO no deriva nada: publicar es sólo cambiar su estado. Por eso
  //     se siembra ya PUBLICADO y el alumno lo ve al entrar al aula.
  //   · Una TAREA publicada SÍ deriva: el RPC de publicación crea una entrega
  //     ASIGNADA por cada matrícula ENROLLED. Insertarla publicada a mano
  //     dejaría una tarea visible SIN entregas, y el libro del docente se vería
  //     vacío en una tarea que sí figura como publicada — un estado que parece
  //     un fallo del sistema y es del sembrado. Por eso la tarea va en BORRADOR:
  //     el docente la publica desde la interfaz y las entregas nacen como deben.
  anuncio: {
    titulo: 'Bienvenidos al lapso [SEMILLA]',
    cuerpo: 'Anuncio creado por el sembrado. El tablón de M6 ya tiene contenido.',
  },
  tarea: {
    titulo: 'Práctica 1: junta a tope [SEMILLA]',
    descripcion: 'Tarea de ejemplo del sembrado. Publícala para generar las entregas.',
    tipo: 'TAREA',
    puntos_maximos: 10,
    tema: 'Unidad 1',
  },
};

const PASSWORD = variable('SEMILLA_PASSWORD') || `Sem!${randomBytes(12).toString('base64url')}`;

// ============================================================================
//  Fontanería HTTP
// ============================================================================

async function crudo(ruta, { metodo = 'GET', cuerpo, extra = {}, auth = true } = {}) {
  const cabeceras = {
    apikey: CLAVE,
    'Content-Type': 'application/json',
    ...extra,
  };
  if (auth) cabeceras.Authorization = `Bearer ${CLAVE}`;

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
  return { estado: r.status, ok: r.ok, datos };
}

/** Igual que `crudo`, pero revienta con un mensaje legible si el HTTP falla. */
async function rest(ruta, opciones = {}) {
  const r = await crudo(`/rest/v1${ruta}`, opciones);
  if (!r.ok) {
    const detalle = typeof r.datos === 'object' ? JSON.stringify(r.datos) : String(r.datos);
    throw new Error(`${opciones.metodo ?? 'GET'} ${ruta} → HTTP ${r.estado}: ${detalle.slice(0, 400)}`);
  }
  return r.datos;
}

/**
 * Alta o actualización por clave natural. Es lo que hace idempotente al script:
 * la segunda corrida actualiza las mismas filas en vez de duplicarlas.
 */
function upsert(tabla, filas, onConflict) {
  return rest(`/${tabla}?on_conflict=${onConflict}`, {
    metodo: 'POST',
    cuerpo: filas,
    extra: { Prefer: 'resolution=merge-duplicates,return=representation' },
  });
}

const uno = (filas) => (Array.isArray(filas) ? filas[0] : filas) ?? null;

/** Crea una cuenta de Auth y devuelve su id. Reutiliza la existente si ya está. */
async function asegurarCuenta({ email, nombres, apellidos }) {
  const existentes = await rest(`/profiles?email=eq.${encodeURIComponent(email)}&select=id`);
  const ya = uno(existentes);
  if (ya?.id) return { id: ya.id, creada: false };

  const creada = await crudo('/auth/v1/admin/users', {
    metodo: 'POST',
    cuerpo: {
      email,
      password: PASSWORD,
      email_confirm: true,
      // `handle_new_user()` lee `nombres`/`apellidos` de aquí y con ellos
      // rellena `profiles`. No se manda la planilla de aspirante completa a
      // propósito: así no se crea fila en `aspirantes` (que exige fecha de
      // nacimiento, sexo y dirección, y cuyo CHECK de tutor legal reventaría).
      user_metadata: { nombres, apellidos },
    },
  });
  if (!creada.ok) {
    throw new Error(`crear ${email} → HTTP ${creada.estado}: ${JSON.stringify(creada.datos).slice(0, 300)}`);
  }
  const id = creada.datos?.id ?? creada.datos?.user?.id ?? null;
  if (!id) throw new Error(`crear ${email}: la respuesta no traía id.`);

  // El perfil lo crea un trigger AFTER INSERT; puede tardar un instante.
  for (let intento = 0; intento < 15; intento += 1) {
    const buscado = await rest(`/profiles?id=eq.${id}&select=id`);
    if (uno(buscado)?.id) return { id, creada: true };
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`crear ${email}: el trigger no dejó fila en profiles.`);
}

// ============================================================================
//  Sembrado
// ============================================================================

const hecho = {};

async function sembrar() {
  // --- 0. El lapso: se LEE, no se inventa -----------------------------------
  //  `sections.period_code` es FK contra `academic_periods.code`, y la Regla 2
  //  compara ese código con `system_settings.periodo_activo` por igualdad
  //  exacta. Usar el valor vivo evita la divergencia que convierte una guarda
  //  en una guarda que no guarda (R-06/R-12).
  const ajuste = uno(
    await rest('/system_settings?clave=eq.periodo_activo&select=valor'),
  );
  const lapso = typeof ajuste?.valor === 'string' ? ajuste.valor : ajuste?.valor?.valor ?? null;
  if (!lapso) throw new Error('system_settings.periodo_activo está vacío: no hay lapso vigente que usar.');

  const registrado = uno(
    await rest(`/academic_periods?code=eq.${encodeURIComponent(lapso)}&select=code,is_active`),
  );
  if (!registrado) {
    throw new Error(
      `El lapso vigente «${lapso}» no está registrado en academic_periods. ` +
        'Sembrar una sección en él fallaría por FK. Regístralo primero.',
    );
  }
  hecho.lapso = lapso;
  console.log(`\n  Lapso vigente (leído de system_settings): ${lapso}`);

  // --- 1. Programa, en BORRADOR --------------------------------------------
  //  Nace con `is_active = false` a propósito. La Regla 1 de M2 es un
  //  constraint trigger diferido: si se insertara activo y sin pensum, la
  //  transacción de PostgREST fallaría al confirmar. El orden es obligatorio.
  const programa = uno(
    await upsert('programs', [{ ...SEMILLA.programa, is_active: false }], 'code'),
  );
  if (!programa?.id) throw new Error('No se pudo crear/leer el programa.');
  hecho.programa = programa;
  console.log(`  Programa: ${programa.code} — ${programa.name} (en borrador: el pensum va después)`);

  // --- 2. Materias ----------------------------------------------------------
  const materias = await upsert(
    'subjects',
    SEMILLA.materias.map(({ code, name, academic_hours }) => ({ code, name, academic_hours })),
    'code',
  );
  if (!Array.isArray(materias) || materias.length !== SEMILLA.materias.length) {
    throw new Error(`Se esperaban ${SEMILLA.materias.length} materias, llegaron ${materias?.length}.`);
  }
  hecho.materias = materias;
  console.log(`  Materias: ${materias.map((m) => m.code).join(', ')}`);

  // --- 3. Pensum ------------------------------------------------------------
  const porCodigo = new Map(materias.map((m) => [m.code, m]));
  let pensum;
  try {
    pensum = await upsert(
      'program_subjects',
      SEMILLA.materias.map((m) => ({
        program_id: programa.id,
        subject_id: porCodigo.get(m.code).id,
        period_order: m.period_order,
      })),
      'program_id,subject_id',
    );
  } catch (e) {
    // Regla 2 de M2: la estructura del pensum de un programa con secciones
    // activas en el lapso vigente no se toca. Una corrida repetida SIN cambios
    // pasa (el trigger sale temprano si `period_order` no cambió), pero editar
    // `SEMILLA.materias[].period_order` con la sección ya sembrada choca contra
    // esta guarda. Es la guarda haciendo su trabajo; el error crudo, en cambio,
    // no explica nada.
    if (e.message.includes('23514') || e.message.includes('No se puede modificar el pensum')) {
      throw new Error(
        'La Regla 2 de M2 bloqueó el cambio de pensum: el programa ya tiene secciones ' +
          'activas en el lapso vigente y su estructura no se puede modificar.\n' +
          '  Si acabas de cambiar `period_order` en el bloque SEMILLA, ésa es la causa. Opciones:\n' +
          '    · deshacer ese cambio (una corrida sin cambios estructurales sí pasa), o\n' +
          '    · limpiar el sembrado antes: --limpiar --confirmar, y volver a sembrar.',
      );
    }
    throw e;
  }
  console.log(`  Pensum: ${Array.isArray(pensum) ? pensum.length : 0} vínculo(s)`);

  // --- 4. AHORA sí, publicar el programa ------------------------------------
  //  Recién aquí hay pensum, así que la Regla 1 pasa. Si esto se adelantara al
  //  paso 3, la carrera activa quedaría con cero materias y el trigger la
  //  rechazaría — que es justo lo que debe hacer.
  //  Un PATCH sin `Prefer: return=representation` responde 204 y sin cuerpo:
  //  la escritura ocurre, pero no hay nada que leer para comprobarla. Sin esa
  //  cabecera, `activado` es null y parece que el programa no se activó cuando
  //  en realidad sí lo hizo.
  const activado = uno(
    await rest(`/programs?id=eq.${programa.id}&select=id,is_active`, {
      metodo: 'PATCH',
      cuerpo: { is_active: true },
      extra: { Prefer: 'return=representation' },
    }),
  );
  if (activado?.is_active !== true) {
    throw new Error(`El programa no quedó activo: ${JSON.stringify(activado)}`);
  }
  hecho.programa.is_active = true;
  console.log('  Programa publicado (is_active = true) tras cargarle el pensum');

  // --- 5. Aulas -------------------------------------------------------------
  const aulas = await upsert('classrooms', SEMILLA.aulas, 'name');
  hecho.aulas = aulas;
  console.log(`  Aulas: ${aulas.map((a) => a.name).join(' | ')}`);

  // --- 6. Personas ----------------------------------------------------------
  const docente = await asegurarCuenta(SEMILLA.docente);
  // El trigger fija `estudiante` siempre (ADR-008: el auto-registro nunca
  // otorga rol). Promover es un UPDATE explícito, fuera de la aplicación.
  await rest(`/profiles?id=eq.${docente.id}`, {
    metodo: 'PATCH',
    cuerpo: { rol: 'docente', active: true },
    extra: { Prefer: 'return=representation' },
  });
  hecho.docente = docente;
  console.log(`  Docente: ${SEMILLA.docente.email} (${docente.creada ? 'creado' : 'ya existía'}) → rol docente`);

  const estudiantes = [];
  for (const e of SEMILLA.estudiantes) {
    estudiantes.push({ ...(await asegurarCuenta(e)), email: e.email });
  }
  hecho.estudiantes = estudiantes;
  console.log(`  Estudiantes: ${estudiantes.map((e) => e.email).join(', ')}`);

  // --- 7. Sección -----------------------------------------------------------
  const materiaSeccion = porCodigo.get(SEMILLA.seccion.materiaCode);
  if (!materiaSeccion) {
    throw new Error(`La sección apunta a «${SEMILLA.seccion.materiaCode}», que no está entre las materias.`);
  }
  const seccion = uno(
    await upsert(
      'sections',
      [{
        program_id: programa.id,
        subject_id: materiaSeccion.id,
        period_code: lapso,
        name: SEMILLA.seccion.name,
        max_capacity: SEMILLA.seccion.max_capacity,
        is_active: true,
      }],
      'period_code,subject_id,name',
    ),
  );
  if (!seccion?.id) throw new Error('No se pudo crear/leer la sección.');
  hecho.seccion = seccion;
  console.log(`  Sección: ${seccion.period_code} / ${seccion.name} (cupo ${seccion.max_capacity})`);

  // --- 8. Cuadrante ---------------------------------------------------------
  //  `schedule_slots` NO tiene restricción única, así que el upsert por clave
  //  natural no existe: hay que buscar antes de insertar. Sin esto, cada
  //  corrida añadiría dos clases más a la misma sección.
  const porNombreAula = new Map(aulas.map((a) => [a.name, a]));
  const yaEnCuadrante = await rest(
    `/schedule_slots?section_id=eq.${seccion.id}&select=id,day_of_week,block`,
  );
  const claveSlot = (d, b) => `${d}-${b}`;
  const ocupados = new Set((yaEnCuadrante ?? []).map((s) => claveSlot(s.day_of_week, s.block)));

  const faltantes = SEMILLA.cuadrante.filter((c) => !ocupados.has(claveSlot(c.day_of_week, c.block)));
  if (faltantes.length > 0) {
    await rest('/schedule_slots', {
      metodo: 'POST',
      cuerpo: faltantes.map((c) => ({
        section_id: seccion.id,
        teacher_id: docente.id,
        classroom_id: porNombreAula.get(c.aulaName).id,
        day_of_week: c.day_of_week,
        block: c.block,
        is_active: true,
      })),
      extra: { Prefer: 'return=representation' },
    });
  }
  console.log(
    `  Cuadrante: ${SEMILLA.cuadrante.length - faltantes.length} ya estaban, ${faltantes.length} añadida(s)`,
  );

  // --- 9. Matrículas --------------------------------------------------------
  //  Se escriben directo con la clave secreta en vez de llamar a
  //  `solicitar_inscripcion()`: aquí no se está probando el flujo de M4 —eso lo
  //  hace `humo-inscripciones.mjs`— sino declarando un estado de partida.
  //
  //  Aquí NO se puede usar `upsert`, y el motivo es concreto. El trigger
  //  `exigir_seccion_unica_por_materia` es BEFORE INSERT y corre ANTES de que
  //  Postgres evalúe el `ON CONFLICT`. En una segunda corrida el INSERT
  //  redundante dispara el trigger, que busca otra sección viva de la misma
  //  materia, la encuentra —la que sembramos en la primera corrida— y aborta
  //  con 23514. La exclusión `e.id <> new.id` del trigger no salva: el id del
  //  INSERT redundante es nuevo, no el de la fila que ya existe.
  //
  //  No es teoría: la primera corrida pasó y la segunda falló con «ya tiene una
  //  sección de la materia …». Por eso se busca antes de insertar.
  const yaMatriculados = await rest(
    `/enrollments?section_id=eq.${seccion.id}&select=student_id,status`,
  );
  const estadoPorEstudiante = new Map((yaMatriculados ?? []).map((m) => [m.student_id, m.status]));

  const sinMatricula = estudiantes.filter((e) => !estadoPorEstudiante.has(e.id));
  const malEstado = estudiantes.filter(
    (e) => estadoPorEstudiante.has(e.id) && estadoPorEstudiante.get(e.id) !== 'ENROLLED',
  );

  if (sinMatricula.length > 0) {
    await rest('/enrollments', {
      metodo: 'POST',
      cuerpo: sinMatricula.map((e) => ({
        student_id: e.id,
        section_id: seccion.id,
        status: 'ENROLLED',
        bid_expires_at: null,
      })),
      extra: { Prefer: 'return=representation' },
    });
  }

  // Un estado distinto de ENROLLED (una baja manual, por ejemplo) sí se corrige
  // con PATCH: ahí la fila que se actualiza es la propia, y el trigger se
  // excluye a sí mismo, así que la transición pasa.
  for (const e of malEstado) {
    await rest(`/enrollments?student_id=eq.${e.id}&section_id=eq.${seccion.id}`, {
      metodo: 'PATCH',
      cuerpo: { status: 'ENROLLED', bid_expires_at: null },
      extra: { Prefer: 'return=representation' },
    });
  }

  const finales = await rest(`/enrollments?section_id=eq.${seccion.id}&select=student_id,status`);
  hecho.matriculas = finales;
  console.log(
    `  Matrículas: ${(finales ?? []).length} → ${(finales ?? []).map((m) => m.status).join(', ')}` +
      ` (${sinMatricula.length} nueva(s), ${malEstado.length} corregida(s))`,
  );

  // --- 10. Contenido de M6 --------------------------------------------------
  //  `m6_anuncios` y `m6_tareas` NO tienen restricción única sobre el título, así
  //  que no hay clave natural que darle a un upsert. Se busca por (sección,
  //  título) antes de insertar: sin eso, cada corrida añadiría un anuncio más.
  const anunciosYa = await rest(
    `/m6_anuncios?seccion_id=eq.${seccion.id}&select=id,titulo,estado`,
  );
  if (!(anunciosYa ?? []).some((a) => a.titulo === SEMILLA.anuncio.titulo)) {
    await rest('/m6_anuncios', {
      metodo: 'POST',
      cuerpo: [{
        seccion_id: seccion.id,
        autor_id: docente.id,
        titulo: SEMILLA.anuncio.titulo,
        cuerpo: SEMILLA.anuncio.cuerpo,
        estado: 'PUBLICADO',
        publicado_en: new Date().toISOString(),
      }],
      extra: { Prefer: 'return=representation' },
    });
    console.log('  Anuncio de M6: creado (PUBLICADO)');
  } else {
    console.log('  Anuncio de M6: ya existía');
  }

  const tareasYa = await rest(`/m6_tareas?seccion_id=eq.${seccion.id}&select=id,titulo,estado`);
  if (!(tareasYa ?? []).some((t) => t.titulo === SEMILLA.tarea.titulo)) {
    await rest('/m6_tareas', {
      metodo: 'POST',
      cuerpo: [{
        seccion_id: seccion.id,
        creado_por: docente.id,
        titulo: SEMILLA.tarea.titulo,
        descripcion: SEMILLA.tarea.descripcion,
        tipo: SEMILLA.tarea.tipo,
        puntos_maximos: SEMILLA.tarea.puntos_maximos,
        tema: SEMILLA.tarea.tema,
        estado: 'BORRADOR',
      }],
      extra: { Prefer: 'return=representation' },
    });
    console.log('  Tarea de M6: creada (BORRADOR — el docente la publica desde el aula)');
  } else {
    console.log('  Tarea de M6: ya existía');
  }
}

// ============================================================================
//  Limpieza — por MARCADOR, nunca por id recordado
// ============================================================================
//  Un sembrado a medias no deja ids que borrar. Por eso la limpieza se ancla en
//  lo que sí sobrevive a una caída: el prefijo de los códigos, el sufijo de los
//  nombres de aula y el dominio de los correos. Una corrida limpia también el
//  residuo de las anteriores.
//
//  El orden importa y no es cosmético:
//    · `sections.program_id` y `sections.subject_id` son `on delete restrict`.
//    · `program_subjects.subject_id` es `on delete restrict`.
//    · `schedule_slots.classroom_id` es `on delete restrict`.
//  Borrar cualquiera de los padres antes que sus hijos falla y deja la mitad.
// ============================================================================
async function limpiar() {
  console.log('\n  --- limpieza por marcador ---');

  // Simular y ejecutar usan la MISMA ruta: sólo cambia el verbo. Así lo que se
  // cuenta en la simulación es exactamente lo que se borraría después.
  const borrar = async (etiqueta, ruta) => {
    if (!CONFIRMAR) {
      const filas = await rest(`${ruta}&select=id`);
      const n = Array.isArray(filas) ? filas.length : 0;
      console.log(`  [simulado] ${etiqueta}: ${n} fila(s)`);
      return;
    }
    await rest(ruta, { metodo: 'DELETE' });
    console.log(`  [borrado ] ${etiqueta}`);
  };

  // 1. Localizar las materias y los programas sembrados.
  const materias = await rest(`/subjects?select=id&code=like.${PREFIJO}*`);
  const idsMaterias = (materias ?? []).map((m) => m.id);
  const programas = await rest(`/programs?select=id&code=like.${PREFIJO}*`);
  const idsProgramas = (programas ?? []).map((p) => p.id);

  const listaMaterias = idsMaterias.length > 0 ? idsMaterias.join(',') : null;
  const listaProgramas = idsProgramas.length > 0 ? idsProgramas.join(',') : null;

  // 2. Secciones del sembrado (por su materia o por su programa).
  //    OJO con la sintaxis de `or=()`: dentro del árbol lógico, columna y
  //    operador se separan con PUNTO (`subject_id.in.(…)`), no con igualdad
  //    (`subject_id=in.(…)`). La forma con `=` da PGRST100 «unexpected "="
  //    expecting … delimiter (.)» — el mismo filtro escrito para un `and`
  //    implícito no sirve aquí.
  let idsSecciones = [];
  if (listaMaterias || listaProgramas) {
    const filtros = [];
    if (listaMaterias) filtros.push(`subject_id.in.(${listaMaterias})`);
    if (listaProgramas) filtros.push(`program_id.in.(${listaProgramas})`);
    const secciones = await rest(`/sections?select=id&or=(${filtros.join(',')})`);
    idsSecciones = (secciones ?? []).map((s) => s.id);
  }
  const listaSecciones = idsSecciones.length > 0 ? idsSecciones.join(',') : null;

  // 3. Hijos de las secciones, de hoja a raíz. Las tablas de M6 pueden no
  //    existir si el módulo nunca se migró: se tolera su ausencia.
  if (listaSecciones) {
    try {
      const tareas = await rest(`/m6_tareas?select=id&seccion_id=in.(${listaSecciones})`);
      const idsTareas = (tareas ?? []).map((t) => t.id);
      if (idsTareas.length > 0) {
        await borrar('entregas de M6', `/m6_entregas?tarea_id=in.(${idsTareas.join(',')})`);
      }
      await borrar('tareas de M6', `/m6_tareas?seccion_id=in.(${listaSecciones})`);
      await borrar('anuncios de M6', `/m6_anuncios?seccion_id=in.(${listaSecciones})`);
    } catch (e) {
      console.log(`  (M6 no disponible, se omite: ${e.message.split(':')[0]})`);
    }
    await borrar('matrículas', `/enrollments?section_id=in.(${listaSecciones})`);
    // El cuadrante antes que el aula: `classroom_id` es restrict.
    await borrar('cuadrante', `/schedule_slots?section_id=in.(${listaSecciones})`);
    await borrar('secciones', `/sections?id=in.(${listaSecciones})`);
  }

  // 4. La Regla 1 de M2 es SIMÉTRICA, y hay que respetarla en los dos sentidos:
  //    al sembrar, activar el programa DESPUÉS de cargarle el pensum; al
  //    limpiar, desactivarlo ANTES de vaciárselo. Si no, el trigger
  //    `programs_exigir_pensum` aborta el borrado del pensum con 23514 —«una
  //    carrera activa no puede quedarse sin materias»— y la limpieza muere a
  //    mitad. Medido: la primera limpieza real se detuvo exactamente aquí.
  if (listaProgramas) {
    if (CONFIRMAR) {
      await rest(`/programs?id=in.(${listaProgramas})`, {
        metodo: 'PATCH',
        cuerpo: { is_active: false },
        extra: { Prefer: 'return=representation' },
      });
      console.log('  [borrador ] programas desactivados para poder vaciar el pensum');
    } else {
      console.log('  [simulado] desactivaría los programas antes de vaciar el pensum');
    }
  }

  // 5. Pensum ANTES que las materias (FK restrict), y luego las materias.
  //    Una sola consulta con `or`: partirlo en dos borrados contaba las mismas
  //    filas dos veces en la simulación y hacía parecer que había el doble.
  const filtrosPensum = [];
  if (listaMaterias) filtrosPensum.push(`subject_id.in.(${listaMaterias})`);
  if (listaProgramas) filtrosPensum.push(`program_id.in.(${listaProgramas})`);
  if (filtrosPensum.length > 0) {
    await borrar('pensum', `/program_subjects?or=(${filtrosPensum.join(',')})`);
  }
  if (listaMaterias) await borrar('materias', `/subjects?id=in.(${listaMaterias})`);
  if (listaProgramas) await borrar('programas', `/programs?id=in.(${listaProgramas})`);

  // 6. Aulas por su marcador en el nombre. Los corchetes van codificados: en
  //    una URL sin codificar el `[` es dudoso, y en SQL LIKE es un literal
  //    (las clases de caracteres son cosa de SIMILAR TO, no de LIKE).
  await borrar('aulas', `/classrooms?name=like.*${encodeURIComponent('[SEMILLA]')}*`);

  // 7. Cuentas. Borrar el usuario de Auth arrastra su `profiles` por FK
  //    (`on delete cascade`), así que no hace falta borrar el perfil aparte.
  const perfiles = await rest(
    `/profiles?select=id,email&email=like.*${encodeURIComponent(DOMINIO)}`,
  );
  for (const p of perfiles ?? []) {
    if (!CONFIRMAR) {
      console.log(`  [simulado] cuenta ${p.email}`);
      continue;
    }
    await crudo(`/auth/v1/admin/users/${p.id}`, { metodo: 'DELETE' });
    console.log(`  [borrado ] cuenta ${p.email}`);
  }
}

// ============================================================================
//  Verificación — contra la base, no contra lo que creemos haber mandado
// ============================================================================
async function verificar() {
  console.log('\n  --- verificación contra la base ---');

  const cuenta = async (ruta) => {
    const filas = await rest(ruta);
    return Array.isArray(filas) ? filas.length : 0;
  };

  const prog = await rest(`/programs?code=eq.${SEMILLA.programa.code}&select=id,is_active,type`);
  const p = uno(prog);
  const materias = await cuenta(`/subjects?select=id&code=like.${PREFIJO}*`);
  const pensum = await cuenta(`/program_subjects?select=id&program_id=eq.${p?.id}`);
  const aulas = await cuenta(
    `/classrooms?select=id&name=like.*${encodeURIComponent('[SEMILLA]')}*`,
  );
  const secciones = await rest(
    `/sections?select=id,name,period_code,max_capacity,is_active&program_id=eq.${p?.id}`,
  );
  const s = uno(secciones);
  const matriculas = s
    ? await rest(`/enrollments?select=status&section_id=eq.${s.id}`)
    : [];
  const slots = s ? await cuenta(`/schedule_slots?select=id&section_id=eq.${s.id}`) : 0;
  const anunciosM6 = s
    ? await cuenta(`/m6_anuncios?select=id&seccion_id=eq.${s.id}&estado=eq.PUBLICADO`)
    : 0;
  const tareasM6 = s
    ? await cuenta(`/m6_tareas?select=id&seccion_id=eq.${s.id}&estado=eq.BORRADOR`)
    : 0;
  const docentes = await cuenta(
    `/profiles?select=id&email=eq.${encodeURIComponent(SEMILLA.docente.email)}&rol=eq.docente`,
  );

  const filas = [
    ['CARRERA activa', p?.is_active === true && p?.type === 'CARRERA', `${p?.type} / activo=${p?.is_active}`],
    ['3 materias', materias === 3, `contadas=${materias}`],
    ['pensum de 3', pensum === 3, `contados=${pensum}`],
    ['2 aulas', aulas === 2, `contadas=${aulas}`],
    ['1 sección abierta', secciones.length === 1 && s?.is_active === true, `secciones=${secciones.length}`],
    ['sección en el lapso vigente', s?.period_code === hecho.lapso, `period_code=${s?.period_code}`],
    ['3 matrículas ENROLLED', matriculas.length === 3 && matriculas.every((m) => m.status === 'ENROLLED'), `estados=${matriculas.map((m) => m.status).join(',')}`],
    ['docente con rol docente', docentes === 1, `encontrados=${docentes}`],
    ['cuadrante con 2 clases', slots === 2, `clases=${slots}`],
    ['1 anuncio PUBLICADO en M6', anunciosM6 === 1, `anuncios=${anunciosM6}`],
    ['1 tarea BORRADOR en M6', tareasM6 === 1, `tareas=${tareasM6}`],
  ];

  let fallos = 0;
  for (const [etiqueta, bien, detalle] of filas) {
    if (!bien) fallos += 1;
    console.log(`  [${bien ? 'OK  ' : 'FALLA'}] ${etiqueta}${bien ? '' : ` — ${detalle}`}`);
  }
  return fallos;
}

// ============================================================================
//  Programa
// ============================================================================
console.log(`\n  Proyecto : ${URL_BASE}`);
console.log(`  Modo     : ${LIMPIAR ? 'LIMPIEZA' : 'SEMBRADO'} · ${CONFIRMAR ? 'REAL' : 'SIMULACIÓN (no escribe)'}`);

try {
  if (LIMPIAR) {
    await limpiar();
    if (!CONFIRMAR) {
      console.log('\n  Simulación: no se borró nada. Repite con --limpiar --confirmar.\n');
      process.exit(0);
    }
    const restos = await rest(`/subjects?select=id&code=like.${PREFIJO}*`);
    const n = Array.isArray(restos) ? restos.length : 0;
    console.log(`\n  Materias del sembrado que quedan: ${n}`);
    console.log(n === 0 ? '  Limpieza completa.\n' : '  Quedan restos: revisa el orden de borrado.\n');
    process.exit(n === 0 ? 0 : 1);
  }

  if (!CONFIRMAR) {
    // La simulación no escribe, pero sí comprueba que las piezas que va a
    // necesitar existen: leer el lapso vigente es la comprobación barata que
    // evita descubrir el problema a mitad de la escritura real.
    const ajuste = uno(await rest('/system_settings?clave=eq.periodo_activo&select=valor'));
    const lapso = typeof ajuste?.valor === 'string' ? ajuste.valor : ajuste?.valor?.valor ?? null;
    const registrado = lapso
      ? uno(await rest(`/academic_periods?code=eq.${encodeURIComponent(lapso)}&select=code`))
      : null;
    console.log(`\n  Lapso vigente: ${lapso ?? '(vacío)'} ${registrado ? '· registrado' : '· NO registrado'}`);
    console.log('\n  Sembraría: 1 carrera, 3 materias, 1 pensum, 2 aulas,');
    console.log('             1 sección, 1 docente, 3 estudiantes, 3 matrículas, 2 clases,');
    console.log('             1 anuncio PUBLICADO y 1 tarea BORRADOR en el aula de M6.');
    console.log('\n  Simulación: no se escribió nada. Repite con --confirmar.\n');
    process.exit(0);
  }

  await sembrar();
  const fallos = await verificar();

  console.log('\n  ----------------  SEMBRADO  ----------------');
  if (hecho.docente?.creada || hecho.estudiantes?.some((e) => e.creada)) {
    console.log(`  Contraseña de las cuentas nuevas: ${PASSWORD}`);
    console.log('  (guárdala ahora: no se vuelve a imprimir y no se puede recuperar)');
  } else {
    console.log('  Todas las cuentas ya existían: contraseñas intactas.');
  }
  console.log(`  Fallos de verificación: ${fallos}`);
  console.log(`  Para deshacerlo: node supabase/sembrar-datos.mjs --limpiar --confirmar\n`);
  process.exit(fallos === 0 ? 0 : 1);
} catch (e) {
  console.error(`\n  ERROR: ${e.message}\n`);
  if (LIMPIAR) {
    console.error('  La limpieza se detuvo antes de terminar. Nada quedó a medias:');
    console.error('  cada borrado es independiente y el orden va de hoja a raíz, así que');
    console.error('  volver a ejecutarla retoma donde se quedó.');
    console.error('      node supabase/sembrar-datos.mjs --limpiar --confirmar\n');
  } else {
    console.error('  El sembrado es idempotente: corregir y volver a ejecutar no duplica nada.');
    console.error('  Para deshacer lo que haya quedado a medias:');
    console.error('      node supabase/sembrar-datos.mjs --limpiar --confirmar\n');
  }
  process.exit(1);
}
