import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/aula_gateway.dart';
import 'package:inces_lms_app/repositories/archivos_repository.dart';
import 'package:inces_lms_app/screens/aula_virtual_dashboard.dart';
import 'package:inces_lms_app/screens/gestor_documental_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_archivos_gateway.dart';
import 'support/fake_aula_gateway.dart';
import 'support/fake_selector_archivos.dart';

/// Pruebas del Aula Virtual (M6).
///
/// Cubren lo que la capa de datos no puede cubrir: **que la pantalla pida lo
/// correcto, pinte lo que recibe en el orden que llega, y que el gestor
/// documental del estudiante quede atado a la entrega correcta** — el `entidadId`
/// que M6 introduce y que M5 no podía expresar.
///
/// La pantalla trae su propio `ContenidoSeccion`, así que se monta en el `body`
/// de un `Scaffold`, igual que la montan los dashboards en producción. Montarla
/// dentro de otro `ContenidoSeccion` sería montarla en un contenedor que no
/// existe.
Future<void> montar(
  WidgetTester tester, {
  required FakeAulaGateway gateway,
  bool esDocente = false,
  FakeArchivosGateway? archivos,
}) async {
  // Ventana alta: la pestaña de trabajo de clase es un `ListView` y con la
  // ventana por defecto (800×600) las tarjetas quedarían fuera del viewport y
  // `find.text` no las encontraría. No es que falte el dato: es que no se pintó.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: Scaffold(
        body: AulaVirtualDashboardScreen(
          seccionId: 'sec-1',
          seccionNombre: 'Soldadura SA26-2',
          gateway: gateway,
          esDocente: esDocente,
          archivosRepositorio:
              archivos == null ? null : ArchivosRepository(gateway: archivos),
          selectorArchivos: FakeSelectorDeArchivos(),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Avanza la interfaz lo justo para que terminen las cargas.
///
/// **No usa `pumpAndSettle` a propósito.** Mientras carga, la pantalla pinta un
/// `CircularProgressIndicator`, que anima indefinidamente: `pumpAndSettle` no
/// terminaría y agotaría su tiempo límite. Sería un fallo de la prueba, no del
/// código.
Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// Cambia de pestaña y espera a que termine la animación.
///
/// Aquí sí vale `pumpAndSettle`: cuando la pantalla ya cargó no hay ningún
/// indicador girando, sólo la transición del `TabBarView`.
Future<void> cambiarPestana(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.text(etiqueta));
  await tester.pumpAndSettle();
}

/// Deja que los avisos temporales caduquen y se marchen.
///
/// Obligatorio al final de cualquier prueba que muestre un aviso: `mostrarAviso`
/// deja un `Timer` vivo y una prueba que termina con un temporizador pendiente
/// falla.
Future<void> cerrarAvisos(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
}

/// Busca un texto sin distinguir mayúsculas, por si el tema lo transforma.
Finder texto(String contenido) => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data ?? '').toUpperCase() == contenido.toUpperCase(),
      description: 'texto «$contenido», sin distinguir mayúsculas',
    );

