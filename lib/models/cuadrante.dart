/// Modelos del Módulo 3 — Cuadrante, Horarios, Aulas y Guardias Docentes.
///
/// **Convención de nombres, otra vez.** La base usa inglés (`classroom_id`,
/// `day_of_week`, `is_workshop`) y la API y Dart usan español (`aulaId`, `dia`,
/// `esTaller`). La traducción ocurre en **una sola capa** —`fromJson`, aquí— y no
/// repartida por las pantallas: confundir las dos capas ya costó dos fallos
/// falsos en el humo de M1, y en el de M3 volvió a aparecer leyendo la vista con
/// los nombres del dominio en vez de los de SQL.
library;

/// Turno del día.
///
/// Es un valor **derivado**, no una decisión: la base lo calcula con
/// `turno_de_bloque(block)` —bloques 1–6 son mañana y 7–12 tarde (R-16)— y la
/// columna es `generated always as (…) stored`. Por eso viaja **sólo de salida**:
/// mandarlo en un `POST`/`PATCH` es un `400 PETICION_INVALIDA` por `.strict()`, y
/// no un campo ignorado en silencio. Aceptar un turno que contradiga al bloque
/// sería aceptar una agenda que miente.
enum Turno {
  manana,
  tarde;

  String get etiqueta => switch (this) {
        Turno.manana => 'Mañana',
        Turno.tarde => 'Tarde',
      };

  /// Valor que usa el backend.
  String get valorApi => switch (this) {
        Turno.manana => 'MAÑANA',
        Turno.tarde => 'TARDE',
      };

  /// Interpreta el valor del backend, con el bloque como red de seguridad.
  ///
  /// El `bloque` es obligatorio a propósito: si el campo `turno` faltara —un
  /// dato corrupto, porque la columna es `not null`— se **deriva** del bloque en
  /// vez de caer a un turno fijo. Inventar «mañana» para un bloque 9 pintaría la
  /// rejilla con la clase en la franja equivocada, que es exactamente lo que R-16
  /// existe para impedir.
  static Turno desdeApi(String? crudo, {required int bloque}) =>
      switch (crudo) {
        'TARDE' => Turno.tarde,
        'MAÑANA' => Turno.manana,
        _ => turnoDeBloque(bloque),
      };
}

/// La frontera de turnos, en un solo sitio.
///
/// Los bloques 1–6 son mañana y 7–12 tarde. Está aquí y no en la base porque la
/// interfaz también la necesita —para agrupar la rejilla y para la red de
/// seguridad de [Turno.desdeApi]— y tenerla escrita dos veces es cómo se acaba
/// con una franja que cambia de sitio al cruzar el mediodía.
const int bloquesDeManana = 6;

/// Último día de la semana con actividad docente. 1 = lunes … 6 = sábado.
///
/// El domingo no existe en el cuadrante del centro: por eso la columna es
/// `check (day_of_week between 1 and 6)` y no 1–7.
const int diaMaximo = 6;

/// Último bloque del día. Doce bloques, seis por turno.
const int bloqueMaximo = 12;

