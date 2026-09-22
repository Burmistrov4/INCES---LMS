import 'package:flutter/material.dart';

import '../core/gateways/aula_gateway.dart';
import '../core/result.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';

/// Creación de un anuncio del Tablón (Centro de Mando del docente, M6).
///
/// Form mínimo: título obligatorio, cuerpo opcional y publicación diferida
/// opcional. Al guardar llama a [AulaGateway.crearAnuncio]; el backend decide si
/// el llamante puede publicar (RLS) y devuelve el anuncio ya creado. Esta
/// pantalla **no** reescribe la autorización: si la RLS lo prohíbe, el error
/// sube y se muestra tal cual (ADR-003).
///
/// Es una pantalla aparte y no un diálogo porque el cuerpo es multilínea y el
/// espacio importa; además así se puede abrir desde el botón «Nuevo anuncio» del
/// tablón del docente y volver a él al cerrar.
class CrearAnuncioPanel extends StatefulWidget {
  const CrearAnuncioPanel({
    super.key,
    required this.seccionId,
    required this.gateway,
    this.onGuardado,
  });

  final String seccionId;
  final AulaGateway gateway;

  /// Se invoca tras un guardado exitoso, antes de cerrar. Permite al llamante
  /// recargar el tablón sin acoplar esta pantalla a quién la abrió.
  final VoidCallback? onGuardado;

  @override
  State<CrearAnuncioPanel> createState() => _CrearAnuncioPanelState();
}

class _CrearAnuncioPanelState extends State<CrearAnuncioPanel> {
  final _forma = GlobalKey<FormState>();
  final _controlTitulo = TextEditingController();
  final _controlCuerpo = TextEditingController();
  DateTime? _programadoPara;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _controlTitulo.dispose();
    _controlCuerpo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_forma.currentState!.validate()) return;
    if (_guardando) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = await Result.guard(
      () => widget.gateway.crearAnuncio(
        seccionId: widget.seccionId,
        titulo: _controlTitulo.text.trim(),
        cuerpo: _controlCuerpo.text.trim(),
        programadoPara: _programadoPara,
      ),
    );

    // El estado de carga se libera antes del `return` por desmontaje: al revés,
    // un cierre durante la petición dejaría el botón bloqueado para siempre.
    if (!mounted) return;
    setState(() => _guardando = false);

    resultado.when(
      success: (_) {
        widget.onGuardado?.call();
        Navigator.of(context).pop(true);
      },
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  Future<void> _elegirProgramacion() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _programadoPara ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: _programadoPara != null
          ? TimeOfDay.fromDateTime(_programadoPara!)
          : const TimeOfDay(hour: 8, minute: 0),
    );
    if (hora == null || !mounted) return;

    setState(() {
      _programadoPara = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Scaffold propio: el panel se abre como ruta aparte y el `MaterialPageRoute`
    // no inyecta Material. Sin esto, el `TextFormField` revienta con «No Material
    // widget found» —en pruebas y en producción por igual.
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo anuncio')),
      body: ContenidoSeccion(
        migas: const ['Inicio', 'Académico', 'Aula Virtual', 'Nuevo anuncio'],
        child: Form(
        key: _forma,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TituloSeccion(
              'Nuevo anuncio',
              subtitulo: 'Se publicará en el tablón de esta sección.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controlTitulo,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (valor) =>
                  (valor == null || valor.trim().isEmpty)
                      ? 'Escribe un título.'
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controlCuerpo,
              decoration: const InputDecoration(
                labelText: 'Cuerpo (opcional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Publicación diferida'),
              subtitle: _programadoPara == null
                  ? const Text('Se publica en cuanto guardes.')
                  : Text(_textoFecha(_programadoPara!)),
              trailing: _programadoPara == null
                  ? null
                  : IconButton(
                      tooltip: 'Quitar programación',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _programadoPara = null),
                    ),
              onTap: _elegirProgramacion,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AvisoEnLinea(
                tono: TonoAviso.peligro,
                icono: Icons.error_outline,
                texto: _error!,
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.campaign_outlined, size: 18),
                label: Text(_guardando ? 'Guardando…' : 'Publicar anuncio'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Quién puede publicar lo decide el centro; si no tienes permiso '
              'sobre esta sección, el guardado lo dirá.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          ),
        ),
      ),
    ),
    );
  }

  String _textoFecha(DateTime fecha) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${fecha.year}-${pad(fecha.month)}-${pad(fecha.day)} '
        '${pad(fecha.hour)}:${pad(fecha.minute)}';
  }
}
