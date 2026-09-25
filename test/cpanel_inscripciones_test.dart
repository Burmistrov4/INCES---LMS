import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/exportacion_hacer.dart';
import 'package:inces_lms_app/models/inscripcion.dart';
import 'package:inces_lms_app/repositories/exportacion_hacer_repository.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripciones_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_exportacion_hacer_gateway.dart';
import 'support/fake_inscripcion_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Monta el panel de administración y espera la carga inicial.
///
/// `MaterialApp` con el tema institucional y `Scaffold(body: panel)`. El panel
/// usa un `Expanded` interno (como `ContenidoSeccion` en producción), así que
/// exige altura acotada: el `Scaffold` la da.
Future<void> montarPanel(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(
    MaterialApp(theme: IncesTheme.claro(), home: Scaffold(body: panel)),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> cerrarAvisos(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
}

/// Busca un botón cuyo `label` contiene el texto indicado, aunque esté
/// construido con el constructor `.icon` (su runtimeType es un subtipo privado,
/// así que `find.widgetWithText` —que usa `byType` interno— no lo encuentra).
Finder botonFilled(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<FilledButton>());

Finder botonOutlined(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<OutlinedButton>());

/// Pulsa un botón que puede estar **por debajo del pliegue**.
///
/// No es un adorno, y CI lo demostró: a 800×600 —la ventana por defecto de
/// `flutter test`— la tarjeta de una sección cae fuera del viewport (cabecera +
/// métricas + los dos avisos), y `tap` sobre un widget fuera de pantalla **no
/// acierta**. Lo dice con un «would not hit test» que se pierde entre la salida
/// —`Offset(564.0, 698.0)` en una raíz de `Size(800.0, 600.0)`— y luego la
/// prueba se cae más adelante culpando a la pantalla. Es la trampa del `Stepper`
/// en otra pantalla, y la lección es la misma: **«está en el árbol» no es «es
/// pulsable»**.
Future<void> pulsar(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
}

void main() {
  group('CpanelInscripcionesPanel (ocupación del admin)', () {
    testWidgets('ocupación vacía muestra el panel vacío', (tester) async {
      final repo = AdminInscripcionesRepository(
        gateway: FakeInscripcionGateway()..ocupacionDevuelta = const [],
      );
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));
      expect(find.text('No hay secciones'), findsOneWidget);
    });

    testWidgets('muestra métricas y la etiqueta «Oferta en el aire»', (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            cuposDisponibles: 2,
            cuposOcupados: 3,
            ofertaVigente: true,
          ),
          ocupacionSeccionEjemplo(
            id: 'sec-2',
            cuposDisponibles: 0,
            cuposOcupados: 5,
            ofertaVigente: false,
          ),
        ];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      // Etiquetas de las métricas presentes.
      expect(find.text('Secciones'), findsOneWidget);
      expect(find.text('Con oferta en el aire'), findsOneWidget);
      expect(find.text('Cupos disponibles'), findsOneWidget);
      expect(find.text('Cupos ocupados'), findsOneWidget);
      // La etiqueta destacada sólo sale para la sección con oferta vigente.
      expect(find.text('Oferta en el aire'), findsOneWidget);
    });

    testWidgets('«Promover siguiente» delega la sección al repositorio (éxito)',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [
          ocupacionSeccionEjemplo(id: 'sec-1', ofertaVigente: false),
          ocupacionSeccionEjemplo(id: 'sec-2', ofertaVigente: false),
        ];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      await pulsar(tester, botonFilled('Promover siguiente').at(0));
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('promoverSiguiente:sec-1'));
    });

    testWidgets('«Promover siguiente» con cola vacía muestra aviso de validación',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo(id: 'sec-1')]
        ..errorAlPromover =
            const AppException.validacion('No hay nadie en la cola.');
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      await pulsar(tester, botonFilled('Promover siguiente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // El aviso es de negocio, no un error técnico disfrazado.
      expect(find.text('No hay nadie en la cola.'), findsOneWidget);
      // La llamada se hizo igual (el gateway registra antes de lanzar).
      expect(fake.llamadas, contains('promoverSiguiente:sec-1'));
      await cerrarAvisos(tester);
    });

    testWidgets('«Expirar ofertas» delega al repositorio', (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo(id: 'sec-1')];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      await tester.tap(
        botonOutlined('Expirar ofertas'),
      );
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('expirarOfertas'));
    });

    testWidgets('Reincorporar valida los ids antes de llamar al repositorio',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ocupacionDevuelta = [ocupacionSeccionEjemplo(id: 'sec-1')];
      final repo = AdminInscripcionesRepository(gateway: fake);
      await montarPanel(tester, CpanelInscripcionesPanel(repositorio: repo));

      // Abre el diálogo.
      await tester.tap(botonFilled('Reincorporar'));
      await tester.pumpAndSettle();
      expect(find.text('Reincorporar estudiante'), findsOneWidget);

      // Confirmar con los campos vacíos: el validador lo bloquea, no hay llamada.
      final confirmar = find.descendant(
        of: find.byType(AlertDialog),
        matching: botonFilled('Reincorporar'),
      );
      await tester.tap(confirmar);
      await tester.pump();
      expect(fake.llamadas.any((c) => c.startsWith('reincorporar:')), isFalse);

      // Con los ids completos, sí llama.
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'est-9',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'sec-9',
      );
      await tester.tap(confirmar);
      await tester.pumpAndSettle();

      expect(fake.llamadas, contains('reincorporar:est-9:sec-9'));
    });
  });

  group('CpanelInscripcionesPanel · exportación hacia HACER', () {
    /// Monta el panel con la exportación y la descarga inyectadas.
    ///
    /// Devuelve los dos dobles para que cada prueba mire **qué se pidió** y
    /// **qué se descargó**: el contrato del botón no es «se llamó a exportar»,
    /// es «exportó *esta* sección» y «el archivo lleva *esta* cabecera y *esta*
    /// fila».
    Future<(FakeExportacionHacerGateway, FakeSelectorDeArchivos)> montarCon(
      WidgetTester tester, {
      required List<OcupacionSeccion> secciones,
    }) async {
      final exportacion = FakeExportacionHacerGateway();
      final selector = FakeSelectorDeArchivos();
      final ocupacion = FakeInscripcionGateway()..ocupacionDevuelta = secciones;

      await montarPanel(
        tester,
        CpanelInscripcionesPanel(
          repositorio: AdminInscripcionesRepository(gateway: ocupacion),
          exportacion: ExportacionHacerRepository(gateway: exportacion),
          selector: selector,
        ),
      );
      return (exportacion, selector);
    }

    /// El botón de exportación de la tarjeta [indice], pulsado.
    ///
    /// Va por [pulsar] porque la tarjeta queda **por debajo del pliegue**; ahí
    /// está el porqué. El `pumpAndSettle` final deja que la descarga y su aviso
    /// terminen antes de que la prueba mire.
    Future<void> pulsarExportar(WidgetTester tester, {int indice = 0}) async {
      await pulsar(
        tester,
        botonOutlined('Exportar Planilla HACER (.csv)').at(indice),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('cada tarjeta lleva su propio botón de exportación',
        (tester) async {
      await montarCon(
        tester,
        secciones: [
          ocupacionSeccionEjemplo(id: 'sec-1'),
          ocupacionSeccionEjemplo(id: 'sec-2'),
        ],
      );

      // Uno por sección, no uno global: el panel no tiene selector de sección,
      // pinta una tarjeta por sección y la tarjeta **es** el contexto. Un botón
      // único en la cabecera tendría que preguntar «¿cuál?» en un diálogo.
      expect(find.text('Exportar Planilla HACER (.csv)'), findsNWidgets(2));
    });

    testWidgets('exporta la sección de su propia tarjeta, no «una» sección',
        (tester) async {
      final (exportacion, _) = await montarCon(
        tester,
        secciones: [
          ocupacionSeccionEjemplo(id: 'sec-1'),
          ocupacionSeccionEjemplo(id: 'sec-2'),
        ],
      );

      await pulsarExportar(tester, indice: 1);
      await cerrarAvisos(tester);

      // La segunda tarjeta exporta `sec-2` y sólo `sec-2`. Sin esta aserción, un
      // botón que exportara siempre la primera sección pasaría inadvertido.
      expect(exportacion.llamadas, ['filasDeSeccion:sec-2']);
    });

    testWidgets('descarga el CSV con el nombre y el contenido de la nómina',
        (tester) async {
      final (exportacion, selector) = await montarCon(
        tester,
        secciones: [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            nombre: 'Sección A',
            materia: 'Soldadura por Arco',
          ),
        ],
      );
      exportacion.filasDevueltas = [
        filaExportacionEjemplo(
          sobrescribir: {'cedula': 'V-12345678', 'nombres': 'Alumna1 Del'},
        ),
      ];

      await pulsarExportar(tester);

      expect(exportacion.llamadas, ['filasDeSeccion:sec-1']);

      // El nombre sale del contexto de la sección, con el período delante: dos
      // descargas del mismo día no se pisan. Y conserva el acento, que en un
      // nombre no es un error de codificación.
      expect(
        selector.ultimoNombreDeTextoDescargado,
        'planilla-hacer-SA26-2-Soldadura-por-Arco-Sección-A.csv',
      );
      expect(selector.ultimoTipoMimeDescargado, contains('text/csv'));

      final csv = selector.ultimoTextoDescargado!;
      final lineas = csv.split('\r\n');

      // Cabecera + una fila + el salto final: tres trozos. El CSV termina en
      // CRLF y no en LF suelto, como manda la RFC 4180.
      expect(lineas.length, 3);
      expect(csv.endsWith('\r\n'), isTrue);
      expect(lineas.first.split(',').length, columnasExportacionHacer.length);
      expect(lineas.first, startsWith('inscripcion_id,seccion_id,lapso'));

      // Y la fila lleva los datos del matriculado, no sólo la cabecera.
      expect(csv, contains('V-12345678'));
      expect(csv, contains('Alumna1 Del'));

      expect(
        find.textContaining('Nómina exportada: 1 matriculado(s)'),
        findsOneWidget,
      );
      await cerrarAvisos(tester);
    });

    testWidgets('una sección sin matriculados avisa y no descarga nada',
        (tester) async {
      final (exportacion, selector) = await montarCon(
        tester,
        secciones: [ocupacionSeccionEjemplo(id: 'sec-1', nombre: 'Sección A')],
      );
      exportacion.filasDevueltas = const [];

      await pulsarExportar(tester);

      // Cero filas no es un error —es una sección recién abierta— pero tampoco
      // es una exportación: descargar un archivo con sólo la cabecera se leería
      // como «se exportó bien».
      expect(selector.llamadas, isNot(contains('descargarTexto')));
      expect(
        find.text('La sección «Sección A» no tiene matriculados todavía: no hay '
            'nómina que exportar.'),
        findsOneWidget,
      );
      await cerrarAvisos(tester);
    });

    testWidgets('si la consulta falla avisa del fallo y no descarga nada',
        (tester) async {
      final (exportacion, selector) = await montarCon(
        tester,
        secciones: [ocupacionSeccionEjemplo(id: 'sec-1')],
      );
      exportacion.errorAlConsultar =
          const AppException.validacion('La vista de exportación no respondió.');

      await pulsarExportar(tester);

      expect(exportacion.llamadas, ['filasDeSeccion:sec-1']);
      expect(find.text('La vista de exportación no respondió.'), findsOneWidget);
      expect(selector.llamadas, isNot(contains('descargarTexto')));
      await cerrarAvisos(tester);
    });

    testWidgets('si la descarga falla avisa y el botón deja de girar',
        (tester) async {
      final (exportacion, selector) = await montarCon(
        tester,
        secciones: [ocupacionSeccionEjemplo(id: 'sec-1')],
      );
      exportacion.filasDevueltas = [filaExportacionEjemplo()];
      selector.errorAlDescargarTexto = Exception('el navegador dijo no');

      await pulsarExportar(tester);

      // El error del navegador no se le enseña al administrador: no le dice
      // nada y no puede hacer nada con él. Se dice qué pasó y qué hacer.
      expect(
        find.text('No se pudo descargar el archivo. Inténtalo de nuevo.'),
        findsOneWidget,
      );

      // Y el indicador se libera **antes** de descargar, así que un fallo del
      // navegador no deja el botón girando para siempre. Si el `remove` del
      // estado de carga se moviera al final del método, esta aserción caería.
      expect(find.text('Exportando…'), findsNothing);
      expect(find.text('Exportar Planilla HACER (.csv)'), findsOneWidget);
      await cerrarAvisos(tester);
    });

    testWidgets('el panel explica qué entra en la nómina y qué no',
        (tester) async {
      await montarCon(
        tester,
        secciones: [ocupacionSeccionEjemplo(id: 'sec-1')],
      );

      // «Nómina» no es «todos los que pidieron cupo»: la cola de espera y las
      // bajas quedan fuera. Si el aviso desapareciera, el administrador tendría
      // que deducirlo del archivo — o no lo deduciría.
      expect(
        find.textContaining('Sólo salen los que tienen asiento confirmado'),
        findsOneWidget,
      );
    });
  });
}
