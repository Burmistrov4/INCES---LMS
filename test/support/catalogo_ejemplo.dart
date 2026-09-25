import 'package:inces_lms_app/models/inscripcion_campo.dart';

/// Un catálogo de prueba con la **forma** del real, para poder conducir el
/// formulario sin red.
///
/// **Por qué es un catálogo y no una lista de campos sueltos.** Lo que hay que
/// probar en la pantalla es que *el catálogo manda*: qué pasos existen, en qué
/// orden, qué se exige y qué se esconde. Una prueba que escribiera los pasos a
/// mano volvería a acoplar la prueba a la pantalla, que es justo lo que la
/// pantalla dejó de hacer.
///
/// Los grupos son cinco, y cada uno está porque ejercita algo distinto:
///  · `Datos personales` — el desglose del nombre (lo que obliga a sintetizar
///    `nombres`/`apellidos`) y un campo **condicional**.
///  · `Ubicación y contacto` — el correo, que tiene validador de formato.
///  · `Misiones` — la **rejilla**, que es la que sustituye a `mision_ribaras`.
///  · `Representante legal` — los cinco campos que la regla de edad vuelve
///    obligatorios para un menor.
///  · `Propuesta formativa` — el campo con `fuente`, cuyas opciones se piden en
///    vivo.
///
/// Las etiquetas son las del catálogo real en lo que importa (son texto que el
/// CFS puede renombrar), pero las pruebas **no** se apoyan en ellas para
/// encontrar los campos: usan el código. Una prueba atada a una etiqueta se cae
/// el día que alguien reescriba el catálogo, y ese día el catálogo está
/// funcionando bien.

/// Un campo del catálogo con los valores por defecto, para no repetir claves.
CampoInscripcion campoCatalogo(
  String codigo, {
  String? etiqueta,
  String grupo = 'Datos personales',
  TipoCampoInscripcion tipo = TipoCampoInscripcion.texto,
  bool obligatorio = false,
  int orden = 0,
  Map<String, dynamic>? opciones,
  String? fuente,
  Map<String, dynamic>? condicion,
  String? ayuda,
}) {
  return CampoInscripcion(
    codigo: codigo,
    etiqueta: etiqueta ?? codigo,
    grupo: grupo,
    tipo: tipo,
    orden: orden,
    obligatorio: obligatorio,
    opciones: opciones,
    fuente: fuente,
    condicion: condicion == null
        ? null
        : CondicionCampoInscripcion.fromJson(condicion),
    ayuda: ayuda,
  );
}

/// Las opciones de un `seleccion`, con la forma del jsonb real.
Map<String, dynamic> opcionesDe(List<(String, String)> pares) => {
      'opciones': [
        for (final (valor, etiqueta) in pares)
          {'valor': valor, 'etiqueta': etiqueta},
      ],
    };

/// Los cinco campos que la regla de edad vuelve obligatorios.
///
/// Se exponen porque la pantalla los nombra por código y una prueba tiene que
/// poder comprobar que esa lista y este catálogo siguen hablando de lo mismo.
const List<String> codigosRepresentante = [
  'numero_identidad_tutor',
  'nombre_tutor',
  'parentesco_tutor',
  'telefono_tutor',
  'correo_tutor',
];

