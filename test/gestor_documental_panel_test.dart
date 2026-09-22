import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/archivo.dart';
import 'package:inces_lms_app/repositories/archivos_repository.dart';
import 'package:inces_lms_app/screens/gestor_documental_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_archivos_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Pruebas del gestor documental (M5, Capa 7).
///
/// Cubren lo que la capa de datos ya no puede cubrir: **que los tres pasos
/// ocurran en orden, con los valores del servidor, y que el usuario vea qué
/// está pasando**. El gateway tiene sus propias pruebas
/// (`archivos_gateway_test.dart`) y el `PUT` real lo cubre
/// `supabase/humo-archivos.mjs`; aquí lo que se prueba es la orquestación y la
/// pantalla.
///
/// Monta el panel dentro de [ContenidoSeccion] y no en un `Scaffold` pelado
/// porque es donde vive en producción, y es el widget que le entrega una altura
/// **acotada** — el detalle que en su día reventó un panel hermano. Probarlo en
/// otro contenedor sería probar un layout que no existe.
Future<void> montar(
  WidgetTester tester, {
  required ArchivosRepository repo,
  required FakeSelectorDeArchivos selector,
  TipoEntidadArchivo tipo = TipoEntidadArchivo.taskSubmission,
  String? entidadId,
}) async {
  // Ventana alta a propósito. El panel es un `ListView`, y con la ventana por
  // defecto de las pruebas (800×600) las tarjetas de la lista quedarían fuera
  // del viewport: sus elementos no llegarían a montarse y `find.text` no las
  // encontraría. No es que falte el dato, es que no se pintó — y una prueba que
  // falla por eso enseña la lección equivocada.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: Scaffold(
        body: ContenidoSeccion(
          child: GestorDocumentalPanel(
            entityType: tipo,
            entidadId: entidadId,
            repositorio: repo,
            selector: selector,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Avanza la interfaz lo justo para que terminen diálogos y animaciones.
///
/// **No usa `pumpAndSettle` a propósito.** El panel pinta un
/// `CircularProgressIndicator` mientras hay una operación en curso, y un
/// indicador anima indefinidamente: `pumpAndSettle` no terminaría nunca y
/// agotaría su tiempo límite. Sería un fallo de la prueba, no del código, y
/// además taparía el fallo real con un mensaje que no habla de él.
Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// Deja que los avisos temporales caduquen y se marchen.
///
/// Obligatorio al final de cualquier prueba que muestre un aviso: `mostrarAviso`
/// deja un `Timer` vivo —3 s el de éxito, 6 s el de error— y una prueba que
/// termina con un temporizador pendiente falla.
Future<void> cerrarAvisos(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
}

/// El botón principal, construido con `.icon` (su tipo real es un subtipo
/// privado, así que `find.widgetWithText` no lo encuentra).
Finder botonFilled(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<FilledButton>());

/// Busca un texto **sin distinguir mayúsculas**.
///
/// `TituloSeccion` pinta su título en mayúsculas, así que «Mis entregas» llega a
/// pantalla como «MIS ENTREGAS». Escribir la versión en mayúsculas en la prueba
/// la ataría a una decisión de estilo: el día que el tema deje de pasarlas a
/// mayúsculas fallarían pruebas que no hablan de estilo. Lo que importa aquí es
/// **qué dice** la pantalla, no cómo lo pinta el tema.
Finder texto(String contenido) => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data ?? '').toUpperCase() == contenido.toUpperCase(),
      description: 'texto «$contenido», sin distinguir mayúsculas',
    );

/// Gateway que retiene el paso 1 hasta que la prueba lo suelta.
///
/// Sirve para mirar la pantalla **mientras** la subida está en curso, que es el
/// único momento en que se ve la etiqueta del paso y en el que importa que no
/// haya un segundo botón de enviar.
class _GatewayConFreno extends FakeArchivosGateway {
  final freno = Completer<void>();

  @override
  Future<SubidaFirmada> firmarSubida({
    required String nombreOriginal,
    required TipoEntidadArchivo entityType,
    String? entidadId,
  }) async {
    await freno.future;
    return super.firmarSubida(
      nombreOriginal: nombreOriginal,
      entityType: entityType,
      entidadId: entidadId,
    );
  }
}

/// Monta el panel, elige un archivo y pulsa subir.
///
/// Devuelve el gateway para poder inspeccionar qué se envió y el selector para
/// comprobar qué se abrió.
Future<({FakeArchivosGateway gateway, FakeSelectorDeArchivos selector})> subir(
  WidgetTester tester, {
  Object? falloAlFirmar,
  Object? falloAlSubirObjeto,
  Object? falloAlConfirmar,
  FakeArchivosGateway? gateway,
}) async {
  final doble = gateway ??
      FakeArchivosGateway()
        ..errorAlFirmar = falloAlFirmar
        ..errorAlSubirObjeto = falloAlSubirObjeto
        ..errorAlConfirmar = falloAlConfirmar;

  final selector = FakeSelectorDeArchivos()..devolver = archivoElegido();
  await montar(
    tester,
    repo: ArchivosRepository(gateway: doble),
    selector: selector,
  );

  await tester.tap(find.text('Elegir archivo'));
  await tester.pump();
  await tester.tap(find.text('Subir'));
  await tester.pump();

  return (gateway: doble, selector: selector);
}

void main() {
  group('GestorDocumentalPanel · estado inicial', () {
    testWidgets('sin entidad lo explica en vez de fingir una lista vacía',
        (tester) async {
      await montar(
        tester,
        repo: ArchivosRepository(gateway: FakeArchivosGateway()),
        selector: FakeSelectorDeArchivos(),
      );

      // El título se deriva del tipo de entidad: el mismo panel sirve para las
      // entregas del estudiante y para las guías del docente.
      expect(texto('Mis entregas'), findsOneWidget);
      expect(texto('Todavía no has subido archivos'), findsOneWidget);
      expect(find.text('Elegir archivo'), findsOneWidget);

      // Sin `entidadId` no hay pregunta que hacer —la ruta pide los archivos de
      // una tarea concreta, y un id nulo daría 400—. Decirlo es la diferencia
      // entre una limitación y una mentira.
      expect(
        find.textContaining('no está atada a una tarea o una guía'),
        findsOneWidget,
      );
    });

    testWidgets('el título por defecto cambia con el tipo de entidad',
        (tester) async {
      await montar(
        tester,
        repo: ArchivosRepository(gateway: FakeArchivosGateway()),
        selector: FakeSelectorDeArchivos(),
        tipo: TipoEntidadArchivo.teacherGuide,
      );

      expect(texto('Material de apoyo'), findsOneWidget);
    });
  });

  group('GestorDocumentalPanel · hidratación de la lista (D17)', () {
    testWidgets('pinta lo ya guardado y pide la entidad correcta',
        (tester) async {
      final gateway = FakeArchivosGateway()
        ..archivosListados = [
          archivoEjemplo(
            id: 'a1b2c3d4-0000-4000-8000-0000000000b1',
            nombreOriginal: 'informe-final.pdf',
            estado: EstadoArchivo.confirmed,
            tamanoBytes: 4096,
            entidadId: 'ent-1',
          ),
          archivoEjemplo(
            id: 'a1b2c3d4-0000-4000-8000-0000000000b2',
            nombreOriginal: 'anexos.pdf',
            entidadId: 'ent-1',
          ),
        ];

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: FakeSelectorDeArchivos(),
        entidadId: 'ent-1',
      );
      await asentar(tester);

      // Lo guardado aparece **sin haber subido nada**: es la diferencia entre un
      // gestor documental y un formulario de subida, y era justo lo que M5 no
      // podía hacer antes de esta ruta.
      expect(texto('informe-final.pdf'), findsOneWidget);
      expect(texto('anexos.pdf'), findsOneWidget);
      expect(texto('Archivos guardados'), findsOneWidget);

      // Y se pidió lo que se debía: el tipo del widget y la entidad recibida.
      expect(gateway.llamadas, contains('listarPorEntidad:TASK_SUBMISSION:ent-1'));

      // El aviso de «no está atada» no sale cuando sí lo está.
      expect(
        find.textContaining('no está atada a una tarea o una guía'),
        findsNothing,
      );
    });

    testWidgets('sin entidad no se llama a la ruta', (tester) async {
      final gateway = FakeArchivosGateway();

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: FakeSelectorDeArchivos(),
      );
      await asentar(tester);

      // No se gasta un viaje en un 400 anunciado.
      expect(gateway.llamadas, isEmpty);
    });

    testWidgets('un fallo al listar no impide subir', (tester) async {
      final gateway = FakeArchivosGateway()
        ..errorAlListar = const AppException(
          type: AppErrorType.red,
          message: 'No hay conexión con el servidor.',
          code: 'SIN_RED',
        );

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: FakeSelectorDeArchivos(),
        entidadId: 'ent-1',
      );
      await asentar(tester);

      // El fallo se cuenta **y la pantalla sigue usable**: perder la lista es una
      // molestia, impedir subir sería convertir un fallo de lectura en una
      // pantalla muerta.
      expect(
        find.textContaining('No pudimos cargar los archivos'),
        findsOneWidget,
      );
      expect(find.text('Elegir archivo'), findsOneWidget);
    });
  });

  group('GestorDocumentalPanel · subida en tres pasos', () {
    testWidgets('firma, sube a R2 y confirma, en ese orden', (tester) async {
      final resultado = await subir(tester);
      final gateway = resultado.gateway;

      // Orden exacto, no sólo «se llamaron las tres». Firmar después del `PUT`
      // dejaría el objeto sin fila; confirmar antes del `PUT` mediría la nada.
      expect(gateway.llamadas, [
        'firmarSubida:Constancia José.pdf',
        'subirObjeto',
        'confirmar:${gateway.archivoFirmadoDevuelto.id}',
      ]);

      // El `PUT` fue a R2 —la URL prefirmada— y no al backend.
      expect(gateway.ultimaUrlDeSubida, gateway.urlDeSubidaDevuelta);
      // Y con los bytes elegidos, enteros.
      expect(gateway.ultimoContenido, hasLength(2048));

      // La tarjeta vuelve al principio y la lista ya tiene el archivo con el
      // tamaño que midió el servidor — no con el que calculó el cliente.
      expect(find.text('Elegir archivo'), findsOneWidget);
      expect(find.text('Confirmado'), findsOneWidget);
      expect(find.text('512 B'), findsOneWidget);

      await cerrarAvisos(tester);
    });

    testWidgets('el peso lo pone el servidor, no el cliente', (tester) async {
      await montar(
        tester,
        repo: ArchivosRepository(gateway: FakeArchivosGateway()),
        selector: FakeSelectorDeArchivos()..devolver = archivoElegido(bytes: 2048),
      );

      await tester.tap(find.text('Elegir archivo'));
      await tester.pump();

      // Antes de subir, el peso es el que cuenta el cliente.
      expect(find.text('2,0 KB'), findsOneWidget);

      await tester.tap(find.text('Subir'));
      await tester.pump();

      // Después, el que sella el `HeadObject` del servidor. Son dos cifras
      // distintas y sólo la segunda es la que queda guardada.
      expect(find.text('2,0 KB'), findsNothing);
      expect(find.text('512 B'), findsOneWidget);

      await cerrarAvisos(tester);
    });

    testWidgets(
        'el PUT lleva el Content-Type que firmó el servidor, no uno deducido del nombre',
        (tester) async {
      // El nombre es de PDF y el servidor firmó un DOCX: incoherentes **a
      // propósito**. Deducir el tipo del nombre —lo natural, y lo que haría un
      // cliente distraído— enviaría `application/pdf`, y R2 rechazaría la firma
      // porque la URL prefirmada cubre ese encabezado. Que viaje el del servidor
      // es lo único que hace que la subida funcione.
      final gateway = FakeArchivosGateway()
        ..archivoFirmadoDevuelto = archivoEjemplo(
          nombreOriginal: 'Constancia José.pdf',
          tipoContenido:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );

      final resultado = await subir(tester, gateway: gateway);

      expect(
        resultado.gateway.ultimoTipoContenidoEnviado,
        resultado.gateway.archivoFirmadoDevuelto.tipoContenido,
      );
      expect(resultado.gateway.ultimoTipoContenidoEnviado, isNot('application/pdf'));

      await cerrarAvisos(tester);
    });

    testWidgets('declara la entidad y el tipo que se le pidieron', (tester) async {
      final gateway = FakeArchivosGateway();
      final selector = FakeSelectorDeArchivos()
        ..devolver = archivoElegido(nombre: 'Guía de soldadura.pdf');

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: selector,
        tipo: TipoEntidadArchivo.teacherGuide,
        entidadId: 'guia-7',
      );

      await tester.tap(find.text('Elegir archivo'));
      await tester.pump();
      await tester.tap(find.text('Subir'));
      await tester.pump();

      // El tipo no es decorativo: el servidor lo valida contra un `CHECK`, así
      // que declarar el contrario haría fallar toda subida con un 400 mientras
      // la pantalla se vería exactamente igual.
      expect(gateway.ultimoEntityType, TipoEntidadArchivo.teacherGuide);
      expect(gateway.ultimaEntidadId, 'guia-7');

      await cerrarAvisos(tester);
    });

    testWidgets('mientras sube no ofrece un segundo envío y dice en qué paso va',
        (tester) async {
      final gateway = _GatewayConFreno();
      final selector = FakeSelectorDeArchivos()..devolver = archivoElegido();

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: selector,
      );

      await tester.tap(find.text('Elegir archivo'));
      await tester.pump();
      await tester.tap(find.text('Subir'));
      await tester.pump();

      // El paso 1 está retenido: la tarjeta muestra en qué paso va y **no** hay
      // botón. La etiqueta concreta es la razón de orquestar los tres pasos a
      // mano: con `subir()` sólo se podría decir «subiendo…» durante todo el
      // proceso y el usuario no sabría si la aplicación avanzó o se colgó.
      expect(find.text('Preparando la subida…'), findsOneWidget);
      expect(find.text('Subir'), findsNothing);
      expect(find.text('Descartar'), findsNothing);

      gateway.freno.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Confirmado'), findsOneWidget);
      // Una sola firma: no hay una segunda reserva `PENDING` abandonada.
      expect(
        gateway.llamadas.where((c) => c.startsWith('firmarSubida')),
        hasLength(1),
      );

      await cerrarAvisos(tester);
    });
  });

  group('GestorDocumentalPanel · elegir archivo', () {
    testWidgets('cancelar el diálogo no es un error ni reserva nada',
        (tester) async {
      final gateway = FakeArchivosGateway();
      // `devolver` queda en `null`: el usuario cerró el diálogo.
      final selector = FakeSelectorDeArchivos();

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: selector,
      );

      await tester.tap(find.text('Elegir archivo'));
      await tester.pump();

      expect(selector.vecesElegir, 1);
      expect(gateway.llamadas, isEmpty);
      // Ni caja de error ni aviso: cancelar es una decisión, no un fallo. Un
      // aviso aquí enseñaría al usuario a ignorar los avisos.
      expect(find.textContaining('No pudimos abrir el selector'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Elegir archivo'), findsOneWidget);
    });

    testWidgets('un fallo del diálogo se explica y deja volver a intentarlo',
        (tester) async {
      final gateway = FakeArchivosGateway();
      final selector = FakeSelectorDeArchivos()
        ..errorAlElegir = StateError('no hay DOM en la VM');

      await montar(
        tester,
        repo: ArchivosRepository(gateway: gateway),
        selector: selector,
      );

      await tester.tap(find.text('Elegir archivo'));
      await tester.pump();

      expect(find.text('No pudimos abrir el selector de archivos.'), findsOneWidget);
      expect(find.text('Recarga la página e inténtalo de nuevo.'), findsOneWidget);
      expect(gateway.llamadas, isEmpty);

      // Y el botón vuelve a estar disponible: el estado de carga se libera
      // **antes** de comprobar `mounted`, que es lo que evita que un fallo deje
      // el botón bloqueado para siempre en la siguiente visita.
      expect(
        tester.widget<FilledButton>(botonFilled('Elegir archivo')).onPressed,
        isNotNull,
      );
    });
  });

  group('GestorDocumentalPanel · fallos del servidor', () {
    testWidgets('413 · no ofrece reintentar el mismo archivo, sino elegir otro',
        (tester) async {
      final resultado = await subir(
        tester,
        falloAlConfirmar: const AppException(
          type: AppErrorType.validacion,
          message: 'El archivo supera el tamaño máximo permitido.',
          code: 'ARCHIVO_DEMASIADO_GRANDE',
        ),
      );

      expect(
        find.text('El archivo supera el tamaño máximo permitido.'),
        findsOneWidget,
      );
      expect(
        find.text('Elige un archivo más pequeño y vuelve a intentarlo.'),
        findsOneWidget,
      );

      // **Lo que esta prueba existe para fijar.** El objeto ya llegó a R2 y el
      // servidor ya lo midió: los mismos bytes pesan lo mismo, así que repetir
      // el `PUT` y el `HeadObject` devuelve el mismo 413. Un botón que dice
      // «Reintentar subida» aquí sería un botón que no puede funcionar.
      expect(find.text('Reintentar subida'), findsNothing);
      expect(find.text('Elegir otro archivo'), findsOneWidget);

      // Y el texto no miente: pulsarlo abre el diálogo en vez de repetir la
      // subida. Se comprueba el efecto, no la etiqueta.
      final llamadasAntes = resultado.gateway.llamadas.length;
      await tester.tap(find.text('Elegir otro archivo'));
      await tester.pump();

      expect(resultado.selector.vecesElegir, 2);
      expect(resultado.gateway.llamadas.length, llamadasAntes);
    });

    testWidgets(
        '404 OBJETO_NO_SUBIDO · reintentar repite el PUT sin reservar otra clave',
        (tester) async {
      final resultado = await subir(
        tester,
        falloAlSubirObjeto: const AppException(
          type: AppErrorType.servidor,
          message: 'La subida no llegó al almacenamiento.',
          code: 'OBJETO_NO_SUBIDO',
        ),
      );

      expect(
        find.text('La reserva sigue hecha: pulsa «Reintentar subida».'),
        findsOneWidget,
      );
      expect(find.text('Reintentar subida'), findsOneWidget);
      expect(resultado.gateway.llamadas, [
        'firmarSubida:Constancia José.pdf',
        'subirObjeto',
      ]);

      // Se arregla la causa y se reintenta.
      resultado.gateway.errorAlSubirObjeto = null;
      await tester.tap(find.text('Reintentar subida'));
      await tester.pump();

      // **La aserción que importa.** `firmarSubida` sigue apareciendo una sola
      // vez: el panel conservó la firma y reanudó en el paso 2. Si hubiera
      // vuelto al paso 1 —lo fácil— habría creado una segunda reserva `PENDING`
      // y abandonado la primera, que es exactamente la basura que el barrido de
      // pendientes existe para recoger. El reintento «funcionaría» igual, así
      // que sin esta comprobación el defecto no se vería.
      expect(
        resultado.gateway.llamadas.where((c) => c.startsWith('firmarSubida')),
        hasLength(1),
      );
      expect(
        resultado.gateway.llamadas.where((c) => c == 'subirObjeto'),
        hasLength(2),
      );
      expect(find.text('Confirmado'), findsOneWidget);

      await cerrarAvisos(tester);
    });

    testWidgets('404 ARCHIVO_INEXISTENTE · el fallo se muestra y deja reintentar',
        (tester) async {
      await subir(
        tester,
        falloAlFirmar: const AppException(
          type: AppErrorType.validacion,
          message: 'No encontramos el archivo.',
          code: 'ARCHIVO_INEXISTENTE',
        ),
      );

      expect(find.text('No encontramos el archivo.'), findsOneWidget);
      // Sin firma no hay nada que reanudar, así que el botón vuelve a ser
      // «Subir» y no «Reintentar subida»: no hay reserva que conservar.
      expect(find.text('Subir'), findsOneWidget);
      expect(find.text('Reintentar subida'), findsNothing);
    });

    testWidgets('un 400 por la extensión dice qué formatos sí valen',
        (tester) async {
      await subir(
        tester,
        falloAlFirmar: const AppException(
          type: AppErrorType.validacion,
          message: 'La extensión del archivo no está permitida.',
          code: 'PETICION_INVALIDA',
        ),
      );

      // El servidor devuelve `PETICION_INVALIDA` tanto si falta la extensión
      // como si no está en la lista, y no manda la lista. Nombrarla aquí es lo
      // que convierte un 400 opaco en algo que el usuario puede corregir solo.
      expect(
        find.text('Comprueba que el nombre termina en PDF, JPG, PNG, WEBP, '
            'DOCX, XLSX o PPTX.'),
        findsOneWidget,
      );
    });
  });

  group('GestorDocumentalPanel · descargar y borrar', () {
    testWidgets('descargar usa la URL y el nombre que devolvió el servidor',
        (tester) async {
      final resultado = await subir(tester);
      await cerrarAvisos(tester);

      await tester.tap(find.byTooltip('Descargar'));
      await tester.pump();

      expect(
        resultado.gateway.llamadas,
        contains('urlDeLectura:${resultado.gateway.archivoConfirmadoDevuelto.id}'),
      );
      // La URL no se arma en el cliente: se pide y se usa la que llega.
      expect(
        resultado.selector.ultimaUrlDescargada,
        resultado.gateway.lecturaDevuelta.urlDeLectura,
      );
      expect(
        resultado.selector.ultimoNombreDescargado,
        resultado.gateway.lecturaDevuelta.nombreOriginal,
      );

      await cerrarAvisos(tester);
    });

    testWidgets('borrar pide confirmación y marca la fila en vez de esconderla',
        (tester) async {
      final resultado = await subir(tester);
      await cerrarAvisos(tester);

      // Cancelar no borra nada.
      await tester.tap(find.byTooltip('Borrar'));
      await asentar(tester);
      expect(find.text('¿Borrar el archivo?'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await asentar(tester);
      expect(
        resultado.gateway.llamadas.any((c) => c.startsWith('borrar:')),
        isFalse,
      );

      // Confirmar sí.
      await tester.tap(find.byTooltip('Borrar'));
      await asentar(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await asentar(tester);

      expect(
        resultado.gateway.llamadas,
        contains('borrar:${resultado.gateway.archivoConfirmadoDevuelto.id}'),
      );

      // La fila sigue en la lista y dice «Borrado». Quitarla dejaría el
      // historial de la sesión como un misterio: algo desapareció y la pantalla
      // no dice qué ni por qué.
      expect(find.text('Borrado'), findsOneWidget);
      expect(find.text('Constancia José.pdf'), findsOneWidget);

      await cerrarAvisos(tester);
    });
  });

  group('formatearBytes', () {
    test('por debajo de 1 KB se cuenta en bytes', () {
      expect(formatearBytes(0), '0 B');
      expect(formatearBytes(512), '512 B');
      expect(formatearBytes(1023), '1023 B');
    });

    test('de KB en adelante usa 1024 y coma decimal', () {
      // 1024 y no 1000 porque es lo que muestra el explorador de archivos del
      // usuario; dos cifras que discrepan en un 2,4 % generan dudas sobre si el
      // archivo se subió entero.
      expect(formatearBytes(1024), '1,0 KB');
      expect(formatearBytes(1536), '1,5 KB');
      expect(formatearBytes(1024 * 1024), '1,0 MB');
      expect(formatearBytes(1024 * 1024 * 1024), '1,0 GB');
    });

    test('a partir de 100 unidades no gasta decimales', () {
      // «100 MB» informa; «100,0 MB» sólo ocupa sitio.
      expect(formatearBytes(99 * 1024 * 1024), '99,0 MB');
      expect(formatearBytes(100 * 1024 * 1024), '100 MB');
    });

    test('la unidad se detiene en GB aunque la cifra crezca', () {
      // El tope del servidor está muy por debajo, pero el tope de la lista de
      // unidades es un detalle que se rompe solo al copiar el código.
      expect(formatearBytes(5 * 1024 * 1024 * 1024), '5,0 GB');
      expect(formatearBytes(2048 * 1024 * 1024 * 1024), '2048 GB');
    });
  });
}
