import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/inces_theme.dart';

/// Piezas de interfaz compartidas entre pantallas.
///
/// Viven aquí y no dentro de una pantalla concreta porque las usan varias. La
/// alternativa —copiar el widget— es la causa de que el login y los paneles
/// tuvieran azules distintos: dos copias del «mismo» componente se desvían en
/// cuanto alguien ajusta una.

// -----------------------------------------------------------------------------
//  Encabezado institucional
// -----------------------------------------------------------------------------

/// Banner superior con la identidad del centro, el rol y el período activo.
///
/// Es el ancla visual de toda la aplicación: el usuario tiene que poder mirar
/// cualquier pantalla y saber dónde está y con qué rol, sin leer el menú.
class EncabezadoInstitucional extends StatelessWidget {
  const EncabezadoInstitucional({
    super.key,
    required this.rolEtiqueta,
    this.nombreUsuario,
    this.correoUsuario,
    this.periodoActivo,
    this.acciones = const [],
    this.onAbrirMenu,
  });

  final String rolEtiqueta;
  final String? nombreUsuario;
  final String? correoUsuario;

  /// Período académico activo (`2026-1`). Si es `null`, no se muestra la
  /// insignia: es preferible a mostrar un guion que no significa nada.
  final String? periodoActivo;

  final List<Widget> acciones;

  /// Si se pasa, aparece el botón de menú. Sólo en pantallas angostas, donde la
  /// barra lateral pasa a ser un cajón.
  final VoidCallback? onAbrirMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;

    // El saludo usa sólo el primer nombre si hay nombre completo: «Bienvenido,
    // Lorenzo Roca» es más largo y el encabezado tiene que caber en una línea.
    final saludo = nombreUsuario == null || nombreUsuario!.trim().isEmpty
        ? 'Bienvenido'
        : 'Bienvenido, ${nombreUsuario!.trim().split(' ').first}';

