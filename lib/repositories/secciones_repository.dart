import '../core/gateways/secciones_gateway.dart';
import '../core/result.dart';
import '../models/seccion.dart';
import '../services/secciones_service.dart';

/// Repositorio de secciones del administrador (Módulo 4).
///
/// Mismo reparto que `AdminInscripcionesRepository`: el gateway lanza, este
/// repositorio captura y entrega `Result`. La UI consume con `when`.
class SeccionesRepository {
  SeccionesRepository({SeccionesGateway? gateway})
      : _gateway = gateway ?? BackendSeccionesGateway();

  final SeccionesGateway _gateway;

  Future<Result<PaginaSecciones>> listarSecciones({
    bool soloActivas = false,
    int limite = 50,
    int desplazamiento = 0,
  }) =>
      Result.guard(() => _gateway.listarSecciones(
            soloActivas: soloActivas,
            limite: limite,
            desplazamiento: desplazamiento,
          ));

  Future<Result<Seccion>> crearSeccion(Seccion borrador) =>
      Result.guard(() => _gateway.crearSeccion(borrador));

  Future<Result<Seccion>> actualizarSeccion(
          String id, CambiosSeccion cambios) =>
      Result.guard(() => _gateway.actualizarSeccion(id, cambios));
}