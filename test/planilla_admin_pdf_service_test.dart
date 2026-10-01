import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/repositories/planilla_admin_descarga_repository.dart';
import 'package:inces_lms_app/services/planilla_admin_pdf_service.dart';

import 'support/fake_planilla_admin_descarga_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Pruebas del servicio que descarga y entrega el PDF de la planilla de **otro**
/// aspirante, para el administrador.
///
/// El servicio no sabe ni de HTTP ni de `Blob`: lo que se prueba aquí es la
/// **secuencia**, los **cuatro desenlaces** y —lo que este servicio tiene de
/// propio— que el UUID que viaja es **el de la persona pedida**. Se espeja
/// `planilla_pdf_service_test.dart`, que cubre la planilla propia.
void main() {
  late FakePlanillaAdminDescargaGateway gateway;
  late FakeSelectorDeArchivos selector;
  late PlanillaAdminPdfService servicio;

  setUp(() {
    gateway = FakePlanillaAdminDescargaGateway();
    selector = FakeSelectorDeArchivos();
    servicio = PlanillaAdminPdfService(
      repositorio: PlanillaAdminDescargaRepository(gateway: gateway),
      selector: selector,
    );
  });

  group('camino feliz', () {
    test('descarga el PDF de la persona pedida y lo entrega al navegador',
        () async {
      gateway.pdfDevuelto = [37, 80, 68, 70]; // %PDF

      final resultado = await servicio.descargarPlanillaDe(
        usuarioId: 'user-1',
        estudiante: 'José Núñez',
      );

      expect(resultado, isA<PlanillaAdminDescargada>());
      expect((resultado as PlanillaAdminDescargada).estudiante, 'José Núñez');

      // El UUID que viaja es el de la persona pedida. Sin esta aserción, un
      // panel que descargara siempre la planilla de la primera fila pasaría.
      expect(gateway.idsSolicitados, ['user-1']);

      expect(selector.llamadas, ['descargarBytes']);
      // Lo que llega al navegador es el PDF entero, no un resumen.
      expect(selector.ultimoContenidoBytesDescargado, [37, 80, 68, 70]);
      expect(selector.ultimoTipoMimeBytesDescargado, 'application/pdf');
      // El nombre identifica a la persona: es lo que permite al administrador
      // distinguir varias planillas descargadas seguidas.
      expect(selector.ultimoNombreDeBytesDescargado, 'planilla-jose-nunez.pdf');
    });

    test('la misma persona en Excel: mismo camino, otro formato', () async {
      // Lo que cambia no es sólo el nombre: es el **método del gateway** que se
      // llama y el tipo MIME con el que se entrega. Si el servicio pidiera el
      // PDF y lo llamara «.xlsx», el archivo no abriría y esta prueba lo ve.
      gateway.pdfDevuelto = [80, 75, 3, 4]; // `PK`

      final resultado = await servicio.descargarExcelDe(
        usuarioId: 'user-9',
        estudiante: 'José Núñez',
      );

      expect(resultado, isA<PlanillaAdminDescargada>());
      expect(gateway.idsSolicitados, ['user-9']);
      expect(gateway.formatosSolicitados, ['xlsx']);
      expect(selector.ultimoNombreDeBytesDescargado, 'planilla-jose-nunez.xlsx');
      expect(
        selector.ultimoTipoMimeBytesDescargado,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    });
  });

  group('AspiranteSinFicha: el 404 no es un error', () {
    test('lo trata como AspiranteSinFicha y dice a quién le falta', () async {
      //  Un estudiante puede estar matriculado y no haber rellenado nunca la
      //  planilla de identidad. No debe pintarse como fallo rojo, y el aviso
      //  tiene que nombrar a la persona: el admin necesita saber a quién.
      gateway.errorAlDescargarPdf = AppException.validacion(
        'Todavía no tienes una ficha de aspirante.',
        code: 'SIN_FICHA_DE_ASPIRANTE',
      );

      final resultado = await servicio.descargarPlanillaDe(
        usuarioId: 'user-2',
        estudiante: 'Luis Pérez',
      );

      expect(resultado, isA<AspiranteSinFicha>());
      expect((resultado as AspiranteSinFicha).estudiante, 'Luis Pérez');
      expect(resultado, isNot(isA<ConsultaAdminFallida>()));
      expect(selector.llamadas, isEmpty);
    });
  });

  group('los dos fallos se distinguen', () {
    test('un error de consulta llega como ConsultaAdminFallida', () async {
      gateway.errorAlDescargarPdf = AppException.validacion(
        'No autenticado',
        code: 'NO_AUTENTICADO',
      );

      final resultado = await servicio.descargarPlanillaDe(
        usuarioId: 'user-3',
        estudiante: 'Ana Gómez',
      );

      expect(resultado, isA<ConsultaAdminFallida>());
      final fallo = resultado as ConsultaAdminFallida;
      expect(fallo.mensaje, 'No autenticado');
      expect(fallo.estudiante, 'Ana Gómez');
      expect(selector.llamadas, isEmpty);
    });

    test('un fallo del navegador llega como DescargaAdminFallida, no como '
        'consulta', () async {
      //  La mitad que falló importa: no es lo mismo que el backend no responda
      //  que que el navegador no pueda entregar el archivo.
      gateway.pdfDevuelto = [1, 2, 3];
      selector.errorAlDescargarBytes = StateError('el Blob no se pudo crear');

      final resultado = await servicio.descargarPlanillaDe(
        usuarioId: 'user-4',
        estudiante: 'Ana Gómez',
      );

      expect(resultado, isA<DescargaAdminFallida>());
      expect((resultado as DescargaAdminFallida).estudiante, 'Ana Gómez');
      expect(resultado, isNot(isA<ConsultaAdminFallida>()));
      expect(selector.llamadas, ['descargarBytes']);
    });

    test('el servicio NO lanza nunca: siempre devuelve un desenlace', () async {
      //  El panel consume con un `switch` exhaustivo, así que un `throw` que se
      //  escapara dejaría el botón girando sin aviso.
      gateway.errorAlDescargarPdf = Exception('boom');

      await expectLater(
        servicio.descargarPlanillaDe(usuarioId: 'user-5', estudiante: 'X'),
        completes,
      );
    });
  });

  group('el nombre del archivo', () {
    test('pliega las tildes y convierte lo no alfanumérico en guiones', () {
      expect(nombreArchivoPlanillaDe('José Núñez'), 'planilla-jose-nunez.pdf');
      expect(nombreArchivoPlanillaDe('Núñez, José'), 'planilla-nunez-jose.pdf');
      //  Los huecos repetidos se colapsan: `maria--del--carmen` sería un nombre
      //  que nadie escribe y que algunas herramientas normalizan distinto.
      expect(
        nombreArchivoPlanillaDe('  María   del  Carmen '),
        'planilla-maria-del-carmen.pdf',
      );
    });

    test('un nombre vacío no produce un archivo sin nombre', () {
      //  El panel no debería pasar vacío, pero `planilla-.pdf` es un archivo que
      //  el usuario no puede identificar; el respaldo evita eso.
      expect(nombreArchivoPlanillaDe('   '), 'planilla-aspirante.pdf');
    });

    test('el formato decide la extensión', () {
      //  El PDF es el valor por defecto porque es la salida que ya existía: sin
      //  él, todas las llamadas que no dicen formato —incluidas las pruebas de
      //  arriba— tendrían que pasar a decirlo.
      expect(nombreArchivoPlanillaDe('José Núñez'), 'planilla-jose-nunez.pdf');
      expect(
        nombreArchivoPlanillaDe('José Núñez', formato: FormatoPlanilla.xlsx),
        'planilla-jose-nunez.xlsx',
      );
    });
  });
}
