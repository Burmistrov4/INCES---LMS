import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/theme/inces_theme.dart';

/// Verifica **numéricamente** que [PaletaInces] cumple WCAG AA en los dos brillos.
///
/// ## Por qué este archivo existe
///
/// Los fallos de contraste del proyecto no se vieron porque ninguna prueba podía
/// verlos: `test/support/formulario_inscripcion.dart` monta el formulario con
/// `IncesTheme.claro()` y nada más, así que el modo oscuro —que nadie había
/// escrito, salió de literales de modo claro— no lo ejercía **ninguna** prueba.
/// Medido el 2026-09-30: 1.18:1, 1.22:1, 2.45:1, 1.42:1.
///
/// Montar el árbol de widgets en los dos temas habría hecho falta para comprobar
/// los píxeles; comprobar la **paleta** no hace falta. Un contraste es una
/// función de dos colores, y los colores ya están declarados: aquí se calculan
/// los pares que el diseño promete y se exige el mínimo de cada uno. Es la
/// comprobación que sí se puede hacer en esta máquina —`flutter test` corre
/// entero en CI, pero el cálculo es puro y no necesita ni un widget—.
///
/// ## Qué se exige, y por qué dos mínimos distintos
///
/// - **4.5:1** para texto (WCAG 1.4.3, nivel AA).
/// - **3:1** para el **límite de un control** y para un gráfico con significado
///   (WCAG 1.4.11). De ahí que el borde de un campo se mida contra su relleno y
///   contra la superficie: si el borde es lo único que delimita el campo, tiene
///   que verse contra las dos.
/// - El borde de una **tarjeta** no se mide a 3:1 a propósito: es decorativo y
///   WCAG no se lo pide. Se comprueba sólo que no sea invisible, que es una
///   afirmación mucho más débil y por eso se escribe aparte.
void main() {
  group('contraste WCAG de PaletaInces', () {
    for (final brillo in Brightness.values) {
      final paleta = PaletaInces.deBrillo(brillo);
      final nombre = brillo == Brightness.light ? 'modo claro' : 'modo oscuro';

      group(nombre, () {
        // Todos los fondos sobre los que esta paleta puede dejar texto. Están los
        // tres porque el resumen del paso final pinta etiquetas sobre
        // `superficieSutil` y los campos escriben sobre `rellenoDeCampo`: medir
        // sólo contra `superficie` habría dejado pasar el 4.34:1.
        final fondos = <String, Color>{
          'superficie': paleta.superficie,
          'superficieSutil': paleta.superficieSutil,
          'rellenoDeCampo': paleta.rellenoDeCampo,
        };

        final textos = <String, Color>{
          'textoPrincipal': paleta.textoPrincipal,
          'textoSecundario': paleta.textoSecundario,
          'textoApagado': paleta.textoApagado,
          'enlace': paleta.enlace,
        };

        textos.forEach((nombreTexto, colorTexto) {
          fondos.forEach((nombreFondo, colorFondo) {
            _exigeContraste(
              '$nombreTexto sobre $nombreFondo',
              colorTexto,
              colorFondo,
              minimo: _textoAA,
              porque: 'es texto: WCAG 1.4.3 pide 4.5:1',
            );
          });
        });

        _exigeContraste(
          'bordeDeCampo sobre rellenoDeCampo',
          paleta.bordeDeCampo,
          paleta.rellenoDeCampo,
          minimo: _controlAA,
          porque: 'es el límite del campo: WCAG 1.4.11 pide 3:1',
        );
        _exigeContraste(
          'bordeDeCampo sobre superficie',
          paleta.bordeDeCampo,
          paleta.superficie,
          minimo: _controlAA,
          porque: 'el campo se apoya en la tarjeta: el borde debe verse contra '
              'las dos',
        );
        _exigeContraste(
          'aviso sobre superficie',
          paleta.aviso,
          paleta.superficie,
          minimo: _controlAA,
          porque: 'es un icono con significado: WCAG 1.4.11 pide 3:1',
        );
        _exigeContraste(
          'aviso sobre superficieSutil',
          paleta.aviso,
          paleta.superficieSutil,
          minimo: _controlAA,
          porque: 'el icono de error de catálogo puede caer sobre los dos fondos',
        );

        // El borde de una tarjeta, medido a la baja y a conciencia. Se declara
        // como comprobación propia para que quede escrito que **no** se le exige
        // 3:1: si algún día alguien lo sube a `_controlAA`, este test lo dirá con
        // su nombre.
        _exigeContraste(
          'borde sobre superficie (decorativo)',
          paleta.borde,
          paleta.superficie,
          minimo: 1.05,
          porque: 'un borde de tarjeta es decorativo: WCAG no le pide 3:1, sólo '
              'que no sea invisible',
        );
      });
    }
  });

  group('pares fijos del tema', () {
    // No dependen del brillo: son superficies saturadas con su propio
    // contenido encima. Si esto se rompe, el aviso rojo o el ámbar dejan de
    // leerse en un tema.
    //
    // El aviso flotante de error es el par que de verdad se pinta: fondo
    // `IncesTheme.error` y encima `sobreError`. Se mide porque el fallo original
    // **no** estaba en el fondo sino en que nadie declaraba el color del texto:
    // lo ponía Material con `onInverseSurface`, que en modo oscuro es oscuro, o
    // sea un aviso rojo con texto casi negro.
    _exigeContraste(
      'sobreError sobre error (el aviso flotante)',
      IncesTheme.sobreError,
      IncesTheme.error,
      minimo: _textoAA,
      porque: 'es el texto y el icono del aviso de error, sobre el rojo del tema',
    );
    _exigeContraste(
      'textoAdvertencia sobre superficieAdvertencia',
      IncesTheme.textoAdvertencia,
      IncesTheme.superficieAdvertencia,
      minimo: _textoAA,
      porque: 'es el texto del bloque de aviso de la oferta formativa',
    );
    _exigeContraste(
      'advertenciaFuerte sobre superficieAdvertencia',
      IncesTheme.advertenciaFuerte,
      IncesTheme.superficieAdvertencia,
      minimo: _controlAA,
      porque: 'es el icono dentro del bloque ámbar',
    );

    test('blanco sobre error pasa AA, y por eso no hay un rojo más oscuro', () {
      // Aquí hubo una prueba que afirmaba lo contrario —que este par fallaba— y
      // se equivocaba. La cifra se había calculado **a mano** y salió 4.41:1;
      // medida con el mismo instrumento que usa el resto del archivo, es 4.83:1.
      // CI la cazó: aquí `flutter test` no arranca. Se deja escrita la medición
      // para que nadie vuelva a añadir un rol que arregle un fallo inexistente.
      final blancoSobreError = _contraste(Colors.white, IncesTheme.error);
      expect(
        blancoSobreError,
        greaterThanOrEqualTo(_textoAA),
        reason: 'si algún día bajara de 4.5:1, sí haría falta oscurecer el fondo '
            'del aviso, y entonces habría que añadir el rol que hoy sobra',
      );
    });

    test('advertenciaFuerte NO sirve sobre la tarjeta oscura', () {
      // La segunda mitad del mismo argumento: el ámbar oscuro del bloque de aviso
      // no vale sobre la superficie de una tarjeta en modo oscuro, y por eso
      // `PaletaInces.aviso` tiene un valor por brillo. Medido: 2.91:1.
      final sobreOscura =
          _contraste(IncesTheme.advertenciaFuerte, IncesTheme.superficieOscura);
      expect(
        sobreOscura,
        lessThan(_controlAA),
        reason: 'si pasara 3:1, el rol `aviso` no haría falta',
      );

      // Y el rol que sí vale, medido aquí mismo para que los dos números queden
      // juntos: es la comparación la que explica la decisión.
      final avisoOscuro = _contraste(
        PaletaInces.deBrillo(Brightness.dark).aviso,
        IncesTheme.superficieOscura,
      );
      expect(avisoOscuro, greaterThanOrEqualTo(_controlAA));
    });
  });

  group('la paleta no puede colapsar a un solo juego de colores', () {
    // El error original fue exactamente éste: un literal sin condición sirviendo
    // a los dos temas, acertando en uno y fallando en el otro. Si un rol tiene el
    // mismo valor en claro y en oscuro, es que uno de los dos temas está mal —o
    // que el rol sobra—.
    final claro = PaletaInces.deBrillo(Brightness.light);
    final oscuro = PaletaInces.deBrillo(Brightness.dark);

    final roles = <String, List<Color>>{
      'textoPrincipal': [claro.textoPrincipal, oscuro.textoPrincipal],
      'textoSecundario': [claro.textoSecundario, oscuro.textoSecundario],
      'textoApagado': [claro.textoApagado, oscuro.textoApagado],
      'enlace': [claro.enlace, oscuro.enlace],
      'aviso': [claro.aviso, oscuro.aviso],
      'superficie': [claro.superficie, oscuro.superficie],
      'superficieSutil': [claro.superficieSutil, oscuro.superficieSutil],
      'borde': [claro.borde, oscuro.borde],
      'rellenoDeCampo': [claro.rellenoDeCampo, oscuro.rellenoDeCampo],
      'bordeDeCampo': [claro.bordeDeCampo, oscuro.bordeDeCampo],
    };

    roles.forEach((rol, valores) {
      test('$rol cambia con el brillo', () {
        expect(
          valores[0],
          isNot(valores[1]),
          reason: '$rol vale lo mismo en claro y en oscuro: un color que no '
              'distingue el brillo sólo puede ser correcto en uno de los dos',
        );
      });
    });

    test('el brillo declarado es el que se pidió', () {
      expect(claro.brillo, Brightness.light);
      expect(oscuro.brillo, Brightness.dark);
    });
  });
}