/// El catálogo por defecto: cinco grupos, con los casos que importan.
///
/// [tipoFecha] existe por un motivo concreto y no para comodidad: la regla de
/// edad de la pantalla lee `fecha_nac` **del mapa de valores**, como el texto
/// `YYYY-MM-DD` que produce el calendario, y no le importa de qué widget salió.
/// Con la fecha declarada como `texto`, una prueba puede escribir la fecha y
/// ejercitar la regla de edad —que es lo que quiere medir— sin pelearse con la
/// navegación por años del calendario de Material. Que el calendario produce ese
/// mismo formato se prueba aparte, en `campos_planilla_test.dart`, que es donde
/// vive ese widget.
CatalogoInscripcion catalogoEjemplo({
  TipoCampoInscripcion tipoFecha = TipoCampoInscripcion.fecha,
}) =>
    CatalogoInscripcion([
      // --- Datos personales -------------------------------------------------
      campoCatalogo('primer_nombre',
          etiqueta: 'Primer nombre', obligatorio: true, orden: 10),
      campoCatalogo('segundo_nombre', etiqueta: 'Segundo nombre', orden: 11),
      campoCatalogo('primer_apellido',
          etiqueta: 'Primer apellido', obligatorio: true, orden: 12),
      campoCatalogo('segundo_apellido', etiqueta: 'Segundo apellido', orden: 13),
      campoCatalogo('cedula',
          etiqueta: 'Cédula de identidad', obligatorio: true, orden: 14),
      campoCatalogo('fecha_nac',
          etiqueta: 'Fecha de nacimiento',
          tipo: tipoFecha,
          obligatorio: true,
          orden: 15),
      campoCatalogo('sexo',
          etiqueta: 'Sexo',
          tipo: TipoCampoInscripcion.seleccion,
          obligatorio: true,
          orden: 16,
          opciones: opcionesDe(const [
            ('M', 'Masculino'),
            ('F', 'Femenino'),
            ('Otro', 'Otro'),
          ])),
      campoCatalogo('pueblo_indigena',
          etiqueta: '¿Pertenece a algún pueblo indígena?',
          tipo: TipoCampoInscripcion.booleano,
          orden: 17),
      // El condicional: sólo aparece con la casilla marcada. Es el caso que
      // obliga a que las claves de estado vayan atadas al código y no a la
      // posición.
      campoCatalogo('pueblo_indigena_cual',
          etiqueta: '¿A cuál?',
          orden: 18,
          condicion: const {'campo': 'pueblo_indigena', 'igual': true}),

      // --- Ubicación y contacto --------------------------------------------
      campoCatalogo('telefono',
          etiqueta: 'Teléfono móvil',
          grupo: 'Ubicación y contacto',
          obligatorio: true,
          orden: 100),
      campoCatalogo('email',
          etiqueta: 'Correo electrónico',
          grupo: 'Ubicación y contacto',
          tipo: TipoCampoInscripcion.email,
          obligatorio: true,
          orden: 101),
      campoCatalogo('direccion',
          etiqueta: 'Domicilio',
          grupo: 'Ubicación y contacto',
          obligatorio: true,
          orden: 102),

      // --- Formación --------------------------------------------------------
      // `nivel_educativo` no es decorativo: `AuthService._validarPlanilla` lo
      // exige para dejar inscribirse, así que sin él ninguna prueba podría
      // llegar al envío y todas fallarían por un motivo ajeno a lo que miden.
      campoCatalogo('nivel_educativo',
          etiqueta: 'Nivel educativo',
          grupo: 'Formación',
          tipo: TipoCampoInscripcion.seleccion,
          obligatorio: true,
          orden: 150,
          opciones: opcionesDe(const [
            ('PRIMARIA', 'Primaria'),
            ('SECUNDARIA', 'Secundaria'),
            ('TECNICO', 'Técnico'),
            ('UNIVERSITARIO', 'Universitario'),
          ])),

      // --- Misiones ---------------------------------------------------------
      campoCatalogo('misiones',
          etiqueta: 'Misiones a las que pertenece',
          grupo: 'Misiones',
          tipo: TipoCampoInscripcion.rejilla,
          orden: 200,
          opciones: const {
            'etiqueta_desde': 'Desde',
            'multiple': true,
            'items': [
              {'valor': 'RIBAS', 'etiqueta': 'Ribas'},
              {'valor': 'MERCAL', 'etiqueta': 'Mercal'},
            ],
          }),

      // --- Representante legal ----------------------------------------------
      campoCatalogo('numero_identidad_tutor',
          etiqueta: 'Cédula del representante',
          grupo: 'Representante legal',
          orden: 300),
      campoCatalogo('nombre_tutor',
          etiqueta: 'Nombre del representante',
          grupo: 'Representante legal',
          orden: 301),
      campoCatalogo('parentesco_tutor',
          etiqueta: 'Parentesco',
          grupo: 'Representante legal',
          orden: 302),
      campoCatalogo('telefono_tutor',
          etiqueta: 'Teléfono del representante',
          grupo: 'Representante legal',
          orden: 303),
      campoCatalogo('correo_tutor',
          etiqueta: 'Correo del representante',
          grupo: 'Representante legal',
          tipo: TipoCampoInscripcion.email,
          orden: 304),

      // --- Propuesta formativa ----------------------------------------------
      campoCatalogo('curso_seleccionado',
          etiqueta: 'Propuesta formativa a cursar',
          grupo: 'Propuesta formativa',
          tipo: TipoCampoInscripcion.seleccion,
          obligatorio: true,
          orden: 400,
          fuente: 'programas'),
    ]);

/// Los cursos que devuelve el catálogo de respaldo en las pruebas.
const List<String> cursosDePrueba = [
  'Herrería',
  'Higiene y Manipulación de Alimentos',
];

/// Los grupos del catálogo de ejemplo, en orden, tal como los ve el formulario.
///
/// Se calcula desde el catálogo y no se escribe a mano: si alguien añade un
/// grupo, las pruebas que recorren los pasos tienen que enterarse solas. Es la
/// misma razón por la que la pantalla no los conoce.
List<String> gruposDeEjemplo() =>
    catalogoEjemplo().grupos.map((grupo) => grupo.nombre).toList();
