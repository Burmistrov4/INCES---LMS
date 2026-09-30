import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/inces_theme.dart';
import 'comunes.dart';

/// Ítem del menú lateral, con su categoría.
class ItemNavegacion {
  const ItemNavegacion({
    required this.icono,
    required this.titulo,
    required this.categoria,
    this.disponible = true,
    this.pendiente,
    this.modulo,
  });

  final IconData icono;
  final String titulo;

  /// Agrupador visible en el menú: *Gestión Académica*, *Control de Aulas*…
  final String categoria;

  /// `false` ⇒ la sección no es pulsable. Se muestra atenuada y sin acción, en
  /// vez de llevar a una pantalla vacía.
  ///
  /// Lo que declara esta bandera es **si la pantalla existe**, que es un hecho
  /// del código. Que el módulo del que depende esté encendido es un hecho
  /// **del servidor** y se aplica encima en tiempo de ejecución — ver [modulo].
  final bool disponible;

  /// Por qué está apagada, cuando **no** es «todavía no existe».
  ///
  /// `null` ⇒ el tooltip cae al mensaje genérico («pendiente de construir»). Se
  /// usa para la sección que **sí existe** pero vive en otro sitio: sin esto el
  /// menú afirmaría que falta algo que está construido, y quien lo busca no lo
  /// encuentra. El caso real es «Calificaciones» en el panel del docente: el
  /// libro de notas existe desde M6 y está a un clic, dentro de cada aula.
  ///
  /// **No puede contener paréntesis.** `test/menu_alcanzable_test.dart` delimita
  /// cada `ItemNavegacion(…)` con el primer `),` que encuentra, y un paréntesis
  /// dentro del texto cortaría el bloque por la mitad.
  final String? pendiente;

  /// Clave del módulo de `system_modules` que gobierna esta sección, o `null`.
  ///
  /// `null` ⇒ la sección no depende de ningún módulo conmutable (el perfil
  /// propio, la ficha del aspirante): apagarla no es una opción del cPanel.
  ///
  /// Cuando tiene valor, el estado real de ese módulo decide si la sección es
  /// pulsable. Antes esa decisión **no existía**: los tres dashboards escribían
  /// `disponible:` a mano y nadie leía `system_modules`, así que apagar
  /// `m6_aula_virtual` desde el cPanel dejaba «Mis aulas» encendida y el clic
  /// devolvía **403**. El menú afirmaba que había algo al otro lado.
  ///
  /// La traducción de clave a «está apagado» la hace
  /// `aplicarEstadoDeModulos` en `lib/widgets/modulos_del_menu.dart`, que es
  /// también donde vive la razón de que un módulo **desconocido** no apague
  /// nada.
  ///
  /// Sólo se mira `habilitado`, **nunca** `roles_permitidos`: esa lista dice
  /// quién puede usar las rutas del módulo, no quién puede ver el menú.
  /// `m7_asistencia` la tiene en `['docente','admin']` y aun así el aprendiz
  /// necesita su sección para marcar — es el rol que marca (D19).
  final String? modulo;

  /// Copia apagada por culpa de su módulo, con el motivo ya redactado.
  ///
  /// Existe en vez de un `copyWith` porque el motivo y la bandera van juntos
  /// siempre: un `copyWith` permitiría apagar la sección y dejar el motivo
  /// viejo, o al revés, y esas dos combinaciones no significan nada.
  ItemNavegacion apagadoPorModulo(String motivo) => ItemNavegacion(
        icono: icono,
        titulo: titulo,
        categoria: categoria,
        disponible: false,
        pendiente: motivo,
        modulo: modulo,
      );
}

/// Andamiaje de la aplicación: barra lateral replegable, encabezado y contenido.
///
/// Existe para que el dashboard del administrador, el del docente y el del
/// estudiante compartan una sola estructura. Antes cada uno montaba su propio
/// `Scaffold` con sus colores, y por eso se veían como tres aplicaciones
/// distintas.
class AndamiajeApp extends StatefulWidget {
  const AndamiajeApp({
    super.key,
    required this.items,
    required this.seleccionado,
    required this.onSeleccionar,
    required this.rolEtiqueta,
    required this.contenido,
    this.nombreUsuario,
    this.correoUsuario,
    this.periodoActivo,
    this.accionesEncabezado = const [],
    this.onCerrarSesion,
    this.temaActual,
    this.onCambiarTema,
  });

