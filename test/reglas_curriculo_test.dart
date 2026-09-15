import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/reglas_curriculo.dart';
import 'package:inces_lms_app/models/pensum.dart';

void main() {
  group('agruparPensum', () {
    test('agrupa por período y los ordena', () {
      final grupos = agruparPensum(const [
        EntradaPensum(materiaId: 'c', periodo: 4),
        EntradaPensum(materiaId: 'a', periodo: 1),
        EntradaPensum(materiaId: 'b', periodo: 1),
      ]);

      expect(grupos.map((g) => g.periodo), [1, 4]);
      expect(grupos.first.materias.map((m) => m.materiaId), ['a', 'b']);
      expect(grupos.last.materias.map((m) => m.materiaId), ['c']);
    });

    test('no rellena los períodos que faltan', () {
      // El caso que importa: 1, 2 y 5 son TRES grupos, no cinco con dos vacíos.
      // Un período sin materias no es un dato, es una ausencia, y rellenarlo
      // obligaría a la interfaz a decidir si es un error o una intención.
      final grupos = agruparPensum(const [
        EntradaPensum(materiaId: 'a', periodo: 1),
        EntradaPensum(materiaId: 'b', periodo: 2),
        EntradaPensum(materiaId: 'c', periodo: 5),
      ]);

      expect(grupos, hasLength(3));
      expect(grupos.map((g) => g.periodo), [1, 2, 5]);
      expect(grupos.every((g) => g.materias.isNotEmpty), isTrue);
    });

    test('un curso libre con un solo período devuelve un solo grupo', () {
      final grupos = agruparPensum(const [
        EntradaPensum(materiaId: 'a', periodo: 1),
        EntradaPensum(materiaId: 'b', periodo: 1),
      ]);

      expect(grupos, hasLength(1));
      expect(grupos.single.totalMaterias, 2);
    });

    test('un pensum vacío devuelve una lista vacía', () {
      expect(agruparPensum(const <EntradaPensum>[]), isEmpty);
    });

    test('conserva los campos extra del tipo enriquecido', () {
      // El genérico existe para esto: la misma agrupación sirve al pensum que se
      // manda (sólo identificadores) y al que se recibe (con código y horas).
      final grupos = agruparPensum(const [
        MateriaEnPensum(
          materiaId: 'a',
          periodo: 1,
          codigo: 'ALG-I',
          nombre: 'Algorítmica',
          horasAcademicas: 96,
        ),
      ]);

      expect(grupos.single.materias.single.codigo, 'ALG-I');
      expect(grupos.single.totalHoras, 96);
    });

    test('las horas suman cero cuando las entradas no las traen', () {
      final grupos = agruparPensum(const [
        EntradaPensum(materiaId: 'a', periodo: 1),
      ]);

      expect(grupos.single.totalHoras, 0);
    });
  });

  group('materiaRepetida', () {
    test('devuelve el identificador de la repetida, no un booleano', () {
      // Devuelve el identificador para que el mensaje pueda nombrar la materia:
      // «hay una repetida» obliga a buscarla a mano en un pensum de treinta
      // líneas.
      final repetida = materiaRepetida(const [
        EntradaPensum(materiaId: 'a', periodo: 1),
        EntradaPensum(materiaId: 'b', periodo: 2),
        EntradaPensum(materiaId: 'a', periodo: 3),
      ]);

      expect(repetida, 'a');
    });

    test('devuelve null cuando no hay repetidas', () {
      expect(
        materiaRepetida(const [
          EntradaPensum(materiaId: 'a', periodo: 1),
          EntradaPensum(materiaId: 'b', periodo: 1),
        ]),
        isNull,
      );
    });

    test('la misma materia en dos períodos distintos también es repetida', () {
      // No se puede cursar dos veces: la base tiene
      // `unique (program_id, subject_id)`.
      expect(
        materiaRepetida(const [
          EntradaPensum(materiaId: 'a', periodo: 1),
          EntradaPensum(materiaId: 'a', periodo: 2),
        ]),
        'a',
      );
    });

    test('una lista vacía no tiene repetidas', () {
      expect(materiaRepetida(const <EntradaPensum>[]), isNull);
    });
  });

  group('pensumEditable', () {
    test('con secciones activas no se toca', () {
      expect(pensumEditable(1), isFalse);
      expect(pensumEditable(7), isFalse);
    });

    test('sin secciones activas sí', () {
      expect(pensumEditable(0), isTrue);
    });
  });

  group('puedeActivarse', () {
    test('un programa sin materias no se puede activar', () {
      expect(puedeActivarse(totalMaterias: 0), isFalse);
    });

    test('con una sola materia ya se puede', () {
      expect(puedeActivarse(totalMaterias: 1), isTrue);
    });
  });

  group('siguientePeriodo', () {
    test('un pensum vacío empieza en el 1', () {
      expect(siguientePeriodo(const []), 1);
    });

    test('devuelve el mayor más uno, sin saltarse ninguno', () {
      expect(siguientePeriodo(const [1, 2, 5]), 6);
      expect(siguientePeriodo(const [4, 1]), 5);
    });
  });
}
