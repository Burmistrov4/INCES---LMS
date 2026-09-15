/// Pensum de un programa: qué materias y en qué período (Módulo 2).
///
/// La distinción entre [EntradaPensum] y [MateriaEnPensum] es deliberada y
/// viene del contrato del backend: al **enviar** un pensum sólo se mandan
/// identificadores y períodos; al **recibir** llegan además el código, el nombre
/// y las horas. Si fueran el mismo tipo, el cliente podría mandar el nombre de
/// una materia compartida y reescribirlo sin querer.
library;

import 'programa.dart';

/// Una materia dentro de un pensum, tal como se **envía**.
class EntradaPensum {
  const EntradaPensum({required this.materiaId, this.periodo = 1});

  final String materiaId;

  /// Período al que pertenece. Siempre mayor o igual que 1.
  final int periodo;

  EntradaPensum conPeriodo(int nuevoPeriodo) =>
      EntradaPensum(materiaId: materiaId, periodo: nuevoPeriodo);

  Map<String, dynamic> toJson() => {
        'materiaId': materiaId,
        'periodo': periodo,
      };

  @override
  String toString() => 'EntradaPensum($materiaId, período $periodo)';
}

/// Una materia dentro de un pensum, tal como se **recibe**: con sus datos.
class MateriaEnPensum extends EntradaPensum {
  const MateriaEnPensum({
    required super.materiaId,
    required super.periodo,
    required this.codigo,
    required this.nombre,
    required this.horasAcademicas,
  });

  final String codigo;
  final String nombre;
  final int horasAcademicas;

  factory MateriaEnPensum.fromJson(Map<String, dynamic> json) {
    return MateriaEnPensum(
      materiaId: json['materiaId'] as String? ?? '',
      periodo: json['periodo'] as int? ?? 1,
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      horasAcademicas: json['horasAcademicas'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'MateriaEnPensum($codigo, período $periodo)';
}

/// Un período del pensum con sus materias.
///
/// Es genérico para que la misma agrupación sirva al pensum que se manda (sólo
/// identificadores) y al que se recibe (con datos), sin duplicar la lógica ni
/// perder los campos extra.
class GrupoPensum<T extends EntradaPensum> {
  const GrupoPensum({required this.periodo, required this.materias});

  final int periodo;
  final List<T> materias;

  int get totalMaterias => materias.length;

  /// Suma de horas académicas del período. Cero cuando las entradas no traen
  /// horas, que es el caso del pensum que se está construyendo en el asistente.
  int get totalHoras =>
      materias.fold(0, (suma, materia) => suma + _horasDe(materia));

  static int _horasDe(EntradaPensum materia) =>
      materia is MateriaEnPensum ? materia.horasAcademicas : 0;
}

/// El detalle completo de un programa.
///
/// `editable` es la materialización de la **Regla 2** del backend: es `false`
/// cuando hay secciones activas del período vigente usando el programa. La UI
/// deshabilita el reordenamiento antes de que el usuario lo intente, en vez de
/// dejarlo chocar contra el `409`.
class DetallePrograma {
  const DetallePrograma({
    required this.programa,
    required this.pensum,
    required this.seccionesActivas,
    required this.editable,
  });

  final Programa programa;
  final List<GrupoPensum<MateriaEnPensum>> pensum;
  final int seccionesActivas;
  final bool editable;

  int get totalMaterias =>
      pensum.fold(0, (suma, grupo) => suma + grupo.totalMaterias);

  int get totalPeriodos => pensum.length;

  int get totalHoras =>
      pensum.fold(0, (suma, grupo) => suma + grupo.totalHoras);

  /// El pensum como entradas simples, para reenviarlo tal cual al reemplazar.
  List<EntradaPensum> get entradas => [
        for (final grupo in pensum)
          for (final materia in grupo.materias)
            EntradaPensum(materiaId: materia.materiaId, periodo: materia.periodo),
      ];

  factory DetallePrograma.fromJson(Map<String, dynamic> json) {
    final crudo = json['pensum'] as List<dynamic>? ?? const <dynamic>[];

    final grupos = <GrupoPensum<MateriaEnPensum>>[];
    for (final elemento in crudo) {
      if (elemento is! Map<String, dynamic>) continue;
      final materias = (elemento['materias'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MateriaEnPensum.fromJson)
          .toList();
      grupos.add(
        GrupoPensum<MateriaEnPensum>(
          periodo: elemento['periodo'] as int? ?? 1,
          materias: materias,
        ),
      );
    }

    return DetallePrograma(
      programa: Programa.fromJson(
        json['programa'] as Map<String, dynamic>? ?? const {},
      ),
      pensum: grupos,
      seccionesActivas: json['seccionesActivas'] as int? ?? 0,
      editable: json['editable'] as bool? ?? true,
    );
  }

  @override
  String toString() =>
      'DetallePrograma(${programa.codigo}, $totalMaterias materias, '
      'editable: $editable)';
}
