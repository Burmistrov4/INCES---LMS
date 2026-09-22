/// Modelos y contrato de la capa de datos del Módulo 6 (Aula Virtual).
///
/// Espejo Dart de las tablas `m6_anuncios`, `m6_tareas` y `m6_entregas`, y de
/// las vistas/RPC que las leen. La UI de la pestaña «Tablón» y de «Trabajo de
/// clase» se construye contra este puerto, igual que el gestor documental de M5
/// se construye contra `ArchivosGateway`.
///
/// ## Estado de la implementación (leer antes de tocar esto)
///
/// **El puerto está completo y es lo que la UI consume.** La implementación HTTP
/// del **contenido** de M6 —[AulaGateway.tablon], [AulaGateway.trabajoDeClase],
/// [AulaGateway.misEntregas], [AulaGateway.entregar] y [AulaGateway.reclamar]—
/// sigue **deliberadamente pendiente**: el backend de M6 se está escribiendo en
/// paralelo y la forma de sus `payloads` JSON todavía no está cerrada. Esos
/// cinco métodos viven hoy **sólo** en el doble
/// `test/support/fake_aula_gateway.dart`, que es lo que la UI usa para
/// desarrollarse y probarse.
///
/// La excepción es [AulasPropiasGateway.misAulas], que **sí** tiene
/// implementación real en `lib/services/aula_service.dart`: su contrato es
/// `GET /api/v1/mi-horario`, una ruta **congelada desde M3** y publicada en el
/// OpenAPI, así que ahí no hay nada que adivinar.
///
/// Escribir aquí un `fromJson` que adivine las claves de M6 produciría un fallo
/// **silencioso** —no un error—: la pantalla se vería vacía porque los campos no
/// se encuentran, y nada avisaría. Por eso los modelos de M6 **no** traen
/// `fromJson`: el parseo llega junto con el servicio, cuando las claves sean un
/// hecho y no una suposición. [MisAulas] es la excepción por la misma razón que
/// [AulasPropiasGateway]: se construye a partir de `MiHorario`, que ya sabe
/// parsearse a sí mismo.
///
/// Las implementaciones del puerto **lanzan** [AppException]; quien las envuelve
/// en `Result` es el consumidor (hoy las pantallas, vía `Result.guard`).
library;

/// Estado del ciclo de vida de un anuncio del tablón.
///
/// `BORRADOR` → `PUBLICADO` → `ELIMINADO`. La publicación programada no cambia
/// el estado: un `BORRADOR` con `programadoPara` vencido se lee como publicado
/// **en la política RLS**, sin ningún proceso que lo escriba (D-4).
enum EstadoAnuncio {
  borrador('BORRADOR'),
  publicado('PUBLICADO'),
  eliminado('ELIMINADO');

  const EstadoAnuncio(this.valorRemoto);

  /// Valor tal como lo devuelve el backend (UPPERCASE).
  final String valorRemoto;

  static EstadoAnuncio desde(String? valor) => switch (valor) {
        'BORRADOR' => borrador,
        'PUBLICADO' => publicado,
        'ELIMINADO' => eliminado,
        _ => throw FormatException('Estado de anuncio desconocido: $valor'),
      };
}

/// Estado del ciclo de vida de una tarea de clase.
///
/// Mismos tres valores que [EstadoAnuncio]; es un enum propio porque son dos
/// tablas distintas y unirlos acoplaría sus ciclos.
enum EstadoTarea {
  borrador('BORRADOR'),
  publicado('PUBLICADO'),
  eliminado('ELIMINADO');

  const EstadoTarea(this.valorRemoto);

  final String valorRemoto;

  static EstadoTarea desde(String? valor) => switch (valor) {
        'BORRADOR' => borrador,
        'PUBLICADO' => publicado,
        'ELIMINADO' => eliminado,
        _ => throw FormatException('Estado de tarea desconocido: $valor'),
      };
}

/// Qué clase de trabajo de clase es.
///
/// Reproduce el reparto de Google entre `CourseWork` y `CourseWorkMaterial`:
/// [material] es de lectura, **no se califica y no genera entregas** —el `CHECK`
/// de la tabla le prohíbe puntos y fecha límite—. [pregunta] es hoy un marcador:
/// el motor de preguntas es un ciclo propio (§7 del diseño).
enum TipoTarea {
  tarea('TAREA'),
  material('MATERIAL'),
  pregunta('PREGUNTA');

  const TipoTarea(this.valorRemoto);

  final String valorRemoto;

  static TipoTarea desde(String? valor) => switch (valor) {
        'TAREA' => tarea,
        'MATERIAL' => material,
        'PREGUNTA' => pregunta,
        _ => throw FormatException('Tipo de tarea desconocido: $valor'),
      };

