import 'package:http/http.dart' as http;

import '../core/errors/app_exception.dart';
import '../core/gateways/archivos_gateway.dart';
import '../core/network/api_client.dart';
import '../models/archivo.dart';
import 'supabase_service.dart';

/// De dónde sale el JWT de la sesión actual.
///
/// Es un parámetro y no una llamada directa a `SupabaseService` por una razón
/// concreta: `SupabaseService.instance.auth` llega hasta `Supabase.instance`,
/// que **lanza** si Supabase no está inicializado. Leerlo dentro del gateway
/// haría que éste no se pudiera construir en una prueba, y el camino HTTP de M5
/// —el único que prueba la firma de R2— quedaría sin cubrir.
typedef ProveedorDeToken = String? Function();

/// Implementación de [ArchivosGateway] contra el backend Fastify y R2.
///
/// Las llamadas al backend pasan por [ApiClient] (que traduce el sobre
/// `{ error: { codigo, mensaje } }` a [AppException]); el `PUT` del objeto va
/// **directo a R2**, sin pasar por el backend, porque el backend nunca ve los
/// bytes.
class BackendArchivosGateway implements ArchivosGateway {
  /// Un solo `http.Client` para las dos cosas.
  ///
  /// No es un atajo: además de reutilizar el grupo de conexiones, deja **un único
  /// punto de inyección**. Con dos clientes distintos, una prueba tendría que
  /// doblar por separado el tráfico al backend y el de R2, y el `PUT` —que es
  /// justo lo que se quiere verificar— podría quedarse sin doblar y salir a la
  /// red real sin que nadie lo note.
  factory BackendArchivosGateway({
    http.Client? httpClient,
    String? baseUrl,
    ProveedorDeToken? tokenSesion,
  }) {
    final cliente = httpClient ?? http.Client();
    return BackendArchivosGateway._(
      ApiClient(httpClient: cliente, baseUrl: baseUrl),
      cliente,
      tokenSesion ?? tokenDeSupabase,
    );
  }

  /// Posicional y privado a propósito: los parámetros **con nombre** no admiten
  /// un guion bajo inicial en Dart, y estos tres campos son privados.
  BackendArchivosGateway._(this._api, this._cliente, this._tokenSesion);

  final ApiClient _api;
  final http.Client _cliente;
  final ProveedorDeToken _tokenSesion;

  /// El token de la sesión de Supabase. Es lo que se inyecta en producción.
  static String? tokenDeSupabase() =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  static const String _base = '/api/v1/archivos';

  @override
  Future<SubidaFirmada> firmarSubida({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    String? entidadId,
  }) async {
    final respuesta = await _api.post(
      '$_base/firmar-subida',
      token: _tokenSesion(),
      cuerpo: {
        'nombreOriginal': nombreOriginal,
        'entityType': entityType.valorRemoto,
        // Nulo es un valor legítimo y frecuente: el archivo puede subirse antes
        // de que exista la tarea o la guía a la que pertenece. El backend sólo
        // aplica el tope por entidad cuando este campo viene con valor.
        'entidadId': entidadId,
      },
    );

    return SubidaFirmada.fromJson(respuesta);
  }

  @override
  Future<void> subirObjeto({
    required String urlDeSubida,
    required String tipoContenido,
    required List<int> contenido,
  }) async {
    final respuesta = await _cliente.put(
      Uri.parse(urlDeSubida),
      headers: {'Content-Type': tipoContenido},
      body: contenido,
    );

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) return;

    // R2 no habla el idioma de errores del backend: aquí no hay
    // `{ error: { codigo, mensaje } }` que traducir. Un 403 en este punto
    // significa casi siempre que el `Content-Type` no es el que se firmó —la URL
    // prefirmada lo cubre—, y eso es un fallo nuestro, no algo que el usuario
    // pueda corregir reintentando, así que el mensaje no lo culpa.
    throw AppException(
      type: AppErrorType.servidor,
      message:
          'No se pudo subir el archivo al almacenamiento. Inténtalo de nuevo.',
      code: 'SUBIDA_RECHAZADA',
      technical: 'R2 respondió ${respuesta.statusCode} al PUT',
    );
  }

  @override
  Future<Archivo> confirmar(String archivoId) async {
    // POST sin cuerpo: `ApiClient` omite el `Content-Type` a propósito, porque
    // Fastify responde 500 (`FST_ERR_CTP_EMPTY_JSON_BODY`) si se declara JSON
    // sin body.
    final respuesta = await _api.post(
      '$_base/$archivoId/confirmar',
      token: _tokenSesion(),
    );

    return Archivo.fromJson(respuesta['archivo'] as Map<String, dynamic>);
  }

  @override
  Future<UrlDeLectura> urlDeLectura(String archivoId) async {
    final respuesta = await _api.get(
      '$_base/$archivoId/url-lectura',
      token: _tokenSesion(),
    );

    return UrlDeLectura.fromJson(respuesta);
  }

  @override
  Future<Archivo> borrar(String archivoId) async {
    final respuesta = await _api.delete(
      '$_base/$archivoId',
      token: _tokenSesion(),
    );

    return Archivo.fromJson(respuesta['archivo'] as Map<String, dynamic>);
  }

  @override
  Future<Archivo> borrarComoAdmin(String archivoId) async {
    final respuesta = await _api.delete(
      '/api/v1/admin/archivos/$archivoId',
      token: _tokenSesion(),
    );

    return Archivo.fromJson(respuesta['archivo'] as Map<String, dynamic>);
  }

  @override
  Future<Archivo> subir({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    required List<int> contenido,
    String? entidadId,
  }) async {
    final firmada = await firmarSubida(
      nombreOriginal: nombreOriginal,
      entityType: entityType,
      entidadId: entidadId,
    );

    await subirObjeto(
      urlDeSubida: firmada.urlDeSubida,
      // El tipo lo dicta el servidor, no el llamante: es el que la firma cubre y
      // el que la base guardó. Derivarlo otra vez aquí abriría la puerta a que
      // las dos derivaciones discrepen y R2 rechace la subida.
      tipoContenido: firmada.archivo.tipoContenido,
      contenido: contenido,
    );

    return confirmar(firmada.archivo.id);
  }
}
