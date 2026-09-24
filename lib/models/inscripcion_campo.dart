/// El catálogo de campos de la planilla de inscripción, tal como lo sirve
/// `GET /api/v1/inscripcion/campos`.
///
/// Este archivo es la pieza que convierte el formulario de inscripción en algo
/// **conducido por datos**: la pantalla no conoce los campos, los lee de aquí y
/// los pinta. Añadir una pregunta al formulario es una fila en
/// `inscripcion_campos`, no un despliegue.
///
/// La consecuencia práctica es que el catálogo tiene que llegar **entero**. Si
/// el modelo proyectara sólo los campos «útiles», cualquier campo nuevo
/// obligaría a tocar este archivo, y eso devolvería el problema que el catálogo
/// existe para resolver.
library;

/// Tipos de campo que el catálogo puede declarar.
///
/// Es un `enum` y no una cadena suelta porque el tipo **decide el widget y la
/// forma del valor guardado**: un `numero` guarda un `num`, una `fecha` una
/// cadena `YYYY-MM-DD`, un `booleano` un `bool` y una `multiseleccion` una
/// `List<String>`. Si el tipo llegara como texto libre, un catálogo con una
/// errata («numbero») no fallaría al leerse: fallaría al pintar, en la cara del
/// aspirante.
///
/// Los nombres coinciden con `TIPOS_CAMPO_INSCRIPCION` del backend y con el
/// `check` de la columna en la base. `name` es, por tanto, el contrato.
enum TipoCampoInscripcion {
  texto,
  email,
  numero,
  fecha,
  seleccion,
  multiseleccion,
  booleano,
  tabla,
  rejilla;

  /// Traduce el valor que viene del catálogo.
  ///
  /// Devuelve `null` ante un tipo desconocido y deja que quien llama decida.
  /// Degradar a `texto` en silencio sería peor: un catálogo con un tipo mal
  /// escrito parecería funcionar y guardaría el valor con otra forma, y el
  /// fallo aparecería mucho más tarde, al leer la planilla.
  static TipoCampoInscripcion? desde(Object? valor) {
    if (valor is! String) return null;
    for (final tipo in TipoCampoInscripcion.values) {
      if (tipo.name == valor) return tipo;
    }
    return null;
  }
}

