/// Modelos y contrato de la capa de datos del Módulo 6 (Aula Virtual).
///
/// Espejo Dart de las tablas `m6_anuncios`, `m6_tareas` y `m6_entregas`, y de
/// las vistas/RPC que las leen. La UI de la pestaña «Tablón» y de «Trabajo de
/// clase» se construye contra este puerto, igual que el gestor documental de M5
/// se construye contra `ArchivosGateway`.
///
/// ## De dónde sale la forma del JSON (leer antes de tocar esto)
///
/// El contrato está **congelado**, y su fuente autoritativa es el backend en dos
/// piezas que hay que leer juntas:
///
/// 1. Las interfaces de `backend/src/dominio/tipos.ts` —`Anuncio`, `Tarea`,
///    `Entrega`, `LibroEntrega`—.
/// 2. Los mapeadores `a*` de `backend/src/infra/repos-supabase.ts`, que son los
///    que **de verdad** nombran las claves de la respuesta.
///
/// Hacen falta las dos porque **ninguna ruta declara un esquema Zod de
/// respuesta**: Fastify serializa el objeto del mapeador tal cual, así que la
/// interfaz sola no basta —hay campos de la interfaz que el mapeador no emite, y
/// viceversa—. Las diez rutas emiten **camelCase**.
///
/// Los `fromJson` de aquí se escriben contra esas claves y no contra una
/// suposición: uno que adivine la clave devuelve `null` en silencio y la
/// pantalla se ve vacía sin que nada avise. Ese es el fallo que la cabecera
/// anterior de este archivo existía para evitar, y por el que los modelos
/// nacieron **sin** `fromJson`: se añadieron cuando las claves dejaron de ser una
/// suposición y pasaron a ser un hecho.
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

  /// Parsea una fila del mapeador `aAnuncio`.
  ///
  /// `autorId` viene en el payload pero **no se lee aquí**: la UI no lo pinta y
  /// un campo que nadie consume es una invitación a que alguien lo use como
  /// fuente de verdad. Si hace falta, se añade con su consumidor.
  factory Anuncio.fromJson(Map<String, dynamic> json) => Anuncio(
        id: json['id'] as String,
        seccionId: json['seccionId'] as String,
        titulo: json['titulo'] as String,
        cuerpo: json['cuerpo'] as String,
        estado: EstadoAnuncio.desde(json['estado'] as String?),
        programadoPara: json['programadoPara'] as String?,
        publicadoEn: json['publicadoEn'] as String?,
      );
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

  /// Parsea una fila del mapeador `aTarea`.
  ///
  /// **`puntosMaximos` se lee como `num`, no como `int`.** La columna es
  /// `numeric(4,2)`, así que un 17,5 es válido; pero según cómo viaje —JSON de
  /// PostgREST, o un entero cuando vale 20— puede llegar como `int` o como
  /// `double`. Un `as double` sobre un `20` entero revienta en tiempo de
  /// ejecución; `(… as num?)?.toDouble()` acepta los dos. El `0` de respaldo
  /// repite el que ya usa el mapeador para un material.
  ///
  /// `permitirEntregaTardia` y `publicadoEn` vienen en el payload y no se leen:
  /// la UI no los pinta todavía.
  factory TareaDeClase.fromJson(Map<String, dynamic> json) => TareaDeClase(
        id: json['id'] as String,
        seccionId: json['seccionId'] as String,
        titulo: json['titulo'] as String,
        descripcion: json['descripcion'] as String,
        tipo: TipoTarea.desde(json['tipo'] as String?),
        puntosMaximos: (json['puntosMaximos'] as num?)?.toDouble() ?? 0,
        fechaLimite: json['fechaLimite'] as String?,
        tema: json['tema'] as String?,
        orden: (json['orden'] as num?)?.toInt() ?? 0,
        estado: EstadoTarea.desde(json['estado'] as String?),
      );
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
///
/// ## Por qué este tipo tampoco tiene `estudianteId`
///
/// Porque **el servidor no lo manda**. Esta forma es la del alumno: `aEntrega`
/// lee `id, tarea_id, estado, es_tardia, nota_asignada, entregada_en` —las
/// mismas seis columnas de `COLUMNAS_ENTREGA`—, y `estudiante_id` no está entre
/// ellas. Un campo `required` que ningún `payload` llena no es un dato que
/// falte: es un `null` disfrazado que revienta al parsear. El «yo» de la entrega
/// lo pone `auth.uid()` en el servidor, así que el cliente no necesita el id
/// para saber de quién es. [LibroEntrega] **sí** lo tiene, porque es el del
/// docente y ahí el `estudiante_id` es la fila.
class Entrega {
  const Entrega({
    required this.id,
    required this.tareaId,
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
  final EstadoEntrega estado;

  /// Se escribe **al entregar**, no con un job: `now() > fecha_limite` (§4.2).
  final bool esTardia;

  /// Visible al estudiante **sólo** en estado `DEVUELTA`; `null` antes.
  final double? notaAsignada;

  final String? entregadaEn;

  /// Parsea una fila del mapeador `aEntrega`.
  ///
  /// **`notaAsignada` se lee como `num`.** Es `numeric` en la base, así que un
  /// 17,5 es válido y un 20 puede llegar como entero; el `as num?` cubre los dos
  /// casos sin reventar.
  ///
  /// `esTardia` cae a `false` si faltara, que es el mismo respaldo que usa el
  /// mapeador: no marcar a nadie como tardío es más prudente que acusarlo sin
  /// dato.
  factory Entrega.fromJson(Map<String, dynamic> json) => Entrega(
        id: json['id'] as String,
        tareaId: json['tareaId'] as String,
        estado: EstadoEntrega.desde(json['estado'] as String?),
        esTardia: json['esTardia'] as bool? ?? false,
        notaAsignada: (json['notaAsignada'] as num?)?.toDouble(),
        entregadaEn: json['entregadaEn'] as String?,
      );

  /// Copia con campos cambiados.
  ///
  /// Existe porque el doble de pruebas necesita producir la fila mutada tras
  /// `entregar`/`reclamar`, y copiar a mano los campos invita a olvidar uno. No
  /// es una utilidad de propósito general: sólo la usa el doble.
  Entrega copyWith({
    EstadoEntrega? estado,
    bool? esTardia,
    double? notaAsignada,
    String? entregadaEn,
  }) =>
      Entrega(
        id: id,
        tareaId: tareaId,
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
    this.devueltaEn,
  });

  final String estudianteId;
  final EstadoEntrega estado;
  final bool esTardia;

  /// Nota de trabajo del docente, aún no devuelta. **Sólo el docente la ve.**
  final double? notaBorrador;

  final double? notaAsignada;

  /// Cuándo se devolvió la entrega al alumno. `null` mientras siga sin devolver.
  ///
  /// **Puede venir ausente, no sólo nula.** `JSON.stringify` borra las claves
  /// `undefined`, y la respuesta de `calificar` no toca `devuelta_en`, así que la
  /// clave no está. En Dart `json['devueltaEn']` devuelve `null` tanto si la
  /// clave falta como si vale `null`, y por eso el parseo no necesita
  /// distinguirlas: lo que **no** se puede hacer es dar por hecho que la clave
  /// existe y reventar con un `as String` no nulo.
  final String? devueltaEn;

  /// «No entregó y ya venció», **derivado al leer** (§4.3), no escrito: no se
  /// auto-imputa un 0 en nombre de un docente que no lo pidió.
  final bool faltante;

  /// Parsea una fila del mapeador `aLibroEntrega`.
  ///
  /// Este `fromJson` cubre también la respuesta de `calificar`/`devolver`, que
  /// es del mismo linaje: trae `notaBorrador` y `devueltaEn`, pero **no** trae
  /// `faltante` ni `entregadaEn`. Por eso los dos se leen con respaldo —
  /// `faltante` cae a `false`, que es lo que hace el mapeador— y no como
  /// obligatorios. Un `as bool` a secas haría que la respuesta de `calificar`
  /// reventara al parsear.
  ///
  /// `id` y `entregadaEn` vienen del libro de calificaciones y no se leen: la UI
  /// del docente todavía no los pinta.
  factory LibroEntrega.fromJson(Map<String, dynamic> json) => LibroEntrega(
        estudianteId: json['estudianteId'] as String,
        estado: EstadoEntrega.desde(json['estado'] as String?),
        esTardia: json['esTardia'] as bool? ?? false,
        notaBorrador: (json['notaBorrador'] as num?)?.toDouble(),
        notaAsignada: (json['notaAsignada'] as num?)?.toDouble(),
        devueltaEn: json['devueltaEn'] as String?,
        faltante: json['faltante'] as bool? ?? false,
      );
}

/// Lo que devuelve [AulaGateway.publicarTarea].
///
/// Es la **cabecera** de la tarea —estado y fecha de publicación— acoplada al
/// recuento de entregas creadas. Eso es todo lo que la RPC devuelve; completar
/// los demás campos aquí sería inventarlos. El recuento importa a la UI: es la
/// confirmación de que se creó un placeholder por estudiante matriculado.
class PublicacionTarea {
  const PublicacionTarea({
    required this.tareaId,
    required this.seccionId,
    required this.titulo,
    required this.estado,
    this.publicadoEn,
    required this.entregasCreadas,
  });

