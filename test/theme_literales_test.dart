import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Impide que vuelva a aparecer un color escrito a mano **fuera del tema**.
///
/// ## El fallo que esto previene
///
/// `IncesTheme` decía en su cabecera, desde el primer día, que existía «para que
/// ninguna pantalla invente sus propios colores». Y aun así había **83 literales
/// hexadecimales en 10 archivos**, con un resultado medido: 1.18:1, 1.22:1,
/// 2.45:1 y 1.42:1, o sea texto que no se lee. La regla estaba escrita y no se
/// cumplía porque **nada la comprobaba**. Este archivo la comprueba.
///
/// ## Qué se prohíbe, exactamente
///
/// 1. **`Color(0x…)` fuera de `lib/theme/inces_theme.dart`.** Es la forma que
///    tuvo el problema: un hexadecimal es un color fijo, y un color fijo sólo
///    puede ser correcto en uno de los dos temas.
/// 2. **`fillColor: Colors.white` fuera del tema.** Es la forma exacta del
///    1.18:1: el relleno casi blanco del campo mientras el texto lo ponía el
///    `ColorScheme` oscuro.
/// 3. **Ningún `Colors.` en la familia del formulario** (`campos_planilla/`),
///    que es la que se migró entera.
///
/// ## Qué NO se prohíbe, y por qué decirlo
///
/// `Colors.white` como **color de primer plano** sobre una superficie saturada
/// —el texto de un botón primario, el de un degradado de marca— **no** se
/// prohíbe: ahí el color correcto es el `onPrimary` del `ColorScheme`, y el
/// blanco coincide con él. Prohibirlo entero obligaría a una lista de excepciones
/// con trece archivos dentro, que es una regla sin regla. Lo que este archivo
/// cubre es la clase de fallo que se midió, no «todo color que no salga del
/// tema»; una prueba que promete más de lo que comprueba es peor que ninguna.
///
/// ## Por qué el escáner quita los comentarios antes de buscar
///
/// Los comentarios de este proyecto **citan** los colores que explican, y varios
/// dicen `Colors.white` o `#F8FAFC` a propósito. Buscar sin quitarlos daría rojos
/// falsos, y un verificador que da rojos falsos se acaba ignorando. El quitado
/// respeta las cadenas de texto —una URL con `//` no es un comentario— y conserva
/// las líneas, para que el mensaje de fallo diga el número correcto.
void main() {
  // Se lee una sola vez: es un centenar largo de archivos y cada grupo los
  // necesita. El número exacto **no se escribe a propósito**: envejece con cada
  // archivo que se añade y convierte este comentario en una afirmación falsa que
  // hay que venir a corregir. Decía «117» y eran 120. La guardia de abajo ya
  // comprueba que se ven más de cien, que es lo que de verdad importa.
  final archivos = _archivosDart('lib');

  group('el escáner mira de verdad', () {
    // Sin esto, un fallo de ruta dejaría los tres grupos de abajo en verde
    // habiendo mirado cero archivos. Un verde que sale de no mirar es peor que un
    // rojo, porque nadie lo revisa.
    test('encuentra los archivos de lib/', () {
      expect(
        archivos.length,
        greaterThan(100),
        reason: 'si el escáner no ve el código, sus verdes no valen nada',
      );
    });

    test('ve el tema y sabe que ahí sí hay hexadecimales', () {
      final tema = archivos[_rutaTema];
      expect(tema, isNotNull, reason: 'falta $_rutaTema');
      expect(
        _sinComentarios(tema!).contains('Color(0x'),
        isTrue,
        reason: 'el tema es donde los colores se declaran: si aquí no se ve '
            'ninguno, el quitado de comentarios se está comiendo el código',
      );
    });

    test('quita comentarios sin comerse las cadenas de texto', () {
      const fuente = '''
// Color(0xFF000000) en una línea comentada
const url = 'https://ejemplo.test/a';
/// Color(0xFF111111) en documentación
final x = Color(0xFF222222);
''';
      final limpio = _sinComentarios(fuente);
      expect(limpio.contains('0xFF000000'), isFalse, reason: 'comentario de línea');
      expect(limpio.contains('0xFF111111'), isFalse, reason: 'comentario de documentación');
      expect(limpio.contains('0xFF222222'), isTrue, reason: 'el código se conserva');
      expect(limpio.contains('https://ejemplo.test/a'), isTrue,
          reason: 'una URL dentro de una cadena no abre un comentario');
      expect(limpio.split('\n').length, fuente.split('\n').length,
          reason: 'las líneas se conservan para que el número del fallo sea el real');
    });
  });

  group('ningún hexadecimal fuera del tema', () {
    test('lib/ entero, salvo las excepciones declaradas', () {
      final culpables = <String>[];
      final contadas = <String, int>{};

      archivos.forEach((ruta, fuente) {
        if (ruta == _rutaTema) return;

        final lineas = _sinComentarios(fuente).split('\n');
        for (var i = 0; i < lineas.length; i++) {
          if (!lineas[i].contains('Color(0x')) continue;
          contadas[ruta] = (contadas[ruta] ?? 0) + 1;
          culpables.add('$ruta:${i + 1}  ${lineas[i].trim()}');
        }
      });

      // Cada excepción se declara con su motivo **y con cuántas se permiten**: si
      // aparece un segundo velo en el mismo archivo, esto también lo dice.
      final permitidas = <String, int>{};
      _excepciones.forEach((ruta, excepcion) {
        permitidas[ruta] = excepcion.cuantas;
      });

      final sinPermiso = <String>[];
      for (final entrada in contadas.entries) {
        final tope = permitidas[entrada.key] ?? 0;
        if (entrada.value > tope) sinPermiso.add(entrada.key);
      }

      expect(
        sinPermiso,
        isEmpty,
        reason: 'hay hexadecimales sin declarar en: ${sinPermiso.join(', ')}.\n'
            'Un color fijo sólo puede ser correcto en un tema. Si el color es de '
            'verdad un rol, decláralo en `PaletaInces` (o en `IncesTheme` si no '
            'depende del brillo) y léelo de ahí.\n'
            'Encontrados:\n${culpables.join('\n')}',
      );
    });

    test('las excepciones siguen siendo ciertas', () {
      // Una lista de excepciones que nadie revisa se llena de entradas muertas y
      // acaba tapando lo que debía vigilar. Cada una tiene que seguir usándose.
      _excepciones.forEach((ruta, excepcion) {
        final fuente = archivos[ruta];
        expect(fuente, isNotNull, reason: '$ruta ya no existe: sobra la excepción');
        final cuantas = _sinComentarios(fuente!).split('Color(0x').length - 1;
        expect(
          cuantas,
          excepcion.cuantas,
          reason: '$ruta declara ${excepcion.cuantas} excepción(es) y tiene '
              '$cuantas. ${excepcion.motivo}',
        );
      });
    });
  });

  group('ningún relleno blanco escrito a mano', () {
    test('fillColor: Colors.white fuera del tema', () {
      final culpables = <String>[];

      archivos.forEach((ruta, fuente) {
        if (ruta == _rutaTema) return;
        final lineas = _sinComentarios(fuente).split('\n');
        for (var i = 0; i < lineas.length; i++) {
          if (lineas[i].replaceAll(' ', '').contains('fillColor:Colors.white')) {
            culpables.add('$ruta:${i + 1}');
          }
        }
      });

      expect(
        culpables,
        isEmpty,
        reason: 'un campo relleno de blanco fijo deja el texto del tema oscuro '
            'sobre casi blanco: es el 1.18:1 medido. Usa '
            '`PaletaInces.rellenoDeCampo`. Encontrados: ${culpables.join(', ')}',
      );
    });
  });

  group('la familia del formulario está entera en la paleta', () {
    // `campos_planilla/` es lo que se migró de punta a punta, así que aquí sí se
    // puede exigir el cero absoluto. Fuera de esta carpeta no se exige —ver la
    // cabecera del archivo—.
    const carpeta = 'lib/widgets/campos_planilla/';

    archivos.forEach((ruta, fuente) {
      if (!ruta.startsWith(carpeta)) return;

      test('${ruta.substring(carpeta.length)} no usa Colors.', () {
        final codigo = _sinComentarios(fuente);
        final usos = <String>[];
        final lineas = codigo.split('\n');
        for (var i = 0; i < lineas.length; i++) {
          if (lineas[i].contains('Colors.')) {
            usos.add('${i + 1}: ${lineas[i].trim()}');
          }
        }

        expect(
          usos,
          isEmpty,
          reason: 'esta carpeta se migró a `PaletaInces`; un `Colors.` aquí es '
              'un color que vuelve a decidirse fuera del tema:\n${usos.join('\n')}',
        );
      });
    });

    test('la carpeta existe y tiene los archivos que se migraron', () {
      final deLaCarpeta =
          archivos.keys.where((r) => r.startsWith(carpeta)).toList();
      expect(
        deLaCarpeta.length,
        greaterThanOrEqualTo(4),
        reason: 'se migraron cuatro archivos de campos; si la carpeta se movió, '
            'esta comprobación dejaría de mirar nada',
      );
    });
  });
}

