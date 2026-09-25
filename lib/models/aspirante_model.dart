import 'inscripcion_campo.dart';

class AspiranteModel {
  final String? id;

  /// Id del usuario en `auth.users`. Lo asigna el trigger de PostgreSQL.
  final String? userId;

  final String nombres;
  final String apellidos;
  final String cedula;
  final DateTime? fechaNacimiento;
  final String sexo;
  final String telefono;
  final String email;
  final String direccion;
  final String nivelEducativo;
  final String cursoSeleccionado;
  final String? misionRibaras;
  final bool discapacidad;
  final String? tipoDiscapacidad;
  final String? numeroIdentidadTutor;
  final String? nombreTutor;
  final String? parentescoTutor;
  final String? telefonoTutor;
  final String? correoTutor;
  final bool requiresLegalTutor;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// La planilla completa, tal como el aspirante la rellenó.
  ///
  /// **Por qué existe además de las columnas de arriba.** Las columnas son el
  /// contrato que ya consumen HACER y los paneles; la planilla es el resto del
  /// formulario —los 44 campos del catálogo—, que no tiene columnas propias y
  /// que hasta ahora se perdía. Sin esto, exportar a HACER obligaría a volver a
  /// teclearlo todo, que es justamente la brecha medida.
  ///
  /// Viaja en `raw_user_meta_data` y el trigger `handle_new_user()` la copia a
  /// `aspirantes.datos_planilla` en la misma transacción. Es **la única clave
  /// que dispara `validar_planilla()`**: si no viene, el trigger no valida, que
  /// es la asimetría deliberada que permitió desplegar la migración sin romper
  /// al formulario viejo.
  final PlanillaInscripcion? datosPlanilla;

  AspiranteModel({
    this.id,
    this.userId,
    required this.nombres,
    required this.apellidos,
    required this.cedula,
    this.fechaNacimiento,
    required this.sexo,
    required this.telefono,
    required this.email,
    required this.direccion,
    required this.nivelEducativo,
    this.cursoSeleccionado = '',
    this.misionRibaras,
    this.discapacidad = false,
    this.tipoDiscapacidad,
    this.numeroIdentidadTutor,
    this.nombreTutor,
    this.parentescoTutor,
    this.telefonoTutor,
    this.correoTutor,
    bool requiresLegalTutor = false,
    this.datosPlanilla,
    this.createdAt,
    this.updatedAt,
  }) : requiresLegalTutor =
            requiresLegalTutor || _esMenorDeEdad(fechaNacimiento);

  factory AspiranteModel.fromJson(Map<String, dynamic> json) {
    return AspiranteModel(
      id: json['id'] as String?,
      userId: json['user_id'] as String? ?? json['userId'] as String?,
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      cedula: json['cedula'] as String? ?? '',
      fechaNacimiento: _parseDate(json['fecha_nac'] ?? json['fechaNacimiento']),
      sexo: json['sexo'] as String? ?? '',
      telefono: json['telefono'] as String? ?? '',
      email: json['email'] as String? ?? '',
      direccion:
          json['direccion'] as String? ?? json['domicilio'] as String? ?? '',
      nivelEducativo: json['nivel_educativo'] as String? ??
          json['nivelEducativo'] as String? ??
          '',
      cursoSeleccionado: json['curso_seleccionado'] as String? ??
          json['cursoSeleccionado'] as String? ??
          '',
      misionRibaras: json['mision_ribaras'] as String? ??
          json['misionEstudiante'] as String?,
      discapacidad: json['discapacidad'] as bool? ??
          json['tiene_discapacidad'] as bool? ??
          false,
      tipoDiscapacidad: json['tipo_discapacidad'] as String?,
      numeroIdentidadTutor: json['numero_identidad_tutor'] as String?,
      nombreTutor: json['nombre_tutor'] as String?,
      parentescoTutor: json['parentesco_tutor'] as String?,
      telefonoTutor: json['telefono_tutor'] as String?,
      correoTutor: json['correo_tutor'] as String?,
      requiresLegalTutor: json['requires_legal_tutor'] as bool? ?? false,
      datosPlanilla: _parsePlanilla(json['datos_planilla']),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  /// Representación para escritura directa en la tabla `aspirantes`.
  ///
  /// La fecha viaja como `YYYY-MM-DD` (no como timestamp ISO) para que Postgres
  /// la interprete como `date` sin ambigüedad de zona horaria. Un timestamp con
  /// hora local podía desplazar un día y romper el CHECK de mayoría de edad.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      'nombres': nombres,
      'apellidos': apellidos,
      'cedula': cedula,
      if (fechaNacimiento != null) 'fecha_nac': _formatDate(fechaNacimiento),
      'sexo': sexo,
      'telefono': telefono,
      'email': email,
      'direccion': direccion,
      'nivel_educativo': nivelEducativo,
      'curso_seleccionado': cursoSeleccionado,
      'mision_ribaras': misionRibaras,
      'discapacidad': discapacidad,
      'tipo_discapacidad': discapacidad ? tipoDiscapacidad : null,
      'numero_identidad_tutor': numeroIdentidadTutor,
      'nombre_tutor': nombreTutor,
      'parentesco_tutor': parentescoTutor,
      'telefono_tutor': telefonoTutor,
      'correo_tutor': correoTutor,
      'requires_legal_tutor': requiresLegalTutor,
      if (datosPlanilla != null) 'datos_planilla': datosPlanilla,
    };
  }

