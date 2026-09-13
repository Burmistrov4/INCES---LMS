import { construirApp, VERSION_API } from './app.js';
import { cargarEnv } from './config/env.js';
import { crearRepositorios, crearVerificadorDeTokens } from './infra/repos-supabase.js';
import { crearRemitenteResend } from './infra/correo.js';
import {
  crearClienteAdmin,
  crearClienteAnonimo,
  crearClienteDeUsuario,
} from './infra/supabase.js';

/**
 * Punto de entrada.
 *
 * Es el único archivo que lee `process.env` y abre conexiones. Todo lo demás
 * recibe sus dependencias por parámetro, y por eso es testeable.
 */
async function main(): Promise<void> {
  // Falla en el arranque si falta configuración: mejor un contenedor que no
  // levanta que un 500 intermitente en producción.
  const env = cargarEnv();

  const clienteAnonimo = crearClienteAnonimo(env);
  const reposAdmin = crearRepositorios(crearClienteAdmin(env));

  const enviarCorreo = crearRemitenteResend({
    apiKey: env.RESEND_API_KEY,
    from: env.RESEND_FROM ?? 'onboarding@resend.dev',
  });

  const app = construirApp(env, {
    verificarToken: crearVerificadorDeTokens(clienteAnonimo),
    reposAdmin,
    reposDePeticion: (token) => crearRepositorios(crearClienteDeUsuario(env, token)),
    enviarCorreo,
  });

  const cerrarOrdenadamente = async (senal: string): Promise<void> => {
    app.log.info(`Señal ${senal} recibida: cerrando sin cortar peticiones en vuelo.`);
    try {
      await app.close();
      process.exit(0);
    } catch (error) {
      app.log.error({ err: error }, 'error al cerrar');
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => void cerrarOrdenadamente('SIGTERM'));
  process.on('SIGINT', () => void cerrarOrdenadamente('SIGINT'));

  await app.listen({ port: env.PORT, host: env.HOST });

  app.log.info(
    `INCES LMS API v${VERSION_API} escuchando en ${env.HOST}:${env.PORT} ` +
      `(entorno: ${env.NODE_ENV})`,
  );
}

main().catch((error: unknown) => {
  const mensaje = error instanceof Error ? error.message : String(error);
  console.error('\nNo se pudo arrancar la API:\n');
  console.error(mensaje);
  console.error('');
  process.exit(1);
});
