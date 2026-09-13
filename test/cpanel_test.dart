import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/config_audit_entry.dart';
import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/models/system_setting.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_auditoria_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_modulos_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_parametros_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/comunes.dart';

import 'support/fake_gateway.dart';

/// Monta un panel y espera a que termine su carga inicial.
///
/// No se usa `pumpAndSettle` para el arranque: mientras carga hay un
/// `CircularProgressIndicator`, cuya animación es infinita y haría que
/// `pumpAndSettle` agotara el tiempo de espera.
///
/// El `MaterialApp` lleva el tema institucional a propósito. Los colores de la
/// tarjeta de módulo se resuelven contra `Theme.of(context)`; sin el tema, el
/// test mediría un `ThemeData` por defecto que la aplicación nunca usa.
///
/// **No se envuelve el panel en un scrollable.** Los dos paneles tienen
/// contratos de layout distintos y ambos son correctos:
///   * `CpanelAuditoriaPanel` gestiona su propio scroll con un `Expanded`
///     interno, así que exige altura **acotada**.
///   * `CpanelModulosPanel` devuelve una columna que crece con su contenido.
///
/// Por eso la prueba los monta en el `body` acotado del `Scaffold`, igual que
/// hace `ContenidoSeccion` en producción con el `ConstrainedBox`. Envolverlos
/// en un `SingleChildScrollView` daría altura infinita al primero y rompería su
/// `Expanded`; y montar el segundo en el `Scaffold` sin más lo haría medir el
/// hueco sobrante, que no es lo que ocurre en la aplicación.
Future<void> montarPanel(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: Scaffold(body: panel),
    ),
  );
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

/// Interruptor de la tarjeta de un módulo concreto.
///
/// Antes se localizaba por posición (`find.byType(Switch).at(1)`), lo que ataba
/// el test al orden de la lista y se rompía con sólo reordenar los módulos. Se
/// busca por nombre: la relación «módulo → su interruptor» es la que el usuario
/// ve, y es la que interesa comprobar.
Finder interruptorDe(String nombreModulo) => find.descendant(
      of: find.ancestor(
        of: find.text(nombreModulo),
        matching: find.byType(TarjetaModulo),
      ),
      matching: find.byType(Switch),
    );

/// Tarjeta de métrica del Command Center, localizada por su etiqueta.
///
/// Se sube del texto a la tarjeta y no se usa `find.byType(TarjetaMetrica).at(n)`:
/// el orden de las métricas es una decisión de diseño que puede cambiar, y un
/// test que se rompa al reordenarlas no está probando nada útil.
Finder tarjetaDeMetrica(String etiqueta) => find.ancestor(
      of: find.text(etiqueta),
      matching: find.byType(TarjetaMetrica),
    );

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

      // `TituloSeccion` pinta el rótulo en mayúsculas desde el rediseño: el
      // dato guardado sigue siendo «nucleo», lo que cambia es cómo se muestra.
      expect(find.text('NÚCLEO'), findsOneWidget);
      expect(find.text('ACADÉMICO'), findsOneWidget);
      expect(find.text('Administrador Maestro'), findsOneWidget);
      expect(find.text('Inscripciones'), findsOneWidget);

      // El resumen cambió de forma: antes era una frase («2 de 3 módulos
      // activos»), ahora son tarjetas de métrica. Se comprueba la relación
      // entre ellas, que es lo que importa: 2 activos de 3 totales ⇒ 1 apagado.
      expect(
        tester.widget<TarjetaMetrica>(tarjetaDeMetrica('Módulos totales')).valor,
        '3',
      );
      expect(
        tester.widget<TarjetaMetrica>(tarjetaDeMetrica('Activos')).valor,
        '2',
      );
      expect(
        tester.widget<TarjetaMetrica>(tarjetaDeMetrica('Apagados')).valor,
        '1',
      );
    });

    testWidgets('el cPanel no ofrece interruptor: muestra un candado', (
      tester,
    ) async {
      final fake = FakeGateway()..listaModulos = modulosDePrueba();

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      // El rediseño fue más lejos que «interruptor deshabilitado»: un control
      // gris apagado sigue invitando a pulsarlo y a preguntarse por qué no
      // responde. Aquí directamente **no hay interruptor**; hay un candado con
      // el motivo. Este test sustituye al anterior, que comprobaba
      // `Switch.onChanged == null` —ese `Switch` ya no existe—, y es más
      // estricto: verifica las dos mitades de la decisión.
      expect(
        interruptorDe('Administrador Maestro'),
        findsNothing,
        reason: 'm0_cpanel da acceso al propio panel: no puede apagarse.',
      );

      // El candado se identifica por su tamaño, no sólo por el icono: la
      // insignia de estado «Crítico» también es un escudo, y contar por icono
      // daría dos coincidencias sin que ninguna esté mal. El control real es el
      // icono grande (20 px); el de la insignia mide 11 px.
      final candadoGrande = tester.widgetList<Icon>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Administrador Maestro'),
            matching: find.byType(TarjetaModulo),
          ),
          matching: find.byIcon(Icons.lock_outline),
        ),
      ).where((icono) => icono.size == 20);
      expect(candadoGrande, hasLength(1));

      // Y el porqué es accesible, no un icono mudo.
      expect(
        find.byTooltip(
          'Módulo crítico: da acceso a este panel. No puede desactivarse.',
        ),
        findsOneWidget,
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

      await tester.tap(interruptorDe('Autenticación'));
      await tester.pump();
      await tester.pump();

      expect(fake.llamadas, contains('actualizarModulo:m1_onboarding'));

      final actualizado = tester.widget<Switch>(interruptorDe('Autenticación'));
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

      await tester.tap(interruptorDe('Autenticación'));
      await tester.pump();
      await tester.pump();

      // El interruptor sigue mostrando la verdad, no la intención.
      final sinCambios = tester.widget<Switch>(interruptorDe('Autenticación'));
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

    testWidgets('la tarjeta dice qué roles ven el módulo', (tester) async {
      final fake = FakeGateway()..listaModulos = modulosDePrueba();

      await montarPanel(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      // Antes, esto sólo se descubría abriendo el diálogo de roles. Si la
      // tarjeta no lo muestra, el administrador tiene que abrir y cerrar un
      // diálogo por módulo para saber quién ve qué.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Administrador Maestro'),
            matching: find.byType(TarjetaModulo),
          ),
          matching: find.text('Administrador'),
        ),
        findsOneWidget,
      );

      // Un módulo sin roles restringidos lo dice explícitamente; dejarlo en
      // blanco se leería como «no hay información», no como «lo ven todos».
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Inscripciones'),
            matching: find.byType(TarjetaModulo),
          ),
          matching: find.text('Todos los roles'),
        ),
        findsOneWidget,
      );
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
