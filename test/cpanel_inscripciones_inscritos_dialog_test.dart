import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/inscripcion.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/repositories/planilla_admin_descarga_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripciones_inscritos_dialog.dart';
import 'package:inces_lms_app/services/planilla_admin_pdf_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_inscripcion_gateway.dart';
import 'support/fake_planilla_admin_descarga_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Pruebas del diálogo que lista los inscritos de una sección y descarga la
/// planilla de cada uno.
///
/// Es la única puerta de la interfaz a
/// `GET /api/v1/inscripcion/planilla/{usuarioId}/pdf`, así que lo que se fija
/// aquí no es «se pintó una lista»: es que el UUID que viaja al backend es **el
/// de la fila que se pulsó**. Un diálogo que descargara siempre la planilla del
/// primer estudiante pasaría una prueba que sólo contara llamadas.
void main() {
  late FakeInscripcionGateway inscripciones;
  late FakePlanillaAdminDescargaGateway descarga;
  late FakeSelectorDeArchivos selector;
  late AdminInscripcionesRepository repo;
  late PlanillaAdminPdfService planilla;

  setUp(() {
    inscripciones = FakeInscripcionGateway();
    descarga = FakePlanillaAdminDescargaGateway();
    selector = FakeSelectorDeArchivos();
    repo = AdminInscripcionesRepository(gateway: inscripciones);
    planilla = PlanillaAdminPdfService(
      repositorio: PlanillaAdminDescargaRepository(gateway: descarga),
      selector: selector,
    );
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: IncesTheme.claro(),
      home: Scaffold(
        body: InscritosSeccionDialog(
          repo: repo,
          planilla: planilla,
          seccionId: 'sec-1',
          seccionNombre: 'Soldadura por Arco',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Pulsa el botón de descarga de una fila.
  ///
  /// **`ensureVisible` antes del `tap`, y no es un paso de más.** El diálogo
  /// mide hasta 640 px de alto y el lienzo por defecto de `flutter test` es de
  /// 600: la última fila cae por debajo del pliegue, y un `tap` sobre algo que no
  /// está en el viewport **no acierta y tampoco se queja** —la aserción se cae
  /// tres líneas después culpando a otra cosa—. Es la trampa que ya documenta
  /// `lecciones.md` para el `Stepper`.
  Future<void> pulsarDescarga(WidgetTester tester, String estudianteId) async {
    final boton = find.byKey(Key('descargar-planilla-$estudianteId'));
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  List<InscripcionDetallada> dosInscritos() => [
        inscripcionDetalladaEjemplo(
          id: 'i-1',
          estudianteId: 'est-A',
          estado: EstadoInscripcion.enrolled,
          estudianteNombre: 'Ana Pérez',
          estudianteEmail: 'ana@inces.gob.ve',
        ),
        inscripcionDetalladaEjemplo(
          id: 'i-2',
          estudianteId: 'est-B',
          estado: EstadoInscripcion.waitlisted,
          posicionEnCola: 1,
          estudianteNombre: 'Beto López',
          estudianteEmail: 'beto@inces.gob.ve',
        ),
      ];

  group('la lista de inscritos', () {
    testWidgets('muestra a cada persona con su estado y su botón', (tester) async {
      inscripciones.inscripcionesDeSeccionDevueltas = dosInscritos();

      await montar(tester);

      expect(find.text('Inscritos — Soldadura por Arco'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('Beto López'), findsOneWidget);
      // El estado se lee en español, no como el valor del backend.
      expect(find.textContaining('Matriculado'), findsOneWidget);
      expect(find.textContaining('En cola'), findsOneWidget);
      // Un botón por persona: es lo que hace que la planilla sea de alguien.
      expect(find.byKey(const Key('descargar-planilla-est-A')), findsOneWidget);
      expect(find.byKey(const Key('descargar-planilla-est-B')), findsOneWidget);

      // La sección se pide a la que se pulsó, no a otra.
      expect(inscripciones.ultimaSeccion, 'sec-1');
      expect(
        inscripciones.llamadas,
        contains('obtenerInscripcionesDeSeccion:sec-1'),
      );
    });

    testWidgets('dice que está vacía sin pintarlo como error', (tester) async {
      inscripciones.inscripcionesDeSeccionDevueltas = const [];

      await montar(tester);

      expect(find.text('Nadie en la sección'), findsOneWidget);
    });

    testWidgets('un fallo de la consulta ofrece reintentar', (tester) async {
      inscripciones.errorAlObtenerInscripcionesDeSeccion =
          AppException.validacion('No autenticado', code: 'NO_AUTENTICADO');

      await montar(tester);

      expect(find.text('No se pudo cargar la lista'), findsOneWidget);
      expect(find.text('No autenticado'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('descargar la planilla de una persona', () {
    testWidgets('baja la planilla de LA FILA pulsada, con su nombre',
        (tester) async {
      inscripciones.inscripcionesDeSeccionDevueltas = dosInscritos();

      await montar(tester);
      await pulsarDescarga(tester, 'est-B');

      // El UUID que viaja es el de Beto, no el de la primera fila.
      expect(descarga.idsSolicitados, ['est-B']);
      expect(selector.llamadas, ['descargarBytes']);
      expect(selector.ultimoTipoMimeBytesDescargado, 'application/pdf');
      // El nombre del archivo identifica a la persona, que es lo que permite
      // distinguir varias planillas descargadas seguidas.
      expect(selector.ultimoNombreDeBytesDescargado, 'planilla-beto-lopez.pdf');
      expect(
        find.textContaining('Planilla de Beto López descargada'),
        findsOneWidget,
      );
    });

    testWidgets('«sin ficha» no se pinta como error, y nombra a la persona',
        (tester) async {
      //  Un estudiante matriculado puede no haber rellenado nunca la planilla de
      //  identidad. El backend responde 404 `SIN_FICHA_DE_ASPIRANTE`, que NO es
      //  un fallo: es una situación real del centro. Lo que sí tiene que hacer es
      //  decir a quién le falta el papel.
      inscripciones.inscripcionesDeSeccionDevueltas = dosInscritos();
      descarga.errorAlDescargarPdf = AppException.validacion(
        'Todavía no tienes una ficha de aspirante.',
        code: 'SIN_FICHA_DE_ASPIRANTE',
      );

      await montar(tester);
      await pulsarDescarga(tester, 'est-A');

      expect(
        find.textContaining('Ana Pérez todavía no tiene ficha de aspirante'),
        findsOneWidget,
      );
      // No llegó nada al navegador: no hay archivo que guardar.
      expect(selector.llamadas, isEmpty);
    });

    testWidgets('un fallo de consulta sí se pinta como error', (tester) async {
      inscripciones.inscripcionesDeSeccionDevueltas = dosInscritos();
      descarga.errorAlDescargarPdf = AppException.validacion(
        'No autenticado',
        code: 'NO_AUTENTICADO',
      );

      await montar(tester);
      await pulsarDescarga(tester, 'est-A');

      expect(find.text('No autenticado'), findsOneWidget);
      expect(selector.llamadas, isEmpty);
    });

    testWidgets('un fallo del navegador lo dice sin soltar el error crudo',
        (tester) async {
      inscripciones.inscripcionesDeSeccionDevueltas = dosInscritos();
      descarga.pdfDevuelto = [1, 2, 3];
      selector.errorAlDescargarBytes = StateError('el Blob no se pudo crear');

      await montar(tester);
      await pulsarDescarga(tester, 'est-A');

      // El `toString()` del error de JavaScript no llega al administrador: no le
      // dice nada y no puede hacer nada con él.
      expect(find.textContaining('el Blob no se pudo crear'), findsNothing);
      expect(
        find.textContaining('el navegador no pudo guardarlo'),
        findsOneWidget,
      );
    });
  });
}
