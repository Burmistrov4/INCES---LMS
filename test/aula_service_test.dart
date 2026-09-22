import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/core/network/api_client.dart';
import 'package:inces_lms_app/services/aula_service.dart';

/// Capa de datos del Aula Virtual (M6): el gateway contra un `http.Client`
/// doblado.
///
/// **Por qué aquí y no en el panel.** El panel prueba que la pantalla pida y
/// pinte; lo que no puede probar es **qué se mandó** ni cómo se parsea lo que
/// llega. Eso vive en el gateway, y es lo que se verifica aquí.
///
/// **Los `payload` de esta suite son los del mapeador real**, no un mapa
/// inventado: camelCase, con las claves que emiten los `a*` de
/// `backend/src/infra/repos-supabase.ts` y sin esquema Zod de respuesta. Una
/// prueba que construyera su propio mapa «parecido» pasaría sin probar el
/// contrato —que es justo lo que se congeló para dejar de adivinar—.
///
/// **Lo que este archivo NO puede probar:** que la RLS devuelva sólo lo del
/// llamante, ni que `/mi-horario` responda de verdad con esa forma. Eso lo cubre
/// la suite de PGlite y el humo del backend.
const String baseApi = 'https://api.inces.test';
const String tokenPrueba = 'jwt-de-prueba';
const String rutaMiHorario = '/api/v1/mi-horario';
const String rutaMisEntregas = '/api/v1/aula/mis-entregas';

/// Las rutas de contenido que llevan la sección o la entrega en el camino.
///
/// Son funciones y no constantes porque el valor de la prueba **es** que el id
/// viaje en la ruta: una constante compartida dejaría pasar un método que
/// mandara el id equivocado.
String rutaTablon(String seccionId) =>
    '/api/v1/aula/secciones/$seccionId/tablon';
String rutaTrabajo(String seccionId) =>
    '/api/v1/aula/secciones/$seccionId/trabajo';
String rutaEntregar(String entregaId) =>
    '/api/v1/aula/entregas/$entregaId/entregar';
String rutaReclamar(String entregaId) =>
    '/api/v1/aula/entregas/$entregaId/reclamar';

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

// --- Payloads de M6, con la forma exacta del mapeador -----------------------
//
// Todos llevan **camelCase** y las claves que emiten los `a*` de
// `repos-supabase.ts`. Incluyen a propósito campos que el modelo Dart no lee
// (`autorId`, `permitirEntregaTardia`, `publicadoEn`, `id`): el mapeador los
// manda y el `fromJson` tiene que ignorarlos sin romperse.

/// Un anuncio tal como lo devuelve `aAnuncio`.
Map<String, dynamic> anuncioJson({
  String id = 'an-1',
  String seccionId = 'sec-1',
  String titulo = 'Bienvenidos al aula',
  String cuerpo = 'Aquí encontrarás el material y las tareas del lapso.',
  String estado = 'PUBLICADO',
  String? programadoPara,
  String? publicadoEn = '2026-09-20T12:00:00.000Z',
}) =>
    {
      'id': id,
      'seccionId': seccionId,
      'autorId': 'doc-1',
      'titulo': titulo,
      'cuerpo': cuerpo,
      'estado': estado,
      'programadoPara': programadoPara,
      'publicadoEn': publicadoEn,
    };

/// Una tarea tal como la devuelve `aTarea`.
///
/// `puntosMaximos` es `Object` y no `double` para poder mandar **un entero o un
/// decimal**: la columna es `numeric(4,2)` y el JSON puede traer los dos.
Map<String, dynamic> tareaJson({
  String id = 'tar-1',
  String seccionId = 'sec-1',
  String titulo = 'Informe de soldadura',
  String descripcion = 'Entrega el informe con las mediciones del taller.',
  String tipo = 'TAREA',
  Object puntosMaximos = 20,
  String? fechaLimite = '2026-10-30T23:59:00.000Z',
  String? tema,
  int orden = 0,
  String estado = 'PUBLICADO',
}) =>
    {
      'id': id,
      'seccionId': seccionId,
      'titulo': titulo,
      'descripcion': descripcion,
      'tipo': tipo,
      'puntosMaximos': puntosMaximos,
      'fechaLimite': fechaLimite,
      'permitirEntregaTardia': true,
      'tema': tema,
      'orden': orden,
      'estado': estado,
      'publicadoEn': '2026-09-20T12:00:00.000Z',
    };

