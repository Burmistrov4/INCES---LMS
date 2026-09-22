import 'package:inces_lms_app/core/gateways/aula_gateway.dart';

/// Doble de prueba de [AulaGateway] para el Aula Virtual (M6).
///
/// Cumple el puerto sin red, sin Supabase y sin backend, igual que los otros
/// dobles del proyecto. Registra qué se pidió —la sección del tablón, la del
/// trabajo de clase, el id de la entrega— porque el contrato de esta capa no es
/// sólo «devuelve una lista»: es «la pide para la sección/entrega correcta».
///
/// **Por qué existe hoy.** El backend de M6 se escribe en paralelo y su JSON no
/// está cerrado, así que no hay servicio HTTP. Este doble es lo que la UI usa
/// para desarrollarse y probarse; cuando llegue el servicio real, el doble sigue
/// valiendo para las pruebas de widget (como el de M5).
///
/// **`entregar` y `reclamar` mutan el estado.** No basta con devolver una fila
/// cambiada: el doble también actualiza su lista, para que una prueba pueda
/// comprobar que el estado **cambió de verdad** y que un `misEntregas()`
/// posterior lo refleja. Un doble que devolviera la mutación pero conservara el
/// estado viejo escondería justo el fallo que importa.
///
/// **`misAulas` es distinto de los demás.** Su implementación real **sí existe**
/// (`lib/services/aula_service.dart`): `GET /api/v1/mi-horario` es una ruta
/// congelada. Aquí se devuelve el resultado ya armado —[misAulasResultado]— y no
/// se simula el horario: el doble no habla la ruta ni conoce `MiHorario`, y
/// reproducir esa reducción sería probar una copia de la lógica en vez de la
/// lógica. La reducción de verdad se prueba en `test/aula_service_test.dart`,
/// contra un `http.Client` doblado.
///
/// **Lo que este doble NO puede probar:** que la RLS deje ver lo que dice, que
/// el `GRANT` por columna esconda `nota_borrador`, ni que `es_tardia` se calcule
/// con el reloj de la base. Eso lo cubre la suite de PGlite (`supabase/tests/`).
class FakeAulaGateway implements AulaGateway {
  // --- Datos que devuelve ---------------------------------------------------

  /// El feed del tablón. **El orden es el de la lista**: el doble no ordena,
  /// igual que el servidor no espera que la UI lo haga.
  List<Anuncio> anuncios = const [];

  /// Las tareas y materiales de la sección, en el orden del servidor.
  List<TareaDeClase> tareas = const [];

  /// Las entregas del estudiante.
  List<Entrega> entregas = const [];

  /// Las aulas del llamante. Se arma a mano: ver la nota de la clase.
  MisAulas misAulasResultado = const MisAulas(esDocente: false);

  // --- Fallos forzados ------------------------------------------------------

  Object? errorAlListarTablon;
  Object? errorAlListarTrabajo;
  Object? errorAlListarEntregas;
  Object? errorAlListarAulas;
  Object? errorAlEntregar;
  Object? errorAlReclamar;

  // --- Registro de llamadas -------------------------------------------------

  final List<String> llamadas = [];

  String? ultimaSeccionTablon;
  String? ultimaSeccionTrabajo;
  String? ultimaEntregaId;
  String? ultimoPeriodoAulas;

  void limpiarLlamadas() => llamadas.clear();

  @override
  Future<MisAulas> misAulas({String? periodo}) async {
    llamadas.add(periodo == null ? 'misAulas' : 'misAulas:$periodo');
    ultimoPeriodoAulas = periodo;
    _lanzarSi(errorAlListarAulas);
    return misAulasResultado;
  }

  @override
  Future<List<Anuncio>> tablon(String seccionId) async {
    llamadas.add('tablon:$seccionId');
    ultimaSeccionTablon = seccionId;
    _lanzarSi(errorAlListarTablon);
    return anuncios;
  }

  @override
  Future<List<TareaDeClase>> trabajoDeClase(String seccionId) async {
    llamadas.add('trabajoDeClase:$seccionId');
    ultimaSeccionTrabajo = seccionId;
    _lanzarSi(errorAlListarTrabajo);
    return tareas;
  }

  @override
  Future<List<Entrega>> misEntregas() async {
    llamadas.add('misEntregas');
    _lanzarSi(errorAlListarEntregas);
    return entregas;
  }

