import 'package:flutter/material.dart';

import '../../services/asistencia_service.dart';

/// Marcaje de asistencia del estudiante (M7).
///
/// **Por qué un campo de texto y no sólo la cámara.** La cámara escanea el QR
/// del pizarra —eso sigue—, y cuando no está disponible o la guardia privada
/// de un móvil la bloquea, el mismo código se puede **teclear**: la página de
/// validación de la base (RLS) no sabe si el código llegó por un escaneo o por
/// seis dedos rápidos. La ventana de 15 segundos es el único guardián serio.
class MarcarAsistenciaPanel extends StatefulWidget {
  const MarcarAsistenciaPanel({super.key, this.servicio});

  /// Opcional, sólo para las pruebas: inyectar un servicio falso.
  final AsistenciaService? servicio;

  @override
  State<MarcarAsistenciaPanel> createState() => _MarcarAsistenciaPanelState();
}

/// El QR que el docente proyecta es `<uuid>:<6 dígitos>`. Esta parte aísla el
/// par: sin UUID válido el cliente no tiene sesión; sin dígitos no tiene código.
class ParseQr {
  ParseQr({required this.sesionId, required this.codigo});

  final String sesionId;
  final String codigo;

  static ParseQr? de(String texto) {
    final limpio = texto.trim();
    final punto = limpio.indexOf(':');
    if (punto < 1) return null;
    final sesionId = limpio.substring(0, punto);
    final codigo = limpio.substring(punto + 1);
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(sesionId)) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) return null;
    return ParseQr(sesionId: sesionId, codigo: codigo);
  }
}

class _MarcarAsistenciaPanelState extends State<MarcarAsistenciaPanel> {
  late final AsistenciaService _servicio = widget.servicio ?? AsistenciaService();
  final _entrada = TextEditingController();
  bool _ocupado = false;

  String? _mensajeError;
  bool _hecho = false;

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  Future<void> _marcar() async {
    final par = ParseQr.de(_entrada.text);
    if (par == null) {
      setState(() {
        _mensajeError =
            'El código no tiene la forma del QR. Pégalo tal cual: `<uuid>:<6 dígitos>`.';
      });
      return;
    }

    setState(() { _ocupado = true; _mensajeError = null; });

    final resultado = await _servicio.marcar(sesionId: par.sesionId, codigo: par.codigo);
    resultado.when(
      success: (_) => setState(() { _ocupado = false; _hecho = true; }),
      failure: (e) => setState(() {
        _ocupado = false;
        _mensajeError = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.qr_code_scanner, size: 48),
              const SizedBox(height: 8),
              Text(
                _hecho ? 'Listo. Ya cuentas.' : 'Marca tu asistencia',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _hecho
                    ? 'La marca ya está guardada y el docente la ve en su pantalla.'
                    : 'Escanea el QR de la pizarra o escribe el código que aparece. Caduca cada pocos segundos.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _entrada,
                enabled: !_hecho && !_ocupado,
                decoration: InputDecoration(
                  labelText: 'Código',
                  hintText: 'ej: 471212',
                  border: const OutlineInputBorder(),
                  errorText: _mensajeError,
                ),
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.number,
                maxLength: 6,
                onSubmitted: (_) => _marcar(),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _ocupado || _hecho ? null : _marcar,
                icon: _ocupado
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check),
                label: Text(_hecho ? 'Marcada' : 'Marcar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
