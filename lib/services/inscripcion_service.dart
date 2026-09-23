import '../core/errors/app_exception.dart';
import '../core/gateways/inscripcion_gateway.dart';
import '../core/network/api_client.dart';
import '../models/inscripcion.dart';
import 'supabase_service.dart';

/// Implementación de [InscripcionGateway] contra el backend Fastify.
///
/// Las rutas de admin exigen el JWT de sesión del usuario (para que el backend
/// valide rol admin). Las de estudiante también lo usan para identificarlo.
class BackendInscripcionGateway implements InscripcionGateway {
  BackendInscripcionGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de sesión del usuario actual, para autenticar la ruta.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  @override
  Future<List<OcupacionSeccion>> obtenerOfertas({bool soloConCupo = false}) async {
    final respuesta = await _api.get(
      '/api/v1/ofertas',
      token: _tokenSesion,
      parametros: soloConCupo ? {'soloConCupo': 'true'} : null,
    );
    final secciones =
        (respuesta['secciones'] as List?)?.cast<Map<String, dynamic>>();
    return secciones?.map(OcupacionSeccion.fromJson).toList() ?? const [];
  }

  @override
  Future<List<InscripcionDetallada>> obtenerMisInscripciones() async {
    final respuesta =
        await _api.get('/api/v1/mis-inscripciones', token: _tokenSesion);
    final inscripciones =
        (respuesta['inscripciones'] as List?)?.cast<Map<String, dynamic>>();
    return inscripciones?.map(InscripcionDetallada.fromJson).toList() ??
        const [];
  }

  @override
  Future<EstadoInscripcion> inscribirse(String seccionId) async {
    final respuesta = await _api.post(
      '/api/v1/inscripciones',
      cuerpo: {'seccionId': seccionId},
      token: _tokenSesion,
    );
    return EstadoInscripcion.desde(respuesta['estado'] as String?);
  }

  @override
  Future<EstadoInscripcion> renunciar(String seccionId) async {
    // POST sin cuerpo: la sección viaja en la ruta. El cliente NO debe mandar
    // `Content-Type: application/json` (trampa FST_ERR_CTP_EMPTY_JSON_BODY).
    final respuesta = await _api.post(
      '/api/v1/inscripciones/$seccionId/renunciar',
      token: _tokenSesion,
    );
    return EstadoInscripcion.desde(respuesta['estado'] as String?);
  }

  @override
  Future<EstadoInscripcion> aceptarOferta(String seccionId) async {
    final respuesta = await _api.post(
      '/api/v1/inscripciones/$seccionId/aceptar',
      token: _tokenSesion,
    );
    return EstadoInscripcion.desde(respuesta['estado'] as String?);
  }

  @override
  Future<List<OcupacionSeccion>> obtenerOcupacion({bool soloConCupo = false}) async {
    final respuesta = await _api.get(
      '/api/v1/admin/ocupacion',
      token: _tokenSesion,
      parametros: soloConCupo ? {'soloConCupo': 'true'} : null,
    );
    final secciones =
        (respuesta['secciones'] as List?)?.cast<Map<String, dynamic>>();
    return secciones?.map(OcupacionSeccion.fromJson).toList() ?? const [];
  }

  @override
  Future<InscripcionDetallada> promoverSiguiente(String seccionId) async {
    // POST sin cuerpo. Devuelve `{ promovida, mensaje }`; `promovida: null`
    // significa «no había nadie a quien promover» (cola vacía, llena o con
    // oferta viva), que es un caso normal y no un error.
    final respuesta = await _api.post(
      '/api/v1/admin/secciones/$seccionId/promover',
      token: _tokenSesion,
    );
    final promovida = respuesta['promovida'] as Map<String, dynamic>?;
    if (promovida == null) {
      throw AppException.validacion(
        'No se promovió a nadie: la cola está vacía, la sección está llena '
        'o ya hay una oferta de cupo en el aire.',
      );
    }
    return InscripcionDetallada.fromJson(promovida);
  }

  @override
  Future<int> expirarOfertas() async {
    final respuesta = await _api.post(
      '/api/v1/admin/inscripciones/expirar',
      token: _tokenSesion,
    );
    return (respuesta['vencidas'] as int?) ?? 0;
  }

  @override
  Future<List<InscripcionDetallada>> obtenerCola(String seccionId) async {
    final respuesta = await _api.get(
      '/api/v1/admin/secciones/$seccionId/cola',
      token: _tokenSesion,
    );
    return ((respuesta['cola'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(InscripcionDetallada.fromJson)
        .toList();
  }

  @override
  Future<List<InscripcionDetallada>> obtenerInscripcionesDeSeccion(
      String seccionId) async {
    final respuesta = await _api.get(
      '/api/v1/admin/secciones/$seccionId/inscripciones',
      token: _tokenSesion,
    );
    return ((respuesta['inscripciones'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(InscripcionDetallada.fromJson)
        .toList();
  }

  @override
  Future<EstadoInscripcion> reincorporar({
    required String estudianteId,
    required String seccionId,
  }) async {
    final respuesta = await _api.post(
      '/api/v1/admin/inscripciones/reincorporar',
      cuerpo: {'estudianteId': estudianteId, 'seccionId': seccionId},
      token: _tokenSesion,
    );
    return EstadoInscripcion.desde(respuesta['estado'] as String?);
  }
}
