import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/aspirante_model.dart';
import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/repositories/aspirante_repository.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';
import 'package:inces_lms_app/repositories/planilla_repository.dart';
import 'package:inces_lms_app/screens/aspirante_dashboard.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/services/planilla_pdf_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_gateway.dart';
import 'support/fake_planilla_gateway.dart';
import 'support/fake_selector_archivos.dart';

class _FakePlanillaServiceControlable extends PlanillaPdfService {
  _FakePlanillaServiceControlable({
    required this.alDescargar,
  });

  final Future<ResultadoDescargaPlanilla> Function() alDescargar;
  int llamadas = 0;

  @override
  Future<ResultadoDescargaPlanilla> descargarPlanillaPropia() async {
    llamadas++;
    return await alDescargar();
  }
}

void main() {
  const claveBoton = ValueKey('descargar-planilla-oficial');

  final aspiranteEjemplo = AspiranteModel(
    id: 'asp-1',
    nombres: 'Lorenzo',
    apellidos: 'Roca',
    cedula: 'V-20123456',
    email: 'lorenzo@example.com',
    telefono: '04141234567',
    direccion: 'Valencia',
    sexo: 'M',
    nivelEducativo: 'Universitario',
    programaNombre: 'Soldadura Básica',
  );

  Widget crearApp({
    required AspiranteModel? ficha,
    required PlanillaPdfService planillaService,
    FakeGateway? gateway,
  }) {
    final fake = gateway ?? FakeGateway()
      ..ficha = ficha
      ..listaModulos = [
        const SystemModule(
          clave: 'm4_inscripciones',
          nombre: 'Inscripciones',
          habilitado: true,
          rolesPermitidos: ['estudiante', 'admin'],
        ),
      ];

    return MaterialApp(
      theme: IncesTheme.claro(),
      home: Scaffold(
        body: AspiranteDashboardScreen(
          repositorio: AspiranteRepository(gateway: fake),
          modulos: ModuloRepository(gateway: fake),
          auth: AuthService(gateway: fake),
          planillaService: planillaService,
        ),
      ),
    );
  }

  Future<void> limpiarSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('AspiranteDashboard · Botón de descarga de planilla oficial', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(1280, 2400);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
    testWidgets('1. El botón de descarga aparece cuando hay ficha en Mi inscripción', (tester) async {
      final fakePlanilla = FakePlanillaGateway()..pdfDevuelto = [37, 80, 68, 70];
      final fakeSelector = FakeSelectorDeArchivos();
      final servicio = PlanillaPdfService(
        repositorio: PlanillaRepository(gateway: fakePlanilla),
        selector: fakeSelector,
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      expect(find.byKey(claveBoton), findsOneWidget);
      expect(find.text('Descargar planilla oficial (PDF)'), findsOneWidget);
      expect(find.text('PLANILLA OFICIAL DE INSCRIPCIÓN'), findsOneWidget);
    });

    testWidgets('2. Al pulsarlo invoca el servicio y entrega el PDF con aviso de éxito', (tester) async {
      final completer = Completer<ResultadoDescargaPlanilla>();
      final servicio = _FakePlanillaServiceControlable(
        alDescargar: () => completer.future,
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(claveBoton));
      await tester.pump(); // Inicia carga

      expect(find.text('Generando PDF…'), findsOneWidget);

      completer.complete(const PlanillaDescargada(nombreArchivo: 'planilla-oficial.pdf'));
      await tester.pumpAndSettle(); // Finaliza descarga y animación

      expect(servicio.llamadas, 1);
      expect(
        find.textContaining('Tu planilla oficial se descargó'),
        findsOneWidget,
      );

      await limpiarSnackBars(tester);
    });

    testWidgets('3. Previene solicitudes concurrentes mientras está descargando', (tester) async {
      final completer = Completer<ResultadoDescargaPlanilla>();
      final servicio = _FakePlanillaServiceControlable(
        alDescargar: () => completer.future,
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(claveBoton));
      await tester.pump();

      expect(servicio.llamadas, 1);
      expect(find.text('Generando PDF…'), findsOneWidget);

      // Segundo tap mientras la solicitud sigue pendiente
      await tester.tap(find.byKey(claveBoton), warnIfMissed: false);
      await tester.pump();

      // No debe haber aumentado las llamadas
      expect(servicio.llamadas, 1);

      // Desbloquear
      completer.complete(const PlanillaDescargada(nombreArchivo: 'planilla.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('Descargar planilla oficial (PDF)'), findsOneWidget);
      await limpiarSnackBars(tester);
    });

    testWidgets('4. Ausencia de ficha (SinFichaDeAspirante) muestra aviso útil sin error no controlado', (tester) async {
      final servicio = _FakePlanillaServiceControlable(
        alDescargar: () async => const SinFichaDeAspirante(),
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(claveBoton));
      await tester.pumpAndSettle();

      expect(
        find.text('No encontramos una ficha de inscripción para generar la planilla.'),
        findsOneWidget,
      );
      expect(find.text('Descargar planilla oficial (PDF)'), findsOneWidget);

      await limpiarSnackBars(tester);
    });

    testWidgets('5. Fallo de consulta (ConsultaFallida) comunica el mensaje de error', (tester) async {
      final servicio = _FakePlanillaServiceControlable(
        alDescargar: () async => const ConsultaFallida('Servicio no disponible momentáneamente'),
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(claveBoton));
      await tester.pumpAndSettle();

      expect(find.text('Servicio no disponible momentáneamente'), findsOneWidget);
      expect(find.text('Descargar planilla oficial (PDF)'), findsOneWidget);

      await limpiarSnackBars(tester);
    });

    testWidgets('6. Fallo de entrega en navegador (DescargaFallida) informa al usuario', (tester) async {
      final servicio = _FakePlanillaServiceControlable(
        alDescargar: () async => const DescargaFallida(),
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(claveBoton));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos entregar el PDF al navegador. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Descargar planilla oficial (PDF)'), findsOneWidget);

      await limpiarSnackBars(tester);
    });

    testWidgets('7. Si el widget se desmonta durante la descarga no lanza excepción de setState', (tester) async {
      final completer = Completer<ResultadoDescargaPlanilla>();
      final servicio = _FakePlanillaServiceControlable(
        alDescargar: () => completer.future,
      );

      await tester.pumpWidget(crearApp(ficha: aspiranteEjemplo, planillaService: servicio));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(claveBoton));
      await tester.pump();

      // Desmontar el árbol mientras la operación está en vuelo
      await tester.pumpWidget(const SizedBox());

      // Completar la operación asíncrona fuera del árbol montado
      completer.complete(const PlanillaDescargada(nombreArchivo: 'planilla.pdf'));
      await tester.pump();

      // No debe lanzar excepciones no controladas
      expect(tester.takeException(), isNull);
    });
  });
}
