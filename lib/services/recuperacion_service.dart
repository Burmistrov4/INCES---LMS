import '../core/gateways/recuperacion_gateway.dart';
import '../core/network/api_client.dart';
import '../models/recuperacion_password.dart';
import 'supabase_service.dart';

/// Implementación del [RecuperacionGateway] contra el backend Fastify.
///
/// La emisión exige el JWT de un administrador (el backend valida el rol). El
/// canje es **público**: quien olvidó su contraseña no tiene sesión, así que no
/// se envía token y la barrera es el propio código.
class BackendRecuperacionGateway implements RecuperacionGateway {
  BackendRecuperacionGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  @override
  Future<CodigoRecuperacion> emitirCodigo(String usuarioId) async {
    // **Sin `cuerpo`.** Mandar `{}` con `Content-Type: application/json` haría
    // que Fastify respondiera `FST_ERR_CTP_EMPTY_JSON_BODY` (500) en una ruta que
    // no lee cuerpo. `ApiClient.post` omite la cabecera cuando `cuerpo` es null,
    // que es la forma correcta de llamar a una ruta sin body.
    final respuesta = await _api.post(
      '/api/v1/admin/usuarios/$usuarioId/restablecer',
      token: _tokenSesion,
    );
    return CodigoRecuperacion.fromJson(respuesta);
  }

  @override
  Future<bool> canjearCodigo({
    required String codigo,
    required String password,
  }) async {
    await _api.post(
      '/api/v1/auth/restablecer-codigo',
      cuerpo: {'codigo': codigo, 'password': password},
    );
    return true;
  }
}
