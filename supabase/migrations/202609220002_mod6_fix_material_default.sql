-- ============================================================================
--  INCES LMS — Módulo 6: parche caliente del valor por defecto de puntos_maximos
--  Archivo: 202609220002_mod6_fix_material_default.sql
--  Aplica con: node supabase/apply-migrations.mjs
-- ============================================================================
--
--  POR QUÉ EXISTE ESTE ARCHIVO (y por qué NO se tocó 202609220001)
--  ---------------------------------------------------------------
--  La migración 202609220001 ya se había APLICADO a la nube con
--  `p_puntos_maximos numeric default 20`. Después, el valor por defecto local se
--  corrigió a `default null` (un MATERIAL no lleva puntos; el 20 de negocio lo
--  aplica el propio RPC sólo para lo calificable, dentro de la rama `else`). Pero
--  una migración ya aplicada no se edita: el libro mayor de migraciones detecta
--  la divergencia por checksum, y reescribir la historia de producción es
--  indeterminado. Lo que toca es un parche caliente que deja la nube en el mismo
--  estado que el repositorio local.
--
--  QUÉ HACE
--  --------
--  `CREATE OR REPLACE FUNCTION` sobre `m6_crear_tarea` con la firma ya
--  corregida (`p_puntos_maximos numeric default null`). `CREATE OR REPLACE`
--  conserva el `GRANT EXECUTE` que concedió 202609220001, así que no hace falta
--  re-concederlo aquí. En la nube sustituye la función con `default 20` por la de
--  `default null`; en local, donde 001 ya tiene `null`, es un no-op (reescribe la
--  función igual).
--
--  El cuerpo es idéntico al de 202609220001; la única diferencia semántica es el
--  `default` del parámetro. Se reproduce entero a propósito: un parche parcial
--  que sólo cambiara el `default` dejaría el resto de la función a merced de la
--  versión antigua de la nube.
--
--  POR QUÉ `null` Y NO `20` (el porqué del arreglo)
--  ------------------------------------------------
--  Con `default 20`, la llamada natural `m6_crear_tarea(sec, 'Lectura', '',
--  'MATERIAL')` —sin pasar puntos, porque un material no se califica— **fallaba
--  con 23514**: el argumento llegaba valiendo 20, la comprobación de coherencia
--  de MATERIAL lo veía como «un material con puntos» y lo rechazaba. Un valor por
--  defecto que contradice al caso más común es peor que no tenerlo, porque el
--  error aparece lejos de su causa. Con `null`, «no me lo dijeron» se distingue
--  de «me dijeron 20», y el 20 se aplica abajo sólo a lo que sí se califica.

create or replace function public.m6_crear_tarea(
  p_seccion_id              uuid,
  p_titulo                  text,
  p_descripcion             text,
  p_tipo                    text        default 'TAREA',
  -- `null` y NO `20`, aunque 20 sea el valor de negocio. Con `default 20`, la
  -- llamada natural `m6_crear_tarea(sec, 'Lectura', '', 'MATERIAL')` —sin
  -- pasar puntos, porque un material no se califica— **fallaba con 23514**: el
  -- argumento llegaba valiendo 20, la comprobación de coherencia de MATERIAL lo
  -- veía como «un material con puntos» y rechazaba. Un valor por defecto que
  -- contradice al caso más común es peor que no tenerlo, porque el error
  -- aparece lejos de su causa. Con `null`, «no me lo dijeron» se distingue de
  -- «me dijeron 20», y el 20 se aplica abajo sólo a lo que sí se califica.
  p_puntos_maximos          numeric     default null,
  p_fecha_limite            timestamptz default null,
  p_permitir_entrega_tardia boolean     default true,
  p_tema                    text        default null,
  p_orden                   integer     default 0
)
returns table (
  id                      uuid,
  seccion_id              uuid,
  titulo                  text,
  descripcion             text,
  tipo                    text,
  puntos_maximos          numeric,
  fecha_limite            timestamptz,
  permitir_entrega_tardia boolean,
  tema                    text,
  orden                   integer,
  estado                  text,
  publicado_en            timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Se requiere una sesión para crear una tarea.'
      using errcode = '42501';
  end if;

  if not public.m6_dicta_seccion(p_seccion_id) then
    raise exception 'No dictas la sección %: no puedes crear trabajo en ella.', p_seccion_id
      using errcode = '42501';
  end if;

  -- La coherencia MATERIAL/sin nota la imponen los CHECK de la tabla; se
  -- comprueba aquí también para dar un mensaje que se entienda, en vez de un
  -- `violates check constraint m6_tareas_material_sin_nota` a secas. Los tres
  -- casos que la tabla rechazaría se traducen aquí a errores de negocio: un
  -- mensaje que nombra la regla ahorra media hora, y uno que nombra la
  -- restricción, no.
  if p_tipo = 'MATERIAL' then
    -- Un MATERIAL es de lectura: ni puntos ni plazo. Se compara contra `null`
    -- («no me lo dijeron») además de contra 0, para que **omitir** el argumento
    -- —que es lo natural en un material— no cuente como «le puse puntos».
    if (p_puntos_maximos is not null and p_puntos_maximos <> 0)
       or p_fecha_limite is not null then
      raise exception 'Un MATERIAL es de lectura: no lleva puntos ni fecha límite.'
        using errcode = '23514';
    end if;
  else
    -- Lo calificable vale entre 0 exclusivo y 20. Se aplica aquí el mismo
    -- valor por defecto que la columna, para poder comprobarlo ANTES de
    -- insertar y dar el mensaje bueno en vez de una violación de CHECK.
    if coalesce(p_puntos_maximos, 20) <= 0 then
      raise exception 'Una tarea calificable debe valer más de 0 puntos.'
        using errcode = '23514';
    end if;

    if coalesce(p_puntos_maximos, 20) > 20 then
      raise exception 'La nota máxima no puede superar 20 (la escala del centro).'
        using errcode = '23514';
    end if;
  end if;

  return query
  insert into public.m6_tareas as t
    (seccion_id, creado_por, titulo, descripcion, tipo, puntos_maximos,
     fecha_limite, permitir_entrega_tardia, tema, orden)
  values
    (p_seccion_id, v_actor, p_titulo, coalesce(p_descripcion, ''), p_tipo,
     case when p_tipo = 'MATERIAL' then 0 else coalesce(p_puntos_maximos, 20) end,
     p_fecha_limite, p_permitir_entrega_tardia, p_tema, coalesce(p_orden, 0))
  returning t.id, t.seccion_id, t.titulo, t.descripcion, t.tipo,
            t.puntos_maximos, t.fecha_limite, t.permitir_entrega_tardia,
            t.tema, t.orden, t.estado, t.publicado_en;
end;
$$;

comment on function public.m6_crear_tarea(uuid, text, text, text, numeric, timestamptz, boolean, text, integer) is
  'Crea trabajo de clase en una sección que el usuario dicta. Nace en BORRADOR y sin entregas: publicar es lo que crea los placeholders. El default de puntos_maximos es null (no 20): un MATERIAL sin puntos no debe rechazarse.';
