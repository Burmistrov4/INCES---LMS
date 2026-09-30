import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño del LMS del INCES.
///
/// Centraliza la identidad gráfica institucional y las decisiones visuales para
/// que ninguna pantalla invente sus propios colores. Antes de este archivo, cada
/// pantalla repetía literales como `Color(0xFF0F172A)` y `Colors.blueAccent`, y
/// eso produjo el problema real que había: **el login era oscuro y los paneles
/// también, pero con azules distintos**, así que la aplicación no se percibía
/// como un solo producto.
///
/// ## Por qué una paleta propia y no `ColorScheme.fromSeed`
///
/// `fromSeed` genera tonos derivados por armonización. Es cómodo, pero el azul
/// y el rojo institucionales del INCES **no se pueden derivar**: son los del
/// logotipo, y un tono intermedio generado automáticamente deja de ser el color
/// de la institución. Por eso la paleta se declara explícitamente y `fromSeed`
/// se usa sólo como base de los colores neutros que sí conviene derivar.
class IncesTheme {
  const IncesTheme._();

  // ---------------------------------------------------------------------------
  //  Paleta institucional
  // ---------------------------------------------------------------------------

  /// Azul institucional. Cabeceras, barras de aplicación y botones primarios.
  static const Color azulPrimario = Color(0xFF003B73);

  /// Azul secundario. Estados hover, enlaces y selección de módulos.
  ///
  /// Es un azul más claro que [azulPrimario] pero de la misma familia: se
  /// distingue por luminosidad, no por tono, que es lo que mantiene la lectura
  /// de «institución» en lugar de «dos azules distintos».
  static const Color azulSecundario = Color(0xFF0059B3);

  /// Rojo institucional. Reservado para énfasis real: alertas y acciones
  /// críticas (apagar un módulo, borrar, degradar un administrador).
  ///
  /// Uso deliberadamente escaso. Si el rojo apareciera en elementos decorativos,
  /// dejaría de señalar peligro, y el aviso de «no puedes apagar el módulo del
  /// cPanel» competiría con el color de un icono cualquiera.
  static const Color rojoInces = Color(0xFFD32F2F);

  // --- Superficies, modo claro -------------------------------------------------

  /// Gris frío de fondo. Deliberadamente no blanco puro: las tarjetas blancas
  /// necesitan un fondo que las distinga, y sobre `#FFFFFF` la elevación es
  /// invisible.
  static const Color fondoClaro = Color(0xFFF8FAFC);
  static const Color superficieClara = Color(0xFFFFFFFF);

  /// Borde de las tarjetas. Muy tenue: con la sombra ya hay separación, y dos
  /// señales fuertes a la vez (borde marcado + sombra) endurecen la interfaz.
  static const Color bordeClaro = Color(0xFFE2E8F0);

  // --- Superficies, modo oscuro ------------------------------------------------

  /// Slate oscuro profesional. No negro puro: el negro absoluto sobre pantallas
  /// OLED produce un contraste tan alto que el texto cansa, y las sombras
  /// —que son oscuras— desaparecen sobre negro.
  static const Color fondoOscuro = Color(0xFF0F172A);
  static const Color superficieOscura = Color(0xFF1E293B);
  static const Color bordeOscuro = Color(0xFF334155);

  // --- Colores de estado, para RELLENO -----------------------------------------
  //
  // Estos cuatro son el acento **como relleno**: el fondo de un bloque sólido,
  // el color de un tinte translúcido o el trazo de un borde decorativo. Son
  // `const` porque un bloque sólido es sólido en los dos temas y el blanco que
  // lleva encima no cambia con el brillo.
  //
  // **No son el color de una letra ni de un icono.** Para eso está
  // `PaletaInces`, que sí cambia con el brillo y está medido contra las
  // superficies. Usarlos como primer plano fue el fallo: de diez combinaciones
  // acento-sobre-superficie se salvaban dos.

  /// El verde institucional **de relleno**.
  ///
  /// Vale `#15803D` y no `#16A34A` por una razón medida: el blanco sobre
  /// `#16A34A` da **3.30:1**, por debajo del 4.5:1 que WCAG pide al texto — y
  /// este verde sólo se usa detrás de texto blanco (los avisos flotantes de
  /// éxito). Sobre `#15803D` el blanco da **5.01:1** y pasa. Medido el
  /// 2026-09-30, junto con los cinco acentos de `PaletaInces`.
  static const Color exito = Color(0xFF15803D);

  /// El ámbar de relleno. Como letra no pasa AA en claro (1.81:1): ver
  /// `PaletaInces.advertencia`.
  static const Color advertencia = Color(0xFFF59E0B);

