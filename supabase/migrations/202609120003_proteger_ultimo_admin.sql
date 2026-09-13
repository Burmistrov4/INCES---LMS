-- ============================================================================
--  Protección del último administrador activo  ·  Deuda D8
-- ============================================================================
--
--  Problema: el sistema puede quedarse sin ningún administrador activo y, con
--  él, sin nadie capaz de gestionarlo. La API ya impedía que un administrador se
--  quitara su propio rol, pero eso no cubre el resto de caminos:
--
--    · Dos administradores degradándose mutuamente a la vez. Cada petición ve al
--      otro todavía como administrador, ambas pasan y el resultado son CERO.
--      Es una carrera clásica de «comprobar y luego actuar».
--    · Desactivar una cuenta (`active = false`) en vez de cambiarle el rol: el
--      mismo agujero por otra puerta, y la guardia de la API no lo miraba.
--    · Cualquier cambio hecho por fuera de la API: el editor SQL de Supabase, un
--      script de mantenimiento, una migración futura.
--
--  Por eso la barrera real vive aquí, en la base de datos, y la API sólo la
--  espeja para dar un mensaje legible. Es la misma decisión que con
--  `m0_cpanel`: la regla se cumple aunque nadie la llame desde donde se espera.
-- ============================================================================

create or replace function public.proteger_ultimo_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  admins_restantes int;
begin
  -- ¿La fila era un administrador activo antes del cambio? Si no lo era, no hay
  -- nada que proteger y se sale sin tocar ningún bloqueo: el caso normal (editar
  -- el nombre de un estudiante) no debe pagar el coste de esta comprobación.
  if not (old.rol = 'admin' and old.active) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- ¿Sigue siendo administrador activo después del cambio?
  if tg_op = 'UPDATE' and new.rol = 'admin' and new.active then
    return new;
  end if;

  -- A partir de aquí la fila está perdiendo la condición de administrador activo.
  --
  -- El bloqueo es lo que cierra la carrera. `pg_advisory_xact_lock` serializa
  -- esta sección entre transacciones concurrentes y se libera solo al terminar
  -- la transacción (no hay que acordarse de soltarlo). Se toma únicamente en el
  -- camino peligroso, así que el resto de escrituras no se ven afectadas.
  perform pg_advisory_xact_lock(hashtext('proteger_ultimo_admin'));

  -- Se cuentan los administradores activos que quedan, excluyendo esta fila.
  select count(*)
    into admins_restantes
    from public.profiles
   where rol = 'admin'
     and active
     and id <> old.id;

  if admins_restantes = 0 then
    raise exception
      'No se puede dejar el sistema sin ningún administrador activo.'
      using
        errcode = '23514',
        hint = 'Promueve a otro usuario a administrador antes de degradar o desactivar a este.';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function public.proteger_ultimo_admin() is
  'Impide degradar, desactivar o borrar al último administrador activo. Cierra la carrera entre dos degradaciones simultáneas con un bloqueo de transacción.';

drop trigger if exists proteger_ultimo_admin on public.profiles;

create trigger proteger_ultimo_admin
  before update or delete on public.profiles
  for each row
  execute function public.proteger_ultimo_admin();

-- ---------------------------------------------------------------------------
-- Índice de apoyo
-- ---------------------------------------------------------------------------
-- La comprobación cuenta administradores activos en cada degradación. Sin este
-- índice, esa cuenta recorre toda la tabla de perfiles; con él es una búsqueda
-- directa. El número de administradores es diminuto, pero la tabla no lo es.

create index if not exists profiles_admins_activos_idx
  on public.profiles (rol, active)
  where rol = 'admin' and active;
