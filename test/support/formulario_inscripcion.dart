/// Cómo conducir el formulario de inscripción desde una prueba.
///
/// Vive aquí y no dentro de un archivo de pruebas porque lo usan **dos**: la
/// suite del formulario conducido por el catálogo y el barrido responsive, que
/// recorre el formulario entero a 375 px para auditar desbordes. Duplicarlo haría
/// que el día que cambie un paso, una de las dos copias se quede atrás y pase a
/// medir otra cosa sin avisar.
///
/// Todo se busca por **código de campo** y nunca por etiqueta: el código es la
/// identidad del campo —renombrarlo es una migración de datos—, mientras que la
/// etiqueta es texto que el CFS reescribe desde el panel cuando quiere. Una
/// prueba atada a una etiqueta se rompe precisamente el día que el catálogo está
/// funcionando como se pretendía.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/repositories/aspirante_repository.dart';
import 'package:inces_lms_app/repositories/planilla_repository.dart';
import 'package:inces_lms_app/screens/aspirante_form_screen.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

import 'catalogo_ejemplo.dart';
import 'fake_gateway.dart';
import 'fake_planilla_gateway.dart';

/// Los dobles de una pantalla montada, para poder mirarlos después.
class ArnesFormulario {
  ArnesFormulario({required this.planilla, required this.gateway});

  /// El doble del catálogo. Registra las llamadas a `campos` y `guardar`.
  final FakePlanillaGateway planilla;

  /// El doble de auth y de aspirantes, en uno. Guarda la metadata que recibió
  /// `signUp`, que es donde se comprueba qué se envió de verdad.
  final FakeGateway gateway;
}

/// Monta el formulario con el catálogo y los tres colaboradores inyectados.
///
/// El catálogo por defecto declara `fecha_nac` como **texto**, no como `fecha`, y
/// eso no es comodidad: este arnés existe para medir la **pantalla** —sus pasos,
/// sus obligatorios, lo que envía—, y la pantalla lee `fecha_nac` del mapa de
/// valores sin importarle de qué widget salió. Con el calendario delante, escribir
/// una fecha obligaría a navegar el selector de años de Material en cada prueba, y
/// las pruebas de la regla de edad acabarían midiendo el calendario en vez de la
/// regla. Que ese calendario produzca el mismo `YYYY-MM-DD` se prueba en
/// `campos_planilla_test.dart`, que es donde vive el widget; una prueba que quiera
/// el calendario de verdad pasa `catalogo: catalogoEjemplo()`.
///
/// La ventana es **alta por defecto** (2400 px) a propósito. Ojo con el `Stepper`,
/// que tiene dos comportamientos distintos y conviene no confundirlos: la
/// **cabecera** de todos los pasos está siempre pintada —por eso se ve el título de
/// cada paso—, pero el **contenido** de un paso que no es el actual se pliega con
/// un `AnimatedCrossFade` a alto cero (`stepper.dart:823`), y ahí dentro van los
/// campos **y los controles**. Sigue en el árbol, así que un `find` lo encuentra,
/// pero `tap` no acierta y avisa con un «would not hit test». Una prueba que busca
/// algo de otro paso y aun así pasa es la peor forma de aprobar.
///
/// Nada de esto toca la red. Un widget que sólo se puede montar contra
/// producción no se prueba.
Future<ArnesFormulario> montarFormulario(
  WidgetTester tester, {
  CatalogoInscripcion? catalogo,
  Object? errorCatalogo,
  List<String>? cursos,
  Object? errorCursos,
  Size tamano = const Size(900, 2400),
}) async {
  final planilla = FakePlanillaGateway()
    ..catalogo =
        catalogo ?? catalogoEjemplo(tipoFecha: TipoCampoInscripcion.texto);
  if (errorCatalogo != null) planilla.errorAlLeerCatalogo = errorCatalogo;

  final gateway = FakeGateway()..cursos = cursos ?? cursosDePrueba;
  if (errorCursos != null) gateway.errorAlCursos = errorCursos;

  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: IncesTheme.claro(),
      home: AspiranteFormScreen(
        planillaRepository: PlanillaRepository(gateway: planilla),
        aspiranteRepository: AspiranteRepository(gateway: gateway),
        authService: AuthService(gateway: gateway),
      ),
    ),
  );

  // Sin `pumpAndSettle`: mientras carga hay un `CircularProgressIndicator`, que es
  // una animación infinita y haría esperar para siempre. Los dobles resuelven en
  // microtareas, así que dos vueltas bastan para dejar el catálogo montado.
  await tester.pump();
  await tester.pump();

  return ArnesFormulario(planilla: planilla, gateway: gateway);
}

