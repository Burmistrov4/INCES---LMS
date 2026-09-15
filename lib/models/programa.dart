/// Programa académico (Módulo 2).
///
/// El backend entrega las claves en `camelCase` y en español —es su contrato de
/// dominio—, así que aquí no hay traducción de `snake_case` como en los modelos
/// que hablan directo con Supabase. La traducción ocurre en un solo sitio: la
/// capa de repositorio del backend.
library;

/// Tipo de programa.
///
/// La distinción no es cosmética: una `CARRERA` activa no puede quedarse sin
/// materias —el constraint trigger diferido la rechaza—, mientras que un
/// `CURSO_LIBRE` normalmente tiene un solo período.
enum TipoPrograma {
  carrera,
  cursoLibre;

  String get etiqueta => switch (this) {
        TipoPrograma.carrera => 'Carrera',
        TipoPrograma.cursoLibre => 'Curso libre',
      };

  /// Valor que espera el backend en el cuerpo y en la consulta.
  String get valorApi => switch (this) {
        TipoPrograma.carrera => 'CARRERA',
        TipoPrograma.cursoLibre => 'CURSO_LIBRE',
      };

  /// Interpreta el valor del backend.
  ///
  /// Un valor desconocido se trata como `carrera`, que es el **más restrictivo**
  /// de los dos: mostrar la insignia de carrera ante un dato raro hace que la
  /// interfaz exija un pensum completo, en lugar de relajar la validación por
  /// haber recibido algo que no se entendió.
  static TipoPrograma desdeApi(String? crudo) =>
      crudo == 'CURSO_LIBRE' ? TipoPrograma.cursoLibre : TipoPrograma.carrera;
}

/// Un programa académico, sin sus totales.
class Programa {
  const Programa({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.requierePasantia,
    required this.activo,
    this.creadoEn,
    this.actualizadoEn,
  });

  final String id;

  /// Identidad del programa. **No se puede cambiar**: cualquier documento
  /// impreso que lo cite quedaría descolgado.
  final String codigo;

  final String nombre;
  final TipoPrograma tipo;
  final bool requierePasantia;
  final bool activo;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  factory Programa.fromJson(Map<String, dynamic> json) {
    return Programa(
      id: json['id'] as String? ?? '',
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      tipo: TipoPrograma.desdeApi(json['tipo'] as String?),
      requierePasantia: json['requierePasantia'] as bool? ?? false,
      activo: json['activo'] as bool? ?? false,
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      actualizadoEn: DateTime.tryParse(json['actualizadoEn']?.toString() ?? ''),
    );
  }

  @override
  String toString() => 'Programa($codigo, ${tipo.name}, activo: $activo)';
}

/// Un programa con el tamaño de su pensum.
///
/// Los dos totales viajan en la misma consulta que la página, no en N+1
/// peticiones: la pantalla necesita saber si un programa está vacío para avisar
/// **antes** de que el administrador intente publicarlo y choque con el 400 del
/// trigger.
class ProgramaConTotales extends Programa {
  const ProgramaConTotales({
    required super.id,
    required super.codigo,
    required super.nombre,
    required super.tipo,
    required super.requierePasantia,
    required super.activo,
    required this.totalMaterias,
    required this.totalPeriodos,
    super.creadoEn,
    super.actualizadoEn,
  });

  final int totalMaterias;
  final int totalPeriodos;

  /// Un programa sin materias no se puede activar.
  bool get estaVacio => totalMaterias == 0;

  factory ProgramaConTotales.fromJson(Map<String, dynamic> json) {
    final base = Programa.fromJson(json);
    return ProgramaConTotales(
      id: base.id,
      codigo: base.codigo,
      nombre: base.nombre,
      tipo: base.tipo,
      requierePasantia: base.requierePasantia,
      activo: base.activo,
      totalMaterias: json['totalMaterias'] as int? ?? 0,
      totalPeriodos: json['totalPeriodos'] as int? ?? 0,
      creadoEn: base.creadoEn,
      actualizadoEn: base.actualizadoEn,
    );
  }
}

/// Una página del listado de programas, con el total que cumple el filtro.
///
/// El total viaja junto a las filas porque sin él la pantalla no puede decir
/// «1 a 25 de 12» ni saber si queda una página más.
class PaginaProgramas {
  const PaginaProgramas({required this.programas, required this.total});

  final List<ProgramaConTotales> programas;
  final int total;

  bool get vacia => programas.isEmpty;
}
