/// Modelos del restablecimiento interno de contraseña.
///
/// El código en claro sólo existe en la respuesta que el backend devuelve **una
/// vez** al administrador. No se guarda en el cliente, no se registra y no se
/// envía por correo: el administrador lo lee de la pantalla y lo entrega por el
/// canal institucional que corresponda.
library;

/// Código temporal recién emitido para un usuario.
class CodigoRecuperacion {
  /// Correo del usuario al que pertenece el código, para que el administrador
  /// confirme a quién se lo está entregando.
  final String email;

  /// El código en claro. **Se muestra una sola vez.**
  final String codigo;

  /// Instante ISO en que caduca (30 minutos desde la emisión).
  final String expiraEn;

  /// Cómo debe entregarse. Hoy siempre `manual`: por el canal institucional.
  final String entrega;

  const CodigoRecuperacion({
    required this.email,
    required this.codigo,
    required this.expiraEn,
    required this.entrega,
  });

  factory CodigoRecuperacion.fromJson(Map<String, dynamic> json) {
    return CodigoRecuperacion(
      email: (json['email'] as String?) ?? '',
      codigo: (json['codigo'] as String?) ?? '',
      expiraEn: (json['expiraEn'] as String?) ?? '',
      entrega: (json['entrega'] as String?) ?? 'manual',
    );
  }
}
