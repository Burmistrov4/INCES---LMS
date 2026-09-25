import 'dart:convert';

/// Las columnas de la exportación hacia HACER, **en el orden en que salen del
/// archivo**.
///
/// Es la misma lista y el mismo orden que `public.v_exportacion_hacer` declara
/// en `202609250004_v_exportacion_hacer.sql`. Está escrita aquí —y no derivada
/// de las claves de la primera fila— por un motivo concreto: **una sección sin
/// matriculados devuelve cero filas**, y un CSV sin cabecera no le sirve a nadie
/// que lo abra en HACER. Derivar la cabecera de los datos haría que el formato
/// del archivo dependiera de si hay datos, que es la clase de fragilidad que
/// este proyecto evita en todas partes.
///
/// **Es la capa que cambia cuando llegue la especificación de HACER.** Hoy no
/// existe: la auditoría de M4 midió que la palabra «HACER» sólo aparece en el
/// repositorio como comentario de consumidor futuro. Cuando la especificación
/// llegue, lo que se toca es esta lista, el `select` de la vista y nada más.
///
/// Las tres primeras columnas del bloque `planilla_` son el nombre desglosado
/// que la planilla física pide y que HACER quiere por separado: en `aspirantes`
/// los nombres viven concatenados (`nombres`, `apellidos`), así que las dos
/// formas viajan en el archivo.
const List<String> columnasExportacionHacer = <String>[
  // Contexto académico: a qué se inscribió.
  'inscripcion_id',
  'seccion_id',
  'lapso',
  'seccion',
  'seccion_activa',
  'programa_id',
  'programa_codigo',
  'programa_nombre',
  'materia_id',
  'materia_codigo',
  'materia_nombre',
  'docente',
  'estado',
  'inscrito_en',

  // Identidad: el contrato que `AspiranteModel` ya declara.
  'aspirante_id',
  'cedula',
  'nombres',
  'apellidos',
  'fecha_nac',
  'sexo',
  'telefono',
  'email',
  'direccion',
  'nivel_educativo',
  'discapacidad',
  'tipo_discapacidad',
  'numero_identidad_tutor',
  'nombre_tutor',
  'parentesco_tutor',
  'telefono_tutor',
  'correo_tutor',

  // Planilla aplanada: los 29 campos que sólo viven en `datos_planilla`.
  'planilla_numero_preimpreso',
  'planilla_primer_nombre',
  'planilla_segundo_nombre',
  'planilla_primer_apellido',
  'planilla_segundo_apellido',
  'planilla_nacionalidad',
  'planilla_estado_civil',
  'planilla_pueblo_indigena',
  'planilla_pueblo_indigena_cual',
  'planilla_deporte',
  'planilla_deporte_desde',
  'planilla_actividad_cultural',
  'planilla_actividad_cultural_desde',
  'planilla_organizacion_social',
  'planilla_organizacion_social_desde',
  'planilla_estado',
  'planilla_municipio',
  'planilla_parroquia',
  'planilla_comunidad',
  'planilla_telefono_fijo',
  'planilla_twitter',
  'planilla_facebook',
  'planilla_familiares',
  'planilla_misiones',
  'planilla_nivel_avance',
  'planilla_ultimo_anio',
  'planilla_especialidad',
  'planilla_otras_formaciones',
  'planilla_experiencias',

  // La red de seguridad: el jsonb crudo, sin aplanar.
  'datos_planilla',
];

/// Fin de línea del CSV: CRLF, como manda la RFC 4180.
///
/// Se fija a CRLF y no se deja al sistema: el archivo se genera en el navegador
/// y lo consume un sistema del INCES, así que el formato no puede depender de
/// en qué máquina se pulsó el botón.
const String _finDeLinea = '\r\n';

/// Una fila de `v_exportacion_hacer`, tal como la devolvió PostgREST.
///
/// Guarda el mapa crudo en vez de 61 campos con nombre a propósito: la lista de
/// columnas va a cambiar cuando llegue la especificación de HACER, y con el mapa
/// ese cambio no toca este archivo. Lo que sí está tipado es la **lectura**
/// ([valorDe]), que es donde vive la decisión de cómo se aplana cada tipo.
class FilaExportacionHacer {
  const FilaExportacionHacer(this.valores);

  final Map<String, dynamic> valores;