  @override
  Future<Entrega> entregar(String entregaId) async {
    llamadas.add('entregar:$entregaId');
    ultimaEntregaId = entregaId;
    _lanzarSi(errorAlEntregar);
    return _mutar(
      entregaId,
      (e) => e.copyWith(
        estado: EstadoEntrega.entregada,
        entregadaEn: '2026-09-22T10:00:00.000Z',
      ),
    );
  }

  @override
  Future<Entrega> reclamar(String entregaId) async {
    llamadas.add('reclamar:$entregaId');
    ultimaEntregaId = entregaId;
    _lanzarSi(errorAlReclamar);
    return _mutar(
      entregaId,
      (e) => e.copyWith(estado: EstadoEntrega.reclamada),
    );
  }

  /// Aplica [cambio] a la entrega y **actualiza la lista**, no sólo la copia
  /// devuelta. Si el id no existe es un fallo de la prueba, y por eso revienta
  /// en vez de devolver algo inventado.
  Entrega _mutar(String entregaId, Entrega Function(Entrega) cambio) {
    final indice = entregas.indexWhere((e) => e.id == entregaId);
    if (indice < 0) {
      throw StateError('El doble no tiene una entrega con id $entregaId');
    }

    final actualizada = cambio(entregas[indice]);
    entregas = [...entregas]..[indice] = actualizada;
    return actualizada;
  }

  void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }
}

/// Fixture: un anuncio con los campos que el backend devuelve de verdad.
Anuncio anuncioEjemplo({
  String id = 'an-1',
  String seccionId = 'sec-1',
  String titulo = 'Bienvenidos al aula',
  String cuerpo = 'Aquí encontrarás el material y las tareas del lapso.',
  EstadoAnuncio estado = EstadoAnuncio.publicado,
  String? programadoPara,
  String? publicadoEn = '2026-09-20T12:00:00.000Z',
}) =>
    Anuncio(
      id: id,
      seccionId: seccionId,
      titulo: titulo,
      cuerpo: cuerpo,
      estado: estado,
      programadoPara: programadoPara,
      publicadoEn: publicadoEn,
    );

/// Fixture: una tarea de clase, calificable por defecto.
TareaDeClase tareaEjemplo({
  String id = 'tar-1',
  String seccionId = 'sec-1',
  String titulo = 'Informe de soldadura',
  String descripcion = 'Entrega el informe con las mediciones del taller.',
  TipoTarea tipo = TipoTarea.tarea,
  double puntosMaximos = 20,
  String? fechaLimite = '2026-10-30T23:59:00.000Z',
  String? tema,
  int orden = 0,
  EstadoTarea estado = EstadoTarea.publicado,
}) =>
    TareaDeClase(
      id: id,
      seccionId: seccionId,
      titulo: titulo,
      descripcion: descripcion,
      tipo: tipo,
      puntosMaximos: puntosMaximos,
      fechaLimite: fechaLimite,
      tema: tema,
      orden: orden,
      estado: estado,
    );

/// Fixture: una entrega del estudiante.
///
/// **No lleva `estudianteId`** porque el servidor no lo manda: la entrega del
/// alumno es anónima respecto de sí misma —el «yo» lo pone `auth.uid()` en el
/// servidor—. El id del estudiante sólo aparece en el libro del docente
/// (`LibroEntrega`).
Entrega entregaEjemplo({
  String id = 'ent-1',
  String tareaId = 'tar-1',
  EstadoEntrega estado = EstadoEntrega.asignada,
  bool esTardia = false,
  double? notaAsignada,
  String? entregadaEn,
}) =>
    Entrega(
      id: id,
      tareaId: tareaId,
      estado: estado,
      esTardia: esTardia,
      notaAsignada: notaAsignada,
      entregadaEn: entregadaEn,
    );

/// Fixture: un aula del listado, con la forma que produce `/mi-horario` ya
/// reducido (una fila por sección, no por franja).
AulaResumen aulaEjemplo({
  String seccionId = 'sec-1',
  String materia = 'Soldadura',
  String seccion = 'Sección A',
  String? programa = 'Formación Profesional',
}) =>
    AulaResumen(
      seccionId: seccionId,
      materia: materia,
      seccion: seccion,
      programa: programa,
    );

/// Fixture: el listado «mis aulas», ya armado.
///
/// Por defecto trae **una** aula, para que una prueba de la pantalla no tenga
/// que montar varias; pasar `aulas` para los casos de orden o de deduplicación.
MisAulas misAulasEjemplo({
  bool esDocente = false,
  String? periodo = 'SA26-2',
  List<AulaResumen>? aulas,
}) =>
    MisAulas(
      esDocente: esDocente,
      periodo: periodo,
      aulas: aulas ?? [aulaEjemplo()],
    );
