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

  // `m6_aula_virtual` va entre `m5_archivos` (orden 50) y `m6_asistencia`
  // (orden 60) porque comparte los archivos de M5. **No** sustituye a
  // `m6_asistencia`: el número 6 estaba tomado por Asistencia desde
  // `202609120002`, y la semilla dice que las claves nunca se renombran. El
  // nombre del archivo de la migración (`202609220001_mod6_aula_virtual.sql`)
  // no crea la clave.
  const esperados = [
    'm0_cpanel', 'm1_onboarding', 'm2_curriculo', 'm3_cuadrante',
    'm4_inscripciones', 'm5_archivos', 'm6_aula_virtual', 'm6_asistencia',
    'm7_calificaciones', 'm8_pasantias',
  ];
  check('hay 10 módulos sembrados', modulos.length === 10, `hay ${modulos.length}`);
  check(
    'los códigos coinciden con el ROADMAP',
    JSON.stringify(modulos.map((m) => m.clave)) === JSON.stringify(esperados),
  );
  check('m9 (certificados/QR) NO se siembra', !modulos.some((m) => m.clave.startsWith('m9')));
  check(
    'arrancan encendidos los módulos construidos y verificados (m0…m6)',
    modulos.filter((m) => m.habilitado).map((m) => m.clave).join(',') ===
      'm0_cpanel,m1_onboarding,m2_curriculo,m3_cuadrante,m4_inscripciones,m5_archivos,m6_aula_virtual',
  );
  // `m5_archivos` estuvo APAGADO a propósito hasta que existiera la Capa 7 (la
  // UI). Se encendía antes y habría quedado un ítem de menú sin circuito detrás
  // —el patrón de R-22—, así que tres aserciones lo fijaban en `false` y su
  // inversión es parte del mismo ciclo que esta.
  //
  // Lo enciende `202609210002_mod5_habilitar_modulo.sql`, **no**
  // `202609210001_mod5_archivos.sql`: esa construye la tabla, las RPC y los
  // parámetros y deja la bandera como estaba. Es la división que ya usó M4
  // (`202609200001` construye, `202609200002` enciende). Se deja escrito porque
  // atribuir el encendido a la migración equivocada es el error natural aquí.
  check(
    'm5_archivos arranca encendido: lo enciende 202609210002',
    modulos.find((m) => m.clave === 'm5_archivos').habilitado === true,
  );
  // `m6_aula_virtual` arrancaba APAGADO a propósito mientras no existiera el
  // lado del docente (R-22: un ítem de menú sin circuito detrás). Al cerrar la
  // Fase 4 el Centro de Mando del Docente está construido y verificado y el
  // servicio de contenido cableado en producción, así que `202609220003` lo
  // enciende. La aserción se invierte para que apagarlo sea una decisión y no un
  // descuido.
  check(
    'm6_aula_virtual arranca ENCENDIDO (202609220003, bucle docente→alumno completo)',
    modulos.find((m) => m.clave === 'm6_aula_virtual').habilitado === true,
  );
  check(
    'm6_aula_virtual va en el orden 55, entre M5 (50) y Asistencia (60)',
    modulos.find((m) => m.clave === 'm6_aula_virtual').orden === 55,
  );
  check(
    'm6_aula_virtual es visible para todos los roles (roles_permitidos vacío)',
    modulos.find((m) => m.clave === 'm6_aula_virtual').roles_permitidos.length === 0,
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
  // 8 de la semilla de 202609120002 + `habilitar_sistema_bids` (M4,
  // 202609190001) + `m5_max_bytes` y `m5_max_archivos_por_entidad` (M5,
  // 202609210001). El conteo es fijo a propósito: obliga a actualizarlo —y a
  // pensarlo— cuando alguien añade un parámetro.
  check('hay 11 parámetros sembrados', settings.length === 11, `hay ${settings.length}`);
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

  // Un módulo normal SÍ debe poder apagarse y volverse a encender: el guardián
  // no es un bloqueo general. La migración 202609180003 ya dejó m2_curriculo
  // encendido, así que lo apagamos y lo encendemos para dejar una transición
  // false->true auditada; si no, el último renglón sería true->true y fallaría.
  await db.exec("update public.system_modules set habilitado = false where clave = 'm2_curriculo'");
  const m2off = (await db.query("select habilitado from public.system_modules where clave = 'm2_curriculo'")).rows[0];
  check('un módulo normal sí se puede apagar', m2off.habilitado === false);
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
  // La semilla de 202609120002 fija periodo_activo = '2026-1' de forma literal.
  // Tras la migración 202609180003 ese lapso se renombró a 'SA26-2' y ya no
  // existe en academic_periods, así que reaplicar la semilla tal cual dispara la
  // guarda exigir_periodo_registrado() (23514). Sustituimos el literal por el
  // periodo vigente REAL para que la reaplicación sea coherente con el estado.
  const periodoVigente = (
    await db.query("select valor #>> '{}' as p from public.system_settings where clave = 'periodo_activo'")
  ).rows[0]?.p;
  const semillaSql = fs
    .readFileSync(path.join(SUPABASE, 'migrations', '202609120002_phase3_admin_core.sql'), 'utf8')
    .split('-- 10. Semilla')[1]
    .split('-- 11.')[0]
    .replaceAll('2026-1', periodoVigente);
  await db.exec(semillaSql);
  const m6 = (await db.query("select habilitado from public.system_modules where clave = 'm6_asistencia'")).rows[0];
  const totalModulos = (await db.query('select count(*)::int as n from public.system_modules')).rows[0].n;
  check('reaplicar la semilla NO revive un módulo apagado a mano', m6.habilitado === false);
  check('reaplicar la semilla NO duplica filas', totalModulos === 10, `hay ${totalModulos}`);

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
  check('puede leer el catálogo de módulos (lo necesita el menú)', alumnoVe.rows[0].n === 10);

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
  check('SÍ puede leer todos los parámetros', settingsAdmin.rows[0].n === 11, `ve ${settingsAdmin.rows[0].n}`);

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
  //
  // M3 exige que el lapso esté REGISTRADO: `sections.period_code` es ahora una
  // FK contra `academic_periods`. El período ficticio se registra aquí, que es
  // justo lo que haría el administrador antes de abrir una sección en él.
  await db.exec(
    `insert into public.academic_periods (code, name, is_active)
     values ('2099-9', 'Lapso futuro de prueba', false)`,
  );
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

  seccion('16. Las dos funciones del asistente (RPC de M2)');

  // Estas funciones existen porque PostgREST no admite insertar un padre con
  // sus hijos en la misma petición (comprobado contra la base real: PGRST204).
  // Aquí se prueba lo que ninguna otra capa puede probar: que la transacción
  // deshace TODO cuando la Regla 1 rechaza el pensum.

  const MAT_RPC = '55555555-5555-5555-5555-555555555555';
  const MAT_RPC2 = '66666666-6666-6666-6666-666666666666';
  await db.exec(
    `insert into public.subjects (id, code, name, academic_hours) values
       ('${MAT_RPC}',  'RPC-I',  'Materia de RPC I',  48),
       ('${MAT_RPC2}', 'RPC-II', 'Materia de RPC II', 48)`,
  );

  // --- seguridad: las funciones no pueden ser un agujero -------------------
  const defs = (
    await db.query(
      "select proname, prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
        "where n.nspname = 'public' and proname in ('crear_programa_con_pensum', 'reemplazar_pensum')",
    )
  ).rows;
  check('existen las dos funciones del asistente', defs.length === 2, `hay ${defs.length}`);
  check(
    'son security INVOKER (con DEFINER se saltarían la RLS)',
    defs.length > 0 && defs.every((f) => f.prosecdef === false),
    defs.map((f) => `${f.proname}=${f.prosecdef}`).join(', '),
  );

  // `anon` no debe poder ejecutarlas. Sin el `revoke` explícito, PostgreSQL
  // concede EXECUTE a PUBLIC por defecto y esto fallaría.
  const anonPuede = (
    await db.query(
      "select has_function_privilege('anon', p.oid, 'EXECUTE') as puede from pg_proc p " +
        "join pg_namespace n on n.oid = p.pronamespace " +
        "where n.nspname = 'public' and proname = 'crear_programa_con_pensum'",
    )
  ).rows[0];
  check('anon NO puede ejecutar la función del asistente', anonPuede?.puede === false);

  // --- el camino feliz: programa activo + pensum en una sola llamada -------
  const creado = (
    await db.query(
      `select public.crear_programa_con_pensum(
         'RPC-01', 'Carrera por función', 'CARRERA', false, true,
         '[{"materiaId":"${MAT_RPC}","periodo":1}]'::jsonb
       ) as id`,
    )
  ).rows[0].id;
  check('la función devuelve el id del programa', typeof creado === 'string' && creado.length > 0);

  const activo = (
    await db.query(`select is_active, type from public.programs where id = '${creado}'`)
  ).rows[0];
  check('el programa nació ACTIVO y la Regla 1 lo aceptó', activo?.is_active === true);
  const pensumCreado = (
    await db.query(`select count(*)::int as n from public.program_subjects where program_id = '${creado}'`)
  ).rows[0].n;
  check('el pensum se insertó en la misma llamada', pensumCreado === 1, `${pensumCreado} fila(s)`);

  // --- LA PRUEBA DE ATOMICIDAD --------------------------------------------
  // Con el pensum vacío, la Regla 1 rechaza al confirmar. Lo que importa no es
  // sólo que falle: es que NO quede el programa. Si la función no fuera
  // transaccional, el `insert into programs` sobreviviría al fallo.
  await esperaError('pensum vacío: la función falla', () =>
    db.query(
      `select public.crear_programa_con_pensum(
         'RPC-02', 'No debe existir', 'CARRERA', false, true, '[]'::jsonb
       )`,
    ),
  );
  const rastro = (
    await db.query("select count(*)::int as n from public.programs where code = 'RPC-02'")
  ).rows[0].n;
  check(
    'ATOMICIDAD: el programa NO quedó a medias',
    rastro === 0,
    rastro === 0 ? 'cero filas' : `quedaron ${rastro}`,
  );

  // --- reemplazo: la diferencia se calcula sola ----------------------------
  await db.query(
    `select public.reemplazar_pensum(
       '${creado}',
       '[{"materiaId":"${MAT_RPC}","periodo":3},{"materiaId":"${MAT_RPC2}","periodo":1}]'::jsonb
     )`,
  );
  const trasReemplazo = (
    await db.query(
      `select subject_id, period_order from public.program_subjects where program_id = '${creado}' order by period_order`,
    )
  ).rows;
  check('el reemplazo deja 2 materias', trasReemplazo.length === 2, `${trasReemplazo.length} fila(s)`);
  check(
    'reordenó la que cambió de período (1 -> 3)',
    trasReemplazo.find((f) => f.subject_id === MAT_RPC)?.period_order === 3,
  );
  check('insertó la que faltaba', trasReemplazo.some((f) => f.subject_id === MAT_RPC2));

  await db.query(
    `select public.reemplazar_pensum('${creado}', '[{"materiaId":"${MAT_RPC2}","periodo":1}]'::jsonb)`,
  );
  const trasQuitar = (
    await db.query(`select count(*)::int as n from public.program_subjects where program_id = '${creado}'`)
  ).rows[0].n;
  check('borró la que sobraba', trasQuitar === 1, `${trasQuitar} fila(s)`);

  // --- Regla 2 a través de la función -------------------------------------
  // Es el camino real: el administrador reordena desde la API y quien bloquea
  // es el trigger, no la función. Si el trigger no abortara la función, la
  // operación habría quedado a medias.
  await db.exec(
    `insert into public.sections (program_id, subject_id, period_code, name, max_capacity, is_active)
     values ('${creado}', '${MAT_RPC2}', (select valor #>> '{}' from public.system_settings where clave = 'periodo_activo'), 'R1', 20, true)`,
  );
  await esperaError('Regla 2: la función no puede reordenar un pensum en uso', () =>
    db.query(
      `select public.reemplazar_pensum('${creado}', '[{"materiaId":"${MAT_RPC2}","periodo":5}]'::jsonb)`,
    ),
  );
  const intacto = (
    await db.query(
      `select period_order from public.program_subjects where program_id = '${creado}' and subject_id = '${MAT_RPC2}'`,
    )
  ).rows[0].period_order;
  check(
    'Regla 2: el período quedó INTACTO tras el bloqueo (la función se deshizo)',
    intacto === 1,
    `period_order = ${intacto}`,
  );

  // ------------------------------------------- 14. Módulo 3 — Cuadrante
  seccion('14. Módulo 3 — Aulas, períodos, guardias y cuadrante');

  const DOC1 = 'd0000001-0000-4000-8000-000000000001';
  const DOC2 = 'd0000002-0000-4000-8000-000000000002';
  const AULA_TALLER = 'a0000001-0000-4000-8000-000000000001';
  const AULA_TEORIA = 'a0000002-0000-4000-8000-000000000002';
  const SEC_M3 = 'c0000001-0000-4000-8000-000000000001';
  const SEC_M3B = 'c0000002-0000-4000-8000-000000000002';

  // ------------------------------------------------- 14.1 academic_periods
  const periodos = (
    await db.query('select code, is_active from public.academic_periods order by code')
  ).rows;
  check(
    'el lapso vigente quedó registrado por la migración',
    periodos.some((p) => p.code === PERIODO),
    `registrados: ${periodos.map((p) => p.code).join(', ')}`,
  );

  // La FK es lo que convierte R-06 en un error de guardado en vez de una guarda
  // silenciosa. Se comprueba que de verdad rechaza.
  await esperaError('la FK rechaza una sección en un lapso no registrado', () =>
    db.exec(
      `insert into public.sections (program_id, subject_id, period_code, name, max_capacity)
       values ('${PROG_ID}', '${MAT_ID}', 'NO-EXISTE', 'SZ', 25)`,
    ),
  );
  const seccionesFantasma = (
    await db.query("select count(*)::int as n from public.sections where name = 'SZ'")
  ).rows[0].n;
  check('la sección del lapso inventado NO se creó', seccionesFantasma === 0);

  // La guarda sobre `periodo_activo`: sin ella, la Regla 2 de M2 dejaría de
  // proteger sin avisar.
  await esperaError('la guarda rechaza un periodo_activo que no es un lapso registrado', () =>
    db.exec(`update public.system_settings set valor = '"2098-8"'::jsonb where clave = 'periodo_activo'`),
  );
  const periodoSigue = (
    await db.query("select valor #>> '{}' as p from public.system_settings where clave = 'periodo_activo'")
  ).rows[0].p;
  check('el periodo_activo quedó intacto tras el rechazo', periodoSigue === PERIODO, String(periodoSigue));

  // ----------------------------------------------------- 14.2 classrooms
  await db.exec(
    `insert into public.classrooms (id, name, capacity, is_workshop) values
       ('${AULA_TALLER}', 'Taller de Soldadura Cabina A', 12, true),
       ('${AULA_TEORIA}', 'Aula Teórica 2', 25, false)`,
  );
  check(
    'se registran aulas y talleres',
    (await db.query('select count(*)::int as n from public.classrooms')).rows[0].n === 2,
  );

  // Una zona es una fila con cupo 0 y sin taller (R-18): un solo concepto de
  // espacio, para que el trigger de colisión tenga un único sitio que mirar.
  await db.exec(
    `insert into public.classrooms (name, capacity, is_workshop)
     values ('Patio central', 0, false)`,
  );
  check(
    'una zona se registra con cupo 0',
    (await db.query("select capacity from public.classrooms where name = 'Patio central'")).rows[0]
      .capacity === 0,
  );

  await esperaError('dos espacios no pueden llamarse igual', () =>
    db.exec(`insert into public.classrooms (name) values ('Aula Teórica 2')`),
  );
  await esperaError('un cupo negativo se rechaza', () =>
    db.exec(`insert into public.classrooms (name, capacity) values ('Aula Rara', -1)`),
  );

  // ------------------------------------------------- 14.3 teacher_duties
  // Dos docentes de prueba. `handle_new_user` crea el perfil al insertar en
  // `auth.users`; aquí se ajusta el rol, como en el resto del archivo.
  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${DOC1}', 'docente1@inces.test', '{"nombres":"Luis","apellidos":"Márquez"}'::jsonb),
      ('${DOC2}', 'docente2@inces.test', '{"nombres":"Carmen","apellidos":"Ríos"}'::jsonb);
    update public.profiles set rol = 'docente' where id in ('${DOC1}', '${DOC2}');
  `);
  check(
    'los dos docentes de prueba tienen rol docente',
    (await db.query(`select count(*)::int as n from public.profiles where id in ('${DOC1}','${DOC2}') and rol = 'docente'`))
      .rows[0].n === 2,
  );

  // Lunes a sábado, turnos mañana y tarde.
  await db.exec(
    `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block) values
       ('${DOC1}', '${AULA_TALLER}', '${PERIODO}', 1, 1),
       ('${DOC2}', '${AULA_TEORIA}', '${PERIODO}', 6, 8)`,
  );
  check(
    'se asignan guardias de lunes a sábado',
    (await db.query('select count(*)::int as n from public.teacher_duties')).rows[0].n === 2,
  );

  // El turno es derivado: no puede contradecir al bloque (R-16).
  const turnos = (
    await db.query('select day_of_week, block, turno from public.teacher_duties order by day_of_week, block')
  ).rows;
  check(
    'el turno se deriva del bloque (1 -> MAÑANA, 8 -> TARDE)',
    turnos[0].turno === 'MAÑANA' && turnos[1].turno === 'TARDE',
    turnos.map((t) => `b${t.block}=${t.turno}`).join(' '),
  );

  await esperaError('el domingo (día 7) no es un día de guardia', () =>
    db.exec(
      `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
       values ('${DOC1}', '${AULA_TALLER}', '${PERIODO}', 7, 1)`,
    ),
  );
  await esperaError('el día 0 no existe', () =>
    db.exec(
      `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
       values ('${DOC1}', '${AULA_TALLER}', '${PERIODO}', 0, 1)`,
    ),
  );
  await esperaError('un bloque fuera de rango se rechaza', () =>
    db.exec(
      `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
       values ('${DOC1}', '${AULA_TALLER}', '${PERIODO}', 2, 13)`,
    ),
  );

  // -------------------------------------------- 14.4 el trigger anti-colisión
  const choqueDocente = await esperaError(
    'un docente no puede tener dos guardias en el mismo bloque',
    () =>
      db.exec(
        `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
         values ('${DOC1}', '${AULA_TEORIA}', '${PERIODO}', 1, 1)`,
      ),
  );
  check(
    'el choque de docente sale como 23514',
    choqueDocente?.code === '23514',
    `código: ${choqueDocente?.code}`,
  );
  check(
    'el mensaje nombra el día y el bloque',
    /lunes/.test(choqueDocente?.message) && /bloque 1/.test(choqueDocente?.message),
    choqueDocente?.message,
  );

  const choqueAula = await esperaError(
    'un espacio no puede tener dos guardias en el mismo bloque',
    () =>
      db.exec(
        `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
         values ('${DOC2}', '${AULA_TALLER}', '${PERIODO}', 1, 1)`,
      ),
  );
  check(
    'el choque de espacio también sale como 23514',
    choqueAula?.code === '23514',
    `código: ${choqueAula?.code}`,
  );

  // Las tres cosas que SÍ deben permitirse. Sin estas, un trigger que rechazara
  // todo pasaría las pruebas de arriba.
  let mismoDocenteOtroDia = true;
  try {
    await db.exec(
      `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
       values ('${DOC1}', '${AULA_TALLER}', '${PERIODO}', 2, 1)`,
    );
  } catch {
    mismoDocenteOtroDia = false;
  }
  check('el mismo docente SÍ puede el mismo bloque otro día', mismoDocenteOtroDia);

  let mismoDocenteOtroBloque = true;
  try {
    await db.exec(
      `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
       values ('${DOC1}', '${AULA_TALLER}', '${PERIODO}', 1, 2)`,
    );
  } catch {
    mismoDocenteOtroBloque = false;
  }
  check('el mismo docente SÍ puede otro bloque el mismo día', mismoDocenteOtroBloque);

  let mismoDocenteOtroPeriodo = true;
  try {
    await db.exec(
      `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
       values ('${DOC1}', '${AULA_TALLER}', '2099-9', 1, 1)`,
    );
  } catch {
    mismoDocenteOtroPeriodo = false;
  }
  check(
    'el mismo docente SÍ puede el mismo bloque en OTRO lapso (planificar el siguiente)',
    mismoDocenteOtroPeriodo,
  );

  // ------------------------------------------- 14.5 el cuadrante y el cruce
  await db.exec(
    `insert into public.sections (id, program_id, subject_id, period_code, name, max_capacity) values
       ('${SEC_M3}',  '${PROG_ID}', '${MAT_ID}', '${PERIODO}', 'SC', 25),
       ('${SEC_M3B}', '${PROG_ID}', '${MAT_ID}', '${PERIODO}', 'SD', 25)`,
  );

  await db.exec(
    `insert into public.schedule_slots (id, section_id, teacher_id, classroom_id, day_of_week, block) values
       ('e0000001-0000-4000-8000-000000000001', '${SEC_M3}',  '${DOC1}', '${AULA_TALLER}', 1, 3),
       ('e0000002-0000-4000-8000-000000000002', '${SEC_M3B}', '${DOC2}', '${AULA_TEORIA}', 2, 3)`,
  );
  check(
    'se crean clases en el cuadrante',
    (await db.query('select count(*)::int as n from public.schedule_slots')).rows[0].n === 2,
  );

  // Las tres colisiones DENTRO del cuadrante.
  await esperaError('un docente no puede dar dos clases en el mismo bloque', () =>
    db.exec(
      `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
       values ('${SEC_M3}', '${DOC1}', '${AULA_TEORIA}', 1, 3)`,
    ),
  );
  // Colisión SÓLO de espacio: DOC2 está libre el lunes bloque 3, pero el Taller
  // ya lo ocupa DOC1 con la clase de SEC_M3. Si el caso usara también a DOC1,
  // saltaría por docente y no diría nada sobre el aula.
  await esperaError('un espacio no puede alojar dos clases en el mismo bloque', () =>
    db.exec(
      `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
       values ('${SEC_M3B}', '${DOC2}', '${AULA_TALLER}', 1, 3)`,
    ),
  );

  // Y LA CLAVE: el cruce entre las dos tablas. Es lo que el requisito pide y lo
  // que una restricción `unique` no podría cubrir nunca.
  const cruceDocente = await esperaError(
    'CRUCE: una clase no puede caer donde el docente ya tiene guardia',
    () =>
      db.exec(
        `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
         values ('${SEC_M3}', '${DOC2}', '${AULA_TALLER}', 6, 8)`,
      ),
  );
  check(
    'el cruce guardia/clase de docente sale como 23514',
    cruceDocente?.code === '23514',
    `código: ${cruceDocente?.code}`,
  );

  const cruceAula = await esperaError(
    'CRUCE: una clase no puede caer donde ya hay guardia en ese espacio',
    () =>
      db.exec(
        `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
         values ('${SEC_M3}', '${DOC1}', '${AULA_TEORIA}', 6, 8)`,
      ),
  );
  check(
    'el cruce guardia/clase de espacio sale como 23514',
    cruceAula?.code === '23514',
    `código: ${cruceAula?.code}`,
  );

  // Archivar libera el hueco: una guardia inactiva no ocupa a nadie.
  await db.exec(
    `update public.teacher_duties set is_active = false
     where teacher_id = '${DOC2}' and day_of_week = 6 and block = 8`,
  );
  let trasArchivarGuardia = true;
  try {
    await db.exec(
      `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
       values ('${SEC_M3}', '${DOC2}', '${AULA_TALLER}', 6, 8)`,
    );
  } catch {
    trasArchivarGuardia = false;
  }
  check('archivar la guardia libera el hueco para una clase', trasArchivarGuardia);

  // ------------------------------------------------------ 14.6 RLS por rol
  const totalDuties = (await db.query('select count(*)::int as n from public.teacher_duties')).rows[0].n;
  const dutiesDoc1 = (
    await db.query(`select count(*)::int as n from public.teacher_duties where teacher_id = '${DOC1}'`)
  ).rows[0].n;

  const veDoc1 = await como('authenticated', DOC1, () =>
    db.query('select teacher_id from public.teacher_duties'),
  );
  check(
    'un docente ve SÓLO sus guardias',
    veDoc1.rows.length === dutiesDoc1 && veDoc1.rows.every((r) => r.teacher_id === DOC1),
    `vio ${veDoc1.rows.length} de ${totalDuties}`,
  );

  const alumnoVeDuties = await como('authenticated', ALUMNO_ID, () =>
    db.query('select count(*)::int as n from public.teacher_duties'),
  );
  check(
    'un estudiante no ve ninguna guardia',
    alumnoVeDuties.rows[0].n === 0,
    `vio ${alumnoVeDuties.rows[0].n}`,
  );

  // `anon` no recibe «cero filas» sino un rechazo de privilegio: no se le concedió
  // SELECT sobre las tablas de agenda. Es la negativa más fuerte de las dos, y
  // por eso se comprueba el código 42501 y no un recuento.
  const anonDuties = await esperaError('anon no tiene privilegio sobre las guardias', () =>
    como('anon', null, () =>
      db.query('select count(*)::int as n from public.teacher_duties'),
    ),
  );
  check(
    'el rechazo de anon es de privilegio (42501), no una lista vacía',
    anonDuties?.code === '42501',
    `código: ${anonDuties?.code}`,
  );

  // El docente ve sus clases y no las ajenas.
  const slotsDoc1 = (
    await db.query(`select count(*)::int as n from public.schedule_slots where teacher_id = '${DOC1}'`)
  ).rows[0].n;
  const veSlotsDoc1 = await como('authenticated', DOC1, () =>
    db.query('select teacher_id from public.schedule_slots'),
  );
  check(
    'un docente ve SÓLO sus clases',
    veSlotsDoc1.rows.length === slotsDoc1 && veSlotsDoc1.rows.every((r) => r.teacher_id === DOC1),
    `vio ${veSlotsDoc1.rows.length}, esperaba ${slotsDoc1}`,
  );

  // El estudiante ve las clases de las secciones en las que está matriculado, y
  // ninguna otra. Se matricula sólo en SEC_M3, así que no debe ver las de SEC_M3B.
  await db.exec(
    `insert into public.enrollments (student_id, section_id, status)
     values ('${ALUMNO_ID}', '${SEC_M3}', 'ENROLLED')`,
  );
  const veSlotsAlumno = await como('authenticated', ALUMNO_ID, () =>
    db.query('select section_id from public.schedule_slots'),
  );
  check(
    'un estudiante ve las clases de SU sección',
    veSlotsAlumno.rows.length >= 1 && veSlotsAlumno.rows.every((r) => r.section_id === SEC_M3),
    `vio ${veSlotsAlumno.rows.length} clases de secciones: ${[...new Set(veSlotsAlumno.rows.map((r) => r.section_id))].join(', ')}`,
  );

  const anonSlots = await esperaError('anon no tiene privilegio sobre el cuadrante', () =>
    como('anon', null, () =>
      db.query('select count(*)::int as n from public.schedule_slots'),
    ),
  );
  check(
    'el rechazo de anon sobre el cuadrante también es 42501',
    anonSlots?.code === '42501',
    `código: ${anonSlots?.code}`,
  );

  // El administrador ve todo el cuadrante.
  const veAdmin = await como('authenticated', ADMIN2_ID, () =>
    db.query('select count(*)::int as n from public.schedule_slots'),
  );
  const totalSlots = (await db.query('select count(*)::int as n from public.schedule_slots')).rows[0].n;
  check(
    'el administrador ve el cuadrante completo',
    veAdmin.rows[0].n === totalSlots,
    `vio ${veAdmin.rows[0].n} de ${totalSlots}`,
  );

  // ------------------------------------------- 14.7 vistas de lectura
  const cuadranteAdmin = await como('authenticated', ADMIN2_ID, () =>
    db.query('select * from public.v_cuadrante_clases'),
  );
  const fila = cuadranteAdmin.rows[0];
  check(
    'la vista del cuadrante resuelve materia, sección, espacio y docente',
    Boolean(fila) && Boolean(fila.subject_name) && Boolean(fila.section_name) &&
      Boolean(fila.classroom_name) && Boolean(fila.teacher_name),
    fila ? JSON.stringify(fila) : 'sin filas',
  );
  check(
    'la vista del cuadrante traduce el día',
    Boolean(fila) && ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'].includes(fila.day_name),
    fila ? String(fila.day_name) : 'sin filas',
  );

  // El nombre del docente se resuelve para un ESTUDIANTE aunque no pueda leer
  // `profiles`: es lo que justifica `nombre_para_mostrar()` (R-14).
  const cuadranteAlumno = await como('authenticated', ALUMNO_ID, () =>
    db.query('select teacher_name from public.v_cuadrante_clases'),
  );
  check(
    'un estudiante ve el NOMBRE del docente sin poder leer profiles',
    cuadranteAlumno.rows.length > 0 && cuadranteAlumno.rows.every((r) => r.teacher_name !== null),
    JSON.stringify(cuadranteAlumno.rows),
  );

  const perfilAjeno = await como('authenticated', ALUMNO_ID, () =>
    db.query(`select count(*)::int as n from public.profiles where id = '${DOC1}'`),
  );
  check(
    'y sigue sin poder leer la fila del docente (la RLS no se relajó)',
    perfilAjeno.rows[0].n === 0,
    `vio ${perfilAjeno.rows[0].n}`,
  );

  const vigente = await como('authenticated', ADMIN2_ID, () =>
    db.query('select code from public.v_periodo_vigente'),
  );
  check(
    'la vista del lapso vigente devuelve el período activo',
    vigente.rows.length === 1 && vigente.rows[0].code === PERIODO,
    JSON.stringify(vigente.rows),
  );

  const guardiasDoc1 = await como('authenticated', DOC1, () =>
    db.query('select teacher_id from public.v_cuadrante_guardias'),
  );
  check(
    'la vista de guardias respeta la RLS del docente',
    guardiasDoc1.rows.length > 0 && guardiasDoc1.rows.every((r) => r.teacher_id === DOC1),
    `vio ${guardiasDoc1.rows.length}`,
  );

  // --------------- 14.8 el camino REAL: escritura como `authenticated`
  // Las pruebas de 14.4 escribían como el DUEÑO de las tablas, y el dueño se
  // salta la comprobación de privilegios de función. Por eso no vieron que los
  // envoltorios de trigger eran `security invoker` mientras el llamante no
  // tenía EXECUTE sobre `exigir_agenda_libre()`: **toda alta real fallaba con
  // 42501** y la protección anti-colisión nunca llegaba a evaluarse. Un doble
  // que corre con más permisos que el usuario real no prueba al usuario real.
  //
  // Aquí se escribe como lo hace el backend: rol `authenticated` con los claims
  // de un admin. Si alguien vuelve a poner los envoltorios en `invoker`, la
  // primera aserción de este bloque se cae.
  //
  // Se usa ADMIN2_ID y no ADMIN_ID porque la sección 12 desactivó a ADMIN_ID a
  // propósito (`active = false`), y `is_admin()` exige `rol = 'admin' AND
  // active`: con el desactivado, la RLS rechazaría la escritura por un motivo
  // que no tiene nada que ver con lo que se está probando.
  seccion('14.8 El trigger funciona para un `authenticated` real, no para el dueño');

  let altaGuardiaOk = true;
  let altaGuardiaError = null;
  try {
    await como('authenticated', ADMIN2_ID, () =>
      db.exec(
        `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
         values ('${DOC2}', '${AULA_TEORIA}', '${PERIODO}', 4, 9)`,
      ),
    );
  } catch (e) {
    altaGuardiaOk = false;
    altaGuardiaError = e;
  }
  check(
    'un admin autenticado SÍ puede dar de alta una guardia',
    altaGuardiaOk,
    altaGuardiaError ? `${altaGuardiaError.code}: ${altaGuardiaError.message}` : '',
  );

  const choqueAutenticado = await esperaError(
    'el trigger sigue protegiendo cuando quien escribe es un admin autenticado',
    () =>
      como('authenticated', ADMIN2_ID, () =>
        db.exec(
          `insert into public.teacher_duties (teacher_id, classroom_id, period_code, day_of_week, block)
           values ('${DOC2}', '${AULA_TALLER}', '${PERIODO}', 4, 9)`,
        ),
      ),
  );
  check(
    'el choque llega como 23514 y no como un fallo de privilegios',
    choqueAutenticado?.code === '23514',
    `código: ${choqueAutenticado?.code}`,
  );

  let altaClaseOk = true;
  let altaClaseError = null;
  try {
    await como('authenticated', ADMIN2_ID, () =>
      db.exec(
        `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
         values ('${SEC_M3}', '${DOC1}', '${AULA_TALLER}', 4, 10)`,
      ),
    );
  } catch (e) {
    altaClaseOk = false;
    altaClaseError = e;
  }
  check(
    'un admin autenticado SÍ puede poner una clase en el cuadrante',
    altaClaseOk,
    altaClaseError ? `${altaClaseError.code}: ${altaClaseError.message}` : '',
  );

  const cruceAutenticado = await esperaError(
    'el cruce guardia/clase también salta para un admin autenticado',
    () =>
      como('authenticated', ADMIN2_ID, () =>
        db.exec(
          `insert into public.schedule_slots (section_id, teacher_id, classroom_id, day_of_week, block)
           values ('${SEC_M3B}', '${DOC1}', '${AULA_TEORIA}', 4, 10)`,
        ),
      ),
  );
  check(
    'el cruce llega como 23514, no como 42501',
    cruceAutenticado?.code === '23514',
    `código: ${cruceAutenticado?.code}`,
  );

  // El límite que NO se debe cruzar para "arreglar" un 42501: conceder EXECUTE
  // a `authenticated` convertiría la función en un oráculo de la agenda ajena
  // (¿está ocupado el jueves a las 9?) y en un grifo del `pg_advisory_xact_lock`.
  const llamadaDirecta = await esperaError(
    'la función delegada no se puede llamar a mano: la puerta es el trigger',
    () =>
      como('authenticated', ADMIN2_ID, () =>
        db.query(
          `select public.exigir_agenda_libre('${PERIODO}', 4::smallint, 9::smallint,
             '${DOC2}'::uuid, '${AULA_TEORIA}'::uuid, 'teacher_duties', gen_random_uuid())`,
        ),
      ),
  );
  check(
    'la llamada directa se rechaza por privilegios (42501)',
    llamadaDirecta?.code === '42501',
    `código: ${llamadaDirecta?.code}`,
  );

  // ------------------------------------------- 17. Módulo 4 — Inscripciones
  seccion('17. Módulo 4 — Inscripciones y cupos (cola FIFO, ofertas y reincorporación)');

  // ------------------------------------------------- 17.1 esquema de la frontera
  // El fallback de la decisión 5 sólo puede dispararse si `max_capacity` es
  // nullable: con `not null default 0`, el 0 tapa el parámetro global.
  const nullableCap = (
    await db.query(
      "select is_nullable from information_schema.columns " +
        "where table_schema='public' and table_name='sections' and column_name='max_capacity'",
    )
  ).rows[0]?.is_nullable;
  check(
    'sections.max_capacity es nullable (sin esto el fallback nunca dispara)',
    nullableCap === 'YES',
    String(nullableCap),
  );

  const bidsSetting = (
    await db.query(
      "select valor, tipo, es_publico from public.system_settings where clave = 'habilitar_sistema_bids'",
    )
  ).rows[0];
  check('habilitar_sistema_bids está sembrado', Boolean(bidsSetting));
  check(
    'habilitar_sistema_bids es boolean, privado y arranca apagado',
    bidsSetting?.tipo === 'boolean' && bidsSetting?.es_publico === false && bidsSetting?.valor === false,
    JSON.stringify(bidsSetting),
  );

  // Las RPC de M4 son `security definer` a propósito (se saltan la RLS y hacen
  // su propia autorización). Si alguna volviera a `invoker`, la escritura
  // directa que acabamos de cerrar seguiría cerrada, pero la función dejaría de
  // poder ver toda la tabla y el motor de cupos sería ciego.
  const rpcM4 = (
    await db.query(
      "select p.proname, p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
        "where n.nspname = 'public' and p.proname in " +
        "('solicitar_inscripcion','aceptar_cupo','renunciar_cupo','promover_siguiente'," +
        "'expirar_ofertas_cupo','reincorporar_inscripcion') order by p.proname",
    )
  ).rows;
  check('existen las 6 RPC de la máquina de estados de M4', rpcM4.length === 6, `hay ${rpcM4.length}`);
  check(
    'las 6 RPC de M4 son security DEFINER',
    rpcM4.length === 6 && rpcM4.every((f) => f.prosecdef === true),
    rpcM4.map((f) => `${f.proname}=${f.prosecdef ? 'DEFINER' : 'invoker'}`).join(', '),
  );

  // El helper del ajuste del 2026-09-18. Es la guarda que hace segura la regla
  // «PENDING_BID no reserva cupo»: sin él, un asiento con oferta en el aire se
  // entregaría también por la vía directa.
  //
  // SÍ necesita EXECUTE para `authenticated`, aunque las RPC que lo usan sean
  // `definer` y no lo necesitaran: la vista `v_ocupacion_secciones` es
  // `security_invoker`, así que la llamada dentro de su SELECT se evalúa con los
  // privilegios de quien consulta. Revocarlo rompería la vista para todos.
  const helperOferta = (
    await db.query(
      "select p.prosecdef, " +
        "has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_puede, " +
        "has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede " +
        "from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
        "where n.nspname = 'public' and p.proname = 'existe_oferta_vigente'",
    )
  ).rows[0];
  check('existe el helper existe_oferta_vigente', Boolean(helperOferta));
  check('existe_oferta_vigente es security DEFINER', helperOferta?.prosecdef === true);
  check(
    'authenticated SÍ puede ejecutar existe_oferta_vigente (la vista invoker lo necesita)',
    helperOferta?.auth_puede === true,
  );
  check('anon NO puede ejecutar existe_oferta_vigente', helperOferta?.anon_puede === false);

  // LA aserción que impide que la frontera se reabra en silencio: la escritura
  // directa de `authenticated` sobre `enrollments` debe estar revocada.
  const escrituraDirecta = (
    await db.query(
      "select has_table_privilege('authenticated','public.enrollments','INSERT') as i, " +
        "has_table_privilege('authenticated','public.enrollments','UPDATE') as u, " +
        "has_table_privilege('authenticated','public.enrollments','DELETE') as d",
    )
  ).rows[0];
  check('authenticated NO puede INSERT directo en enrollments', escrituraDirecta.i === false);
  check('authenticated NO puede UPDATE directo en enrollments', escrituraDirecta.u === false);
  check('authenticated NO puede DELETE directo en enrollments', escrituraDirecta.d === false);

  const politicasEnrollments = (
    await db.query(
      "select policyname from pg_policies where schemaname='public' and tablename='enrollments'",
    )
  ).rows.map((p) => p.policyname);
  check(
    'las políticas de escritura propias fueron eliminadas',
    !['enrollments_insert_own', 'enrollments_update_own', 'enrollments_delete_own'].some((p) =>
      politicasEnrollments.includes(p),
    ),
    politicasEnrollments.join(', '),
  );
  check('enrollments_read_own sigue en pie', politicasEnrollments.includes('enrollments_read_own'));
  check('enrollments_admin_all sigue en pie', politicasEnrollments.includes('enrollments_admin_all'));

  const triggersM4 = (
    await db.query(
      "select t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid " +
        "where c.relname = 'enrollments' and not t.tgisinternal",
    )
  ).rows.map((t) => t.tgname);
  check(
    'existe el trigger anti-duplicado por (estudiante, materia, lapso)',
    triggersM4.includes('enrollments_seccion_unica_por_materia'),
    triggersM4.join(', '),
  );

  // ------------------------------------------------- 17.2 el motor, bids APAGADO
  const ALU3 = '22222222-2222-2222-2222-222222222233';
  const ALU4 = '22222222-2222-2222-2222-222222222244';
  const ALU5 = '22222222-2222-2222-2222-222222222255';
  const ALU6 = '22222222-2222-2222-2222-222222222266';
  const ALU7 = '22222222-2222-2222-2222-222222222277';
  const ALU8 = '22222222-2222-2222-2222-222222222288';
  const ALU9 = '22222222-2222-2222-2222-222222222299';
  const ALU10 = '22222222-2222-2222-2222-222222222200';
  const MAT_M4 = '99999999-9999-4999-8999-999999999991';
  const SEC_M4A = 'bbbbbbb1-0000-4000-8000-000000000001';
  const SEC_M4B = 'bbbbbbb2-0000-4000-8000-000000000002';

  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${ALU3}', 'alu3@inces.test', '{"nombres":"Bruno","apellidos":"Díaz"}'::jsonb),
      ('${ALU4}', 'alu4@inces.test', '{"nombres":"Carla","apellidos":"Gil"}'::jsonb),
      ('${ALU5}', 'alu5@inces.test', '{"nombres":"Diego","apellidos":"Soto"}'::jsonb),
      ('${ALU6}', 'alu6@inces.test', '{"nombres":"Elena","apellidos":"Ruiz"}'::jsonb),
      ('${ALU7}', 'alu7@inces.test', '{"nombres":"Fabián","apellidos":"Luz"}'::jsonb),
      ('${ALU8}', 'alu8@inces.test', '{"nombres":"Gina","apellidos":"Paz"}'::jsonb),
      ('${ALU9}', 'alu9@inces.test', '{"nombres":"Hugo","apellidos":"Mar"}'::jsonb),
      ('${ALU10}', 'alu10@inces.test', '{"nombres":"Iris","apellidos":"Vega"}'::jsonb);
  `);

  await db.exec(
    `insert into public.subjects (id, code, name, academic_hours)
     values ('${MAT_M4}', 'M4-I', 'Materia de M4', 48)`,
  );
  await db.exec(
    `insert into public.sections (id, program_id, subject_id, period_code, name, max_capacity) values
       ('${SEC_M4A}', '${PROG_ID}', '${MAT_M4}', '${PERIODO}', 'MA', 2),
       ('${SEC_M4B}', '${PROG_ID}', '${MAT_M4}', '${PERIODO}', 'MB', 1)`,
  );

  const inscribe = (alumno, seccion) =>
    como('authenticated', alumno, () =>
      db.query(`select public.solicitar_inscripcion('${seccion}') as s`),
    );

  const s1 = await inscribe(ALU3, SEC_M4A);
  check('el primer estudiante entra ENROLLED', s1.rows[0].s === 'ENROLLED', String(s1.rows[0].s));
  const s2 = await inscribe(ALU4, SEC_M4A);
  check('el segundo llena el cupo (2/2) como ENROLLED', s2.rows[0].s === 'ENROLLED', String(s2.rows[0].s));
  const s3 = await inscribe(ALU5, SEC_M4A);
  check('el tercero, con la sección llena, va a WAITLISTED', s3.rows[0].s === 'WAITLISTED', String(s3.rows[0].s));

  // La escritura directa ahora es un rechazo de privilegios, no un insert.
  const directo = await esperaError('un autenticado no puede insertar una inscripción a mano', () =>
    como('authenticated', ALU3, () =>
      db.exec(
        `insert into public.enrollments (student_id, section_id, status)
         values ('${ALU3}', '${SEC_M4B}', 'ENROLLED')`,
      ),
    ),
  );
  check('el rechazo directo es de privilegios (42501)', directo?.code === '42501', `código ${directo?.code}`);

  // `anon` no tiene NADA que hacer con `enrollments`: ni leer. Sin GRANT de
  // SELECT la RLS ni se evalúa, así que el rechazo tiene que ser de privilegios
  // (42501) y no una lista vacía. Comprobar sólo la escritura dejaría abierta la
  // puerta de la lectura, que también expone datos de menores.
  const anonIns = await esperaError('anon no puede insertar en enrollments', () =>
    como('anon', null, () =>
      db.exec(
        `insert into public.enrollments (student_id, section_id, status)
         values ('${ALU3}', '${SEC_M4B}', 'ENROLLED')`,
      ),
    ),
  );
  check('el rechazo de anon al ESCRIBIR es de privilegios (42501)', anonIns?.code === '42501', `código ${anonIns?.code}`);
  const anonSel = await esperaError('anon no puede leer enrollments', () =>
    como('anon', null, () => db.query('select * from public.enrollments limit 1')),
  );
  check('el rechazo de anon al LEER es de privilegios (42501)', anonSel?.code === '42501', `código ${anonSel?.code}`);

  // Ni un ADMIN escribe directo: el GRANT está revocado para TODO
  // `authenticated`. Si esto pasara, la frontera tendría una puerta trasera que
  // el `revoke` no cubre y el motor de cupos volvería a ser decorativo.
  const adminDirecto = await esperaError('ni un admin puede insertar directo en enrollments', () =>
    como('authenticated', ADMIN2_ID, () =>
      db.exec(
        `insert into public.enrollments (student_id, section_id, status)
         values ('${ADMIN2_ID}', '${SEC_M4B}', 'ENROLLED')`,
      ),
    ),
  );
  check('el rechazo del admin directo también es de privilegios (42501)', adminDirecto?.code === '42501', `código ${adminDirecto?.code}`);

  // Decisión 6: dos secciones de la misma materia en el mismo lapso.
  const dup = await esperaError(
    'un estudiante no puede tener dos secciones de la misma materia en el lapso',
    () => inscribe(ALU3, SEC_M4B),
  );
  check('el duplicado sale como 23514 y no como un error de unicidad', dup?.code === '23514', `código ${dup?.code}`);

  // Renuncia con bids APAGADO: promoción FIFO directa a ENROLLED.
  const baja = await como('authenticated', ALU3, () =>
    db.query(`select public.renunciar_cupo('${SEC_M4A}') as s`),
  );
  check('renunciar devuelve DROPPED', baja.rows[0].s === 'DROPPED', String(baja.rows[0].s));
  const promovidoFifo = (
    await db.query(
      `select status from public.enrollments where student_id='${ALU5}' and section_id='${SEC_M4A}'`,
    )
  ).rows[0]?.status;
  check('con bids apagado, el primero de la cola pasa directo a ENROLLED', promovidoFifo === 'ENROLLED', String(promovidoFifo));

  // Reincorporación: es una excepción de administración, no una vía del estudiante.
  // REGLA INSTITUCIONAL (2026-09-18): el administrador PUEDE exceder la capacidad.
  // Antes esto se rechazaba con 23514; ahora debe PROCEDER. La aserción se
  // invirtió a propósito, y se comprueba el exceso de verdad, no sólo el estado.
  const antesReinc = (
    await db.query(
      `select cupos_ocupados, cupo_efectivo from public.v_ocupacion_secciones where id = '${SEC_M4A}'`,
    )
  ).rows[0];
  check(
    'antes de reincorporar, la sección está llena (no hay hueco que dar)',
    antesReinc.cupos_ocupados === antesReinc.cupo_efectivo,
    `${antesReinc.cupos_ocupados}/${antesReinc.cupo_efectivo}`,
  );

  const reinc = await como('authenticated', ADMIN2_ID, () =>
    db.query(`select public.reincorporar_inscripcion('${ALU3}', '${SEC_M4A}') as s`),
  );
  check('un administrador reincorpora a un DROPPED como ENROLLED', reinc.rows[0].s === 'ENROLLED', String(reinc.rows[0].s));

  const despuesReinc = (
    await db.query(
      `select cupos_ocupados, cupo_efectivo from public.v_ocupacion_secciones where id = '${SEC_M4A}'`,
    )
  ).rows[0];
  check(
    'el administrador PUDO exceder la capacidad de la sección',
    despuesReinc.cupos_ocupados > despuesReinc.cupo_efectivo,
    `${despuesReinc.cupos_ocupados}/${despuesReinc.cupo_efectivo}`,
  );

  // Y el estudiante no puede hacerlo por su cuenta: la excepción es del admin.
  const noAdmin = await esperaError('un estudiante no puede reincorporar inscripciones', () =>
    como('authenticated', ALU5, () =>
      db.query(`select public.reincorporar_inscripcion('${ALU4}', '${SEC_M4A}')`),
    ),
  );
  check('la reincorporación sin ser admin se rechaza por permisos (42501)', noAdmin?.code === '42501', `código ${noAdmin?.code}`);

  // ------------------------------------------------- 17.3 el motor, bids ENCENDIDO
  await db.exec("update public.system_settings set valor = 'true'::jsonb where clave = 'habilitar_sistema_bids'");
  check(
    'el interruptor de bids quedó encendido',
    (await db.query("select valor from public.system_settings where clave='habilitar_sistema_bids'")).rows[0]
      .valor === true,
  );

  const b1 = await inscribe(ALU6, SEC_M4B);
  check('con bids encendido, un cupo libre sigue admitiendo ENROLLED', b1.rows[0].s === 'ENROLLED', String(b1.rows[0].s));
  const b2 = await inscribe(ALU7, SEC_M4B);
  check('con la sección llena, el siguiente va a WAITLISTED', b2.rows[0].s === 'WAITLISTED', String(b2.rows[0].s));

  // La prueba de que el recuento no lo filtra la RLS: ALU7 consulta la vista y
  // debe ver el asiento de ALU6, que NO es suyo. Si la vista fuera `invoker` sin
  // funciones definer, vería 0 y el cupo parecería siempre vacío.
  const vistaAjena = await como('authenticated', ALU7, () =>
    db.query(`select cupos_ocupados from public.v_ocupacion_secciones where id = '${SEC_M4B}'`),
  );
  check(
    'la vista cuenta asientos AJENOS: los definer saltan la RLS del llamante',
    vistaAjena.rows[0]?.cupos_ocupados === 1,
    JSON.stringify(vistaAjena.rows[0] ?? {}),
  );

  await como('authenticated', ALU6, () => db.query(`select public.renunciar_cupo('${SEC_M4B}')`));
  const oferta = (
    await db.query(
      `select status, bid_expires_at from public.enrollments where student_id='${ALU7}' and section_id='${SEC_M4B}'`,
    )
  ).rows[0];
  check('con bids encendido, el primero de la cola recibe una OFERTA (PENDING_BID)', oferta?.status === 'PENDING_BID', String(oferta?.status));
  check(
    'la oferta nace con vencimiento futuro (bid_expires_at)',
    oferta?.bid_expires_at != null && new Date(oferta.bid_expires_at).getTime() > Date.now(),
    String(oferta?.bid_expires_at),
  );

  const acepta = await como('authenticated', ALU7, () =>
    db.query(`select public.aceptar_cupo('${SEC_M4B}') as s`),
  );
  check('aceptar la oferta confirma ENROLLED', acepta.rows[0].s === 'ENROLLED', String(acepta.rows[0].s));
  const trasAceptar = (
    await db.query(
      `select status, bid_expires_at from public.enrollments where student_id='${ALU7}' and section_id='${SEC_M4B}'`,
    )
  ).rows[0];
  check('al aceptar se limpia el vencimiento', trasAceptar.status === 'ENROLLED' && trasAceptar.bid_expires_at === null);

  // ---------------------------------------------- 17.4 expiración idempotente
  const b8 = await inscribe(ALU8, SEC_M4B);
  check('otro estudiante con la sección llena va a WAITLISTED', b8.rows[0].s === 'WAITLISTED', String(b8.rows[0].s));
  await como('authenticated', ALU7, () => db.query(`select public.renunciar_cupo('${SEC_M4B}')`));
  const oferta8 = (
    await db.query(`select status from public.enrollments where student_id='${ALU8}' and section_id='${SEC_M4B}'`)
  ).rows[0]?.status;
  check('el primero de la cola recibe la nueva oferta', oferta8 === 'PENDING_BID', String(oferta8));

  // Un segundo en cola, detrás de la oferta viva.
  const b9 = await inscribe(ALU9, SEC_M4B);
  check('detrás de una oferta viva, el siguiente queda en WAITLISTED', b9.rows[0].s === 'WAITLISTED', String(b9.rows[0].s));

  // Se fuerza el vencimiento de la oferta y se barre.
  await db.exec(
    `update public.enrollments set bid_expires_at = now() - interval '1 hour'
     where student_id='${ALU8}' and section_id='${SEC_M4B}'`,
  );
  const expiradas = (await db.query('select public.expirar_ofertas_cupo() as n')).rows[0].n;
  check('expirar_ofertas_cupo devuelve 1 oferta expirada', expiradas === 1, `devolvió ${expiradas}`);
  const alu8Tras = (
    await db.query(`select status from public.enrollments where student_id='${ALU8}' and section_id='${SEC_M4B}'`)
  ).rows[0]?.status;
  check('la oferta vencida queda DROPPED', alu8Tras === 'DROPPED', String(alu8Tras));
  const alu9Tras = (
    await db.query(`select status from public.enrollments where student_id='${ALU9}' and section_id='${SEC_M4B}'`)
  ).rows[0]?.status;
  check('tras expirar, se promueve al siguiente de la cola (PENDING_BID)', alu9Tras === 'PENDING_BID', String(alu9Tras));

  const expiradas2 = (await db.query('select public.expirar_ofertas_cupo() as n')).rows[0].n;
  check('expirar_ofertas_cupo es idempotente (la segunda vez devuelve 0)', expiradas2 === 0, `devolvió ${expiradas2}`);

  // ---------------------- 17.5 reglas institucionales (ajuste del 2026-09-18)
  //  Dos reglas cambiaron respecto a la primera versión del motor, y la segunda
  //  trae una consecuencia que hay que vigilar: si una oferta viva no cuenta como
  //  ocupación, el contador dice que hay hueco mientras la oferta está en el aire.
  const ocupacion = await como('authenticated', ALU5, () =>
    db.query(
      `select cupo_efectivo, cupos_ocupados, cupos_disponibles, oferta_vigente
         from public.v_ocupacion_secciones where id = '${SEC_M4B}'`,
    ),
  );
  const oc = ocupacion.rows[0] ?? {};

  check(
    'una oferta viva NO suma a cupos_ocupados: sólo cuenta ENROLLED',
    oc.cupos_ocupados === 0,
    `cupos_ocupados = ${oc.cupos_ocupados}`,
  );
  check(
    'pero la vista DECLARA la oferta en el aire, para que la interfaz no mienta',
    oc.oferta_vigente === true,
    `oferta_vigente = ${oc.oferta_vigente}`,
  );
  check(
    'el contador por sí solo diría que hay hueco — por eso la guarda es imprescindible',
    oc.cupos_disponibles > 0,
    `cupos_disponibles = ${oc.cupos_disponibles}`,
  );

  // LA GUARDA ANTI-DOBLE-VENTA. Sin ella este recién llegado entraría directo a
  // ENROLLED (el contador dice que hay hueco) y después ALU9 aceptaría su oferta:
  // dos personas en un asiento de uno.
  const b10 = await inscribe(ALU10, SEC_M4B);
  check(
    'con una oferta viva, un recién llegado NO entra directo a ENROLLED',
    b10.rows[0].s === 'WAITLISTED',
    String(b10.rows[0].s),
  );

  // Al resolverse la oferta, el asiento pasa a contar y la guarda se levanta.
  await como('authenticated', ALU9, () => db.query(`select public.aceptar_cupo('${SEC_M4B}')`));
  const trasAceptar9 = (
    await db.query(
      `select cupo_efectivo, cupos_ocupados, oferta_vigente
         from public.v_ocupacion_secciones where id = '${SEC_M4B}'`,
    )
  ).rows[0];
  check(
    'al aceptar ALU9, el asiento cuenta y la oferta deja de estar vigente',
    trasAceptar9.cupos_ocupados === 1 && trasAceptar9.oferta_vigente === false,
    JSON.stringify(trasAceptar9),
  );

  const alu10Estado = (
    await db.query(`select status from public.enrollments where student_id='${ALU10}' and section_id='${SEC_M4B}'`)
  ).rows[0]?.status;
  check(
    'ALU10 sigue en la cola: aceptar no promueve a nadie por detrás',
    alu10Estado === 'WAITLISTED',
    String(alu10Estado),
  );

  // ------------------------------------------- 18. Módulo 5 — Archivos (R2)
  seccion('18. Módulo 5 — Archivos (R2): RLS, RPCs y frontera de escritura');

  // ------------------------------------------------- 18.1 esquema y RLS
  const tablaM5 = (
    await db.query(
      "select rowsecurity from pg_tables where schemaname='public' and tablename='files_metadata'",
    )
  ).rows[0];
  check('existe files_metadata con RLS activo', tablaM5?.rowsecurity === true);

  const colsM5 = (
    await db.query(
      "select column_name from information_schema.columns where table_schema='public' and table_name='files_metadata'",
    )
  ).rows.map((c) => c.column_name);
  check(
    'files_metadata tiene las columnas del contrato de M5',
    [
      'propietario_id', 'r2_key', 'nombre_original', 'tipo_contenido', 'tamano_bytes',
      'entity_type', 'entidad_id', 'estado', 'confirmado_en', 'deleted_at',
    ].every((c) => colsM5.includes(c)),
    colsM5.join(', '),
  );

  // La frontera de escritura (decisión 1): lectura sí, escritura directa NO. Se
  // comprueban las dos mitades porque `revoke all` sin el `grant select` dejaría
  // al propietario sin ver ni lo suyo, y un `grant` de más reabriría la puerta.
  const permisosM5 = (
    await db.query(
      "select has_table_privilege('authenticated','public.files_metadata','SELECT') as s, " +
        "has_table_privilege('authenticated','public.files_metadata','INSERT') as i, " +
        "has_table_privilege('authenticated','public.files_metadata','UPDATE') as u, " +
        "has_table_privilege('authenticated','public.files_metadata','DELETE') as d",
    )
  ).rows[0];
  check('authenticated SÍ puede SELECT en files_metadata', permisosM5.s === true);
  check('authenticated NO puede INSERT directo en files_metadata', permisosM5.i === false);
  check('authenticated NO puede UPDATE directo en files_metadata', permisosM5.u === false);
  check('authenticated NO puede DELETE directo en files_metadata', permisosM5.d === false);

  const politicasM5 = (
    await db.query(
      "select policyname from pg_policies where schemaname='public' and tablename='files_metadata'",
    )
  ).rows.map((p) => p.policyname);
  check('existe la política del propietario', politicasM5.includes('files_metadata_read_own'));
  check('existe la política del administrador', politicasM5.includes('files_metadata_admin_read'));

  // ------------------------------------------------- 18.2 RPCs: firma y privilegios
  const rpcM5 = (
    await db.query(
      "select p.proname, p.prosecdef, " +
        "has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede, " +
        "has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_puede " +
        "from pg_proc p join pg_namespace n on n.oid = p.pronamespace " +
        "where n.nspname='public' and p.proname in " +
        "('registrar_archivo_pendiente','confirmar_archivo','marcar_archivo_borrado') order by p.proname",
    )
  ).rows;
  check('existen las 3 RPC de escritura de M5', rpcM5.length === 3, `hay ${rpcM5.length}`);
  check(
    'las 3 RPC de M5 son security DEFINER',
    rpcM5.length === 3 && rpcM5.every((f) => f.prosecdef === true),
    rpcM5.map((f) => `${f.proname}=${f.prosecdef ? 'DEFINER' : 'invoker'}`).join(', '),
  );
  check(
    'anon NO puede ejecutar ninguna RPC de M5',
    rpcM5.length === 3 && rpcM5.every((f) => f.anon_puede === false),
    rpcM5.map((f) => `${f.proname}=${f.anon_puede ? 'PUEDE' : 'no'}`).join(', '),
  );
  check(
    'authenticated SÍ puede ejecutar las RPC de M5',
    rpcM5.length === 3 && rpcM5.every((f) => f.auth_puede === true),
  );

  // ------------------------------------------------- 18.3 semilla de límites
  const maxBytes = (
    await db.query(
      "select valor, tipo, es_publico from public.system_settings where clave='m5_max_bytes'",
    )
  ).rows[0];
  check('m5_max_bytes sembrado en 10485760 (10 MB)', maxBytes?.valor === 10485760, JSON.stringify(maxBytes));
  check('m5_max_bytes es number y privado', maxBytes?.tipo === 'number' && maxBytes?.es_publico === false);

  const maxArchivos = (
    await db.query(
      "select valor, tipo, es_publico from public.system_settings where clave='m5_max_archivos_por_entidad'",
    )
  ).rows[0];
  check('m5_max_archivos_por_entidad sembrado en 10', maxArchivos?.valor === 10, JSON.stringify(maxArchivos));
  check(
    'm5_max_archivos_por_entidad es number y privado',
    maxArchivos?.tipo === 'number' && maxArchivos?.es_publico === false,
  );

  // ------------------------------------------------- 18.4 el ciclo por RPC
  const PROPIETARIO = ALUMNO_ID;
  const TERCERO = DOC1;
  const ADMIN_M5 = ADMIN2_ID;

  const registro = await como('authenticated', PROPIETARIO, () =>
    db.query(
      `select id, propietario_id, estado, tamano_bytes from public.registrar_archivo_pendiente(
         '${PROPIETARIO}', 'm5_archivos/prueba/2026/09/abc.pdf',
         'informe.pdf', 'application/pdf', 'TASK_SUBMISSION', null)`,
    ),
  );
  const archivo = registro.rows[0];
  check('registrar_archivo_pendiente devuelve la fila', Boolean(archivo?.id));
  check('el archivo nace en PENDING', archivo?.estado === 'PENDING', String(archivo?.estado));
  check(
    'el archivo nace SIN tamaño (el objeto aún no se verificó)',
    archivo?.tamano_bytes === null,
    String(archivo?.tamano_bytes),
  );
  check('el propietario es quien lo registró', archivo?.propietario_id === PROPIETARIO);
  const archivoId = archivo.id;

  // Registrar a nombre de un tercero: prohibido salvo admin (decisión 1). Sin
  // esta comprobación, un usuario podría colgarle adjuntos a otro.
  const aTercero = await esperaError('un usuario NO puede registrar a nombre de otro', () =>
    como('authenticated', PROPIETARIO, () =>
      db.query(
        `select * from public.registrar_archivo_pendiente(
           '${TERCERO}', 'm5_archivos/ajeno/x.pdf', 'x.pdf', 'application/pdf', 'TEACHER_GUIDE', null)`,
      ),
    ),
  );
  check('registrar a nombre de otro sale como 42501', aTercero?.code === '42501', `código ${aTercero?.code}`);

  const adminRegistra = await como('authenticated', ADMIN_M5, () =>
    db.query(
      `select propietario_id from public.registrar_archivo_pendiente(
         '${TERCERO}', 'm5_archivos/en-nombre-de/def.pdf', 'guia.pdf', 'application/pdf', 'TEACHER_GUIDE', null)`,
    ),
  );
  check(
    'un admin SÍ puede registrar a nombre de otro',
    adminRegistra.rows[0]?.propietario_id === TERCERO,
    String(adminRegistra.rows[0]?.propietario_id),
  );

  // Confirmar: fija tamaño y sello temporal, y pasa a CONFIRMED.
  const conf = await como('authenticated', PROPIETARIO, () =>
    db.query(
      `select estado, tamano_bytes, confirmado_en from public.confirmar_archivo('${archivoId}', 123456)`,
    ),
  );
  const confirmado = conf.rows[0];
  check('confirmar fija tamano_bytes', confirmado?.tamano_bytes === 123456, String(confirmado?.tamano_bytes));
  check('confirmar fija confirmado_en', confirmado?.confirmado_en != null, String(confirmado?.confirmado_en));
  check('confirmar pasa a CONFIRMED', confirmado?.estado === 'CONFIRMED', String(confirmado?.estado));

  const reconfirmar = await esperaError('reconfirmar un CONFIRMED se rechaza (estado terminal)', () =>
    como('authenticated', PROPIETARIO, () =>
      db.query(`select * from public.confirmar_archivo('${archivoId}', 999)`),
    ),
  );
  check('reconfirmar sale como 23514', reconfirmar?.code === '23514', `código ${reconfirmar?.code}`);

  const confAjeno = await esperaError('no se puede confirmar un archivo ajeno', () =>
    como('authenticated', TERCERO, () =>
      db.query(`select * from public.confirmar_archivo('${archivoId}', 1)`),
    ),
  );
  check('confirmar un archivo ajeno sale como 42501', confAjeno?.code === '42501', `código ${confAjeno?.code}`);

  // Borrado lógico y su doble.
  const borrado = await como('authenticated', PROPIETARIO, () =>
    db.query(`select estado, deleted_at from public.marcar_archivo_borrado('${archivoId}')`),
  );
  check(
    'marcar_archivo_borrado hace soft delete (DELETED)',
    borrado.rows[0]?.estado === 'DELETED',
    String(borrado.rows[0]?.estado),
  );
  check('marcar_archivo_borrado fija deleted_at', borrado.rows[0]?.deleted_at != null);

  const dobleBorrado = await esperaError('borrar dos veces se rechaza', () =>
    como('authenticated', PROPIETARIO, () =>
      db.query(`select * from public.marcar_archivo_borrado('${archivoId}')`),
    ),
  );
  check('el doble borrado sale como 23514', dobleBorrado?.code === '23514', `código ${dobleBorrado?.code}`);

  // `anon` no puede ni llamar a las RPC: no tiene EXECUTE.
  const anonM5 = await esperaError('anon NO puede ejecutar las RPC de M5', () =>
    como('anon', null, () =>
      db.query(
        `select * from public.registrar_archivo_pendiente(
           '${PROPIETARIO}', 'm5_archivos/anon/x.pdf', 'x.pdf', 'application/pdf', 'TASK_SUBMISSION', null)`,
      ),
    ),
  );
  check('la llamada de anon se rechaza por privilegios (42501)', anonM5?.code === '42501', `código ${anonM5?.code}`);

  // ------------------------------------------------- 18.5 RLS de lectura
  const totalM5 = (await db.query('select count(*)::int as n from public.files_metadata')).rows[0].n;
  const totalPropias = (
    await db.query(
      `select count(*)::int as n from public.files_metadata where propietario_id='${PROPIETARIO}'`,
    )
  ).rows[0].n;

  const vePropias = await como('authenticated', PROPIETARIO, () =>
    db.query('select propietario_id from public.files_metadata'),
  );
  check(
    'el propietario ve SÓLO sus filas',
    vePropias.rows.length === totalPropias && vePropias.rows.every((r) => r.propietario_id === PROPIETARIO),
    `vio ${vePropias.rows.length} de ${totalM5}`,
  );

  const veAjenas = await como('authenticated', TERCERO, () =>
    db.query(
      `select count(*)::int as n from public.files_metadata where propietario_id='${PROPIETARIO}'`,
    ),
  );
  check('otro usuario NO ve las filas del propietario', veAjenas.rows[0].n === 0, `vio ${veAjenas.rows[0].n}`);

  const veAdminM5 = await como('authenticated', ADMIN_M5, () =>
    db.query('select count(*)::int as n from public.files_metadata'),
  );
  check('el admin ve TODAS las filas', veAdminM5.rows[0].n === totalM5, `vio ${veAdminM5.rows[0].n} de ${totalM5}`);

  // ------------------------------------------------- 18.6 escritura directa prohibida
  const insDirecto = await esperaError('un autenticado no puede INSERT directo en files_metadata', () =>
    como('authenticated', PROPIETARIO, () =>
      db.exec(
        `insert into public.files_metadata (propietario_id, r2_key, nombre_original, tipo_contenido, entity_type)
         values ('${PROPIETARIO}', 'm5_archivos/directo/x.pdf', 'x.pdf', 'application/pdf', 'TASK_SUBMISSION')`,
      ),
    ),
  );
  check(
    'el INSERT directo se rechaza por privilegios (42501)',
    insDirecto?.code === '42501',
    `código ${insDirecto?.code}`,
  );

  const updDirecto = await esperaError('un autenticado no puede UPDATE directo en files_metadata', () =>
    como('authenticated', PROPIETARIO, () =>
      db.exec(`update public.files_metadata set estado='CONFIRMED' where propietario_id='${PROPIETARIO}'`),
    ),
  );
  check(
    'el UPDATE directo se rechaza por privilegios (42501)',
    updDirecto?.code === '42501',
    `código ${updDirecto?.code}`,
  );

  const delDirecto = await esperaError('un autenticado no puede DELETE directo en files_metadata', () =>
    como('authenticated', PROPIETARIO, () =>
      db.exec(`delete from public.files_metadata where propietario_id='${PROPIETARIO}'`),
    ),
  );
  check(
    'el DELETE directo se rechaza por privilegios (42501)',
    delDirecto?.code === '42501',
    `código ${delDirecto?.code}`,
  );

  // ------------------------------------------------- 18.7 idempotencia
  // Reaplicar la migración entera no debe duplicar la semilla ni el estado del
  // módulo. La semilla usa `on conflict do nothing`; y la bandera de
  // `m5_archivos` NO se toca en esta migración, así que reaplicarla la deja
  // igual: **encendida**, porque quien la encendió es `202609210002`.
  //
  // El valor esperado cambió con el ciclo de la Capa 7, y el nuevo es el que
  // enseña algo: reaplicar una migración vieja **no puede deshacer** una
  // posterior. Si esto devolviera `false`, significaría que `202609210001`
  // escribe la bandera —y entonces el encendido de `202609210002` se perdería en
  // cada reaplicación, que es exactamente el fallo que el libro mayor existe
  // para evitar.
  const settingsAntesM5 = (await db.query('select count(*)::int as n from public.system_settings')).rows[0].n;
  const archivosAntesM5 = (await db.query('select count(*)::int as n from public.files_metadata')).rows[0].n;
  await aplicar(path.join(SUPABASE, 'migrations', '202609210001_mod5_archivos.sql'));
  const settingsDespuesM5 = (await db.query('select count(*)::int as n from public.system_settings')).rows[0].n;
  const archivosDespuesM5 = (await db.query('select count(*)::int as n from public.files_metadata')).rows[0].n;
  const m5Sigue = (
    await db.query("select habilitado from public.system_modules where clave='m5_archivos'")
  ).rows[0].habilitado;
  check(
    'reaplicar la migración de M5 NO duplica parámetros',
    settingsDespuesM5 === settingsAntesM5,
    `${settingsAntesM5} → ${settingsDespuesM5}`,
  );
  check(
    'reaplicar la migración de M5 NO duplica filas de archivos',
    archivosDespuesM5 === archivosAntesM5,
    `${archivosAntesM5} → ${archivosDespuesM5}`,
  );
  check(
    'reaplicar la migración de M5 deja el módulo ENCENDIDO (no lo apaga ni lo enciende)',
    m5Sigue === true,
  );

  // ==========================================================================
  // 19. Módulo 6 — Aula Virtual: RLS, RPCs y ciclo de calificación
  // ==========================================================================
  //  El «Google Classroom del INCES». No estrena una tabla de cursos: una
  //  `sections` de M3 YA es el curso, con su roster (M4) y sus docentes (M3).
  //  Nacen tres tablas (`m6_anuncios`, `m6_tareas`, `m6_entregas`) y ocho RPC.
  //
  //  Aquí se prueban tres cosas que no caben en ningún otro sitio, y por eso la
  //  sección existe:
  //    · el GRANT POR COLUMNA sobre `nota_borrador` — una política RLS es por
  //      FILA y no puede esconder una COLUMNA; sin el grant, el alumno leería su
  //      nota antes de que el docente la devuelva;
  //    · la publicación programada SIN planificador — la visibilidad se decide
  //      al LEER, no la escribe ningún job (no puede haberlo: cortes eléctricos);
  //    · las tres políticas nuevas sobre `files_metadata`, que cierran la mitad
  //      de D17 que M5 no podía expresar porque `entidad_id` no tenía tabla.
  seccion('19. Módulo 6 — Aula Virtual: RLS, RPCs y ciclo de calificación');

  // ------------------------------------------------- 19.1 fixtures
  // El docente que dicta el aula reutiliza DOC1. El «tercero» que no ve nada es
  // DOC2: es docente, pero NO dicta esta sección, así que distingue «no soy
  // docente» de «no soy docente DE ESTA sección» — que es la pregunta que hace
  // la autorización de M6.
  const DOC_M6 = DOC1;

  // UUIDs frescos: `enrollments` y `schedule_slots` tienen reglas de unicidad
  // que una reutilización haría saltar por el motivo equivocado.
  const MAT_M6 = 'f6000001-0000-4000-8000-000000000001';
  const SEC_M6 = 'f6000002-0000-4000-8000-000000000002';
  const ALU_M6A = 'f6000003-0000-4000-8000-000000000003'; // ENROLLED
  const ALU_M6B = 'f6000004-0000-4000-8000-000000000004'; // ENROLLED
  const ALU_M6W = 'f6000005-0000-4000-8000-000000000005'; // WAITLISTED
  const ALU_M6D = 'f6000006-0000-4000-8000-000000000006'; // DROPPED
  const ALU_M6X = 'f6000007-0000-4000-8000-000000000007'; // estudiante sin matrícula
  const SLOT_M6 = 'f6000008-0000-4000-8000-000000000008';

  await db.exec(
    `insert into public.subjects (id, code, name, academic_hours)
     values ('${MAT_M6}', 'M6-AV', 'Aula Virtual', 48)`,
  );
  await db.exec(
    `insert into public.sections (id, program_id, subject_id, period_code, name, max_capacity)
     values ('${SEC_M6}', '${PROG_ID}', '${MAT_M6}', '${PERIODO}', 'M6A', 30)`,
  );

  // `handle_new_user` crea el perfil al insertar en `auth.users`; por eso se
  // inserta ahí y se eleva el rol por SQL, como en todo el archivo. Insertar
  // además en `profiles` chocaría con la PK.
  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${ALU_M6A}', 'm6a@inces.test', '{"nombres":"Alba","apellidos":"Mora"}'::jsonb),
      ('${ALU_M6B}', 'm6b@inces.test', '{"nombres":"Beto","apellidos":"Nava"}'::jsonb),
      ('${ALU_M6W}', 'm6w@inces.test', '{"nombres":"Cira","apellidos":"Ortiz"}'::jsonb),
      ('${ALU_M6D}', 'm6d@inces.test', '{"nombres":"Dani","apellidos":"Paz"}'::jsonb),
      ('${ALU_M6X}', 'm6x@inces.test', '{"nombres":"Eva","apellidos":"Quiroz"}'::jsonb);
  `);

  // El roster mezcla estados A PROPÓSITO: publicar debe crear placeholders sólo
  // para ENROLLED. Un placeholder de un WAITLISTED o un DROPPED aparecería en el
  // libro como «faltante» de alguien que no cursa el aula.
  await db.exec(
    `insert into public.enrollments (student_id, section_id, status) values
       ('${ALU_M6A}', '${SEC_M6}', 'ENROLLED'),
       ('${ALU_M6B}', '${SEC_M6}', 'ENROLLED'),
       ('${ALU_M6W}', '${SEC_M6}', 'WAITLISTED'),
       ('${ALU_M6D}', '${SEC_M6}', 'DROPPED')`,
  );

  // La clase que convierte a DOC1 en docente DE ESTA sección: sin un
  // `schedule_slot` activo, `m6_dicta_seccion` es falso y todo el módulo se
  // cerraría. El día/bloque (5,5) no choca con ningún slot ni guardia previos.
  await db.exec(
    `insert into public.schedule_slots (id, section_id, teacher_id, classroom_id, day_of_week, block)
     values ('${SLOT_M6}', '${SEC_M6}', '${DOC_M6}', '${AULA_TALLER}', 5, 5)`,
  );

  const matriculadosM6 = (
    await db.query(
      `select count(*)::int as n from public.enrollments where section_id='${SEC_M6}' and status='ENROLLED'`,
    )
  ).rows[0].n;
  check(
    'la sección de M6 tiene 2 alumnos ENROLLED (y dos no-alumnos de control)',
    matriculadosM6 === 2,
    `hay ${matriculadosM6}`,
  );

  // ------------------------------------------------- 19.2 estructura y RLS
  const tablasM6 = (
    await db.query(
      "select tablename, rowsecurity from pg_tables where schemaname='public' " +
        "and tablename in ('m6_anuncios','m6_tareas','m6_entregas') order by tablename",
    )
  ).rows;
  check('existen las 3 tablas de M6', tablasM6.length === 3, `hay ${tablasM6.length}`);
  check('RLS activo en las 3 tablas de M6', tablasM6.every((t) => t.rowsecurity));

  // Los CHECK NOMBRADOS son el contrato que el backend cita al traducir un
  // 23514. Se comprueban por nombre porque un CHECK anónimo obligaría a leer el
  // mensaje crudo del motor para saber cuál saltó.
  const checksTareas = (
    await db.query(
      "select conname from pg_constraint where conrelid = 'public.m6_tareas'::regclass and contype = 'c'",
    )
  ).rows.map((r) => r.conname);
  check(
    'm6_tareas trae los 4 CHECK de coherencia por tipo y de programación',
    [
      'm6_tareas_material_sin_nota',
      'm6_tareas_material_sin_plazo',
      'm6_tareas_calificable_con_puntos',
      'm6_tareas_programado_coherente',
    ].every((c) => checksTareas.includes(c)),
    checksTareas.join(', '),
  );
  const checksAnuncios = (
    await db.query(
      "select conname from pg_constraint where conrelid = 'public.m6_anuncios'::regclass and contype = 'c'",
    )
  ).rows.map((r) => r.conname);
  check(
    'm6_anuncios exige coherencia de programación',
    checksAnuncios.includes('m6_anuncios_programado_coherente'),
    checksAnuncios.join(', '),
  );
  const checksEntregas = (
    await db.query(
      "select conname, contype from pg_constraint where conrelid = 'public.m6_entregas'::regclass",
    )
  ).rows;
  check(
    'm6_entregas exige un borrador antes de la nota asignada',
    checksEntregas.some((c) => c.conname === 'm6_entregas_nota_asignada_exige_borrador'),
  );
  // La unicidad (tarea, estudiante) es lo que hace IDEMPOTENTE a publicar: el
  // `on conflict do nothing` de la RPC no puede apoyarse en nada más.
  check(
    'm6_entregas tiene unique (tarea_id, estudiante_id)',
    checksEntregas.some((c) => c.conname === 'm6_entregas_una_por_alumno' && c.contype === 'u'),
    checksEntregas.map((c) => c.conname).join(', '),
  );

  // ------------------------------------- 19.3 el GRANT por columna (metadato)
  //  `nota_borrador` NO se protege con RLS —una política es por fila y no puede
  //  esconder una columna— sino con GRANT POR COLUMNA. Es la garantía de la
  //  decisión 3: el alumno no ve la nota hasta que el docente devuelve.
  const privM6 = (
    await db.query(
      "select " +
        "has_column_privilege('authenticated','public.m6_entregas','nota_borrador','SELECT') as nb, " +
        "has_column_privilege('authenticated','public.m6_entregas','nota_asignada','SELECT') as na, " +
        "has_column_privilege('authenticated','public.m6_entregas','estado','SELECT') as est, " +
        "has_table_privilege('authenticated','public.m6_entregas','SELECT') as ts, " +
        "has_table_privilege('authenticated','public.m6_anuncios','SELECT') as ta, " +
        "has_table_privilege('authenticated','public.m6_tareas','SELECT') as tt",
    )
  ).rows[0];
  check('authenticated NO tiene privilegio de columna sobre nota_borrador', privM6.nb === false);
  check('authenticated SÍ puede leer nota_asignada (la ve al devolverse)', privM6.na === true);
  check('authenticated SÍ puede leer estado', privM6.est === true);
  // `has_table_privilege(...,'SELECT')` es FALSO aunque el SELECT funcione: el
  // privilegio es por columna, no por tabla. Es la señal de que el GRANT está
  // bien hecho; si fuera `true`, la columna protegida viajaría en cualquier
  // `select *`.
  check(
    'el SELECT de m6_entregas es por columna, no por tabla (has_table_privilege=false)',
    privM6.ts === false,
  );
  check('anuncios y tareas sí son SELECT de tabla completa', privM6.ta === true && privM6.tt === true);

  const escrituraM6 = (
    await db.query(
      "select " +
        "has_table_privilege('authenticated','public.m6_anuncios','INSERT') as ai, " +
        "has_table_privilege('authenticated','public.m6_anuncios','UPDATE') as au, " +
        "has_table_privilege('authenticated','public.m6_anuncios','DELETE') as ad, " +
        "has_table_privilege('authenticated','public.m6_tareas','INSERT') as ti, " +
        "has_table_privilege('authenticated','public.m6_tareas','UPDATE') as tu, " +
        "has_table_privilege('authenticated','public.m6_tareas','DELETE') as td, " +
        "has_table_privilege('authenticated','public.m6_entregas','INSERT') as ei, " +
        "has_table_privilege('authenticated','public.m6_entregas','UPDATE') as eu, " +
        "has_table_privilege('authenticated','public.m6_entregas','DELETE') as ed",
    )
  ).rows[0];
  check(
    'authenticated no tiene INSERT/UPDATE/DELETE directo en ninguna tabla de M6',
    Object.values(escrituraM6).every((v) => v === false),
    JSON.stringify(escrituraM6),
  );

  // ------------------------------------------------- 19.4 el ciclo por RPC
  const TAREA1 = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','Tarea 1','Primera tarea')`),
    )
  ).rows[0];
  check('m6_crear_tarea nace en BORRADOR', TAREA1.estado === 'BORRADOR', String(TAREA1.estado));
  check('un borrador no tiene fecha de publicación', TAREA1.publicado_en === null);
  // `numeric` vuelve como texto en el driver (`"20.00"`), no como número: la
  // coerción es del test, no del contrato.
  check('los puntos por defecto son 20', Number(TAREA1.puntos_maximos) === 20, String(TAREA1.puntos_maximos));
  check('el tipo por defecto es TAREA', TAREA1.tipo === 'TAREA', String(TAREA1.tipo));

  const crearComoAlumno = await esperaError('un alumno NO puede crear tareas', () =>
    como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','X','X')`),
    ),
  );
  check(
    'crear tarea como alumno sale 42501',
    crearComoAlumno?.code === '42501',
    `código ${crearComoAlumno?.code}`,
  );

  // Autorización por SECCIÓN, no por rol: ser docente no basta, hay que dictar
  // ESTA sección. SEC_M3B la dicta DOC2, así que DOC1 rebota.
  const crearAjeno = await esperaError('un docente NO crea tareas en una sección que no dicta', () =>
    como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M3B}','X','X')`),
    ),
  );
  check('crear en sección ajena sale 42501', crearAjeno?.code === '42501', `código ${crearAjeno?.code}`);

  // MATERIAL con puntos: la RPC lo rechaza como error de NEGOCIO (23514 con
  // mensaje legible), no dejando que salte el CHECK crudo.
  const materialConPuntos = await esperaError('un MATERIAL no puede llevar puntos', () =>
    como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','Material','', 'MATERIAL', 5)`),
    ),
  );
  check(
    'MATERIAL con puntos sale 23514',
    materialConPuntos?.code === '23514',
    `código ${materialConPuntos?.code}`,
  );
  check(
    'el mensaje explica la regla, no cita un CHECK',
    /MATERIAL/.test(materialConPuntos?.message ?? '') && !/constraint/i.test(materialConPuntos?.message ?? ''),
    materialConPuntos?.message,
  );

  // REGRESIÓN que la sección 19 cazó: omitir `puntos_maximos` al crear un
  // MATERIAL debe FUNCIONAR. Antes fallaba con 23514 porque el argumento tenía
  // `default 20` y la comprobación de MATERIAL lo leía como «un material con
  // puntos»: la llamada natural —un material no se califica, así que no se le
  // pasan puntos— era justo la que rompía, y el error aparecía lejos de su
  // causa. Se corrigió el default a `null` («no me lo dijeron» ≠ «me dijeron
  // 20»). Esta aserción es la que lo habría cazado; no enshrinar el 23514 fue
  // lo que permitió arreglar la raíz en vez de documentar el rodeo.
  const materialSinPuntos = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','Lectura','', 'MATERIAL')`),
    )
  ).rows[0];
  check(
    'un MATERIAL SIN pasar puntos se crea (regresión del default 20)',
    materialSinPuntos?.tipo === 'MATERIAL' && Number(materialSinPuntos?.puntos_maximos) === 0,
    String(materialSinPuntos?.puntos_maximos),
  );
  check('ese MATERIAL nace sin fecha límite', materialSinPuntos?.fecha_limite === null);

  // El mismo MATERIAL con una fecha límite explícita sí contradice su
  // naturaleza: el guard sigue guardando.
  const materialConPlazo = await esperaError('un MATERIAL no puede llevar fecha límite', () =>
    como('authenticated', DOC_M6, () =>
      db.query(
        `select * from public.m6_crear_tarea('${SEC_M6}','Lectura 2','', 'MATERIAL', null, now() + interval '1 day')`,
      ),
    ),
  );
  check(
    'MATERIAL con fecha límite sale 23514',
    materialConPlazo?.code === '23514',
    `código ${materialConPlazo?.code}`,
  );

  // El default de negocio sigue aplicándose DONDE debe: lo calificable vale 20.
  const tareaSinPuntos = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','Tarea sin puntos','')`),
    )
  ).rows[0];
  check(
    'una TAREA sin pasar puntos toma el default de negocio (20)',
    tareaSinPuntos?.tipo === 'TAREA' && Number(tareaSinPuntos?.puntos_maximos) === 20,
    String(tareaSinPuntos?.puntos_maximos),
  );

  // Los dos límites de lo calificable, como error de NEGOCIO: si el mensaje
  // nombrara `m6_tareas_calificable_con_puntos`, la pre-comprobación no estaría
  // disparando y el 400 saldría con el texto crudo del motor.
  const tareaCero = await esperaError('una tarea calificable no puede valer 0', () =>
    como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','T','', 'TAREA', 0)`),
    ),
  );
  check('TAREA con 0 puntos sale 23514', tareaCero?.code === '23514', `código ${tareaCero?.code}`);
  check(
    'el mensaje nombra la regla («más de 0 puntos»), no la restricción',
    /más de 0 puntos/.test(tareaCero?.message ?? '') && !/constraint/i.test(tareaCero?.message ?? ''),
    tareaCero?.message,
  );

  const tareaExcede = await esperaError('una tarea no puede valer más de 20', () =>
    como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','T','', 'TAREA', 21)`),
    ),
  );
  check('TAREA con 21 puntos sale 23514', tareaExcede?.code === '23514', `código ${tareaExcede?.code}`);
  check(
    'el mensaje de la nota máxima es legible, no una violación de CHECK',
    /superar 20/.test(tareaExcede?.message ?? '') && !/constraint/i.test(tareaExcede?.message ?? ''),
    tareaExcede?.message,
  );

  // El caso válido, para que el CHECK no sea «rechaza todo»: MATERIAL con 0.
  const MATERIAL1 = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_tarea('${SEC_M6}','Material de apoyo','', 'MATERIAL', 0)`),
    )
  ).rows[0];
  check(
    'un MATERIAL con 0 puntos sí se crea',
    MATERIAL1.tipo === 'MATERIAL' && Number(MATERIAL1.puntos_maximos) === 0,
  );
  check('un MATERIAL no lleva fecha límite', MATERIAL1.fecha_limite === null);
  check('el MATERIAL nace BORRADOR (aún no lo ve el alumno)', MATERIAL1.estado === 'BORRADOR');

  // TAREA2 con fecha límite VENCIDA: es la que permite probar «tardía» (4.2) y
  // «faltante» (4.3) sin viajar en el tiempo.
  const TAREA2 = (
    await como('authenticated', DOC_M6, () =>
      db.query(
        `select * from public.m6_crear_tarea('${SEC_M6}','Tarea 2','Con plazo', 'TAREA', 10, now() - interval '2 days')`,
      ),
    )
  ).rows[0];
  check('la tarea con plazo guarda 10 puntos', Number(TAREA2.puntos_maximos) === 10);
  check('la tarea con plazo nace BORRADOR', TAREA2.estado === 'BORRADOR');

  // --- publicar: crea los placeholders de cada matrícula ENROLLED ---
  const entregasAntes = (
    await db.query(`select count(*)::int as n from public.m6_entregas where tarea_id='${TAREA1.id}'`)
  ).rows[0].n;
  check('antes de publicar NO hay ninguna entrega', entregasAntes === 0, `hay ${entregasAntes}`);

  const publicada = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_publicar_tarea('${TAREA1.id}')`),
    )
  ).rows[0];
  check('publicar deja la tarea en PUBLICADO', publicada.estado === 'PUBLICADO', String(publicada.estado));
  check('publicar fija publicado_en', publicada.publicado_en != null);
  check(
    'publicar devuelve el número de placeholders creados',
    Number(publicada.entregas) === 2,
    String(publicada.entregas),
  );

  const entregasT1 = (
    await db.query(
      `select estudiante_id from public.m6_entregas where tarea_id='${TAREA1.id}' order by estudiante_id`,
    )
  ).rows;
  check(
    'se crea EXACTAMENTE una entrega por alumno ENROLLED',
    entregasT1.length === matriculadosM6 && entregasT1.length === 2,
    `hay ${entregasT1.length}`,
  );
  check(
    'los placeholders son de los dos ENROLLED',
    entregasT1
      .map((r) => r.estudiante_id)
      .sort()
      .join(',') === [ALU_M6A, ALU_M6B].sort().join(','),
  );
  const sinPlaceholder = (
    await db.query(
      `select count(*)::int as n from public.m6_entregas where tarea_id='${TAREA1.id}' and estudiante_id in ('${ALU_M6W}','${ALU_M6D}')`,
    )
  ).rows[0].n;
  check('WAITLISTED y DROPPED NO reciben placeholder', sinPlaceholder === 0, `hay ${sinPlaceholder}`);

  // IDEMPOTENCIA: es la garantía que hace seguro un botón que se pulsa dos
  // veces. Sin ella, republicar duplicaría entregas por alumno.
  const publicada2 = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_publicar_tarea('${TAREA1.id}')`),
    )
  ).rows[0];
  const entregasT1bis = (
    await db.query(`select count(*)::int as n from public.m6_entregas where tarea_id='${TAREA1.id}'`)
  ).rows[0].n;
  check('republicar NO duplica entregas (idempotencia)', entregasT1bis === 2, `hay ${entregasT1bis}`);
  check(
    'republicar reporta las entregas ya existentes',
    Number(publicada2.entregas) === 2,
    String(publicada2.entregas),
  );

  // Y la barrera de verdad, la del motor: el `on conflict do nothing` se apoya
  // en la `unique`; sin ella no habría nada que absorbiera el duplicado.
  const duplicadoEntrega = await esperaError('el motor rechaza una entrega duplicada', () =>
    db.exec(
      `insert into public.m6_entregas (tarea_id, estudiante_id) values ('${TAREA1.id}','${ALU_M6A}')`,
    ),
  );
  check(
    'el duplicado de entrega sale 23505 (unique_violation)',
    duplicadoEntrega?.code === '23505',
    `código ${duplicadoEntrega?.code}`,
  );

  // --- el GRANT por columna, EN EJECUCIÓN y con filas (el metadato está en 19.3) ---
  // La prueba de fuego que pide el diseño: un `select` como alumno sobre la
  // columna protegida debe FALLAR por privilegios (42501), no devolver NULL. Un
  // NULL silencioso sería peor: parecería «sin nota».
  const verNotaBorrador = await esperaError('un alumno NO puede leer nota_borrador', () =>
    como('authenticated', ALU_M6A, () => db.query('select nota_borrador from public.m6_entregas')),
  );
  check(
    'la lectura de nota_borrador por el alumno es 42501',
    verNotaBorrador?.code === '42501',
    `código ${verNotaBorrador?.code}`,
  );
  // `select *` es el error natural del repositorio: expande la columna
  // protegida y falla. La migración lo advierte; aquí queda demostrado.
  const verAsterisco = await esperaError('un alumno NO puede hacer select * en m6_entregas', () =>
    como('authenticated', ALU_M6A, () => db.query('select * from public.m6_entregas')),
  );
  check(
    'el select * del alumno es 42501',
    verAsterisco?.code === '42501',
    `código ${verAsterisco?.code}`,
  );
  // Pero la lista CONCEDIDA sí debe funcionar: si no, la frontera sería una
  // pared y el alumno no podría ver ni sus propias entregas.
  const columnasConcedidas = await como('authenticated', ALU_M6A, () =>
    db.query(
      'select id, tarea_id, estudiante_id, estado, es_tardia, nota_asignada, entregada_en from public.m6_entregas',
    ),
  );
  check(
    'el alumno SÍ lee las columnas concedidas y sólo SUS filas',
    columnasConcedidas.rows.length >= 1 &&
      columnasConcedidas.rows.every((r) => r.estudiante_id === ALU_M6A),
    `${columnasConcedidas.rows.length} filas`,
  );

  const e1 = (
    await db.query(
      `select id from public.m6_entregas where tarea_id='${TAREA1.id}' and estudiante_id='${ALU_M6A}'`,
    )
  ).rows[0].id;
  const e2 = (
    await db.query(
      `select id from public.m6_entregas where tarea_id='${TAREA1.id}' and estudiante_id='${ALU_M6B}'`,
    )
  ).rows[0].id;

  await como('authenticated', DOC_M6, () =>
    db.query(`select * from public.m6_publicar_tarea('${TAREA2.id}')`),
  );
  const entregasT2 = (
    await db.query(`select count(*)::int as n from public.m6_entregas where tarea_id='${TAREA2.id}'`)
  ).rows[0].n;
  check('publicar TAREA2 también crea 2 placeholders', entregasT2 === 2, `hay ${entregasT2}`);
  const eT2A = (
    await db.query(
      `select id from public.m6_entregas where tarea_id='${TAREA2.id}' and estudiante_id='${ALU_M6A}'`,
    )
  ).rows[0].id;

  // Entregar con plazo VENCIDO y `permitir_entrega_tardia=true`: se admite y
  // `es_tardia` se ESCRIBE al entregar (4.2), no lo calcula ningún job.
  const entregaTardia = (
    await como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_entregar_tarea('${eT2A}')`),
    )
  ).rows[0];
  check('entregar tras el plazo marca es_tardia', entregaTardia.es_tardia === true);
  check(
    'la entrega tardía queda ENTREGADA',
    entregaTardia.estado === 'ENTREGADA',
    String(entregaTardia.estado),
  );

  // --- entregar / reclamar ---
  const entregada = (
    await como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_entregar_tarea('${e1}')`),
    )
  ).rows[0];
  check('el alumno dueño entrega su tarea', entregada.estado === 'ENTREGADA', String(entregada.estado));
  check('entregar fija entregada_en', entregada.entregada_en != null);
  // Sin fecha límite, nunca es tardía (4.2).
  check('sin plazo, la entrega NO es tardía', entregada.es_tardia === false);

  const entregaAjena = await esperaError('un alumno NO entrega la tarea de otro', () =>
    como('authenticated', ALU_M6B, () => db.query(`select * from public.m6_entregar_tarea('${e1}')`)),
  );
  check('entregar la ajena sale 42501', entregaAjena?.code === '42501', `código ${entregaAjena?.code}`);

  // MODIFIABLE_UNTIL_TURNED_IN (el defecto de Google): una vez entregada, no se
  // vuelve a entregar sin reclamar. Es el 23514 que abre la válvula `reclamar`.
  const entregaDoble = await esperaError('no se entrega dos veces sin reclamar', () =>
    como('authenticated', ALU_M6A, () => db.query(`select * from public.m6_entregar_tarea('${e1}')`)),
  );
  check('la segunda entrega sale 23514', entregaDoble?.code === '23514', `código ${entregaDoble?.code}`);

  const reclamada = (
    await como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_reclamar_entrega('${e1}')`),
    )
  ).rows[0];
  check('reclamar deja la entrega en RECLAMADA', reclamada.estado === 'RECLAMADA', String(reclamada.estado));

  const reEntregada = (
    await como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_entregar_tarea('${e1}')`),
    )
  ).rows[0];
  check(
    'tras reclamar, SÍ se puede volver a entregar',
    reEntregada.estado === 'ENTREGADA',
    String(reEntregada.estado),
  );

  const reclamarAsignada = await esperaError('no se reclama lo que nunca se entregó', () =>
    como('authenticated', ALU_M6B, () => db.query(`select * from public.m6_reclamar_entrega('${e2}')`)),
  );
  check(
    'reclamar una ASIGNADA sale 23514',
    reclamarAsignada?.code === '23514',
    `código ${reclamarAsignada?.code}`,
  );

  // --- calificar / devolver ---
  const calificada = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_calificar_entrega('${e1}', 15)`),
    )
  ).rows[0];
  check(
    'calificar escribe la nota BORRADOR',
    Number(calificada.nota_borrador) === 15,
    String(calificada.nota_borrador),
  );
  // La nota asignada sigue vacía: el alumno todavía no ve nada. Escribirla aquí
  // sería saltarse el paso de devolución.
  check(
    'calificar NO asigna la nota todavía',
    calificada.nota_asignada === null,
    String(calificada.nota_asignada),
  );

  const nota21 = await esperaError('una nota de 21 se rechaza', () =>
    como('authenticated', DOC_M6, () => db.query(`select * from public.m6_calificar_entrega('${e1}', 21)`)),
  );
  check('la nota 21 sale 23514', nota21?.code === '23514', `código ${nota21?.code}`);
  const notaNeg = await esperaError('una nota negativa se rechaza', () =>
    como('authenticated', DOC_M6, () => db.query(`select * from public.m6_calificar_entrega('${e1}', -1)`)),
  );
  check('la nota -1 sale 23514', notaNeg?.code === '23514', `código ${notaNeg?.code}`);
  // Por encima del máximo DE LA TAREA (10), aunque dentro del 0..20 global.
  const notaExcede = await esperaError('la nota no puede superar los puntos de la tarea', () =>
    como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_calificar_entrega('${eT2A}', 11)`),
    ),
  );
  check('la nota por encima del máximo sale 23514', notaExcede?.code === '23514', `código ${notaExcede?.code}`);

  const calificarVacia = await esperaError('no se califica un placeholder vacío', () =>
    como('authenticated', DOC_M6, () => db.query(`select * from public.m6_calificar_entrega('${e2}', 5)`)),
  );
  check(
    'calificar una ASIGNADA sale 23514',
    calificarVacia?.code === '23514',
    `código ${calificarVacia?.code}`,
  );

  const calificarAlumno = await esperaError('un alumno NO califica', () =>
    como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_calificar_entrega('${e1}', 5)`),
    ),
  );
  check(
    'calificar como alumno sale 42501',
    calificarAlumno?.code === '42501',
    `código ${calificarAlumno?.code}`,
  );

  const devuelta = (
    await como('authenticated', DOC_M6, () => db.query(`select * from public.m6_devolver_entrega('${e1}')`))
  ).rows[0];
  check('devolver deja la entrega en DEVUELTA', devuelta.estado === 'DEVUELTA', String(devuelta.estado));
  // La devolución COPIA el borrador a la nota asignada: es el único momento en
  // que el alumno ve una nota.
  check(
    'devolver copia el borrador a la nota asignada',
    devuelta.nota_asignada === devuelta.nota_borrador && Number(devuelta.nota_asignada) === 15,
    `${devuelta.nota_borrador} -> ${devuelta.nota_asignada}`,
  );
  check('devolver fija devuelta_en', devuelta.devuelta_en != null);

  const entregarTrasDevolver = await esperaError('una entrega devuelta no se reabre', () =>
    como('authenticated', ALU_M6A, () => db.query(`select * from public.m6_entregar_tarea('${e1}')`)),
  );
  check(
    'entregar tras DEVUELTA sale 23514',
    entregarTrasDevolver?.code === '23514',
    `código ${entregarTrasDevolver?.code}`,
  );

  // --- el libro del docente: `nota_borrador` y el «faltante» DERIVADO ---
  const libroT2 = await como('authenticated', DOC_M6, () =>
    db.query(`select * from public.m6_entregas_de_tarea('${TAREA2.id}')`),
  );
  const filaA = libroT2.rows.find((r) => r.estudiante_id === ALU_M6A);
  const filaB = libroT2.rows.find((r) => r.estudiante_id === ALU_M6B);
  check('el libro del docente trae una fila por alumno', libroT2.rows.length === 2, `${libroT2.rows.length}`);
  check(
    'el docente recibe la nota_borrador que el GRANT le esconde a authenticated',
    filaA !== undefined && 'nota_borrador' in filaA,
  );
  // 4.3: «faltante» se DERIVA al leer (ASIGNADA + plazo vencido), no se escribe.
  check('quien entregó NO aparece como faltante', filaA?.faltante === false, String(filaA?.faltante));
  check(
    'quien no entregó y venció el plazo SÍ aparece como faltante',
    filaB?.faltante === true,
    String(filaB?.faltante),
  );
  // La prueba de la decisión 4.3: el sistema NO auto-escribió un 0. Si lo
  // hubiera hecho, `nota_borrador` no sería NULL y el alumno quedaría congelado
  // con un cero que nadie puso.
  check(
    'el sistema NO escribió un 0 implícito en el faltante (nota_borrador sigue NULL)',
    filaB?.nota_borrador === null,
    String(filaB?.nota_borrador),
  );

  const libroAlumno = await como('authenticated', ALU_M6A, () =>
    db.query(`select * from public.m6_entregas_de_tarea('${TAREA2.id}')`),
  );
  check(
    'el libro del docente NO devuelve filas a un alumno',
    libroAlumno.rows.length === 0,
    `${libroAlumno.rows.length} filas`,
  );

  // ------------------------------------------------- 19.5 RLS de lectura
  const verTarea = (sub, id) =>
    como('authenticated', sub, () => db.query(`select id from public.m6_tareas where id = '${id}'`));

  // El docente ve su borrador; el alumno no. Es la razón de existir del estado
  // BORRADOR: se prepara sin publicar.
  check('el docente ve su propio BORRADOR', (await verTarea(DOC_M6, MATERIAL1.id)).rows.length === 1);
  check('el alumno NO ve el BORRADOR', (await verTarea(ALU_M6A, MATERIAL1.id)).rows.length === 0);
  check('tras publicar, el alumno SÍ ve la tarea', (await verTarea(ALU_M6A, TAREA1.id)).rows.length === 1);
  check(
    'un alumno no matriculado no ve ninguna tarea',
    (await como('authenticated', ALU_M6X, () => db.query('select count(*)::int as n from public.m6_tareas')))
      .rows[0].n === 0,
  );
  // DOC2 es docente, pero no dicta ESTA sección: no ve el aula ajena. Distingue
  // «no ser docente» de «no ser docente de esta sección».
  check(
    'un docente que no dicta la sección no ve el aula',
    (await como('authenticated', DOC2, () => db.query('select count(*)::int as n from public.m6_tareas')))
      .rows[0].n === 0,
  );

  // --- decisión 4.1: publicación programada SIN planificador ---
  // No hay job, ni cron, ni función que se llame entre el UPDATE y el SELECT.
  // La política de lectura compara `programado_para <= now()` y el resultado es
  // el mismo que si un proceso hubiera publicado. El UPDATE es SQL directo del
  // superusuario, para que quede claro que NADIE más actúa.
  await db.exec(
    `update public.m6_tareas set estado='BORRADOR', programado_para = now() - interval '1 hour' where id='${MATERIAL1.id}'`,
  );
  check(
    'una tarea programada a pasado es visible para el alumno SIN que ningún job la publique',
    (await verTarea(ALU_M6A, MATERIAL1.id)).rows.length === 1,
  );
  await db.exec(
    `update public.m6_tareas set programado_para = now() + interval '1 hour' where id='${MATERIAL1.id}'`,
  );
  check(
    'una tarea programada a futuro sigue oculta al alumno',
    (await verTarea(ALU_M6A, MATERIAL1.id)).rows.length === 0,
  );
  check('el docente ve el borrador programado en ambos sentidos', (await verTarea(DOC_M6, MATERIAL1.id)).rows.length === 1);

  // --- el tablón: mismas dos reglas ---
  const ANUNCIO1 = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_anuncio('${SEC_M6}','Aviso 1','Contenido')`),
    )
  ).rows[0];
  check(
    'el anuncio nace BORRADOR y sin publicar',
    ANUNCIO1.estado === 'BORRADOR' && ANUNCIO1.publicado_en === null,
  );

  const anuncioAlumno = await esperaError('un alumno NO publica en el tablón', () =>
    como('authenticated', ALU_M6A, () =>
      db.query(`select * from public.m6_crear_anuncio('${SEC_M6}','X','X')`),
    ),
  );
  check(
    'crear anuncio como alumno sale 42501',
    anuncioAlumno?.code === '42501',
    `código ${anuncioAlumno?.code}`,
  );

  const verAnuncio = (sub) =>
    como('authenticated', sub, () => db.query(`select id from public.m6_anuncios where id = '${ANUNCIO1.id}'`));
  check('el alumno NO ve el anuncio en BORRADOR', (await verAnuncio(ALU_M6A)).rows.length === 0);
  await db.exec(
    `update public.m6_anuncios set programado_para = now() - interval '1 hour' where id='${ANUNCIO1.id}'`,
  );
  check(
    'el anuncio programado a pasado es visible SIN planificador',
    (await verAnuncio(ALU_M6A)).rows.length === 1,
  );
  await db.exec(
    `update public.m6_anuncios set programado_para = now() + interval '1 hour' where id='${ANUNCIO1.id}'`,
  );
  check('el anuncio programado a futuro sigue oculto', (await verAnuncio(ALU_M6A)).rows.length === 0);

  // Un anuncio programado conserva su fecha: `programado_para` es la promesa.
  const ANUNCIO2 = (
    await como('authenticated', DOC_M6, () =>
      db.query(`select * from public.m6_crear_anuncio('${SEC_M6}','Aviso 2','', now() + interval '1 day')`),
    )
  ).rows[0];
  check(
    'un anuncio programado conserva su fecha y sigue en BORRADOR',
    ANUNCIO2.programado_para != null && ANUNCIO2.estado === 'BORRADOR',
  );

  // --------------------------------- 19.6 las 3 políticas nuevas de archivos
  //  Cierran la mitad de D17 que M5 no podía expresar: `files_metadata.entidad_id`
  //  no tenía tabla que lo respaldara. M6 se la da (`m6_tareas` / `m6_entregas`)
  //  y añade tres políticas de lectura ADITIVAS sobre la tabla de M5 —que no se
  //  edita—. PostgreSQL combina los SELECT con OR: ninguna de M5 se debilita.
  const veArchivo = (sub, id) =>
    como('authenticated', sub, () =>
      db.query(`select count(*)::int as n from public.files_metadata where id = '${id}'`),
    );

  // (a) El docente sube una guía de SU tarea publicada.
  const guiaT1 = (
    await como('authenticated', DOC_M6, () =>
      db.query(
        `select id from public.registrar_archivo_pendiente('${DOC_M6}','m6/guias/t1.pdf','guia-t1.pdf','application/pdf','TEACHER_GUIDE','${TAREA1.id}')`,
      ),
    )
  ).rows[0];
  check('el docente registra una guía de su tarea (el trigger la acepta)', Boolean(guiaT1?.id));

  // (b) Guía colgada de un BORRADOR: el alumno no la ve hasta que se publique.
  // Se limpia `programado_para` para que el borrador no sea «programado a pasado».
  await db.exec(`update public.m6_tareas set programado_para = null where id='${MATERIAL1.id}'`);
  const guiaBorrador = (
    await como('authenticated', DOC_M6, () =>
      db.query(
        `select id from public.registrar_archivo_pendiente('${DOC_M6}','m6/guias/borrador.pdf','guia-borrador.pdf','application/pdf','TEACHER_GUIDE','${MATERIAL1.id}')`,
      ),
    )
  ).rows[0];

  check(
    'el alumno matriculado VE la guía de una tarea publicada',
    (await veArchivo(ALU_M6A, guiaT1.id)).rows[0].n === 1,
  );
  check(
    'el alumno NO ve la guía de una tarea en BORRADOR',
    (await veArchivo(ALU_M6A, guiaBorrador.id)).rows[0].n === 0,
  );
  check(
    'un alumno no matriculado tampoco ve la guía publicada',
    (await veArchivo(ALU_M6X, guiaT1.id)).rows[0].n === 0,
  );

  // (c) LA ASERCIÓN QUE CIERRA D17: el alumno sube su entrega y el DOCENTE la ve,
  // aunque el archivo NO sea suyo. Antes de M6 era imposible: no había unión
  // entre `entidad_id` y ninguna tabla.
  const entregaFile = (
    await como('authenticated', ALU_M6A, () =>
      db.query(
        `select id from public.registrar_archivo_pendiente('${ALU_M6A}','m6/entregas/a1.pdf','entrega.pdf','application/pdf','TASK_SUBMISSION','${e1}')`,
      ),
    )
  ).rows[0];
  check('el alumno registra su entrega', Boolean(entregaFile?.id));
  check(
    'EL DOCENTE VE LA ENTREGA DE SU ALUMNO (política files_metadata_docente_entrega)',
    (await veArchivo(DOC_M6, entregaFile.id)).rows[0].n === 1,
  );
  check('otro alumno NO ve la entrega ajena', (await veArchivo(ALU_M6B, entregaFile.id)).rows[0].n === 0);
  check(
    'un alumno no matriculado tampoco ve la entrega ajena',
    (await veArchivo(ALU_M6X, entregaFile.id)).rows[0].n === 0,
  );
  // M5 sigue valiendo: el dueño ve lo suyo. Las nuevas políticas son aditivas.
  check(
    'el dueño sigue viendo su propio archivo (M5 intacta, políticas aditivas)',
    (await veArchivo(ALU_M6A, entregaFile.id)).rows[0].n === 1,
  );

  // ----------------------------- 19.7 trigger de integridad de `entidad_id`
  //  PARTE 7.1: M6 da sentido a `entidad_id`, así que M6 impide que apunte a
  //  cualquier cosa. Sin esto, un alumno colgaría un archivo de la entrega de
  //  OTRO compañero y al docente le aparecería material ajeno.
  const ajeno = await esperaError('no se ata un archivo a la entrega de otro', () =>
    como('authenticated', ALU_M6B, () =>
      db.query(
        `select id from public.registrar_archivo_pendiente('${ALU_M6B}','m6/x/ajena.pdf','x.pdf','application/pdf','TASK_SUBMISSION','${e1}')`,
      ),
    ),
  );
  check('atarse a la entrega ajena sale 23503', ajeno?.code === '23503', `código ${ajeno?.code}`);

  const inexistente = await esperaError('no se ata un archivo a una entidad inexistente', () =>
    como('authenticated', ALU_M6A, () =>
      db.query(
        `select id from public.registrar_archivo_pendiente('${ALU_M6A}','m6/x/nada.pdf','x.pdf','application/pdf','TASK_SUBMISSION','00000000-0000-4000-8000-0000000000ff')`,
      ),
    ),
  );
  check('la entidad inexistente sale 23503', inexistente?.code === '23503', `código ${inexistente?.code}`);

  const guiaAjena = await esperaError('un alumno no cuelga una guía en una tarea que no dicta', () =>
    como('authenticated', ALU_M6A, () =>
      db.query(
        `select id from public.registrar_archivo_pendiente('${ALU_M6A}','m6/x/guia.pdf','x.pdf','application/pdf','TEACHER_GUIDE','${TAREA1.id}')`,
      ),
    ),
  );
  check('la guía en tarea ajena sale 23503', guiaAjena?.code === '23503', `código ${guiaAjena?.code}`);

  // `entidad_id` NULL sigue permitido: M5 lo admite a propósito (la entidad
  // puede crearse después) y la UI sube material de apoyo sin atarlo todavía.
  const sinEntidad = await como('authenticated', ALU_M6A, () =>
    db.query(
      `select id from public.registrar_archivo_pendiente('${ALU_M6A}','m6/x/suelto.pdf','x.pdf','application/pdf','TASK_SUBMISSION',null)`,
    ),
  );
  check('entidad_id NULL sigue permitido (M5 lo admite)', Boolean(sinEntidad.rows[0]?.id));

  // El caso válido que prueba que el trigger no rechaza todo: una guía de una
  // tarea que el docente SÍ dicta.
  const guiaValida = await como('authenticated', DOC_M6, () =>
    db.query(
      `select id from public.registrar_archivo_pendiente('${DOC_M6}','m6/guias/t2.pdf','guia-t2.pdf','application/pdf','TEACHER_GUIDE','${TAREA2.id}')`,
    ),
  );
  check('una guía válida del docente se acepta (el trigger no rechaza todo)', Boolean(guiaValida.rows[0]?.id));

  // ----------------------------------------------- 19.8 semilla del módulo
  //  La sección 2 ya fija clave, orden y bandera. Aquí sólo lo que le es propio
  //  a M6 —nombre, icono y categoría—, que no se comprueba en ningún otro sitio.
  const moduloM6 = (
    await db.query(
      "select nombre, icono, categoria from public.system_modules where clave='m6_aula_virtual'",
    )
  ).rows[0];
  check('el módulo se llama «Aula Virtual»', moduloM6?.nombre === 'Aula Virtual', String(moduloM6?.nombre));
  check('el módulo usa el icono school', moduloM6?.icono === 'school', String(moduloM6?.icono));
  check('el módulo es de categoría academico', moduloM6?.categoria === 'academico', String(moduloM6?.categoria));

  // ------------------------------- 20. Catálogo de inscripción (202609240001)
  seccion('20. Catálogo de inscripción y datos_planilla (202609240001)');

  // --- la semilla del catálogo
  const campos = (
    await db.query('select codigo, obligatorio, tipo from public.inscripcion_campos')
  ).rows;
  const obligatorios = campos.filter((c) => c.obligatorio);
  check('el catálogo sembró los campos de la planilla física', campos.length >= 40, `hay ${campos.length}`);
  check(
    'hay campos obligatorios: sin ellos validar_planilla() pasaría siempre',
    obligatorios.length > 0,
    `hay ${obligatorios.length}`,
  );
  check(
    'ningún código rompe el formato exigido',
    (
      await db.query(
        "select count(*)::int as n from public.inscripcion_campos where codigo !~ '^[a-z][a-z0-9_]*$'",
      )
    ).rows[0].n === 0,
  );
  check(
    'ningún tipo está fuera del CHECK',
    campos.every((c) =>
      ['texto', 'email', 'numero', 'fecha', 'seleccion', 'multiseleccion', 'booleano', 'tabla', 'rejilla'].includes(c.tipo),
    ),
  );

  // --- la trampa del mapeo catálogo↔trigger
  //  El catálogo desglosa nombres y apellidos (primer_nombre/segundo_nombre) pero
  //  el trigger lee `nombres` y `apellidos`. Estos siete códigos SÍ coinciden
  //  literalmente con claves de metadata; si alguno desapareciera del catálogo,
  //  el formulario nuevo dejaría de mandar la clave y la ficha no se crearía,
  //  sin error. Por eso se comprueban por nombre.
  const codigos = new Set(campos.map((c) => c.codigo));
  for (const c of [
    'cedula',
    'fecha_nac',
    'sexo',
    'telefono',
    'direccion',
    'nivel_educativo',
    'curso_seleccionado',
  ]) {
    check(`el catálogo declara «${c}», que el trigger lee por ese nombre`, codigos.has(c));
  }

  // --- la columna
  const colPlanilla = (
    await db.query(
      'select data_type, is_nullable, column_default from information_schema.columns ' +
        "where table_schema='public' and table_name='aspirantes' and column_name='datos_planilla'",
    )
  ).rows[0];
  check('aspirantes.datos_planilla existe y es jsonb', colPlanilla?.data_type === 'jsonb', String(colPlanilla?.data_type));
  check('aspirantes.datos_planilla NO es nullable', colPlanilla?.is_nullable === 'NO', String(colPlanilla?.is_nullable));
  check(
    'aspirantes.datos_planilla arranca en {}',
    String(colPlanilla?.column_default).includes("'{}'"),
    String(colPlanilla?.column_default),
  );

  // --- la función
  const vp = (
    await db.query(
      'select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
        "where n.nspname='public' and p.proname='validar_planilla'",
    )
  ).rows[0];
  check('validar_planilla() existe', Boolean(vp));
  check(
    'validar_planilla() es SECURITY DEFINER (quien dispara el trigger no lee el catálogo)',
    vp?.prosecdef === true,
  );

  // --- validar_planilla() se comporta
  const errVacio = await esperaError('una planilla vacía se rechaza', () =>
    db.query("select public.validar_planilla('{}'::jsonb)"),
  );
  check('el error nombra los campos que faltan', /Faltan campos obligatorios/.test(String(errVacio?.message)));
  check('el error de planilla incompleta es 23514', errVacio?.code === '23514', String(errVacio?.code));
  await esperaError('una planilla que no es objeto se rechaza', () =>
    db.query("select public.validar_planilla('[]'::jsonb)"),
  );

  const planillaCompleta = Object.fromEntries(obligatorios.map((c) => [c.codigo, 'x']));
  await db.query('select public.validar_planilla($1::jsonb)', [JSON.stringify(planillaCompleta)]);
  check('una planilla con todos los obligatorios pasa', true);

  //  El anti-agujero: sin esto, un cliente «cumpliría» mandando [] o espacios.
  const errArray = await esperaError('un array vacío NO cuenta como campo cumplido', () =>
    db.query('select public.validar_planilla($1::jsonb)', [
      JSON.stringify({ ...planillaCompleta, [obligatorios[0].codigo]: [] }),
    ]),
  );
  check('el array vacío sale 23514', errArray?.code === '23514', String(errArray?.code));

  const errEspacios = await esperaError('una cadena de espacios NO cuenta como cumplida', () =>
    db.query('select public.validar_planilla($1::jsonb)', [
      JSON.stringify({ ...planillaCompleta, [obligatorios[0].codigo]: '   ' }),
    ]),
  );
  check('la cadena de espacios sale 23514', errEspacios?.code === '23514', String(errEspacios?.code));

  // --- el trigger: la asimetría deliberada
  //  UUIDs propios: los `3333…`/`4444…`/`5555…` ya están tomados en otras
  //  secciones de este archivo, y reutilizarlos revienta con 23505 en
  //  `auth.users` (pasó al escribir esta sección).
  const VIEJO_ID = 'a0000000-0000-4000-8000-000000000001';
  const NUEVO_OK = 'a0000000-0000-4000-8000-000000000002';
  const NUEVO_MAL = 'a0000000-0000-4000-8000-000000000003';
  //  `identidad` es función y no objeto porque cada usuario de prueba necesita
  //  su PROPIA cédula: `profiles` tiene `unique (cedula)`, y el insert del perfil
  //  ocurre ANTES de la validación de la planilla. Con la misma cédula en los
  //  tres, el segundo y el tercero morían con 23505 (cédula duplicada) y ese
  //  error enmascaraba el 23514 que estas aserciones quieren comprobar.
  const identidad = (cedula) => ({
    cedula,
    nombres: 'Luis',
    apellidos: 'Gomez',
    fecha_nac: '1990-01-01',
    sexo: 'M',
    telefono: '04141111111',
    direccion: 'Calle 1',
    nivel_educativo: 'SECUNDARIO',
    curso_seleccionado: 'Soldadura',
  });

  //  (a) cliente VIEJO (el formulario actual): no manda la clave.
  await db.exec(
    `insert into auth.users (id, email, raw_user_meta_data) values ` +
      `('${VIEJO_ID}', 'viejo@inces.test', '${JSON.stringify(identidad('90000001'))}'::jsonb);`,
  );
  const fichaVieja = (
    await db.query(`select datos_planilla from public.aspirantes where user_id = '${VIEJO_ID}'`)
  ).rows[0];
  check('un cliente SIN datos_planilla sigue creando la ficha (no hay regresión)', Boolean(fichaVieja));
  check(
    'y la deja en objeto vacío, no en NULL',
    JSON.stringify(fichaVieja?.datos_planilla) === '{}',
    JSON.stringify(fichaVieja?.datos_planilla),
  );

  //  (b) cliente NUEVO con planilla incompleta: el registro entero falla.
  const errRegistro = await esperaError('una planilla incompleta aborta el registro', () =>
    db.exec(
      `insert into auth.users (id, email, raw_user_meta_data) values ` +
        `('${NUEVO_MAL}', 'malo@inces.test', ` +
        `'${JSON.stringify({ ...identidad('90000002'), datos_planilla: { primer_nombre: 'Luis' } })}'::jsonb);`,
    ),
  );
  check('el registro con planilla incompleta sale 23514', errRegistro?.code === '23514', String(errRegistro?.code));
  check(
    'no quedó ficha huérfana del registro fallido',
    (
      await db.query(`select count(*)::int as n from public.aspirantes where user_id = '${NUEVO_MAL}'`)
    ).rows[0].n === 0,
  );

  //  (c) cliente NUEVO con planilla completa: la ficha guarda el JSONB.
  const planillaBuena = {
    ...planillaCompleta,
    primer_nombre: 'Luis',
    primer_apellido: 'Gomez',
    familiares: [{ cedula: '1', nombres: 'Ana', apellidos: 'B', parentesco: 'Madre' }],
  };
  await db.exec(
    `insert into auth.users (id, email, raw_user_meta_data) values ` +
      `('${NUEVO_OK}', 'nuevo@inces.test', ` +
      `'${JSON.stringify({ ...identidad('90000003'), datos_planilla: planillaBuena })}'::jsonb);`,
  );
  const fichaNueva = (
    await db.query(`select datos_planilla from public.aspirantes where user_id = '${NUEVO_OK}'`)
  ).rows[0];
  check('un cliente CON planilla completa crea la ficha', Boolean(fichaNueva));
  check(
    'la planilla llegó íntegra a la columna',
    fichaNueva?.datos_planilla?.primer_nombre === 'Luis',
    String(fichaNueva?.datos_planilla?.primer_nombre),
  );
  check(
    'las tablas repetibles viajan como array',
    Array.isArray(fichaNueva?.datos_planilla?.familiares) &&
      fichaNueva.datos_planilla.familiares.length === 1,
  );

  // --- RLS del catálogo
  const anonVe = await como('anon', null, () =>
    db.query('select count(*)::int as n from public.inscripcion_campos'),
  );
  check('anon LEE el catálogo (el formulario se pinta sin sesión)', anonVe.rows[0].n >= 40, `ve ${anonVe.rows[0].n}`);

  await como('anon', null, () =>
    db.exec("update public.inscripcion_campos set obligatorio = false where codigo = 'cedula'"),
  );
  check(
    'anon NO puede editar el catálogo',
    (await db.query("select obligatorio from public.inscripcion_campos where codigo='cedula'")).rows[0]
      .obligatorio === true,
  );

  // ------------------------------- 21. Guardia de escritura (202609240002)
  seccion('21. Guardia de escritura de la planilla (202609240002)');

  // --- el trigger existe y está cableado
  const defTrigger = (
    await db.query(
      'select pg_get_triggerdef(t.oid) as def from pg_trigger t ' +
        'join pg_class c on c.oid = t.tgrelid ' +
        'join pg_namespace n on n.oid = c.relnamespace ' +
        "where n.nspname = 'public' and c.relname = 'aspirantes' " +
        "and t.tgname = 'aspirantes_validar_planilla'",
    )
  ).rows[0]?.def;

  check('existe el trigger aspirantes_validar_planilla', Boolean(defTrigger), String(defTrigger));
  // Sin el `OF datos_planilla` el trigger dispararía en CUALQUIER escritura de la
  // fila, y una edición de teléfono revalidaría una planilla vacía legítima.
  check(
    'el trigger está limitado a la columna datos_planilla',
    /datos_planilla/.test(String(defTrigger)),
    String(defTrigger),
  );
  check(
    'el trigger dispara en INSERT y en UPDATE',
    /INSERT/.test(String(defTrigger)) && /UPDATE/.test(String(defTrigger)),
    String(defTrigger),
  );

  const envoltorio = (
    await db.query(
      'select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace ' +
        "where n.nspname = 'public' and p.proname = 'validar_planilla_guardada'",
    )
  ).rows[0];
  check('existe el envoltorio validar_planilla_guardada()', Boolean(envoltorio));
  // La lección de `202609180002`: un envoltorio `invoker` que delega en una
  // función sin EXECUTE para el llamante deja el módulo inoperable con 42501.
  check(
    'el envoltorio es SECURITY DEFINER (lección de 202609180002)',
    envoltorio?.prosecdef === true,
    String(envoltorio?.prosecdef),
  );

  // --- LA ASERCIÓN QUE IMPORTA: el agujero, escrito como usuario real
  //  Se escribe **como `authenticated` con los claims de un usuario**, no como el
  //  dueño de las tablas. El dueño se salta la comprobación de privilegios y no
  //  reproduce al usuario real: es exactamente el fallo que `202609180002`
  //  documenta y por el que existió la sección 14.8 de este archivo.
  //
  //  Sin esta aserción, la guardia podría estar ausente y la batería seguiría
  //  verde, porque el camino del `signUp` ya valida por su cuenta.
  const planillaIncompleta = { primer_nombre: 'Luis' };

  const errDirecto = await esperaError(
    'un usuario autenticado NO puede escribir una planilla incompleta por UPDATE directo',
    () =>
      como('authenticated', VIEJO_ID, () =>
        db.query('update public.aspirantes set datos_planilla = $1::jsonb where user_id = $2', [
          JSON.stringify(planillaIncompleta),
          VIEJO_ID,
        ]),
      ),
  );
  check(
    'el rechazo de la escritura directa sale 23514',
    errDirecto?.code === '23514',
    String(errDirecto?.code),
  );
  check(
    'el rechazo nombra los campos que faltan',
    /Faltan campos obligatorios/.test(String(errDirecto?.message)),
    String(errDirecto?.message),
  );
  check(
    'la planilla no cambió tras el rechazo',
    JSON.stringify(
      (await db.query(`select datos_planilla from public.aspirantes where user_id = '${VIEJO_ID}'`))
        .rows[0]?.datos_planilla,
    ) === '{}',
  );

  // --- y el camino legítimo sigue abierto
  await como('authenticated', VIEJO_ID, () =>
    db.query('update public.aspirantes set datos_planilla = $1::jsonb where user_id = $2', [
      JSON.stringify(planillaCompleta),
      VIEJO_ID,
    ]),
  );
  check('un usuario autenticado SÍ puede escribir su planilla completa', true);

  // --- la asimetría sigue en pie: `{}` es «sin planilla», no una planilla vacía
  await como('authenticated', VIEJO_ID, () =>
    db.query("update public.aspirantes set datos_planilla = '{}'::jsonb where user_id = $1", [
      VIEJO_ID,
    ]),
  );
  check(
    'el objeto vacío sigue permitido: es el «sin planilla» del formulario viejo',
    JSON.stringify(
      (await db.query(`select datos_planilla from public.aspirantes where user_id = '${VIEJO_ID}'`))
        .rows[0]?.datos_planilla,
    ) === '{}',
  );

  // --- una escritura que NO toca la planilla no la revalida
  //  Es la mitad del `OF datos_planilla`: si el trigger disparara en toda la fila,
  //  la ficha de todo el que se registró con el formulario viejo —planilla `{}`—
  //  no se podría editar nunca más.
  await como('authenticated', VIEJO_ID, () =>
    db.query('update public.aspirantes set telefono = $1 where user_id = $2', [
      '04149999999',
      VIEJO_ID,
    ]),
  );
  check(
    'una edición que no toca la planilla no la revalida',
    (await db.query(`select telefono from public.aspirantes where user_id = '${VIEJO_ID}'`)).rows[0]
      ?.telefono === '04149999999',
  );

  // --- el alta directa: `aspirantes_insert_own` existe, así que también valida
  //  Un usuario sin ficha —alguien registrado como docente, por ejemplo— podría
  //  crearse la suya con `aspirantes_insert_own`. El insert también pasa por la
  //  guardia, y sin él esta puerta quedaría abierta.
  const SIN_FICHA = 'a0000000-0000-4000-8000-000000000004';
  await db.exec(
    `insert into auth.users (id, email, raw_user_meta_data) values ` +
      `('${SIN_FICHA}', 'sinficha@inces.test', '{}'::jsonb);`,
  );
  check(
    'el usuario de prueba quedó sin ficha de aspirante',
    (
      await db.query(`select count(*)::int as n from public.aspirantes where user_id = '${SIN_FICHA}'`)
    ).rows[0].n === 0,
  );

  const errAlta = await esperaError(
    'un usuario autenticado NO puede insertar su ficha con una planilla incompleta',
    () =>
      como('authenticated', SIN_FICHA, () =>
        db.query(
          'insert into public.aspirantes ' +
            '(user_id, cedula, nombres, apellidos, fecha_nac, sexo, telefono, email, direccion, ' +
            ' nivel_educativo, curso_seleccionado, datos_planilla) ' +
            'values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::jsonb)',
          [
            SIN_FICHA,
            '91000001',
            'Sin',
            'Ficha',
            '1990-01-01',
            'M',
            '04141111111',
            'sinficha@inces.test',
            'Calle 1',
            'SECUNDARIO',
            'Soldadura',
            JSON.stringify(planillaIncompleta),
          ],
        ),
      ),
  );
  check('el rechazo del alta directa sale 23514', errAlta?.code === '23514', String(errAlta?.code));

  await como('authenticated', SIN_FICHA, () =>
    db.query(
      'insert into public.aspirantes ' +
        '(user_id, cedula, nombres, apellidos, fecha_nac, sexo, telefono, email, direccion, ' +
        ' nivel_educativo, curso_seleccionado, datos_planilla) ' +
        'values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::jsonb)',
      [
        SIN_FICHA,
        '91000001',
        'Sin',
        'Ficha',
        '1990-01-01',
        'M',
        '04141111111',
        'sinficha@inces.test',
        'Calle 1',
        'SECUNDARIO',
        'Soldadura',
        JSON.stringify(planillaCompleta),
      ],
    ),
  );
  check('…y sí puede insertarla completa', true);

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
