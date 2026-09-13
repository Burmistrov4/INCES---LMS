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
  });

  final IconData icono;
  final String titulo;

  /// Agrupador visible en el menú: *Gestión Académica*, *Control de Aulas*…
  final String categoria;

  /// `false` ⇒ la sección todavía no está construida. Se muestra atenuada y sin
  /// acción, en vez de llevar a una pantalla vacía.
  final bool disponible;
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
  });

  final List<ItemNavegacion> items;
  final int seleccionado;
  final bool replegado;
  final ValueChanged<int> onSeleccionar;
  final String rolEtiqueta;
  final String? correoUsuario;
  final VoidCallback? onCerrarSesion;
  final VoidCallback? onAlternarReplegado;

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

            // --- Pie: replegar (cuando no hay cabecera) y cerrar sesión --------
            const Divider(height: 1),
            if (replegado && onAlternarReplegado != null)
              IconButton(
                tooltip: 'Desplegar menú',
                onPressed: onAlternarReplegado,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
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

    final conTooltip = replegado || !item.disponible
        ? Tooltip(
            message: replegado
                ? item.titulo
                : '${item.titulo} — pendiente de construir',
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
//  Contenedor de contenido
// -----------------------------------------------------------------------------

/// Envuelve el contenido de una sección con márgenes, migas de pan y ancho
/// máximo.
///
/// El ancho máximo existe por legibilidad: en un monitor ancho, una línea de
/// texto que ocupe los 2500 px es incómoda de leer porque el ojo pierde el
/// principio de la línea siguiente.
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
        return SingleChildScrollView(
          padding: EdgeInsets.all(esAngosto ? 16 : 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: anchoMaximo),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (migas.isNotEmpty) MigasDePan(partes: migas),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
