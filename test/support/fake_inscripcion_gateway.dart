import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/inscripcion_gateway.dart';
import 'package:inces_lms_app/models/inscripcion.dart';

/// Doble de prueba de [InscripcionGateway] para el Módulo 4.
///
/// Cumple el puerto sin red ni Supabase, igual que [FakeCuadranteGateway]: un
/// test de widget o de repositorio corre en el VM de `flutter test` con datos
/// controlados. Registra **qué se envió** (sección, ids, flags) para comprobar
/// el contrato de transporte, no solo lo que la pantalla pinta.
///
/// Los errores se fuerzan con los campos `errorAl*`; al lanzar un [AppException]
/// el repositorio los envuelve en [Result.failure], que es justo lo que la UI
/// debe distinguir de un éxito.
class FakeInscripcionGateway implements InscripcionGateway {
  // --- Datos que devuelve ---------------------------------------------------

  List<OcupacionSeccion> ofertasDevueltas = const [];
  List<InscripcionDetallada> misInscripcionesDevueltas = const [];
  List<OcupacionSeccion> ocupacionDevuelta = const [];

  EstadoInscripcion inscritoDevuelto = EstadoInscripcion.enrolled;
  EstadoInscripcion renunciadoDevuelto = EstadoInscripcion.dropped;
  EstadoInscripcion aceptadoDevuelto = EstadoInscripcion.enrolled;
  EstadoInscripcion reincorporadoDevuelto = EstadoInscripcion.enrolled;

  InscripcionDetallada promovidaDevuelta = inscripcionDetalladaEjemplo();

  /// Secuencia de «ofertas vencidas» que devuelve `expirarOfertas`. Vacía → 0.
  /// Sirve para probar la idempotencia: [3, 0] simula «primera llamada 3,
  /// segunda 0».
  List<int> expirarSecuencia = const [0];

  // --- Fallos forzados ------------------------------------------------------

  Object? errorAlObtenerOfertas;
  Object? errorAlObtenerMisInscripciones;
  Object? errorAlInscribirse;
  Object? errorAlRenunciar;
  Object? errorAlAceptar;
  Object? errorAlObtenerOcupacion;
  Object? errorAlPromover;
  Object? errorAlExpirar;
  Object? errorAlReincorporar;

  // --- Registro de llamadas -------------------------------------------------

  final List<String> llamadas = [];

  String? ultimaSeccion;
  String? ultimoEstudiante;
  bool? ultimoSoloConCupo;

  void limpiarLlamadas() => llamadas.clear();

  // ---------------------------------------------------------------------------
  // Catálogo de ofertas del estudiante
  // ---------------------------------------------------------------------------

  @override
  Future<List<OcupacionSeccion>> obtenerOfertas({bool soloConCupo = false}) async {
    llamadas.add('obtenerOfertas');
    ultimoSoloConCupo = soloConCupo;
    _lanzarSi(errorAlObtenerOfertas);
    return ofertasDevueltas;
  }

  // ---------------------------------------------------------------------------
  // Mis inscripciones
  // ---------------------------------------------------------------------------

  @override
  Future<List<InscripcionDetallada>> obtenerMisInscripciones() async {
    llamadas.add('obtenerMisInscripciones');
    _lanzarSi(errorAlObtenerMisInscripciones);
    return misInscripcionesDevueltas;
  }

  // ---------------------------------------------------------------------------
  // Acciones del estudiante
  // ---------------------------------------------------------------------------

  @override
  Future<EstadoInscripcion> inscribirse(String seccionId) async {
    llamadas.add('inscribirse:$seccionId');
    ultimaSeccion = seccionId;
    _lanzarSi(errorAlInscribirse);
    return inscritoDevuelto;
  }

  @override
  Future<EstadoInscripcion> renunciar(String seccionId) async {
    llamadas.add('renunciar:$seccionId');
    ultimaSeccion = seccionId;
    _lanzarSi(errorAlRenunciar);
    return renunciadoDevuelto;
  }

  @override
  Future<EstadoInscripcion> aceptarOferta(String seccionId) async {
    llamadas.add('aceptarOferta:$seccionId');
    ultimaSeccion = seccionId;
    _lanzarSi(errorAlAceptar);
    return aceptadoDevuelto;
  }

  // ---------------------------------------------------------------------------
  // Panel de ocupación del administrador
  // ---------------------------------------------------------------------------

  @override
  Future<List<OcupacionSeccion>> obtenerOcupacion({bool soloConCupo = false}) async {
    llamadas.add('obtenerOcupacion');
    ultimoSoloConCupo = soloConCupo;
    _lanzarSi(errorAlObtenerOcupacion);
    return ocupacionDevuelta;
  }

  @override
  Future<InscripcionDetallada> promoverSiguiente(String seccionId) async {
    llamadas.add('promoverSiguiente:$seccionId');
    ultimaSeccion = seccionId;
    _lanzarSi(errorAlPromover);
    return promovidaDevuelta;
  }

  @override
  Future<int> expirarOfertas() async {
    llamadas.add('expirarOfertas');
    _lanzarSi(errorAlExpirar);
    return expirarSecuencia.isEmpty ? 0 : expirarSecuencia.removeAt(0);
  }

  @override
  Future<EstadoInscripcion> reincorporar({
    required String estudianteId,
    required String seccionId,
  }) async {
    llamadas.add('reincorporar:$estudianteId:$seccionId');
    ultimoEstudiante = estudianteId;
    ultimaSeccion = seccionId;
    _lanzarSi(errorAlReincorporar);
    return reincorporadoDevuelto;
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }
}

/// Fixture: una sección con ocupación, para catálogo y panel de admin.
OcupacionSeccion ocupacionSeccionEjemplo({
  String id = 'sec-1',
  String nombre = 'Soldadura por Arco',
  String materia = 'Soldadura por Arco',
  int cupoEfectivo = 5,
  int cuposOcupados = 2,
  int cuposDisponibles = 3,
  bool ofertaVigente = false,
}) =>
    OcupacionSeccion(
      seccionId: id,
      periodo: 'SA26-2',
      programaId: 'prog-1',
      programaNombre: 'Soldadura',
      materiaId: 'mat-1',
      materiaNombre: materia,
      nombre: nombre,
      activa: true,
      cupoEfectivo: cupoEfectivo,
      cuposOcupados: cuposOcupados,
      cuposDisponibles: cuposDisponibles,
      ofertaVigente: ofertaVigente,
    );

/// Fixture: una inscripción detallada, para «Mis inscripciones».
InscripcionDetallada inscripcionDetalladaEjemplo({
  String id = 'insc-1',
  String estudianteId = 'est-1',
  String seccionId = 'sec-1',
  EstadoInscripcion estado = EstadoInscripcion.waitlisted,
  String? ofertaVenceEn,
  int? posicionEnCola,
  String seccionNombre = 'Soldadura por Arco',
  String materia = 'Soldadura por Arco',
  String programa = 'Soldadura',
}) =>
    InscripcionDetallada(
      id: id,
      estudianteId: estudianteId,
      seccionId: seccionId,
      estado: estado,
      ofertaVenceEn: ofertaVenceEn,
      periodo: 'SA26-2',
      seccionNombre: seccionNombre,
      materiaId: 'mat-1',
      materiaNombre: materia,
      programaId: 'prog-1',
      programaNombre: programa,
      posicionEnCola: posicionEnCola,
      estudianteNombre: 'Lorenzo Roca',
      estudianteEmail: 'lorenzo@inces.gob.ve',
    );
