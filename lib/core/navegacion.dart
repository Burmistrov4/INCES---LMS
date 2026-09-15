/// Enrutado de los enlaces que llegan desde la URL.
///
/// Flutter resuelve la tabla `routes` de `MaterialApp` con coincidencia
/// **exacta de cadena**. Un enlace profundo no llega limpio: llega con su
/// consulta pegada (`/auth/activate?token=abc`), así que no coincide con la
/// entrada `/auth/activate`. Cuando eso pasa, el `Navigator` no encuentra
/// destino, **descarta la pila inicial entera** y cae a `/`
/// (`Navigator.defaultGenerateInitialRoutes`, `navigator.dart`): el enlace de
/// activación quedaba inservible porque el token se perdía antes de que la
/// pantalla pudiera leerlo.
///
/// Aquí vive la regla que separa el camino de la consulta. Son funciones puras
/// y sin dependencia de Flutter para poder probarlas sin navegador.
library;

/// Camino de la pantalla de activación de docentes invitados.
const String rutaActivacion = '/auth/activate';

/// Un nombre de ruta ya interpretado.
class DestinoRuta {
  const DestinoRuta({required this.ruta, this.token});

  /// Camino sin consulta ni fragmento, listo para buscar en la tabla de rutas.
  final String ruta;

  /// Token de invitación, si el nombre lo traía. `null` si no venía.
  final String? token;

  @override
  String toString() => 'DestinoRuta(ruta: $ruta, token: $token)';
}

/// Separa un nombre de ruta en camino y token.
///
/// Cubre la forma que produce Flutter web con la estrategia de hash —la que usa
/// el proyecto—, donde el nombre llega como `/auth/activate?token=abc`, y
/// también el caso defensivo de un nombre que todavía arrastra el fragmento
/// (`/#/auth/activate?token=abc`).
DestinoRuta analizarRuta(String? nombreRuta) {
  final original = (nombreRuta ?? '').trim();
  if (original.isEmpty) return const DestinoRuta(ruta: '/');

  final uri = Uri.parse(original);

  // Caso normal: el nombre ya es la ruta, con su consulta si la trae.
  if (uri.fragment.isEmpty) {
    return DestinoRuta(
      ruta: _camino(uri.path),
      token: _noVacio(uri.queryParameters['token']),
    );
  }

  // El nombre trae el fragmento dentro. El fragmento es a su vez una ruta, así
  // que se interpreta como tal: `Uri.parse(fragmento).queryParameters` sí ve el
  // token, mientras que leerlo como cadena de consulta no lo vería.
  final interno = Uri.parse(uri.fragment);
  final caminoExterno = _camino(uri.path);
  final elFragmentoTieneRuta = interno.path.isNotEmpty;

  return DestinoRuta(
    ruta: (caminoExterno == '/' && elFragmentoTieneRuta)
        ? _camino(interno.path)
        : caminoExterno,
    token: _noVacio(interno.queryParameters['token']) ??
        _noVacio(uri.queryParameters['token']),
  );
}

/// Extrae el token de invitación de la URL de la página.
///
/// Cubre las dos estrategias de enrutado de Flutter web:
///
///  * **hash** (la del proyecto): el token vive dentro del fragmento,
///    `http://host/#/auth/activate?token=abc`;
///  * **path**: el token está en el query real,
///    `http://host/auth/activate?token=abc`.
///
/// El query de la página manda sobre el fragmento cuando ambos lo traen. Es el
/// orden que ya tenía la pantalla y se conserva a propósito: cambiarlo no
/// arreglaba nada y sí movía el comportamiento bajo los pies.
String? tokenDeUrl(Uri url) {
  final delQuery = _noVacio(url.queryParameters['token']);
  if (delQuery != null) return delQuery;

  final fragmento = url.fragment;
  if (fragmento.isEmpty) return null;

  return _noVacio(Uri.parse(fragmento).queryParameters['token']);
}

String _camino(String camino) => camino.isEmpty ? '/' : camino;

String? _noVacio(String? valor) =>
    (valor == null || valor.isEmpty) ? null : valor;