  final String tareaId;
  final String seccionId;
  final String titulo;
  final EstadoTarea estado;

  /// Cuándo se publicó. `null` no debería ocurrir en una publicación exitosa,
  /// pero se lee con respaldo para no reventar si la RPC lo omite.
  final String? publicadoEn;

  /// Cuántas entregas se crearon. 0 en una segunda publicación (idempotente),
  /// y eso es un 200 con la verdad, no un error.
  final int entregasCreadas;

  factory PublicacionTarea.fromJson(Map<String, dynamic> json) => PublicacionTarea(
        tareaId: json['id'] as String,
        seccionId: json['seccionId'] as String,
        titulo: json['titulo'] as String,
        estado: EstadoTarea.desde(json['estado'] as String?),
        publicadoEn: json['publicadoEn'] as String?,
        entregasCreadas: (json['entregasCreadas'] as num?)?.toInt() ?? 0,
      );
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

/// Lo que se puede saber de las aulas de una persona **sin abrir ninguna**.
///
/// Es un puerto **más estrecho** que [AulaGateway] y vive aquí, junto a él,
/// porque listar aulas y leer su contenido son dos cosas distintas: el listado se
/// apoya en `GET /api/v1/mi-horario` —una ruta de M3 que sirve también al panel
/// «Mi horario»— y no necesita saber nada del tablón ni de las entregas.
///
/// Un solo puerto obligaría a que cualquier implementación del listado declarara
/// los cinco métodos de contenido aunque no los tocara; separando, quien sólo
/// necesita listar aulas declara sólo esto. [AulaGateway] **hereda** de aquí
/// porque el aula se abre **desde** el listado: quien tiene la puerta del
/// contenido tiene, por construcción, la del listado.
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
/// Refleja las rutas HTTP de §6 del diseño:
///
/// | Método | Ruta |
/// |---|---|
/// | [misAulas] | `GET /api/v1/mi-horario` (heredada de [AulasPropiasGateway]) |
/// | [tablon] | `GET /aula/secciones/:seccionId/tablon` |
/// | [trabajoDeClase] | `GET /aula/secciones/:seccionId/trabajo` |
/// | [misEntregas] | `GET /aula/mis-entregas` |
/// | [entregar] | `POST /aula/entregas/:entregaId/entregar` |
/// | [reclamar] | `POST /aula/entregas/:entregaId/reclamar` |
/// | [crearAnuncio] | `POST /aula/secciones/:seccionId/anuncios` |
/// | [crearTarea] | `POST /aula/secciones/:seccionId/tareas` |
/// | [publicarTarea] | `POST /aula/tareas/:tareaId/publicar` |
/// | [libroDeCalificaciones] | `GET /aula/tareas/:tareaId/entregas` |
/// | [calificar] | `POST /aula/entregas/:entregaId/calificar` |
/// | [devolver] | `POST /aula/entregas/:entregaId/devolver` |
///
/// Las seis primeras son del ciclo del alumno; las seis últimas, del Centro de
/// Mando del docente. Ambas viven en el mismo puerto porque el Aula Virtual es
/// **una** pantalla con dos modos ([esDocente] sólo decide presentación; la
/// autorización la hace la RLS, ADR-003).
///
/// La implementación real es `BackendAulaGateway` (`lib/services/aula_service.dart`),
/// que cubre este puerto entero. El doble de pruebas
/// (`test/support/fake_aula_gateway.dart`) sigue valiendo para la UI, como el de
/// M5.
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

