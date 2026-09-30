import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';

/// El alta que el servidor rechaza **después** de que los datos ya pasaron la
/// validación del formulario.
///
/// El caso no se inventó: se midió el 2026-09-29 contra la nube, enviando el
/// formulario real y **leyendo el cuerpo de la respuesta**, que es lo que nunca
/// se había hecho.
///
/// ```
/// POST /auth/v1/signup → HTTP 500
/// {"code":500,"error_code":"unexpected_failure",
///  "msg":"Error sending confirmation email"}
/// ```
///
/// GoTrue **revierte el alta entera** cuando no puede enviar el correo de
/// confirmación. `auth.users` no crece, así que el fallo se parece a un problema
/// de los datos del formulario —que es justo lo que la aplicación decía:
/// «verifica que la cédula no esté ya inscrita y que la fecha de nacimiento sea
/// correcta»— y no lo era.
///
/// Se prueba contra la **forma real** del error, y con la clase real de gotrue
/// en lugar de un doble, porque lo que se verifica es que un 500 llegue a esta
/// rama. Un `AuthException` fabricado probaría que el `catch` funciona, no que
/// la rama sea alcanzable — y si la rama no se alcanza, la traducción **no
/// falla**: cae al mensaje genérico y nadie se entera.
void main() {
  /// Un 500 tal como lo lanza el SDK.
  ///
  /// `gotrue/lib/src/fetch.dart`, rama `statusCode >= 500`: lanza
  /// `AuthRetryableFetchException(message: response.body, statusCode: …)`. O
  /// sea, el mensaje es el **cuerpo entero** y `code` queda **sin poner** — por
  /// eso la razón real hay que sacarla del JSON, y por eso los códigos del enum
  /// `ErrorCode` no sirven para este caso.
  AppException desde500(String cuerpo) => AppException.from(
        AuthRetryableFetchException(message: cuerpo, statusCode: '500'),
      );

  const cuerpoCorreo =
      '{"code":500,"error_code":"unexpected_failure",'
      '"msg":"Error sending confirmation email"}';

  group('500 al enviar el correo de confirmación', () {
    test('es un fallo del servidor, no de los datos del aspirante', () {
      final error = desde500(cuerpoCorreo);

      expect(error.type, AppErrorType.servidor);
      expect(error.code, '500');
    });

    test('el mensaje NO manda a revisar la cédula ni la fecha de nacimiento', () {
      // Éste es el defecto que se está arreglando. La rama anterior afirmaba dos
      // cosas que nadie había medido —cédula duplicada, fecha de nacimiento
      // incorrecta— y mandaba al aspirante a buscar un error en sus datos que no
      // existía. Medido después: el disparador de PostgreSQL resultó inocente.
      final mensaje = desde500(cuerpoCorreo).message.toLowerCase();

      expect(mensaje, isNot(contains('cédula')));
      expect(mensaje, isNot(contains('cedula')));
      expect(mensaje, isNot(contains('fecha de nacimiento')));
    });

    test('el mensaje dice que el problema es el correo del centro', () {
      final mensaje = desde500(cuerpoCorreo).message.toLowerCase();

      expect(mensaje, contains('correo'));
      expect(mensaje, contains('no de tus datos'));
      expect(mensaje, contains('administrador'));
    });

    test('el cuerpo crudo se conserva en `technical`, no se pierde', () {
      // Es la única copia de la causa real que el cliente llega a tener: el
      // detalle no está en ningún log que el usuario pueda ver. Si se tira, el
      // fallo vuelve a ser ilegible desde fuera, que es lo que costó una sesión
      // entera de diagnóstico equivocado.
      expect(desde500(cuerpoCorreo).technical, cuerpoCorreo);
    });

    test('es recuperable: reintentar tiene sentido cuando el correo vuelva', () {
      expect(desde500(cuerpoCorreo).esRecuperable, isTrue);
    });
  });

  group('500 que no nombra el correo', () {
    test('el disparador rechazó la fila: validación, y sin ordenar nada', () {
      final error = desde500(
        '{"code":500,"error_code":"unexpected_failure",'
        '"msg":"Database error saving new user"}',
      );

      expect(error.type, AppErrorType.validacion);
      // **No se puede afirmar QUÉ campo falló**: GoTrue reduce el fallo del
      // disparador a esa frase y el detalle sólo existe en los logs del
      // servidor. La cédula se menciona como posibilidad —es la causa más
      // probable de un rechazo ahí—, pero el mensaje ya no **ordena** verificar
      // nada, que era lo que mandaba al aspirante a cazar un error inexistente.
      expect(error.message.toLowerCase(), isNot(contains('verifica')));
      expect(error.technical, contains('Database error saving new user'));
    });

    test('un 500 sin razón reconocible sigue siendo `servidor` y honesto', () {
      final error = desde500('{"code":500,"error_code":"unexpected_failure"}');

      expect(error.type, AppErrorType.servidor);
      expect(
        error.message.toLowerCase(),
        contains('no tienen por qué estar mal'),
      );
    });

    test('un cuerpo que empieza por llave y no es JSON no rompe el mapeo', () {
      // El ayudante que saca la razón no puede convertir un error en otro peor:
      // si el cuerpo no es JSON, se sigue con el texto crudo en lugar de
      // sustituir el error original por un `FormatException`.
      final error = desde500('{esto no es json}');

      expect(error.type, AppErrorType.servidor);
      expect(error.technical, '{esto no es json}');
    });
  });

  group('las ramas que ya funcionaban no se tragan', () {
    // Regresión: el cambio tocó la cabecera de `_fromAuth` —de dónde sale la
    // cadena contra la que se compara—, así que hay que comprobar que las
    // traducciones anteriores siguen respondiendo.
    //
    // La forma es la que gotrue produce de verdad para un error 4xx:
    // `AuthApiException(_getErrorMessage(data), statusCode: …, code: errorCode)`,
    // o sea el `msg` ya extraído y el `error_code` en `code`.
    AppException desdeApi(String mensaje, {String? codigo}) => AppException.from(
          AuthApiException(mensaje, statusCode: '400', code: codigo),
        );

    test('credenciales inválidas', () {
      expect(
        desdeApi('Invalid login credentials').type,
        AppErrorType.credenciales,
      );
    });

    test('correo sin confirmar', () {
      expect(
        desdeApi('Email not confirmed', codigo: 'email_not_confirmed').type,
        AppErrorType.correoNoConfirmado,
      );
    });

    test('cuenta ya registrada', () {
      expect(
        desdeApi('User already registered', codigo: 'user_already_exists').type,
        AppErrorType.duplicado,
      );
    });

    test('contraseña demasiado corta', () {
      final error = desdeApi('Password should be at least 6 characters');

      expect(error.type, AppErrorType.validacion);
      expect(error.message, contains('contraseña'));
    });

    test('demasiados intentos seguidos', () {
      final error = desdeApi('Email rate limit exceeded');

      expect(error.type, AppErrorType.servidor);
      expect(error.message, contains('intentos'));
    });

    test('un mensaje suelto que no coincide con nada cae al genérico', () {
      // El contraste que impide que las ramas nuevas se coman lo que no es
      // suyo: un texto normal no es JSON y no debe activar ninguna.
      final error = desdeApi('Something completely unexpected happened');

      expect(error.type, AppErrorType.servidor);
      expect(error.message, contains('Inténtalo de nuevo'));
    });
  });
}
