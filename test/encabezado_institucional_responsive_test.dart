import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/comunes.dart';

/// Guardia de layout de [EncabezadoInstitucional] en pantalla estrecha.
///
/// **Por qué existe.** Es la barra de las tres pantallas principales, y tenía
/// la misma estructura que `TituloSeccion` antes de arreglarlo: una `Row` con
/// un `Expanded` en el medio y las acciones al final como hijos **no
/// flexibles**. El `Expanded` (saludo + insignias) se queda con lo que sobre, y
/// si las acciones piden más de lo que hay, se queda sin ancho.
///
/// **Hoy el fallo no se manifiesta**, y eso hay que decirlo con precisión:
/// `accionesEncabezado` existe y se reenvía (`andamiaje.dart`), pero **ningún
/// llamador le pasa nada**, así que la lista va siempre vacía. No es un bug
/// activo: es una **trampa latente**. El primero que meta un botón ahí
/// reproduce el desborde. Estas pruebas fijan el comportamiento con acciones
/// para que eso no ocurra.
void main() {
  const movil = Size(375, 812);
  const escritorio = Size(1440, 900);

  Future<void> montar(
    WidgetTester tester,
    Size tamano, {
    List<Widget> acciones = const [],
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: EncabezadoInstitucional(
            rolEtiqueta: 'Administrador Maestro',
            // Nombres largos a propósito: el saludo usa sólo el primer nombre
            // justamente porque el completo no cabe. Probar con «Ana» no
            // probaría la decisión.
            nombreUsuario: 'Lorenzo Alejandro Roca Martínez',
            correoUsuario: 'lorenzo.roca.martinez@inces.gob.ve',
            periodoActivo: 'SA26-2',
            // En móvil el andamiaje pasa esto: la barra lateral es un cajón.
            onAbrirMenu: () {},
            acciones: acciones,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EncabezadoInstitucional · sin desbordes', () {
    testWidgets('a 375 px sin acciones', (tester) async {
      await montar(tester, movil);
      expect(find.text('Bienvenido, Lorenzo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 375 px con acciones (la trampa latente)', (tester) async {
      // El saludo se recorta al primer nombre por diseño; con las insignias y
      // dos botones, el ancho es el peor caso realista en móvil.
      await montar(tester, movil, acciones: [
        IconButton(
          tooltip: 'Notificaciones',
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: const Text('Salir'),
        ),
      ]);
      expect(tester.takeException(), isNull,
          reason: 'el encabezado desborda a 375 px cuando recibe acciones');
    });

    testWidgets('a 1440 px con acciones', (tester) async {
      await montar(tester, escritorio, acciones: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.logout_rounded, size: 17),
          label: const Text('Salir'),
        ),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el saludo usa sólo el primer nombre', (tester) async {
      // Es una decisión de diseño documentada en el widget, y la que evita que
      // el saludo se coma el ancho de las insignias.
      await montar(tester, movil);
      expect(find.text('Bienvenido, Lorenzo'), findsOneWidget);
      expect(find.textContaining('Roca Martínez'), findsNothing);
    });
  });
}