  /// ¿Se califica y tiene fecha límite? Un material, no.
  bool get seCalifica => this != material;
}

/// Estado de la entrega de un estudiante para una tarea.
///
/// `ASIGNADA` (placeholder creado al publicar la tarea) → `ENTREGADA` → y luego
/// el docente `DEVUELVE` con la nota, o el estudiante `RECLAMA` (el
/// «des-entregar» de Google) para volver a editar.
enum EstadoEntrega {
  asignada('ASIGNADA'),
  entregada('ENTREGADA'),
  devuelta('DEVUELTA'),
  reclamada('RECLAMADA');

  const EstadoEntrega(this.valorRemoto);

  final String valorRemoto;

  static EstadoEntrega desde(String? valor) => switch (valor) {
        'ASIGNADA' => asignada,
        'ENTREGADA' => entregada,
        'DEVUELTA' => devuelta,
        'RECLAMADA' => reclamada,
        _ => throw FormatException('Estado de entrega desconocido: $valor'),
      };

  /// ¿El estudiante ya puede editar sus adjuntos? Sí cuando entregó o el
  /// docente se lo devolvió; no mientras está asignada o reclamada.
  bool get esEditable => this == entregada || this == reclamada;
}

/// Un anuncio del Tablón de una sección.
class Anuncio {
  const Anuncio({
    required this.id,
    required this.seccionId,
    required this.titulo,
    required this.cuerpo,
    required this.estado,
    this.programadoPara,
    this.publicadoEn,
  });

  final String id;
  final String seccionId;
  final String titulo;
  final String cuerpo;
  final EstadoAnuncio estado;

  /// Publicación diferida. `null` significa «se publica en cuanto el docente
  /// pulse publicar», no «sin fecha».
  final String? programadoPara;

  /// Cuándo se publicó. Es la clave de orden del feed; `null` mientras siga
  /// siendo borrador.
  final String? publicadoEn;
}

/// Una tarea (o material) del Trabajo de clase de una sección.
class TareaDeClase {
  const TareaDeClase({
    required this.id,
    required this.seccionId,
    required this.titulo,
    required this.descripcion,
    required this.tipo,
    required this.puntosMaximos,
    required this.orden,
    required this.estado,
    this.fechaLimite,
    this.tema,
  });

  final String id;
  final String seccionId;
  final String titulo;
  final String descripcion;
  final TipoTarea tipo;

  /// Escala 0–20 (D-5). **Un [TipoTarea.material] siempre trae 0**: la UI no debe
  /// pintarlo, porque un «0 pts» sobre material de lectura es una mentira.
  final double puntosMaximos;

  /// `null` es un caso real, no un dato que falte: un material no vence, y una
  /// tarea puede publicarse sin fecha límite.
  final String? fechaLimite;

  /// Agrupación por texto, no por tabla (§7).
  final String? tema;

  /// Orden manual dentro del tema. Se respeta el que da el servidor.
  final int orden;

  final EstadoTarea estado;
}

/// La entrega de **un estudiante** para una tarea.
///
/// ## Por qué este tipo no tiene `notaBorrador`
///
/// El backend esconde la nota en borrador con un `GRANT` por columna, no con
/// RLS (§3.2 del diseño): `select (…, nota_asignada, …)` sin `nota_borrador`.
/// La razón es de producto: el estudiante no debe ver su nota hasta que el
/// docente **devuelve** la entrega (D-6).
///
/// Un modelo Dart que cargara `notaBorrador` devolvería por la UI justo el dato
/// que la base se molesta en esconder. Por eso el campo **no existe aquí**, y no
/// debe añadirse «por comodidad» en un refactor: el único tipo con
/// `notaBorrador` es [LibroEntrega], que es del docente.
class Entrega {
  const Entrega({
    required this.id,
    required this.tareaId,
    required this.estudianteId,
    required this.estado,
    required this.esTardia,
    this.notaAsignada,
    this.entregadaEn,
  });

  /// Es el `entidad_id` de los archivos `TASK_SUBMISSION` que el estudiante
  /// sube desde el gestor documental (M5). Ese id es la unión que deja al
  /// docente ver la entrega (§3.3).
  final String id;

  final String tareaId;
  final String estudianteId;
  final EstadoEntrega estado;

  /// Se escribe **al entregar**, no con un job: `now() > fecha_limite` (§4.2).
  final bool esTardia;

  /// Visible al estudiante **sólo** en estado `DEVUELTA`; `null` antes.
  final double? notaAsignada;

  final String? entregadaEn;

