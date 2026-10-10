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
   * Demasiados intentos en poco tiempo.
   *
   * **429 y no 401 ni 404**, y la diferencia es de diagnóstico: un 401 dice «tu
   * credencial no sirve» y un 404 «eso no existe»; los dos invitan a seguir
   * probando. Un 429 dice «deja de probar», que es exactamente lo que hay que
   * comunicar a quien está haciendo fuerza bruta contra un código temporal. El
   * mensaje es genérico a propósito: no revela si el intento acertó.
   */
  static demasiadasPeticiones(
    mensaje = 'Demasiados intentos seguidos. Espera unos minutos e inténtalo de nuevo.',
  ) {
    return new ErrorApi(429, 'DEMASIADOS_INTENTOS', mensaje);
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

  /**
   * El dato está bien formado pero no es válido **en este momento**.
   *
   * **422 y no 400, y la diferencia importa para el usuario.** Un 400 dice «lo
   * que mandaste está roto»; un 422 dice «lo que mandaste es correcto, pero no
   * aplica ahora». El código rotativo del QR de asistencia (M7) es el caso que
   * obligó a separarlos: seis dígitos bien escritos que ya caducaron merecen
   * «vuelve a mirar la pizarra», no «tu petición está mal», que manda a nadie a
   * arreglar nada.
   *
   * `peticionInvalida` NO sirve para esto porque fija el código a
   * `PETICION_INVALIDA`; aquí el código es del dominio y el cliente decide con él.
   */
  static invalido(codigo: string, mensaje: string, detalles?: unknown) {
    return new ErrorApi(422, codigo, mensaje, detalles);
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
