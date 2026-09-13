import type { FastifyError, FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import { cuerpoDeError, ErrorApi } from '../../dominio/errores.js';
import { traducirError } from '../../infra/traducir-error.js';

/**
 * Manejador de errores único.
 *
 * Garantiza que **toda** respuesta de error tenga la misma forma:
 *   { error: { codigo, mensaje, detalles? } }
 *
 * El cliente nunca tiene que adivinar si el fallo viene como texto plano, como
 * `{message}` o como HTML. Es el equivalente backend de `AppException`: un solo
 * idioma para los errores.
 */
export function registrarManejadorDeErrores(app: FastifyInstance): void {
  app.setErrorHandler((error, request, reply) => {
    // 1. Errores de validación de Zod (cuerpo de la petición).
    if (error instanceof ZodError) {
      const api = ErrorApi.peticionInvalida(
        'Los datos enviados no son válidos.',
        error.issues.map((p) => ({
          campo: p.path.join('.') || '(raíz)',
          problema: p.message,
        })),
      );
      return reply.status(api.estado).send(cuerpoDeError(api));
    }

    // 2. Errores de negocio, ya tipados.
    if (error instanceof ErrorApi) {
      if (error.estado >= 500) {
        request.log.error({ err: error }, `fallo en ${request.url}`);
      }
      return reply.status(error.estado).send(cuerpoDeError(error));
    }

    // 3. Errores de validación de esquema de Fastify.
    //    Fastify tipa el error como `unknown` (se puede lanzar cualquier cosa),
    //    así que a partir de aquí se trata como un FastifyError parcial.
    const fallo = error as Partial<FastifyError>;

    if (fallo.validation) {
      const api = ErrorApi.peticionInvalida(
        'La petición no cumple el formato esperado.',
        { tecnico: fallo.message },
      );
      return reply.status(api.estado).send(cuerpoDeError(api));
    }

    // 4. Cuerpo JSON malformado.
    if (fallo.statusCode === 400 && fallo.code === 'FST_ERR_CTP_INVALID_MEDIA_TYPE') {
      const api = ErrorApi.peticionInvalida('El cuerpo debe ser JSON válido.');
      return reply.status(api.estado).send(cuerpoDeError(api));
    }

    // 5. Cualquier otra cosa: se registra completo y se responde genérico.
    //    El detalle técnico no sale al cliente en producción.
    request.log.error({ err: error }, 'error no controlado');

    const api =
      process.env.NODE_ENV === 'production'
        ? ErrorApi.interno()
        : traducirError(error, `manejo de ${request.method} ${request.url}`);

    return reply.status(api.estado).send(cuerpoDeError(api));
  });

  app.setNotFoundHandler((request, reply) => {
    const api = ErrorApi.noEncontrado(
      'RUTA_NO_ENCONTRADA',
      `No existe ${request.method} ${request.url}.`,
    );
    return reply.status(api.estado).send(cuerpoDeError(api));
  });
}
