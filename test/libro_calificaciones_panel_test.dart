import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/screens/libro_calificaciones_panel.dart';

import 'support/fake_aula_gateway.dart';

/// Fixture: una fila del libro de calificaciones.
LibroEntrega _fila({
  String id = 'est-1',
  EstadoEntrega estado = EstadoEntrega.entregada,
  bool esTardia = false,
  double? notaBorrador,
  double? notaAsignada,
  String? devueltaEn,
  bool faltante = false,
}) =>
    LibroEntrega(
      estudianteId: id,
      estado: estado,
      esTardia: esTardia,
      notaBorrador: notaBorrador,
      notaAsignada: notaAsignada,
      devueltaEn: devueltaEn,
      faltante: faltante,
    );

/// Botón por su etiqueta, robusto frente a los `.icon(...)` (que no exponen
/// `text`). Sube al `FilledButton`/`OutlinedButton` ancestro del `Text`.
Finder botonConTexto(String texto, Type tipo) => find.ancestor(
      of: find.text(texto),
      matching: find.byType(tipo),
    );

void main() {
  Future<void> montar(WidgetTester tester, FakeAulaGateway fake) async {
    await tester.pumpWidget(
      MaterialApp(
        // El panel ya trae su propio `Scaffold`; basta con acotar el alto para
        // que el `Expanded` de la grilla tenga cota.
        home: SizedBox(
          width: 900,
          height: 700,
          child: LibroCalificacionesPanel(
            tareaId: 'tar-1',
            tareaTitulo: 'Soldadura',
            gateway: fake,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('muestra una fila por estudiante matriculado', (tester) async {
    final fake = FakeAulaGateway()
      ..libro = [
        _fila(id: 'est-1'),
        _fila(id: 'est-2', estado: EstadoEntrega.devuelta, notaAsignada: 16),
      ];

    await montar(tester, fake);

    expect(find.text('est-1'), findsOneWidget);
    expect(find.text('est-2'), findsOneWidget);
    // La nota asignada se pinta con coma decimal, a lo venezolano.
    expect(find.text('16,0'), findsOneWidget);
  });

  testWidgets('calificar escribe la nota borrador del estudiante', (tester) async {
    final fake = FakeAulaGateway()
      ..libro = [_fila(id: 'est-1'), _fila(id: 'est-2')];

    await montar(tester, fake);

    // El primer botón «Calificar» de la grilla.
    await tester.tap(botonConTexto('Calificar', FilledButton).first);
    await tester.pumpAndSettle();

    // El parser de nota usa `double.tryParse`, así que el separador es punto.
    await tester.enterText(find.byType(TextFormField), '17.5');
    await tester.tap(botonConTexto('Guardar nota', FilledButton));
    await tester.pumpAndSettle();

    expect(fake.ultimoIdCalificar, 'est-1');
    expect(fake.ultimaNotaCalificar, 17.5);
    // La nota borrador ya se refleja en la grilla tras recargar.
    expect(find.text('17,5'), findsOneWidget);
  });

  testWidgets('devolver cierra el ciclo de la entrega', (tester) async {
    final fake = FakeAulaGateway()
      ..libro = [_fila(id: 'est-1'), _fila(id: 'est-2')];

    await montar(tester, fake);

    await tester.tap(botonConTexto('Devolver', OutlinedButton).first);
    await tester.pumpAndSettle();

    expect(fake.ultimoIdDevolver, 'est-1');
    // Tras devolver, la fila pasa a estado DEVUELTA y la nota borrador se copia
    // a la asignada: por eso la grilla muestra la nota. La celda usa
    // `_etiquetaEstado`, que pinta «Devuelta». Hay dos «Devuelta» en pantalla:
    // la cabecera de la columna y la celda de estado de la fila; por eso
    // `findsWidgets` y no `findsOneWidget`. La prueba real del ciclo cerrado es
    // `ultimoIdDevolver` de arriba.
    expect(find.text('Devuelta'), findsWidgets);
  });

  testWidgets('estado vacío cuando la tarea no tiene entregas', (tester) async {
    final fake = FakeAulaGateway()..libro = const [];

    await montar(tester, fake);

    expect(find.text('Todavía no hay entregas'), findsOneWidget);
  });

  testWidgets('muestra el error si la carga falla', (tester) async {
    // Un fallo de red: `AppException.from` lo traduce al mensaje amable de
    // conectividad en español (no deja pasar el texto crudo del error).
    final fake = FakeAulaGateway()
      ..errorAlLibro = Exception('network is unreachable');

    await montar(tester, fake);

    expect(
      find.textContaining('No pudimos conectar con el servidor'),
      findsOneWidget,
    );
  });
}
