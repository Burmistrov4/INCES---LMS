import { z } from 'zod';
import { ErrorApi } from '../dominio/errores.js';

/**
 * Esquemas de validación de entrada.
 *
 * Todo lo que llega del cliente pasa por Zod antes de tocar la base de datos.
 * `.strict()` rechaza campos desconocidos a propósito: si alguien intenta colar
 * `{"habilitado": true, "es_critico": false}`, se entera de que `es_critico` no
 * existe, en vez de que se ignore en silencio.
 */

/**
 * Los roles se escriben literales (no derivados de `ROLES`) para que Zod
 * conserve la unión exacta y `z.infer` dé `'admin' | 'docente' | 'estudiante'`.
 * El test comprueba que esta lista y `ROLES` siguen coincidiendo.
 */
export const rolSchema = z.enum(['admin', 'docente', 'estudiante']);

/** Valores JSON admitidos en `system_settings.valor`. */
const valorJsonSchema = z.union([
  z.string(),
  z.number(),
  z.boolean(),
  z.null(),
  z.array(z.unknown()),
  z.record(z.unknown()),
]);

export const esquemaCambiosModulo = z
  .object({
    habilitado: z.boolean().optional(),
    orden: z.number().int().min(0).max(9999).optional(),
    rolesPermitidos: z.array(rolSchema).max(3).optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio (habilitado, orden o rolesPermitidos).',
  });

export const esquemaValorParametro = z
  .object({
    valor: valorJsonSchema,
  })
  .strict();

export const esquemaCambioRol = z
  .object({
    rol: rolSchema,
  })
  .strict();

/**
 * Un identificador de perfil que viene por la URL.
 *
 * Existe porque sin esto un valor como `/usuarios/me/rol` viaja tal cual hasta
 * Postgres, que responde `22P02 invalid input syntax for type uuid: "me"`. Ese
 * error se traducía a un `500 ERROR_BASE_DE_DATOS` genérico: un `500` para lo
 * que en realidad es una URL mal escrita. Validar aquí convierte el problema en
 * un `400` que nombra el parámetro, y evita un viaje a la base de datos para
 * tirar la petición.
 *
 * No se acepta el atajo `/usuarios/me/...`: el `id` del llamante ya viaja en
 * `request.usuario.id`, así que el atajo sólo añadiría una forma más de
 * equivocarse. Si algún día hace falta, se resolverá antes de llegar aquí.
 */
export const esquemaIdPerfil = z.string().uuid({
  message: 'El identificador de usuario debe ser un UUID válido.',
});

export const esquemaListadoAuditoria = z.object({
  limite: z.coerce.number().int().min(1).max(200).default(50),
});

export type CambiosModuloEntrada = z.infer<typeof esquemaCambiosModulo>;
export type ValorParametroEntrada = z.infer<typeof esquemaValorParametro>;
export type CambioRolEntrada = z.infer<typeof esquemaCambioRol>;

/**
 * Comprueba que el valor encaje con el `tipo` declarado del parámetro.
 *
 * Sin esto, `max_faltas_consecutivas` podría quedar guardado como `"tres"` y el
 * módulo de asistencia empezaría a comportarse de forma impredecible mucho
 * después, lejos del sitio donde se cometió el error.
 */
export function validarValorSegunTipo(
  tipo: string,
  valor: unknown,
  clave: string,
): void {
  const espera = (esperado: string): never => {
    throw ErrorApi.peticionInvalida(
      `El parámetro "${clave}" espera un valor de tipo ${esperado}.`,
      { clave, tipo, valorRecibido: typeof valor },
    );
  };

  switch (tipo) {
    case 'number':
      if (typeof valor !== 'number' || !Number.isFinite(valor)) espera('number');
      return;
    case 'boolean':
      if (typeof valor !== 'boolean') espera('boolean');
      return;
    case 'string':
      if (typeof valor !== 'string') espera('string');
      return;
    case 'json':
      return;
    default:
      throw ErrorApi.peticionInvalida(
        `El parámetro "${clave}" declara un tipo desconocido: "${tipo}".`,
        { clave, tipo },
      );
  }
}
