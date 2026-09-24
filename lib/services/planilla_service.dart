import '../core/gateways/planilla_gateway.dart';
import '../core/network/api_client.dart';
import '../models/inscripcion_campo.dart';
import 'supabase_service.dart';

/// Implementación de [PlanillaGateway] contra el backend Fastify.
///
/// Va por HTTP y **no** contra Supabase directo, que es la regla del proyecto:
/// el `23514` que nombra los campos que faltan lo produce un trigger y sólo el
/// backend lo puede convertir en un mensaje accionable. Además, el catálogo es
/// público, así que no tiene sentido atarlo a una sesión de Supabase.
class BackendPlanillaGateway implements PlanillaGateway {
  BackendPlanillaGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de sesión, sólo para la escritura. La lectura del catálogo es pública
  /// y viaja **sin** `Authorization` a propósito: si el token caducó, el
  /// formulario de inscripción tiene que seguir pudiendo pintarse.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  @override
  Future<CatalogoInscripcion> campos() async {
    final respuesta = await _api.get('/api/v1/inscripcion/campos');
    return CatalogoInscripcion.fromJson(respuesta);
  }

  @override
  Future<PlanillaInscripcion> guardar(PlanillaInscripcion planilla) async {
    final respuesta = await _api.put(
      '/api/v1/yo/planilla',
      cuerpo: {'planilla': planilla},
      token: _tokenSesion,
    );

    final guardada = respuesta['planilla'];
    return guardada is Map<String, dynamic> ? guardada : <String, dynamic>{};
  }
}
