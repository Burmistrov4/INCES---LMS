/**
 * Error de negocio con código estable y estado HTTP.
 *
 * Regla del proyecto: ningún fallo se convierte en `null` ni en una lista
 * vacía. O hay dato, o hay error explícito con código. Es la misma decisión que
 * se tomó en Flutter con `Result` + `AppException` (deuda D1), trasladada al
 * backend para que el cliente reciba siempre un cuerpo de error interpretable.
 */
export class ErrorApi extends Error {
  readonly estado: number;
  readonly codigo: string;
  readonly detalles: unknown;

  constructor(
    estado: number,
    codigo: string,
    mensaje: string,
    detalles?: unknown,
  ) {
    super(mensaje);
    this.name = 'ErrorApi';
    this.estado = estado;
    this.codigo = codigo;
    this.detalles = detalles;
  }

  static noAutorizado(mensaje = 'Necesitas iniciar sesión para continuar.') {
    return new ErrorApi(401, 'NO_AUTENTICADO', mensaje);
  }

  static prohibido(codigo: string, mensaje: string, detalles?: unknown) {
    return new ErrorApi(403, codigo, mensaje, detalles);
  }

  static noEncontrado(codigo: string, mensaje: string) {
    return new ErrorApi(404, codigo, mensaje);
  }

  static caducado(mensaje = 'El recurso solicitado ha caducado.') {
    return new ErrorApi(410, 'RECURSO_CADUCADO', mensaje);
  }

  /**
   * El archivo pesa más de lo permitido.
   *
   * **413 y no 400**, y la distinción es la razón de que esta fábrica exista: la
   * petición es correcta y el problema es el **tamaño** del contenido. El 400
   * queda para el tamaño *corrupto* —negativo, `NaN`, infinito—, que es un dato
   * mal formado y no un archivo grande. Antes de esto, `validarTamano` devolvía
   * 400 para las dos cosas y el cliente no podía distinguir «vuelve a subir algo
   * más pequeño» de «el dato que mandaste está roto».
   */
  static demasiadoGrande(mensaje: string, detalles?: unknown) {
    return new ErrorApi(413, 'ARCHIVO_DEMASIADO_GRANDE', mensaje, detalles);
  }

  static conflicto(codigo: string, mensaje: string, detalles?: unknown) {
    return new ErrorApi(409, codigo, mensaje, detalles);
  }

  static peticionInvalida(mensaje: string, detalles?: unknown) {
    return new ErrorApi(400, 'PETICION_INVALIDA', mensaje, detalles);
  }

  static interno(mensaje = 'Ocurrió un error inesperado.') {
    return new ErrorApi(500, 'ERROR_INTERNO', mensaje);
  }

  static servicioNoDisponible(mensaje = 'El servicio no está disponible.') {
    return new ErrorApi(503, 'SERVICIO_NO_DISPONIBLE', mensaje);
  }
}

/** Cuerpo de error uniforme. El cliente sólo necesita leer `error.codigo`. */
export interface CuerpoError {
  error: {
    codigo: string;
    mensaje: string;
    detalles?: unknown;
  };
}

export function cuerpoDeError(error: ErrorApi): CuerpoError {
  return {
    error: {
      codigo: error.codigo,
      mensaje: error.message,
      ...(error.detalles === undefined ? {} : { detalles: error.detalles }),
    },
  };
}
