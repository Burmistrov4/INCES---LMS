import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/archivo.dart';
import 'package:inces_lms_app/services/archivos_service.dart';

/// Capa de datos de M5: el gateway contra un `http.Client` doblado.
///
/// **Por qué aquí y no en el repositorio.** El repositorio del proyecto no habla
/// HTTP (ADR-010): envuelve el gateway en `Result`. Los tres pasos de la subida
/// son tres llamadas HTTP, así que su sitio es el gateway, y es el gateway lo que
/// hay que probar con un cliente doblado.
///
/// **Qué se verifica de verdad aquí.** No sólo los códigos de estado: también
/// *qué se envió*. Que el `PUT` vaya a R2 y no al backend, que lleve el
/// `Content-Type` que el servidor firmó, que el `POST` de confirmar no declare
/// JSON sin cuerpo, y que un `PUT` fallido **no** confirme el archivo. Nada de eso
/// se ve en el valor de retorno.
///
/// **Lo que este archivo NO puede probar:** que R2 acepte la firma, que el objeto
/// pese lo que dice, y que un `Content-Type` mentido sea rechazado de verdad. Eso
/// necesita el bucket real y lo cubre `supabase/humo-archivos.mjs`.
const String baseApi = 'https://api.inces.test';
const String idArchivo = 'a1b2c3d4-0000-4000-8000-000000000001';
const String rutaR2 = '/bucket/m5_archivos/clave.pdf';
const String urlR2 = 'https://cuenta.r2.cloudflarestorage.com$rutaR2?firma=abc';
const String tokenPrueba = 'jwt-de-prueba';

/// Los bytes que se suben. Deterministas: un `List<int>` fijo permite comparar
/// el cuerpo del `PUT` byte a byte.
const List<int> contenido = [37, 80, 68, 70, 45, 49, 46, 52];

/// Respuesta JSON declarando UTF-8 a propósito.
///
/// Sin el `charset`, `http.Response` codifica en **latin1**, y un nombre con
/// acento se compara distinto según por dónde haya pasado. Es la clase de detalle
/// que hace fallar una prueba por la razón equivocada.
http.Response json(Object cuerpo, [int estado = 200]) => http.Response(
      jsonEncode(cuerpo),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Cuerpo de error con el sobre uniforme del backend.
http.Response errorJson(int estado, String codigo, String mensaje) =>
    json({
      'error': {'codigo': codigo, 'mensaje': mensaje},
    }, estado);

Map<String, dynamic> archivoJson({
  String estado = 'PENDING',
  int? tamanoBytes,
  String tipoContenido = 'application/pdf',
  String nombreOriginal = 'Constancia José.pdf',
}) =>
    {
      'id': idArchivo,
      'propietarioId': 'prop-1',
      'r2Key': 'm5_archivos/prop-1/2026/09/clave.pdf',
      'nombreOriginal': nombreOriginal,
      'tipoContenido': tipoContenido,
      'tamanoBytes': tamanoBytes,
      'entityType': 'TASK_SUBMISSION',
      'entidadId': null,
      'estado': estado,
      'creadoEn': '2026-09-18T12:00:00.000Z',
      'confirmadoEn': null,
      'borradoEn': null,
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
      if (peticion.method == metodo && peticion.url.path == ruta) return peticion;
    }
    return null;
  }
}

/// Las respuestas del camino feliz: los tres pasos, en verde.
Map<String, http.Response> respuestasFelices({
  String tipoContenido = 'application/pdf',
  int tamanoBytes = 8,
}) =>
    {
      'POST /api/v1/archivos/firmar-subida': json({
        'archivo': archivoJson(tipoContenido: tipoContenido),
        'urlDeSubida': urlR2,
        'expiraEnSegundos': 900,
      }, 201),
      'PUT $rutaR2': http.Response('', 200),
      'POST /api/v1/archivos/$idArchivo/confirmar': json({
        'archivo': archivoJson(estado: 'CONFIRMED', tamanoBytes: tamanoBytes),
      }),
    };

BackendArchivosGateway gatewayDe(BackendFalso falso, {String? token = tokenPrueba}) =>
    BackendArchivosGateway(
      httpClient: falso.cliente,
      baseUrl: baseApi,
      tokenSesion: () => token,
    );

Future<Archivo> subirDePrueba(BackendArchivosGateway gateway) => gateway.subir(
      nombreOriginal: 'Constancia José.pdf',
      entityType: TipoEntidadArchivo.taskSubmission,
      contenido: contenido,
    );

