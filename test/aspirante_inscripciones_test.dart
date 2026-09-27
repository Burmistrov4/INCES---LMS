import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/inscripcion.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/screens/aspirante_dashboard.dart';
import 'package:inces_lms_app/screens/mis_inscripciones_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_inscripcion_gateway.dart';

/// Monta un panel del aspirante y espera la carga inicial.
///
/// Igual que en `cpanel_test.dart`: `MaterialApp` con el tema institucional y
/// `Scaffold(body: panel)`. No se usa `pumpAndSettle` durante la carga porque el
/// indicador de progreso es una animación infinita.
Future<void> montarPanel(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(
    MaterialApp(theme: IncesTheme.claro(), home: Scaffold(body: panel)),
  );
  await tester.pump();
  await tester.pump();
}

/// Deja pasar el tiempo para que el SnackBar se cierre solo (sin temporizadores
/// pendientes al terminar el test).
Future<void> cerrarAvisos(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 8));
  await tester.pump();
}

/// Busca un botón cuyo `label` contiene el texto indicado, aunque esté
/// construido con el constructor `.icon` (su runtimeType es un subtipo privado
/// `_FilledButtonWithIcon`, así que `find.widgetWithText` —que usa `byType`
/// interno— no lo encuentra).
Finder botonFilled(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<FilledButton>());

Finder botonOutlined(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.bySubtype<OutlinedButton>());

