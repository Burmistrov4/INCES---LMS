import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorApi } from '../../dominio/errores.js';
import { descripcionDeEstado } from '../../dominio/reglas-inscripciones.js';
import {
  esquemaIdSeccion,
  esquemaListadoOfertas,
  esquemaReincorporar,
  esquemaSolicitarInscripcion,
} from '../esquemas.js';
import { exigirAdmin, exigirSesion, reposDe } from '../plugins/autenticacion.js';

/**
 * Rutas del Módulo 4 — Inscripciones y cupos.
 *
 * **Aquí no se decide ningún cupo.** La lógica vive entera en PostgreSQL, en las
 * RPC `security definer` y en el cerrojo por sección. Este archivo sólo traduce
 * entre HTTP y esas RPC, y su trabajo real es **traducir los errores**: un
 * `23514` genérico no le dice al estudiante que ya está en otra sección de esa
 * materia, ni al administrador que el chico nunca cursó la sección.
 *
 * **Ninguna ruta escribe en `enrollments` directo.** La tabla tiene `INSERT`,
 * `UPDATE`, `DELETE` y `TRUNCATE` revocados para `anon` y `authenticated` (R-23):
 * intentarlo daría `42501`. Y no es una limitación que haya que rodear — la clave
 * publishable viaja al cliente (ADR-003), así que si se pudiera escribir directo,
 * cualquiera se auto-inscribiría en `ENROLLED` y el motor sería decorativo.
 *
 * **El archivo usa los dos patrones de registro a propósito.** Las rutas de
 * estudiante van sueltas con la ruta completa y la guardia por ruta (Patrón B);
 * las de administración van en un bloque con prefijo y una sola guardia (Patrón
 * A). Es la misma mezcla que hace `cuadrante.ts`.
 *
 * El contrato completo, con el porqué de cada decisión, está en
 * `docs/BRIEFING_BACKEND_MODULO4.md`.
 */

/**
 * Envoltorios de `params`.
 *
 * **`:id` es el identificador de la SECCIÓN, no el de la inscripción.** Una
 * inscripción no tiene identidad propia en la API: se identifica por el par
 * (estudiante, sección), y el estudiante es siempre el de la sesión. Las RPC
 * reciben `p_section_id`, así que el parámetro de la ruta es la sección.
 */
const esquemaRutaIdSeccion = z.object({ id: esquemaIdSeccion });

