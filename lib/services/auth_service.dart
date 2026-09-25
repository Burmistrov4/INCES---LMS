import '../core/errors/app_exception.dart';
import '../core/gateways/auth_gateway.dart';
import '../core/result.dart';
import '../models/aspirante_model.dart';
import '../models/registro_resultado.dart';
import '../providers/role_provider.dart';
import 'supabase_service.dart';

/// Reglas de autenticación y onboarding.
///
/// Depende de [AuthGateway], no del singleton de Supabase (deuda D1 resuelta).
/// Toda operación que pueda fallar devuelve `Result<T>` con un [AppException]
/// tipado. Nada se traga en silencio.
class AuthService {
  final AuthGateway _gateway;

  AuthService({AuthGateway? gateway})
      : _gateway = gateway ?? SupabaseService.instance;

  static const int _largoMinimoPassword = 8;

  // ---------------------------------------------------------------------------
  // Sesión
  // ---------------------------------------------------------------------------

  Future<UserRole> obtenerRolActual() async {
    final id = _gateway.userId;
    if (id == null) return UserRole.desconocido;

    try {
      final rol = await _gateway.rolDePerfil(id);
      if (rol != null && rol.isNotEmpty) return userRoleFromName(rol);
    } catch (_) {
      // Si la consulta falla (RLS, red), caemos a la metadata del token.
      // No es fatal: el rol se puede reconstruir desde la sesión.
    }

    return userRoleFromName(_gateway.rolMetadata);
  }

  bool get tieneSesion => _gateway.tieneSesion;

  /// Correo del usuario con sesión activa, o `null` si no hay sesión.
  ///
  /// Lo usa el cPanel para mostrar quién está conectado en lugar de un texto
  /// fijo. Un panel de administración que muestra un correo de ejemplo es una
  /// invitación a confundirse de cuenta.
  String? get emailActual => _gateway.userEmail;

  Stream<bool> get cambiosDeSesion => _gateway.cambiosDeSesion;

  Future<Result<UserRole>> iniciarSesion({
    required String identificador,
    required String password,
  }) {
    return Result.guard(() async {
      final identifier = identificador.trim();
      if (identifier.isEmpty || password.isEmpty) {
        throw const AppException.validacion(
          'Ingresa tu cédula/correo y tu contraseña.',
        );
      }

      var email = identifier;

      if (!identifier.contains('@')) {
        final encontrado = await _gateway.emailPorCedula(identifier);
        if (encontrado == null) {
          // Mensaje genérico a propósito: no revelamos si la cédula existe.
          throw const AppException(
            type: AppErrorType.credenciales,
            message: 'Credenciales inválidas. Verifica tus datos e inténtalo '
                'de nuevo.',
          );
        }
        email = encontrado;
      }

      await _gateway.iniciarConPassword(email: email, password: password);

      // Repara fichas huérfanas creadas por el bug anterior, si las hubiera.
      await vincularFichaPendiente();

      return obtenerRolActual();
    });
  }

  Future<void> cerrarSesion() async {
    await _gateway.cerrarSesion();
  }

  Future<Result<bool>> enviarCorreoRecuperacion(String email) {
    return Result.guard(() async {
      final correo = email.trim();
      if (!_esEmailValido(correo)) {
        throw const AppException.validacion('Ingresa un correo válido.');
      }
      await _gateway.enviarRecuperacion(correo);
      return true;
    });
  }

  /// Define una contraseña nueva para el usuario con sesión activa.
  ///
  /// Cubre los dos caminos del restablecimiento:
  ///
  ///  - El **enlace del correo de recuperación**. Supabase redirige con el token
  ///    en el fragmento de la URL; el SDK lo detecta al inicializarse y deja una
  ///    sesión temporal. Si el enlace caducó, no hay sesión y esta llamada
  ///    falla con un mensaje que lo explica, en lugar de fingir que funcionó.
  ///  - El **cambio voluntario** desde dentro de la app.
  ///
  /// La validación de longitud vive aquí y no en el widget: la regla es del
  /// dominio, y así los tests la cubren sin montar la interfaz.
  Future<Result<bool>> restablecerPassword(String password) {
    return Result.guard(() async {
      if (!_gateway.tieneSesion) {
        throw const AppException(
          type: AppErrorType.credenciales,
          message: 'El enlace ya no es válido. Solicita uno nuevo desde la '
              'pantalla de inicio de sesión.',
        );
      }

      if (password.length < _largoMinimoPassword) {
        throw const AppException.validacion(
          'La contraseña debe tener al menos 8 caracteres.',
        );
      }

      if (password.trim().isEmpty) {
        throw const AppException.validacion(
          'La contraseña no puede estar vacía.',
        );
      }

      await _gateway.actualizarPassword(password);
      return true;
    });
  }

