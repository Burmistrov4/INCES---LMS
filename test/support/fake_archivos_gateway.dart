import 'package:inces_lms_app/core/gateways/archivos_gateway.dart';
import 'package:inces_lms_app/models/archivo.dart';

/// Doble de prueba de [ArchivosGateway] para el Módulo 5.
///
/// Cumple el puerto sin red, sin Supabase y **sin R2**, igual que los otros
/// dobles del proyecto. Registra qué se envió —nombre, entidad, el
/// `Content-Type` del `PUT` y el contenido— porque el contrato de esta capa no
/// es sólo «devuelve un archivo»: es «sube los bytes al sitio correcto con el
/// tipo que el servidor firmó».
///
/// Los errores se fuerzan con los campos `errorAl*`; al lanzar un [AppException]
/// el repositorio lo envuelve en `Failure`, que es lo que la UI debe distinguir
/// de un éxito.
///
/// **Lo que este doble NO puede probar:** que R2 acepte la firma, que el objeto
/// pese lo que dice, ni que el `Content-Type` firmado sea realmente rechazado si
/// se miente. Aquí no hay `PUT` de verdad. Eso lo cubre `supabase/humo-archivos.mjs`
/// contra el bucket real.
class FakeArchivosGateway implements ArchivosGateway {
  // --- Datos que devuelve ---------------------------------------------------

  /// El archivo que devuelve el paso 1: recién reservado, `PENDING` y sin tamaño.
  Archivo archivoFirmadoDevuelto = archivoEjemplo();

  /// El archivo que devuelve el paso 3: ya confirmado y con el tamaño sellado.
  Archivo archivoConfirmadoDevuelto = archivoEjemplo(
    estado: EstadoArchivo.confirmed,
    tamanoBytes: 512,
    confirmadoEn: '2026-09-18T12:00:05.000Z',
  );

  Archivo archivoBorradoDevuelto = archivoEjemplo(
    estado: EstadoArchivo.deleted,
    tamanoBytes: 512,
    borradoEn: '2026-09-18T12:05:00.000Z',
  );

  UrlDeLectura lecturaDevuelta = const UrlDeLectura(
    urlDeLectura: 'https://cuenta.r2.cloudflarestorage.com/bucket/clave.pdf?firma=x',
    expiraEnSegundos: 300,
    nombreOriginal: 'Constancia José.pdf',
  );

  String urlDeSubidaDevuelta =
      'https://cuenta.r2.cloudflarestorage.com/bucket/m5_archivos/clave.pdf?firma=y';

  int expiraSubidaDevuelta = 900;

  /// Lo que devuelve el listado por entidad.
  ///
  /// Es una lista **asignable** y no una constante: lo que se prueba es que el
  /// panel pinte lo que recibe y en qué orden, y para eso la prueba tiene que
  /// poder decidir qué recibe.
  List<Archivo> archivosListados = const [];

  // --- Fallos forzados ------------------------------------------------------

  Object? errorAlFirmar;
  Object? errorAlSubirObjeto;
  Object? errorAlConfirmar;
  Object? errorAlLeer;
  Object? errorAlBorrar;
  Object? errorAlBorrarComoAdmin;
  Object? errorAlSubir;
  Object? errorAlListar;

  // --- Registro de llamadas -------------------------------------------------

  final List<String> llamadas = [];

  String? ultimoNombreOriginal;
  TipoEntidadArchivo? ultimoEntityType;
  String? ultimaEntidadId;
  String? ultimoArchivoId;

  /// El `Content-Type` que recibió el `PUT`. Es la aserción que importa: tiene
  /// que ser el del servidor, no uno deducido aquí.
  String? ultimoTipoContenidoEnviado;

  /// La URL a la que fue el `PUT`. Debe ser la de R2, no la del backend.
  String? ultimaUrlDeSubida;

  List<int>? ultimoContenido;

  void limpiarLlamadas() => llamadas.clear();

