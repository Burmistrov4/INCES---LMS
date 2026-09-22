import '../core/gateways/aula_gateway.dart';
import '../core/network/api_client.dart';
import '../models/cuadrante.dart';
import 'supabase_service.dart';

/// Implementación de [AulasPropiasGateway] contra el backend Fastify.
///
/// Lee `GET /api/v1/mi-horario` —la misma ruta que sirve al panel «Mi horario»
/// de M3— y la reduce al listado de aulas del menú «Mis aulas».
///
/// ## Lo que este servicio NO implementa
///
/// El **contenido** del aula: `tablon`, `trabajoDeClase`, `misEntregas`,
/// `entregar` y `reclamar`. Los `payloads` de M6 no están cerrados (ver la
/// cabecera de `lib/core/gateways/aula_gateway.dart`), así que esos cinco
/// métodos viven **sólo** en `test/support/fake_aula_gateway.dart`.
///
/// Por eso esta clase declara [AulasPropiasGateway] y no [AulaGateway]: es la
/// forma de que el compilador impida cablearla donde se espera una puerta de
/// contenido, en vez de dejar cinco métodos que revientan en producción.
///
/// El token de sesión se manda para que el backend resuelva el rol. La ruta no
/// cuelga del prefijo de administración: la guarda `exigirSesion()` y el
/// aislamiento por rol lo hace la RLS.
class BackendAulaGateway implements AulasPropiasGateway {
  /// [tokenSesion] es un parámetro y no una llamada directa a `SupabaseService`
  /// por la misma razón que en M5: `SupabaseService.instance.auth` llega hasta
  /// `Supabase.instance`, que **lanza** si Supabase no está inicializado, y
  /// leerlo dentro haría que el gateway no se pudiera construir en una prueba.
  /// Sin este hueco, la única ruta real de M6 que ya existe quedaría sin cubrir.
  BackendAulaGateway({ApiClient? api, String? Function()? tokenSesion})
      : _api = api ?? ApiClient(),
        _tokenSesion = tokenSesion ?? _tokenDeSupabase;

  final ApiClient _api;

  /// De dónde sale el JWT de la sesión actual.
  final String? Function() _tokenSesion;

  /// El token de la sesión de Supabase. Es lo que se inyecta en producción.
  static String? _tokenDeSupabase() =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  /// La ruta del horario propio.
  ///
  /// Es la **misma** que usa `BackendCuadranteGateway`: no son dos rutas, son
  /// dos lecturas de la misma respuesta. El listado de aulas necesita la
  /// sección, la materia y el programa; el panel de horario necesita además el
  /// día y el bloque. Compartir la ruta evita que las dos se desvíen.
  static const String _rutaMiHorario = '/api/v1/mi-horario';

  @override
  Future<MisAulas> misAulas({String? periodo}) async {
    final respuesta = await _api.get(
      _rutaMiHorario,
      token: _tokenSesion(),
      // Un período en blanco se omite: `ApiClient` descarta los parámetros
      // vacíos, así que `null` y `''` acaban en la misma URL limpia y el
      // backend no recibe un `periodo=` que rechazaría.
      parametros: {'periodo': ?_limpiar(periodo)},
    );

    return _reducir(MiHorario.fromJson(respuesta));
  }

  /// Reduce el horario del llamante a un aula por sección.
  ///
  /// **Una sección, una fila.** `clases` trae una fila por franja del cuadrante,
  /// así que la misma sección aparece tantas veces como días y bloques tenga: en
  /// un listado de aulas eso serían tarjetas repetidas. Se deduplica por
  /// `seccionId` conservando la **primera** aparición, que es la que fija la
  /// etiqueta.
  ///
  /// **Las guardias no son aulas.** Una guardia es una presencia de custodia, no
  /// una clase con tablón ni trabajo de clase: se ignora aunque venga en el
  /// payload. Para un estudiante ya viene vacía, así que esto sólo cambia el
  /// caso del docente.
  ///
  /// El rol sale del payload y no de una bandera del llamante: quien sabe qué es
  /// el usuario es el servidor, y una bandera del cliente sería una segunda
  /// fuente de verdad sobre permisos (ADR-003).
  static MisAulas _reducir(MiHorario horario) {
    final vistas = <String>{};
    final aulas = <AulaResumen>[];

    for (final clase in horario.clases) {
      // `add` devuelve `false` si la sección ya estaba: una sola pasada hace de
      // deduplicación y de recorrido.
      if (!vistas.add(clase.seccionId)) continue;

      aulas.add(
        AulaResumen(
          seccionId: clase.seccionId,
          materia: clase.materia,
          seccion: clase.seccion,
          // Vacío y nulo significan lo mismo aquí: la vista no resolvió el
          // programa. Se normaliza a `null` para que la etiqueta no deje un
          // separador colgando.
          programa: clase.programa.trim().isEmpty ? null : clase.programa,
        ),
      );
    }

    return MisAulas(
      esDocente: horario.rol == 'docente',
      periodo: horario.periodo,
      aulas: aulas,
    );
  }

  /// Un texto de consulta en blanco equivale a no filtrar.
  static String? _limpiar(String? texto) {
    final limpio = texto?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }
}
