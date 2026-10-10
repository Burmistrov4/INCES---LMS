import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

void main() {
  testWidgets('el botón Menú abre el cajón en móvil', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: AndamiajeApp(
          items: const [
            ItemNavegacion(
              icono: Icons.home_outlined,
              titulo: 'Inicio de prueba',
              categoria: 'General',
            ),
          ],
          seleccionado: 0,
          onSeleccionar: (_) {},
          rolEtiqueta: 'Administrador',
          contenido: const Center(child: Text('Contenido de prueba')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Menú'), findsOneWidget);
    expect(find.text('Inicio de prueba'), findsNothing);
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();

    expect(find.text('Inicio de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
