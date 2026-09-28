-- ============================================================================
--  INCES LMS — Asistencia: el alumno YA puede marcar y el docente YA puede
--  cerrar (dos políticas inalcanzables) + resolutor de código para D21
--  Archivo: 202609270001_asistencia_marca_y_cierre.sql
-- ============================================================================
--
--  QUÉ CIERRA — y cómo se supo
--  ---------------------------
--  Hasta hoy, NINGÚN alumno podía marcar asistencia. La política
--  `attendance_marks_estudiante_insert` (202609260001) llama a
--  `asistencia_codigo_vigente(...)`, y esa función termina con
--
--      revoke all on function public.asistencia_codigo_vigente(uuid, text)
--        from public, anon, authenticated;          -- 202609260004, PARTE 1
--
--  El comentario de 202609260001 decía «sólo la llaman las políticas RLS», y
--  eso es falso: PostgreSQL comprueba EXECUTE contra el rol que CONSULTA
--  también dentro de una expresión de política. Medido, no deducido, con el
--  arnés `supabase/tests/validate.mjs` (sección 20), que ejerce el INSERT con
--  un `authenticated` real y un `auth.uid()` real:
--
--      ✗ el alumno ENROLLED con el código vigente SÍ marca
--        → 42501: permission denied for function asistencia_codigo_vigente
--
--  Es el peor tipo de fallo: no rompe la compilación, no lo ve `flutter
--  analyze`, y las 32 pruebas de M7 del backend no lo ven porque usan
--  repositorios falsos. Con todo en verde, la asistencia entera era inservible.
--
--  Y había un segundo daño, más silencioso: las aserciones NEGATIVAS del arnés
--  («un código caducado no vale», «un WAITLISTED no marca») daban verde por el
--  motivo equivocado —el 42501 del permiso, no el de la política—, así que no
--  medían nada. Es el patrón de D25: un verde que no mide. Se destapó al
--  ejercer el camino FELIZ, que es el único que puede distinguirlos.
--
--  Y un TERCER fallo, encadenado al anterior: al ejercer el cierre para poder
--  probar «con la sesión cerrada no se marca» resultó que el docente no podía
--  cerrar. `attendance_sessions` tenía políticas de INSERT y de SELECT para el
--  docente, y ninguna de UPDATE, así que el botón «Cerrar» del tablero afectaba
--  0 filas y el backend lo leía como «no eres el dueño». Detalle en PARTE 2.5.
--
--  Los tres son la misma familia: una regla escrita que nadie ejecutó nunca.
--
--
--  LA CORRECCIÓN, Y POR QUÉ NO ES «DAR PERMISO Y YA»
--  ------------------------------------------------
--  La salida obvia era `grant execute on asistencia_codigo_vigente to
--  authenticated`. Funciona, pero convierte la función en un ORÁCULO: cualquier
--  usuario con sesión podría preguntar «¿es válido este código para esta
--  sesión?» y acertar por fuerza bruta en segundos.
--
--  En su lugar se interpone `asistencia_puede_marcar`, que NO responde hasta
--  comprobar que quien pregunta podría marcar de todas formas —matriculado
--  ENROLLED en la sección de una sesión abierta—. Quien no cumple eso recibe
--  `false` sin que se llegue a evaluar el código, así que no aprende nada. El
--  oráculo queda cerrado y la regla delicada sigue en la base, no en la app.
--
--
--  PARTE 3 — el resolutor de D21
--  -----------------------------
--  Decisión de producto (2026-09-27): el alumno teclea los SEIS DÍGITOS, sin
--  UUID. La cámara llegará después y reutilizará el mismo camino.
--
--  El alumno no puede listar `attendance_sessions` —no hay política de SELECT
--  para él, y está bien que no la haya—, así que la sesión tiene que
--  resolverla el servidor. `asistencia_resolver_codigo` lo hace en la base, con
--  `auth.uid()` como identidad real, y devuelve un veredicto en vez de una fila
--  para que la UI pueda decir QUÉ pasó en lugar de «no se pudo».
--
--  NO edita ninguna migración aplicada: 202609260001..005 están en el libro
--  mayor con su checksum y `apply-migrations.mjs` rechazaría la deriva. Aquí se
--  abre y se cierra la porta (la política) y se añaden funciones nuevas.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — La función que la política SÍ puede llamar
-- ---------------------------------------------------------------------------
create or replace function public.asistencia_puede_marcar(
  p_sesion uuid,
  p_codigo text
)
returns boolean
language plpgsql
security definer
stable
set search_path = public, extensions, pg_temp
as $$
declare
  v_vigente boolean;
