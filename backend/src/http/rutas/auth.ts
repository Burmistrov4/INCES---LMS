import type { FastifyInstance } from 'fastify';
import { ErrorApi } from '../../dominio/errores.js';
import { estadoDeCodigoRecuperacion } from '../../dominio/reglas-recuperacion.js';
import { estadoDeInvitacion } from '../../dominio/reglas-invitaciones.js';
import type { DependenciasRutas } from '../dependencias.js';
import { esquemaActivarCuenta, esquemaCanjearCodigo } from '../esquemas.js';
import { crearLimitador } from '../limitador.js';
import { hashearToken, normalizarCodigo } from '../../infra/tokens.js';

/**
 * Rutas de autenticación públicas.
 *
 * Dos: la activación de la invitación de docente y el canje del código de
 * recuperación. Son las únicas rutas protegidas por un **secreto temporal** en
 * vez de por un JWT, porque quien las llama todavía no tiene sesión. Por eso
 * consultan la base con `reposAdmin` (service_role), que salta RLS, y por eso
 * llevan **límite de intentos**: son la puerta que un atacante golpearía.
 *
 * El limitador se crea **por instancia de app** y no a nivel de módulo: en las
 * pruebas se montan varias apps en el mismo proceso y un limitador compartido
 * haría que los casos se estorbaran entre sí, dando fallos que no son del código.
 */
