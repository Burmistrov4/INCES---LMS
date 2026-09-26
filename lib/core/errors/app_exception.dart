import 'package:supabase_flutter/supabase_flutter.dart';

/// Clasificación de errores del dominio.
///
/// Sirve para que la UI decida QUÉ hacer (reintentar, mostrar un campo en rojo,
/// pedir confirmación de correo) en lugar de mostrar un texto crudo de Postgres.
enum AppErrorType {
  /// Datos inválidos o incompletos (validación de negocio).
  validacion,

  /// Cédula o correo ya registrados.
  duplicado,

  /// Credenciales incorrectas en el login.
  credenciales,

  /// La cuenta existe pero el correo no está confirmado.
  correoNoConfirmado,

  /// La política de seguridad (RLS) impidió la operación.
  permisos,

  /// No se pudo alcanzar el servidor.
  red,

  /// El servidor falló o respondió algo inesperado.
  servidor,

  /// La base de datos no tiene el objeto que la app espera: falta una migración.
  ///
  /// **No es un error del usuario y reintentar no lo arregla**, y por eso tiene
  /// tipo propio en vez de caer en [servidor]: con `servidor` la UI ofrece
  /// «Reintentar» y el usuario pulsa un botón que **nunca** puede funcionar
  /// —el objeto seguirá faltando—. El arreglo es de despliegue, y el mensaje
  /// tiene que decir eso, no «algo salió mal».
  ///
  /// Códigos que llegan aquí, medidos contra la nube (2026-09-26):
  /// `PGRST205` (tabla ausente del schema cache, HTTP 404) y `42703` (columna
  /// ausente, HTTP 400). `42P01` es el de Postgres dentro de una función y lo
  /// traduce el backend a `ESQUEMA_DESACTUALIZADO`.
  esquemaDesactualizado,

  /// Cualquier otra cosa. Nunca debería llegar al usuario sin contexto.
  desconocido,
}

/// Error de aplicación con mensaje en español listo para mostrar.
///
/// Regla del proyecto: las capas de datos **lanzan** [AppException]; nunca
/// devuelven `null` para señalar un fallo. Un `null` debe significar
/// "no existe", jamás "algo salió mal".
class AppException implements Exception {
  final AppErrorType type;

  /// Mensaje para el usuario final, en español y accionable.
  final String message;

  /// Código crudo (Postgres, PostgREST o GoTrue). Útil en logs.
  final String? code;

  /// Detalle técnico. Para depurar, nunca para mostrar.
  final String? technical;

  const AppException({
    required this.type,
    required this.message,
    this.code,
    this.technical,
  });

  const AppException.validacion(String message, {String? code})
      : this(type: AppErrorType.validacion, message: message, code: code);

  const AppException.duplicado(String message, {String? code})
      : this(type: AppErrorType.duplicado, message: message, code: code);

  const AppException.red()
      : this(
          type: AppErrorType.red,
          message:
              'No pudimos conectar con el servidor. Verifica tu conexión a '
              'internet e inténtalo de nuevo.',
        );

  const AppException.servidor({String? code, String? technical})
      : this(
          type: AppErrorType.servidor,
          message:
              'Ocurrió un error en el servidor. Inténtalo de nuevo en unos '
              'momentos.',
          code: code,
          technical: technical,
        );

  const AppException.desconocido({String? technical})
      : this(
          type: AppErrorType.desconocido,
          message: 'Ocurrió un error inesperado. Inténtalo de nuevo.',
          technical: technical,
        );

  /// Traduce cualquier excepción de Supabase/red a un [AppException] tipado.
  factory AppException.from(Object error, {StackTrace? stackTrace}) {
    if (error is AppException) return error;

    if (error is PostgrestException) {
      return _fromPostgrest(error);
    }

    if (error is AuthException) {
      return _fromAuth(error);
    }

    final typeName = error.runtimeType.toString();
    final raw = error.toString();

    if (_looksLikeNetworkError(typeName, raw)) {
      return AppException(
        type: AppErrorType.red,
        message:
            'No pudimos conectar con el servidor. Verifica tu conexión a '
            'internet e inténtalo de nuevo.',
        technical: raw,
      );
    }

    return AppException.desconocido(technical: '$typeName: $raw');
  }

  /// ¿Tiene sentido que el usuario reintente la misma acción?
  ///
  /// `esquemaDesactualizado` es `false` por el mismo motivo que `permisos`:
  /// reintentar una consulta contra un objeto que la base no tiene da
  /// exactamente el mismo resultado. Ofrecer «Reintentar» ahí sería un botón
  /// que no puede funcionar, que es peor que no ofrecerlo.
  bool get esRecuperable =>
      type != AppErrorType.permisos &&
      type != AppErrorType.esquemaDesactualizado;

