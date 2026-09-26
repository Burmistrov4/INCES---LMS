import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/repositories/aspirante_repository.dart';
import 'package:inces_lms_app/screens/landing_page.dart';

import 'support/fake_gateway.dart';

/// Pruebas de la portada pública (la raíz `/` sin sesión).
///
/// La portada lee la oferta formativa del Módulo 2 con
/// `AspiranteRepository.obtenerProgramasDisponibles()`. Se le inyecta un doble
/// para no tocar la red, igual que hacen el resto de pruebas del proyecto.
void main() {
  late FakeGateway gateway;

  setUp(() => gateway = FakeGateway());

  /// Monta la portada con las dos rutas a las que apuntan sus botones.
  Widget montar() {
    return MaterialApp(
      home: LandingPage(
        aspiranteRepository: AspiranteRepository(gateway: gateway),
      ),
      routes: {
        '/inscripcion': (_) => const Scaffold(body: Text('FORMULARIO')),
        '/login': (_) => const Scaffold(body: Text('LOGIN')),
      },
    );
  }

  testWidgets('muestra la identidad institucional en el hero', (tester) async {
    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    expect(find.textContaining('Rafael Urdaneta'), findsWidgets);
    expect(find.text('INCES LMS'), findsOneWidget);
    expect(find.text('INCES La Isabelica'), findsOneWidget);
  });

  testWidgets('pinta una tarjeta por curso de la oferta real', (tester) async {
    gateway.programas = const [
      OpcionCampo(valor: 'uuid-herreria', etiqueta: 'Herrería'),
      OpcionCampo(valor: 'uuid-soldadura', etiqueta: 'Soldadura por Arco'),
    ];

    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    expect(find.text('Herrería'), findsOneWidget);
    expect(find.text('Soldadura por Arco'), findsOneWidget);
    expect(gateway.llamadas, contains('programasDisponibles'));
  });

  testWidgets('un fallo de la oferta se avisa y ofrece reintentar',
      (tester) async {
    gateway.errorAlProgramas = const AppException.validacion('sin red');

    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos cargar la oferta'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('una oferta vacía se distingue de un fallo', (tester) async {
    gateway.programas = const [];

    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    expect(find.textContaining('Todavía no hay cursos'), findsOneWidget);
    expect(find.textContaining('No pudimos cargar la oferta'), findsNothing);
  });

  testWidgets('el botón Inscribirse lleva al formulario de inscripción',
      (tester) async {
    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inscribirse'));
    await tester.pumpAndSettle();

    expect(find.text('FORMULARIO'), findsOneWidget);
  });

  testWidgets('el botón Portal Académico lleva al login', (tester) async {
    await tester.pumpWidget(montar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Portal Académico'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });
}
