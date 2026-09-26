import 'dart:typed_data';

import '../core/gateways/planilla_gateway.dart';
import '../core/result.dart';
import '../models/inscripcion_campo.dart';
import '../services/planilla_service.dart';

/// Repositorio del catálogo de campos y de la planilla de inscripción.
///
/// Envuelve el gateway en [Result], igual que el resto de repositorios: un fallo
/// de red, de permisos o de validación llega con su `AppException`, y **no** se
/// convierte en una lista vacía. La diferencia importa aquí más que en ningún
/// sitio: un catálogo vacío y un catálogo que no se pudo leer producen la misma
/// pantalla —un formulario sin campos— y sólo el `Result` los distingue.
class PlanillaRepository {
  PlanillaRepository({PlanillaGateway? gateway})
      : _gateway = gateway ?? BackendPlanillaGateway();

  final PlanillaGateway _gateway;

  Future<Result<CatalogoInscripcion>> obtenerCatalogo() {
    return Result.guard(() => _gateway.campos());
  }

  Future<Result<PlanillaInscripcion>> guardar(PlanillaInscripcion planilla) {
    return Result.guard(() => _gateway.guardar(planilla));
  }

  /// Descarga la planilla del llamante como PDF.
  ///
  /// Igual que [guardar]: envuelve el gateway en [Result] para que un fallo de
  /// red, de permisos o de «sin ficha» llegue con su `AppException` y no se
  /// convierta en una lista vacía. El llamante —el servicio de PDF— es quien
  /// decide qué hacer con cada código.
  Future<Result<Uint8List>> descargarPdf() {
    return Result.guard(() => _gateway.descargarPdf());
  }
}
