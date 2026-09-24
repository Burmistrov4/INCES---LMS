import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { origenesCors, type Env } from './config/env.js';
import type { PuertaAlmacenamiento, Repositorios } from './dominio/puertos.js';
import type { DependenciasRutas } from './http/dependencias.js';
import { registrarAutenticacion } from './http/plugins/autenticacion.js';
import { registrarManejadorDeErrores } from './http/plugins/errores.js';
import { comprobarMantenimiento } from './http/plugins/modulos.js';
import { rutasAdmin } from './http/rutas/admin.js';
import { rutasArchivos } from './http/rutas/archivos.js';
import { rutasAula } from './http/rutas/aula.js';
import { rutasAuth } from './http/rutas/auth.js';
import { rutasCuadrante } from './http/rutas/cuadrante.js';
import { rutasCurriculo } from './http/rutas/curriculo.js';
import { rutasInscripciones } from './http/rutas/inscripciones.js';
import { rutasPlanilla } from './http/rutas/planilla.js';
import { rutasSalud } from './http/rutas/salud.js';
import { rutasSecciones } from './http/rutas/secciones.js';
import { rutasYo } from './http/rutas/yo.js';
import { CacheModulos, CacheParametros } from './infra/cache.js';
import type { EnvioCorreo } from './infra/correo.js';
import { crearAlmacenamiento } from './infra/r2_service.js';

export const VERSION_API = '0.1.0';

export interface DependenciasApp {
  /** Verifica un token de Supabase. Inyectable para poder testear sin red. */
  verificarToken: (token: string) => Promise<{ id: string; email: string | null } | null>;

  /**
   * Repositorios con la service_role key. Se usan sólo para alimentar las
   * cachés de módulos y parámetros, que son configuración del sistema y no
   * datos de nadie.
   */
  reposAdmin: Repositorios;

  /** Repositorios atados al token del llamante, para que RLS siga aplicando. */
  reposDePeticion: (token: string | null) => Repositorios;

  /** Enviador de correo transaccional (Resend) para invitaciones y avisos. */
  enviarCorreo: EnvioCorreo;

  /**
   * Almacenamiento pesado (Cloudflare R2).
   *
   * **Si se omite, se construye desde `env`** con `crearAlmacenamiento`, que
   * devuelve `null` cuando las cuatro variables de R2 no están definidas. Es el
   * camino de producción y el de cualquier despliegue que no use archivos.
   *
   * Se admite explícitamente para dos casos que el entorno no puede expresar:
   * inyectar un doble en los tests —firmar es puro, pero `HeadObject` y
   * `DeleteObject` saldrían a la red— y forzar `null` en un entorno que sí tiene
   * credenciales, para probar el 503 sin borrar variables.
   */
  almacenamiento?: PuertaAlmacenamiento | null;

  version?: string;
}

/**
 * Construye la aplicación.
 *
 * Recibe **todo** por parámetro: entorno y dependencias. No lee `process.env`,
 * no importa singletons y no abre conexiones. Por eso los tests pueden montar la
 * API completa en memoria y ejercitar rutas, guardias y traducción de errores
 * sin credenciales ni red.
 */
