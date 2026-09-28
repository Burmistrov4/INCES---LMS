import 'dart:async';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/result.dart';
import 'package:inces_lms_app/services/asistencia_service.dart';

/// Doble de prueba de [AsistenciaService] para la asistencia concurrente (M7).
///
/// **Por qué hereda y no implementa.** [AsistenciaService] es una clase concreta
/// sin interfaz propia, así que el doble la **extiende** y sobrescribe los cinco
/// métodos. Es lo que los dos paneles esperan: `servicio: widget.servicio ??
/// AsistenciaService()`, un parámetro del mismo tipo. Los demás dobles del
/// proyecto (`FakeAulaGateway`) implementan un `abstract interface class` porque
/// el gateway sí tiene puerto; aquí no lo hay, y añadirlo sólo para poder doblarlo
/// sería diseñar la producción alrededor de la prueba.
///
/// **`codigoQr` NO se dobla.** Es `static` y es la pieza que se prueba de verdad
/// en `test/asistencia_service_test.dart`, contra vectores calculados por
/// Postgres. Sobrescribirla aquí haría que los paneles se probaran contra una
/// derivación inventada y la paridad real quedara sin cubrir.
///
/// **El canal en vivo se controla desde la prueba.** `enVivo` devuelve el stream
/// de un `StreamController` que la prueba maneja, porque el empuje es justo lo
/// que hay que provocar: un doble que nunca emitiera dejaría el camino «llega una
/// marca y la fila se pinta» sin ejercitar, que es la mitad del diseño de M7.
///
/// **Lo que este doble NO puede probar:** que la RLS acepte o rechace de verdad,
/// ni que el código derivado coincida con el de la base. Eso lo cubren
/// `backend/test/asistencia.test.ts` (contrato de las rutas contra el doble del
/// arnés) y los vectores dorados de `asistencia_service_test.dart`.
class FakeAsistenciaService extends AsistenciaService {
  // --- Registro de llamadas -------------------------------------------------

  final List<String> llamadas = [];

  String? ultimaSeccionAbierta;
  int? ultimaVentanaPedida;
  String? ultimoSesionIdCerrado;
  String? ultimoSesionIdMarcado;
  String? ultimoCodigoMarcado;
  String? ultimoSesionIdEnVivo;

  /// El código de la vía MANUAL de D21: seis dígitos, sin sesión.
  ///
  /// Va en su propio campo y no reutiliza [ultimoCodigoMarcado] a propósito: si
  /// las dos vías escribieran en el mismo sitio, una prueba que viera el código
  /// correcto no podría distinguir por cuál de las dos entró, y esa distinción
  /// es justo lo que D21 añadió.
  String? ultimoCodigoSuelto;

  void limpiarLlamadas() => llamadas.clear();

  // --- Datos que devuelve ---------------------------------------------------

  /// La fila que devuelve `abrirSesion`. Por defecto, una sesión abierta válida.
  Map<String, dynamic> sesionAResponder = {
    'id': 'e5e5e5e5-0001-4001-8001-000000000001',
    'section_id': 'cccccccc-0001-4001-8001-000000000001',
    'opened_by': '33333333-3333-3333-3333-333333333333',
    'opened_at': '2026-09-27T10:00:00.000Z',
    'qr_secret': '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
    'ventana_seg': 15,
    'status': 'OPEN',
  };

  /// Las marcas que devuelve `marcas` (rehidratación al abrir el panel).
  List<MarcaAsistencia> marcasAResponder = const [];

  // --- Fallos forzados ------------------------------------------------------

  Object? errorAlAbrir;
  Object? errorAlCerrar;
  Object? errorAlMarcar;
  Object? errorAlListarMarcas;

  /// Lo que devuelve la vía manual cuando el alumno ya estaba contado.
  ///
  /// Es un dato y no un fallo: el servidor responde 200 con `duplicada: true`, y
  /// la pantalla tiene que pintarlo como un «ya estabas» y no como un error. Sin
  /// este interruptor, ese camino —el único que distingue «marqué» de «ya
  /// estaba»— no se podría provocar desde una prueba.
  bool marcarConCodigoDevuelveDuplicada = false;

  // --- El canal en vivo -----------------------------------------------------

  StreamController<EventoAsistencia>? _canal;

  /// Empuja un evento al panel, como haría el servidor.
  void empujar(Map<String, dynamic> evento) {
    _canal?.add(EventoAsistencia.deJson(evento));
  }

  /// Empuja una marca, con la forma exacta que serializa el backend.
  void empujarMarca({
    String sesionId = 'e5e5e5e5-0001-4001-8001-000000000001',
    String estudianteId = '22222222-2222-2222-2222-222222222222',
    String marcadaEn = '2026-09-27T10:00:05.000Z',
  }) {
    empujar({
      'tipo': 'marca',
      'sesionId': sesionId,
      'marca': {
        'id': 'f6f6f6f6-0000-4000-8000-000000000001',
        'session_id': sesionId,
        'student_id': estudianteId,
        'marked_at': marcadaEn,
      },
    });
  }

  /// Cierra el canal **limpiamente**, como cuando el otro extremo se despide.
  ///
  /// Ojo: un cierre limpio **no** es un error. `WebSocketChannel` emite `done`,
  /// no `error`, y el panel tiene que tratar los dos casos por separado — con
  /// sólo `onError` el tablero se congelaba en silencio (ver **D22**).
  void cerrarCanal() {
    _canal?.close();
    _canal = null;
  }

  /// Rompe el canal con un **error**, como una conexión que se cae de verdad.
  void fallarCanal([Object error = const _FalloDeCanal()]) {
    _canal?.addError(error);
  }

