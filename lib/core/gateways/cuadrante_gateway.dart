import '../../models/cuadrante.dart';

/// Contrato del Módulo 3 — Cuadrante, Horarios, Aulas y Guardias.
///
/// Separa la fuente de datos (el backend Fastify) de la capa de aplicación,
/// igual que [CurriculoGateway] e [InvitacionGateway]. Las implementaciones
/// **lanzan** `AppException` en fallo; el repositorio las envuelve en `Result`.
/// Para los tests se inyecta un doble sin red ni credenciales.
///
/// El puerto declara la **intención**; cómo se cumple es asunto del adaptador.
/// Que la invariante de colisión la imponga un trigger que cruza dos tablas no
/// se ve desde aquí: si mañana cambiara el mecanismo, este contrato seguiría
/// siendo el mismo.
///
/// **Ninguna operación borra.** Archivar es `activa: false`, y la base lo
/// refuerza con `on delete restrict` para que borrar un aula en uso no sea
/// posible ni por accidente.
abstract interface class CuadranteGateway {
  // --- Aulas ---------------------------------------------------------------

  /// Pide una página del catálogo de espacios, aplicando los filtros.
  Future<PaginaAulas> listarAulas({
    TipoAula? tipo,
    bool? activa,
    String? busqueda,
    int limite,
    int desplazamiento,
  });

  Future<Aula> crearAula(EntradaCrearAula entrada);

  Future<Aula> actualizarAula(String id, CambiosAula cambios);

  // --- Períodos ------------------------------------------------------------

  /// El catálogo completo de lapsos, sin paginar: un centro acumula unos pocos
  /// al año y el desplegable los necesita todos para ofrecer el siguiente.
  Future<List<Periodo>> listarPeriodos();

  Future<Periodo> crearPeriodo(EntradaCrearPeriodo entrada);

  Future<Periodo> actualizarPeriodo(String id, CambiosPeriodo cambios);

  /// Declara ese lapso como el vigente.
  ///
  /// Es la **única** forma de moverlo: escribe `system_settings.periodo_activo`.
  /// No se acepta por [actualizarPeriodo] para que no haya dos caminos que
  /// cambien lo mismo por vías distintas.
  Future<Periodo> marcarVigente(String id);

  // --- Guardias ------------------------------------------------------------

  Future<PaginaGuardias> listarGuardias({
    String? periodo,
    String? docenteId,
    String? aulaId,
    int? dia,
    int? bloque,
    bool? activa,
    int limite,
    int desplazamiento,
  });

  Future<Guardia> crearGuardia(EntradaCrearGuardia entrada);

  Future<Guardia> actualizarGuardia(String id, CambiosGuardia cambios);

  // --- Cuadrante -----------------------------------------------------------

  /// La rejilla maestra de un lapso: clases, guardias, aulas y docentes.
  Future<RejillaCuadrante> rejilla({
    String? periodo,
    String? seccionId,
    String? docenteId,
    String? aulaId,
    bool incluirInactivas,
  });

  Future<ClaseCuadrante> crearClase(EntradaCrearClase entrada);

  Future<ClaseCuadrante> actualizarClase(String id, CambiosClase cambios);

  // --- Horario por rol -----------------------------------------------------

  /// El horario del llamante. La ruta decide qué filas ve según su rol.
  Future<MiHorario> miHorario({String? periodo});
}

// -----------------------------------------------------------------------------
//  Aulas
// -----------------------------------------------------------------------------

/// Cuerpo de `POST /api/v1/admin/aulas`.
class EntradaCrearAula {
  const EntradaCrearAula({
    required this.nombre,
    required this.capacidad,
    this.esTaller = false,
  });

  final String nombre;
  final int capacidad;
  final bool esTaller;

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'capacidad': capacidad,
        'esTaller': esTaller,
      };
}

/// Cambios de un espacio. Sólo se envía lo que cambia.
///
/// El esquema del backend es `.strict()`: manda un campo que no reconoce y
/// devuelve `400`. Y omitir un campo **no** es lo mismo que mandarlo `null`: lo
/// omitido se queda como estaba, lo nulo se escribe.
class CambiosAula {
  const CambiosAula({this.nombre, this.capacidad, this.esTaller, this.activa});

  final String? nombre;
  final int? capacidad;
  final bool? esTaller;
  final bool? activa;

  bool get vacio =>
      nombre == null && capacidad == null && esTaller == null && activa == null;

  Map<String, dynamic> toJson() => {
        if (nombre != null) 'nombre': nombre,
        if (capacidad != null) 'capacidad': capacidad,
        if (esTaller != null) 'esTaller': esTaller,
        if (activa != null) 'activa': activa,
      };
}

// -----------------------------------------------------------------------------
//  Períodos
// -----------------------------------------------------------------------------

/// Cuerpo de `POST /api/v1/admin/periodos`.
///
/// Las fechas son opcionales **a propósito**: el centro no ha cargado las del
/// lapso en curso, e inventarlas sería fabricar un dato institucional (R-17).
class EntradaCrearPeriodo {
  const EntradaCrearPeriodo({
    required this.codigo,
    this.nombre,
    this.fechaInicio,
    this.fechaFin,
  });

  final String codigo;
  final String? nombre;

  /// ISO `YYYY-MM-DD`. Nunca un `DateTime`: un ISO completo desplaza un día por
  /// zona horaria.
  final String? fechaInicio;
  final String? fechaFin;

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        if (nombre != null) 'nombre': nombre,
        if (fechaInicio != null) 'fechaInicio': fechaInicio,
        if (fechaFin != null) 'fechaFin': fechaFin,
      };
}