  final List<ItemNavegacion> items;
  final int seleccionado;
  final ValueChanged<int> onSeleccionar;
  final String rolEtiqueta;
  final Widget contenido;

  final String? nombreUsuario;
  final String? correoUsuario;
  final String? periodoActivo;
  final List<Widget> accionesEncabezado;
  final VoidCallback? onCerrarSesion;

  /// Tema vigente, para marcar cuál está elegido en el selector del pie.
  ///
  /// Nulable por el mismo motivo que [onCambiarTema]: quien no ofrece el
  /// selector no tiene por qué declarar un tema.
  final ThemeMode? temaActual;

  /// Cambia el tema de la aplicación.
  ///
  /// **`null` ⇒ el selector no se dibuja.** Es la convención que ya usa
  /// [onCerrarSesion], y aquí no es un detalle de estilo: hay pruebas que montan
  /// este andamiaje **sin ningún proveedor de tema** —`menu_alcanzable_test.dart`
  /// lo monta con un `SizedBox` de contenido, y `aula_produccion_test.dart` y
  /// `menu_gobernado_por_modulos_test.dart` montan el panel del docente, que lo
  /// incluye—. Un selector incondicional obligaría a todas ellas a inventarse un
  /// proveedor para poder montar el widget que están probando, y la prueba
  /// mediría otra cosa.
  final ValueChanged<ThemeMode>? onCambiarTema;

  @override
  State<AndamiajeApp> createState() => _AndamiajeAppState();
}

class _AndamiajeAppState extends State<AndamiajeApp> {
  /// El menú arranca replegado en pantallas medianas para dar más sitio al
  /// contenido, y extendido en las grandes.
  bool _replegado = false;
  bool _inicializado = false;

