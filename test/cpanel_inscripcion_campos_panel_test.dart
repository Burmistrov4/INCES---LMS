import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/repositories/planilla_admin_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_inscripcion_campos_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'support/catalogo_ejemplo.dart';
import 'support/fake_planilla_admin_gateway.dart';

/// El panel de administración del catálogo de la planilla.
///
/// Lo que estas pruebas defienden no es que los botones existan, sino las cuatro
/// propiedades que hacen que el panel sirva para algo:
///
///  1. **Un campo apagado sigue en la lista.** Si desapareciera, apagarlo sería
///     irreversible desde la interfaz, que es el fallo que obligó a que el
///     gateway administrativo fuera distinto del público.
///  2. **`codigo` y `tipo` no son editables.** No porque falte un control, sino
///     porque el contrato de `actualizar` no los acepta: aquí se comprueba que el
///     diálogo no los ofrece como campo.
///  3. **Reordenar mueve dos filas y ninguna más**, y la pantalla lo refleja
///     porque relee el catálogo.
///  4. **Un rechazo del servidor no se convierte en un cambio silencioso.**
void main() {
  /// Ventana ancha y **alta**. A 800×600 las filas de abajo quedan fuera del
  /// viewport, `tap` no acierta y la prueba pasaría sin haber pulsado nada —
  /// que es la peor forma de aprobar. Es la misma razón por la que el barrido
  /// responsive usa 2400 px de alto.
  const Size ventana = Size(900, 2000);

  Future<void> montar(
    WidgetTester tester,
    FakePlanillaAdminGateway gateway,
  ) async {
    tester.view.physicalSize = ventana;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: CpanelInscripcionCamposPanel(
            repositorio: PlanillaAdminRepository(gateway: gateway),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Asienta la cadena asíncrona.
  ///
  /// `pumpAndSettle` y no un par de `pump()`: un intercambio de orden hace
  /// **dos** viajes al gateway —el intercambio y la relectura—, así que fijar el
  /// número de bombeos ataría la prueba al número de saltos de la
  /// implementación, y añadir uno la rompería sin que nada estuviera mal.
  Future<void> asentar(WidgetTester tester) => tester.pumpAndSettle();

  /// Deja cerrarse el aviso. Sin esto su temporizador sigue pendiente al acabar
  /// la prueba y el framework lo reporta como fallo.
  Future<void> cerrarAvisos(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  }

  /// La fila de un campo, por su código.
  Finder fila(String codigo) => find.byKey(ValueKey('fila-$codigo'));

  /// Un control de la fila de un campo, por su icono.
  Finder control(String codigo, IconData icono) => find.descendant(
        of: fila(codigo),
        matching: find.widgetWithIcon(IconButton, icono),
      );

  Finder interruptor(String codigo) => find.descendant(
        of: fila(codigo),
        matching: find.byType(Switch),
      );

  group('lectura del catálogo', () {
    testWidgets('pinta los grupos y sus campos', (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      // Los grupos son los que declara el catálogo, no una lista escrita aquí:
      // si alguien añade uno, esta prueba tiene que seguir pasando.
      expect(find.text('Datos personales'), findsOneWidget);
      expect(find.text('Formación'), findsOneWidget);
      expect(find.text('Propuesta formativa'), findsOneWidget);

      expect(find.text('Primer nombre'), findsOneWidget);
      expect(find.text('Propuesta formativa a cursar'), findsOneWidget);
      expect(gateway.llamadas, contains('catalogoCompleto'));
    });

    testWidgets('un campo apagado sigue en la lista y sale atenuado',
        (tester) async {
      // Ésta es la propiedad central del panel. Si el apagado desapareciera de
      // la lista, no habría forma de volver a encenderlo desde la interfaz.
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      expect(find.text('Talla de camisa'), findsOneWidget);
      expect(find.text('Apagado'), findsOneWidget);
      expect(tester.widget<Switch>(interruptor('talla_camisa')).value, isFalse);
    });

    testWidgets('las insignias de inspección se pintan sin ser editables',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      // `condicion`, `aplica_a` y `fuente` se muestran: quien administra tiene
      // que poder ver por qué un campo encendido puede no aparecer.
      expect(find.text('Depende de pueblo_indigena'), findsOneWidget);
      expect(find.text('Sólo 2 programas'), findsOneWidget);
      expect(find.text('Opciones en vivo'), findsOneWidget);
    });

    testWidgets('con el catálogo vacío lo dice, en vez de quedarse en blanco',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = const [];

      await montar(tester, gateway);

      expect(find.text('El catálogo está vacío'), findsOneWidget);
    });

    testWidgets('si la carga falla, muestra el error y permite reintentar',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()
        ..campos = catalogoAdminEjemplo()
        ..errorAlLeer = const AppException.servidor();

      await montar(tester, gateway);
      expect(find.text('No pudimos cargar esta sección'), findsOneWidget);

      gateway.errorAlLeer = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await asentar(tester);

      expect(find.text('Primer nombre'), findsOneWidget);
    });
  });

  group('encender y apagar', () {
    testWidgets('encender un campo apagado lo manda al gateway y lo refleja',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await tester.tap(interruptor('talla_camisa'));
      await asentar(tester);

      expect(gateway.llamadas, contains('actualizar'));
      expect(gateway.codigoActualizado, 'talla_camisa');
      expect(gateway.cambiosActualizados, {'activo': true});

      // El interruptor muestra lo que devolvió el servidor, no lo que se pidió.
      expect(tester.widget<Switch>(interruptor('talla_camisa')).value, isTrue);
      await cerrarAvisos(tester);
    });

    testWidgets('apagar un campo lo atenúa pero lo deja reordenable',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await tester.tap(interruptor('segundo_nombre'));
      await asentar(tester);

      expect(gateway.cambiosActualizados, {'activo': false});
      expect(tester.widget<Switch>(interruptor('segundo_nombre')).value, isFalse);
      // Sigue teniendo sus botones: apagado no es congelado.
      expect(control('segundo_nombre', Icons.arrow_upward_rounded),
          findsOneWidget);
      expect(control('segundo_nombre', Icons.edit_outlined), findsOneWidget);
      await cerrarAvisos(tester);
    });

    testWidgets('si el gateway rechaza, el interruptor vuelve a la verdad',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()
        ..campos = catalogoAdminEjemplo()
        // `AppException` no tiene constructor nombrado `permisos`: sólo el enum
        // `AppErrorType.permisos`, que se alcanza por el genérico. Inventarse el
        // constructor compila en la cabeza y no en el analizador — y el
        // analizador fue el que lo cazó.
        ..errorAlActualizar = const AppException(
          type: AppErrorType.permisos,
          message: 'Sólo un administrador puede modificar el catálogo.',
          code: '42501',
        );

      await montar(tester, gateway);
      await tester.tap(interruptor('talla_camisa'));
      await asentar(tester);

      // No se cambió nada en el servidor, así que la pantalla no puede decir que
      // sí: muestra la verdad (sigue apagado) y avisa del motivo.
      expect(tester.widget<Switch>(interruptor('talla_camisa')).value, isFalse);
      expect(find.byType(SnackBar), findsOneWidget);
      await cerrarAvisos(tester);
    });
  });

  group('reordenar', () {
    testWidgets('subir un campo lo intercambia con su vecino anterior',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      // Antes: Primer nombre (10) va por encima de Segundo nombre (11).
      expect(
        tester.getTopLeft(find.text('Primer nombre')).dy,
        lessThan(tester.getTopLeft(find.text('Segundo nombre')).dy),
      );

      await tester.tap(control('segundo_nombre', Icons.arrow_upward_rounded));
      await asentar(tester);

      final intercambio = gateway.ultimoIntercambio;
      expect(intercambio, isNotNull);
      expect(intercambio!.$1.codigo, 'segundo_nombre');
      expect(intercambio.$2.codigo, 'primer_nombre');

      // Y la pantalla lo refleja: se releyó el catálogo en vez de mover la lista
      // a mano, así que lo que se ve es lo que quedó en la base.
      expect(
        tester.getTopLeft(find.text('Segundo nombre')).dy,
        lessThan(tester.getTopLeft(find.text('Primer nombre')).dy),
      );
      await cerrarAvisos(tester);
    });

    testWidgets('el primer campo de un grupo no puede subir', (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      final subir = tester.widget<IconButton>(
        control('primer_nombre', Icons.arrow_upward_rounded),
      );
      expect(subir.onPressed, isNull);
    });

    testWidgets('el último campo de un grupo no puede bajar', (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      // `talla_camisa` (orden 15) es el último de «Datos personales»; su
      // vecino por orden es `pueblo_indigena_cual` (14). Se comprueba contra el
      // último real y no contra el penúltimo: `pueblo_indigena_cual` **sí** puede
      // bajar, y afirmar lo contrario habría hecho fallar la prueba por una
      // cuenta mal llevada a mano —que es justo el error que el catálogo de
      // ejemplo existe para no tener que cometer—.
      final bajar = tester.widget<IconButton>(
        control('talla_camisa', Icons.arrow_downward_rounded),
      );
      expect(bajar.onPressed, isNull);
    });

    testWidgets('el vecino se busca dentro del grupo, no en la lista global',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);

      // `herramientas_propias` es el único campo de su grupo: subir o bajar
      // tendría que intercambiarlo con un campo de OTRO grupo si el vecino se
      // buscara en la lista global, y el admin vería moverse una fila que no
      // tocó. Los dos botones están deshabilitados.
      expect(
        tester
            .widget<IconButton>(
                control('herramientas_propias', Icons.arrow_upward_rounded))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
                control('herramientas_propias', Icons.arrow_downward_rounded))
            .onPressed,
        isNull,
      );
    });
  });

  group('alta de un campo', () {
    Future<void> abrirAlta(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir campo'));
      await asentar(tester);
      expect(find.text('Añadir campo'), findsNWidgets(2));
    }

    testWidgets('crea el campo con el orden siguiente al último',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirAlta(tester);

      await tester.enterText(
          find.byKey(const ValueKey('dialogo-codigo')), 'talla_zapato');
      await tester.enterText(
          find.byKey(const ValueKey('dialogo-etiqueta')), 'Talla de zapato');
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
      await asentar(tester);

      final creado = gateway.ultimoCreado;
      expect(creado, isNotNull);
      expect(creado!.codigo, 'talla_zapato');
      expect(creado.etiqueta, 'Talla de zapato');
      // El orden no lo teclea nadie: nace después del último (200 → 210). Si se
      // pidiera a mano, el admin tendría que saber qué números están libres.
      expect(creado.orden, 210);
      expect(creado.tipo, TipoCampoInscripcion.texto);
      expect(creado.activo, isTrue);

      // Y aparece en la lista sin recargar la página.
      expect(find.text('Talla de zapato'), findsOneWidget);
      await cerrarAvisos(tester);
    });

    testWidgets('un código con formato inválido no llega al gateway',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirAlta(tester);

      // El `CHECK` de la base rechazaría esto con un 23514. Validarlo aquí no
      // duplica la regla: evita un viaje para recibir un error que se puede
      // saber sin preguntar.
      await tester.enterText(
          find.byKey(const ValueKey('dialogo-codigo')), 'Talla Zapato');
      await tester.enterText(
          find.byKey(const ValueKey('dialogo-etiqueta')), 'Talla de zapato');
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
      await asentar(tester);

      expect(
        find.text('Sólo minúsculas, números y guion bajo, empezando por una letra.'),
        findsOneWidget,
      );
      expect(gateway.llamadas, isNot(contains('crear')));
      // El diálogo sigue abierto: no se perdió lo escrito.
      expect(find.byKey(const ValueKey('dialogo-codigo')), findsOneWidget);
    });

    testWidgets('un código repetido muestra el mensaje del servidor',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirAlta(tester);

      // `primer_nombre` ya existe. El doble lanza el 23505 como lo haría el
      // `unique` de la tabla, y la traducción de `AppException` tiene que
      // convertirlo en algo que se entienda.
      await tester.enterText(
          find.byKey(const ValueKey('dialogo-codigo')), 'primer_nombre');
      await tester.enterText(
          find.byKey(const ValueKey('dialogo-etiqueta')), 'Otra cosa');
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
      await asentar(tester);

      expect(find.textContaining('Ya existe un campo con ese código'),
          findsOneWidget);
      await cerrarAvisos(tester);
    });
  });

  group('edición de un campo', () {
    Future<void> abrirEdicion(WidgetTester tester, String codigo) async {
      await tester.tap(control(codigo, Icons.edit_outlined));
      await asentar(tester);
    }

    testWidgets('cambia la etiqueta y manda sólo lo editable', (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirEdicion(tester, 'primer_nombre');

      await tester.enterText(
          find.byKey(const ValueKey('dialogo-etiqueta')), 'Nombres de pila');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await asentar(tester);

      expect(gateway.codigoActualizado, 'primer_nombre');
      expect(gateway.cambiosActualizados!['etiqueta'], 'Nombres de pila');
      // `codigo` y `tipo` no viajan: `actualizar` no los acepta, así que no hay
      // forma de mandarlos ni por descuido.
      expect(gateway.cambiosActualizados, isNot(contains('codigo')));
      expect(gateway.cambiosActualizados, isNot(contains('tipo')));
      expect(find.text('Nombres de pila'), findsOneWidget);
      await cerrarAvisos(tester);
    });

    testWidgets('el código y el tipo se muestran como dato, no como campo',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirEdicion(tester, 'primer_nombre');

      // Un campo deshabilitado invita a intentar cambiarlo; y un
      // `TextFormField` de sólo lectura se traga un `enterText` sin decir nada,
      // así que una prueba que lo intentara pasaría escribiendo en el vacío.
      expect(find.byKey(const ValueKey('dialogo-codigo')), findsNothing);
      expect(find.byKey(const ValueKey('dialogo-tipo')), findsNothing);
      expect(find.text('no editable'), findsNWidgets(2));
    });

    testWidgets('borrar la ayuda manda cadena vacía y la deja en nulo',
        (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirEdicion(tester, 'talla_camisa');

      await tester.enterText(
          find.byKey(const ValueKey('dialogo-ayuda')), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await asentar(tester);

      // Cadena vacía y no `null`: `null` significa «no toques esta columna», que
      // aquí no es lo que se quiere. La base guarda `''` y el modelo lo
      // normaliza a `null` al leer.
      expect(gateway.cambiosActualizados!['ayuda'], '');
      expect(
        gateway.campos.firstWhere((c) => c.codigo == 'talla_camisa').ayuda,
        isNull,
      );
      await cerrarAvisos(tester);
    });

    testWidgets('cambiar el grupo mueve el campo de paso', (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirEdicion(tester, 'segundo_nombre');

      await tester.enterText(
          find.byKey(const ValueKey('dialogo-grupo')), 'Formación');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await asentar(tester);

      expect(gateway.cambiosActualizados!['grupo'], 'Formación');
      await cerrarAvisos(tester);
    });

    testWidgets('cerrar sin tocar nada no gasta una petición', (tester) async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();

      await montar(tester, gateway);
      await abrirEdicion(tester, 'primer_nombre');

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await asentar(tester);

      expect(gateway.llamadas, isNot(contains('actualizar')));
    });
  });
}
