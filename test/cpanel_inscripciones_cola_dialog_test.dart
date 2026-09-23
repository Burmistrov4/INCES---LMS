import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/models/inscripcion.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripciones_cola_dialog.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_inscripcion_gateway.dart';

void main() {
  group('ColaSeccionDialog — vista de cola FIFO del administrador', () {
    testWidgets('lista la cola en orden con posición visible', (tester) async {
      final fake = FakeInscripcionGateway()
        ..colaDevuelta = [
          inscripcionDetalladaEjemplo(
            id: 'i-1',
            estudianteId: 'est-A',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: 1,
            estudianteNombre: 'Ana Pérez',
            estudianteEmail: 'ana@inces.gob.ve',
          ),
          inscripcionDetalladaEjemplo(
            id: 'i-2',
            estudianteId: 'est-B',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: 2,
            estudianteNombre: 'Beto López',
            estudianteEmail: 'beto@inces.gob.ve',
          ),
        ];
      final repo = AdminInscripcionesRepository(gateway: fake);

      await tester.pumpWidget(MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ColaSeccionDialog(
            repo: repo,
            seccionId: 'sec-1',
            seccionNombre: 'Soldadura por Arco',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Cola — Soldadura por Arco'), findsOneWidget);
      // Posición visible por candidato (la garantía de la cola FIFO).
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('Beto López'), findsOneWidget);
      expect(find.text('ana@inces.gob.ve'), findsOneWidget);
      expect(fake.ultimaSeccion, 'sec-1');
      expect(fake.llamadas, contains('obtenerCola:sec-1'));
    });

    testWidgets('muestra estado vacío claro si no hay candidatos', (tester) async {
      final fake = FakeInscripcionGateway()..colaDevuelta = const [];
      final repo = AdminInscripcionesRepository(gateway: fake);

      await tester.pumpWidget(MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ColaSeccionDialog(
            repo: repo,
            seccionId: 'sec-vacia',
            seccionNombre: 'Sección sin cola',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nadie en cola'),
        findsOneWidget,
        reason: 'El estado vacío debe explicar el caso, no quedar mudo',
      );
    });

    testWidgets('reintenta cuando la primera petición falla', (tester) async {
      final fake = FakeInscripcionGateway()
        ..errorAlObtenerCola = Exception('red caída')
        ..colaDevuelta = [
          inscripcionDetalladaEjemplo(estudianteNombre: 'Recuperada'),
        ];
      final repo = AdminInscripcionesRepository(gateway: fake);

      await tester.pumpWidget(MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ColaSeccionDialog(
            repo: repo,
            seccionId: 'sec-1',
            seccionNombre: 'X',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // El título nombra QUÉ falló; el mensaje traducido va debajo. Si el título
// repitiera «Ocurrió un error», las dos líneas dirían lo mismo.
      expect(find.text('No se pudo cargar la cola'), findsOneWidget);
      final boton = find.widgetWithText(FilledButton, 'Reintentar');
      expect(boton, findsOneWidget);

      // Se emitieron exactamente DOS consultas: la que falló y la del reintento.
      // Sin esta aserción, un botón que no hiciera nada daría verde mientras
      // la pantalla siguiera en error.
      final antes = fake.llamadas.where((l) => l == 'obtenerCola:sec-1').length;
      expect(antes, 1);

      // La red se recuperó: sin esto el doble seguiría fallando y el reintento
      // no probaría nada.
      fake.errorAlObtenerCola = null;

      await tester.tap(boton);
      await tester.pumpAndSettle();
      expect(find.text('Recuperada'), findsOneWidget);
      expect(
        fake.llamadas.where((l) => l == 'obtenerCola:sec-1').length,
        2,
        reason: 'El reintento debe volver a consultar, no sólo repintar',
      );
    });
  });
}