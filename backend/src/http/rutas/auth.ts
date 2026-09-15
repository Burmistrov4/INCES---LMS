import type { FastifyInstance } from 'fastify';
import { ErrorApi } from '../../dominio/errores.js';
import { estadoDeInvitacion } from '../../dominio/reglas-invitaciones.js';
import type { DependenciasRutas } from '../dependencias.js';
import { esquemaActivarCuenta } from '../esquemas.js';
import { hashearToken } from '../../infra/tokens.js';

/**
 * Rutas de autenticación públicas.
 *
 * Sólo una por ahora: la activación de la invitación de docente. Es la única
 * ruta protegida por el token de invitación en vez de por un JWT, porque el
 * profesor aún no tiene sesión cuando abre el enlace. Por eso consulta la base
 * con `reposAdmin` (service_role), que salta RLS.
 */
export function rutasAuth(app: FastifyInstance, deps: DependenciasRutas): void {
  app.register(
    async (aut) => {
      aut.post('/activar', async (request) => {
        const { token, password } = esquemaActivarCuenta.parse(request.body);

        const ip = request.ip;
        const hash = hashearToken(token);

        const invitacion = await deps.reposAdmin.invitaciones.porTokenHash(hash);

        if (!invitacion) {
          await deps.reposAdmin.acceso.registrar({
            userId: null,
            email: null,
            ip,
            estado: 'FAILED',
          });
          // Respuesta genérica: no revela si el correo existe o si el token es
          // real. Un atacante no distingue "token malo" de "token inexistente".
          throw ErrorApi.noEncontrado(
            'INVITACION_INVALIDA',
            'El enlace de invitación no es válido.',
          );
        }

        const estado = estadoDeInvitacion(invitacion);

        if (estado === 'usada') {
          await deps.reposAdmin.acceso.registrar({
            userId: invitacion.id,
            email: invitacion.email,
            ip,
            estado: 'FAILED',
          });
          throw ErrorApi.conflicto('INVITACION_YA_USADA', 'Esta invitación ya fue utilizada.');
        }

        if (estado === 'expirada') {
          await deps.reposAdmin.acceso.registrar({
            userId: invitacion.id,
            email: invitacion.email,
            ip,
            estado: 'FAILED',
          });
          throw ErrorApi.caducado(
            'La invitación caducó. Solicite una nueva al administrador.',
          );
        }

        // Token válido: creamos el usuario ya confirmado y lo promovemos a docente.
        try {
          const idUsuario = await deps.reposAdmin.invitaciones.crearUsuarioDocente(
            invitacion.email,
            password,
            invitacion.nombres,
            invitacion.apellidos,
          );
          const perfil = await deps.reposAdmin.perfiles.cambiarRol(idUsuario, 'docente');
          await deps.reposAdmin.invitaciones.marcarUsada(invitacion.id);
          await deps.reposAdmin.acceso.registrar({
            userId: idUsuario,
            email: invitacion.email,
            ip,
            estado: 'SUCCESS',
          });
          return { email: perfil.email, perfil };
        } catch (error) {
          // La creación puede fallar (p.ej. correo ya registrado). Registramos el
          // intento fallido; el error ya viene como `ErrorApi` y se propaga.
          await deps.reposAdmin.acceso.registrar({
            userId: null,
            email: invitacion.email,
            ip,
            estado: 'FAILED',
          });
          throw error;
        }
      });
    },
    { prefix: '/api/v1/auth' },
  );
}
