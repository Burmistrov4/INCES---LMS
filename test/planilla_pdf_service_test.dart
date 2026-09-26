import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/repositories/planilla_repository.dart';
import 'package:inces_lms_app/services/planilla_pdf_service.dart';

import 'support/fake_planilla_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Pruebas del servicio que descarga y entrega el PDF de la planilla propia.
///
/// El servicio no sabe ni de HTTP ni de `Blob`: lo que se prueba aquí es la
/// **secuencia** y los **cuatro desenlaces**. Antes esa secuencia habría estado
/// dentro del `State` de la pantalla, y por eso no se podría probar sin montar
/// una pantalla entera. Se espeja `hacer_export_service_test.dart`.
void main() {
  late FakePlanillaGateway gateway;
  late FakeSelectorDeArchivos selector;
  late PlanillaPdfService servicio;

  setUp(() {
    gateway = FakePlanillaGateway();
    selector = FakeSelectorDeArchivos();
    servicio = PlanillaPdfService(
      repositorio: PlanillaRepository(gateway: gateway),
      selector: selector,
    );
  });

  group('camino feliz', () {
    test('descarga el PDF y lo entrega al navegador con su nombre', () async {
      gateway.pdfDevuelto = [37, 80, 68, 70]; // %PDF

      final resultado = await servicio.descargarPlanillaPropia();

      expect(resultado, isA<PlanillaDescargada>());
      expect(selector.llamadas, ['descargarBytes']);
      expect(selector.ultimoNombreDeBytesDescargado, endsWith('.pdf'));
      expect(selector.ultimoTipoMimeBytesDescargado, 'application/pdf');
      // Lo que llega al navegador es el PDF, no un resumen.
      expect(selector.ultimoContenidoBytesDescargado, [37, 80, 68, 70]);
    });
  });

  group('SinFichaDeAspirante: el 404 no es un error', () {
    test('lo trata como SinFichaDeAspirante, no como ConsultaFallida', () async {
      //  El backend devuelve 404 `SIN_FICHA_DE_ASPIRANTE` antes de inscribirse.
      //  No debe pintarse como fallo rojo.
      gateway.errorAlDescargarPdf = AppException.validacion(
        'No tienes ficha de aspirante.',
        code: 'SIN_FICHA_DE_ASPIRANTE',
      );

      final resultado = await servicio.descargarPlanillaPropia();

      expect(resultado, isA<SinFichaDeAspirante>());
      expect(resultado, isNot(isA<ConsultaFallida>()));
      expect(selector.llamadas, isEmpty);
    });
  });

  group('los dos fallos se distinguen', () {
    test('un error de consulta (otro código) llega como ConsultaFallida', () async {
      gateway.errorAlDescargarPdf = AppException.validacion(
        'No autenticado',
        code: 'NO_AUTENTICADO',
      );

      final resultado = await servicio.descargarPlanillaPropia();

      expect(resultado, isA<ConsultaFallida>());
      expect((resultado as ConsultaFallida).mensaje, 'No autenticado');
      expect(selector.llamadas, isEmpty);
    });

    test('un fallo del navegador llega como DescargaFallida, no como consulta',
        () async {
      //  La mitad que falló importa: no es lo mismo que el backend no responda
      //  que que el navegador no pueda entregar el archivo, y el usuario no puede
      //  hacer nada con el `toString()` de un error de JavaScript.
      gateway.pdfDevuelto = [1, 2, 3];
      selector.errorAlDescargarBytes = StateError('el Blob no se pudo crear');

      final resultado = await servicio.descargarPlanillaPropia();

      expect(resultado, isA<DescargaFallida>());
      expect(resultado, isNot(isA<ConsultaFallida>()));
      expect(selector.llamadas, ['descargarBytes']);
    });

    test('el servicio NO lanza nunca: siempre devuelve un desenlace', () async {
      //  La pantalla consume con un `switch` exhaustivo, así que un `throw` que
      //  se escapara dejaría el botón girando sin aviso. Cualquier error se
      //  convierte en valor.
      gateway.errorAlDescargarPdf = Exception('boom');

      await expectLater(servicio.descargarPlanillaPropia(), completes);
    });
  });
}