void main() {
  group('Aula Virtual · pestañas', () {
    testWidgets('las dos pestañas se pintan y cambiar muestra el contenido correcto',
        (tester) async {
      final gateway = FakeAulaGateway()
        ..anuncios = [anuncioEjemplo(titulo: 'Aviso importante')]
        ..tareas = [tareaEjemplo(titulo: 'Taller de soldadura')];

      await montar(tester, gateway: gateway);
      await asentar(tester);

      expect(find.text('Tablón'), findsOneWidget);
      expect(find.text('Trabajo de Clase'), findsOneWidget);
      // El tablón es la pestaña inicial.
      expect(find.text('Aviso importante'), findsOneWidget);

      await cambiarPestana(tester, 'Trabajo de Clase');

      expect(find.text('Taller de soldadura'), findsOneWidget);
      expect(find.text('Aviso importante'), findsNothing);
    });
  });

  group('Aula Virtual · Tablón', () {
    testWidgets('los anuncios se pintan en el orden que da el gateway', (tester) async {
      // El gateway entrega más reciente primero. La pantalla **no re-ordena**:
      // se comprueba la posición vertical, que es lo que ve el usuario.
      final gateway = FakeAulaGateway()
        ..anuncios = [
          anuncioEjemplo(id: 'a2', titulo: 'Nuevo', publicadoEn: '2026-09-21T12:00:00.000Z'),
          anuncioEjemplo(id: 'a1', titulo: 'Viejo', publicadoEn: '2026-09-20T12:00:00.000Z'),
        ];

      await montar(tester, gateway: gateway);
      await asentar(tester);

      expect(
        tester.getTopLeft(find.text('Nuevo')).dy,
        lessThan(tester.getTopLeft(find.text('Viejo')).dy),
      );
      // Y se pidió una sola vez: un segundo orden sería una segunda fuente de
      // verdad, y aquí se fija que no la hay.
      expect(gateway.llamadas.where((c) => c.startsWith('tablon:')), hasLength(1));
    });

    testWidgets('un tablón vacío muestra el estado vacío y no un indicador de carga',
        (tester) async {
      final gateway = FakeAulaGateway();

      await montar(tester, gateway: gateway);
      await asentar(tester);

      expect(texto('Todavía no hay anuncios'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('un fallo del tablón muestra el aviso y la pantalla sigue usable',
        (tester) async {
      final gateway = FakeAulaGateway()
        ..errorAlListarTablon = const AppException(
          type: AppErrorType.red,
          message: 'No hay conexión con el servidor.',
          code: 'SIN_RED',
        )
        ..tareas = [tareaEjemplo(titulo: 'Taller de soldadura')];

      await montar(tester, gateway: gateway);
      await asentar(tester);

      // El fallo se cuenta **sin** vaciar la pantalla: la otra pestaña sigue
      // funcionando.
      expect(find.textContaining('No pudimos cargar el tablón'), findsOneWidget);

      await cambiarPestana(tester, 'Trabajo de Clase');
      expect(find.text('Taller de soldadura'), findsOneWidget);
    });
  });

  group('Aula Virtual · Trabajo de clase', () {
    testWidgets('una tarea de tipo material no muestra puntos ni fecha límite',
        (tester) async {
      // Un `MATERIAL` trae `puntosMaximos == 0` y `fechaLimite == null` por
      // diseño. Pintarlos sería un «0 pts» y una fecha vacía sobre material de
      // lectura: una mentira sobre lo que la tarea es.
      final gateway = FakeAulaGateway()
        ..tareas = [
          tareaEjemplo(
            id: 'mat-1',
            titulo: 'Guía de lectura',
            tipo: TipoTarea.material,
            puntosMaximos: 0,
            fechaLimite: null,
          ),
        ]
        ..entregas = [entregaEjemplo(id: 'ent-mat', tareaId: 'mat-1')];

      await montar(tester, gateway: gateway);
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');

      expect(find.text('Guía de lectura'), findsOneWidget);
      expect(find.textContaining('pts'), findsNothing);
      expect(find.textContaining('Vence'), findsNothing);
    });

    testWidgets('la tarjeta refleja los cuatro estados de entrega', (tester) async {
      final gateway = FakeAulaGateway()
        ..tareas = [
          tareaEjemplo(id: 't1', titulo: 'Tarea A'),
          tareaEjemplo(id: 't2', titulo: 'Tarea B'),
          tareaEjemplo(id: 't3', titulo: 'Tarea C'),
          tareaEjemplo(id: 't4', titulo: 'Tarea D'),
        ]
        ..entregas = [
          entregaEjemplo(id: 'e1', tareaId: 't1', estado: EstadoEntrega.asignada),
          entregaEjemplo(id: 'e2', tareaId: 't2', estado: EstadoEntrega.entregada),
          entregaEjemplo(
            id: 'e3',
            tareaId: 't3',
            estado: EstadoEntrega.devuelta,
            notaAsignada: 18,
          ),
          entregaEjemplo(id: 'e4', tareaId: 't4', estado: EstadoEntrega.reclamada),
        ];

      await montar(tester, gateway: gateway);
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');

      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Entregada'), findsOneWidget);
      // La nota sólo se pinta cuando el docente devolvió, y va con el estado.
      expect(find.text('Devuelta · 18 pts'), findsOneWidget);
      expect(find.text('Reclamada'), findsOneWidget);
    });

    testWidgets('una tarea vencida sin entregar se lee como pendiente', (tester) async {
      // El backend **no** guarda un estado «faltante» (§4.3): la UI lo deriva
      // del reloj. Sigue siendo «Pendiente» —es la verdad—, pero se marca.
      final gateway = FakeAulaGateway()
        ..tareas = [
          tareaEjemplo(
            id: 't1',
            titulo: 'Tarea vencida',
            fechaLimite: '2020-01-01T00:00:00.000Z',
          ),
        ]
        ..entregas = [
          entregaEjemplo(id: 'e1', tareaId: 't1', estado: EstadoEntrega.asignada),
        ];

      await montar(tester, gateway: gateway);
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');

      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.textContaining('Vencida'), findsOneWidget);
    });

    testWidgets('una entrega atrasada se marca como tardía', (tester) async {
      final gateway = FakeAulaGateway()
        ..tareas = [tareaEjemplo(id: 't1', titulo: 'Tarea tardía')]
        ..entregas = [
          entregaEjemplo(
            id: 'e1',
            tareaId: 't1',
            estado: EstadoEntrega.entregada,
            esTardia: true,
          ),
        ];

      await montar(tester, gateway: gateway);
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');

      expect(find.text('Entregada'), findsOneWidget);
    });
  });

  group('Aula Virtual · el gestor documental atado a la entrega', () {
    testWidgets('abrir una tarea monta el panel con el entidadId de la entrega',
        (tester) async {
      final gateway = FakeAulaGateway()
        ..tareas = [tareaEjemplo(id: 't1', titulo: 'Informe final')]
        ..entregas = [
          entregaEjemplo(id: 'ent-1', tareaId: 't1', estado: EstadoEntrega.asignada),
        ];
      final archivos = FakeArchivosGateway();

      await montar(tester, gateway: gateway, archivos: archivos);
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');

      await tester.tap(find.text('Informe final'));
      await asentar(tester);

      expect(find.byType(GestorDocumentalPanel), findsOneWidget);
      // **La aserción que importa.** El `entidadId` es el `m6_entregas.id`, no
      // el de la tarea: es la unión que deja al docente ver la entrega desde
      // las políticas de M6 sobre `files_metadata`. Pasar el id de la tarea
      // colgaría el archivo de una entidad inexistente, sin dar error.
      expect(archivos.llamadas, contains('listarPorEntidad:TASK_SUBMISSION:ent-1'));
    });

    testWidgets('el docente no ve el panel de entrega del alumno', (tester) async {
      final gateway = FakeAulaGateway()
        ..tareas = [tareaEjemplo(id: 't1', titulo: 'Informe final')];
      final archivos = FakeArchivosGateway();

      await montar(tester, gateway: gateway, esDocente: true, archivos: archivos);
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');

      await tester.tap(find.text('Informe final'));
      await asentar(tester);

      expect(find.byType(GestorDocumentalPanel), findsNothing);
      expect(archivos.llamadas, isEmpty);
      // Y no se pidió `mis-entregas`: la ruta es del alumno (§6) y devolvería
      // 403 para el docente.
      expect(gateway.llamadas, isNot(contains('misEntregas')));
    });

    testWidgets('entregar cambia el estado y se refleja en pantalla', (tester) async {
      final gateway = FakeAulaGateway()
        ..tareas = [tareaEjemplo(id: 't1', titulo: 'Informe final')]
        ..entregas = [
          entregaEjemplo(id: 'ent-1', tareaId: 't1', estado: EstadoEntrega.asignada),
        ];

      await montar(tester, gateway: gateway, archivos: FakeArchivosGateway());
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');
      await tester.tap(find.text('Informe final'));
      await asentar(tester);

      await tester.tap(find.text('Entregar tarea'));
      await asentar(tester);

      expect(gateway.llamadas, contains('entregar:ent-1'));
      // El doble mutó de verdad: su lista lo refleja.
      expect(gateway.entregas.single.estado, EstadoEntrega.entregada);
      expect(find.textContaining('Entregada.'), findsOneWidget);
      // El botón pasa a la acción inversa: reclamar.
      expect(find.text('Reclamar entrega'), findsOneWidget);

      await cerrarAvisos(tester);
    });

    testWidgets('un fallo al entregar se cuenta y no cambia el estado', (tester) async {
      final gateway = FakeAulaGateway()
        ..tareas = [tareaEjemplo(id: 't1', titulo: 'Informe final')]
        ..entregas = [
          entregaEjemplo(id: 'ent-1', tareaId: 't1', estado: EstadoEntrega.asignada),
        ]
        ..errorAlEntregar = const AppException(
          type: AppErrorType.validacion,
          message: 'La fecha límite ya pasó y la tarea no admite entrega tardía.',
          code: 'ENTREGA_FUERA_DE_PLAZO',
        );

      await montar(tester, gateway: gateway, archivos: FakeArchivosGateway());
      await asentar(tester);
      await cambiarPestana(tester, 'Trabajo de Clase');
      await tester.tap(find.text('Informe final'));
      await asentar(tester);

      await tester.tap(find.text('Entregar tarea'));
      await asentar(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      // El estado no cambió: sigue pendiente y el botón sigue ofreciendo entregar.
      expect(gateway.entregas.single.estado, EstadoEntrega.asignada);
      expect(find.text('Entregar tarea'), findsOneWidget);

      await cerrarAvisos(tester);
    });
  });
}
