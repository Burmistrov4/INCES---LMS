/// Entrada de la traza de accesos (tabla `auth_logs`).
///
/// Responde a «¿quién entró, desde qué IP y con qué resultado?». Sin esto, un
/// intento de acceso con una contraseña ajena no dejaría rastro investigable:
/// el administrador sólo sabría que «alguien intentó entrar» cuando el afectado
/// se lo contara.
///
/// El backend ya entrega las claves en `camelCase` (es su contrato de dominio),
/// así que aquí no hay que traducir de `snake_case` como en otros modelos.
enum EstadoAcceso { exito, fallo }

extension EstadoAccesoX on EstadoAcceso {
  String get etiqueta => switch (this) {
        EstadoAcceso.exito => 'Exitoso',
        EstadoAcceso.fallo => 'Fallido',
      };

  /// Valor que espera el backend en el parámetro `estado` de la consulta.
  String get valorApi => switch (this) {
        EstadoAcceso.exito => 'SUCCESS',
        EstadoAcceso.fallo => 'FAILED',
      };
}

class EntradaAcceso {
  const EntradaAcceso({
    required this.id,
    required this.estado,
    this.userId,
    this.email,
    this.ip,
    this.creadoEn,
  });

  final String id;

  /// Identificador de la cuenta. `null` cuando el intento fue de un correo que
  /// no tiene cuenta: justo el caso que más interesa auditar.
  final String? userId;

  final String? email;
  final String? ip;
  final EstadoAcceso estado;
  final DateTime? creadoEn;

  factory EntradaAcceso.fromJson(Map<String, dynamic> json) {
    // Un valor desconocido se trata como éxito: degradar a lo benigno mantiene
    // la pantalla usable. Reventar aquí tiraría el panel entero por una fila.
    final crudo = json['estado'] as String?;
    return EntradaAcceso(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String?,
      email: json['email'] as String?,
      ip: json['ip'] as String?,
      estado: crudo == 'FAILED' ? EstadoAcceso.fallo : EstadoAcceso.exito,
      creadoEn: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  bool get fueExitoso => estado == EstadoAcceso.exito;

  /// Quién protagonizó el intento, para cuando el correo llegó nulo.
  String get actor => email ?? userId ?? 'desconocido';

  @override
  String toString() => 'EntradaAcceso($actor, ${estado.name})';
}

/// Una página de la traza, con el total que cumple el filtro.
///
/// El total viaja junto a las filas porque sin él la pantalla no puede decir
/// «1 a 25 de 340» ni saber cuántas páginas quedan.
class PaginaAcceso {
  const PaginaAcceso({required this.entradas, required this.total});

  final List<EntradaAcceso> entradas;
  final int total;
}
