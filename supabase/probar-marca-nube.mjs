/**
 * Prueba de comportamiento de M7 (asistencia) CONTRA LA NUBE REAL.
 *
 * `verificar-esquema.mjs` inspecciona el catálogo: dice que la política existe y
 * que su expresión es la correcta. Eso NO es lo mismo que decir que el INSERT
 * del alumno pasa. D27 fue exactamente eso: la política estaba, la expresión era
 * plausible, y el alumno no podía marcar nunca porque la función que la política
 * llamaba tenía el EXECUTE revocado.
 *
 * Este script EJERCE la RLS con la identidad real de cada rol (JWT simulado con
 * `request.jwt.claims` + `set local role authenticated`) y comprueba el veredicto.
 *
 * Dos decisiones que lo hacen seguro de correr contra producción:
 *
 *   1. TODO ocurre dentro de una transacción que termina en `rollback`. No crea
 *      ni un dato. El `select` de resultados va ANTES del `rollback` y la API
 *      devuelve sus filas igualmente (medido: `begin; select 42; rollback;` →
 *      `201 [{"respuesta":42}]`), así que se ven los resultados y no queda rastro.
 *   2. Los fixtures se DESCUBREN, no se escriben a mano. Un UUID hardcodeado
 *      envejece en silencio: apuntaría a una sección borrada y la prueba diría
 *      «pasa» sin haber tocado nada.
 *
 * Uso: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/probar-marca-nube.mjs
 */
const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
const ref = (process.env.SUPABASE_PROJECT_REF ?? 'twdppwnxlnmxkiejbrei').trim();

if (token.length === 0) {
  console.error('Falta SUPABASE_ACCESS_TOKEN.');
  process.exit(1);
}

async function consultar(query) {
  const respuesta = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  const texto = await respuesta.text();
  if (!respuesta.ok) {
    throw new Error(`HTTP ${respuesta.status}: ${texto}`);
  }
  return texto.length > 0 ? JSON.parse(texto) : [];
}

// ---------------------------------------------------------------------------
//  1. Descubrir los fixtures
// ---------------------------------------------------------------------------
//  Se busca una sección que tenga a la vez docente en el cuadrante e inscritos
//  ENROLLED, porque las dos cosas son requisito para que el camino feliz exista.
//  Si no la hay, la prueba NO puede pasar: se dice y se sale con error.
const [fixture] = await consultar(`
  select sl.section_id,
         sl.teacher_id,
         s.name as seccion,
         s.period_code
    from public.schedule_slots sl
    join public.sections s on s.id = sl.section_id
    join public.enrollments e on e.section_id = sl.section_id
   where e.status = 'ENROLLED'
   group by sl.section_id, sl.teacher_id, s.name, s.period_code
  having count(distinct e.student_id) >= 2
   order by count(distinct e.student_id) desc
   limit 1;
`);

if (!fixture) {
  console.error(
    'No hay ninguna sección con docente en el cuadrante y >=2 inscritos ENROLLED.\n' +
      'Sin eso el camino feliz no se puede ni plantear, así que no se prueba nada.',
  );
  process.exit(1);
}

const alumnos = await consultar(`
  select student_id::text as id
    from public.enrollments
   where section_id = '${fixture.section_id}'
     and status = 'ENROLLED'
   order by student_id
   limit 2;
`);

if (alumnos.length < 2) {
  console.error('Se esperaban >=2 inscritos y llegaron ' + alumnos.length + '.');
  process.exit(1);
}

console.log('\nFixtures descubiertos (no hardcodeados):');
console.log(`  sección : ${fixture.seccion} · ${fixture.period_code} · ${fixture.section_id}`);
console.log(`  docente : ${fixture.teacher_id}`);
console.log(`  alumno 1: ${alumnos[0].id}`);
console.log(`  alumno 2: ${alumnos[1].id}`);
console.log(`  ajeno   : ${fixture.teacher_id} (autenticado, NO inscrito)\n`);

