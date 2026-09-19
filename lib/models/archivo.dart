/// Modelos del Módulo 5 — Archivos (Cloudflare R2).
///
/// Espejo Dart de `ArchivoMetadata` en el backend (`src/dominio/tipos.ts`). El
/// backend firma URLs y guarda el METADATO; el objeto pesado vive en R2 y el
/// cliente lo sube y lo baja directamente, así que este modelo es lo único que
/// la UI conoce del archivo: nunca la ruta del bucket.
///
/// Igual que en M4, un valor que no reconocemos es un **contrato roto**, no un
/// caso a tolerar: probablemente una migración añadió un estado nuevo y el
/// cliente no se enteró. Por eso `desde` lanza en vez de degradar a «otro».
library;

/// Estados del ciclo de vida de un archivo.
///
/// `PENDING` (fila reservada, objeto sin verificar) → `CONFIRMED` (el backend
/// comprobó con `HeadObject` que el objeto llegó y cuánto pesa) → `DELETED`
/// (borrado lógico: la fila se conserva como historial).
enum EstadoArchivo {
  pending('PENDING'),
  confirmed('CONFIRMED'),
  deleted('DELETED');

  const EstadoArchivo(this.valorRemoto);

  /// Valor tal como lo devuelve el backend (UPPERCASE).
  final String valorRemoto;

  static EstadoArchivo desde(String? valor) => switch (valor) {
        'PENDING' => pending,
        'CONFIRMED' => confirmed,
        'DELETED' => deleted,
        _ => throw FormatException('Estado de archivo desconocido: $valor'),
      };

  /// Sólo lo confirmado tiene un objeto verificado que se pueda descargar.
  /// Un `PENDING` no llegó (o nadie lo midió) y un `DELETED` ya no cuenta.
  bool get esLegible => this == confirmed;
}

/// A qué clase de entidad pertenece el archivo.
///
/// Es un valor cerrado y no una cadena libre porque el backend lo valida contra
/// un `CHECK` en la tabla: inventarse uno aquí daría un 400 en la primera llamada.
enum TipoEntidadArchivo {
  taskSubmission('TASK_SUBMISSION'),
  teacherGuide('TEACHER_GUIDE');

  const TipoEntidadArchivo(this.valorRemoto);

  final String valorRemoto;

  static TipoEntidadArchivo desde(String? valor) => switch (valor) {
        'TASK_SUBMISSION' => taskSubmission,
        'TEACHER_GUIDE' => teacherGuide,
        _ => throw FormatException('Tipo de entidad desconocido: $valor'),
      };
}

/// Metadatos de un archivo, tal como los devuelve la API.
class Archivo {
  const Archivo({
    required this.id,
    required this.propietarioId,
    required this.r2Key,
    required this.nombreOriginal,
    required this.tipoContenido,
    required this.tamanoBytes,
    required this.entityType,
    required this.entidadId,
    required this.estado,
    required this.creadoEn,
    this.confirmadoEn,
    this.borradoEn,
  });

  final String id;
  final String propietarioId;

  /// Clave del objeto en R2. La construye siempre el servidor. **No es una URL**
  /// y no debe usarse para armar una: para leer se pide una URL firmada.
  final String r2Key;

  /// Nombre legible que eligió el usuario, con acentos incluidos.
  final String nombreOriginal;

  /// Tipo MIME canónico, derivado de la extensión en el servidor.
  ///
  /// Es el que hay que enviar en el `PUT` a R2: la URL prefirmada firma el
  /// `Content-Type`, así que mandar otro hace que R2 rechace la subida.
  final String tipoContenido;

  /// `null` mientras está `PENDING`: una subida a medias no tiene tamaño.
  final int? tamanoBytes;

  final TipoEntidadArchivo entityType;

  /// Id de la tarea o guía concreta. `null` si la entidad aún no existe.
  final String? entidadId;

  final EstadoArchivo estado;
  final String creadoEn;
  final String? confirmadoEn;
  final String? borradoEn;

  factory Archivo.fromJson(Map<String, dynamic> json) => Archivo(
        id: json['id'] as String,
        propietarioId: json['propietarioId'] as String,
        r2Key: json['r2Key'] as String,
        nombreOriginal: json['nombreOriginal'] as String,
        tipoContenido: json['tipoContenido'] as String,
        tamanoBytes: (json['tamanoBytes'] as num?)?.toInt(),
        entityType: TipoEntidadArchivo.desde(json['entityType'] as String?),
        entidadId: json['entidadId'] as String?,
        estado: EstadoArchivo.desde(json['estado'] as String?),
        creadoEn: json['creadoEn'] as String,
        confirmadoEn: json['confirmadoEn'] as String?,
        borradoEn: json['borradoEn'] as String?,
      );

  @override
  String toString() => 'Archivo($id, $nombreOriginal, ${estado.valorRemoto})';
}

/// Respuesta de `POST /archivos/firmar-subida`.
///
/// Trae las tres cosas que hacen falta para subir: **el `id`** (lo único que
/// permite confirmar después), la URL prefirmada y el `Content-Type` que hay que
/// enviar. El `archivo` viene `PENDING` y sin tamaño.
class SubidaFirmada {
  const SubidaFirmada({
    required this.archivo,
    required this.urlDeSubida,
    required this.expiraEnSegundos,
  });

  final Archivo archivo;

  /// URL de R2 a la que se hace `PUT` **directamente**, sin pasar por el backend.
  final String urlDeSubida;

  final int expiraEnSegundos;

  factory SubidaFirmada.fromJson(Map<String, dynamic> json) => SubidaFirmada(
        archivo: Archivo.fromJson(json['archivo'] as Map<String, dynamic>),
        urlDeSubida: json['urlDeSubida'] as String,
        expiraEnSegundos: (json['expiraEnSegundos'] as num).toInt(),
      );
}

/// Respuesta de `GET /archivos/:id/url-lectura`.
class UrlDeLectura {
  const UrlDeLectura({
    required this.urlDeLectura,
    required this.expiraEnSegundos,
    required this.nombreOriginal,
  });

  final String urlDeLectura;
  final int expiraEnSegundos;
  final String nombreOriginal;

  factory UrlDeLectura.fromJson(Map<String, dynamic> json) => UrlDeLectura(
        urlDeLectura: json['urlDeLectura'] as String,
        expiraEnSegundos: (json['expiraEnSegundos'] as num).toInt(),
        nombreOriginal: json['nombreOriginal'] as String,
      );
}
