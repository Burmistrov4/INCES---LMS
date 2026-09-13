import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/invitacion_docente.dart';
import '../../repositories/invitacion_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Panel de invitación de docentes (Módulo 1 del cPanel).
///
/// El administrador introduce el correo; el backend genera un token de un solo
/// uso, crea el usuario como docente al consumirlo y devuelve el enlace de
/// activación. Como el correo puede no llegar (Resend sin dominio verificado),
/// el enlace también se muestra aquí para copiarlo o reenviarlo por otro medio.
class CpanelInvitacionesPanel extends StatefulWidget {
  const CpanelInvitacionesPanel({super.key, this.repositorio});

  final InvitacionRepository? repositorio;

  @override
  State<CpanelInvitacionesPanel> createState() =>
      _CpanelInvitacionesPanelState();
}

class _CpanelInvitacionesPanelState extends State<CpanelInvitacionesPanel> {
  late final InvitacionRepository _repo =
      widget.repositorio ?? InvitacionRepository();

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();

  bool _isLoading = false;
  String? _error;
  InvitacionDocente? _invitacion;

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _invitacion = null;
    });

    final resultado = await _repo.invitarDocente(_emailController.text);

    // El estado de carga se libera ANTES de comprobar `mounted`: al revés, un
    // desmontaje durante la petición dejaría el botón bloqueado para siempre.
    if (mounted) setState(() => _isLoading = false);
    if (!mounted) return;

    resultado.when(
      success: (invitacion) {
        setState(() => _invitacion = invitacion);
        mostrarAviso(context, 'Invitación enviada.', exito: true);
      },
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Invitación de docentes',
          subtitulo: 'Registra un nuevo docente por correo. El enlace de '
              'activación caduca en 48 horas.',
        ),
        const SizedBox(height: 16),
        const AvisoEnLinea(
          texto: 'El docente recibe un enlace para fijar su contraseña. Si el '
              'correo no llega, el mismo enlace se muestra abajo para '
              'reenviarlo por otro medio.',
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.send,
                  onFieldSubmitted: (_) => _enviar(),
                  style: theme.textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    labelText: 'Correo del docente',
                    prefixIcon: Icon(Icons.mail_outline, size: 20),
                    hintText: 'nombre@dominio.edu.ve',
                  ),
                  validator: (valor) {
                    final texto = valor?.trim() ?? '';
                    if (texto.isEmpty) {
                      return 'Ingresa el correo del docente.';
                    }
                    if (!RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$')
                        .hasMatch(texto)) {
                      return 'Formato de correo no válido.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _enviar,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Enviar invitación'),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: IncesTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              border: Border.all(
                color: IncesTheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: IncesTheme.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: IncesTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_invitacion != null) _EnlaceActivacion(invitacion: _invitacion!),
      ],
    );
  }
}

class _EnlaceActivacion extends StatelessWidget {
  const _EnlaceActivacion({required this.invitacion});

  final InvitacionDocente invitacion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entregado = invitacion.correoEnviado;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.link_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Enlace de activación', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: entregado
                          ? IncesTheme.exito.withValues(alpha: 0.12)
                          : IncesTheme.advertencia.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      entregado ? 'Correo enviado' : 'Correo no entregado',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: entregado
                            ? IncesTheme.exito
                            : IncesTheme.advertencia,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                invitacion.enlaceActivacion,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Caduca: ${invitacion.expiraEn}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!entregado) ...[
                const SizedBox(height: 10),
                const AvisoEnLinea(
                  tono: TonoAviso.advertencia,
                  icono: Icons.warning_amber_outlined,
                  texto: 'El correo no pudo entregarse (dominio de Resend sin '
                      'verificar). Comparte este enlace por otro medio: es la '
                      'vía de activación.',
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: invitacion.enlaceActivacion),
                    );
                    if (context.mounted) {
                      mostrarAviso(context, 'Enlace copiado.', exito: true);
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copiar enlace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