  // --- Centro de Mando del docente ------------------------------------------

  /// Crea un anuncio en el tablón de una sección.
  ///
  /// Nace `BORRADOR` (o programado, si [programadoPara] no es nulo) y lo
  /// publica quien tenga permiso sobre la sección —lo decide la RLS, no el
  /// cliente—. [cuerpo] es opcional (por defecto vacío); [programadoPara] es la
  /// publicación diferida, y `null` significa «publícalo ya».
  Future<Anuncio> crearAnuncio({
    required String seccionId,
    required String titulo,
    String? cuerpo,
    DateTime? programadoPara,
  });

  /// Crea una tarea o material del trabajo de clase.
  ///
  /// Nace `BORRADOR` y **sin entregas**: [publicarTarea] es lo que crea los
  /// placeholders, uno por matrícula. Un [TipoTarea.material] no se califica (no
  /// lleva puntos ni fecha límite), así que [puntosMaximos] y [fechaLimite] deben
  /// ir en `null` para él —la coherencia la refuerza la RPC, pero el cliente no
  /// debe ofrecer campos que el tipo prohíbe—. [orden] y [tema] agrupan dentro del
  /// tablero; [permitirEntregaTardia] rige la entrega fuera de plazo.
  Future<TareaDeClase> crearTarea({
    required String seccionId,
    required String titulo,
    String? descripcion,
    required TipoTarea tipo,
    double? puntosMaximos,
    DateTime? fechaLimite,
    bool permitirEntregaTardia = true,
    String? tema,
    int orden = 0,
  });