  /// Ancho a partir del cual el menú es fijo. Por debajo pasa a cajón: un `Row`
  /// con ancho fijo desborda en pantallas angostas.
  static const double _anchoEscritorio = 900;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inicializado) return;
    _inicializado = true;

    // Sólo se calcula una vez. Si se recalculara en cada `build`, cambiar el
    // tamaño de la ventana revertiría el replegado que el usuario eligió.
    final ancho = MediaQuery.sizeOf(context).width;
    _replegado = ancho < 1280;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ancho = MediaQuery.sizeOf(context).width;
    final esAngosto = ancho < _anchoEscritorio;

    return Scaffold(
      drawer: esAngosto
          ? Drawer(
              width: IncesTheme.anchoMenu,
              backgroundColor: theme.colorScheme.surface,
              child: _MenuLateral(
                items: widget.items,
                seleccionado: widget.seleccionado,
                replegado: false,
                onSeleccionar: (i) {
                  widget.onSeleccionar(i);
                  Navigator.of(context).pop();
                },
                onCerrarSesion: widget.onCerrarSesion,
                rolEtiqueta: widget.rolEtiqueta,
                correoUsuario: widget.correoUsuario,
                temaActual: widget.temaActual,
                onCambiarTema: widget.onCambiarTema,
              ),
            )
          : null,
      body: Row(
        children: [
          if (!esAngosto)
            _MenuLateral(
              items: widget.items,
              seleccionado: widget.seleccionado,
              replegado: _replegado,
              onSeleccionar: widget.onSeleccionar,
              onCerrarSesion: widget.onCerrarSesion,
              rolEtiqueta: widget.rolEtiqueta,
              correoUsuario: widget.correoUsuario,
              temaActual: widget.temaActual,
              onCambiarTema: widget.onCambiarTema,
              onAlternarReplegado: () =>
                  setState(() => _replegado = !_replegado),
            ),
          Expanded(
            child: Column(
              children: [
                EncabezadoInstitucional(
                  rolEtiqueta: widget.rolEtiqueta,
                  nombreUsuario: widget.nombreUsuario,
                  correoUsuario: widget.correoUsuario,
                  periodoActivo: widget.periodoActivo,
                  acciones: widget.accionesEncabezado,
                  onAbrirMenu:
                      esAngosto ? () => Scaffold.of(context).openDrawer() : null,
                ),
                Expanded(child: widget.contenido),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Menú lateral, por categorías y replegable.
class _MenuLateral extends StatelessWidget {
  const _MenuLateral({
    required this.items,
    required this.seleccionado,
    required this.replegado,
    required this.onSeleccionar,
    required this.rolEtiqueta,
    this.correoUsuario,
    this.onCerrarSesion,
    this.onAlternarReplegado,
    this.temaActual,
    this.onCambiarTema,
  });

  final List<ItemNavegacion> items;
  final int seleccionado;
  final bool replegado;
  final ValueChanged<int> onSeleccionar;
  final String rolEtiqueta;
  final String? correoUsuario;
  final VoidCallback? onCerrarSesion;
  final VoidCallback? onAlternarReplegado;
  final ThemeMode? temaActual;
  final ValueChanged<ThemeMode>? onCambiarTema;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;

    // Las categorías se derivan de los ítems, en orden de aparición. Así añadir
    // un módulo nuevo a una categoría existente no exige tocar este archivo.
    final categorias = <String, List<int>>{};
    for (var i = 0; i < items.length; i++) {
      categorias.putIfAbsent(items[i].categoria, () => []).add(i);
    }

    return AnimatedContainer(
      // La animación del ancho es lo que hace que replegar se sienta fluido en
      // vez de instantáneo. 200 ms es lo bastante corto para no estorbar.
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: replegado ? IncesTheme.anchoMenuReplegado : IncesTheme.anchoMenu,
      decoration: BoxDecoration(
        color: esOscuro
            ? IncesTheme.superficieOscura
            : IncesTheme.superficieClara,
        border: Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Cabecera del menú: identidad y botón de replegado -------------
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: replegado ? 12 : 16,
                vertical: 16,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: IncesTheme.degradadoAzul,
                      borderRadius:
                          BorderRadius.circular(IncesTheme.radioControl),
                    ),
                    child: Text(
                      'I',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!replegado) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'INCES LMS',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'La Isabelica',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onAlternarReplegado != null)
                      IconButton(
                        tooltip: 'Replegar menú',
                        onPressed: onAlternarReplegado,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),

            // --- Ítems, agrupados por categoría --------------------------------
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final entrada in categorias.entries) ...[
                    if (!replegado)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(
                          entrada.key.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                    for (final indice in entrada.value)
                      _ItemMenu(
                        item: items[indice],
                        seleccionado: seleccionado == indice,
                        replegado: replegado,
                        onTap: () => onSeleccionar(indice),
                      ),
                  ],
                ],
              ),
            ),

            // --- Pie: tema, replegar (cuando no hay cabecera) y cerrar sesión --
            const Divider(height: 1),
            if (replegado && onAlternarReplegado != null)
              IconButton(
                tooltip: 'Desplegar menú',
                onPressed: onAlternarReplegado,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
            // El tema va aquí, en el pie, y no en el encabezado: es una
            // preferencia del usuario, no una acción del contexto de trabajo, y
            // el encabezado ya lleva el período activo y las acciones de la
            // sección. En el pie queda visible desde **todas** las pantallas,
            // que es la condición que se pidió para poder ponerlo.
            if (onCambiarTema != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: _SelectorDeTema(
                  actual: temaActual ?? ThemeMode.system,
                  onCambiar: onCambiarTema!,
                  replegado: replegado,
                ),
              ),
            if (onCerrarSesion != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton.icon(
                  onPressed: onCerrarSesion,
                  icon: Icon(
                    Icons.logout_rounded,
                    size: 17,
                    color: theme.colorScheme.error,
                  ),
                  label: replegado
                      ? const SizedBox.shrink()
                      : Text(
                          'Cerrar sesión',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.error,
                          ),
                        ),
                  style: TextButton.styleFrom(
                    alignment: replegado
                        ? Alignment.center
                        : Alignment.centerLeft,
                    padding: EdgeInsets.symmetric(
                      horizontal: replegado ? 0 : 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.item,
    required this.seleccionado,
    required this.replegado,
    required this.onTap,
  });

  final ItemNavegacion item;
  final bool seleccionado;
  final bool replegado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = seleccionado
        ? theme.colorScheme.primary
        : item.disponible
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

    final contenido = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      margin: EdgeInsets.symmetric(horizontal: replegado ? 8 : 10, vertical: 2),
      padding: EdgeInsets.symmetric(
        horizontal: replegado ? 0 : 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        // El fondo del ítem activo es tenue y no el azul pleno: con azul sólido
        // el texto blanco compite con la franja de marca del encabezado.
        color: seleccionado
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
        border: seleccionado
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment:
            replegado ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(item.icono, size: 18, color: color),
          if (!replegado) ...[
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                item.titulo,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight:
                      seleccionado ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            if (!item.disponible)
              Icon(
                Icons.construction_outlined,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.45),
              ),
          ],
        ],
      ),
    );

    // El mensaje de una sección apagada sale de `item.pendiente` cuando lo hay.
    // «pendiente de construir» es la verdad **por defecto**, pero no siempre lo
    // es —«Calificaciones» del docente existe y vive dentro del aula—, y un
    // mensaje falso sobre algo construido manda al usuario a buscar lo que ya
    // tiene. Replegado manda el título: el icono suelto no comunica nada y ahí
    // la etiqueta no se ve.
    final conTooltip = replegado || !item.disponible
        ? Tooltip(
            message: replegado
                ? item.titulo
                : item.pendiente ?? '${item.titulo} — pendiente de construir',
            child: contenido,
          )
        : contenido;

    // Una sección sin construir no es pulsable: llegar a una pantalla vacía es
    // peor que no poder entrar.
    if (!item.disponible) return conTooltip;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      child: conTooltip,
    );
  }
}

