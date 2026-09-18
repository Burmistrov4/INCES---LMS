/**
 * Reglas de almacenamiento pesado (Cloudflare R2), sin dependencia del SDK.
 *
 * Todo lo de este archivo es puro: se prueba sin red, sin credenciales y sin
 * contenedor. Es deliberado. La decisión de seguridad más importante del módulo
 * de archivos —**quién elige la clave del objeto**— se verifica con funciones
 * puras, no arrancando infraestructura.
 *
 * Contexto: una URL prefirmada de subida es una autorización de escritura. Si la
 * clave la propone el cliente, esa autorización alcanza a *cualquier* objeto del
 * bucket: se podría sobrescribir el archivo de otro usuario, o un recurso del
 * sistema, simplemente pidiendo una URL para `../../lo-que-sea`. Por eso la clave
 * se construye **siempre** aquí, en el servidor, y el nombre original sólo se usa
 * para extraer la extensión.
 */
import { randomUUID } from 'node:crypto';
import { ErrorApi } from './errores.js';

/**
 * Extensiones admitidas, con su tipo MIME canónico.
 *
 * El tipo MIME **no** se toma del cliente: se deriva de la extensión. Si se
 * aceptara el que manda el navegador, bastaría con declarar `image/png` al subir
 * un ejecutable para que el objeto quedara servido con un tipo engañoso.
 */
export const TIPOS_PERMITIDOS: Readonly<Record<string, string>> = Object.freeze({
  '.pdf': 'application/pdf',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.docx':
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xlsx':
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.pptx':
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
});

/**
 * 10 MB — **valor por defecto**, no una constante intocable.
 *
 * El límite efectivo puede venir de `system_settings.m5_max_bytes`, que el
 * administrador cambia desde el panel sin desplegar código. Por eso este valor
 * sólo se usa cuando no hay parámetro: la comprobación de tamaño recibe el
 * límite por argumento (`validarTamano`), nunca lo lee de aquí a escondidas.
 *
 * 10 MB es lo que el centro declaró razonable: por encima, la subida pesa más
 * de lo que aporta y el navegador del INCES sufre.
 */
export const TAMANO_MAXIMO_BYTES = 10 * 1024 * 1024;

/** Caducidades por defecto, en segundos. */
export const TTL_SUBIDA_SEGUNDOS = 300; // 5 minutos: subir, no pasear.
export const TTL_DESCARGA_SEGUNDOS = 900; // 15 minutos: leer una vez.

/** Tamaño en MB con un decimal, para un mensaje que se entienda. */
function aMegabytes(bytes: number): string {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Comprueba que un archivo no excede el tamaño máximo permitido.
 *
 * El límite entra por **parámetro** y no se lee aquí dentro, por una razón de
 * producto cerrada con el dueño del sistema: el administrador puede cambiar el
 * tamaño máximo desde el panel (`system_settings.m5_max_bytes`) sin desplegar
 * código. Si esta función leyera la base o usara `TAMANO_MAXIMO_BYTES` a
 * escondidas, el cambio del administrador no surtiría efecto hasta un
 * despliegue, y el dominio —que debe ser puro— quedaría acoplado al almacén de
 * parámetros.
 *
 * Se llama **después** de subir el objeto: una URL PUT prefirmada no admite
 * `content-length-range`, así que el tamaño real sólo se conoce con un
 * `HeadObject` posterior. `tamanoBytes` es ese dato, ya medido.
 */
export function validarTamano(tamanoBytes: number, maximoBytes: number): void {
  // Un tamaño negativo o no finito (NaN, ±Infinity) es un dato corrupto, no un
  // archivo grande: se rechaza como petición inválida en vez de compararlo.
  if (!Number.isFinite(tamanoBytes) || tamanoBytes < 0) {
    throw ErrorApi.peticionInvalida(
      'El tamaño del archivo no es un número válido.',
      { tamanoBytes },
    );
  }

  // Un límite NaN haría que `tamanoBytes > maximoBytes` fuera SIEMPRE falso
  // —toda comparación con NaN lo es— y dejaría pasar cualquier archivo. Es el
  // agujero que este guard cierra. Un límite negativo tampoco es un valor
  // configurable válido.
  if (Number.isNaN(maximoBytes) || maximoBytes < 0) {
    throw ErrorApi.peticionInvalida(
      'El límite de tamaño configurado no es válido.',
      { maximoBytes },
    );
  }

  if (tamanoBytes > maximoBytes) {
    throw ErrorApi.peticionInvalida(
      `El archivo pesa ${aMegabytes(tamanoBytes)} y el máximo permitido es ${aMegabytes(maximoBytes)}.`,
      { tamanoBytes, maximoBytes },
    );
  }
}

export interface PeticionUrlSubida {
  /** Carpeta lógica. La compone el servidor; nunca llega del cliente. */
  prefijo: string;
  /** Nombre que eligió el usuario. Sólo se usa para la extensión. */
  nombreOriginal: string;
}

export interface UrlFirmada {
  clave: string;
  url: string;
  expiraEnSegundos: number;
  tipoContenido: string;
}

/** Caracteres admitidos en un prefijo: sin `..`, sin barras iniciales, sin `%`. */
const PATRON_PREFIJO = /^[a-z0-9][a-z0-9/_-]*$/;

/**
 * Valida y normaliza la carpeta destino.
 *
 * Se rechaza `..` de forma explícita además del patrón: si algún día alguien
 * relaja el patrón para admitir puntos (por ejemplo en un nombre de curso), el
 * recorrido de rutas seguiría bloqueado por su propia comprobación.
 */
export function normalizarPrefijo(prefijo: string): string {
  const limpio = prefijo.trim().toLowerCase().replace(/^\/+|\/+$/g, '');

  if (limpio.length === 0) {
    throw ErrorApi.peticionInvalida(
      'El prefijo de almacenamiento no puede estar vacío.',
    );
  }
  if (limpio.includes('..')) {
    throw ErrorApi.peticionInvalida(
      'El prefijo de almacenamiento no puede contener «..».',
    );
  }
  if (!PATRON_PREFIJO.test(limpio)) {
    throw ErrorApi.peticionInvalida(
      `Prefijo de almacenamiento inválido: «${prefijo}».`,
    );
  }

  return limpio;
}

/** Extrae la extensión validada de un nombre de archivo. */
export function extensionDe(nombreOriginal: string): string {
  const punto = nombreOriginal.lastIndexOf('.');

  if (punto < 0) {
    throw ErrorApi.peticionInvalida(
      `El archivo «${nombreOriginal}» no tiene extensión.`,
    );
  }

  const extension = nombreOriginal.slice(punto).toLowerCase();

  if (!Object.hasOwn(TIPOS_PERMITIDOS, extension)) {
    throw ErrorApi.peticionInvalida(
      `Extensión no permitida: «${extension}».`,
      { admitidas: Object.keys(TIPOS_PERMITIDOS) },
    );
  }

  return extension;
}

/**
 * Construye la clave definitiva del objeto.
 *
 * El nombre base es un UUID, no el nombre original: dos personas subiendo
 * `informe.pdf` no pueden pisarse, y el nombre que eligió el usuario no puede
 * usarse para inyectar rutas. El nombre «bonito» se conserva sólo en la base de
 * datos y se aplica al descargar mediante `Content-Disposition`.
 *
 * `generarId` se inyecta para que los tests sean deterministas.
 */
export function construirClave(
  prefijo: string,
  nombreOriginal: string,
  generarId: () => string = randomUUID,
): string {
  return `${normalizarPrefijo(prefijo)}/${generarId()}${extensionDe(nombreOriginal)}`;
}

/**
 * Prefijo canónico de un archivo del módulo M5.
 *
 * Incluye al propietario para que nadie colisione con nadie y para poder borrar
 * por usuario con una regla de ciclo de vida. El año y el mes evitan que una
 * sola «carpeta» acumule cientos de miles de objetos y vuelva lento el listado.
 */
export function prefijoDeArchivo(
  propietarioId: string,
  fecha: Date = new Date(),
): string {
  // El id viene de `auth.users`, pero se sanea igual: un prefijo se construye
  // con datos de confianza, no con datos que *parecen* de confianza.
  const propietario = propietarioId
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, '');

  if (propietario.length === 0) {
    throw ErrorApi.peticionInvalida(
      'El identificador del propietario no es válido.',
    );
  }

  const anio = fecha.getUTCFullYear();
  const mes = String(fecha.getUTCMonth() + 1).padStart(2, '0');

  return `m5_archivos/${propietario}/${anio}/${mes}`;
}