  /// Nunca interrumpe el login: si falla, se ignora.
  Future<bool> vincularFichaPendiente() async {
    try {
      return await _gateway.vincularFichaPendiente();
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Registro de aspirantes (Fase 1)
  // ---------------------------------------------------------------------------

  /// Registra un aspirante de punta a punta.
  ///
  /// Flujo:
  ///  1. Valida los datos localmente (falla rápido, sin gastar red).
  ///  2. Prechequea cédula/correo duplicados contra la base de datos.
  ///  3. Llama a `signUp` con la metadata de la planilla.
  ///  4. El trigger `handle_new_user()` crea `profiles` + `aspirantes`
  ///     **en una sola transacción**. Si algo falla, Postgres revierte todo:
  ///     no queda usuario huérfano ni ficha a medias.
  Future<Result<RegistroResultado>> registrarAspirante({
    required AspiranteModel aspirante,
    required String password,
  }) {
    return Result.guard(() async {
      _validarPlanilla(aspirante, password);

      final precheck = await _gateway.precheck(
        cedula: aspirante.cedula,
        email: aspirante.email,
      );

      switch (precheck) {
        case 'OK':
          break;
        case 'CEDULA_DUPLICADA':
          throw const AppException.duplicado(
            'Ya existe una inscripción registrada con esa cédula.',
            code: 'CEDULA_DUPLICADA',
          );
        case 'EMAIL_DUPLICADO':
          throw const AppException.duplicado(
            'Ya existe una cuenta registrada con ese correo.',
            code: 'EMAIL_DUPLICADO',
          );
        case 'EMAIL_INVALIDO':
          throw const AppException.validacion(
            'El correo electrónico no tiene un formato válido.',
            code: 'EMAIL_INVALIDO',
          );
        case 'CEDULA_REQUERIDA':
          throw const AppException.validacion(
            'La cédula es obligatoria para completar la inscripción.',
            code: 'CEDULA_REQUERIDA',
          );
        default:
          throw AppException.servidor(
            technical: 'Código de precheck desconocido: $precheck',
          );
      }

      final sesion = await _gateway.registrarConPassword(
        email: aspirante.email,
        password: password,
        metadata: aspirante.toMetadata(),
      );

      if (sesion.userId == null) {
        throw const AppException(
          type: AppErrorType.servidor,
          message: 'No pudimos crear tu cuenta. Verifica tus datos e inténtalo '
              'de nuevo.',
        );
      }

      return RegistroResultado(
        email: aspirante.email,
        userId: sesion.userId,
        sesionIniciada: sesion.tieneSesion,
        // El trigger es atómico: si signUp no lanzó, la ficha existe.
        fichaCreada: true,
        requiereTutorLegal: aspirante.requiresLegalTutor,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Validaciones locales
  // ---------------------------------------------------------------------------

  void _validarPlanilla(AspiranteModel a, String password) {
    if (password.length < _largoMinimoPassword) {
      throw const AppException.validacion(
        'La contraseña debe tener al menos 8 caracteres.',
      );
    }

    final faltantes = <String>[
      if (a.cedula.trim().isEmpty) 'cédula',
      if (a.nombres.trim().isEmpty) 'nombres',
      if (a.apellidos.trim().isEmpty) 'apellidos',
      if (a.fechaNacimiento == null) 'fecha de nacimiento',
      if (a.sexo.trim().isEmpty) 'sexo',
      if (a.telefono.trim().isEmpty) 'teléfono',
      if (!_esEmailValido(a.email)) 'correo electrónico',
      if (a.direccion.trim().isEmpty) 'domicilio',
      if (a.nivelEducativo.trim().isEmpty) 'nivel educativo',
      if (a.programId.trim().isEmpty) 'propuesta formativa',
    ];

    if (faltantes.isNotEmpty) {
      throw AppException.validacion(
        'Faltan datos obligatorios: ${faltantes.join(', ')}.',
      );
    }

    if (!const ['M', 'F', 'Otro'].contains(a.sexo)) {
      throw const AppException.validacion('El sexo seleccionado no es válido.');
    }

    // Un menor de edad sin representante legal no puede inscribirse: el CHECK
    // de la base de datos lo rechazaría igual, pero aquí damos un mensaje claro.
    if (a.requiresLegalTutor) {
      final faltantesTutor = <String>[
        if ((a.numeroIdentidadTutor ?? '').trim().isEmpty)
          'cédula del representante',
        if ((a.nombreTutor ?? '').trim().isEmpty) 'nombre del representante',
        if ((a.parentescoTutor ?? '').trim().isEmpty)
          'parentesco del representante',
        if ((a.telefonoTutor ?? '').trim().isEmpty)
          'teléfono del representante',
        if ((a.correoTutor ?? '').trim().isEmpty) 'correo del representante',
      ];

      if (faltantesTutor.isNotEmpty) {
        throw AppException.validacion(
          'El aspirante es menor de edad y falta: ${faltantesTutor.join(', ')}.',
        );
      }
    }
  }

  static bool _esEmailValido(String value) {
    final texto = value.trim();
    if (texto.isEmpty) return false;
    return RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(texto);
  }
}
