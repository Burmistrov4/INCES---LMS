import '../../models/archivo.dart';

/// Contrato de la capa de datos del Módulo 5 (Archivos en Cloudflare R2).
///
/// **Por qué la orquestación de subida vive aquí y no en el repositorio.** El
/// repositorio de este proyecto es una envoltura fina sobre el gateway: convierte
/// excepciones en `Result` y no habla HTTP (ADR-010). Subir un archivo son tres
/// llamadas —firmar, `PUT` a R2, confirmar— y las tres son HTTP, así que su sitio
/// es el gateway. Ponerlas en el repositorio dejaría a éste haciendo red y sería
/// el único de los ocho que lo hace.
///
/// Las implementaciones **lanzan** [AppException]; el repositorio las envuelve.
abstract interface class ArchivosGateway {
  /// Paso 1. Reserva el archivo y devuelve la URL con la que subirlo.
  ///
  /// Deja una fila en `PENDING` **antes** de que el objeto exista: no hay
  /// transacción que abarque R2 y PostgreSQL, y una fila huérfana es visible y
  /// barrible, mientras que un objeto sin fila sería un archivo fantasma.
  ///
  /// El `Content-Type` **no se envía**: lo deriva el servidor de la extensión y
  /// lo devuelve en `archivo.tipoContenido`. Mandarlo desde aquí permitiría
  /// declarar un tipo que no corresponde al nombre.
  Future<SubidaFirmada> firmarSubida({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    String? entidadId,
  });

  /// Paso 2. Sube los bytes **directamente a R2**, sin pasar por el backend.
  ///
  /// [tipoContenido] debe ser exactamente `SubidaFirmada.archivo.tipoContenido`:
  /// la URL prefirmada cubre el `Content-Type`, así que enviar otro hace que R2
  /// rechace la firma. Es lo que impide subir un ejecutable con nombre `.pdf`.
  Future<void> subirObjeto({
    required String urlDeSubida,
    required String tipoContenido,
    required List<int> contenido,
  });

  /// Paso 3. Confirma que el objeto llegó y sella su tamaño real.
  ///
  /// Aquí es donde se aplica el límite de peso, y no al firmar: una URL `PUT`
  /// prefirmada no admite `content-length-range`, así que el tamaño sólo se
  /// conoce con el `HeadObject` posterior. Por eso el cliente no lo manda.
  ///
  /// Puede fallar con 404 `OBJETO_NO_SUBIDO` (la subida se interrumpió), 413
  /// `ARCHIVO_DEMASIADO_GRANDE` (se pasó del límite) o 409 si ya estaba
  /// confirmado.
  Future<Archivo> confirmar(String archivoId);

  /// Devuelve una URL de descarga temporal para un archivo confirmado.
  ///
  /// Un archivo ajeno da **404**, no 403: la RLS esconde la fila y el handler no
  /// puede distinguir «no existe» de «no es tuyo». Y no debe poder.
  Future<UrlDeLectura> urlDeLectura(String archivoId);

  /// Borra un archivo propio (borrado lógico + objeto fuera de R2).
  Future<Archivo> borrar(String archivoId);

  /// Borra cualquier archivo como administrador.
  Future<Archivo> borrarComoAdmin(String archivoId);

  /// Los tres pasos, en orden, devolviendo el archivo ya confirmado.
  ///
  /// Es el camino que usa la UI. Se ofrece además de los pasos sueltos porque
  /// reanudar una subida interrumpida exige control fino: la fila sigue
  /// `PENDING`, y reintentar desde el paso 1 crearía otra reserva en vez de
  /// aprovechar la que ya existe.
  Future<Archivo> subir({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    required List<int> contenido,
    String? entidadId,
  });
}
