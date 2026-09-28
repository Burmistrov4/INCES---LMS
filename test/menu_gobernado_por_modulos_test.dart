import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';
import 'package:inces_lms_app/screens/docente_dashboard.dart';
import 'package:inces_lms_app/screens/mis_aulas_panel.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';
import 'package:inces_lms_app/widgets/modulos_del_menu.dart';

import 'support/fake_aula_gateway.dart';
import 'support/fake_gateway.dart';

/// El menú gobernado por `system_modules`.
///
/// ## El fallo que estas pruebas cierran
///
/// Los tres dashboards declaraban `disponible:` a mano y **nadie leía**
/// `system_modules`. Medido: apagar `m6_aula_virtual` desde el cPanel dejaba
/// «Mis aulas» encendida en el menú del docente y del aprendiz, y el clic
/// devolvía **403** — el menú prometía una pantalla que el backend rechazaba.
///
/// ## Las dos mitades, y por qué están separadas
///
///  1. **La regla** —`aplicarEstadoDeModulos`— probada como función pura. Aquí
///     viven las decisiones que importan: qué se apaga, qué no, y qué pasa con
///     un módulo **desconocido**.
///  2. **El cableado** — que los dashboards la llamen de verdad. Una regla
///     perfecta que nadie invoca no arregla nada, y es exactamente el error que
///     este proyecto ya cometió con los tres paneles huérfanos de M3.
///
/// Sin la mitad 2, borrar la llamada a `menuConModulos` dejaría todo en verde.
const String _motivoAulaApagada =
    'El módulo «Aula Virtual» está apagado. Actívalo en el cPanel, en Módulos '
    'del Sistema.';

/// Un módulo de `system_modules` con lo mínimo que lee el menú.
SystemModule _modulo(String clave, String nombre, {bool habilitado = true}) =>
    SystemModule(clave: clave, nombre: nombre, habilitado: habilitado);

/// El estado de módulos doblado, para que la prueba no toque Supabase.
///
/// `AuthService` y `ModuloRepository` caen a `SupabaseService.instance` cuando no
/// se les inyecta nada, y en una prueba de widget `Supabase.instance` no está
/// inicializado. Se doblan los dos por la misma razón: lo que se mide aquí es el
/// cableado del menú, no el azar de una lectura de red.
ModuloRepository _repoCon(List<SystemModule> modulos) =>
    ModuloRepository(gateway: FakeGateway()..listaModulos = modulos);

/// Monta el dashboard del docente.
///
/// Se usa el del **docente** porque su índice 0 ya es «Mis aulas»: el panel se
/// monta sin navegar, así que la sección gobernada por `m6_aula_virtual` es la
/// que se está mirando.
///
/// El listado de aulas se dobla **siempre**. Sin él, `PanelMisAulas` recibiría el
/// `BackendAulaGateway` real y saldría a la red en el primer `pump` —antes de que
/// el estado de los módulos llegue—, y la prueba mediría un fallo de red en vez
/// del menú.
Future<void> _montarDocente(
  WidgetTester tester, {
  required ModuloRepository modulos,
}) async {
  // Ancha y alta: por debajo de 900 px el menú pasa a cajón y no se pinta en el
  // árbol, y por debajo de 1280 arranca replegado, donde no se ven las etiquetas.
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: DocenteDashboardScreen(
        auth: AuthService(gateway: FakeGateway()),
        modulos: modulos,
        aulasPropias: FakeAulaGateway()..misAulasResultado = misAulasEjemplo(),
      ),
    ),
  );

  // **Sin `pumpAndSettle`**: mientras carga hay animaciones que no terminan.
  // Dos `pump` bastan: el primero resuelve la lectura de módulos —el doble es
  // `async` pero inmediato— y el segundo reconstruye con el `setState`.
  await tester.pump();
  await tester.pump();
}

/// Los mensajes de **todos** los `Tooltip` del árbol.
///
/// Se leen así y no con un `findsOneWidget` por texto porque el andamiaje ya
/// pinta tooltips propios —el botón de replegar— y contarlos sería frágil sin
/// medir nada más. Es el mismo criterio que `menu_alcanzable_test.dart`.
List<String?> _mensajesDeTooltip(WidgetTester tester) => tester
    .widgetList<Tooltip>(find.byType(Tooltip))
    .map((t) => t.message)
    .toList();

