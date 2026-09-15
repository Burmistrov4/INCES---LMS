import 'package:inces_lms_app/core/gateways/cuadrante_gateway.dart';
import 'package:inces_lms_app/models/cuadrante.dart';

/// Doble de prueba de [CuadranteGateway].
///
/// Cumple el puerto sin red ni credenciales, igual que [FakeCurriculoGateway] y
/// [FakeGateway]. Registra lo que recibe para poder comprobar **qué se envió** y
/// no sólo qué se mostró: una pantalla puede pintar bien y mandar un cuerpo
/// equivocado, y eso es justo lo que interesa atrapar.
///
/// Los datos que devuelve van con sufijo `Devuelto` a propósito: `rejilla` y
/// `miHorario` son nombres de método del puerto, y un campo con el mismo nombre
/// no compila —el campo choca con el miembro heredado—.
///
/// **Lo que este doble no puede probar, y conviene recordarlo:** la colisión de
/// agenda. La invariante la impone un trigger que cruza `schedule_slots` y
/// `teacher_duties`, y un doble en memoria no reproduce ni el motor ni las dos
/// tablas. Aquí sólo se comprueba que un `CHOQUE_DE_AGENDA` que llega **se
/// distingue de un 400 genérico**; que la base lo lance de verdad lo prueba
/// `supabase/humo-cuadrante.mjs` contra la base real.
class FakeCuadranteGateway implements CuadranteGateway {
  // --- Datos que devuelve ---------------------------------------------------

  List<Aula> aulas = const [];
  int totalAulas = 0;

  List<Periodo> periodos = const [];

  List<Guardia> guardias = const [];
  int totalGuardias = 0;

  RejillaCuadrante rejillaDevuelta = const RejillaCuadrante();
  MiHorario miHorarioDevuelto = const MiHorario(rol: 'docente');

  Aula? aulaCreada;
  Aula? aulaActualizada;
  Periodo? periodoCreado;
  Periodo? periodoActualizado;
  Periodo? periodoVigente;
  Guardia? guardiaCreada;
  Guardia? guardiaActualizada;
  ClaseCuadrante? claseCreada;
  ClaseCuadrante? claseActualizada;

  // --- Fallos forzados ------------------------------------------------------

  Object? errorAlListarAulas;
  Object? errorAlCrearAula;
  Object? errorAlActualizarAula;
  Object? errorAlListarPeriodos;
  Object? errorAlCrearPeriodo;
  Object? errorAlActualizarPeriodo;
  Object? errorAlMarcarVigente;
  Object? errorAlListarGuardias;
  Object? errorAlCrearGuardia;
  Object? errorAlActualizarGuardia;
  Object? errorAlRejilla;
  Object? errorAlCrearClase;
  Object? errorAlActualizarClase;
  Object? errorAlMiHorario;

  // --- Registro de llamadas -------------------------------------------------

  final List<String> llamadas = [];

  EntradaCrearAula? ultimaAula;
  CambiosAula? ultimosCambiosAula;
  EntradaCrearPeriodo? ultimoPeriodo;
  CambiosPeriodo? ultimosCambiosPeriodo;
  EntradaCrearGuardia? ultimaGuardia;
  CambiosGuardia? ultimosCambiosGuardia;
  EntradaCrearClase? ultimaClase;
  CambiosClase? ultimosCambiosClase;

  TipoAula? ultimoTipoAula;
  bool? ultimoActiva;
  String? ultimaBusqueda;
  int? ultimoDia;
  int? ultimoBloque;
  String? ultimoPeriodoFiltro;
  String? ultimoDocenteFiltro;
  String? ultimoAulaFiltro;
  bool? ultimoIncluirInactivas;
  String? ultimoPeriodoDeHorario;

  void limpiarLlamadas() => llamadas.clear();

  // ---------------------------------------------------------------------------
  // Aulas
  // ---------------------------------------------------------------------------