/// Nombres de los días, indexados por el número que usa la base.
///
/// La posición 0 queda vacía a propósito: así `diasDeLaSemana[dia]` funciona con
/// el `dia` real sin restar uno en cada sitio, que es donde se cuelan los
/// desplazamientos de un día.
const List<String> diasDeLaSemana = [
  '',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

/// El turno que corresponde a un bloque, con la misma frontera que la base.
Turno turnoDeBloque(int bloque) =>
    bloque <= bloquesDeManana ? Turno.manana : Turno.tarde;

/// Nombre legible de un día, o `null` si el número se sale del rango.
///
/// Devuelve `null` en vez de «Día 9» porque un día fuera de rango no es un dato
/// raro que haya que enseñar: es un error, y la pantalla debe poder distinguirlo.
String? diaLegible(int dia) =>
    (dia >= 1 && dia <= diaMaximo) ? diasDeLaSemana[dia] : null;

/// Las tres formas que puede tener un espacio, **derivadas** de dos columnas.
///
/// No es una columna de la base: sale de cruzar `is_workshop` con `capacity`
/// (R-18). Existe como concepto de API porque el filtro de la pantalla de aulas
/// se elige entre estas tres, y decir «taller», «aula» o «zona» es más claro que
/// pedir al usuario que combine dos casillas.
///
/// Las tres son excluyentes y cubren todos los casos, así que el filtro nunca
/// deja un espacio fuera sin decirlo.
enum TipoAula {
  taller,
  aula,
  zona;

  String get etiqueta => switch (this) {
        TipoAula.taller => 'Taller',
        TipoAula.aula => 'Aula',
        TipoAula.zona => 'Zona',
      };

  String get valorApi => switch (this) {
        TipoAula.taller => 'TALLER',
        TipoAula.aula => 'AULA',
        TipoAula.zona => 'ZONA',
      };

  /// El tipo que corresponde a un espacio, según sus dos columnas.
  ///
  /// `esTaller` manda sobre la capacidad: un taller con cupo 0 sigue siendo un
  /// taller, porque lo que lo define es su uso, no su aforo.
  static TipoAula deAula({required bool esTaller, required int capacidad}) {
    if (esTaller) return TipoAula.taller;
    return capacidad > 0 ? TipoAula.aula : TipoAula.zona;
  }
}

/// Un espacio del centro: aula, taller o zona.
///
/// `capacidad` en 0 significa «sin cupo declarado» —una zona, un pasillo—, que
/// **no** es lo mismo que desconocido: por eso la columna es `not null default 0`
/// y aquí no es un `int?`.
class Aula {
  const Aula({
    required this.id,
    required this.nombre,
    required this.capacidad,
    required this.esTaller,
    required this.activa,
    this.creadoEn,
    this.actualizadoEn,
  });

  final String id;
  final String nombre;
  final int capacidad;
  final bool esTaller;
  final bool activa;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// La forma del espacio, derivada de sus dos columnas.
  TipoAula get tipo => TipoAula.deAula(esTaller: esTaller, capacidad: capacidad);

  factory Aula.fromJson(Map<String, dynamic> json) {
    return Aula(
      id: json['id'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      capacidad: json['capacidad'] as int? ?? 0,
      esTaller: json['esTaller'] as bool? ?? false,
      activa: json['activa'] as bool? ?? false,
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      actualizadoEn: DateTime.tryParse(json['actualizadoEn']?.toString() ?? ''),
    );
  }

  @override
  String toString() => 'Aula($nombre, ${tipo.etiqueta})';
}

/// Una página del catálogo de espacios.
class PaginaAulas {
  const PaginaAulas({
    required this.aulas,
    required this.total,
    this.limite = 25,
    this.desplazamiento = 0,
  });

  final List<Aula> aulas;
  final int total;

  /// Eco de la paginación: la pantalla pinta «1 a 25 de 9» con él, sin conservar
  /// su propia copia de lo que pidió.
  final int limite;
  final int desplazamiento;

  bool get vacia => aulas.isEmpty;

  factory PaginaAulas.fromJson(Map<String, dynamic> json) {
    return PaginaAulas(
      aulas: (json['aulas'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Aula.fromJson)
          .toList(),
      total: json['total'] as int? ?? 0,
      limite: json['limite'] as int? ?? 25,
      desplazamiento: json['desplazamiento'] as int? ?? 0,
    );
  }
}

/// Un lapso académico.
///
/// `activo` y `vigente` **no son lo mismo** y por eso son dos campos (R-19):
/// `activo` es «este lapso está abierto, se puede planificar en él», y `vigente`
/// es «este es el que el sistema considera en curso»
/// (`system_settings.periodo_activo`). Puede haber varios abiertos y sólo uno
/// vigente, y ése es el caso real: al cerrar un lapso se prepara el siguiente
/// mientras el vigente sigue dictándose.
///
/// Las fechas son **anulables a propósito**: el centro no las ha cargado e
/// inventarlas sería fabricar dato institucional (R-17). La pantalla debe decir
/// «sin fechas cargadas», no un rango inventado.
class Periodo {
  const Periodo({
    required this.id,
    required this.codigo,
    this.nombre,
    this.fechaInicio,
    this.fechaFin,
    required this.activo,
    required this.vigente,
    this.creadoEn,
    this.actualizadoEn,
  });

  final String id;
  final String codigo;
  final String? nombre;

  /// Fechas en ISO `YYYY-MM-DD`, tal y como viajan. Se guardan como texto y no
  /// como `DateTime` porque convertirlas a `DateTime` las desplaza un día por
  /// zona horaria al ir y volver.
  final String? fechaInicio;
  final String? fechaFin;

  final bool activo;
  final bool vigente;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  /// Lo que se enseña cuando el lapso no tiene nombre propio.
  String get etiqueta => (nombre?.trim().isNotEmpty ?? false) ? nombre! : codigo;

  /// ¿Tiene fechas cargadas? Si no, la pantalla dice «sin fechas cargadas».
  bool get tieneFechas => fechaInicio != null || fechaFin != null;

  factory Periodo.fromJson(Map<String, dynamic> json) {
    return Periodo(
      id: json['id'] as String? ?? '',
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String?,
      fechaInicio: json['fechaInicio'] as String?,
      fechaFin: json['fechaFin'] as String?,
      activo: json['activo'] as bool? ?? false,
      vigente: json['vigente'] as bool? ?? false,
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      actualizadoEn: DateTime.tryParse(json['actualizadoEn']?.toString() ?? ''),
    );
  }

  @override
  String toString() => 'Periodo($codigo${vigente ? ', vigente' : ''})';
}

/// Una guardia de custodia.
///
/// Es una **presencia**, no una clase: dice quién cubre qué espacio, qué día y
/// qué bloque, **independientemente de que haya clase**. Por eso es su propia
/// tabla y no un tipo de `schedule_slots`.
///
/// `periodo` es obligatorio: sin él, una guardia del lunes a primera hora
/// chocaría con las clases de cualquier lapso, incluido uno futuro que todavía
/// no ha empezado (R-15).
class Guardia {
  const Guardia({
    required this.id,
    required this.docenteId,
    required this.aulaId,
    required this.periodo,
    required this.dia,
    required this.bloque,
    required this.turno,
    this.notas,
    required this.activa,
    this.creadoEn,
    this.actualizadoEn,
  });

  final String id;
  final String docenteId;
  final String aulaId;
  final String periodo;
  final int dia;
  final int bloque;
  final Turno turno;
  final String? notas;
  final bool activa;
  final DateTime? creadoEn;
  final DateTime? actualizadoEn;

  factory Guardia.fromJson(Map<String, dynamic> json) {
    final bloque = json['bloque'] as int? ?? 0;
    return Guardia(
      id: json['id'] as String? ?? '',
      docenteId: json['docenteId'] as String? ?? '',
      aulaId: json['aulaId'] as String? ?? '',
      periodo: json['periodo'] as String? ?? '',
      dia: json['dia'] as int? ?? 0,
      bloque: bloque,
      turno: Turno.desdeApi(json['turno'] as String?, bloque: bloque),
      notas: json['notas'] as String?,
      activa: json['activa'] as bool? ?? false,
      creadoEn: DateTime.tryParse(json['creadoEn']?.toString() ?? ''),
      actualizadoEn: DateTime.tryParse(json['actualizadoEn']?.toString() ?? ''),
    );
  }

  @override
  String toString() => 'Guardia(${diaLegible(dia)}, bloque $bloque)';
}

/// Una página del listado de guardias.
class PaginaGuardias {
  const PaginaGuardias({
    required this.guardias,
    required this.total,
    this.limite = 25,
    this.desplazamiento = 0,
  });

  final List<Guardia> guardias;
  final int total;
  final int limite;
  final int desplazamiento;

  bool get vacia => guardias.isEmpty;

  factory PaginaGuardias.fromJson(Map<String, dynamic> json) {
    return PaginaGuardias(
      guardias: (json['guardias'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Guardia.fromJson)
          .toList(),
      total: json['total'] as int? ?? 0,
      limite: json['limite'] as int? ?? 25,
      desplazamiento: json['desplazamiento'] as int? ?? 0,
    );
  }
}

/// Una clase del cuadrante: sección + docente + aula + día/bloque.
///
/// Los cinco campos de la tabla son `seccionId`, `docenteId`, `aulaId`, `dia` y
/// `bloque`. **El período no viaja en la tabla**: se deriva de la sección, y
/// duplicarlo aquí crearía una segunda fuente de verdad que puede desviarse.
///
/// El resto lo aporta la vista `v_cuadrante_clases`, que ya resuelve los
/// nombres. Los nombres de las columnas de la vista son los de SQL
/// (`subject_name`, `section_name`, `classroom_name`, `teacher_name`) y **no** los
/// del dominio: leerlos con el nombre del dominio devuelve `null` en silencio, y
/// eso ya pasó una vez al escribir el humo de M3.
class ClaseCuadrante {
  const ClaseCuadrante({
    required this.id,
    required this.seccionId,
    required this.docenteId,
    required this.aulaId,
    required this.dia,
    required this.bloque,
    required this.turno,
    required this.activa,
    required this.periodo,
    required this.programaId,
    required this.programa,
    required this.materiaId,
    required this.materia,
    required this.seccion,
    required this.aula,
    required this.docente,
  });

  final String id;
  final String seccionId;
  final String docenteId;
  final String aulaId;
  final int dia;
  final int bloque;
  final Turno turno;
  final bool activa;

  // --- resuelto por `v_cuadrante_clases` ---
  final String periodo;
  final String programaId;
  final String programa;
  final String materiaId;
  final String materia;
  final String seccion;
  final String aula;

  /// Nombre del docente, vía `nombre_para_mostrar()`.
  ///
  /// Puede ser `null`-equivalente (cadena vacía) por **R-21**: el canal de
  /// invitación nunca captura `nombres`/`apellidos`, así que la función devuelve
  /// NULL. La interfaz debe decir «Docente sin nombre» en ese caso en vez de
  /// dejar un hueco mudo.
  final String docente;

  /// ¿La vista no pudo resolver el nombre del docente? Ver R-21.
  bool get docenteSinNombre => docente.trim().isEmpty;

  factory ClaseCuadrante.fromJson(Map<String, dynamic> json) {
    final bloque = json['bloque'] as int? ?? 0;
    return ClaseCuadrante(
      id: json['id'] as String? ?? '',
      seccionId: json['seccionId'] as String? ?? '',
      docenteId: json['docenteId'] as String? ?? '',
      aulaId: json['aulaId'] as String? ?? '',
      dia: json['dia'] as int? ?? 0,
      bloque: bloque,
      turno: Turno.desdeApi(json['turno'] as String?, bloque: bloque),
      activa: json['activa'] as bool? ?? false,
      periodo: json['periodo'] as String? ?? '',
      programaId: json['programaId'] as String? ?? '',
      programa: json['programa'] as String? ?? '',
      materiaId: json['materiaId'] as String? ?? '',
      materia: json['materia'] as String? ?? '',
      seccion: json['seccion'] as String? ?? '',
      aula: json['aula'] as String? ?? '',
      docente: json['docente'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'ClaseCuadrante($materia, ${diaLegible(dia)}, bloque $bloque)';
}

/// Un docente, reducido a lo que la rejilla necesita para pintar una fila.
class DocenteResumen {
  const DocenteResumen({required this.id, required this.nombre});

  final String id;

  /// Nombre, o vacío si R-21 lo dejó sin resolver. Ver
  /// [ClaseCuadrante.docenteSinNombre].
  final String nombre;

  bool get sinNombre => nombre.trim().isEmpty;

  factory DocenteResumen.fromJson(Map<String, dynamic> json) {
    return DocenteResumen(
      id: json['id'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
    );
  }

  @override
  String toString() => 'DocenteResumen($nombre)';
}

/// La rejilla maestra de un lapso, completa en una sola respuesta.
///
/// **Las cuatro listas juntas, y no por comodidad.** La rejilla necesita pintar
/// las clases, las guardias, las columnas de aulas y las filas de docentes a la
/// vez: son las cuatro dimensiones de la misma rejilla. Con cuatro peticiones la
/// pantalla puede quedar a medio pintar mostrando una guardia junto a una clase
/// que ya no existe, y el administrador no sabría si eso es un choque real o una
/// pantalla desactualizada. Una sola respuesta es coherente por construcción.
class RejillaCuadrante {
  const RejillaCuadrante({
    this.periodo,
    this.clases = const [],
    this.guardias = const [],
    this.aulas = const [],
    this.docentes = const [],
  });

  /// `null` cuando no hay lapso vigente y no se pidió ninguno.
  ///
  /// En ese caso `clases` y `guardias` salen vacías pero **`aulas` y `docentes`
  /// siguen llenas**: la pantalla puede decir «no hay lapso vigente» en vez de
  /// aparecer en blanco, y el administrador ve que el catálogo sí tiene datos.
  final String? periodo;

  final List<ClaseCuadrante> clases;
  final List<Guardia> guardias;
  final List<Aula> aulas;
  final List<DocenteResumen> docentes;

  bool get sinPeriodo => periodo == null;

  /// Sin aulas no se puede armar el cuadrante: una clase sin aula no existe.
  /// La pantalla debe decirlo en vez de mostrar un desplegable vacío.
  bool get sinAulas => aulas.isEmpty;

  factory RejillaCuadrante.fromJson(Map<String, dynamic> json) {
    return RejillaCuadrante(
      periodo: json['periodo'] as String?,
      clases: (json['clases'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClaseCuadrante.fromJson)
          .toList(),
      guardias: (json['guardias'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Guardia.fromJson)
          .toList(),
      aulas: (json['aulas'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Aula.fromJson)
          .toList(),
      docentes: (json['docentes'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DocenteResumen.fromJson)
          .toList(),
    );
  }
}

/// El horario del llamante: docente o estudiante.
///
/// Una sola forma para los dos roles porque el aislamiento lo garantiza la RLS y
/// lo único que cambia es qué filas sobreviven al filtro. Un docente recibe sus
/// clases **y** sus guardias; un estudiante, las clases de las secciones en las
/// que está matriculado, y `guardias` **siempre vacío**.
class MiHorario {
  const MiHorario({
    required this.rol,
    this.periodo,
    this.clases = const [],
    this.guardias = const [],
  });

  final String rol;
  final String? periodo;
  final List<ClaseCuadrante> clases;
  final List<Guardia> guardias;

  bool get sinPeriodo => periodo == null;
  bool get vacio => clases.isEmpty && guardias.isEmpty;

  factory MiHorario.fromJson(Map<String, dynamic> json) {
    return MiHorario(
      rol: json['rol'] as String? ?? '',
      periodo: json['periodo'] as String?,
      clases: (json['clases'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClaseCuadrante.fromJson)
          .toList(),
      guardias: (json['guardias'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Guardia.fromJson)
          .toList(),
    );
  }
}
