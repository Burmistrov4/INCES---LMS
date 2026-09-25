import 'dart:convert';

// ============================================================================
//  La exportación hacia HACER: las columnas y el serializador del archivo
// ============================================================================
//
//  ESTADO DE LA ESPECIFICACIÓN (D17)
//  ---------------------------------
//  Este archivo fue durante meses «lo único que se podía escribir sin la
//  especificación de HACER». Ya no del todo: el 2026-09-25 llegaron las
//  **reglas de formateo** del sistema receptor, y están implementadas abajo,
//  cada una con su motivo escrito al lado.
//
//  **Lo que sigue SIN especificar, y no conviene confundir**: qué columnas, en
//  qué orden y con qué nombres espera HACER. Este archivo entrega las 61 de la
//  vista en el orden en que la vista las declara, más `documento_identidad`,
//  que es una derivación. Cuando llegue la lista de campos de HACER, lo que se
//  toca es [columnasExportacionHacer] y el `select` de la vista — y nada más.

/// Las columnas de la exportación hacia HACER, **en el orden en que salen del
/// archivo**.
///
/// Es la misma lista y el mismo orden que `public.v_exportacion_hacer` declara
/// en `202609250004_v_exportacion_hacer.sql`, **más `documento_identidad`**, que
/// no viene de la vista sino que se deriva aquí (ver [FilaExportacionHacer
/// .documentoIdentidad]).
///
/// Está escrita a mano —y no derivada de las claves de la primera fila— por un
/// motivo concreto: **una sección sin matriculados devuelve cero filas**, y un
/// CSV sin cabecera no le sirve a nadie que lo abra en HACER. Derivar la
/// cabecera de los datos haría que el formato del archivo dependiera de si hay
/// datos, que es la clase de fragilidad que este proyecto evita en todas partes.
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
  // Derivada, no de la vista. Va pegada a `cedula` porque es su lectura
  // «documento oficial»: nacionalidad + cédula, con relleno de ceros.
  'documento_identidad',
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

/// El separador de campos: **punto y coma**, como exige HACER.
///
/// No es una preferencia estética. El punto y coma es la convención de los
/// sistemas que abren el archivo en una configuración regional donde la **coma
/// es el separador decimal**: allí un `1,5` partiría la celda en dos. Y es
/// además lo que el sistema receptor pide, que es el motivo que manda.
///
/// **Consecuencia que hay que respetar**: la regla de entrecomillado depende del
/// separador. Ver [_celdaCsv].
const String separadorHacer = ';';

/// Fin de línea del CSV: CRLF, como manda la RFC 4180 **y** como exige HACER.
///
/// Se fija a CRLF y no se deja al sistema: el archivo se genera en el navegador
/// y lo consume un sistema del INCES, así que el formato no puede depender de
/// en qué máquina se pulsó el botón.
const String _finDeLinea = '\r\n';

/// La marca de orden de bytes (BOM) de UTF-8, como **carácter**.
///
/// Se escribe el carácter `U+FEFF` y no los tres bytes a mano porque es
/// exactamente equivalente y no rompe el tipo: al codificar la cadena a UTF-8,
/// `U+FEFF` se convierte en `EF BB BF`, que son los tres bytes que el archivo
/// necesita al principio.
///
/// **Por qué el BOM no es opcional aquí.** Sin él, Excel —y buena parte del
/// software administrativo que lee CSV— no deduce que el archivo es UTF-8 y cae
/// en la codificación del sistema (Windows-1252 en un equipo en español), con lo
/// que «ÑÚÑEZ» sale como «Ã‘ÃšÃ‘EZ». El `charset=utf-8` del `Content-Type` no
/// basta: ese encabezado describe el transporte, y el archivo queda guardado en
/// disco sin él. Los tres bytes viajan **dentro** del archivo, que es el único
/// sitio donde el programa que lo abra más tarde los va a encontrar.
const String marcaOrdenDeBytes = '\uFEFF';

