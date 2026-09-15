import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/reglas_cuadrante.dart';
import 'package:inces_lms_app/models/cuadrante.dart';
import 'package:inces_lms_app/repositories/cuadrante_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_aulas_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_lapsos_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_cuadrante_gateway.dart';

/// Pruebas de los paneles de espacios y lapsos.
///
/// Se montan **dentro de `ContenidoSeccion`**, que es donde viven de verdad.
/// Montarlos en el `body` acotado de un `Scaffold` escondería justo el fallo que
/// importa: `ContenidoSeccion` entrega a su hijo una altura acotada, y un panel
/// que reparte el espacio con `Expanded` revienta si recibe una infinita. Ese
/// fallo ya ocurrió en tres paneles del cPanel y ninguna prueba lo vio.
void main() {
  late FakeCuadranteGateway gateway;
  late CuadranteRepository repo;

  setUp(() {
    gateway = FakeCuadranteGateway();
    repo = CuadranteRepository(gateway: gateway);
  });

  /// Rótulo tal y como queda en pantalla.
  ///
  /// `TituloSeccion` pinta `texto.toUpperCase()`, así que buscar el título en su
  /// forma legible nunca lo encuentra.
  String rotulo(String texto) => texto.toUpperCase();

  /// Monta un panel en una ventana amplia, dentro del contenedor real.
  Future<Object?> montar(WidgetTester tester, Widget panel) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ContenidoSeccion(
            migas: const ['Inicio', 'Control de aulas'],
            child: panel,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tester.takeException();
  }

  group('panel de espacios', () {
    testWidgets('la lista se pinta sin romper el layout', (tester) async {
      gateway.aulas = const [
        Aula(
          id: 'a1',
          nombre: 'Taller de Soldadura Cabina A',
          capacidad: 12,
          esTaller: true,
          activa: true,
        ),
        Aula(
          id: 'a2',
          nombre: 'Pasillo de talleres',
          capacidad: 0,
          esTaller: false,
          activa: true,
        ),
      ];
      gateway.totalAulas = 2;

      final excepcion = await montar(tester, CpanelAulasPanel(repositorio: repo));

      expect(excepcion, isNull, reason: 'el layout no debe reventar');
      expect(find.text('Taller de Soldadura Cabina A'), findsOneWidget);
      expect(find.text('Pasillo de talleres'), findsOneWidget);
    });

    testWidgets('la capacidad cero se lee como «sin cupo», no como cero puestos',
        (tester) async {
      gateway.aulas = const [
        Aula(
          id: 'a2',
          nombre: 'Pasillo de talleres',
          capacidad: 0,
          esTaller: false,
          activa: true,
        ),
      ];
      gateway.totalAulas = 1;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      // Cero es «sin cupo declarado», que no es lo mismo que un aula vacía. El
      // tipo lo confirma: es una zona.
      expect(find.text('Sin cupo declarado'), findsOneWidget);
      expect(find.text('0 puestos'), findsNothing);
      expect(find.text('Zona'), findsOneWidget);
    });

    testWidgets('el tipo del espacio sale de sus columnas', (tester) async {
      gateway.aulas = const [
        Aula(id: 'a1', nombre: 'Taller A', capacidad: 12, esTaller: true,
            activa: true),
        Aula(id: 'a2', nombre: 'Aula 3', capacidad: 30, esTaller: false,
            activa: true),
        Aula(id: 'a3', nombre: 'Pasillo', capacidad: 0, esTaller: false,
            activa: true),
      ];
      gateway.totalAulas = 3;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      expect(find.text('Taller'), findsOneWidget);
      expect(find.text('Aula'), findsOneWidget);
      expect(find.text('Zona'), findsOneWidget);
    });

    testWidgets('el vacío explica que sin espacios no hay cuadrante',
        (tester) async {
      gateway.aulas = const [];
      gateway.totalAulas = 0;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      expect(find.text('Todavía no hay espacios registrados'), findsOneWidget);
      // El vacío dice POR QUÉ, y por qué no viene sembrado: si no, se lee como
      // una lista rota o un problema de permisos.
      expect(
        find.textContaining('no se puede armar el cuadrante'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no trae espacios de ejemplo'),
        findsOneWidget,
      );
    });

    testWidgets('un filtro sin resultados lo dice, en vez de parecer vacío',
        (tester) async {
      gateway.aulas = const [];
      gateway.totalAulas = 0;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      await tester.tap(find.text('Talleres'));
      await tester.pump();
      await tester.pump();

      // «No hay nada» y «no hay nada que coincida» son dos cosas distintas, y
      // el usuario tiene que poder distinguirlas sin adivinar.
      expect(
        find.text('Ningún espacio coincide con el filtro'),
        findsOneWidget,
      );
      expect(gateway.ultimoTipoAula, TipoAula.taller);
    });

    testWidgets('archivar manda activa:false y no borra nada', (tester) async {
      gateway.aulas = const [
        Aula(id: 'a1', nombre: 'Taller A', capacidad: 12, esTaller: true,
            activa: true),
      ];
      gateway.totalAulas = 1;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      await tester.tap(find.byTooltip('Archivar'));
      await tester.pump();
      await tester.pump();

      // Archivar es desactivar: un `DELETE` se llevaría por delante el cuadrante
      // y las guardias que apuntan al espacio, y la base lo impide con
      // `on delete restrict`.
      expect(gateway.ultimosCambiosAula!.toJson(), {'activa': false});
    });

    testWidgets('un nombre repetido se explica con su propio mensaje',
        (tester) async {
      gateway.errorAlCrearAula = const AppException(
        type: AppErrorType.validacion,
        message: 'Ese registro ya existe en el sistema.',
        code: codigoRegistroDuplicado,
      );

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      await tester.tap(find.text('Registrar espacio'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'Taller A',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      // El mensaje genérico del backend no dice cuál de los dos espacios está
      // repetido ni que basta con cambiarle el nombre.
      expect(
        find.textContaining('Ya existe un espacio con ese nombre'),
        findsOneWidget,
      );
    });

    testWidgets('el formulario no deja guardar un nombre en blanco',
        (tester) async {
      await montar(tester, CpanelAulasPanel(repositorio: repo));

      await tester.tap(find.text('Registrar espacio'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresa el nombre del espacio.'), findsOneWidget);
      // No llegó a ESCRIBIR: la validación previa existe para no gastar un viaje
      // en un 400 que ya se podía prever.
      //
      // Se comprueba la escritura y no el registro entero: el panel carga la
      // lista en `initState`, así que `listarAulas` está ahí y siempre estará.
      // Un `expect(llamadas, isEmpty)` falla por un motivo que no es el que la
      // prueba quiere vigilar.
      expect(gateway.llamadas, isNot(contains('crearAula')));
    });

    testWidgets('con una sola página no hay botones de paginación',
        (tester) async {
      gateway.aulas = const [
        Aula(id: 'a1', nombre: 'Taller A', capacidad: 12, esTaller: true,
            activa: true),
      ];
      gateway.totalAulas = 1;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      // Con nueve espacios —el catálogo entero del centro— unos botones muertos
      // serían ruido.
      expect(find.text('Siguientes'), findsNothing);
      expect(find.text('Anteriores'), findsNothing);
    });

    testWidgets('con más de una página aparece el pie y no se puede volver',
        (tester) async {
      // Se declara el total ANTES de montar: el panel lee en `initState`, y
      // volver a montar sobre el mismo árbol reutiliza el `State` —mismo tipo,
      // sin clave—, así que no vuelve a cargar. Por eso son dos pruebas y no
      // una con dos `montar` seguidos.
      gateway.aulas = const [
        Aula(id: 'a1', nombre: 'Taller A', capacidad: 12, esTaller: true,
            activa: true),
      ];
      gateway.totalAulas = 60;

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      expect(find.text('Siguientes'), findsOneWidget);
      // En la primera página no hay a dónde volver.
      final anterior = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Anteriores'),
      );
      expect(anterior.onPressed, isNull);
    });

    testWidgets('si la carga falla se ofrece reintentar', (tester) async {
      gateway.errorAlListarAulas = const AppException.red();

      await montar(tester, CpanelAulasPanel(repositorio: repo));

      expect(find.text('No pudimos cargar esta sección'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('panel de lapsos', () {
    testWidgets('distingue «abierto» de «vigente», que son cosas distintas',
        (tester) async {
      gateway.periodos = const [
        Periodo(
          id: 'p1',
          codigo: '2026-1',
          nombre: 'Lapso 2026-1',
          activo: true,
          vigente: true,
        ),
        Periodo(
          id: 'p2',
          codigo: '2026-2',
          activo: true,
          vigente: false,
        ),
      ];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      // El vigente lleva las dos insignias; el que sólo está abierto, una. Si
      // ambos se llamaran «activo», no habría forma de saber qué se está
      // dictando (R-19).
      expect(find.text('Vigente'), findsOneWidget);
      expect(find.text('Abierto'), findsNWidgets(2));
    });

    testWidgets('las fechas que faltan se dicen, no se inventan',
        (tester) async {
      gateway.periodos = const [
        Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
        Periodo(
          id: 'p2',
          codigo: '2026-2',
          fechaInicio: '2026-09-21',
          fechaFin: '2027-02-13',
          activo: true,
          vigente: false,
        ),
      ];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      // El centro no ha cargado las fechas del lapso en curso. Rellenarlas con
      // algo plausible sería fabricar un dato institucional (R-17).
      expect(find.text('Sin fechas cargadas'), findsOneWidget);
      expect(find.text('2026-09-21 → 2027-02-13'), findsOneWidget);
    });

    testWidgets('el vigente se ordena primero', (tester) async {
      gateway.periodos = const [
        Periodo(id: 'p2', codigo: '2027-1', activo: true, vigente: false),
        Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
      ];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      // El lapso en curso es lo que se viene a mirar.
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(
        textos.indexOf('Lapso 2026-1'),
        lessThan(textos.indexOf('2027-1')),
      );
    });

    testWidgets('«Hacer vigente» no se ofrece al que ya lo es', (tester) async {
      gateway.periodos = const [
        Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
        Periodo(id: 'p2', codigo: '2026-2', activo: true, vigente: false),
      ];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      // Mover el vigente es una sola ruta (`PUT /periodos/:id/vigente`), y
      // ofrecerla sobre el que ya lo es sería un botón que no hace nada.
      expect(find.text('Hacer vigente'), findsOneWidget);
    });

    testWidgets('el vacío explica para qué sirve registrar un lapso',
        (tester) async {
      gateway.periodos = const [];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      expect(find.text('Todavía no hay lapsos registrados'), findsOneWidget);
      expect(
        find.textContaining('pertenece siempre a un lapso'),
        findsOneWidget,
      );
    });

    testWidgets('el código de un lapso ya creado no se edita', (tester) async {
      gateway.periodos = const [
        Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
      ];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      // El código es la identidad del lapso y ya está citado en documentos:
      // se enseña pero no se toca.
      final campo = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Código'),
      );
      expect(campo.enabled, isFalse);
    });

    testWidgets('un código mal formado se rechaza antes de salir',
        (tester) async {
      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      await tester.tap(find.text('Registrar lapso'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Código'),
        '-2026',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('empezar por letra o dígito'),
        findsOneWidget,
      );
      expect(gateway.llamadas, isNot(contains('crearPeriodo')));
    });

    testWidgets('el título de la sección se pinta en mayúsculas', (tester) async {
      gateway.periodos = const [
        Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
      ];

      await montar(tester, CpanelLapsosPanel(repositorio: repo));

      // Se deja escrito a propósito: `TituloSeccion` aplica `toUpperCase()`, y
      // buscar el título en su forma legible no lo encuentra nunca.
      expect(find.text(rotulo('Lapsos académicos')), findsOneWidget);
    });
  });
}
