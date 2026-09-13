import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/main.dart';
import 'package:inces_lms_app/providers/role_provider.dart';
import 'package:inces_lms_app/screens/login_screen.dart';
import 'package:inces_lms_app/screens/registro_exitoso_screen.dart';

void main() {
  setUpAll(() async {
    // Mock de SharedPreferences para que Supabase pueda inicializar
    // su almacenamiento local en el entorno de test.
    SharedPreferences.setMockInitialValues({});

    // Inicializa Supabase con credenciales de prueba para que AuthGate
    // pueda acceder al cliente sin conexión real.
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoyMDAwMDAwMDAwfQ.test',
    );
  });

  testWidgets('LoginScreen muestra el formulario de acceso institucional', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Campos del formulario. La etiqueta del botón va en minúscula desde el
    // rediseño («Ingresar al sistema»), y ese literal es el que se comprueba
    // —no el de la versión anterior en mayúscula— porque el estilo tipográfico
    // ya no necesita gritar para destacar: el botón es un `ElevatedButton`
    // primario sobre un fondo claro.
    expect(find.text('Cédula o Correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Ingresar al sistema'), findsOneWidget);

    // Identidad institucional. En el ancho de prueba (800×600) el panel de
    // marca lateral está oculto —se muestra a partir de 900 px—, así que la
    // identidad aparece en su variante compacta sobre el formulario.
    expect(find.text('INCES LMS'), findsOneWidget);
    expect(find.text('La Isabelica'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('LoginScreen muestra el panel de marca en pantallas anchas', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Con sitio suficiente, el panel de marca aparece y **la identidad compacta
    // desaparece**: el mismo nombre dos veces en la misma pantalla sería ruido.
    expect(find.text('Sistema de Gestión\nAcadémica'), findsOneWidget);
    expect(find.text('CFS Nacional de Soldadura\n«Rafael Urdaneta»'), findsOneWidget);
    expect(find.text('INCES LMS'), findsNothing);
  });

  testWidgets('AuthGate muestra splash de inicialización sin sesión activa', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RoleProvider(),
        child: const MaterialApp(home: AuthGate()),
      ),
    );

    // Mientras se inicializa la sesión, muestra el splash de carga.
    // El literal usa puntos suspensivos tipográficos (`…`), no tres puntos
    // seguidos: es un solo carácter, y buscar `...` no encuentra nada.
    expect(find.text('Inicializando sesión…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Registro exitoso muestra confirmación adaptativa', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RegistroExitosoScreen(
          email: 'aspirante@example.com',
          requiereTutorLegal: true,
        ),
      ),
    );

    expect(find.text('Inscripción registrada'), findsOneWidget);
    expect(find.text('aspirante@example.com'), findsOneWidget);
    expect(find.text('Ir al inicio de sesión'), findsOneWidget);
    expect(
      find.text('Tu representante legal será contactado para validar la inscripción.'),
      findsOneWidget,
    );
  });

  testWidgets('Registro exitoso se adapta a pantallas angostas', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: RegistroExitosoScreen(
          email: 'aspirante@example.com',
          requiereTutorLegal: false,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Inscripción registrada'), findsOneWidget);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
