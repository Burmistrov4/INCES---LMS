import 'package:inces_lms_app/core/gateways/curriculo_gateway.dart';
import 'package:inces_lms_app/models/materia.dart';
import 'package:inces_lms_app/models/pensum.dart';
import 'package:inces_lms_app/models/programa.dart';

/// Doble de prueba de [CurriculoGateway].
///
/// Cumple el puerto sin red ni credenciales, igual que [FakeGateway] con los
/// gateways de M1. Registra lo que recibe para poder comprobar **qué se envió**
/// y no sólo qué se mostró: el asistente puede pintar bien la revisión y mandar
/// un cuerpo equivocado, y eso es justo lo que interesa atrapar.
class FakeCurriculoGateway implements CurriculoGateway {
  // --- Datos que devuelve ---------------------------------------------------

  List<ProgramaConTotales> programas = const [];
  int totalProgramas = 0;

  List<Materia> materias = const [];
  int totalMaterias = 0;

  DetallePrograma? detalle;
  DetallePrograma? detalleCreado;
  DetallePrograma? detalleReemplazado;
  Programa? programaActualizado;
  Materia? materiaCreada;

  // --- Fallos forzados ------------------------------------------------------

  Object? errorAlListar;
  Object? errorAlDetalle;
  Object? errorAlCrear;
  Object? errorAlActualizar;
  Object? errorAlReemplazar;
  Object? errorAlListarMaterias;
  Object? errorAlCrearMateria;

  // --- Registro de llamadas -------------------------------------------------

  final List<String> llamadas = [];

  EntradaCrearPrograma? ultimaCreacion;
  CambiosPrograma? ultimosCambios;
  List<EntradaPensum>? ultimoPensum;
  EntradaCrearMateria? ultimaMateria;
  String? ultimaBusquedaMaterias;
  int? ultimoDesplazamientoMaterias;

  void limpiarLlamadas() => llamadas.clear();

  @override
  Future<PaginaProgramas> listarProgramas({
    TipoPrograma? tipo,
    bool? activo,
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    llamadas.add('listarProgramas');
    _lanzarSi(errorAlListar);
    return PaginaProgramas(programas: programas, total: totalProgramas);
  }

  @override
  Future<DetallePrograma> detallePrograma(String id) async {
    llamadas.add('detallePrograma:$id');
    _lanzarSi(errorAlDetalle);
    final d = detalle;
    if (d == null) throw StateError('El doble no tiene detalle configurado.');
    return d;
  }

  @override
  Future<DetallePrograma> crearPrograma(EntradaCrearPrograma entrada) async {
    llamadas.add('crearPrograma');
    ultimaCreacion = entrada;
    _lanzarSi(errorAlCrear);
    final d = detalleCreado;
    if (d == null) throw StateError('El doble no tiene detalleCreado.');
    return d;
  }

  @override
  Future<Programa> actualizarPrograma(String id, CambiosPrograma cambios) async {
    llamadas.add('actualizarPrograma:$id');
    ultimosCambios = cambios;
    _lanzarSi(errorAlActualizar);
    final p = programaActualizado;
    if (p == null) throw StateError('El doble no tiene programaActualizado.');
    return p;
  }

  @override
  Future<DetallePrograma> reemplazarPensum(
    String id,
    List<EntradaPensum> pensum,
  ) async {
    llamadas.add('reemplazarPensum:$id');
    ultimoPensum = pensum;
    _lanzarSi(errorAlReemplazar);
    final d = detalleReemplazado;
    if (d == null) throw StateError('El doble no tiene detalleReemplazado.');
    return d;
  }

  @override
  Future<PaginaMaterias> listarMaterias({
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    llamadas.add('listarMaterias');
    ultimaBusquedaMaterias = busqueda;
    ultimoDesplazamientoMaterias = desplazamiento;
    _lanzarSi(errorAlListarMaterias);
    return PaginaMaterias(materias: materias, total: totalMaterias);
  }

  @override
  Future<Materia> crearMateria(EntradaCrearMateria entrada) async {
    llamadas.add('crearMateria');
    ultimaMateria = entrada;
    _lanzarSi(errorAlCrearMateria);
    final m = materiaCreada;
    if (m == null) throw StateError('El doble no tiene materiaCreada.');
    return m;
  }

  static void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }
}

// -----------------------------------------------------------------------------
//  Datos de ejemplo
// -----------------------------------------------------------------------------

const String idSistemas = '11111111-1111-4111-8111-111111111111';
const String idAlgoritmica = '22222222-2222-4222-8222-222222222222';
const String idBasedatos = '33333333-3333-4333-8333-333333333333';

Materia algoritmica() => const Materia(
      id: idAlgoritmica,
      codigo: 'ALG-I',
      nombre: 'Algorítmica',
      horasAcademicas: 96,
    );

Materia basesDeDatos() => const Materia(
      id: idBasedatos,
      codigo: 'BD-I',
      nombre: 'Bases de Datos',
      horasAcademicas: 80,
    );

ProgramaConTotales programaSistemas({
  int totalMaterias = 2,
  int totalPeriodos = 2,
  bool activo = true,
}) =>
    ProgramaConTotales(
      id: idSistemas,
      codigo: 'SIST-01',
      nombre: 'Análisis de Sistemas',
      tipo: TipoPrograma.carrera,
      requierePasantia: true,
      activo: activo,
      totalMaterias: totalMaterias,
      totalPeriodos: totalPeriodos,
    );

DetallePrograma detalleSistemas({
  List<GrupoPensum<MateriaEnPensum>>? pensum,
  bool editable = true,
  int seccionesActivas = 0,
}) =>
    DetallePrograma(
      programa: programaSistemas(),
      pensum: pensum ??
          [
            GrupoPensum<MateriaEnPensum>(
              periodo: 1,
              materias: [
                const MateriaEnPensum(
                  materiaId: idAlgoritmica,
                  periodo: 1,
                  codigo: 'ALG-I',
                  nombre: 'Algorítmica',
                  horasAcademicas: 96,
                ),
              ],
            ),
            GrupoPensum<MateriaEnPensum>(
              periodo: 4,
              materias: [
                const MateriaEnPensum(
                  materiaId: idBasedatos,
                  periodo: 4,
                  codigo: 'BD-I',
                  nombre: 'Bases de Datos',
                  horasAcademicas: 80,
                ),
              ],
            ),
          ],
      seccionesActivas: seccionesActivas,
      editable: editable,
    );