/// WCAG 1.4.3 (nivel AA) para texto.
const double _textoAA = 4.5;

/// WCAG 1.4.11 para el límite de un control y para gráficos con significado.
const double _controlAA = 3.0;

/// La luminancia relativa de un color, según la definición de WCAG 2.x.
///
/// El canal se linealiza con la corrección gamma antes de ponderarlo: sin eso,
/// comparar dos colores claros da un número tranquilizador y falso.
double _luminancia(Color color) {
  double canal(double v) {
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * canal(color.r) +
      0.7152 * canal(color.g) +
      0.0722 * canal(color.b);
}

/// La razón de contraste entre dos colores: entre 1:1 y 21:1.
double _contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  final claro = math.max(la, lb);
  final oscuro = math.min(la, lb);
  return (claro + 0.05) / (oscuro + 0.05);
}

/// El hexadecimal de un color, para que el mensaje de fallo sea accionable.
String _hex(Color c) {
  String dos(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${dos(c.r)}${dos(c.g)}${dos(c.b)}'.toUpperCase();
}

/// Exige un contraste mínimo e informa **la cifra medida** cuando no lo alcanza.
///
/// El mensaje lleva el valor y el motivo: un fallo que dice sólo «se esperaba
/// 4.5» obliga a volver a medir a mano para saber cuánto falta, que es lo que
/// este archivo existe para evitar.
void _exigeContraste(
  String etiqueta,
  Color primero,
  Color segundo, {
  required double minimo,
  required String porque,
}) {
  test(etiqueta, () {
    final medido = _contraste(primero, segundo);
    expect(
      medido,
      greaterThanOrEqualTo(minimo),
      reason: '${_hex(primero)} sobre ${_hex(segundo)} da '
          '${medido.toStringAsFixed(2)}:1 y el mínimo es '
          '${minimo.toStringAsFixed(1)}:1 porque $porque',
    );
  });
}
