import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

/// Pruebas de que las secciones del menú son **alcanzables**.
///
/// Existen por **R-22**: `CpanelProgramasPanel` estaba construido, probado y
/// enrutado en el `switch` del cPanel… y su ítem del menú seguía con
/// `disponible: false`. `AndamiajeApp` **no envuelve en `InkWell`** un ítem no
/// disponible (`widgets/andamiaje.dart`), así que ese `case` era **código
/// muerto**: ningún administrador podía abrir el asistente de currículo.
///
/// Ninguna de las 197 pruebas lo vio porque **ninguna monta el dashboard**.
/// Probaban cada panel montado a mano dentro de `ContenidoSeccion` —que es lo
/// correcto para el layout, y es lo que destapó el crash de altura acotada— y
/// el **cableado del menú** quedaba sin cubrir. La lección, que es distinta de
/// «faltan pruebas de widget»: **probar el panel donde vive no prueba que se
/// pueda llegar a él.** Son dos contratos y sólo uno estaba cubierto.
///
/// De ahí las dos partes de este archivo:
///
///  1. un **contrato leído del código fuente**, que compara las secciones del
///     menú con las ramas del `switch` y falla si alguna queda inalcanzable;
///  2. la **prueba del mecanismo** en [AndamiajeApp], que fija por qué un ítem
///     no disponible no se puede pulsar. Sin ella, el contrato de (1) exigiría
///     una propiedad que nadie garantiza en tiempo de ejecución.
///
/// El contrato de (1) **no se escribe como un espejo a mano** —una lista de
/// títulos copiada en la prueba— porque eso sólo probaría que la copia coincide
/// consigo misma. Se lee el archivo real, igual que `reglas-cuadrante.test.ts`
/// lee la migración de M3.
void main() {
  group('cPanel · cada sección con panel construido es alcanzable', () {
    test('las secciones disponibles y las ramas del switch coinciden', () {
      final fuente = _fuenteDashboard().readAsStringSync();
      final secciones = _leerSecciones(fuente);
      final atendidas = _leerRamasDelSwitch(fuente);

      // Suelo explícito: si el analizador se rompe (un formato distinto, un
      // renombrado), esta prueba fallaría comparando dos conjuntos vacíos y
      // daría un verde hueco. Con el suelo, un fallo del analizador se ve como
      // lo que es.
      expect(
        secciones.length,
        greaterThanOrEqualTo(8),
        reason: 'se esperaban al menos 8 secciones en el menú del cPanel; '
            'el analizador de _items probablemente se rompió',
      );
      expect(
        atendidas.length,
        greaterThanOrEqualTo(6),
        reason: 'se esperaban al menos 6 ramas en el switch de _contenido(); '
            'el analizador probablemente se rompió',
      );

      final disponibles = {
        for (final seccion in secciones)
          if (seccion.disponible) seccion.titulo,
      };

      // Las dos direcciones, y cada una tapa un fallo distinto:
      //
      //  · una sección con rama y la bandera puesta es **inalcanzable** — es
      //    exactamente R-22, y por eso esta igualdad es la que lo habría
      //    atrapado;
      //  · una sección disponible **sin** rama cae al `default:` del switch,
      //    que sólo pinta las migas de pan: el usuario entra y ve una página
      //    vacía. Es peor que no poder entrar, que es justo lo que la bandera
      //    existía para evitar.
      expect(
        disponibles,
        atendidas,
        reason: 'Toda sección con panel construido debe tener la bandera '
            'levantada Y su rama en el switch. Una diferencia aquí significa '
            'o un panel inalcanzable (R-22) o una sección que abre en blanco.',
      );
    });

    test('el analizador lee las secciones y sus banderas', () {
      // Prueba del propio analizador, con un texto de forma conocida. Sin
      // esto, un analizador que devolviera siempre la lista vacía pasaría el
      // suelo de la prueba anterior… y con él, cualquier comparación.
      final fuente = '''
  static const List<ItemNavegacion> _items = [
    ItemNavegacion(
      icono: Icons.tune_outlined,
      titulo: 'Con Panel',
      categoria: 'General',
    ),
    ItemNavegacion(
      icono: Icons.build_outlined,
      titulo: 'Sin Panel',
      categoria: 'General',
      disponible: false,
    ),
  ];
''';

      final secciones = _leerSecciones(fuente);

      expect(secciones.map((s) => s.titulo), ['Con Panel', 'Sin Panel']);
      expect(secciones.map((s) => s.disponible), [true, false]);
    });

    test('el analizador lee las ramas del switch', () {
      final fuente = '''
  Widget _contenido() {
    switch (x) {
      case 'Una':
        return const A();
      case 'Otra':
        return const B();
      default:
        return const C();
    }
  }
''';

      expect(_leerRamasDelSwitch(fuente), {'Una', 'Otra'});
    });
  });

  group('AndamiajeApp · un ítem no disponible no es pulsable', () {
    /// Monta el andamiaje con una sección construida y otra pendiente.
    ///
    /// Se monta a **1400 px de ancho** a propósito: por debajo de 900 el menú
    /// pasa a cajón (`Drawer`) y no se pinta en el árbol, y por debajo de 1280
    /// arranca replegado, donde las etiquetas tampoco se ven. En la ventana por
    /// defecto de las pruebas (800×600) no se encontraría ninguna etiqueta.
    Future<int?> montarYpulsar(
      WidgetTester tester, {
      String? pulsar,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? seleccionada;
      await tester.pumpWidget(
        MaterialApp(
          theme: IncesTheme.claro(),
          home: AndamiajeApp(
            items: const [
              ItemNavegacion(
                icono: Icons.tune_outlined,
                titulo: 'Construida',
                categoria: 'General',
              ),
              ItemNavegacion(
                icono: Icons.build_outlined,
                titulo: 'Pendiente',
                categoria: 'General',
                disponible: false,
              ),
            ],
            seleccionado: 0,
            onSeleccionar: (indice) => seleccionada = indice,
            rolEtiqueta: 'Administrador Maestro',
            contenido: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      if (pulsar != null) {
        // `warnIfMissed: false` porque el caso que interesa es precisamente
        // pulsar algo que no recibe el toque.
        await tester.tap(find.text(pulsar), warnIfMissed: false);
        await tester.pump();
      }

      return seleccionada;
    }

    testWidgets('pulsar una sección construida la selecciona', (tester) async {
      expect(await montarYpulsar(tester, pulsar: 'Construida'), 0);
    });

    testWidgets('pulsar una sección pendiente no selecciona nada', (
      tester,
    ) async {
      // El toque no puede llegar a `onSeleccionar`: es la razón de que el
      // `case` de una sección con la bandera puesta fuera código muerto.
      expect(await montarYpulsar(tester, pulsar: 'Pendiente'), isNull);
    });

    testWidgets('sólo la construida queda dentro de un InkWell', (
      tester,
    ) async {
      await montarYpulsar(tester);

      expect(
        find.ancestor(
          of: find.text('Construida'),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Pendiente'),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });
  });
}

// -----------------------------------------------------------------------------
//  Lectura del dashboard
// -----------------------------------------------------------------------------

/// Una sección del menú, tal y como está declarada en el dashboard.
class _Seccion {
  const _Seccion(this.titulo, {required this.disponible});

  final String titulo;

  /// `false` ⇒ la sección se pinta atenuada y **sin** `InkWell`: inalcanzable.
  final bool disponible;
}

/// Localiza `lib/screens/admin_dashboard.dart` sin dar por hecho el directorio.
///
/// `flutter test` corre desde la raíz del paquete, pero asumirlo convertiría un
/// cambio de invocación en un «fichero no encontrado» que no explica nada. Se
/// sube por los directorios padres hasta encontrarlo, y si no aparece se falla
/// diciendo desde dónde se buscó.
File _fuenteDashboard() {
  var directorio = Directory.current;

  for (var intentos = 0; intentos < 6; intentos++) {
    final candidato = File(
      '${directorio.path}/lib/screens/admin_dashboard.dart',
    );
    if (candidato.existsSync()) return candidato;

    final padre = directorio.parent;
    if (padre.path == directorio.path) break;
    directorio = padre;
  }

  fail(
    'No se encontró lib/screens/admin_dashboard.dart subiendo desde '
    '${Directory.current.path}',
  );
}

/// Extrae las secciones de la lista `_items`.
List<_Seccion> _leerSecciones(String fuente) {
  final inicio = fuente.indexOf('static const List<ItemNavegacion> _items');
  if (inicio == -1) {
    fail('No se encontró la lista _items en admin_dashboard.dart');
  }
  final fin = fuente.indexOf('];', inicio);
  if (fin == -1) {
    fail('No se encontró el cierre de la lista _items');
  }

  final bloque = fuente.substring(inicio, fin);
  final secciones = <_Seccion>[];

  // Un bloque por `ItemNavegacion(…)`. El cuerpo no contiene paréntesis —sólo
  // iconos, títulos y categorías—, así que el primer `),` cierra el bloque.
  for (final coincidencia
      in RegExp(r'ItemNavegacion\(([\s\S]*?)\),').allMatches(bloque)) {
    final cuerpo = coincidencia.group(1) ?? '';
    final titulo = RegExp(r"titulo:\s*'([^']+)'").firstMatch(cuerpo);
    if (titulo == null) continue;

    secciones.add(
      _Seccion(
        titulo.group(1)!,
        // Ausencia de `disponible: false` equivale a disponible: el valor por
        // defecto del constructor es `true`. Leerlo así evita depender de que
        // cada ítem construido escriba `disponible: true` explícitamente.
        disponible: !cuerpo.contains('disponible: false'),
      ),
    );
  }

  return secciones;
}

/// Extrae los títulos que el `switch` de `_contenido()` atiende de verdad.
Set<String> _leerRamasDelSwitch(String fuente) {
  final inicio = fuente.indexOf('Widget _contenido()');
  if (inicio == -1) {
    fail('No se encontró _contenido() en admin_dashboard.dart');
  }
  final fin = fuente.indexOf('default:', inicio);
  if (fin == -1) {
    fail('No se encontró la rama default del switch de _contenido()');
  }

  final bloque = fuente.substring(inicio, fin);
  return RegExp(r"case '([^']+)':")
      .allMatches(bloque)
      .map((m) => m.group(1)!)
      .toSet();
}
