/// Registro de auditoría de cambios en la configuración del sistema.
///
/// Responde a "¿quién apagó este módulo y cuándo?". Sin esto, el Poder del
/// Administrador Maestro sería un agujero: nadie podría reconstruir por qué el
/// sistema se comporta distinto.
class ConfigAuditEntry {
  final String id;

  /// Tabla afectada: `system_modules` o `system_settings`.
  final String tabla;

  final String clave;
  final Object? valorAnterior;
  final Object? valorNuevo;
  final String? usuarioEmail;
  final DateTime? creadoEn;

  const ConfigAuditEntry({
    required this.id,
    required this.tabla,
    required this.clave,
    this.valorAnterior,
    this.valorNuevo,
    this.usuarioEmail,
    this.creadoEn,
  });

  factory ConfigAuditEntry.fromJson(Map<String, dynamic> json) {
    return ConfigAuditEntry(
      id: json['id'] as String? ?? '',
      tabla: json['tabla'] as String? ?? '',
      clave: json['clave'] as String? ?? '',
      valorAnterior: json['valor_anterior'],
      valorNuevo: json['valor_nuevo'],
      usuarioEmail: json['usuario_email'] as String?,
      creadoEn: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  /// Describe el cambio de forma legible para el cPanel.
  String get descripcionCorta {
    final antes = _resumir(valorAnterior);
    final despues = _resumir(valorNuevo);
    return '$clave: $antes → $despues';
  }

  static String _resumir(Object? valor) {
    if (valor == null) return '—';
    if (valor is Map) {
      // Para módulos, mostramos sólo el interruptor si está presente.
      final habilitado = valor['habilitado'];
      if (habilitado is bool) return habilitado ? 'activo' : 'inactivo';
    }
    final texto = valor.toString();
    return texto.length > 40 ? '${texto.substring(0, 37)}...' : texto;
  }

  @override
  String toString() => 'ConfigAuditEntry($tabla.$clave)';
}
