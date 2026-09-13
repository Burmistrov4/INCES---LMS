/// Parámetro de configuración editable desde el cPanel.
///
/// Ejemplos: `max_faltas_consecutivas`, `enrollment_lock_days`,
/// `r2_presign_ttl_minutos`, `periodo_activo`.
class SystemSetting {
  final String clave;

  /// Valor en JSON. Puede ser numérico, booleano, texto u objeto.
  final Object? valor;

  /// `number` | `boolean` | `string` | `json`
  final String tipo;

  final String? descripcion;
  final String categoria;

  /// Si es `true`, el frontend puede leerlo sin ser administrador.
  final bool esPublico;

  final DateTime? updatedAt;

  const SystemSetting({
    required this.clave,
    required this.valor,
    this.tipo = 'string',
    this.descripcion,
    this.categoria = 'general',
    this.esPublico = false,
    this.updatedAt,
  });

  factory SystemSetting.fromJson(Map<String, dynamic> json) {
    return SystemSetting(
      clave: json['clave'] as String? ?? '',
      valor: json['valor'],
      tipo: json['tipo'] as String? ?? 'string',
      descripcion: json['descripcion'] as String?,
      categoria: json['categoria'] as String? ?? 'general',
      esPublico: json['es_publico'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clave': clave,
      'valor': valor,
      'tipo': tipo,
      'descripcion': descripcion,
      'categoria': categoria,
      'es_publico': esPublico,
    };
  }

  // --- Accesos tipados: evitan castear `valor` en cada punto de uso ---------

  int? get comoEntero {
    final v = valor;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? get comoDecimal {
    final v = valor;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool? get comoBooleano {
    final v = valor;
    if (v is bool) return v;
    if (v is String) {
      if (v.toLowerCase() == 'true') return true;
      if (v.toLowerCase() == 'false') return false;
    }
    return null;
  }

  String get comoTexto => valor?.toString() ?? '';

  SystemSetting copyWith({
    Object? valor,
    String? tipo,
    String? descripcion,
    String? categoria,
    bool? esPublico,
    DateTime? updatedAt,
  }) {
    return SystemSetting(
      clave: clave,
      valor: valor ?? this.valor,
      tipo: tipo ?? this.tipo,
      descripcion: descripcion ?? this.descripcion,
      categoria: categoria ?? this.categoria,
      esPublico: esPublico ?? this.esPublico,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'SystemSetting($clave = $valor)';
}
