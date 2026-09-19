/// Elige la implementación de [SelectorDeArchivos] según la plataforma.
///
/// **Por qué un export condicional y no un `if (kIsWeb)`.** `kIsWeb` es una
/// comprobación en **tiempo de ejecución**, pero el problema es de **compilación**:
/// `package:web` y `dart:js_interop` no existen en la VM, así que importarlos en
/// un archivo que `flutter test` compila rompe la compilación aunque la rama
/// nunca se ejecute. El import condicional decide en tiempo de compilación y el
/// archivo que no aplica ni siquiera se carga.
///
/// El consumidor importa este archivo y usa
/// `SelectorDeArchivosDelNavegador` sin saber cuál de los dos le tocó.
library;

export 'selector_archivos_io.dart'
    if (dart.library.js_interop) 'selector_archivos_web.dart';