    return Container(
      decoration: BoxDecoration(
        color: esOscuro
            ? IncesTheme.superficieOscura
            : IncesTheme.superficieClara,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Franja de marca: 3 px de degradado azul→rojo. Es la firma visual más
          // barata y reconocible; basta para que la aplicación se lea como
          // institucional sin ocupar espacio útil.
          Container(height: 3, decoration:
              const BoxDecoration(gradient: IncesTheme.degradadoMarca)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (onAbrirMenu != null) ...[
                  IconButton(
                    tooltip: 'Menú',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: onAbrirMenu,
                  ),
                  const SizedBox(width: 4),
                ],
                const _EscudoInces(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        saludo,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      // `Wrap` y no `Row`: en móvil el rol y el período no caben
                      // junto al nombre y deben poder saltar de línea en vez de
                      // desbordar.
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _InsigniaRol(etiqueta: rolEtiqueta),
                          if (periodoActivo != null)
                            _InsigniaPeriodo(periodo: periodoActivo!),
                          if (correoUsuario != null)
                            Text(
                              correoUsuario!,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                ...acciones,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Escudo con las iniciales del centro, sobre degradado institucional.
///
/// No es el logotipo real del INCES —no se dispone de la versión vectorial— y
/// por eso **no se dibuja una imitación**: una aproximación chapucera del
/// logotipo oficial es peor que no ponerlo. Es una marca tipográfica neutra,
/// fácil de sustituir por el archivo real cuando se tenga.
class _EscudoInces extends StatelessWidget {
  const _EscudoInces();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: IncesTheme.degradadoAzul,
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      ),
      child: Text(
        'I',
        style: GoogleFonts.inter(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _InsigniaRol extends StatelessWidget {
  const _InsigniaRol({required this.etiqueta});

  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        etiqueta,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _InsigniaPeriodo extends StatelessWidget {
  const _InsigniaPeriodo({required this.periodo});

  final String periodo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Período académico activo',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              periodo,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Migas de pan
// -----------------------------------------------------------------------------

/// Ruta de navegación. Evita que el usuario pierda el contexto.
///
/// El último elemento nunca es pulsable: es la página actual, y ofrecer un
/// enlace a donde ya se está no aporta nada.
class MigasDePan extends StatelessWidget {
  const MigasDePan({super.key, required this.partes});

  /// De la raíz a la página actual. El último es el actual.
  final List<String> partes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (partes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < partes.length; i++) ...[
            if (i > 0)
              Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            Text(
              partes[i],
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: i == partes.length - 1
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: i == partes.length - 1
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Tarjeta de módulo
// -----------------------------------------------------------------------------

/// Tarjeta de módulo con cabecera de marca, estado y micro-interruptor.
///
/// Sustituye la fila plana del panel anterior. La fila obligaba a leer de
/// izquierda a derecha para saber qué estaba encendido; la tarjeta permite
/// reconocerlo por color y por badge antes de leer nada.
class TarjetaModulo extends StatelessWidget {
  const TarjetaModulo({
    super.key,
    required this.titulo,
    required this.estado,
    required this.icono,
    this.descripcion,
    this.rolesEtiquetas = const [],
    this.habilitado = false,
    this.guardando = false,
    this.candadoRazon,
    this.onAlternar,
    this.onEditarRoles,
  });

  final String titulo;
  final String? descripcion;
  final EstadoModulo estado;
  final IconData icono;

  /// Roles con acceso. Vacío = visible para todos.
  final List<String> rolesEtiquetas;

  final bool habilitado;
  final bool guardando;

  /// Si no es `null`, el interruptor se bloquea y el tooltip explica por qué.
  final String? candadoRazon;

  final ValueChanged<bool>? onAlternar;
  final VoidCallback? onEditarRoles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloqueado = candadoRazon != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera con el degradado de marca. Es la señal de «esto es un
          // módulo del sistema», y sólo se usa aquí.
          Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: bloqueado
                  // El módulo crítico cambia el degradado por el rojo sólido.
                  // El color transmite la restricción antes de que el usuario
                  // llegue a intentar pulsar.
                  ? const LinearGradient(
                      colors: [IncesTheme.rojoInces, IncesTheme.rojoInces],
                    )
                  : IncesTheme.degradadoMarca,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: estado.color.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(IncesTheme.radioControl),
                      ),
                      child: Icon(icono, size: 20, color: estado.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          _BadgeEstado(estado: estado),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // El interruptor se sustituye por un indicador mientras
                    // guarda. Es la única parte que se bloquea durante la
                    // petición: los campos y el botón de la tarjeta siguen
                    // vivos, porque el usuario no debería quedarse sin poder
                    // hacer nada por el guardado de otro módulo.
                    if (guardando)
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (bloqueado)
                      Tooltip(
                        message: candadoRazon!,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.lock_outline,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Switch(
                        value: habilitado,
                        onChanged: onAlternar,
                      ),
                  ],
                ),
                if (descripcion != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    descripcion!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _FilaRoles(etiquetas: rolesEtiquetas)),
                    if (onEditarRoles != null)
                      TextButton.icon(
                        onPressed: guardando ? null : onEditarRoles,
                        icon: const Icon(Icons.group_outlined, size: 15),
                        label: const Text('Roles'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeEstado extends StatelessWidget {
  const _BadgeEstado({required this.estado});

  final EstadoModulo estado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: estado.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icono, size: 11, color: estado.color),
          const SizedBox(width: 4),
          Text(
            estado.etiqueta,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: estado.color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaRoles extends StatelessWidget {
  const _FilaRoles({required this.etiquetas});

  final List<String> etiquetas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (etiquetas.isEmpty) {
      return Row(
        children: [
          Icon(
            Icons.public_outlined,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            'Todos los roles',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final etiqueta in etiquetas)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              etiqueta,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Tarjeta de métrica
// -----------------------------------------------------------------------------

/// Métrica rápida para la cabecera del Command Center.
class TarjetaMetrica extends StatelessWidget {
  const TarjetaMetrica({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.color,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acento = color ?? theme.colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: acento.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              ),
              child: Icon(icono, size: 19, color: acento),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valor,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    etiqueta,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Aviso
// -----------------------------------------------------------------------------

/// Aviso en línea, para explicar reglas que el usuario no puede deducir.
///
/// Se mantiene distinto del `SnackBar` a propósito: el SnackBar desaparece y
/// sirve para confirmar una acción; esto explica una regla vigente y tiene que
/// seguir visible mientras el usuario decide.
class AvisoEnLinea extends StatelessWidget {
  const AvisoEnLinea({
    super.key,
    required this.texto,
    this.icono = Icons.info_outline,
    this.tono = TonoAviso.info,
  });

  final String texto;
  final IconData icono;
  final TonoAviso tono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = switch (tono) {
      TonoAviso.info => theme.colorScheme.primary,
      TonoAviso.exito => IncesTheme.exito,
      TonoAviso.advertencia => IncesTheme.advertencia,
      TonoAviso.peligro => IncesTheme.rojoInces,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum TonoAviso { info, exito, advertencia, peligro }

// -----------------------------------------------------------------------------
//  Estados de carga y error
// -----------------------------------------------------------------------------

/// Envoltorio que resuelve los estados de carga y error de un panel.
///
/// Se conserva la lógica de la versión anterior —era correcta y evitaba que uno
/// de los tres paneles se quedara sin manejar el error— pero con la identidad
/// nueva.
class EstadoPanel extends StatelessWidget {
  const EstadoPanel({
    super.key,
    required this.cargando,
    required this.error,
    required this.onReintentar,
    required this.child,
  });

  final bool cargando;
  final String? error;
  final VoidCallback onReintentar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final mensaje = error;
    if (mensaje != null) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 26,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No pudimos cargar esta sección',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return child;
  }
}

/// Título de sección dentro de un panel.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.subtitulo, this.acciones});

  final String texto;
  final String? subtitulo;
  final List<Widget>? acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitulo!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...?acciones,
        ],
      ),
    );
  }
}

/// Estado vacío explicativo.
///
/// Un panel vacío sin texto deja al usuario sin saber si le falta un permiso,
/// si no hay datos, o si la aplicación falla. Las tres cosas se ven igual, así
/// que el vacío **siempre** dice cuál de las tres es.
class PanelVacio extends StatelessWidget {
  const PanelVacio({
    super.key,
    required this.titulo,
    required this.mensaje,
    required this.icono,
    this.nota,
  });

  final String titulo;
  final String mensaje;
  final IconData icono;

  /// Aclaración adicional sobre por qué está vacío (qué módulo falta, etc.).
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 30, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (nota != null) ...[
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AvisoEnLinea(texto: nota!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Utilidades
// -----------------------------------------------------------------------------

/// Formatea una fecha en algo legible sin depender de `intl`.
String formatearFechaHora(DateTime? fecha) {
  if (fecha == null) return '—';

  final local = fecha.toLocal();
  final dia = local.day.toString().padLeft(2, '0');
  final mes = local.month.toString().padLeft(2, '0');
  final hora = local.hour.toString().padLeft(2, '0');
  final minuto = local.minute.toString().padLeft(2, '0');

  return '$dia/$mes/${local.year} $hora:$minuto';
}

/// Muestra un mensaje temporal en la parte inferior.
///
/// Sustituye el `SnackBar` sin estilo por uno con icono y color según el tono:
/// el texto solo obliga a leer la frase entera para saber si algo salió bien.
void mostrarAviso(
  BuildContext context,
  String mensaje, {
  bool error = false,
  bool exito = false,
}) {
  if (!context.mounted) return;

  final theme = Theme.of(context);
  final color = error
      ? IncesTheme.error
      : exito
          ? IncesTheme.exito
          : null;

  // El icono depende del tono; el color del texto, de si hay tono o no. Un
  // SnackBar sin tono usa el color de acento del tema, que ya contrasta sobre
  // el fondo inverso.
  final colorContenido =
      color != null ? Colors.white : theme.colorScheme.onInverseSurface;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: error ? 6 : 3),
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline
                  : exito
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
              size: 19,
              color: colorContenido,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: colorContenido,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
