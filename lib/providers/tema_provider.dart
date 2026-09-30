import 'package:flutter/material.dart';

import '../core/gateways/preferencias_tema.dart';
import '../services/preferencias_tema_dispositivo.dart';

/// Traduce el valor guardado a un [ThemeMode].
///
/// Es de nivel superior y no un método del proveedor por el mismo motivo que
/// `userRoleFromName` en `role_provider.dart`: la traducción de un texto
/// externo a un tipo del dominio es una función pura, y conviene poder
/// probarla sin construir nada.
///
/// **Una cadena desconocida cae a [ThemeMode.system], no lanza.** El valor
/// puede venir de una versión anterior de la aplicación, de un valor escrito a
/// mano en `localStorage`, o de una preferencia corrupta. La preferencia de
/// tema es una comodidad: no hay ninguna entrada que justifique que un valor
/// ilegible deje la aplicación sin arrancar, y el modo del sistema es
/// exactamente lo que hacía la aplicación antes de que esta preferencia
/// existiera. Un `throw` aquí cambiaría un detalle estético por una pantalla en
/// blanco.
ThemeMode modoDeTemaDesde(String? valor) {
  for (final modo in ThemeMode.values) {
    if (modo.name == valor) return modo;
  }
  return ThemeMode.system;
}

/// Mantiene el tema que el usuario eligió y lo recuerda entre sesiones.
///
/// ## Por qué arranca en `system` y no en «cargando»
///
/// La lectura del almacenamiento es asíncrona, así que durante los primeros
/// fotogramas el proveedor todavía no sabe qué eligió el usuario. El valor
/// inicial es [ThemeMode.system] —el que la aplicación usaba antes de que este
/// proveedor existiera— porque es el único que **no puede estar equivocado de
/// forma visible**: si no hay preferencia guardada, es el correcto; si la hay,
/// el cambio llega un instante después. Un valor inicial «neutro» inventado, en
/// cambio, pintaría un tema que nadie pidió y luego saltaría al real.
///
/// Y si la lectura falla, se queda aquí: el fallo y la ausencia de preferencia
/// dan el mismo resultado, que resulta ser el correcto en los dos casos.
class TemaProvider extends ChangeNotifier {
  /// Crea el proveedor.
  ///
  /// [preferencias] es inyectable y **su valor por defecto es el almacén del
  /// dispositivo**. Ese `??` no es adorno: es el idioma que ya usan `AuthService`,
  /// los repositorios y los gateways de este proyecto
  /// (`_gateway = gateway ?? SupabaseService.instance`), y además es lo que evita
  /// una incidencia de `flutter analyze`: una asignación directa
  /// `_preferencias = preferencias` dispara `prefer_initializing_formals`, que
  /// **tumba el CI** —medido el 2026-09-30—. Con el `??` el campo sigue siendo
  /// privado, que es lo que se quiere, y el valor de producción vive aquí en vez
  /// de en `main.dart`.
  TemaProvider({PreferenciasTema? preferencias})
      : _preferencias = preferencias ?? PreferenciasTemaDelDispositivo();

  final PreferenciasTema _preferencias;

  ThemeMode _modo = ThemeMode.system;

  /// El modo de tema vigente.
  ThemeMode get modo => _modo;

  bool _falloAlRecordar = false;

  /// `true` si la última vez que se intentó guardar la preferencia, no se pudo.
  ///
  /// Existe porque el fallo se **absorbe** a propósito (ver [cambiar]) y una
  /// degradación silenciosa no se puede probar: sin este observable, una prueba
  /// sólo podría comprobar que el tema cambió, cosa que también es cierta
  /// cuando el guardado funcionó. Con él, la prueba distingue «cambió y quedó
  /// recordado» de «cambió y no se pudo recordar», que son dos estados
  /// distintos del sistema y no el mismo con suerte distinta.
  bool get falloAlRecordar => _falloAlRecordar;

  /// Lee la preferencia guardada y la aplica.
  ///
  /// Se llama una sola vez, al construir el proveedor. Es asíncrona y nadie
  /// puede esperarla desde `create`, así que la aplicación arranca con el valor
  /// por defecto y sólo cambia si había algo guardado.
  Future<void> cargar() async {
    final guardado = await _preferencias.leer();
    final modo = modoDeTemaDesde(guardado);

    // Sólo se notifica si el valor cambió. Notificar de más no rompe nada —quien
    // escucha compara y repinta lo mismo—, pero despertar a los oyentes para
    // decirles que nada cambió es ruido en el perfil de reconstrucción, y en el
    // arranque es justo el momento en que más se nota.
    if (modo == _modo) return;
    _modo = modo;
    notifyListeners();
  }

  /// Cambia el tema y lo persiste.
  ///
  /// El orden importa: primero se cambia en memoria y se notifica, y sólo
  /// después se intenta guardar. Así el usuario ve el tema nuevo en el mismo
  /// fotograma del clic, sin esperar a un canal de plataforma.
  Future<void> cambiar(ThemeMode modo) async {
    if (modo == _modo) return;

    _modo = modo;
    notifyListeners();

    try {
      await _preferencias.guardar(modo.name);
      _falloAlRecordar = false;
    } on Exception {
      // El tema ya cambió, que es lo que el usuario pidió. Que no se pueda
      // recordar para la próxima sesión es una degradación, no un fallo de la
      // acción, y por eso **no se revierte**: volver atrás castigaría al usuario
      // por un problema del almacenamiento. Tampoco se relanza, porque nadie
      // puede hacer nada con ello y una excepción asíncrona sin dueño acabaría
      // en el manejador global como un error de la aplicación.
      //
      // Lo que sí se hace es **dejarlo medible** en [falloAlRecordar].
      _falloAlRecordar = true;
    }
  }
}
