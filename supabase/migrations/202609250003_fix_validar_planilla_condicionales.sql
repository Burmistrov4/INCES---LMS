-- ============================================================================
--  INCES LMS — M4: un campo condicional deja de ser exigible cuando su
--                condición no se cumple
--  Archivo: 202609250003_fix_validar_planilla_condicionales.sql
--  Aplica con: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ RESUELVE
--  ------------
--  La auditoría de M4 (`AUDITORIA_M4.md`, 2026-09-25) encontró una trampa de un
--  solo clic, y el clic es justo la función que se acababa de entregar:
--
--    1. El panel `cpanel_inscripcion_campos_panel.dart` deja marcar «Obligatorio»
--       en CUALQUIER campo, incluido uno con `condicion`. No hay guarda en el
--       diálogo ni en el gateway.
--    2. El formulario del aspirante OCULTA el campo cuando la condición no se
--       cumple y lo OMITE de la planilla que envía (`visibleCon` en
--       `aspirante_form_screen.dart`).
--    3. `validar_planilla()` exigía todo campo `activo and obligatorio` **sin
--       leer `condicion`**. Lo decía, literalmente, el comentario de
--       `202609240001`: «quien decide qué es obligatorio es `validar_planilla()`
--       en la base, que no lee `condicion`».
--
--  El resultado: el aspirante rellena los nueve pasos, el formulario valida en
--  verde y el alta falla al final con un 23514 que nombra un campo que nunca vio.
--  La base no lo impedía: la única restricción de `inscripcion_campos` es el
--  formato de `codigo`.
--
--  Este archivo cierra la trampa por el lado de la base. El lado de la pantalla
--  se cierra en la misma entrega deshabilitando el interruptor cuando hay
--  condición.
--
--
--  MEDIDO ANTES DE ESCRIBIRLO, NO DEDUCIDO
--  ---------------------------------------
--  Contra la base real, el 2026-09-25:
--
--      inscripcion_campos     44 filas, 13 con obligatorio = true
--      con condicion != null   2   ·  `pueblo_indigena_cual` (pueblo_indigena = true)
--                                  ·  `tipo_discapacidad`    (discapacidad    = true)
--      de esos 2, obligatorios 0
--
--  Es decir: hoy la trampa NO está armada —ningún campo condicional es
--  obligatorio— y por eso este arreglo no cambia el comportamiento de ninguna
--  inscripción real. Se hace ahora, y no el día que alguien marque el
--  interruptor, porque entonces el fallo aparecería como «la inscripción no
--  funciona», sin relación aparente con el cambio que lo causó.
--
--
--  LA REGLA, Y POR QUÉ ES LA MISMA QUE YA TIENE EL CLIENTE
--  -----------------------------------------------------
--  `condicion` es `{"campo": "...", "igual": ...}`. El cliente lo evalúa en
--  `CondicionCampoInscripcion.seCumple` (`lib/models/inscripcion_campo.dart`) y
--  esta migración lo replica en `condicion_campo_se_cumple()`:
--
--    · `igual` es `true` o `1`   → se cumple si el campo vale `true` o `1`.
--    · `igual` es `false` o `0`  → se cumple si el campo vale `false` o `0`.
--    · cualquier otro valor      → se cumple si el campo vale exactamente eso.
--
--  Las dos particularidades se copian a propósito, porque son las que hacen que
--  las dos implementaciones coincidan:
--
--    · La comparación es de DOS LADOS. `true` y `1` son el mismo «sí» venga de
--      donde venga. Mirar sólo un lado es el error que `seCumple` ya tuvo una
--      vez; replicarlo aquí lo reintroduciría en la base.
--    · Un campo que no viaja en la planilla no cumple ninguna condición. Es lo
--      correcto: si el aspirante no marcó la casilla, la pregunta de detalle no
--      aparece —ni en la pantalla ni en la validación—.
--
--
--  POR QUÉ LA REGLA VIVE EN LA BASE Y NO SÓLO EN DART
--  -------------------------------------------------
--  ADR-003: la frontera de autorización es la RLS, no la API. Vale igual para la
--  coherencia de los datos. Si esta regla viviera sólo en el formulario, una
--  petición fabricada a mano —o el cliente viejo que aún manda `{}`— seguiría
--  pasando por la puerta de atrás. `validar_planilla()` es la MISMA función que
--  usan las dos puertas de escritura (`handle_new_user()` en el alta y
--  `validar_planilla_guardada()` en la corrección posterior), así que se arregla
--  una vez y queda arreglado en las dos.
--
--
--  LO QUE ESTA MIGRACIÓN NO HACE
--  ----------------------------
--  · NO edita `202609250001`, que ya está aplicada — y una migración aplicada no
--    se edita nunca: su checksum está en el libro mayor y el script de aplicación
--    se negaría a continuar por deriva. Por eso el cuerpo de `validar_planilla`
--    se vuelve a copiar aquí entero, con su línea nueva. El comentario obsoleto
--    de `202609240001` («no lee `condicion`») se deja como está: envejeció, pero
--    editarlo sería falsear el registro de lo que se aplicó.
--  · NO cambia los privilegios de `validar_planilla()`. Hoy `authenticated` puede
--    ejecutarla por el privilegio por defecto, y eso es DELIBERADO:
--    `202609240002` documenta que el envoltorio es `security definer` para no
--    depender de ello, pero se prefiere no tocar el privilegio.
--  · NO toca la tolerancia transitoria de D14 ni el resolutor de programas.
--  · NO valida tipos: `validar_planilla()` valida FORMA. Los tipos los valida Zod
--    en el backend y el propio formulario.
-- ============================================================================


