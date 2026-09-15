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
}