  /// El rojo de relleno. El blanco encima da 4.83:1, así que sí sirve detrás de
  /// texto; como letra sobre su propio tinte da 3.67:1 y no.
  static const Color error = Color(0xFFDC2626);

  /// El azul informativo de relleno. El blanco encima da 5.17:1. Como letra
  /// sobre blanco da 4.01:1: se queda corto y por eso existe el rol de la paleta.
  static const Color info = Color(0xFF2563EB);

  /// Lo que va **encima de un rojo de error**: el texto y el icono de un aviso
  /// flotante.
  ///
  /// Existe porque el fallo real no estaba en el fondo sino en quién elegía el
  /// texto. El aviso llevaba `backgroundColor` rojo y **ningún** color de texto,
  /// así que lo ponía Material con `onInverseSurface` — claro en tema claro y
  /// **oscuro en tema oscuro—: en modo oscuro el aviso se leía casi negro sobre
  /// rojo. Con este rol, el par queda escrito.
  ///
  /// Blanco sobre [error] (#DC2626) da **4.83:1**, que sí pasa AA.
  ///
  /// Por eso **no** hay un `superficieError` más oscuro. Lo hubo, y se fue con el
  /// fallo que decía arreglar: se añadió creyendo que el par daba 4.41:1 —por
  /// debajo de 4.5—, y esa cifra era una cuenta **a mano** mal hecha. La medición
  /// real dice 4.83:1. Lo detectó CI, que es donde corre la prueba de contraste:
  /// aquí `flutter test` no arranca. La lección queda escrita porque costó una
  /// corrida: **una cifra de contraste no entra en un comentario si no sale del
  /// medidor**, y una prueba no puede afirmar que algo falla sin haberlo medido
  /// con el mismo instrumento que usa para afirmar que pasa.
  static const Color sobreError = Color(0xFFFFFFFF);

  /// El fondo de un bloque de advertencia.
  ///
  /// Se queda **claro en los dos temas** a propósito. Es un aviso que se lee una
  /// vez, y el par con [textoAdvertencia] da 8.15:1 sobre este fondo sea cual sea
  /// el tema: un bloque claro dentro de una página oscura llama la atención sin
  /// perder ni un punto de contraste. Inventarle una variante oscura sería
  /// diseñar un segundo aviso que nadie ha pedido, y el riesgo de dejar el texto
  /// sin par es mayor que el de que desentone.
  static const Color superficieAdvertencia = Color(0xFFFEF3C7);

  /// El texto de [superficieAdvertencia]. 8.15:1 sobre ella.
  static const Color textoAdvertencia = Color(0xFF78350F);

  /// El icono de [superficieAdvertencia]: 4.51:1 sobre ese fondo.
  ///
  /// **No sirve sobre la superficie de una tarjeta** en modo oscuro: ahí da
  /// 2.91:1, por debajo del 3:1 que WCAG pide para un gráfico con significado.
  /// Para ese caso está `PaletaInces.aviso`, que sí cambia con el brillo.
  static const Color advertenciaFuerte = Color(0xFFB45309);

  /// Texto secundario en modo oscuro. El blanco al 60 % no da el contraste
  /// suficiente sobre `#1E293B`; este tono sí y sigue leyéndose como apagado.
  static const Color textoApagadoOscuro = Color(0xFF94A3B8);

  // ---------------------------------------------------------------------------
  //  Métricas compartidas
  // ---------------------------------------------------------------------------

  /// Radio de las tarjetas grandes.
  static const double radioTarjeta = 12;

  /// Radio de botones y campos. Más pequeño que el de las tarjetas a propósito:
  /// dentro de una tarjeta redondeada, un botón igual de redondeado se ve
  /// «flotando» en vez de encajado.
  static const double radioControl = 8;

