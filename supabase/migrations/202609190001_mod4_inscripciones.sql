-- ============================================================================
--  INCES LMS — Módulo 4: Inscripciones y Cupos
--  Archivo: 202609190001_mod4_inscripciones.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  Hasta ahora la inscripción no tenía motor: `enrollments_insert_own`
--  (202609100001_init.sql:225) dejaba a cualquier autenticado insertar su propia
--  fila con `status = 'ENROLLED'`, y `enrollments_update_own` (:231) permitía
--  subir de WAITLISTED a ENROLLED sin comprobar nada. La clave publishable viaja
--  al cliente, así que un "motor de cupos" que viviera sólo en la app sería
--  decorativo. Este archivo mueve la frontera de seguridad a la BASE DE DATOS.
--
--  DECISIONES (cerradas con el dueño del producto)
--  ------------------------------------------------
--  1. Las escrituras sobre `enrollments` pasan a funciones RPC `security
--     definer`, y se revocan los INSERT/UPDATE/DELETE directos a `authenticated`.
--     Se conservan `enrollments_read_own` (el estudiante ve lo suyo) y
--     `enrollments_admin_all` (lectura de admin).
--  2. `unique (student_id, section_id)` se mantiene: un DROPPED conserva su fila
--     como historial. Reincorporar (volver a ENROLLED) es una excepción
--     explícita de administración, con su propia RPC.
--  3. El sistema de bids es opcional (`habilitar_sistema_bids`).
--       · Apagado: la inscripción pasa directo a ENROLLED; sin cupo, a
--         WAITLISTED. Al liberarse un cupo, el primero de la cola pasa a
--         ENROLLED.
--       · Encendido: al liberarse un cupo, el primero de la cola pasa a
--         PENDING_BID con `bid_expires_at = now() + bid_ttl_horas`; aceptar →
--         ENROLLED; vencer → DROPPED y se promueve al siguiente.
--  4. La expiración es una RPC idempotente (`expirar_ofertas_cupo`), no un
--     planificador concreto. El despliegue es dual (nube/local) y hay cortes
--     eléctricos: depender de `pg_cron` dejaría ofertas colgadas para siempre.
--     La llama el backend cuando toca cerrar el ciclo; repetirla es inocuo.
--  5. Jerarquía de cupo: manda `sections.max_capacity`; si es nulo, cae a
--     `system_settings.cupo_maximo_por_seccion`; si tampoco, 0.
--  6. Un estudiante no puede tener dos secciones de la misma materia en el mismo
--     lapso (para que no acapare cupos). El `unique` actual no lo impide (cruza
--     dos tablas), así que hay un trigger que cruza `enrollments` con
--     `sections`.
--
--  `security definer` OBLIGA A AUTORIZAR A MANO (lección R-20)
--  -----------------------------------------------------------
--  Una función `definer` corre con los privilegios de su dueño y SE SALTA la
--  RLS de `enrollments`. Por eso cada RPC hace su propia autorización con
--  `auth.uid()` (y `is_admin()` donde toca) y fija `search_path = public,
--  pg_temp`. La RLS ya no es la red de seguridad de estas escrituras: lo es la
--  autorización explícita de cada función. Conceder EXECUTE de más aquí sería
--  abrir la puerta que este archivo viene a cerrar.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 0 — `sections.max_capacity` pasa a ser NULLABLE
-- ---------------------------------------------------------------------------
--  Nació `integer not null default 0` (202609160001:226). Con NOT NULL, el
--  fallback al parámetro global de la decisión 5 NUNCA podría dispararse: 0 es
--  un valor, no "sin definir". Se suelta el NOT NULL para que el nulo signifique
--  "usa el cupo por defecto del sistema". No hay riesgo de datos: la nube tiene
--  0 filas en `sections`. El `check (max_capacity >= 0)` se mantiene a
--  propósito: un CHECK pasa con NULL, así que sigue siendo válido.
alter table public.sections alter column max_capacity drop not null;


