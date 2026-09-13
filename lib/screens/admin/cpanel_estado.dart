import 'package:flutter/material.dart';

/// Piezas comunes a los paneles del cPanel.
///
/// Los tres paneles (módulos, parámetros, auditoría) tienen los mismos tres
/// estados: cargando, error con reintento, y contenido. Duplicar esa lógica tres
/// veces garantizaba que una de las tres se quedara sin manejar el error —que es
/// justo el bug que se corrigió en la Fase 1—.

/// Envoltorio que resuelve los estados de carga y error de un panel.
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'No pudimos cargar esta sección',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh_rounded),
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

/// Cabecera de sección dentro de un panel.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.subtitulo});

  final String texto;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(subtitulo!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Aviso informativo, para explicar reglas que el usuario no puede deducir.
class Aviso extends StatelessWidget {
  const Aviso({super.key, required this.texto, this.icono = Icons.info_outline});

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

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
void mostrarAviso(BuildContext context, String mensaje, {bool error = false}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? theme.colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: error ? 6 : 3),
      ),
    );
}
