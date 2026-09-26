import fastifyWebsocket from '@fastify/websocket';
import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { z } from 'zod';
import { exigirSesion, reposDe } from '../plugins/autenticacion.js';

/**
 * Rutas de la asistencia concurrente (QR efímero + WebSocket). M7.
 *
 * **La arquitectura en dos canales, y por qué.**
 *
 *   1. REST guarda. La marca de asistencia es un HECHO y la verdad la tiene la
 *      base. La validación del código efímero NO vive en esta ruta: vive en la
 *      política RLS `attendance_marks_estudiante_insert` (202609260001), que
 *      llama a `asistencia_codigo_vigente` y rechaza con 42501 un código
 *      caducado. Si el alumno se salta la app y habla directo a PostgREST, la
 *      barrera es la misma.
 *
 *   2. WS avisa. El tablero del docente NO hace polling: se suscribe al canal
 *      de la sesión y el backend empuja un evento por cada marca que entra. La
 *      PC del docente vive sin recargar; el nombre del alumno llega al instante.
 *
 * **El secreto del QR viaja UNA vez** (en la respuesta de `POST /sesiones`) y
 * no se vuelve a leer: la app del docente lo conserva en memoria y deriva el
 * código en cada ventana de 15 s. Si un alumno fotografía la pantalla, el
 * código ya caducó —la ventana chica es el antídoto barato—.
 *
 * **El código se compruña en la base, no aquí — ADR-003:** la frontera es la
 * RLS, no la API. Esta ruta sólo hace la forma (Zod) y empuja el evento al WS.
 */
export function rutasAsistencia(app: FastifyInstance): void {
  // --- REST: crear, marcar, leer, cerrar -----------------------------------
  app.register(
    async (asistencia) => {
      asistencia.addHook('preHandler', exigirSesion());

      // Docente: abre una sesión y recibe el secreto del QR (una sola vez).
      asistencia.post('/sesiones', async (request) => {
        const { seccionId, ventanaSeg } = esquemaCrearSesion.parse(request.body);
        const usuario = request.usuario!;

        const sesion = await reposDe(request).asistencia.crearSesion({
          seccionId,
          abiertoPor: usuario.id,
          ventanaSeg,
        });

        return reply201(sesion);
      });

      // Docente/admin: las marcas de una sesión, en orden de llegada.
      asistencia.get<{ Params: { id: string } }>('/sesiones/:id/marcas', async (request) => {
        const { id } = esquemaIdSesion.parse(request.params);
        const marcas = await reposDe(request).asistencia.marcasDeSesion(id);
        return { marcas };
      });

      // Estudiante: marca asistencia. La RLS valida el código — aquí se espera.
      asistencia.post('/marcar', async (request) => {
        const { sesionId, codigo } = esquemaMarcar.parse(request.body);
        const usuario = request.usuario!;

        const resultado = await reposDe(request).asistencia.marcar(sesionId, codigo, usuario.id);

        if (resultado !== 'duplicada') {
          // Avisa al canal WS: la pantalla del docente pinta la fila verde
          // sin polling.
          difundir(sesionId, {
            tipo: 'marca',
            sesionId,
            marca: resultado,
          });
        }

        return { ok: true, duplicada: resultado === 'duplicada' };
      });

      // Docente: cierra la sesión. Las marcas se conservan.
      asistencia.patch<{ Params: { id: string } }>('/sesiones/:id/cerrar', async (request) => {
        const { id } = esquemaIdSesion.parse(request.params);
        await reposDe(request).asistencia.cerrarSesion(id, request.usuario!.id);
        difundir(id, { tipo: 'sesion_cerrada', sesionId: id });
        return { ok: true };
      });
    },
    { prefix: '/api/v1/asistencia' },
  );

  // -------------------------------------------------------------------------
  //  WebSocket: el canal POR SESIÓN que pinta el tablero del docente en vivo
  // -------------------------------------------------------------------------
  //
  // Suscripción: `GET /api/v1/asistencia/rt?sesion=<uuid>` con `Authorization:
  // Bearer <jwt>` — el mismo JWT de Supabase que usa REST, no una puerta aparte.
  //
  // El canal es UNIDIRECCIONAL (servidor → cliente) por diseño: el estudiante
  // marca por REST y el WS SÓLO avisa. Un cliente no puede mandar una marca por
  // aquí.
  app.register(
    async (rt) => {
      await rt.register(fastifyWebsocket);
      rt.addHook('preHandler', exigirSesion());

      rt.route({
        method: 'GET',
        url: '/rt',
        // `wsHandler` y no `websocket: true`: éste último sustituye el handler
        // HTTP por un 404 fijo, y el contrato OpenAPI del repo —que pide a cada
        // ruta documentada responder algo distinto de 404— reprobaría la ruta.
        // Con `wsHandler` el GET plano (autenticado) responde 200 con la
        // explicación del upgrade, y el upgrade real pasa por
        // `manejarSuscripcion`.
        wsHandler: manejarSuscripcion,
        handler: (request, reply) => {
          const { sesion } = (request.query ?? {}) as Record<string, string | undefined>;
          if (!sesion) {
            return reply.code(400).send({
              error: {
                codigo: 'SESION_REQUERIDA',
                mensaje: 'Falta `?sesion=<uuid>` en la consulta.',
              },
            });
          }
          return reply.send({
            canal: 'websocket',
            como: 'Conéctate con el header `Upgrade: websocket` y la misma URL.',
            sesion,
          });
        },
      });
    },
    { prefix: '/api/v1/asistencia' },
  );
}

// --- Piezas ----------------------------------------------------------------

const esquemaCrearSesion = z.object({
  seccionId: z.string().uuid('seccionId debe ser uuid.'),
  ventanaSeg: z.coerce.number().int().min(5).max(120).default(15),
});

const esquemaIdSesion = z.object({ id: z.string().uuid() });

const esquemaMarcar = z.object({
  sesionId: z.string().uuid(),
  codigo: z.string().min(1, 'Falta el código del QR.'),
});

function reply201(datos: unknown) {
  return { sesion: datos };
}

type Canal = Set<WebSocket>;
const canales = new Map<string, Canal>();

/**
 * La suscripción WS de una sesión de asistencia. Unidireccional a propósito:
 * el estudiante marca por REST y aquí sólo se empuja; nadie siembra marcas
 * por el canal.
 */
function manejarSuscripcion(
  socket: WebSocket,
  request: { usuario: unknown; query: unknown },
): void {
  const { sesion } = (request.query ?? {}) as Record<string, string | undefined>;
  if (!sesion || !/^[0-9a-f-]{36}$/i.test(sesion)) {
    socket.close(4000, 'sesión inválida');
    return;
  }
  if (!request.usuario) {
    socket.close(4001, 'sin sesión');
    return;
  }
  if (!canales.has(sesion)) canales.set(sesion, new Set());
  canales.get(sesion)!.add(socket);

  socket.send(JSON.stringify({ tipo: 'conectado', sesionId: sesion }));

  socket.on('close', () => {
    const canal = canales.get(sesion);
    if (!canal) return;
    canal.delete(socket);
    if (canal.size === 0) canales.delete(sesion);
  });
}

function difundir(sesionId: string, evento: unknown): void {
  const canal = canales.get(sesionId);
  if (!canal) return;
  const datos = JSON.stringify(evento);
  for (const ws of canal) {
    if (ws.readyState === ws.OPEN) {
      try { ws.send(datos); } catch { /* la próxima marca lo reintenta */ }
    }
  }
}
