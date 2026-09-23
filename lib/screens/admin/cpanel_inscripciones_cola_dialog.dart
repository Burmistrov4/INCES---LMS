import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/inscripcion.dart';
import '../../repositories/inscripcion_repository.dart';
import '../../widgets/comunes.dart';

/// Diálogo con la cola FIFO de una sección (Módulo 4, vista del admin).
///
/// La cola es la lista de `WAITLISTED` en orden de llegada: la base calcula
/// la `posicionEnCola`. Aquí la pintamos en ese orden con su número bien
/// grande, para que un administrador pueda decir de un vistazo «el tercero
/// está a dos puestos del asiento».
///
/// Diseñado como widget top-level (no método del panel) para poder
/// probarlo aislado en `test/cpanel_inscripciones_cola_dialog_test.dart`,
/// siguiendo el mismo criterio que el resto de paneles del cPanel.
class ColaSeccionDialog extends StatefulWidget {
  const ColaSeccionDialog({
    super.key,
    required this.repo,
    required this.seccionId,
    required this.seccionNombre,
  });

  final AdminInscripcionesRepository repo;
  final String seccionId;
  final String seccionNombre;

  @override
  State<ColaSeccionDialog> createState() => _ColaSeccionDialogState();
}

class _ColaSeccionDialogState extends State<ColaSeccionDialog> {
  late Future<Result<List<InscripcionDetallada>>> _futuro =
      widget.repo.obtenerCola(widget.seccionId);

  void _reintentar() {
    setState(() {
      _futuro = widget.repo.obtenerCola(widget.seccionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cola — ${widget.seccionNombre}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Orden de llegada. La base calcula la posición; aquí '
                          'sólo la mostramos.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<Result<List<InscripcionDetallada>>>(
                  future: _futuro,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final resultado = snap.data;
                    if (resultado == null) {
                      return const PanelVacio(
                        titulo: 'Sin respuesta',
                        mensaje: 'La consulta no devolvió datos.',
                        icono: Icons.help_outline_rounded,
                      );
                    }
                    return resultado.when(
                      success: (cola) {
                        if (cola.isEmpty) {
                          return const PanelVacio(
                            titulo: 'Nadie en cola',
                            mensaje:
                                'Aún no hay estudiantes en lista de espera '
                                'para esta sección.',
                            icono: Icons.people_outline_rounded,
                          );
                        }
                        return _ListaCola(cola: cola);
                      },
                      failure: (fallo) => _ErrorConReintento(
                        mensaje: fallo.message,
                        onReintentar: _reintentar,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListaCola extends StatelessWidget {
  const _ListaCola({required this.cola});

  final List<InscripcionDetallada> cola;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: cola.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = cola[i];
        final posicion = c.posicionEnCola ?? (i + 1);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(
              '$posicion',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(c.estudianteNombre ?? c.estudianteId),
          subtitle: Text(
            c.estudianteEmail ??
                'Inscripción ${c.id.substring(0, c.id.length < 8 ? c.id.length : 8)}',
          ),
        );
      },
    );
  }
}

class _ErrorConReintento extends StatelessWidget {
  const _ErrorConReintento({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            // El título dice QUÉ falló, no repite la palabra «error»: el
            // mensaje traducido de AppException ya empieza por «Ocurrió un
            // error…», y duplicarlo deja al usuario sin información nueva.
            Text(
              'No se pudo cargar la cola',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
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
}

/// Helper para abrir el diálogo desde el panel de ocupación.
///
/// Se exporta como función para que el panel no tenga que importar
/// `ColaSeccionDialog` y para centralizar el `showDialog` con sus claves
/// semánticas y el formateo del título.
Future<void> mostrarColaDeSeccion({
  required BuildContext context,
  required AdminInscripcionesRepository repo,
  required String seccionId,
  required String seccionNombre,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ColaSeccionDialog(
      repo: repo,
      seccionId: seccionId,
      seccionNombre: seccionNombre,
    ),
  );
}