  /// Sombra sutil de tarjeta en modo claro.
  ///
  /// Dos decisiones: el alfa es 0.04 —lo justo para separar del fondo sin que se
  /// lea como un borde— y el desplazamiento vertical es mayor que el desenfoque,
  /// que es lo que hace que la tarjeta parezca apoyada y no iluminada de frente.
  static List<BoxShadow> sombraTarjeta(Brightness brillo) {
    if (brillo == Brightness.dark) {
      // En oscuro, la elevación se expresa con el borde, no con la sombra:
      // una sombra negra sobre fondo casi negro es invisible.
      return const [];
    }
    return const [
      BoxShadow(
        color: Color(0x0A000000),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ];
  }

  /// Desenfoque del cristal del encabezado y la barra lateral.
  ///
  /// Un valor bajo (10) basta para que el contenido se intuya detrás sin volver
  /// ilegible el texto. Es deliberadamente sutil: el desenfoque aquí separa
  /// planos, no decora.
  static const double desenfoqueCristal = 10;

  /// Ancho del menú lateral en escritorio.
  static const double anchoMenu = 268;

  /// Ancho del menú lateral replegado.
  ///
  /// 76 px es lo que ocupa un icono de 22 px con relleno a ambos lados y sigue
  /// dejando sitio para el indicador de selección. Por debajo de 68 los iconos
  /// quedan pegados a los bordes.
  static const double anchoMenuReplegado = 76;

  // ---------------------------------------------------------------------------
  //  Tipografía
  // ---------------------------------------------------------------------------

  /// Familia tipográfica de toda la aplicación.
  ///
  /// [Inter] y no [Poppins]: Poppins es geométrica y de trazo grueso —excelente
  /// para titulares— pero sus cifras y minúsculas son más anchas, y este sistema
  /// muestra muchas tablas de datos (auditoría, parámetros, listas de usuarios).
  /// Inter está diseñada para interfaces densas en información.
  static TextTheme _textTheme(Brightness brillo) {
    final base = brillo == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    final inter = GoogleFonts.interTextTheme(base);

    // La jerarquía se construye con PESO y TAMAÑO juntos, no sólo tamaño. Un
    // titular de 20 px en peso normal y un cuerpo de 15 px en peso normal se
    // confunden; con el titular en w600 la diferencia es inmediata.
    return inter.copyWith(
      headlineMedium: inter.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineSmall: inter.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: inter.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: inter.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: inter.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      // El cuerpo queda en peso normal: subirlo a w500 en textos largos
      // engorda el bloque y cansa en pantalla.
      labelSmall: inter.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  Esquemas de color
  // ---------------------------------------------------------------------------

  static ColorScheme _colorScheme(Brightness brillo) {
    final esOscuro = brillo == Brightness.dark;

    // Los neutros sí se derivan: no son marca, son soporte, y `fromSeed` da una
    // escala coherente sin tener que declarar veinte tonos a mano.
    final base = ColorScheme.fromSeed(
      seedColor: azulPrimario,
      brightness: brillo,
    );

    return base.copyWith(
      // Los colores de marca se SOBREESCRIBEN con los institucionales exactos.
      // Es el punto de este archivo: que el azul de la aplicación sea el azul
      // del logotipo y no un tono armonizado que se le parece.
      primary: esOscuro ? azulSecundario : azulPrimario,
      onPrimary: Colors.white,
      secondary: azulSecundario,
      onSecondary: Colors.white,
      tertiary: rojoInces,
      onTertiary: Colors.white,
      error: esOscuro ? const Color(0xFFF87171) : error,
      onError: Colors.white,
      surface: esOscuro ? superficieOscura : superficieClara,
      onSurface: esOscuro ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      onSurfaceVariant:
          esOscuro ? textoApagadoOscuro : const Color(0xFF475569),
      outline: esOscuro ? bordeOscuro : bordeClaro,
      outlineVariant:
          esOscuro ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
    );
  }

  // ---------------------------------------------------------------------------
  //  Tema completo
  // ---------------------------------------------------------------------------

  static ThemeData claro() => _construir(Brightness.light);
  static ThemeData oscuro() => _construir(Brightness.dark);

  static ThemeData _construir(Brightness brillo) {
    final scheme = _colorScheme(brillo);
    final esOscuro = brillo == Brightness.dark;

    // La paleta por roles del mismo brillo. Se resuelve aquí para que el tema y
    // los widgets lean los MISMOS colores: cuando cada uno los tomaba por su
    // cuenta, el tema acertaba el modo oscuro y `estilos_campo.dart` lo
    // sobrescribía con literales claros.
    final paleta = PaletaInces.deBrillo(brillo);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brillo,
      scaffoldBackgroundColor: esOscuro ? fondoOscuro : fondoClaro,
      textTheme: _textTheme(brillo),

      // Material 3 usa `surfaceTint` para teñir las superficies elevadas con el
      // color primario. Con un azul tan saturado como el institucional, eso
      // vuelve moradas las tarjetas blancas al elevarse. Se anula y la
      // elevación se expresa con sombra y borde, que es lo predecible.
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioTarjeta),
          side: BorderSide(color: scheme.outline),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: esOscuro ? superficieOscura : superficieClara,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          // `minimumSize` en lugar de un `SizedBox` alrededor de cada botón: así
          // el objetivo táctil se garantiza desde el tema y ningún botón nuevo
          // puede olvidarlo. 44 px es el mínimo recomendado para el dedo.
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radioControl),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radioControl),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radioControl),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Los MISMOS roles que usan los widgets de campo. El tema y
        // `estilos_campo.dart` tenían cada uno su idea del relleno: el tema
        // acertaba el modo oscuro y el widget lo pisaba con `#F8FAFC` —casi
        // blanco— mientras el texto lo seguía poniendo el `ColorScheme` oscuro
        // en `#E2E8F0`. De ahí el 1.18:1 que hacía ilegible lo que se escribía.
        fillColor: paleta.rellenoDeCampo,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          borderSide: BorderSide(color: paleta.bordeDeCampo),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          borderSide: BorderSide(color: paleta.bordeDeCampo),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          // 1.5 px y no 2: el foco se nota por el color y por el grosor, y a
          // 2 px el campo parece saltar al enfocarse.
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        labelStyle: TextStyle(color: paleta.textoApagado),
        // Faltaba, y su ausencia se notaba: el texto de ayuda heredaba el
        // `bodySmall` del `textTheme`, que no tiene por qué contrastar con el
        // relleno del campo en ninguno de los dos brillos.
        helperStyle: TextStyle(color: paleta.textoApagado),
        errorStyle: TextStyle(color: scheme.error),
      ),

      // El interruptor usa el azul institucional cuando está activo y un gris
      // neutro cuando no. El gris importa: si el estado apagado heredara el
      // color primario con opacidad, un módulo apagado parecería activo.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) {
            return scheme.onSurfaceVariant.withValues(alpha: 0.5);
          }
          return estados.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) {
            return scheme.onSurfaceVariant.withValues(alpha: 0.12);
          }
          return estados.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (estados) => estados.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outline),
        labelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioControl),
        ),
        contentTextStyle: GoogleFonts.inter(fontSize: 14),
      ),

      dialogTheme: DialogThemeData(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radioTarjeta),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: esOscuro ? const Color(0xFF334155) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  // ---------------------------------------------------------------------------
  //  Degradado institucional
  // ---------------------------------------------------------------------------

  /// Degradado azul→rojo de las cabeceras de tarjeta.
  ///
  /// Es el único degradado del sistema, y se usa **sólo** en la franja superior
  /// de las tarjetas de módulo y curso. Repetido en más sitios dejaría de
  /// identificar y pasaría a ser ruido.
  ///
  /// Empieza en [azulPrimario] y no en [azulSecundario] para que el texto blanco
  /// que va encima mantenga el contraste en todo el recorrido.
  static const LinearGradient degradadoMarca = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [azulPrimario, azulSecundario, rojoInces],
    // El rojo entra al final y en poca proporción: es un acento de marca, no la
    // mitad del degradado. A partes iguales, el resultado parece un semáforo.
    stops: [0.0, 0.65, 1.0],
  );

  /// Degradado de una sola familia, para superficies que necesitan profundidad
  /// sin introducir el rojo.
  static const LinearGradient degradadoAzul = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [azulPrimario, azulSecundario],
  );
}