/// Una opción de un `seleccion` o `multiseleccion`.
class OpcionCampo {
  const OpcionCampo({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  factory OpcionCampo.fromJson(Map<String, dynamic> json) {
    final valor = (json['valor'] ?? '').toString();
    final etiqueta = (json['etiqueta'] ?? '').toString();
    return OpcionCampo(
      valor: valor,
      // La etiqueta cae al valor: una opción sin texto que se pintara vacía
      // dejaría una casilla que el aspirante no puede identificar.
      etiqueta: etiqueta.isEmpty ? valor : etiqueta,
    );
  }
}

/// Una columna de un campo `tabla`.
class ColumnaTabla {
  const ColumnaTabla({
    required this.codigo,
    required this.etiqueta,
    required this.tipo,
    this.obligatorio = false,
    this.opciones = const [],
  });

  final String codigo;
  final String etiqueta;
  final TipoCampoInscripcion tipo;
  final bool obligatorio;
  final List<OpcionCampo> opciones;

  factory ColumnaTabla.fromJson(Map<String, dynamic> json) {
    final opciones = (json['opciones'] as List?) ?? const [];
    return ColumnaTabla(
      codigo: (json['codigo'] ?? '').toString(),
      etiqueta: (json['etiqueta'] ?? json['codigo'] ?? '').toString(),
      tipo: TipoCampoInscripcion.desde(json['tipo']) ?? TipoCampoInscripcion.texto,
      obligatorio: json['obligatorio'] == true,
      opciones: opciones
          .whereType<Map<String, dynamic>>()
          .map(OpcionCampo.fromJson)
          .toList(),
    );
  }
}

/// Un ítem de un campo `rejilla`.
class ItemRejilla {
  const ItemRejilla({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  factory ItemRejilla.fromJson(Map<String, dynamic> json) {
    final valor = (json['valor'] ?? '').toString();
    final etiqueta = (json['etiqueta'] ?? '').toString();
    return ItemRejilla(
      valor: valor,
      etiqueta: etiqueta.isEmpty ? valor : etiqueta,
    );
  }
}

/// Visibilidad condicional de un campo: se muestra sólo si otro campo vale
/// `igual`. Ejemplo del catálogo: `pueblo_indigena_cual` se muestra cuando
/// `pueblo_indigena` es `true`.
///
/// **Sólo afecta a la presentación.** El campo existe siempre en el catálogo y
/// su valor se puede guardar siempre; quien decide qué es obligatorio es
/// `validar_planilla()` en la base, que **no lee `condicion`**.
class CondicionCampoInscripcion {
  const CondicionCampoInscripcion({required this.campo, this.igual});

  final String campo;
  final Object? igual;

  factory CondicionCampoInscripcion.fromJson(Map<String, dynamic> json) {
    return CondicionCampoInscripcion(
      campo: (json['campo'] ?? '').toString(),
      igual: json['igual'],
    );
  }

  /// ¿Se cumple la condición con los valores que hay ahora en el formulario?
  ///
  /// Un campo que nunca se ha tocado no está en el mapa, así que la comparación
  /// con `null` da `false` y el campo dependiente no se muestra. Es lo correcto:
  /// hasta que el aspirante no marque la casilla, la pregunta de detalle no
  /// tiene sentido.
  bool seCumple(Map<String, dynamic> valores) {
    final actual = valores[campo];

    // `true` y `1` se consideran el mismo sí a propósito. El catálogo guarda
    // `igual` en jsonb y un `1` es una forma razonable de escribir «marcado»;
    // tratarlos como distintos haría que la pregunta de detalle no apareciera
    // nunca y el fallo se leería como «el catálogo no funciona».
    if (igual == true) return actual == true || actual == 1;
    if (igual == false) return actual == false || actual == 0;

    return actual == igual;
  }
}

/// Un campo del catálogo de la planilla.
class CampoInscripcion {
  const CampoInscripcion({
    required this.codigo,
    required this.etiqueta,
    required this.grupo,
    required this.tipo,
    required this.orden,
    this.obligatorio = false,
    this.opciones,
    this.fuente,
    this.condicion,
    this.ayuda,
  });

  /// Clave con la que el valor viaja dentro de la planilla. Es también la
  /// identidad del campo: renombrarlo es una migración de datos.
  final String codigo;
  final String etiqueta;

  /// Agrupación visual («Datos personales»). **No es un paso ni un índice**: el
  /// formulario agrupa por este valor y el orden de los grupos es el de
  /// aparición. Añadir un grupo es añadir filas, no tocar la pantalla.
  final String grupo;

  final TipoCampoInscripcion tipo;

  /// Orden **global**, no por grupo: el renderizador ordena sin conocer los
  /// grupos.
  final int orden;

  /// Espejo informativo de la regla de la base, para marcar el campo antes de
  /// enviarlo. La autoridad sigue siendo el trigger de PostgreSQL.
  final bool obligatorio;

  /// El contenido crudo de `opciones`, transportado **tal cual**. Su forma
  /// depende de `tipo` y el backend no la interpreta, así que aquí tampoco se
  /// reinterpreta: se lee con las vistas de abajo, que saben qué buscar.
  final Map<String, dynamic>? opciones;

  /// Origen **dinámico** de las opciones, o `null` si están incrustadas. Hoy el
  /// único valor es `'programas'`: la oferta formativa cambia y no puede quedar
  /// congelada en el catálogo.
  final String? fuente;

  final CondicionCampoInscripcion? condicion;

  /// Aclaración bajo el campo, o `null`.
  final String? ayuda;

  factory CampoInscripcion.fromJson(Map<String, dynamic> json) {
    final opciones = json['opciones'];
    final condicion = json['condicion'];

    return CampoInscripcion(
      codigo: (json['codigo'] ?? '').toString(),
      etiqueta: (json['etiqueta'] ?? json['codigo'] ?? '').toString(),
      grupo: (json['grupo'] ?? '').toString(),
      // Un tipo desconocido cae a `texto` **sólo en el peor caso**: el campo se
      // pinta como una caja de texto y el dato se puede escribir. Es una
      // degradación visible, no silenciosa, y es preferible a que la pantalla
      // entera falle por un campo que el CFS acaba de añadir.
      tipo: TipoCampoInscripcion.desde(json['tipo']) ?? TipoCampoInscripcion.texto,
      orden: json['orden'] is int ? json['orden'] as int : 0,
      obligatorio: json['obligatorio'] == true,
      opciones: opciones is Map<String, dynamic> ? opciones : null,
      fuente: json['fuente'] is String && (json['fuente'] as String).isNotEmpty
          ? json['fuente'] as String
          : null,
      condicion: condicion is Map<String, dynamic>
          ? CondicionCampoInscripcion.fromJson(condicion)
          : null,
      ayuda: json['ayuda'] is String && (json['ayuda'] as String).isNotEmpty
          ? json['ayuda'] as String
          : null,
    );
  }

  // --- Vistas de `opciones` -------------------------------------------------
  //
  // Se leen aquí y no en cada widget para que la forma del jsonb tenga un solo
  // intérprete. Los widgets piden «las opciones» y no «`opciones['opciones']`».

  /// La lista cerrada de un `seleccion` o `multiseleccion`.
  List<OpcionCampo> get opcionesCerradas {
    final lista = opciones?['opciones'];
    if (lista is! List) return const [];
    return lista.whereType<Map<String, dynamic>>().map(OpcionCampo.fromJson).toList();
  }

  /// Los ítems de una `rejilla`.
  List<ItemRejilla> get itemsRejilla {
    final lista = opciones?['items'];
    if (lista is! List) return const [];
    return lista.whereType<Map<String, dynamic>>().map(ItemRejilla.fromJson).toList();
  }

  /// Las columnas de una `tabla`.
  List<ColumnaTabla> get columnasTabla {
    final lista = opciones?['columnas'];
    if (lista is! List) return const [];
    return lista.whereType<Map<String, dynamic>>().map(ColumnaTabla.fromJson).toList();
  }

  /// El rótulo del valor «desde» de una `rejilla` («Desde»), o `null`.
  String? get etiquetaDesde {
    final valor = opciones?['etiqueta_desde'];
    return valor is String && valor.isNotEmpty ? valor : null;
  }

  /// ¿La rejilla admite más de un ítem marcado?
  bool get multiple => opciones?['multiple'] != false;

  /// ¿Las opciones hay que pedirlas a otra fuente en vivo?
  bool get tieneFuenteExterna => fuente != null;

  /// ¿Se muestra el campo con los valores actuales?
  bool visibleCon(Map<String, dynamic> valores) {
    final regla = condicion;
    if (regla == null) return true;
    return regla.seCumple(valores);
  }

  /// ¿Hay que exigirlo con los valores actuales?
  ///
  /// Un campo oculto no se exige: no se puede rellenar lo que no se ve. Ojo con
  /// la consecuencia, que es una **incoherencia latente del catálogo**: como
  /// `validar_planilla()` no lee `condicion`, marcar como obligatorio un campo
  /// condicional lo haría imposible de cumplir cuando la condición es falsa.
  /// Hoy ningún campo del catálogo está en ese caso.
  bool obligatorioCon(Map<String, dynamic> valores) =>
      obligatorio && visibleCon(valores);
}

/// El catálogo completo, ordenado, como lo sirve el backend.
class CatalogoInscripcion {
  const CatalogoInscripcion(this.campos);

  final List<CampoInscripcion> campos;

  factory CatalogoInscripcion.fromJson(Map<String, dynamic> json) {
    final lista = (json['campos'] as List?) ?? const [];
    return CatalogoInscripcion(
      lista.whereType<Map<String, dynamic>>().map(CampoInscripcion.fromJson).toList(),
    );
  }

  /// Los grupos, en el orden en que aparecen en el catálogo.
  ///
  /// El orden lo fija `orden` (que es global) y no el alfabeto: el grupo de un
  /// campo aparece donde aparece su primer campo, así que reordenar el catálogo
  /// reordena los pasos del formulario sin tocar código.
  List<GrupoPlanilla> get grupos {
    final ordenados = [...campos]..sort((a, b) => a.orden.compareTo(b.orden));

    final nombres = <String>[];
    final porGrupo = <String, List<CampoInscripcion>>{};
    for (final campo in ordenados) {
      final nombre = campo.grupo.isEmpty ? 'Otros' : campo.grupo;
      if (!porGrupo.containsKey(nombre)) {
        nombres.add(nombre);
        porGrupo[nombre] = [];
      }
      porGrupo[nombre]!.add(campo);
    }

    return [
      for (final nombre in nombres)
        GrupoPlanilla(nombre: nombre, campos: porGrupo[nombre]!),
    ];
  }

  /// El campo con ese código, o `null`.
  CampoInscripcion? porCodigo(String codigo) {
    for (final campo in campos) {
      if (campo.codigo == codigo) return campo;
    }
    return null;
  }
}

/// Un grupo de campos: lo que el formulario pinta como un paso.
class GrupoPlanilla {
  const GrupoPlanilla({required this.nombre, required this.campos});

  final String nombre;
  final List<CampoInscripcion> campos;
}

/// La planilla rellena: código de campo → valor.
///
/// **El cliente no valida su forma.** Quién decide qué campos son obligatorios
/// es `inscripcion_campos` y lo aplica `validar_planilla()` en la base; repetir
/// aquí la lista sería una tercera copia de la regla (SQL, backend y
/// formulario) y las tres se desviarían en cuanto el CFS marcara un campo como
/// obligatorio desde el panel.
typedef PlanillaInscripcion = Map<String, dynamic>;

/// ¿El valor está ausente o vacío?
///
/// Replica la regla de `validar_planilla()`, y **`false` y `0` no están vacíos**:
/// en una planilla real hay preguntas de sí/no donde `false` es una respuesta, y
/// un `0` puede ser un número legítimo. Escribir esto como `if (!valor)` es el
/// error clásico, y rechazaría respuestas válidas.
bool valorDeCampoVacio(Object? valor) {
  if (valor == null) return true;
  if (valor is String) return valor.trim().isEmpty;
  if (valor is Iterable) return valor.isEmpty;
  if (valor is Map) return valor.isEmpty;
  return false;
}

/// Las claves planas que el trigger de PostgreSQL espera, derivadas del
/// catálogo.
///
/// **Por qué hace falta.** El catálogo pide el nombre desglosado
/// (`primer_nombre` + `segundo_nombre`) y el trigger lee `nombres` concatenado.
/// Son vocabularios distintos, y el mapeo no es 1 a 1. La consecuencia de
/// olvidarlo está documentada en `202609240001` y es un fallo **silencioso**: si
/// sólo viaja `primer_nombre`, el trigger deja `v_nombres` en NULL, la condición
/// `v_es_aspirante` falla y **la ficha no se crea, sin error**. El aspirante ve
/// «registro exitoso» y no tiene ficha.
///
/// `mision_ribaras` **no se sintetiza a propósito**: la planilla nueva manda la
/// rejilla `misiones`, y el campo de texto libre del formulario viejo deja de
/// enviarse. Duplicar el dato en dos claves con formas distintas sólo serviría
/// para que un día discrepen.
Map<String, dynamic> sintetizarClavesPlanas(PlanillaInscripcion planilla) {
  String texto(String codigo) => (planilla[codigo] ?? '').toString().trim();

  // Equivale al `btrim(a || ' ' || b)` del trigger: si falta una mitad, no
  // quedan espacios dobles ni sueltos.
  String unir(String primero, String segundo) {
    final partes = [texto(primero), texto(segundo)].where((p) => p.isNotEmpty);
    return partes.join(' ');
  }

  /// Los códigos que **coinciden** con la clave del trigger y sólo hay que
  /// copiar. Se listan explícitamente en vez de reenviar la planilla entera:
  /// mandar todas las claves del catálogo al `signUp` engordaría
  /// `raw_user_meta_data` con datos que el trigger no lee, y esa columna tiene
  /// un límite de tamaño real.
  const clavesDirectas = [
    'cedula',
    'fecha_nac',
    'sexo',
    'telefono',
    'direccion',
    'nivel_educativo',
    'curso_seleccionado',
    'discapacidad',
    'numero_identidad_tutor',
    'nombre_tutor',
    'parentesco_tutor',
    'telefono_tutor',
    'correo_tutor',
  ];

  return {
    'nombres': unir('primer_nombre', 'segundo_nombre'),
    'apellidos': unir('primer_apellido', 'segundo_apellido'),
    for (final clave in clavesDirectas)
      if (planilla[clave] != null) clave: planilla[clave],
  };
}
