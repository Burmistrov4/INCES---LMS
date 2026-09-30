import 'package:inces_lms_app/core/gateways/preferencias_tema.dart';

/// Doble en memoria de [PreferenciasTema].
///
/// Existe en vez de usar el mock de `shared_preferences`
/// (`setMockInitialValues`) porque lo que hay que probar es **nuestra** lógica
/// —la traducción del valor guardado, el valor por defecto, la degradación
/// cuando el almacén falla— y no que el doble del plugin responda. Con este
/// doble, la prueba del tema no depende de ningún canal de plataforma.
class FakePreferenciasTema implements PreferenciasTema {
  FakePreferenciasTema({this.guardado, this.fallaAlGuardar = false});

  /// Lo que hay guardado ahora mismo.
  ///
  /// Es público y mutable **a propósito**, y no un campo privado con un `get`:
  /// un doble de pruebas necesita que la prueba pueda leerlo —para comprobar qué
  /// se escribió— y prepararlo. Además, `this.guardado` es un parámetro
  /// inicializador formal; asignarlo a mano desde el constructor dispararía
  /// `prefer_initializing_formals`, que `flutter analyze` cuenta como incidencia.
  String? guardado;

  /// Si es `true`, [guardar] lanza. Es mutable para poder probar la secuencia
  /// «falla y luego funciona», que es la que comprueba que la marca de fallo se
  /// limpia en vez de quedarse pegada.
  bool fallaAlGuardar;

  /// Cuántas veces se pidió guardar.
  ///
  /// Sirve para comprobar que elegir el modo que ya estaba **no escribe**: sin
  /// este contador, una implementación que escribiera siempre pasaría las demás
  /// pruebas igual.
  int escrituras = 0;

  @override
  Future<String?> leer() async => guardado;

  @override
  Future<void> guardar(String valor) async {
    escrituras++;
    if (fallaAlGuardar) throw const _AlmacenNoDisponible();
    guardado = valor;
  }
}

/// El fallo que el doble lanza para simular un almacén inaccesible.
///
/// Implementa `Exception` y no `Error` **a propósito**: es la misma distinción
/// que hace la implementación real. Un almacén ausente es una condición de la
/// plataforma —y por eso el proveedor la absorbe—; un `Error` sería un defecto
/// de programación, que debe ser ruidoso.
class _AlmacenNoDisponible implements Exception {
  const _AlmacenNoDisponible();

  @override
  String toString() => 'el almacén de preferencias no está disponible';
}
