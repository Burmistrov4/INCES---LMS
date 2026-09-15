import '../../models/invitacion_docente.dart';

/// Contrato del flujo de invitación de docentes (Módulo 1).
///
/// Separa la fuente de datos (el backend Fastify) de la capa de aplicación.
/// Las implementaciones **lanzan** [AppException] en fallo; el repositorio las
/// envuelve en [Result]. Para los tests se inyecta un doble.
abstract interface class InvitacionGateway {
  /// Envía una invitación a un correo. Devuelve el enlace de activación, que la
  /// UI muestra cuando el correo no llega (Resend sin dominio verificado).
  ///
  /// [nombres] y [apellidos] son el nombre real del docente capturado por el
  /// administrador; viajan en `user_metadata` al activar para que el cuadrante
  /// muestre el nombre (R-21).
  Future<InvitacionDocente> invitarDocente(
    String email,
    String nombres,
    String apellidos,
  );

  /// Consume el token de invitación y crea la cuenta de docente con su contraseña.
  Future<ActivacionCuenta> activarCuenta({
    required String token,
    required String password,
  });
}
