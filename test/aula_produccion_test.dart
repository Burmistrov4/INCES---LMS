import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/core/network/api_client.dart';
import 'package:inces_lms_app/screens/aula_virtual_dashboard.dart';
import 'package:inces_lms_app/screens/docente_dashboard.dart';
import 'package:inces_lms_app/screens/mis_aulas_panel.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/services/aula_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_aula_gateway.dart';
import 'support/fake_gateway.dart';

/// El aula **en producción**: que se abra de verdad y que las pruebas que piden
/// un listado sin contenido sigan viendo lo que piden.
///
/// ## El hueco que estas pruebas cierran
///
/// Los dashboards construían `PanelMisAulas(aulaGateway: widget.aulaGateway)`.
/// En producción nadie inyecta `aulaGateway`, así que llegaba `null`, el panel
/// marcaba la tarjeta como **no** pulsable y el aula no se podía abrir **nunca**:
/// todo el servicio de contenido de M6 quedaba inalcanzable desde la UI.
///
/// ## La trampa que estas pruebas vigilan
///
/// El arreglo no puede ser `widget.aulaGateway ?? BackendAulaGateway()`. Hay un
/// caso legítimo —el de las pruebas de widget— en el que se inyecta **sólo** el
/// gateway del listado (`aulasPropias`) y se deja `aulaGateway` en `null` para
/// pedir un listado **sin** aula abrible. Con el `??` ingenuo ese caso recibiría
/// un servicio real, la tarjeta pasaría a ser pulsable y el toque saldría a la
/// red. Por eso la condición es «no se inyectó **nada**», y por eso hay una
/// prueba para cada lado de la moneda.
///
/// **Lo que estas pruebas NO pueden probar:** que el backend responda, ni que la
/// RLS deje ver lo que dice. Eso lo cubre la suite de PGlite y el humo del
/// backend. Aquí sólo se prueba el **cableado** y que la forma del `payload`
/// real llega hasta la pantalla.
const String _baseApi = 'https://api.inces.test';

/// La etiqueta del aula de ejemplo por defecto.
const String _etiquetaAula = 'Soldadura · Sección A · Formación Profesional';

/// Respuesta JSON declarando UTF-8, igual que en `aula_service_test.dart`.
http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(
      jsonEncode(cuerpo),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Backend doblado que enruta por «MÉTODO /ruta» y **guarda lo pedido**.
///
/// Falla en alto con una ruta sin doblar en vez de devolver un 200 por defecto:
/// un 200 dejaría pasar una prueba por la razón equivocada.
class _BackendDoblado {
  _BackendDoblado(this.respuestas);

  final Map<String, http.Response> respuestas;
  final List<http.Request> recibidas = [];

  http.Client get cliente => MockClient((peticion) async {
        recibidas.add(peticion);

        final respuesta = respuestas['${peticion.method} ${peticion.url.path}'];
        if (respuesta == null) {
          return _json({
            'error': {
              'codigo': 'RUTA_NO_DOBLADA',
              'mensaje': 'El test no dobló '
                  '${peticion.method} ${peticion.url.path}',
            },
          }, 599);
        }
        return respuesta;
      });

  bool pidio(String metodo, String ruta) => recibidas
      .any((p) => p.method == metodo && p.url.path == ruta);
}

/// El servicio de contenido **real** sobre un backend doblado.
///
/// Es el objeto de producción —el que usa la app— y sólo se dobla el
/// `http.Client` de debajo. Doblar el cliente y no el gateway es lo que hace que
/// estas pruebas ejerciten el parseo y el desempaquetado de verdad.
BackendAulaGateway _aulaReal(_BackendDoblado backend) => BackendAulaGateway(
      api: ApiClient(httpClient: backend.cliente, baseUrl: _baseApi),
      tokenSesion: () => 'jwt-de-prueba',
    );

/// Monta el dashboard del docente con lo mínimo.
///
/// Se usa el del **docente** y no el del estudiante por una razón de forma: su
/// primera sección ya es «Mis aulas», así que el panel se monta sin tener que
/// navegar por el menú. La lógica del cableado es la misma en los dos.
///
/// `auth` se dobla **siempre**: sin él, `AuthService` leería
/// `Supabase.instance`, que lanza si Supabase no está inicializado. Es la
/// inyección mínima para que la prueba no toque Supabase, y no tiene nada que
/// ver con las puertas del aula —que es lo que estas pruebas deciden inyectar o
/// no—.
Future<void> _montarDocente(
  WidgetTester tester, {
  AulaGateway? aulaGateway,
  AulasPropiasGateway? aulasPropias,
}) async {
  // Ventana ancha y alta: por debajo de 900 px el menú pasa a cajón y a 1280
  // arranca replegado; y el listado de aulas es un `ListView`, que con la
  // ventana por defecto (800×600) dejaría las tarjetas fuera del viewport.
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: DocenteDashboardScreen(
        auth: AuthService(gateway: FakeGateway()),
        aulaGateway: aulaGateway,
        aulasPropias: aulasPropias,
      ),
    ),
  );
  await _asentar(tester);
}

