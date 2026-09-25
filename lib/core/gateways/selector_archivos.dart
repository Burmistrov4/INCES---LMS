/// Contrato para elegir un archivo del disco y para abrir una descarga.
///
/// **Por qué es un puerto y no una llamada directa.** Elegir un archivo es una
/// operación del navegador —un `<input type="file">`— y abrir una descarga es
/// otra —`window.open`—. Las dos viven en `dart:js_interop` y `package:web`, que
/// **no existen** cuando el código se compila para la VM: `flutter test` corre en
/// la VM, así que una llamada directa haría que las pruebas del panel no
/// compilaran, y sin pruebas el camino de los tres pasos quedaría sin cubrir.
///
/// Es el mismo criterio que el proyecto ya aplica a los servicios externos: **se
/// inyectan, no se derivan por dentro**. La UI recibe un [SelectorDeArchivos]; en
/// producción es el del navegador, en las pruebas es un doble.
///
/// **Lo que este puerto NO decide.** No valida extensiones ni tamaños: eso lo
/// hace el servidor, que es el único que puede (la URL prefirmada de `PUT` no
/// admite `content-length-range`, así que el peso sólo se conoce con el
/// `HeadObject` posterior). Filtrar aquí por tamaño daría una falsa sensación de
/// seguridad y además impediría subir un archivo que el servidor sí aceptaría si
/// el límite cambiara sin desplegar el cliente.
library;

/// Un archivo que el usuario eligió, ya leído en memoria.
///
/// Los bytes viajan como `List<int>` porque es lo que consume el `PUT` a R2 y lo
/// que el gateway declara. No se expone la ruta original: el navegador no la da
/// (sólo un nombre), y el nombre que importa es el que el usuario ve.
class ArchivoElegido {
  const ArchivoElegido({required this.nombre, required this.contenido});

  /// Nombre tal como lo eligió el usuario, con acentos y espacios.
  ///
  /// El servidor deriva de la extensión el `Content-Type` que firmará, así que
  /// este nombre **no es decorativo**: decide si la subida es aceptable y con qué
  /// tipo MIME viajará.
  final String nombre;

  final List<int> contenido;

  int get bytes => contenido.length;
}

abstract interface class SelectorDeArchivos {
  /// Abre el diálogo del sistema y devuelve el archivo elegido.
  ///
  /// Devuelve `null` cuando el usuario **cancela**, que no es un error: la UI no
  /// debe mostrar ningún aviso en ese caso. Un fallo real del diálogo sí lanza.
  Future<ArchivoElegido?> elegir();

  /// Abre una URL de descarga temporal en una pestaña nueva.
  ///
  /// La URL viene firmada por el backend y caduca; este puerto no la construye ni
  /// la guarda.
  Future<void> descargar({required String url, required String nombre});

  /// Descarga contenido **generado en el cliente**, no una URL del servidor.
  ///
  /// Es distinto de [descargar], y la diferencia no es cosmética: allí el
  /// archivo ya existe en algún servidor y basta con abrir su URL; aquí el
  /// contenido lo produjo la aplicación —el CSV de la exportación hacia HACER—
  /// y **no existe en ningún servidor**, así que hay que entregarlo como
  /// archivo. En el navegador eso se resuelve con un `Blob` y una URL de objeto,
  /// que es la única vía para descargar algo que nadie sirve por HTTP.
  ///
  /// [tipoMime] importa de verdad: sin el `charset=utf-8`, una hoja de cálculo
  /// que abra el CSV usa la codificación del sistema y los acentos de «José» o
  /// «Núñez» salen rotos. El valor por defecto es el del caso que lo motivó.
  ///
  /// Es un método de este puerto y no de un puerto nuevo porque esta interfaz ya
  /// se declara a sí misma como el contrato de «elegir un archivo y abrir una
  /// descarga»: añadir un tercer puerto con las mismas dos implementaciones
  /// obligaría a repetir la danza del import condicional para ganar nada.
  Future<void> descargarTexto({
    required String nombre,
    required String contenido,
    String tipoMime = 'text/csv;charset=utf-8',
  });
}
