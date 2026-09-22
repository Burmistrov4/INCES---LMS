import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/screens/mis_aulas_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_aula_gateway.dart';

/// Pruebas del listado «Mis aulas».
///
/// Cubren lo que el gateway no puede: que la pantalla **pida el listado**, que
/// pinte una tarjeta por aula, y que pulsar una abra el Aula Virtual **de esa
/// sección** —con la misma etiqueta y con el rol que vino en el payload—.
///
/// El panel trae su propio `ContenidoSeccion`, así que se monta en el `body` de
/// un `Scaffold`, que es el contrato de altura con el que lo montan los
/// dashboards. Montarlo dentro de otro `ContenidoSeccion` sería montarlo en un
/// contenedor que no existe.
Future<void> montar(
  WidgetTester tester, {
  required FakeAulaGateway gateway,
  bool conPuertaDeContenido = true,
}) async {
  // Ventana alta: el listado es un `ListView` y con la ventana por defecto
  // (800×600) las tarjetas quedarían fuera del viewport y `find.text` no las
  // encontraría. No es que falte el dato: es que no se pintó.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: Scaffold(
        body: PanelMisAulas(
          gateway: gateway,
          aulaGateway: conPuertaDeContenido ? gateway : null,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Avanza lo justo para que terminen las cargas.
///
/// **Sin `pumpAndSettle` a propósito.** Mientras carga, la pantalla pinta un
/// `CircularProgressIndicator`, que anima indefinidamente: `pumpAndSettle` no
/// terminaría y agotaría su tiempo límite. Sería un fallo de la prueba, no del
/// código.
Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// Busca un texto sin distinguir mayúsculas.
///
/// Hace falta porque el título del aula pasa por `TituloSeccion`, que lo pinta
/// en mayúsculas: la etiqueta de la tarjeta y el título del aula son el mismo
/// dato, pero no el mismo caso.
Finder texto(String contenido) => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data ?? '').toUpperCase() == contenido.toUpperCase(),
      description: 'texto «$contenido», sin distinguir mayúsculas',
    );

/// La etiqueta del aula de ejemplo por defecto.
const String etiquetaA = 'Soldadura · Sección A · Formación Profesional';

