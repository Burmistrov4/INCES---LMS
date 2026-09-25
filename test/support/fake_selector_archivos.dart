import 'package:inces_lms_app/core/gateways/selector_archivos.dart';

/// Doble de prueba de [SelectorDeArchivos].
///
/// Existe por la misma razón que el puerto: la implementación real vive en
/// `package:web` y `dart:js_interop`, que **no compilan** en la VM donde corre
/// `flutter test`. Sin este doble, el panel no se podría montar en una prueba y
/// el camino de los tres pasos quedaría sin cubrir.
///
/// Registra las llamadas porque el contrato de la descarga no es «se llamó a
/// descargar»: es «se llamó **con la URL que firmó el servidor** y con el nombre
/// que el servidor devolvió», no con una URL armada en el cliente.
class FakeSelectorDeArchivos implements SelectorDeArchivos {
  /// Lo que devuelve [elegir]. El valor por defecto es `null`, que significa
  /// «el usuario cerró el diálogo» y **no** es un error.
  ArchivoElegido? devolver;

  /// Fuerza un fallo del diálogo.
  ///
  /// Se **lanza** y no se devuelve: un `null` ya significa «canceló», así que
  /// devolver `null` para señalar un fallo haría que la prueba no distinguiera
  /// una cancelación de un diálogo roto — y son cosas opuestas para el usuario.
  Object? errorAlElegir;

  /// Fuerza un fallo al abrir la descarga.
  Object? errorAlDescargar;

  /// Fuerza un fallo al descargar contenido generado.
  Object? errorAlDescargarTexto;

  final List<String> llamadas = [];

  /// Cuántas veces se abrió el diálogo.
  ///
  /// Sirve para comprobar que un botón que dice «Elegir otro archivo» abre el
  /// diálogo de verdad, en vez de limitarse a repetir la subida del mismo.
  int vecesElegir = 0;

  String? ultimaUrlDescargada;
  String? ultimoNombreDescargado;

  /// El contenido de la última descarga **generada** (el CSV), entero.
  ///
  /// Se guarda el texto completo y no un resumen a propósito: la exportación
  /// hacia HACER se prueba comprobando que el archivo contiene la cabecera y la
  /// fila del matriculado, y eso exige el texto, no un «se llamó a descargar».
  String? ultimoTextoDescargado;

  /// El nombre con el que se ofreció esa descarga.
  String? ultimoNombreDeTextoDescargado;

  /// El tipo MIME con el que se ofreció esa descarga.
  String? ultimoTipoMimeDescargado;

  @override
  Future<ArchivoElegido?> elegir() async {
    vecesElegir++;
    llamadas.add('elegir');
    _lanzarSi(errorAlElegir);
    return devolver;
  }

  @override
  Future<void> descargar({required String url, required String nombre}) async {
    llamadas.add('descargar');
    ultimaUrlDescargada = url;
    ultimoNombreDescargado = nombre;
    _lanzarSi(errorAlDescargar);
  }

  @override
  Future<void> descargarTexto({
    required String nombre,
    required String contenido,
    String tipoMime = 'text/csv;charset=utf-8',
  }) async {
    llamadas.add('descargarTexto');
    ultimoNombreDeTextoDescargado = nombre;
    ultimoTextoDescargado = contenido;
    ultimoTipoMimeDescargado = tipoMime;
    _lanzarSi(errorAlDescargarTexto);
  }

  void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }
}

/// Fixture: un archivo elegido, con contenido real del tamaño pedido.
///
/// El contenido no es decorativo: son los bytes que recibe el `PUT`, así que su
/// longitud es lo que la prueba compara contra lo que se envió.
ArchivoElegido archivoElegido({
  String nombre = 'Constancia José.pdf',
  int bytes = 2048,
}) =>
    ArchivoElegido(nombre: nombre, contenido: List<int>.filled(bytes, 65));
