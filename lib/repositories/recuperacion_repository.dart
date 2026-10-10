import '../core/errors/app_exception.dart';
import '../core/gateways/recuperacion_gateway.dart';
import '../core/result.dart';
import '../models/recuperacion_password.dart';
import '../services/recuperacion_service.dart';

/// Repositorio del restablecimiento interno de contraseña.
///
/// La validación vive aquí y no en el widget: la regla es del dominio y así los
/// tests la cubren sin montar la interfaz. El repositorio **no guarda** el
/// código ni la contraseña en ningún sitio: los pasa al gateway y se olvida.
class RecuperacionRepository {
  RecuperacionRepository({RecuperacionGateway? gateway})
      : _gateway = gateway ?? BackendRecuperacionGateway();

  final RecuperacionGateway _gateway;

  /// Longitud mínima de la contraseña, la misma que exige el backend y que el
  /// resto del sistema. Duplicarla aquí no es deriva: es lo que permite dar el
  /// mensaje **sin** gastar una petición, y si divergiera, el backend seguiría
  /// siendo el que manda.
  static const int largoMinimoPassword = 8;

  /// Longitud mínima del código **normalizado**. El código real tiene 12
  /// caracteres; se acepta desde 8 para no rechazar por un dedazo un código que
  /// el backend quizá sí reconozca —quien decide de verdad es el backend—.
  static const int largoMinimoCodigo = 8;

  Future<Result<CodigoRecuperacion>> emitirCodigo(String usuarioId) {
    return Result.guard(() {
      if (usuarioId.trim().isEmpty) {
        throw const AppException.validacion(
          'No se pudo identificar al usuario que necesita el restablecimiento.',
        );
      }
      return _gateway.emitirCodigo(usuarioId);
    });
  }

  Future<Result<bool>> canjearCodigo({
    required String codigo,
    required String password,
  }) {
    return Result.guard(() async {
      // Misma normalización que el backend: quitar guiones y espacios y subir a
      // mayúsculas. El código lo teclea una persona que lo leyó de una pantalla o
      // lo recibió dictado, así que exigirle el formato exacto sería fricción sin
      // ninguna ganancia de seguridad.
      final limpio = codigo.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
      if (limpio.length < largoMinimoCodigo) {
        throw const AppException.validacion(
          'El código no es válido. Revisa que lo hayas escrito completo.',
        );
      }
      if (password.length < largoMinimoPassword) {
        throw const AppException.validacion(
          'La contraseña debe tener al menos 8 caracteres.',
        );
      }
      return _gateway.canjearCodigo(codigo: limpio, password: password);
    });
  }
}
