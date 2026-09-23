import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/models/seccion.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/repositories/secciones_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripciones_cola_dialog.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripciones_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_secciones_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_inscripcion_gateway.dart';
import 'support/fake_secciones_gateway.dart';

/// Auditoría de layout responsive de los paneles de M4 (Inscripciones y Cupos).
///
/// **Por qué esto es un test y no una captura de pantalla.** La auditoría en
/// navegador no puede cubrir el layout de estas pantallas por dos motivos
/// independientes: Flutter Web pinta en un único `<canvas>` (CanvasKit), así
/// que Playwright no ve los widgets ni puede pulsarlos ni teclear; y las
/// aserciones de layout están **apagadas en `--release`**, así que un build de
/// producción no emite el aviso aunque desborde.
///
/// En un widget test, en cambio, un `RenderFlex overflowed` **lanza una
/// excepción** y rompe la prueba. Montar el panel a 375 px *es* la auditoría,
/// y además queda como red permanente en vez de como evidencia de un momento.
///
/// Los tamaños no son arbitrarios: 375×812 es el ancho lógico del móvil más
/// común, y por debajo de 900 px el andamiaje del proyecto cambia a cajón
/// (`Drawer`), que es donde un panel ancho suele reventar. 1440×900 es el
/// escritorio de referencia del proyecto.
void main() {
  const movil = Size(375, 812);
  const escritorio = Size(1440, 900);

  /// Monta [hijo] a [tamano] dentro de su **padre real**.
  ///
  /// `devicePixelRatio` en 1.0 para que `physicalSize` sea el tamaño lógico y
  /// las cuentas de la prueba sean las que se leen.
  ///
  /// **El `ContenidoSeccion` no es decorativo.** Es el padre que el panel tiene
  /// en la app: aporta el `anchoMaximo` de 1280 y el scroll. Montar el panel
  /// suelto en un `Scaffold` pelado cambia el layout y produce desbordes que el
  /// producto no tiene — mediría mi arnés, no el panel. Los demás paneles del
  /// proyecto se montan igual por este mismo motivo.
  Future<void> montarA(WidgetTester tester, Size tamano, Widget hijo) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ContenidoSeccion(
            migas: const ['Inicio', 'Inscripciones y Cupos'],
            child: hijo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Un desborde de layout se registra como excepción; sin este `expect` el
  /// fallo llegaría igual, pero con un mensaje que no dice qué pantalla ni qué
  /// tamaño lo provocó.
  void sinDesbordes(WidgetTester tester, String pantalla, Size tamano) {
    expect(
      tester.takeException(),
      isNull,
      reason: '$pantalla desborda a ${tamano.width.toInt()} px de ancho',
    );
  }

  group('CpanelSeccionesPanel · sin desbordes en móvil ni escritorio', () {
    Future<void> montarPanel(WidgetTester tester, Size tamano) async {
      final fake = FakeSeccionesGateway()
        ..paginaDevuelta = PaginaSecciones(
          secciones: [
            seccionEjemplo(id: 's-1', nombre: 'SA'),
            seccionEjemplo(id: 's-2', nombre: 'SB'),
          ],
          total: 2,
          limite: 50,
          desplazamiento: 0,
        );
      await montarA(
        tester,
        tamano,
        CpanelSeccionesPanel(repositorio: SeccionesRepository(gateway: fake)),
      );
    }

    testWidgets('a 375 px (móvil)', (tester) async {
      await montarPanel(tester, movil);
      expect(find.text('SA'), findsOneWidget);
      sinDesbordes(tester, 'CpanelSeccionesPanel', movil);
    });

    testWidgets('a 1440 px (escritorio)', (tester) async {
      await montarPanel(tester, escritorio);
      expect(find.text('Total: 2'), findsOneWidget);
      sinDesbordes(tester, 'CpanelSeccionesPanel', escritorio);
    });

    testWidgets('el estado vacío tampoco desborda a 375 px', (tester) async {
      // El vacío es el caso que más se olvida: sin filas, la cabecera y el CTA
      // quedan solos y es donde una `Row` sin `Wrap` se sale del ancho.
      final fake = FakeSeccionesGateway()
        ..paginaDevuelta = const PaginaSecciones(
          secciones: [],
          total: 0,
          limite: 50,
          desplazamiento: 0,
        );
      await montarA(
        tester,
        movil,
        CpanelSeccionesPanel(repositorio: SeccionesRepository(gateway: fake)),
      );
      sinDesbordes(tester, 'CpanelSeccionesPanel (vacío)', movil);
    });
  });

  group('CpanelInscripcionesPanel · sin desbordes en móvil ni escritorio', () {
    Future<void> montarPanel(WidgetTester tester, Size tamano) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [
          ocupacionSeccionEjemplo(id: 'sec-1', nombre: 'Soldadura por Arco'),
          ocupacionSeccionEjemplo(
            id: 'sec-2',
            nombre: 'Soldadura TIG',
            cuposOcupados: 5,
            cuposDisponibles: 0,
            ofertaVigente: true,
          ),
        ];
      await montarA(
        tester,
        tamano,
        CpanelInscripcionesPanel(
          repositorio: AdminInscripcionesRepository(gateway: fake),
        ),
      );
    }

    testWidgets('a 375 px (móvil)', (tester) async {
      await montarPanel(tester, movil);
      expect(find.text('Soldadura por Arco'), findsWidgets);
      sinDesbordes(tester, 'CpanelInscripcionesPanel', movil);
    });

    testWidgets('a 1440 px (escritorio)', (tester) async {
      await montarPanel(tester, escritorio);
      expect(find.text('Soldadura por Arco'), findsWidgets);
      sinDesbordes(tester, 'CpanelInscripcionesPanel', escritorio);
    });

    testWidgets('sin ocupación tampoco desborda a 375 px', (tester) async {
      final fake = FakeInscripcionGateway()..ocupacionDevuelta = const [];
      await montarA(
        tester,
        movil,
        CpanelInscripcionesPanel(
          repositorio: AdminInscripcionesRepository(gateway: fake),
        ),
      );
      sinDesbordes(tester, 'CpanelInscripcionesPanel (vacío)', movil);
    });
  });

  group('ColaSeccionDialog · sin desbordes con nombres largos', () {
    Future<void> montarDialogo(WidgetTester tester, Size tamano) async {
      final fake = FakeInscripcionGateway()
        // Un nombre de alumno largo y una sección larga: si algo va a
        // desbordar en una `Row` de cola, es con el texto largo, no con
        // «Ana». Probar con el caso cómodo no prueba nada.
        ..colaDevuelta = [
          inscripcionDetalladaEjemplo(
            id: 'i-1',
            posicionEnCola: 1,
            estudianteNombre: 'Lorenzo Alejandro Roca Martínez',
            estudianteEmail: 'lorenzo.roca.martinez@inces.gob.ve',
          ),
          inscripcionDetalladaEjemplo(
            id: 'i-2',
            posicionEnCola: 2,
            estudianteNombre: 'Sleither Vásquez',
          ),
        ];
      await montarA(
        tester,
        tamano,
        ColaSeccionDialog(
          repo: AdminInscripcionesRepository(gateway: fake),
          seccionId: 'sec-1',
          seccionNombre: 'Soldadura por Arco con Electrodo Revestido (SA26-2)',
        ),
      );
    }

    testWidgets('a 375 px (móvil)', (tester) async {
      await montarDialogo(tester, movil);
      expect(find.text('Sleither Vásquez'), findsOneWidget);
      sinDesbordes(tester, 'ColaSeccionDialog', movil);
    });

    testWidgets('a 1440 px (escritorio)', (tester) async {
      await montarDialogo(tester, escritorio);
      expect(find.text('Sleither Vásquez'), findsOneWidget);
      sinDesbordes(tester, 'ColaSeccionDialog', escritorio);
    });

    testWidgets('cola vacía a 375 px', (tester) async {
      final fake = FakeInscripcionGateway()..colaDevuelta = const [];
      await montarA(
        tester,
        movil,
        ColaSeccionDialog(
          repo: AdminInscripcionesRepository(gateway: fake),
          seccionId: 'sec-1',
          seccionNombre: 'Soldadura por Arco',
        ),
      );
      sinDesbordes(tester, 'ColaSeccionDialog (vacía)', movil);
    });
  });
}