/// Cambios de un lapso. **No incluye el vigente**: eso es [marcarVigente].
class CambiosPeriodo {
  const CambiosPeriodo({
    this.nombre,
    this.fechaInicio,
    this.fechaFin,
    this.activo,
    this.borrarFechas = false,
  });

  final String? nombre;
  final String? fechaInicio;
  final String? fechaFin;
  final bool? activo;

  /// Manda las fechas como `null`, que es como se borran.
  ///
  /// Hace falta un indicador explícito porque en este modelo «campo ausente» y
  /// «campo nulo» significan cosas distintas: ausente es «no lo toques» y nulo
  /// es «bórralo». Sin él no habría forma de deshacer una fecha mal cargada.
  final bool borrarFechas;

  bool get vacio =>
      nombre == null &&
      fechaInicio == null &&
      fechaFin == null &&
      activo == null &&
      !borrarFechas;

  Map<String, dynamic> toJson() => {
        if (nombre != null) 'nombre': nombre,
        if (borrarFechas) ...{'fechaInicio': null, 'fechaFin': null},
        if (!borrarFechas && fechaInicio != null) 'fechaInicio': fechaInicio,
        if (!borrarFechas && fechaFin != null) 'fechaFin': fechaFin,
        if (activo != null) 'activo': activo,
      };
}

// -----------------------------------------------------------------------------
//  Guardias
// -----------------------------------------------------------------------------

/// Cuerpo de `POST /api/v1/admin/guardias`.
///
/// `periodo` es obligatorio y no es un formalismo (R-15): sin él, una guardia
/// del lunes a primera hora chocaría con las clases de **cualquier** lapso —el
/// pasado, el vigente y el que se está planificando—.
///
/// **`turno` no se manda.** Es derivado del bloque y el esquema lo rechaza con
/// `400` en vez de ignorarlo.
class EntradaCrearGuardia {
  const EntradaCrearGuardia({
    required this.docenteId,
    required this.aulaId,
    required this.periodo,
    required this.dia,
    required this.bloque,
    this.notas,
  });

  final String docenteId;
  final String aulaId;
  final String periodo;
  final int dia;
  final int bloque;
  final String? notas;

  Map<String, dynamic> toJson() => {
        'docenteId': docenteId,
        'aulaId': aulaId,
        'periodo': periodo,
        'dia': dia,
        'bloque': bloque,
        if (notas != null) 'notas': notas,
      };
}

/// Cambios de una guardia. Cambiar `dia` o `bloque` es un **traslado**.
class CambiosGuardia {
  const CambiosGuardia({
    this.docenteId,
    this.aulaId,
    this.periodo,
    this.dia,
    this.bloque,
    this.notas,
    this.borrarNotas = false,
    this.activa,
  });

  final String? docenteId;
  final String? aulaId;
  final String? periodo;
  final int? dia;
  final int? bloque;
  final String? notas;

  /// Manda `notas` como `null`, que es como se borran. Ver [CambiosPeriodo].
  final bool borrarNotas;

  final bool? activa;

  bool get vacio =>
      docenteId == null &&
      aulaId == null &&
      periodo == null &&
      dia == null &&
      bloque == null &&
      notas == null &&
      !borrarNotas &&
      activa == null;

  Map<String, dynamic> toJson() => {
        if (docenteId != null) 'docenteId': docenteId,
        if (aulaId != null) 'aulaId': aulaId,
        if (periodo != null) 'periodo': periodo,
        if (dia != null) 'dia': dia,
        if (bloque != null) 'bloque': bloque,
        if (borrarNotas) 'notas': null,
        if (!borrarNotas && notas != null) 'notas': notas,
        if (activa != null) 'activa': activa,
      };
}

// -----------------------------------------------------------------------------
//  Cuadrante
// -----------------------------------------------------------------------------

/// Cuerpo de `POST /api/v1/admin/cuadrante`.
///
/// **El período no se manda: se deriva de la sección** (`sections.period_code`).
/// Aceptarlo del cliente abriría la puerta a una fila cuya sección pertenece al
/// lapso `2026-1` mientras la rejilla se dibuja en el `2026-2`, y el chequeo de
/// colisiones compararía peras con manzanas. **`turno` tampoco**: es derivado.
class EntradaCrearClase {
  const EntradaCrearClase({
    required this.seccionId,
    required this.docenteId,
    required this.aulaId,
    required this.dia,
    required this.bloque,
  });

  final String seccionId;
  final String docenteId;
  final String aulaId;
  final int dia;
  final int bloque;

  Map<String, dynamic> toJson() => {
        'seccionId': seccionId,
        'docenteId': docenteId,
        'aulaId': aulaId,
        'dia': dia,
        'bloque': bloque,
      };
}

/// Cambios de una clase. Mover `dia` o `bloque` es un traslado.
class CambiosClase {
  const CambiosClase({
    this.docenteId,
    this.aulaId,
    this.dia,
    this.bloque,
    this.activa,
  });

  final String? docenteId;
  final String? aulaId;
  final int? dia;
  final int? bloque;
  final bool? activa;

  bool get vacio =>
      docenteId == null && aulaId == null && dia == null && bloque == null &&
      activa == null;

  Map<String, dynamic> toJson() => {
        if (docenteId != null) 'docenteId': docenteId,
        if (aulaId != null) 'aulaId': aulaId,
        if (dia != null) 'dia': dia,
        if (bloque != null) 'bloque': bloque,
        if (activa != null) 'activa': activa,
      };
}
