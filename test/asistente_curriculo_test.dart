import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/materia.dart';
import 'package:inces_lms_app/models/programa.dart';
import 'package:inces_lms_app/repositories/curriculo_repository.dart';
import 'package:inces_lms_app/screens/admin/asistente_curriculo_screen.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/fake_curriculo_gateway.dart';

/// Pruebas del asistente de tres pasos (Módulo 2).
///
/// Lo que se comprueba no es sólo que pinte: el asistente acumula estado en
/// memoria y **sólo escribe al final**, así que lo que importa es que el cuerpo
/// que llega al backend sea exactamente el que se revisó en el paso 3.
void main() {
  late FakeCurriculoGateway gateway;
  late CurriculoRepository repo;

  /// Rótulo tal y como queda en pantalla.
  ///
  /// Los títulos del asistente pasan por `TituloSeccion`, que pinta
  /// `texto.toUpperCase()` (`widgets/comunes.dart`). Buscarlos en su forma
  /// legible nunca los encuentra; las etiquetas del indicador de pasos, en
  /// cambio, se pintan tal cual. Esta función deja explícito cuál es cuál.
  String rotulo(String texto) => texto.toUpperCase();

  setUp(() {
    gateway = FakeCurriculoGateway()
      ..materias = [algoritmica(), basesDeDatos()]
      ..totalMaterias = 2;
    repo = CurriculoRepository(gateway: gateway);
  });

  /// Monta el asistente en una ventana amplia.
  ///
  /// El paso 2 reparte banco y pensum en dos columnas a partir de 900 px de
  /// ancho, y en una ventana de prueba de 800 el contenido queda por debajo del
  /// pliegue y los toques no alcanzan los botones.
  Future<void> montar(WidgetTester tester, {Widget? pantalla}) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: pantalla ?? AsistenteCurriculoScreen(repositorio: repo),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Toca algo que puede estar fuera del pliegue.
  Future<void> tocar(WidgetTester tester, Finder buscador) async {
    await tester.ensureVisible(buscador);
    await tester.pump();
    await tester.tap(buscador);
    await tester.pump();
  }

  /// Deja cerrarse el SnackBar. Sin esto, su temporizador sigue pendiente al
  /// terminar la prueba y el framework lo reporta como fallo.
  Future<void> cerrarAvisos(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  }

  /// Rellena el paso 1 y avanza al 2.
  Future<void> irAlPensum(
    WidgetTester tester, {
    String codigo = 'SIST-01',
    String nombre = 'Análisis de Sistemas',
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), codigo);
    await tester.enterText(find.byType(TextFormField).at(1), nombre);
    await tocar(tester, find.text('Siguiente'));
  }

  group('paso 1 · datos del programa', () {
    testWidgets('arranca en la identidad del programa', (tester) async {
      await montar(tester);

      expect(find.text(rotulo('Identidad del programa')), findsOneWidget);
      // Éstas son del indicador de pasos, que no pasa por `TituloSeccion`.
      expect(find.text('Datos del programa'), findsOneWidget);
      expect(find.text('Pensum'), findsOneWidget);
      expect(find.text('Revisión'), findsOneWidget);
      // Un programa nuevo se publica por defecto: es lo que el administrador
      // quiere casi siempre, y dejarlo en borrador por descuido es peor que
      // publicarlo por descuido (se ve en el catálogo y se puede archivar).
      expect(find.text('Publicar al crear'), findsOneWidget);
    });

    testWidgets('no avanza con el código vacío', (tester) async {
      await montar(tester);

      await tocar(tester, find.text('Siguiente'));

      expect(find.text('Ingresa el código.'), findsOneWidget);
      // Sigue en el paso 1.
      expect(find.text(rotulo('Identidad del programa')), findsOneWidget);
    });

    testWidgets('rechaza un código con espacios', (tester) async {
      await montar(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'SIST 01');
      await tester.enterText(find.byType(TextFormField).at(1), 'Un nombre');
      await tocar(tester, find.text('Siguiente'));

      expect(
        find.text('Sólo mayúsculas, dígitos y guiones, '
            'empezando por letra o dígito.'),
        findsOneWidget,
      );
      // El asistente carga el banco de materias al abrirse, así que la lista de
      // llamadas nunca está vacía. Lo que importa es que un código inválido no
      // llegue a escribir nada.
      expect(gateway.llamadas, isNot(contains('crearPrograma')));
    });

    testWidgets('pasa el código a mayúsculas mientras se escribe',
        (tester) async {
      await montar(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'sist-01');

      // El backend exige mayúsculas. Imponerlas al escribir es honesto: el
      // usuario ve exactamente lo que se va a mandar.
      //
      // Se lee el controlador y no el texto pintado porque el campo lleva
      // `hintText: 'SIST-01'`, y el hint sigue en el árbol aunque no se vea:
      // `find.text('SIST-01')` encontraría dos.
      final campo = tester.widget<TextFormField>(
        find.byType(TextFormField).at(0),
      );
      expect(campo.controller!.text, 'SIST-01');
    });
  });

  group('paso 2 · pensum', () {
    testWidgets('no deja avanzar sin materias', (tester) async {
      await montar(tester);
      await irAlPensum(tester);

      expect(find.text('El pensum está vacío. Añade materias desde el banco.'),
          findsOneWidget);

      await tocar(tester, find.text('Siguiente'));

      expect(
        find.text('El pensum necesita al menos una materia.'),
        findsOneWidget,
      );
      // Sigue en el paso 2.
      expect(find.text('Añadir al período'), findsOneWidget);
      await cerrarAvisos(tester);
    });

    testWidgets('añade una materia del banco al período elegido',
        (tester) async {
      await montar(tester);
      await irAlPensum(tester);

      await tocar(tester, find.byIcon(Icons.add_circle_outline).first);

      expect(find.text('Período 1'), findsOneWidget);
      expect(find.text('1 materia · 96 h'), findsOneWidget);
      // Y desaparece el estado vacío.
      expect(find.text('El pensum está vacío. Añade materias desde el banco.'),
          findsNothing);
    });

    testWidgets('no añade dos veces la misma materia', (tester) async {
      await montar(tester);
      await irAlPensum(tester);

      await tocar(tester, find.byIcon(Icons.add_circle_outline).first);
      // La ya añadida muestra un check en vez del botón, así que se intenta por
      // el banco otra vez: el icono de añadir que queda es el de la otra
      // materia, y la primera ya no ofrece añadir.
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

      await cerrarAvisos(tester);
    });

    testWidgets('permite añadir un período nuevo', (tester) async {
      await montar(tester);
      await irAlPensum(tester);

      await tocar(tester, find.widgetWithText(TextButton, 'Período'));
      await tocar(tester, find.byIcon(Icons.add_circle_outline).first);

      // La materia entra en el período 2, que es el que quedó seleccionado.
      expect(find.text('Período 2'), findsOneWidget);
      expect(find.text('Período 1'), findsNothing);
    });

    testWidgets('registra una materia en caliente y la añade', (tester) async {
      gateway.materiaCreada = const Materia(
        id: 'nueva-1',
        codigo: 'BD-II',
        nombre: 'Bases de Datos II',
        horasAcademicas: 96,
      );

      await montar(tester);
      await irAlPensum(tester);

      await tocar(
        tester,
        find.widgetWithText(OutlinedButton, 'Registrar materia'),
      );

      expect(find.text('Registrar materia'), findsWidgets);

      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'BD-II');
      await tester.enterText(campos.at(1), 'Bases de Datos II');
      await tester.enterText(campos.at(2), '96');
      await tocar(tester, find.widgetWithText(FilledButton, 'Registrar'));

      // Se mandó al backend con el código normalizado…
      expect(gateway.ultimaMateria!.codigo, 'BD-II');
      expect(gateway.ultimaMateria!.horasAcademicas, 96);
      // …y quedó en el pensum.
      expect(find.text('Bases de Datos II'), findsWidgets);
      await cerrarAvisos(tester);
    });

    testWidgets('ante un código repetido ofrece usar la existente',
        (tester) async {
      // El caso frecuente: la materia ya estaba en el banco y alguien la
      // escribió con otro nombre. Mostrar sólo el error obligaría a cancelar,
      // buscarla a mano y volver a empezar.
      gateway.errorAlCrearMateria = const AppException.duplicado(
        'Ya existe una materia con ese código.',
        code: 'REGISTRO_DUPLICADO',
      );
      gateway.materias = [basesDeDatos()];
      gateway.totalMaterias = 1;

      await montar(tester);
      await irAlPensum(tester);

      await tocar(
        tester,
        find.widgetWithText(OutlinedButton, 'Registrar materia'),
      );

      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), 'BD-I');
      await tester.enterText(campos.at(1), 'Base de datos');
      await tester.enterText(campos.at(2), '80');
      await tocar(tester, find.widgetWithText(FilledButton, 'Registrar'));

      expect(find.text('Usar la materia existente'), findsOneWidget);

      await tocar(
        tester,
        find.widgetWithText(TextButton, 'Usar la materia existente'),
      );

      // Se buscó por el código y se añadió la que ya existía.
      expect(gateway.ultimaBusquedaMaterias, 'BD-I');
      expect(find.text('Bases de Datos'), findsWidgets);
      await cerrarAvisos(tester);
    });
  });

  group('paso 3 · revisión y guardado', () {
    testWidgets('resume lo que se va a guardar y lo envía entero',
        (tester) async {
      gateway.detalleCreado = detalleSistemas();

      await montar(tester);
      await irAlPensum(tester);
      await tocar(tester, find.byIcon(Icons.add_circle_outline).first);
      await tocar(tester, find.text('Siguiente'));

      expect(find.text('Revisión'), findsOneWidget);
      expect(find.text('Análisis de Sistemas'), findsWidgets);
      expect(find.text('SIST-01'), findsWidgets);

      await tocar(tester, find.widgetWithText(FilledButton, 'Crear programa'));

      final enviado = gateway.ultimaCreacion!;
      expect(enviado.codigo, 'SIST-01');
      expect(enviado.nombre, 'Análisis de Sistemas');
      expect(enviado.tipo, TipoPrograma.carrera);
      expect(enviado.publicar, isTrue);
      expect(enviado.requierePasantia, isFalse);
      expect(enviado.pensum, hasLength(1));
      expect(enviado.pensum.single.materiaId, idAlgoritmica);
      expect(enviado.pensum.single.periodo, 1);
      await cerrarAvisos(tester);
    });

    testWidgets('muestra el fallo del backend sin cerrar el asistente',
        (tester) async {
      gateway.errorAlCrear = const AppException.validacion(
        'Una carrera activa no puede quedarse sin materias.',
        code: 'RESTRICCION_VIOLADA',
      );

      await montar(tester);
      await irAlPensum(tester);
      await tocar(tester, find.byIcon(Icons.add_circle_outline).first);
      await tocar(tester, find.text('Siguiente'));
      await tocar(tester, find.widgetWithText(FilledButton, 'Crear programa'));

      expect(
        find.text('Una carrera activa no puede quedarse sin materias.'),
        findsOneWidget,
      );
      // Sigue en el paso 3: el trabajo hecho no se pierde.
      expect(find.text('Revisión'), findsOneWidget);
    });
  });

  group('modo edición', () {
    testWidgets('arranca en el pensum y no ofrece cambiar la identidad',
        (tester) async {
      await montar(
        tester,
        pantalla: AsistenteCurriculoScreen(
          repositorio: repo,
          detalleInicial: detalleSistemas(),
        ),
      );

      // El código y el tipo no se pueden cambiar, así que no hay paso de datos.
      expect(find.text(rotulo('Identidad del programa')), findsNothing);
      // `Pensum` aparece dos veces: el título de la sección (en mayúsculas) y la
      // cabecera del constructor. Se pide cada uno por su forma.
      expect(find.text(rotulo('Pensum')), findsOneWidget);
      expect(find.text(rotulo('Revisión')), findsNothing);
      expect(find.text('Revisión'), findsOneWidget);
      // Y las dos materias del programa ya están cargadas.
      expect(find.text('Algorítmica'), findsWidgets);
      expect(find.text('Bases de Datos'), findsWidgets);
    });

    testWidgets('guarda con un reemplazo completo del pensum', (tester) async {
      gateway.detalleReemplazado = detalleSistemas();

      await montar(
        tester,
        pantalla: AsistenteCurriculoScreen(
          repositorio: repo,
          detalleInicial: detalleSistemas(),
        ),
      );

      await tocar(tester, find.text('Siguiente'));
      await tocar(tester, find.widgetWithText(FilledButton, 'Guardar pensum'));

      expect(gateway.llamadas, contains('reemplazarPensum:$idSistemas'));
      // Se manda el estado final completo, no una lista de cambios.
      expect(gateway.ultimoPensum, hasLength(2));
      expect(
        gateway.ultimoPensum!.map((e) => e.periodo),
        containsAll(<int>[1, 4]),
      );
      await cerrarAvisos(tester);
    });

    testWidgets('con secciones activas bloquea el pensum y lo explica',
        (tester) async {
      await montar(
        tester,
        pantalla: AsistenteCurriculoScreen(
          repositorio: repo,
          detalleInicial: detalleSistemas(editable: false, seccionesActivas: 3),
        ),
      );

      expect(find.textContaining('no se puede modificar'), findsOneWidget);
      expect(find.textContaining('3 sección(es)'), findsOneWidget);

      // El candado vive en el pie, junto a donde iría el botón de guardar, y el
      // pie sólo lo enseña en el último paso. Se avanza para comprobarlo: el
      // aviso del cuerpo ya explica el bloqueo desde el paso del pensum.
      await tocar(tester, find.text('Siguiente'));

      expect(find.text('Pensum bloqueado'), findsOneWidget);

      // Y no hay botón de guardar: la operación la rechazaría el backend.
      expect(
        find.widgetWithText(FilledButton, 'Guardar pensum'),
        findsNothing,
      );
    });
  });
}
