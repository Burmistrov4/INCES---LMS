/// Cómo se mueve el aspirante por los pasos del formulario de inscripción.
///
/// **Qué protege.** El `Stepper` sólo tenía `onStepContinue` y `onStepCancel`: se
/// avanzaba y se retrocedía de uno en uno. Corregir la fecha de nacimiento desde
/// el paso de confirmación obligaba a pulsar «Atrás» una vez por cada paso
/// intermedio, y el aspirante tenía que saberse de memoria en qué paso estaba el
/// campo que quería cambiar. Eso es lo que se arregló, y esto es lo que impide
/// que se vuelva a romper en silencio.
///
/// **Cómo se mide el paso actual.** Leyendo `Stepper.currentStep` del widget
/// montado, y no la geometría. Es la única señal que no depende de si el cuerpo
/// del paso está plegado por el `AnimatedCrossFade`, de si el encabezado es
/// `role="group"` o `role="button"`, ni de si algo cae fuera del pliegue. Una
/// aserción geométrica aquí mediría el `Stepper` en lugar de la navegación, y
/// pasaría el día que la navegación estuviera rota.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/formulario_inscripcion.dart';

void main() {
  /// El paso en el que está el formulario, leído del propio `Stepper`.
  int pasoActual(WidgetTester tester) =>
      tester.widget<Stepper>(find.byType(Stepper)).currentStep;

  /// Pulsa algo que puede estar por debajo del pliegue.
  ///
  /// Con `ensureVisible` delante, como el resto del arnés: en un formulario de
  /// siete pasos el resumen del último crece con los datos que se hayan
  /// rellenado, y `tap` sobre algo fuera de la ventana no acierta.
  Future<void> pulsar(WidgetTester tester, Finder objetivo) async {
    await tester.ensureVisible(objetivo);
    await tester.pump();
    await tester.tap(objetivo);
    await tester.pumpAndSettle();
  }

  testWidgets('el formulario empieza en el primer paso', (tester) async {
    await montarFormulario(tester);

    expect(pasoActual(tester), 0);
  });

  testWidgets('pulsar el paso en el que ya se está no hace nada', (tester) async {
    await montarFormulario(tester);

    await pulsar(tester, find.text('Datos personales').first);

    expect(pasoActual(tester), 0);
  });

  testWidgets('pulsar el título de un paso ya visitado vuelve a él sin exigir nada',
      (tester) async {
    // Éste es el caso que originó el cambio: desde la confirmación, volver a
    // corregir un dato del principio.
    await montarFormulario(tester);
    await completarFormulario(tester); // deja en la confirmación (paso 6)
    expect(pasoActual(tester), 6);

    // `.first` y no un `find.text` a secas: desde que el resumen agrupa los datos
    // por paso, el nombre del grupo aparece DOS veces —en el encabezado del
    // `Stepper` y como título del bloque del resumen—. El encabezado va primero
    // en el árbol porque el `Stepper` vertical pinta, por cada paso,
    // [cabecera, cuerpo], y el resumen vive dentro del cuerpo del último.
    await pulsar(tester, find.text('Datos personales').first);

    expect(pasoActual(tester), 0);
  });

  testWidgets('retroceder no exige nada: se vuelve aunque el paso esté incompleto',
      (tester) async {
    // El motivo de volver es justo corregir un dato ya escrito. Si retroceder
    // exigiera que el paso estuviera correcto, el aspirante quedaría encerrado
    // con el error que quiere arreglar.
    await montarFormulario(tester);
    // Rellena el paso 0 y deja el formulario **en el paso 1, que está vacío**:
    // así el paso del que se sale es el que tiene obligatorios sin responder, que
    // es lo que hace que la prueba muerda. Una implementación que validara el
    // paso actual antes de dejarlo —el error fácil de cometer aquí— no pasaría.
    await completarFormulario(tester, paso: 1);
    expect(pasoActual(tester), 1);

    await pulsar(tester, find.text('Datos personales').first);

    expect(pasoActual(tester), 0);
    // Y no se queja de nada: retroceder no valida.
    expect(find.textContaining('Faltan datos obligatorios'), findsNothing);
  });

  testWidgets('saltar hacia delante exige rellenar los pasos intermedios',
      (tester) async {
    await montarFormulario(tester);

    // Nada rellenado: se pulsa el título del tercer paso.
    await pulsar(tester, find.text('Formación').first);

    // No se mueve, y el aviso nombra lo que falta **del paso en el que está**
    // —que es el que puede resolver ahora—, no del destino al que quería ir.
    expect(pasoActual(tester), 0);
    expect(find.textContaining('Faltan datos obligatorios'), findsOneWidget);
    expect(find.textContaining('primer nombre'), findsOneWidget);
  });

  testWidgets('el resumen ofrece un acceso directo por cada grupo con datos',
      (tester) async {
    await montarFormulario(tester);
    await completarFormulario(tester);

    // Cinco de los seis grupos tienen datos: «Representante legal» queda vacío
    // —el catálogo de ejemplo es de una persona adulta, sin representante—, y un
    // grupo sin respuestas no se pinta. Si el resumen listara los grupos del
    // catálogo en vez de los que tienen datos, serían seis.
    expect(find.text('Editar'), findsNWidgets(5));
  });

  testWidgets('«Editar» lleva al paso del grupo, no a la posición del botón',
      (tester) async {
    await montarFormulario(tester);
    await completarFormulario(tester);

    // El quinto botón corresponde al ÚLTIMO grupo con datos, que es el paso 5:
    // «Representante legal» (paso 4) no tiene botón porque no tiene datos. Si el
    // atajo usara la posición del botón como índice de paso, llevaría al 4 —que
    // está vacío— y el aspirante no encontraría lo que fue a corregir.
    await pulsar(tester, find.text('Editar').at(4));

    expect(pasoActual(tester), 5);
  });

  testWidgets('«Editar» del primer grupo lleva al primer paso', (tester) async {
    await montarFormulario(tester);
    await completarFormulario(tester);

    await pulsar(tester, find.text('Editar').at(0));

    expect(pasoActual(tester), 0);
  });
}
