-- ============================================================================
--  INCES LMS — Fase 3 de D14: se retira el andamiaje transitorio
--  Archivo: 202609250002_d14_fase3_retirar_tolerancia_y_vista.sql
--  Aplica con: SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs
-- ============================================================================
--
--  QUÉ CIERRA
--  ----------
--  · **D12, del todo.** `public.cursos` se creó en `202609160001` como VISTA DE
--    COMPATIBILIDAD —no como tabla— para que el desplegable del formulario
--    público siguiera funcionando mientras el cliente se migraba. El cliente ya
--    no la lee (Fase 2, `80432c1`), así que se retira. La propia vista lo dejó
--    escrito en su `comment`:
--
--      «Se retira con `drop view public.cursos;` cuando
--       `SupabaseService.cursosDisponibles()` lea `programs` directamente.»
--
--    Esa condición se cumple. Esta migración ejecuta la instrucción que la
--    propia vista dejó puesta; no inventa una decisión nueva.
--
--  · **La tolerancia transitoria de D14.** `resolver_programa_inscripcion()`
--    aceptaba DOS vocabularios —uuid (nuevo) y nombre exacto (viejo)— para que
--    la migración `202609250001` pudiera aplicarse antes de desplegar el cliente
--    nuevo, sin romper la inscripción pública en el hueco. Ese hueco ya no
--    existe y la tolerancia se retira: sólo uuid.
--
--
--  MEDIDO ANTES DE ESCRIBIRLA, NO DEDUCIDO (2026-09-25)
--  ---------------------------------------------------
--  La retirada de la tolerancia era **destructiva para un cliente desplegado**:
--  el formulario viejo manda el NOMBRE, y sin tolerancia el nombre no resuelve,
--  `v_es_aspirante` queda falso y el aspirante vería «registro exitoso» **sin
--  ficha** — el fallo silencioso que `202609250001` se cuidó de evitar. Antes de
--  retirarla había que saber si ese cliente existe. Se midió contra GitHub, no
--  contra la memoria del proyecto:
--
--      GET /repos/…/deployments        → []            (vacío)
--      GET /repos/…/environments       → total_count 0
--      repositorio                     → homepage: null, has_pages: false
--      estado de commit 80432c1        → total_count 0 (ningún host reportó build)
--      corridas de Actions (20)        → todas «Flutter CI» / push
--      .github/workflows/*.yml         → ninguna mención de deploy/vercel/pages
--      ESTADO_DEL_SISTEMA.md:484-485   → «API publicada ❌ Pendiente»
--                                        «Frontend publicado ❌ Pendiente»
--
--  **No hay nada desplegado.** No existe un cliente viejo en producción al que
--  proteger, así que la tolerancia es una póliza sobre un siniestro que nunca
--  ocurrió: se retira. Y con el mismo argumento cae la vista, que existía para
--  alimentar el desplegable de ese mismo formulario.
--
--  LÍMITE DE ESA MEDICIÓN, dicho en voz alta: sólo alcanza a GitHub. Si alguien
--  hubiera desplegado por fuera de la integración (CLI de Vercel sin Git,
--  publicación manual), el repositorio no lo sabría. Tres señales independientes
--  —deployments, homepage y el propio documento de estado— dicen que no. Si
--  apareciera una URL pública, esta migración deja de ser inocua y hay que
--  volver a decidir.
--
--
--  POR QUÉ LA VISTA SE SUELTA CON UNA GUARDIA Y NO CON `drop view` A SECAS
--  ---------------------------------------------------------------------
--  `202609160001` ya documentó el motivo: `cursos` puede estar en DOS formas
--  según de dónde venga la base —tabla (recién migrada desde Fase 0) o vista—, y
--  **ni `drop table if exists` ni `drop view if exists` sirven para las dos**: el
--  `if exists` perdona que el objeto no esté, no que sea del tipo equivocado
--  (`ERROR: "cursos" is not a view`, código 42809). Se repite el idioma que esa
--  migración usó: mirar `pg_class.relkind` y soltar lo que de verdad haya.
--
--  Sin `cascade` en el caso vista, a propósito: si algo dependiera de ella, el
--  `drop` **falla** y queremos que falle. Un `cascade` aquí se llevaría por
--  delante el objeto dependiente en silencio, que es justo lo contrario de lo que
--  esta fase busca.
--
--
--  POR QUÉ UN VALOR QUE NO ES UUID LANZA 23503 Y NO OTRO CÓDIGO
--  -----------------------------------------------------------
--  Tres razones, y las tres son medidas, no de gusto:
--
--   · **Coherencia interna.** La función ya usa 23503 para TODO lo que significa
--     «esta referencia a programa no es aceptable»: no existe, existe pero está
--     inactivo, existe pero es CARRERA, nombre ambiguo. Un valor que no es uuid
--     es la misma familia, no una nueva.
--
--   · **El mensaje del cliente no miente.** `app_exception.dart` traduce 23503 a
--     `validacion` con «El registro hace referencia a datos que no existen.»
--     —impreciso pero no engañoso—. La rama de 23514 dice «Revisa la fecha de
--     nacimiento y los datos del representante», que para un identificador de
--     curso mal formado sería **activamente falso**.
--
--   · **`22P02` queda descartado.** Es lo que PostgreSQL lanzaría solo al castear
--     mal, pero ni `traducir-error.ts` ni `app_exception.dart` lo traducen: caería
--     al caso por defecto y saldría como **500 opaco**. Elegirlo sería reintroducir
--     el problema que el mapeo de 23502 viene a resolver.
--
--  El mensaje sí es específico, para que quien lea el log no tenga que adivinar.
--
--
--  LO QUE ESTA MIGRACIÓN NO HACE (a propósito)
--  -------------------------------------------
--  · **NO renombra el código del catálogo.** `inscripcion_campos.codigo` sigue
--    siendo `curso_seleccionado`; lo que cambia —desde `202609250001`— es su
--    VALOR. Renombrar el código arrastraría `sintetizarClavesPlanas`, el
--    formulario y cinco archivos de prueba sin ganar nada.
--  · **NO toca `202609100001` ni `202609160001`.** Una migración aplicada no se
--    edita nunca: el libro mayor detecta la deriva por checksum.
--  · **NO borra la política `programs_read_activos`.** Es lo que sigue escondiendo
--    los borradores de `anon` ahora que no hay vista de por medio. La vista era
--    `security_invoker` precisamente para que esa política mandara.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- PARTE 1 — Se suelta la vista de compatibilidad
-- ---------------------------------------------------------------------------
do $$
declare
  v_tipo "char";
begin
  select c.relkind into v_tipo
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'cursos';

  if v_tipo = 'r' then
    -- Base venida de Fase 0 sin pasar por `202609160001`: es la tabla del
    -- prototipo. `cascade` sí aquí, porque sus dependientes serían andamiaje de
    -- la misma época y no hay nada legítimo que pueda colgar de ella.
    execute 'drop table public.cursos cascade';
  elsif v_tipo = 'v' then
    -- El caso normal. Sin `cascade`: si algo depende, queremos el error.
    execute 'drop view public.cursos';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- PARTE 2 — El resolutor pierde el vocabulario viejo
-- ---------------------------------------------------------------------------
-- Cuerpo copiado LITERAL de `202609250001` con UN cambio: el bloque (2) —la rama
-- que resolvía un nombre contra `programs.name`— se elimina, y en su lugar un
-- valor que no es uuid lanza. Todo lo demás —el `nullif(btrim(...))`, el retorno
-- temprano de null, la distinción entre «no existe» y «existe pero no es
-- inscribible», la comprobación de `is_active` y `type`— se copia sin cambiar una
-- coma.
--
-- Se conserva la comprobación explícita de `is_active` y `type` por el motivo que
-- `202609250001` documentó: `handle_new_user()` es `security definer` y **no pasa
-- por RLS**, así que `programs_read_activos` no protege de nada dentro del
-- trigger. La regla tiene que estar aquí.
create or replace function public.resolver_programa_inscripcion(p_valor text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_texto  text := nullif(btrim(coalesce(p_valor, '')), '');
  v_uuid   uuid;
  v_id     uuid;
  v_cuantos int;
begin
  -- Ausente o vacío no es un error: es «este registro no trae propuesta
  -- formativa», que es el caso del alta de un docente o de un admin. Quien
  -- decide si eso impide crear la ficha es `handle_new_user()`, no esto.
  if v_texto is null then
    return null;
  end if;

  -- ---- El ÚNICO vocabulario: un uuid --------------------------------------
  begin
    v_uuid := v_texto::uuid;
  exception when invalid_text_representation then
    v_uuid := null;
  end;

  -- (D14 Fase 3) Aquí vivía la tolerancia transitoria al nombre. Se retiró en
  -- `202609250002`: no hay cliente desplegado que la necesite (ver la cabecera).
  -- Un valor que no es un uuid ya no se intenta interpretar como nada.
  if v_uuid is null then
    raise exception
      'El identificador de la propuesta formativa no es válido: se esperaba el '
      'identificador de un curso de formación continua, no un nombre.'
      using errcode = '23503';
  end if;

  select p.id into v_id
    from public.programs p
   where p.id = v_uuid
     and p.is_active
     and p.type = 'CURSO_LIBRE';

  if v_id is not null then
    return v_id;
  end if;

  -- Distinguir «no existe» de «existe pero no es inscribible» importa: son dos
  -- errores distintos para quien los lee. El mensaje los separa.
  select count(*) into v_cuantos from public.programs p where p.id = v_uuid;

  if v_cuantos = 0 then
    raise exception
      'La propuesta formativa indicada no existe en la oferta formativa.'
      using errcode = '23503';
  end if;

  raise exception
    'La propuesta formativa indicada no está abierta a inscripción: sólo se '
    'puede elegir un curso de formación continua activo.'
    using errcode = '23503';
end;
$$;

comment on function public.resolver_programa_inscripcion(text) is
  'Resuelve el valor de `curso_seleccionado` a un `programs.id`. Desde `202609250002` sólo acepta un uuid: la tolerancia transitoria al NOMBRE se retiró al comprobarse que no hay cliente desplegado que la necesitara. Exige que el programa exista, esté activo y sea CURSO_LIBRE — comprobaciones que RLS no puede hacer dentro de un trigger security definer. Lanza 23503 con el motivo concreto.';

-- Se repite el `revoke` de `202609250001` aunque `create or replace` conserva la
-- ACL: dejarlo explícito hace que esta migración sea autosuficiente y que el
-- cierre de la puerta no dependa de un archivo anterior.
revoke all on function public.resolver_programa_inscripcion(text)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- PARTE 3 — Comprobación de la propia migración
-- ---------------------------------------------------------------------------
-- Cada aserción corresponde a una forma concreta de que esto quede a medias sin
-- que nada falle:
--   · la vista sobrevive            → D12 no se cerró, y nadie lo notaría;
--   · el resolutor dejó de resolver  → se rompió el camino bueno en silencio;
--   · el resolutor acepta un nombre  → la tolerancia sigue viva y el cliente
--                                      podría seguir mandando texto libre.
do $$
declare
  v_tipo      "char";
  v_nombre    text;
  v_ejemplo   uuid;
  v_resuelto  uuid;
  v_rechazado boolean := false;
begin
  -- (a) La vista ya no existe, en ninguna de sus dos formas.
  select c.relkind into v_tipo
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'cursos';

  if v_tipo is not null then
    raise exception
      'La vista de compatibilidad `public.cursos` sigue existiendo (relkind = %). '
      'D12 no quedó cerrada.', v_tipo
      using errcode = '23514';
  end if;

  select p.id, p.name into v_ejemplo, v_nombre
    from public.programs p
   where p.type = 'CURSO_LIBRE' and p.is_active
   order by p.code
   limit 1;

  -- (b) El camino bueno sigue funcionando. Sólo se comprueba si hay semilla con
  -- la que probar: esta migración no debe fallar por un catálogo vacío, que es un
  -- estado legítimo en una base recién creada y sin sembrar.
  if v_ejemplo is not null then
    v_resuelto := public.resolver_programa_inscripcion(v_ejemplo::text);

    if v_resuelto is distinct from v_ejemplo then
      raise exception
        'El resolutor dejó de resolver un uuid válido: devolvió %.',
        coalesce(v_resuelto::text, 'null')
        using errcode = '23514';
    end if;
  end if;

  -- (c) Y ya NO acepta un NOMBRE. Se usa el de un curso REAL cuando lo hay: es
  -- más contundente que un literal, porque prueba que ni siquiera un nombre que
  -- existe se acepta. Sin semilla, un literal cualquiera sirve igual.
  v_nombre := coalesce(v_nombre, 'Curso Inexistente');

  begin
    perform public.resolver_programa_inscripcion(v_nombre);
  exception when others then
    if sqlstate = '23503' then
      v_rechazado := true;
    else
      -- Un código distinto significa que el rechazo vino de otro sitio: se
      -- propaga en vez de darlo por bueno.
      raise;
    end if;
  end;

  if not v_rechazado then
    raise exception
      'El resolutor sigue aceptando el nombre «%»: la tolerancia transitoria no '
      'se retiró.', v_nombre
      using errcode = '23514';
  end if;
end;
$$;
