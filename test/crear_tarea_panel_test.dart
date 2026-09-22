import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/screens/crear_tarea_panel.dart';
import 'support/fake_aula_gateway.dart';

void main() {
  late FakeAulaGateway fake;

  Future<void> cargar(WidgetTester tester) async {
    fake = FakeAulaGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CrearTareaPanel(
                    seccionId: 'sec-1',
                    gateway: fake,
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('crea y publica una TAREA y genera los placeholders',
      (tester) async {
    await cargar(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Informe');
    final boton = find.widgetWithText(FilledButton, 'Crear y publicar');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(fake.ultimoTipoTarea, TipoTarea.tarea);
    expect(fake.ultimaSeccionTarea, 'sec-1');
    // Dos llamadas encadenadas: crear (borrador) y publicar (placeholders).
    expect(
      fake.llamadas,
      containsAll(['crearTarea:sec-1', 'publicarTarea:tar-nueva']),
    );
    // La pantalla de éxito reporta cuántas entregas se crearon.
    expect(find.textContaining('12 entrega'), findsOneWidget);
  });

  testWidgets('un MATERIAL no muestra ni envía puntos', (tester) async {
    await cargar(tester);

    // El campo de puntos existe para TAREA...
    expect(find.text('Puntos máximos (0–20, opcional)'), findsOneWidget);
    // ...y desaparece al elegir MATERIAL.
    final tipoTarea = find.text('Tarea (se califica)').first;
    await tester.ensureVisible(tipoTarea);
    await tester.tap(tipoTarea);
    await tester.pumpAndSettle();
    final material = find.text('Material (de lectura)').last;
    await tester.ensureVisible(material);
    await tester.tap(material);
    await tester.pumpAndSettle();
    expect(find.text('Puntos máximos (0–20, opcional)'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Lectura');
    final boton = find.widgetWithText(FilledButton, 'Crear y publicar');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(fake.ultimoTipoTarea, TipoTarea.material);
    // Lo que no se muestra no se envía: el backend recibe null, no un 0 que
    // reventaría el CHECK de material.
    expect(fake.ultimosPuntosTarea, isNull);
    expect(fake.llamadas, contains('crearTarea:sec-1'));
    expect(find.textContaining('12 entrega'), findsOneWidget);
  });

  testWidgets('valida el título vacío de la tarea', (tester) async {
    await cargar(tester);

    final boton = find.widgetWithText(FilledButton, 'Crear y publicar');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(find.text('Escribe un título.'), findsOneWidget);
    expect(fake.llamadas, isNot(contains('crearTarea:sec-1')));
  });
}