  /// Copia con campos cambiados.
  ///
  /// Existe porque el doble de pruebas necesita producir la fila mutada tras
  /// `entregar`/`reclamar`, y copiar a mano los siete campos invita a olvidar
  /// uno. No es una utilidad de propósito general: sólo la usa el doble.
  Entrega copyWith({
    EstadoEntrega? estado,
    bool? esTardia,
    double? notaAsignada,
    String? entregadaEn,
  }) =>
      Entrega(
        id: id,
        tareaId: tareaId,
        estudianteId: estudianteId,
        estado: estado ?? this.estado,
        esTardia: esTardia ?? this.esTardia,
        notaAsignada: notaAsignada ?? this.notaAsignada,
        entregadaEn: entregadaEn ?? this.entregadaEn,
      );
}

/// Una fila del **libro de calificaciones del docente** para una tarea.
///
/// Es el único tipo que carga [notaBorrador], y es deliberado: el `GRANT` por
/// columna se la esconde a `authenticated`, así que la única forma de leerla es
/// la RPC `security definer` del docente (`m6_entregas_de_tarea`, §5). Un
/// `SELECT` normal devolvería la columna en blanco **sin dar error**, que es el
/// fallo silencioso que la RPC existe para evitar.
class LibroEntrega {
  const LibroEntrega({
    required this.estudianteId,
    required this.estado,
    required this.esTardia,
    required this.faltante,
    this.notaBorrador,
    this.notaAsignada,
  });

  final String estudianteId;
  final EstadoEntrega estado;
  final bool esTardia;

  /// Nota de trabajo del docente, aún no devuelta. **Sólo el docente la ve.**
  final double? notaBorrador;

  final double? notaAsignada;

  /// «No entregó y ya venció», **derivado al leer** (§4.3), no escrito: no se
  /// auto-imputa un 0 en nombre de un docente que no lo pidió.
  final bool faltante;
}

/// Una de las aulas del llamante, reducida a lo que el menú necesita.
///
/// **Es una vista reducida de `ClaseCuadrante`, no una tabla.** `/mi-horario`
/// devuelve una fila por franja del cuadrante, así que la misma sección aparece
/// tantas veces como días y bloques tenga; aquí sobrevive **una**: el aula es la
/// sección, no la hora a la que se dicta.
class AulaResumen {
  const AulaResumen({
    required this.seccionId,
    required this.materia,
    required this.seccion,
    this.programa,
  });

  /// La sección de M3. Es lo que se le pasa a [AulaGateway.tablon] y
  /// [AulaGateway.trabajoDeClase] al abrir el aula.
  final String seccionId;

  final String materia;
  final String seccion;

  /// El programa, si la vista `v_cuadrante_clases` lo resolvió. Nulo es un caso
  /// real —una sección sin programa cargado—, no un dato que falte.
  final String? programa;

  /// Lo que se enseña: «Materia · Sección · Programa».
  ///
  /// Se compone aquí y no en la pantalla para que el listado y el título del
  /// aula digan **exactamente** lo mismo; dos composiciones distintas del mismo
  /// dato se desvían en cuanto alguien ajusta una.
  ///
  /// El programa se omite cuando viene vacío en vez de dejar un separador
  /// colgando, y si no hay materia cae a la sección: una fila a la que le falte
  /// un nombre no debe quedar en blanco.
  String get etiqueta {
    final programaLimpio = programa?.trim() ?? '';
    final partes = <String>[
      if (materia.trim().isNotEmpty) materia.trim(),
      if (seccion.trim().isNotEmpty) seccion.trim(),
      if (programaLimpio.isNotEmpty) programaLimpio,
    ];

    return partes.isEmpty ? 'Sección sin nombre' : partes.join(' · ');
  }

  @override
  String toString() => 'AulaResumen($seccionId, $etiqueta)';
}

/// El listado «mis aulas» del llamante: qué secciones tiene y con qué rol.
///
/// Es el resultado de [AulasPropiasGateway.misAulas]. Trae el rol **derivado del
/// servidor** y no una bandera que ponga el cliente: quien sabe si alguien es
/// docente es el backend (`/mi-horario` responde `rol`), y repetir esa decisión
/// en la UI sería una segunda fuente de verdad sobre permisos (ADR-003).
class MisAulas {
  const MisAulas({
    required this.esDocente,
    this.periodo,
    this.aulas = const [],
  });

  /// `rol == 'docente'` en el payload. Sólo decide **presentación** (qué pestaña
  /// y qué acciones se pintan); la autorización la hace la RLS.
  final bool esDocente;

  /// El lapso del horario, o `null` si el centro no tiene uno vigente.
  final String? periodo;

  /// Una entrada por sección, en el orden en que aparecen en `clases`.
  final List<AulaResumen> aulas;

  bool get vacio => aulas.isEmpty;

