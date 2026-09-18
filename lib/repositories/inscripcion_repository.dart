import '../core/gateways/inscripcion_gateway.dart';
import '../core/result.dart';
import '../models/inscripcion.dart';
import '../services/inscripcion_service.dart';

/// Repositorio de inscripciones del estudiante (Módulo 4).
///
/// Devuelve [Result]: la capa de datos lanza, aquí se captura. La UI consume
/// con `when(success: ..., failure: ...)`. La validación de la sección vive en
/// el dominio (este repositorio), no en el widget.
class InscripcionesRepository {
  InscripcionesRepository({InscripcionGateway? gateway})
      : _gateway = gateway ?? BackendInscripcionGateway();

  final InscripcionGateway _gateway;

  Future<Result<List<OcupacionSeccion>>> obtenerOfertas(
          {bool soloConCupo = false}) =>
      Result.guard(() => _gateway.obtenerOfertas(soloConCupo: soloConCupo));

  Future<Result<List<InscripcionDetallada>>> obtenerMisInscripciones() =>
      Result.guard(_gateway.obtenerMisInscripciones);

  Future<Result<EstadoInscripcion>> inscribirse(String seccionId) =>
      Result.guard(() => _gateway.inscribirse(seccionId));

  Future<Result<EstadoInscripcion>> renunciar(String seccionId) =>
      Result.guard(() => _gateway.renunciar(seccionId));

  Future<Result<EstadoInscripcion>> aceptarOferta(String seccionId) =>
      Result.guard(() => _gateway.aceptarOferta(seccionId));
}

/// Repositorio de inscripciones del administrador (Módulo 4).
class AdminInscripcionesRepository {
  AdminInscripcionesRepository({InscripcionGateway? gateway})
      : _gateway = gateway ?? BackendInscripcionGateway();

  final InscripcionGateway _gateway;

  Future<Result<List<OcupacionSeccion>>> obtenerOcupacion(
          {bool soloConCupo = false}) =>
      Result.guard(() => _gateway.obtenerOcupacion(soloConCupo: soloConCupo));

  /// `promovida: null` (cola vacía, llena o con oferta viva) se traduce a
  /// [Failure] con mensaje de validación: es un caso normal, no un error de
  /// red, y la UI lo muestra sin fingir un fallo técnico.
  Future<Result<InscripcionDetallada>> promoverSiguiente(String seccionId) =>
      Result.guard(() => _gateway.promoverSiguiente(seccionId));

  /// Idempotente: la segunda llamada devuelve 0 ofertas vencidas.
  Future<Result<int>> expirarOfertas() =>
      Result.guard(_gateway.expirarOfertas);

  Future<Result<EstadoInscripcion>> reincorporar({
    required String estudianteId,
    required String seccionId,
  }) =>
      Result.guard(
        () => _gateway.reincorporar(
          estudianteId: estudianteId,
          seccionId: seccionId,
        ),
      );
}
