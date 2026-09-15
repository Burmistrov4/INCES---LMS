import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/cuadrante.dart';
import 'package:inces_lms_app/repositories/cuadrante_repository.dart';
import 'package:inces_lms_app/screens/mi_horario_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_cuadrante_gateway.dart';

/// Pruebas del panel «Mi horario» (docente / estudiante).
///
/// Se monta **dentro de `ContenidoSeccion`**, como vive de verdad.
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
            migas: const ['Inicio', 'Mi horario'],
            child: panel,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tester.takeException();
  }

  ClaseCuadrante claseEn(int dia, int bloque, {String aula = 'Taller A'}) =>
      ClaseCuadrante(
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
        aula: aula,
        docente: 'Luis Márquez',
      );

  group('panel mi horario', () {
    testWidgets('pinta las clases del llamante en la rejilla', (tester) async {
      gateway.miHorarioDevuelto = MiHorario(
        rol: 'docente',
        periodo: 'SA26-2',
        clases: [claseEn(1, 1)],
      );

      final excepcion = await montar(tester, MiHorarioPanel(repositorio: repo));

      expect(excepcion, isNull, reason: 'el layout no debe reventar');
      expect(find.text('Soldadura por Arco'), findsOneWidget);
      expect(find.text('Taller A · SC-01'), findsOneWidget);
    });

    testWidgets('un docente ve también sus guardias', (tester) async {
      gateway.miHorarioDevuelto = MiHorario(
        rol: 'docente',
        periodo: 'SA26-2',
        clases: [claseEn(1, 1)],
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

      await montar(tester, MiHorarioPanel(repositorio: repo));

      expect(find.text('Guardia'), findsOneWidget);
    });

    testWidgets('sin clases asignadas el vacío lo dice', (tester) async {
      gateway.miHorarioDevuelto = const MiHorario(
        rol: 'docente',
        periodo: 'SA26-2',
      );

      await montar(tester, MiHorarioPanel(repositorio: repo));

      expect(
        find.text('No tienes clases asignadas en este lapso'),
        findsOneWidget,
      );
    });

    testWidgets('un perfil sin rol explica qué falta (PERFIL_SIN_ROL)',
        (tester) async {
      gateway.errorAlMiHorario = const AppException.validacion(
        'Sin rol',
        code: 'PERFIL_SIN_ROL',
      );

      await montar(tester, MiHorarioPanel(repositorio: repo));

      expect(
        find.text('Tu perfil aún no tiene un rol asignado'),
        findsOneWidget,
      );
    });
  });
}
