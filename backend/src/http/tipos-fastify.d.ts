import type { Repositorios } from '../dominio/puertos.js';
import type { UsuarioAutenticado } from '../dominio/tipos.js';

/**
 * Ampliación de los tipos de Fastify.
 *
 * `usuario` y `repos` los rellena el plugin de autenticación en `onRequest`,
 * que se ejecuta antes que cualquier handler. Declararlos aquí evita castear en
 * cada ruta.
 */
declare module 'fastify' {
  interface FastifyRequest {
    /** Identidad resuelta, o `null` si la petición es anónima. */
    usuario: UsuarioAutenticado | null;

    /**
     * Repositorios atados al token del llamante (RLS activo).
     *
     * Se declara anulable porque Fastify exige un valor por defecto en
     * `decorateRequest` y compartir una instancia entre peticiones sería un bug
     * grave. El plugin de autenticación siempre lo rellena; para leerlo con
     * garantías, usa `reposDe(request)`.
     */
    repos: Repositorios | null;
  }
}
