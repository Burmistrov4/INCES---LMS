import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/inscripcion.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';

import 'support/fake_inscripcion_gateway.dart';

/// Capa 1 (datos) del Módulo 4: el repositorio envuelve el gateway en [Result]
/// y no disfraza un fallo de validación como un error de servidor.
void main() {
  group('InscripcionesRepository (estudiante)', () {
    test('obtenerOfertas envuelve la lista en Success', () async {
      final g = FakeInscripcionGateway()
        ..ofertasDevueltas = [
          ocupacionSeccionEjemplo(id: 'a'),
          ocupacionSeccionEjemplo(id: 'b'),
        ];
      final repo = InscripcionesRepository(gateway: g);

      final r = await repo.obtenerOfertas();

      final lista = r.when(success: (v) => v, failure: (_) => const <OcupacionSeccion>[]);
      expect(lista, hasLength(2));
      expect(g.llamadas, contains('obtenerOfertas'));
    });

    test('obtenerMisInscripciones envuelve la lista en Success', () async {
      final g = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [inscripcionDetalladaEjemplo()];
      final repo = InscripcionesRepository(gateway: g);

      final r = await repo.obtenerMisInscripciones();

      final lista =
          r.when(success: (v) => v, failure: (_) => const <InscripcionDetallada>[]);
      expect(lista, hasLength(1));
    });

    test('inscribirse delega la sección y devuelve el estado', () async {
      final g = FakeInscripcionGateway()
        ..inscritoDevuelto = EstadoInscripcion.waitlisted;
      final repo = InscripcionesRepository(gateway: g);

      final r = await repo.inscribirse('sec-42');

      final estado = r.when(success: (v) => v, failure: (_) => null);
      expect(estado, EstadoInscripcion.waitlisted);
      expect(g.ultimaSeccion, 'sec-42');
    });

    test('inscribirse traduce un fallo del gateway a Failure', () async {
      final g = FakeInscripcionGateway()
        ..errorAlInscribirse = const AppException.servidor();
      final repo = InscripcionesRepository(gateway: g);

      final r = await repo.inscribirse('sec-42');

      expect(r.isFailure, isTrue);
    });

    test('renunciar y aceptarOferta envuelven en Success', () async {
      final g = FakeInscripcionGateway();
      final repo = InscripcionesRepository(gateway: g);

      final ren = await repo.renunciar('sec-1');
      final acep = await repo.aceptarOferta('sec-1');

      expect(ren.isFailure, isFalse);
      expect(acep.isFailure, isFalse);
      expect(g.llamadas, contains('renunciar:sec-1'));
      expect(g.llamadas, contains('aceptarOferta:sec-1'));
    });
  });

  group('AdminInscripcionesRepository (administrador)', () {
    test('obtenerOcupacion envuelve la lista en Success', () async {
      final g = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo()];
      final repo = AdminInscripcionesRepository(gateway: g);

      final r = await repo.obtenerOcupacion();

      final lista = r.when(success: (v) => v, failure: (_) => const <OcupacionSeccion>[]);
      expect(lista, hasLength(1));
      expect(g.llamadas, contains('obtenerOcupacion'));
    });

    test('promoverSiguiente devuelve Success con la inscripción promovida', () async {
      final g = FakeInscripcionGateway()
        ..promovidaDevuelta = inscripcionDetalladaEjemplo(seccionId: 'sec-7');
      final repo = AdminInscripcionesRepository(gateway: g);

      final r = await repo.promoverSiguiente('sec-7');

      final promovida = r.when(success: (v) => v, failure: (_) => null);
      expect(promovida, isNotNull);
      expect(promovida?.seccionId, 'sec-7');
      expect(g.llamadas, contains('promoverSiguiente:sec-7'));
    });

    test('promoverSiguiente con cola vacía es Failure de VALIDACIÓN, no de servidor',
        () async {
      // El backend no promueve a nadie (sección llena o con oferta en el aire)
      // y el gateway lanza. La UI debe mostrarlo como aviso de negocio, no como
      // un fallo técnico disfrazado.
      final g = FakeInscripcionGateway()
        ..errorAlPromover = const AppException.validacion('No hay nadie en la cola.');
      final repo = AdminInscripcionesRepository(gateway: g);

      final r = await repo.promoverSiguiente('sec-7');

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.validacion);
    });

    test('expirarOfertas es idempotente: segunda llamada devuelve 0', () async {
      final g = FakeInscripcionGateway()..expirarSecuencia = [3, 0];
      final repo = AdminInscripcionesRepository(gateway: g);

      final primera = await repo.expirarOfertas();
      final segunda = await repo.expirarOfertas();

      expect(primera.when(success: (v) => v, failure: (_) => -1), 3);
      expect(segunda.when(success: (v) => v, failure: (_) => -1), 0);
    });

    test('reincorporar delega ids y envuelve en Success', () async {
      final g = FakeInscripcionGateway();
      final repo = AdminInscripcionesRepository(gateway: g);

      final r = await repo.reincorporar(estudianteId: 'est-9', seccionId: 'sec-9');

      expect(r.isFailure, isFalse);
      expect(g.ultimoEstudiante, 'est-9');
      expect(g.ultimaSeccion, 'sec-9');
    });

    test('reincorporar traduce un fallo del gateway a Failure', () async {
      final g = FakeInscripcionGateway()
        ..errorAlReincorporar = const AppException(
          type: AppErrorType.permisos,
          message: 'No tienes permisos para realizar esta acción.',
        );
      final repo = AdminInscripcionesRepository(gateway: g);

      final r = await repo.reincorporar(estudianteId: 'est-9', seccionId: 'sec-9');

      expect(r.isFailure, isTrue);
    });
  });
}