  /// El valor de [columna] aplanado a texto, o `null` si no hay dato.
  ///
  /// El aplanado del lado del cliente es corto porque el trabajo difícil ya lo
  /// hizo `planilla_texto()` en la base: lo que llega por aquí son cadenas,
  /// booleanos, números y —sólo en `datos_planilla`— una estructura.
  ///
  /// `true`/`false` se escriben literales y no «Sí»/«No»: es lo que guarda la
  /// base y lo que un importador espera. Traducirlos aquí crearía una segunda
  /// convención que el sistema de destino no pidió.
  String? valorDe(String columna) {
    final valor = valores[columna];
    if (valor == null) return null;

    if (valor is String) return valor.isEmpty ? null : valor;
    if (valor is bool) return valor ? 'true' : 'false';
    if (valor is num) return valor.toString();

    // `datos_planilla`: el jsonb viaja como JSON compacto, que es lo que lo hace
    // recuperable. Es la única estructura que llega sin aplanar.
    return jsonEncode(valor);
  }
}

/// La nómina de una sección, lista para serializar.
class ExportacionHacer {
  const ExportacionHacer({required this.filas});

  final List<FilaExportacionHacer> filas;

  factory ExportacionHacer.fromJson(List<dynamic> json) => ExportacionHacer(
        filas: json
            .whereType<Map<String, dynamic>>()
            .map(FilaExportacionHacer.new)
            .toList(growable: false),
      );

  bool get vacia => filas.isEmpty;
  int get total => filas.length;

  /// El archivo completo, cabecera incluida.
  String aCsv() => csvDeExportacionHacer(filas);
}

/// Serializa las filas a CSV (RFC 4180).
///
/// Es una función libre y no un método porque es una transformación pura de
/// datos: se prueba con una lista literal, sin montar una pantalla ni un
/// gateway.
///
/// **La cabecera es la lista declarada, más las claves que PostgREST haya
/// devuelto y no estén declaradas.** Esa segunda mitad no es adorno: si una
/// migración futura añade una columna a la vista, sin ella el dato nuevo
/// desaparecería del CSV en silencio y el archivo seguiría pareciendo correcto.
/// Las claves extra van al final y ordenadas, para que el archivo sea
/// determinista.
String csvDeExportacionHacer(List<FilaExportacionHacer> filas) {
  final extra = <String>{};
  for (final fila in filas) {
    for (final clave in fila.valores.keys) {
      if (!columnasExportacionHacer.contains(clave)) extra.add(clave);
    }
  }

  final columnas = <String>[
    ...columnasExportacionHacer,
    ...(extra.toList()..sort()),
  ];

  final buffer = StringBuffer()
    ..write(columnas.map(_celdaCsv).join(','))
    ..write(_finDeLinea);

  for (final fila in filas) {
    buffer
      ..write(columnas.map((c) => _celdaCsv(fila.valorDe(c))).join(','))
      ..write(_finDeLinea);
  }

  return buffer.toString();
}

/// Una celda, entrecomillada sólo si lo necesita.
///
/// Se entrecomilla cuando el valor contiene coma, comilla o salto de línea, que
/// son los tres casos que la RFC 4180 obliga a proteger. Una comilla interior se
/// duplica.
///
/// **No se «sanea» el contenido.** Un valor que empiece por `=`, `+`, `-` o `@`
/// es una fórmula si el archivo se abre en Excel, pero en este catálogo hay
/// teléfonos que empiezan por `+` de verdad: prefijarlos con un apóstrofo
/// corrompería el dato para HACER, que es el consumidor real. El archivo es un
/// intercambio entre sistemas, no una hoja de cálculo.
String _celdaCsv(String? valor) {
  if (valor == null || valor.isEmpty) return '';

  final necesitaComillas = valor.contains(',') ||
      valor.contains('"') ||
      valor.contains('\n') ||
      valor.contains('\r');

  if (!necesitaComillas) return valor;

  return '"${valor.replaceAll('"', '""')}"';
}

/// El nombre del archivo descargado.
///
/// Se construye a partir de la sección para que dos descargas del mismo día no
/// se pisen, y se limpia de los caracteres que ningún sistema de archivos
/// admite. **No se quitan los acentos**: `José` es un nombre, no un error, y
/// tanto el atributo `download` del navegador como los sistemas modernos los
/// aceptan.
String nombreArchivoHacer({
  required String periodo,
  required String seccion,
  String? materia,
}) {
  final partes = <String>[
    'planilla-hacer',
    periodo,
    if (materia != null && materia.trim().isNotEmpty) materia,
    seccion,
  ];

  final nombre = partes
      .map(_sinCaracteresIlegales)
      .where((parte) => parte.isNotEmpty)
      .join('-');

  return '$nombre.csv';
}

/// Quita lo que ningún sistema de archivos admite (`\ / : * ? " < > |` y los
/// caracteres de control) y convierte los espacios en guiones.
String _sinCaracteresIlegales(String texto) => texto
    .trim()
    .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
    .replaceAll(RegExp(r'\s+'), '-');
