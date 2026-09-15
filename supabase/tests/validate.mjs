// ============================================================================
//  Validador de migraciones — INCES LMS
//  Archivo: supabase/tests/validate.mjs
//
//  Uso:
//    cd supabase/tests
//    npm install
//    npm test
//
//  Qué hace: levanta un PostgreSQL real (PGlite = Postgres compilado a WASM),
//  aplica el shim de Supabase y TODAS las migraciones en orden alfabético, y
//  después ejecuta aserciones sobre el resultado.
//
//  No sustituye a probar contra el Supabase real, pero atrapa lo caro: errores
//  de sintaxis, triggers mal escritos, políticas RLS que no filtran y semillas
//  que no son idempotentes.
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const SUPABASE = path.resolve(AQUI, '..');

const ADMIN_ID = '11111111-1111-1111-1111-111111111111';
const ALUMNO_ID = '22222222-2222-2222-2222-222222222222';

// --- mini framework de aserciones -------------------------------------------
let pasadas = 0;
const fallos = [];

function check(nombre, condicion, detalle = '') {
  if (condicion) {
    pasadas++;
    console.log(`  \x1b[32m✓\x1b[0m ${nombre}`);
  } else {
    fallos.push(nombre);
    console.log(`  \x1b[31m✗ ${nombre}\x1b[0m${detalle ? `  → ${detalle}` : ''}`);
  }
}

function seccion(titulo) {
  console.log(`\n\x1b[1m${titulo}\x1b[0m`);
}

async function esperaError(nombre, fn) {
  try {
    await fn();
    check(nombre, false, 'no lanzó excepción');
  } catch (e) {
    check(nombre, true);
    return e;
  }
}

// --- entorno ---------------------------------------------------------------
// `pgcrypto` no viene en el núcleo de PGlite: se carga como contrib, igual que
// en Supabase, donde las migraciones hacen `create extension pgcrypto`.
const db = new PGlite({ extensions: { pgcrypto } });

/** Ejecuta un SELECT como un rol concreto, con el JWT simulado. */
async function como(rol, sub, fn) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [
    JSON.stringify({ sub, role: rol }),
  ]);
  await db.exec(`set role ${rol}`);
  try {
    return await fn();
  } finally {
    await db.exec('reset role');
    await db.query(`select set_config('request.jwt.claims', '', false)`);
  }
}

async function aplicar(archivo) {
  const sql = fs.readFileSync(archivo, 'utf8');
  await db.exec(sql);
}

function migraciones() {
  const dir = path.join(SUPABASE, 'migrations');
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => path.join(dir, f));
}