  static AppException _fromPostgrest(PostgrestException error) {
    final detail = '${error.message} ${error.details ?? ''}'.toLowerCase();
    final technical = 'PostgrestException(${error.code}): ${error.message}';

    // El catálogo se resuelve ANTES del `switch` y en su propia función, porque
    // sus mensajes no tienen nada que ver con los de inscripción. Ver el porqué
    // del orden en la documentación de `_desdeCatalogoInscripcion`.
    final delCatalogo = _desdeCatalogoInscripcion(error.code, detail, technical);
    if (delCatalogo != null) return delCatalogo;

    switch (error.code) {
      // 23502 = not_null_violation. Faltaba, y su ausencia se notaba: caía al
      // `servidor` del final y el usuario leía «No pudimos guardar la
      // información» por un campo que no rellenó — un mensaje que no le dice qué
      // hacer. `validacion` es la categoría correcta: el problema está en los
      // datos, no en el servidor, y `esRecuperable` sigue siendo `true`.
      case '23502': // not_null_violation
        return AppException(
          type: AppErrorType.validacion,
          message:
              'Faltó un dato obligatorio. Revisa el formulario e inténtalo de '
              'nuevo.',
          code: error.code,
          technical: technical,
        );

      case '23505': // unique_violation
        if (detail.contains('cedula') || detail.contains('cédula')) {
          return AppException(
            type: AppErrorType.duplicado,
            message: 'Ya existe una inscripción registrada con esa cédula.',
            code: error.code,
            technical: technical,
          );
        }
        if (detail.contains('email') || detail.contains('correo')) {
          return AppException(
            type: AppErrorType.duplicado,
            message: 'Ya existe una cuenta registrada con ese correo.',
            code: error.code,
            technical: technical,
          );
        }
        return AppException(
          type: AppErrorType.duplicado,
          message: 'Ese registro ya existe en el sistema.',
          code: error.code,
          technical: technical,
        );

      case '23514': // check_violation
        return AppException(
          type: AppErrorType.validacion,
          message:
              'Algunos datos no cumplen las reglas de inscripción del INCES. '
              'Revisa la fecha de nacimiento y los datos del representante.',
          code: error.code,
          technical: technical,
        );

      case '23503': // foreign_key_violation
        return AppException(
          type: AppErrorType.validacion,
          message: 'El registro hace referencia a datos que no existen.',
          code: error.code,
          technical: technical,
        );

      case '42501': // insufficient_privilege (RLS)
        return AppException(
          type: AppErrorType.permisos,
          message: 'No tienes permisos para realizar esta acción.',
          code: error.code,
          technical: technical,
        );

      case 'PGRST116': // 0 filas donde se esperaba 1
        return AppException(
          type: AppErrorType.validacion,
          message: 'No encontramos la información solicitada.',
          code: error.code,
          technical: technical,
        );

      // El objeto que la app espera no existe en la base. Medidos contra la nube
      // (2026-09-26, clave anónima):
      //   tabla ausente  → PGRST205, HTTP 404, «Could not find the table …»
      //   columna ausente → 42703,  HTTP 400, «column X.Y does not exist»
      //
      // Sin estas ramas los dos caían al `servidor` del final, que dice «No
      // pudimos guardar la información» —falso: aquí no se estaba guardando— y
      // además es `esRecuperable`, así que la UI invitaba a reintentar algo que
      // no puede cambiar. `42P01` es el de Postgres dentro de una función y lo
      // traduce el backend a `ESQUEMA_DESACTUALIZADO`, que el cliente recibe por
      // HTTP y clasifica en `ApiClient._clasificar`.
      case 'PGRST205':
      case '42703':
        return AppException(
          type: AppErrorType.esquemaDesactualizado,
          message:
              'Esta versión de la aplicación necesita una actualización del '
              'servidor que todavía no está aplicada. Avisa al administrador '
              'del centro.',
          code: error.code,
          technical: technical,
        );
    }

    return AppException(
      type: AppErrorType.servidor,
      message: 'No pudimos guardar la información. Inténtalo de nuevo.',
      code: error.code,
      technical: technical,
    );
  }

