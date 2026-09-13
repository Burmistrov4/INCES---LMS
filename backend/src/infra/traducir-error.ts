import { ErrorApi } from '../dominio/errores.js';

/**
 * Traduce los códigos de PostgreSQL/PostgREST a errores de la API.
 *
 * Sin esto, un `insufficient_privilege` de RLS llegaría al usuario como un 500
 * "algo salió mal" y nadie sabría si el problema es de permisos o del servidor.
 * Los códigos son los mismos que ya traduce el cliente Flutter en
 * `AppException.from`, así que ambos extremos hablan el mismo idioma.
 */

interface ErrorPostgres {
  code?: string | null;
  message?: string | null;
  details?: string | null;
  hint?: string | null;
}

/** `true` si el objeto parece un error de PostgREST **con código real**. */
export function pareceErrorPostgres(valor: unknown): valor is ErrorPostgres {
  if (typeof valor !== 'object' || valor === null) return false;
  const codigo = (valor as { code?: unknown }).code;
  // El código tiene que ser NO vacío. Supabase envuelve los fallos de red en un
  // objeto con `code: ''`, y tratar eso como error de Postgres haría que un
  // «no puedo alcanzar la base de datos» se reportara como 500 en vez de 503.
  return typeof codigo === 'string' && codigo.length > 0;
}

/** Patrones que delatan un fallo de transporte, no de la base de datos. */
const PATRONES_DE_RED = [
  'fetch failed',
  'network',
  'econnrefused',
  'econnreset',
  'enotfound',
  'etimedout',
  'socket hang up',
  'und_err',
];

/** Extrae el mensaje de un error, sea `Error` o un objeto suelto. */
export function mensajeDe(error: unknown): string {
  if (typeof error === 'object' && error !== null && 'message' in error) {
    const mensaje = (error as { message?: unknown }).message;
    if (typeof mensaje === 'string') return mensaje;
  }
  return error instanceof Error ? error.message : String(error);
}

/** `true` si el texto delata un fallo de transporte. */
export function pareceMensajeDeRed(mensaje: string): boolean {
  const texto = mensaje.toLowerCase();
  return PATRONES_DE_RED.some((patron) => texto.includes(patron));
}

/** `true` si parece un fallo de red (no llegó a responder Supabase). */
export function pareceErrorDeRed(valor: unknown): boolean {
  return pareceMensajeDeRed(mensajeDe(valor));
}

/**
 * `true` si PostgREST respondió **416 Range Not Satisfiable**.
 *
 * Pasa cuando se pide un `range()` que empieza más allá de la última fila. No es
 * un fallo: es el final de la lista. PostgREST no le pone `code`, así que
 * `pareceErrorPostgres` lo deja pasar y acabaría siendo un `500`, que es
 * justo lo contrario de lo que significa.
 *
 * Lo reconoce el repositorio que hizo la consulta paginada, no el traductor
 * genérico: sólo quien pidió una página sabe que una página de más es legítima.
 * Traducirlo a `400` en el traductor sería peor que no hacer nada: convertiría
 * una petición bien formada en un error del cliente.
 */
export function esRangoNoSatisfacible(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const conEstado = error as { status?: unknown; code?: unknown; message?: unknown };
  if (conEstado.status === 416) return true;
  // El cliente no siempre copia el estado HTTP: cuando no está, el mensaje es
  // el único rastro que queda («Requested range not satisfiable»).
  return (
    typeof conEstado.message === 'string' &&
    conEstado.message.toLowerCase().includes('range not satisfiable')
  );
}

/**
 * Convierte cualquier fallo en un [ErrorApi].
 *
 * `contexto` describe la operación ("leer módulos", "actualizar parámetro") y se
 * incluye en los detalles para poder diagnosticar sin exponer nada sensible.
 */
export function traducirError(error: unknown, contexto: string): ErrorApi {
  if (error instanceof ErrorApi) return error;

  // El orden importa: primero el transporte. Supabase envuelve un fallo de red
  // en un objeto con forma de error de PostgREST, así que si se comprobara
  // después, nunca se detectaría.
  if (pareceErrorDeRed(error)) {
    return new ErrorApi(
      503,
      'SUPABASE_INALCANZABLE',
      'No pudimos comunicarnos con la base de datos. Inténtalo de nuevo.',
      { contexto, tecnico: mensajeDe(error) },
    );
  }

  if (pareceErrorPostgres(error)) {
    const codigo = error.code ?? '';
    const tecnico = error.message ?? '';

    switch (codigo) {
      case '23505':
        return new ErrorApi(409, 'REGISTRO_DUPLICADO', 'Ese registro ya existe.', {
          contexto,
          tecnico,
        });

      case '23514':
        return new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          'Los datos no cumplen una regla del sistema.',
          { contexto, tecnico },
        );

      case '23503':
        return new ErrorApi(
          400,
          'REFERENCIA_INVALIDA',
          'Se hace referencia a un registro que no existe.',
          { contexto, tecnico },
        );

      case '42501':
        return new ErrorApi(
          403,
          'PERMISO_DENEGADO',
          'No tienes permisos para realizar esta acción.',
          { contexto, tecnico },
        );

      case '42P01':
        return new ErrorApi(
          500,
          'ESQUEMA_DESACTUALIZADO',
          'Falta aplicar una migración en la base de datos.',
          { contexto, tecnico },
        );

      // PostgREST: .single() no encontró filas (o encontró más de una).
      case 'PGRST116':
        return new ErrorApi(404, 'NO_ENCONTRADO', 'El recurso solicitado no existe.', {
          contexto,
        });

      // PostgREST: JWT ausente, vencido o inválido.
      case 'PGRST301':
      case 'PGRST302':
        return ErrorApi.noAutorizado('Tu sesión venció. Vuelve a iniciar sesión.');

      default:
        return new ErrorApi(500, 'ERROR_BASE_DE_DATOS', 'Ocurrió un error al acceder a los datos.', {
          contexto,
          codigoPg: codigo,
          tecnico,
        });
    }
  }

  return new ErrorApi(500, 'ERROR_INTERNO', 'Ocurrió un error inesperado.', {
    contexto,
    tecnico: mensajeDe(error),
  });
}

/**
 * Desempaqueta `{ data, error }` de Supabase.
 *
 * Existe para que ningún repositorio pueda ignorar `error` por descuido: la
 * única forma de obtener el dato es pasar por aquí, y aquí se lanza.
 */
export function desenvolver<T>(
  respuesta: { data: T | null; error: unknown },
  contexto: string,
): T {
  if (respuesta.error) throw traducirError(respuesta.error, contexto);
  if (respuesta.data === null) {
    throw new ErrorApi(404, 'NO_ENCONTRADO', 'El recurso solicitado no existe.', { contexto });
  }
  return respuesta.data;
}