  // --- Retener una petición en vuelo ----------------------------------------

  /// Si es `true`, `marcar` **no** resuelve hasta que la prueba llame a
  /// [completarMarcar].
  ///
  /// **Por qué hace falta.** Un futuro que se resuelve solo es imposible de
  /// observar «en vuelo»: `tester.tap` ya deja correr los microtareas, así que
  /// para cuando la prueba mira el botón la petición terminó y el botón está
  /// deshabilitado **por otro motivo**. Una prueba así pasa y no prueba nada.
  /// Con el `Completer`, el estado intermedio dura lo que la prueba quiera.
  bool retenerMarcar = false;

  final List<Completer<void>> _marcasRetenidas = [];

  /// Suelta las peticiones que [retenerMarcar] dejó en el aire.
  void completarMarcar() {
    for (final espera in _marcasRetenidas) {
      if (!espera.isCompleted) espera.complete();
    }
    _marcasRetenidas.clear();
  }

  // --- El puerto ------------------------------------------------------------

  @override
  Future<Result<Map<String, dynamic>>> abrirSesion({
    required String seccionId,
    int ventanaSeg = 15,
  }) async {
    llamadas.add('abrirSesion:$seccionId');
    ultimaSeccionAbierta = seccionId;
    ultimaVentanaPedida = ventanaSeg;

    final fallo = errorAlAbrir;
    if (fallo != null) {
      return Failure<Map<String, dynamic>>(_comoAppException(fallo));
    }
    return Success<Map<String, dynamic>>(sesionAResponder);
  }

  @override
  Future<Result<void>> cerrarSesion({required String sesionId}) async {
    llamadas.add('cerrarSesion:$sesionId');
    ultimoSesionIdCerrado = sesionId;

    final fallo = errorAlCerrar;
    if (fallo != null) return Failure<void>(_comoAppException(fallo));
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> marcar({required String sesionId, required String codigo}) async {
    llamadas.add('marcar:$sesionId');
    ultimoSesionIdMarcado = sesionId;
    ultimoCodigoMarcado = codigo;

    if (retenerMarcar) {
      final espera = Completer<void>();
      _marcasRetenidas.add(espera);
      await espera.future;
    }

    final fallo = errorAlMarcar;
    if (fallo != null) return Failure<void>(_comoAppException(fallo));
    return const Success<void>(null);
  }

  /// La vía MANUAL (D21): seis dígitos y ninguna sesión.
  ///
  /// Comparte [errorAlMarcar] con la vía del QR a propósito: para la pantalla,
  /// «la base rechazó la marca» es el mismo hecho por los dos caminos, y lo que
  /// cambia es sólo el mensaje que el servidor manda dentro. Un segundo campo de
  /// error dejaría creer que son dos fallos distintos.
  @override
  Future<Result<bool>> marcarConCodigo({required String codigo}) async {
    llamadas.add('marcarConCodigo:$codigo');
    ultimoCodigoSuelto = codigo;

    if (retenerMarcar) {
      final espera = Completer<void>();
      _marcasRetenidas.add(espera);
      await espera.future;
    }

    final fallo = errorAlMarcar;
    if (fallo != null) return Failure<bool>(_comoAppException(fallo));
    return Success<bool>(marcarConCodigoDevuelveDuplicada);
  }

  @override
  Future<Result<List<MarcaAsistencia>>> marcas({required String sesionId}) async {
    llamadas.add('marcas:$sesionId');

    final fallo = errorAlListarMarcas;
    if (fallo != null) {
      return Failure<List<MarcaAsistencia>>(_comoAppException(fallo));
    }
    return Success<List<MarcaAsistencia>>(marcasAResponder);
  }

  @override
  Stream<EventoAsistencia> enVivo({required String sesionId}) {
    llamadas.add('enVivo:$sesionId');
    ultimoSesionIdEnVivo = sesionId;

    _canal = StreamController<EventoAsistencia>();
    return _canal!.stream;
  }
}

/// El fallo que [FakeAsistenciaService.fallarCanal] inyecta por defecto.
///
/// Es un tipo propio y `const` por una razón concreta: los valores por defecto
/// de un parámetro tienen que ser constantes, y `StateError` no lo es.
class _FalloDeCanal implements Exception {
  const _FalloDeCanal();

  @override
  String toString() => 'La conexión en vivo se cayó.';
}

/// Convierte lo que la prueba haya puesto en `errorAlX` en una [AppException].
///
/// Se acepta tanto un `AppException` ya hecho —para fijar el mensaje que la
/// pantalla debe mostrar— como una cadena suelta, que es el caso cómodo. Sin
/// esto, cada prueba tendría que construir la excepción a mano y el doble
/// dejaría de ser cómodo de usar, que es cuando se deja de usar.
AppException _comoAppException(Object fallo) {
  if (fallo is AppException) return fallo;
  return AppException.validacion(fallo.toString());
}

/// Fixture: una marca de asistencia con la forma que devuelve el backend.
MarcaAsistencia marcaAsistenciaEjemplo({
  String id = 'f6f6f6f6-0000-4000-8000-000000000001',
  String sesionId = 'e5e5e5e5-0001-4001-8001-000000000001',
  String estudianteId = '22222222-2222-2222-2222-222222222222',
  String marcadaEn = '2026-09-27T10:00:00.000Z',
}) =>
    MarcaAsistencia(
      id: id,
      sessionId: sesionId,
      studentId: estudianteId,
      marcadaEn: marcadaEn,
    );
