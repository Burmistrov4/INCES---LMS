import type { FastifyInstance } from 'fastify';
import { ErrorApi } from '../../dominio/errores.js';
import { modulosVisibles } from '../../dominio/tipos.js';
import type { DependenciasRutas } from '../dependencias.js';
import { exigirSesion } from '../plugins/autenticacion.js';

/**
 * Rutas del usuario autenticado.
 *
 * `/yo` es la llamada que hace el frontend al arrancar: devuelve quién es, con
 * qué rol, y **sólo los módulos que puede ver**. Con esto la UI se construye sin
 * tener que conocer la lista de módulos ni sus reglas de visibilidad.
 */
export function rutasYo(app: FastifyInstance, deps: DependenciasRutas): void {
  app.get('/api/v1/yo', { preHandler: [exigirSesion()] }, async (request) => {
    const usuario = request.usuario;
    if (!usuario) throw ErrorApi.noAutorizado();

    const modulos = await deps.caches.modulos.todos();

    return {
      perfil: usuario.perfil,
      rol: usuario.rol,
      modulos: modulosVisibles(modulos, usuario.rol),
    };
  });

  app.get('/api/v1/modulos', { preHandler: [exigirSesion()] }, async (request) => {
    const usuario = request.usuario;
    if (!usuario) throw ErrorApi.noAutorizado();

    const modulos = await deps.caches.modulos.todos();

    return { modulos: modulosVisibles(modulos, usuario.rol) };
  });
}