/// Los tonos semánticos de una etiqueta de estado.
///
/// Es un enumerado y **no un `Color`** porque el color de una etiqueta depende
/// del brillo y el estado del dato no. `EstadoModulo` es `const` y tiene que
/// seguir siéndolo: su trabajo es decir «este módulo está activo», no de qué
/// color pintarlo. Separando el tono —semántica, sin brillo— del par de colores
/// —pintura, con brillo— los dos caben sin que ninguno mienta.
enum TonoEstado { info, exito, advertencia, error, neutro }

/// El par de colores de una etiqueta de estado: su fondo y su texto.
///
/// ## Por qué es un par y no dos colores sueltos
///
/// Los dos van juntos y se **miden como par**: el color del texto sólo tiene
/// sentido contra ese fondo concreto. Dos `Color` sueltos invitarían a pintar el
/// texto de una etiqueta sobre el fondo de otra, y el par medido dejaría de ser
/// cierto sin que nada avisara.
///
/// ## Por qué sólo hay dos colores y no tres
///
/// El borde de algunas etiquetas se deriva del texto, pero **no vive aquí**: es
/// decorativo, WCAG no le exige nada, y meterlo en el par daría a entender que
/// también está medido. Los dos que sí están son los que tienen una relación que
/// se puede incumplir.
@immutable
class ParDeEtiqueta {
  const ParDeEtiqueta({required this.fondo, required this.texto});

  /// El fondo: **el propio color de [texto] al 12 %**, translúcido.
  ///
  /// Que sea translúcido importa para la medición: el color real del chip es la
  /// mezcla con la tarjeta que tenga debajo, así que el par se mide contra las
  /// **dos** superficies donde se ha visto un chip, no contra una sola. Medir
  /// sólo contra la tarjeta dejaría pasar un color que falla en el bloque hundido
  /// — que es exactamente el error que costó una corrección en el Bloque B.
  ///
  /// Que salga de [texto] y no del acento «de marca» es lo que se midió: el
  /// medidor compone la mezcla con el color de la letra. Pintar el fondo con otro
  /// tono dejaría la cifra sin respaldo.
  final Color fondo;