  /// Metadata que viaja en `auth.signUp(data: ...)`.
  ///
  /// El trigger `handle_new_user()` lee exactamente estas claves para crear el
  /// perfil y la ficha de aspirante en una sola transacción. **No incluye
  /// `rol`**: el rol lo fija el servidor para impedir auto-promoción.
  ///
  /// **`mision_ribaras` ya no se envía**, y es a propósito. El catálogo pide la
  /// rejilla `misiones` (20 casillas, cada una con su «desde») y ese dato viaja
  /// dentro de `datos_planilla`; seguir mandando además el texto libre del
  /// formulario viejo sería guardar lo mismo dos veces con dos formas distintas,
  /// y el día que discreparan no habría forma de saber cuál manda. El trigger lo
  /// tolera sin cambios: `v_mision` es nullable y **no** forma parte de la
  /// condición `v_es_aspirante`, así que su ausencia no impide crear la ficha.
  /// El campo y `toJson()` se conservan para leer la columna y para las
  /// escrituras de administración.
  ///
  /// **`datos_planilla` es la clave que dispara la validación.** Es la única que
  /// hace que el trigger llame a `validar_planilla()`; sin ella no valida, que
  /// es lo que permite que un cliente antiguo siga funcionando.
  Map<String, dynamic> toMetadata() {
    return {
      'cedula': cedula,
      'nombres': nombres,
      'apellidos': apellidos,
      if (fechaNacimiento != null) 'fecha_nac': _formatDate(fechaNacimiento),
      'sexo': sexo,
      'telefono': telefono,
      'direccion': direccion,
      'nivel_educativo': nivelEducativo,
      'curso_seleccionado': cursoSeleccionado,
      'discapacidad': discapacidad,
      if (discapacidad && tipoDiscapacidad != null)
        'tipo_discapacidad': tipoDiscapacidad,
      if (numeroIdentidadTutor != null && numeroIdentidadTutor!.isNotEmpty)
        'numero_identidad_tutor': numeroIdentidadTutor,
      if (nombreTutor != null && nombreTutor!.isNotEmpty)
        'nombre_tutor': nombreTutor,
      if (parentescoTutor != null && parentescoTutor!.isNotEmpty)
        'parentesco_tutor': parentescoTutor,
      if (telefonoTutor != null && telefonoTutor!.isNotEmpty)
        'telefono_tutor': telefonoTutor,
      if (correoTutor != null && correoTutor!.isNotEmpty)
        'correo_tutor': correoTutor,
      if (datosPlanilla != null) 'datos_planilla': datosPlanilla,
    };
  }

  bool get esMenorDeEdad => _esMenorDeEdad(fechaNacimiento);

  String get nombreCompleto => '$nombres $apellidos';

  /// Lee `datos_planilla`, que puede llegar como mapa o como el texto JSON que
  /// devuelve PostgREST en algunas proyecciones.
  ///
  /// Un valor con otra forma se descarta en vez de reventar: la planilla es un
  /// dato accesorio de la ficha, y no poder leerla no debe impedir mostrar el
  /// aspirante.
  static PlanillaInscripcion? _parsePlanilla(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null || value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Formatea como `YYYY-MM-DD` sin depender de `intl`.
  static String? _formatDate(DateTime? value) {
    if (value == null) return null;
    final anio = value.year.toString().padLeft(4, '0');
    final mes = value.month.toString().padLeft(2, '0');
    final dia = value.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }

  /// Cálculo de mayoría de edad alineado con el CHECK de la base de datos:
  /// `fecha_nac > (current_date - interval '18 years')`.
  ///
  /// Es `static` **a propósito**: el formulario necesita preguntar lo mismo
  /// —para saber si los datos del representante legal son obligatorios— antes de
  /// que exista un [AspiranteModel], y la alternativa era una segunda copia de
  /// esta cuenta en la pantalla. Dos copias de una regla de edad se desvían en
  /// el borde exacto de los 18 años, que es justo donde importa.
  static bool esMenorDeEdadCon(DateTime? fechaNacimiento) =>
      _esMenorDeEdad(fechaNacimiento);

  static bool _esMenorDeEdad(DateTime? fechaNacimiento) {
    if (fechaNacimiento == null) return false;
    final hoy = DateTime.now();
    final edad = hoy.year - fechaNacimiento.year;
    final cumpleYaPaso = hoy.month > fechaNacimiento.month ||
        (hoy.month == fechaNacimiento.month && hoy.day >= fechaNacimiento.day);
    return edad - (cumpleYaPaso ? 0 : 1) < 18;
  }
}
