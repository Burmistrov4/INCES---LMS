import '../core/gateways/selector_archivos.dart';

/// Implementación de [SelectorDeArchivos] para la VM (y para cualquier destino
/// que no sea el navegador).
///
/// **No es un hueco por pereza: es lo que permite que `flutter test` compile.**
/// El selector real necesita `package:web` y `dart:js_interop`, que no existen en
/// la VM. Si el panel importara el selector web directamente, ninguna prueba del
/// panel podría compilarse, y el camino de los tres pasos —lo único que la UI
/// aporta de verdad— quedaría sin cubrir.
///
/// La elección entre este archivo y el web la hace el import condicional de
/// `selector_archivos_navegador.dart`.
///
/// **Lanza a propósito.** Devolver `null` haría que, si alguien olvidara inyectar
/// el selector en producción, la UI dijera «no elegiste ningún archivo» para
/// siempre: un fallo de configuración disfrazado de comportamiento normal. Un
/// `UnsupportedError` con el motivo escrito es diagnosticable en un minuto.
class SelectorDeArchivosDelNavegador implements SelectorDeArchivos {
  @override
  Future<ArchivoElegido?> elegir() => throw UnsupportedError(
        'Elegir archivos sólo está implementado para el navegador. En esta '
        'plataforma hay que inyectar un SelectorDeArchivos.',
      );

  @override
  Future<void> descargar({required String url, required String nombre}) =>
      throw UnsupportedError(
        'Abrir una descarga sólo está implementado para el navegador. En esta '
        'plataforma hay que inyectar un SelectorDeArchivos.',
      );

  @override
  Future<void> descargarTexto({
    required String nombre,
    required String contenido,
    String tipoMime = 'text/csv;charset=utf-8',
  }) =>
      throw UnsupportedError(
        'Descargar contenido generado sólo está implementado para el '
        'navegador. En esta plataforma hay que inyectar un SelectorDeArchivos.',
      );
}
