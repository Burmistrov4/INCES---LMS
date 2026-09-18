/// Estados de una inscripción en el Módulo 4 (Inscripciones y Cupos).
///
/// El ciclo es: `WAITLISTED` (en cola) → `PENDING_BID` (se le ofreció un asiento,
/// con vencimiento) → `ENROLLED` (dentro) → `DROPPED` (fuera, pero la fila se
/// conserva como historial). `DROPPED` no es un borrado.
enum EstadoInscripcion {
  enrolled('ENROLLED'),
  waitlisted('WAITLISTED'),
  pendingBid('PENDING_BID'),
  dropped('DROPPED');

  const EstadoInscripcion(this.valorRemoto);

  /// Valor tal como lo devuelve el backend (UPPERCASE).
  final String valorRemoto;

  /// Convierte el valor del backend al enum, fallando si es desconocido.
  ///
  /// Igual que el backend, un estado que no reconocemos es un contrato roto:
  /// probablemente una migración añadió uno nuevo y el cliente no se enteró.
  static EstadoInscripcion desde(String? valor) => switch (valor) {
        'ENROLLED' => enrolled,
        'WAITLISTED' => waitlisted,
        'PENDING_BID' => pendingBid,
        'DROPPED' => dropped,
        _ => throw FormatException('Estado de inscripción desconocido: $valor'),
      };

  /// ¿Hay una oferta de cupo en el aire esperando aceptación?
  bool get esOfertaViva => this == pendingBid;

  /// ¿Sigue en la cola de espera (sin asiento aún)?
  bool get enCola => this == waitlisted;

  /// ¿Está matriculado con asiento confirmado?
  bool get estaAdentro => this == enrolled;
}

/// Ocupación de una sección, con nombres ya resueltos.
///
/// Sale de `v_ocupacion_secciones`. La usa tanto el catálogo de ofertas del
/// estudiante como el panel de ocupación del administrador. `cuposDisponibles`
/// puede ser > 0 aunque `ofertaVigente` sea `true`: por eso la UI debe usar
/// `ofertaVigente` para decidir si ofrece el asiento, no el contador.
class OcupacionSeccion {
  final String seccionId;
  final String periodo;
  final String programaId;
  final String? programaNombre;
  final String materiaId;
  final String? materiaNombre;
  final String nombre;
  final bool activa;
  final int cupoEfectivo;
  final int cuposOcupados;
  final int cuposDisponibles;
  final bool ofertaVigente;

  const OcupacionSeccion({
    required this.seccionId,
    required this.periodo,
    required this.programaId,
    this.programaNombre,
    required this.materiaId,
    this.materiaNombre,
    required this.nombre,
    required this.activa,
    required this.cupoEfectivo,
    required this.cuposOcupados,
    required this.cuposDisponibles,
    required this.ofertaVigente,
  });

  factory OcupacionSeccion.fromJson(Map<String, dynamic> json) => OcupacionSeccion(
        seccionId: json['seccionId'] as String,
        periodo: json['periodo'] as String,
        programaId: json['programaId'] as String,
        programaNombre: json['programaNombre'] as String?,
        materiaId: json['materiaId'] as String,
        materiaNombre: json['materiaNombre'] as String?,
        nombre: json['nombre'] as String,
        activa: json['activa'] as bool? ?? false,
        cupoEfectivo: json['cupoEfectivo'] as int? ?? 0,
        cuposOcupados: json['cuposOcupados'] as int? ?? 0,
        cuposDisponibles: json['cuposDisponibles'] as int? ?? 0,
        ofertaVigente: json['ofertaVigente'] as bool? ?? false,
      );

  /// Etiqueta corta del estado de cupo para la lista («3/5» o «3/—»).
  String get resumenCupo =>
      '$cuposOcupados/${cupoEfectivo == 0 ? '—' : cupoEfectivo}';
}

/// Una inscripción con el contexto que la pantalla necesita.
///
/// Se aplana la sección en vez de anidarla porque las pantallas pintan los
/// mismos campos (mis inscripciones, cola del administrador).
class InscripcionDetallada {
  final String id;
  final String estudianteId;
  final String seccionId;
  final EstadoInscripcion estado;
  final String? ofertaVenceEn;
  final String periodo;
  final String seccionNombre;
  final String materiaId;
  final String? materiaNombre;
  final String programaId;
  final String? programaNombre;
  final int? posicionEnCola;
  final String? estudianteNombre;
  final String? estudianteEmail;

  const InscripcionDetallada({
    required this.id,
    required this.estudianteId,
    required this.seccionId,
    required this.estado,
    this.ofertaVenceEn,
    required this.periodo,
    required this.seccionNombre,
    required this.materiaId,
    this.materiaNombre,
    required this.programaId,
    this.programaNombre,
    this.posicionEnCola,
    this.estudianteNombre,
    this.estudianteEmail,
  });

  factory InscripcionDetallada.fromJson(Map<String, dynamic> json) =>
      InscripcionDetallada(
        id: json['id'] as String,
        estudianteId: json['estudianteId'] as String,
        seccionId: json['seccionId'] as String,
        estado: EstadoInscripcion.desde(json['estado'] as String?),
        ofertaVenceEn: json['ofertaVenceEn'] as String?,
        periodo: json['periodo'] as String,
        seccionNombre: json['seccionNombre'] as String,
        materiaId: json['materiaId'] as String,
        materiaNombre: json['materiaNombre'] as String?,
        programaId: json['programaId'] as String,
        programaNombre: json['programaNombre'] as String?,
        posicionEnCola: json['posicionEnCola'] as int?,
        estudianteNombre: json['estudianteNombre'] as String?,
        estudianteEmail: json['estudianteEmail'] as String?,
      );
}