  /// El color del texto **y del icono**, medido contra [fondo].
  ///
  /// El mismo valor sirve para los dos porque el listón del texto (4.5:1) es más
  /// exigente que el de un gráfico con significado (3:1): si pasa como texto, pasa
  /// como icono. Al revés no, y ése fue el fallo: los acentos estaban elegidos
  /// para un icono y se usaron como texto.
  final Color texto;
}

/// Los colores de la aplicación **por su papel**, resueltos para un brillo.
///
/// ## Por qué existe
///
/// `IncesTheme` declaraba las superficies de marca y los colores de estado, pero
/// **no los roles de texto ni los del campo de formulario**. Esa ausencia se
/// llenó a mano, archivo por archivo, con literales de modo claro — y el modo
/// oscuro que salió de ahí nadie lo había escrito. Medido el 2026-09-30:
///
/// | dónde | qué | contraste |
/// |---|---|---|
/// | `estilos_campo.dart:30` + `onSurface` oscuro | texto `#E2E8F0` sobre relleno `#F8FAFC` | **1.18:1** |
/// | `estilos_campo.dart:24` | etiqueta `#94A3B8` sobre relleno `#F8FAFC` | **2.45:1** |
/// | `campo_rejilla.dart:73` | etiqueta `#0F172A` sobre tarjeta `#1E293B` | **1.22:1** |
///
/// WCAG AA exige 4.5:1 para texto. Los tres están a la altura de una mancha: no
/// es que se lean mal, es que **no se leen**. Y los dos primeros son
/// claro-sobre-claro mientras el tercero es oscuro-sobre-oscuro: el mismo error
/// cometido en las dos direcciones.
///
/// Al migrar los literales aparecieron **dos fallos más**, los dos ya en los
/// valores de esta paleta y los dos medidos antes de tocar nada:
///
/// | qué | contraste | por qué importa |
/// |---|---|---|
/// | `textoApagado` `#64748B` sobre `superficieSutil` `#F1F5F9` | **4.34:1** | es donde caen las etiquetas del resumen del paso final |
/// | `bordeDeCampo` `#CBD5E1` sobre relleno `#F8FAFC` | **1.42:1** | es el **único** borde que delimita cada campo del formulario |
///
/// El primero se queda corto por poco y el segundo no es que se quede corto: es
/// que el campo no tenía límite visible. Y el borde tenía además un comentario
/// que afirmaba 3.75:1 en oscuro cuando el valor real era **2.36:1** — una
/// cobertura que sólo existía en el comentario.
///
/// ## Cómo se usa
///
/// ```dart
/// final paleta = PaletaInces.de(context);
/// ```
///
/// Se resuelve **una vez por brillo** y se lee de aquí. Un widget que necesite un
/// color **no vuelve a escribir un hexadecimal**: si le falta un rol, se añade
/// aquí, que pasa a ser el único sitio del proyecto donde un color se decide.
///
/// Los contrastes están **medidos y verificados** en `test/paleta_inces_test.dart`
/// para los dos brillos, y `test/theme_literales_test.dart` impide que vuelva a
/// aparecer un hexadecimal fuera de este archivo. Un rol nuevo que no pase AA
/// pone el primero en rojo, que es la única forma de que esto no se repita.
@immutable
class PaletaInces {
  const PaletaInces._({
    required this.brillo,
    required this.textoPrincipal,
    required this.textoSecundario,
    required this.textoApagado,
    required this.enlace,
    required this.aviso,
    required this.superficie,
    required this.superficieSutil,
    required this.borde,
    required this.rellenoDeCampo,
    required this.bordeDeCampo,
    required this.info,
    required this.exito,
    required this.advertencia,
    required this.error,
    required this.neutro,
  });

  /// La paleta del tema que hay montado ahora mismo.
  factory PaletaInces.de(BuildContext context) =>
      PaletaInces.deBrillo(Theme.of(context).brightness);

