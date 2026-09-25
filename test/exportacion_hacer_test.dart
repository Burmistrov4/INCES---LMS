import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/exportacion_hacer.dart';

import 'support/fake_exportacion_hacer_gateway.dart';

/// Pruebas del serializador CSV de la exportación hacia HACER.
///
/// Son pruebas puras —sin gateway, sin pantalla, sin base— porque
/// `csvDeExportacionHacer` es una transformación de datos y ahí es donde vive
/// todo lo que puede corromper un archivo en silencio: el orden de las columnas,
/// el entrecomillado, el salto de línea y qué cuenta como celda vacía. Un CSV
/// mal escapado no falla: se abre, y una columna se ha partido en dos.
void main() {
  group('columnasExportacionHacer', () {
    test('no tiene duplicados (una repetida partiría el CSV en dos)', () {
      expect(
        columnasExportacionHacer.toSet().length,
        columnasExportacionHacer.length,
      );
    });

    test('son las 61 columnas de la vista', () {
      // Es un listón a propósito, no una tautología: obliga a actualizar el
      // contrato del cliente cuando la vista gane una columna, en vez de dejar
      // que el CSV y la base se separen sin que nadie lo note.
      expect(columnasExportacionHacer.length, 61);
    });

    test('la primera es el contexto y la última el jsonb crudo', () {
      expect(columnasExportacionHacer.first, 'inscripcion_id');
      expect(columnasExportacionHacer.last, 'datos_planilla');
    });
  });

  group('csvDeExportacionHacer', () {
    test('sin filas sigue emitiendo la cabecera', () {
      //  Una sección sin matriculados no puede producir un archivo sin cabecera:
      //  es justo el caso en que alguien abre el CSV para comprobar que está
      //  vacío, y un archivo de cero bytes no dice nada.
      final csv = csvDeExportacionHacer(const []);

      expect(csv, '${columnasExportacionHacer.join(',')}\r\n');
    });

    test('la cabecera respeta el orden declarado, no el de las claves', () {
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);
      final lineas = csv.split('\r\n');

      expect(lineas.first.split(','), columnasExportacionHacer);
    });

    test('una fila por registro, y termina en salto de línea', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(),
        filaExportacionEjemplo(sobrescribir: {'cedula': 'V-2'}),
      ]);
      final lineas = csv.split('\r\n');

      // cabecera + 2 filas + el vacío que deja el salto final
      expect(lineas.length, 4);
      expect(lineas.last, '');
    });

    test('usa CRLF, no LF: el formato no depende de la máquina', () {
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);

      expect(csv.contains('\r\n'), isTrue);
      expect(csv.replaceAll('\r\n', '').contains('\n'), isFalse);
    });

    test('entrecomilla una celda con coma', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'direccion': 'Calle 1, Casa 2'}),
      ]);

      expect(csv, contains('"Calle 1, Casa 2"'));
    });

    test('duplica la comilla interior', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'nombres': 'Jo"sé'}),
      ]);

      expect(csv, contains('"Jo""sé"'));
    });

    test('entrecomilla una celda con salto de línea', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'direccion': 'Calle 1\nCasa 2'}),
      ]);

      expect(csv, contains('"Calle 1\nCasa 2"'));
    });

    test('NO sanea fórmulas: un teléfono que empieza por + es un teléfono', () {
      //  Prefijar con apóstrofo protegería a Excel y corrompería el dato para
      //  HACER, que es el consumidor real del archivo. Se fija aquí para que
      //  nadie lo «arregle» más adelante creyendo que es un olvido.
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'telefono': '+584121234567'}),
      ]);

      expect(csv, contains('+584121234567'));
      expect(csv, isNot(contains("'+584121234567")));
    });

    test('un valor nulo y uno vacío dan la misma celda vacía', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {'planilla_twitter': null, 'planilla_facebook': ''},
        ),
      ]);
      final celdas = csv.split('\r\n')[1].split(',');

      final iTwitter = columnasExportacionHacer.indexOf('planilla_twitter');
      final iFacebook = columnasExportacionHacer.indexOf('planilla_facebook');
      expect(celdas[iTwitter], '');
      expect(celdas[iFacebook], '');
    });

    test('una clave declarada ausente en la fila deja la celda vacía', () {
      //  El caso real: `PostgREST` siempre devuelve todas las columnas, pero si
      //  algún día no lo hace, la fila no puede desplazar las demás.
      final csv = csvDeExportacionHacer([
        const FilaExportacionHacer({'cedula': 'V-1'}),
      ]);
      final celdas = csv.split('\r\n')[1].split(',');

      expect(celdas.length, columnasExportacionHacer.length);
      expect(celdas[columnasExportacionHacer.indexOf('cedula')], 'V-1');
      expect(celdas[columnasExportacionHacer.indexOf('nombres')], '');
    });

    test('una columna que la vista devuelva y no esté declarada se AÑADE', () {
      //  Sin esto, un `alter view` que añadiera una columna la perdería en
      //  silencio: el archivo seguiría saliendo y parecería correcto.
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'columna_nueva': 'x'}),
      ]);
      final cabecera = csv.split('\r\n').first.split(',');

      expect(cabecera.length, columnasExportacionHacer.length + 1);
      expect(cabecera.last, 'columna_nueva');
      expect(csv, contains(',x\r\n'));
    });

    test('varias columnas extra salen ordenadas, para que el archivo sea estable', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'zeta': '1', 'alfa': '2'}),
      ]);
      final cabecera = csv.split('\r\n').first.split(',');

      expect(cabecera.sublist(cabecera.length - 2), ['alfa', 'zeta']);
    });
  });

  group('FilaExportacionHacer.valorDe', () {
    test('una cadena viaja tal cual', () {
      expect(const FilaExportacionHacer({'x': 'Wayuu'}).valorDe('x'), 'Wayuu');
    });

    test('un booleano sale true/false, no Sí/No', () {
      expect(const FilaExportacionHacer({'x': true}).valorDe('x'), 'true');
      expect(const FilaExportacionHacer({'x': false}).valorDe('x'), 'false');
    });

    test('un número sale como texto', () {
      expect(const FilaExportacionHacer({'x': 42}).valorDe('x'), '42');
      expect(const FilaExportacionHacer({'x': 4.5}).valorDe('x'), '4.5');
    });

    test('el jsonb crudo sale como JSON compacto, para que sea recuperable', () {
      final fila = const FilaExportacionHacer({
        'datos_planilla': {'pueblo_indigena_cual': 'Wayuu'},
      });

      expect(fila.valorDe('datos_planilla'), '{"pueblo_indigena_cual":"Wayuu"}');
    });

    test('una clave ausente es null, no la cadena "null"', () {
      expect(const FilaExportacionHacer({}).valorDe('x'), isNull);
    });
  });

  group('ExportacionHacer', () {
    test('fromJson descarta lo que no sea un mapa', () {
      final exportacion = ExportacionHacer.fromJson(<dynamic>[
        <String, dynamic>{'cedula': 'V-1'},
        'basura',
        null,
        <String, dynamic>{'cedula': 'V-2'},
      ]);

      expect(exportacion.total, 2);
      expect(exportacion.vacia, isFalse);
    });

    test('sin filas está vacía pero sigue produciendo un CSV con cabecera', () {
      const exportacion = ExportacionHacer(filas: []);

      expect(exportacion.vacia, isTrue);
      expect(exportacion.aCsv().startsWith(columnasExportacionHacer.first), isTrue);
    });
  });

  group('nombreArchivoHacer', () {
    test('lleva lapso, materia y sección, y termina en .csv', () {
      expect(
        nombreArchivoHacer(periodo: 'SA26-2', seccion: 'EA', materia: 'Soldadura'),
        'planilla-hacer-SA26-2-Soldadura-EA.csv',
      );
    });

    test('sin materia no deja un guion de más', () {
      expect(
        nombreArchivoHacer(periodo: 'SA26-2', seccion: 'EA'),
        'planilla-hacer-SA26-2-EA.csv',
      );
    });

    test('quita los caracteres que ningún sistema de archivos admite', () {
      expect(
        nombreArchivoHacer(periodo: 'SA26-2', seccion: 'E/A:1'),
        'planilla-hacer-SA26-2-EA1.csv',
      );
    });

    test('convierte los espacios en guiones', () {
      expect(
        nombreArchivoHacer(periodo: 'SA26-2', seccion: 'Soldadura por Arco'),
        'planilla-hacer-SA26-2-Soldadura-por-Arco.csv',
      );
    });

    test('CONSERVA los acentos: José es un nombre, no un error', () {
      expect(
        nombreArchivoHacer(periodo: 'SA26-2', seccion: 'José Núñez'),
        'planilla-hacer-SA26-2-José-Núñez.csv',
      );
    });
  });
}
