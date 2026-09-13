import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/services/auth_service.dart';

import 'support/fake_gateway.dart';

void main() {
  // ---------------------------------------------------------------------------
  // El flujo de restablecimiento cubre dos caminos que convergen en la misma
  // llamada: el enlace del correo (sesión temporal) y el cambio voluntario
  // desde dentro de la app. Ambos llegan a `actualizarPassword`.
  // ---------------------------------------------------------------------------
  group('AuthService.restablecerPassword · camino feliz', () {
    test('cambia la contraseña cuando hay sesión', () async {
      final fake = FakeGateway()..tieneSesion = true;

      final resultado = await AuthService(
        gateway: fake,
      ).restablecerPassword('contrasena-nueva-123');

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull, isTrue);
      expect(fake.llamadas, contains('actualizarPassword'));
    });

    test('la longitud mínima son 8 caracteres, no 7', () async {
      final fake = FakeGateway()..tieneSesion = true;

      final resultado = await AuthService(
        gateway: fake,
      ).restablecerPassword('1234567');

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.type, AppErrorType.validacion);
      // Falla rápido: no debe gastar una llamada de red.
      expect(fake.llamadas, isNot(contains('actualizarPassword')));
    });

    test('acepta exactamente 8 caracteres (borde inferior)', () async {
      final fake = FakeGateway()..tieneSesion = true;

      final resultado = await AuthService(
        gateway: fake,
      ).restablecerPassword('12345678');

      expect(resultado.isSuccess, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthService.restablecerPassword · sin sesión', () {
    test('sin sesión falla con mensaje de enlace caducado', () async {
      // Un enlace de recuperación caducado deja al usuario sin sesión. El
      // mensaje tiene que explicarlo: si dijera «credenciales inválidas» el
      // usuario pensaría que se equivocó al escribir, no que llegó tarde.
      final fake = FakeGateway()..tieneSesion = false;

      final resultado = await AuthService(
        gateway: fake,
      ).restablecerPassword('contrasena-nueva-123');

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.type, AppErrorType.credenciales);
      expect(
        resultado.errorOrNull?.message.toLowerCase(),
        contains('enlace'),
      );
      expect(fake.llamadas, isNot(contains('actualizarPassword')));
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthService.restablecerPassword · propagación de fallos', () {
    test('si el gateway falla, el error llega tipado', () async {
      final fake = FakeGateway()
        ..tieneSesion = true
        ..errorAlActualizarPassword = const AppException(
          type: AppErrorType.servidor,
          message: 'Supabase rechazó la operación.',
        );

      final resultado = await AuthService(
        gateway: fake,
      ).restablecerPassword('contrasena-nueva-123');

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.message, contains('rechazó'));
    });

    test('una contraseña de sólo espacios no cuenta como válida', () async {
      // 8 cadenas vacías miden 8, pero no son una contraseña. Sin esta guarda
      // el usuario podría fijar algo que no puede volver a teclear.
      final fake = FakeGateway()..tieneSesion = true;

      final resultado = await AuthService(
        gateway: fake,
      ).restablecerPassword('        ');

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.type, AppErrorType.validacion);
      expect(fake.llamadas, isNot(contains('actualizarPassword')));
    });
  });
}
