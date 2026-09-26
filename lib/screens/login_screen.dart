import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/screens/aspirante_form_screen.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';

/// Pantalla de inicio de sesión.
///
/// ## Qué cambió en el rediseño
///
/// Antes era una tarjeta oscura sobre fondo oscuro. Funcionaba, pero la
/// aplicación entera se veía apagada y el contraste entre una pantalla de acceso
/// institucional y una herramienta cualquiera era nulo. Ahora hay un **panel de
/// marca** a la izquierda —degradado institucional, nombre del centro y sede— y
/// la tarjeta del formulario a la derecha.
///
/// En pantallas angostas el panel de marca desaparece en lugar de encogerse: un
/// degradado de 60 px de ancho no comunica nada y roba sitio al formulario.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  final AuthService _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;

  /// Ancho a partir del cual se muestra el panel de marca lateral.
  static const double _anchoConPanelMarca = 900;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Guarda de reentrada. Sin esto, pulsar Enter dos veces (o Enter mientras
    // un intento está en vuelo) lanza dos peticiones en paralelo: la segunda
    // compite con la primera y el último `setState` gana, así que el estado de
    // carga puede quedar desincronizado con la realidad.
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final resultado = await _authService.iniciarSesion(
      identificador: _identifierController.text,
      password: _passwordController.text,
    );

    // `_isLoading` se libera ANTES de comprobar `mounted`.
    //
    // El orden importa: si el widget se desmonta mientras la petición viaja
    // (el usuario navega, cierra la pestaña, el AuthGate cambia de pantalla),
    // un `return` temprano dejaría `_isLoading` en `true` para siempre. Al
    // volver a esta pantalla, los campos seguirían deshabilitados y la interfaz
    // parecería congelada sin causa visible.
    if (mounted) setState(() => _isLoading = false);

    if (!mounted) return;

    resultado.when(
      // El AuthGate escucha los cambios de sesión y enruta al panel del rol.
      success: (_) => _cerrarSiFueEmpujada(),
      failure: (AppException error) => _showError(error.message),
    );
  }

  /// Cierra esta pantalla si se abrió **empujada** sobre el `AuthGate`.
  ///
  /// El `AuthGate` es la raíz y ya está reconstruyendo hacia el panel del rol
  /// cuando la sesión cambia. Pero si el login se abrió empujado —desde el botón
  /// «Portal Académico» de la portada—, esa ruta empujada quedaría **por encima**
  /// del panel reconstruido y el usuario seguiría viendo el formulario de acceso
  /// con la sesión ya iniciada. Hay que cerrarla.
  ///
  /// Si el login es hijo directo del `AuthGate` no hay nada que cerrar: es la
  /// primera ruta y `canPop()` es falso, así que esto no hace nada.
  void _cerrarSiFueEmpujada() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((ruta) => ruta.isFirst);
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: IncesTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(IncesTheme.radioControl),
          ),
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Envía el correo de recuperación.
  ///
  /// Reutiliza el identificador ya escrito en el formulario: quien olvidó la
  /// contraseña acaba de teclear su correo, y volver a pedírselo en un diálogo
  /// es una fricción gratuita.
  ///
  /// Si el campo parece una cédula (no tiene `@`), se avisa en lugar de enviar:
  /// Supabase necesita un correo, y el mensaje genérico de «credenciales
  /// inválidas» no serviría aquí.
  Future<void> _handleRecuperacion() async {
    if (_isLoading) return;

    final identificador = _identifierController.text.trim();

    if (!identificador.contains('@')) {
      _showError(
        'Escribe tu correo en el primer campo para enviarte el enlace.',
      );
      return;
    }

    setState(() => _isLoading = true);
    final resultado = await _authService.enviarCorreoRecuperacion(identificador);

    // Mismo criterio que en `_handleLogin`: liberar el estado de carga antes
    // del `return` por desmontaje, para no dejar los campos bloqueados.
    if (mounted) setState(() => _isLoading = false);
    if (!mounted) return;

    resultado.when(
      success: (_) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: IncesTheme.exito,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              ),
              content: Row(
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Si el correo está registrado, recibirás un enlace para '
                      'restablecer tu contraseña.',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
      },
      failure: (excepcion) => _showError(excepcion.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esAngosto = MediaQuery.sizeOf(context).width < _anchoConPanelMarca;

    return Scaffold(
      body: Row(
        children: [
          if (!esAngosto) const Expanded(flex: 5, child: _PanelMarca()),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _formulario(theme),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulario(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En móvil el panel de marca no se ve, así que la identidad tiene que
        // aparecer aquí. Se muestra sólo cuando el panel está oculto para no
        // repetir el nombre del centro dos veces en la misma pantalla.
        if (MediaQuery.sizeOf(context).width < _anchoConPanelMarca) ...[
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('INCES LMS', style: theme.textTheme.titleMedium),
                    Text(
                      'La Isabelica',
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
          const SizedBox(height: 28),
        ],
        Text('Iniciar sesión', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Accede con tu cédula o tu correo institucional.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _identifierController,
                // NOTA: los campos NO se deshabilitan durante la carga.
                //
                // Aquí había `enabled: !_isLoading`, y era un error: al pulsar
                // Enter en este campo se disparaba el inicio de sesión, que ponía
                // `_isLoading = true` y **deshabilitaba el campo de contraseña
                // mientras el usuario aún escribía**. Un campo que deja de
                // aceptar texto sin explicación es indistinguible de una
                // aplicación colgada. Se bloquea el BOTÓN, no el campo.
                style: theme.textTheme.bodyMedium,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                // Mueve el foco al campo de contraseña.
                //
                // `TextInputAction.next` NO lo hace: sólo cambia la tecla que
                // dibuja el teclado. Sin este callback, pulsar Enter lanzaba el
                // inicio de sesión con la contraseña vacía.
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Cédula o Correo',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Ingresa tu cédula o correo';
                  }
                  if (text.contains('@') &&
                      !RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(text)) {
                    return 'Ingresa un correo válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                style: theme.textTheme.bodyMedium,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                obscureText: _obscurePassword,
                onFieldSubmitted: (_) => _handleLogin(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Mostrar contraseña'
                        : 'Ocultar contraseña',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa tu contraseña';
                  }
                  return null;
                },
              ),

              // Enlace de recuperación alineado a la derecha, pegado al campo al
              // que pertenece: en una pantalla de acceso, un enlace huérfano en
              // el centro se pierde.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading ? null : _handleRecuperacion,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Ingresar al sistema'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: theme.colorScheme.outline)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '¿Eres nuevo?',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Expanded(child: Divider(color: theme.colorScheme.outline)),
          ],
        ),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: _isLoading
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AspiranteFormScreen(),
                    ),
                  ),
          icon: const Icon(Icons.assignment_outlined, size: 18),
          label: const Text('Inscribirme como aspirante'),
        ),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Acceso restringido al personal autorizado',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Panel de marca: identidad institucional a la izquierda del formulario.
class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: IncesTheme.degradadoAzul),
      child: Stack(
        children: [
          // Círculos decorativos con muy baja opacidad. Su función es dar
          // profundidad al degradado plano, que si no se ve como un rectángulo
          // de color sin más. Al 6 % no compiten con el texto.
          Positioned(top: -60, right: -60, child: _circulo(220, 0.06)),
          Positioned(bottom: -80, left: -40, child: _circulo(260, 0.05)),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    'I',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Sistema de Gestión\nAcadémica',
                  style: GoogleFonts.inter(
                    fontSize: 30,
                    height: 1.24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 44,
                  height: 3,
                  decoration: BoxDecoration(
                    color: IncesTheme.rojoInces,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'CFS Nacional de Soldadura\n«Rafael Urdaneta»',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'INCES La Isabelica',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 40),
                // Nota de alcance: deja claro frente a un evaluador o un
                // docente qué cubre el sistema hoy, sin prometer lo que aún no
                // existe.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(IncesTheme.radioTarjeta),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Plataforma académica a la medida del INCES: '
                          'inscripciones, control de aulas y administración '
                          'centralizada.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circulo(double tamano, double opacidad) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacidad),
      ),
    );
  }
}