/// Las columnas cuyo valor **no** se pasa a mayúsculas.
///
/// La regla de HACER es «todo el texto a mayúsculas», y se aplica a todo lo que
/// es texto de verdad. Esta lista es la **excepción medida**, no una opinión, y
/// sale de mirar el tipo SQL de cada columna en la vista:
///
///  * **`uuid` (5)** — `inscripcion_id`, `seccion_id`, `programa_id`,
///    `materia_id`, `aspirante_id`. Un uuid en mayúsculas es un uuid **inválido**
///    para cualquier analizador estricto: los dígitos hexadecimales en mayúscula
///    no forman parte de la forma canónica de la RFC 9562. Subirlos a mayúsculas
///    rompería justo el dato que sirve para casar la fila con el sistema de
///    origen.
///  * **`jsonb` (1)** — `datos_planilla`. Es la red de seguridad: viaja crudo
///    para que ningún campo sea irrecuperable. Subir la cadena a mayúsculas
///    subiría también **sus claves**, y el jsonb pasaría a tener
///    `{"NACIONALIDAD": ...}` mientras las 29 columnas `planilla_*` siguen
///    leyendo el código del catálogo en minúsculas. Serían dos vocabularios para
///    el mismo dato dentro del mismo archivo.
///  * **`boolean` (2)** — `seccion_activa`, `discapacidad`. Salen como `true` y
///    `false` literales, que es lo que guarda la base y lo que un importador
///    espera. Convertirlos en `TRUE`/`FALSE` sería inventar una segunda
///    convención que nadie pidió.
///  * **fechas (2)** — `inscrito_en`, `fecha_nac`. Viajan en ISO 8601, que ya es
///    un formato cerrado y en minúsculas por convención (`2026-09-25T…`).
///
/// **Un campo nuevo del catálogo no está en esta lista, así que se pondrá en
/// mayúsculas**, que es lo que la regla de HACER manda por defecto. Es la
/// dirección segura del error: el texto de más se ve al abrir el archivo, un
/// uuid roto se descubre al intentar importarlo.
const Set<String> columnasSinMayusculas = <String>{
  'inscripcion_id',
  'seccion_id',
  'programa_id',
  'materia_id',
  'aspirante_id',
  'datos_planilla',
  'seccion_activa',
  'discapacidad',
  'inscrito_en',
  'fecha_nac',
};

/// Una fila de `v_exportacion_hacer`, tal como la devolvió PostgREST.
///
/// Guarda el mapa crudo en vez de 62 campos con nombre a propósito: la lista de
/// columnas va a cambiar cuando llegue la especificación de campos de HACER, y
/// con el mapa ese cambio no toca este archivo. Lo que sí está tipado es la
/// **lectura** ([valorDe]), que es donde vive la decisión de cómo se aplana cada
/// tipo.
class FilaExportacionHacer {
  const FilaExportacionHacer(this.valores);

  final Map<String, dynamic> valores;

  /// El valor de [columna] aplanado a texto, o `null` si no hay dato.
  ///
  /// Devuelve el dato **crudo**: las reglas de formateo del archivo (mayúsculas,
  /// saltos de línea, entrecomillado) las aplica el serializador, no esto. La
  /// única excepción es [documentoIdentidad], que no es un formateo sino una
  /// **derivación**: el documento oficial no existe en ninguna columna de la
  /// vista, se construye a partir de dos.
  ///
  /// `true`/`false` se escriben literales y no «Sí»/«No»: es lo que guarda la
  /// base y lo que un importador espera. Traducirlos aquí crearía una segunda
  /// convención que el sistema de destino no pidió.
  String? valorDe(String columna) {
    if (columna == 'documento_identidad') return documentoIdentidad();

    final valor = valores[columna];
    if (valor == null) return null;

    if (valor is String) return valor.isEmpty ? null : valor;
    if (valor is bool) return valor ? 'true' : 'false';
    if (valor is num) return valor.toString();

    // `datos_planilla`: el jsonb viaja como JSON compacto, que es lo que lo hace
    // recuperable. Es la única estructura que llega sin aplanar.
    return jsonEncode(valor);
  }

