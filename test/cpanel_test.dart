import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/config_audit_entry.dart';
import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/models/system_setting.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_auditoria_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_modulos_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_parametros_panel.dart';

import 'support/fake_gateway.dart';

/// Monta un panel y espera a que termine su carga inicial.
///
/// No se usa `pumpAndSettle` para el arranque: mientras carga hay un
/// `CircularProgressIndicator`, cuya animación es infinita y haría que
/// `pumpAndSettle` agotara el tiempo de espera.
Future<void> montarPanel(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: panel)));
  await tester.pump();
  await tester.pump();
}

/// Deja pasar el tiempo suficiente para que el SnackBar se cierre solo.
///
/// Sin esto, el temporizador del SnackBar sigue pendiente al terminar el test y
/// el framework lo reporta como fallo.
Future<void> cerrarAvisos(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
}

List<SystemModule> modulosDePrueba() => const [
      SystemModule(
        clave: 'm0_cpanel',
        nombre: 'Administrador Maestro',
        habilitado: true,
        orden: 0,
        categoria: 'nucleo',
        rolesPermitidos: ['admin'],
      ),
      SystemModule(
        clave: 'm1_onboarding',
        nombre: 'Autenticación',
        habilitado: true,
        orden: 10,
        categoria: 'nucleo',
      ),
      SystemModule(
        clave: 'm4_inscripciones',
        nombre: 'Inscripciones',
        habilitado: false,
        orden: 40,
        categoria: 'academico',
      ),
    ];

