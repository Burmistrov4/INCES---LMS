import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/models/inscripcion_campo.dart';

/// El catálogo de la planilla: lectura, agrupación, visibilidad condicional y la
/// síntesis de las claves planas.
///
/// Esta suite no necesita ni red ni base de datos, y es la que fija las
/// decisiones que el resto del formulario da por hechas. La más importante es la
/// última: `sintetizarClavesPlanas`, porque su fallo es **silencioso** —la ficha
/// de aspirante no se crea y nadie recibe un error—.
void main() {
  /// Un campo con los valores por defecto, para no repetir diez claves por caso.
  CampoInscripcion campo(
    String codigo, {
    String? etiqueta,
    String grupo = 'Datos personales',
    TipoCampoInscripcion tipo = TipoCampoInscripcion.texto,
    bool obligatorio = false,
    int orden = 0,
    Map<String, dynamic>? opciones,
    String? fuente,
    Map<String, dynamic>? condicion,
    String? ayuda,
  }) {
    return CampoInscripcion(
      codigo: codigo,
      etiqueta: etiqueta ?? codigo,
      grupo: grupo,
      tipo: tipo,
      orden: orden,
      obligatorio: obligatorio,
      opciones: opciones,
      fuente: fuente,
      condicion: condicion == null ? null : CondicionCampoInscripcion.fromJson(condicion),
      ayuda: ayuda,
    );
  }

  group('lectura del catálogo', () {
    test('lee un campo de texto con sus nulos', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'primer_nombre',
        'etiqueta': 'Primer nombre',
        'grupo': 'Datos personales',
        'tipo': 'texto',
        'obligatorio': true,
        'orden': 20,
        'opciones': null,
        'fuente': null,
        'condicion': null,
        'ayuda': null,
      });

      expect(leido.codigo, 'primer_nombre');
      expect(leido.tipo, TipoCampoInscripcion.texto);
      expect(leido.obligatorio, isTrue);
      expect(leido.orden, 20);
      expect(leido.opciones, isNull);
      expect(leido.fuente, isNull);
      expect(leido.condicion, isNull);
      expect(leido.tieneFuenteExterna, isFalse);
    });

    test('lee los nueve tipos que declara el contrato', () {
      // Si el backend añadiera un tipo y aquí no se reconociera, el campo caería
      // a `texto` en silencio. Esta prueba fija el acuerdo entre los dos lados.
      const esperados = [
        'texto',
        'email',
        'numero',
        'fecha',
        'seleccion',
        'multiseleccion',
        'booleano',
        'tabla',
        'rejilla',
      ];

      for (final nombre in esperados) {
        expect(
          TipoCampoInscripcion.desde(nombre),
          isNotNull,
          reason: 'el tipo $nombre debería reconocerse',
        );
      }
      expect(TipoCampoInscripcion.values, hasLength(esperados.length));
    });

    test('un tipo desconocido cae a texto en vez de reventar', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'campo_del_futuro',
        'tipo': 'geo',
        'orden': 1,
      });

      expect(leido.tipo, TipoCampoInscripcion.texto);
    });

    test('lee las opciones de un seleccion', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'nacionalidad',
        'tipo': 'seleccion',
        'orden': 70,
        'opciones': {
          'opciones': [
            {'valor': 'V', 'etiqueta': 'Venezolano/a'},
            {'valor': 'E', 'etiqueta': 'Extranjero/a'},
          ],
        },
      });

      expect(leido.opcionesCerradas, hasLength(2));
      expect(leido.opcionesCerradas.first.valor, 'V');
      expect(leido.opcionesCerradas.first.etiqueta, 'Venezolano/a');
    });

    test('una opción sin etiqueta usa su valor, para no pintar una casilla vacía', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'x',
        'tipo': 'seleccion',
        'orden': 1,
        'opciones': {
          'opciones': [
            {'valor': 'SI'},
          ],
        },
      });

      expect(leido.opcionesCerradas.single.etiqueta, 'SI');
    });

    test('lee una rejilla con su rótulo «desde»', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'misiones',
        'tipo': 'rejilla',
        'orden': 320,
        'opciones': {
          'etiqueta_desde': 'Desde',
          'multiple': true,
          'items': [
            {'valor': 'RIBAS', 'etiqueta': 'Ribas'},
            {'valor': 'MERCAL', 'etiqueta': 'Mercal'},
          ],
        },
      });

      expect(leido.itemsRejilla, hasLength(2));
      expect(leido.etiquetaDesde, 'Desde');
      expect(leido.multiple, isTrue);
    });

    test('lee las columnas de una tabla, con su tipo y su obligatoriedad', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'familiares',
        'tipo': 'tabla',
        'orden': 310,
        'opciones': {
          'columnas': [
            {'codigo': 'cedula', 'etiqueta': 'Cédula', 'tipo': 'texto', 'obligatorio': true},
            {'codigo': 'genero', 'etiqueta': 'Género', 'tipo': 'seleccion', 'obligatorio': false, 'opciones': [
              {'valor': 'F', 'etiqueta': 'Femenino'},
            ]},
          ],
        },
      });

      expect(leido.columnasTabla, hasLength(2));
      expect(leido.columnasTabla.first.codigo, 'cedula');
      expect(leido.columnasTabla.first.tipo, TipoCampoInscripcion.texto);
      expect(leido.columnasTabla.first.obligatorio, isTrue);
      expect(leido.columnasTabla[1].tipo, TipoCampoInscripcion.seleccion);
      expect(leido.columnasTabla[1].opciones.single.valor, 'F');
    });

    test('una opción sin `multiple` se considera múltiple', () {
      // El catálogo sólo escribe `multiple` cuando es `true`; ausente significa
      // «varios». Leerlo al revés dejaría la rejilla de misiones en mono-selección
      // sin que nada fallara.
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'misiones',
        'tipo': 'rejilla',
        'orden': 320,
        'opciones': {'items': []},
      });

      expect(leido.multiple, isTrue);
    });

    test('lee una condición de visibilidad', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'pueblo_indigena_cual',
        'tipo': 'texto',
        'orden': 120,
        'condicion': {'campo': 'pueblo_indigena', 'igual': true},
      });

      expect(leido.condicion, isNotNull);
      expect(leido.condicion!.campo, 'pueblo_indigena');
      expect(leido.condicion!.igual, isTrue);
    });

    test('lee la fuente externa de las opciones', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'curso_seleccionado',
        'tipo': 'seleccion',
        'orden': 440,
        'fuente': 'programas',
      });

      expect(leido.tieneFuenteExterna, isTrue);
      expect(leido.fuente, 'programas');
      expect(leido.opcionesCerradas, isEmpty);
    });

    test('una fuente vacía no cuenta como fuente externa', () {
      final leido = CampoInscripcion.fromJson(const {
        'codigo': 'x',
        'tipo': 'texto',
        'orden': 1,
        'fuente': '',
      });

      expect(leido.tieneFuenteExterna, isFalse);
    });
  });

  group('agrupación en pasos', () {
    test('agrupa por `grupo` y respeta el orden global', () {
      // El orden de los grupos es el de aparición de su primer campo, no el
      // alfabeto: reordenar el catálogo tiene que reordenar los pasos.
      final catalogo = CatalogoInscripcion([
        campo('b', grupo: 'Zeta', orden: 10),
        campo('a', grupo: 'Alfa', orden: 20),
        campo('c', grupo: 'Zeta', orden: 30),
      ]);

      final grupos = catalogo.grupos;

      expect(grupos.map((g) => g.nombre).toList(), ['Zeta', 'Alfa']);
      expect(grupos.first.campos.map((c) => c.codigo).toList(), ['b', 'c']);
      expect(grupos[1].campos.single.codigo, 'a');
    });

    test('ordena los campos dentro del grupo por `orden`, no por llegada', () {
      final catalogo = CatalogoInscripcion([
        campo('tercero', orden: 30),
        campo('primero', orden: 10),
        campo('segundo', orden: 20),
      ]);

      expect(
        catalogo.grupos.single.campos.map((c) => c.codigo).toList(),
        ['primero', 'segundo', 'tercero'],
      );
    });

    test('un campo sin grupo cae en «Otros» en vez de perderse', () {
      // Un campo sin grupo que desapareciera sería un campo que el aspirante no
      // puede rellenar y que la base exige: un formulario imposible de enviar.
      final catalogo = CatalogoInscripcion([campo('suelto', grupo: '', orden: 1)]);

      expect(catalogo.grupos.single.nombre, 'Otros');
    });

    test('porCodigo encuentra un campo y devuelve null si no está', () {
      final catalogo = CatalogoInscripcion([campo('cedula', orden: 1)]);

      expect(catalogo.porCodigo('cedula')?.codigo, 'cedula');
      expect(catalogo.porCodigo('no_existe'), isNull);
    });

    test('un catálogo vacío no tiene grupos, y no revienta', () {
      const catalogo = CatalogoInscripcion([]);

      expect(catalogo.grupos, isEmpty);
    });
  });

  group('visibilidad y obligatoriedad condicional', () {
    final dependiente = campo(
      'pueblo_indigena_cual',
      orden: 120,
      condicion: const {'campo': 'pueblo_indigena', 'igual': true},
    );

    test('un campo sin condición siempre es visible', () {
      expect(campo('cedula').visibleCon(const {}), isTrue);
    });

    test('el dependiente no se ve hasta que la casilla está marcada', () {
      expect(dependiente.visibleCon(const {}), isFalse);
      expect(dependiente.visibleCon(const {'pueblo_indigena': false}), isFalse);
      expect(dependiente.visibleCon(const {'pueblo_indigena': true}), isTrue);
    });

    test('un campo oculto no se exige, aunque el catálogo lo marque obligatorio', () {
      // No se puede rellenar lo que no se ve. Ojo: `validar_planilla()` **no lee
      // `condicion`**, así que marcar como obligatorio un campo condicional sería
      // una incoherencia del catálogo. Hoy no hay ninguno en ese caso.
      final condicionalObligatorio = campo(
        'dependiente',
        obligatorio: true,
        condicion: const {'campo': 'dispara', 'igual': true},
      );

      expect(condicionalObligatorio.obligatorioCon(const {'dispara': false}), isFalse);
      expect(condicionalObligatorio.obligatorioCon(const {'dispara': true}), isTrue);
    });

    test('la condición también acepta comparaciones que no son booleanas', () {
      final porValor = campo(
        'detalle',
        condicion: const {'campo': 'tipo', 'igual': 'OTRO'},
      );

      expect(porValor.visibleCon(const {'tipo': 'OTRO'}), isTrue);
      expect(porValor.visibleCon(const {'tipo': 'ALGO'}), isFalse);
    });

    test('`igual: 1` cuenta como sí, para que una casilla marcada no la oculte', () {
      final conUno = campo('detalle', condicion: const {'campo': 'dispara', 'igual': 1});

      expect(conUno.visibleCon(const {'dispara': true}), isTrue);
    });
  });

  group('valorDeCampoVacio', () {
    test('ausente, nulo y blanco están vacíos', () {
      expect(valorDeCampoVacio(null), isTrue);
      expect(valorDeCampoVacio(''), isTrue);
      expect(valorDeCampoVacio('   '), isTrue);
      expect(valorDeCampoVacio(<String>[]), isTrue);
      expect(valorDeCampoVacio(<String, dynamic>{}), isTrue);
    });

    test('`false` y `0` NO están vacíos', () {
      // Es la mitad que se olvida. «¿Tiene alguna diversidad funcional?» con
      // respuesta `false` es una respuesta, no una ausencia, y escribir esto como
      // `if (!valor)` la rechazaría.
      expect(valorDeCampoVacio(false), isFalse);
      expect(valorDeCampoVacio(0), isFalse);
      expect(valorDeCampoVacio(0.0), isFalse);
    });

    test('un valor con contenido no está vacío', () {
      expect(valorDeCampoVacio('Lorenzo'), isFalse);
      expect(valorDeCampoVacio(<String>['RIBAS']), isFalse);
    });
  });

  group('síntesis de las claves planas', () {
    test('concatena el nombre desglosado en `nombres` y `apellidos`', () {
      // Es la prueba que existe por el fallo silencioso de `202609240001`: sin
      // `nombres`, el trigger deja `v_nombres` en NULL, la condición
      // `v_es_aspirante` falla y **la ficha no se crea, sin error**.
      final planas = sintetizarClavesPlanas(const {
        'primer_nombre': 'Lorenzo',
        'segundo_nombre': 'José',
        'primer_apellido': 'Roca',
        'segundo_apellido': 'Pérez',
      });

      expect(planas['nombres'], 'Lorenzo José');
      expect(planas['apellidos'], 'Roca Pérez');
    });

    test('un segundo nombre ausente no deja un espacio de más', () {
      // Equivale al `btrim(a || ' ' || b)` del trigger: si se concatenara a lo
      // bruto, «Lorenzo » con espacio final viajaría a la base.
      final planas = sintetizarClavesPlanas(const {
        'primer_nombre': 'Lorenzo',
        'primer_apellido': 'Roca',
      });

      expect(planas['nombres'], 'Lorenzo');
      expect(planas['apellidos'], 'Roca');
    });

    test('un segundo nombre en blanco tampoco deja espacios', () {
      final planas = sintetizarClavesPlanas(const {
        'primer_nombre': 'Lorenzo',
        'segundo_nombre': '   ',
        'primer_apellido': 'Roca',
        'segundo_apellido': '',
      });

      expect(planas['nombres'], 'Lorenzo');
      expect(planas['apellidos'], 'Roca');
    });

    test('recorta los espacios de los extremos', () {
      final planas = sintetizarClavesPlanas(const {
        'primer_nombre': '  Lorenzo  ',
        'primer_apellido': ' Roca ',
      });

      expect(planas['nombres'], 'Lorenzo');
      expect(planas['apellidos'], 'Roca');
    });

    test('sin nombres, las claves quedan vacías y no ausentes', () {
      // Vacías y no ausentes: el trigger lee `->>` y una clave ausente da `null`,
      // que es lo mismo que un vacío para `v_es_aspirante`. Se mantienen las dos
      // claves para que el payload tenga siempre la misma forma.
      final planas = sintetizarClavesPlanas(const {'cedula': '123'});

      expect(planas['nombres'], '');
      expect(planas['apellidos'], '');
    });

    test('copia las claves que coinciden con las del trigger', () {
      final planas = sintetizarClavesPlanas(const {
        'cedula': '12345678',
        'sexo': 'F',
        'fecha_nac': '2003-05-14',
        'telefono': '04141234567',
        'direccion': 'Calle 1',
        'nivel_educativo': 'SECUNDARIO',
        'curso_seleccionado': 'Herrería',
        'discapacidad': true,
        'numero_identidad_tutor': '87654321',
        'nombre_tutor': 'Ana Pérez',
        'parentesco_tutor': 'MADRE',
        'telefono_tutor': '04149876543',
        'correo_tutor': 'ana@example.com',
      });

      expect(planas['cedula'], '12345678');
      expect(planas['sexo'], 'F');
      expect(planas['fecha_nac'], '2003-05-14');
      expect(planas['nivel_educativo'], 'SECUNDARIO');
      expect(planas['curso_seleccionado'], 'Herrería');
      expect(planas['discapacidad'], isTrue);
      expect(planas['parentesco_tutor'], 'MADRE');
      expect(planas['correo_tutor'], 'ana@example.com');
    });

    test('NO sintetiza `mision_ribaras`: la rejilla lo sustituye', () {
      // La decisión de la pantalla nueva: la rejilla `misiones` viaja dentro de
      // la planilla y el campo de texto libre deja de enviarse. Duplicar el dato
      // en dos claves con formas distintas sólo serviría para que un día
      // discrepen.
      final planas = sintetizarClavesPlanas(const {
        'misiones': ['RIBAS', 'MERCAL'],
      });

      expect(planas.containsKey('mision_ribaras'), isFalse);
      expect(planas.containsKey('misiones'), isFalse);
    });

    test('no arrastra campos del catálogo que el trigger no lee', () {
      // `raw_user_meta_data` tiene un límite real de tamaño: mandar los 44 campos
      // cuando el trigger lee 17 es engordar la fila de `auth.users` para nada.
      final planas = sintetizarClavesPlanas(const {
        'primer_nombre': 'Lorenzo',
        'estado_civil': 'SOLTERO',
        'deporte': 'Fútbol',
        'twitter': '@alguien',
        'familiares': [
          {'cedula': '1'},
        ],
      });

      expect(planas.containsKey('estado_civil'), isFalse);
      expect(planas.containsKey('deporte'), isFalse);
      expect(planas.containsKey('twitter'), isFalse);
      expect(planas.containsKey('familiares'), isFalse);
    });

    test('las claves con valor nulo no se mandan', () {
      final planas = sintetizarClavesPlanas(const {
        'cedula': '123',
        'telefono': null,
      });

      expect(planas.containsKey('telefono'), isFalse);
    });

    test('un valor `false` sí se manda: es una respuesta', () {
      final planas = sintetizarClavesPlanas(const {'discapacidad': false});

      expect(planas.containsKey('discapacidad'), isTrue);
      expect(planas['discapacidad'], isFalse);
    });
  });
}
