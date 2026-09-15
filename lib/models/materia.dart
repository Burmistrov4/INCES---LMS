/// Materia del banco global (Módulo 2).
///
/// Las materias viven en `subjects` y las **comparten varios pensums**. Por eso
/// el cliente nunca manda el nombre de una materia al reemplazar un pensum: si
/// pudiera, un cambio de pensum reescribiría una materia que otros programas
/// están usando, sin que nadie lo hubiera pedido.
library;

class Materia {
  const Materia({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.horasAcademicas,
    this.creadoEn,
    this.actualizadoEn,
  });

  final String id;
  final String codigo;
  final String nombre;

  /// Horas académicas del período. Siempre mayor que cero.
  final int horasAcademicas;

  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  factory Materia.fromJson(Map<String, dynamic> json) {
    return Materia(
      id: json['id'] as String? ?? '',
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      horasAcademicas: json['horasAcademicas'] as int? ?? 0,
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      actualizadoEn: DateTime.tryParse(json['actualizadoEn']?.toString() ?? ''),
    );
  }

  @override
  String toString() => 'Materia($codigo, $horasAcademicas h)';
}

/// Una página del banco de materias, con el total que cumple el filtro.
class PaginaMaterias {
  const PaginaMaterias({required this.materias, required this.total});

  final List<Materia> materias;
  final int total;

  bool get vacia => materias.isEmpty;
}
