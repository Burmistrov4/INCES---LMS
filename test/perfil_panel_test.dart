import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/perfil_usuario.dart';
import 'package:inces_lms_app/screens/perfil_panel.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_gateway.dart';

/// Pruebas del panel «Mi perfil» y de las reglas de `AuthService` que lo
/// sostienen.
///
/// El panel lo usan el administrador y el aprendiz —es el mismo widget—, así que
/// lo que aquí se prueba vale para los dos. Lo que **no** se prueba aquí es
/// quién puede escribir: eso lo decide la RLS (ADR-003), no la pantalla ni el
/// servicio, y afirmarlo desde Dart daría un verde que no mide nada.
void main() {
  late FakeGateway fake;
  late AuthService auth;

  setUp(() {
    fake = FakeGateway();
    auth = AuthService(gateway: fake);
  });

  PerfilUsuario perfilDe({
    String id = 'u-1',
    String email = 'aprendiz@example.com',
    String nombres = 'Ana',
    String apellidos = 'Gómez',
    String rol = 'estudiante',
  }) =>
      PerfilUsuario(
        id: id,
        email: email,
        nombres: nombres,
        apellidos: apellidos,
        rol: rol,
      );

  /// Monta el panel **dentro de `ContenidoSeccion`**, que es donde vive.
  ///
  /// Montarlo en el `body` suelto de un `Scaffold` escondería el fallo que
  /// importa: `ContenidoSeccion` entrega a su hijo una altura acotada, y un panel
  /// que reparte el espacio con `Expanded` revienta si recibe una infinita. Ese
  /// fallo ya ocurrió en tres paneles del cPanel.
  ///
  /// La comprobación del layout va **aquí dentro** y no en cada prueba a
  /// propósito: `takeException()` **consume** la excepción, así que capturarla
  /// sin mirarla dejaría pasar un desborde en silencio — un verde que no mide.
  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ContenidoSeccion(
            migas: const ['Inicio', 'Mi cuenta', 'Mi Perfil'],
            child: PerfilPanel(auth: auth),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull, reason: 'el layout no debe reventar');
  }

  /// El campo localizado por su etiqueta, como widget.
  ///
  /// `widgetWithText` sirve porque la etiqueta del `InputDecoration` se pinta
  /// **dentro** del `TextField`, así que éste queda como su ancestro.
  TextField campo(WidgetTester tester, String etiqueta) => tester.widget<TextField>(
        find.widgetWithText(TextField, etiqueta),
      );

  /// Lo que hay escrito en un campo.
  ///
  /// Se lee el controlador y no el texto pintado: `find.text` sí encuentra el
  /// contenido de un `EditableText`, pero afirmar sobre el controlador dice
  /// exactamente lo que se quiere decir —«el campo contiene esto»— y no depende
  /// de cómo lo pinte el tema.
  String escrito(WidgetTester tester, String etiqueta) =>
      campo(tester, etiqueta).controller?.text ?? '';

  Future<void> escribir(
    WidgetTester tester,
    String etiqueta,
    String valor,
  ) async {
    await tester.enterText(find.widgetWithText(TextField, etiqueta), valor);
    await tester.pump();
  }

  /// Pulsa «Guardar cambios» y deja asentar el guardado.
  ///
  /// **No se usa `pumpAndSettle`**, y no es preferencia: mientras `_guardando`
  /// es `true` el botón muestra un `CircularProgressIndicator`, que anima sin
  /// fin, así que `pumpAndSettle` esperaría para siempre. Se avanzan fotogramas
  /// explícitos: uno para el `setState` del guardado, otro para que se resuelva
  /// el futuro del doble, y uno corto para la entrada del `SnackBar`.
  Future<void> guardar(WidgetTester tester) async {
    // Por el texto y no por `find.byType(FilledButton)`: `FilledButton.icon`
    // construye una subclase privada, y `byType` compara el tipo exacto, así que
    // no la encontraría. El `Text` del rótulo sí está dentro del área que recibe
    // el toque.
    await tester.tap(find.text('Guardar cambios'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // El guardado puede añadir un aviso en línea dentro del formulario, así que
    // también hay que comprobar que el layout sigue en pie después.
    expect(
      tester.takeException(),
      isNull,
      reason: 'guardar no debe romper el layout',
    );
  }

  /// Deja salir al `SnackBar` para no cerrar la prueba con un temporizador vivo.
  Future<void> dejarSalirAlAviso(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
  }

  // ---------------------------------------------------------------------------
  // Carga
  // ---------------------------------------------------------------------------

  group('panel de perfil · carga', () {
    testWidgets('los campos llegan sembrados con lo que hay en la base',
        (tester) async {
      // Éste es el «desde el momento en que se registraron»: `handle_new_user()`
      // inserta la fila de `profiles` con el nombre que la persona tecleó al
      // inscribirse, en la misma transacción del alta. El panel no pide nada
      // extra; lo que hace es **mostrarlo** ya puesto, sin que haya que
      // completar nada.
      fake.perfil = perfilDe(nombres: 'Ana', apellidos: 'Gómez');

      await montar(tester);

      expect(escrito(tester, 'Nombres'), 'Ana');
      expect(escrito(tester, 'Apellidos'), 'Gómez');
      // Se pinta en mayúsculas: buscar «Mi perfil» en su forma legible no lo
      // encuentra, y creer que el título falta llevaría a «arreglar» lo que no
      // está roto.
      expect(find.text('MI PERFIL'), findsOneWidget);
      expect(find.text('Mi perfil'), findsNothing);
    });

    testWidgets('el rol se muestra legible, no como la clave de la base',
        (tester) async {
      // En la base vive `admin`; en pantalla tiene que leerse «Administrador».
      // Enseñar la clave cruda sería filtrar el vocabulario interno.
      fake.perfil = perfilDe(rol: 'admin', email: 'lorenzo@example.com');

      await montar(tester);

      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('admin'), findsNothing);
      expect(find.text('lorenzo@example.com'), findsOneWidget);
    });

    testWidgets('una cuenta sin fila en profiles no se pinta como un error',
        (tester) async {
      // `null` es «no existe», nunca «algo salió mal». Confundir los dos haría
      // que una cuenta sin ficha —altas antiguas o interrumpidas— se viera como
      // una caída de red y ofreciera reintentar algo que no puede cambiar.
      fake.perfil = null;

      await montar(tester);

      expect(find.text('Tu cuenta todavía no tiene perfil'), findsOneWidget);
      expect(find.text('No pudimos cargar esta sección'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      // Y no se pinta el formulario, porque no hay fila que corregir.
      expect(find.text('Nombres'), findsNothing);
    });

    testWidgets('si la carga falla se ofrece reintentar y no se pinta el '
        'formulario', (tester) async {
      fake.errorAlLeerPerfil = const AppException.red();

      await montar(tester);

      expect(find.text('No pudimos cargar esta sección'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Nombres'), findsNothing);
    });

    testWidgets('«Reintentar» vuelve a intentarlo de verdad', (tester) async {
      // Sin esto, `onReintentar: _cargar` podría estar cableado a un no-op y la
      // prueba anterior seguiría en verde: sólo comprobaría que el botón existe.
      fake.errorAlLeerPerfil = const AppException.red();
      await montar(tester);
      expect(find.text('Reintentar'), findsOneWidget);

      fake.errorAlLeerPerfil = null;
      fake.perfil = perfilDe();

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('No pudimos cargar esta sección'), findsNothing);
      expect(escrito(tester, 'Nombres'), 'Ana');
    });
  });

  // ---------------------------------------------------------------------------
  // Guardado
  // ---------------------------------------------------------------------------

  group('panel de perfil · guardado', () {
    testWidgets('guardar envía el nombre ya recortado y confirma',
        (tester) async {
      // El panel manda lo que hay en el campo **tal cual**; quien recorta es el
      // servicio. Se afirma sobre lo que recibió el gateway y no sobre el
      // resultado: mirando sólo el resultado, «recortó» y «ya venía limpio» se
      // ven igual.
      fake.perfil = perfilDe(nombres: 'Ana', apellidos: 'Gómez');
      await montar(tester);

      await escribir(tester, 'Nombres', '  Ana María  ');
      await escribir(tester, 'Apellidos', '  Gómez  ');
      await guardar(tester);

      expect(fake.nombresEnviados, 'Ana María');
      expect(fake.apellidosEnviados, 'Gómez');
      expect(find.text('Tus datos se guardaron.'), findsOneWidget);

      await dejarSalirAlAviso(tester);
    });

    testWidgets('los campos se reescriben con lo que devolvió la base',
        (tester) async {
      // Después de guardar, lo que se ve es el valor **guardado** —ya
      // recortado—, no lo que quedó en el campo. Si la base normalizara algo,
      // se vería aquí en vez de quedar escondido tras el texto tecleado.
      fake.perfil = perfilDe(nombres: 'Ana', apellidos: 'Gómez');
      await montar(tester);

      await escribir(tester, 'Nombres', '  Ana María  ');
      await guardar(tester);

      expect(escrito(tester, 'Nombres'), 'Ana María');

      await dejarSalirAlAviso(tester);
    });

    testWidgets('un nombre vacío se rechaza con el mensaje del dominio',
        (tester) async {
      // `profiles.nombres` es `not null`, pero la cadena vacía lo satisface: sin
      // esta validación Postgres aceptaría un perfil sin nombre y la cabecera de
      // la aplicación quedaría en blanco sin que nada fallara.
      fake.perfil = perfilDe();
      await montar(tester);

      await escribir(tester, 'Nombres', '   ');
      await guardar(tester);

      expect(find.textContaining('Completa el nombre'), findsOneWidget);
      // Falla rápido: no debe gastar una llamada de red.
      expect(fake.nombresEnviados, isNull);
      expect(fake.llamadas, isNot(contains('actualizarPerfil')));
    });

    testWidgets('con los dos campos vacíos se nombran los dos',
        (tester) async {
      fake.perfil = perfilDe();
      await montar(tester);

      await escribir(tester, 'Nombres', '');
      await escribir(tester, 'Apellidos', '  ');
      await guardar(tester);

      expect(
        find.textContaining('Completa el nombre y el apellido'),
        findsOneWidget,
      );
      expect(fake.llamadas, isNot(contains('actualizarPerfil')));
    });

    testWidgets('si el guardado falla, se ve el motivo y no se pierde lo '
        'escrito', (tester) async {
      // El error del guardado va **dentro** del formulario, no en el lugar del
      // error de carga: si reemplazara la sección entera, borraría lo que la
      // persona acaba de teclear justo cuando tiene que corregirlo.
      fake.perfil = perfilDe(nombres: 'Ana', apellidos: 'Gómez');
      fake.errorAlActualizarPerfil = const AppException(
        type: AppErrorType.servidor,
        message: 'No pudimos guardar tus datos.',
      );
      await montar(tester);

      await escribir(tester, 'Nombres', 'Ana María');
      await guardar(tester);

      expect(find.text('No pudimos guardar tus datos.'), findsOneWidget);
      // El formulario sigue ahí y con el texto tecleado.
      expect(escrito(tester, 'Nombres'), 'Ana María');
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.text('No pudimos cargar esta sección'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Las reglas del servicio, sin montar interfaz
  // ---------------------------------------------------------------------------

  group('AuthService.actualizarPerfil', () {
    test('recorta antes de enviar', () async {
      final resultado = await auth.actualizarPerfil(
        nombres: '  Luis  ',
        apellidos: '  Pérez  ',
      );

      expect(resultado.isSuccess, isTrue);
      expect(fake.nombresEnviados, 'Luis');
      expect(fake.apellidosEnviados, 'Pérez');
    });

    test('el nombre en blanco falla como validación y no toca la red',
        () async {
      final resultado = await auth.actualizarPerfil(
        nombres: '   ',
        apellidos: 'Pérez',
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.type, AppErrorType.validacion);
      expect(resultado.errorOrNull?.message, contains('el nombre'));
      expect(fake.llamadas, isNot(contains('actualizarPerfil')));
    });

    test('el apellido en blanco también se rechaza', () async {
      final resultado = await auth.actualizarPerfil(
        nombres: 'Luis',
        apellidos: '',
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.message, contains('el apellido'));
      expect(fake.llamadas, isNot(contains('actualizarPerfil')));
    });
  });

  group('AuthService.miPerfil', () {
    test('un fallo de red llega como failure, no como null', () async {
      // La distinción es la razón de ser de este método: si un corte de red se
      // pintara como `null`, el panel diría «tu cuenta no tiene perfil» —un
      // diagnóstico falso— en vez de ofrecer reintentar.
      fake.errorAlLeerPerfil = const AppException.red();

      final resultado = await auth.miPerfil();

      expect(resultado.isFailure, isTrue);
      expect(resultado.valueOrNull, isNull);
      expect(resultado.errorOrNull?.type, AppErrorType.red);
    });

    test('una cuenta sin fila es success(null), no un fallo', () async {
      fake.perfil = null;

      final resultado = await auth.miPerfil();

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull, isNull);
    });

    test('devuelve el perfil con el nombre ya compuesto', () async {
      fake.perfil = perfilDe(nombres: 'Ana', apellidos: 'Gómez');

      final resultado = await auth.miPerfil();

      expect(resultado.valueOrNull?.nombreCompleto, 'Ana Gómez');
    });
  });
}
