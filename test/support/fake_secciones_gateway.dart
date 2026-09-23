import 'package:inces_lms_app/core/gateways/secciones_gateway.dart';
import 'package:inces_lms_app/models/seccion.dart';

/// Doble de prueba de [SeccionesGateway] para el panel de administración.
///
/// Mismo patrón que `FakeInscripcionGateway`: datos controlados + errores
/// forzados + registro de llamadas. Las pruebas verifican QUÉ pidió la UI y
/// CON QUÉ cuerpo, no la pinta en sí — eso lo hace el widget test.
class FakeSeccionesGateway implements SeccionesGateway {
  // --- Datos que devuelve ----------------------------------------------------

  PaginaSecciones paginaDevuelta = const PaginaSecciones(
    secciones: [],
    total: 0,
    limite: 50,
    desplazamiento: 0,
  );

  Seccion creadaDevuelta = const Seccion(
    id: 'sec-nueva',
    programaId: 'prog-1',
    materiaId: 'mat-1',
    periodo: 'SA26-2',
    nombre: 'SA',
    cupoMaximo: null,
    activa: true,
  );

  Seccion actualizadaDevuelta = const Seccion(
    id: 'sec-1',
    programaId: 'prog-1',
    materiaId: 'mat-1',
    periodo: 'SA26-2',
    nombre: 'SA',
    cupoMaximo: null,
    activa: true,
  );

  // --- Fallos forzados -------------------------------------------------------

  Object? errorAlListar;
  Object? errorAlCrear;
  Object? errorAlActualizar;

  // --- Registro de llamadas --------------------------------------------------

  final List<String> llamadas = [];
  bool? ultimoSoloActivas;
  int? ultimoLimite;
  int? ultimoDesplazamiento;
  Seccion? ultimoBorrador;
  String? ultimaIdActualizada;
  CambiosSeccion? ultimosCambios;

  void limpiarLlamadas() => llamadas.clear();

  @override
  Future<PaginaSecciones> listarSecciones({
    bool soloActivas = false,
    int limite = 50,
    int desplazamiento = 0,
  }) async {
    llamadas.add('listarSecciones');
    ultimoSoloActivas = soloActivas;
    ultimoLimite = limite;
    ultimoDesplazamiento = desplazamiento;
    _lanzarSi(errorAlListar);
    return paginaDevuelta;
  }

  @override
  Future<Seccion> crearSeccion(Seccion borrador) async {
    llamadas.add('crearSeccion');
    ultimoBorrador = borrador;
    _lanzarSi(errorAlCrear);
    return creadaDevuelta;
  }

  @override
  Future<Seccion> actualizarSeccion(String id, CambiosSeccion cambios) async {
    llamadas.add('actualizarSeccion:$id');
    ultimaIdActualizada = id;
    ultimosCambios = cambios;
    _lanzarSi(errorAlActualizar);
    return actualizadaDevuelta;
  }

  void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }
}

/// Fixture: una sección activa con cupo global.
Seccion seccionEjemplo({
  String id = 'sec-1',
  String nombre = 'SA',
  int? cupoMaximo,
  bool activa = true,
}) =>
    Seccion(
      id: id,
      programaId: 'prog-1',
      materiaId: 'mat-1',
      periodo: 'SA26-2',
      nombre: nombre,
      cupoMaximo: cupoMaximo,
      activa: activa,
    );