void main() {
  group('PanelMisAulas · el listado', () {
    testWidgets('pide el listado y pinta una tarjeta por aula', (tester) async {
      final gateway = FakeAulaGateway()
        ..misAulasResultado = misAulasEjemplo(
          aulas: [
            aulaEjemplo(seccionId: 'sec-1'),
            aulaEjemplo(
              seccionId: 'sec-2',
              materia: 'Electricidad',
              seccion: 'Sección B',
              programa: null,
            ),
          ],
        );

      await montar(tester, gateway: gateway);
      await asentar(tester);

      expect(gateway.llamadas, contains('misAulas'));
      expect(texto(etiquetaA), findsOneWidget);
      expect(texto('Electricidad · Sección B'), findsOneWidget);
    });

    testWidgets('sin aulas explica por qué, en vez de dejar la pantalla vacía',
        (tester) async {
      final gateway = FakeAulaGateway()
        ..misAulasResultado =
            const MisAulas(esDocente: false, periodo: 'SA26-2');

      await montar(tester, gateway: gateway);
      await asentar(tester);

      expect(find.text('Todavía no tienes aulas activas'), findsOneWidget);
      // El lapso se dice: un vacío sin contexto no distingue «no hay clases» de
      // «no hay lapso vigente».
      expect(find.textContaining('SA26-2'), findsWidgets);
    });

    testWidgets('un fallo se cuenta con su mensaje y un reintento', (tester) async {
      final gateway = FakeAulaGateway()
        ..errorAlListarAulas = const AppException(
          type: AppErrorType.red,
          message: 'No pudimos conectar con el servidor.',
        );

      await montar(tester, gateway: gateway);
      await asentar(tester);

      expect(find.text('No pudimos cargar esta sección'), findsOneWidget);
      expect(find.text('No pudimos conectar con el servidor.'), findsOneWidget);

      // El reintento vuelve a pedir el listado de verdad, no repinta lo viejo.
      gateway
        ..errorAlListarAulas = null
        ..misAulasResultado = misAulasEjemplo();
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(texto(etiquetaA), findsOneWidget);
      expect(gateway.llamadas.where((l) => l == 'misAulas'), hasLength(2));
    });

    testWidgets('sin puerta de contenido la tarjeta no se puede pulsar',
        (tester) async {
      // El listado viene de una ruta congelada y es real; el contenido del aula
      // no. Sin puerta, la tarjeta no promete algo que no puede cumplir.
      final gateway = FakeAulaGateway()..misAulasResultado = misAulasEjemplo();

      await montar(tester, gateway: gateway, conPuertaDeContenido: false);
      await asentar(tester);

      expect(
        find.textContaining('Estas son tus secciones reales'),
        findsOneWidget,
      );

      await tester.tap(texto(etiquetaA), warnIfMissed: false);
      await asentar(tester);

      // Sigue en el listado y no se pidió ningún tablón.
      expect(texto(etiquetaA), findsOneWidget);
      expect(gateway.llamadas.where((l) => l.startsWith('tablon')), isEmpty);
    });
  });

  group('PanelMisAulas · abrir un aula', () {
    testWidgets('abre el aula de la sección pulsada, con su etiqueta',
        (tester) async {
      final gateway = FakeAulaGateway()
        ..misAulasResultado = misAulasEjemplo(
          aulas: [
            aulaEjemplo(seccionId: 'sec-1'),
            aulaEjemplo(
              seccionId: 'sec-2',
              materia: 'Electricidad',
              seccion: 'Sección B',
              programa: null,
            ),
          ],
        )
        ..anuncios = [
          anuncioEjemplo(
            seccionId: 'sec-2',
            titulo: 'Bienvenidos a Electricidad',
          ),
        ];

      await montar(tester, gateway: gateway);
      await asentar(tester);

      await tester.tap(texto('Electricidad · Sección B'));
      await asentar(tester);

      // Se pidió el tablón de **esa** sección, no el de la primera del listado.
      expect(gateway.ultimaSeccionTablon, 'sec-2');
      expect(gateway.llamadas, contains('tablon:sec-2'));
      expect(find.text('Bienvenidos a Electricidad'), findsOneWidget);
      // El título del aula es la misma etiqueta que la tarjeta: no hay dos
      // composiciones del mismo dato que puedan discrepar.
      expect(texto('Electricidad · Sección B'), findsOneWidget);
    });

    testWidgets('el rol del payload decide la vista del aula', (tester) async {
      // Docente: el aula no pide `misEntregas` —esa ruta es del alumno y
      // devolvería 403— y no ofrece el panel de subida del estudiante.
      final gateway = FakeAulaGateway()
        ..misAulasResultado = misAulasEjemplo(esDocente: true);

      await montar(tester, gateway: gateway);
      await asentar(tester);

      await tester.tap(texto(etiquetaA));
      await asentar(tester);

      expect(gateway.llamadas, isNot(contains('misEntregas')));
    });

    testWidgets('volver regresa al listado', (tester) async {
      // Sin este botón el usuario quedaría encerrado: volver a pulsar «Mis
      // aulas» en el menú no reinicia el estado del panel, porque el widget se
      // conserva.
      final gateway = FakeAulaGateway()..misAulasResultado = misAulasEjemplo();

      await montar(tester, gateway: gateway);
      await asentar(tester);

      await tester.tap(texto(etiquetaA));
      await asentar(tester);
      expect(find.text('Volver a Mis aulas'), findsOneWidget);

      await tester.tap(find.text('Volver a Mis aulas'));
      await asentar(tester);

      expect(find.text('Volver a Mis aulas'), findsNothing);
      expect(texto(etiquetaA), findsOneWidget);
    });
  });
}
