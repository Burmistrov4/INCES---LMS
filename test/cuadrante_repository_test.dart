import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/cuadrante_gateway.dart';
import 'package:inces_lms_app/core/reglas_cuadrante.dart';
import 'package:inces_lms_app/core/result.dart';
import 'package:inces_lms_app/models/cuadrante.dart';
import 'package:inces_lms_app/repositories/cuadrante_repository.dart';

import 'support/fake_cuadrante_gateway.dart';

/// Pruebas del repositorio de M3.
///
/// Se centran en dos cosas que la interfaz no puede garantizar por sí sola:
/// **qué se envía** —no sólo qué se muestra— y que un fallo llegue como
/// `Failure` con su mensaje, nunca como un `null` que se lea como «no hay
/// datos».
///
/// La validación se comprueba aquí porque vive aquí: el widget no la repite, así
/// que si no se prueba en esta capa, no se prueba en ninguna.
void main() {
  late FakeCuadranteGateway gateway;
  late CuadranteRepository repo;

  // UUID con la forma correcta, para no chocar con la validación previa.
  const docente = '11111111-1111-1111-1111-111111111111';
  const aula = '22222222-2222-2222-2222-222222222222';
  const seccion = '33333333-3333-3333-3333-333333333333';

  setUp(() {
    gateway = FakeCuadranteGateway();
    repo = CuadranteRepository(gateway: gateway);
  });

  /// El mensaje de un `Failure`, o `null` si salió bien.
  String? falloDe(Result<Object?> resultado) =>
      resultado.errorOrNull?.message;

  group('aulas', () {
    test('la lista pasa los filtros al gateway', () async {
      gateway.totalAulas = 9;

      final resultado = await repo.listarAulas(
        tipo: TipoAula.taller,
        activa: true,
        busqueda: 'cabina',
      );

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimoTipoAula, TipoAula.taller);
      expect(gateway.ultimoActiva, isTrue);
      expect(gateway.ultimaBusqueda, 'cabina');
    });

    test('un filtro de tipo nulo significa «todos», no «taller»', () async {
      await repo.listarAulas();
      expect(gateway.ultimoTipoAula, isNull);
      expect(gateway.ultimoActiva, isNull);
    });

    test('rechaza un tamaño de página fuera de rango, sin llamar al gateway',
        () async {
      final cero = await repo.listarAulas(limite: 0);
      final enorme = await repo.listarAulas(limite: 101);
      final negativo = await repo.listarAulas(desplazamiento: -1);

      expect(cero.isFailure, isTrue);
      expect(enorme.isFailure, isTrue);
      expect(negativo.isFailure, isTrue);

      // Ninguna de las tres llegó a la red: la validación previa existe para no
      // gastar un viaje en un 400 que ya se podía prever.
      expect(gateway.llamadas, isEmpty);
    });

    test('crear recorta el nombre y respeta la forma del espacio', () async {
      final resultado = await repo.crearAula(
        const EntradaCrearAula(
          nombre: '  Taller de Soldadura Cabina A  ',
          capacidad: 12,
          esTaller: true,
        ),
      );

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimaAula?.nombre, 'Taller de Soldadura Cabina A');
      expect(gateway.ultimaAula?.esTaller, isTrue);
    });

    test('crear rechaza un nombre en blanco', () async {
      final resultado = await repo.crearAula(
        const EntradaCrearAula(nombre: '   ', capacidad: 10),
      );

      expect(falloDe(resultado), 'Ingresa el nombre del espacio.');
      expect(gateway.llamadas, isEmpty);
    });

    test('crear rechaza una capacidad negativa y explica el cero', () async {
      final resultado = await repo.crearAula(
        const EntradaCrearAula(nombre: 'Pasillo', capacidad: -1),
      );

      // El mensaje nombra el cero porque es la salida que el usuario no conoce:
      // «capacidad no puede ser negativa» a secas deja sin saber qué poner para
      // una zona sin cupo.
      expect(falloDe(resultado), contains('Usa 0'));
      expect(gateway.llamadas, isEmpty);
    });

    test('crear acepta la capacidad cero de una zona', () async {
      final resultado = await repo.crearAula(
        const EntradaCrearAula(nombre: 'Pasillo de talleres', capacidad: 0),
      );

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimaAula?.capacidad, 0);
    });

    test('actualizar envía SÓLO lo que cambia', () async {
      await repo.actualizarAula(aula, const CambiosAula(activa: false));

      final enviado = gateway.ultimosCambiosAula!.toJson();

      // Archivar no es borrar: se manda `activa: false` y nada más. Mandar el
      // objeto entero convertiría cada campo ausente en un intento de escribir
      // `null`, que el esquema `.strict()` del backend rechaza.
      expect(enviado, {'activa': false});
    });

    test('actualizar rechaza un cambio vacío', () async {
      final resultado = await repo.actualizarAula(aula, const CambiosAula());

      expect(falloDe(resultado), 'No hay ningún cambio que guardar.');
      expect(gateway.llamadas, isEmpty);
    });

    test('actualizar valida el nombre sólo si viene', () async {
      final conNombreMalo = await repo.actualizarAula(
        aula,
        const CambiosAula(nombre: '  '),
      );
      expect(conNombreMalo.isFailure, isTrue);

      final soloCapacidad = await repo.actualizarAula(
        aula,
        const CambiosAula(capacidad: 20),
      );
      expect(soloCapacidad.isSuccess, isTrue);
    });

    test('actualizar exige un identificador', () async {
      final resultado = await repo.actualizarAula(
        '   ',
        const CambiosAula(activa: false),
      );

      expect(falloDe(resultado), 'Falta el identificador de el espacio.');
      expect(gateway.llamadas, isEmpty);
    });
  });

  group('períodos', () {
    test('crear normaliza el código y las fechas opcionales', () async {
      final resultado = await repo.crearPeriodo(
        const EntradaCrearPeriodo(
          codigo: ' 2026-2 ',
          nombre: '  Lapso 2026-2  ',
          fechaInicio: '2026-09-21',
          fechaFin: '2027-02-13',
        ),
      );

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimoPeriodo?.codigo, '2026-2');
      expect(gateway.ultimoPeriodo?.nombre, 'Lapso 2026-2');
    });

    test('crear un lapso sin fechas es válido', () async {
      // El centro no ha cargado las fechas del lapso en curso, e inventarlas
      // sería fabricar un dato institucional (R-17).
      final resultado = await repo.crearPeriodo(
        const EntradaCrearPeriodo(codigo: '2027-1'),
      );

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimoPeriodo?.fechaInicio, isNull);
      expect(gateway.ultimoPeriodo?.fechaFin, isNull);
    });

    test('crear rechaza un código mal formado', () async {
      final resultado = await repo.crearPeriodo(
        const EntradaCrearPeriodo(codigo: '-2026'),
      );

      expect(falloDe(resultado), contains('empezar por letra o dígito'));
      expect(gateway.llamadas, isEmpty);
    });

    test('crear rechaza un rango invertido y un día inexistente', () async {
      final invertido = await repo.crearPeriodo(
        const EntradaCrearPeriodo(
          codigo: '2026-3',
          fechaInicio: '2027-02-13',
          fechaFin: '2026-09-21',
        ),
      );
      expect(falloDe(invertido), contains('posterior a la de inicio'));

      final imposible = await repo.crearPeriodo(
        const EntradaCrearPeriodo(codigo: '2026-4', fechaInicio: '2027-02-30'),
      );
      expect(falloDe(imposible), contains('fecha válida'));

      expect(gateway.llamadas, isEmpty);
    });

    test('actualizar rechaza un cambio vacío', () async {
      final resultado = await repo.actualizarPeriodo(
        'lapso-1',
        const CambiosPeriodo(),
      );

      expect(falloDe(resultado), 'No hay ningún cambio que guardar.');
    });

    test('borrar las fechas se envía como nulo explícito', () async {
      await repo.actualizarPeriodo(
        'lapso-1',
        const CambiosPeriodo(borrarFechas: true),
      );

      final enviado = gateway.ultimosCambiosPeriodo!.toJson();

      // «Ausente» y «nulo» significan cosas distintas: ausente es «no lo
      // toques», nulo es «bórralo». Sin esta distinción no habría forma de
      // deshacer una fecha mal cargada.
      expect(enviado, {'fechaInicio': null, 'fechaFin': null});
    });

    test('marcar el vigente no manda cuerpo y exige el identificador', () async {
      await repo.marcarVigente('lapso-1');
      expect(gateway.llamadas, contains('marcarVigente:lapso-1'));

      gateway.limpiarLlamadas();
      final resultado = await repo.marcarVigente('  ');

      expect(falloDe(resultado), 'Falta el identificador de el lapso.');
      expect(gateway.llamadas, isEmpty);
    });

    test('el catálogo no se pagina', () async {
      gateway.periodos = const [
        Periodo(id: 'a', codigo: '2026-1', activo: true, vigente: true),
      ];

      final resultado = await repo.listarPeriodos();

      expect(resultado.valueOrNull, hasLength(1));
      expect(gateway.llamadas, ['listarPeriodos']);
    });
  });

  group('guardias', () {
    test('crear exige docente, espacio y lapso', () async {
      final sinDocente = await repo.crearGuardia(
        const EntradaCrearGuardia(
          docenteId: '',
          aulaId: aula,
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
        ),
      );
      expect(falloDe(sinDocente), 'Elige el docente.');

      final sinLapso = await repo.crearGuardia(
        const EntradaCrearGuardia(
          docenteId: docente,
          aulaId: aula,
          periodo: '',
          dia: 1,
          bloque: 1,
        ),
      );
      // R-15: sin período, una guardia del lunes a primera hora chocaría con las
      // clases de cualquier lapso.
      expect(falloDe(sinLapso), 'Elige el lapso.');

      expect(gateway.llamadas, isEmpty);
    });

    test('crear rechaza el domingo y el bloque 13', () async {
      final domingo = await repo.crearGuardia(
        const EntradaCrearGuardia(
          docenteId: docente,
          aulaId: aula,
          periodo: '2026-1',
          dia: 7,
          bloque: 1,
        ),
      );
      expect(falloDe(domingo), contains('lunes y el sábado'));

      final bloque13 = await repo.crearGuardia(
        const EntradaCrearGuardia(
          docenteId: docente,
          aulaId: aula,
          periodo: '2026-1',
          dia: 1,
          bloque: 13,
        ),
      );
      expect(falloDe(bloque13), contains('entre 1 y 12'));

      expect(gateway.llamadas, isEmpty);
    });

    test('crear NO manda el turno: lo deriva la base del bloque', () async {
      await repo.crearGuardia(
        const EntradaCrearGuardia(
          docenteId: docente,
          aulaId: aula,
          periodo: '2026-1',
          dia: 2,
          bloque: 9,
        ),
      );

      final enviado = gateway.ultimaGuardia!.toJson();

      // El esquema del backend es `.strict()`: mandar `turno` es un 400, no un
      // campo ignorado. Aceptar un turno que contradiga al bloque sería aceptar
      // una agenda que miente.
      expect(enviado.containsKey('turno'), isFalse);
      expect(enviado['bloque'], 9);
    });

    test('unas notas en blanco se guardan como nulo, no como cadena vacía',
        () async {
      await repo.crearGuardia(
        const EntradaCrearGuardia(
          docenteId: docente,
          aulaId: aula,
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          notas: '   ',
        ),
      );

      expect(gateway.ultimaGuardia?.notas, isNull);
    });

    test('rechaza unas notas que pasan del límite', () async {
      final resultado = await repo.crearGuardia(
        EntradaCrearGuardia(
          docenteId: docente,
          aulaId: aula,
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          notas: 'a' * 501,
        ),
      );

      expect(falloDe(resultado), contains('500 caracteres'));
      expect(gateway.llamadas, isEmpty);
    });

    test('archivar es activa:false y no borra nada', () async {
      await repo.actualizarGuardia(
        'guardia-1',
        const CambiosGuardia(activa: false),
      );

      expect(gateway.ultimosCambiosGuardia!.toJson(), {'activa': false});
    });

    test('borrar las notas se envía como nulo explícito', () async {
      await repo.actualizarGuardia(
        'guardia-1',
        const CambiosGuardia(borrarNotas: true),
      );

      expect(gateway.ultimosCambiosGuardia!.toJson(), {'notas': null});
    });

    test('los filtros de la lista se validan antes de salir', () async {
      final diaMalo = await repo.listarGuardias(dia: 0);
      final bloqueMalo = await repo.listarGuardias(bloque: 99);
      final uuidMalo = await repo.listarGuardias(docenteId: 'no-es-uuid');

      expect(diaMalo.isFailure, isTrue);
      expect(bloqueMalo.isFailure, isTrue);
      expect(falloDe(uuidMalo), contains('formato esperado'));
      expect(gateway.llamadas, isEmpty);
    });

    test('un filtro de docente vacío no se valida ni se envía', () async {
      // La pantalla manda cadena vacía cuando el desplegable está en «todos».
      final resultado = await repo.listarGuardias(docenteId: '');

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimoDocenteFiltro, isNull);
    });

    test('los filtros en blanco se normalizan a «sin filtro»', () async {
      // La normalización vive en el repositorio, no en el adaptador: si
      // dependiera del adaptador, el puerto recibiría '   ' donde su contrato
      // dice «sin filtro», y cada implementación tendría que acordarse de
      // limpiarlo. Lo destapó esta prueba: `miHorario` pasaba la cadena tal cual.
      await repo.listarGuardias(periodo: '   ', aulaId: '  ');

      expect(gateway.ultimoPeriodoFiltro, isNull);
      expect(gateway.ultimoAulaFiltro, isNull);
    });
  });

  group('cuadrante', () {
    test('la rejilla pide las inactivas sólo cuando se piden', () async {
      await repo.rejilla(periodo: '2026-1');
      expect(gateway.ultimoIncluirInactivas, isFalse);

      await repo.rejilla(periodo: '2026-1', incluirInactivas: true);
      expect(gateway.ultimoIncluirInactivas, isTrue);
    });

    test('la rejilla admite que no haya lapso vigente', () async {
      gateway.rejillaDevuelta = const RejillaCuadrante(
        aulas: [
          Aula(
            id: 'a',
            nombre: 'Taller A',
            capacidad: 1,
            esTaller: true,
            activa: true,
          ),
        ],
      );

      final resultado = await repo.rejilla();

      // Sin lapso, las clases salen vacías pero el catálogo sigue lleno: la
      // pantalla puede decir «no hay lapso vigente» en vez de aparecer en blanco.
      expect(resultado.valueOrNull?.sinPeriodo, isTrue);
      expect(resultado.valueOrNull?.sinAulas, isFalse);
    });

    test('un lapso en blanco en la rejilla equivale a no pedirlo', () async {
      await repo.rejilla(periodo: '   ');
      expect(gateway.ultimoPeriodoFiltro, isNull);
    });

    test('crear una clase NO manda período ni turno', () async {
      await repo.crearClase(
        const EntradaCrearClase(
          seccionId: seccion,
          docenteId: docente,
          aulaId: aula,
          dia: 3,
          bloque: 5,
        ),
      );

      final enviado = gateway.ultimaClase!.toJson();

      // El período se deriva de la sección: aceptarlo del cliente abriría la
      // puerta a una fila cuya sección es del lapso 2026-1 mientras la rejilla
      // se dibuja en el 2026-2, y el chequeo compararía peras con manzanas.
      expect(enviado.keys.toSet(), {
        'seccionId',
        'docenteId',
        'aulaId',
        'dia',
        'bloque',
      });
    });

    test('crear una clase exige sección, docente y espacio', () async {
      final sinSeccion = await repo.crearClase(
        const EntradaCrearClase(
          seccionId: '',
          docenteId: docente,
          aulaId: aula,
          dia: 1,
          bloque: 1,
        ),
      );

      expect(falloDe(sinSeccion), 'Elige la sección.');
      expect(gateway.llamadas, isEmpty);
    });

    test('mover una clase es un cambio parcial', () async {
      await repo.actualizarClase(
        'clase-1',
        const CambiosClase(dia: 4, bloque: 2),
      );

      expect(gateway.ultimosCambiosClase!.toJson(), {'dia': 4, 'bloque': 2});
    });

    test('actualizar rechaza un cambio vacío', () async {
      final resultado = await repo.actualizarClase(
        'clase-1',
        const CambiosClase(),
      );

      expect(falloDe(resultado), 'No hay ningún cambio que guardar.');
    });
  });

  group('horario por rol', () {
    test('el lapso es opcional: sin él, el backend usa el vigente', () async {
      final resultado = await repo.miHorario();

      expect(resultado.isSuccess, isTrue);
      expect(gateway.ultimoPeriodoDeHorario, isNull);
    });

    test('un lapso en blanco equivale a no pedirlo', () async {
      await repo.miHorario(periodo: '   ');
      expect(gateway.ultimoPeriodoDeHorario, isNull);
    });

    test('un lapso demasiado largo se rechaza antes de salir', () async {
      final resultado = await repo.miHorario(periodo: '2026-1-extra-largo');

      expect(resultado.isFailure, isTrue);
      expect(gateway.llamadas, isEmpty);
    });
  });

  group('propagación de errores', () {
    test('un choque de agenda llega como Failure con su código', () async {
      // El backend responde 409 CHOQUE_DE_AGENDA cuando el docente o el espacio
      // ya están ocupados en ese bloque. `ApiClient` lo clasifica como
      // `validacion`, así que es el CÓDIGO el que permite distinguirlo de un
      // dato mal formado y dar un mensaje útil.
      gateway.errorAlCrearClase = const AppException(
        type: AppErrorType.validacion,
        message: 'Ese docente ya tiene una clase o guardia asignada el martes '
            'en el bloque 5.',
        code: codigoChoqueDeAgenda,
      );

      final resultado = await repo.crearClase(
        const EntradaCrearClase(
          seccionId: seccion,
          docenteId: docente,
          aulaId: aula,
          dia: 2,
          bloque: 5,
        ),
      );

      expect(resultado.isFailure, isTrue);
      expect(esChoqueDeAgenda(resultado.errorOrNull?.code), isTrue);
      expect(resultado.errorOrNull?.message, contains('ya tiene una clase'));
    });

    test('un fallo inesperado NO se convierte en null', () async {
      // La regla del proyecto: nunca `catch (e) { return null; }`. Un `null`
      // significa «no existe», jamás «algo salió mal».
      gateway.errorAlListarAulas = StateError('el doble reventó');

      final resultado = await repo.listarAulas();

      expect(resultado.isFailure, isTrue);
      expect(resultado.valueOrNull, isNull);
      expect(resultado.errorOrNull, isNotNull);
    });

    test('un 404 de aula inexistente conserva su código', () async {
      gateway.errorAlActualizarAula = const AppException(
        type: AppErrorType.validacion,
        message: 'El espacio no existe.',
        code: codigoAulaInexistente,
      );

      final resultado = await repo.actualizarAula(
        '44444444-4444-4444-4444-444444444444',
        const CambiosAula(activa: false),
      );

      expect(resultado.errorOrNull?.code, codigoAulaInexistente);
    });
  });
}
