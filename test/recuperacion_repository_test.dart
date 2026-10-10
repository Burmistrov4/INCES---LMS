import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/recuperacion_gateway.dart';
import 'package:inces_lms_app/models/recuperacion_password.dart';
import 'package:inces_lms_app/repositories/recuperacion_repository.dart';

/// Doble del gateway: sin red ni Supabase, corre en el VM de `flutter test`.
class _GatewayFalso implements RecuperacionGateway {
  bool lanzar = false;
  String? usuarioIdRecibido;
  String? codigoRecibido;
  String? passwordRecibida;

  @override
  Future<CodigoRecuperacion> emitirCodigo(String usuarioId) async {
    if (lanzar) throw const AppException.validacion('error simulado');
    usuarioIdRecibido = usuarioId;
    return const CodigoRecuperacion(
      email: 'alumno@inces.test',
      codigo: 'ABCD-EFGH-JKMN',
      expiraEn: '2026-01-01T00:30:00.000Z',
      entrega: 'manual',
    );
  }

  @override
  Future<bool> canjearCodigo({
    required String codigo,
    required String password,
  }) async {
    if (lanzar) throw const AppException.validacion('error simulado');
    codigoRecibido = codigo;
    passwordRecibida = password;
    return true;
  }
}

void main() {
  group('RecuperacionRepository', () {
    test('un código demasiado corto no llega al gateway', () async {
      final gateway = _GatewayFalso();
      final repo = RecuperacionRepository(gateway: gateway);

      final r = await repo.canjearCodigo(codigo: 'AB-12', password: 'clave12345');

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.validacion);
      expect(gateway.codigoRecibido, isNull);
    });

    test('una contraseña corta no llega al gateway', () async {
      final gateway = _GatewayFalso();
      final repo = RecuperacionRepository(gateway: gateway);

      final r = await repo.canjearCodigo(codigo: 'ABCD-EFGH-JKMN', password: 'corta');

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.validacion);
      expect(gateway.passwordRecibida, isNull);
    });

    test('normaliza el código antes de enviarlo', () async {
      final gateway = _GatewayFalso();
      final repo = RecuperacionRepository(gateway: gateway);

      // Tal como lo teclea una persona: en minúsculas, con espacios y guiones.
      final r = await repo.canjearCodigo(
        codigo: '  abcd efgh-jkmn  ',
        password: 'clave12345',
      );

      expect(r.isSuccess, isTrue);
      // Sin espacios, sin guiones y en mayúsculas: la misma forma con la que el
      // backend calcula el hash, para que las dos partes coincidan.
      expect(gateway.codigoRecibido, 'ABCDEFGHJKMN');
      expect(gateway.passwordRecibida, 'clave12345');
    });

    test('un usuario vacío no llega al gateway', () async {
      final gateway = _GatewayFalso();
      final repo = RecuperacionRepository(gateway: gateway);

      final r = await repo.emitirCodigo('   ');

      expect(r.isFailure, isTrue);
      expect(gateway.usuarioIdRecibido, isNull);
    });

    test('emite el código para el usuario indicado y lo devuelve', () async {
      final gateway = _GatewayFalso();
      final repo = RecuperacionRepository(gateway: gateway);

      final r = await repo.emitirCodigo('22222222-2222-2222-2222-222222222222');

      expect(r.isSuccess, isTrue);
      expect(gateway.usuarioIdRecibido, '22222222-2222-2222-2222-222222222222');
      expect(r.valueOrNull?.codigo, 'ABCD-EFGH-JKMN');
      expect(r.valueOrNull?.entrega, 'manual');
    });

    test('un fallo del gateway se convierte en Failure, no en excepción', () async {
      final gateway = _GatewayFalso()..lanzar = true;
      final repo = RecuperacionRepository(gateway: gateway);

      final r = await repo.canjearCodigo(codigo: 'ABCD-EFGH-JKMN', password: 'clave12345');

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.message, 'error simulado');
    });
  });
}
