import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/auth_gateway.dart';
import 'package:inces_lms_app/models/aspirante_model.dart';
import 'package:inces_lms_app/providers/role_provider.dart';
import 'package:inces_lms_app/repositories/aspirante_repository.dart';
import 'package:inces_lms_app/services/auth_service.dart';

import 'support/fake_gateway.dart';

AspiranteModel _aspiranteValido() => AspiranteModel(
      nombres: 'Ana',
      apellidos: 'Pérez',
      cedula: '12345678',
      fechaNacimiento: DateTime(DateTime.now().year - 20, 1, 15),
      sexo: 'F',
      telefono: '04141234567',
      email: 'ana.perez@example.com',
      direccion: 'Calle Principal, casa 1',
      nivelEducativo: 'Secundario',
      cursoSeleccionado: 'Herrería',
    );

void main() {
  // ---------------------------------------------------------------------------
  group('AuthService.registrarAspirante · camino feliz', () {
    test('registra y devuelve la ficha creada con sesión iniciada', () async {
      final fake = FakeGateway()
        ..precheckResultado = 'OK'
        ..sesionRegistro = const SesionAuth(
          userId: 'uuid-123',
          tieneSesion: true,
        );

      final resultado = await AuthService(gateway: fake).registrarAspirante(
        aspirante: _aspiranteValido(),
        password: 'contrasena-valida',
      );

      final registro = resultado.valueOrNull;
      expect(resultado.isSuccess, isTrue);
      expect(registro, isNotNull);
      expect(registro!.userId, 'uuid-123');
      expect(registro.sesionIniciada, isTrue);
      expect(registro.requiereConfirmacionEmail, isFalse);
      // El trigger es atómico: si signUp no falló, la ficha existe.
      expect(registro.fichaCreada, isTrue);
      expect(registro.requiereTutorLegal, isFalse);
    });

    test(
      'con confirmación de correo activada informa que hay que confirmar',
      () async {
        final fake = FakeGateway()
          ..sesionRegistro = const SesionAuth(
            userId: 'uuid-456',
            tieneSesion: false,
          );

        final resultado = await AuthService(gateway: fake).registrarAspirante(
          aspirante: _aspiranteValido(),
          password: 'contrasena-valida',
        );

        expect(resultado.isSuccess, isTrue);
        expect(resultado.valueOrNull!.requiereConfirmacionEmail, isTrue);
      },
    );

    test('envía la metadata de la planilla al gateway', () async {
      final fake = FakeGateway();
      final aspirante = _aspiranteValido();

      await AuthService(gateway: fake).registrarAspirante(
        aspirante: aspirante,
        password: 'contrasena-valida',
      );

      // El gateway recibe la metadata; el detalle de su contenido ya está
      // cubierto en phase1_onboarding_test.dart.
      expect(fake.llamadas, contains('registrarConPassword'));
      expect(fake.llamadas.indexOf('precheck'),
          lessThan(fake.llamadas.indexOf('registrarConPassword')));
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthService.registrarAspirante · orden y fallos', () {
    test(
      'la validación local ocurre ANTES de tocar la red (no llama a precheck)',
      () async {
        final fake = FakeGateway();

        final resultado = await AuthService(gateway: fake).registrarAspirante(
          aspirante: _aspiranteValido(),
          password: '123', // demasiado corta
        );

        expect(resultado.isFailure, isTrue);
        expect(resultado.errorOrNull!.type, AppErrorType.validacion);
        expect(
          fake.llamadas,
          isEmpty,
          reason: 'No debe gastarse red si la planilla es inválida.',
        );
      },
    );

    test('cédula duplicada corta el flujo antes de crear la cuenta', () async {
      final fake = FakeGateway()..precheckResultado = 'CEDULA_DUPLICADA';

      final resultado = await AuthService(gateway: fake).registrarAspirante(
        aspirante: _aspiranteValido(),
        password: 'contrasena-valida',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.duplicado);
      expect(resultado.errorOrNull!.code, 'CEDULA_DUPLICADA');
      expect(
        fake.llamadas,
        isNot(contains('registrarConPassword')),
        reason: 'No debe crearse un usuario si la cédula ya está inscrita.',
      );
    });

    test('correo duplicado se distingue de la cédula', () async {
      final fake = FakeGateway()..precheckResultado = 'EMAIL_DUPLICADO';

      final resultado = await AuthService(gateway: fake).registrarAspirante(
        aspirante: _aspiranteValido(),
        password: 'contrasena-valida',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.duplicado);
      expect(resultado.errorOrNull!.code, 'EMAIL_DUPLICADO');
    });

    test('un código de precheck desconocido se trata como error de servidor',
        () async {
      final fake = FakeGateway()..precheckResultado = 'ALGO_RARO';

      final resultado = await AuthService(gateway: fake).registrarAspirante(
        aspirante: _aspiranteValido(),
        password: 'contrasena-valida',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.servidor);
    });

    test('un fallo de red en signUp se propaga como error de red', () async {
      final fake = FakeGateway()
        ..errorAlRegistrar = Exception('Failed to fetch');

      final resultado = await AuthService(gateway: fake).registrarAspirante(
        aspirante: _aspiranteValido(),
        password: 'contrasena-valida',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.red);
      expect(resultado.errorOrNull!.esRecuperable, isTrue);
    });

    test('si el gateway no devuelve usuario, es error de servidor', () async {
      final fake = FakeGateway()
        ..sesionRegistro = const SesionAuth(userId: null, tieneSesion: false);

      final resultado = await AuthService(gateway: fake).registrarAspirante(
        aspirante: _aspiranteValido(),
        password: 'contrasena-valida',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.servidor);
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthService.iniciarSesion', () {
    test('con correo devuelve el rol del perfil', () async {
      final fake = FakeGateway()
        ..rolDelPerfil = 'estudiante'
        ..tieneSesion = true;

      final resultado = await AuthService(gateway: fake).iniciarSesion(
        identificador: 'ana.perez@example.com',
        password: 'contrasena-valida',
      );

      expect(resultado.valueOrNull, UserRole.estudiante);
      expect(fake.llamadas, contains('iniciarConPassword'));
      expect(
        fake.llamadas,
        isNot(contains('emailPorCedula')),
        reason: 'Con correo no hace falta resolver la cédula.',
      );
    });

    test('con cédula resuelve el correo antes de autenticar', () async {
      final fake = FakeGateway()
        ..emailDeCedula = 'ana.perez@example.com'
        ..rolDelPerfil = 'docente';

      final resultado = await AuthService(gateway: fake).iniciarSesion(
        identificador: '12345678',
        password: 'contrasena-valida',
      );

      expect(resultado.valueOrNull, UserRole.docente);
      expect(
        fake.llamadas.indexOf('emailPorCedula'),
        lessThan(fake.llamadas.indexOf('iniciarConPassword')),
      );
    });

    test('una cédula inexistente da credenciales inválidas, sin revelar que '
        'no existe', () async {
      final fake = FakeGateway()..emailDeCedula = null;

      final resultado = await AuthService(gateway: fake).iniciarSesion(
        identificador: '99999999',
        password: 'contrasena-valida',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.credenciales);
      expect(
        fake.llamadas,
        isNot(contains('iniciarConPassword')),
        reason: 'No debe intentarse autenticar sin correo resuelto.',
      );
    });

    test('rechaza credenciales vacías sin llamar al gateway', () async {
      final fake = FakeGateway();

      final resultado = await AuthService(gateway: fake).iniciarSesion(
        identificador: '   ',
        password: '',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.validacion);
      expect(fake.llamadas, isEmpty);
    });

    test('credenciales inválidas de Supabase se traducen', () async {
      final fake = FakeGateway()
        ..errorAlIniciar = const AppException(
          type: AppErrorType.credenciales,
          message: 'Credenciales inválidas.',
        );

      final resultado = await AuthService(gateway: fake).iniciarSesion(
        identificador: 'ana@example.com',
        password: 'mala',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.credenciales);
    });
  });

  // ---------------------------------------------------------------------------
  group('AspiranteRepository · un fallo NUNCA se convierte en dato vacío', () {
    // Estas pruebas existen por el bug original: `catch (e) { return null; }`
    // hacía indistinguible "no hay datos" de "algo se rompió".

    test('si el gateway falla, obtenerTodos devuelve Failure (no lista vacía)',
        () async {
      final fake = FakeGateway()..errorAlListar = Exception('sin conexión');
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.obtenerTodos();

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull, isNotNull);
      expect(
        resultado.valueOrNull,
        isNull,
        reason: 'Un fallo no debe parecer una lista vacía legítima.',
      );
    });

    test('una lista vacía legítima es Success, no Failure', () async {
      final fake = FakeGateway()..fichas = const [];
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.obtenerTodos();

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull, isEmpty);
    });

    test('"no existe" es Success(null), distinto de un error', () async {
      final fake = FakeGateway()..ficha = null;
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.obtenerPorCedula('00000000');

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull, isNull);
      expect(resultado.errorOrNull, isNull);
    });

    test('el fallo del catálogo de cursos se expone para que la UI decida',
        () async {
      final fake = FakeGateway()..errorAlCursos = Exception('timeout');
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.obtenerCursosDisponibles();

      expect(resultado.isFailure, isTrue);
      // La UI usa `cursosRespaldo`, pero el fallo debe ser visible y reintentable.
      expect(AspiranteRepository.cursosRespaldo, isNotEmpty);
    });

    test('precheck propaga el error de red', () async {
      final fake = FakeGateway()..errorAlPrecheck = Exception('Failed to fetch');
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.precheck(
        cedula: '12345678',
        email: 'a@b.com',
      );

      expect(resultado.errorOrNull!.type, AppErrorType.red);
    });

    test('eliminar devuelve Success(true) cuando funciona', () async {
      final fake = FakeGateway();
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.eliminar('uuid-1');

      expect(resultado.valueOrNull, isTrue);
    });

    test('eliminar devuelve Failure cuando el gateway falla', () async {
      final fake = FakeGateway()..errorAlCrear = Exception('permiso denegado');
      final repo = AspiranteRepository(gateway: fake);

      final resultado = await repo.eliminar('uuid-1');

      expect(resultado.isFailure, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthService · utilidades', () {
    test('enviarCorreoRecuperacion valida el formato antes de llamar',
        () async {
      final fake = FakeGateway();

      final resultado =
          await AuthService(gateway: fake).enviarCorreoRecuperacion('no-es-correo');

      expect(resultado.errorOrNull!.type, AppErrorType.validacion);
      expect(fake.llamadas, isEmpty);
    });

    test('enviarCorreoRecuperacion llama al gateway con un correo válido',
        () async {
      final fake = FakeGateway();

      final resultado = await AuthService(gateway: fake)
          .enviarCorreoRecuperacion('ana@example.com');

      expect(resultado.valueOrNull, isTrue);
      expect(fake.llamadas, contains('enviarRecuperacion'));
    });

    test('vincularFichaPendiente nunca interrumpe el login', () async {
      final fake = FakeGateway()..errorAlVincular = Exception('boom');

      final reparado = await AuthService(gateway: fake).vincularFichaPendiente();

      expect(reparado, isFalse);
    });

    test('obtenerRolActual cae a la metadata si el perfil falla', () async {
      // Un gateway que responde en todo menos en `rolDePerfil`.
      final fake = _GatewayQueFallaEnPerfil()
        ..userId = 'user-9'
        ..rolMetadata = 'docente';

      final servicio = AuthService(gateway: fake);

      expect(await servicio.obtenerRolActual(), UserRole.docente);
    });
  });
}

/// Fuerza el fallo de `rolDePerfil` sobre un [FakeGateway].
///
/// Hereda en vez de implementar: así, si el contrato de [AuthGateway] gana un
/// método nuevo, este doble no se rompe ni hay que reimplementar el resto.
class _GatewayQueFallaEnPerfil extends FakeGateway {
  @override
  Future<String?> rolDePerfil(String userId) async =>
      throw Exception('perfil inaccesible');
}
