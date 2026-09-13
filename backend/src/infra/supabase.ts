import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../config/env.js';

/**
 * Fábrica de clientes Supabase.
 *
 * Se usan DOS clientes con propósitos distintos, y la diferencia importa:
 *
 *  · Cliente de usuario (`crearClienteDeUsuario`): lleva el JWT del llamante, de
 *    modo que Postgres aplica RLS. Es la barrera que protege los datos aunque la
 *    API tuviera un fallo de autorización. Se crea por petición.
 *
 *  · Cliente administrador (`crearClienteAdmin`): usa la service_role key, que
 *    **ignora RLS**. Se reserva para lo que no puede depender del usuario:
 *    verificar tokens y alimentar las cachés de módulos y parámetros. Nunca se
 *    usa para leer o escribir datos personales.
 */

const OPCIONES_AUTH = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false,
} as const;

/** Cliente con la identidad del llamante. `null` ⇒ actúa como `anon`. */
export function crearClienteDeUsuario(env: Env, token: string | null): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: OPCIONES_AUTH,
    global: token
      ? { headers: { Authorization: `Bearer ${token}` } }
      : {},
  });
}

/** Cliente privilegiado. Ignora RLS: úsalo sólo donde está justificado. */
export function crearClienteAdmin(env: Env): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: OPCIONES_AUTH,
  });
}

/** Cliente anónimo, sin identidad. Sólo para verificar tokens. */
export function crearClienteAnonimo(env: Env): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: OPCIONES_AUTH,
  });
}
