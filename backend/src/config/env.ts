import { z } from 'zod';
import {
  TTL_DESCARGA_SEGUNDOS,
  TTL_SUBIDA_SEGUNDOS,
} from '../dominio/almacenamiento.js';

/**
 * Configuración del proceso, validada al arrancar.
 *
 * Se valida con Zod y se falla en el arranque, no en la primera petición: una
 * variable mal escrita debe impedir que el contenedor levante, no provocar un
 * 500 intermitente en producción cuando alguien abra la pantalla equivocada.
 */
/**
 * Variable opcional que trata la **cadena vacía como ausente**.
 *
 * Hace falta de verdad: `node --env-file`, Docker Compose y la mayoría de
 * gestores exportan `VACIA=` como cadena vacía, no como variable ausente. Con un
 * `.optional()` a secas, `min(1)` rechaza esa cadena vacía y el arranque falla
 * aunque el operador sólo haya dejado el hueco sin rellenar — que es justo lo que
 * dice la plantilla `.env.example`.
 *
 * La distinción importa: una variable **obligatoria** vacía debe fallar y
 * nombrarse; una **opcional** vacía significa «no configurado».
 */
const textoOpcional = z
  .string()
  .optional()
  .transform((valor) =>
    valor === undefined || valor.trim().length === 0 ? undefined : valor,
  );

const esquema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),

  PORT: z.coerce.number().int().positive().max(65535).default(3000),
  HOST: z.string().min(1).default('0.0.0.0'),

  SUPABASE_URL: z.string().url('SUPABASE_URL debe ser una URL válida.'),
  SUPABASE_ANON_KEY: z.string().min(20, 'SUPABASE_ANON_KEY parece incompleta.'),
  SUPABASE_SERVICE_ROLE_KEY: z
    .string()
    .min(20, 'SUPABASE_SERVICE_ROLE_KEY parece incompleta.'),

  /**
   * Orígenes permitidos por CORS, separados por coma. `*` = cualquiera.
   *
   * El valor por defecto es el del **frontend**, no el del propio backend: quien
   * llama a la API desde un navegador es el servidor de desarrollo de Flutter
   * (`flutter run --web-port=8090`), y es su origen —no el del backend— lo que
   * CORS debe autorizar. Poner aquí el puerto del backend no autoriza nada.
   *
   * Puerto elegido: **8090**, no 8080. El 8080 es el puerto alternativo de
   * Apache y lo ocupa XAMPP en cuanto arranca; el 3000 corre la misma suerte con
   * los servidores de desarrollo de Node. Ver la sección «Puertos» del README.
   */
  CORS_ORIGINS: z.string().default('http://localhost:8090'),

  /** TTL de la caché de módulos. `0` la desactiva (útil en tests). */
  MODULE_CACHE_TTL_MS: z.coerce.number().int().min(0).default(30_000),

  /** TTL de la caché de parámetros (modo mantenimiento, etc.). */
  SETTINGS_CACHE_TTL_MS: z.coerce.number().int().min(0).default(30_000),

  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(300),
  RATE_LIMIT_WINDOW: z.string().default('1 minute'),

  LOG_LEVEL: z
    .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
    .default('info'),

  /**
   * Cloudflare R2 (almacenamiento pesado, módulo M5).
   *
   * Las cuatro credenciales son opcionales **en conjunto**: sin ellas el backend
   * arranca y el módulo de archivos simplemente no está activo. Una
   * configuración *parcial* sí es un error — lo detecta `configuracionR2()`.
   */
  CLOUDFLARE_ACCOUNT_ID: textoOpcional,
  R2_ACCESS_KEY_ID: textoOpcional,
  R2_SECRET_ACCESS_KEY: textoOpcional,
  R2_BUCKET: textoOpcional,

  R2_PUT_TTL_SEGUNDOS: z.coerce
    .number()
    .int()
    .positive()
    .max(604_800)
    .default(TTL_SUBIDA_SEGUNDOS),
  R2_GET_TTL_SEGUNDOS: z.coerce
    .number()
    .int()
    .positive()
    .max(604_800)
    .default(TTL_DESCARGA_SEGUNDOS),

  /**
   * Resend (correo transaccional). La API key es opcional: sin ella el envío se
   * considera "no entregado" y el flujo sigue funcionando porque el enlace de
   * activación se devuelve en la respuesta de la invitación.
   */
  RESEND_API_KEY: textoOpcional,

  /** Remitente de Resend. Sin dominio verificado, Resend exige `onboarding@resend.dev`. */
  RESEND_FROM: textoOpcional,

  /**
   * Origen del frontend (Flutter web). Se usa para construir el enlace de
   * activación que se envía por correo y se devuelve en la respuesta.
   */
  FRONTEND_URL: textoOpcional,
});

