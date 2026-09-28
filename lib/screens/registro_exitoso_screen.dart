import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/planilla_pdf_service.dart';
import '../theme/inces_theme.dart';

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
///
/// ## Por qué esta pantalla dejó de ser oscura
///
/// Estaba forzada a `#0F172A` con literales, así que con `ThemeMode.system` en
/// claro el aspirante aterrizaba en una pantalla oscura justo después de
/// registrarse — y el resto de la aplicación es claro. Los literales eran los
/// valores de `IncesTheme.fondoOscuro` y compañía, así que la pantalla *parecía*
/// seguir el sistema de diseño sin seguirlo: tomaba la paleta oscura y la
/// ignoraba cuando el sistema pedía la clara.
///
/// Ahora todo sale del `ColorScheme` del tema. Un literal de color que quede
/// aquí es un color que no sigue al tema, y eso es lo que se retiró.
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

  /// Lleva al usuario al destino correcto según haya sesión o no.
  ///
  /// **Con sesión activa** («Ir a mi panel») basta con desapilar hasta la raíz:
  /// la raíz es el `AuthGate`, que con sesión ya resuelve el panel del rol.
  ///
  /// **Sin sesión** («Ir al inicio de sesión») hay que REEMPLAZAR el historial
  /// entero. `popUntil(isFirst)` ya no sirve: desde que existe la portada
  /// pública, la raíz sin sesión es la Landing, así que desapilar dejaba al
  /// aspirante en la portada —con un botón «Inscribirse» que vuelve a empezar—
  /// en vez de en el formulario de acceso. `pushNamedAndRemoveUntil` con el
  /// predicado `(route) => false` vacía la pila y monta `/login` limpio, de modo
  /// que el botón «atrás» no puede devolverlo a esta pantalla de éxito.
  ///
  /// No se unifica en una sola llamada a propósito: mandar a `/login` a quien
  /// ya tiene sesión sería un retroceso —el login no es su destino—, y ese es
  /// exactamente el caso «Ir a mi panel».
  void _irAlDestino() {
    final navigator = Navigator.of(context);
    if (sesionIniciada) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
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
                // Blanco sobre el color de estado: el aviso va sobre un fondo
                // saturado, y ahí el `onSurface` del tema sería ilegible.
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(mensaje)),
            ],
          ),
          // `IncesTheme.exito` y `.error` y no literales: son los mismos tonos
          // que usa el resto de la aplicación para decir «bien» y «mal».
          backgroundColor: esError ? IncesTheme.error : IncesTheme.exito,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IncesTheme.radioControl),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // Sin `backgroundColor`: lo pone el tema. Ésta era la pantalla que se
      // quedaba oscura en un sistema en claro.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta + 4),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIcono(theme),
                const SizedBox(height: 24),
                Text(
                  _titulo,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _subtitulo,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                _buildPanelProximosPasos(theme),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _descargando
                            ? 'Generando PDF…'
                            : 'Descargar mi planilla (PDF)',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  // Sin `styleFrom`: el tema ya da el azul institucional y la
                  // forma. Sobrescribirlo era lo que metía un azul distinto.
                  child: ElevatedButton(
                    onPressed: _irAlDestino,
                    child: Text(
                      sesionIniciada
                          ? 'Ir a mi panel'
                          : 'Ir al inicio de sesión',
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

  Widget _buildIcono(ThemeData theme) {
    final confirmando = requiereConfirmacionEmail && !sesionIniciada;
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: IncesTheme.exito.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta + 4),
        border: Border.all(color: IncesTheme.exito.withValues(alpha: 0.4)),
      ),
      child: Icon(
        confirmando
            ? Icons.mark_email_read_outlined
            : Icons.check_circle_outline,
        color: IncesTheme.exito,
        size: 36,
      ),
    );
  }

  Widget _buildPanelProximosPasos(ThemeData theme) {
    final pasos = <Widget>[
      if (requiereConfirmacionEmail && !sesionIniciada)
        _buildPaso(
          theme,
          Icons.email_outlined,
          'Confirma tu correo electrónico para activar la cuenta.',
        )
      else
        _buildPaso(
          theme,
          Icons.verified_outlined,
          'Tu cuenta ya está activa y con sesión iniciada.',
        ),
      _buildPaso(
        theme,
        Icons.how_to_reg_outlined,
        'Podrás ingresar con tu cédula o correo y la contraseña que creaste.',
      ),
      if (requiereTutorLegal)
        _buildPaso(
          theme,
          Icons.family_restroom,
          'Tu representante legal será contactado para validar la inscripción.',
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Superficie hundida: en claro queda un gris frío y en oscuro un tono
        // por debajo de la tarjeta. El literal `#0F172A` daba el mismo bloque
        // casi negro en los dos modos.
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Próximos pasos', style: theme.textTheme.titleSmall),
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

  Widget _buildPaso(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