/** Tipo MIME canónico de una extensión ya validada. */
export function tipoContenidoDe(extension: string): string {
  const tipo = TIPOS_PERMITIDOS[extension];

  if (tipo === undefined) {
    throw ErrorApi.peticionInvalida(
      `Extensión no permitida: «${extension}».`,
    );
  }

  return tipo;
}

/** Caracteres admitidos en una clave completa: ya incluye el punto de la extensión. */
const PATRON_CLAVE = /^[a-z0-9][a-z0-9/_.-]*$/;

/**
 * Valida una clave que ya existe (viene de la base de datos).
 *
 * Aunque el origen sea de confianza, se valida igual. Una clave guardada por una
 * versión anterior del código, o manipulada a mano en la base de datos, no debe
 * poder convertirse en una lectura arbitraria del bucket.
 */
export function validarClave(clave: string): string {
  const limpia = clave.trim().toLowerCase();

  if (limpia.length === 0) {
    throw ErrorApi.peticionInvalida('La clave del objeto no puede estar vacía.');
  }
  if (limpia.startsWith('/')) {
    throw ErrorApi.peticionInvalida('La clave del objeto no puede ser absoluta.');
  }
  if (limpia.includes('..')) {
    throw ErrorApi.peticionInvalida(
      'La clave del objeto no puede contener «..».',
    );
  }
  if (!PATRON_CLAVE.test(limpia)) {
    throw ErrorApi.peticionInvalida(`Clave de objeto inválida: «${clave}».`);
  }

  return limpia;
}

/**
 * Construye el valor de `Content-Disposition` para una descarga.
 *
 * Se emiten las dos formas a propósito. `filename=` es la que entienden todos
 * los navegadores, pero sólo admite ASCII: con ella, «Constancia de Trabajo
 * José.pdf» llegaría como «Constancia de Trabajo Jos_.pdf». `filename*=UTF-8''…`
 * (RFC 5987) es la que conserva los acentos, y los navegadores actuales la
 * prefieren cuando está presente.
 *
 * Las comillas y los saltos de línea se eliminan siempre: un nombre de archivo
 * es entrada del usuario y no puede cerrar la cabecera e inyectar otra.
 */
export function cabeceraDisposicion(nombreDescarga: string): string {
  const sinControl = nombreDescarga
    .replace(/[\r\n]/g, '')
    .replace(/["\\]/g, '')
    .trim();

  const nombre = sinControl.length > 0 ? sinControl : 'archivo';

  // Los caracteres fuera de ASCII se sustituyen por «_» en la forma simple.
  const ascii = nombre.replace(/[^\x20-\x7e]/g, '_');
  const codificado = encodeURIComponent(nombre);

  return `attachment; filename="${ascii}"; filename*=UTF-8''${codificado}`;
}