export function construirApp(env: Env, deps: DependenciasApp): FastifyInstance {
  const version = deps.version ?? VERSION_API;

  const app = Fastify({
    // En tests no se registra nada: además de ensuciar la salida, el logger
    // desactiva el registro de peticiones por sí solo, sin necesidad de la
    // opción `disableRequestLogging` (deprecada en Fastify 5 y eliminada en 6).
    logger: env.NODE_ENV === 'test' ? false : { level: env.LOG_LEVEL },
    trustProxy: true,
    // La API no sube archivos: eso va directo a R2 con URLs firmadas.
    bodyLimit: 1_048_576,
  });

  const caches = {
    modulos: new CacheModulos(deps.reposAdmin.modulos, env.MODULE_CACHE_TTL_MS),
    parametros: new CacheParametros(
      deps.reposAdmin.parametros,
      env.SETTINGS_CACHE_TTL_MS,
    ),
  };

  const depsRutas: DependenciasRutas = {
    version,
    caches,
    revisarBase: async () => {
      try {
        await deps.reposAdmin.modulos.todos();
        return true;
      } catch {
        return false;
      }
    },
    // La ruta de activación de invitaciones es pública y necesita saltarse RLS:
    // usa estos repositorios con service_role para leer por el hash del token y
    // crear el usuario. Jamás se exponen al cliente; sólo los usa el servidor.
    reposAdmin: deps.reposAdmin,
    enviarCorreo: deps.enviarCorreo,
    // El frente corre en 8090 (no 8080: lo ocupa XAMPP). Si el despliegue no
    // declara FRONTEND_URL, el enlace de activación debe apuntar ahí.
    urlFrente: env.FRONTEND_URL ?? 'http://localhost:8090',
    // `crearAlmacenamiento` devuelve `null` cuando R2 no está configurado, y
    // eso es una configuración válida: el módulo de archivos responde 503 y el
    // resto del backend funciona igual. Quien construye la app puede sustituirlo
    // —o forzar ese `null`— pasándolo en `deps`.
    almacenamiento:
      deps.almacenamiento === undefined
        ? crearAlmacenamiento(env)
        : deps.almacenamiento,
  };

  registrarManejadorDeErrores(app);

  // CORS, helmet y rate limit se registran primero para que envuelvan a todo.
  void app.register(cors, {
    origin: origenesCors(env),
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: false,
    maxAge: 86_400,
  });

  void app.register(helmet, {
    // La API no sirve HTML; la CSP se aplica en el frontend.
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  });

  void app.register(rateLimit, {
    max: env.RATE_LIMIT_MAX,
    timeWindow: env.RATE_LIMIT_WINDOW,
    // Los errores 5xx no cuentan: un fallo de la base de datos no debe consumir
    // la cuota del usuario y dejarlo bloqueado cuando el servicio se recupere.
    skipOnError: true,
  });

  // Resuelve `request.usuario` y `request.repos` antes que cualquier handler.
  registrarAutenticacion(app, {
    verificarToken: deps.verificarToken,
    reposDePeticion: deps.reposDePeticion,
  });

  // Modo mantenimiento, global.
  //
  // Va en `preValidation` y NO en `onRequest` a propósito: `onRequest` se
  // ejecuta ANTES del enrutado, así que una ruta inexistente dispararía una
  // consulta a la base de datos y devolvería un error de configuración en vez
  // del 404 que corresponde. `preValidation` corre después de resolver la ruta,
  // y los 404 se resuelven antes de llegar aquí.
  //
  // Las sondas de salud quedan exentas: el orquestador necesita poder preguntar
  // si el proceso sigue vivo precisamente cuando algo va mal.
  app.addHook('preValidation', async (request) => {
    if (request.method === 'OPTIONS') return;
    if (request.url.startsWith('/salud')) return;

    await comprobarMantenimiento(caches.parametros, request.usuario?.rol ?? null);
  });

  rutasSalud(app, depsRutas);
  rutasYo(app, depsRutas);
  rutasAdmin(app, depsRutas);
  rutasCurriculo(app);
  rutasCuadrante(app);
  // El catálogo de secciones antes que las inscripciones: M4 se inscribe *en* una
  // sección, así que sin poder crearlas el motor de cupos no tiene sobre qué
  // operar. Son módulos distintos por alcance (M3) y por consumo (M4).
  rutasSecciones(app);
  // El catálogo de la planilla va con las de M4, pero se registra aparte porque
  // su visibilidad es la contraria: es la única ruta PÚBLICA del módulo —el
  // formulario se pinta antes de que el aspirante tenga cuenta— mientras que
  // todas las de abajo exigen sesión. Ver `rutas/planilla.ts`.
  rutasPlanilla(app);
  rutasInscripciones(app);
  // M5 necesita el almacenamiento inyectado, así que recibe `depsRutas` — a
  // diferencia de M3 y M4, que no dependen de ningún servicio externo.
  rutasArchivos(app, depsRutas);
  // M6 reutiliza los archivos de M5 (las guías y las entregas cuelgan de sus
  // tablas) y necesita la caché de módulos para su propia guardia.
  rutasAula(app, depsRutas);
  rutasAuth(app, depsRutas);

  return app;
}
