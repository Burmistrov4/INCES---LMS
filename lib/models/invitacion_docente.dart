/// Respuesta de la invitación de un docente.
///
/// Es un objeto del dominio, no un `Response` de `http`, para que los tests
/// puedan simular el flujo sin depender del paquete de red.
class InvitacionDocente {
  final String email;
  final String expiraEn;
  final String enlaceActivacion;
  final bool correoEnviado;

  const InvitacionDocente({
    required this.email,
    required this.expiraEn,
    required this.enlaceActivacion,
    required this.correoEnviado,
  });

  factory InvitacionDocente.fromJson(Map<String, dynamic> json) {
    return InvitacionDocente(
      email: json['email'] as String,
      expiraEn: json['expiraEn'] as String,
      enlaceActivacion: json['enlaceActivacion'] as String,
      correoEnviado: json['correoEnviado'] as bool? ?? false,
    );
  }
}

/// Resultado de activar una invitación: la cuenta ya existe y es docente.
class ActivacionCuenta {
  final String email;
  final String rol;

  const ActivacionCuenta({required this.email, required this.rol});

  factory ActivacionCuenta.fromJson(Map<String, dynamic> json) {
    final perfil = json['perfil'] as Map<String, dynamic>? ?? {};
    return ActivacionCuenta(
      email: (json['email'] as String?) ?? (perfil['email'] as String? ?? ''),
      rol: (perfil['rol'] as String?) ?? 'docente',
    );
  }
}
