import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/screens/crear_anuncio_panel.dart';
import 'support/fake_aula_gateway.dart';

void main() {
  late FakeAulaGateway fake;

  /// Abre el panel sobre un navigator con una ruta previa, para poder verificar
  /// que al guardar el panel se cierra (pop) y vuelve el botón «abrir».
  Future<void> cargar(WidgetTester tester) async {
    fake = FakeAulaGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CrearAnuncioPanel(
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

  testWidgets('crea un anuncio con título y cuerpo y cierra el panel',
      (tester) async {
    await cargar(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Bienvenidos');
    await tester.enterText(find.byType(TextFormField).at(1), 'Hola curso');
    final boton = find.widgetWithText(FilledButton, 'Publicar anuncio');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    // El gateway recibió la sección y los campos exactos.
    expect(fake.ultimaSeccionAnuncio, 'sec-1');
    expect(fake.ultimoTituloAnuncio, 'Bienvenidos');
    expect(fake.ultimoCuerpoAnuncio, 'Hola curso');
    expect(fake.llamadas, contains('crearAnuncio:sec-1'));

    // El panel se cerró: volvemos al botón «abrir» y el formulario desapareció.
    expect(find.text('abrir'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Publicar anuncio'), findsNothing);
  });

  testWidgets('valida el título vacío y no llama al gateway', (tester) async {
    await cargar(tester);

    final boton = find.widgetWithText(FilledButton, 'Publicar anuncio');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(find.text('Escribe un título.'), findsOneWidget);
    expect(fake.llamadas, isNot(contains('crearAnuncio:sec-1')));
    // El panel sigue abierto.
    expect(find.widgetWithText(FilledButton, 'Publicar anuncio'), findsOneWidget);
  });
}
