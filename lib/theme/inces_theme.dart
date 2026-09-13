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

  // --- Colores de estado -------------------------------------------------------

  static const Color exito = Color(0xFF16A34A);
  static const Color advertencia = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

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
        fillColor: esOscuro ? fondoOscuro : const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControl),
          borderSide: BorderSide(color: scheme.outline),
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
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
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

/// Paleta semántica de un módulo según su estado.
///
/// Vive fuera del tema porque depende del **estado del dato** (`habilitado`,
/// roles asignados), no de la preferencia de claro/oscuro, y porque el estado
/// tiene que ser reconocible tanto por color como por texto: hay usuarios con
/// daltonismo, y un badge que sólo se distingue por verde o gris no comunica.
class EstadoModulo {
  const EstadoModulo._(this.etiqueta, this.color, this.icono);

  final String etiqueta;
  final Color color;
  final IconData icono;

  static const activo = EstadoModulo._(
    'Activo',
    IncesTheme.exito,
    Icons.check_circle_outline,
  );

  static const inactivo = EstadoModulo._(
    'Inactivo',
    Color(0xFF64748B),
    Icons.pause_circle_outline,
  );

  static const critico = EstadoModulo._(
    'Crítico',
    IncesTheme.rojoInces,
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
