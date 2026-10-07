-- ============================================================================
--  E-2 · Cierre de los bypasses administrativos de `planilla_versiones`
-- ============================================================================
--
--  LO QUE SE MIDIÓ CON JWT REAL DE ADMIN (bloque 6.2), y estaba abierto:
--
--    INSERT ENVIADA / OBSERVADA / REENVIADA      -> 201  persistida
--    INSERT APROBADA completa                    -> 201  persistida  ← grave
--    INSERT numero=99, REENVIADA como v1, v2 sin observada -> 201
--    DELETE ENVIADA / OBSERVADA / REENVIADA / APROBADA     -> 200
--
--  **La causa, en una frase:** `versiones_admin_all` era `FOR ALL`, y eso da al
--  admin exactamente lo que al aspirante le negamos con su `with check`.
--  Al aspirante se le acotó el estado; al admin se le dejó el `FOR ALL` sin
--  acotar, y por ahí entra todo: fabricar una APROBADA, saltarse la numeración
--  y borrar el historial.
--
--  LA CORRECCIÓN: separar el `FOR ALL` en SELECT + UPDATE, y **quitar INSERT y
--  DELETE**.
--
--  **Por qué sin INSERT:** el workflow **sólo crea versiones al ENVIAR o
--  REENVIAR**, y esas dos operaciones las hace **el aspirante**. El admin no
--  necesita crear ninguna versión — sólo observar y aprobar. Quitarle el INSERT
--  **no le quita ninguna capacidad real** y cierra los ocho casos de golpe.
--
--  **Por qué sin DELETE:** **nada en el workflow borra versiones.** Un historial
--  formal no se borra: se consulta. Y una planilla APROBADA no debería poder
--  desaparecer por un `DELETE` por PostgREST.
--
--  QUÉ CAPA GARANTIZA QUÉ — para no duplicar lógica:
--
--    · contenido histórico inmutable (aspirante_id, numero, datos_snapshot,
--      enviada_at, created_at)  →  **TRIGGER** `impedir_version_modificada()`
--    · transiciones legales      →  **TRIGGER** (enumera las cuatro)
--    · quién puede escribir      →  **RLS** (esta migración)
--    · coherencia estado↔fecha   →  **CHECK**
--    · unicidad (aspirante, nº)  →  **UNIQUE**
--
--  La RLS **no repite** lo que el trigger ya garantiza: si lo hiciera, habría dos
--  sitios donde la regla puede divergir.
-- ============================================================================

-- ---------------------------------------------------------------------------
--  1. Retirar el `FOR ALL`
-- ---------------------------------------------------------------------------
drop policy if exists versiones_admin_all on public.planilla_versiones;

-- ---------------------------------------------------------------------------
--  2. Admin: LEER
-- ---------------------------------------------------------------------------
drop policy if exists versiones_admin_leer on public.planilla_versiones;
create policy versiones_admin_leer
  on public.planilla_versiones for select to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------------
--  3. Admin: TRANSICIONAR — y nada más
-- ---------------------------------------------------------------------------
--
--  El `using` decide **qué filas puede tocar**; el `with check` decide **cómo
--  pueden quedar**. Aquí el `with check` acota el destino a los dos estados a los
--  que un admin puede llevar una versión: `OBSERVADA` o `APROBADA`.
--
--  **No acota el origen** — eso lo hace el trigger, que ya enumera las cuatro
--  transiciones legales y tiene el `OLD` a mano. Duplicarlo aquí sería tener la
--  misma regla en dos sitios.
--
--  **Y exige la aprobación completa**: si el destino es `APROBADA`, tienen que
--  venir `approved_by` y `aprobada_at`. El `CHECK` de la tabla ya lo impone, pero
--  ponerlo también aquí hace que el error sea un 403 de autorización en vez de un
--  400 de constraint — más claro para quien lo lea.
drop policy if exists versiones_admin_transicionar on public.planilla_versiones;
create policy versiones_admin_transicionar
  on public.planilla_versiones for update to authenticated
  using (public.is_admin())
  with check (
    public.is_admin()
    and (
      estado = 'OBSERVADA'
      or (
        estado = 'APROBADA'
        and aprobada_at is not null
        and approved_by is not null
      )
    )
  );

-- **No se crea ninguna política de INSERT ni de DELETE para el admin.** La
-- ausencia es la protección: sin política, la operación no tiene `with check` que
-- la autorice y PostgreSQL la deniega.

-- ---------------------------------------------------------------------------
--  4. Autocomprobación
-- ---------------------------------------------------------------------------
--
--  Aquí SÍ se puede comprobar sin ejercer el trigger: las políticas se leen del
--  catálogo, y lo que hay que verificar es que **no quede un `FOR ALL`** — que es
--  el error que esta migración corrige. Un `drop policy if exists` sobre un
--  nombre que no existe **no falla**: simplemente no hace nada, y la política
--  vieja seguiría abierta. Por eso se comprueba el catálogo, no la intención.
do $autocomprobacion$
declare
  v_forall integer;
  v_admin  integer;
begin
  -- Ninguna política de esta tabla puede ser `ALL`.
  select count(*) into v_forall
    from pg_policies
   where schemaname = 'public'
     and tablename = 'planilla_versiones'
     and cmd = 'ALL';
  if v_forall > 0 then
    raise exception 'Queda % política(s) FOR ALL en planilla_versiones: siguen abiertos INSERT y DELETE', v_forall;
  end if;

  -- Y el admin tiene exactamente dos: leer y transicionar.
  select count(*) into v_admin
    from pg_policies
   where schemaname = 'public'
     and tablename = 'planilla_versiones'
     and policyname like 'versiones_admin%';
  if v_admin <> 2 then
    raise exception 'Se esperaban 2 políticas de admin (leer, transicionar), hay %', v_admin;
  end if;
end
$autocomprobacion$;
