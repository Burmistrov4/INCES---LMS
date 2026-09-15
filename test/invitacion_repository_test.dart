import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/invitacion_gateway.dart';
import 'package:inces_lms_app/models/invitacion_docente.dart';
import 'package:inces_lms_app/repositories/invitacion_repository.dart';

/// Doble del gateway: no toca la red ni Supabase, así el test corre en el VM de
/// `flutter test` sin dispositivo ni credenciales.
class _GatewayFalso implements InvitacionGateway {
  bool lanzar = false;
  String? tokenRecibido;
  String? passwordRecibido;

  @override
  Future<InvitacionDocente> invitarDocente(String email, String nombres, String apellidos) async {
    if (lanzar) throw const AppException.validacion('error simulado');
    return InvitacionDocente(
      email: email,
      expiraEn: '2026-01-01T00:00:00.000Z',
      enlaceActivacion: 'https://app/#/auth/activate?token=abc',
      correoEnviado: true,
    );
  }

  @override
  Future<ActivacionCuenta> activarCuenta({
    required String token,
    required String password,
  }) async {
    tokenRecibido = token;
    passwordRecibido = password;
    return const ActivacionCuenta(email: 'd@x.com', rol: 'docente');
  }
}

void main() {
  group('InvitacionRepository', () {
    test('rechaza correo vacío', () async {
      final repo = InvitacionRepository(gateway: _GatewayFalso());
      final r = await repo.invitarDocente('  ', 'N', 'A');
      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.validacion);
    });

    test('rechaza formato de correo inválido', () async {
      final repo = InvitacionRepository(gateway: _GatewayFalso());
      final r = await repo.invitarDocente('no-es-correo', 'N', 'A');
      expect(r.isFailure, isTrue);
    });

    test('invita con correo válido', () async {
      final repo = InvitacionRepository(gateway: _GatewayFalso());
      final r = await repo.invitarDocente('profesor@inces.gob.ve', 'José', 'Pérez');
      expect(r.isSuccess, isTrue);
      expect(r.valueOrNull?.correoEnviado, isTrue);
    });

    test('propaga el error del gateway como Failure', () async {
      final g = _GatewayFalso()..lanzar = true;
      final repo = InvitacionRepository(gateway: g);
      final r = await repo.invitarDocente('profesor@inces.gob.ve', 'José', 'Pérez');
      expect(r.isFailure, isTrue);
    });

    test('activar pasa token y password al gateway', () async {
      final g = _GatewayFalso();
      final repo = InvitacionRepository(gateway: g);
      final r = await repo.activarCuenta(token: 'tok', password: 'secreto12');
      expect(r.isSuccess, isTrue);
      expect(g.tokenRecibido, 'tok');
      expect(g.passwordRecibido, 'secreto12');
    });
  });
}
