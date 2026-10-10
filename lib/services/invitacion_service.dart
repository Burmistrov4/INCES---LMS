import '../core/gateways/invitacion_gateway.dart';
import '../core/network/api_client.dart';
import '../models/invitacion_docente.dart';
import 'supabase_service.dart';

/// Implementación del [InvitacionGateway] contra el backend Fastify.
///
/// La invitación de admin exige el JWT de sesión del usuario (para que el
/// backend valide rol admin). La activación es pública: el docente aún no tiene
/// sesión cuando abre el enlace, así que no se envía token.
class BackendInvitacionGateway implements InvitacionGateway {
  BackendInvitacionGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de sesión del usuario actual, para autenticar la ruta de admin.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  @override
  Future<InvitacionDocente> invitarDocente(
    String email,
    String nombres,
    String apellidos,
  ) async {
    final respuesta = await _api.post(
      '/api/v1/admin/usuarios/invitaciones',
      cuerpo: {
        'email': email,
        'nombres': nombres,
        'apellidos': apellidos,
      },
      token: _tokenSesion,
    );
    return InvitacionDocente.fromJson(respuesta);
  }

  @override
  Future<ActivacionCuenta> activarCuenta({
    required String token,
    required String password,
  }) async {
    final respuesta = await _api.post(
      '/api/v1/auth/activar',
      cuerpo: {'token': token, 'password': password},
    );
    return ActivacionCuenta.fromJson(respuesta);
  }

  @override
  Future<List<InvitacionListada>> listarInvitaciones() async {
    final respuesta = await _api.get(
      '/api/v1/admin/usuarios/invitaciones',
      token: _tokenSesion,
    );
    final crudas = respuesta['invitaciones'] as List<dynamic>? ?? const [];
    return crudas
        .whereType<Map<String, dynamic>>()
        .map(InvitacionListada.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> revocarInvitacion(String id) async {
    // **Sin `cuerpo`**: la ruta no lee body y mandar `{}` con
    // `Content-Type: application/json` haría que Fastify respondiera 500
    // (`FST_ERR_CTP_EMPTY_JSON_BODY`).
    await _api.post(
      '/api/v1/admin/usuarios/invitaciones/$id/revocar',
      token: _tokenSesion,
    );
  }

  @override
  Future<InvitacionDocente> renovarInvitacion(String id) async {
    final respuesta = await _api.post(
      '/api/v1/admin/usuarios/invitaciones/$id/renovar',
      token: _tokenSesion,
    );
    return InvitacionDocente.fromJson(respuesta);
  }
}
