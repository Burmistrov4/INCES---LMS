-- ============================================================================
--  E-2 · Corrección de las transiciones permitidas
-- ============================================================================
--
--  **El trigger de `202610060001` era más ancho que el contrato.**
--
--  Tenía:
--
--    (old.estado in ('ENVIADA','REENVIADA') and new.estado in ('OBSERVADA','APROBADA'))
--
--  y esa condición agrupaba `ENVIADA` con `REENVIADA` para los DOS destinos, lo
--  que **permitía `REENVIADA → OBSERVADA`** — prohibida por el contrato.
--
--  Por qué se coló: la batería del bloque 5 probó `ENVIADA → OBSERVADA` (P5) y
--  `OBSERVADA → APROBADA` (P7), pero **nunca `REENVIADA → OBSERVADA`**. El único
--  par que el agrupamiento rompía era justo el que no se probó.
--
--  **Lección aplicada aquí:** la corrección no agrupa por origen. **Enumera las
--  cuatro transiciones permitidas una a una**, y una prueba las recorre todas.
--
--  El workflow del contrato es:
--
--    ENVIADA   → OBSERVADA   ✓
--    ENVIADA   → APROBADA    ✓
--    OBSERVADA → REENVIADA   ✓
--    REENVIADA → APROBADA    ✓
--    APROBADA  → (nada)      ✗
-- ============================================================================

create or replace function public.impedir_version_modificada()
returns trigger
language plpgsql
as $$
declare
  v_permitida boolean;
begin
  -- El contenido histórico no cambia NUNCA, ni al aprobar.
  if new.aspirante_id   is distinct from old.aspirante_id
     or new.numero         is distinct from old.numero
     or new.datos_snapshot is distinct from old.datos_snapshot
     or new.enviada_at     is distinct from old.enviada_at
     or new.created_at     is distinct from old.created_at then
    raise exception 'Una versión formalizada no puede alterar su contenido histórico'
      using errcode = '23514';
  end if;

  -- **Las cuatro transiciones, enumeradas.** No se agrupa por origen: agrupar es
  -- lo que dejó pasar `REENVIADA → OBSERVADA`.
  if new.estado is distinct from old.estado then
    v_permitida :=
         (old.estado = 'ENVIADA'   and new.estado = 'OBSERVADA')
      or (old.estado = 'ENVIADA'   and new.estado = 'APROBADA')
      or (old.estado = 'OBSERVADA' and new.estado = 'REENVIADA')
      or (old.estado = 'REENVIADA' and new.estado = 'APROBADA');

    if not v_permitida then
      raise exception 'Transición de planilla no permitida: % → %', old.estado, new.estado
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.impedir_version_modificada() is
  'Congela el contenido de una versión y enumera las CUATRO transiciones del contrato. No agrupa por origen: agrupar permitió REENVIADA→OBSERVADA.';

-- ---------------------------------------------------------------------------
--  Nota sobre la autocomprobación
-- ---------------------------------------------------------------------------
--
--  **Aquí NO hay autocomprobación, y es una decisión, no un olvido.**
--
--  El primer intento la tenía: llamaba a `impedir_version_modificada()` con filas
--  sintéticas para verificar las cuatro transiciones. **Falló con `0A000: trigger
--  functions can only be called as triggers`** — PostgreSQL prohíbe invocar una
--  función de trigger fuera de un trigger.
--
--  Es decir: **la lógica de una función de trigger no se puede comprobar
--  directamente**, sólo ejerciendo el trigger de verdad con un INSERT/UPDATE
--  sobre filas reales. Eso requiere un aspirante y una versión, y **una migración
--  no es el sitio para crear datos de prueba**.
--
--  La verificación se movió a la batería (`supabase/probar-e2-persistencia.mjs`),
--  que **sí** ejerce el trigger con filas reales y JWT reales — y que además debe
--  recorrer **las cuatro transiciones permitidas y las prohibidas**, incluida
--  `REENVIADA → OBSERVADA`, que es la que se había colado.
