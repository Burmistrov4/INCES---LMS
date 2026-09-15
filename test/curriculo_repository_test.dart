import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/curriculo_gateway.dart';
import 'package:inces_lms_app/models/pensum.dart';
import 'package:inces_lms_app/models/programa.dart';
import 'package:inces_lms_app/repositories/curriculo_repository.dart';

import 'support/fake_curriculo_gateway.dart';

void main() {
  late FakeCurriculoGateway gateway;
  late CurriculoRepository repo;

  setUp(() {
    gateway = FakeCurriculoGateway();
    repo = CurriculoRepository(gateway: gateway);
  });

  EntradaCrearPrograma entradaValida({
    String codigo = 'SIST-01',
    String nombre = 'Análisis de Sistemas',
    List<EntradaPensum>? pensum,
  }) =>
      EntradaCrearPrograma(
        codigo: codigo,
        nombre: nombre,
        tipo: TipoPrograma.carrera,
        pensum: pensum ?? const [EntradaPensum(materiaId: idAlgoritmica)],
      );

  group('crearPrograma · normalización', () {
    test('recorta el nombre y pasa el código a mayúsculas', () {
      gateway.detalleCreado = detalleSistemas();

      final resultado = repo.crearPrograma(
        entradaValida(codigo: '  sist-01  ', nombre: '  Análisis de Sistemas '),
      );

      return resultado.then((r) {
        expect(r.isSuccess, isTrue);
        // El backend exige mayúsculas; normalizar aquí evita un 400 por algo
        // que el usuario no puede adivinar. El campo del formulario además las
        // impone al escribir, así que lo que se manda es lo que se vio.
        expect(gateway.ultimaCreacion!.codigo, 'SIST-01');
        expect(gateway.ultimaCreacion!.nombre, 'Análisis de Sistemas');
      });
    });

    test('no reescribe el pensum ni el tipo que recibe', () {
      gateway.detalleCreado = detalleSistemas();

      return repo
          .crearPrograma(
            EntradaCrearPrograma(
              codigo: 'CL-01',
              nombre: 'Soldadura básica',
              tipo: TipoPrograma.cursoLibre,
              pensum: const [
                EntradaPensum(materiaId: idAlgoritmica, periodo: 1),
              ],
              requierePasantia: true,
              publicar: false,
            ),
          )
          .then((r) {
        expect(r.isSuccess, isTrue);
        final enviado = gateway.ultimaCreacion!;
        expect(enviado.tipo, TipoPrograma.cursoLibre);
        expect(enviado.requierePasantia, isTrue);
        expect(enviado.publicar, isFalse);
        expect(enviado.pensum, hasLength(1));
      });
    });
  });

  group('crearPrograma · validaciones de dominio', () {
    Future<AppException?> falloDe(EntradaCrearPrograma entrada) async {
      final r = await repo.crearPrograma(entrada);
      return r.errorOrNull;
    }

    test('rechaza un código con espacios', () async {
      final fallo = await falloDe(entradaValida(codigo: 'SIST 01'));

      expect(fallo, isNotNull);
      expect(fallo!.type, AppErrorType.validacion);
      expect(fallo.message, contains('mayúsculas'));
      // Y no se llegó a llamar al gateway: el viaje de red se evita.
      expect(gateway.llamadas, isEmpty);
    });

    test('rechaza un código que empieza por guion', () async {
      expect(await falloDe(entradaValida(codigo: '-SIST')), isNotNull);
    });

    test('rechaza un código de más de 12 caracteres', () async {
      final fallo = await falloDe(entradaValida(codigo: 'ABCDEFGHIJKLM'));

      expect(fallo!.message, contains('12'));
    });

    test('rechaza el código vacío', () async {
      expect(await falloDe(entradaValida(codigo: '   ')), isNotNull);
    });

    test('rechaza el nombre vacío', () async {
      expect(await falloDe(entradaValida(nombre: '  ')), isNotNull);
    });

    test('rechaza un nombre de más de 100 caracteres', () async {
      expect(await falloDe(entradaValida(nombre: 'x' * 101)), isNotNull);
    });

    test('rechaza un pensum vacío', () async {
      final fallo = await falloDe(entradaValida(pensum: const []));

      expect(fallo!.message, contains('al menos una materia'));
    });

    test('rechaza una materia repetida y lo marca con un código', () async {
      final fallo = await falloDe(
        entradaValida(
          pensum: const [
            EntradaPensum(materiaId: idAlgoritmica, periodo: 1),
            EntradaPensum(materiaId: idAlgoritmica, periodo: 2),
          ],
        ),
      );

      expect(fallo!.code, 'MATERIA_REPETIDA');
      expect(gateway.llamadas, isEmpty);
    });

    test('rechaza un período menor que 1', () async {
      final fallo = await falloDe(
        entradaValida(
          pensum: const [EntradaPensum(materiaId: idAlgoritmica, periodo: 0)],
        ),
      );

      expect(fallo!.message, contains('empiezan en 1'));
    });
  });

  group('actualizarPrograma', () {
    test('rechaza un cambio sin ningún campo', () async {
      final r = await repo.actualizarPrograma(idSistemas, const CambiosPrograma());

      expect(r.errorOrNull!.message, contains('ningún cambio'));
      expect(gateway.llamadas, isEmpty);
    });

    test('recorta el nombre antes de enviarlo', () async {
      gateway.programaActualizado = programaSistemas();

      final r = await repo.actualizarPrograma(
        idSistemas,
        const CambiosPrograma(nombre: '  Otro nombre  '),
      );

      expect(r.isSuccess, isTrue);
      expect(gateway.ultimosCambios!.nombre, 'Otro nombre');
    });

    test('sólo manda el campo que cambia', () async {
      // El esquema del backend es `.strict()`: un `null` donde no se quiere
      // escribir nada sería un intento de borrar el campo.
      gateway.programaActualizado = programaSistemas(activo: false);

      await repo.actualizarPrograma(
        idSistemas,
        const CambiosPrograma(activo: false),
      );

      expect(gateway.ultimosCambios!.toJson(), {'activo': false});
    });

    test('propaga el fallo del gateway como Failure tipado', () async {
      gateway.errorAlActualizar = const AppException.validacion(
        'Una carrera activa no puede quedarse sin materias.',
        code: 'RESTRICCION_VIOLADA',
      );

      final r = await repo.actualizarPrograma(
        idSistemas,
        const CambiosPrograma(activo: true),
      );

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull!.code, 'RESTRICCION_VIOLADA');
    });
  });

  group('reemplazarPensum', () {
    test('rechaza un pensum vacío sin llamar al gateway', () async {
      final r = await repo.reemplazarPensum(idSistemas, const []);

      expect(r.errorOrNull, isNotNull);
      expect(gateway.llamadas, isEmpty);
    });

    test('envía el pensum tal cual cuando es válido', () async {
      gateway.detalleReemplazado = detalleSistemas();

      final r = await repo.reemplazarPensum(
        idSistemas,
        const [EntradaPensum(materiaId: idAlgoritmica, periodo: 3)],
      );

      expect(r.isSuccess, isTrue);
      expect(gateway.ultimoPensum!.single.periodo, 3);
    });
  });

  group('crearMateria', () {
    test('rechaza horas en cero o negativas', () async {
      final r = await repo.crearMateria(
        const EntradaCrearMateria(
          codigo: 'BD-II',
          nombre: 'Bases de Datos II',
          horasAcademicas: 0,
        ),
      );

      expect(r.errorOrNull!.message, contains('mayores que cero'));
      expect(gateway.llamadas, isEmpty);
    });

    test('normaliza el código a mayúsculas', () async {
      gateway.materiaCreada = basesDeDatos();

      await repo.crearMateria(
        const EntradaCrearMateria(
          codigo: 'bd-ii',
          nombre: 'Bases de Datos II',
          horasAcademicas: 96,
        ),
      );

      expect(gateway.ultimaMateria!.codigo, 'BD-II');
    });
  });

  group('paginación', () {
    test('rechaza un desplazamiento negativo', () async {
      final r = await repo.listarProgramas(desplazamiento: -1);

      expect(r.errorOrNull!.message, contains('negativo'));
      expect(gateway.llamadas, isEmpty);
    });

    test('rechaza un tamaño de página fuera de rango', () async {
      expect((await repo.listarProgramas(limite: 0)).errorOrNull, isNotNull);
      expect((await repo.listarProgramas(limite: 101)).errorOrNull, isNotNull);
      expect((await repo.listarMaterias(limite: 0)).errorOrNull, isNotNull);
    });

    test('acepta los extremos del rango', () async {
      expect((await repo.listarProgramas(limite: 1)).isSuccess, isTrue);
      expect((await repo.listarProgramas(limite: 100)).isSuccess, isTrue);
    });

    test('rechaza una búsqueda demasiado larga', () async {
      final r = await repo.listarMaterias(busqueda: 'x' * 101);

      expect(r.errorOrNull, isNotNull);
      expect(gateway.llamadas, isEmpty);
    });
  });

  group('listarProgramas', () {
    test('devuelve la página y su total', () async {
      gateway.programas = [programaSistemas()];
      gateway.totalProgramas = 7;

      final r = await repo.listarProgramas();

      expect(r.valueOrNull!.programas, hasLength(1));
      expect(r.valueOrNull!.total, 7);
    });

    test('propaga el fallo del gateway', () async {
      gateway.errorAlListar = const AppException.red();

      final r = await repo.listarProgramas();

      expect(r.isFailure, isTrue);
      expect(r.errorOrNull!.type, AppErrorType.red);
    });
  });
}
