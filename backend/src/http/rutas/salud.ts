import type { FastifyInstance } from 'fastify';
import type { DependenciasRutas } from '../dependencias.js';
import { construirDocumentoOpenApi } from '../openapi.js';

/**
 * Sondas de salud.
 *
 * Dos niveles, a propósito:
 *  · `/salud` — liveness. No toca la base de datos. Si esto falla, el proceso
 *    está muerto y el orquestador debe reiniciarlo.
 *  · `/salud/profundo` — readiness. Comprueba la base de datos. Si esto falla,
 *    el proceso está vivo pero no debe recibir tráfico.
 *
 * Confundir ambas cosas provoca reinicios en bucle cuando el problema está en la
 * base de datos, no en la aplicación.
 */
export function rutasSalud(app: FastifyInstance, deps: DependenciasRutas): void {
  // Las sondas no cuentan para el límite de peticiones: un orquestador que
  // sondea cada 5 segundos agotaría la cuota y provocaría un falso positivo.
  const sinLimite = { config: { rateLimit: false } };

  app.get('/salud', sinLimite, async () => ({
    estado: 'ok',
    version: deps.version,
    hora: new Date().toISOString(),
  }));

  app.get('/salud/profundo', sinLimite, async (_request, reply) => {
    const baseOk = await deps.revisarBase();

    return reply.status(baseOk ? 200 : 503).send({
      estado: baseOk ? 'ok' : 'degradado',
      baseDeDatos: baseOk ? 'ok' : 'inalcanzable',
      version: deps.version,
      hora: new Date().toISOString(),
    });
  });

  /**
   * Documento OpenAPI 3.1, generado en cada petición a partir de los esquemas
   * Zod (deuda D6).
   *
   * Se genera al vuelo y no se sirve un archivo compilado a propósito: así es
   * imposible que lo servido y lo que valida la API se separen. El coste es
   * despreciable (no hay ida a la base de datos ni lectura de disco) y va
   * marcado `sinLimite` para no gastar cuota, igual que las sondas.
   *
   * Es público: no revela nada que no revele ya el propio contrato de la API, y
   * los generadores de cliente necesitan alcanzarlo sin credenciales.
   */
  app.get('/openapi.json', sinLimite, async () => construirDocumentoOpenApi());
}