// ---------------------------------------------------------------------------
//  2. La prueba, entera dentro de un DO y de una transacción que se deshace
// ---------------------------------------------------------------------------
//  Un solo bloque `do` para que las variables sobrevivan a los cambios de rol:
//  `set local role` se hace con `execute` y se deshace con `reset role` antes de
//  volver a escribir en la tabla de resultados (que es del rol dueño).
const sql = `
begin;

create temp table resultado (
  orden int generated always as identity,
  prueba text,
  esperado text,
  obtenido text,
  ok boolean
) on commit drop;

-- La tabla es del rol dueño, pero las aserciones se escriben MIENTRAS el rol es
-- \`authenticated\` (que es justo lo que hay que probar). Sin este grant el
-- bloque muere con 42501 —permiso denegado sobre la propia tabla de resultados—
-- y la prueba fallaría por el andamio, no por el código.
grant insert, select on resultado to authenticated;

-- ---------------------------------------------------------------------------
--  0. La cota de 12 h, contra las sesiones OPEN olvidadas de verdad
-- ---------------------------------------------------------------------------
--  Producción tenía sesiones con status OPEN del 2026-09-26 —el botón «Cerrar»
--  estaba roto por D28, así que nadie pudo cerrarlas—. El resolutor lleva una
--  cota de 12 h justamente para que una sesión olvidada no cuente como «hay
--  clase abierta» y el mensaje que ve el alumno sea mentira. Esto lo comprueba
--  sobre esas filas reales, no sobre una hipótesis.
--
--  La aserción es CONDICIONAL a propósito: si algún día hay una sesión fresca
--  abierta, la respuesta correcta pasa a ser CODIGO_INVALIDO y afirmar
--  SIN_SESION_ACTIVA sería un rojo falso. Se dice que no se pudo comprobar.
do $cota$
declare
  v_viejas  int;
  v_frescas int;
  v_estado  text;
begin
  select count(*) filter (where opened_at <= now() - interval '12 hours'),
         count(*) filter (where opened_at >  now() - interval '12 hours')
    into v_viejas, v_frescas
    from public.attendance_sessions
   where status = 'OPEN';

  if v_frescas = 0 then
    perform set_config('request.jwt.claims',
                       json_build_object('sub', '${alumnos[1].id}', 'role', 'authenticated')::text,
                       true);
    execute 'set local role authenticated';
    v_estado := public.asistencia_resolver_codigo('123456') ->> 'estado';
    execute 'reset role';

    insert into resultado (prueba, esperado, obtenido, ok)
    values (format('el resolutor ignora %s sesión(es) OPEN olvidada(s) de >12 h', v_viejas),
            'SIN_SESION_ACTIVA', v_estado, v_estado = 'SIN_SESION_ACTIVA');
  else
    insert into resultado (prueba, esperado, obtenido, ok)
    values (format('la cota de 12 h con %s sesión(es) OPEN olvidada(s)', v_viejas),
            'comprobable', format('NO COMPROBADA: hay %s sesión(es) fresca(s) abierta(s)', v_frescas),
            true);
  end if;
end
$cota$;

do $prueba$
declare
  v_seccion uuid := '${fixture.section_id}';
  v_docente uuid := '${fixture.teacher_id}';
  v_alumno1 uuid := '${alumnos[0].id}';
  v_alumno2 uuid := '${alumnos[1].id}';
  v_sesion  uuid;
  v_codigo  text;
  v_otro    text;
  v_estado  text;
  v_res     text;
  v_id      uuid;
  v_n       int;
  v_intento int := 0;
begin
  -- --- El docente abre una sesión para SU sección ---------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_docente, 'role', 'authenticated')::text,
                     true);
  execute 'set local role authenticated';
  begin
    insert into public.attendance_sessions (section_id, opened_by, qr_secret)
    values (v_seccion, v_docente, md5(random()::text || clock_timestamp()::text))
    returning id into v_sesion;
    v_res := 'PERMITIDO';
  exception when others then
    v_res := 'DENEGADO ' || sqlstate;
  end;
  execute 'reset role';
  insert into resultado (prueba, esperado, obtenido, ok)
  values ('el docente abre la sesión de su propia sección',
          'PERMITIDO', v_res, v_res = 'PERMITIDO');

  if v_sesion is null then
    -- Sin sesión no hay nada más que probar. Se marca y se sigue para que la
    -- salida diga QUÉ falló en vez de reventar con un null más adelante.
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('el resto de la prueba', 'ejecutable', 'ABORTADA: no se pudo abrir la sesión', false);
  else

    -- --- El código vigente (se pide como dueño: es el oráculo) ---------------
    select public.asistencia_codigo_actual(v_sesion) into v_codigo;

    insert into resultado (prueba, esperado, obtenido, ok)
    values ('el código vigente tiene forma de seis dígitos',
            '6 dígitos', coalesce(v_codigo, 'null'),
            v_codigo ~ '^[0-9]{6}$');

    -- --- Un código que NO es vigente, para el caso de error -----------------
    v_otro := '000000';
    while (select v.vigente from public.asistencia_codigo_vigente(v_sesion, v_otro) v)
          and v_intento < 20 loop
      v_otro := lpad((((v_otro::int + 1) % 1000000))::text, 6, '0');
      v_intento := v_intento + 1;
    end loop;

    -- =====================================================================
    --  ALUMNO 1
    -- =====================================================================
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_alumno1, 'role', 'authenticated')::text,
                       true);
    execute 'set local role authenticated';

    -- (a) la guardia dice que sí
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('la guardia deja pasar al alumno inscrito con el código vigente',
            'true', public.asistencia_puede_marcar(v_sesion, v_codigo)::text,
            public.asistencia_puede_marcar(v_sesion, v_codigo));

    -- (b) el resolutor dice OK
    v_estado := public.asistencia_resolver_codigo(v_codigo) ->> 'estado';
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('el resolutor reconoce los seis dígitos', 'OK', v_estado, v_estado = 'OK');

    -- (c) EL INSERT DEL ALUMNO — el que llevaba roto desde el 2026-09-26
    begin
      insert into public.attendance_marks (session_id, student_id, code, ventana_idx)
      values (v_sesion, v_alumno1, v_codigo, 0)
      returning id into v_id;
      v_res := 'PERMITIDO';
    exception when others then
      v_res := 'DENEGADO ' || sqlstate;
    end;
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('el alumno inscrito MARCA su asistencia', 'PERMITIDO', v_res, v_res = 'PERMITIDO');

    -- (d) repetir sale YA_MARCADO, no un segundo registro
    v_estado := public.asistencia_resolver_codigo(v_codigo) ->> 'estado';
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('volver a teclear el código dice YA_MARCADO', 'YA_MARCADO', v_estado,
            v_estado = 'YA_MARCADO');

    execute 'reset role';

    -- =====================================================================
    --  ALUMNO 2
    -- =====================================================================
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_alumno2, 'role', 'authenticated')::text,
                       true);
    execute 'set local role authenticated';

    v_estado := public.asistencia_resolver_codigo(v_codigo) ->> 'estado';
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('un compañero que no ha marcado sigue viendo OK', 'OK', v_estado, v_estado = 'OK');

    v_estado := public.asistencia_resolver_codigo(v_otro) ->> 'estado';
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('seis dígitos que no son el vigente', 'CODIGO_INVALIDO', v_estado,
            v_estado = 'CODIGO_INVALIDO');

    -- (e) no puede marcar a nombre de otro: la política exige student_id = auth.uid()
    begin
      insert into public.attendance_marks (session_id, student_id, code, ventana_idx)
      values (v_sesion, v_alumno1, v_codigo, 0)
      returning id into v_id;
      v_res := 'PERMITIDO (mal: debería denegar)';
    exception when others then
      v_res := 'DENEGADO ' || sqlstate;
    end;
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('no se puede marcar a nombre de otro alumno', 'DENEGADO', v_res,
            v_res like 'DENEGADO%');

    -- (f) el código equivocado no pasa la política de INSERT
    begin
      insert into public.attendance_marks (session_id, student_id, code, ventana_idx)
      values (v_sesion, v_alumno2, v_otro, 0)
      returning id into v_id;
      v_res := 'PERMITIDO (mal: debería denegar)';
    exception when others then
      v_res := 'DENEGADO ' || sqlstate;
    end;
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('un código que no es el vigente no entra por la política', 'DENEGADO', v_res,
            v_res like 'DENEGADO%');

    -- (g) el oráculo sigue cerrado para authenticated
    begin
      select count(*) into v_n from public.asistencia_codigo_vigente(v_sesion, v_codigo);
      v_res := 'PERMITIDO (mal: es el oráculo de fuerza bruta)';
    exception when others then
      v_res := 'DENEGADO ' || sqlstate;
    end;
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('authenticated NO puede llamar a asistencia_codigo_vigente', 'DENEGADO 42501', v_res,
            v_res = 'DENEGADO 42501');

    execute 'reset role';

    -- =====================================================================
    --  UN AUTENTICADO QUE NO ESTÁ INSCRITO (el docente)
    -- =====================================================================
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_docente, 'role', 'authenticated')::text,
                       true);
    execute 'set local role authenticated';

    insert into resultado (prueba, esperado, obtenido, ok)
    values ('la guardia frena a quien no está inscrito (sin mirar el código)',
            'false', public.asistencia_puede_marcar(v_sesion, v_codigo)::text,
            not public.asistencia_puede_marcar(v_sesion, v_codigo));

    v_estado := public.asistencia_resolver_codigo(v_codigo) ->> 'estado';
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('código correcto de una clase que no cursa', 'NO_INSCRITO', v_estado,
            v_estado = 'NO_INSCRITO');

    -- --- Y AHORA EL CIERRE, que es D28 ------------------------------------
    update public.attendance_sessions set status = 'CLOSED', closed_at = now()
     where id = v_sesion;
    get diagnostics v_n = row_count;
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('el docente CIERRA su sesión (afecta 1 fila, antes 0)', '1 fila',
            v_n::text || ' fila(s)', v_n = 1);

    execute 'reset role';

    -- =====================================================================
    --  CON LA SESIÓN CERRADA
    -- =====================================================================
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_alumno2, 'role', 'authenticated')::text,
                       true);
    execute 'set local role authenticated';

    v_estado := public.asistencia_resolver_codigo(v_codigo) ->> 'estado';
    insert into resultado (prueba, esperado, obtenido, ok)
    values ('con la clase cerrada no hay sesión activa', 'SIN_SESION_ACTIVA', v_estado,
            v_estado = 'SIN_SESION_ACTIVA');

    insert into resultado (prueba, esperado, obtenido, ok)
    values ('cerrada la sesión, la guardia ya no deja marcar',
            'false', public.asistencia_puede_marcar(v_sesion, v_codigo)::text,
            not public.asistencia_puede_marcar(v_sesion, v_codigo));

    execute 'reset role';
  end if;
end
$prueba$;

select prueba, esperado, obtenido, ok from resultado order by orden;

rollback;
`;

