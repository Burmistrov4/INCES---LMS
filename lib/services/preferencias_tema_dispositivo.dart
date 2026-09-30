import 'package:shared_preferences/shared_preferences.dart';

import '../core/gateways/preferencias_tema.dart';

/// Guarda la preferencia de tema en el almacenamiento del dispositivo.
///
/// Es la implementación de producción. En web escribe en `localStorage`; en
/// móvil y escritorio, en las preferencias nativas. Este archivo no sabe cuál
/// de las dos cosas está pasando: `shared_preferences` resuelve esa diferencia
/// con sus propios paquetes por plataforma (`shared_preferences_web`,
/// `shared_preferences_android`, …), que ya vienen resueltos como transitivas.
///
/// ## Por qué la API heredada y no `SharedPreferencesAsync`
///
/// El paquete 2.5.5 ofrece las dos. Se usa la heredada —`getInstance()`—
/// porque **el doble de las pruebas sólo atiende a la heredada**:
/// `SharedPreferences.setMockInitialValues` prepara el almacén que consulta
/// `SharedPreferences`, no `SharedPreferencesAsyncPlatform`. Cambiar a la nueva
/// obligaría a reescribir el `setUpAll` de tres archivos de prueba que hoy
/// pasan —`deep_link_activacion_test.dart`, `phase1_onboarding_test.dart` y
/// `widget_test.dart`— para no ganar nada: la preferencia es una cadena y no
/// necesita la API sin caché.
class PreferenciasTemaDelDispositivo implements PreferenciasTema {
  /// Clave con la que se guarda el modo de tema.
  ///
  /// Es un nombre corto y sin prefijo porque el almacén de `localStorage` es
  /// por origen, no por aplicación. El prefijo lo pone el propio paquete
  /// (`flutter.`), que es lo que permite distinguir esta clave de cualquier
  /// otra que escriba la página.
  static const String _clave = 'tema';

  @override
  Future<String?> leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_clave);
    } on Exception {
      // Sin plugin —el caso de `flutter test` sin `setMockInitialValues`— o con
      // el almacén caído. El contrato del puerto dice que esto es «no hay
      // preferencia», no un error: quien llama tiene un valor por defecto.
      //
      // Se captura `Exception` y **no** `Object` a propósito: un `Error` es un
      // fallo de programación, no una plataforma ausente, y tragárselo aquí
      // convertiría un defecto real en un tema que «misteriosamente» no se
      // recuerda.
      return null;
    }
  }

  @override
  Future<void> guardar(String valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, valor);
  }
}