begin
  -- 1. LA GUARDA, Y VA PRIMERO: sólo se responde a quien podría marcar. Un
  --    curioso con el uuid de una sesión ajena sale por aquí con `false` y sin
  --    haber evaluado el código — por eso esta función no es un oráculo.
  --    `auth.uid()` es el del LLAMANTE aunque la función sea `security definer`:
  --    definer cambia `current_user`, no la identidad del JWT.
  if not exists (
    select 1
      from public.attendance_sessions s
      join public.enrollments e on e.section_id = s.section_id
     where s.id = p_sesion
       and s.status = 'OPEN'
       and e.student_id = auth.uid()
       and e.status = 'ENROLLED'
  ) then
    return false;
  end if;

  -- 2. Y sólo entonces, la pregunta cara: ¿es vigente el código? (±1 ventana,
  --    que lo resuelve la función de siempre). Aquí ya se puede llamar a
  --    `asistencia_codigo_vigente` aunque `authenticated` no tenga EXECUTE
  --    sobre ella: dentro de una función `security definer` el usuario actual
  --    es el DUEÑO, y el dueño sí lo tiene.
  select v.vigente into v_vigente
    from public.asistencia_codigo_vigente(p_sesion, p_codigo) v;

  return coalesce(v_vigente, false);
end;
$$;

comment on function public.asistencia_puede_marcar(uuid, text) is
  '¿Puede el llamante marcar esta sesión con este código? Exige ENROLLED en la sección y sesión OPEN ANTES de mirar el código, así que no sirve de oráculo para adivinarlo. Es la que llama la política de INSERT desde 202609270001: sin ella, la política invocaba una función revocada para `authenticated` y el INSERT del alumno moría con 42501.';

-- Supabase concede EXECUTE a `anon`/`authenticated` por defecto sobre toda
-- función nueva en `public` (el shim del arnés lo emula a propósito). Se revoca
-- lo que no toca y se concede sólo lo que sí.
revoke all on function public.asistencia_puede_marcar(uuid, text)
  from public, anon;
grant execute on function public.asistencia_puede_marcar(uuid, text)
  to authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 2 — La política, apuntada a la función que sí es alcanzable
-- ---------------------------------------------------------------------------
--  Se cambia SÓLO la expresión de `WITH CHECK`; el nombre de la política, su
--  tabla y sus roles (`to authenticated`) se conservan. El nombre no cambia a
--  propósito: los comentarios de 202609260001, el ADR-003 y
--  `ESTADO_DEL_SISTEMA.md` la citan por su nombre.
--
--  `student_id = auth.uid()` se queda EXPLÍCITA aunque `asistencia_puede_marcar`
--  ya compruebe la matrícula: son dos cosas distintas —la primera dice «esta
--  fila es tuya», la segunda «esta fila tiene derecho a existir»— y la barata no
--  debe depender de la cara.
alter policy attendance_marks_estudiante_insert on public.attendance_marks
  with check (
    public.asistencia_puede_marcar(attendance_marks.session_id, attendance_marks.code)
    and student_id = auth.uid()
  );


-- ---------------------------------------------------------------------------
--  PARTE 2.5 — Y el docente tampoco podía CERRAR
-- ---------------------------------------------------------------------------
--  El segundo fallo, encontrado al ejercer el cierre para poder probar «con la
--  sesión cerrada no se marca». Medido en el mismo arnés:
--
--      ✗ el docente puede cerrar su sesión (el UPDATE es alcanzable)
--        → filas afectadas: 0
--
--  `attendance_sessions` tiene tres políticas: INSERT del docente, SELECT del
--  docente y ALL del admin. **No hay UPDATE del docente**, así que
--  `PATCH /asistencia/sesiones/:id/cerrar` —el botón «Cerrar» del tablero— no
--  actualizaba ninguna fila, y el backend lo traducía a un 403 «No eres el
--  dueño de esta sesión». El docente abría la sesión y no podía pararla: el QR
--  seguía rotando y el alumno podía marcar indefinidamente.
--
--  No salta a la vista porque el síntoma que produce —0 filas— es idéntico al
--  de «no es tuya», y el backend ya tenía un mensaje para eso. Un fallo de
--  permisos disfrazado de fallo de propiedad.
--
--  La condición del `USING` se repite en el `WITH CHECK`, y no es redundancia:
--  `USING` decide QUÉ FILAS puede tocar, `WITH CHECK` decide CÓMO QUEDAN. Sin
--  el segundo, un docente podría cambiar el `section_id` de su sesión al de una
--  sección que no dicta —y desde ahí leer las marcas de esa otra sección—,
--  porque la fila ya estaría dentro del `USING`. Es el mismo patrón que la
--  política del admin, que también lleva los dos.
--
--  No hace falta guardia por COLUMNA (un trigger que sólo deje tocar `status` y
--  `closed_at`): el `WITH CHECK` ya cierra el `section_id` y el `opened_by`, que
--  son los dos únicos campos con los que se ganaría algo. Reabrir una sesión
--  cerrada sí está permitido, y es deliberado: un docente que cerró por error
--  tiene que poder volver a abrirla.
create policy attendance_sessions_docente_update
  on public.attendance_sessions for update
  to authenticated
  using (
    opened_by = auth.uid()
    or exists (
      select 1 from public.schedule_slots s
       where s.section_id = attendance_sessions.section_id
         and s.teacher_id = auth.uid()
    )
  )
  with check (
    opened_by = auth.uid()
    or exists (
      select 1 from public.schedule_slots s
       where s.section_id = attendance_sessions.section_id
         and s.teacher_id = auth.uid()
    )
  );

