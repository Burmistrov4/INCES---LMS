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

/// Estado de una invitación, tal como lo resuelve el **dominio del backend**.
///
/// El cliente no lo deduce: lo recibe calculado. Así el panel no puede pintar un
/// estado distinto del que decide el endpoint de activación, que es la única
/// fuente de verdad sobre si un enlace sirve o no.
enum EstadoInvitacion {
  valida,
  usada,
  expirada,
  revocada,
  desconocido;

  static EstadoInvitacion desde(String? valor) {
    return switch (valor) {
      'valida' => EstadoInvitacion.valida,
      'usada' => EstadoInvitacion.usada,
      'expirada' => EstadoInvitacion.expirada,
      'revocada' => EstadoInvitacion.revocada,
      _ => EstadoInvitacion.desconocido,
    };
  }

  /// Etiqueta para el panel, en el idioma del usuario.
  String get etiqueta => switch (this) {
        EstadoInvitacion.valida => 'Pendiente de entrega',
        EstadoInvitacion.usada => 'Activada',
        EstadoInvitacion.expirada => 'Caducada',
        EstadoInvitacion.revocada => 'Revocada',
        EstadoInvitacion.desconocido => 'Desconocido',
      };

  /// Si el enlace todavía sirve. Sólo una invitación válida se puede entregar.
  bool get sirve => this == EstadoInvitacion.valida;
}

/// Una invitación en el listado del cPanel, con su estado ya resuelto.
class InvitacionListada {
  final String id;
  final String email;
  final String nombres;
  final String apellidos;
  final bool isUsed;
  final String createdAt;
  final String expiresAt;
  final String? revokedAt;
  final EstadoInvitacion estado;

  const InvitacionListada({
    required this.id,
    required this.email,
    required this.nombres,
    required this.apellidos,
    required this.isUsed,
    required this.createdAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.estado,
  });

  String get nombreCompleto {
    final n = '$nombres $apellidos'.trim();
    return n.isEmpty ? email : n;
  }

  factory InvitacionListada.fromJson(Map<String, dynamic> json) {
    return InvitacionListada(
      id: (json['id'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      nombres: (json['nombres'] as String?) ?? '',
      apellidos: (json['apellidos'] as String?) ?? '',
      isUsed: (json['isUsed'] as bool?) ?? false,
      createdAt: (json['createdAt'] as String?) ?? '',
      expiresAt: (json['expiresAt'] as String?) ?? '',
      revokedAt: json['revokedAt'] as String?,
      estado: EstadoInvitacion.desde(json['estado'] as String?),
    );
  }
}
