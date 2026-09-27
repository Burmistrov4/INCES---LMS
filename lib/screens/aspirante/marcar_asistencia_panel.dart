import 'package:flutter/material.dart';

import '../../services/asistencia_service.dart';

/// Marcaje de asistencia del estudiante (M7).
///
/// **Por qué un campo de texto.** Hoy es la **única** vía de entrada: no hay
/// cámara en este panel ni en el resto del cliente (`pubspec.yaml` sólo trae
/// `qr_flutter`, que **pinta** QR, no los lee). El campo acepta el código tal
/// como lo codifica la pizarra —`<uuid>:<6 dígitos>`— porque es lo que exige
/// tanto el `ParseQr` de aquí abajo como el cuerpo de `POST /asistencia/marcar`
/// (`{ sesionId, codigo }`): sin el UUID no hay sesión que marcar.
///
/// **El campo NO limita el largo, y es deliberado.** Hasta el 2026-09-27 llevaba
/// `maxLength: 6` y `keyboardType: number`, así que sólo admitía seis dígitos
/// mientras `ParseQr` exige 43 caracteres: `ParseQr.de()` devolvía `null`
/// **siempre** y la pantalla contestaba «el código no tiene la forma del QR»
/// hiciera lo que hiciera el alumno. Estaba muerta y nadie lo había visto.
/// Ver **D21** en `ESTADO_DEL_SISTEMA.md`; `test/asistencia_paneles_test.dart`
/// lo fija con una prueba que afirma el contenido del campo.
///
/// **Deuda de diseño declarada, no resuelta aquí:** teclear (o pegar) un UUID a
/// mano es mal UX, y sin cámara no hay atajo. Las dos salidas honestas —añadir
/// un lector (`mobile_scanner`) o una ruta que resuelva la sesión abierta a
/// partir de los seis dígitos— son decisiones de producto, no un arreglo
/// mecánico. La ventana de 15 segundos sigue siendo el único guardián serio.
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
                  // La pista tiene que mostrar la forma REAL: con `ej: 471212`
                  // el alumno escribía seis dígitos y el parser los rechazaba
                  // —el UUID es obligatorio—, así que la ayuda y el error se
                  // contradecían entre sí. Ver D21.
                  hintText: '<uuid>:471212',
                  border: const OutlineInputBorder(),
                  errorText: _mensajeError,
                ),
                textInputAction: TextInputAction.done,
                // `text`, no `number`: un teclado numérico no puede producir ni
                // el UUID ni los dos puntos.
                keyboardType: TextInputType.text,
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