// -----------------------------------------------------------------------------
//  Selector de tema
// -----------------------------------------------------------------------------

/// Icono y etiqueta de cada modo de tema.
///
/// Es un `switch` **exhaustivo** y no un `Map`: si Flutter añade un
/// `ThemeMode`, esto deja de compilar. Con un `Map` habría que acordarse de
/// añadir la entrada, y olvidarlo daría un modo sin nombre ni icono —un
/// desplegable con una fila en blanco— sin que nada avisara.
({IconData icono, String etiqueta}) _describirTema(ThemeMode modo) {
  switch (modo) {
    case ThemeMode.system:
      return (icono: Icons.brightness_auto_rounded, etiqueta: 'Sistema');
    case ThemeMode.light:
      return (icono: Icons.light_mode_rounded, etiqueta: 'Claro');
    case ThemeMode.dark:
      return (icono: Icons.dark_mode_rounded, etiqueta: 'Oscuro');
  }
}

/// Selector del tema de la aplicación, para el pie de la barra lateral.
///
/// Un `PopupMenuButton` y no tres botones seguidos: el pie ya tiene el botón de
/// replegar y el de cerrar sesión, y una fila de tres controles de tema ahí
/// competiría con ellos. El menú enseña los tres modos de una vez y marca el
/// vigente, que es lo que hace falta para saber en cuál se está.
///
/// **Sin un solo color literal.** Todos salen de `Theme.of(context)` o del tema
/// heredado, que es la regla que dejó el Bloque B: un `Color(0x…)` escrito aquí
/// se vería bien en un tema y mal en el otro, y
/// `test/theme_literales_test.dart` lo delata.
class _SelectorDeTema extends StatelessWidget {
  const _SelectorDeTema({
    required this.actual,
    required this.onCambiar,
    required this.replegado,
  });

  final ThemeMode actual;
  final ValueChanged<ThemeMode> onCambiar;
  final bool replegado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vigente = _describirTema(actual);

