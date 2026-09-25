import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/gateways/selector_archivos.dart';

/// Implementación de [SelectorDeArchivos] para el navegador.
///
/// Se elige por importación condicional (ver `selector_archivos_navegador.dart`),
/// así que este archivo **sólo** entra en la compilación web. La VM —y por tanto
/// `flutter test`— usa el stub, que lanza: por eso la UI recibe el selector
/// inyectado y las pruebas nunca llegan aquí.
///
/// Usa `package:web` + `dart:js_interop` y **no** `dart:html`, que está
/// deprecado y rompería la regla `avoid_web_libraries_in_flutter` del proyecto.
class SelectorDeArchivosDelNavegador implements SelectorDeArchivos {
  @override
  Future<ArchivoElegido?> elegir() async {
    final completer = Completer<ArchivoElegido?>();

    // El `<input>` se crea y se pulsa desde código: no hay ningún widget de
    // Flutter que abra el diálogo del sistema.
    final entrada = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..style.display = 'none';

    // `change` es el camino normal. Si el usuario **cancela**, el navegador
    // dispara `cancel` (Chrome 113+); sin escucharlo, la `Future` no se
    // completaría nunca y el botón quedaría bloqueado para siempre —el mismo
    // fallo que la convención del proyecto prohíbe al liberar el estado de
    // carga—. Se deja también la comprobación de lista vacía como red.
    entrada.onchange = ((web.Event _) {
      final elegidos = entrada.files;
      if (elegidos == null || elegidos.length == 0) {
        _completar(completer, null);
        return;
      }

      final archivo = elegidos.item(0)!;
      _leer(archivo)
          .then((contenido) => _completar(
                completer,
                ArchivoElegido(nombre: archivo.name, contenido: contenido),
              ))
          .catchError((Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      });
    }).toJS;

    entrada.oncancel = ((web.Event _) => _completar(completer, null)).toJS;

    // El elemento tiene que estar en el documento para que el diálogo se abra de
    // forma fiable, y se retira al terminar para no dejar basura en el DOM.
    web.document.body?.append(entrada);
    entrada.click();

    try {
      return await completer.future;
    } finally {
      entrada.remove();
    }
  }

  @override
  Future<void> descargar({required String url, required String nombre}) async {
    // El nombre no se usa aquí a propósito: la URL viene firmada por el backend
    // con el `Content-Disposition` ya puesto, así que es el servidor quien
    // decide cómo se llama el archivo descargado. Reenviarlo desde el cliente
    // sólo serviría para que las dos partes pudieran discrepar.
    web.window.open(url, '_blank');
  }

  @override
  Future<void> descargarTexto({
    required String nombre,
    required String contenido,
    String tipoMime = 'text/csv;charset=utf-8',
  }) async {
    // El `Blob` es lo que convierte una cadena en algo descargable. El `type`
    // lleva el `charset` a propósito: sin él, Excel abre el CSV con la
    // codificación del sistema y los acentos de los nombres salen rotos.
    //
    // La lista se tipa como `<JSAny>` explícitamente porque `BlobPart` es un
    // alias de `JSAny`: sin el tipo, `[contenido.toJS].toJS` sería
    // `JSArray<JSString>` y la asignación al parámetro no compilaría.
    final blob = web.Blob(
      <JSAny>[contenido.toJS].toJS,
      web.BlobPropertyBag(type: tipoMime),
    );

    final url = web.URL.createObjectURL(blob);

    // El `<a download>` se crea, se pulsa y se retira desde código: no hay
    // ningún widget de Flutter que abra el diálogo de guardar del navegador, y
    // `window.open` sobre una URL de objeto sólo la mostraría, sin descargarla.
    final enlace = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = nombre
      ..style.display = 'none';

    web.document.body?.append(enlace);
    enlace.click();

    // Se revoca la URL y se retira el enlace en el mismo instante. Una URL de
    // objeto **retiene su `Blob` en memoria** hasta que se revoca; en una
    // pantalla donde se exportan varias secciones seguidas, no revocarlas iría
    // acumulando nóminas completas sin que nada las suelte.
    enlace.remove();
    web.URL.revokeObjectURL(url);
  }

  /// Lee los bytes del archivo elegido.
  ///
  /// `arrayBuffer()` y no `text()`: el archivo puede ser un PDF o una imagen, y
  /// decodificarlo como texto lo corrompería en silencio.
  Future<List<int>> _leer(web.File archivo) async {
    final buffer = await archivo.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  void _completar(Completer<ArchivoElegido?> completer, ArchivoElegido? valor) {
    if (!completer.isCompleted) completer.complete(valor);
  }
}
