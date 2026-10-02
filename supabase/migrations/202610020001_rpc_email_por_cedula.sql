-- ============================================================================
--  Login con cédula: resolver el correo sin abrir el padrón a `anon`
-- ============================================================================
--
--  EL PROBLEMA, MEDIDO (2026-10-01)
--  -------------------------------
--  `AuthService.iniciarSesion` resuelve la cédula con `emailPorCedula`, que hace
--  `profiles.select('email').eq('cedula', …)`. Esa consulta corre **sin sesión**
--  —el usuario todavía no se ha autenticado—, así que decide la RLS, y son DOS
--  causas apiladas:
--
--    1. `profiles.cedula` está rellena en **1 de 6** perfiles. La cédula real
--       vive en `aspirantes.cedula`.
--    2. Las tres políticas de `profiles` (`profiles_admin_all`,
--       `profiles_read_own`, `profiles_update_own`) son **todas para
--       `authenticated`**. Ninguna incluye `anon`, así que la consulta devuelve
--       **cero filas** y el cliente lo lee como «la cédula no existe».
--
--  La pantalla prometía lo que el sistema no podía cumplir: «Accede con tu cédula
--  o tu correo institucional».
--
--  LA DECISIÓN
--  -----------
--  Una función `security definer` con **contrato de retorno único**: entra una
--  cédula, sale **un `text`** —el correo— o `null`. No devuelve filas, no
--  devuelve el padrón, no permite `select * from aspirantes`. `anon` gana
--  `EXECUTE` sobre esta función y **nada más**.
--
--  **El riesgo que se acepta, dicho en voz alta:** esto convierte a la función
--  en un **oráculo de existencia** —un anónimo puede comprobar si una cédula
--  está registrada—. El autor lo aprobó explícitamente el 2026-10-02 a cambio de
--  un login coherente. No es una propiedad accidental: es el precio, y está
--  escrito aquí para que nadie lo descubra dentro de un año.
--
--  Lo que **no** se hace, y por qué: no se concede `SELECT` sobre `aspirantes` a
--  `anon`, ni se crea una política `anon` en `profiles`. Cualquiera de las dos
--  abriría el padrón entero —cédulas, nombres, domicilios, teléfonos— para
--  resolver una consulta que sólo necesita un correo.
-- ============================================================================

-- Normaliza una cédula a sus dígitos.
--
-- **En ambos lados de la comparación, y por eso es una función.** La cédula se
-- guarda de formas distintas según por dónde entró: el formulario de inscripción
-- la escribe como `V-12345678` y el sembrado la escribe como `12345678`. Sin
-- normalizar, un usuario que teclee su cédula sin el prefijo —o con él— falla la
-- mitad de las veces, y ese fallo se ve como «credenciales inválidas», que
-- apunta a la contraseña en vez de al formato.
--
-- `immutable` porque el resultado sólo depende de la entrada: eso permite usarla
-- en un índice si algún día hace falta, y deja claro que no toca la base.
create or replace function public.solo_digitos(p_texto text)
returns text
language sql
immutable
set search_path = pg_temp
as $$
  select nullif(regexp_replace(coalesce(p_texto, ''), '[^0-9]', '', 'g'), '')
$$;

comment on function public.solo_digitos(text) is
  'Los dígitos de una cédula, sin prefijo ni separadores. Devuelve NULL si no queda ninguno, para que dos cadenas sin dígitos no coincidan entre sí por ser ambas la cadena vacía.';

-- El correo de una cédula, o NULL si no hay ninguna ficha con esa cédula.
--
-- `security definer` para que la lectura de `aspirantes` **no** dependa de la RLS
-- del llamante: es exactamente el punto. `anon` no puede leer la tabla, pero sí
-- puede invocar esta función, que le devuelve un solo `text`.
--
-- `stable` y no `volatile`: dentro de una misma consulta el resultado no cambia,
-- y el planificador puede cachearlo en vez de reevaluarlo por fila.
create or replace function public.email_por_cedula(p_cedula text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select a.email
    from public.aspirantes a
   where public.solo_digitos(a.cedula) = public.solo_digitos(p_cedula)
   limit 1
$$;

comment on function public.email_por_cedula(text) is
  'El correo de la ficha cuya cédula coincida por dígitos, o NULL. Devuelve UN text: no expone el padrón. Concede EXECUTE a anon a propósito —el login ocurre sin sesión— y acepta el oráculo de existencia que eso implica (aprobado 2026-10-02).';

-- ---------------------------------------------------------------------------
--  Permisos
-- ---------------------------------------------------------------------------
--
-- `revoke all from public` primero: en PostgreSQL toda función nace con EXECUTE
-- concedido a `PUBLIC`, y conceder sin revocar antes deja el permiso abierto a
-- cualquier rol, incluidos los que se creen en el futuro. El orden importa.
revoke all on function public.email_por_cedula(text) from public;
revoke all on function public.solo_digitos(text) from public;

grant execute on function public.email_por_cedula(text) to anon, authenticated;

-- `solo_digitos` NO se concede a nadie: es un detalle de implementación de la
-- anterior. Si algún día hace falta desde el cliente, se concede entonces y con
-- su motivo escrito.

-- ---------------------------------------------------------------------------
--  Autocomprobación
-- ---------------------------------------------------------------------------
--
-- Se ejecuta al aplicar la migración y aborta si algo no quedó como se espera.
-- Un `grant` mal puesto no da error —simplemente concede de más o de menos—, así
-- que la única forma de que una migración de permisos sea fiable es que se
-- compruebe a sí misma.
do $autocomprobacion$
declare
  v_anon_puede      boolean;
  v_authenticated   boolean;
  v_public_no_puede boolean;
  v_security_definer boolean;
begin
  select has_function_privilege('anon', 'public.email_por_cedula(text)', 'execute')
    into v_anon_puede;
  if not v_anon_puede then
    raise exception 'email_por_cedula NO es ejecutable por anon: el login con cédula seguiría roto';
  end if;

  select has_function_privilege('authenticated', 'public.email_por_cedula(text)', 'execute')
    into v_authenticated;
  if not v_authenticated then
    raise exception 'email_por_cedula NO es ejecutable por authenticated';
  end if;

  -- El control negativo: si `public` conservara el EXECUTE, cualquier rol
  -- presente o futuro podría llamarla, y la concesión explícita a anon sería una
  -- ilusión de control.
  select not has_function_privilege('public', 'public.email_por_cedula(text)', 'execute')
    into v_public_no_puede;
  if not v_public_no_puede then
    raise exception 'email_por_cedula sigue ejecutable por PUBLIC: el REVOKE no surtió efecto';
  end if;

  select p.prosecdef
    into v_security_definer
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'email_por_cedula';
  if not v_security_definer then
    raise exception 'email_por_cedula NO es security definer: la RLS de aspirantes la bloquearía';
  end if;
end
$autocomprobacion$;

-- ---------------------------------------------------------------------------
--  Lo que el cliente tiene que cambiar
-- ---------------------------------------------------------------------------
--
-- `lib/services/supabase_service.dart`, método `emailPorCedula`:
--
--   -    final respuesta = await client
--   -        .from(_tablaPerfiles)
--   -        .select('email')
--   -        .eq('cedula', cedula)
--   -        .maybeSingle();
--   -
--   -    final email = respuesta?['email'] as String?;
--   +    final email = await client.rpc(
--   +      'email_por_cedula',
--   +      params: {'p_cedula': cedula},
--   +    ) as String?;
--
--  El resto del método —devolver `null` cuando no hay correo— no cambia: la
--  función devuelve `NULL` en el mismo caso en que antes no había fila.