  @override
  Future<SubidaFirmada> firmarSubida({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    String? entidadId,
  }) async {
    llamadas.add('firmarSubida:$nombreOriginal');
    ultimoNombreOriginal = nombreOriginal;
    ultimoEntityType = entityType;
    ultimaEntidadId = entidadId;
    _lanzarSi(errorAlFirmar);

    return SubidaFirmada(
      archivo: archivoFirmadoDevuelto,
      urlDeSubida: urlDeSubidaDevuelta,
      expiraEnSegundos: expiraSubidaDevuelta,
    );
  }

  @override
  Future<void> subirObjeto({
    required String urlDeSubida,
    required String tipoContenido,
    required List<int> contenido,
  }) async {
    llamadas.add('subirObjeto');
    ultimaUrlDeSubida = urlDeSubida;
    ultimoTipoContenidoEnviado = tipoContenido;
    ultimoContenido = contenido;
    _lanzarSi(errorAlSubirObjeto);
  }

  @override
  Future<Archivo> confirmar(String archivoId) async {
    llamadas.add('confirmar:$archivoId');
    ultimoArchivoId = archivoId;
    _lanzarSi(errorAlConfirmar);
    return archivoConfirmadoDevuelto;
  }

  @override
  Future<UrlDeLectura> urlDeLectura(String archivoId) async {
    llamadas.add('urlDeLectura:$archivoId');
    ultimoArchivoId = archivoId;
    _lanzarSi(errorAlLeer);
    return lecturaDevuelta;
  }

  @override
  Future<Archivo> borrar(String archivoId) async {
    llamadas.add('borrar:$archivoId');
    ultimoArchivoId = archivoId;
    _lanzarSi(errorAlBorrar);
    return archivoBorradoDevuelto;
  }

  @override
  Future<Archivo> borrarComoAdmin(String archivoId) async {
    llamadas.add('borrarComoAdmin:$archivoId');
    ultimoArchivoId = archivoId;
    _lanzarSi(errorAlBorrarComoAdmin);
    return archivoBorradoDevuelto;
  }

  @override
  Future<List<Archivo>> listarPorEntidad({
    required TipoEntidadArchivo entityType,
    required String entidadId,
  }) async {
    llamadas.add('listarPorEntidad:${entityType.valorRemoto}:$entidadId');
    ultimoEntityType = entityType;
    ultimaEntidadId = entidadId;
    _lanzarSi(errorAlListar);
    return archivosListados;
  }

  @override
  Future<Archivo> subir({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    required List<int> contenido,
    String? entidadId,
  }) async {
    llamadas.add('subir:$nombreOriginal');
    ultimoNombreOriginal = nombreOriginal;
    ultimoEntityType = entityType;
    ultimaEntidadId = entidadId;
    ultimoContenido = contenido;
    _lanzarSi(errorAlSubir);
    return archivoConfirmadoDevuelto;
  }

  void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }
}

/// Fixture: un archivo con los campos que el backend devuelve de verdad.
///
/// Por defecto nace `PENDING` y sin tamaño, que es como sale del paso 1: una
/// fila reservada a la que todavía no se le ha medido el objeto.
Archivo archivoEjemplo({
  String id = 'a1b2c3d4-0000-4000-8000-000000000001',
  String propietarioId = 'prop-1',
  String nombreOriginal = 'Constancia José.pdf',
  String tipoContenido = 'application/pdf',
  int? tamanoBytes,
  TipoEntidadArchivo entityType = TipoEntidadArchivo.taskSubmission,
  String? entidadId,
  EstadoArchivo estado = EstadoArchivo.pending,
  String creadoEn = '2026-09-18T12:00:00.000Z',
  String? confirmadoEn,
  String? borradoEn,
}) =>
    Archivo(
      id: id,
      propietarioId: propietarioId,
      r2Key: 'm5_archivos/$propietarioId/2026/09/00000000-0000-4000-8000-000000000009.pdf',
      nombreOriginal: nombreOriginal,
      tipoContenido: tipoContenido,
      tamanoBytes: tamanoBytes,
      entityType: entityType,
      entidadId: entidadId,
      estado: estado,
      creadoEn: creadoEn,
      confirmadoEn: confirmadoEn,
      borradoEn: borradoEn,
    );