async function main() {
  console.log('\x1b[1mINCES LMS — validación de migraciones\x1b[0m');

  // ---------------------------------------------------------------- 1. aplicar
  seccion('1. Aplicación de migraciones');
  await aplicar(path.join(AQUI, 'supabase_shim.sql'));
  console.log('  · shim de Supabase aplicado');

  for (const m of migraciones()) {
    await aplicar(m);
    console.log(`  · ${path.basename(m)} aplicado`);
  }
  check('las migraciones aplican sin errores', true);

  // ------------------------------------------------- 2. semilla de módulos
  seccion('2. Semilla de system_modules');
  const modulos = (
    await db.query('select clave, habilitado, orden, categoria, roles_permitidos from public.system_modules order by orden')
  ).rows;

  const esperados = [
    'm0_cpanel', 'm1_onboarding', 'm2_curriculo', 'm3_cuadrante',
    'm4_inscripciones', 'm5_archivos', 'm6_asistencia', 'm7_calificaciones',
    'm8_pasantias',
  ];
  check('hay 9 módulos sembrados', modulos.length === 9, `hay ${modulos.length}`);
  check(
    'los códigos coinciden con el ROADMAP',
    JSON.stringify(modulos.map((m) => m.clave)) === JSON.stringify(esperados),
  );
  check('m9 (certificados/QR) NO se siembra', !modulos.some((m) => m.clave.startsWith('m9')));
  check(
    'sólo m0_cpanel y m1_onboarding arrancan encendidos',
    modulos.filter((m) => m.habilitado).map((m) => m.clave).join(',') === 'm0_cpanel,m1_onboarding',
  );
  check(
    'm0_cpanel está restringido al rol admin',
    JSON.stringify(modulos.find((m) => m.clave === 'm0_cpanel').roles_permitidos) === '["admin"]',
  );
  check(
    'un módulo sin roles declarados es visible para todos',
    modulos.find((m) => m.clave === 'm1_onboarding').roles_permitidos.length === 0,
  );

  // ------------------------------------------------- 3. semilla de settings
  seccion('3. Semilla de system_settings');
  const settings = (await db.query('select clave, valor, tipo, es_publico from public.system_settings')).rows;
  check('hay 8 parámetros sembrados', settings.length === 8, `hay ${settings.length}`);
  check(
    'modo_mantenimiento es público (la UI necesita leerlo)',
    settings.find((s) => s.clave === 'modo_mantenimiento')?.es_publico === true,
  );
  check(
    'max_faltas_consecutivas es privado',
    settings.find((s) => s.clave === 'max_faltas_consecutivas')?.es_publico === false,
  );
  check(
    'el tipo declarado es coherente con el valor',
    settings.find((s) => s.clave === 'inscripciones_abiertas')?.tipo === 'boolean',
  );

  // ------------------------------------------------------ 4. cortacircuitos
  seccion('4. Cortacircuitos (no perder el acceso al panel)');
  await esperaError('deshabilitar m0_cpanel lanza excepción', () =>
    db.exec("update public.system_modules set habilitado = false where clave = 'm0_cpanel'"),
  );
  await esperaError('eliminar m0_cpanel lanza excepción', () =>
    db.exec("delete from public.system_modules where clave = 'm0_cpanel'"),
  );
  await esperaError('insertar m0_cpanel deshabilitado lanza excepción', () =>
    db.exec("insert into public.system_modules (clave, nombre, habilitado) values ('m0_cpanel', 'x', false)"),
  );

  // Un módulo cualquiera SÍ debe poder apagarse: el guardián no es un bloqueo general.
  await db.exec("update public.system_modules set habilitado = true where clave = 'm2_curriculo'");
  const m2 = (await db.query("select habilitado from public.system_modules where clave = 'm2_curriculo'")).rows[0];
  check('un módulo normal sí se puede encender', m2.habilitado === true);

  // ---------------------------------------------------------- 5. auditoría
  seccion('5. Auditoría de configuración');
  const auditoriaSeed = (
    await db.query("select count(*)::int as n from public.config_audit_log where usuario_email = 'sistema'")
  ).rows[0].n;
  check('la propia semilla queda auditada', auditoriaSeed >= 17, `hay ${auditoriaSeed} filas de sistema`);

  const ultimo = (
    await db.query(
      "select tabla, clave, valor_anterior, valor_nuevo, usuario_email from public.config_audit_log order by created_at desc limit 1",
    )
  ).rows[0];
  check('la última entrada apunta al módulo tocado', ultimo.clave === 'm2_curriculo' && ultimo.tabla === 'system_modules');
  check(
    'guarda el valor anterior y el nuevo',
    ultimo.valor_anterior?.habilitado === false && ultimo.valor_nuevo?.habilitado === true,
    JSON.stringify({ antes: ultimo.valor_anterior?.habilitado, despues: ultimo.valor_nuevo?.habilitado }),
  );

  await db.exec("update public.system_settings set valor = '5'::jsonb where clave = 'max_faltas_consecutivas'");
  const auditSetting = (
    await db.query(
      "select valor_anterior, valor_nuevo from public.config_audit_log where tabla = 'system_settings' and clave = 'max_faltas_consecutivas' order by created_at desc limit 1",
    )
  ).rows[0];
  check(
    'un cambio de parámetro también se audita',
    auditSetting.valor_anterior?.valor === 3 && auditSetting.valor_nuevo?.valor === 5,
  );

  // ------------------------------------------------------- 6. idempotencia
  seccion('6. Idempotencia de la semilla');
  await db.exec("update public.system_modules set habilitado = false where clave = 'm6_asistencia'");
  const semillaSql = fs
    .readFileSync(path.join(SUPABASE, 'migrations', '202609120002_phase3_admin_core.sql'), 'utf8')
    .split('-- 10. Semilla')[1]
    .split('-- 11.')[0];
  await db.exec(semillaSql);
  const m6 = (await db.query("select habilitado from public.system_modules where clave = 'm6_asistencia'")).rows[0];
  const totalModulos = (await db.query('select count(*)::int as n from public.system_modules')).rows[0].n;
  check('reaplicar la semilla NO revive un módulo apagado a mano', m6.habilitado === false);
  check('reaplicar la semilla NO duplica filas', totalModulos === 9, `hay ${totalModulos}`);

  // ------------------------------------------------------------ 7. usuarios
  seccion('7. Onboarding atómico (Fase 1) y datos de prueba');
  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${ADMIN_ID}',  'admin@inces.test',  '{}'::jsonb),
      ('${ALUMNO_ID}', 'alumno@inces.test', '{
        "cedula":"87654321","nombres":"Ana","apellidos":"Pérez",
        "fecha_nac":"2000-05-10","sexo":"F","telefono":"04141234567",
        "direccion":"Calle 1","nivel_educativo":"Bachiller",
        "curso_seleccionado":"Herrería"
      }'::jsonb);
    update public.profiles set rol = 'admin' where email = 'admin@inces.test';
  `);
  const perfiles = (await db.query('select count(*)::int as n from public.profiles')).rows[0].n;
  const fichas = (await db.query('select count(*)::int as n from public.aspirantes')).rows[0].n;
  check('el trigger crea un perfil por cada usuario', perfiles === 2, `hay ${perfiles}`);
  check('el trigger crea la ficha sólo con la planilla completa', fichas === 1, `hay ${fichas}`);
  const rolAdmin = (await db.query("select rol from public.profiles where email = 'admin@inces.test'")).rows[0].rol;
  check('el rol del admin se eleva por SQL (no por auto-registro)', rolAdmin === 'admin');

  // --------------------------------------------------- 8. RLS: no-admin
  seccion('8. RLS — usuario autenticado sin privilegios');
  const alumnoVe = await como('authenticated', ALUMNO_ID, () =>
    db.query('select count(*)::int as n from public.system_modules'),
  );
  check('puede leer el catálogo de módulos (lo necesita el menú)', alumnoVe.rows[0].n === 9);

  await como('authenticated', ALUMNO_ID, () =>
    db.exec("update public.system_modules set orden = 999 where clave = 'm1_onboarding'"),
  );
  const ordenTrasIntento = (
    await db.query("select orden from public.system_modules where clave = 'm1_onboarding'")
  ).rows[0].orden;
  check('NO puede modificar un módulo (RLS filtra la fila)', ordenTrasIntento !== 999, `orden = ${ordenTrasIntento}`);

  const settingsAlumno = await como('authenticated', ALUMNO_ID, () =>
    db.query('select clave from public.system_settings'),
  );
  check(
    'sólo ve los parámetros marcados como públicos',
    settingsAlumno.rows.length === 3 && !settingsAlumno.rows.some((s) => s.clave === 'max_faltas_consecutivas'),
    `ve ${settingsAlumno.rows.length}`,
  );

  const auditAlumno = await como('authenticated', ALUMNO_ID, () =>
    db.query('select count(*)::int as n from public.config_audit_log'),
  );
  check('NO puede leer la auditoría', auditAlumno.rows[0].n === 0);

  await esperaError('NO puede escribir en la auditoría (ni con grant, ni sin política)', () =>
    como('authenticated', ALUMNO_ID, () =>
      db.exec("insert into public.config_audit_log (tabla, clave) values ('x', 'y')"),
    ),
  );

  const moduloM0Alumno = await como('authenticated', ALUMNO_ID, () =>
    db.query("select count(*)::int as n from public.system_modules where clave = 'm0_cpanel'"),
  );
  check('el módulo del cPanel existe en el catálogo (el filtro por rol es de UI)', moduloM0Alumno.rows[0].n === 1);

  // ------------------------------------------------------ 9. RLS: admin
  seccion('9. RLS — administrador');
  await como('authenticated', ADMIN_ID, () =>
    db.exec("update public.system_modules set orden = 25 where clave = 'm2_curriculo'"),
  );
  const ordenAdmin = (
    await db.query("select orden from public.system_modules where clave = 'm2_curriculo'")
  ).rows[0].orden;
  check('SÍ puede modificar un módulo', ordenAdmin === 25, `orden = ${ordenAdmin}`);

  const auditAdmin = await como('authenticated', ADMIN_ID, () =>
    db.query('select count(*)::int as n from public.config_audit_log'),
  );
  check('SÍ puede leer la auditoría', auditAdmin.rows[0].n > 0);

  const settingsAdmin = await como('authenticated', ADMIN_ID, () =>
    db.query('select count(*)::int as n from public.system_settings'),
  );
  check('SÍ puede leer todos los parámetros', settingsAdmin.rows[0].n === 8, `ve ${settingsAdmin.rows[0].n}`);

  const adminPuedeAjustar = await como('authenticated', ADMIN_ID, () =>
    db.query("select public.is_admin() as es"),
  );
  check('is_admin() es ejecutable por authenticated', adminPuedeAjustar.rows[0].es === true);

  // ------------------------------------------------ 10. RLS: anónimo
  seccion('10. RLS — visitante anónimo');
  const settingsAnon = await como('anon', null, () => db.query('select clave from public.system_settings'));
  check(
    'sólo ve parámetros públicos',
    settingsAnon.rows.length === 3,
    `ve ${settingsAnon.rows.length}`,
  );

  // El formulario público de inscripción no necesita el catálogo de módulos, así
  // que a `anon` no se le concede ni el GRANT de SELECT. El resultado correcto
  // es un rechazo de permisos (42501 → AppException.permisos en el cliente), no
  // una lista vacía: una lista vacía ocultaría un error de configuración.
  const errAnon = await esperaError('NO tiene ningún acceso al catálogo de módulos', () =>
    como('anon', null, () => db.query('select count(*)::int as n from public.system_modules')),
  );
  check(
    'el rechazo es un error de permisos explícito (42501)',
    errAnon?.code === '42501',
    `code = ${errAnon?.code}`,
  );

  // -------------------------------------------------------- 11. constraints
  seccion('11. Restricciones de integridad');
  await esperaError('un rol inventado en roles_permitidos es rechazado', () =>
    db.exec("update public.system_modules set roles_permitidos = array['superadmin'] where clave = 'm1_onboarding'"),
  );
  await esperaError('una clave con formato inválido es rechazada', () =>
    db.exec("insert into public.system_modules (clave, nombre) values ('M1-Malo', 'x')"),
  );
  await esperaError('un tipo de parámetro desconocido es rechazado', () =>
    db.exec("insert into public.system_settings (clave, tipo) values ('prueba', 'inventado')"),
  );

  // ------------------------------------ 12. último administrador activo (D8)
  seccion('12. Protección del último administrador activo (D8)');
  const ADMIN2_ID = '33333333-3333-3333-3333-333333333333';

  // Con un solo administrador, las TRES vías que le quitan esa condición deben
  // fallar. Probar sólo el cambio de rol dejaría abiertas la desactivación y el
  // borrado, que son el mismo agujero por otras puertas.
  const errDegradar = await esperaError(
    'no se puede degradar al último administrador',
    () => db.exec(`update public.profiles set rol = 'estudiante' where id = '${ADMIN_ID}'`),
  );
  check(
    'el rechazo explica el motivo y cómo resolverlo',
    /sin ningún administrador activo/.test(errDegradar?.message ?? '') &&
      /Promueve a otro usuario/.test(errDegradar?.hint ?? ''),
    errDegradar?.message,
  );

  await esperaError('no se puede desactivar al último administrador', () =>
    db.exec(`update public.profiles set active = false where id = '${ADMIN_ID}'`),
  );

  await esperaError('no se puede borrar al último administrador', () =>
    db.exec(`delete from public.profiles where id = '${ADMIN_ID}'`),
  );

  // La guardia no debe estorbar los cambios legítimos sobre esa misma fila.
  await db.exec(
    `update public.profiles set nombres = 'Admin Renombrado' where id = '${ADMIN_ID}'`,
  );
  const renombrado = (
    await db.query(`select nombres from public.profiles where id = '${ADMIN_ID}'`)
  ).rows[0].nombres;
  check('editar otros campos del último administrador sigue permitido', renombrado === 'Admin Renombrado');

  // Con un segundo administrador activo, degradar al primero es legítimo.
  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${ADMIN2_ID}', 'admin2@inces.test', '{}'::jsonb);
    update public.profiles set rol = 'admin' where id = '${ADMIN2_ID}';
  `);
  await db.exec(`update public.profiles set rol = 'docente' where id = '${ADMIN_ID}'`);
  const degradado = (
    await db.query(`select rol from public.profiles where id = '${ADMIN_ID}'`)
  ).rows[0].rol;
  check('con otro administrador activo, degradar sí se permite', degradado === 'docente');

  // Al quedar uno solo, la protección vuelve a activarse: no es una regla que se
  // agote por haber pasado una vez.
  await esperaError('al quedar uno solo, la protección vuelve a activarse', () =>
    db.exec(`update public.profiles set rol = 'docente' where id = '${ADMIN2_ID}'`),
  );

  // Un administrador DESACTIVADO no sirve de respaldo: no puede entrar al
  // sistema, así que el sistema seguiría sin nadie capaz de gestionarlo.
  await db.exec(
    `update public.profiles set rol = 'admin', active = false where id = '${ADMIN_ID}'`,
  );
  const adminsActivos = (
    await db.query("select count(*)::int as n from public.profiles where rol = 'admin' and active")
  ).rows[0].n;
  check('el administrador desactivado no cuenta como activo', adminsActivos === 1, `hay ${adminsActivos}`);
  await esperaError('un administrador inactivo no cuenta como respaldo', () =>
    db.exec(`update public.profiles set rol = 'docente' where id = '${ADMIN2_ID}'`),
  );

  // ------------------------------------------- 13. Módulo 2 — Currículo
  seccion('13. Módulo 2 — Currículo y Pensum');

  const PROG_ID = '33333333-3333-3333-3333-333333333333';
  const MAT_ID = '44444444-4444-4444-4444-444444444444';

  const tablasM2 = (
    await db.query(
      "select tablename, rowsecurity from pg_tables where schemaname = 'public' " +
        "and tablename in ('programs', 'subjects', 'program_subjects')",
    )
  ).rows;
  check('existen las 3 tablas de M2', tablasM2.length === 3, `hay ${tablasM2.length}`);
  check('RLS activo en las 3 tablas de M2', tablasM2.every((t) => t.rowsecurity));

  await db.exec(
    `insert into public.subjects (id, code, name, academic_hours)
     values ('${MAT_ID}', 'ALG-I', 'Algorítmica', 96)`,
  );

  // --- integridad de los datos maestros -----------------------------------
  await esperaError('programs.code rechaza minúsculas', () =>
    db.exec("insert into public.programs (code, name, type) values ('cur-sist-01', 'X', 'CARRERA')"),
  );
  await esperaError('subjects rechaza una carga horaria de cero', () =>
    db.exec("insert into public.subjects (code, name, academic_hours) values ('CERO-1', 'Vacía', 0)"),
  );
  await esperaError('programs.type rechaza un tipo inventado', () =>
    db.exec("insert into public.programs (code, name, type) values ('TIPO-1', 'X', 'DIPLOMADO')"),
  );

  // Ninguna CARRERA sembrada todavía: `programs` sólo trae los cursos libres que
  // absorbió la migración de D12. Se comprueba sobre el dato, no sobre una
  // consulta vacía: `select ... limit 0` no prueba absolutamente nada.
  const carrerasAntes = (
    await db.query("select count(*)::int as n from public.programs where type = 'CARRERA'")
  ).rows[0].n;
  check(
    'todavía no hay ninguna CARRERA sembrada (sólo cursos libres)',
    carrerasAntes === 0,
    `hay ${carrerasAntes}`,
  );

  // --- Regla 1: no existen carreras vacías ---------------------------------
  // El trigger es DIFERIDO: no falla al insertar, falla al CONFIRMAR. Esa es la
  // propiedad que hace posible el asistente de una sola petición.
  await db.exec('begin');
  await db.exec(
    `insert into public.programs (id, code, name, type, is_active)
     values ('${PROG_ID}', 'VACIO-01', 'Programa sin materias', 'CARRERA', true)`,
  );
  await esperaError('un programa activo sin materias no se puede confirmar', () =>
    db.exec('commit'),
  );

  // El mismo contenido, pero con el pensum en la MISMA transacción: confirma.
  let asistenteOk = true;
  try {
    await db.exec('begin');
    await db.exec(
      `insert into public.programs (id, code, name, type, is_active)
       values ('${PROG_ID}', 'SIST-01', 'Análisis de Sistemas', 'CARRERA', true)`,
    );
    await db.exec(
      `insert into public.program_subjects (program_id, subject_id, period_order)
       values ('${PROG_ID}', '${MAT_ID}', 1)`,
    );
    await db.exec('commit');
  } catch (e) {
    asistenteOk = false;
    await db.exec('rollback');
  }
  check('el asistente confirma programa + pensum en una sola transacción', asistenteOk);

  await esperaError('una materia no puede estar dos veces en el mismo pensum', () =>
    db.exec(
      `insert into public.program_subjects (program_id, subject_id, period_order)
       values ('${PROG_ID}', '${MAT_ID}', 2)`,
    ),
  );

  // El otro camino al mismo estado inválido: vaciarle el pensum a un programa
  // que ya está activo.
  await db.exec('begin');
  await db.exec(`delete from public.program_subjects where program_id = '${PROG_ID}'`);
  await esperaError('quitarle la última materia a un programa activo no se puede confirmar', () =>
    db.exec('commit'),
  );

  // El escape que documenta la migración: archivar primero sí se permite.
  let archivadoOk = true;
  try {
    await db.exec('begin');
    await db.exec(`update public.programs set is_active = false where id = '${PROG_ID}'`);
    await db.exec(`delete from public.program_subjects where program_id = '${PROG_ID}'`);
    await db.exec('commit');
  } catch {
    archivadoOk = false;
    await db.exec('rollback');
  }
  check('archivar el programa antes de vaciar el pensum sí se permite', archivadoOk);

  // Se deja el programa publicado otra vez para las pruebas de RLS.
  await db.exec('begin');
  await db.exec(`update public.programs set is_active = true where id = '${PROG_ID}'`);
  await db.exec(
    `insert into public.program_subjects (program_id, subject_id, period_order)
     values ('${PROG_ID}', '${MAT_ID}', 1)`,
  );
  await db.exec('commit');

  // --- RLS ----------------------------------------------------------------
  // Se afirma sobre la PRESENCIA o AUSENCIA de una fila concreta, no sobre un
  // recuento: `programs` ya trae los 5 cursos libres que sembró la migración de
  // D12, y un `length === 1` se rompe en cuanto el catálogo crezca.
  const anonProgramas = await como('anon', null, () =>
    db.query('select code from public.programs order by code'),
  );
  check(
    'anon ve la oferta activa (el formulario de inscripción la necesita)',
    anonProgramas.rows.some((p) => p.code === 'SIST-01'),
    `ve ${anonProgramas.rows.length} programas`,
  );
  check(
    'un programa en borrador NO asoma a anon',
    !anonProgramas.rows.some((p) => p.code === 'BORR-01'),
  );

  await esperaError('anon NO tiene acceso al banco de materias', () =>
    como('anon', null, () => db.query('select count(*)::int as n from public.subjects')),
  );

  await esperaError('un estudiante NO puede crear un programa', () =>
    como('authenticated', ALUMNO_ID, () =>
      db.exec("insert into public.programs (code, name, type) values ('HACK-01', 'X', 'CARRERA')"),
    ),
  );

  const alumnoLee = await como('authenticated', ALUMNO_ID, () =>
    db.query('select code from public.programs'),
  );
  check(
    'un estudiante sí puede leer la oferta completa',
    alumnoLee.rows.some((p) => p.code === 'SIST-01'),
  );

  // Un borrador no debe asomar al formulario público.
  await db.exec(
    `insert into public.programs (code, name, type, is_active)
     values ('BORR-01', 'Programa en borrador', 'CURSO_LIBRE', false)`,
  );
  const anonTrasBorrador = await como('anon', null, () =>
    db.query('select code from public.programs'),
  );
  check(
    'sigue sin asomar tras crear más programas',
    !anonTrasBorrador.rows.some((p) => p.code === 'BORR-01'),
  );

  const adminProgramas = await como('authenticated', ADMIN_ID, () =>
    db.query('select code from public.programs'),
  );
  check('el admin sí ve el borrador', adminProgramas.rows.some((p) => p.code === 'BORR-01'));

  // ------------------------------ 14. D12 y D13
  seccion('14. D12 — programs absorbe cursos');

  // `information_schema.tables` INCLUYE las vistas (con table_type='VIEW'), así
  // que no basta con que la fila exista: hay que mirar el tipo.
  const tipoCursos = (
    await db.query(
      "select table_type from information_schema.tables where table_schema='public' and table_name='cursos'",
    )
  ).rows[0]?.table_type;
  check('cursos YA NO es una tabla base', tipoCursos === 'VIEW', String(tipoCursos));
  check(
    'cursos es una vista de compatibilidad',
    (
      await db.query(
        "select count(*)::int as n from information_schema.views where table_schema='public' and table_name='cursos'",
      )
    ).rows[0].n === 1,
  );

  const cursosVista = await db.query('select nombre from public.cursos order by nombre');
  check(
    'la vista proyecta los 5 cursos libres de Fase 0',
    cursosVista.rows.length >= 5,
    `ve ${cursosVista.rows.length}`,
  );

  const programasCurso = await db.query(
    "select code, name, is_active from public.programs where code like 'CUR-%' order by code",
  );
  check(
    'los 5 cursos viven ahora en programs con código institucional',
    programasCurso.rows.length === 5,
    `hay ${programasCurso.rows.length}`,
  );
  check('y se conservaron activos', programasCurso.rows.every((p) => p.is_active));

  // El fix de la Regla 1: un CURSO_LIBRE activo sin pensum es válido. Si no,
  // esta misma migración no habría podido aplicarse.
  let cursoLibreVacioOk = true;
  try {
    await db.exec('begin');
    await db.exec(
      "insert into public.programs (code, name, type, is_active) values ('CUR-TEST-1', 'Curso libre de prueba', 'CURSO_LIBRE', true)",
    );
    await db.exec('commit');
  } catch {
    cursoLibreVacioOk = false;
    await db.exec('rollback');
  }
  check('un CURSO_LIBRE activo SIN pensum sí se puede confirmar', cursoLibreVacioOk);

  // Y una CARRERA vacía sigue bloqueada: la regla se acotó, no se desactivó.
  await db.exec('begin');
  await db.exec(
    "insert into public.programs (code, name, type, is_active) values ('CAR-VACIA1', 'Carrera vacía', 'CARRERA', true)",
  );
  await esperaError('una CARRERA activa sin pensum SIGUE sin poder confirmarse', () =>
    db.exec('commit'),
  );

  // --- RLS de la vista -----------------------------------------------------
  const anonCursos = await como('anon', null, () => db.query('select nombre from public.cursos'));
  check(
    'anon ve los cursos libres activos a través de la vista',
    anonCursos.rows.length === 6,
    `ve ${anonCursos.rows.length}`,
  );
  check(
    'security_invoker funciona: un curso libre archivado NO asoma a anon',
    !anonCursos.rows.some((c) => c.nombre === 'Programa en borrador'),
  );
  const authCursos = await como('authenticated', ALUMNO_ID, () =>
    db.query('select nombre from public.cursos'),
  );
  check(
    'un autenticado sí ve el curso libre en borrador (la vista no lo filtra)',
    authCursos.rows.some((c) => c.nombre === 'Programa en borrador'),
  );

  seccion('15. D13 — sections rediseñada + Regla 2 de M2');

  const cols = (
    await db.query(
      "select column_name from information_schema.columns where table_schema='public' and table_name='sections' order by column_name",
    )
  ).rows.map((c) => c.column_name);
  check('sections tiene program_id (lo que el documento no tenía)', cols.includes('program_id'));
  check('sections tiene subject_id', cols.includes('subject_id'));
  check('sections tiene period_code', cols.includes('period_code'));
  check('sections tiene max_capacity', cols.includes('max_capacity'));
  check('sections ya no tiene cupo_maximo', !cols.includes('cupo_maximo'));
  check('sections ya no tiene nombre', !cols.includes('nombre'));

  check(
    'RLS sigue activo en sections',
    (
      await db.query(
        "select rowsecurity from pg_tables where schemaname='public' and tablename='sections'",
      )
    ).rows[0]?.rowsecurity === true,
  );
  check(
    'el FK enrollments.section_id -> sections se recreó',
    (
      await db.query(
        "select count(*)::int as n from information_schema.table_constraints where constraint_schema='public' and table_name='enrollments' and constraint_name='enrollments_section_id_fkey'",
      )
    ).rows[0].n === 1,
  );

  const PERIODO = (
    await db.query(
      "select valor #>> '{}' as p from public.system_settings where clave = 'periodo_activo'",
    )
  ).rows[0]?.p;
  check(
    'hay un período vigente declarado (sin él la Regla 2 no tiene contra qué comparar)',
    typeof PERIODO === 'string' && PERIODO.length > 0,
    String(PERIODO),
  );

  const SEC_ID = '55555555-5555-5555-5555-555555555555';

  // Sin secciones todavía, el pensum se puede reordenar.
  let reordenSinUso = true;
  try {
    await db.exec(`update public.program_subjects set period_order = 2 where program_id = '${PROG_ID}'`);
  } catch {
    reordenSinUso = false;
  }
  check('sin secciones activas, reordenar el pensum SÍ se permite', reordenSinUso);

  await db.exec(
    `insert into public.sections (id, program_id, subject_id, period_code, name, max_capacity)
     values ('${SEC_ID}', '${PROG_ID}', '${MAT_ID}', '${PERIODO}', 'SA', 25)`,
  );
  check(
    'la sección de prueba nace activa',
    (await db.query(`select is_active from public.sections where id = '${SEC_ID}'`)).rows[0]
      .is_active === true,
  );

  await esperaError('con una sección activa, reordenar el pensum se bloquea', () =>
    db.exec(`update public.program_subjects set period_order = 3 where program_id = '${PROG_ID}'`),
  );
  await esperaError('con una sección activa, quitar la materia del pensum se bloquea', () =>
    db.exec(`delete from public.program_subjects where program_id = '${PROG_ID}'`),
  );

  // La excepción que evita el falso bloqueo: guardar sin cambiar nada. Un
  // formulario que falla al pulsar "guardar" sin haber tocado nada es la clase
  // de comportamiento que hace que la gente desconfíe del sistema.
  let noOpOk = true;
  try {
    await db.exec(
      `update public.program_subjects set period_order = period_order where program_id = '${PROG_ID}'`,
    );
  } catch {
    noOpOk = false;
  }
  check('un UPDATE que no cambia la estructura NO se bloquea', noOpOk);

  // Una sección de OTRO período no bloquea. Para probarlo hay que archivar antes
  // la del período vigente: si no, la prueba pasaría (o fallaría) por el motivo
  // equivocado y no diría nada sobre el filtro de período.
  await db.exec(
    `insert into public.sections (id, program_id, subject_id, period_code, name, max_capacity)
     values ('66666666-6666-6666-6666-666666666666', '${PROG_ID}', '${MAT_ID}', '2099-9', 'SB', 25)`,
  );
  await esperaError('mientras la del período vigente siga activa, sigue bloqueado', () =>
    db.exec(`update public.program_subjects set period_order = 5 where program_id = '${PROG_ID}'`),
  );

  await db.exec(`update public.sections set is_active = false where id = '${SEC_ID}'`);
  let soloOtroPeriodo = true;
  try {
    await db.exec(`update public.program_subjects set period_order = 5 where program_id = '${PROG_ID}'`);
  } catch {
    soloOtroPeriodo = false;
  }
  check('una sección de OTRO período no bloquea el pensum', soloOtroPeriodo);

  // La misma sección no se puede abrir dos veces para la misma materia y
  // período, aunque la existente esté archivada: el nombre identifica la
  // sección, y dos 'SA' del mismo lapso serían la misma sección dos veces.
  await esperaError('la misma sección no se duplica para materia y período', () =>
    db.exec(
      `insert into public.sections (program_id, subject_id, period_code, name, max_capacity)
       values ('${PROG_ID}', '${MAT_ID}', '${PERIODO}', 'SA', 25)`,
    ),
  );

  // Mover una materia entre programas: si el DESTINO está en uso también se
  // bloquea. Comprobar sólo el origen dejaría ese agujero abierto.
  const PROG2 = '77777777-7777-7777-7777-777777777777';
  const MAT2 = '88888888-8888-8888-8888-888888888888';
  await db.exec('begin');
  await db.exec(
    `insert into public.programs (id, code, name, type, is_active)
     values ('${PROG2}', 'SIST-02', 'Analisis de Sistemas II', 'CARRERA', true)`,
  );
  await db.exec(
    `insert into public.subjects (id, code, name, academic_hours)
     values ('${MAT2}', 'BD-I', 'Bases de Datos I', 96)`,
  );
  await db.exec(
    `insert into public.program_subjects (program_id, subject_id, period_order)
     values ('${PROG2}', '${MAT2}', 1)`,
  );
  await db.exec('commit');
  await db.exec(
    `insert into public.sections (program_id, subject_id, period_code, name, max_capacity)
     values ('${PROG2}', '${MAT2}', '${PERIODO}', 'SA', 25)`,
  );
  await esperaError('mover una materia a un programa EN USO también se bloquea', () =>
    db.exec(`update public.program_subjects set program_id = '${PROG2}' where program_id = '${PROG_ID}'`),
  );

  // Archivar la sección es la salida que documenta la migración.
  await db.exec(`update public.sections set is_active = false where program_id = '${PROG_ID}'`);
  let trasArchivar = true;
  try {
    await db.exec(`update public.program_subjects set period_order = 4 where program_id = '${PROG_ID}'`);
  } catch {
    trasArchivar = false;
  }
  check('archivar las secciones desbloquea el pensum (la salida documentada)', trasArchivar);

  // ---------------------------------------------------------------- resumen
  console.log(
    `\n\x1b[1m${fallos.length === 0 ? '\x1b[32mTODO VERDE\x1b[0m' : '\x1b[31mHAY FALLOS\x1b[0m'}\x1b[0m ` +
      `— ${pasadas} aserciones pasadas, ${fallos.length} fallidas`,
  );
  if (fallos.length) {
    console.log('\nFallos:');
    for (const f of fallos) console.log(`  · ${f}`);
  }

  await db.close();
  process.exit(fallos.length === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('\n\x1b[31mError fatal durante la validación:\x1b[0m');
  console.error(e);
  process.exit(1);
});
