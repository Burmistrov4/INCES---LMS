import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripciones_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_inscripcion_gateway.dart';

/// Monta el panel de administración y espera la carga inicial.
///
/// `MaterialApp` con el tema institucional y `Scaffold(body: panel)`. El panel
/// usa un `Expanded` interno (como `ContenidoSeccion` en producción), así que
/// exige altura acotada: el `Scaffold` la da.
Future<void> montarPanel(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(
    MaterialApp(theme: IncesTheme.claro(), home: Scaffold(body: panel)),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> cerrarAvisos(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
}

/// Busca un botón cuyo `label` contiene el texto indicado, aunque esté
/// construido con el constructor `.icon` (su runtimeType es un subtipo privado,
/// así que `find.widgetWithText` —que usa `byType` interno— no lo encuentra).
Finder botonFilled(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<FilledButton>());

Finder botonOutlined(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<OutlinedButton>());

void main() {
  group('CpanelInscripcionesPanel (ocupación del admin)', () {
    testWidgets('ocupación vacía muestra el panel vacío', (tester) async {
      final repo = AdminInscripcionesRepository(
        gateway: FakeInscripcionGateway()..ocupacionDevuelta = const [],
      );
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));
      expect(find.text('No hay secciones'), findsOneWidget);
    });

    testWidgets('muestra métricas y la etiqueta «Oferta en el aire»', (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            cuposDisponibles: 2,
            cuposOcupados: 3,
            ofertaVigente: true,
          ),
          ocupacionSeccionEjemplo(
            id: 'sec-2',
            cuposDisponibles: 0,
            cuposOcupados: 5,
            ofertaVigente: false,
          ),
        ];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      // Etiquetas de las métricas presentes.
      expect(find.text('Secciones'), findsOneWidget);
      expect(find.text('Con oferta en el aire'), findsOneWidget);
      expect(find.text('Cupos disponibles'), findsOneWidget);
      expect(find.text('Cupos ocupados'), findsOneWidget);
      // La etiqueta destacada sólo sale para la sección con oferta vigente.
      expect(find.text('Oferta en el aire'), findsOneWidget);
    });

    testWidgets('«Promover siguiente» delega la sección al repositorio (éxito)',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [
          ocupacionSeccionEjemplo(id: 'sec-1', ofertaVigente: false),
          ocupacionSeccionEjemplo(id: 'sec-2', ofertaVigente: false),
        ];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      await tester.tap(
        botonFilled('Promover siguiente').at(0),
      );
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('promoverSiguiente:sec-1'));
    });

    testWidgets('«Promover siguiente» con cola vacía muestra aviso de validación',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo(id: 'sec-1')]
        ..errorAlPromover =
            const AppException.validacion('No hay nadie en la cola.');
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      await tester.tap(
        botonFilled('Promover siguiente'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // El aviso es de negocio, no un error técnico disfrazado.
      expect(find.text('No hay nadie en la cola.'), findsOneWidget);
      // La llamada se hizo igual (el gateway registra antes de lanzar).
      expect(fake.llamadas, contains('promoverSiguiente:sec-1'));
      await cerrarAvisos(tester);
    });

    testWidgets('«Expirar ofertas» delega al repositorio', (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo(id: 'sec-1')];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      await tester.tap(
        botonOutlined('Expirar ofertas'),
      );
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('expirarOfertas'));
    });

    testWidgets('Reincorporar valida los ids antes de llamar al repositorio',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo(id: 'sec-1')];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      // Abre el diálogo.
      await tester.tap(botonFilled('Reincorporar'));
      await tester.pumpAndSettle();
      expect(find.text('Reincorporar estudiante'), findsOneWidget);

      // Confirmar con los campos vacíos: el validador lo bloquea, no hay llamada.
      final confirmar = find.descendant(
        of: find.byType(AlertDialog),
        matching: botonFilled('Reincorporar'),
      );
      await tester.tap(confirmar);
      await tester.pump();
      expect(fake.llamadas.any((c) => c.startsWith('reincorporar:')), isFalse);

      // Con los ids completos, sí llama.
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'est-9',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'sec-9',
      );
      await tester.tap(confirmar);
      await tester.pumpAndSettle();

      expect(fake.llamadas, contains('reincorporar:est-9:sec-9'));
    });
  });
}