export function rutasInscripciones(app: FastifyInstance): void {
  // --- Estudiante -----------------------------------------------------------
  //  Patrón B: ruta completa inline y la guardia en las opciones de la ruta.

  app.get(
    '/api/v1/ofertas',
    { preHandler: [exigirSesion()] },
    async (request) => {
      const { periodo, programaId, materiaId, soloConCupo, busqueda, limite, desplazamiento } =
        esquemaListadoOfertas.parse(request.query);

      const { secciones, total } = await reposDe(request).inscripciones.listarOfertas({
        periodo,
        programaId,
        materiaId,
        soloConCupo,
        busqueda,
        limite,
        desplazamiento,
      });

      // Cada fila trae `ofertaVigente` y `cuposDisponibles` por separado a
      // propósito: con una oferta en el aire, `cuposDisponibles` puede ser > 0 y
      // el asiento NO se puede dar. La pantalla debe usar `ofertaVigente` para no
      // ofrecer algo que la base va a negar.
      return { secciones, total, limite, desplazamiento };
    },
  );

  app.get(
    '/api/v1/mis-inscripciones',
    { preHandler: [exigirSesion()] },
    async (request) => {
      const usuario = request.usuario;
      if (!usuario) throw ErrorApi.noAutorizado();

      // El id se pasa explícito: un administrador tiene permiso para leer todas
      // las filas, así que sin esto vería las inscripciones de todo el centro.
      const inscripciones = await reposDe(request).inscripciones.misInscripciones(usuario.id);

      return { inscripciones };
    },
  );

  app.post(
    '/api/v1/inscripciones',
    { preHandler: [exigirSesion()] },
    async (request, reply) => {
      const { seccionId } = esquemaSolicitarInscripcion.parse(request.body);

      const estado = await reposDe(request).inscripciones.solicitar(seccionId);

      // 201: se creó una inscripción, y el estado resultante dice si entró o
      // quedó en la cola. **No se adivina aquí**: lo decide la base dentro de su
      // cerrojo, y una segunda copia de la regla se desviaría.
      return reply.status(201).send({
        estado,
        mensaje: descripcionDeEstado(estado),
      });
    },
  );

  app.post<{ Params: { id: string } }>(
    '/api/v1/inscripciones/:id/aceptar',
    { preHandler: [exigirSesion()] },
    async (request) => {
      const { id } = esquemaRutaIdSeccion.parse(request.params);

      const estado = await reposDe(request).inscripciones.aceptar(id);

      return { estado, mensaje: descripcionDeEstado(estado) };
    },
  );

  app.post<{ Params: { id: string } }>(
    '/api/v1/inscripciones/:id/renunciar',
    { preHandler: [exigirSesion()] },
    async (request) => {
      const { id } = esquemaRutaIdSeccion.parse(request.params);

      const estado = await reposDe(request).inscripciones.renunciar(id);

      // `DROPPED` no es un borrado: la fila se conserva como historial, y volver
      // a entrar es una excepción de administración. Se responde 200 y no 204
      // para poder decir el estado resultante.
      return { estado, mensaje: descripcionDeEstado(estado) };
    },
  );

  // --- Administración -------------------------------------------------------
  //  Patrón A: bloque con prefijo y una sola guardia para todas las rutas.

  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());

      admin.get('/ocupacion', async (request) => {
        const { periodo, programaId, materiaId, soloConCupo, busqueda, limite, desplazamiento } =
          esquemaListadoOfertas.parse(request.query);

        // A diferencia de `/ofertas`, aquí **sí** se ven las secciones archivadas:
        // el administrador necesita poder consultar el histórico de una cerrada.
        const { secciones, total } = await reposDe(request).inscripciones.listarOcupacion({
          periodo,
          programaId,
          materiaId,
          soloConCupo,
          busqueda,
          limite,
          desplazamiento,
        });

        return { secciones, total, limite, desplazamiento };
      });

      admin.get<{ Params: { id: string } }>('/secciones/:id/cola', async (request) => {
        const { id } = esquemaRutaIdSeccion.parse(request.params);

        // Orden FIFO: el primero que llegó es el primero. `PENDING_BID` no
        // aparece aquí —ya salió de la cola, se le ofreció un asiento— y
        // `ENROLLED` tampoco.
        const cola = await reposDe(request).inscripciones.colaDeSeccion(id);

        return { cola };
      });

      admin.get<{ Params: { id: string } }>('/secciones/:id/inscripciones', async (request) => {
        const { id } = esquemaRutaIdSeccion.parse(request.params);

        // Todos los estados, no sólo la cola: es la vista de «quién está en esta
        // sección», incluidos los que se dieron de baja.
        const inscripciones = await reposDe(request).inscripciones.inscritosDeSeccion(id);

        return { inscripciones };
      });

      admin.post<{ Params: { id: string } }>('/secciones/:id/promover', async (request) => {
        const { id } = esquemaRutaIdSeccion.parse(request.params);

        const promovida = await reposDe(request).inscripciones.promover(id);

        // **Un `null` no es un error y no puede ser un 404.** Significa que no
        // había nadie a quien promover, y eso pasa por tres motivos legítimos:
        // la cola está vacía, la sección está llena, o ya hay una oferta viva
        // (una oferta por asiento). Devolver un error obligaría al administrador a
        // adivinar cuál de los tres es; devolver 200 con la explicación se lo dice.
        if (promovida === null) {
          return {
            promovida: null,
            mensaje:
              'No se promovió a nadie: la cola está vacía, la sección está llena, ' +
              'o ya hay una oferta de cupo en el aire para esa sección.',
          };
        }

        return { promovida, mensaje: descripcionDeEstado(promovida.estado) };
      });

      admin.post('/inscripciones/reincorporar', async (request) => {
        const { estudianteId, seccionId } = esquemaReincorporar.parse(request.body);

        const estado = await reposDe(request).inscripciones.reincorporar(
          estudianteId,
          seccionId,
        );

        // Esta RPC **puede exceder la capacidad** y es deliberado: «si el admin
        // autoriza, el sistema obedece». No es un agujero, es una decisión de
        // administración, y queda registrada en la fila.
        return { estado, mensaje: descripcionDeEstado(estado) };
      });

      admin.post('/inscripciones/expirar', async (request) => {
        // Idempotente y sin `pg_cron` a propósito: el proyecto tiene arquitectura
        // dual (nube + servidor local) y cortes eléctricos, así que no se puede
        // depender de un planificador concreto. La segunda llamada devuelve 0.
        const vencidas = await reposDe(request).inscripciones.expirarOfertas();

        return {
          vencidas,
          mensaje:
            vencidas === 0
              ? 'No había ofertas vencidas.'
              : `Se vencieron ${vencidas} oferta(s) de cupo y se promovió a quien correspondía.`,
        };
      });
    },
    { prefix: '/api/v1/admin' },
  );
}