export type Env = z.infer<typeof esquema>;

/** Formatea los problemas de Zod en un mensaje accionable. */
function describirProblemas(error: z.ZodError): string {
  return error.issues
    .map((p) => {
      const ruta = p.path.join('.') || '(raíz)';
      return `  · ${ruta}: ${p.message}`;
    })
    .join('\n');
}

/**
 * Lee y valida la configuración.
 *
 * Se expone como función (no como constante evaluada al importar) para que los
 * tests puedan construir un entorno propio sin tocar `process.env`.
 */
export function cargarEnv(origen: NodeJS.ProcessEnv = process.env): Env {
  const resultado = esquema.safeParse(origen);

  if (!resultado.success) {
    throw new Error(
      'Configuración inválida. Revisa el archivo .env:\n' +
        describirProblemas(resultado.error),
    );
  }

  return resultado.data;
}

/** Lista de orígenes CORS ya normalizada. */
export function origenesCors(env: Env): string[] | true {
  const bruto = env.CORS_ORIGINS.trim();
  if (bruto === '*' || bruto === '') return true;
  return bruto
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0);
}

/** Credenciales de R2 ya resueltas. */
export interface ConfigR2 {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
  ttlSubidaSegundos: number;
  ttlDescargaSegundos: number;
}

const CLAVES_R2 = [
  'CLOUDFLARE_ACCOUNT_ID',
  'R2_ACCESS_KEY_ID',
  'R2_SECRET_ACCESS_KEY',
  'R2_BUCKET',
] as const;

/**
 * Resuelve la configuración de R2, o `null` si el módulo no está activo.
 *
 * Sin ninguna variable devuelve `null` y el backend arranca: R2 es una capacidad
 * opcional, no un requisito de arranque. Pero con **algunas** variables puestas
 * lanza en vez de continuar. Una configuración a medias no es un modo degradado:
 * es un error de despliegue. Dejarla pasar produciría fallos de subida con
 * «Access Denied» que parecen un problema de permisos de R2 cuando en realidad
 * falta una variable.
 */
export function configuracionR2(env: Env): ConfigR2 | null {
  const presentes = CLAVES_R2.filter((clave) => {
    const valor = env[clave];
    return typeof valor === 'string' && valor.trim().length > 0;
  });

  if (presentes.length === 0) return null;

  if (presentes.length < CLAVES_R2.length) {
    const faltan = CLAVES_R2.filter((clave) => !presentes.includes(clave));
    throw new Error(
      'Configuración de R2 incompleta. Faltan: ' +
        `${faltan.join(', ')}. Define las cuatro o ninguna.`,
    );
  }

  return {
    accountId: env.CLOUDFLARE_ACCOUNT_ID as string,
    accessKeyId: env.R2_ACCESS_KEY_ID as string,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY as string,
    bucket: env.R2_BUCKET as string,
    ttlSubidaSegundos: env.R2_PUT_TTL_SEGUNDOS,
    ttlDescargaSegundos: env.R2_GET_TTL_SEGUNDOS,
  };
}
