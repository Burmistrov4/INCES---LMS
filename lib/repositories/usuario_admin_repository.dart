import '../core/network/api_client.dart';
import '../core/result.dart';
import '../models/usuario_admin.dart';
import '../services/supabase_service.dart';

class UsuariosAdminRepository {
  UsuariosAdminRepository({
    ApiClient? api,
    this.tokenResolver,
  })  : _api = api ?? ApiClient();
  final ApiClient _api;
  final String? Function()? tokenResolver;
  String? get _token {
    if (tokenResolver != null) return tokenResolver!();
    try {
      return SupabaseService.instance.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }
  Future<Result<PaginaUsuarios>> listar({
    String? rol,
    bool? activo,
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) => Result.guard(() async {
    final j = await _api.get(
      '/api/v1/admin/usuarios',
      token: _token,
      parametros: {
        if (rol != null && rol.isNotEmpty) 'rol': rol,
        if (activo != null) 'activo': activo.toString(),
        if (busqueda != null && busqueda.trim().isNotEmpty)
          'busqueda': busqueda.trim(),
        'limite': '$limite',
        'desplazamiento': '$desplazamiento',
      },
    );
    return PaginaUsuarios.fromJson(j);
  });
  Future<Result<UsuarioAdmin>> cambiarRol({
    required String id,
    required String rol,
  }) => Result.guard(() async {
    final j = await _api.patch(
      '/api/v1/admin/usuarios/$id/rol',
      token: _token,
      cuerpo: {'rol': rol},
    );
    return UsuarioAdmin.fromJson(j['perfil'] as Map<String, dynamic>);
  });
}
