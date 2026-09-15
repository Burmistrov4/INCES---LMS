import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/reglas_cuadrante.dart';
import 'package:inces_lms_app/models/cuadrante.dart';
import 'package:inces_lms_app/repositories/cuadrante_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_guardias_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_cuadrante_gateway.dart';

/// Pruebas del panel de guardias docentes.
///
/// Se monta **dentro de `ContenidoSeccion`**, que es donde vive de verdad: el
/// contenedor le entrega una altura acotada y un panel que reparte con `Expanded`
/// revienta si la recibe infinita. Montarlo en un `Scaffold` pelado escondería
/// justo ese fallo.
void main() {
  late FakeCuadranteGateway gateway;
  late CuadranteRepository repo;

  setUp(() {
    gateway = FakeCuadranteGateway();
    repo = CuadranteRepository(gateway: gateway);
  });

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
            migas: const ['Inicio', 'Guardias docentes'],
            child: panel,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tester.takeException();
  }

  /// Un lapso vigente y un catálogo mínimo con los que la rejilla responde.
  void sembrarCatalogo({
    String lapso = '2026-1',
    List<DocenteResumen>? docentes,
    List<Aula>? aulas,
  }) {
    gateway.periodos = [
      Periodo(id: 'p1', codigo: lapso, activo: true, vigente: true),
    ];
    gateway.rejillaDevuelta = RejillaCuadrante(
      periodo: lapso,
      aulas: aulas ??
          const [
            Aula(
              id: 'a1',
              nombre: 'Taller de Soldadura Cabina A',
              capacidad: 12,
              esTaller: true,
              activa: true,
            ),
          ],
      docentes: docentes ?? const [DocenteResumen(id: 'd1', nombre: 'Luis Márquez')],
    );
  }

  group('panel de guardias', () {
    testWidgets('la lista se pinta sin romper el layout', (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          docenteId: 'd1',
          aulaId: 'a1',
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          turno: Turno.manana,
          activa: true,
        ),
      ];
      gateway.totalGuardias = 1;

      final excepcion = await montar(
        tester,
        CpanelGuardiasPanel(repositorio: repo),
      );

      expect(excepcion, isNull, reason: 'el layout no debe reventar');
      expect(find.text('Luis Márquez'), findsOneWidget);
      expect(find.text('Taller de Soldadura Cabina A'), findsOneWidget);
      expect(find.text('Lunes · Bloque 1'), findsOneWidget);
      expect(find.text('Mañana'), findsOneWidget);
    });

    testWidgets('un docente desactivado no se deja como hueco mudo (R-23)',
        (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          // Id que la rejilla ya no devuelve: el docente se desactivó después de
          // asignar la guardia.
          docenteId: 'd-zombie',
          aulaId: 'a1',
          periodo: '2026-1',
          dia: 2,
          bloque: 4,
          turno: Turno.manana,
          activa: true,
        ),
      ];
      gateway.totalGuardias = 1;

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      // Huérfano, pero nombrado: se distingue de «sin nombre» (R-21), que es
      // otra cosa.
      expect(find.text('Docente no disponible'), findsOneWidget);
    });

    testWidgets('un espacio fuera del catálogo se dice, no se inventa',
        (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          docenteId: 'd1',
          aulaId: 'a-fantasma',
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          turno: Turno.manana,
          activa: true,
        ),
      ];
      gateway.totalGuardias = 1;

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      expect(find.text('Espacio no disponible'), findsOneWidget);
    });

    testWidgets('archivar manda activa:false y no borra', (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          docenteId: 'd1',
          aulaId: 'a1',
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          turno: Turno.manana,
          activa: true,
        ),
      ];
      gateway.totalGuardias = 1;

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      await tester.tap(find.byTooltip('Archivar'));
      await tester.pump();
      await tester.pump();

      // Archivar es desactivar: un `DELETE` se llevaría por delante las clases y
      // el cuadrante que apuntan a la guardia.
      expect(gateway.ultimosCambiosGuardia!.toJson(), {'activa': false});
    });

    testWidgets('la insignia «Archivada» acompaña a las guardias inactivas',
        (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          docenteId: 'd1',
          aulaId: 'a1',
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          turno: Turno.manana,
          activa: false,
        ),
      ];
      gateway.totalGuardias = 1;

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      expect(find.text('Archivada'), findsOneWidget);
    });

    testWidgets('reactivar choca y el panel lo dice con su propio mensaje',
        (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          docenteId: 'd1',
          aulaId: 'a1',
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          turno: Turno.manana,
          activa: false,
        ),
      ];
      gateway.totalGuardias = 1;
      gateway.errorAlActualizarGuardia = const AppException(
        type: AppErrorType.validacion,
        message: 'mensaje genérico de 409',
        code: codigoChoqueDeAgenda,
      );

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      await tester.tap(find.byTooltip('Reactivar'));
      await tester.pumpAndSettle();

      // El choque merece su mensaje: el `409` del backend no dice cuál de los
      // dos —docente o espacio— ya está ocupado.
      expect(find.textContaining('ya están ocupados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la paginación aparece cuando hay más de una página',
        (tester) async {
      sembrarCatalogo();
      gateway.guardias = const [
        Guardia(
          id: 'g1',
          docenteId: 'd1',
          aulaId: 'a1',
          periodo: '2026-1',
          dia: 1,
          bloque: 1,
          turno: Turno.manana,
          activa: true,
        ),
      ];
      gateway.totalGuardias = 60;

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      expect(find.text('Siguientes'), findsOneWidget);
    });

    testWidgets('sin lapsos registrados el vacío explica por qué', (tester) async {
      // Catálogo vacío: el panel no puede elegir ni siquiera un lapso vigente.
      gateway.periodos = const [];
      gateway.rejillaDevuelta = const RejillaCuadrante();

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      expect(
        find.text('Todavía no hay lapsos registrados'),
        findsOneWidget,
      );
      // El botón no se esconde: se muestra deshabilitado con un tooltip que
      // explica por qué, para no parecer un fallo de permisos.
      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Asignar guardia'),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('sin lapso vigente no se inventa uno', (tester) async {
      // Hay lapsos, pero ninguno vigente.
      gateway.periodos = const [
        Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: false),
      ];
      gateway.rejillaDevuelta = const RejillaCuadrante();

      await montar(tester, CpanelGuardiasPanel(repositorio: repo));

      expect(find.text('No hay ningún lapso vigente'), findsOneWidget);
      expect(
        find.textContaining('no la toma por ti'),
        findsOneWidget,
      );
    });
  });
}
