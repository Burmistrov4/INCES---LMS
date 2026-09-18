import '../../models/inscripcion.dart';

/// Contrato de la capa de datos del Módulo 4 (Inscripciones y Cupos).
///
/// Separa la fuente (el backend Fastify) de la capa de aplicación. Las
/// implementaciones **lanzan** [AppException]; el repositorio las envuelve en
/// [Result].
abstract interface class InscripcionGateway {
  /// Catálogo de ofertas del estudiante.
  Future<List<OcupacionSeccion>> obtenerOfertas({bool soloConCupo = false});

  /// Inscripciones del estudiante autenticado, con contexto de sección.
  Future<List<InscripcionDetallada>> obtenerMisInscripciones();

  /// Solicita un asiento en una sección (entra o queda en cola).
  Future<EstadoInscripcion> inscribirse(String seccionId);

  /// Renuncia al asiento (o a la cola) de una sección.
  Future<EstadoInscripcion> renunciar(String seccionId);

  /// Acepta la oferta de cupo en el aire para una sección.
  Future<EstadoInscripcion> aceptarOferta(String seccionId);

  /// Panel de ocupación del administrador.
  Future<List<OcupacionSeccion>> obtenerOcupacion({bool soloConCupo = false});

  /// Promueve manualmente al siguiente de la cola (override tras ampliar cupo).
  Future<InscripcionDetallada> promoverSiguiente(String seccionId);

  /// Vence las ofertas caducadas (idempotente). Devuelve cuántas vencieron.
  Future<int> expirarOfertas();

  /// Reincorpora a un estudiante dado de baja (puede exceder la capacidad).
  Future<EstadoInscripcion> reincorporar({
    required String estudianteId,
    required String seccionId,
  });
}
