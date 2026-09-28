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
  // 16 y 14 desde el 2026-09-27: ese día se cablearon los tres paneles huérfanos
  // de M3 (lapsos, espacios y guardias) y se añadió «Mi Perfil». El número es el
  // estado real medido, no una estimación: subirlo es parte del cambio que añade
  // una sección, y bajarlo sin querer es lo que este suelo existe para que no
  // pase inadvertido.
  'admin_dashboard.dart': (items: 16, ramas: 14),
  'docente_dashboard.dart': (items: 5, ramas: 4),
  'aspirante_dashboard.dart': (items: 8, ramas: 8),
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

    testWidgets('una sección apagada explica por qué, y no siempre lo mismo', (
      tester,
    ) async {
      // Una sección gris sin explicación no se distingue de una plataforma
      // incompleta. El mensaje genérico —«pendiente de construir»— además era
      // falso sobre «Calificaciones» del docente: el libro de notas existe y
      // está dentro de cada aula. `pendiente` es el hueco para decirlo.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: IncesTheme.claro(),
          home: AndamiajeApp(
            items: const [
              ItemNavegacion(
                icono: Icons.tune_outlined,
                titulo: 'Sin Motivo',
                categoria: 'General',
                disponible: false,
              ),
              ItemNavegacion(
                icono: Icons.grading_outlined,
                titulo: 'En Otro Sitio',
                categoria: 'General',
                disponible: false,
                pendiente: 'Se hace dentro de cada aula.',
              ),
            ],
            seleccionado: 0,
            onSeleccionar: (_) {},
            rolEtiqueta: 'Docente',
            contenido: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      // Se comparan los mensajes de **todos** los `Tooltip` del árbol y no un
      // `findsOneWidget` por texto: el andamiaje ya pinta tooltips propios —el
      // botón de replegar—, y contarlos sería frágil sin medir nada más.
      expect(
        tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message),
        containsAll(<String>[
          // Sin motivo declarado el mensaje sigue siendo el genérico: el cambio
          // es aditivo y no reescribe el caso que ya existía.
          'Sin Motivo — pendiente de construir',
          // Con motivo, dice dónde está la función en vez de afirmar que falta.
          'Se hace dentro de cada aula.',
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  //  La dirección que faltaba
  // ---------------------------------------------------------------------------
  //
  // El contrato de arriba va del **menú al switch**: si una sección tiene la
  // bandera levantada, tiene que haber una rama. Es la dirección de R-22.
  //
  // Pero hay una segunda forma de quedar inalcanzable que no se parece a R-22 y
  // que la guardia no miraba: **que el panel no esté en el menú en absoluto**.
  // Ahí no hay ítem con el que comparar, la igualdad de conjuntos se cumple con
  // los dos lados sin él, y el panel queda construido, probado y muerto. Pasó
  // tres veces en M3 —lapsos, espacios y guardias— y lo destapó una medición a
  // mano, no una prueba.
  //
  // El criterio es **«alguien lo importa»**, que es lo más fuerte que se puede
  // afirmar leyendo el código fuente sin montarlo. No es lo mismo que «es
  // alcanzable»: un import que nadie usa no llega a la pantalla. Ese caso lo
  // cierra el analizador: `unused_import` es un **aviso** —medido en
  // `analyzer/lib/src/diagnostic/diagnostic.g.dart`, `DiagnosticType
  // .STATIC_WARNING`— y `flutter analyze` falla ante avisos, porque
  // `--fatal-warnings` viene activado por defecto. El flujo **no** pasa
  // `--fatal-infos`, y no le hace falta: lo que hace falta es que sea aviso, y
  // lo es. Entre las dos comprobaciones el hueco queda tapado.
  //
  // Sólo se barre `lib/screens/**`, y es deliberado: en `lib/services/` hay
  // archivos que no importa nadie *a propósito*, porque los elige una
  // exportación condicional (`selector_archivos_navegador.dart` exporta
  // `selector_archivos_io.dart` **o** `selector_archivos_web.dart` según la
  // plataforma). Un contrato global señalaría a esos dos como huérfanos, y
  // sería falso.
  group('ninguna pantalla queda huérfana · la dirección que faltaba', () {
    test('toda pantalla bajo lib/screens se importa desde algún archivo de lib/',
        () {
      final lib = _raizLib();

      final dart = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      // El texto se lee una sola vez por archivo: lo que se comprueba es
      // «¿alguno de los demás lo menciona en un `import` o un `export`?».
      final textos = <String, String>{
        for (final f in dart) f.path: f.readAsStringSync(),
      };

      final pantallas = dart.where((f) => _bajoLibScreens(f.path)).toList();

      // Sin este suelo, una ruta mal escrita dejaría `pantallas` vacía y la
      // prueba daría un verde hueco: exactamente el fallo que este archivo
      // documenta más arriba con el suelo de `_dashboards`.
      expect(
        pantallas.length,
        greaterThan(20),
        reason: 'el barrido no encontró pantallas bajo lib/screens: la ruta '
            'está mal y el verde de abajo no significaría nada',
      );

      final huerfanas = <String>[];

      for (final pantalla in pantallas) {
        final archivo = pantalla.uri.pathSegments.last;
        final patron = RegExp(
          "(?:import|export)\\s+'[^']*${RegExp.escape(archivo)}'",
        );

        final alcanzable = textos.entries.any(
          (e) => e.key != pantalla.path && patron.hasMatch(e.value),
        );

        if (!alcanzable) {
          huerfanas.add(_etiquetaPantalla(pantalla.path));
        }
      }

      expect(
        huerfanas,
        isEmpty,
        reason: 'estas pantallas existen y nadie las importa: están '
            'construidas y son inalcanzables. Es el fallo de R-22 —«probar el '
            'panel donde vive no prueba que se pueda llegar a él»— en su forma '
            'más directa. Cablea el panel en un menú, o bórralo si ya no sirve.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  //  La misma dirección, un nivel más abajo
  // ---------------------------------------------------------------------------
  //
  // La guardia de arriba mira **archivos**: «toda pantalla se importa desde algún
  // sitio». Pero un archivo puede importarse y tener dentro una clase que no
  // construye nadie, y eso no lo ve nadie: `flutter analyze` **no avisa** de una
  // clase pública sin usar —no es un aviso, es API—, así que el código muerto se
  // acumula en silencio. No es hipotético: `_DialogoReincorporar` estuvo en la
  // lista de deudas dando vueltas cuando ya estaba cableado, y al revés, tres
  // paneles de M3 estuvieron construidos y sin cablear.
  //
  // Medido el 2026-09-28: `TarjetaAccesoSeccion`, en `admin_dashboard.dart`,
  // estaba declarada, documentada como «reutilizable cuando el resto de secciones
  // tengan contenido propio» y **no la construía nadie** — ni el código de
  // producción ni una sola prueba. Noventa líneas de interfaz que nadie podía
  // ver. Se borró, y esta comprobación existe para que no vuelva a pasar.
  //
  // La regla **no** es «contar menciones», y el motivo importa: una clase **con**
  // constructor explícito suma dos menciones propias estando muerta —la
  // declaración y el constructor—, mientras que una **sin** constructor suma una
  // sola cuando está muerta y dos cuando se usa una vez. «Dos menciones propias»
  // significa «muerta» en un caso y «viva» en el otro, así que contar no
  // distingue nada. Hay que saber si hay constructor, y se mira en la cabecera de
  // la clase y las tres líneas que la siguen, que es donde va siempre en este
  // código.
  //
  // Se cuenta también una mención en un comentario, y es deliberado: hace la
  // comprobación **más permisiva**, que es la dirección segura. Prefiere dejar
  // pasar una clase muerta antes que poner en rojo una que sí se usa.
  //
  // El algoritmo se validó **por mutación** antes de escribirlo aquí: sobre el
  // árbol de hoy da cero, y sobre `admin_dashboard.dart` tal y como estaba en
  // `f3c7731` —antes de borrar la clase— da exactamente «TarjetaAccesoSeccion».
  // Un guardián que no atrapa el caso que lo motivó no sirve de nada.
  group('ninguna clase queda muerta · la misma dirección, un nivel abajo', () {
    test('toda clase o mixin de lib/screens y lib/widgets se menciona en algún '
        'sitio', () {
      final lib = _raizLib();

      final archivos = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final textos = <String, String>{
        for (final f in archivos) f.path: f.readAsStringSync(),
      };

      // Sólo la superficie de interfaz. Los gateways y servicios de `lib/core` y
      // `lib/services` quedan fuera a propósito: ahí sí hay implementaciones que
      // elige una exportación condicional y que ningún archivo importa por su
      // nombre (`selector_archivos_web.dart` es el caso), y señalarlas sería
      // falso. Es la misma excepción que documenta la guardia de archivos.
      final declarantes =
          archivos.where((f) => _esSuperficieDeInterfaz(f.path)).toList();

      expect(
        declarantes.length,
        greaterThan(20),
        reason: 'el barrido no encontró pantallas ni widgets: la ruta está mal y '
            'el verde de abajo no significaría nada',
      );

      final muertas = <String>[];

      for (final archivo in declarantes) {
        final fuente = textos[archivo.path]!;

        for (final m in _declaracionesDeClase.allMatches(fuente)) {
          final nombre = m.group(1)!;

          if (!_estaMuerta(nombre, m.start, archivo.path, fuente, textos)) {
            continue;
          }

          muertas.add('${_etiquetaPantalla(archivo.path)} → $nombre');
        }
      }

      expect(
        muertas,
        isEmpty,
        reason: 'estas clases existen y no las construye nadie: están muertas. '
            '`flutter analyze` no lo dice —una clase pública sin usar no es un '
            'aviso, es API—, así que sólo se ve midiendo. Cablea la clase donde '
            'corresponde, o bórrala si ya no sirve.',
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

/// Normaliza los separadores para poder comparar rutas en Windows y en Linux.
///
/// `listSync` devuelve `\` en Windows y `/` en Linux.
String _normalizar(String ruta) => ruta.replaceAll('\\', '/');

/// ¿La ruta está bajo `lib/screens/`?
///
/// Se comparan **segmentos** y no una subcadena `'/lib/screens/'`: esa forma
/// depende de que la ruta venga absoluta, y una ruta relativa (`lib/screens/…`)
/// no contiene la barra inicial. El suelo `greaterThan(20)` de la prueba
/// atraparía la lista vacía resultante, pero es mejor que el filtro no dependa
/// de cómo se invocó `flutter test`.
bool _bajoLibScreens(String ruta) {
  final partes = _normalizar(ruta).split('/');
  final i = partes.indexOf('lib');
  return i != -1 && i + 1 < partes.length && partes[i + 1] == 'screens';
}

/// La ruta tal y como se enseña en el mensaje de fallo: desde `screens/`.
String _etiquetaPantalla(String ruta) {
  final partes = _normalizar(ruta).split('/');
  final i = partes.indexOf('screens');
  return i == -1 ? _normalizar(ruta) : partes.sublist(i).join('/');
}

/// Localiza `lib/` subiendo por los directorios padres, igual que [_fuente].
///
/// `flutter test` corre desde la raíz del paquete, pero asumirlo convertiría un
/// cambio de invocación en un «directorio no encontrado» que no explica nada.
Directory _raizLib() {
  var directorio = Directory.current;

  for (var intentos = 0; intentos < 6; intentos++) {
    final candidato = Directory('${directorio.path}/lib');
    if (candidato.existsSync()) return candidato;

    final padre = directorio.parent;
    if (padre.path == directorio.path) break;
    directorio = padre;
  }

  fail('No se encontró lib/ subiendo desde ${Directory.current.path}');
}

// -----------------------------------------------------------------------------
//  Clases muertas
// -----------------------------------------------------------------------------

/// Las declaraciones de clase y de mixin de un archivo, con su nombre.
///
/// Cubre las cinco formas que Dart permite además de `class` —`abstract`,
/// `sealed`, `base`, `final`, `interface`— y `mixin`, aunque hoy en
/// `lib/screens` y `lib/widgets` sólo haya `class`: el día que alguien escriba
/// `sealed class`, una comprobación que no lo mirara dejaría de cubrir esa clase
/// sin avisar.
final RegExp _declaracionesDeClase = RegExp(
  r'^(?:abstract |sealed |base |final |interface )?'
  r'(?:class|mixin)\s+([A-Z][A-Za-z0-9_]*)',
  multiLine: true,
);

/// ¿La ruta está bajo `lib/screens/` o `lib/widgets/`?
///
/// Se comparan **segmentos** y no una subcadena, por lo mismo que en
/// [_bajoLibScreens]: una ruta relativa no contiene la barra inicial.
bool _esSuperficieDeInterfaz(String ruta) {
  final partes = _normalizar(ruta).split('/');
  final i = partes.indexOf('lib');
  if (i == -1 || i + 1 >= partes.length) return false;
  return partes[i + 1] == 'screens' || partes[i + 1] == 'widgets';
}

/// ¿[nombre] está declarada y no la construye nadie?
///
/// La regla, y por qué no basta con contar menciones, está explicada en el
/// comentario del grupo que usa esto. En una línea: una mención en **otro**
/// archivo basta para estar viva; dentro del suyo, se descuentan la declaración y
/// el constructor cuando lo hay, y si no sobra ninguna mención, está muerta.
bool _estaMuerta(
  String nombre,
  int inicioDeclaracion,
  String archivoQueDeclara,
  String fuenteQueDeclara,
  Map<String, String> textos,
) {
  final patron = RegExp('\\b${RegExp.escape(nombre)}\\b');

  for (final entrada in textos.entries) {
    if (entrada.key != archivoQueDeclara && patron.hasMatch(entrada.value)) {
      return false;
    }
  }

  // Línea (0-based) donde está la declaración, contando saltos de línea.
  final lineaCabecera =
      '\n'.allMatches(fuenteQueDeclara.substring(0, inicioDeclaracion)).length;

  final lineas = fuenteQueDeclara.split('\n');
  final fin = lineaCabecera + 4 > lineas.length
      ? lineas.length
      : lineaCabecera + 4;

  // El constructor va justo debajo del `{` de la cabecera en todo este código,
  // así que mirar cuatro líneas es holgado y no depende del formato del resto.
  final ventana = lineas.sublist(lineaCabecera, fin).join('\n');

  final tieneConstructor = RegExp(
    '^\\s*(?:const\\s+)?${RegExp.escape(nombre)}\\s*\\(',
    multiLine: true,
  ).hasMatch(ventana);

  // 1 por la declaración, y 1 más por el constructor cuando lo hay. Si no sobra
  // ninguna mención propia, no la construye nadie.
  final esperadas = 1 + (tieneConstructor ? 1 : 0);

  return patron.allMatches(fuenteQueDeclara).length <= esperadas;
}