  /// Traduce los fallos propios del catálogo de la planilla de inscripción.
  ///
  /// **Corre antes que el `switch` genérico, y eso no es estilo: es corrección.**
  /// El detalle que da Postgres para una clave duplicada es
  /// `Key (codigo)=(email) already exists.`, así que un campo del catálogo
  /// llamado `email` haría saltar la rama del correo y el administrador leería
  /// «ya existe una cuenta registrada con ese correo» mientras intenta añadir un
  /// campo a la planilla. La firma específica tiene que ganarle a la genérica, y
  /// eso sólo se consigue comprobándola primero.
  ///
  /// `PGRST116` **no** pasa por aquí a propósito: su mensaje
  /// (`JSON object requested, multiple (or no) rows returned`) no nombra la
  /// tabla, así que no hay forma de distinguir un campo del catálogo que ya no
  /// existe de cualquier otra consulta sin filas. Cae al mensaje genérico, que
  /// es impreciso pero no miente. Se anota para que nadie lo «arregle» con una
  /// heurística que acertaría casi siempre.
  ///
  /// Devuelve `null` cuando el error no es del catálogo, y entonces manda el
  /// `switch` de siempre.
  static AppException? _desdeCatalogoInscripcion(
    String? code,
    String detail,
    String technical,
  ) {
    // El nombre de la tabla o del constraint es lo que identifica al catálogo.
    // Es estable: lo genera Postgres a partir del DDL, no de la consulta, así que
    // no cambia porque cambie la forma de preguntar.
    const tabla = 'inscripcion_campos';
    if (!detail.contains(tabla)) return null;

    switch (code) {
      case '23505': // unique_violation → el `codigo` ya está tomado
        return AppException(
          type: AppErrorType.duplicado,
          message: 'Ya existe un campo con ese código en el catálogo.',
          code: code,
          technical: technical,
        );

      case '23514': // check_violation
        if (detail.contains('inscripcion_campos_codigo_formato')) {
          return AppException(
            type: AppErrorType.validacion,
            message:
                'El código sólo admite minúsculas, números y guion bajo, y tiene '
                'que empezar por una letra.',
            code: code,
            technical: technical,
          );
        }
        return AppException(
          type: AppErrorType.validacion,
          message: 'El campo no cumple las reglas del catálogo de inscripción.',
          code: code,
          technical: technical,
        );

      case '42501': // insufficient_privilege → la RLS lo bloqueó
        return AppException(
          type: AppErrorType.permisos,
          message:
              'Sólo un administrador puede modificar el catálogo de '
              'inscripción.',
          code: code,
          technical: technical,
        );
    }

    return null;
  }

  static AppException _fromAuth(AuthException error) {
    final raw = error.message;
    final msg = raw.toLowerCase();

    if (msg.contains('invalid login credentials')) {
      return AppException(
        type: AppErrorType.credenciales,
        message:
            'Credenciales inválidas. Verifica tu cédula/correo y contraseña.',
        code: error.statusCode,
        technical: raw,
      );
    }

    if (msg.contains('email not confirmed')) {
      return AppException(
        type: AppErrorType.correoNoConfirmado,
        message:
            'Tu correo aún no ha sido confirmado. Revisa tu bandeja de entrada '
            'y la carpeta de spam.',
        code: error.statusCode,
        technical: raw,
      );
    }

    if (msg.contains('already registered') || msg.contains('already exists')) {
      return AppException(
        type: AppErrorType.duplicado,
        message: 'Ya existe una cuenta registrada con ese correo.',
        code: error.statusCode,
        technical: raw,
      );
    }

    if (msg.contains('password should be at least') ||
        msg.contains('password is too short')) {
      return AppException(
        type: AppErrorType.validacion,
        message: 'La contraseña es demasiado corta. Usa al menos 8 caracteres.',
        code: error.statusCode,
        technical: raw,
      );
    }

    if (msg.contains('rate limit') ||
        msg.contains('too many') ||
        msg.contains('over_email_send_rate_limit')) {
      return AppException(
        type: AppErrorType.servidor,
        message:
            'Demasiados intentos seguidos. Espera unos minutos e inténtalo de '
            'nuevo.',
        code: error.statusCode,
        technical: raw,
      );
    }

    // Caso clave: el trigger de PostgreSQL rechazó los datos (cédula duplicada
    // o constraint incumplido) y GoTrue devolvió un mensaje genérico. El
    // detalle real solo aparece en los logs de Supabase.
    if (msg.contains('database error saving new user') ||
        msg.contains('unexpected_failure') ||
        msg.contains('500')) {
      return AppException(
        type: AppErrorType.validacion,
        message:
            'No pudimos completar el registro. Verifica que la cédula no esté '
            'ya inscrita y que la fecha de nacimiento sea correcta.',
        code: error.statusCode,
        technical: raw,
      );
    }

    return AppException(
      type: AppErrorType.servidor,
      message: 'No pudimos completar la operación. Inténtalo de nuevo.',
      code: error.statusCode,
      technical: raw,
    );
  }

  /// Detección de red sin importar `dart:io`, porque el frontend también
  /// compila a Web y `SocketException` no existe allí.
  static bool _looksLikeNetworkError(String typeName, String raw) {
    const marcas = <String>[
      'socketexception',
      'clientexception',
      'failed to fetch',
      'xmlhttprequest',
      'connection closed',
      'connection refused',
      'network is unreachable',
      'timeout',
    ];
    final texto = '$typeName $raw'.toLowerCase();
    return marcas.any(texto.contains);
  }

  @override
  String toString() =>
      'AppException(type: $type, code: $code, message: $message)';
}
