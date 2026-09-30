import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/main.dart';
import 'package:inces_lms_app/repositories/aspirante_repository.dart';

import 'support/fake_gateway.dart';
import 'support/fake_preferencias_tema.dart';

/// Prueba del cableado del tema: de la preferencia guardada hasta `MaterialApp`.
///
/// **Por qué hace falta, teniendo `selector_tema_test.dart`.** Allí se prueba el
/// selector del pie, que es la mitad visible. La otra mitad es esta: que el
/// `themeMode` de `MaterialApp` **lea de verdad** del proveedor. Un
/// `themeMode: ThemeMode.system` escrito a mano, o un `watch` colocado en el
/// sitio equivocado —por encima del proveedor en vez de por debajo, que es la
/// trampa que documenta `MultiProvider`—, pasaría todas las demás pruebas del
/// proyecto y sólo se notaría al abrir la aplicación.
///
/// Monta la aplicación **real** porque es la única forma de medir eso: el
/// cableado vive dentro de `IncesLmsApp.build`, así que reproducirlo en la
/// prueba mediría la prueba y no el código.
void main() {
  setUpAll(() async {
    // El `AuthGate` que cuelga de la aplicación necesita el cliente de Supabase
    // inicializado para poder decidir que no hay sesión; y `supabase_flutter`
    // guarda la sesión en `shared_preferences`, así que su doble también hace
    // falta. Es el mismo `setUpAll` que usa `deep_link_activacion_test.dart`,
    // que monta esta misma aplicación por otro motivo.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoyMDAwMDAwMDAwfQ.test',
    );
  });

  /// Monta la aplicación con la preferencia indicada y devuelve el `themeMode`
  /// con el que quedó el `MaterialApp` de arriba.
  ///
  /// [guardado] es lo que hay en el almacén: `null` significa que el usuario
  /// nunca eligió tema, y una cadena como `'no-existe'` reproduce una
  /// preferencia corrupta.
  Future<ThemeMode?> montarYLeerModo(
    WidgetTester tester,
    String? guardado,
  ) async {
    await tester.pumpWidget(
      IncesLmsApp(
        // El doble se inyecta en vez de usar el mock de `shared_preferences`:
        // así lo que se mide es nuestro cableado, no que el doble del plugin
        // responda.
        preferenciasTema: FakePreferenciasTema(guardado: guardado),
        // Sin esto, el `AuthGate` —que decide que no hay sesión— haría que la
        // portada pública disparara una consulta real a Supabase.
        landingRepository: AspiranteRepository(gateway: FakeGateway()),
      ),
    );

    // Tres `pump` y **no** `pumpAndSettle`: el primero construye con el valor
    // por defecto, el segundo deja resolverse la lectura de la preferencia
    // —que es asíncrona— y el tercero reconstruye `MaterialApp` con el modo ya
    // leído. `pumpAndSettle` se quedaría esperando el indicador de carga
    // circular del `AuthGate`, que anima indefinidamente y agotaría el tiempo.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // `.first` porque el orden del recorrido es el del árbol: el primero es el
    // `MaterialApp` de la aplicación, no el que pudiera montar alguna pantalla
    // por dentro.
    return tester.widget<MaterialApp>(find.byType(MaterialApp).first).themeMode;
  }

  testWidgets('sin preferencia guardada la aplicación usa el modo del sistema',
      (tester) async {
    // Es el caso de un usuario nuevo y también el del almacén que no se pudo
    // leer: los dos llegan aquí como `null`. Es además el comportamiento que la
    // aplicación tenía antes de que existiera este selector, así que esta prueba
    // es también la que garantiza que no se cambió por accidente.
    expect(await montarYLeerModo(tester, null), ThemeMode.system);
    expect(
      tester.takeException(),
      isNull,
      reason: 'el arranque con la preferencia ausente no debe lanzar nada',
    );
  });

  testWidgets('con «dark» guardado la aplicación arranca en oscuro',
      (tester) async {
    expect(await montarYLeerModo(tester, 'dark'), ThemeMode.dark);
  });

  testWidgets('con «light» guardado la aplicación arranca en claro',
      (tester) async {
    // Las dos direcciones y no sólo una: con una sola, un cableado que
    // tradujera cualquier valor a `dark` pasaría la prueba anterior.
    expect(await montarYLeerModo(tester, 'light'), ThemeMode.light);
  });

  testWidgets('con una preferencia corrupta cae al modo del sistema',
      (tester) async {
    expect(await montarYLeerModo(tester, 'no-existe'), ThemeMode.system);
  });
}
