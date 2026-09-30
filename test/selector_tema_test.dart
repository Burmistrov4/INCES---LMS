import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

/// Pruebas del selector de tema del pie de la barra lateral (Bloque D).
///
/// Se monta `AndamiajeApp` **directamente** y no la aplicación entera: lo que se
/// comprueba aquí es el contrato del widget —que el selector aparezca sólo
/// cuando hay a quién avisar, que esté en el pie, que ofrezca los tres modos y
/// que avise con el elegido—, y montar `IncesLmsApp` traería consigo el enrutado
/// por sesión, que no tiene nada que ver. La prueba mediría otra cosa.
void main() {
  /// Monta el andamiaje con la ventana ancha que hace falta para ver el pie.
  ///
  /// **1400×2000 y no la ventana por defecto.** Con 800×600 el menú pasa a
  /// **cajón** (por debajo de 900 px no se pinta en el árbol, sólo dentro del
  /// `Drawer`) y el pie no existiría para el buscador de widgets; y por debajo
  /// de 1280 arranca **replegado**, donde el selector enseña sólo el icono y no
  /// la etiqueta. Las dos condiciones están en `_AndamiajeAppState`, así que la
  /// ventana no es un detalle del test sino un requisito de lo que se mide.
  Future<void> montar(
    WidgetTester tester, {
    ThemeMode? temaActual,
    ValueChanged<ThemeMode>? onCambiarTema,
    VoidCallback? onCerrarSesion,
    List<ItemNavegacion> items = const <ItemNavegacion>[],
  }) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        darkTheme: IncesTheme.oscuro(),
        themeMode: temaActual,
        home: AndamiajeApp(
          items: items,
          seleccionado: 0,
          onSeleccionar: (_) {},
          rolEtiqueta: 'Docente',
          contenido: const SizedBox.shrink(),
          temaActual: temaActual,
          onCambiarTema: onCambiarTema,
          onCerrarSesion: onCerrarSesion,
        ),
      ),
    );
    await tester.pump();
  }

  /// Abre el menú del selector y deja terminar su animación de entrada.
  ///
  /// **Sin `pumpAndSettle`**: es el criterio que ya usan las demás pruebas del
  /// proyecto, porque una animación que no termina agota el tiempo límite y
  /// convierte un fallo del código en un fallo de la prueba. Dos `pump`
  /// acotados bastan para que el menú esté montado y en su sitio.
  Future<void> abrirMenu(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<ThemeMode>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// El ítem del menú cuya etiqueta es [etiqueta].
  ///
  /// **No se puede pulsar con `find.text` a secas.** Cuando el modo vigente es
  /// el mismo que se va a elegir, la etiqueta aparece dos veces —en la del pie y
  /// en la opción del menú—, y un `tap` sobre un localizador que encuentra dos
  /// widgets falla por ambigüedad. Acotar al `PopupMenuItem` deja una sola.
  Finder opcionDelMenu(String etiqueta) => find.descendant(
        of: find.byType(PopupMenuItem<ThemeMode>),
        matching: find.text(etiqueta),
      );

  // ---------------------------------------------------------------------------
  //  El contrato que protege a las pruebas que ya existían
  // ---------------------------------------------------------------------------

  testWidgets('sin onCambiarTema el selector no se dibuja', (tester) async {
    // Es la garantía de que este cambio no rompe a quien monta el andamiaje sin
    // proveedor de tema: `menu_alcanzable_test.dart` lo monta con un
    // `SizedBox`, y el panel del docente —que incluye el andamiaje— se monta
    // así en `aula_produccion_test.dart` y
    // `menu_gobernado_por_modulos_test.dart`. Un selector incondicional les
    // exigiría un proveedor inventado para poder montar lo que están probando.
    await montar(tester);

    expect(find.byType(PopupMenuButton<ThemeMode>), findsNothing);
    expect(find.text('Sistema'), findsNothing);
  });

  testWidgets('con onCambiarTema el selector sí se dibuja', (tester) async {
    // La cara opuesta de la prueba anterior. Sin ella, un `null` permanente
    // pasaría la primera y nadie notaría que el selector nunca aparece.
    await montar(tester, onCambiarTema: (_) {});

    expect(find.byType(PopupMenuButton<ThemeMode>), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  //  Dónde vive
  // ---------------------------------------------------------------------------

  testWidgets('el selector está en el pie: debajo de los ítems', (tester) async {
    // La decisión fue «pie de la barra lateral», y esto la mide: se compara la
    // posición vertical contra un ítem del menú, que tiene que quedar por
    // encima. Sin esta comprobación, mover el selector al encabezado pasaría
    // todas las demás pruebas.
    await montar(
      tester,
      onCambiarTema: (_) {},
      items: const [
        ItemNavegacion(
          icono: Icons.home_rounded,
          titulo: 'Inicio',
          categoria: 'General',
        ),
      ],
    );

    final item = tester.getTopLeft(find.text('Inicio')).dy;
    final selector =
        tester.getTopLeft(find.byType(PopupMenuButton<ThemeMode>)).dy;

    expect(
      selector,
      greaterThan(item),
      reason: 'el selector es del pie: va por debajo de los ítems del menú',
    );
  });

  testWidgets('el selector queda por encima de cerrar sesión', (tester) async {
    // El pie se lee de arriba abajo: ajustes, controles y por último la acción
    // que saca al usuario de la aplicación.
    await montar(
      tester,
      onCambiarTema: (_) {},
      onCerrarSesion: () {},
    );

    final selector =
        tester.getTopLeft(find.byType(PopupMenuButton<ThemeMode>)).dy;
    final cerrar = tester.getTopLeft(find.text('Cerrar sesión')).dy;

    expect(selector, lessThan(cerrar));
  });

  // ---------------------------------------------------------------------------
  //  Qué enseña
  // ---------------------------------------------------------------------------

  testWidgets('la etiqueta del pie nombra el modo vigente', (tester) async {
    await montar(tester, temaActual: ThemeMode.dark, onCambiarTema: (_) {});

    expect(find.text('Oscuro'), findsOneWidget);
    expect(find.text('Sistema'), findsNothing);
    expect(find.text('Claro'), findsNothing);
  });

  testWidgets('sin tema declarado el pie dice «Sistema»', (tester) async {
    // `temaActual` es nulable y cae a `system`. Es el caso de quien ofrece el
    // selector sin declarar cuál está puesto, y el que hace que la etiqueta no
    // pueda quedar en blanco.
    await montar(tester, onCambiarTema: (_) {});

    expect(find.text('Sistema'), findsOneWidget);
  });

  testWidgets('el menú ofrece los tres modos, en orden', (tester) async {
    await montar(tester, temaActual: ThemeMode.system, onCambiarTema: (_) {});
    await abrirMenu(tester);

    final ofrecidos = tester
        .widgetList<PopupMenuItem<ThemeMode>>(
          find.byType(PopupMenuItem<ThemeMode>),
        )
        .map((opcion) => opcion.value)
        .toList();

    expect(
      ofrecidos,
      [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
      reason: 'los tres modos de `ThemeMode`, en el orden en que los declara',
    );

    // Y con su nombre visible. Se usa `findsWidgets` y no un conteo exacto
    // porque «Sistema» aparece dos veces con el modo del sistema vigente: en la
    // etiqueta del pie y en la opción del menú. Contarlas ataría la prueba a
    // cuál está seleccionado, que es justo lo que cambia entre pruebas.
    expect(find.text('Sistema'), findsWidgets);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Oscuro'), findsOneWidget);
  });

  testWidgets('el modo vigente lleva la marca de selección', (tester) async {
    await montar(tester, temaActual: ThemeMode.dark, onCambiarTema: (_) {});
    await abrirMenu(tester);

    // Una sola marca, y sólo una: es lo que distingue «marca el vigente» de
    // «marca los tres».
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  //  Qué avisa
  // ---------------------------------------------------------------------------

  testWidgets('elegir un modo avisa con ese modo', (tester) async {
    final elegidos = <ThemeMode>[];
    await montar(
      tester,
      temaActual: ThemeMode.system,
      onCambiarTema: elegidos.add,
    );
    await abrirMenu(tester);

    await tester.tap(opcionDelMenu('Oscuro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      elegidos,
      [ThemeMode.dark],
      reason: 'se avisa una vez y con el modo elegido, no con el vigente',
    );
  });

  testWidgets('elegir el modo que ya estaba también avisa', (tester) async {
    // El andamiaje no decide si el modo cambió: eso es del proveedor, que ya lo
    // comprueba en `tema_provider_test.dart`. Aquí se fija el reparto de
    // responsabilidades —el widget avisa siempre, el proveedor filtra— para que
    // nadie mueva esa decisión al widget sin darse cuenta.
    final elegidos = <ThemeMode>[];
    await montar(
      tester,
      temaActual: ThemeMode.dark,
      onCambiarTema: elegidos.add,
    );
    await abrirMenu(tester);

    await tester.tap(opcionDelMenu('Oscuro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(elegidos, [ThemeMode.dark]);
  });
}
