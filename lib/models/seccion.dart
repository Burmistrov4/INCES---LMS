/// Modelo de una sección académica (Módulo 4: Inscripciones y Cupos).
///
/// Es el grupo de una materia en un lapso: lo que el estudiante elige. Una
/// clase del cuadrante es una franja semanal; una sección es el conjunto.
class Seccion {
  final String id;
  final String programaId;
  final String materiaId;
  final String periodo;

  /// Identificador corto dentro del lapso ("SA", "SC"). El nombre largo de la
  /// materia vive en `subjects.name`.
  final String nombre;

  /// Cupo declarado. `null` significa "usar el global del centro"
  /// (`cupo_maximo_por_seccion`); `0` es "sección sin cupo" y NO equivale a
  /// nulo: una sección con `0` cupo no acepta inscripciones, una con `null`
  /// cae al global.
  final int? cupoMaximo;

  /// `false` = archivada. No hay borrado: el `DELETE` está revocado en la
  /// base para no llevarse el historial de inscripciones por delante.
  final bool activa;

  final String? creadoEn;
  final String? actualizadoEn;

  const Seccion({
    required this.id,
    required this.programaId,
    required this.materiaId,
    required this.periodo,
    required this.nombre,
    required this.cupoMaximo,
    required this.activa,
    this.creadoEn,
    this.actualizadoEn,
  });

  factory Seccion.fromJson(Map<String, dynamic> json) => Seccion(
        id: json['id'] as String,
        programaId: json['programaId'] as String,
        materiaId: json['materiaId'] as String,
        periodo: json['periodo'] as String,
        nombre: json['nombre'] as String,
        cupoMaximo: json['cupoMaximo'] as int?,
        activa: json['activa'] as bool? ?? false,
        creadoEn: json['creadoEn'] as String?,
        actualizadoEn: json['actualizadoEn'] as String?,
      );

  /// Constructor para peticiones de creación. Sólo lo que el cliente envía;
  /// el resto lo rellena la base.
  factory Seccion.crear({
    required String programaId,
    required String materiaId,
    required String periodo,
    required String nombre,
    int? cupoMaximo,
  }) =>
      Seccion(
        id: '',
        programaId: programaId,
        materiaId: materiaId,
        periodo: periodo,
        nombre: nombre,
        cupoMaximo: cupoMaximo,
        activa: true,
      );
}

/// Página de secciones con metadatos de paginación.
class PaginaSecciones {
  final List<Seccion> secciones;
  final int total;
  final int limite;
  final int desplazamiento;

  const PaginaSecciones({
    required this.secciones,
    required this.total,
    required this.limite,
    required this.desplazamiento,
  });
}

/// Cambios admitidos por el backend al archivar/renombrar/recapacitar una
/// sección. Ningún campo toca la identidad (`programaId`, `materiaId`,
/// `periodo`): cambiarlos equivaldría a un borrado encubierto.
class CambiosSeccion {
  final String? nombre;
  final int? cupoMaximo;
  final bool? activa;
  final bool vaciarCupoMaximo;

  const CambiosSeccion({
    this.nombre,
    this.cupoMaximo,
    this.activa,
    this.vaciarCupoMaximo = false,
  });

  Map<String, dynamic> toJson() {
    final cuerpo = <String, dynamic>{};
    if (nombre != null) cuerpo['nombre'] = nombre;
    if (cupoMaximo != null) cuerpo['cupoMaximo'] = cupoMaximo;
    if (vaciarCupoMaximo) cuerpo['cupoMaximo'] = null;
    if (activa != null) cuerpo['activa'] = activa;
    return cuerpo;
  }
}