import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/models/seccion.dart';
import 'package:inces_lms_app/repositories/secciones_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_secciones_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_secciones_gateway.dart';

void main() {
  group('CpanelSeccionesPanel — CRUD de secciones (admin)', () {
    testWidgets('muestra la lista paginada del repositorio', (tester) async {
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
      final repo = SeccionesRepository(gateway: fake);

      await tester.pumpWidget(MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: CpanelSeccionesPanel(repositorio: repo),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SA'), findsOneWidget);
      expect(find.text('SB'), findsOneWidget);
      // El total se pinta en un único Text («Total: 2»): find.text hace
      // coincidencia EXACTA, así que buscar '2' a secas no lo encuentra.
      expect(find.text('Total: 2'), findsOneWidget);
      expect(fake.llamadas, contains('listarSecciones'));
    });

    testWidgets('abre el diálogo de creación al pulsar «Nueva sección»',
        (tester) async {
      final fake = FakeSeccionesGateway()
        ..paginaDevuelta = const PaginaSecciones(
          secciones: [],
          total: 0,
          limite: 50,
          desplazamiento: 0,
        );
      final repo = SeccionesRepository(gateway: fake);

      await tester.pumpWidget(MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(body: CpanelSeccionesPanel(repositorio: repo)),
      ));
      await tester.pumpAndSettle();

      // El CTA vive en la cabecera.
      await tester.tap(find.widgetWithText(FilledButton, 'Nueva sección'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva sección'), findsWidgets); // el del diálogo
      expect(
        find.byType(TextFormField),
        findsAtLeast(3),
        reason: 'Tres campos mínimos: programa, materia, nombre',
      );
    });

    testWidgets('al archivar pide confirmación y luego PATCH',
        (tester) async {
      final fake = FakeSeccionesGateway()
        ..paginaDevuelta = PaginaSecciones(
          secciones: [seccionEjemplo(id: 's-1', nombre: 'SA')],
          total: 1,
          limite: 50,
          desplazamiento: 0,
        );
      final repo = SeccionesRepository(gateway: fake);

      await tester.pumpWidget(MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(body: CpanelSeccionesPanel(repositorio: repo)),
      ));
      await tester.pumpAndSettle();

      // Botón archivar (icon-only) de la fila.
      await tester.tap(find.byTooltip('Archivar'));
      await tester.pumpAndSettle();

      // El diálogo de confirmación aparece.
      expect(
        find.textContaining('Archivar'),
        findsAtLeast(2),
        reason: 'título del diálogo + confirmación textual',
      );

      // Confirmamos.
      await tester.tap(find.widgetWithText(FilledButton, 'Archivar'));
      await tester.pumpAndSettle();

      expect(fake.ultimaIdActualizada, 's-1');
      expect(fake.ultimosCambios?.activa, isFalse);
      // Y se vuelve a pedir el listado (la UI recarga tras mutar).
      expect(fake.llamadas.where((l) => l == 'listarSecciones').length,
          greaterThanOrEqualTo(2));
    });
  });
}