void main() {
  group('cPanel · Módulos del Sistema', () {
    testWidgets('muestra el indicador de carga antes de tener datos', (
      tester,
    ) async {
      final fake = FakeGateway()..listaModulos = modulosDePrueba();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('agrupa los módulos por categoría', (tester) async {
      final fake = FakeGateway()..listaModulos = modulosDePrueba();

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(find.text('NÚCLEO'), findsOneWidget);
      expect(find.text('ACADÉMICO'), findsOneWidget);
      expect(find.text('Administrador Maestro'), findsOneWidget);
      expect(find.text('Inscripciones'), findsOneWidget);
      // Resumen del estado: 2 de 3 activos.
      expect(find.textContaining('2 de 3 módulos activos'), findsOneWidget);
    });

    testWidgets('el interruptor del cPanel está deshabilitado', (tester) async {
      final fake = FakeGateway()..listaModulos = modulosDePrueba();

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      final primero = tester.widget<Switch>(find.byType(Switch).at(0));
      expect(
        primero.onChanged,
        isNull,
        reason: 'm0_cpanel da acceso al propio panel: no puede apagarse.',
      );
    });

    testWidgets('al pulsar el interruptor guarda y refleja el nuevo estado', (
      tester,
    ) async {
      final fake = FakeGateway()..listaModulos = modulosDePrueba();

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      // El interruptor 0 es m0_cpanel (deshabilitado); el 1 es m1_onboarding.
      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();
      await tester.pump();

      expect(fake.llamadas, contains('actualizarModulo:m1_onboarding'));

      final actualizado = tester.widget<Switch>(find.byType(Switch).at(1));
      expect(actualizado.value, isFalse);

      await cerrarAvisos(tester);
    });

    testWidgets('si el guardado falla, el interruptor NO cambia', (tester) async {
      final fake = FakeGateway()
        ..listaModulos = modulosDePrueba()
        ..errorAlActualizarModulo = Exception('permiso denegado');

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();
      await tester.pump();

      // El interruptor sigue mostrando la verdad, no la intención.
      final sinCambios = tester.widget<Switch>(find.byType(Switch).at(1));
      expect(sinCambios.value, isTrue);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsOneWidget);

      await cerrarAvisos(tester);
    });

    testWidgets('si la carga falla, muestra el error y permite reintentar', (
      tester,
    ) async {
      final fake = FakeGateway()
        ..listaModulos = modulosDePrueba()
        ..errorAlListarModulos = Exception('sin conexión');

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(find.text('No pudimos cargar esta sección'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      // El segundo intento sí funciona: la lista aparece.
      fake.errorAlListarModulos = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Administrador Maestro'), findsOneWidget);
    });
  });

  group('cPanel · Parámetros', () {
    testWidgets('un parámetro booleano se pinta como interruptor', (tester) async {
      final fake = FakeGateway()
        ..listaSettings = [
          const SystemSetting(
            clave: 'modo_mantenimiento',
            valor: false,
            tipo: 'boolean',
            esPublico: true,
          ),
        ];

      await montarPanel(
        tester,
        CpanelParametrosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump();

      expect(fake.llamadas, contains('actualizarSetting:modo_mantenimiento'));
      expect(
        fake.listaSettings.first.valor,
        isTrue,
      );

      await cerrarAvisos(tester);
    });

    testWidgets('un parámetro numérico acepta la coma como separador decimal', (
      tester,
    ) async {
      final fake = FakeGateway()
        ..listaSettings = [
          const SystemSetting(
            clave: 'max_faltas_consecutivas',
            valor: 3,
            tipo: 'number',
          ),
        ];

      await montarPanel(
        tester,
        CpanelParametrosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      await tester.enterText(find.byType(TextField), '2,5');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump();

      expect(fake.llamadas, contains('actualizarSetting:max_faltas_consecutivas'));
      expect(fake.listaSettings.first.valor, 2.5);

      await cerrarAvisos(tester);
    });

    testWidgets('un valor numérico inválido no llega al servidor', (tester) async {
      final fake = FakeGateway()
        ..listaSettings = [
          const SystemSetting(
            clave: 'max_faltas_consecutivas',
            valor: 3,
            tipo: 'number',
          ),
        ];

      await montarPanel(
        tester,
        CpanelParametrosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Guardar'));
      await tester.pump();

      expect(find.textContaining('Escribe un número'), findsOneWidget);
      // Falla rápido en local: no se gasta una petición para algo que ya se sabe.
      expect(fake.llamadas, isNot(contains('actualizarSetting:max_faltas_consecutivas')));
    });
  });

  group('cPanel · Auditoría', () {
    testWidgets('muestra los cambios con su descripción legible', (tester) async {
      final fake = FakeGateway()
        ..listaAuditoria = [
          ConfigAuditEntry(
            id: 'a1',
            tabla: 'system_modules',
            clave: 'm4_inscripciones',
            valorAnterior: const {'habilitado': false},
            valorNuevo: const {'habilitado': true},
            usuarioEmail: 'admin@inces.test',
            creadoEn: DateTime(2026, 9, 12, 10, 30),
          ),
        ];

      await montarPanel(
        tester,
        CpanelAuditoriaPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(
        find.text('m4_inscripciones: inactivo → activo'),
        findsOneWidget,
      );
      expect(find.textContaining('admin@inces.test'), findsOneWidget);
    });

    testWidgets('con el historial vacío lo dice, en vez de quedarse en blanco', (
      tester,
    ) async {
      final fake = FakeGateway()..listaAuditoria = const [];

      await montarPanel(
        tester,
        CpanelAuditoriaPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(find.text('Todavía no hay cambios registrados.'), findsOneWidget);
    });

    testWidgets('si la carga falla, lo indica con opción de reintentar', (
      tester,
    ) async {
      final fake = FakeGateway()
        ..errorAlListarAuditoria = Exception('sin conexión');

      await montarPanel(
        tester,
        CpanelAuditoriaPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(find.text('No pudimos cargar esta sección'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      // Un fallo NO debe parecer un historial vacío: son cosas distintas.
      expect(find.text('Todavía no hay cambios registrados.'), findsNothing);

      fake.errorAlListarAuditoria = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Todavía no hay cambios registrados.'), findsOneWidget);
    });
  });
}