comment on policy attendance_sessions_docente_update on public.attendance_sessions is
  'El docente (o quien dicta la sección) puede actualizar su sesión. Sin esta política el botón «Cerrar» del tablero afectaba 0 filas y la sesión quedaba abierta para siempre: el UPDATE no tenía política, y el síntoma se confundía con «no eres el dueño».';


-- ---------------------------------------------------------------------------
--  PARTE 3 — El resolutor: de seis dígitos a sesión (D21)
-- ---------------------------------------------------------------------------
create or replace function public.asistencia_resolver_codigo(
  p_codigo text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, extensions, pg_temp
as $$
declare
  --  Cota de la búsqueda. Sin ella, una sesión OPEN olvidada de la semana
  --  pasada seguiría contando como «hay clase abierta» y el diagnóstico que
  --  ve el alumno sería mentira. Doce horas cubren de sobra una jornada
  --  formativa y ninguna sesión real se queda abierta más tiempo.
  v_limite constant interval := interval '12 hours';
  v_codigo text := btrim(coalesce(p_codigo, ''));
  v_yo     uuid := auth.uid();
  v_hay    boolean;
  v_match  record;
begin
  -- Sin identidad no hay nada que resolver. No debería ocurrir (la ruta exige
  -- sesión), pero devolver un veredicto es más honesto que reventar.
  if v_yo is null then
    return jsonb_build_object('estado', 'SIN_SESION');
  end if;

  -- La forma se comprueba aquí y no sólo en el Zod del backend: si un día
  -- alguien llama a esta función por PostgREST de frente, la regla viaja con
  -- ella. Seis dígitos, ni uno más.
  if v_codigo !~ '^[0-9]{6}$' then
    return jsonb_build_object('estado', 'CODIGO_INVALIDO');
  end if;

  select exists (
    select 1 from public.attendance_sessions s
     where s.status = 'OPEN'
       and s.opened_at > now() - v_limite
  ) into v_hay;

  if not v_hay then
    return jsonb_build_object('estado', 'SIN_SESION_ACTIVA');
  end if;

  --  La sesión cuyo código vigente coincide. El `order by` resuelve el caso
  --  —improbable, uno entre un millón por ventana— de que dos clases abiertas
  --  produzcan los mismos seis dígitos: gana aquella en la que el alumno SÍ
  --  está matriculado, y si no está en ninguna, la más reciente. Sin ese orden
  --  el veredicto dependería del plan de ejecución, que es la clase de cosa que
  --  cambia sola al añadir un índice.
  select s.id, s.section_id
    into v_match
    from public.attendance_sessions s
   where s.status = 'OPEN'
     and s.opened_at > now() - v_limite
     and (select v.vigente
            from public.asistencia_codigo_vigente(s.id, v_codigo) v)
   order by
     (exists (
        select 1 from public.enrollments e
         where e.section_id = s.section_id
           and e.student_id = v_yo
           and e.status = 'ENROLLED')) desc,
     s.opened_at desc
   limit 1;

  if not found then
    -- Hay clase abierta, pero ninguna reconoce esos dígitos: o están mal
    -- copiados, o el QR rotó mientras el alumno los tecleaba.
    return jsonb_build_object('estado', 'CODIGO_INVALIDO');
  end if;

  if not exists (
    select 1 from public.enrollments e
     where e.section_id = v_match.section_id
       and e.student_id = v_yo
       and e.status = 'ENROLLED'
  ) then
    -- El código es correcto, pero es de una clase que no cursa. No se devuelve
    -- el `seccionId` a propósito: no le sirve para nada y no hay razón para
    -- regalarle el identificador de una sección ajena.
    return jsonb_build_object('estado', 'NO_INSCRITO');
  end if;

  if exists (
    select 1 from public.attendance_marks m
     where m.session_id = v_match.id
       and m.student_id = v_yo
  ) then
    -- El único es (session_id, student_id), no (día, student_id): una clase
    -- puede tener varias sesiones el mismo día —mañana y tarde— y las dos
    -- cuentan. Por eso el mensaje que la UI deriva de aquí dice «en esta
    -- clase», y no «hoy», que sería falso.
    return jsonb_build_object('estado', 'YA_MARCADO', 'sesionId', v_match.id);
  end if;

  return jsonb_build_object(
    'estado', 'OK',
    'sesionId', v_match.id,
    'seccionId', v_match.section_id
  );
end;
$$;

comment on function public.asistencia_resolver_codigo(text) is
  'De los seis dígitos a la sesión abierta, con `auth.uid()` como identidad real (D21). Devuelve un veredicto —OK, CODIGO_INVALIDO, SIN_SESION_ACTIVA, NO_INSCRITO, YA_MARCADO— para que la UI pueda explicar qué pasó. El alumno no tiene política de SELECT sobre attendance_sessions, así que la sesión no se puede resolver en el cliente.';

revoke all on function public.asistencia_resolver_codigo(text)
  from public, anon;
grant execute on function public.asistencia_resolver_codigo(text)
  to authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 4 — Autocomprobación
-- ---------------------------------------------------------------------------
--  HERMÉTICA, como manda la convención del repositorio (ver 202609260004): sólo
--  inspecciona catálogos. No inserta sesiones ni lee perfiles, porque en una
--  base limpia —la que construye el arnés aplicando SÓLO migraciones— esas
--  tablas están vacías y una comprobación que dependa de ellas aborta el
--  despliegue entero.
--
--  La comprobación FUNCIONAL —que un alumno real marque de verdad— vive en
--  `supabase/tests/validate.mjs`, sección 20, que es donde hay datos. Aquí sólo
--  se afirma que la causa del fallo ya no está: la política apunta a una función
--  que `authenticated` SÍ puede ejecutar.
do $$
declare
  v_check text;
  v_def   boolean;
begin
  -- 1. La política llama a la función nueva.
  select p.with_check into v_check
    from pg_policies p
   where p.schemaname = 'public'
     and p.tablename = 'attendance_marks'
     and p.policyname = 'attendance_marks_estudiante_insert';

  if v_check is null or position('asistencia_puede_marcar' in v_check) = 0 then
    raise exception
      'La política del alumno no apunta a asistencia_puede_marcar (with_check = %).',
      coalesce(v_check, 'NULL')
      using errcode = '23514';
  end if;

  -- 2. Y no quedó llamando a la función revocada, que es el fallo que cierra
  --    esta migración. Se busca la llamada con paréntesis para no confundirla
  --    con el nombre de la función nueva, que la contiene como subcadena.
  if position('asistencia_codigo_vigente(' in v_check) > 0 then
    raise exception
      'La política sigue llamando a asistencia_codigo_vigente, que authenticated no puede ejecutar.'
      using errcode = '23514';
  end if;

  -- 3. El alumno SÍ puede ejecutar la que la política necesita; el anónimo no.
  if not has_function_privilege(
           'authenticated',
           'public.asistencia_puede_marcar(uuid, text)',
           'EXECUTE') then
    raise exception
      'authenticated no puede ejecutar asistencia_puede_marcar: la política volvería a ser inalcanzable.'
      using errcode = '23514';
  end if;

  if has_function_privilege(
       'anon',
       'public.asistencia_puede_marcar(uuid, text)',
       'EXECUTE') then
    raise exception 'anon no debe poder ejecutar asistencia_puede_marcar.'
      using errcode = '23514';
  end if;

  -- 4. El resolutor de D21 existe, es `security definer` (tiene que leer
  --    attendance_sessions, que el alumno no ve) y tiene el mismo reparto de
  --    permisos.
  select p.prosecdef into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'asistencia_resolver_codigo';

  if v_def is distinct from true then
    raise exception 'asistencia_resolver_codigo no quedó security definer.'
      using errcode = '23514';
  end if;

  if not has_function_privilege(
           'authenticated',
           'public.asistencia_resolver_codigo(text)',
           'EXECUTE') then
    raise exception 'authenticated no puede ejecutar asistencia_resolver_codigo.'
      using errcode = '23514';
  end if;

  if has_function_privilege(
       'anon',
       'public.asistencia_resolver_codigo(text)',
       'EXECUTE') then
    raise exception 'anon no debe poder ejecutar asistencia_resolver_codigo.'
      using errcode = '23514';
  end if;

  -- 5. La política de UPDATE del docente existe y lleva `with check`: sin él,
  --    el docente podría mudar su sesión a una sección que no dicta.
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'attendance_sessions'
       and policyname = 'attendance_sessions_docente_update'
       and cmd = 'UPDATE'
       and with_check is not null
  ) then
    raise exception
      'Falta attendance_sessions_docente_update con su with_check: el botón «Cerrar» del docente volvería a afectar 0 filas.'
      using errcode = '23514';
  end if;

  raise notice 'Autocomprobación 202609270001: la política del alumno ya es alcanzable (asistencia_puede_marcar), el docente puede cerrar su sesión y el resolutor de código de D21 está en pie.';
end;
$$;
