import type { FastifyInstance, FastifyRequest, preHandlerHookHandler } from 'fastify';
import { ErrorApi } from '../../dominio/errores.js';
import type { Repositorios } from '../../dominio/puertos.js';
import type { UsuarioAutenticado } from '../../dominio/tipos.js';

export interface OpcionesAutenticacion {
  /** Verifica el token y devuelve la identidad, o `null` si no es válido. */
  verificarToken: (token: string) => Promise<{ id: string; email: string | null } | null>;

  /**
   * Repositorios atados al token del llamante. Se crean por petición para que
   * Postgres aplique RLS: si la autorización de la API fallara, la base de datos
   * seguiría siendo una barrera.
   */
  reposDePeticion: (token: string | null) => Repositorios;
}

/** Extrae el token de `Authorization: Bearer <token>`. */
export function extraerToken(cabecera: string | undefined): string | null {
  if (!cabecera) return null;
  const partes = cabecera.split(' ');
  if (partes.length !== 2) return null;

  const [esquema, valor] = partes;
  if (!esquema || esquema.toLowerCase() !== 'bearer') return null;

  const token = valor?.trim();
  return token && token.length > 0 ? token : null;
}

/**
 * Resuelve la identidad de cada petición.
 *
 * Un token inválido o ausente NO es un error: deja `request.usuario` en `null` y
 * son las guardias de cada ruta las que deciden si eso es aceptable. Así una
 * ruta pública y una protegida conviven bajo el mismo plugin.
 */
export function registrarAutenticacion(
  app: FastifyInstance,
  opciones: OpcionesAutenticacion,
): void {
  app.decorateRequest('usuario', null);
  app.decorateRequest('repos', null);

  app.addHook('onRequest', async (request) => {
    const token = extraerToken(request.headers.authorization);

    // Siempre hay repositorios, incluso sin token (actúan como `anon`).
    request.repos = opciones.reposDePeticion(token);

    if (!token) {
      request.usuario = null;
      return;
    }

    const identidad = await opciones.verificarToken(token);
    if (!identidad) {
      request.usuario = null;
      return;
    }

    const perfil = await request.repos.perfiles.porId(identidad.id);

    // Sin perfil no se puede saber el rol. En vez de expulsar al usuario (lo que
    // dejaría fuera a cuentas creadas antes del trigger de onboarding), se asume
    // el rol con menos privilegios. Degradar es seguro; bloquear no lo es.
    const rol = perfil?.rol ?? 'estudiante';

    if (perfil && !perfil.activo) {
      throw ErrorApi.prohibido(
        'CUENTA_INACTIVA',
        'Tu cuenta está desactivada. Contacta al centro formativo.',
      );
    }

    const usuario: UsuarioAutenticado = {
      id: identidad.id,
      email: identidad.email ?? perfil?.email ?? '',
      rol,
      perfil:
        perfil ??
        ({
          id: identidad.id,
          email: identidad.email ?? '',
          cedula: null,
          nombres: '',
          apellidos: '',
          rol: 'estudiante',
          activo: true,
        } satisfies UsuarioAutenticado['perfil']),
    };

    request.usuario = usuario;
  });
}

/** Exige una sesión válida. */
export function exigirSesion(): preHandlerHookHandler {
  return async (request) => {
    if (!request.usuario) throw ErrorApi.noAutorizado();
  };
}

/**
 * Repositorios de la petición, con la garantía de que existen.
 *
 * El plugin de autenticación los asigna siempre, pero el tipo es anulable (ver
 * `tipos-fastify.d.ts`). En vez de usar `!` —que silenciaría un fallo real si
 * algún día el orden de los hooks cambiara— se comprueba y se falla ruidosamente.
 */
export function reposDe(request: FastifyRequest): Repositorios {
  const repos = request.repos;
  if (!repos) {
    throw ErrorApi.interno(
      'Los repositorios de la petición no se inicializaron. Revisa el orden de los hooks.',
    );
  }
  return repos;
}

/**
 * Exige el rol de administrador.
 *
 * La API comprueba el rol aquí; la base de datos lo vuelve a comprobar en las
 * políticas RLS. Son dos barreras independientes, no una repetida.
 */
export function exigirAdmin(): preHandlerHookHandler {
  return async (request) => {
    const usuario = request.usuario;
    if (!usuario) throw ErrorApi.noAutorizado();

    if (usuario.rol !== 'admin') {
      throw ErrorApi.prohibido(
        'SOLO_ADMIN',
        'Esta acción está reservada al Administrador Maestro.',
      );
    }
  };
}
