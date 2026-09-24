import type { FastifyInstance } from 'fastify';
import { ErrorApi } from '../../dominio/errores.js';
import { modulosVisibles } from '../../dominio/tipos.js';
import type { DependenciasRutas } from '../dependencias.js';
import { esquemaPlanilla } from '../esquemas.js';
import { exigirSesion, reposDe } from '../plugins/autenticacion.js';

/**
 * Rutas del usuario autenticado.
 *
 * `/yo` es la llamada que hace el frontend al arrancar: devuelve quién es, con
 * qué rol, y **sólo los módulos que puede ver**. Con esto la UI se construye sin
 * tener que conocer la lista de módulos ni sus reglas de visibilidad.
 *
 * Además del par de lecturas del arranque, aquí vive la **escritura de la
 * planilla de inscripción** (`PUT /api/v1/yo/planilla`). Está en este archivo y
 * no en `rutas/planilla.ts` —que es donde se lee el catálogo— porque `/yo` es un
 * espacio de nombres con dueño: quien busque una ruta `/yo/...` la busca aquí.
 * Repartirlas por «de qué hablan» en vez de «bajo qué prefijo viven» obligaría a
 * saber de antemano qué archivo elegir, que es justo lo que un espacio de
 * nombres evita. Las dos rutas se referencian en sus comentarios.
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

  /**
   * Guarda la planilla de inscripción del llamante.
   *
   * `PUT` y no `PATCH`, y la diferencia importa: esta ruta **reemplaza** la
   * planilla entera. No es un parche incremental —que obligaría al cliente a
   * saber qué campos borrar, y esa no es su responsabilidad— sino el estado
   * final. Es la misma decisión que `esquemaReemplazarPensum` en M2.
   *
   * **Por qué pasa por el backend y no escribe el cliente directo.** El
   * formulario actual hace `signUp` desde Flutter sin tocar Fastify, y está bien:
   * tiene que ocurrir en el cliente para establecer la sesión. Esta escritura no
   * tiene esa excusa. Pasa por aquí porque (a) la regla del proyecto es
   * Flutter→Fastify y el `signUp` es la excepción justificada, no la norma, y
   * (b) el `23514` de `validar_planilla()` **nombra los campos que faltan** y sólo
   * se puede traducir a un mensaje útil en el servidor. La validación en sí no
   * depende de esta ruta: la impone el trigger `aspirantes_validar_planilla`
   * (`202609240002`) sobre la tabla, así que escribir la columna por PostgREST
   * saltándose esta ruta da el mismo error.
   *
   * `usuario.id` se pasa **explícito** aunque la RLS ya filtre por
   * `user_id = auth.uid()`: un administrador tiene permiso para escribir
   * cualquier fila, y sin el parámetro esta ruta escribiría en la ficha que la
   * base eligiera. Misma razón que en `misInscripciones` y `miHorario`.
   */
  app.put('/api/v1/yo/planilla', { preHandler: [exigirSesion()] }, async (request) => {
    const usuario = request.usuario;
    if (!usuario) throw ErrorApi.noAutorizado();

    const { planilla } = esquemaPlanilla.parse(request.body);

    const guardada = await reposDe(request).planilla.guardar(usuario.id, planilla);

    // Se devuelve la planilla que quedó **en la base**, no la que llegó: es lo
    // que el cliente necesita para refrescar su estado sin una segunda petición,
    // y no es un eco — jsonb normaliza lo que guarda.
    return { planilla: guardada };
  });
}
