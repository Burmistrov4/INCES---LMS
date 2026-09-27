import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/screens/aspirante/marcar_asistencia_panel.dart';
import 'package:inces_lms_app/screens/docente/asistencia_qr_panel.dart';

import 'support/fake_asistencia_service.dart';
import 'support/fake_aula_gateway.dart';

/// Las dos pantallas de la asistencia (M7), sobre el servicio doblado.
///
/// **Por qué hacía falta (D18).** `asistencia_qr_panel.dart` y
/// `marcar_asistencia_panel.dart` no aparecían en ningún archivo de `test/`. Una
/// pantalla sin prueba es una pantalla que nadie ha visto fallar, y estas dos
/// tienen caminos que fallan en silencio: el panel del docente rota el QR solo y
/// pinta lo que llega por el canal, y el del alumno tiene que distinguir «el
/// código no tiene la forma» de «la base lo rechazó» — dos errores con el mismo
/// síntoma para el usuario.
///
/// **La trampa de esta suite, y cómo se evita.** El panel del docente arranca un
/// `Timer.periodic` de un segundo para rotar el QR. Por eso aquí **no se usa
/// `pumpAndSettle`** después de abrir una sesión: con un temporizador periódico
/// vivo, `pumpAndSettle` nunca converge y la prueba muere por tiempo de espera en
/// vez de por lo que estaba comprobando. Se usa `pump()` con duraciones
/// explícitas, y al final de cada prueba se desmonta el panel con
/// `pumpWidget(SizedBox())` para que su `dispose` cancele el temporizador y la
/// suscripción — si no, flutter_test reporta «A Timer is still pending».
///
/// **Dos defectos quedan fijados aquí, y los dos se midieron antes de tocar
/// nada:**
///
/// * **D21** — el campo del alumno llevaba `maxLength: 6`, así que nunca podía
///   contener el `<uuid>:<6 dígitos>` que exige `ParseQr`: la pantalla estaba
///   muerta y no había ninguna prueba que lo dijera.
/// * **D22** — el panel del docente escuchaba `onError` pero no `onDone`, así
///   que un cierre **limpio** del socket congelaba el tablero en silencio.
///
/// Se escribe contra la conducta **correcta**, no contra la observada: una
/// prueba que fotografiara el fallo lo volvería permanente.
void main() {
  late FakeAsistenciaService fake;
  late FakeAulaGateway aulas;

  setUp(() {
    fake = FakeAsistenciaService();
    aulas = FakeAulaGateway()
      ..misAulasResultado = misAulasEjemplo(esDocente: true);
  });

  /// Monta el panel del docente.
  ///
  /// **Dónde se monta, y por qué aquí vale.** En producción el panel vive dentro
  /// de `ContenidoSeccion` (`docente_dashboard.dart`), que lo envuelve en un
  /// `Column` con `Flexible(child: …)`. Lo único que el panel necesita de ese
  /// envoltorio es **altura acotada** —usa `Expanded`—, y `Scaffold(body:)`
  /// también la da. La anchura efectiva cambia poco y no cambia de rama: con
  /// `ContenidoSeccion` serían 752 px y sin él 768, y el panel conmuta de
  /// disposición en 740. Montarlo aquí evita arrastrar `MigasDePan` a una prueba
  /// que no habla de migas de pan.
  Future<void> montarDocente(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AsistenciaQrPanel(servicio: fake, aulas: aulas))),
    );
    // Un `pump` para que se resuelva la carga de secciones.
    await tester.pump();
    await tester.pump();
  }

  /// Abre la sesión tocando la primera sección del listado.
  Future<void> abrirSesion(WidgetTester tester) async {
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump();
  }

  /// Desmonta el panel para que `dispose` cancele el temporizador de rotación.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  group('el panel del docente', () {
    testWidgets('lista las secciones que dicta, una por aula', (tester) async {
      await montarDocente(tester);

      expect(find.text('Toma asistencia'), findsOneWidget);
      // La etiqueta la compone `AulaResumen.etiqueta`: materia · sección · programa.
      expect(
        find.text('Soldadura · Sección A · Formación Profesional'),
        findsOneWidget,
      );
      expect(aulas.llamadas, contains('misAulas'));
    });

    testWidgets('sin secciones asignadas lo dice, y no deja un listado vacío',
        (tester) async {
      // El caso real del docente que todavía no tiene cuadrante cargado. Un
      // listado en blanco se lee como «la pantalla se rompió»; el mensaje, no.
      aulas.misAulasResultado = const MisAulas(esDocente: true);

      await montarDocente(tester);

      expect(find.textContaining('No tienes secciones asignadas'), findsOneWidget);
    });

    testWidgets('al elegir una sección abre la sesión y proyecta el QR',
        (tester) async {
      await montarDocente(tester);
      await abrirSesion(tester);

      // Se pidió la sesión de **esa** sección, y con la ventana por defecto.
      expect(fake.ultimaSeccionAbierta, 'sec-1');
      expect(fake.ultimaVentanaPedida, 15);

      // El QR se pinta, y el contador dice cuánto le queda a la ventana.
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('Rota en'), findsOneWidget);
      expect(find.text('Sesión abierta'), findsOneWidget);

      // Lo que se codifica es `<sesión>:<seis dígitos>` — el mismo par que el
      // panel del alumno sabe volver a separar con `ParseQr`.
      //
      // **Aquí NO se afirma ese texto, y no por comodidad: no se puede.** Medido
      // en el paquete: `QrImageView` recibe `required String data` pero lo guarda
      // en un campo **privado** (`final String? _data`), sin getter público, así
      // que el contenido codificado no es legible desde el árbol de widgets. Lo
      // que sí se puede leer es la etiqueta de accesibilidad que el panel pone
      // encima, y esa se afirma abajo.
      //
      // La **costura** —que lo que el docente codifica sea lo que el alumno sabe
      // leer— se fija en `asistencia_service_test.dart`, que es donde vive la
      // derivación del código. Tampoco se afirma aquí un valor concreto: el panel
      // llama a `codigoQr` sin `ahora`, así que lee el reloj de verdad y afirmar
      // un valor sería una prueba que falla una vez cada quince segundos.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').startsWith('Código QR de asistencia.'),
        ),
        findsOneWidget,
        reason: 'el QR tiene que anunciar su caducidad a quien no lo ve',
      );

      // Y el canal en vivo se abrió para esa misma sesión.
      expect(fake.ultimoSesionIdEnVivo, 'e5e5e5e5-0001-4001-8001-000000000001');

      await desmontar(tester);
    });

    testWidgets('una marca que llega por el canal se pinta sin recargar nada',
        (tester) async {
      // El corazón del diseño de M7: el tablero del docente **no hace polling**.
      // Esta prueba es la única que ejerce ese empuje desde el lado de la
      // pantalla.
      await montarDocente(tester);
      await abrirSesion(tester);

      expect(find.text('Aún no hay marcas.'), findsOneWidget);

      fake.empujarMarca(estudianteId: 'Iris Vega');
      await tester.pump();
      await tester.pump();

      expect(find.text('Aún no hay marcas.'), findsNothing);
      expect(find.text('Iris Vega'), findsOneWidget);
      // El canal se abrió **una** vez: el panel no se re-suscribe en cada marca.
      expect(
        fake.llamadas.where((l) => l.startsWith('enVivo')).length,
        1,
      );

      await desmontar(tester);
    });

    testWidgets('las marcas ya guardadas se rehidratan al abrir la sesión',
        (tester) async {
      // Si la página se recarga a mitad de clase, las marcas anteriores tienen
      // que volver: el WebSocket sólo avisa de las nuevas. Sin esta rehidratación,
      // el docente vería el tablero vacío y creería que no ha entrado nadie.
      fake.marcasAResponder = [
        marcaAsistenciaEjemplo(estudianteId: 'Ana Pérez', marcadaEn: '10:00:00'),
        marcaAsistenciaEjemplo(
          id: 'f6f6f6f6-0000-4000-8000-000000000002',
          estudianteId: 'Bruno Aguilar',
          marcadaEn: '10:00:30',
        ),
      ];

      await montarDocente(tester);
      await abrirSesion(tester);

      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('Bruno Aguilar'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('cerrar la sesión la marca como cerrada y deja de rotar',
        (tester) async {
      await montarDocente(tester);
      await abrirSesion(tester);

      await tester.tap(find.text('Cerrar'));
      await tester.pump();
      await tester.pump();

      expect(fake.ultimoSesionIdCerrado, 'e5e5e5e5-0001-4001-8001-000000000001');
      expect(find.textContaining('Sesión cerrada'), findsOneWidget);
      // Cerrada, el QR ya no se proyecta: no tiene sentido mostrar un código que
      // la base va a rechazar.
      expect(find.byType(QrImageView), findsNothing);

      await desmontar(tester);
    });

    testWidgets('un fallo al abrir la sesión se muestra y no deja media pantalla',
        (tester) async {
      fake.errorAlAbrir = const AppException(
        type: AppErrorType.permisos,
        message: 'No dictas esa sección: no puedes abrir asistencia en ella.',
      );

      await montarDocente(tester);
      await abrirSesion(tester);

      expect(
        find.text('No dictas esa sección: no puedes abrir asistencia en ella.'),
        findsOneWidget,
      );
      // Sin sesión no hay QR: el panel se queda en el selector en vez de pintar
      // un código que nadie podría validar.
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('si el canal se rompe con un error, lo dice y no borra lo ya marcado',
        (tester) async {
      // Perder el canal **no** pierde las marcas: están en la base, y el propio
      // mensaje lo recuerda. Lo que se pierde es el aviso, y eso el docente tiene
      // que saberlo para no creer que la clase no ha entrado.
      await montarDocente(tester);
      await abrirSesion(tester);

      fake.empujarMarca(estudianteId: 'Ana Pérez');
      await tester.pump();
      await tester.pump();

      fake.fallarCanal();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('La conexión en vivo se cayó'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('un cierre LIMPIO del canal también se avisa', (tester) async {
      // D22, fijado. Un cierre limpio y una avería llegan por caminos distintos:
      // `WebSocketChannel` emite `done` en el primero y `error` en la segunda. El
      // panel sólo escuchaba `onError`, así que si el servidor cerraba el socket
      // —reinicio, o la sesión terminando de su lado— el tablero se quedaba
      // congelado **sin decir nada**, que es justo lo que este mensaje existe
      // para evitar.
      await montarDocente(tester);
      await abrirSesion(tester);

      fake.cerrarCanal();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('La conexión en vivo se cayó'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('cerrar la sesión y caerse el canal después NO alarma',
        (tester) async {
      // La otra mitad de D22: al cerrar la sesión el servidor cierra el socket,
      // así que ese `done` es lo esperado. Si el aviso se pintara igual, el
      // docente aprendería a ignorarlo y el mensaje dejaría de servir.
      await montarDocente(tester);
      await abrirSesion(tester);

      // El servidor anuncia el cierre de la sesión...
      fake.empujar({
        'tipo': 'sesion_cerrada',
        'sesionId': 'e5e5e5e5-0001-4001-8001-000000000001',
      });
      await tester.pump();
      await tester.pump();

      // ...y entonces se cae el canal.
      fake.cerrarCanal();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Sesión cerrada'), findsOneWidget);
      expect(find.textContaining('La conexión en vivo se cayó'), findsNothing);

      await desmontar(tester);
    });
  });

  group('el panel del alumno', () {
    Future<void> montarAlumno(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MarcarAsistenciaPanel(servicio: fake))),
      );
      await tester.pump();
    }

    testWidgets('un texto sin la forma del QR se rechaza en el cliente',
        (tester) async {
      // La primera barrera, y la única que ahorra una petición. El mensaje nombra
      // la forma esperada a propósito: el alumno que teclea a mano no tiene por
      // qué saber que hace falta el UUID delante.
      await montarAlumno(tester);

      await tester.enterText(find.byType(TextField), '471212');
      await tester.tap(find.text('Marcar'));
      await tester.pump();

      expect(find.textContaining('no tiene la forma del QR'), findsOneWidget);
      // Y no se gastó ninguna petición.
      expect(fake.llamadas, isEmpty);
    });

    testWidgets('el campo conserva el código entero — sin esto la pantalla está muerta',
        (tester) async {
      // **D21, fijado, y es la prueba más importante de este archivo.**
      //
      // Hasta el 2026-09-27 el campo llevaba `maxLength: 6` y
      // `keyboardType: number`, mientras `ParseQr` exige `<uuid>:<6 dígitos>`
      // —43 caracteres—. `TextField` inserta un `LengthLimitingTextInputFormatter`
      // en cuanto `maxLength != null`, y ese formateador **trunca**: medido en el
      // SDK, `LengthLimitingTextInputFormatter.formatEditUpdate` devuelve
      // `truncate(newValue, maxLength)` para todos los modos menos `none`, y el
      // modo por defecto de web es `truncateAfterCompositionEnds`, que también
      // trunca. Así que el texto quedaba en seis caracteres, `ParseQr.de()`
      // devolvía `null` **siempre**, y la pantalla respondía «no tiene la forma
      // del QR» hiciera lo que hiciera el alumno. El camino de teclear —el único
      // que existe, porque no hay cámara— no funcionaba.
      //
      // Esta prueba no comprueba una conducta nueva: comprueba que el campo **no**
      // recorta. Es la única forma de que el defecto no vuelva con un `maxLength`
      // copiado de otro formulario.
      await montarAlumno(tester);

      const codigoCompleto = 'e5e5e5e5-0001-4001-8001-000000000001:471212';
      await tester.enterText(find.byType(TextField), codigoCompleto);
      await tester.pump();

      final campo = tester.widget<TextField>(find.byType(TextField));
      // La causa: no hay tope declarado.
      expect(campo.maxLength, isNull);
      // Y el efecto, que es lo que de verdad importa: el texto sobrevive entero.
      expect(campo.controller?.text, codigoCompleto);
    });

    testWidgets('un código con la forma correcta se manda partido en sesión y código',
        (tester) async {
      await montarAlumno(tester);

      await tester.enterText(
        find.byType(TextField),
        'e5e5e5e5-0001-4001-8001-000000000001:471212',
      );
      await tester.tap(find.text('Marcar'));
      await tester.pump();
      await tester.pump();

      // La separación es lo que se está probando: si viajara el texto entero, la
      // base recibiría un `sesionId` que no es un UUID.
      expect(fake.ultimoSesionIdMarcado, 'e5e5e5e5-0001-4001-8001-000000000001');
      expect(fake.ultimoCodigoMarcado, '471212');

      expect(find.text('Listo. Ya cuentas.'), findsOneWidget);
      expect(find.text('Marcada'), findsOneWidget);
    });

    testWidgets('el rechazo de la base se muestra con SU mensaje, no con uno propio',
        (tester) async {
      // Y aquí está lo incómodo, medido: cuando el código caduca, la base rechaza
      // con `42501` y el backend lo traduce a un 403 genérico —«No tienes permisos
      // para realizar esta acción.»—, porque el código de error de Postgres no
      // distingue *por qué* la política dijo que no. El alumno que llegó dos
      // segundos tarde lee algo sobre permisos.
      //
      // La prueba fija el texto **real** a propósito: afirma que la pantalla
      // reenvía el mensaje del servidor en vez de inventarse uno, que es lo
      // correcto, y deja constancia de que ese mensaje es mejorable. Corregirlo
      // es una decisión de producto (que la política emita un código distinto), no
      // un cambio de pantalla.
      fake.errorAlMarcar = const AppException(
        type: AppErrorType.permisos,
        message: 'No tienes permisos para realizar esta acción.',
      );

      await montarAlumno(tester);

      await tester.enterText(
        find.byType(TextField),
        'e5e5e5e5-0001-4001-8001-000000000001:471212',
      );
      await tester.tap(find.text('Marcar'));
      await tester.pump();
      await tester.pump();

      expect(find.text('No tienes permisos para realizar esta acción.'), findsOneWidget);
      // No se dio por marcada: el botón sigue disponible para reintentar con el
      // código nuevo, que es lo que el alumno va a hacer.
      expect(find.text('Marcada'), findsNothing);
      expect(find.text('Marcar'), findsOneWidget);
    });

    testWidgets('mientras la petición está en vuelo, no se puede pulsar dos veces',
        (tester) async {
      // Un doble toque manda dos marcas. La segunda sería «duplicada» y la base no
      // se rompe, pero el botón no debe permitirlo: el alumno vería el estado
      // parpadear sin motivo.
      //
      // **La petición se retiene a propósito.** Con un futuro que se resuelve
      // solo, `tester.tap` ya deja correr los microtareas y para cuando la prueba
      // mira el botón la petición terminó: el botón estaría deshabilitado **por
      // estar hecho**, no por estar en vuelo, y la prueba pasaría sin probar lo
      // que dice probar. Ver `FakeAsistenciaService.retenerMarcar`.
      fake.retenerMarcar = true;

      await montarAlumno(tester);

      await tester.enterText(
        find.byType(TextField),
        'e5e5e5e5-0001-4001-8001-000000000001:471212',
      );
      await tester.tap(find.text('Marcar'));
      await tester.pump(Duration.zero);

      // La petición salió y sigue sin resolver.
      expect(fake.llamadas, contains('marcar:e5e5e5e5-0001-4001-8001-000000000001'));
      // El botón ya está bloqueado, y se ve el giro: el alumno sabe que algo pasa.
      final enVuelo = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(enVuelo.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Y todavía NO se dio por marcada.
      expect(find.text('Marcada'), findsNothing);

      // Ahora se suelta: la marca entra y el estado cambia.
      fake.completarMarcar();
      await tester.pump();
      await tester.pump();

      expect(find.text('Listo. Ya cuentas.'), findsOneWidget);
      expect(find.text('Marcada'), findsOneWidget);
    });
  });
}
