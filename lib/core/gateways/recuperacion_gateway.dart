import '../../models/recuperacion_password.dart';

/// Contrato del **restablecimiento interno de contraseña**.
///
/// La decisión de producto es que recuperar una cuenta no dependa de un
/// proveedor de correo: un administrador autorizado verifica la identidad por el
/// procedimiento institucional, emite un código temporal y lo entrega por el
/// canal aprobado; el titular lo canjea y fija su propia contraseña.
///
/// Las implementaciones **lanzan** [AppException] en fallo; el repositorio las
/// envuelve en [Result]. Para los tests se inyecta un doble.
abstract interface class RecuperacionGateway {
  /// Emite un código de un solo uso para el usuario indicado.
  ///
  /// Requiere sesión de administrador: el backend valida el rol. El código en
  /// claro sólo viene en esta respuesta y **no se vuelve a poder consultar**.
  Future<CodigoRecuperacion> emitirCodigo(String usuarioId);

  /// Canjea el código y fija la contraseña nueva. Ruta pública: quien olvidó su
  /// contraseña no tiene sesión con la que autenticarse.
  ///
  /// El backend normaliza el código, así que se puede enviar tal cual lo teclee
  /// el usuario.
  Future<bool> canjearCodigo({required String codigo, required String password});
}
