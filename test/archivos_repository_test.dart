import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/archivo.dart';
import 'package:inces_lms_app/repositories/archivos_repository.dart';

import 'support/fake_archivos_gateway.dart';

/// Capa de datos de M5: el repositorio envuelve el gateway en [Result].
///
/// Aquí no se prueba el transporte —eso es `archivos_gateway_test.dart`, con el
/// `http.Client` doblado— sino el contrato del repositorio: que un fallo llegue
/// como `Failure` **con su código y su tipo**, y que no se confunda con un éxito
/// vacío. Un `Failure` con `ARCHIVO_DEMASIADO_GRANDE` y otro con un fallo de red
/// llevan a la UI a sitios distintos.
void main() {
  group('subir', () {
    test('envuelve el archivo confirmado en Success', () async {
      final g = FakeArchivosGateway()
        ..archivoConfirmadoDevuelto = archivoEjemplo(
          estado: EstadoArchivo.confirmed,
          tamanoBytes: 2048,
          confirmadoEn: '2026-09-18T12:00:05.000Z',
        );
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.subir(
        nombreOriginal: 'Constancia José.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
        contenido: const [1, 2, 3],
      );

      final archivo = r.when(success: (v) => v, failure: (_) => null);
      expect(archivo, isNotNull);
      expect(archivo!.estado, EstadoArchivo.confirmed);
      expect(archivo.tamanoBytes, 2048);
      expect(g.llamadas, contains('subir:Constancia José.pdf'));
      expect(g.ultimoEntityType, TipoEntidadArchivo.taskSubmission);
    });

    test('delega la entidad cuando el archivo pertenece a una tarea', () async {
      final g = FakeArchivosGateway();
      final repo = ArchivosRepository(gateway: g);

      await repo.subir(
        nombreOriginal: 'entrega.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
        contenido: const [1],
        entidadId: 'tarea-7',
      );

      expect(g.ultimaEntidadId, 'tarea-7');
    });

    test('un 413 llega como Failure de VALIDACIÓN con su código', () async {
      // Es el caso que la UI tiene que saber contar: «tu archivo pesa demasiado,
      // sube otro», no «el servidor falló».
      final g = FakeArchivosGateway()
        ..errorAlSubir = const AppException.validacion(
          'El contenido supera el tamaño máximo permitido.',
          code: 'ARCHIVO_DEMASIADO_GRANDE',
        );
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.subir(
        nombreOriginal: 'enorme.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
        contenido: const [1],
      );

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.validacion);
      expect(r.errorOrNull?.code, 'ARCHIVO_DEMASIADO_GRANDE');
    });

    test('un 503 (R2 apagado) llega como Failure de SERVIDOR', () async {
      final g = FakeArchivosGateway()
        ..errorAlSubir = const AppException.servidor(code: 'SERVICIO_NO_DISPONIBLE');
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.subir(
        nombreOriginal: 'x.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
        contenido: const [1],
      );

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.servidor);
    });

    test('un fallo NO se confunde con un éxito vacío', () async {
      // Regla del proyecto: `null` significa «no existe», nunca «falló». Si un
      // fallo se colara como Success con valor nulo, la UI diría «listo» sin
      // haber subido nada.
      final g = FakeArchivosGateway()
        ..errorAlSubir = const AppException.red();
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.subir(
        nombreOriginal: 'x.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
        contenido: const [1],
      );

      expect(r.isSuccess, isFalse);
      expect(r.valueOrNull, isNull);
      expect(r.errorOrNull, isNotNull);
    });
  });

  group('los pasos sueltos, para reanudar una subida cortada', () {
    test('firmarSubida devuelve la URL y el tipo que hay que enviar', () async {
      final g = FakeArchivosGateway();
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.firmarSubida(
        nombreOriginal: 'Constancia José.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
      );

      final firmada = r.when(success: (v) => v, failure: (_) => null);
      expect(firmada, isNotNull);
      expect(firmada!.urlDeSubida, g.urlDeSubidaDevuelta);
      expect(firmada.archivo.estado, EstadoArchivo.pending);
      expect(firmada.archivo.tamanoBytes, isNull);
    });

    test('subirObjeto propaga el tipo recibido sin reinterpretarlo', () async {
      final g = FakeArchivosGateway();
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.subirObjeto(
        urlDeSubida: g.urlDeSubidaDevuelta,
        tipoContenido: 'application/pdf',
        contenido: const [9, 9],
      );

      expect(r.isSuccess, isTrue);
      expect(g.ultimoTipoContenidoEnviado, 'application/pdf');
      expect(g.ultimoContenido, const [9, 9]);
    });

    test('confirmar y urlDeLectura delegan el id', () async {
      final g = FakeArchivosGateway();
      final repo = ArchivosRepository(gateway: g);

      await repo.confirmar('arch-3');
      expect(g.ultimoArchivoId, 'arch-3');

      final lectura = await repo.urlDeLectura('arch-4');
      expect(g.ultimoArchivoId, 'arch-4');
      expect(
        lectura.when(success: (v) => v.nombreOriginal, failure: (_) => ''),
        'Constancia José.pdf',
      );
    });

    test('firmarSubida traduce un 503 a Failure', () async {
      final g = FakeArchivosGateway()
        ..errorAlFirmar = const AppException.servidor(code: 'SERVICIO_NO_DISPONIBLE');
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.firmarSubida(
        nombreOriginal: 'x.pdf',
        entityType: TipoEntidadArchivo.taskSubmission,
      );

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.code, 'SERVICIO_NO_DISPONIBLE');
    });
  });

  group('borrado', () {
    test('borrar devuelve el archivo en DELETED con su sello', () async {
      final g = FakeArchivosGateway();
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.borrar('arch-1');

      final archivo = r.when(success: (v) => v, failure: (_) => null);
      expect(archivo?.estado, EstadoArchivo.deleted);
      expect(archivo?.borradoEn, isNotNull);
      expect(g.llamadas, contains('borrar:arch-1'));
    });

    test('borrarComoAdmin usa la ruta de administración', () async {
      final g = FakeArchivosGateway();
      final repo = ArchivosRepository(gateway: g);

      await repo.borrarComoAdmin('arch-1');

      expect(g.llamadas, contains('borrarComoAdmin:arch-1'));
    });

    test('borrar un archivo ajeno llega como Failure de permisos', () async {
      final g = FakeArchivosGateway()
        ..errorAlBorrar = const AppException(
          type: AppErrorType.permisos,
          message: 'No puedes borrar un archivo que no es tuyo.',
          code: 'ARCHIVO_AJENO',
        );
      final repo = ArchivosRepository(gateway: g);

      final r = await repo.borrar('arch-ajeno');

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.permisos);
      expect(r.errorOrNull?.code, 'ARCHIVO_AJENO');
    });
  });
}
