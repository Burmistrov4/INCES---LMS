import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/exportacion_hacer.dart';
import 'package:inces_lms_app/repositories/exportacion_hacer_repository.dart';
import 'package:inces_lms_app/services/hacer_export_service.dart';

import 'support/fake_exportacion_hacer_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Pruebas del servicio que genera y entrega el archivo de HACER.
///
/// El servicio no tiene lógica de formato propia —eso vive en el serializador,
/// probado en `exportacion_hacer_test.dart`— ni sabe de `setState`: lo que se
/// prueba aquí es la **secuencia** y los **cuatro desenlaces**. Antes esa
/// secuencia estaba dentro del `State` del panel, y por eso no se podía probar
/// sin montar una pantalla entera.
void main() {
  late FakeExportacionHacerGateway gateway;
  late FakeSelectorDeArchivos selector;
  late HacerExportService servicio;

  setUp(() {
    gateway = FakeExportacionHacerGateway();
    selector = FakeSelectorDeArchivos();
    servicio = HacerExportService(
      repositorio: ExportacionHacerRepository(gateway: gateway),
      selector: selector,
    );
  });

  Future<ResultadoExportacionHacer> exportar({String seccionId = 'sec-1'}) =>
      servicio.exportarSeccion(
        seccionId: seccionId,
        periodo: 'SA26-2',
        seccion: 'Sección A',
        materia: 'Soldadura por Arco',
      );

  group('camino feliz', () {
    test('consulta la sección que se le pide, y sólo esa', () async {
      gateway.filasDevueltas = [filaExportacionEjemplo()];

      await exportar(seccionId: 'sec-2');

      expect(gateway.llamadas, ['filasDeSeccion:sec-2']);
    });

    test('con la nómina, descarga el archivo y lo reporta', () async {
      gateway.filasDevueltas = [
        filaExportacionEjemplo(),
        filaExportacionEjemplo(sobrescribir: {'cedula': 'V-2'}),
      ];

      final resultado = await exportar();

      expect(resultado, isA<NominaDescargada>());
      final descargada = resultado as NominaDescargada;
      expect(descargada.matriculados, 2);
      expect(
        descargada.nombreArchivo,
        'planilla-hacer-SA26-2-Soldadura-por-Arco-Sección-A.csv',
      );
      expect(selector.llamadas, ['descargarTexto']);
    });

    test('lo que entrega al navegador es el archivo, no un resumen', () async {
      //  El contrato del botón no es «se llamó a descargar»: es que el texto que
      //  llega al navegador **es** el archivo de HACER. Se comprueban las tres
      //  cosas que lo definen: el BOM, el separador y el documento derivado.
      gateway.filasDevueltas = [
        filaExportacionEjemplo(
          sobrescribir: {'cedula': '12345678', 'planilla_nacionalidad': 'V'},
        ),
      ];

      await exportar();

      final csv = selector.ultimoTextoDescargado!;
      expect(utf8.encode(csv).take(3).toList(), [0xEF, 0xBB, 0xBF]);
      expect(csv, contains(separadorHacer));
      expect(csv, contains('V012345678'));
      expect(csv, endsWith('\r\n'));
    });

    test('declara el tipo MIME con charset, para que Excel no adivine', () async {
      gateway.filasDevueltas = [filaExportacionEjemplo()];

      await exportar();

      expect(selector.ultimoTipoMimeDescargado, 'text/csv;charset=utf-8');
    });

    test('el nombre del archivo sale del contexto, no de las filas', () async {
      //  Dos descargas del mismo día no pueden pisarse, y el nombre tiene que
      //  decir de qué sección es sin abrir el archivo.
      gateway.filasDevueltas = [filaExportacionEjemplo()];

      await servicio.exportarSeccion(
        seccionId: 'sec-1',
        periodo: 'SA26-2',
        seccion: 'EA',
      );

      expect(selector.ultimoNombreDeTextoDescargado, 'planilla-hacer-SA26-2-EA.csv');
    });
  });

  group('NadaQueExportar: una sección recién abierta no es un fallo', () {
    test('no descarga nada y devuelve la sección, para poder nombrarla', () async {
      gateway.filasDevueltas = const [];

      final resultado = await exportar();

      expect(resultado, isA<NadaQueExportar>());
      expect((resultado as NadaQueExportar).seccion, 'Sección A');
      expect(selector.llamadas, isEmpty);
    });

    test('no es un fallo: no viaja como ConsultaFallida', () async {
      //  Si viajara como fallo, el panel pintaría un error rojo por una
      //  situación normal y el administrador aprendería a ignorar los rojos.
      gateway.filasDevueltas = const [];

      expect(await exportar(), isNot(isA<ConsultaFallida>()));
    });
  });

  group('los dos fallos se distinguen', () {
    test('un fallo de la consulta llega como ConsultaFallida, con su mensaje', () async {
      gateway.errorAlConsultar =
          const AppException.validacion('La vista de exportación no respondió.');

      final resultado = await exportar();

      expect(resultado, isA<ConsultaFallida>());
      expect(
        (resultado as ConsultaFallida).mensaje,
        'La vista de exportación no respondió.',
      );
      expect(selector.llamadas, isEmpty);
    });

    test('un fallo del navegador llega como DescargaFallida, no como consulta', () async {
      //  La mitad que falló importa: no es lo mismo que la vista no responda que
      //  que el navegador no pueda entregar el archivo, y el administrador no
      //  puede hacer nada con el `toString()` de un error de JavaScript.
      gateway.filasDevueltas = [filaExportacionEjemplo()];
      selector.errorAlDescargarTexto = StateError('el Blob no se pudo crear');

      final resultado = await exportar();

      expect(resultado, isA<DescargaFallida>());
      expect(resultado, isNot(isA<ConsultaFallida>()));
      expect(selector.llamadas, ['descargarTexto']);
    });

    test('el servicio NO lanza nunca: siempre devuelve un desenlace', () async {
      //  El panel consume con un `switch` exhaustivo, así que un `throw` que se
      //  escapara dejaría el botón girando sin aviso. Cualquier error se
      //  convierte en valor.
      gateway.errorAlConsultar = Exception('boom');

      await expectLater(exportar(), completes);
    });
  });
}