  /// El documento de identidad: nacionalidad + cédula, con la parte numérica
  /// rellenada con ceros hasta 9 dígitos, de modo que el documento tenga **10
  /// caracteres** (`V` + `012345678` = `V012345678`).
  ///
  /// **Por qué el relleno va en los dígitos y no en la cadena entera.** El
  /// ejemplo de la especificación —`V12345678` → `V012345678`— lo fija: si se
  /// rellenara la cadena completa saldría `0V12345678`, con la letra en medio,
  /// que no es un documento de ningún país. La letra va siempre primero.
  ///
  /// **No se inventa nada.** Si no hay cédula, no hay documento (`null`, que el
  /// serializador escribe como celda vacía). Si hay cédula pero no hay
  /// nacionalidad, sale la cédula con su relleno y **sin prefijo**: prefijar `V`
  /// por defecto afirmaría una nacionalidad que la base no tiene, y esto es un
  /// documento oficial. La nacionalidad y la cédula vienen de fuentes distintas
  /// —la cédula es columna plana de `aspirantes`, la nacionalidad vive en el
  /// jsonb de la planilla— así que el caso vacío es probable, no exótico.
  ///
  /// **Tampoco se prefija dos veces.** Una cédula puede venir ya con su letra
  /// (`V12345678`, `V-12345678`) porque el campo del catálogo es texto libre.
  /// Concatenar sin mirar produciría `VV12345678`, que es el fallo clásico de
  /// esta regla. Si la cédula trae su propia letra, **esa manda** sobre la de la
  /// planilla: es la que la persona escribió en su documento.
  ///
  /// Una cédula con una forma que no encaja en ninguna de las dos (letras
  /// sueltas, símbolos) **no se trocea**: se devuelve tal cual, con la
  /// nacionalidad delante sólo si no empieza ya por letra. Ante la duda, el dato
  /// original viaja íntegro — y `cedula` sigue en el archivo, así que nada se
  /// pierde.
  String? documentoIdentidad() {
    final cedula = valorDe('cedula');
    if (cedula == null) return null;

    final nacionalidad = valorDe('planilla_nacionalidad');
    final forma = RegExp(r'^([A-Za-z]{1,2})?[-\s]?(\d+)$').firstMatch(cedula.trim());

    if (forma == null) {
      if (nacionalidad == null || RegExp(r'^[A-Za-z]').hasMatch(cedula)) {
        return cedula;
      }
      return '$nacionalidad$cedula';
    }

    final letra = forma.group(1) ?? nacionalidad;
    final relleno = forma.group(2)!.padLeft(9, '0');

    return letra == null ? relleno : '$letra$relleno';
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

  /// El archivo completo, cabecera y BOM incluidos.
  String aCsv() => csvDeExportacionHacer(filas);
}

/// Serializa las filas al archivo de HACER, **con su BOM delante**.
///
/// Es una función libre y no un método porque es una transformación pura de
/// datos: se prueba con una lista literal, sin montar una pantalla ni un
/// gateway. Lo que devuelve **es el archivo**, no una descripción de él: de ahí
/// que incluya la marca de orden de bytes. Si se separaran, existiría un estado
/// intermedio —«el CSV sin BOM»— que alguien acabaría descargando por error.
///
/// **La cabecera es la lista declarada, más las claves que PostgREST haya
/// devuelto y no estén declaradas.** Esa segunda mitad no es adorno: si una
/// migración futura añade una columna a la vista, sin ella el dato nuevo
/// desaparecería del CSV en silencio y el archivo seguiría pareciendo correcto.
/// Las claves extra van al final y ordenadas, para que el archivo sea
/// determinista.
///
/// **La cabecera no se pasa a mayúsculas.** Las reglas de formateo que HACER
/// pidió son de *datos* —nulos, texto, saltos de línea—, y la cabecera no es un
/// dato: es la etiqueta que el sistema receptor usa para reconocer cada columna.
/// Cambiarle las mayúsculas a una etiqueta es cambiar el contrato con quien lee,
/// no sanear un valor. Si HACER pide la cabecera en mayúsculas, es **esta línea**
/// la que cambia, y conviene confirmarlo antes de hacerlo.
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
    ..write(marcaOrdenDeBytes)
    ..write(columnas.map(_celdaCsv).join(separadorHacer))
    ..write(_finDeLinea);

