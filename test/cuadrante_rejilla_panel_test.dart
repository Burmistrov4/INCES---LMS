import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/cuadrante.dart';
import 'package:inces_lms_app/repositories/cuadrante_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_cuadrante_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_cuadrante_gateway.dart';

/// Pruebas del panel de la rejilla del cuadrante.
///
/// Se monta **dentro de `ContenidoSeccion`**, que es donde vive de verdad: el
/// contenedor le entrega una altura acotada y la rejilla (en dos
/// `SingleChildScrollView`) necesita precisamente eso para no reventar el layout.
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
            migas: const ['Inicio', 'Cuadrante y Horarios'],
            child: panel,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tester.takeException();
  }

  /// Un lapso vigente, un aula, un docente y una clase ya colocada.
  void sembrarCuadrante({
    bool vigente = true,
    List<ClaseCuadrante> clases = const [],
    List<Guardia> guardias = const [],
  }) {
    gateway.periodos = [
      Periodo(id: 'p1', codigo: 'SA26-2', activo: true, vigente: vigente),
    ];
    gateway.rejillaDevuelta = RejillaCuadrante(
      periodo: 'SA26-2',
      aulas: const [
        Aula(
          id: 'a1',
          nombre: 'Taller A',
          capacidad: 12,
          esTaller: true,
          activa: true,
        ),
      ],
      docentes: const [DocenteResumen(id: 'd1', nombre: 'Luis Márquez')],
      clases: clases,
      guardias: guardias,
    );
  }

  ClaseCuadrante claseEn(int dia, int bloque) => ClaseCuadrante(
        id: 'c1',
        seccionId: 's1',
        docenteId: 'd1',
        aulaId: 'a1',
        dia: dia,
        bloque: bloque,
        turno: Turno.manana,
        activa: true,
        periodo: 'SA26-2',
        programaId: 'prog1',
        programa: 'Soldadura',
        materiaId: 'm1',
        materia: 'Soldadura por Arco',
        seccion: 'SC-01',
        aula: 'Taller A',
        docente: 'Luis Márquez',
      );

  group('panel de la rejilla', () {
    testWidgets('la rejilla se pinta sin romper el layout', (tester) async {
      sembrarCuadrante(clases: [claseEn(1, 1)]);

      final excepcion = await montar(
        tester,
        CpanelCuadrantePanel(repositorio: repo),
      );

      expect(excepcion, isNull, reason: 'el layout no debe reventar');
      // Cabecera de día y la clase colocada en su celda.
      expect(find.text('Lunes'), findsWidgets);
      expect(find.text('Soldadura por Arco'), findsOneWidget);
      expect(find.text('Taller A · Luis Márquez'), findsOneWidget);
    });

    testWidgets('una guardia aparece como chip de sólo lectura', (tester) async {
      sembrarCuadrante(
        guardias: const [
          Guardia(
            id: 'g1',
            docenteId: 'd1',
            aulaId: 'a1',
            periodo: 'SA26-2',
            dia: 2,
            bloque: 1,
            turno: Turno.manana,
            activa: true,
          ),
        ],
      );

      await montar(tester, CpanelCuadrantePanel(repositorio: repo));

      expect(find.text('Guardia'), findsOneWidget);
      expect(find.text('Taller A'), findsWidgets);
    });

    testWidgets('sin lapsos registrados el vacío lo explica', (tester) async {
      gateway.periodos = const [];
      gateway.rejillaDevuelta = const RejillaCuadrante();

      await montar(tester, CpanelCuadrantePanel(repositorio: repo));

      expect(
        find.text('Todavía no hay lapsos registrados'),
        findsOneWidget,
      );
    });

    testWidgets('sin aulas registradas el cuadrante no se puede armar',
        (tester) async {
      gateway.periodos = const [
        Periodo(id: 'p1', codigo: 'SA26-2', activo: true, vigente: true),
      ];
      gateway.rejillaDevuelta = const RejillaCuadrante(
        periodo: 'SA26-2',
        aulas: [],
        docentes: [DocenteResumen(id: 'd1', nombre: 'Luis Márquez')],
      );

      await montar(tester, CpanelCuadrantePanel(repositorio: repo));

      expect(find.text('No hay espacios registrados'), findsOneWidget);
    });

    testWidgets('un lapso sin marcar como vigente lo avisa, pero pinta',
        (tester) async {
      sembrarCuadrante(vigente: false, clases: [claseEn(1, 1)]);

      await montar(tester, CpanelCuadrantePanel(repositorio: repo));

      expect(
        find.textContaining('Ningún lapso está marcado como vigente'),
        findsOneWidget,
      );
      expect(find.text('Soldadura por Arco'), findsOneWidget);
    });

    testWidgets('lapso recién creado sin clases invita a asignar la primera',
        (tester) async {
      sembrarCuadrante(); // aulas + docentes, pero cero clases

      await montar(tester, CpanelCuadrantePanel(repositorio: repo));

      expect(
        find.text('Este lapso aún no tiene clases ni guardias'),
        findsOneWidget,
      );
      // Sin secciones disponibles no se puede crear: el botón queda deshabilitado.
      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Asignar clase'),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('tocar una clase abre su edición', (tester) async {
      sembrarCuadrante(clases: [claseEn(1, 1)]);

      await montar(tester, CpanelCuadrantePanel(repositorio: repo));

      await tester.tap(find.text('Soldadura por Arco'));
      await tester.pumpAndSettle();

      expect(find.text('Editar clase'), findsOneWidget);
      // Cierra el diálogo para no dejarlo abierto.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });
}
