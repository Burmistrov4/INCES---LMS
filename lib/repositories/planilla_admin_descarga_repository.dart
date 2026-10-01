import 'dart:typed_data';

import '../core/gateways/planilla_admin_descarga_gateway.dart';
import '../core/result.dart';
import '../services/backend_planilla_admin_descarga_gateway.dart';

/// Repositorio de la descarga de la planilla de otro aspirante.
///
/// Envuelve el gateway en [Result] como el resto de repositorios, y aquí la
/// distinción vuelve a importar: «esa persona no tiene ficha» y «no se pudo
/// consultar» producen las dos la misma pantalla —ningún archivo— y sólo el
/// `Result` las separa. El llamante —el servicio de PDF— es quien decide qué
/// hacer con cada código.
class PlanillaAdminDescargaRepository {
  PlanillaAdminDescargaRepository({PlanillaAdminDescargaGateway? gateway})
      : _gateway = gateway ?? BackendPlanillaAdminDescargaGateway();

  final PlanillaAdminDescargaGateway _gateway;

  /// Descarga el PDF de la planilla de [usuarioId].
  ///
  /// Igual que `PlanillaRepository.descargarPdf`: un fallo de red, de permisos o
  /// de «sin ficha» llega con su `AppException` y **no** se convierte en una
  /// lista vacía.
  Future<Result<Uint8List>> descargarPdfDe(String usuarioId) {
    return Result.guard(() => _gateway.descargarPdfDe(usuarioId));
  }

  /// La misma planilla, en `.xlsx` editable.
  ///
  /// Igual que [descargarPdfDe]: un fallo de red, de permisos o de «sin ficha»
  /// llega con su `AppException`, no como una lista vacía.
  Future<Result<Uint8List>> descargarXlsxDe(String usuarioId) {
    return Result.guard(() => _gateway.descargarXlsxDe(usuarioId));
  }
}