  for (final fila in filas) {
    buffer
      ..write(
        columnas
            .map((c) => _celdaCsv(_formatearCelda(c, fila.valorDe(c))))
            .join(separadorHacer),
      )
      ..write(_finDeLinea);
  }

  return buffer.toString();
}

/// Aplica a una celda las reglas de saneado que exige HACER.
///
/// Tres decisiones, y las tres se ven al abrir el archivo:
///
///  1. **Nulo o vacío → cadena vacía.** No `null`, no `"NULL"`, no un guion. La
///     celda vacía es la única forma de «no hay dato» que ningún importador
///     confunde con un valor.
///  2. **Los saltos de línea internos se sustituyen por un espacio.** Una
///     dirección escrita en dos renglones —`Av. Bolívar\nCalle 5`— rompería la
///     estructura del archivo: el registro se partiría en dos y a partir de ahí
///     todo lo que sigue estaría descolocado, columna a columna. Se sustituye
///     por **un espacio y no por nada**, porque borrarlo pegaría las palabras
///     (`AV. BOLÍVARCALLE 5`) y el dato dejaría de leerse. Los renglones
///     consecutivos colapsan en uno solo, y el resultado se recorta.
///  3. **Mayúsculas**, salvo en [columnasSinMayusculas], por lo explicado allí.
///
/// El orden importa poco —mayusculizar no crea saltos de línea— pero se recorta
/// al final para que el `trim` no reintroduzca nada.
String _formatearCelda(String columna, String? valor) {
  if (valor == null || valor.isEmpty) return '';

  final texto = valor.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (texto.isEmpty) return '';

  return columnasSinMayusculas.contains(columna) ? texto : texto.toUpperCase();
}

/// Una celda, entrecomillada sólo si lo necesita.
///
/// Se entrecomilla cuando el valor contiene **el separador**, una comilla o un
/// salto de línea. Que la condición sea «contiene [separadorHacer]» y no
/// «contiene una coma» no es un detalle: **la regla de entrecomillado sigue al
/// separador**, y con `;` de separador un campo con una coma (`1,5`) ya no
/// necesita comillas, mientras que uno con un punto y coma sí. Escribir la coma
/// a mano en esta condición dejaría el archivo mal entrecomillado el día que el
/// separador cambiara — que es exactamente lo que acaba de pasar.
///
/// Una comilla interior se duplica, como manda la RFC 4180.
///
/// **No se «sanea» el contenido.** Un valor que empiece por `=`, `+`, `-` o `@`
/// es una fórmula si el archivo se abre en Excel, pero en este catálogo hay
/// teléfonos que empiezan por `+` de verdad: prefijarlos con un apóstrofo
/// corrompería el dato para HACER, que es el consumidor real. El archivo es un
/// intercambio entre sistemas, no una hoja de cálculo.
String _celdaCsv(String texto) {
  if (texto.isEmpty) return '';

  final necesitaComillas = texto.contains(separadorHacer) ||
      texto.contains('"') ||
      texto.contains('\n') ||
      texto.contains('\r');

  if (!necesitaComillas) return texto;

  return '"${texto.replaceAll('"', '""')}"';
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
