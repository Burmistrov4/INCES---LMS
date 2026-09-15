import '../core/errors/app_exception.dart';
import '../core/gateways/invitacion_gateway.dart';
import '../core/result.dart';
import '../models/invitacion_docente.dart';
import '../services/invitacion_service.dart';

/// Repositorio del flujo de invitación de docentes (Módulo 1).
///
/// Devuelve [Result]: la capa de datos lanza, aquí se captura. La validación de
/// correo vive en el dominio (este repositorio), no en el widget, para que los
/// tests la cubran sin montar la interfaz.
class InvitacionRepository {
  InvitacionRepository({InvitacionGateway? gateway})
      : _gateway = gateway ?? BackendInvitacionGateway();

  final InvitacionGateway _gateway;

  static final RegExp _patronEmail = RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$');

  Future<Result<InvitacionDocente>> invitarDocente(
    String email,
    String nombres,
    String apellidos,
  ) {
    return Result.guard(() async {
      final correo = email.trim();
      if (correo.isEmpty) {
        throw const AppException.validacion('Ingresa el correo del docente.');
      }
      if (!_patronEmail.hasMatch(correo)) {
        throw const AppException.validacion(
          'El correo no tiene un formato válido.',
        );
      }
      final nombresLimpios = nombres.trim();
      final apellidosLimpios = apellidos.trim();
      if (nombresLimpios.isEmpty) {
        throw const AppException.validacion('Ingresa el nombre del docente.');
      }
      if (apellidosLimpios.isEmpty) {
        throw const AppException.validacion('Ingresa los apellidos del docente.');
      }
      return _gateway.invitarDocente(correo, nombresLimpios, apellidosLimpios);
    });
  }

  Future<Result<ActivacionCuenta>> activarCuenta({
    required String token,
    required String password,
  }) {
    return Result.guard(
      () => _gateway.activarCuenta(token: token, password: password),
    );
  }
}