  /// La paleta de un brillo concreto, sin `BuildContext`.
  ///
  /// Existe aparte para que `IncesTheme._construir` pueda usar los mismos roles
  /// al armar el `inputDecorationTheme`: si el tema y los widgets tomaran los
  /// colores por caminos distintos, volverían a desincronizarse, que es
  /// exactamente el fallo que este archivo está arreglando.
  factory PaletaInces.deBrillo(Brightness brillo) {
    final esOscuro = brillo == Brightness.dark;

    return PaletaInces._(
      brillo: brillo,
      textoPrincipal:
          esOscuro ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      textoSecundario:
          esOscuro ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
      // `#64748B` —el gris que usaba todo el proyecto— sobre el bloque hundido
      // del resumen (`superficieSutil`, #F1F5F9) da **4.34:1**: se queda corto, y
      // el resumen del paso final es justo donde caen esas etiquetas. Este tono
      // da 4.75:1 ahí, 4.97:1 sobre el relleno del campo y 5.20:1 sobre blanco.
      // Medido el 2026-09-30.
      textoApagado:
          esOscuro ? IncesTheme.textoApagadoOscuro : const Color(0xFF5F6E82),
      // El azul de enlace **no** puede ser `IncesTheme.info` en los dos brillos:
      // `#2563EB` da 5.2:1 sobre blanco pero sólo 2.8:1 sobre el fondo oscuro, o
      // sea que no pasa AA donde más falta hace. Medido el 2026-09-30 al
      // sustituir un `#60A5FA` suelto: ese literal era el azul de enlace de modo
      // oscuro aplicado sin condición, bueno en oscuro (7:1) y malo en claro
      // (2.5:1). Un rol propio resuelve los dos.
      enlace: esOscuro ? const Color(0xFF60A5FA) : IncesTheme.azulSecundario,
      // El acento de un aviso **sí** cambia con el brillo, y por una razón
      // medida: el mismo tono no puede leerse a la vez sobre el bloque ámbar
      // claro y sobre la tarjeta oscura. `#B45309` da 4.51:1 sobre el ámbar y
      // 5.02:1 sobre blanco, pero sólo 2.91:1 sobre `#1E293B` — por debajo del
      // 3:1 que WCAG pide para un gráfico con significado. En oscuro se usa
      // `#FBBF24`, que da 8.77:1. Medido el 2026-09-30.
      aviso: esOscuro ? const Color(0xFFFBBF24) : IncesTheme.advertenciaFuerte,
      superficie:
          esOscuro ? IncesTheme.superficieOscura : IncesTheme.superficieClara,
      superficieSutil:
          esOscuro ? IncesTheme.fondoOscuro : const Color(0xFFF1F5F9),
      borde: esOscuro ? IncesTheme.bordeOscuro : IncesTheme.bordeClaro,
      rellenoDeCampo:
          esOscuro ? IncesTheme.fondoOscuro : const Color(0xFFF8FAFC),
      // El borde de un campo es el **límite de un control**, así que WCAG 1.4.11
      // le pide 3:1 contra lo que lo rodea. No es el caso del borde de una
      // tarjeta —ése es decorativo y no se le exige—, y por eso `borde` y
      // `bordeDeCampo` son dos roles y no uno.
      //
      // Aquí hubo dos afirmaciones falsas, medidas el 2026-09-30. El comentario
      // anterior decía que `#475569` daba 3.75:1 en oscuro: da **2.36:1** contra
      // el relleno y **1.93:1** contra la tarjeta, o sea que no pasaba ninguna de
      // las dos. Y en claro `#CBD5E1` daba **1.42:1** contra su propio relleno
      // —casi blanco sobre casi blanco—, así que el único borde que delimita el
      // campo era prácticamente invisible. Los valores actuales pasan los cuatro
      // pares: en oscuro 3.75:1 contra el relleno y 3.07:1 contra la tarjeta; en
      // claro 3.22:1 y 3.37:1.
      bordeDeCampo:
          esOscuro ? const Color(0xFF64748B) : const Color(0xFF7E8DA3),
      // --- Los cinco acentos de estado, como PRIMER PLANO --------------------
      //
      // Un acento de estado tiene **dos contratos** y `IncesTheme` sólo declaraba
      // uno. `IncesTheme.exito` (#15803D) es un **relleno**: el fondo de un bloque
      // sólido, donde el texto va en blanco. Como **texto o icono** el mismo tono
      // no vale — y ahí estaba el fallo: se usaba el color del relleno como color
      // de la letra, en diez sitios y con cinco copias distintas del mismo widget.
      //
      // Medido el 2026-09-30, contra las **dos** superficies donde cae un chip
      // (`superficie` y `superficieSutil`, porque el tinte es translúcido y su
      // color real es la mezcla con la tarjeta de debajo):
      //
      //   acento                claro              oscuro
      //   info                  4.01:1  ✗          2.54:1  ✗
      //   exito                 2.65:1  ✗          3.78:1  ✗
      //   advertencia           1.81:1  ✗          5.54:1  ✓
      //   error                 4.83:1  ✓          2.85:1  ✗
      //   rojoInces             3.80:1  ✗          2.74:1  ✗
      //   neutro (#64748B)      3.78:1  ✗          2.72:1  ✗
      //
      // De diez combinaciones se salvaban dos. No es que se leyeran mal: es que no
      // se leían. Y el mismo medidor comprobó que el listón del **icono** (3:1)
      // tampoco se cumplía — seis de doce —, así que no bastaba con subir el texto.
      //
      // Los valores de abajo son los que **sí** pasan, buscados como el paso de la
      // misma familia más fiel a la marca que aún llega a 4.5:1 en el peor de los
      // dos fondos, con margen hasta 4.6:1 para que un retoque no lo tumbe:
      //
      //   acento        claro                     oscuro
      //   info          #1D4ED8   5.11:1          #60A5FA   4.67:1
      //   exito         #166534   5.46:1          #22C55E   5.20:1
      //   advertencia   #92400E   5.39:1          #F59E0B   5.54:1
      //   error         #B91C1C   4.83:1          #FCA5A5   6.04:1
      //   neutro        #475569   5.82:1          #94A3B8   4.62:1
      //
      // Un mismo valor sirve para texto **y** para icono: 4.5:1 es más exigente
      // que el 3:1 de un gráfico con significado, así que si pasa como letra pasa
      // como icono. Al revés no — y ése fue exactamente el error que se está
      // corrigiendo. El par (texto, su propio tinte al 12 %) se mide entero en
      // `test/paleta_inces_test.dart`.
      //
      // Que `advertencia` en oscuro coincida con `IncesTheme.advertencia` es
      // casualidad, no dependencia: el ámbar ya pasaba en oscuro y no pasaba en
      // claro, que es justo lo que un valor único no puede resolver.
      info: esOscuro ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
      exito: esOscuro ? const Color(0xFF22C55E) : const Color(0xFF166534),
      advertencia: esOscuro ? const Color(0xFFF59E0B) : const Color(0xFF92400E),
      error: esOscuro ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
      neutro: esOscuro ? const Color(0xFF94A3B8) : const Color(0xFF475569),
    );
  }