    return PopupMenuButton<ThemeMode>(
      // El tooltip nombra el modo vigente porque replegado sólo se ve el icono,
      // y un icono suelto no dice en cuál se está. Usa la misma etiqueta que la
      // vista desplegada para no crear dos vocabularios para lo mismo.
      tooltip: 'Tema: ${vigente.etiqueta}',
      onSelected: onCambiar,
      // La posición por defecto (`over`) coloca el menú **encima** del botón.
      // Para un elemento del pie es lo correcto: abriéndolo hacia abajo se
      // saldría de la ventana en cuanto la barra llegara al borde inferior.
      itemBuilder: (context) => [
        for (final modo in ThemeMode.values)
          PopupMenuItem<ThemeMode>(
            value: modo,
            child: _OpcionDeTema(
              descripcion: _describirTema(modo),
              seleccionado: modo == actual,
            ),
          ),
      ],
      // Se pasa `child` en vez de `icon` para poder cambiar la forma según el
      // replegado: con `icon`, `PopupMenuButton` dibuja siempre un `IconButton`
      // cuadrado y en la barra desplegada quedaría un icono suelto sin la
      // etiqueta que sí tienen los ítems del menú.
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: replegado ? 0 : 12,
          vertical: 10,
        ),
        child: replegado
            ? Icon(
                vigente.icono,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : Row(
                children: [
                  Icon(
                    vigente.icono,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      vigente.etiqueta,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Una fila del menú de temas: icono, etiqueta y marca del vigente.
class _OpcionDeTema extends StatelessWidget {
  const _OpcionDeTema({required this.descripcion, required this.seleccionado});

  final ({IconData icono, String etiqueta}) descripcion;
  final bool seleccionado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          descripcion.icono,
          size: 17,
          // `onSurfaceVariant` y no `onSurface`: el menú lo pinta Flutter con su
          // propio color de superficie, y este par es el que el esquema de
          // Material garantiza legible sobre él en los dos temas.
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            descripcion.etiqueta,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: seleccionado ? FontWeight.w600 : FontWeight.w500,
              // Sin color propio cuando no está seleccionado: así hereda el del
              // menú, que es el que el tema define para su superficie. Fijarlo
              // aquí obligaría a acertar con el color de fondo del menú, que no
              // lo decide este archivo.
              color: seleccionado ? theme.colorScheme.primary : null,
            ),
          ),
        ),
        // La marca del vigente. Sin ella habría que recordar cuál se eligió la
        // última vez para saber cuál está activo, que es justo lo que un
        // selector tiene que responder de un vistazo.
        if (seleccionado)
          Icon(
            Icons.check_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Contenedor de contenido
// -----------------------------------------------------------------------------

/// Envuelve el contenido de una sección con márgenes, migas de pan y ancho
/// máximo.
///
/// El ancho máximo existe por legibilidad: en un monitor ancho, una línea de
/// texto que ocupe los 2500 px es incómoda de leer porque el ojo pierde el
/// principio de la línea siguiente.
///
/// ## El contrato de altura, y por qué ya no hay un scroll aquí
///
/// Esta sección entrega a su hijo una altura **acotada**: la que sobra tras las
/// migas de pan. No la envuelve en un `SingleChildScrollView`.
///
/// Antes sí lo hacía, y era un fallo silencioso: un scroll vertical da al hijo
/// altura **infinita**, y un panel que reparte el espacio con `Expanded` —o que
/// usa un `ListView` normal— revienta con «incoming height constraints are
/// unbounded». Tres paneles del cPanel lo hacían, así que abrirlos en la
/// aplicación real lanzaba una excepción de layout; las pruebas no lo veían
/// porque los montaban en el `body` acotado de un `Scaffold`, que no es como se
/// montan de verdad.
///
/// La regla, entonces: **el panel decide si llena el hueco o si crece.** Si su
/// contenido puede pasar de la pantalla, se envuelve él mismo en un
/// `SingleChildScrollView`. Así los dos contratos caben, en vez de obligar a
/// todos a compartir uno que sólo sirve a unos.
class ContenidoSeccion extends StatelessWidget {
  const ContenidoSeccion({
    super.key,
    required this.child,
    this.migas = const [],
    this.anchoMaximo = 1280,
  });

  final Widget child;
  final List<String> migas;
  final double anchoMaximo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final esAngosto = restricciones.maxWidth < 700;
        return Padding(
          padding: EdgeInsets.all(esAngosto ? 16 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: anchoMaximo),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (migas.isNotEmpty) MigasDePan(partes: migas),
                  // `Flexible` y no un hijo suelto: en un `Column`, un hijo no
                  // flexible recibe altura **infinita** en el eje principal, así
                  // que un panel con `Expanded` o con un `ListView` normal
                  // volvería a reventar. Siendo flexible, recibe el hueco que
                  // sobra —acotado— y lo reparte como quiera. El ajuste es
                  // holgado, no forzado: un panel corto no se estira.
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
