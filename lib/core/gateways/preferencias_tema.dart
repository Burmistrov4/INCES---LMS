/// Contrato de persistencia de la preferencia de tema del usuario.
///
/// **Por qué es un puerto y no una llamada directa a `shared_preferences`.**
/// El almacenamiento real es un canal de plataforma, y **en `flutter test` no
/// hay plugin que lo atienda**: `SharedPreferences.getInstance()` lanza
/// `MissingPluginException` salvo que la prueba haya llamado antes a
/// `setMockInitialValues`. Eso convertiría a la prueba del tema en una prueba
/// del *doble del plugin*: comprobaría que el mock responde, no que nuestra
/// lógica elige bien el tema ni que sabe caer al valor por defecto cuando la
/// preferencia no existe o es ilegible —que es justo lo que puede fallar—.
///
/// Es el mismo criterio que el proyecto ya aplica a los servicios externos y
/// que está escrito en `selector_archivos.dart`: **se inyectan, no se derivan
/// por dentro**. El proveedor de tema recibe un [PreferenciasTema]; en
/// producción es el del dispositivo, en las pruebas es un doble en memoria.
///
/// **No hay `export` condicional aquí, y es deliberado.** El puerto hermano
/// [SelectorDeArchivos] sí lo necesita porque `package:web` y
/// `dart:js_interop` **no existen** en la VM, así que el problema es de
/// *compilación*. `shared_preferences` sí compila en la VM: su problema es de
/// *ejecución*, y eso se resuelve inyectando, no bifurcando el import. Copiar
/// la bifurcación sin su motivo habría añadido dos archivos que no hacen nada.
///
/// **Lo que este puerto NO decide.** No valida el valor: guarda y devuelve una
/// cadena opaca. Traducirla a un `ThemeMode` —y decidir qué hacer con una
/// cadena desconocida— es de quien la interpreta, que es el único que conoce el
/// dominio. Un puerto que "arreglara" valores inválidos escondería el caso
/// límite en vez de dejarlo resuelto en un solo sitio y con nombre.
library;

abstract interface class PreferenciasTema {
  /// Devuelve el valor guardado, o `null` si no hay ninguno.
  ///
  /// Devuelve `null` —en vez de lanzar— cuando el almacenamiento **no está
  /// disponible**. No poder leer una preferencia no es un error: es la ausencia
  /// de la preferencia, y quien llama ya tiene un valor por defecto sensato
  /// (`ThemeMode.system` en el caso del tema). Distinguir «no hay» de «no se
  /// pudo leer» no cambiaría ninguna decisión aguas arriba, así que no se
  /// distingue.
  Future<String?> leer();

  /// Guarda [valor], sobrescribiendo lo anterior.
  ///
  /// A diferencia de [leer], un fallo **sí lanza**: aquí el usuario pidió algo
  /// concreto y no se cumplió, y quien llama decide qué hacer con ello. El
  /// proveedor de tema lo captura, porque su acción —cambiar el tema— ya se
  /// completó en memoria y no depende de que se recuerde.
  Future<void> guardar(String valor);
}