/// El widget de un campo, por su código.
///
/// La clave se la pone la pantalla al montarlo. Es única: la que lleva el widget
/// de dentro del campo tiene otro prefijo (`entrada-`) justamente para que esta
/// búsqueda no sea ambigua.
Finder campoDe(String codigo) => find.byKey(ValueKey('campo-$codigo'));

/// El `TextFormField` de dentro de un campo.
Finder entradaDe(String codigo) => find.descendant(
      of: campoDe(codigo),
      matching: find.byType(TextFormField),
    );

/// Escribe en un campo de texto.
///
/// Con `ensureVisible` delante: en un formulario de siete pasos el campo que se
/// quiere tocar puede estar por debajo del pliegue, y `enterText` sobre algo que
/// no se ha pintado no escribe nada y no avisa.
///
/// Y con la guarda de `readOnly`. Un campo de fecha se pinta con `readOnly: true`
/// —lo llena el calendario, no el teclado—, así que `enterText` lo ignora **sin
/// error**: la prueba escribe en el vacío y se cae tres pasos más allá, acusando a
/// la pantalla de un fallo del arnés. Vale más romper aquí, con el nombre del
/// campo delante.
Future<void> escribir(WidgetTester tester, String codigo, String texto) async {
  final entrada = entradaDe(codigo);
  await tester.ensureVisible(entrada);
  await tester.pump();

  final teclado = find.descendant(of: entrada, matching: find.byType(TextField));
  if (tester.widget<TextField>(teclado).readOnly) {
    fail(
      'El campo «$codigo» es de sólo lectura (lo llena un calendario), así que '
      '`escribir` no puede rellenarlo: `enterText` lo ignoraría sin error. '
      'Declara ese campo como `TipoCampoInscripcion.texto` en el catálogo de la '
      'prueba, o elige la fecha con el calendario.',
    );
  }

  await tester.enterText(entrada, texto);
  await tester.pump();
}

