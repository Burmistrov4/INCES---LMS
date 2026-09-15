import '../core/gateways/cuadrante_gateway.dart';
import '../core/network/api_client.dart';
import '../models/cuadrante.dart';
import 'supabase_service.dart';

/// Implementación de [CuadranteGateway] contra el backend Fastify.
///
/// Pasa por el backend y no por Supabase directamente por la misma razón que el
/// resto de operaciones de administración: la invariante que impide que un
/// docente esté en dos sitios a la vez vive en un trigger que **cruza dos
/// tablas** (`schedule_slots` y `teacher_duties`), y una escritura directa desde
/// aquí contra `schedule_slots` se saltaría el chequeo de las guardias. No es
/// una preferencia de estilo: es lo que impide que el cuadrante admita una
/// agenda imposible.
///
/// El token de sesión se manda para que el backend valide el rol. Las lecturas
/// de `/mi-horario` no pasan por el prefijo de administración: esa ruta la
/// guarda `exigirSesion()` y el aislamiento lo hace la RLS.
class BackendCuadranteGateway implements CuadranteGateway {
  BackendCuadranteGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de sesión del llamante, para que el backend valide su rol.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  static const String _base = '/api/v1/admin';

  /// La ruta del horario propio **no** cuelga de `/admin`: un docente y un
  /// estudiante no son administradores, y montarla bajo el prefijo habría
  /// exigido relajar la guardia que protege todo lo demás.
  static const String _rutaMiHorario = '/api/v1/mi-horario';

  // ---------------------------------------------------------------------------
  // Aulas
  // ---------------------------------------------------------------------------