  /// El brillo del que salen estos valores.
  final Brightness brillo;

  /// Títulos, valores y **el texto que el usuario escribe**.
  final Color textoPrincipal;

  /// Texto de apoyo con presencia: subtítulos y descripciones.
  final Color textoSecundario;

  /// Etiquetas de campo, textos de ayuda e iconos secundarios.
  final Color textoApagado;

  /// Un enlace o un texto accionable. Tiene rol propio porque el azul de marca
  /// **no** puede ser el mismo en los dos brillos: `azulSecundario` (#0059B3) da
  /// 7.0:1 sobre blanco pero 1.9:1 sobre `#0F172A`, y el `#60A5FA` que lo
  /// sustituía daba lo contrario. Un literal sin condición sólo puede acertar en
  /// uno de los dos temas.
  final Color enlace;

  /// El acento de un aviso —el icono de «no se pudo cargar», por ejemplo—.
  ///
  /// Distinto de [IncesTheme.advertenciaFuerte], que es el icono **dentro** del
  /// bloque ámbar y por tanto no cambia con el tema. Éste sí, porque el mismo
  /// icono cae sobre superficies de brillo opuesto según el tema.
  final Color aviso;

  /// La superficie de una tarjeta.
  final Color superficie;

  /// Un bloque hundido dentro de una superficie, para agrupar sin elevarlo.
  final Color superficieSutil;

  /// El borde de una tarjeta o un separador.
  final Color borde;

  /// El relleno de un campo de formulario.
  final Color rellenoDeCampo;

  /// El borde de un campo de formulario.
  final Color bordeDeCampo;

  // --- Acentos de estado, como PRIMER PLANO ---------------------------------

  /// El alfa del tinte de una etiqueta de estado.
  ///
  /// Es el único sitio donde se decide. Está aquí y no en cada pantalla porque la
  /// medición de [PaletaInces.deBrillo] se hizo **a este alfa**: si una etiqueta
  /// lo cambiara a ojo, el par medido dejaría de ser cierto sin que nada avisara.
  static const double _alfaDelTinte = 0.12;

  /// El acento de un estado pintado **como texto o como icono**.
  ///
  /// ## Por qué esto no puede ser un `static const` de `IncesTheme`
  ///
  /// Un color de estado tiene **dos contratos**, y piden valores distintos:
  ///
  /// | contrato | qué se pinta | qué tiene que contrastar |
  /// |---|---|---|
  /// | relleno | el fondo de un bloque sólido | el blanco que va encima, 4.5:1 |
  /// | primer plano | la letra y el icono de una etiqueta | el acento contra su fondo, 4.5:1 |
  ///
  /// El primer contrato **no** depende del brillo —un bloque sólido es sólido en
  /// los dos temas— y por eso vive en `IncesTheme`, que es `const`. Éste sí: el
  /// mismo verde tiene que ser oscuro sobre una tarjeta blanca y claro sobre una
  /// tarjeta oscura. Un valor único sólo puede acertar en un tema, y así estaban
  /// las diez etiquetas del proyecto.
  final Color info;