-- ---------------------------------------------------------------------------
--  PARTE 1 — El interruptor del sistema de bids
-- ---------------------------------------------------------------------------
--  Mismo idioma que la semilla de 202609120002: idempotente y NO destructiva
--  (`on conflict do nothing`), para que reaplicar la migración nunca pise lo que
--  el administrador ya configuró.
--
--  `bid_ttl_horas` YA existe (categoría `inscripciones`): aquí NO se duplica.
--  Crear un segundo sitio con la misma verdad es justo el defecto que esta fase
--  corrige en el cupo.
insert into public.system_settings
  (clave, valor, tipo, descripcion, categoria, es_publico)
values
  ('habilitar_sistema_bids', 'false'::jsonb, 'boolean',
   'Si está activo, al liberarse un cupo se ofrece al primero de la cola con vencimiento (PENDING_BID); si no, pasa directo a ENROLLED.',
   'inscripciones', false)
on conflict (clave) do nothing;


-- ---------------------------------------------------------------------------
--  PARTE 2 — El cupo efectivo y los asientos ocupados
-- ---------------------------------------------------------------------------
--  Fuente única de la decisión 5, usada por las RPC y por la vista de ocupación.
--
--  `security definer` aunque sea sólo lectura: `cupo_maximo_por_seccion` es un
--  parámetro PRIVADO (`es_publico = false`), así que un estudiante no puede
--  leerlo por RLS. Sin `definer`, el fallback devolvería NULL para él, `coalesce`
--  caería a 0 y la sección parecería llena: nadie podría inscribirse. Devuelve
--  un solo entero y no expone nada sensible: el cupo es información que el
--  estudiante necesita conocer.
create or replace function public.cupo_efectivo(p_section_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select s.max_capacity from public.sections s where s.id = p_section_id),
    (select (ss.valor #>> '{}')::int
       from public.system_settings ss
      where ss.clave = 'cupo_maximo_por_seccion'),
    0
  );
$$;

comment on function public.cupo_efectivo(uuid) is
  'Cupo efectivo de una sección: coalesce(max_capacity, cupo_maximo_por_seccion, 0). `security definer` porque el parámetro global es privado y con la RLS del llamante el fallback devolvería 0.';

--  Cuántos asientos consume hoy una sección. ENROLLED y PENDING_BID ocupan: una
--  oferta viva reserva el asiento, así que cuenta. WAITLISTED y DROPPED no.
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
    and e.status in ('ENROLLED', 'PENDING_BID');
$$;

comment on function public.cupos_ocupados(uuid) is
  'Asientos consumidos por una sección (ENROLLED + PENDING_BID). `security definer` para que el recuento no dependa de qué filas le deja ver la RLS al llamante.';


-- ---------------------------------------------------------------------------
--  PARTE 3 — Anti-acaparamiento: una materia, una sección por lapso
-- ---------------------------------------------------------------------------
--  Decisión 6. El `unique (student_id, section_id)` no lo cubre: la regla cruza
--  `enrollments` con `sections` (materia + lapso). `security definer` porque el
--  chequeo tiene que ver TODAS las inscripciones vivas del estudiante, no sólo
--  las que la RLS dejaría ver a quien escribe.
create or replace function public.exigir_seccion_unica_por_materia()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_periodo varchar(10);
  v_materia uuid;
  v_otra    uuid;
