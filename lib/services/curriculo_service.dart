import '../core/gateways/curriculo_gateway.dart';
import '../core/network/api_client.dart';
import '../models/materia.dart';
import '../models/pensum.dart';
import '../models/programa.dart';
import 'supabase_service.dart';

/// Implementación de [CurriculoGateway] contra el backend Fastify.
///
/// Pasa por el backend y no por Supabase directamente por la misma razón que el
/// resto de operaciones de administración: la atomicidad del asistente vive en
/// las funciones `crear_programa_con_pensum` y `reemplazar_pensum`, y la API
/// además exige rol admin y devuelve mensajes de error en español.
///
/// Una escritura directa desde aquí contra `programs` o `program_subjects`
/// **se saltaría la transacción** que esas funciones existen para dar. No es
/// una preferencia de estilo: es lo que impide dejar un programa a medio armar.
class BackendCurriculoGateway implements CurriculoGateway {
  BackendCurriculoGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de sesión del administrador, para que el backend valide su rol.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  static const String _base = '/api/v1/admin';

  @override
  Future<PaginaProgramas> listarProgramas({
    TipoPrograma? tipo,
    bool? activo,
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    final tipoApi = tipo?.valorApi;
    final activoTexto = activo == null ? null : '$activo';
    final busquedaTexto = _limpiar(busqueda);

    final respuesta = await _api.get(
      '$_base/programas',
      token: _tokenSesion,
      parametros: {
        // Los filtros sin usar se omiten del todo: mandar `busqueda=` vacío
        // haría que el backend lo rechazara por no cumplir la longitud mínima.
        'tipo': ?tipoApi,
        'activo': ?activoTexto,
        'busqueda': ?busquedaTexto,
        'limite': '$limite',
        'desplazamiento': '$desplazamiento',
      },
    );

    final programas = (respuesta['programas'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProgramaConTotales.fromJson)
        .toList();

    return PaginaProgramas(
      programas: programas,
      // Si el total no viniera, se cae al tamaño de la página antes que a 0:
      // un «de 0» en la interfaz haría creer que no hay nada registrado.
      total: respuesta['total'] as int? ?? programas.length,
    );
  }

  @override
  Future<DetallePrograma> detallePrograma(String id) async {
    final respuesta = await _api.get(
      '$_base/programas/$id',
      token: _tokenSesion,
    );

    return DetallePrograma.fromJson(respuesta);
  }

  @override
  Future<DetallePrograma> crearPrograma(EntradaCrearPrograma entrada) async {
    // El 201 devuelve el detalle completo, no sólo el programa: así el
    // asistente puede mostrar el pensum agrupado sin una segunda petición.
    final respuesta = await _api.post(
      '$_base/programas',
      cuerpo: entrada.toJson(),
      token: _tokenSesion,
    );

    return DetallePrograma.fromJson(respuesta);
  }

  @override
  Future<Programa> actualizarPrograma(String id, CambiosPrograma cambios) async {
    final respuesta = await _api.patch(
      '$_base/programas/$id',
      cuerpo: cambios.toJson(),
      token: _tokenSesion,
    );

    return Programa.fromJson(
      respuesta['programa'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<DetallePrograma> reemplazarPensum(
    String id,
    List<EntradaPensum> pensum,
  ) async {
    final respuesta = await _api.patch(
      '$_base/programas/$id/pensum',
      cuerpo: {'pensum': [for (final entrada in pensum) entrada.toJson()]},
      token: _tokenSesion,
    );

    return DetallePrograma.fromJson(respuesta);
  }

  @override
  Future<PaginaMaterias> listarMaterias({
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    final busquedaTexto = _limpiar(busqueda);

    final respuesta = await _api.get(
      '$_base/materias',
      token: _tokenSesion,
      parametros: {
        'busqueda': ?busquedaTexto,
        'limite': '$limite',
        'desplazamiento': '$desplazamiento',
      },
    );

    final materias = (respuesta['materias'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Materia.fromJson)
        .toList();

    return PaginaMaterias(
      materias: materias,
      total: respuesta['total'] as int? ?? materias.length,
    );
  }

  @override
  Future<Materia> crearMateria(EntradaCrearMateria entrada) async {
    final respuesta = await _api.post(
      '$_base/materias',
      cuerpo: entrada.toJson(),
      token: _tokenSesion,
    );

    return Materia.fromJson(
      respuesta['materia'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Un texto de búsqueda en blanco equivale a no filtrar.
  ///
  /// Se recorta aquí y no en la pantalla para que valga igual desde cualquier
  /// llamante: un filtro escrito con un espacio al final no encuentra nada y el
  /// administrador culpa a los datos.
  static String? _limpiar(String? texto) {
    final limpio = texto?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }
}