  /// Publica una tarea y crea los placeholders de entrega (uno por estudiante
  /// matriculado).
  ///
  /// Es **idempotente**: publicar dos veces no duplica entregas —el `unique
  /// (tarea_id, estudiante_id)` con `on conflict do nothing` lo garantiza en la
  /// base—, y por eso [PublicacionTarea.entregasCreadas] puede ser 0 en la segunda
  /// llamada sin que eso sea un error. Devuelve la **cabecera** de la tarea
  /// (estado y fecha de publicación) más el recuento; no la tarea entera.
  Future<PublicacionTarea> publicarTarea(String tareaId);

  /// El libro de calificaciones de una tarea: una fila por estudiante matriculado.
  ///
  /// Es la única lectura que trae [LibroEntrega.notaBorrador] —por eso va por la
  /// RPC `security definer` del docente y no por una lectura directa—, y por eso
  /// el tipo es [LibroEntrega] y no [Entrega]: el alumno no ve este dato.
  Future<List<LibroEntrega>> libroDeCalificaciones(String tareaId);

  /// Escribe la nota **borrador** de una entrega. El alumno aún no la ve; la copia
  /// a [LibroEntrega.notaAsignada] ocurre al [devolver]. Lanza si la entrega no
  /// está entregada o la nota se pasa de los puntos de la tarea (lo decide la
  /// RPC, con su mensaje).
  Future<LibroEntrega> calificar(String entregaId, double nota);

  /// Devuelve la entrega: copia el borrador a la nota asignada y cierra el ciclo.
  ///
  /// Es el **único** momento en que el alumno ve una nota. Devolver sin nota
  /// previa es legítimo —«devuelta sin calificar»—; lo que prohíbe el `CHECK` es
  /// una nota asignada sin borrador.
  Future<LibroEntrega> devolver(String entregaId);
}