begin
  -- Un DROPPED es historial: no ocupa ni bloquea. Sin esta salida, reincorporar
  -- o volver a solicitar tras una baja quedaría atrapado por la propia fila.
  if new.status = 'DROPPED' then
    return new;
  end if;

  select s.period_code, s.subject_id
    into v_periodo, v_materia
  from public.sections s
  where s.id = new.section_id;

  -- Si la sección no existe, la FK lo rechazará con un error más claro. Aquí se
  -- sale para no comparar contra NULL, que dejaría el chequeo ciego.
  if v_materia is null then
    return new;
  end if;

  -- Se excluye la propia fila (`e.id <> new.id`): en una promoción
  -- WAITLISTED→ENROLLED el estudiante no puede bloquearse a sí mismo.
  select e.id
    into v_otra
  from public.enrollments e
  join public.sections s2 on s2.id = e.section_id
  where e.student_id = new.student_id
    and e.id <> new.id
    and e.status <> 'DROPPED'
    and s2.subject_id = v_materia
    and s2.period_code = v_periodo
  limit 1;

  if v_otra is not null then
    raise exception
      'El estudiante % ya tiene una sección de la materia % en el lapso %. Un estudiante no puede acaparar cupos en dos secciones de la misma materia.',
      new.student_id, v_materia, v_periodo
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.exigir_seccion_unica_por_materia() is
  'Impide que un estudiante tenga dos secciones vivas de la misma materia en el mismo lapso (decisión 6 de M4). `security definer`: con la RLS del llamante sólo vería sus propias filas y el chequeo sería ciego.';

-- Filtra por columnas en el `of` para no disparar en cada `updated_at`: sólo
-- importa cuando cambia el estado o la sección.
drop trigger if exists enrollments_seccion_unica_por_materia on public.enrollments;
create trigger enrollments_seccion_unica_por_materia
before insert or update of status, section_id on public.enrollments
for each row execute function public.exigir_seccion_unica_por_materia();


-- ---------------------------------------------------------------------------
--  PARTE 4 — La máquina de estados, en funciones atómicas
-- ---------------------------------------------------------------------------
--  Toda decisión de cupo toma un cerrojo por sección con
--  `pg_advisory_xact_lock`. Sin él, dos solicitudes simultáneas por el último
--  asiento leerían «hay hueco» las dos y las dos insertarían: sobrecupo. El
--  cerrojo se libera al terminar la transacción y es reentrante, así que llamar
--  a una función que ya lo tomó no bloquea.
--
--  Los `raise exception` de regla de negocio usan `23514` (el backend los
--  traduce a 400 y muestra el mensaje tal cual). Los de autorización usan
--  `42501` (→ 403), que es el mismo código que produce la RLS y ya está
--  contemplado en el contrato de la API. Todos nombran la entidad concreta.


-- ---------------------------------------------------------------------------
--  4.1 Solicitar una inscripción (el estudiante se inscribe a sí mismo)
-- ---------------------------------------------------------------------------
--  Devuelve el estado resultante: 'ENROLLED' si había hueco, 'WAITLISTED' si no.
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

  -- Decisión 3 y 5: con hueco, directo a ENROLLED (los bids sólo actúan al
  -- liberarse un cupo, no en la solicitud inicial); sin hueco, a la cola.
  if public.cupos_ocupados(p_section_id) < public.cupo_efectivo(p_section_id) then
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
  'Inscribe al llamante en una sección: ENROLLED si hay cupo, WAITLISTED si no. `security definer` con autorización propia (auth.uid()); la regla anti-acaparamiento la aplica el trigger enrollments_seccion_unica_por_materia.';


-- ---------------------------------------------------------------------------
--  4.2 Aceptar una oferta de cupo (PENDING_BID → ENROLLED)
-- ---------------------------------------------------------------------------
--  No cambia el número de asientos ocupados (PENDING_BID ya contaba), así que no
--  necesita cerrojo: no hay carrera de cupo que perder.
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

  update public.enrollments
     set status = 'ENROLLED', bid_expires_at = null
   where id = v_id;

  return 'ENROLLED';
end;
$$;

comment on function public.aceptar_cupo(uuid) is
  'El estudiante acepta una oferta PENDING_BID y pasa a ENROLLED. Rechaza ofertas vencidas: la limpieza la hace expirar_ofertas_cupo().';