  @override
  Future<PaginaAulas> listarAulas({
    TipoAula? tipo,
    bool? activa,
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    final respuesta = await _api.get(
      '$_base/aulas',
      token: _tokenSesion,
      parametros: {
        // Los filtros sin usar se omiten del todo: mandar `busqueda=` vacío
        // haría que el backend lo rechazara por no cumplir la longitud mínima.
        'tipo': ?tipo?.valorApi,
        'activa': ?_booleano(activa),
        'busqueda': ?_limpiar(busqueda),
        'limite': '$limite',
        'desplazamiento': '$desplazamiento',
      },
    );

    return PaginaAulas.fromJson(respuesta);
  }

  @override
  Future<Aula> crearAula(EntradaCrearAula entrada) async {
    final respuesta = await _api.post(
      '$_base/aulas',
      cuerpo: entrada.toJson(),
      token: _tokenSesion,
    );

    return Aula.fromJson(_objeto(respuesta, 'aula'));
  }

  @override
  Future<Aula> actualizarAula(String id, CambiosAula cambios) async {
    final respuesta = await _api.patch(
      '$_base/aulas/$id',
      cuerpo: cambios.toJson(),
      token: _tokenSesion,
    );

    return Aula.fromJson(_objeto(respuesta, 'aula'));
  }

  // ---------------------------------------------------------------------------
  // Períodos
  // ---------------------------------------------------------------------------

  @override
  Future<List<Periodo>> listarPeriodos() async {
    final respuesta = await _api.get('$_base/periodos', token: _tokenSesion);

    return (respuesta['periodos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Periodo.fromJson)
        .toList();
  }

  @override
  Future<Periodo> crearPeriodo(EntradaCrearPeriodo entrada) async {
    final respuesta = await _api.post(
      '$_base/periodos',
      cuerpo: entrada.toJson(),
      token: _tokenSesion,
    );

    return Periodo.fromJson(_objeto(respuesta, 'periodo'));
  }

  @override
  Future<Periodo> actualizarPeriodo(String id, CambiosPeriodo cambios) async {
    final respuesta = await _api.patch(
      '$_base/periodos/$id',
      cuerpo: cambios.toJson(),
      token: _tokenSesion,
    );

    return Periodo.fromJson(_objeto(respuesta, 'periodo'));
  }

  @override
  Future<Periodo> marcarVigente(String id) async {
    // Sin cuerpo: la ruta no lee ninguno. El `id` del camino es toda la
    // información que necesita.
    final respuesta = await _api.put(
      '$_base/periodos/$id/vigente',
      token: _tokenSesion,
    );

    return Periodo.fromJson(_objeto(respuesta, 'periodo'));
  }

  // ---------------------------------------------------------------------------
  // Guardias
  // ---------------------------------------------------------------------------

  @override
  Future<PaginaGuardias> listarGuardias({
    String? periodo,
    String? docenteId,
    String? aulaId,
    int? dia,
    int? bloque,
    bool? activa,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    final respuesta = await _api.get(
      '$_base/guardias',
      token: _tokenSesion,
      parametros: {
        'periodo': ?_limpiar(periodo),
        'docenteId': ?_limpiar(docenteId),
        'aulaId': ?_limpiar(aulaId),
        'dia': ?dia?.toString(),
        'bloque': ?bloque?.toString(),
        'activa': ?_booleano(activa),
        'limite': '$limite',
        'desplazamiento': '$desplazamiento',
      },
    );

    return PaginaGuardias.fromJson(respuesta);
  }

  @override
  Future<Guardia> crearGuardia(EntradaCrearGuardia entrada) async {
    final respuesta = await _api.post(
      '$_base/guardias',
      cuerpo: entrada.toJson(),
      token: _tokenSesion,
    );

    return Guardia.fromJson(_objeto(respuesta, 'guardia'));
  }

  @override
  Future<Guardia> actualizarGuardia(String id, CambiosGuardia cambios) async {
    final respuesta = await _api.patch(
      '$_base/guardias/$id',
      cuerpo: cambios.toJson(),
      token: _tokenSesion,
    );

    return Guardia.fromJson(_objeto(respuesta, 'guardia'));
  }

  // ---------------------------------------------------------------------------
  // Cuadrante
  // ---------------------------------------------------------------------------

  @override
  Future<RejillaCuadrante> rejilla({
    String? periodo,
    String? seccionId,
    String? docenteId,
    String? aulaId,
    bool incluirInactivas = false,
  }) async {
    final respuesta = await _api.get(
      '$_base/cuadrante',
      token: _tokenSesion,
      parametros: {
        'periodo': ?_limpiar(periodo),
        'seccionId': ?_limpiar(seccionId),
        'docenteId': ?_limpiar(docenteId),
        'aulaId': ?_limpiar(aulaId),
        // Se manda siempre y no sólo cuando es `true`: el backend tiene
        // `false` por defecto, pero explicitarlo deja la intención escrita y
        // evita que un cambio de defecto en el servidor altere lo que ve el
        // administrador sin que nadie toque esta línea.
        'incluirInactivas': '$incluirInactivas',
      },
    );

    return RejillaCuadrante.fromJson(respuesta);
  }

  @override
  Future<ClaseCuadrante> crearClase(EntradaCrearClase entrada) async {
    final respuesta = await _api.post(
      '$_base/cuadrante',
      cuerpo: entrada.toJson(),
      token: _tokenSesion,
    );

    return ClaseCuadrante.fromJson(_objeto(respuesta, 'clase'));
  }

  @override
  Future<ClaseCuadrante> actualizarClase(
    String id,
    CambiosClase cambios,
  ) async {
    final respuesta = await _api.patch(
      '$_base/cuadrante/$id',
      cuerpo: cambios.toJson(),
      token: _tokenSesion,
    );

    return ClaseCuadrante.fromJson(_objeto(respuesta, 'clase'));
  }

  // ---------------------------------------------------------------------------
  // Horario por rol
  // ---------------------------------------------------------------------------

  @override
  Future<MiHorario> miHorario({String? periodo}) async {
    final respuesta = await _api.get(
      _rutaMiHorario,
      token: _tokenSesion,
      parametros: {'periodo': ?_limpiar(periodo)},
    );

    return MiHorario.fromJson(respuesta);
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  /// Saca el objeto de un sobre `{ "aula": { … } }`.
  ///
  /// El backend envuelve siempre el recurso en una clave con su nombre, para que
  /// una respuesta no sea un objeto suelto cuya forma dependa del endpoint. Si
  /// la clave no viniera, se cae al cuerpo entero antes que devolver un objeto
  /// vacío: un modelo con todos los campos en blanco se lee como «el registro no
  /// tiene datos», que es peor que fallar.
  static Map<String, dynamic> _objeto(
    Map<String, dynamic> respuesta,
    String clave,
  ) {
    final anidado = respuesta[clave];
    return anidado is Map<String, dynamic> ? anidado : respuesta;
  }

  /// Un booleano de consulta, en la forma que espera el backend.
  ///
  /// Se omite el filtro cuando es `null`, pero un `false` **sí** se manda: «no
  /// filtrar por activa» y «mostrar sólo las archivadas» son preguntas distintas.
  static String? _booleano(bool? valor) => valor?.toString();

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
