import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/aspirante_model.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';

import 'support/catalogo_ejemplo.dart';
import 'support/fake_gateway.dart';
import 'support/fake_planilla_gateway.dart';
import 'support/formulario_inscripcion.dart';

/// El formulario **conducido por el catálogo**.
///
/// Lo que estas pruebas defienden no es que el formulario pinte campos: es que
/// **el catálogo manda**. La pantalla no conoce ni los pasos, ni las preguntas,
/// ni cuáles son obligatorias; todo eso sale de las filas. Así que las pruebas
/// tampoco lo escriben a mano: montan un catálogo y comprueban que la pantalla
/// se comporta como ese catálogo dice. Cambiar el catálogo y que cambie la
/// pantalla *es* la prueba.
///
/// Los campos se buscan por **código** y nunca por etiqueta. La etiqueta es
/// texto que el CFS puede reescribir desde el panel —de hecho esa es la gracia—
/// y una prueba atada a ella se rompería precisamente el día que el catálogo
/// está funcionando como se pretendía.
///
/// Nada de esto toca la red: los tres repositorios y el servicio entran
/// inyectados. Un widget que sólo se puede montar contra producción no se prueba.
void main() {
  // ---------------------------------------------------------------------------
  // Arnés
  // ---------------------------------------------------------------------------

  /// Los dobles de una pantalla montada, para poder mirarlos después.
  late FakePlanillaGateway planilla;
  late FakeGateway gateway;

  /// Monta la pantalla y deja los dobles a mano.
  ///
  /// El montaje de verdad —inyección, ventana y espera de la carga— vive en
  /// `support/formulario_inscripcion.dart`, porque el barrido responsive monta la
  /// misma pantalla. Aquí sólo se guardan los dobles con los nombres que usan los
  /// casos de abajo, que es lo que les interesa mirar después: `gateway` para ver
  /// qué se envió y `planilla` para contar cuántas veces se pidió el catálogo.
  Future<void> montar(
    WidgetTester tester, {
    CatalogoInscripcion? catalogo,
    Object? errorCatalogo,
    List<OpcionCampo>? programas,
    Object? errorProgramas,
  }) async {
    final arnes = await montarFormulario(
      tester,
      catalogo: catalogo,
      errorCatalogo: errorCatalogo,
      programas: programas,
      errorProgramas: errorProgramas,
    );
    gateway = arnes.gateway;
    planilla = arnes.planilla;
  }

  // Las ayudas para conducir el formulario —buscar un campo por su código,
  // escribir, elegir en un desplegable, marcar una casilla, avanzar de paso y
  // rellenarlo entero— viven en `support/formulario_inscripcion.dart`, porque las
  // usa también el barrido responsive. Aquí se importan y se usan tal cual.

  // ---------------------------------------------------------------------------
  // El catálogo manda
  // ---------------------------------------------------------------------------

  group('los pasos salen del catálogo', () {
    testWidgets('hay un paso por grupo, con el nombre del grupo', (tester) async {
      await montar(tester);

      // Los nombres se sacan del propio catálogo: si alguien añade un grupo, esta
      // prueba lo exige sin que haya que tocarla.
      for (final grupo in gruposDeEjemplo()) {
        expect(
          find.text(grupo),
          findsWidgets,
          reason: 'el grupo «$grupo» del catálogo no aparece como paso',
        );
      }

      expect(find.text('Confirmación y Contraseña'), findsOneWidget);
    });

    testWidgets('un catálogo distinto produce pasos distintos', (tester) async {
      // La prueba que de verdad distingue «conducido por datos» de «pintado a
      // mano»: se cambia el dato y cambia la pantalla, sin tocar código.
      await montar(
        tester,
        catalogo: CatalogoInscripcion([
          campoCatalogo('solo_uno',
              etiqueta: 'Pregunta única', grupo: 'Grupo inventado', orden: 1),
        ]),
      );

      expect(find.text('Grupo inventado'), findsWidgets);
      expect(find.text('Datos personales'), findsNothing);
      expect(find.text('Misiones'), findsNothing);
      // Un grupo ⇒ un «Continuar», más el paso de confirmación.
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Finalizar inscripción'), findsOneWidget);
    });

    testWidgets('los campos que se pintan son los del catálogo', (tester) async {
      await montar(tester);

      for (final campo in catalogoEjemplo().campos) {
        // Los condicionales se saltan: nacen ocultos, y exigirlos aquí sería
        // exigir que el formulario pinte preguntas cuya condición es falsa.
        if (!campo.visibleCon(const {})) continue;
        expect(
          campoDe(campo.codigo),
          findsOneWidget,
          reason: 'el campo ${campo.codigo} del catálogo no se pintó',
        );
      }
      // Y uno que no está, no está.
      expect(campoDe('campo_que_no_existe'), findsNothing);
    });

    testWidgets('el orden de los pasos es el del catálogo, no el alfabeto',
        (tester) async {
      // Se invierte el `orden` de dos grupos y los pasos tienen que invertirse.
      await montar(
        tester,
        catalogo: CatalogoInscripcion([
          campoCatalogo('b', etiqueta: 'B', grupo: 'Zeta', orden: 1),
          campoCatalogo('a', etiqueta: 'A', grupo: 'Alfa', orden: 2),
        ]),
      );

      final zeta = tester.getTopLeft(find.text('Zeta').first).dy;
      final alfa = tester.getTopLeft(find.text('Alfa').first).dy;
      expect(zeta, lessThan(alfa));
    });
  });

  // ---------------------------------------------------------------------------
  // Cuando el catálogo no llega
  // ---------------------------------------------------------------------------

  group('un catálogo que no se pudo leer', () {
    testWidgets('se dice, y no se pinta un formulario vacío', (tester) async {
      // Un catálogo vacío y uno que no se pudo leer pintan lo mismo —una pantalla
      // sin campos— y sólo el `Result` los distingue. Mostrar el formulario vacío
      // ante un fallo de red haría creer que la inscripción no tiene preguntas.
      await montar(tester, errorCatalogo: Exception('sin red'));

      expect(find.textContaining('No pudimos cargar el formulario'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Continuar'), findsNothing);
    });

    testWidgets('un catálogo vacío avisa de que no está publicado', (tester) async {
      await montar(tester, catalogo: const CatalogoInscripcion([]));

      expect(find.textContaining('llegó vacío'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('al reintentar, se vuelve a pedir el catálogo', (tester) async {
      await montar(tester, errorCatalogo: Exception('sin red'));

      planilla.errorAlLeerCatalogo = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(planilla.llamadas.where((l) => l == 'campos').length, 2);
      expect(find.text('Datos personales'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Lo que el catálogo exige
  // ---------------------------------------------------------------------------

  group('obligatoriedad', () {
    testWidgets('un obligatorio vacío bloquea el paso y dice cuál falta',
        (tester) async {
      await montar(tester);

      await avanzar(tester, 0);

      // El mensaje nombra los campos: con 44 preguntas, «algo falló» no sirve
      // para corregir.
      expect(
        find.textContaining('Faltan datos obligatorios'),
        findsOneWidget,
      );
      expect(find.textContaining('primer nombre'), findsOneWidget);
      expect(find.textContaining('cédula de identidad'), findsOneWidget);
    });

    testWidgets('al completar el paso, el aviso desaparece', (tester) async {
      await montar(tester);

      await escribir(tester, 'primer_nombre', 'Lorenzo');
      await escribir(tester, 'primer_apellido', 'Roca');
      await escribir(tester, 'cedula', '20123456');
      await escribir(tester, 'fecha_nac', '2000-01-01');
      await elegirEnDesplegable(tester, 'sexo', 'Femenino');

      await avanzar(tester, 0);

      expect(find.textContaining('Faltan datos obligatorios'), findsNothing);
      // Y ahora el que bloquea es el paso siguiente: eso demuestra que se avanzó.
      await avanzar(tester, 1);
      expect(find.textContaining('teléfono móvil'), findsOneWidget);
    });

    testWidgets('un campo opcional vacío no bloquea nada', (tester) async {
      // `segundo_nombre` no es obligatorio: rellenar sólo lo exigido tiene que
      // bastar. Si el formulario exigiera todo, el aspirante no podría inscribirse.
      await montar(tester);

      await escribir(tester, 'primer_nombre', 'Lorenzo');
      await escribir(tester, 'primer_apellido', 'Roca');
      await escribir(tester, 'cedula', '20123456');
      await escribir(tester, 'fecha_nac', '2000-01-01');
      await elegirEnDesplegable(tester, 'sexo', 'Masculino');

      await avanzar(tester, 0);

      expect(find.textContaining('Faltan datos obligatorios'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Visibilidad condicional
  // ---------------------------------------------------------------------------

  group('preguntas condicionales', () {
    testWidgets('la pregunta de detalle no se ve hasta marcar su disparador',
        (tester) async {
      await montar(tester);

      expect(campoDe('pueblo_indigena_cual'), findsNothing);

      await marcarPrimeraCasilla(tester, 'pueblo_indigena');

      expect(campoDe('pueblo_indigena_cual'), findsOneWidget);
    });

    testWidgets('desmarcar la esconde otra vez', (tester) async {
      await montar(tester);

      await marcarPrimeraCasilla(tester, 'pueblo_indigena');
      expect(campoDe('pueblo_indigena_cual'), findsOneWidget);

      await marcarPrimeraCasilla(tester, 'pueblo_indigena');
      expect(campoDe('pueblo_indigena_cual'), findsNothing);
    });

    testWidgets('el valor escrito no se pierde al ocultarse y volver a aparecer',
        (tester) async {
      // Aquí es donde se paga la decisión de que el valor viva en el mapa de la
      // pantalla y no en el widget: una pregunta que se oculta y se vuelve a
      // mostrar conserva lo que el aspirante había escrito. Sin eso, el
      // aspirante que se equivoca al marcar una casilla pierde lo tecleado.
      await montar(tester);

      await marcarPrimeraCasilla(tester, 'pueblo_indigena');
      await escribir(tester, 'pueblo_indigena_cual', 'Wayúu');

      await marcarPrimeraCasilla(tester, 'pueblo_indigena');
      expect(campoDe('pueblo_indigena_cual'), findsNothing);

      await marcarPrimeraCasilla(tester, 'pueblo_indigena');
      expect(
        find.descendant(
          of: campoDe('pueblo_indigena_cual'),
          matching: find.text('Wayúu'),
        ),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // La regla de edad del representante legal
  // ---------------------------------------------------------------------------

  group('representante legal y edad', () {
    /// Un menor de edad: 15 años. Es el mínimo que admite el propio centro —hay
    /// un «Curso Introductorio» para 15 y 16 años—, así que es un caso real y no
    /// un borde artificial.
    ///
    /// Es una variable y no un `get`, y no es un detalle de estilo: **Dart no
    /// admite `get` locales**. Escribirlo como accesor no compila, y el error que
    /// da el analizador («Expected to find ';'») apunta al sitio equivocado.
    final fechaDeMenor = '${DateTime.now().year - 15}-01-01';

    testWidgets('para un mayor de edad, el representante no se exige',
        (tester) async {
      // El error que esto evita es el contrario: que la pantalla exija el
      // representante a todo el mundo y un adulto no pueda inscribirse sin
      // inventarse un tutor.
      await montar(tester);

      await completarFormulario(tester, fechaNac: '2000-01-01');

      expect(find.text('Revisa tus datos antes de enviar'), findsOneWidget);
    });

    testWidgets('para un menor de edad, sí se exige y dice cuál falta',
        (tester) async {
      await montar(tester);

      // Se rellena todo menos el representante legal (paso 4), que para un menor
      // es obligatorio aunque el catálogo no lo marque: la condición es la EDAD,
      // y la columna `condicion` del catálogo compara un campo contra otro.
      await escribir(tester, 'primer_nombre', 'Lorenzo');
      await escribir(tester, 'primer_apellido', 'Roca');
      await escribir(tester, 'cedula', '20123456');
      await escribir(tester, 'fecha_nac', fechaDeMenor);
      await elegirEnDesplegable(tester, 'sexo', 'Masculino');
      await avanzar(tester, 0);
      await escribir(tester, 'telefono', '04141234567');
      await escribir(tester, 'email', 'lorenzo@example.com');
      await escribir(tester, 'direccion', 'Valencia, Carabobo');
      await avanzar(tester, 1);
      await elegirEnDesplegable(tester, 'nivel_educativo', 'Secundaria');
      await avanzar(tester, 2);
      await avanzar(tester, 3); // Misiones, nada obligatorio

      // El paso del representante tiene que bloquear.
      await avanzar(tester, 4);

      expect(find.textContaining('Faltan datos obligatorios'), findsOneWidget);
      expect(find.textContaining('cédula del representante'), findsOneWidget);
    });

    testWidgets('con los datos del representante, el menor sí puede seguir',
        (tester) async {
      await montar(tester);

      await escribir(tester, 'primer_nombre', 'Lorenzo');
      await escribir(tester, 'primer_apellido', 'Roca');
      await escribir(tester, 'cedula', '20123456');
      await escribir(tester, 'fecha_nac', fechaDeMenor);
      await elegirEnDesplegable(tester, 'sexo', 'Masculino');
      await avanzar(tester, 0);
      await escribir(tester, 'telefono', '04141234567');
      await escribir(tester, 'email', 'lorenzo@example.com');
      await escribir(tester, 'direccion', 'Valencia, Carabobo');
      await avanzar(tester, 1);
      await elegirEnDesplegable(tester, 'nivel_educativo', 'Secundaria');
      await avanzar(tester, 2);
      await avanzar(tester, 3);

      await escribir(tester, 'numero_identidad_tutor', '87654321');
      await escribir(tester, 'nombre_tutor', 'Ana Pérez');
      await escribir(tester, 'parentesco_tutor', 'Madre');
      await escribir(tester, 'telefono_tutor', '04149876543');
      await escribir(tester, 'correo_tutor', 'ana@example.com');

      await avanzar(tester, 4);

      expect(find.textContaining('Faltan datos obligatorios'), findsNothing);
      // Y el modelo se marca como menor: el servidor lo va a volver a comprobar.
      expect(
        AspiranteModel.esMenorDeEdadCon(DateTime.parse(fechaDeMenor)),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // El envío: la síntesis de las claves planas
  // ---------------------------------------------------------------------------

  group('el envío', () {
    /// Rellena la contraseña y las dos confirmaciones del paso final.
    Future<void> ponerPassword(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña (mínimo 8 caracteres)'),
        'secreto12345',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña'),
        'secreto12345',
      );
      await tester.pump();
    }

    /// Pulsa «Finalizar inscripción» y deja que el envío se resuelva.
    ///
    /// Sin `pumpAndSettle`: durante el envío se pinta un
    /// `LinearProgressIndicator`, que es una animación infinita y colgaría la
    /// espera. Los dobles resuelven en microtareas, así que unas vueltas bastan.
    Future<void> enviar(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Finalizar inscripción'));
      await tester.pump();
      await tester.tap(find.text('Finalizar inscripción'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('sintetiza `nombres` y `apellidos` antes de enviar',
        (tester) async {
      // **La prueba que existe por el fallo silencioso de `202609240001`.** El
      // catálogo pide el nombre desglosado y el trigger de PostgreSQL lee
      // `nombres` concatenado. Si la síntesis no ocurriera, el trigger dejaría
      // `v_nombres` en NULL, la condición `v_es_aspirante` fallaría y **la ficha
      // no se crearía, sin error**: el aspirante vería «registro exitoso» y no
      // tendría ficha.
      await montar(tester);

      await completarFormulario(tester);
      await ponerPassword(tester);
      await enviar(tester);

      final metadata = gateway.ultimaMetadata;
      expect(metadata, isNotNull, reason: 'no se llegó a llamar a signUp');
      expect(metadata!['nombres'], 'Lorenzo José');
      expect(metadata['apellidos'], 'Roca Pérez');
    });

    testWidgets('manda `datos_planilla` con la planilla completa', (tester) async {
      await montar(tester);

      await completarFormulario(tester);
      await ponerPassword(tester);
      await enviar(tester);

      final planillaEnviada = gateway.ultimaMetadata!['datos_planilla'];
      expect(planillaEnviada, isA<Map<String, dynamic>>());

      final mapa = planillaEnviada as Map<String, dynamic>;
      // Lleva los campos que **no** tienen columna propia: eso es justo lo que se
      // perdía y lo que obliga a volver a teclear todo al exportar a HACER.
      expect(mapa['primer_nombre'], 'Lorenzo');
      expect(mapa['segundo_apellido'], 'Pérez');
      expect(mapa['misiones'], isA<Map>());
      expect((mapa['misiones'] as Map).keys, contains('RIBAS'));
    });

    testWidgets('NO manda `mision_ribaras`', (tester) async {
      // La decisión de la pantalla nueva: la rejilla `misiones` viaja dentro de
      // `datos_planilla` y el campo de texto libre del formulario viejo deja de
      // enviarse. Mandar los dos sería guardar lo mismo dos veces con dos formas
      // distintas, y el día que discreparan no habría forma de saber cuál manda.
      await montar(tester);

      await completarFormulario(tester);
      await ponerPassword(tester);
      await enviar(tester);

      expect(gateway.ultimaMetadata!.containsKey('mision_ribaras'), isFalse);
    });

    testWidgets('copia las claves planas que el trigger lee', (tester) async {
      await montar(tester);

      await completarFormulario(tester);
      await ponerPassword(tester);
      await enviar(tester);

      final metadata = gateway.ultimaMetadata!;
      expect(metadata['cedula'], '20123456');
      expect(metadata['sexo'], 'M');
      expect(metadata['telefono'], '04141234567');
      expect(metadata['nivel_educativo'], 'SECUNDARIA');
      // D14: la CLAVE sigue siendo `curso_seleccionado` —es el código del campo
      // del catálogo y la que lee `handle_new_user()`—, pero el VALOR es el
      // **uuid** del programa, no su nombre. Antes viajaba «Herrería», y renombrar
      // el programa en M2 dejaba huérfana la ficha que lo había elegido.
      expect(metadata['curso_seleccionado'], uuidHerreria);
      expect(metadata['curso_seleccionado'], isNot('Herrería'));
      expect(metadata['direccion'], 'Valencia, Carabobo');
      // El correo no viaja en la metadata —lo pone `auth.users`—, pero sí se usa
      // para el registro y el prechequeo.
      expect(gateway.ultimoEmailRegistro, 'lorenzo@example.com');
      expect(gateway.ultimaPasswordRegistro, 'secreto12345');
    });

    testWidgets('un campo oculto no viaja en la planilla', (tester) async {
      // Si viajara, `datos_planilla` guardaría una contradicción —un detalle de
      // pueblo indígena junto a un «no pertenezco»— y nadie sabría después cuál
      // de las dos cosas es la respuesta.
      await montar(tester);

      await escribir(tester, 'primer_nombre', 'Lorenzo');
      await escribir(tester, 'primer_apellido', 'Roca');
      await escribir(tester, 'cedula', '20123456');
      await escribir(tester, 'fecha_nac', '2000-01-01');
      await elegirEnDesplegable(tester, 'sexo', 'Masculino');

      // Se contesta el detalle y después se desdice la respuesta de la que depende.
      await marcarPrimeraCasilla(tester, 'pueblo_indigena');
      await escribir(tester, 'pueblo_indigena_cual', 'Wayúu');
      await marcarPrimeraCasilla(tester, 'pueblo_indigena');

      await avanzar(tester, 0);
      await escribir(tester, 'telefono', '04141234567');
      await escribir(tester, 'email', 'lorenzo@example.com');
      await escribir(tester, 'direccion', 'Valencia, Carabobo');
      await avanzar(tester, 1);
      await elegirEnDesplegable(tester, 'nivel_educativo', 'Secundaria');
      await avanzar(tester, 2);
      await avanzar(tester, 3);
      await avanzar(tester, 4);
      await elegirEnDesplegable(tester, 'curso_seleccionado', 'Herrería');
      await avanzar(tester, 5);

      await ponerPassword(tester);
      await enviar(tester);

      final mapa = gateway.ultimaMetadata!['datos_planilla'] as Map<String, dynamic>;
      expect(mapa.containsKey('pueblo_indigena_cual'), isFalse);
      // Y la respuesta que sí se dejó puesta viaja: ocultar una pregunta no puede
      // llevarse por delante a las demás.
      expect(mapa['primer_nombre'], 'Lorenzo');
    });

    testWidgets('una contraseña corta no deja enviar', (tester) async {
      await montar(tester);

      await completarFormulario(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña (mínimo 8 caracteres)'),
        'corta',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmar contraseña'),
        'corta',
      );
      await tester.pump();
      await enviar(tester);

      // La pantalla no llegó a pedir el registro: se paró en su propia validación.
      expect(gateway.ultimaMetadata, isNull);
      expect(gateway.llamadas.contains('registrarConPassword'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // La oferta formativa que se pide en vivo
  // ---------------------------------------------------------------------------

  group('la oferta formativa', () {
    testWidgets('el resumen del paso final pinta el nombre, no el uuid',
        (tester) async {
      // La mitad visible de D14. Lo que se guarda es el uuid —eso lo fijan
      // `campos_planilla_test.dart` (el widget sube el `valor`) y la prueba
      // «copia las claves planas» de más arriba (el uuid llega a la metadata)—,
      // pero el resumen del paso final es el único sitio donde un valor guardado
      // se vuelve a convertir en texto. Como `curso_seleccionado` declara
      // `fuente`, sus opciones no están en el catálogo: un resumen que no las
      // recibiera pintaría el uuid crudo en la cara del aspirante.
      await montar(tester);
      await completarFormulario(tester);

      expect(find.text('Herrería'), findsWidgets);
      expect(find.textContaining(uuidHerreria), findsNothing);
    });

    testWidgets('si la oferta formativa falla, se avisa y se puede reintentar',
        (tester) async {
      // La oferta formativa cambia, así que no puede quedar congelada en el
      // catálogo: se pide en vivo. Cuando falla, el aspirante tiene que verlo y
      // poder reintentar en vez de quedarse mirando un desplegable vacío sin
      // saber por qué.
      //
      // D14 se llevó por delante el respaldo de nombres escrito a mano: con la
      // clave foránea esos nombres no son inscribibles —el trigger los resuelve
      // contra `programs` y no los encuentra—, así que «seguir con los cursos
      // conocidos» ya no es una opción y el aviso es la única salida honesta.
      await montar(
        tester,
        programas: const [],
        errorProgramas: Exception('sin red'),
      );

      // Hay que **llegar** al paso de la propuesta formativa antes de tocar nada:
      // el aviso vive ahí, y aunque `find` lo encuentra desde el paso 0 —el
      // `Stepper` deja el contenido de todos los pasos en el árbol—, el de un paso
      // que no es el actual está plegado a alto cero, así que `tap` no acertaría.
      // Una prueba que pulsa un botón sin acertarle y pasa no prueba nada.
      await completarFormulario(tester, paso: 5);

      expect(find.textContaining('No pudimos cargar la oferta formativa'),
          findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      gateway.errorAlProgramas = null;
      gateway.programas = programasDePrueba;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No pudimos cargar la oferta formativa'),
          findsNothing);
    });
  });
}