/// Elige una opción en un desplegable, por el texto de la opción.
Future<void> elegirEnDesplegable(
  WidgetTester tester,
  String codigo,
  String etiqueta,
) async {
  final desplegable = find.descendant(
    of: campoDe(codigo),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.ensureVisible(desplegable);
  await tester.pump();
  await tester.tap(desplegable);
  await tester.pumpAndSettle();
  // `.last` y no `first`: el desplegable pinta la opción elegida también en su
  // ranura, así que el texto aparece dos veces cuando ya hay algo seleccionado.
  await tester.tap(find.text(etiqueta).last);
  await tester.pumpAndSettle();
}

/// Marca la primera casilla de un campo: un booleano, o el primer ítem de una
/// rejilla.
Future<void> marcarPrimeraCasilla(WidgetTester tester, String codigo) async {
  final casilla =
      find.descendant(of: campoDe(codigo), matching: find.byType(Checkbox)).first;
  await tester.ensureVisible(casilla);
  await tester.pump();
  await tester.tap(casilla);
  await tester.pump();
}

/// Pulsa el «Continuar» del paso indicado.
///
/// El `Stepper` deja los controles de **todos** los pasos en el árbol, así que
/// `find.text('Continuar')` encuentra uno por paso y el del paso `i` es `.at(i)`
/// —el último dice «Finalizar inscripción» y no entra en la cuenta—. Sin esto,
/// `tap` se negaría por ambigüedad; con `.last` se pulsaría el botón de otro paso
/// y la prueba mediría lo que no cree.
///
/// Los dos `pumpAndSettle` no son adorno, y el segundo es el que importa. En un
/// `Stepper` vertical los controles se construyen **dentro del cuerpo del paso**
/// (`stepper.dart:822`), y el cuerpo de un paso que no es el actual está plegado a
/// alto cero por un `AnimatedCrossFade` de 200 ms. Un `pump()` sin duración **no
/// avanza el reloj**, así que la transición no correría nunca y el «Continuar» del
/// paso siguiente se quedaría midiendo cero: el `tap` no acertaría, `onStepContinue`
/// ni siquiera se llamaría —así que tampoco habría aviso de error que delatara el
/// fallo— y la prueba se caería más adelante culpando a la pantalla. Se espera a
/// que el paso esté de verdad en pantalla antes de pulsar, y a que termine la
/// transición después.
Future<void> avanzar(WidgetTester tester, int paso) async {
  await tester.pumpAndSettle();

  final boton = find.text('Continuar').at(paso);
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

/// Rellena los pasos del catálogo de ejemplo y deja la pantalla en [paso].
///
/// Por defecto [paso] es 6, la confirmación: es donde terminan los casos de envío.
/// Pero hay cosas que sólo se pueden tocar **estando** en su paso —el aviso de los
/// cursos vive en el de la propuesta formativa, y su «Reintentar» no es pulsable
/// desde otro—, así que [paso] permite parar antes. Se rellenan los pasos
/// anteriores al pedido, y ninguno más.
///
/// `fechaNac` se escribe como texto porque el arnés monta el catálogo con la fecha
/// declarada como `texto`: lo que se mide con esto es la pantalla —sus pasos, sus
/// obligatorios, lo que envía—, y la pantalla lee `fecha_nac` del mapa de valores
/// sin importarle de qué widget salió. Que el calendario produzca ese mismo
/// `YYYY-MM-DD` se prueba en `campos_planilla_test.dart`, que es donde vive ese
/// widget.
Future<void> completarFormulario(
  WidgetTester tester, {
  String fechaNac = '2000-01-01',
  int paso = 6,
}) async {
  // Paso 0 · Datos personales
  if (paso == 0) return;
  await escribir(tester, 'primer_nombre', 'Lorenzo');
  await escribir(tester, 'segundo_nombre', 'José');
  await escribir(tester, 'primer_apellido', 'Roca');
  await escribir(tester, 'segundo_apellido', 'Pérez');
  await escribir(tester, 'cedula', '20123456');
  await escribir(tester, 'fecha_nac', fechaNac);
  await elegirEnDesplegable(tester, 'sexo', 'Masculino');
  await avanzar(tester, 0);

  // Paso 1 · Ubicación y contacto
  if (paso == 1) return;
  await escribir(tester, 'telefono', '04141234567');
  await escribir(tester, 'email', 'lorenzo@example.com');
  await escribir(tester, 'direccion', 'Valencia, Carabobo');
  await avanzar(tester, 1);

  // Paso 2 · Formación
  if (paso == 2) return;
  await elegirEnDesplegable(tester, 'nivel_educativo', 'Secundaria');
  await avanzar(tester, 2);

  // Paso 3 · Misiones
  if (paso == 3) return;
  await marcarPrimeraCasilla(tester, 'misiones');
  await avanzar(tester, 3);

  // Paso 4 · Representante legal — vacío, y para un adulto está bien.
  if (paso == 4) return;
  await avanzar(tester, 4);

  // Paso 5 · Propuesta formativa
  if (paso == 5) return;
  await elegirEnDesplegable(tester, 'curso_seleccionado', 'Herrería');
  await avanzar(tester, 5);
}
