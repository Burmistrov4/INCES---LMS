import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/exportacion_hacer.dart';

import 'support/fake_exportacion_hacer_gateway.dart';

/// El archivo sin la marca de orden de bytes, para poder trocearlo.
///
/// El BOM es un carácter más de la cadena, así que sin quitarlo la primera
/// celda de la cabecera se llamaría `\uFEFFinscripcion_id` y ninguna comparación
/// contra [columnasExportacionHacer] cuadraría. Que las pruebas tengan que
/// quitarlo a mano es *bueno*: deja escrito que el BOM viaja **dentro** del
/// archivo, que es exactamente lo que se quiere fijar.
String sinBom(String csv) => csv.startsWith(marcaOrdenDeBytes)
    ? csv.substring(marcaOrdenDeBytes.length)
    : csv;

/// Las celdas de una línea del archivo. La 0 es la cabecera.
List<String> celdas(String csv, {int fila = 1}) =>
    sinBom(csv).split('\r\n')[fila].split(separadorHacer);

/// La celda de [columna] en la fila de datos.
String celdaDe(String csv, String columna) =>
    celdas(csv)[columnasExportacionHacer.indexOf(columna)];

/// Pruebas del serializador del archivo de HACER.
///
/// Son pruebas puras —sin gateway, sin pantalla, sin base— porque
/// `csvDeExportacionHacer` es una transformación de datos y ahí es donde vive
/// todo lo que puede corromper un archivo en silencio: el separador, el orden de
/// las columnas, el entrecomillado, el salto de línea, las mayúsculas y qué
/// cuenta como celda vacía. Un CSV mal escapado no falla: se abre, y una columna
/// se ha partido en dos.
void main() {
  group('columnasExportacionHacer', () {
    test('no tiene duplicados (una repetida partiría el CSV en dos)', () {
      expect(
        columnasExportacionHacer.toSet().length,
        columnasExportacionHacer.length,
      );
    });

    test('son las 61 columnas de la vista más documento_identidad', () {
      // Es un listón a propósito, no una tautología: obliga a actualizar el
      // contrato del cliente cuando la vista gane una columna, en vez de dejar
      // que el CSV y la base se separen sin que nadie lo note.
      //
      // 61 + 1: `documento_identidad` **no viene de la vista**, se deriva de
      // `cedula` y `planilla_nacionalidad` (ver `FilaExportacionHacer`).
      expect(columnasExportacionHacer.length, 62);
    });

    test('la primera es el contexto y la última el jsonb crudo', () {
      expect(columnasExportacionHacer.first, 'inscripcion_id');
      expect(columnasExportacionHacer.last, 'datos_planilla');
    });

    test('documento_identidad va pegado a cedula', () {
      // Va al lado porque es su lectura «documento oficial»: si alguien abre el
      // archivo y compara, las dos columnas tienen que estar juntas.
      expect(
        columnasExportacionHacer.indexOf('documento_identidad'),
        columnasExportacionHacer.indexOf('cedula') + 1,
      );
    });

    test('ninguna columna exenta de mayúsculas está fuera de la lista', () {
      // Un nombre mal escrito en `columnasSinMayusculas` no daría error: sólo
      // dejaría de proteger una columna, y el uuid roto se descubriría al
      // importar el archivo.
      for (final columna in columnasSinMayusculas) {
        expect(
          columnasExportacionHacer,
          contains(columna),
          reason: '«$columna» está exenta de mayúsculas pero no se exporta',
        );
      }
    });
  });

  group('el archivo: separador, BOM y fin de línea', () {
    test('el separador es punto y coma', () {
      expect(separadorHacer, ';');
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);
      expect(celdas(csv).length, columnasExportacionHacer.length);
    });

    test('empieza con los tres bytes del BOM, no con el carácter', () {
      //  La aserción sobre los BYTES es la que vale: el archivo lo abre otro
      //  programa, y lo que ese programa ve son bytes. `U+FEFF` codificado en
      //  UTF-8 **es** `EF BB BF`, y esto lo comprueba en vez de suponerlo.
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);

      expect(csv.startsWith(marcaOrdenDeBytes), isTrue);
      expect(utf8.encode(csv).take(3).toList(), [0xEF, 0xBB, 0xBF]);
    });

    test('el BOM va una sola vez, al principio del archivo', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(),
        filaExportacionEjemplo(),
      ]);

      expect(marcaOrdenDeBytes.allMatches(csv).length, 1);
      expect(csv.indexOf(marcaOrdenDeBytes), 0);
    });

    test('sin filas sigue emitiendo la cabecera', () {
      //  Una sección sin matriculados no puede producir un archivo sin cabecera:
      //  es justo el caso en que alguien abre el CSV para comprobar que está
      //  vacío, y un archivo de cero bytes no dice nada.
      final csv = csvDeExportacionHacer(const []);

      expect(csv, '$marcaOrdenDeBytes${columnasExportacionHacer.join(';')}\r\n');
    });

    test('la cabecera respeta el orden declarado, no el de las claves', () {
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);

      expect(sinBom(csv).split('\r\n').first.split(';'), columnasExportacionHacer);
    });

    test('la cabecera NO se pasa a mayúsculas', () {
      //  Las reglas de saneado que HACER pidió son de datos. La cabecera es la
      //  etiqueta con la que el sistema receptor reconoce cada columna: cambiarle
      //  las mayúsculas es cambiar el contrato con quien lee, no sanear un valor.
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);

      expect(celdaDe(csv, 'inscripcion_id'), isNot('INSCRIPCION_ID'));
      expect(sinBom(csv), startsWith('inscripcion_id;seccion_id;lapso'));
    });

    test('una fila por registro, y termina en salto de línea', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(),
        filaExportacionEjemplo(sobrescribir: {'cedula': 'V-2'}),
      ]);
      final lineas = sinBom(csv).split('\r\n');

      // cabecera + 2 filas + el vacío que deja el salto final
      expect(lineas.length, 4);
      expect(lineas.last, '');
    });

    test('usa CRLF, no LF: el formato no depende de la máquina', () {
      final csv = csvDeExportacionHacer([filaExportacionEjemplo()]);

      expect(csv.contains('\r\n'), isTrue);
      expect(csv.replaceAll('\r\n', '').contains('\n'), isFalse);
    });
  });

  group('entrecomillado: la regla sigue al separador', () {
    test('entrecomilla una celda con punto y coma', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'direccion': 'Calle 1; Casa 2'}),
      ]);

      expect(csv, contains('"CALLE 1; CASA 2"'));
    });

    test('una coma ya NO obliga a entrecomillar', () {
      //  Este es el cambio que trae el separador nuevo, y es el que más fácil se
      //  pasa por alto: con `;` de separador, una coma es un carácter más. Si la
      //  condición de entrecomillado siguiera escrita a mano con una coma, el
      //  archivo saldría lleno de comillas innecesarias — y peor, dejaría de
      //  proteger los puntos y coma.
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'direccion': 'Calle 1, Casa 2'}),
      ]);

      expect(csv, contains('CALLE 1, CASA 2'));
      expect(csv, isNot(contains('"CALLE 1, CASA 2"')));
    });

    test('duplica la comilla interior', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'nombres': 'Jo"sé'}),
      ]);

      expect(csv, contains('"JO""SÉ"'));
    });
  });

  group('saneado: saltos de línea, mayúsculas y nulos', () {
    test('un salto de línea interno se sustituye por un espacio', () {
      //  Es el fallo más caro de todos: un salto dentro de una celda parte el
      //  registro en dos y, a partir de ahí, todo lo que sigue queda descolocado
      //  columna a columna. No se lanza ningún error.
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'direccion': 'Av. Bolívar\nCalle 5'}),
      ]);

      expect(csv, contains('AV. BOLÍVAR CALLE 5'));
      expect(celdaDe(csv, 'direccion'), 'AV. BOLÍVAR CALLE 5');
    });

    test('un retorno de carro suelto también, y los seguidos colapsan en uno', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {'direccion': 'Calle 1\r\n\r\nCasa 2'},
        ),
      ]);

      //  No «CALLE 1  CASA 2» (dos espacios) ni «CALLE 1CASA 2» (ninguno): un
      //  espacio. Pegarlos haría ilegible el dato.
      expect(celdaDe(csv, 'direccion'), 'CALLE 1 CASA 2');
    });

    test('el salto de línea NO rompe la estructura del archivo', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'direccion': 'A\nB'}),
        filaExportacionEjemplo(sobrescribir: {'cedula': 'V-2'}),
      ]);

      //  cabecera + 2 filas + el vacío final. Si el salto sobreviviera, aquí
      //  habría 5 trozos y el archivo estaría corrupto.
      expect(sinBom(csv).split('\r\n').length, 4);
    });

    test('el texto se pasa a MAYÚSCULAS, y conserva los acentos', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {
            'nombres': 'José María',
            'planilla_municipio': 'San Diego',
          },
        ),
      ]);

      //  `toUpperCase` en Dart sube la ñ y las vocales acentuadas: no hay que
      //  normalizar nada antes. Se fija aquí porque es lo que HACER necesita
      //  para que «ÑÚÑEZ» salga bien y no como un carácter roto.
      expect(celdaDe(csv, 'nombres'), 'JOSÉ MARÍA');
      expect(celdaDe(csv, 'planilla_municipio'), 'SAN DIEGO');
    });

    test('los uuid NO se pasan a mayúsculas', () {
      //  Un uuid en mayúsculas es un uuid inválido para un analizador estricto:
      //  la forma canónica de la RFC 9562 es en minúsculas. Subirlo rompería
      //  justo el dato que casa la fila con el sistema de origen.
      const uuid = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {
            'inscripcion_id': uuid,
            'seccion_id': uuid,
            'aspirante_id': uuid,
          },
        ),
      ]);

      expect(celdaDe(csv, 'inscripcion_id'), uuid);
      expect(celdaDe(csv, 'seccion_id'), uuid);
      expect(celdaDe(csv, 'aspirante_id'), uuid);
      expect(csv, isNot(contains(uuid.toUpperCase())));
    });

    test('el jsonb crudo conserva sus CLAVES en minúsculas', () {
      //  Subir el jsonb a mayúsculas subiría también sus claves, y el archivo
      //  tendría dos vocabularios para el mismo dato: `{"NACIONALIDAD":…}` en el
      //  jsonb y `planilla_nacionalidad` en las columnas aplanadas.
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {
            'datos_planilla': {'pueblo_indigena_cual': 'Wayuu'},
          },
        ),
      ]);

      //  Se compara la **clave JSON entrecomillada** y no la palabra suelta: la
      //  columna `planilla_pueblo_indigena_cual` sí se mayusculiza, y contiene
      //  esa misma subcadena. Buscar la palabra a secas daría un rojo falso.
      expect(csv, contains('"pueblo_indigena_cual"'));
      expect(csv, isNot(contains('"PUEBLO_INDIGENA_CUAL"')));
    });

    test('los booleanos siguen siendo true/false, no TRUE/FALSE', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {'seccion_activa': true, 'discapacidad': false},
        ),
      ]);

      expect(celdaDe(csv, 'seccion_activa'), 'true');
      expect(celdaDe(csv, 'discapacidad'), 'false');
    });

    test('las fechas no se tocan', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {
            'fecha_nac': '2007-03-14',
            'inscrito_en': '2026-09-25T12:00:00+00:00',
          },
        ),
      ]);

      expect(celdaDe(csv, 'fecha_nac'), '2007-03-14');
      expect(celdaDe(csv, 'inscrito_en'), '2026-09-25T12:00:00+00:00');
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

      expect(celdaDe(csv, 'planilla_twitter'), '');
      expect(celdaDe(csv, 'planilla_facebook'), '');
    });

    test('una celda que sólo tenía espacios sale vacía, no con espacios', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'planilla_comunidad': '   '}),
      ]);

      expect(celdaDe(csv, 'planilla_comunidad'), '');
    });

    test('una clave declarada ausente en la fila deja la celda vacía', () {
      //  El caso real: `PostgREST` siempre devuelve todas las columnas, pero si
      //  algún día no lo hace, la fila no puede desplazar las demás.
      final csv = csvDeExportacionHacer([
        const FilaExportacionHacer({'cedula': 'V-1'}),
      ]);

      expect(celdas(csv).length, columnasExportacionHacer.length);
      expect(celdaDe(csv, 'cedula'), 'V-1');
      expect(celdaDe(csv, 'nombres'), '');
    });

    test('una columna que la vista devuelva y no esté declarada se AÑADE', () {
      //  Sin esto, un `alter view` que añadiera una columna la perdería en
      //  silencio: el archivo seguiría saliendo y parecería correcto.
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'columna_nueva': 'x'}),
      ]);
      final cabecera = sinBom(csv).split('\r\n').first.split(';');

      expect(cabecera.length, columnasExportacionHacer.length + 1);
      expect(cabecera.last, 'columna_nueva');
      expect(csv, contains(';X\r\n'));
    });

    test('varias columnas extra salen ordenadas, para que el archivo sea estable', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(sobrescribir: {'zeta': '1', 'alfa': '2'}),
      ]);
      final cabecera = sinBom(csv).split('\r\n').first.split(';');

      expect(cabecera.sublist(cabecera.length - 2), ['alfa', 'zeta']);
    });
  });

  group('FilaExportacionHacer.valorDe', () {
    test('una cadena viaja tal cual, sin formatear', () {
      //  El formateo —mayúsculas, saltos— lo aplica el serializador, no la
      //  lectura. Aquí se fija que no se adelanta trabajo: si `valorDe` ya
      //  mayusculizara, el serializador no podría decidir por columna.
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

  group('documento_identidad: nacionalidad + cédula con relleno', () {
    /// Un documento a partir de una cédula y una nacionalidad opcionales.
    ///
    /// Las claves se omiten cuando el valor es nulo —con el marcador `?`— para
    /// que «sin cédula» y «sin nacionalidad» sean la **ausencia de la clave**, y
    /// no una clave con valor nulo: es lo que devuelve PostgREST y lo que el
    /// servicio tiene que saber tratar.
    String? documento({String? cedula, String? nacionalidad}) =>
        FilaExportacionHacer({
          'cedula': ?cedula,
          'planilla_nacionalidad': ?nacionalidad,
        }).documentoIdentidad();

    test('el ejemplo de la especificación: V + 8 dígitos da 10 caracteres', () {
      //  Es el caso que fija la regla entera. Si el relleno se aplicara a la
      //  cadena completa saldría `0V12345678`, con la letra en medio.
      expect(documento(cedula: '12345678', nacionalidad: 'V'), 'V012345678');
      expect(documento(cedula: '12345678', nacionalidad: 'V')!.length, 10);
    });

    test('una cédula de 9 dígitos no se recorta ni se rellena', () {
      expect(documento(cedula: '123456789', nacionalidad: 'V'), 'V123456789');
    });

    test('una cédula más larga que 9 dígitos NO se trunca', () {
      //  Recortar un documento de identidad para que «quepa» en 10 caracteres
      //  sería fabricar un dato falso. Si es más largo, es más largo.
      expect(
        documento(cedula: '1234567890', nacionalidad: 'V'),
        'V1234567890',
      );
    });

    test('sin nacionalidad sale la cédula rellenada, sin prefijo', () {
      //  Decisión tomada a conciencia: prefijar `V` por defecto afirmaría una
      //  nacionalidad que la base no tiene, y esto es un documento oficial. La
      //  nacionalidad vive en el jsonb de la planilla y la cédula en una columna
      //  plana, así que el caso vacío es probable, no exótico.
      expect(documento(cedula: '12345678'), '012345678');
    });

    test('una cédula que YA trae su letra no se prefija dos veces', () {
      //  `cedula` es un campo de texto libre del catálogo, así que puede venir
      //  escrita como la persona la escribe. Concatenar sin mirar daría
      //  `VV12345678`, que no es un documento de ningún país.
      expect(documento(cedula: 'V12345678', nacionalidad: 'V'), 'V012345678');
      expect(documento(cedula: 'V-12345678', nacionalidad: 'V'), 'V012345678');
      expect(documento(cedula: 'V 12345678', nacionalidad: 'V'), 'V012345678');
    });

    test('si la cédula trae letra, esa manda sobre la de la planilla', () {
      //  Es la que la persona escribió en su documento. Que la planilla diga
      //  otra cosa no la invalida: el dato propio gana sobre el deducido.
      expect(documento(cedula: 'E12345678', nacionalidad: 'V'), 'E012345678');
    });

    test('sin cédula no hay documento: null, no una celda inventada', () {
      expect(documento(nacionalidad: 'V'), isNull);
      expect(documento(), isNull);
    });

    test('una forma inesperada no se trocea: viaja tal cual', () {
      //  Ante la duda, el dato original íntegro. Y `cedula` sigue en el archivo,
      //  así que nada se pierde.
      expect(documento(cedula: 'S/N', nacionalidad: 'V'), 'S/N');
      expect(documento(cedula: '1234-5678'), '1234-5678');
    });

    test('gana la derivación: un valor puesto en el mapa se ignora', () {
      //  `documento_identidad` no es una columna de la vista. Si alguien la
      //  sobrescribe —el fixture lo hace, rellenando todas las declaradas— el
      //  valor calculado tiene que imponerse, o el archivo llevaría un
      //  documento que no corresponde a la cédula.
      final fila = FilaExportacionHacer({
        'cedula': '12345678',
        'planilla_nacionalidad': 'V',
        'documento_identidad': 'NO_DEBE_SALIR',
      });

      expect(fila.valorDe('documento_identidad'), 'V012345678');
    });

    test('en el archivo sale la columna, con el relleno aplicado', () {
      final csv = csvDeExportacionHacer([
        filaExportacionEjemplo(
          sobrescribir: {'cedula': '12345678', 'planilla_nacionalidad': 'V'},
        ),
      ]);

      expect(celdaDe(csv, 'documento_identidad'), 'V012345678');
      // Y la cédula cruda sigue ahí: nada se sustituye.
      expect(celdaDe(csv, 'cedula'), '12345678');
      expect(celdaDe(csv, 'planilla_nacionalidad'), 'V');
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

    test('sin filas está vacía pero sigue produciendo un archivo con cabecera', () {
      const exportacion = ExportacionHacer(filas: []);

      expect(exportacion.vacia, isTrue);
      expect(exportacion.aCsv(), startsWith(marcaOrdenDeBytes));
      expect(exportacion.aCsv(), contains('inscripcion_id'));
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