void main() {
  group('el ciclo de tres pasos', () {
    test('subir hace firmar → PUT a R2 → confirmar, en ese orden', () async {
      final falso = BackendFalso(respuestasFelices());
      final gateway = gatewayDe(falso);

      final archivo = await subirDePrueba(gateway);

      expect(archivo.estado, EstadoArchivo.confirmed);
      expect(archivo.tamanoBytes, contenido.length);

      expect(
        falso.recibidas.map((p) => '${p.method} ${p.url.path}').toList(),
        <String>[
          'POST /api/v1/archivos/firmar-subida',
          'PUT $rutaR2',
          'POST /api/v1/archivos/$idArchivo/confirmar',
        ],
        reason: 'los tres pasos van en orden y el PUT se intercala',
      );
    });

    test('el PUT va a R2 directamente, no al backend', () async {
      final falso = BackendFalso(respuestasFelices());

      await subirDePrueba(gatewayDe(falso));

      final put = falso.porRuta('PUT', rutaR2);
      expect(put, isNotNull);
      expect(put!.url.host, 'cuenta.r2.cloudflarestorage.com');
      expect(
        put.bodyBytes,
        contenido,
        reason: 'los bytes van a R2 tal cual: el backend nunca los ve',
      );
    });

    test('el PUT lleva el Content-Type que devolvió el servidor', () async {
      // El servidor devuelve un tipo que el cliente NO podría deducir del
      // nombre. Si el cliente lo adivinara por su cuenta, esta prueba falla.
      final falso = BackendFalso(
        respuestasFelices(tipoContenido: 'application/x-firmado-por-el-servidor'),
      );

      await subirDePrueba(gatewayDe(falso));

      expect(
        falso.porRuta('PUT', rutaR2)!.headers['content-type'],
        'application/x-firmado-por-el-servidor',
        reason: 'la URL prefirmada cubre el Content-Type: adivinarlo la rompe',
      );
    });

    test('si el PUT falla, NO se confirma el archivo', () async {
      final respuestas = respuestasFelices();
      respuestas['PUT $rutaR2'] = http.Response('AccessDenied', 403);
      final falso = BackendFalso(respuestas);

      await expectLater(
        subirDePrueba(gatewayDe(falso)),
        throwsA(
          isA<AppException>().having((e) => e.code, 'code', 'SUBIDA_RECHAZADA'),
        ),
      );

      expect(falso.recibidas, hasLength(2), reason: 'firmar y el PUT, nada más');
      expect(
        falso.porRuta('POST', '/api/v1/archivos/$idArchivo/confirmar'),
        isNull,
        reason: 'confirmar un objeto que no llegó sería sellar una mentira',
      );
    });

    test('el paso 1 manda nombre, entidad y entidadId nulo explícito', () async {
      final falso = BackendFalso(respuestasFelices());

      await subirDePrueba(gatewayDe(falso));

      final cuerpo = jsonDecode(
        falso.porRuta('POST', '/api/v1/archivos/firmar-subida')!.body,
      ) as Map<String, dynamic>;

      expect(cuerpo['nombreOriginal'], 'Constancia José.pdf');
      expect(cuerpo['entityType'], 'TASK_SUBMISSION');
      expect(
        cuerpo.containsKey('entidadId'),
        isTrue,
        reason: 'nulo es un valor legítimo: el archivo puede preceder a la tarea',
      );
      expect(cuerpo['entidadId'], isNull);
      expect(
        cuerpo.containsKey('tipoContenido'),
        isFalse,
        reason: 'el tipo lo deriva el servidor de la extensión, no el cliente',
      );
    });
  });

  group('traducción de errores del backend', () {
    test('413 → ARCHIVO_DEMASIADO_GRANDE y tipo VALIDACIÓN, no de servidor', () async {
      // Un archivo que se pasa del límite es algo que el usuario corrige. Si
      // cayera en «error de servidor», la UI diría «inténtalo en unos momentos»
      // y nadie arreglaría nada.
      final respuestas = respuestasFelices();
      respuestas['POST /api/v1/archivos/$idArchivo/confirmar'] = errorJson(
        413,
        'ARCHIVO_DEMASIADO_GRANDE',
        'El contenido supera el tamaño máximo permitido.',
      );

      await expectLater(
        subirDePrueba(gatewayDe(BackendFalso(respuestas))),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', 'ARCHIVO_DEMASIADO_GRANDE')
              .having((e) => e.type, 'type', AppErrorType.validacion)
              .having((e) => e.message, 'mensaje', contains('tamaño máximo')),
        ),
      );
    });

    test('503 (R2 apagado) llega como error de servidor con el mensaje del backend', () async {
      final respuestas = respuestasFelices();
      respuestas['POST /api/v1/archivos/firmar-subida'] = errorJson(
        503,
        'SERVICIO_NO_DISPONIBLE',
        'El almacenamiento de archivos no está configurado en este servidor.',
      );

      await expectLater(
        subirDePrueba(gatewayDe(BackendFalso(respuestas))),
        throwsA(
          isA<AppException>()
              .having((e) => e.type, 'type', AppErrorType.servidor)
              .having((e) => e.message, 'mensaje', contains('no está configurado')),
        ),
      );
    });

    test('dos 404 con causas opuestas se distinguen por el CÓDIGO', () async {
      // Mismo estado HTTP, significados contrarios: «la subida se cortó, repítela»
      // frente a «ese archivo no existe, no hay nada que repetir». El estado no
      // los separa; el código sí, y es lo que la UI necesita para decidir.
      Future<AppException> falloCon(String codigo) async {
        final respuestas = respuestasFelices();
        respuestas['POST /api/v1/archivos/$idArchivo/confirmar'] =
            errorJson(404, codigo, 'mensaje del backend');

        try {
          await subirDePrueba(gatewayDe(BackendFalso(respuestas)));
        } on AppException catch (e) {
          return e;
        }
        fail('se esperaba un AppException para $codigo');
      }

      final noLlego = await falloCon('OBJETO_NO_SUBIDO');
      final noExiste = await falloCon('ARCHIVO_INEXISTENTE');

      expect(noLlego.code, 'OBJETO_NO_SUBIDO');
      expect(noExiste.code, 'ARCHIVO_INEXISTENTE');
      expect(noLlego.code, isNot(noExiste.code));
    });
  });

  group('cabeceras y rutas', () {
    test('manda el JWT en Authorization', () async {
      final falso = BackendFalso(respuestasFelices());

      await subirDePrueba(gatewayDe(falso));

      expect(
        falso.porRuta('POST', '/api/v1/archivos/firmar-subida')!.headers['authorization'],
        'Bearer $tokenPrueba',
      );
    });

    test('sin sesión no manda Authorization (el backend responde 401)', () async {
      final falso = BackendFalso(respuestasFelices());

      await subirDePrueba(gatewayDe(falso, token: null));

      expect(
        falso.porRuta('POST', '/api/v1/archivos/firmar-subida')!.headers
            .containsKey('authorization'),
        isFalse,
      );
    });

    test('confirmar no declara Content-Type (trampa FST_ERR_CTP_EMPTY_JSON_BODY)', () async {
      // Un POST sin cuerpo con `Content-Type: application/json` hace que Fastify
      // responda 500. Es la trampa que ya mordió en las rutas sin body de M4.
      final falso = BackendFalso(respuestasFelices());

      await subirDePrueba(gatewayDe(falso));

      expect(
        falso
            .porRuta('POST', '/api/v1/archivos/$idArchivo/confirmar')!
            .headers
            .containsKey('content-type'),
        isFalse,
      );
    });

    test('borrar usa la ruta del propietario y borrarComoAdmin la de admin', () async {
      final respuestas = respuestasFelices();
      respuestas['DELETE /api/v1/archivos/$idArchivo'] =
          json({'archivo': archivoJson(estado: 'DELETED')});
      respuestas['DELETE /api/v1/admin/archivos/$idArchivo'] =
          json({'archivo': archivoJson(estado: 'DELETED')});
      final falso = BackendFalso(respuestas);
      final gateway = gatewayDe(falso);

      final propio = await gateway.borrar(idArchivo);
      final ajeno = await gateway.borrarComoAdmin(idArchivo);

      expect(propio.estado, EstadoArchivo.deleted);
      expect(ajeno.estado, EstadoArchivo.deleted);
      expect(falso.porRuta('DELETE', '/api/v1/archivos/$idArchivo'), isNotNull);
      expect(falso.porRuta('DELETE', '/api/v1/admin/archivos/$idArchivo'), isNotNull);
    });

    test('urlDeLectura conserva el nombre con acento que devuelve el servidor', () async {
      final respuestas = respuestasFelices();
      respuestas['GET /api/v1/archivos/$idArchivo/url-lectura'] = json({
        'urlDeLectura': 'https://cuenta.r2.cloudflarestorage.com$rutaR2?firma=z',
        'expiraEnSegundos': 300,
        'nombreOriginal': 'Constancia José.pdf',
      });
      final falso = BackendFalso(respuestas);

      final lectura = await gatewayDe(falso).urlDeLectura(idArchivo);

      expect(lectura.nombreOriginal, 'Constancia José.pdf');
      expect(lectura.urlDeLectura, contains('firma=z'));
      expect(lectura.expiraEnSegundos, 300);
    });
  });

  group('el modelo no tolera un contrato roto', () {
    test('un estado desconocido lanza en vez de degradar', () {
      // Si el backend añade un estado nuevo y el cliente lo ignorara en silencio,
      // la UI mostraría un archivo en un estado que no sabe pintar.
      expect(() => EstadoArchivo.desde('ARCHIVADO'), throwsFormatException);
      expect(() => EstadoArchivo.desde(null), throwsFormatException);
    });

    test('un tipo de entidad desconocido lanza', () {
      expect(() => TipoEntidadArchivo.desde('PRACTICA'), throwsFormatException);
    });

    test('sólo CONFIRMED es legible', () {
      expect(EstadoArchivo.confirmed.esLegible, isTrue);
      expect(EstadoArchivo.pending.esLegible, isFalse);
      expect(EstadoArchivo.deleted.esLegible, isFalse);
    });
  });
}