-- ---------------------------------------------------------------------------
--  4.3 Renunciar a una inscripción (→ DROPPED) y liberar el cupo
-- ---------------------------------------------------------------------------
create or replace function public.renunciar_cupo(p_section_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor  uuid := auth.uid();
  v_id     uuid;
  v_status text;
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para renunciar a un cupo.'
      using errcode = '42501';
  end if;

  select e.id, e.status
    into v_id, v_status
  from public.enrollments e
  where e.student_id = v_actor
    and e.section_id = p_section_id;

  if v_id is null then
    raise exception 'No tienes ninguna inscripción en la sección %.', p_section_id
      using errcode = '23514';
  end if;

  if v_status = 'DROPPED' then
    raise exception 'Tu inscripción en la sección % ya estaba dada de baja.', p_section_id
      using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(hashtext('inscripcion|' || p_section_id::text));

  update public.enrollments
     set status = 'DROPPED', bid_expires_at = null
   where id = v_id;

  -- Liberar un cupo dispara la promoción del siguiente (decisión 3). Si la
  -- sección sigue llena —p. ej. había una oferta viva—, el promotor no hace nada.
  perform public.promover_siguiente_de_cola(p_section_id);

  return 'DROPPED';
end;
$$;

comment on function public.renunciar_cupo(uuid) is
  'El estudiante da de baja su inscripción (DROPPED) y libera el cupo, promoviendo al primero de la cola. `security definer` con autorización propia.';


-- ---------------------------------------------------------------------------
--  4.4 Promover al primero de la cola
-- ---------------------------------------------------------------------------
--  Núcleo interno: NO comprueba rol, porque lo invocan otras funciones ya
--  autorizadas (renuncia, expiración) y la RPC pública de abajo. Se revoca su
--  EXECUTE a todos: la puerta es quien la llama, no el cliente.
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
  'Núcleo interno: promueve al primero de la cola FIFO si hay cupo. Con bids apagado pasa a ENROLLED; con bids encendido, a PENDING_BID con vencimiento. No autoriza por sí misma: la llaman funciones ya autorizadas.';

-- RPC pública de administración: permite forzar la promoción a mano (p. ej.
-- tras una corrección manual de cupos).
create or replace function public.promover_siguiente(p_section_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Sólo un administrador puede forzar la promoción de la cola.'
      using errcode = '42501';
  end if;

  return public.promover_siguiente_de_cola(p_section_id);
end;
$$;

comment on function public.promover_siguiente(uuid) is
  'RPC de administración: fuerza la promoción del primero de la cola de una sección. Devuelve el id del estudiante promovido, o NULL si no había hueco o cola.';


-- ---------------------------------------------------------------------------
--  4.5 Expirar las ofertas de cupo (idempotente, sin planificador)
-- ---------------------------------------------------------------------------
--  Devuelve cuántas ofertas expiró. Se apoya en el reloj de la base, no en un
--  `pg_cron` (arquitectura dual + cortes eléctricos: un planificador dejaría
--  ofertas colgadas). Es segura de repetir: la segunda pasada devuelve 0.
create or replace function public.expirar_ofertas_cupo()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Se materializa la lista ANTES de tocar nada: iterar con un cursor sobre una
  -- consulta que se modifica en el propio bucle daría un recorrido indefinido.
  v_ids     uuid[];
  v_id      uuid;
  v_section uuid;
  v_total   integer := 0;
begin
  -- Orden por `section_id` para adquirir los cerrojos en un orden consistente:
  -- dos barridos simultáneos que los tomaran en distinto orden podrían abrazarse
  -- (deadlock). El desempate por vencimiento conserva la prioridad FIFO.
  select array_agg(e.id order by e.section_id, e.bid_expires_at, e.id)
    into v_ids
  from public.enrollments e
  where e.status = 'PENDING_BID'
    and e.bid_expires_at is not null
    and e.bid_expires_at <= now();

  if v_ids is null then
    return 0;
  end if;

  foreach v_id in array v_ids loop
    select e.section_id into v_section
    from public.enrollments e
    where e.id = v_id;

    -- La fila pudo desaparecer en cascada dentro de la misma transacción.
    if v_section is null then
      continue;
    end if;

    perform pg_advisory_xact_lock(hashtext('inscripcion|' || v_section::text));

    update public.enrollments
       set status = 'DROPPED', bid_expires_at = null
     where id = v_id
       and status = 'PENDING_BID';

    -- `found` tras el UPDATE: sólo cuenta y promueve si de verdad la expiró.
    if found then
      perform public.promover_siguiente_de_cola(v_section);
      v_total := v_total + 1;
    end if;
  end loop;

  return v_total;
end;
$$;

comment on function public.expirar_ofertas_cupo() is
  'Expira las ofertas PENDING_BID vencidas: las pasa a DROPPED y promueve al siguiente de la cola. Devuelve cuántas expiró. Idempotente y sin pg_cron: la llama el backend.';


-- ---------------------------------------------------------------------------
--  4.6 Reincorporar una inscripción dada de baja (excepción de administración)
-- ---------------------------------------------------------------------------
--  Decisión 2: el `unique (student_id, section_id)` impide reinscribirse en una
--  sección ya cursada. Esta es la vía explícita para volver a ENROLLED, sólo
--  para administradores y sólo si hay cupo (no se rompe el invariante
--  ocupados ≤ cupo).
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

  if public.cupos_ocupados(p_section_id) >= public.cupo_efectivo(p_section_id) then
    raise exception
      'No hay cupo disponible en la sección % para reincorporar al estudiante %.',
      p_section_id, p_student_id
      using errcode = '23514';
  end if;

  -- El trigger anti-acaparamiento sigue vigilando: si el estudiante ya tiene
  -- otra sección viva de la misma materia y lapso, esta reincorporación se
  -- rechaza. La excepción de administración es sobre el `unique`, no sobre la
  -- regla de equidad.
  update public.enrollments
     set status = 'ENROLLED', bid_expires_at = null
   where id = v_id;

  return 'ENROLLED';
end;
$$;

comment on function public.reincorporar_inscripcion(uuid, uuid) is
  'Excepción de administración: vuelve a ENROLLED una inscripción DROPPED, si hay cupo. Cubre el caso que el unique (student_id, section_id) bloquea por diseño.';


-- ---------------------------------------------------------------------------
--  PARTE 5 — Vista de ocupación
-- ---------------------------------------------------------------------------
--  `security_invoker` para que la RLS de `sections` decida qué secciones ve cada
--  quien (el admin todas, el estudiante las activas). Los recuentos salen de
--  funciones `definer` (`cupo_efectivo`, `cupos_ocupados`), así que NO dependen
--  de la RLS de `enrollments`: una vista `invoker` que contara filas de
--  `enrollments` directamente mostraría a cada estudiante sólo su propia
--  inscripción y el cupo parecería siempre vacío.
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
  greatest(public.cupo_efectivo(s.id) - public.cupos_ocupados(s.id), 0) as cupos_disponibles
from public.sections s;

comment on view public.v_ocupacion_secciones is
  'Ocupación por sección (cupos ocupados vs. cupo efectivo). `security_invoker` sobre sections; los recuentos vienen de funciones definer para que la RLS de enrollments no los falsee.';


-- ---------------------------------------------------------------------------
--  PARTE 6 — Frontera de seguridad: cerrar la escritura directa
-- ---------------------------------------------------------------------------
--  Aquí está el corazón de la decisión 1. Se quitan los GRANT de escritura a
--  `authenticated` (y de paso a `anon`, que no tiene nada que hacer con
--  `enrollments`) y se sueltan las tres políticas propias de escritura. Sin
--  esto, la RLS seguiría siendo la única barrera y `enrollments_insert_own`
--  dejaría al estudiante escribir su propia fila con ENROLLED.
--
--  `enrollments_read_own` y `enrollments_admin_all` SE CONSERVAN: la lectura
--  sigue por RLS. La cláusula de escritura de `enrollments_admin_all` queda
--  inerte al no haber GRANT de INSERT/UPDATE/DELETE, que es justo lo que se
--  busca: toda escritura pasa por las RPC.
revoke all on public.enrollments from anon, authenticated;
grant select on public.enrollments to authenticated;

drop policy if exists enrollments_insert_own on public.enrollments;
drop policy if exists enrollments_update_own on public.enrollments;
drop policy if exists enrollments_delete_own on public.enrollments;


-- ---------------------------------------------------------------------------
--  PARTE 7 — Índices que sostienen la cola y la expiración
-- ---------------------------------------------------------------------------
--  Cola FIFO: «primer WAITLISTED de una sección por created_at». Parcial sobre
--  el estado porque WAITLISTED es una minoría del histórico.
create index if not exists enrollments_cola_fifo_idx
  on public.enrollments (section_id, created_at)
  where status = 'WAITLISTED';

-- Expiración: «PENDING_BID con bid_expires_at vencido». Parcial sobre
-- PENDING_BID para que el barrido no recorra todo el histórico.
create index if not exists enrollments_oferta_vigente_idx
  on public.enrollments (bid_expires_at)
  where status = 'PENDING_BID';

-- Recuento de ocupación por sección (lo usan cupos_ocupados y la vista).
create index if not exists enrollments_ocupacion_idx
  on public.enrollments (section_id)
  where status in ('ENROLLED', 'PENDING_BID');

-- El trigger anti-acaparamiento busca por estudiante. Sin este índice, cada
-- inserción recorrería la tabla entera.
create index if not exists enrollments_student_idx
  on public.enrollments (student_id);


-- ---------------------------------------------------------------------------
--  PARTE 8 — Permisos de las funciones
-- ---------------------------------------------------------------------------
--  PostgreSQL concede EXECUTE a PUBLIC por defecto en toda función nueva: sin el
--  `revoke` explícito, `anon` podría llamar a las RPC. Se revoca de `public` y
--  `anon`, y se concede sólo a `authenticated` (que es quien tiene sesión; la
--  autorización fina la hace cada función con `auth.uid()` / `is_admin()`).
revoke all on function public.cupo_efectivo(uuid)                       from public, anon;
revoke all on function public.cupos_ocupados(uuid)                      from public, anon;
revoke all on function public.solicitar_inscripcion(uuid)               from public, anon;
revoke all on function public.aceptar_cupo(uuid)                        from public, anon;
revoke all on function public.renunciar_cupo(uuid)                      from public, anon;
revoke all on function public.promover_siguiente(uuid)                  from public, anon;
revoke all on function public.expirar_ofertas_cupo()                    from public, anon;
revoke all on function public.reincorporar_inscripcion(uuid, uuid)      from public, anon;

grant execute on function public.cupo_efectivo(uuid)                    to authenticated;
grant execute on function public.cupos_ocupados(uuid)                   to authenticated;
grant execute on function public.solicitar_inscripcion(uuid)            to authenticated;
grant execute on function public.aceptar_cupo(uuid)                     to authenticated;
grant execute on function public.renunciar_cupo(uuid)                   to authenticated;
grant execute on function public.promover_siguiente(uuid)               to authenticated;
grant execute on function public.expirar_ofertas_cupo()                 to authenticated;
grant execute on function public.reincorporar_inscripcion(uuid, uuid)   to authenticated;

-- Internas: ni siquiera `authenticated` las llama a mano. El núcleo de
-- promoción se alcanza sólo desde funciones ya autorizadas, y el trigger no es
-- invocable directamente (devuelve `trigger`).
revoke all on function public.promover_siguiente_de_cola(uuid)          from public, anon, authenticated;
revoke all on function public.exigir_seccion_unica_por_materia()        from public, anon, authenticated;

-- La vista de ocupación: sólo lectura, y sólo para autenticados (un `anon` no
-- tiene sesión que ocupar, y sus recuentos vienen de funciones definer que no
-- puede ejecutar).
revoke all on public.v_ocupacion_secciones from anon, authenticated;
grant select on public.v_ocupacion_secciones to authenticated;
