import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pantalla final del onboarding.
///
/// Cubre los dos desenlaces reales del registro:
///  - **Con sesión activa** (confirmación de correo desactivada): el aspirante
///    ya está dentro y el `AuthGate` mostrará su panel al volver a la raíz.
///  - **Sin sesión** (confirmación de correo activada): debe revisar su bandeja
///    antes de poder entrar.
class RegistroExitosoScreen extends StatelessWidget {
  final String email;
  final bool requiereTutorLegal;
  final bool requiereConfirmacionEmail;
  final bool sesionIniciada;

  const RegistroExitosoScreen({
    super.key,
    required this.email,
    required this.requiereTutorLegal,
    this.requiereConfirmacionEmail = true,
    this.sesionIniciada = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIcono(),
                const SizedBox(height: 24),
                Text(
                  _titulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _subtitulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                _buildPanelProximosPasos(),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      // Vuelve a la raíz: el AuthGate decide qué mostrar según
                      // haya sesión o no (panel del aspirante o login).
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      sesionIniciada
                          ? 'Ir a mi panel'
                          : 'Ir al inicio de sesión',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcono() {
    final confirmando = requiereConfirmacionEmail && !sesionIniciada;
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Icon(
        confirmando
            ? Icons.mark_email_read_outlined
            : Icons.check_circle_outline,
        color: Colors.green,
        size: 36,
      ),
    );
  }

  Widget _buildPanelProximosPasos() {
    final pasos = <Widget>[
      if (requiereConfirmacionEmail && !sesionIniciada)
        _buildPaso(
          Icons.email_outlined,
          'Confirma tu correo electrónico para activar la cuenta.',
        )
      else
        _buildPaso(
          Icons.verified_outlined,
          'Tu cuenta ya está activa y con sesión iniciada.',
        ),
      _buildPaso(
        Icons.how_to_reg_outlined,
        'Podrás ingresar con tu cédula o correo y la contraseña que creaste.',
      ),
      if (requiereTutorLegal)
        _buildPaso(
          Icons.family_restroom,
          'Tu representante legal será contactado para validar la inscripción.',
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Próximos pasos',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < pasos.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            pasos[i],
          ],
        ],
      ),
    );
  }

  String get _titulo => sesionIniciada
      ? 'Inscripción completada'
      : 'Inscripción registrada';

  String get _subtitulo => sesionIniciada
      ? 'Tu ficha quedó guardada y tu cuenta está lista.'
      : 'Enviamos las instrucciones de confirmación a:';

  Widget _buildPaso(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF94A3B8), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