/// Avanza lo justo para que terminen las cargas.
///
/// **Sin `pumpAndSettle`**: mientras carga hay un `CircularProgressIndicator`,
/// que anima indefinidamente y agotaría el tiempo límite. Sería un fallo de la
/// prueba, no del código.
Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('resolverPuertaDeContenido · la regla', () {
    test('sin inyectar nada resuelve el servicio real', () {
      // Es el caso de producción: nadie inyecta, y el aula tiene que abrirse.
      final puerta = resolverPuertaDeContenido(
        inyectada: null,
        listadoInyectado: null,
      );

      expect(puerta, isA<BackendAulaGateway>());
    });

    test('con el listado inyectado y sin contenido, no hay puerta', () {
      // La seguridad de las pruebas. Quien inyecta el listado y deja el
      // contenido nulo está pidiendo un listado SIN aula abrible; devolverle un
      // servicio real lo sacaría a la red.
      final puerta = resolverPuertaDeContenido(
        inyectada: null,
        listadoInyectado: FakeAulaGateway(),
      );

      expect(puerta, isNull);
    });

    test('una puerta inyectada se respeta tal cual', () {
      final doble = FakeAulaGateway();

      expect(
        resolverPuertaDeContenido(inyectada: doble, listadoInyectado: null),
        same(doble),
      );
      // Aunque además se inyecte el listado, la puerta de contenido manda: es
      // lo que pidió quien la inyectó.
      expect(
        resolverPuertaDeContenido(
          inyectada: doble,
          listadoInyectado: FakeAulaGateway(),
        ),
        same(doble),
      );
    });
  });

  group('el dashboard en producción', () {
    testWidgets('sin inyectar nada, el panel recibe el servicio real de contenido',
        (tester) async {
      // Hoy —antes del arreglo— esta prueba falla: el panel recibía `null`.
      await _montarDocente(tester);

      final panel = tester.widget<PanelMisAulas>(find.byType(PanelMisAulas));

      expect(
        panel.aulaGateway,
        isA<BackendAulaGateway>(),
        reason: 'en producción el panel tiene que recibir el servicio real; con '
            '`null` la tarjeta no se puede pulsar y el aula nunca se abre',
      );
    });

    testWidgets('con el servicio real, pulsar la tarjeta abre el Aula Virtual',
        (tester) async {
      // El listado y el contenido salen del **mismo** `BackendAulaGateway` real,
      // sobre un backend doblado: es el camino de producción, sin red.
      final backend = _BackendDoblado({
        'GET /api/v1/mi-horario': _json({
          'rol': 'docente',
          'periodo': 'SA26-2',
          'clases': [
            {
              'id': 'cl-1',
              'seccionId': 'sec-1',
              'docenteId': 'doc-1',
              'aulaId': 'aul-1',
              'dia': 1,
              'bloque': 1,
              'turno': 'MAÑANA',
              'activa': true,
              'periodo': 'SA26-2',
              'programaId': 'pro-1',
              'programa': 'Formación Profesional',
              'materiaId': 'mat-1',
              'materia': 'Soldadura',
              'seccion': 'Sección A',
              'aula': 'Taller 3',
              'docente': 'Ana Pérez',
            },
          ],
          'guardias': <Object>[],
        }),
        'GET /api/v1/aula/secciones/sec-1/tablon': _json({
          'anuncios': [
            {
              'id': 'an-1',
              'seccionId': 'sec-1',
              'autorId': 'doc-1',
              'titulo': 'Bienvenidos al aula',
              'cuerpo': 'Aquí está el material del lapso.',
              'estado': 'PUBLICADO',
              'programadoPara': null,
              'publicadoEn': '2026-09-20T12:00:00.000Z',
            },
          ],
        }),
        'GET /api/v1/aula/secciones/sec-1/trabajo': _json({'tareas': <Object>[]}),
      });

      await _montarDocente(tester, aulaGateway: _aulaReal(backend));

      // La tarjeta existe y es pulsable: la puerta es real.
      expect(find.text(_etiquetaAula), findsOneWidget);
      await tester.tap(find.text(_etiquetaAula));
      await _asentar(tester);

      // Se llegó al aula…
      expect(find.byType(AulaVirtualDashboardScreen), findsOneWidget);
      // …y cargó su tablón con el servicio real, no con un doble: el anuncio del
      // `payload` llegó hasta la pantalla.
      expect(find.text('Bienvenidos al aula'), findsOneWidget);
      expect(
        backend.pidio('GET', '/api/v1/aula/secciones/sec-1/tablon'),
        isTrue,
        reason: 'el aula abierta tiene que pedir el tablón de **su** sección',
      );
    });

    testWidgets('si sólo se inyecta el listado, el aula sigue sin poder abrirse',
        (tester) async {
      // La prueba de seguridad, ahora en el dashboard: es el caso que un
      // `?? BackendAulaGateway()` ingenuo rompería.
      final listado = FakeAulaGateway()..misAulasResultado = misAulasEjemplo();

      await _montarDocente(tester, aulasPropias: listado);

      final panel = tester.widget<PanelMisAulas>(find.byType(PanelMisAulas));
      expect(
        panel.aulaGateway,
        isNull,
        reason: 'inyectar sólo el listado es pedir un listado sin aula abrible',
      );

      // El listado sí se pintó: la tarjeta está y el toque no la abre.
      expect(find.text(_etiquetaAula), findsOneWidget);
      await tester.tap(find.text(_etiquetaAula), warnIfMissed: false);
      await _asentar(tester);

      expect(find.byType(AulaVirtualDashboardScreen), findsNothing);
      expect(
        listado.llamadas.where((l) => l.startsWith('tablon')),
        isEmpty,
        reason: 'sin puerta de contenido no se puede pedir ningún tablón',
      );
    });
  });
}
