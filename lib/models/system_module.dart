/// Módulo funcional del sistema, controlable desde el cPanel.
///
/// Es la pieza central del "Poder Absoluto del Administrador Maestro": el
/// interruptor `habilitado` decide si el módulo existe para el resto del
/// sistema, tanto en la API como en el frontend.
class SystemModule {
  /// Identificador estable. No se renombra: la API y el frontend lo referencian.
  final String clave;

  final String nombre;
  final String? descripcion;
  final bool habilitado;
  final int orden;
  final String? icono;

  /// Roles que pueden ver el módulo. Lista vacía = todos los roles.
  final List<String> rolesPermitidos;

  final String categoria;
  final DateTime? updatedAt;

  const SystemModule({
    required this.clave,
    required this.nombre,
    this.descripcion,
    required this.habilitado,
    this.orden = 0,
    this.icono,
    this.rolesPermitidos = const [],
    this.categoria = 'general',
    this.updatedAt,
  });

  factory SystemModule.fromJson(Map<String, dynamic> json) {
    final roles = json['roles_permitidos'];

    return SystemModule(
      clave: json['clave'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      descripcion: json['descripcion'] as String?,
      habilitado: json['habilitado'] as bool? ?? false,
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      icono: json['icono'] as String?,
      rolesPermitidos: roles is List
          ? roles.map((r) => r.toString()).toList(growable: false)
          : const [],
      categoria: json['categoria'] as String? ?? 'general',
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clave': clave,
      'nombre': nombre,
      'descripcion': descripcion,
      'habilitado': habilitado,
      'orden': orden,
      'icono': icono,
      'roles_permitidos': rolesPermitidos,
      'categoria': categoria,
    };
  }

  /// ¿Este rol puede ver el módulo?
  bool permiteRol(String rol) =>
      rolesPermitidos.isEmpty || rolesPermitidos.contains(rol);

  SystemModule copyWith({
    String? nombre,
    String? descripcion,
    bool? habilitado,
    int? orden,
    String? icono,
    List<String>? rolesPermitidos,
    String? categoria,
    DateTime? updatedAt,
  }) {
    return SystemModule(
      clave: clave,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      habilitado: habilitado ?? this.habilitado,
      orden: orden ?? this.orden,
      icono: icono ?? this.icono,
      rolesPermitidos: rolesPermitidos ?? this.rolesPermitidos,
      categoria: categoria ?? this.categoria,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'SystemModule($clave, habilitado: $habilitado)';
}
