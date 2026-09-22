import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/network/api_client.dart';
import 'package:inces_lms_app/services/aula_service.dart';

/// Capa de datos del listado «Mis aulas»: el gateway contra un `http.Client`
/// doblado.
///
/// **Por qué aquí y no en el panel.** El panel prueba que la pantalla pida y
/// pinte; lo que no puede probar es **qué se mandó** ni que la reducción de
/// `/mi-horario` a un aula por sección sea la correcta. Eso vive en el gateway,
/// y es lo que se verifica aquí.
///
/// **Lo que este archivo NO puede probar:** que la RLS devuelva sólo las
/// secciones del llamante, ni que `/mi-horario` responda de verdad con esa
/// forma. Eso lo cubre la suite de PGlite y el humo del backend.
const String baseApi = 'https://api.inces.test';
const String tokenPrueba = 'jwt-de-prueba';
const String rutaMiHorario = '/api/v1/mi-horario';

/// Respuesta JSON declarando UTF-8 a propósito: sin el `charset`, `http.Response`
/// codifica en latin1 y un nombre con acento se compara distinto según por dónde
/// haya pasado.
http.Response json(Object cuerpo, [int estado = 200]) => http.Response(
      jsonEncode(cuerpo),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Cuerpo de error con el sobre uniforme del backend.
http.Response errorJson(int estado, String codigo, String mensaje) => json({
      'error': {'codigo': codigo, 'mensaje': mensaje},
    }, estado);

/// Una fila de `clases`, con **los nombres de la vista** (`materia`, `seccion`,
/// `programa`) y no los del dominio.
///
/// La distinción no es cosmética: leer la vista con los nombres del dominio
/// devuelve `null` en silencio, y eso ya costó dos falsos positivos en el humo
/// de M1/M3. Una prueba que use las claves equivocadas pasaría sin probar nada.
Map<String, dynamic> claseJson({
  String id = 'cl-1',
  String seccionId = 'sec-1',
  String materia = 'Soldadura',
  String seccion = 'Sección A',
  String programa = 'Formación Profesional',
  int dia = 1,
  int bloque = 1,
}) =>
    {
      'id': id,
      'seccionId': seccionId,
      'docenteId': 'doc-1',
      'aulaId': 'aul-1',
      'dia': dia,
      'bloque': bloque,
      'turno': 'MAÑANA',
      'activa': true,
      'periodo': 'SA26-2',
      'programaId': 'pro-1',
      'programa': programa,
      'materiaId': 'mat-1',
      'materia': materia,
      'seccion': seccion,
      'aula': 'Taller 3',
      'docente': 'Ana Pérez',
    };

/// Una guardia: presencia de custodia, **no** una clase.
Map<String, dynamic> guardiaJson({
  String id = 'gu-1',
  int dia = 2,
  int bloque = 7,
}) =>
    {
      'id': id,
      'docenteId': 'doc-1',
      'aulaId': 'aul-2',
      'periodo': 'SA26-2',
      'dia': dia,
      'bloque': bloque,
      'turno': 'TARDE',
      'notas': null,
      'activa': true,
    };

/// El payload de `/mi-horario`, con la forma de `MiHorario`.
Map<String, dynamic> horarioJson({
  String rol = 'estudiante',
  String? periodo = 'SA26-2',
  List<Map<String, dynamic>>? clases,
  List<Map<String, dynamic>>? guardias,
}) =>
    {
      'rol': rol,
      'periodo': periodo,
      'clases': clases ?? [claseJson()],
      'guardias': guardias ?? const <Map<String, dynamic>>[],
    };

/// Doble de `http.Client` que enruta por «MÉTODO /ruta» y **guarda lo recibido**.
class BackendFalso {
  BackendFalso(this.respuestas);

  final Map<String, http.Response> respuestas;
  final List<http.Request> recibidas = [];

  http.Client get cliente => MockClient((peticion) async {
        recibidas.add(peticion);

        final respuesta = respuestas['${peticion.method} ${peticion.url.path}'];
        if (respuesta == null) {
          // Fallar en alto en vez de devolver un 200 por defecto: una ruta que
          // nadie dobló es un error del test, y devolver 200 la dejaría pasando
          // por la razón equivocada.
          return errorJson(
            599,
            'RUTA_NO_DOBLADA',
            'El test no dobló ${peticion.method} ${peticion.url.path}',
          );
        }
        return respuesta;
      });

  http.Request? porRuta(String metodo, String ruta) {
    for (final peticion in recibidas) {
      if (peticion.method == metodo && peticion.url.path == ruta) {
        return peticion;
      }
    }
    return null;
  }
}

BackendAulaGateway gatewayDe(BackendFalso falso, {String? token = tokenPrueba}) =>
    BackendAulaGateway(
      api: ApiClient(httpClient: falso.cliente, baseUrl: baseApi),
      tokenSesion: () => token,
    );

/// Un doble que siempre responde el mismo horario, para las pruebas de la
/// petición (que no miran el cuerpo).
BackendFalso conHorario(Map<String, dynamic> horario) =>
    BackendFalso({'GET $rutaMiHorario': json(horario)});

void main() {
  group('misAulas · reducción de /mi-horario', () {
    test('una sección con varias franjas es un solo aula', () async {
      // Un horario real: la misma sección el lunes a primera y el miércoles a
      // segunda. En un listado de aulas eso serían dos tarjetas idénticas.
      final falso = conHorario(
        horarioJson(
          clases: [
            claseJson(id: 'cl-1', seccionId: 'sec-1', dia: 1, bloque: 1),
            claseJson(id: 'cl-2', seccionId: 'sec-1', dia: 3, bloque: 2),
            claseJson(
              id: 'cl-3',
              seccionId: 'sec-2',
              materia: 'Electricidad',
              seccion: 'Sección B',
              dia: 2,
              bloque: 4,
            ),
          ],
        ),
      );

      final mis = await gatewayDe(falso).misAulas();

      expect(mis.aulas.map((a) => a.seccionId), ['sec-1', 'sec-2']);
      expect(mis.aulas, hasLength(2));
    });

    test('la etiqueta se compone con materia, sección y programa', () async {
      final falso = conHorario(horarioJson());

      final mis = await gatewayDe(falso).misAulas();

      expect(
        mis.aulas.single.etiqueta,
        'Soldadura · Sección A · Formación Profesional',
      );
    });

    test('conserva la primera aparición de la sección, no la última', () async {
      // Dos franjas de la misma sección con materia distinta: es un dato
      // corrupto a propósito. Lo que importa es que la etiqueta salga de la
      // **primera** fila y no de la que el servidor mandó al final, para que el
      // listado sea estable y no dependa del orden de las franjas.
      final falso = conHorario(
        horarioJson(
          clases: [
            claseJson(id: 'cl-1', seccionId: 'sec-1', materia: 'Soldadura'),
            claseJson(id: 'cl-2', seccionId: 'sec-1', materia: 'Otra materia'),
          ],
        ),
      );

      final mis = await gatewayDe(falso).misAulas();

      expect(mis.aulas.single.materia, 'Soldadura');
    });

    test('las guardias no son aulas', () async {
      // Un docente recibe clases **y** guardias. Una guardia es una presencia de
      // custodia: no tiene tablón ni trabajo de clase, así que no es un aula.
      final falso = conHorario(
        horarioJson(
          rol: 'docente',
          clases: [claseJson(seccionId: 'sec-1')],
          guardias: [guardiaJson(), guardiaJson(id: 'gu-2', dia: 4, bloque: 9)],
        ),
      );

      final mis = await gatewayDe(falso).misAulas();

      expect(mis.aulas, hasLength(1));
      expect(mis.aulas.single.seccionId, 'sec-1');
    });

    test('el rol del payload decide esDocente', () async {
      final docente = await gatewayDe(conHorario(horarioJson(rol: 'docente')))
          .misAulas();
      final estudiante =
          await gatewayDe(conHorario(horarioJson(rol: 'estudiante'))).misAulas();

      expect(docente.esDocente, isTrue);
      expect(estudiante.esDocente, isFalse);
    });

    test('sin clases el listado queda vacío pero conserva el lapso', () async {
      final falso = conHorario(horarioJson(clases: const [], periodo: 'SA26-1'));

      final mis = await gatewayDe(falso).misAulas();

      expect(mis.vacio, isTrue);
      expect(mis.periodo, 'SA26-1');
    });

    test('sin lapso vigente el período es nulo, no cadena vacía', () async {
      final falso = conHorario(horarioJson(clases: const [], periodo: null));

      final mis = await gatewayDe(falso).misAulas();

      expect(mis.periodo, isNull);
    });

    test('un programa en blanco no deja un separador colgando', () async {
      final falso = conHorario(horarioJson(clases: [claseJson(programa: '  ')]));

      final mis = await gatewayDe(falso).misAulas();

      expect(mis.aulas.single.etiqueta, 'Soldadura · Sección A');
      expect(mis.aulas.single.programa, isNull);
    });
  });

  group('misAulas · lo que viaja en la petición', () {
    test('va a /mi-horario con el token de sesión', () async {
      final falso = conHorario(horarioJson());

      await gatewayDe(falso).misAulas();

      final peticion = falso.porRuta('GET', rutaMiHorario);
      expect(peticion, isNotNull, reason: 'no se pidió /mi-horario');
      expect(peticion!.headers['Authorization'], 'Bearer $tokenPrueba');
    });

    test('sin período no manda el parámetro', () async {
      final falso = conHorario(horarioJson());

      await gatewayDe(falso).misAulas();

      expect(falso.porRuta('GET', rutaMiHorario)!.url.queryParameters, isEmpty);
    });

    test('con período lo manda recortado', () async {
      final falso = conHorario(horarioJson());

      await gatewayDe(falso).misAulas(periodo: '  SA26-1  ');

      expect(
        falso.porRuta('GET', rutaMiHorario)!.url.queryParameters['periodo'],
        'SA26-1',
      );
    });

    test('un período en blanco equivale a no filtrar', () async {
      // Mandar `periodo=` vacío haría que el backend lo rechazara por cadena
      // vacía; el filtro sin usar tiene que desaparecer de la URL.
      final falso = conHorario(horarioJson());

      await gatewayDe(falso).misAulas(periodo: '   ');

      expect(falso.porRuta('GET', rutaMiHorario)!.url.queryParameters, isEmpty);
    });

    test('un fallo del backend llega como AppException con su mensaje', () async {
      final falso = BackendFalso({
        'GET $rutaMiHorario': errorJson(
          403,
          'SIN_PERMISO',
          'No tienes acceso a este horario.',
        ),
      });

      await expectLater(
        gatewayDe(falso).misAulas(),
        throwsA(
          isA<AppException>()
              .having((e) => e.message, 'message', 'No tienes acceso a este horario.')
              .having((e) => e.type, 'type', AppErrorType.permisos)
              .having((e) => e.code, 'code', 'SIN_PERMISO'),
        ),
      );
    });
  });
}