/// El tema es el único sitio donde un color se declara.
const String _rutaTema = 'lib/theme/inces_theme.dart';

/// Los hexadecimales que se quedan, cada uno con su motivo y su tope.
///
/// Son **uno**: el velo del visor de la cámara. No es un color del tema ni un
/// rol: es una sombra que se pinta sobre un lienzo y que tiene que ser negra
/// translúcida sobre lo que la cámara esté viendo, sea claro u oscuro. Un rol de
/// la paleta sería mentira —no depende del brillo del tema, depende del vídeo—.
const Map<String, _Excepcion> _excepciones = {
  'lib/screens/aspirante/escaner_qr_screen.dart': _Excepcion(
    cuantas: 1,
    motivo: 'el velo translúcido del visor de la cámara: se pinta sobre el '
        'vídeo, no sobre el tema',
  ),
};

class _Excepcion {
  const _Excepcion({required this.cuantas, required this.motivo});

  final int cuantas;
  final String motivo;
}

/// Todos los `.dart` de [raiz], con la ruta normalizada a `/`.
Map<String, String> _archivosDart(String raiz) {
  final resultado = <String, String>{};
  final directorio = Directory(raiz);
  if (!directorio.existsSync()) return resultado;

  for (final entidad in directorio.listSync(recursive: true)) {
    if (entidad is! File || !entidad.path.endsWith('.dart')) continue;
    final ruta = entidad.path.replaceAll('\\', '/');
    resultado[ruta] = entidad.readAsStringSync();
  }
  return resultado;
}

