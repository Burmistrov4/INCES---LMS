import 'dart:typed_data';

import '../core/gateways/planilla_admin_descarga_gateway.dart';
import '../core/network/api_client.dart';
import 'supabase_service.dart';

/// Implementación de [PlanillaAdminDescargaGateway] contra el backend Fastify.
///
/// Va por HTTP y **no** contra Supabase directo, a diferencia de
/// `SupabasePlanillaAdminGateway`. No es una inconsistencia: la frontera de
/// autorización es distinta en cada caso. El catálogo se lee y se escribe por
/// PostgREST porque su política RLS (`inscripcion_campos_admin_*`) ya está
/// escrita para ese límite (ADR-003). El PDF, en cambio, **no se puede** sacar
/// por PostgREST: no es una fila, es un documento que compone un renderizador
/// del servidor leyendo el catálogo activo y el `datos_planilla` de la ficha. Por
/// eso la ruta existe en Fastify, con `exigirAdmin()` + `exigirModulo`, y por eso
/// el nombre dice `Backend`.
class BackendPlanillaAdminDescargaGateway
    implements PlanillaAdminDescargaGateway {
  BackendPlanillaAdminDescargaGateway({ApiClient? api})
      : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Token de la sesión activa. El backend saca **de aquí** quién pregunta, y
  /// del UUID de la ruta **a quién** se le pinta la planilla: son dos datos
  /// distintos y el token no puede sustituir al parámetro.
  String? get _tokenSesion =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  @override
  Future<Uint8List> descargarPdfDe(String usuarioId) => _descargar(usuarioId, 'pdf');

  @override
  Future<Uint8List> descargarXlsxDe(String usuarioId) => _descargar(usuarioId, 'xlsx');

  /// La ruta es la misma y sólo cambia la extensión; por eso el sufijo se pasa
  /// y no se repite la construcción de la URL. Escrita dos veces, la segunda
  /// acabaría con un segmento de menos.
  ///
  /// El archivo viaja binario, así que se usa [ApiClient.getBytes] y no `get`:
  /// el cuerpo no es JSON y `_procesar` intentaría decodificarlo. El error sí
  /// viene como JSON y `getBytes` lo rescata para no inventar un mensaje.
  Future<Uint8List> _descargar(String usuarioId, String formato) {
    return _api.getBytes(
      '/api/v1/inscripcion/planilla/$usuarioId/$formato',
      token: _tokenSesion,
    );
  }
}
