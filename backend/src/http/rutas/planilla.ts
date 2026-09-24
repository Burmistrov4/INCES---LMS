import type { FastifyInstance } from 'fastify';
import { reposDe } from '../plugins/autenticacion.js';

/**
 * Catálogo público del formulario de inscripción (Módulo 4).
 *
 * ========================================================================
 *  POR QUÉ ESTE ARCHIVO NO ES `inscripciones.ts`
 * ========================================================================
 * Los dos son Módulo 4 y los dos hablan de inscribirse, así que conviene decir
 * por qué están separados en vez de dejar que se descubra por el nombre.
 *
 * `inscripciones.ts` es el **motor de cupos**: cola FIFO, ofertas con
 * vencimiento, reincorporación. Todas sus rutas exigen sesión, porque hay que
 * ser alguien para pedir un asiento. Lo que vive aquí es otra cosa: la
 * **declaración de los campos** que el aspirante va a rellenar. Y su
 * visibilidad es la contraria —tiene que leerse **sin sesión**—, porque el
 * formulario se pinta *antes* de que el aspirante tenga cuenta.
 *
 * Un archivo aparte deja ese contraste a la vista. Metido dentro de
 * `inscripciones.ts`, entre doce rutas que todas exigen sesión, la única ruta
 * pública del módulo parecería un descuido en vez de una decisión.
 *
 * ========================================================================
 *  POR QUÉ LA RUTA ES PÚBLICA, Y POR QUÉ ESO NO EXPONE NADA
 * ========================================================================
 * `GET /api/v1/inscripcion/campos` **no lleva `exigirSesion()`**, y es la única
 * ruta nueva del proyecto que no lo lleva. La justificación, porque una ruta
 * sin guardia es exactamente lo que hay que mirar dos veces:
 *
 *   · Lo que devuelve son **definiciones de campo** —«Segundo nombre», «Estado
 *     civil», «¿Pertenece a un pueblo indígena?»—, no respuestas de nadie. Saber
 *     que el formulario pregunta el estado civil no dice nada de ningún
 *     aspirante.
 *   · Un formulario de inscripción pública **no puede exigir autenticación para
 *     saber qué preguntar**: quien se está inscribiendo todavía no tiene cuenta.
 *     La alternativa —autenticarse primero y rellenar después— es justo el orden
 *     que rompe ADR-007, porque abriría una cuenta sin planilla y una ventana en
 *     la que el usuario existe a medias.
 *   · No hay nada que autorizar: el catálogo es **configuración del sistema**,
 *     del mismo tipo que `system_settings`, que ya tiene parámetros públicos
 *     (`es_publico`) legibles sin sesión. Es el mismo criterio, aplicado a la
 *     misma clase de dato.
 *
 * La barrera de verdad está en la base, no aquí (ADR-003): la política
 * `inscripcion_campos_lectura_publica` deja leer a `anon` **sólo los campos
 * activos**, y la escritura del catálogo está cerrada a `is_admin()`. Es decir,
 * aunque esta ruta no comprobara nada, un cliente no podría ver un campo
 * desactivado ni tocar el catálogo. La ruta no es la frontera; la RLS lo es.
 *
 * **La escritura de la planilla no está aquí**: vive en `PUT /api/v1/yo/planilla`
 * (`rutas/yo.ts`), que sí exige sesión y es su propio recurso. Este archivo sólo
 * lee.
 */
export function rutasPlanilla(app: FastifyInstance): void {
  app.get('/api/v1/inscripcion/campos', async (request) => {
    // Sin `preHandler` a propósito: ver la cabecera. `reposDe(request)` sigue
    // siendo válido sin sesión —el plugin de autenticación asigna los
    // repositorios siempre, y sin token actúan como `anon`—, así que la consulta
    // sale con la clave publishable y es la RLS la que decide qué se ve.
    const campos = await reposDe(request).planilla.campos();

    return { campos };
  });
}
