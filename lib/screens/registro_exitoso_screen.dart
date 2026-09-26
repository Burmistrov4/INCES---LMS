import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/planilla_pdf_service.dart';

/// Pantalla final del onboarding.
///
/// Cubre los dos desenlaces reales del registro:
///  - **Con sesión activa** (confirmación de correo desactivada): el aspirante
///    ya está dentro y el `AuthGate` mostrará su panel al volver a la raíz.
///  - **Sin sesión** (confirmación de correo activada): debe revisar su bandeja
///    antes de poder entrar.
///
/// Cuando hay sesión activa, el aspirante ya tiene su ficha de aspirante y puede
/// descargar el PDF de su planilla del INCES —ya llena— directamente desde aquí.
/// El botón sólo se muestra en ese caso: sin sesión no hay JWT que enviar al
/// backend, y la descarga devolvería 401.
class RegistroExitosoScreen extends StatefulWidget {
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
    this.planillaService,
  });

  /// Inyectable para las pruebas.
  ///
  /// Sin esto la pantalla instancia el servicio real, que va por HTTP y al
  /// navegador, y ninguna prueba podría montarla sin red. Es el mismo patrón que
  /// ya usan los paneles del cPanel (`repositorio:`).
  final PlanillaPdfService? planillaService;

  @override
  State<RegistroExitosoScreen> createState() => _RegistroExitosoScreenState();
}

class _RegistroExitosoScreenState extends State<RegistroExitosoScreen> {
  late final PlanillaPdfService _planillaService;
  bool _descargando = false;

  @override
  void initState() {
    super.initState();
    _planillaService = widget.planillaService ?? PlanillaPdfService();
  }

  String get email => widget.email;
  bool get requiereTutorLegal => widget.requiereTutorLegal;
  bool get requiereConfirmacionEmail => widget.requiereConfirmacionEmail;
  bool get sesionIniciada => widget.sesionIniciada;

  Future<void> _descargarPlanilla() async {
    if (_descargando) return;
    setState(() => _descargando = true);

    final resultado = await _planillaService.descargarPlanillaPropia();
    if (!mounted) return;
    setState(() => _descargando = false);

    // `ResultadoDescargaPlanilla` es `sealed`, así que el `switch` es exhaustivo:
    // no hay un desenlace que se nos pueda escapar sin tratar.
    switch (resultado) {
      case PlanillaDescargada():
        _mostrarAviso(
          'Tu planilla se descargó. Ábrela o imprímela para conservar tu '
          'comprobante de inscripción.',
          esError: false,
        );
      case SinFichaDeAspirante():
        _mostrarAviso(
          'Aún no tienes una ficha de aspirante. Completa tu inscripción para '
          'poder descargar la planilla.',
          esError: true,
        );
      case ConsultaFallida(:final mensaje):
        _mostrarAviso(mensaje, esError: true);
      case DescargaFallida():
        _mostrarAviso(
          'No pudimos entregar el archivo a tu navegador. Inténtalo de nuevo.',
          esError: true,
        );
    }
  }

  void _mostrarAviso(String mensaje, {required bool esError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                esError ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(mensaje)),
            ],
          ),
          backgroundColor:
              esError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
  }

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
                if (sesionIniciada) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _descargando ? null : _descargarPlanilla,
                      icon: _descargando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _descargando
                            ? 'Generando PDF…'
                            : 'Descargar mi planilla (PDF)',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
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
