import '../core/gateways/auditoria_acceso_gateway.dart';
import '../core/network/api_client.dart';
import '../models/entrada_acceso.dart';
import 'supabase_service.dart';

/// Implementación del [AuditoriaAccesoGateway] contra el backend Fastify.
///
/// Pasa por el backend y no por Supabase directamente por la misma razón que el
/// resto de operaciones de administración: el filtrado y el recuento viven en un
/// solo sitio, y la política RLS no es la única barrera (la API además exige rol
/// admin y devuelve un error con mensaje en español).
class BackendAuditoriaAccesoGateway implements AuditoriaAccesoGateway {
  BackendAuditoriaAccesoGateway({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de sesión del administrador, para que el backend valide su rol.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  @override
  Future<PaginaAcceso> listarAccesos({
    EstadoAcceso? estado,
    String? email,
    String? userId,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    final respuesta = await _api.get(
      '/api/v1/admin/acceso',
      token: _tokenSesion,
      parametros: {
        // Los filtros que no se usan se omiten del todo con el elemento
        // null-aware: mandar `email=` vacío haría que el backend lo rechazara
        // con un 400 por cadena demasiado corta.
        if (estado != null) 'estado': estado.valorApi,
        'email': ?email,
        'userId': ?userId,
        'limite': '$limite',
        'desplazamiento': '$desplazamiento',
      },
    );

    final entradas = (respuesta['entradas'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(EntradaAcceso.fromJson)
        .toList();

    // Si el total no viniera, se cae al tamaño de la página antes que a 0:
    // un «de 0» en la interfaz haría creer que no hay nada registrado.
    return PaginaAcceso(
      entradas: entradas,
      total: respuesta['total'] as int? ?? entradas.length,
    );
  }
}
