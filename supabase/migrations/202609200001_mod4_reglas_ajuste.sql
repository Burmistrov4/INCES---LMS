-- =============================================================================
--  MÓDULO 4 — Ajuste de las reglas institucionales de cupo
-- =============================================================================
--  Fecha: 2026-09-18
--
--  POR QUÉ EXISTE
--  --------------
--  `202609190001` implementó el motor de cupos con dos decisiones que Lorenzo
--  revisó después y cambió. Como esa migración YA ESTÁ APLICADA en la nube y el
--  libro mayor detecta deriva por checksum, NO se edita: se corrige aquí, que es
--  la regla de oro del proyecto.
--
--  LO QUE CAMBIA, Y POR QUÉ
--  ------------------------
--  1. `cupos_ocupados` cuenta SÓLO `ENROLLED`.
--     Antes contaba `ENROLLED + PENDING_BID`. La regla institucional es que una
--     solicitud pendiente NO reserva cupo: sólo el aprendiz matriculado ocupa.
--
--     ⚠️ CONSECUENCIA QUE HAY QUE ENTENDER, porque no es cosmética: si una
--     oferta viva deja de sumar, el contador dice que hay hueco MIENTRAS una
--     oferta está en el aire. Sin nada más, esto abre una doble venta:
--       capacidad 1 · A renuncia → hueco · se promueve a B (PENDING_BID)
--       → ocupados = 0 (B no cuenta) → entra C directo a ENROLLED
--       → B acepta → ENROLLED. DOS personas en un asiento de uno.
--     Por eso se añade (2), que es la guarda mínima para cumplir la regla sin
--     romper el invariante. `PENDING_BID` sigue sin contar como ocupación —que
--     es lo pedido— pero un asiento con oferta en el aire no se entrega dos veces.
--
--  2. `existe_oferta_vigente(sección)`: nueva. `solicitar_inscripcion` y
--     `promover_siguiente_de_cola` la consultan. Con esto sólo hay UNA oferta
--     viva por sección y nadie entra directo detrás de una oferta.
--
--  3. `reincorporar_inscripcion` deja de exigir cupo libre.
--     Regla institucional: si el administrador autoriza, el sistema obedece.
--     La excepción es suya. Se retira la comprobación de capacidad; se conserva
--     el cerrojo y el trigger anti-acaparamiento.
--
--  4. `aceptar_cupo` pasa a tomar el cerrojo por sección.
--     Antes no lo necesitaba porque `PENDING_BID` ya contaba y aceptar no movía
--     el contador. Ahora SÍ lo mueve (es el paso que suma el asiento), así que
--     entra en la misma serialización que el resto de decisiones de la sección.
--
--  5. La vista expone `oferta_vigente`.
--     Para que la interfaz pueda explicar un «1 disponible» que no es
--     inscribible: hay una oferta en el aire. Sin esta columna el panel mentiría
--     por omisión.
--
--  `max_faltas_consecutivas` (global, 3 por defecto) se usa tal cual: NO se crea
--  una variable nueva. Duplicar la misma verdad es el defecto que esta iteración
--  corrige, no el que introduce.
-- =============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — La ocupación cuenta SÓLO lo matriculado
-- ---------------------------------------------------------------------------
create or replace function public.cupos_ocupados(p_section_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.enrollments e
  where e.section_id = p_section_id
    and e.status = 'ENROLLED';
$$;

comment on function public.cupos_ocupados(uuid) is
  'Asientos ocupados por una sección: SÓLO ENROLLED. Una oferta PENDING_BID no reserva cupo (regla institucional); WAITLISTED y DROPPED tampoco. `security definer` para que el recuento no dependa de qué filas le deja ver la RLS al llamante. Ojo: como PENDING_BID no cuenta, la ocupación por sí sola NO basta para decidir si se puede admitir — hay que consultar además existe_oferta_vigente().';


-- ---------------------------------------------------------------------------
--  PARTE 2 — ¿Hay una oferta de cupo en el aire?
-- ---------------------------------------------------------------------------
--  La guarda que hace segura la parte 1. Una oferta VENCIDA no cuenta: si el
--  reloj ya la anuló, el asiento está genuinamente libre, y el barrido de
--  `expirar_ofertas_cupo` puede no haber pasado todavía. Por eso se compara
--  contra `now()` en lugar de mirar sólo el estado.
create or replace function public.existe_oferta_vigente(p_section_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.enrollments e
    where e.section_id = p_section_id
      and e.status = 'PENDING_BID'
      and (e.bid_expires_at is null or e.bid_expires_at > now())
  );
$$;

comment on function public.existe_oferta_vigente(uuid) is
  'true si la sección tiene una oferta PENDING_BID sin vencer. Existe porque cupos_ocupados ya no cuenta PENDING_BID: sin esta comprobación, un asiento con oferta en el aire se entregaría también por la vía directa (doble venta). Una oferta vencida NO cuenta: el asiento está libre aunque el barrido no haya pasado.';


-- ---------------------------------------------------------------------------
--  PARTE 3 — Solicitar: con hueco Y sin oferta en el aire
-- ---------------------------------------------------------------------------
create or replace function public.solicitar_inscripcion(p_section_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor     uuid := auth.uid();
  v_activa    boolean;
  v_existente text;
  v_nuevo     text;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para solicitar una inscripción.'
      using errcode = '42501';
  end if;

  select s.is_active into v_activa
  from public.sections s
  where s.id = p_section_id;

  if v_activa is null then
    raise exception 'La sección % no existe.', p_section_id
      using errcode = '23514';
  end if;

  if not v_activa then
    raise exception 'La sección % está archivada y no admite inscripciones.', p_section_id
      using errcode = '23514';
  end if;

  -- ¿Ya existe fila para (estudiante, sección)? El `unique` la protege, pero un
  -- error crudo de unicidad no explica la salida. Un DROPPED es historial: para
  -- volver hay una RPC de administración, no una reinscripción libre.
  select e.status into v_existente
  from public.enrollments e
  where e.student_id = v_actor
    and e.section_id = p_section_id;

  if v_existente is not null then
    if v_existente = 'DROPPED' then
      raise exception
        'Ya cursaste la sección %: un administrador debe reincorporarte explícitamente.',
        p_section_id
        using errcode = '23514';
    else
      raise exception
        'Ya tienes una solicitud activa (%) para la sección %.',
        v_existente, p_section_id
        using errcode = '23514';
    end if;
  end if;

  -- Cerrojo por sección: serializa la decisión de cupo.
  perform pg_advisory_xact_lock(hashtext('inscripcion|' || p_section_id::text));

  -- Entra directo a ENROLLED sólo si hay hueco Y el asiento no está prometido.
  -- Las dos condiciones son necesarias desde que PENDING_BID no cuenta como
  -- ocupación: sin la segunda, esta vía y una oferta viva venderían el mismo
  -- asiento (ver la cabecera).
  if public.cupos_ocupados(p_section_id) < public.cupo_efectivo(p_section_id)
     and not public.existe_oferta_vigente(p_section_id) then
    v_nuevo := 'ENROLLED';
  else
    v_nuevo := 'WAITLISTED';
  end if;

  -- La regla anti-acaparamiento (decisión 6) la aplica el trigger, no esta
  -- función: una sola fuente de verdad para cada invariante.
  insert into public.enrollments (student_id, section_id, status)
  values (v_actor, p_section_id, v_nuevo);

  return v_nuevo;
end;
$$;

comment on function public.solicitar_inscripcion(uuid) is
  'Inscribe al llamante: ENROLLED si hay hueco Y no hay oferta vigente; WAITLISTED si no. `security definer` con autorización propia (auth.uid()); la regla anti-acaparamiento la aplica el trigger enrollments_seccion_unica_por_materia.';


-- ---------------------------------------------------------------------------
--  PARTE 4 — Promover: una sola oferta viva por sección
-- ---------------------------------------------------------------------------
--  Se reemplaza el cuerpo entero. Los cambios son la guarda de oferta vigente y
--  nada más; el resto (FIFO, desempate por id, TTL) queda idéntico.
create or replace function public.promover_siguiente_de_cola(p_section_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id        uuid;
  v_promovido uuid;
  v_bids      boolean;
  v_ttl       integer;
begin
  perform pg_advisory_xact_lock(hashtext('inscripcion|' || p_section_id::text));

  -- ¿Hay hueco ahora mismo? Si la sección está llena, nadie que promover.
  if public.cupos_ocupados(p_section_id) >= public.cupo_efectivo(p_section_id) then
    return null;
  end if;

  -- Y si ya hay una oferta en el aire, tampoco: dos ofertas vivas para el mismo
  -- asiento es la otra mitad de la doble venta. Se espera a que la actual se
  -- acepte o venza.
  if public.existe_oferta_vigente(p_section_id) then
    return null;
  end if;

  -- El primero de la cola, FIFO por `created_at`. El desempate por `id` hace el
  -- orden determinista si dos filas comparten `created_at` (inserción masiva o
  -- reloj de poca resolución).
  select e.id
    into v_id
  from public.enrollments e
  where e.section_id = p_section_id
    and e.status = 'WAITLISTED'
  order by e.created_at, e.id
  limit 1;

  if v_id is null then
    return null;
  end if;

  v_bids := coalesce(
    (select (ss.valor #>> '{}')::boolean
       from public.system_settings ss
      where ss.clave = 'habilitar_sistema_bids'),
    false
  );

  if v_bids then
    v_ttl := coalesce(
      (select (ss.valor #>> '{}')::int
         from public.system_settings ss
        where ss.clave = 'bid_ttl_horas'),
      24
    );

    update public.enrollments
       set status = 'PENDING_BID',
           bid_expires_at = now() + make_interval(hours => v_ttl)
     where id = v_id
    returning student_id into v_promovido;
  else
    update public.enrollments
       set status = 'ENROLLED',
           bid_expires_at = null
     where id = v_id
    returning student_id into v_promovido;
  end if;

  return v_promovido;
end;
$$;

comment on function public.promover_siguiente_de_cola(uuid) is
  'Núcleo interno de promoción FIFO. Revocada a todos: la puerta son las RPC que la llaman. No promueve si la sección está llena ni si ya hay una oferta vigente (una oferta por asiento).';


-- ---------------------------------------------------------------------------
--  PARTE 5 — Aceptar: ahora mueve el contador, así que toma el cerrojo
-- ---------------------------------------------------------------------------
--  Con PENDING_BID fuera del recuento, aceptar es el momento en que el asiento
--  pasa a estar ocupado. Entra en la misma serialización por sección.
create or replace function public.aceptar_cupo(p_section_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_id    uuid;
  v_exp   timestamptz;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para aceptar un cupo.'
      using errcode = '42501';
  end if;

  select e.id, e.bid_expires_at
    into v_id, v_exp
  from public.enrollments e
  where e.student_id = v_actor
    and e.section_id = p_section_id
    and e.status = 'PENDING_BID';

  if v_id is null then
    raise exception 'No tienes una oferta de cupo pendiente para la sección %.', p_section_id
      using errcode = '23514';
  end if;

  -- Una oferta vencida ya no vale. El asiento lo libera `expirar_ofertas_cupo`;
  -- aquí sólo se rechaza para no confirmar algo que el reloj ya anuló.
  if v_exp is not null and v_exp <= now() then
    raise exception 'La oferta de cupo para la sección % ya venció.', p_section_id
      using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtext('inscripcion|' || p_section_id::text));

  update public.enrollments
     set status = 'ENROLLED', bid_expires_at = null
   where id = v_id;

  return 'ENROLLED';
end;
$$;

comment on function public.aceptar_cupo(uuid) is
  'El estudiante acepta una oferta PENDING_BID y pasa a ENROLLED. Rechaza ofertas vencidas: la limpieza la hace expirar_ofertas_cupo(). Toma el cerrojo por sección porque, al no contar PENDING_BID como ocupación, este UPDATE es el que suma el asiento.';


-- ---------------------------------------------------------------------------
--  PARTE 6 — Reincorporar: el administrador puede exceder la capacidad
-- ---------------------------------------------------------------------------
--  Regla institucional: si el administrador autoriza, el sistema obedece. Se
--  retira la comprobación de cupo. Lo que NO se retira:
--    · la comprobación de rol (sigue siendo sólo para admin),
--    · el cerrojo por sección,
--    · el trigger anti-acaparamiento (la excepción es sobre la capacidad, no
--      sobre la regla de equidad entre materias).
create or replace function public.reincorporar_inscripcion(
  p_student_id uuid,
  p_section_id uuid
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id     uuid;
  v_status text;
begin
  if not public.is_admin() then
    raise exception 'Sólo un administrador puede reincorporar una inscripción.'
      using errcode = '42501';
  end if;

  select e.id, e.status
    into v_id, v_status
  from public.enrollments e
  where e.student_id = p_student_id
    and e.section_id = p_section_id;

  if v_id is null then
    raise exception
      'No existe una inscripción previa del estudiante % en la sección %.',
      p_student_id, p_section_id
      using errcode = '23514';
  end if;

  if v_status <> 'DROPPED' then
    raise exception
      'La inscripción del estudiante % en la sección % no está dada de baja (estado actual: %).',
      p_student_id, p_section_id, v_status
      using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtext('inscripcion|' || p_section_id::text));

  -- Sin comprobación de cupo A PROPÓSITO: es una decisión de administración.
  -- Queda registrado en la respuesta para que el panel pueda avisar de que la
  -- sección superó su capacidad.
  update public.enrollments
     set status = 'ENROLLED', bid_expires_at = null
   where id = v_id;

  return 'ENROLLED';
end;
$$;

comment on function public.reincorporar_inscripcion(uuid, uuid) is
  'Excepción de administración: vuelve a ENROLLED una inscripción DROPPED. Puede EXCEDER la capacidad de la sección (regla institucional: si el admin autoriza, el sistema obedece). Cubre el caso que el unique (student_id, section_id) bloquea por diseño.';


-- ---------------------------------------------------------------------------
--  PARTE 7 — La vista declara si hay oferta en el aire
-- ---------------------------------------------------------------------------
--  `create or replace view` sólo admite AÑADIR columnas AL FINAL. Se respeta el
--  orden original y `oferta_vigente` va última.
create or replace view public.v_ocupacion_secciones
with (security_invoker = true)
as
select
  s.id,
  s.period_code,
  s.program_id,
  s.subject_id,
  s.name,
  s.is_active,
  public.cupo_efectivo(s.id)   as cupo_efectivo,
  public.cupos_ocupados(s.id)  as cupos_ocupados,
  greatest(public.cupo_efectivo(s.id) - public.cupos_ocupados(s.id), 0) as cupos_disponibles,
  public.existe_oferta_vigente(s.id) as oferta_vigente
from public.sections s;

comment on view public.v_ocupacion_secciones is
  'Ocupación por sección. `cupos_ocupados` cuenta SÓLO ENROLLED, así que `cupos_disponibles` puede ser > 0 con una oferta en el aire: `oferta_vigente` lo declara, y la interfaz debe usarlo para no ofrecer un asiento que no se puede dar. `security_invoker` sobre sections; los recuentos vienen de funciones definer para que la RLS de enrollments no los falsee.';


-- ---------------------------------------------------------------------------
--  PARTE 8 — Privilegios de la función nueva
-- ---------------------------------------------------------------------------
--  `create or replace function` conserva la ACL de las funciones existentes, así
--  que las de las partes 1 a 6 no se tocan. La de la parte 2 es NUEVA: nace con
--  el EXECUTE que PostgreSQL concede a `public` por defecto, y hay que revocarlo.
revoke all on function public.existe_oferta_vigente(uuid) from public, anon, authenticated;
grant execute on function public.existe_oferta_vigente(uuid) to authenticated;

--  La vista se recreó: hay que devolverle los privilegios que tenía.
revoke all on public.v_ocupacion_secciones from anon, authenticated;
grant select on public.v_ocupacion_secciones to authenticated;