void main() {
  group('PanelOfertas (catálogo del estudiante)', () {
    testWidgets('sin secciones abiertas muestra el panel vacío', (tester) async {
      final repo = InscripcionesRepository(
        gateway: FakeInscripcionGateway()..ofertasDevueltas = const [],
      );
      await montarPanel(tester, PanelOfertas(repositorio: repo));
      expect(find.text('No hay secciones abiertas'), findsOneWidget);
    });

    testWidgets('sección en asignación bloquea «Inscribirme» aunque haya cupos',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ofertasDevueltas = [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            cuposDisponibles: 3,
            cuposOcupados: 2,
            ofertaVigente: true,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelOfertas(repositorio: repo));

      // Botón de asignación presente y DESHABILITADO.
      final finderAsig = botonFilled('Asiento en\nasignación');
      expect(finderAsig, findsOneWidget);
      expect(tester.widget<FilledButton>(finderAsig).onPressed, isNull);
      // Etiqueta destacada que explica el estado.
      expect(find.text('Asiento en asignación'), findsOneWidget);
      // El botón de inscribirse no aparece.
      expect(botonFilled('Inscribirme'), findsNothing);
    });

    testWidgets('con cupo y sin oferta vigente habilita «Inscribirme»',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ofertasDevueltas = [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            cuposDisponibles: 2,
            cuposOcupados: 3,
            ofertaVigente: false,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelOfertas(repositorio: repo));

      final finder = botonFilled('Inscribirme');
      expect(finder, findsOneWidget);
      expect(tester.widget<FilledButton>(finder).onPressed, isNotNull);
      expect(find.text('Asiento en asignación'), findsNothing);
    });

    testWidgets('sin cupos y sin oferta vigente muestra «Sin cupos» deshabilitado',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ofertasDevueltas = [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            cuposDisponibles: 0,
            cuposOcupados: 5,
            ofertaVigente: false,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelOfertas(repositorio: repo));

      final finder = botonFilled('Sin cupos');
      expect(finder, findsOneWidget);
      expect(tester.widget<FilledButton>(finder).onPressed, isNull);
      expect(botonFilled('Inscribirme'), findsNothing);
    });

    testWidgets('al pulsar «Inscribirme» delega la sección al repositorio',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..ofertasDevueltas = [
          ocupacionSeccionEjemplo(
            id: 'sec-1',
            cuposDisponibles: 2,
            cuposOcupados: 3,
            ofertaVigente: false,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelOfertas(repositorio: repo));

      await tester.tap(botonFilled('Inscribirme'));
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('inscribirse:sec-1'));
    });
  });

  group('PanelMisInscripciones (Mis inscripciones)', () {
    testWidgets('sin inscripciones muestra el panel vacío', (tester) async {
      final repo = InscripcionesRepository(
        gateway: FakeInscripcionGateway()..misInscripcionesDevueltas = const [],
      );
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));
      expect(find.text('Aún no tienes inscripciones'), findsOneWidget);
    });

    testWidgets('WAITLISTED muestra la posición en la cola y «Renunciar»',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: 3,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      expect(find.text('Lugar 3 en la cola'), findsOneWidget);
      expect(botonOutlined('Renunciar'), findsOneWidget);
      expect(botonFilled('Aceptar cupo'), findsNothing);
    });

    testWidgets('WAITLISTED sin posición muestra «En lista de espera»',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: null,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      expect(find.text('En lista de espera'), findsOneWidget);
    });

    testWidgets('PENDING_BID muestra «Aceptar cupo» y «Renunciar»', (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.pendingBid,
            ofertaVenceEn:
                DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      expect(botonFilled('Aceptar cupo'), findsOneWidget);
      expect(botonOutlined('Renunciar'), findsOneWidget);
    });

    testWidgets('ENROLLED no ofrece acciones y confirma el asiento', (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.enrolled,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      expect(botonOutlined('Renunciar'), findsNothing);
      expect(botonFilled('Aceptar cupo'), findsNothing);
      expect(find.text('Tienes tu asiento confirmado en esta sección.'),
          findsOneWidget);
    });

    testWidgets('DROPPED conserva la fila como historial', (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.dropped,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      expect(find.text('Renunciaste a este cupo. La fila se conserva como '
          'historial.'),
          findsOneWidget);
    });

    testWidgets('al pulsar «Renunciar» delega la sección al repositorio',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: 2,
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      await tester.tap(botonOutlined('Renunciar'));
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('renunciar:sec-1'));
    });

    testWidgets('al pulsar «Aceptar cupo» delega la sección al repositorio',
        (tester) async {
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.pendingBid,
            ofertaVenceEn:
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
          ),
        ];
      final repo = InscripcionesRepository(gateway: fake);
      await montarPanel(tester, PanelMisInscripciones(repositorio: repo));

      await tester.tap(botonFilled('Aceptar cupo'));
      await tester.pump();
      await cerrarAvisos(tester);

      expect(fake.llamadas, contains('aceptarOferta:sec-1'));
    });
  });

  group('PanelMisInscripciones · urgencia (color y orden)', () {
    /// El color base de una insignia, leído del `Icon` que la pinta.
    ///
    /// Se lee del `Icon` y no del fondo del contenedor porque el icono lleva el
    /// color **puro** del tema mientras el fondo lo lleva con alfa 0.12:
    /// comparar contra el puro es exacto y no depende de cómo se redondeen los
    /// flotantes de `withValues`.
    Color? colorDeIcono(WidgetTester tester, IconData icono) =>
        tester.widget<Icon>(find.byIcon(icono)).color;

    testWidgets('PENDING_BID va en ámbar y WAITLISTED en azul — no al revés',
        (tester) async {
      // Esta prueba existe porque el fallo real era **invisible**: el estado
      // pasivo (en cola) gritaba en ámbar y el urgente (oferta por aceptar, con
      // fecha límite) susurraba en el azul primario, que es el color de medio
      // interfaz. Ninguna prueba afirmaba sobre el color, así que el
      // intercambio sobrevivió sin que nadie lo viera.
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-oferta',
            materia: 'Oferta',
            estado: EstadoInscripcion.pendingBid,
            ofertaVenceEn:
                DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
          ),
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-cola',
            materia: 'Cola',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: 4,
          ),
        ];
      await montarPanel(
        tester,
        PanelMisInscripciones(
          repositorio: InscripcionesRepository(gateway: fake),
        ),
      );

      expect(
        colorDeIcono(tester, Icons.local_offer_outlined),
        IncesTheme.advertencia,
        reason: 'la oferta por aceptar es el estado urgente: va en ámbar',
      );
      expect(
        colorDeIcono(tester, Icons.people_outline),
        IncesTheme.info,
        reason: 'estar en la cola no exige acción: va en azul, no en ámbar',
      );
      expect(
        colorDeIcono(tester, Icons.local_offer_outlined),
        isNot(colorDeIcono(tester, Icons.people_outline)),
        reason: 'si coincidieran, el color no distinguiría nada',
      );
    });

    testWidgets('la oferta por aceptar se pinta por ENCIMA de la cola',
        (tester) async {
      // El orden del backend no es el orden de la pantalla: lo que caduca va
      // primero. Se le pide al revés a propósito —la cola antes que la oferta—
      // para que un orden que se limitara a respetar al servidor fallara.
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-cola',
            materia: 'Cola',
            estado: EstadoInscripcion.waitlisted,
            posicionEnCola: 2,
          ),
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-oferta',
            materia: 'Oferta',
            estado: EstadoInscripcion.pendingBid,
            ofertaVenceEn:
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
          ),
        ];
      await montarPanel(
        tester,
        PanelMisInscripciones(
          repositorio: InscripcionesRepository(gateway: fake),
        ),
      );

      final yOferta = tester.getTopLeft(find.text('Oferta')).dy;
      final yCola = tester.getTopLeft(find.text('Cola')).dy;

      expect(
        yOferta,
        lessThan(yCola),
        reason: 'la oferta con fecha límite debe leerse antes que la espera',
      );
    });

    testWidgets('con ofertas vivas, la cabecera lo dice en palabras',
        (tester) async {
      // El color de una insignia es una señal débil. El aviso de cabecera es la
      // red que evita que el alumno pierda el cupo por no mirar la fila.
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-oferta',
            estado: EstadoInscripcion.pendingBid,
            ofertaVenceEn:
                DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
          ),
        ];
      await montarPanel(
        tester,
        PanelMisInscripciones(
          repositorio: InscripcionesRepository(gateway: fake),
        ),
      );

      expect(
        find.textContaining('oferta de cupo esperando respuesta'),
        findsOneWidget,
      );
    });

    testWidgets('sin ofertas vivas no hay aviso de cabecera', (tester) async {
      // El contrapeso de la prueba anterior: un aviso que sale siempre deja de
      // avisar, y «tienes 0 ofertas esperando» sería ruido.
      final fake = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(
            seccionId: 'sec-1',
            estado: EstadoInscripcion.enrolled,
          ),
        ];
      await montarPanel(
        tester,
        PanelMisInscripciones(
          repositorio: InscripcionesRepository(gateway: fake),
        ),
      );

      expect(find.textContaining('esperando respuesta'), findsNothing);
    });
  });
}
