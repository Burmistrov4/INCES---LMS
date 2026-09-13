import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/screens/aspirante_form_screen.dart';
import 'package:inces_lms_app/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
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
      success: (_) {},
      failure: (AppException error) => _showError(error.message),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Si el correo está registrado, recibirás un enlace para '
              'restablecer tu contraseña.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
      failure: (excepcion) => _showError(excepcion.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo / Identidad Institucional
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: Color(0xFF2563EB),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'INCES LMS',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'cPanel & Aula Virtual',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Campo: Cédula o Correo
                    TextFormField(
                      controller: _identifierController,
                      enabled: !_isLoading,
                      style: const TextStyle(color: Colors.white),
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDecoration(
                        label: 'Cédula o Correo',
                        icon: Icons.badge_outlined,
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) {
                          return 'Ingresa tu cédula o correo';
                        }
                        if (text.contains('@') &&
                            !RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$')
                                .hasMatch(text)) {
                          return 'Ingresa un correo válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Campo: Contraseña
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      style: const TextStyle(color: Colors.white),
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      obscureText: _obscurePassword,
                      onFieldSubmitted: (_) => _handleLogin(),
                      decoration:
                          _inputDecoration(
                            label: 'Contraseña',
                            icon: Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa tu contraseña';
                        }
                        return null;
                      },
                    ),

                    // Enlace de recuperación. Alineado a la derecha, pegado al
                    // campo al que pertenece: en una pantalla de login, un
                    // enlace huérfano en el centro se pierde.
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : _handleRecuperacion,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Botón de Ingreso
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF2563EB)
                              .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.login_rounded, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Ingresar al Sistema',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Acceso al formulario público de inscripción.
                    // Wrap en lugar de Row: si no cabe en una línea (móvil
                    // angosto), el botón baja a la siguiente en vez de
                    // desbordar el layout.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '¿Eres nuevo?',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AspiranteFormScreen(),
                                    ),
                                  ),
                          child: Text(
                            'Inscríbete como aspirante',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF60A5FA),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Pie institucional
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Acceso restringido al personal autorizado',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      errorStyle: const TextStyle(color: Color(0xFFF87171)),
    );
  }
}