  @override
  String toString() =>
      'MisAulas(esDocente: $esDocente, ${aulas.length} aula(s))';
}

/// Lo que **hoy** se puede pedir de verdad sobre las aulas de una persona.
///
/// Es un puerto **más estrecho** que [AulaGateway] y vive aquí, junto a él, por
/// una razón concreta: `GET /api/v1/mi-horario` es una ruta **congelada** —está
/// en el OpenAPI y sirve al panel «Mi horario» desde M3— mientras que los
/// `payloads` del contenido de M6 todavía no están cerrados.
///
/// Un solo puerto con las dos cosas obligaría a que su implementación HTTP
/// declarara los cinco métodos de M6 sin poder implementarlos, y una clase de
/// producción cuyos métodos revientan es una trampa para el siguiente que la
/// cablee. Separando, `lib/services/aula_service.dart` implementa **sólo** lo que
/// existe, y los métodos de M6 siguen viviendo únicamente en el doble.
abstract interface class AulasPropiasGateway {
  /// Las secciones del llamante, una por aula.
  ///
  /// Se apoya en `/mi-horario` y **no** en `/mis-inscripciones`: esa segunda
  /// ruta es sólo del estudiante y trae el estado de matrícula, mientras que
  /// `/mi-horario` responde para los dos roles con la misma forma.
  ///
  /// **Las guardias no salen de aquí.** Una guardia es una presencia de
  /// custodia, no una clase con tablón ni trabajo de clase: el listado se arma
  /// con `clases` y `guardias` se ignora, aunque venga en el payload.
  ///
  /// `periodo` es opcional; sin él, el backend responde con el lapso vigente.
  Future<MisAulas> misAulas({String? periodo});
}

/// Contrato de la capa de datos del Aula Virtual (M6).
///
/// Refleja las rutas HTTP de §6 del diseño, con la salvedad de que el puerto
/// expone **sólo** las que la UI del aula necesita hoy:
///
/// | Método | Ruta |
/// |---|---|
/// | [misAulas] | `GET /api/v1/mi-horario` (heredada de [AulasPropiasGateway]) |
/// | [tablon] | `GET /aula/secciones/:seccionId/tablon` |
/// | [trabajoDeClase] | `GET /aula/secciones/:seccionId/trabajo` |
/// | [misEntregas] | `GET /aula/mis-entregas` |
/// | [entregar] | `POST /aula/entregas/:entregaId/entregar` |
/// | [reclamar] | RPC `m6_reclamar_entrega` (sin ruta propia en §6) |
///
/// Las rutas de escritura del docente (crear anuncio/tarea, publicar,
/// calificar, devolver, libro de calificaciones) **no** están en el puerto
/// todavía: su UI es un ciclo aparte y el contrato de su payload aún no está
/// cerrado. Añadirlas sin esa UI daría métodos sin consumidor.
///
/// Hereda de [AulasPropiasGateway] porque el aula se abre **desde** el listado
/// de aulas: quien tiene la puerta del contenido tiene, por construcción, la del
/// listado. La implementación real de hoy (`BackendAulaGateway`) cubre sólo la
/// parte congelada, y por eso declara [AulasPropiasGateway] y no este puerto.
abstract interface class AulaGateway implements AulasPropiasGateway {
  /// El feed del tablón de una sección.
  ///
  /// **Devuelve lo que la RLS deja ver** (§3.1): el docente ve borradores y
  /// programados; el estudiante, sólo lo publicado o lo programado ya vencido.
  /// No hay filtro por rol aquí a propósito: sería una segunda copia de una
  /// regla que ya vive en la base (ADR-003).
  ///
  /// El orden lo fija el servidor (más reciente primero). La UI **no re-ordena**:
  /// un segundo criterio de orden es una segunda fuente de verdad que se
  /// desvía de la del feed.
  Future<List<Anuncio>> tablon(String seccionId);

  /// Las tareas y materiales de una sección, en el orden del servidor.
  Future<List<TareaDeClase>> trabajoDeClase(String seccionId);

  /// Las entregas del estudiante autenticado, de todas sus secciones.
  ///
  /// Se cruzan por `tareaId` con [trabajoDeClase] para pintar el estado de cada
  /// tarea. No lleva parámetro: el «yo» lo pone `auth.uid()` en el servidor.
  Future<List<Entrega>> misEntregas();

  /// Marca la entrega como entregada (y escribe `esTardia`).
  ///
  /// Falla con error de negocio si venció y la tarea no admite entrega tardía
  /// (§4.4); no es un `CHECK`, porque depende del reloj.
  Future<Entrega> entregar(String entregaId);

  /// Des-hace la entrega para poder volver a editar (el «des-entregar»).
  Future<Entrega> reclamar(String entregaId);
}
