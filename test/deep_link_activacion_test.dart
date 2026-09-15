import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/main.dart';
import 'package:inces_lms_app/screens/activar_cuenta_screen.dart';

/// Prueba de regresión del enlace profundo de activación (Módulo 1).
///
/// El fallo medido, antes de este arreglo: `MaterialApp.routes` compara cadenas
/// **exactas**, así que `/auth/activate?token=…` no encontraba destino. El
/// `Navigator` reportaba «Could not navigate to initial route» y **descartaba la
/// pila inicial entera**, cayendo a `/`. El docente abría el enlace del correo y
/// aterrizaba en el login: el token se perdía por el camino y la pantalla de
/// activación nunca llegaba a montarse.
///
/// Estas pruebas montan la aplicación **real** con la ruta inicial que en web
/// fija el navegador, para que el fallo no pueda volver sin que algo se ponga
/// rojo.
void main() {
  setUpAll(() async {
    // El `AuthGate` que queda debajo del enlace necesita el cliente de Supabase
    // inicializado para poder decidir que no hay sesión.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoyMDAwMDAwMDAwfQ.test',
    );
  });

  /// Monta la app en [rutaInicial] y deja terminar la transición de entrada.
  ///
  /// No se usa `pumpAndSettle`: el `AuthGate` de abajo muestra un indicador de
  /// carga circular, que es una animación infinita, y `pumpAndSettle` se
  /// quedaría esperándola hasta agotar el tiempo.
  Future<void> montarEn(WidgetTester tester, String rutaInicial) async {
    await tester.pumpWidget(IncesLmsApp(rutaInicial: rutaInicial));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('un enlace con token monta la pantalla de activación',
      (tester) async {
    await montarEn(tester, '/auth/activate?token=ABC');

    expect(
      tester.takeException(),
      isNull,
      reason: 'el enrutado no debe descartar la ruta inicial del enlace',
    );
    expect(find.byType(ActivarCuentaScreen), findsOneWidget);
    expect(find.text('Activar cuenta de docente'), findsOneWidget);
  });

  testWidgets('el token del enlace llega hasta la pantalla', (tester) async {
    await montarEn(tester, '/auth/activate?token=ABC');

    await tester.tap(find.text('Activar cuenta'));
    await tester.pump();

    // Éste es el observable que prueba que el token viajó desde la URL hasta la
    // pantalla: con token, el formulario se queja de la contraseña vacía; sin
    // token, se quejaría de que falta el token. La comprobación del token va
    // **antes** de validar el formulario, así que el orden importa.
    expect(find.textContaining('Falta el token'), findsNothing);
    expect(find.text('Ingresa tu nueva contraseña'), findsOneWidget);
  });

  testWidgets('sin token la pantalla lo dice en vez de fingir', (tester) async {
    await montarEn(tester, '/auth/activate');

    await tester.tap(find.text('Activar cuenta'));
    await tester.pump();

    expect(find.textContaining('Falta el token'), findsOneWidget);
  });

  testWidgets('una ruta desconocida cae al inicio de sesión, no en blanco',
      (tester) async {
    await montarEn(tester, '/ruta/que/no/existe');

    // Flutter avisa de que el enlace no tiene destino y sustituye la ruta
    // inicial por `/` (`defaultGenerateInitialRoutes`, `navigator.dart`). Lo que
    // se comprueba es que la app **arranca y muestra algo con sentido** en vez
    // de quedarse en blanco. El aviso del framework forma parte de ese camino,
    // así que se consume aquí para que no ensucie la prueba.
    expect(tester.takeException(), isNotNull);
    expect(find.byType(ActivarCuentaScreen), findsNothing);
    expect(find.text('Ingresar al sistema'), findsOneWidget);
  });
}
