import '../core/gateways/archivos_gateway.dart';
import '../core/result.dart';
import '../models/archivo.dart';
import '../services/archivos_service.dart';

/// Repositorio de archivos del Módulo 5 (Cloudflare R2).
///
/// Envoltura fina sobre [ArchivosGateway], como el resto de repositorios del
/// proyecto: convierte las excepciones que lanza la capa de datos en [Result] y
/// no habla HTTP. La orquestación de los tres pasos de la subida vive en el
/// gateway, que es donde está el transporte.
///
/// La UI consume con `when(success: ..., failure: ...)`.
class ArchivosRepository {
  ArchivosRepository({ArchivosGateway? gateway})
      : _gateway = gateway ?? BackendArchivosGateway();

  final ArchivosGateway _gateway;

  /// Los tres pasos de la subida, en orden, hasta dejar el archivo `CONFIRMED`.
  ///
  /// Es el camino normal. Un `Failure` aquí puede significar cosas muy distintas
  /// y el código del error es lo que las separa: `ARCHIVO_DEMASIADO_GRANDE`
  /// (413, el usuario sube otro más pequeño), `OBJETO_NO_SUBIDO` (404, la subida
  /// se cortó y hay que repetirla) o un fallo de red.
  Future<Result<Archivo>> subir({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    required List<int> contenido,
    String? entidadId,
  }) =>
      Result.guard(
        () => _gateway.subir(
          nombreOriginal: nombreOriginal,
          entityType: entityType,
          contenido: contenido,
          entidadId: entidadId,
        ),
      );

  /// Paso 1 suelto: reserva y firma.
  ///
  /// Se expone aparte de [subir] para poder **reanudar**: si el `PUT` se cortó, la
  /// fila sigue `PENDING` con su clave ya reservada, y volver a empezar desde el
  /// paso 1 crearía una reserva nueva en vez de aprovechar la que existe.
  Future<Result<SubidaFirmada>> firmarSubida({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    String? entidadId,
  }) =>
      Result.guard(
        () => _gateway.firmarSubida(
          nombreOriginal: nombreOriginal,
          entityType: entityType,
          entidadId: entidadId,
        ),
      );

  /// Paso 2 suelto: el `PUT` directo a R2.
  Future<Result<void>> subirObjeto({
    required String urlDeSubida,
    required String tipoContenido,
    required List<int> contenido,
  }) =>
      Result.guard(
        () => _gateway.subirObjeto(
          urlDeSubida: urlDeSubida,
          tipoContenido: tipoContenido,
          contenido: contenido,
        ),
      );

  /// Paso 3 suelto: confirma y sella el tamaño.
  Future<Result<Archivo>> confirmar(String archivoId) =>
      Result.guard(() => _gateway.confirmar(archivoId));

  /// URL de descarga temporal de un archivo confirmado.
  Future<Result<UrlDeLectura>> urlDeLectura(String archivoId) =>
      Result.guard(() => _gateway.urlDeLectura(archivoId));

  /// Los archivos vivos de una tarea o una guía.
  ///
  /// Es la lectura que permite **hidratar** el panel al abrirlo: sin ella la
  /// pantalla sólo podía mostrar lo subido durante la sesión actual, y al
  /// recargar parecía que no había nada guardado.
  Future<Result<List<Archivo>>> listarPorEntidad({
    required TipoEntidadArchivo entityType,
    required String entidadId,
  }) =>
      Result.guard(
        () => _gateway.listarPorEntidad(
          entityType: entityType,
          entidadId: entidadId,
        ),
      );

  /// Borra un archivo propio.
  Future<Result<Archivo>> borrar(String archivoId) =>
      Result.guard(() => _gateway.borrar(archivoId));

  /// Borra cualquier archivo como administrador.
  Future<Result<Archivo>> borrarComoAdmin(String archivoId) =>
      Result.guard(() => _gateway.borrarComoAdmin(archivoId));
}
