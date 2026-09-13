import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';

/// Pantalla donde el usuario define una contraseña nueva.
///
/// Se abre de dos maneras, y las dos importan:
///
/// 1. **Desde el enlace del correo de recuperación.** Supabase redirige con el
///    token en el fragmento de la URL (`#access_token=...&type=recovery`). Ese
///    fragmento *no viaja al servidor*, sólo lo lee el navegador: por eso el
///    propio SDK de Supabase, al inicializarse, detecta el fragmento y crea una
///    sesión temporal. Cuando esta pantalla aparece en ese caso, ya hay sesión.
///
/// 2. **Desde dentro de la app**, con una sesión normal, para cambiarla a
///    voluntad.
///
/// En los dos casos la operación es la misma: `updateUser(password:)`. No hace
/// falta distinguir el origen, y no distinguirlo evita una pantalla que se
/// rompe cuando el enlace caduca.
///
/// El token de recuperación **caduca** (una hora por defecto). Si el usuario
/// llega tarde, no hay sesión y esta pantalla lo dice con claridad en lugar de
/// dejar el botón sin efecto.
class RestablecerPasswordScreen extends StatefulWidget {
  const RestablecerPasswordScreen({super.key});

  @override
  State<RestablecerPasswordScreen> createState() =>
      _RestablecerPasswordScreenState();
}

class _RestablecerPasswordScreenState
    extends State<RestablecerPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _passwordVisible = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _handleRestablecer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final resultado = await _authService.restablecerPassword(
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    resultado.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contraseña actualizada. Ya puedes iniciar sesión.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        Navigator.of(context).pop();
      },
      failure: (excepcion) {
        setState(() => _error = excepcion.message);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final haySesion = _authService.tieneSesion;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: const Color(0xFF1E293B),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_reset_outlined,
                        color: Color(0xFF2563EB),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        haySesion
                            ? 'Nueva contraseña'
                            : 'Enlace no válido o caducado',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        haySesion
                            ? 'Elige una contraseña que puedas recordar. Mínimo '
                                '8 caracteres.'
                            : 'Los enlaces de recuperación caducan por '
                                'seguridad. Solicita uno nuevo desde la '
                                'pantalla de inicio de sesión.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (haySesion) ...[
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Nueva contraseña',
                            labelStyle:
                                const TextStyle(color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: Color(0xFF64748B),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFF64748B),
                              ),
                              onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (valor) {
                            if (valor == null || valor.isEmpty) {
                              return 'Ingresa tu nueva contraseña';
                            }
                            if (valor.length < 8) {
                              return 'Debe tener al menos 8 caracteres';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmarController,
                          obscureText: !_passwordVisible,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Confirmar contraseña',
                            labelStyle:
                                const TextStyle(color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (valor) {
                            if (valor != _passwordController.text) {
                              return 'Las contraseñas no coinciden';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F1D1D).withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFFFCA5A5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRestablecer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Guardar contraseña',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          haySesion ? 'Cancelar' : 'Volver al inicio',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
