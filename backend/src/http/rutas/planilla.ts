import type { FastifyInstance } from 'fastify';
import type { DependenciasRutas } from '../dependencias.js';
import { exigirAdmin, reposDe } from '../plugins/autenticacion.js';
import { exigirModulo } from '../plugins/modulos.js';

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
 *
 * ========================================================================
 *  LA GUARDIA DE MÓDULO, Y POR QUÉ NO CONTRADICE LO DE ARRIBA
 * ========================================================================
 * Las dos rutas llevan `exigirModulo('m4_inscripciones')` y responden 403
 * `MODULO_DESHABILITADO` si el administrador apaga el módulo desde el cPanel. No
 * contradice la defensa de la ruta pública: `exigirSesion()` pregunta **quién
 * llama** —y aquí no hay nada que preguntar, porque el formulario se pinta antes
 * de que exista una cuenta—, mientras que `exigirModulo()` pregunta **si el
 * módulo está encendido**. Son dos ejes distintos, y con el módulo apagado no hay
 * formulario que pintar. La bandera la respeta el frontend escondiendo el ítem
 * del menú; que la imponga también la API es lo que la vuelve una barrera y no un
 * adorno.
 */
export function rutasPlanilla(app: FastifyInstance, deps: DependenciasRutas): void {
  /**
   * La guardia del módulo, construida **una sola vez** para las dos rutas.
   *
   * `exigirModulo` es una fábrica y el hook no tiene estado, así que compartirlo
   * es seguro. En el bloque de administración va después de `exigirAdmin()` —como
   * en `inscripciones.ts`, `curriculo.ts` y `cuadrante.ts`— para que una petición
   * anónima reciba **401** y no el 403 del módulo.
   */
  const exigirInscripciones = exigirModulo(deps.caches.modulos, 'm4_inscripciones');

  app.get('/api/v1/inscripcion/campos', { preHandler: [exigirInscripciones] }, async (request) => {
    // Sin `exigirSesion()` a propósito: ver la cabecera. Pero **sí** lleva la
    // guardia del módulo, y son dos preguntas distintas: `exigirSesion()` habla de
    // quién llama, `exigirModulo()` de si el módulo está encendido. Con el módulo
    // apagado no hay formulario que pintar, y por eso el catálogo se apaga con él.
    // Sin sesión, `reposDe(request)` sigue siendo válido —el plugin de
    // autenticación asigna los repositorios siempre, y sin token actúan como
    // `anon`—, así que la consulta sale con la clave publishable y es la RLS la
    // que decide qué se ve.
    const campos = await reposDe(request).planilla.campos();

    return { campos };
  });

  /**
   * Genera la planilla de inscripción del INCES **llena** en PDF para **cualquier**
   * aspirante, a partir de su UUID.
   *
   * Es la variante de administrador de `GET /api/v1/yo/planilla/pdf`: la misma
   * ficha pintada, pero dirigida por un UUID que llega en la ruta y no en la
   * sesión. La RLS `aspirantes_admin_all` es la que autoriza leer la fila ajena;
   * aquí sólo se exige el rol de administrador. Si el UUID no corresponde a una
   * ficha, el adaptador responde `SIN_FICHA_DE_ASPIRANTE` (404).
   */
  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());
      // Segundo a propósito: ver el porqué en la guardia de arriba.
      admin.addHook('preHandler', exigirInscripciones);

      admin.get('/planilla/:usuarioId/pdf', async (request, reply) => {
        const { usuarioId } = request.params as { usuarioId: string };

        const pdf = await reposDe(request).planilla.generarPdf(usuarioId);

        return reply
          .type('application/pdf')
          .header(
            'Content-Disposition',
            `attachment; filename="planilla-inscripcion-${usuarioId}.pdf"`,
          )
          .send(Buffer.from(pdf));
      });
    },
    { prefix: '/api/v1/inscripcion' },
  );
}