  @override
  Future<PaginaAulas> listarAulas({
    TipoAula? tipo,
    bool? activa,
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    llamadas.add('listarAulas');
    ultimoTipoAula = tipo;
    ultimoActiva = activa;
    ultimaBusqueda = busqueda;
    _lanzarSi(errorAlListarAulas);
    return PaginaAulas(aulas: aulas, total: totalAulas);
  }

  @override
  Future<Aula> crearAula(EntradaCrearAula entrada) async {
    llamadas.add('crearAula');
    ultimaAula = entrada;
    _lanzarSi(errorAlCrearAula);
    return aulaCreada ??
        Aula(
          id: 'aula-nueva',
          nombre: entrada.nombre,
          capacidad: entrada.capacidad,
          esTaller: entrada.esTaller,
          activa: true,
        );
  }

  @override
  Future<Aula> actualizarAula(String id, CambiosAula cambios) async {
    llamadas.add('actualizarAula:$id');
    ultimosCambiosAula = cambios;
    _lanzarSi(errorAlActualizarAula);
    return aulaActualizada ??
        Aula(
          id: id,
          nombre: cambios.nombre ?? 'Espacio',
          capacidad: cambios.capacidad ?? 0,
          esTaller: cambios.esTaller ?? false,
          activa: cambios.activa ?? true,
        );
  }

  // ---------------------------------------------------------------------------
  // Períodos
  // ---------------------------------------------------------------------------

  @override
  Future<List<Periodo>> listarPeriodos() async {
    llamadas.add('listarPeriodos');
    _lanzarSi(errorAlListarPeriodos);
    return periodos;
  }

  @override
  Future<Periodo> crearPeriodo(EntradaCrearPeriodo entrada) async {
    llamadas.add('crearPeriodo');
    ultimoPeriodo = entrada;
    _lanzarSi(errorAlCrearPeriodo);
    return periodoCreado ??
        Periodo(
          id: 'lapso-nuevo',
          codigo: entrada.codigo,
          nombre: entrada.nombre,
          fechaInicio: entrada.fechaInicio,
          fechaFin: entrada.fechaFin,
          activo: true,
          vigente: false,
        );
  }

  @override
  Future<Periodo> actualizarPeriodo(
    String id,
    CambiosPeriodo cambios,
  ) async {
    llamadas.add('actualizarPeriodo:$id');
    ultimosCambiosPeriodo = cambios;
    _lanzarSi(errorAlActualizarPeriodo);
    return periodoActualizado ??
        Periodo(
          id: id,
          codigo: '2026-1',
          activo: cambios.activo ?? true,
          vigente: false,
        );
  }

  @override
  Future<Periodo> marcarVigente(String id) async {
    llamadas.add('marcarVigente:$id');
    _lanzarSi(errorAlMarcarVigente);
    return periodoVigente ??
        Periodo(id: id, codigo: '2026-1', activo: true, vigente: true);
  }

  // ---------------------------------------------------------------------------
  // Guardias
  // ---------------------------------------------------------------------------

  @override
  Future<PaginaGuardias> listarGuardias({
    String? periodo,
    String? docenteId,
    String? aulaId,
    int? dia,
    int? bloque,
    bool? activa,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    llamadas.add('listarGuardias');
    ultimoPeriodoFiltro = periodo;
    ultimoDocenteFiltro = docenteId;
    ultimoAulaFiltro = aulaId;
    ultimoDia = dia;
    ultimoBloque = bloque;
    ultimoActiva = activa;
    _lanzarSi(errorAlListarGuardias);
    return PaginaGuardias(guardias: guardias, total: totalGuardias);
  }

  @override
  Future<Guardia> crearGuardia(EntradaCrearGuardia entrada) async {
    llamadas.add('crearGuardia');
    ultimaGuardia = entrada;
    _lanzarSi(errorAlCrearGuardia);
    return guardiaCreada ?? _guardiaDesde(entrada);
  }

  @override
  Future<Guardia> actualizarGuardia(
    String id,
    CambiosGuardia cambios,
  ) async {
    llamadas.add('actualizarGuardia:$id');
    ultimosCambiosGuardia = cambios;
    _lanzarSi(errorAlActualizarGuardia);
    return guardiaActualizada ??
        Guardia(
          id: id,
          docenteId: cambios.docenteId ?? 'docente-1',
          aulaId: cambios.aulaId ?? 'aula-1',
          periodo: cambios.periodo ?? '2026-1',
          dia: cambios.dia ?? 1,
          bloque: cambios.bloque ?? 1,
          turno: turnoDeBloque(cambios.bloque ?? 1),
          notas: cambios.notas,
          activa: cambios.activa ?? true,
        );
  }

  // ---------------------------------------------------------------------------
  // Cuadrante
  // ---------------------------------------------------------------------------

  @override
  Future<RejillaCuadrante> rejilla({
    String? periodo,
    String? seccionId,
    String? docenteId,
    String? aulaId,
    bool incluirInactivas = false,
  }) async {
    llamadas.add('rejilla');
    ultimoPeriodoFiltro = periodo;
    ultimoIncluirInactivas = incluirInactivas;
    _lanzarSi(errorAlRejilla);
    return rejillaDevuelta;
  }

  @override
  Future<ClaseCuadrante> crearClase(EntradaCrearClase entrada) async {
    llamadas.add('crearClase');
    ultimaClase = entrada;
    _lanzarSi(errorAlCrearClase);
    return claseCreada ?? _claseDesde(entrada);
  }

  @override
  Future<ClaseCuadrante> actualizarClase(
    String id,
    CambiosClase cambios,
  ) async {
    llamadas.add('actualizarClase:$id');
    ultimosCambiosClase = cambios;
    _lanzarSi(errorAlActualizarClase);
    return claseActualizada ??
        ClaseCuadrante(
          id: id,
          seccionId: 'seccion-1',
          docenteId: cambios.docenteId ?? 'docente-1',
          aulaId: cambios.aulaId ?? 'aula-1',
          dia: cambios.dia ?? 1,
          bloque: cambios.bloque ?? 1,
          turno: turnoDeBloque(cambios.bloque ?? 1),
          activa: cambios.activa ?? true,
          periodo: '2026-1',
          programaId: 'programa-1',
          programa: 'Soldadura',
          materiaId: 'materia-1',
          materia: 'Soldadura por Arco',
          seccion: 'SC',
          aula: 'Taller A',
          docente: 'Luis Márquez',
        );
  }

  // ---------------------------------------------------------------------------
  // Horario por rol
  // ---------------------------------------------------------------------------

  @override
  Future<MiHorario> miHorario({String? periodo}) async {
    llamadas.add('miHorario');
    ultimoPeriodoDeHorario = periodo;
    _lanzarSi(errorAlMiHorario);
    return miHorarioDevuelto;
  }

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }

  Guardia _guardiaDesde(EntradaCrearGuardia entrada) => Guardia(
        id: 'guardia-nueva',
        docenteId: entrada.docenteId,
        aulaId: entrada.aulaId,
        periodo: entrada.periodo,
        dia: entrada.dia,
        bloque: entrada.bloque,
        turno: turnoDeBloque(entrada.bloque),
        notas: entrada.notas,
        activa: true,
      );

  ClaseCuadrante _claseDesde(EntradaCrearClase entrada) => ClaseCuadrante(
        id: 'clase-nueva',
        seccionId: entrada.seccionId,
        docenteId: entrada.docenteId,
        aulaId: entrada.aulaId,
        dia: entrada.dia,
        bloque: entrada.bloque,
        turno: turnoDeBloque(entrada.bloque),
        activa: true,
        periodo: '2026-1',
        programaId: 'programa-1',
        programa: 'Soldadura',
        materiaId: 'materia-1',
        materia: 'Soldadura por Arco',
        seccion: 'SC',
        aula: 'Taller A',
        docente: 'Luis Márquez',
      );
}