void main() {
  group('aplicarEstadoDeModulos · la regla', () {
    const conModulo = ItemNavegacion(
      icono: Icons.dashboard_outlined,
      titulo: 'Con módulo',
      categoria: 'General',
      modulo: 'm6_aula_virtual',
    );

    test('apaga la sección cuyo módulo está apagado y nombra el módulo', () {
      final resultado = aplicarEstadoDeModulos(
        const [conModulo],
        apagadas: {'m6_aula_virtual'},
        nombres: {'m6_aula_virtual': 'Aula Virtual'},
      );

      expect(resultado.single.disponible, isFalse);
      expect(resultado.single.pendiente, _motivoAulaApagada);
      // El título y la categoría no se tocan: lo único que cambia es si se
      // puede entrar, y el ítem tiene que seguir ocupando su sitio en el menú.
      expect(resultado.single.titulo, 'Con módulo');
      expect(resultado.single.categoria, 'General');
    });

    test('deja intacta la sección cuyo módulo está encendido', () {
      final resultado = aplicarEstadoDeModulos(
        const [conModulo],
        apagadas: {'m5_archivos'},
        nombres: {'m5_archivos': 'Almacenamiento de Archivos'},
      );

      expect(resultado.single.disponible, isTrue);
      expect(resultado.single.pendiente, isNull);
    });

    test('no toca la sección sin módulo', () {
      // El perfil propio y la ficha del aspirante no dependen de ningún
      // interruptor: apagar «todo lo demás» no puede apagarlos.
      const sinModulo = ItemNavegacion(
        icono: Icons.account_circle_outlined,
        titulo: 'Mi Perfil',
        categoria: 'Mi cuenta',
      );

      final resultado = aplicarEstadoDeModulos(
        const [sinModulo],
        apagadas: {'m0_cpanel', 'm1_onboarding', 'm6_aula_virtual'},
      );

      expect(resultado.single.disponible, isTrue);
    });

    test('un módulo desconocido no apaga nada', () {
      // La regla que hace que la lectura pueda fallar sin romper la aplicación.
      // `apagadas` trae una clave que no es la del ítem, así que el ítem sigue
      // disponible: es el mismo camino que un `system_modules` que no se pudo
      // leer.
      final resultado = aplicarEstadoDeModulos(
        const [conModulo],
        apagadas: {'m_modulo_que_no_existe'},
      );

      expect(resultado.single.disponible, isTrue);
    });

    test('sin nada apagado devuelve la misma lista, sin copiarla', () {
      // Es el caso «no se pudo leer» y el caso «todo encendido», y los dos
      // tienen que costar cero: ni copia ni reconstrucción del menú.
      const items = [conModulo];
      final resultado = aplicarEstadoDeModulos(items, apagadas: const {});

      expect(identical(resultado, items), isTrue);
    });

    test('el motivo del módulo pisa la nota estática de la sección', () {
      // Una sección puede traer su propio `pendiente` («Calificaciones» del
      // docente lo trae). Si además su módulo se apaga, manda la causa **viva**:
      // decir «se califica dentro de cada aula» cuando el administrador apagó el
      // módulo entero sería cierto y a la vez inútil.
      const conNota = ItemNavegacion(
        icono: Icons.grading_outlined,
        titulo: 'Con nota',
        categoria: 'General',
        disponible: false,
        pendiente: 'Se hace dentro de cada aula.',
        modulo: 'm7_calificaciones',
      );

      final resultado = aplicarEstadoDeModulos(
        const [conNota],
        apagadas: {'m7_calificaciones'},
        nombres: {'m7_calificaciones': 'Calificaciones'},
      );

      expect(
        resultado.single.pendiente,
        'El módulo «Calificaciones» está apagado. Actívalo en el cPanel, en '
        'Módulos del Sistema.',
      );
    });

    test('sin nombre conocido cae a la clave, no a un hueco', () {
      // No debería pasar —los nombres salen de las mismas filas que las
      // claves—, pero un motivo que dijera «El módulo «null» está apagado» sería
      // peor que decir la clave.
      final resultado = aplicarEstadoDeModulos(
        const [conModulo],
        apagadas: {'m6_aula_virtual'},
      );

      expect(resultado.single.pendiente, contains('m6_aula_virtual'));
      expect(resultado.single.pendiente, isNot(contains('null')));
    });
  });

  group('el menú del docente · el cableado', () {
    testWidgets('con el módulo encendido, «Mis aulas» abre su panel',
        (tester) async {
      // El caso de hoy: `m6_aula_virtual` está encendido en la nube (medido), así
      // que el menú tiene que dejar entrar. Es el control de la prueba de abajo:
      // sin esto, un `menuConModulos` que apagara todo daría verde.
      await _montarDocente(
        tester,
        modulos: _repoCon([_modulo('m6_aula_virtual', 'Aula Virtual')]),
      );

      expect(find.byType(PanelMisAulas), findsOneWidget);
      expect(_mensajesDeTooltip(tester), isNot(contains(_motivoAulaApagada)));
    });

    testWidgets('con el módulo apagado, «Mis aulas» no abre y explica por qué',
        (tester) async {
      await _montarDocente(
        tester,
        modulos: _repoCon([
          _modulo('m6_aula_virtual', 'Aula Virtual', habilitado: false),
        ]),
      );

      // El panel no se monta: no es que se vea vacío, es que no se entra. Sin
      // esta aserción la prueba pasaría aunque el `switch` siguiera pintando el
      // aula de un módulo apagado.
      expect(
        find.byType(PanelMisAulas),
        findsNothing,
        reason: 'un módulo apagado no puede seguir pintando su panel',
      );

      // Y lo dice con el nombre del módulo, que es lo que convierte un gris en
      // algo accionable. El texto sale de `motivoDeModuloApagado`, así que
      // encontrarlo prueba que el dashboard llamó a `menuConModulos`.
      expect(find.text(_motivoAulaApagada), findsOneWidget);
      expect(_mensajesDeTooltip(tester), contains(_motivoAulaApagada));
    });

    testWidgets('si la lectura de módulos falla, el menú se queda abierto',
        (tester) async {
      // Fail-open, y es una decisión: un corte de red no puede dejar la
      // aplicación sin secciones. El backend sigue siendo el que autoriza, así
      // que enseñar de más acaba en un 403 explicado y no en un menú vacío.
      await _montarDocente(
        tester,
        modulos: ModuloRepository(
          gateway: FakeGateway()..errorAlListarModulos = Exception('sin red'),
        ),
      );

      expect(find.byType(PanelMisAulas), findsOneWidget);
      expect(_mensajesDeTooltip(tester), isNot(contains(_motivoAulaApagada)));
    });
  });
}