/// Una entrega del alumno tal como la devuelve `aEntrega`.
///
/// **No trae `estudianteId` ni `notaBorrador`**: el mapeador no los emite, y la
/// segunda está además vetada por el `GRANT` por columna. `extra` existe para
/// colar una clave a propósito y comprobar que el modelo la ignora.
Map<String, dynamic> entregaJson({
  String id = 'ent-1',
  String tareaId = 'tar-1',
  String estado = 'ASIGNADA',
  bool esTardia = false,
  Object? notaAsignada,
  String? entregadaEn,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'tareaId': tareaId,
      'estado': estado,
      'esTardia': esTardia,
      'notaAsignada': notaAsignada,
      'entregadaEn': entregadaEn,
      ...extra,
    };

/// Una fila del libro de calificaciones, tal como la devuelve `aLibroEntrega`.
Map<String, dynamic> libroEntregaJson({
  String id = 'ent-1',
  String estudianteId = 'est-1',
  String estado = 'ENTREGADA',
  bool esTardia = false,
  Object? notaBorrador = 15.5,
  Object? notaAsignada,
  String? entregadaEn = '2026-09-21T10:00:00.000Z',
  String? devueltaEn,
  bool faltante = false,
}) =>
    {
      'id': id,
      'estudianteId': estudianteId,
      'estado': estado,
      'esTardia': esTardia,
      'notaBorrador': notaBorrador,
      'notaAsignada': notaAsignada,
      'entregadaEn': entregadaEn,
      'devueltaEn': devueltaEn,
      'faltante': faltante,
    };

/// El objeto que devuelven `calificar` y `devolver` (`aEntregaCalificada`).
///
/// **`devueltaEn` NO está**: `JSON.stringify` borra las claves `undefined`, y la
/// RPC de calificar no toca `devuelta_en`. Tampoco trae `faltante` ni
/// `entregadaEn`, que son del libro. Reproduce las tres ausencias a la vez
/// porque las tres llegan en el mismo `payload`.
Map<String, dynamic> entregaCalificadaJson({
  String id = 'ent-1',
  String tareaId = 'tar-1',
  String estudianteId = 'est-1',
  String estado = 'ENTREGADA',
  bool esTardia = false,
  Object? notaBorrador = 17.5,
  Object? notaAsignada,
}) =>
    {
      'id': id,
      'tareaId': tareaId,
      'estudianteId': estudianteId,
      'estado': estado,
      'esTardia': esTardia,
      'notaBorrador': notaBorrador,
      'notaAsignada': notaAsignada,
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

  group('tablon · el feed del aula', () {
    test('pide la ruta de la sección con el token y desempaqueta `anuncios`',
        () async {
      final falso = BackendFalso({
        'GET ${rutaTablon('sec-1')}': json({
          'anuncios': [
            anuncioJson(),
            anuncioJson(id: 'an-2', titulo: 'Segundo anuncio'),
          ],
        }),
      });

      final anuncios = await gatewayDe(falso).tablon('sec-1');

      expect(anuncios, hasLength(2));
      expect(anuncios.first.id, 'an-1');
      expect(anuncios.first.titulo, 'Bienvenidos al aula');
      expect(anuncios.first.estado, EstadoAnuncio.publicado);
      expect(anuncios.first.publicadoEn, '2026-09-20T12:00:00.000Z');
      // El orden es el del servidor: el gateway no re-ordena.
      expect(anuncios.map((a) => a.id), ['an-1', 'an-2']);

      final peticion = falso.porRuta('GET', rutaTablon('sec-1'));
      expect(peticion, isNotNull, reason: 'no se pidió el tablón de la sección');
      expect(peticion!.headers['Authorization'], 'Bearer $tokenPrueba');
    });

    test('un anuncio programado sin publicar trae las dos fechas nulas', () async {
      final falso = BackendFalso({
        'GET ${rutaTablon('sec-1')}': json({
          'anuncios': [
            anuncioJson(
              estado: 'BORRADOR',
              programadoPara: '2026-10-01T08:00:00.000Z',
              publicadoEn: null,
            ),
          ],
        }),
      });

      final anuncio = (await gatewayDe(falso).tablon('sec-1')).single;

      expect(anuncio.estado, EstadoAnuncio.borrador);
      expect(anuncio.programadoPara, '2026-10-01T08:00:00.000Z');
      expect(anuncio.publicadoEn, isNull);
    });
  });

  group('trabajoDeClase · puntos y tipos', () {
    test('pide la ruta de la sección y desempaqueta `tareas`', () async {
      final falso = BackendFalso({
        'GET ${rutaTrabajo('sec-2')}': json({'tareas': [tareaJson()]}),
      });

      final tareas = await gatewayDe(falso).trabajoDeClase('sec-2');

      final tarea = tareas.single;
      expect(tarea.tipo, TipoTarea.tarea);
      expect(tarea.puntosMaximos, 20);
      expect(tarea.fechaLimite, '2026-10-30T23:59:00.000Z');
      expect(tarea.orden, 0);

      // El id de la sección viaja en la ruta: pedir `sec-1` y recibir la
      // respuesta de `sec-2` sería un fallo silencioso.
      expect(falso.porRuta('GET', rutaTrabajo('sec-2')), isNotNull);
      expect(falso.porRuta('GET', rutaTrabajo('sec-1')), isNull);
    });

    test('`puntosMaximos` entero (20) y decimal (17.5) se leen los dos', () async {
      // La columna es `numeric(4,2)`, así que un 17,5 es válido; pero un 20
      // puede llegar como entero. Un `as double` sobre el entero reventaría en
      // tiempo de ejecución, y el `fromJson` tiene que aceptar los dos.
      final falso = BackendFalso({
        'GET ${rutaTrabajo('sec-1')}': json({
          'tareas': [
            tareaJson(id: 'tar-entera', puntosMaximos: 20),
            tareaJson(id: 'tar-decimal', puntosMaximos: 17.5),
          ],
        }),
      });

      final tareas = await gatewayDe(falso).trabajoDeClase('sec-1');

      expect(tareas.map((t) => t.puntosMaximos), [20.0, 17.5]);
    });

    test('un material sin puntos ni plazo llega como 0 y nulo, no como error',
        () async {
      // El `CHECK` de coherencia le prohíbe puntos y fecha límite a un MATERIAL.
      // La UI no debe pintar «0 pts» sobre material de lectura.
      final falso = BackendFalso({
        'GET ${rutaTrabajo('sec-1')}': json({
          'tareas': [
            tareaJson(
              tipo: 'MATERIAL',
              puntosMaximos: 0,
              fechaLimite: null,
              tema: 'Unidad 1',
            ),
          ],
        }),
      });

      final tarea = (await gatewayDe(falso).trabajoDeClase('sec-1')).single;

      expect(tarea.tipo, TipoTarea.material);
      expect(tarea.tipo.seCalifica, isFalse);
      expect(tarea.puntosMaximos, 0);
      expect(tarea.fechaLimite, isNull);
      expect(tarea.tema, 'Unidad 1');
    });
  });

  group('misEntregas · la entrega del alumno', () {
    test('va a /mis-entregas sin parámetros y desempaqueta `entregas`', () async {
      final falso = BackendFalso({
        'GET $rutaMisEntregas': json({
          'entregas': [
            entregaJson(id: 'e1'),
            entregaJson(
              id: 'e2',
              estado: 'ENTREGADA',
              esTardia: true,
              entregadaEn: '2026-09-21T10:00:00.000Z',
            ),
          ],
        }),
      });

      final entregas = await gatewayDe(falso).misEntregas();

      expect(entregas, hasLength(2));
      expect(entregas.first.estado, EstadoEntrega.asignada);
      expect(entregas.last.esTardia, isTrue);
      expect(entregas.last.entregadaEn, '2026-09-21T10:00:00.000Z');

      final peticion = falso.porRuta('GET', rutaMisEntregas)!;
      expect(peticion.headers['Authorization'], 'Bearer $tokenPrueba');
      // El «yo» lo pone `auth.uid()` en el servidor: el cliente no manda filtro.
      expect(peticion.url.queryParameters, isEmpty);
    });

    test('`notaAsignada` entera o decimal se lee como double', () async {
      final falso = BackendFalso({
        'GET $rutaMisEntregas': json({
          'entregas': [
            entregaJson(id: 'e1', estado: 'DEVUELTA', notaAsignada: 18),
            entregaJson(id: 'e2', estado: 'DEVUELTA', notaAsignada: 15.5),
          ],
        }),
      });

      final entregas = await gatewayDe(falso).misEntregas();

      expect(entregas.map((e) => e.notaAsignada), [18.0, 15.5]);
    });

    test('una `notaBorrador` colada NO se convierte en nota asignada', () async {
      // El `GRANT` por columna impide que `nota_borrador` viaje al alumno, pero
      // si un cambio futuro la colara en el `payload`, el modelo no debe
      // confundirla con la nota asignada: el alumno no ve su nota hasta que el
      // docente devuelve (D-6). `Entrega` no tiene el campo, y esta prueba lo
      // fija.
      final falso = BackendFalso({
        'GET $rutaMisEntregas': json({
          'entregas': [
            entregaJson(
              estado: 'ENTREGADA',
              extra: {'notaBorrador': 17},
            ),
          ],
        }),
      });

      final entrega = (await gatewayDe(falso).misEntregas()).single;

      expect(entrega.notaAsignada, isNull);
    });

    test('las claves son camelCase: una snake_case no cuela en silencio',
        () async {
      // Sin esquema Zod de respuesta, la forma la fija el mapeador. Si el
      // `fromJson` leyera `tarea_id` —la columna— en vez de `tareaId` —la
      // clave—, un `payload` real devolvería `null` y la pantalla se vería
      // vacía sin que nada avisara. Aquí revienta, que es lo que queremos.
      final falso = BackendFalso({
        'GET $rutaMisEntregas': json({
          'entregas': [
            {'id': 'e1', 'tarea_id': 'tar-1', 'estado': 'ASIGNADA'},
          ],
        }),
      });

      await expectLater(
        gatewayDe(falso).misEntregas(),
        throwsA(isA<TypeError>()),
      );
    });

    test('una lista vacía —o una clave ausente— no es un error', () async {
      // El libro de calificaciones del docente devuelve `200 { entregas: [] }` a
      // quien no dicta la sección: un libro vacío es indistinguible de «no hay
      // entregas», y ninguno de los dos es un fallo. El sobre de M6 se
      // desempaqueta con el mismo ayudante en las tres lecturas, así que la
      // tolerancia se prueba aquí una vez.
      final vacio = BackendFalso({
        'GET $rutaMisEntregas': json({'entregas': <Object>[]}),
      });
      final sinClave = BackendFalso({
        'GET $rutaMisEntregas': json(<String, Object>{}),
      });

      expect(await gatewayDe(vacio).misEntregas(), isEmpty);
      expect(await gatewayDe(sinClave).misEntregas(), isEmpty);
    });
  });

  group('entregar y reclamar · misma forma, distinto verbo', () {
    test('entregar hace POST a su ruta, sin cuerpo y sin Content-Type', () async {
      final falso = BackendFalso({
        'POST ${rutaEntregar('ent-1')}': json({
          'entrega': entregaJson(
            estado: 'ENTREGADA',
            esTardia: true,
            entregadaEn: '2026-09-22T10:00:00.000Z',
          ),
        }),
      });

      final entrega = await gatewayDe(falso).entregar('ent-1');

      expect(entrega.estado, EstadoEntrega.entregada);
      expect(entrega.esTardia, isTrue);
      expect(entrega.entregadaEn, '2026-09-22T10:00:00.000Z');

      final peticion = falso.porRuta('POST', rutaEntregar('ent-1'))!;
      expect(peticion.headers['Authorization'], 'Bearer $tokenPrueba');
      // Sin cuerpo, `ApiClient` no declara JSON: declararlo dispararía el
      // `FST_ERR_CTP_EMPTY_JSON_BODY` de Fastify.
      expect(peticion.headers.containsKey('Content-Type'), isFalse);
      expect(peticion.body, isEmpty);
    });

    test('reclamar hace POST a su ruta y devuelve la misma forma', () async {
      // La RPC de reclamar devuelve `id, tarea_id, estado, es_tardia,
      // nota_asignada, entregada_en`, igual que la de entregar: la misma
      // `Entrega` en camelCase.
      final falso = BackendFalso({
        'POST ${rutaReclamar('ent-7')}': json({
          'entrega': entregaJson(id: 'ent-7', estado: 'RECLAMADA'),
        }),
      });

      final entrega = await gatewayDe(falso).reclamar('ent-7');

      expect(entrega.id, 'ent-7');
      expect(entrega.estado, EstadoEntrega.reclamada);

      final peticion = falso.porRuta('POST', rutaReclamar('ent-7'))!;
      expect(peticion.headers['Authorization'], 'Bearer $tokenPrueba');
      expect(peticion.headers.containsKey('Content-Type'), isFalse);
      expect(peticion.body, isEmpty);
    });

    test('un 400 al entregar tarde llega con el mensaje del servidor', () async {
      final falso = BackendFalso({
        'POST ${rutaEntregar('ent-1')}': errorJson(
          400,
          'TAREA_CERRADA',
          'La tarea cerró el 30/10/2026 y no admite entregas tardías.',
        ),
      });

      await expectLater(
        gatewayDe(falso).entregar('ent-1'),
        throwsA(
          isA<AppException>()
              .having(
                (e) => e.message,
                'message',
                'La tarea cerró el 30/10/2026 y no admite entregas tardías.',
              )
              .having((e) => e.type, 'type', AppErrorType.validacion)
              .having((e) => e.code, 'code', 'TAREA_CERRADA'),
        ),
      );
    });
  });

  group('LibroEntrega · el libro del docente', () {
    test('lee `notaBorrador`, `devueltaEn` y `faltante` de la fila del libro', () {
      final libro = LibroEntrega.fromJson(libroEntregaJson());

      expect(libro.estudianteId, 'est-1');
      expect(libro.estado, EstadoEntrega.entregada);
      expect(libro.notaBorrador, 15.5);
      expect(libro.notaAsignada, isNull);
      expect(libro.devueltaEn, isNull);
      expect(libro.faltante, isFalse);
    });

    test('`faltante` llega derivado de la RPC y se lee tal cual', () {
      // «No entregó y ya venció» lo deriva la RPC al leer, no lo recalcula el
      // cliente: el reloj que decide es el de la base.
      final libro = LibroEntrega.fromJson(
        libroEntregaJson(estado: 'ASIGNADA', notaBorrador: null, faltante: true),
      );

      expect(libro.faltante, isTrue);
      expect(libro.notaBorrador, isNull);
    });

    test('tolera que `devueltaEn` venga AUSENTE, no sólo nula', () {
      // La respuesta de `calificar` no toca `devuelta_en`, y `JSON.stringify`
      // borra las claves `undefined`: la clave no llega. Parsear sin dar por
      // hecho que existe es lo que evita reventar sobre una clave ausente.
      final calificada = entregaCalificadaJson();
      expect(calificada.containsKey('devueltaEn'), isFalse);

      final libro = LibroEntrega.fromJson(calificada);

      expect(libro.devueltaEn, isNull);
      expect(libro.notaBorrador, 17.5);
      expect(libro.estudianteId, 'est-1');
    });

    test('el objeto de `calificar` no trae `faltante` ni `entregadaEn` y aun así parsea',
        () {
      // Mismo linaje de `payload`: la RPC de calificar devuelve `notaBorrador` y
      // `devueltaEn`, pero no la columna derivada `faltante`. Si el `fromJson`
      // la exigiera, la respuesta del docente reventaría al parsear.
      final calificada = entregaCalificadaJson();
      expect(calificada.containsKey('faltante'), isFalse);
      expect(calificada.containsKey('entregadaEn'), isFalse);

      final libro = LibroEntrega.fromJson(calificada);

      expect(libro.faltante, isFalse);
      expect(libro.esTardia, isFalse);
      expect(libro.notaAsignada, isNull);
    });

    test('una nota borrador entera o decimal se lee como double', () {
      expect(
        LibroEntrega.fromJson(libroEntregaJson(notaBorrador: 18)).notaBorrador,
        18.0,
      );
      expect(
        LibroEntrega.fromJson(libroEntregaJson(notaBorrador: 17.5)).notaBorrador,
        17.5,
      );
    });
  });
}