  /// El acento de éxito como primer plano. Ver [info].
  final Color exito;

  /// El acento de advertencia como primer plano. Ver [info].
  final Color advertencia;

  /// El acento de error como primer plano. Ver [info].
  final Color error;

  /// El acento neutro —lo apagado, lo que no exige nada— como primer plano.
  ///
  /// Tiene tono propio y no reutiliza [textoApagado]: el chip necesita un par
  /// medido contra **su propio tinte**, y [textoApagado] está medido contra las
  /// superficies limpias. Son dos fondos distintos y por eso son dos roles.
  final Color neutro;

  /// El acento de un tono semántico, para texto o icono.
  ///
  /// El `switch` es exhaustivo a propósito: añadir un tono nuevo **no compila**
  /// hasta darle color. Es la única forma de que un estado no acabe pintado con
  /// el acento de otro, que es el tipo de error que este archivo no puede cazar
  /// midiendo.
  Color acentoDe(TonoEstado tono) => switch (tono) {
        TonoEstado.info => info,
        TonoEstado.exito => exito,
        TonoEstado.advertencia => advertencia,
        TonoEstado.error => error,
        TonoEstado.neutro => neutro,
      };

  /// El par (fondo, texto) de una etiqueta de estado.
  ///
  /// El fondo es **el propio acento al 12 %**, que es el patrón que ya usaban las
  /// diez etiquetas del proyecto (`color.withValues(alpha: 0.12)` con la letra
  /// del mismo color). Se conserva por dos razones: el chip se lee como una
  /// pastilla teñida de su propio color, y así el par se mide contra su propio
  /// fondo y no contra el de otro estado.
  ///
  /// Devuelve el par y no los dos colores por separado porque los dos se miden
  /// **juntos**: el acento de éxito no tiene un contraste «en abstracto», lo tiene
  /// contra este fondo. Separarlos invitaría a pintar el texto de una etiqueta
  /// sobre el fondo de otra, y la medición dejaría de ser cierta en silencio.
  ParDeEtiqueta etiquetaDe(TonoEstado tono) {
    final acento = acentoDe(tono);
    return ParDeEtiqueta(
      fondo: acento.withValues(alpha: _alfaDelTinte),
      texto: acento,
    );
  }
}

/// El estado de un módulo del sistema, con su **tono** semántico.
///
/// Vive fuera del tema porque depende del **estado del dato** (`habilitado`,
/// roles asignados), no de la preferencia de claro/oscuro, y porque el estado
/// tiene que ser reconocible tanto por color como por texto: hay usuarios con
/// daltonismo, y un badge que sólo se distingue por verde o gris no comunica.
///
/// ## Por qué lleva un [TonoEstado] y no un `Color`
///
/// Llevaba un `Color` y era el mismo error que el resto de este bloque: un color
/// no puede depender del brillo y a la vez vivir en un `const`. El tono es
/// **semántica** —«esto está bien», «esto exige cuidado»— y no cambia con el
/// tema; el color es **pintura** y sí. Separados, este objeto sigue siendo
/// `const` y el color lo resuelve `PaletaInces.acentoDe` con el brillo montado.
///
/// El rojo institucional (`#D32F2F`) se cambió por el tono de error por una razón
/// medida: como letra da **3.80:1** en claro y **2.74:1** en oscuro, o sea que no
/// pasa AA en ninguno de los dos temas. El tono de error sí (4.83:1 y 6.04:1). El
/// rojo de marca no se pierde: sigue en la franja superior de la tarjeta, que es
/// un relleno y ahí no se le pide contraste.
class EstadoModulo {
  const EstadoModulo._(this.etiqueta, this.tono, this.icono);

  final String etiqueta;
  final TonoEstado tono;
  final IconData icono;

  static const activo = EstadoModulo._(
    'Activo',
    TonoEstado.exito,
    Icons.check_circle_outline,
  );

  static const inactivo = EstadoModulo._(
    'Inactivo',
    TonoEstado.neutro,
    Icons.pause_circle_outline,
  );

  static const critico = EstadoModulo._(
    'Crítico',
    TonoEstado.error,
    Icons.gpp_maybe_outlined,
  );

  /// El estado a mostrar para un módulo, en orden de prioridad.
  ///
  /// El orden importa: un módulo crítico **está** habilitado, pero lo que el
  /// administrador necesita saber es que no puede apagarlo. Si se comprobara
  /// `habilitado` primero, el aviso de criticidad se perdería.
  static EstadoModulo para({
    required bool habilitado,
    required bool esCritico,
  }) {
    if (esCritico) return critico;
    return habilitado ? activo : inactivo;
  }
}
