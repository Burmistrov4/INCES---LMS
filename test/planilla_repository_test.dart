import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/repositories/planilla_repository.dart';

import 'support/fake_planilla_gateway.dart';

/// El repositorio de la planilla: envuelve el gateway en `Result` y **no
/// disfraza un fallo de lista vacía**.
///
/// La distinción importa más aquí que en ningún otro repositorio: un catálogo
/// que no se pudo leer y un catálogo vacío producen la misma pantalla —un
/// formulario sin campos— y sólo el `Result` los separa. Si el fallo se
/// convirtiera en una lista vacía, el aspirante vería un formulario en blanco
/// sin saber que el problema era la red.
void main() {
  group('PlanillaRepository.obtenerCatalogo', () {
    test('devuelve el catálogo del gateway', () async {
      final gateway = FakePlanillaGateway()
        ..catalogo = CatalogoInscripcion([
          const CampoInscripcion(
            codigo: 'cedula',
            etiqueta: 'Cédula',
            grupo: 'Datos personales',
            tipo: TipoCampoInscripcion.texto,
            orden: 60,
            obligatorio: true,
          ),
        ]);
      final repo = PlanillaRepository(gateway: gateway);

      final resultado = await repo.obtenerCatalogo();

      final catalogo = resultado.when(
        success: (v) => v,
        failure: (_) => const CatalogoInscripcion([]),
      );
      expect(catalogo.campos, hasLength(1));
      expect(catalogo.porCodigo('cedula')?.etiqueta, 'Cédula');
      expect(gateway.llamadas, contains('campos'));
    });

    test('un fallo del gateway es Failure, no una lista vacía', () async {
      final gateway = FakePlanillaGateway()
        ..errorAlLeerCatalogo = const AppException.servidor();
      final repo = PlanillaRepository(gateway: gateway);

      final resultado = await repo.obtenerCatalogo();

      expect(resultado.isFailure, isTrue);
    });

    test('conserva el código del error, para poder distinguir 503 de 404', () async {
      final gateway = FakePlanillaGateway()
        ..errorAlLeerCatalogo = const AppException(
          type: AppErrorType.servidor,
          message: 'El servicio no está disponible.',
          code: 'SERVICIO_NO_DISPONIBLE',
        );
      final repo = PlanillaRepository(gateway: gateway);

      final resultado = await repo.obtenerCatalogo();

      final error = resultado.when(success: (_) => null, failure: (e) => e);
      expect(error?.code, 'SERVICIO_NO_DISPONIBLE');
    });
  });

  group('PlanillaRepository.guardar', () {
    test('delega la planilla entera y devuelve lo guardado', () async {
      final gateway = FakePlanillaGateway()
        ..planillaGuardada = const {'cedula': '123', 'nombres': 'Lorenzo'};
      final repo = PlanillaRepository(gateway: gateway);

      final resultado = await repo.guardar(const {'cedula': '123'});

      final guardada = resultado.when(success: (v) => v, failure: (_) => <String, dynamic>{});
      expect(guardada['nombres'], 'Lorenzo');
      expect(gateway.ultimaPlanilla, const {'cedula': '123'});
    });

    test('un fallo de validación llega como Failure con su código', () async {
      // `PLANILLA_INCOMPLETA` es el 400 que nombra los campos que faltan: el
      // código tiene que sobrevivir al repositorio porque la pantalla lo usa
      // para llevar al aspirante al paso donde está el campo que falta.
      final gateway = FakePlanillaGateway()
        ..errorAlGuardar = const AppException(
          type: AppErrorType.validacion,
          message: 'Faltan campos obligatorios en la planilla: cedula.',
          code: 'PLANILLA_INCOMPLETA',
        );
      final repo = PlanillaRepository(gateway: gateway);

      final resultado = await repo.guardar(const {'cedula': ''});

      final error = resultado.when(success: (_) => null, failure: (e) => e);
      expect(error?.code, 'PLANILLA_INCOMPLETA');
      expect(error?.message, contains('cedula'));
    });

    test('un fallo de permisos no se convierte en éxito', () async {
      final gateway = FakePlanillaGateway()
        ..errorAlGuardar = const AppException(
          type: AppErrorType.permisos,
          message: 'Falta la sesión.',
          code: 'NO_AUTENTICADO',
        );
      final repo = PlanillaRepository(gateway: gateway);

      final resultado = await repo.guardar(const {'cedula': '123'});

      expect(resultado.isFailure, isTrue);
    });
  });
}
