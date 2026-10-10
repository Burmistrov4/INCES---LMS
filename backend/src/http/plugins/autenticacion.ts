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
 * Lee el `sub` del token **sin verificar la firma**.
 *
 * Existe sólo para poder empezar la lectura del perfil **en paralelo** con la
 * verificación del token, que es la que manda. No autoriza nada por sí sola:
 *
 *   · el perfil se lee con el cliente del propio token, así que PostgREST
 *     valida la firma y aplica RLS antes de devolver una fila;
 *   · el resultado **sólo se usa si coincide con la identidad que devuelve la
 *     verificación autoritativa**; si no coincide, se relee con el id verificado.
 *
 * Un `sub` inventado no abre ninguna puerta: la consulta que lo usa va firmada
 * con el mismo token, y un token inválido muere en PostgREST.
 */
export function subDeclaradoDelToken(token: string): string | null {
  const partes = token.split('.');
  if (partes.length !== 3) return null;
  try {
    const carga = JSON.parse(Buffer.from(partes[1]!, 'base64url').toString('utf8')) as {
      sub?: unknown;
    };
    return typeof carga.sub === 'string' && carga.sub.length > 0 ? carga.sub : null;
  } catch {
    return null;
  }
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

    // **Los dos viajes de red van en paralelo.** Verificar el token (GoTrue) y
    // leer el perfil (PostgREST) eran secuenciales, y cada uno cuesta ~200 ms de
    // ida y vuelta al proyecto: ~420 ms de coste fijo en CADA petición
    // autenticada, antes de que el manejador haga nada. Medido el 2026-10-09:
    // `GET /api/v1/yo` (que no consulta nada por su cuenta) tardaba 421 ms.
    //
    // La dependencia que los encadenaba era aparente: el perfil se lee por el
    // `sub`, y el `sub` ya está en el token. Se lee sin verificar (ver
    // `subDeclaradoDelToken`) y **el resultado sólo se acepta si coincide con la
    // identidad verificada**; si no coincidiera, se relee con el id de confianza.
    // Un token inválido sigue muriendo en la verificación.
    const sub = subDeclaradoDelToken(token);
    const [verificacion, lecturaPerfil] = await Promise.allSettled([
      opciones.verificarToken(token),
      sub === null ? Promise.resolve(null) : request.repos.perfiles.porId(sub),
    ]);

    // Un fallo de la verificación se propaga (500), como antes: un servicio de
    // identidad caído no es «no tienes sesión». Sólo un resultado nulo —token
    // inválido o expirado— deja la petición sin usuario.
    if (verificacion.status === 'rejected') throw verificacion.reason;

    const identidad = verificacion.value;
    if (!identidad) {
      request.usuario = null;
      return;
    }

    // El token es válido, así que el perfil tiene que haberse podido leer. Si su
    // lectura falló se propaga —igual que antes— en vez de degradar el rol en
    // silencio, que convertiría un fallo transitorio de la base en un 403
    // inexplicable para el usuario.
    if (lecturaPerfil.status === 'rejected') throw lecturaPerfil.reason;

    const perfil =
      sub === identidad.id
        ? lecturaPerfil.value
        : // Defensivo y en la práctica inalcanzable: para un token válido, `sub`
          // y el id verificado son el mismo. Si algún día no lo fueran, manda la
          // verificación y se relee por el id de confianza.
          await request.repos.perfiles.porId(identidad.id);

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
