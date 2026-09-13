import type { preHandlerHookHandler } from 'fastify';
import { ErrorApi } from '../../dominio/errores.js';
import type { Rol } from '../../dominio/tipos.js';
import type { CacheModulos, CacheParametros } from '../../infra/cache.js';

/**
 * Guardias de módulo: el corazón del Poder Absoluto del Administrador.
 *
 * Cuando el administrador apaga un módulo desde el cPanel, la API debe dejar de
 * atenderlo **de inmediato** (dentro del TTL de la caché) y con un error
 * explícito, no con un 500 ni con datos a medias. El frontend, además, lo
 * ocultará del menú; pero el frontend no es una barrera de seguridad.
 *
 * La lógica vive en funciones puras (`comprobarModulo`, `comprobarMantenimiento`)
 * y los `preHandler` son sólo adaptadores. Así los tests verifican la regla sin
 * levantar un servidor.
 */

export async function comprobarModulo(
  cache: CacheModulos,
  clave: string,
  rol: Rol | null,
): Promise<void> {
  const modulo = await cache.porClave(clave);

  if (!modulo) {
    throw ErrorApi.noEncontrado(
      'MODULO_DESCONOCIDO',
      `El módulo "${clave}" no está registrado en el sistema.`,
    );
  }

  if (!modulo.habilitado) {
    throw ErrorApi.prohibido(
      'MODULO_DESHABILITADO',
      `El módulo "${modulo.nombre}" está deshabilitado por el administrador.`,
      { modulo: clave },
    );
  }

  // Lista vacía = visible para todos. Con valores, es una lista blanca.
  if (modulo.rolesPermitidos.length > 0) {
    if (rol === null || !modulo.rolesPermitidos.includes(rol)) {
      throw ErrorApi.prohibido(
        'MODULO_NO_AUTORIZADO',
        `No tienes acceso al módulo "${modulo.nombre}".`,
        { modulo: clave, rolesPermitidos: modulo.rolesPermitidos },
      );
    }
  }
}

/**
 * Bloquea la API durante el mantenimiento, salvo para administradores.
 *
 * El administrador conserva el acceso a propósito: si no, activar el
 * mantenimiento lo dejaría fuera y ya no podría desactivarlo.
 */
export async function comprobarMantenimiento(
  cache: CacheParametros,
  rol: Rol | null,
): Promise<void> {
  if (rol === 'admin') return;

  if (await cache.mantenimientoActivo()) {
    throw ErrorApi.servicioNoDisponible(
      'El sistema está en mantenimiento. Inténtalo de nuevo en unos minutos.',
    );
  }
}

/** `preHandler` de Fastify para exigir un módulo encendido y autorizado. */
export function exigirModulo(
  cache: CacheModulos,
  clave: string,
): preHandlerHookHandler {
  return async (request) => {
    await comprobarModulo(cache, clave, request.usuario?.rol ?? null);
  };
}

/** `preHandler` de Fastify para respetar el modo mantenimiento. */
export function exigirSinMantenimiento(
  cache: CacheParametros,
): preHandlerHookHandler {
  return async (request) => {
    await comprobarMantenimiento(cache, request.usuario?.rol ?? null);
  };
}