-- ---------------------------------------------------------------------------
--  PARTE 1 — La regla de la condición, en una función con nombre
-- ---------------------------------------------------------------------------
-- Se aísla en su propia función por dos motivos: el `where` de `validar_planilla`
-- ya tiene cinco comprobaciones de «vacío» y meter la condición ahí lo volvería
-- ilegible; y una regla con nombre se puede probar sola.
--
-- `immutable` y sin `security definer`: no lee ninguna tabla, sólo sus dos
-- argumentos. Como no toca tablas tampoco necesita `search_path` propio —todo lo
-- que usa (`jsonb_typeof`, `btrim` y los operadores de `jsonb`) vive en
-- `pg_catalog`, que siempre está en la ruta—.
create or replace function public.condicion_campo_se_cumple(
  p_condicion jsonb,
  p_valores   jsonb
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_valores   jsonb := p_valores;
  v_campo     text;
  v_igual     jsonb;
  v_actual    jsonb;
  v_espera_si boolean;
  v_espera_no boolean;
begin
  -- Un campo sin condición es incondicional: su obligatoriedad se exige siempre.
  -- Se devuelve `true` y no `false` a propósito: esta función responde a la
  -- pregunta «¿hay que exigir este campo?», no a «¿se cumple la condición?».
  if p_condicion is null
     or jsonb_typeof(p_condicion) <> 'object'
     or not (p_condicion ? 'campo') then
    return true;
  end if;

  v_campo := p_condicion ->> 'campo';

  -- Una condición sin campo al que mirar no se puede evaluar. Se trata como
  -- incondicional y no como «nunca se cumple»: lo segundo dejaría el campo
  -- permanentemente inexigible por un error de tecleo en el catálogo, y el fallo
  -- sería mudo.
  if v_campo is null or btrim(v_campo) = '' then
    return true;
  end if;

  if v_valores is null or jsonb_typeof(v_valores) <> 'object' then
    v_valores := '{}'::jsonb;
  end if;

  -- La clave ausente y el JSON `null` se colapsan en el mismo caso. En el
  -- formulario también: `valores[campo]` da `null` en los dos.
  v_actual := v_valores -> v_campo;

  v_igual := p_condicion -> 'igual';

  -- Lado «sí»: `igual` vale `true` o `1`.
  v_espera_si := coalesce(v_igual = 'true'::jsonb or v_igual = '1'::jsonb, false);
  if v_espera_si then
    return coalesce(v_actual = 'true'::jsonb or v_actual = '1'::jsonb, false);
  end if;

  -- Lado «no»: `igual` vale `false` o `0`.
  v_espera_no := coalesce(v_igual = 'false'::jsonb or v_igual = '0'::jsonb, false);
  if v_espera_no then
    return coalesce(v_actual = 'false'::jsonb or v_actual = '0'::jsonb, false);
  end if;

  -- `igual` ausente o JSON `null`. En el cliente, `actual == igual` es verdadero
  -- justo cuando el campo referenciado no viaja en el mapa, así que se replica
  -- aquí para que las dos implementaciones no discrepen. Hoy el catálogo no tiene
  -- ningún caso así —los dos campos condicionales usan `igual: true`—, pero la
  -- función se escribe para la forma del dato, no para la semilla de hoy.
  if v_igual is null or v_igual = 'null'::jsonb then
    return v_actual is null or v_actual = 'null'::jsonb;
  end if;

  -- Cualquier otro valor: comparación exacta.
  return coalesce(v_actual = v_igual, false);
end;
$$;

comment on function public.condicion_campo_se_cumple(jsonb, jsonb) is
  'Responde «¿hay que exigir este campo?»: `true` si el campo no tiene condición y, si la tiene, `true` sólo cuando se cumple contra los valores enviados. Réplica exacta de `CondicionCampoInscripcion.seCumple` en `lib/models/inscripcion_campo.dart`: `true`/`1` son el mismo «sí» y `false`/`0` el mismo «no», en los DOS lados, y una clave ausente no cumple ninguna condición.';

-- Sólo la llaman funciones `security definer` del propio esquema. Se cierra la
-- puerta a que un cliente la invoque por RPC, igual que se hizo con
-- `resolver_programa_inscripcion()`. Como el llamante es `validar_planilla()`,
-- que es `security definer`, la llamada interna se evalúa contra el dueño y este
-- `revoke` no la estorba.
revoke all on function public.condicion_campo_se_cumple(jsonb, jsonb)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
--  PARTE 2 — `validar_planilla()` aprende a leer la condición
-- ---------------------------------------------------------------------------
-- Cuerpo copiado LITERAL de `202609250001` (líneas 264-315), que a su vez lo
-- copió de `202609240001`, con UN cambio: la condición añadida al `where` del
-- `array_agg`. Todo lo demás —la normalización de `null`, el rechazo de lo que
-- no es objeto, las cinco formas de «vacío», el mensaje que nombra los campos y
-- el bloque de D14— se copia sin cambiar una coma.
create or replace function public.validar_planilla(p_datos jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_faltan text[];
begin
  if p_datos is null then
    p_datos := '{}'::jsonb;
  end if;

  if jsonb_typeof(p_datos) <> 'object' then
    raise exception
      'La planilla tiene que ser un objeto JSON; llegó %.', jsonb_typeof(p_datos)
      using errcode = '23514';
  end if;

  select array_agg(c.codigo order by c.orden)
    into v_faltan
    from public.inscripcion_campos c
   where c.activo
     and c.obligatorio
     -- (202609250003) AÑADIDO. Un campo condicional cuya condición NO se cumple
     -- en los datos enviados no se exige. Sin esta línea, el formulario ocultaba
     -- el campo, el aspirante lo veía validar en verde y el alta fallaba con un
     -- 23514 que nombraba un campo que nunca vio.
     and public.condicion_campo_se_cumple(c.condicion, p_datos)
     and (
          not (p_datos ? c.codigo)
       or p_datos -> c.codigo = 'null'::jsonb
       or (jsonb_typeof(p_datos -> c.codigo) = 'string'
           and btrim(p_datos ->> c.codigo) = '')
       or (jsonb_typeof(p_datos -> c.codigo) = 'array'
           and jsonb_array_length(p_datos -> c.codigo) = 0)
       or (jsonb_typeof(p_datos -> c.codigo) = 'object'
           and p_datos -> c.codigo = '{}'::jsonb)
     );

  if v_faltan is not null and array_length(v_faltan, 1) > 0 then
    -- El mensaje nombra los campos concretos, igual que hacen los triggers de
    -- M2, M3 y M4: un error que dice qué falta ahorra una sesión de depuración.
    raise exception
      'Faltan campos obligatorios en la planilla: %.', array_to_string(v_faltan, ', ')
      using errcode = '23514';
  end if;

  -- (D14) AÑADIDO en `202609250001`. La propuesta formativa tiene que apuntar a
  -- un programa real. Sólo se comprueba si la clave viene: una planilla sin ella
  -- ya se ha rechazado arriba por obligatoria, y una planilla `'{}'` —el «sin
  -- planilla» del formulario viejo— no debe fallar aquí.
  if p_datos ? 'curso_seleccionado' then
    perform public.resolver_programa_inscripcion(p_datos ->> 'curso_seleccionado');
  end if;
end;
$$;

comment on function public.validar_planilla(jsonb) is
  'Comprueba que la planilla traiga todos los campos marcados obligatorios en `inscripcion_campos` —saltando los condicionales cuya condición no se cumple en los datos enviados (202609250003)—, y (D14) que `curso_seleccionado` apunte a un programa inscribible. Lanza 23514 nombrando los campos que faltan, o 23503 si la referencia al programa no es válida.';


-- ---------------------------------------------------------------------------
--  PARTE 3 — Autocomprobación
-- ---------------------------------------------------------------------------
-- Aplicar sin error no es lo mismo que haber aplicado. Estas comprobaciones
-- corren dentro de la misma transacción que el resto del archivo: si alguna
-- falla, no queda nada aplicado.
do $$
declare
  v_prosrc    text;
  v_inmutable boolean;
  v_campo     text;
  v_cond      jsonb;
  v_igual     jsonb;
  v_n_cond    int;
  v_n_eval    int := 0;
begin
  -- 1. La función auxiliar existe y quedó IMMUTABLE.
  select p.prosrc, p.provolatile = 'i'
    into v_prosrc, v_inmutable
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'condicion_campo_se_cumple';

  if v_prosrc is null then
    raise exception 'No quedó la función `condicion_campo_se_cumple`.'
      using errcode = '23514';
  end if;

  if not v_inmutable then
    raise exception '`condicion_campo_se_cumple` no quedó IMMUTABLE.'
      using errcode = '23514';
  end if;

  -- 2. `validar_planilla()` es la NUEVA, no la vieja. Un `create or replace` que
  --    no llega a correr deja la función anterior en su sitio y el fallo no se
  --    vería: la planilla completa seguiría pasando.
  select p.prosrc into v_prosrc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'validar_planilla';

  if v_prosrc is null or v_prosrc not like '%condicion_campo_se_cumple%' then
    raise exception
      '`validar_planilla()` no quedó llamando a `condicion_campo_se_cumple`: el arreglo no se aplicó.'
      using errcode = '23514';
  end if;

  -- 3. Un campo sin condición se sigue exigiendo. Es la garantía de que el
  --    arreglo no desactivó la validación entera, que es el riesgo real de
  --    tocar este `where`.
  if not public.condicion_campo_se_cumple(null, '{}'::jsonb) then
    raise exception
      'Un campo sin condición dejó de exigirse: la validación quedó desactivada.'
      using errcode = '23514';
  end if;

  -- 4. La regla se comporta como el cliente, condición por condición, sobre las
  --    condiciones REALES del catálogo. Se leen en vez de escribirlas a mano: si
  --    mañana cambia la semilla, esto sigue comprobando lo que hay.
  select count(*) into v_n_cond
    from public.inscripcion_campos
   where condicion is not null
     and condicion ? 'campo'
     and coalesce(btrim(condicion ->> 'campo'), '') <> '';

  if v_n_cond = 0 then
    raise notice
      'No hay ningún campo con `condicion` en el catálogo: la comprobación 4 no tiene nada que medir.';
  end if;

  for v_campo, v_cond in
    select codigo, condicion
      from public.inscripcion_campos
     where condicion is not null
       and condicion ? 'campo'
       and coalesce(btrim(condicion ->> 'campo'), '') <> ''
  loop
    v_igual := v_cond -> 'igual';

    -- (a) Con el campo referenciado valiendo exactamente `igual`, se cumple.
    if not public.condicion_campo_se_cumple(
             v_cond,
             jsonb_build_object(v_cond ->> 'campo', v_igual)
           ) then
      raise exception
        'La condición de `%` no se cumple ni cuando el campo vale exactamente `igual`.',
        v_campo
        using errcode = '23514';
    end if;

    -- (b) Con el campo referenciado AUSENTE no se cumple —salvo cuando `igual`
    --     es nulo, que es el caso raro documentado en la PARTE 1—. Esta es,
    --     literalmente, la trampa que este archivo cierra.
    if v_igual is not null and v_igual <> 'null'::jsonb then
      if public.condicion_campo_se_cumple(v_cond, '{}'::jsonb) then
        raise exception
          'La condición de `%` se cumple con el campo referenciado ausente: es exactamente la trampa que este archivo viene a cerrar.',
          v_campo
          using errcode = '23514';
      end if;
    end if;

    v_n_eval := v_n_eval + 1;
  end loop;

  raise notice
    'Autocomprobación 202609250003: `condicion_campo_se_cumple` instalada y probada contra % condición(es) del catálogo.',
    v_n_eval;
end;
$$;