export function rutasAuth(app: FastifyInstance, deps: DependenciasRutas): void {
  // 20 intentos por cuarto de hora y por IP. Un código de 59 bits no se rompe
  // por fuerza bruta ni con millones de intentos; el límite protege sobre todo
  // al servidor (y a GoTrue) de un bucle automatizado, y hace que el abuso deje
  // huella en forma de 429.
  const limitador = crearLimitador({ maximo: 20, ventanaMs: 15 * 60 * 1000 });

  app.register(
    async (aut) => {
      aut.post('/activar', async (request) => {
        if (!limitador.permitir(`activar:${request.ip}`)) {
          throw ErrorApi.demasiadasPeticiones();
        }

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

        if (estado === 'revocada') {
          await deps.reposAdmin.acceso.registrar({
            userId: invitacion.id,
            email: invitacion.email,
            ip,
            estado: 'FAILED',
          });
          throw ErrorApi.prohibido(
            'INVITACION_REVOCADA',
            'Esta invitación fue anulada por el administrador. Solicita una nueva.',
          );
        }

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

        // **Se reclama el token ANTES de crear la cuenta.** El estado se acaba
        // de leer, pero entre esa lectura y este `update` cabe otra petición: si
        // se creara el usuario primero, dos activaciones simultáneas del mismo
        // enlace podrían crear dos cuentas. Aquí sólo una gana la carrera en la
        // base, y la que pierde recibe el mismo 409 que si hubiera llegado tarde.
        const reclamada = await deps.reposAdmin.invitaciones.consumirSiValida(invitacion.id);

        if (!reclamada) {
          await deps.reposAdmin.acceso.registrar({
            userId: invitacion.id,
            email: invitacion.email,
            ip,
            estado: 'FAILED',
          });
          throw ErrorApi.conflicto('INVITACION_YA_USADA', 'Esta invitación ya fue utilizada.');
        }

        try {
          const idUsuario = await deps.reposAdmin.invitaciones.crearUsuarioDocente(
            invitacion.email,
            password,
            invitacion.nombres,
            invitacion.apellidos,
          );
          const perfil = await deps.reposAdmin.perfiles.cambiarRol(idUsuario, 'docente');
          await deps.reposAdmin.acceso.registrar({
            userId: idUsuario,
            email: invitacion.email,
            ip,
            estado: 'SUCCESS',
          });
          return { email: perfil.email, perfil };
        } catch (error) {
          // El token ya está reclamado y la cuenta no se creó (lo más común:
          // ese correo ya tiene cuenta). Se **libera** la invitación para que el
          // profesor pueda reintentar o el administrador revocarla a mano; sin
          // esto, un fallo transitorio dejaría el enlace quemado para siempre.
          await deps.reposAdmin.invitaciones.liberar(invitacion.id);
          await deps.reposAdmin.acceso.registrar({
            userId: null,
            email: invitacion.email,
            ip,
            estado: 'FAILED',
          });
          throw error;
        }
      });

      /**
       * Canje del código de recuperación.
       *
       * Recorrido: el administrador verifica la identidad por el procedimiento
       * institucional, emite el código y lo entrega en mano o por canal interno;
       * el titular lo trae aquí junto con la contraseña NUEVA que quiere.
       *
       * El código **solo** identifica el restablecimiento: no hace falta el
       * correo, así que no hay nada que enumerar. Un código que no existe, uno
       * caducado y uno ya canjeado responden **lo mismo** —no se distingue el
       * motivo—, que es lo que pide la protección contra enumeración.
       */
      aut.post('/restablecer-codigo', async (request) => {
        if (!limitador.permitir(`recuperar:${request.ip}`)) {
          throw ErrorApi.demasiadasPeticiones();
        }

        const { codigo, password } = esquemaCanjearCodigo.parse(request.body);
        const ip = request.ip;
        const hash = hashearToken(normalizarCodigo(codigo));

        const registro = await deps.reposAdmin.recuperacion.porCodeHash(hash);

        if (!registro) {
          await deps.reposAdmin.acceso.registrar({ userId: null, email: null, ip, estado: 'FAILED' });
          throw ErrorApi.noEncontrado(
            'CODIGO_INVALIDO',
            'El código no es válido o ya caducó. Solicita uno nuevo.',
          );
        }

        const estado = estadoDeCodigoRecuperacion(registro);

        if (estado !== 'valido') {
          await deps.reposAdmin.acceso.registrar({
            userId: registro.userId,
            email: null,
            ip,
            estado: 'FAILED',
          });
          // **Mismo mensaje para los tres motivos** (usado, revocado, caducado):
          // decir «ya se usó» le confirmaría a quien prueba códigos ajenos que
          // acertó uno. El titular legítimo, que tiene el código en la mano,
          // entiende igual el mensaje y pide otro.
          throw ErrorApi.noEncontrado(
            'CODIGO_INVALIDO',
            'El código no es válido o ya caducó. Solicita uno nuevo.',
          );
        }

        // Mismo patrón que la invitación: reclamar antes de tocar la cuenta.
        const reclamado = await deps.reposAdmin.recuperacion.consumirSiValido(registro.id);

        if (!reclamado) {
          await deps.reposAdmin.acceso.registrar({
            userId: registro.userId,
            email: null,
            ip,
            estado: 'FAILED',
          });
          throw ErrorApi.noEncontrado(
            'CODIGO_INVALIDO',
            'El código no es válido o ya caducó. Solicita uno nuevo.',
          );
        }

        try {
          await deps.reposAdmin.recuperacion.cambiarPassword(registro.userId, password);

          // Cambiar la contraseña NO invalida por sí solo los refresh tokens ya
          // emitidos: sin esto, una sesión robada seguiría abierta después del
          // restablecimiento, que es justo lo contrario de lo que se busca.
          await deps.reposAdmin.recuperacion.revocarSesiones(registro.userId);

          const perfil = await deps.reposAdmin.perfiles.porId(registro.userId);
          await deps.reposAdmin.acceso.registrar({
            userId: registro.userId,
            email: perfil?.email ?? null,
            ip,
            estado: 'SUCCESS',
          });

          // El limitador se limpia tras un canje válido: quien acertó no debe
          // arrastrar el contador de sus intentos fallidos previos.
          limitador.olvidar(`recuperar:${ip}`);

          return { email: perfil?.email ?? null };
        } catch (error) {
          // El código vuelve a su estado anterior: si GoTrue falló, el titular
          // no debe quedarse sin el código que le entregaron en mano.
          await deps.reposAdmin.recuperacion.liberar(registro.id);
          await deps.reposAdmin.acceso.registrar({
            userId: registro.userId,
            email: null,
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
