import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/screens/aspirante/escaner_qr_screen.dart';
import 'package:inces_lms_app/screens/aspirante/marcar_asistencia_panel.dart';

import 'support/fake_asistencia_service.dart';

/// El escáner de QR (M7 · D21, segunda mitad) y su cableado en el panel.
///
/// **Qué se puede probar aquí y qué no, y por qué conviene decirlo.** En
/// `flutter test` no hay cámara: montar la vista previa de verdad haría que el
/// paquete intentara hablar con un canal de plataforma que no existe. Así que
/// esta suite **no** prueba que la cámara lea un QR —eso es del paquete, y se
/// comprueba en un dispositivo—. Prueba lo que sí es nuestro y sí puede fallar en
/// silencio:
///
/// 1. **La puerta de plataforma**, que decide en qué tres destinos aparece el
///    botón. Es una regla de producto con dos ramas y las dos se afirman.
/// 2. **El cableado**: que lo que devuelve el escáner se marque por la vía del
///    QR **con su sesión**, no por la manual. Si esto se rompiera, el alumno
///    marcaría igual y nadie lo notaría —la marca entraría por la otra vía—, que
///    es la peor clase de fallo: el que no se ve.
/// 3. **El antirrebote**, que es la parte del usuario que no se puede dejar en un
///    comentario: se ejerce el objeto que decide, no la cámara que alimenta.
/// 4. **Que una costura que devuelve basura no gaste una petición**, incluido el
///    caso que parece válido y no lo es: un UUID suelto, sin los seis dígitos.
///
/// **La trampa de plataforma, medida:** `flutter_test` **no** sobreescribe
/// `debugDefaultTargetPlatformOverride` —sólo lo hace `TargetPlatformVariant`,
/// que es opcional—, así que `defaultTargetPlatform` vale la plataforma
/// anfitriona. En el CI de Linux eso es `TargetPlatform.linux`, y por eso las
/// pruebas que necesitan ver el botón **fijan el override a mano** y lo devuelven
/// a `null` en `addTearDown`. Sin esa devolución, el propio `flutter_test` falla
/// la prueba por dejar un override global vivo.
void main() {
  late FakeAsistenciaService fake;

  setUp(() {
    fake = FakeAsistenciaService();
  });

  /// Fija la plataforma para una prueba y la deja limpia al terminar.
  ///
  /// `addTearDown` y no `tearDown` a propósito: así la limpieza viaja pegada a la
  /// prueba que ensucia, y no depende de que nadie se acuerde de un `tearDown`
  /// global el día que se añada otra prueba al archivo.
  void conPlataforma(TargetPlatform plataforma) {
    debugDefaultTargetPlatformOverride = plataforma;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  /// Monta el panel del alumno, con la costura del escáner que se quiera.
  Future<void> montarPanel(
    WidgetTester tester, {
    Widget? accionAdyacente,
    AbrirEscaner? abrirEscaner,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarcarAsistenciaPanel(
            servicio: fake,
            accionAdyacente: accionAdyacente,
            abrirEscaner: abrirEscaner,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// El par que codifica el QR del docente, tal como lo devolvería la cámara.
  const parDelQr = 'e5e5e5e5-0001-4001-8001-000000000001:471212';
  const sesionDelQr = 'e5e5e5e5-0001-4001-8001-000000000001';
  const mensajeNoEsQr = 'Ese código no es un QR de asistencia del INCES.';

  group('la puerta de plataforma', () {
    testWidgets('en Android el panel dibuja el botón del escáner',
        (tester) async {
      // La rama que sí: es uno de los tres destinos institucionales.
      conPlataforma(TargetPlatform.android);

      await montarPanel(tester);

      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.byTooltip('Escanear el código QR de la pizarra'), findsOneWidget);
      // El `Row` aguanta con el botón dentro: si faltara el `Expanded` del campo,
      // el desborde saldría como excepción de la prueba.
      expect(tester.takeException(), isNull);
    });

    testWidgets('en Linux el panel no dibuja nada: la pantalla queda como estaba',
        (tester) async {
      // La otra rama, y la que corre por defecto en el CI. Sin cámara no hay
      // botón, y el campo recupera el ancho entero. Es la garantía de que añadir
      // el escáner **no cambió** nada en macOS, Windows ni Linux.
      conPlataforma(TargetPlatform.linux);

      await montarPanel(tester);

      expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el botón del escáner puesto sigue habiendo UN solo FilledButton',
        (tester) async {
      // **Esta prueba protege a otra.** `asistencia_paneles_test.dart:575` hace
      // `tester.widget<FilledButton>(find.byType(FilledButton))`, que revienta por
      // ambigüedad si aparece un segundo `FilledButton` en el árbol. El botón del
      // escáner es un `IconButton` justamente por eso, y aquí se deja escrito para
      // que el día que alguien lo «mejore» a `FilledButton` se entere aquí y no
      // allí.
      conPlataforma(TargetPlatform.android);

      await montarPanel(tester);

      expect(find.byType(FilledButton), findsOneWidget);
    });

    test('la regla dice Android, iOS y Web; y no macOS, Windows ni Linux',
        () {
      // Se afirma la función directamente, sin montar nada: es la regla de
      // producto en su forma más desnuda, y así se lee de un vistazo cuál es la
      // lista. Ojo al matiz documentado: **macOS sí lo soporta el paquete**; se
      // excluye por alcance, no por incapacidad.
      for (final plataforma in [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        conPlataforma(plataforma);
        expect(
          plataformaPuedeEscanearQr,
          isTrue,
          reason: '$plataforma debería poder escanear',
        );
      }

      for (final plataforma in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        conPlataforma(plataforma);
        expect(
          plataformaPuedeEscanearQr,
          isFalse,
          reason: '$plataforma no está en el alcance',
        );
      }
    });
  });

  group('el cableado del escáner en el panel', () {
    testWidgets('lo leído se marca por la vía del QR, CON su sesión',
        (tester) async {
      // **La prueba que importa de verdad.** Si el escáner mandara el texto por la
      // vía manual —o si el panel lo tratara como seis dígitos—, la marca entraría
      // igual y nadie notaría que se perdió la sesión que el QR lleva dentro. Por
      // eso se afirman las dos cosas: la sesión **y** el código, y además que la
      // vía manual no se tocó.
      conPlataforma(TargetPlatform.android);

      await montarPanel(tester, abrirEscaner: (_) async => parDelQr);

      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pump();
      await tester.pump();

      expect(fake.ultimoSesionIdMarcado, sesionDelQr);
      expect(fake.ultimoCodigoMarcado, '471212');
      // La vía manual no se usó: sin esta línea, un panel que mandara los seis
      // dígitos sueltos pasaría la prueba de arriba si el doble rellenara los dos
      // campos a la vez.
      expect(fake.ultimoCodigoSuelto, isNull);

      // Y el texto leído queda en el campo: el escáner **rellena el campo**, no
      // marca por su cuenta. Es lo que hace que exista un solo camino de marcaje.
      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller?.text, parDelQr);

      expect(find.text('Listo. Ya cuentas.'), findsOneWidget);
    });

    testWidgets('si el alumno prefiere escribir, no se manda nada',
        (tester) async {
      // `null` es el veredicto de «quiero teclear»: el escáner se cierra y el
      // panel no manda ninguna petición ni pinta ningún error. Es la garantía de
      // que el plan B es de verdad un camino y no una salida que ensucia la
      // pantalla.
      conPlataforma(TargetPlatform.android);

      await montarPanel(tester, abrirEscaner: (_) async => null);

      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pump();
      await tester.pump();

      expect(fake.llamadas, isEmpty);
      expect(find.text(mensajeNoEsQr), findsNothing);
      // Y el campo sigue utilizable, que es el punto del plan B.
      await tester.enterText(find.byType(TextField), '471212');
      await tester.tap(find.text('Marcar'));
      await tester.pump();
      await tester.pump();
      expect(fake.ultimoCodigoSuelto, '471212');
    });

    testWidgets('un UUID suelto, sin los seis dígitos, se rechaza sin gastar petición',
        (tester) async {
      // **El caso que parece válido y no lo es**, y el que justifica que el
      // validador no sea «que tenga pinta de UUID». Un UUID suelto tiene el
      // formato que el usuario pidió comprobar, pero no es un código de
      // asistencia: el servidor no tendría seis dígitos que validar. Se rechaza
      // en el cliente, con un mensaje, en vez de gastar una petición para recibir
      // un «no» más lento.
      conPlataforma(TargetPlatform.android);

      await montarPanel(tester, abrirEscaner: (_) async => sesionDelQr);

      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pump();
      await tester.pump();

      expect(find.text(mensajeNoEsQr), findsOneWidget);
      expect(fake.llamadas, isEmpty);
    });

    testWidgets('una costura que devuelve basura tampoco gasta petición',
        (tester) async {
      // El panel **no se fía de la costura**: `abrirEscaner` es inyectable, así
      // que lo que devuelve se valida otra vez. El validador ya dijo que sí dentro
      // del escáner, pero eso es el camino real; esto es el contrato.
      conPlataforma(TargetPlatform.android);

      await montarPanel(tester, abrirEscaner: (_) async => 'buenos días');

      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pump();
      await tester.pump();

      expect(find.text(mensajeNoEsQr), findsOneWidget);
      expect(fake.llamadas, isEmpty);
    });

    testWidgets('si la marca falla, el error es el del servidor y se puede reintentar',
        (tester) async {
      // El caso real: el código caducó entre que el alumno apuntó y que la
      // petición llegó. La pantalla tiene que decir lo que dijo el servidor y
      // **no** darse por marcada, para que el alumno pueda volver a apuntar.
      conPlataforma(TargetPlatform.android);
      // El mismo mensaje **real** que fija `asistencia_paneles_test.dart` para
      // este caso, y por el mismo motivo: es lo que el servidor manda hoy cuando
      // el código caduca (un 403 genérico, porque el `42501` de Postgres no
      // distingue *por qué* la política dijo que no). Se afirma tal cual para que
      // la pantalla no se invente uno propio; mejorarlo es una decisión de
      // producto sobre la política, no sobre esta pantalla.
      fake.errorAlMarcar = const AppException(
        type: AppErrorType.permisos,
        message: 'No tienes permisos para realizar esta acción.',
      );

      await montarPanel(tester, abrirEscaner: (_) async => parDelQr);

      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      await tester.pump();
      await tester.pump();

      expect(find.text('No tienes permisos para realizar esta acción.'), findsOneWidget);
      expect(find.text('Marcada'), findsNothing);
      // Y el botón del escáner sigue disponible: es lo que el alumno va a usar.
      final boton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.qr_code_scanner),
          matching: find.byType(IconButton),
        ),
      );
      expect(boton.onPressed, isNotNull);
    });
  });

  group('el antirrebote', () {
    test('acepta una sola vez y después ignora todo', () {
      // El usuario lo pidió con estas palabras: que no se dispare veinte veces por
      // segundo si el código se queda delante de la cámara. La capa que corta eso
      // en Dart es este objeto, y aquí se ejerce de verdad: se le llama tres veces
      // y sólo la primera pasa.
      final antirrebote = AntirreboteDeLectura();

      expect(antirrebote.aceptar(), isTrue);
      expect(antirrebote.aceptar(), isFalse);
      expect(antirrebote.aceptar(), isFalse);
    });

    test('dos antirrebotes distintos no se contaminan', () {
      // Cada pantalla que se abre tiene el suyo: si el estado fuera global, cerrar
      // el escáner y volver a abrirlo dejaría el segundo mudo, y el alumno vería
      // una cámara que no lee nada sin explicación.
      final primero = AntirreboteDeLectura();
      final segundo = AntirreboteDeLectura();

      expect(primero.aceptar(), isTrue);
      expect(segundo.aceptar(), isTrue);
    });

    test('la captura se lee saltando los códigos sin contenido', () {
      // El fallo silencioso que se evita: tomar `barcodes.first.rawValue` sobre
      // una lista cuyo primer elemento viene vacío devuelve `null` y la lectura se
      // pierde. Aquí el contenido está en el segundo, y se encuentra.
      final captura = BarcodeCapture(
        barcodes: const [
          Barcode(rawValue: null),
          Barcode(rawValue: '   '),
          Barcode(rawValue: parDelQr),
        ],
      );

      expect(textoDeLaCaptura(captura), parDelQr);
    });

    test('una captura sin códigos no devuelve nada', () {
      expect(textoDeLaCaptura(const BarcodeCapture()), isNull);
    });
  });

  group('la pantalla del escáner donde no hay cámara', () {
    testWidgets('no revienta, lo explica y ofrece el plan B', (tester) async {
      // En `flutter test` no hay cámara, así que la pantalla toma su rama de
      // respaldo. Que esta prueba exista tiene dos lecturas: comprueba el mensaje
      // —el alumno nunca debe ver una pantalla negra— y comprueba que montar la
      // pantalla es seguro, que es la precondición de todo lo demás.
      conPlataforma(TargetPlatform.linux);

      String? devuelto;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  devuelto = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => EscanerQrScreen(validador: (_) => true),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no puede leer códigos QR'), findsOneWidget);

      // Y la salida devuelve `null`, que es «quiero escribir»: no una cadena
      // vacía, que sería un valor con un significado que ya tiene `null`.
      await tester.tap(find.text('Escribir los seis dígitos'));
      await tester.pumpAndSettle();

      expect(devuelto, isNull);
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
