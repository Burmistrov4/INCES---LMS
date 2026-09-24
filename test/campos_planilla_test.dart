import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/widgets/campos_planilla/campo_planilla.dart';
import 'package:inces_lms_app/widgets/campos_planilla/campo_rejilla.dart';
import 'package:inces_lms_app/widgets/campos_planilla/campo_tabla.dart';

/// El renderizador del catálogo: un widget por tipo, y el layout a 375 px.
///
/// **Por qué esto es un test y no una captura de pantalla.** Flutter Web pinta
/// en un único `<canvas>`, así que ni Playwright ve los widgets ni puede
/// pulsarlos, y las aserciones de layout están **apagadas en `--release`**. En un
/// widget test, en cambio, un `RenderFlex overflowed` **lanza una excepción** y
/// rompe la prueba: montar cada tipo a 375 px *es* la auditoría, y queda como red
/// permanente en vez de como evidencia de un momento.
///
/// Y el otro motivo, que es el que importa de verdad aquí: **una prueba de que un
/// campo oculto no se lleva el texto del que ocupaba su sitio**. El formulario es
/// conducido por datos, así que los campos cambian de posición cuando una
/// pregunta condicional aparece; sin claves estables, Flutter reutiliza el estado
/// del `FormField` que estaba en esa posición y el aspirante ve el texto de otra
/// pregunta. Es un fallo silencioso y esta suite existe para que no lo sea.
void main() {
  /// Un campo con los valores por defecto, para no repetir claves por caso.
  CampoInscripcion campo(
    String codigo, {
    String? etiqueta,
    TipoCampoInscripcion tipo = TipoCampoInscripcion.texto,
    bool obligatorio = false,
    int orden = 0,
    Map<String, dynamic>? opciones,
    String? ayuda,
  }) {
    return CampoInscripcion(
      codigo: codigo,
      etiqueta: etiqueta ?? codigo,
      grupo: 'Datos personales',
      tipo: tipo,
      orden: orden,
      obligatorio: obligatorio,
      opciones: opciones,
      ayuda: ayuda,
    );
  }

  /// Un anfitrión con estado, como lo tiene la pantalla real.
  ///
  /// El valor vive fuera del campo —en el mapa de la pantalla— y baja por
  /// `valor`; el campo lo sube por `onCambio`. Montar el campo suelto con un
  /// valor fijo no probaría nada: lo que hay que ejercitar es justamente ese ida
  /// y vuelta.
  /// Devuelve el **estado**, no el widget: lo que las pruebas leen es
  /// `anfitrion.ultimo`, que es el último valor que subió el campo, y eso vive
  /// en el estado. `tester.state<T>()` devuelve `T`, así que el parámetro de
  /// tipo tiene que ser `_AnfitrionState` — declarar aquí `_Anfitrion` compila
  /// el cuerpo pero no el `return`, y es un error de tipos, no un matiz.
  Future<_AnfitrionState> montar(
    WidgetTester tester,
    CampoInscripcion campo, {
    Object? inicial,
    Size tamano = const Size(600, 900),
    List<OpcionCampo>? opciones,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Anfitrion(
                // La clave ata el estado al campo: sin ella, montar dos campos
                // distintos en la misma prueba reutilizaría el estado del primero
                // —`initState` no vuelve a correr— y el valor inicial del segundo
                // se perdería.
                key: ValueKey(campo.codigo),
                campo: campo,
                inicial: inicial,
                opciones: opciones,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return tester.state<_AnfitrionState>(find.byType(_Anfitrion));
  }

  /// Un desborde de layout se registra como excepción. Sin este `expect` el
  /// fallo llegaría igual, pero sin decir qué tipo ni qué ancho lo provocó.
  void sinDesbordes(WidgetTester tester, String que, Size tamano) {
    expect(
      tester.takeException(),
      isNull,
      reason: '$que desborda a ${tamano.width.toInt()} px de ancho',
    );
  }

  group('despacho por tipo', () {
    testWidgets('texto y email se pintan como caja de texto', (tester) async {
      await montar(tester, campo('primer_nombre', tipo: TipoCampoInscripcion.texto));
      expect(find.byType(TextFormField), findsOneWidget);

      await montar(tester, campo('email', tipo: TipoCampoInscripcion.email));
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('numero y fecha se pintan como caja de texto', (tester) async {
      await montar(tester, campo('hijos', tipo: TipoCampoInscripcion.numero));
      expect(find.byType(TextFormField), findsOneWidget);

      await montar(tester, campo('fecha_nac', tipo: TipoCampoInscripcion.fecha));
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('seleccion se pinta como desplegable con las opciones del catálogo', (
      tester,
    ) async {
      await montar(
        tester,
        campo(
          'nacionalidad',
          etiqueta: 'Nacionalidad',
          tipo: TipoCampoInscripcion.seleccion,
          opciones: const {
            'opciones': [
              {'valor': 'V', 'etiqueta': 'Venezolano/a'},
              {'valor': 'E', 'etiqueta': 'Extranjero/a'},
            ],
          },
        ),
      );

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Nacionalidad'), findsWidgets);
    });

    testWidgets('un desplegable con fuente externa usa las opciones que le pasan', (
      tester,
    ) async {
      // `curso_seleccionado` declara `fuente: 'programas'`: sus opciones no están
      // en el catálogo. Si el widget ignorara las que le pasan, el aspirante
      // vería un desplegable vacío.
      await montar(
        tester,
        CampoInscripcion(
          codigo: 'curso_seleccionado',
          etiqueta: 'Propuesta formativa a cursar',
          grupo: 'Propuesta formativa',
          tipo: TipoCampoInscripcion.seleccion,
          orden: 440,
          obligatorio: true,
          fuente: 'programas',
        ),
        opciones: const [OpcionCampo(valor: 'Herrería', etiqueta: 'Herrería')],
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Herrería'), findsWidgets);
    });

    testWidgets('booleano se pinta como casilla', (tester) async {
      await montar(
        tester,
        campo(
          'discapacidad',
          etiqueta: '¿Tiene alguna diversidad funcional?',
          tipo: TipoCampoInscripcion.booleano,
        ),
      );

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('¿Tiene alguna diversidad funcional?'), findsOneWidget);
    });

    testWidgets('multiseleccion se pinta como fichas, una por opción', (tester) async {
      await montar(
        tester,
        campo(
          'tipo_discapacidad',
          etiqueta: 'Tipo de diversidad funcional',
          tipo: TipoCampoInscripcion.multiseleccion,
          opciones: const {
            'opciones': [
              {'valor': 'FISICA_MANO', 'etiqueta': 'Física (mano)'},
              {'valor': 'SENSORIAL_AUDITIVA', 'etiqueta': 'Sensorial auditiva'},
            ],
          },
        ),
      );

      expect(find.byType(FilterChip), findsNWidgets(2));
    });

    testWidgets('rejilla y tabla tienen su propio widget', (tester) async {
      await montar(
        tester,
        campo(
          'misiones',
          tipo: TipoCampoInscripcion.rejilla,
          opciones: const {
            'items': [
              {'valor': 'RIBAS', 'etiqueta': 'Ribas'},
            ],
          },
        ),
      );
      expect(find.byType(CampoRejilla), findsOneWidget);

      await montar(
        tester,
        campo(
          'familiares',
          tipo: TipoCampoInscripcion.tabla,
          opciones: const {
            'columnas': [
              {'codigo': 'nombres', 'etiqueta': 'Nombres', 'tipo': 'texto'},
            ],
          },
        ),
      );
      expect(find.byType(CampoTabla), findsOneWidget);
    });
  });

  group('ida y vuelta del valor', () {
    testWidgets('escribir en un texto sube el valor recortado', (tester) async {
      final anfitrion = await montar(tester, campo('primer_nombre'));

      await tester.enterText(find.byType(TextFormField), '  Lorenzo  ');
      await tester.pump();

      expect(anfitrion.ultimo, 'Lorenzo');
    });

    testWidgets('vaciar un texto sube null, no cadena vacía', (tester) async {
      // `null` y `''` son lo mismo para la base, pero `null` deja el mapa sin la
      // clave y evita mandar campos vacíos a `raw_user_meta_data`.
      final anfitrion = await montar(tester, campo('primer_nombre'), inicial: 'Lorenzo');

      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump();

      expect(anfitrion.ultimo, isNull);
    });

    testWidgets('un numero se guarda como número, no como texto', (tester) async {
      final anfitrion = await montar(
        tester,
        campo('hijos', tipo: TipoCampoInscripcion.numero),
      );

      await tester.enterText(find.byType(TextFormField), '3');
      await tester.pump();

      expect(anfitrion.ultimo, 3);
      expect(anfitrion.ultimo, isA<num>());
    });

    testWidgets('un cero no se confunde con un campo vacío', (tester) async {
      // El error clásico: `if (!valor)` trata el 0 como ausencia y borra una
      // respuesta legítima.
      final anfitrion = await montar(
        tester,
        campo('hijos', tipo: TipoCampoInscripcion.numero),
      );

      await tester.enterText(find.byType(TextFormField), '0');
      await tester.pump();

      expect(anfitrion.ultimo, 0);
      expect(valorDeCampoVacio(anfitrion.ultimo), isFalse);
    });

    testWidgets('marcar un booleano sube `true`, y desmarcarlo `false`', (tester) async {
      final anfitrion = await montar(
        tester,
        campo('discapacidad', tipo: TipoCampoInscripcion.booleano),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(anfitrion.ultimo, isTrue);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(anfitrion.ultimo, isFalse);

      // Y `false` **no** está vacío: es una respuesta, y un campo obligatorio de
      // este tipo tiene que poder cumplirse.
      expect(valorDeCampoVacio(anfitrion.ultimo), isFalse);
    });

    testWidgets('elegir en un desplegable sube el valor de la opción', (tester) async {
      final anfitrion = await montar(
        tester,
        campo(
          'nacionalidad',
          etiqueta: 'Nacionalidad',
          tipo: TipoCampoInscripcion.seleccion,
          opciones: const {
            'opciones': [
              {'valor': 'V', 'etiqueta': 'Venezolano/a'},
              {'valor': 'E', 'etiqueta': 'Extranjero/a'},
            ],
          },
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extranjero/a').last);
      await tester.pumpAndSettle();

      expect(anfitrion.ultimo, 'E');
    });

    testWidgets('marcar una ficha acumula, y desmarcarla quita', (tester) async {
      final anfitrion = await montar(
        tester,
        campo(
          'tipo_discapacidad',
          tipo: TipoCampoInscripcion.multiseleccion,
          opciones: const {
            'opciones': [
              {'valor': 'FISICA_MANO', 'etiqueta': 'Física (mano)'},
              {'valor': 'SENSORIAL_AUDITIVA', 'etiqueta': 'Sensorial auditiva'},
            ],
          },
        ),
      );

      await tester.tap(find.byType(FilterChip).first);
      await tester.pump();
      expect(anfitrion.ultimo, ['FISICA_MANO']);

      await tester.tap(find.byType(FilterChip).last);
      await tester.pump();
      expect(anfitrion.ultimo, ['FISICA_MANO', 'SENSORIAL_AUDITIVA']);

      await tester.tap(find.byType(FilterChip).first);
      await tester.pump();
      expect(anfitrion.ultimo, ['SENSORIAL_AUDITIVA']);
    });
  });

  group('rejilla', () {
    CampoInscripcion rejillaDeMisiones() => campo(
          'misiones',
          etiqueta: 'Misiones a las que pertenece',
          tipo: TipoCampoInscripcion.rejilla,
          opciones: const {
            'etiqueta_desde': 'Desde',
            'multiple': true,
            'items': [
              {'valor': 'RIBAS', 'etiqueta': 'Ribas'},
              {'valor': 'MERCAL', 'etiqueta': 'Mercal'},
            ],
          },
        );

    testWidgets('marcar un ítem guarda un mapa con ese ítem', (tester) async {
      // Un mapa y no una lista: cada ítem marcado lleva su «desde», y dos
      // estructuras paralelas podrían discrepar.
      final anfitrion = await montar(tester, rejillaDeMisiones());

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(anfitrion.ultimo, {'RIBAS': ''});
    });

    testWidgets('el campo «desde» aparece sólo al marcar, y guarda su texto', (tester) async {
      final anfitrion = await montar(tester, rejillaDeMisiones());

      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '2019');
      await tester.pump();

      expect(anfitrion.ultimo, {'RIBAS': '2019'});
    });

    testWidgets('desmarcar un ítem lo saca del mapa, con su «desde»', (tester) async {
      final anfitrion = await montar(
        tester,
        rejillaDeMisiones(),
        inicial: {'RIBAS': '2019'},
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(anfitrion.ultimo, isEmpty);
    });

    testWidgets('marcar dos ítems conserva los dos «desde»', (tester) async {
      // Aquí es donde una clave por índice se rompería: al marcar el segundo
      // ítem aparece un campo nuevo y los de debajo cambian de posición.
      final anfitrion = await montar(tester, rejillaDeMisiones());

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '2015');
      await tester.pump();

      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();

      expect(find.byType(TextFormField), findsNWidgets(2));
      // El primer «desde» no se ha perdido al aparecer el segundo.
      expect((anfitrion.ultimo as Map)['RIBAS'], '2015');
      expect((anfitrion.ultimo as Map)['MERCAL'], '');
    });
  });

  group('tabla', () {
    CampoInscripcion tablaDeFamiliares() => campo(
          'familiares',
          etiqueta: 'Familiares',
          tipo: TipoCampoInscripcion.tabla,
          opciones: const {
            'columnas': [
              {'codigo': 'nombres', 'etiqueta': 'Nombres', 'tipo': 'texto', 'obligatorio': true},
            ],
          },
        );

    testWidgets('«Añadir fila» agrega una fila vacía', (tester) async {
      final anfitrion = await montar(tester, tablaDeFamiliares());

      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.text('Añadir fila'));
      await tester.pump();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(anfitrion.ultimo, [<String, dynamic>{}]);
    });

    testWidgets('escribir en una celda guarda el valor bajo el código de la columna', (
      tester,
    ) async {
      final anfitrion = await montar(
        tester,
        tablaDeFamiliares(),
        inicial: [<String, dynamic>{}],
      );

      await tester.enterText(find.byType(TextFormField), 'Ana Pérez');
      await tester.pump();

      expect(anfitrion.ultimo, [
        {'nombres': 'Ana Pérez'},
      ]);
    });

    testWidgets('quitar la primera fila NO le deja los datos a la segunda', (tester) async {
      // La prueba que justifica que los ids de fila sean estables y se retiren en
      // su índice. Con claves por índice —o recortando los ids por el final—
      // Flutter reutilizaría el estado de la fila borrada y el aspirante vería
      // «Ana» en el sitio de «Luis».
      final anfitrion = await montar(
        tester,
        tablaDeFamiliares(),
        inicial: [
          {'nombres': 'Ana'},
          {'nombres': 'Luis'},
        ],
      );

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Luis'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();

      expect(anfitrion.ultimo, [
        {'nombres': 'Luis'},
      ]);
      expect(find.text('Luis'), findsOneWidget);
      expect(find.text('Ana'), findsNothing);
    });

    testWidgets('quitar la segunda fila deja intacta la primera', (tester) async {
      final anfitrion = await montar(
        tester,
        tablaDeFamiliares(),
        inicial: [
          {'nombres': 'Ana'},
          {'nombres': 'Luis'},
        ],
      );

      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pump();

      expect(anfitrion.ultimo, [
        {'nombres': 'Ana'},
      ]);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Luis'), findsNothing);
    });
  });

  group('layout a 375 px', () {
    const movil = Size(375, 812);

    testWidgets('ningún tipo desborda en móvil', (tester) async {
      // Un `RenderFlex overflowed` lanza en un widget test. El recorte silencioso
      // —el que produjo el bug del desplegable de cursos— **no** lanza, así que
      // esta prueba no lo cubre: para eso están las claves explícitas
      // (`isExpanded`, `maxLines: 1`) del propio widget.
      final tipos = <TipoCampoInscripcion, CampoInscripcion>{
        TipoCampoInscripcion.texto: campo(
          'primer_nombre',
          etiqueta: 'Primer nombre',
          tipo: TipoCampoInscripcion.texto,
        ),
        TipoCampoInscripcion.email: campo(
          'email',
          etiqueta: 'Correo electrónico',
          tipo: TipoCampoInscripcion.email,
        ),
        TipoCampoInscripcion.numero: campo(
          'hijos',
          etiqueta: 'Número de hijos',
          tipo: TipoCampoInscripcion.numero,
        ),
        TipoCampoInscripcion.fecha: campo(
          'fecha_nac',
          etiqueta: 'Fecha de nacimiento',
          tipo: TipoCampoInscripcion.fecha,
        ),
        TipoCampoInscripcion.booleano: campo(
          'discapacidad',
          etiqueta: '¿Tiene alguna diversidad funcional?',
          tipo: TipoCampoInscripcion.booleano,
        ),
        TipoCampoInscripcion.seleccion: campo(
          'curso_seleccionado',
          etiqueta: 'Propuesta formativa a cursar',
          tipo: TipoCampoInscripcion.seleccion,
          opciones: const {
            'opciones': [
              {'valor': 'a', 'etiqueta': 'Higiene y Manipulación de Alimentos'},
              {'valor': 'b', 'etiqueta': 'Estética (cejas y pestañas)'},
            ],
          },
        ),
        TipoCampoInscripcion.multiseleccion: campo(
          'tipo_discapacidad',
          etiqueta: 'Tipo de diversidad funcional',
          tipo: TipoCampoInscripcion.multiseleccion,
          opciones: const {
            'opciones': [
              {'valor': 'FISICA_MANO', 'etiqueta': 'Física (mano)'},
              {'valor': 'FISICA_PIERNAS', 'etiqueta': 'Física (piernas)'},
              {'valor': 'SENSORIAL_AUDITIVA', 'etiqueta': 'Sensorial auditiva'},
              {'valor': 'SENSORIAL_CEGUERA', 'etiqueta': 'Sensorial (ceguera)'},
              {'valor': 'DEBILIDAD_INTELECTUAL', 'etiqueta': 'Debilidad intelectual'},
            ],
          },
        ),
        TipoCampoInscripcion.rejilla: campo(
          'misiones',
          etiqueta: 'Misiones a las que pertenece',
          tipo: TipoCampoInscripcion.rejilla,
          opciones: const {
            'etiqueta_desde': 'Desde',
            'multiple': true,
            'items': [
              {'valor': 'RIBAS', 'etiqueta': 'Ribas'},
              {'valor': 'MADRES_DEL_BARRIO', 'etiqueta': 'Madres del Barrio'},
              {'valor': 'GM_VIVIENDA_VZLA', 'etiqueta': 'Gran Misión Vivienda Venezuela'},
            ],
          },
        ),
        TipoCampoInscripcion.tabla: campo(
          'familiares',
          etiqueta: 'Familiares',
          tipo: TipoCampoInscripcion.tabla,
          opciones: const {
            'columnas': [
              {'codigo': 'cedula', 'etiqueta': 'Cédula', 'tipo': 'texto', 'obligatorio': true},
              {'codigo': 'nombres', 'etiqueta': 'Nombres', 'tipo': 'texto', 'obligatorio': true},
              {
                'codigo': 'parentesco',
                'etiqueta': 'Parentesco',
                'tipo': 'seleccion',
                'opciones': [
                  {'valor': 'MADRE', 'etiqueta': 'Madre'},
                ],
              },
            ],
          },
        ),
      };

      // Los nueve tipos del contrato tienen que estar cubiertos: si alguien añade
      // uno y no lo mete aquí, esta prueba pasaría sin haberlo mirado.
      expect(tipos.keys.toSet(), TipoCampoInscripcion.values.toSet());

      for (final entrada in tipos.entries) {
        // Y el campo tiene que ser del tipo que dice la clave. Sin esto, un
        // `campo('email', ...)` sin `tipo: email` se pintaría como texto y la
        // prueba daría verde sobre un tipo que no comprobó —que es exactamente lo
        // que pasó la primera vez que se escribió esta tabla—.
        expect(
          entrada.value.tipo,
          entrada.key,
          reason: 'la entrada de ${entrada.key.name} no es de ese tipo',
        );

        await montar(tester, entrada.value, tamano: movil);
        sinDesbordes(tester, entrada.key.name, movil);
      }
    });

    testWidgets('la rejilla con un ítem marcado tampoco desborda en móvil', (tester) async {
      // El caso que de verdad puede desbordar: al marcar aparece el campo
      // «desde» al lado del rótulo, y los dos comparten una fila de 375 px.
      final anfitrion = await montar(
        tester,
        campo(
          'misiones',
          etiqueta: 'Misiones a las que pertenece',
          tipo: TipoCampoInscripcion.rejilla,
          opciones: const {
            'etiqueta_desde': 'Desde',
            'multiple': true,
            'items': [
              {'valor': 'GM_VIVIENDA_VZLA', 'etiqueta': 'Gran Misión Vivienda Venezuela'},
            ],
          },
        ),
        tamano: movil,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect((anfitrion.ultimo as Map).keys, ['GM_VIVIENDA_VZLA']);
      sinDesbordes(tester, 'rejilla marcada', movil);
    });

    testWidgets('la tabla con una fila tampoco desborda en móvil', (tester) async {
      await montar(
        tester,
        campo(
          'familiares',
          etiqueta: 'Familiares',
          tipo: TipoCampoInscripcion.tabla,
          opciones: const {
            'columnas': [
              {'codigo': 'cedula', 'etiqueta': 'Cédula', 'tipo': 'texto', 'obligatorio': true},
              {'codigo': 'nombres', 'etiqueta': 'Nombres', 'tipo': 'texto', 'obligatorio': true},
              {'codigo': 'parentesco', 'etiqueta': 'Parentesco', 'tipo': 'texto'},
              {'codigo': 'diversidad', 'etiqueta': 'Diversidad funcional', 'tipo': 'texto'},
            ],
          },
        ),
        inicial: [
          <String, dynamic>{},
        ],
        tamano: movil,
      );

      await tester.pumpAndSettle();
      sinDesbordes(tester, 'tabla con una fila', movil);
    });
  });
}

/// Anfitrión con estado: imita a la pantalla, que guarda la planilla en un mapa
/// y pasa cada valor hacia abajo.
class _Anfitrion extends StatefulWidget {
  const _Anfitrion({
    super.key,
    required this.campo,
    this.inicial,
    this.opciones,
  });

  final CampoInscripcion campo;
  final Object? inicial;
  final List<OpcionCampo>? opciones;

  @override
  State<_Anfitrion> createState() => _AnfitrionState();
}

class _AnfitrionState extends State<_Anfitrion> {
  Object? valor;

  @override
  void initState() {
    super.initState();
    valor = widget.inicial;
  }

  /// Lo último que subió el campo.
  Object? get ultimo => valor;

  @override
  Widget build(BuildContext context) {
    return CampoPlanilla(
      campo: widget.campo,
      valor: valor,
      opciones: widget.opciones,
      onCambio: (v) => setState(() => valor = v),
    );
  }
}
