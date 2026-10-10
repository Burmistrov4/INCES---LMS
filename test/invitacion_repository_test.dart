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

  /// Estado del doble para las pruebas del ciclo de vida.
  List<InvitacionListada> listado = const [];
  String? revocadoId;
  String? renovadoId;

  @override
  Future<List<InvitacionListada>> listarInvitaciones() async {
    if (lanzar) throw const AppException.validacion('error simulado');
    return listado;
  }

  @override
  Future<void> revocarInvitacion(String id) async {
    if (lanzar) throw const AppException.validacion('error simulado');
    revocadoId = id;
  }

  @override
  Future<InvitacionDocente> renovarInvitacion(String id) async {
    if (lanzar) throw const AppException.validacion('error simulado');
    renovadoId = id;
    return InvitacionDocente(
      email: 'docente@inces.test',
      expiraEn: '2026-01-01T00:00:00.000Z',
      enlaceActivacion: 'https://app/#/auth/activate?token=nuevo',
      correoEnviado: false,
    );
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