/// Devuelve [fuente] sin comentarios, conservando el número de líneas.
///
/// Se recorre carácter a carácter en vez de usar una expresión regular porque hay
/// cadenas de texto que contienen `//` —cualquier URL— y cortarlas por ahí
/// escondería el código que viniera detrás en esa misma línea. Esconder código es
/// el único error que un verificador no se puede permitir.
String _sinComentarios(String fuente) {
  final salida = StringBuffer();
  var i = 0;

  // Estados: fuera de todo, dentro de una cadena, o dentro de un comentario.
  while (i < fuente.length) {
    final c = fuente[i];
    final siguiente = i + 1 < fuente.length ? fuente[i + 1] : '';

    // Comentario de bloque: se sustituye por espacios y se respetan los saltos.
    if (c == '/' && siguiente == '*') {
      i += 2;
      while (i < fuente.length &&
          !(fuente[i] == '*' && i + 1 < fuente.length && fuente[i + 1] == '/')) {
        salida.write(fuente[i] == '\n' ? '\n' : ' ');
        i++;
      }
      i += 2;
      continue;
    }

    // Comentario de línea.
    if (c == '/' && siguiente == '/') {
      while (i < fuente.length && fuente[i] != '\n') {
        salida.write(' ');
        i++;
      }
      continue;
    }

    // Cadena con comillas triples: puede contener saltos de línea.
    if ((c == "'" || c == '"') && fuente.startsWith(c * 3, i)) {
      final cierre = c * 3;
      salida.write(cierre);
      i += 3;
      while (i < fuente.length && !fuente.startsWith(cierre, i)) {
        salida.write(fuente[i]);
        i++;
      }
      if (i < fuente.length) {
        salida.write(cierre);
        i += 3;
      }
      continue;
    }

    // Cadena normal: se copia tal cual, respetando el escape de la barra.
    if (c == "'" || c == '"') {
      salida.write(c);
      i++;
      while (i < fuente.length && fuente[i] != c) {
        if (fuente[i] == '\\' && i + 1 < fuente.length) {
          salida.write(fuente[i]);
          i++;
        }
        salida.write(fuente[i]);
        i++;
      }
      if (i < fuente.length) {
        salida.write(fuente[i]);
        i++;
      }
      continue;
    }

    salida.write(c);
    i++;
  }

  return salida.toString();
}
