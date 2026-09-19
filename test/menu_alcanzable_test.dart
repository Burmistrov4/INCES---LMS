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
/// Los dashboards que deben cumplir el contrato, con el suelo de cada uno.
///
/// **Los tres, y no sólo el cPanel.** R-22 pasó en el cPanel y por eso el
/// contrato se escribió mirando sólo `admin_dashboard.dart`… pero el fallo no
/// era del cPanel: era de **cualquier** dashboard con un menú y un `switch`. El
/// docente y el estudiante tenían exactamente la misma exposición, sin red.
/// Cuando se cableó la Capa 7 de M5 en los tres, se extendió la guardia.
///
/// **El suelo es por dashboard, no global.** Si el analizador se rompe en uno
/// solo (un formato distinto, un renombrado), un suelo compartido lo dejaría
/// pasar comparando dos conjuntos vacíos y daría un verde hueco — justo el fallo
/// que el suelo existe para evitar. Los números son el estado real de cada
/// archivo, no una estimación: `items` es el total del menú y `ramas` las
/// secciones que de verdad tienen panel.
const Map<String, ({int items, int ramas})> _dashboards = {
  'admin_dashboard.dart': (items: 10, ramas: 8),
  'docente_dashboard.dart': (items: 5, ramas: 3),
  'aspirante_dashboard.dart': (items: 6, ramas: 4),
};

void main() {
  group('cada dashboard · toda sección con panel construido es alcanzable', () {
    for (final entrada in _dashboards.entries) {
      test('${entrada.key}: disponibles y ramas del switch coinciden', () {
        final fuente = _fuente(entrada.key).readAsStringSync();
        final secciones = _leerSecciones(fuente);
        final atendidas = _leerRamasDelSwitch(fuente);

        // Suelo explícito: si el analizador se rompe, esta prueba fallaría
        // comparando dos conjuntos vacíos y daría un verde hueco. Con el suelo,
        // un fallo del analizador se ve como lo que es.
        expect(
          secciones.length,
          greaterThanOrEqualTo(entrada.value.items),
          reason: 'se esperaban al menos ${entrada.value.items} secciones en el '
              'menú de ${entrada.key}; el analizador de _items probablemente se '
              'rompió',
        );
        expect(
          atendidas.length,
          greaterThanOrEqualTo(entrada.value.ramas),
          reason: 'se esperaban al menos ${entrada.value.ramas} ramas en el '
              'switch de _contenido() de ${entrada.key}; el analizador '
              'probablemente se rompió',
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
          reason: 'En ${entrada.key}, toda sección con panel construido debe '
              'tener la bandera levantada Y su rama en el switch. Una '
              'diferencia aquí significa o un panel inalcanzable (R-22) o una '
              'sección que abre en blanco.',
        );
      });
    }

    test('el gestor documental de cada dashboard declara el tipo que le toca', () {
      // El tipo no es decorativo: el servidor lo valida contra un `CHECK`, así
      // que intercambiarlos haría fallar **toda** subida con un 400 mientras la
      // pantalla se vería exactamente igual. El docente sube guías; el
      // estudiante, entregas. Sin esta comprobación, un copiar-pegar entre los
      // dos dashboards pasa desapercibido hasta que alguien intenta subir.
      expect(
        _fuente('docente_dashboard.dart').readAsStringSync(),
        contains('TipoEntidadArchivo.teacherGuide'),
      );
      expect(
        _fuente('aspirante_dashboard.dart').readAsStringSync(),
        contains('TipoEntidadArchivo.taskSubmission'),
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

/// Localiza un dashboard bajo `lib/screens/` sin dar por hecho el directorio.
///
/// `flutter test` corre desde la raíz del paquete, pero asumirlo convertiría un
/// cambio de invocación en un «fichero no encontrado» que no explica nada. Se
/// sube por los directorios padres hasta encontrarlo, y si no aparece se falla
/// diciendo desde dónde se buscó.
File _fuente(String nombre) {
  var directorio = Directory.current;

  for (var intentos = 0; intentos < 6; intentos++) {
    final candidato = File('${directorio.path}/lib/screens/$nombre');
    if (candidato.existsSync()) return candidato;

    final padre = directorio.parent;
    if (padre.path == directorio.path) break;
    directorio = padre;
  }

  fail(
    'No se encontró lib/screens/$nombre subiendo desde '
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