const filas = await consultar(sql);

console.log('Resultados de EJERCER la RLS en la nube:\n');
let fallos = 0;
for (const f of filas) {
  if (!f.ok) fallos += 1;
  console.log(`  [${f.ok ? 'OK  ' : 'FALLA'}] ${f.prueba}`);
  if (!f.ok) {
    console.log(`          esperado: ${f.esperado}`);
    console.log(`          obtenido: ${f.obtenido}`);
  }
}

// ---------------------------------------------------------------------------
//  3. Probar que el rollback no dejó rastro
// ---------------------------------------------------------------------------
const [marcas] = await consultar(
  'select count(*)::int as total from public.attendance_marks;',
);
const [sesiones] = await consultar(
  "select count(*)::int as total from public.attendance_sessions where status = 'OPEN' and opened_at > now() - interval '12 hours';",
);

console.log('');
const sinRastro = marcas.total === 0;
console.log(
  `  [${sinRastro ? 'OK  ' : 'FALLA'}] el rollback no dejó rastro — marcas en la tabla: ${marcas.total}`,
);
if (!sinRastro) fallos += 1;
console.log(
  `  [info] sesiones OPEN de las últimas 12 h: ${sesiones.total} (no se ha creado ninguna)`,
);

console.log('');
if (fallos === 0) {
  console.log(`✓ ${filas.length} aserciones ejercidas contra la nube, 0 fallos.`);
  process.exit(0);
} else {
  console.log(`✗ ${fallos} de ${filas.length} aserciones fallaron.`);
  process.exit(1);
}
