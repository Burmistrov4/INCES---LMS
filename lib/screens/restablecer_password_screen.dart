import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/inces_theme.dart';

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
///
/// ## Por qué esta pantalla dejó de ser oscura
///
/// Estaba forzada a `#0F172A` con literales —los mismos valores que
/// `IncesTheme.fondoOscuro`, `superficieOscura`, `bordeOscuro` y
/// `textoApagadoOscuro`, copiados a mano—. Con `ThemeMode.system` en claro, el
/// usuario que llega desde el correo de recuperación aterrizaba en una pantalla
/// oscura que además repetía el sistema de diseño en lugar de usarlo.
///
/// Ahora todo sale del `ColorScheme`. Un literal de color aquí es un color que
/// no sigue al tema, y no queda ninguno.
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
          SnackBar(
            content: const Text(
              'Contraseña actualizada. Ya puedes iniciar sesión.',
            ),
            backgroundColor: IncesTheme.exito,
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
    final theme = Theme.of(context);
    final haySesion = _authService.tieneSesion;

    return Scaffold(
      // Sin `backgroundColor`: lo pone el tema. Ésta era la segunda pantalla
      // que se quedaba oscura en un sistema en claro.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            // `Card` sin `color` ni `elevation`: hereda el `cardTheme`, que ya
            // trae la superficie, el borde y la ausencia de tinte de M3.
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.lock_reset_outlined,
                        color: theme.colorScheme.primary,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        haySesion
                            ? 'Nueva contraseña'
                            : 'Enlace no válido o caducado',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (haySesion) ...[
                        // Sin `style`, `labelStyle`, `fillColor` ni colores en
                        // los iconos: el `inputDecorationTheme` del tema ya los
                        // define, y repetirlos era lo que los desincronizaba.
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          decoration: InputDecoration(
                            labelText: 'Nueva contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _passwordVisible
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
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
                          decoration: const InputDecoration(
                            labelText: 'Confirmar contraseña',
                            prefixIcon: Icon(Icons.lock_outline),
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
                          _avisoDeError(theme, _error!),
                          const SizedBox(height: 16),
                        ],

                        SizedBox(
                          height: 48,
                          // Sin `styleFrom`: el tema da el azul y la forma.
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRestablecer,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Guardar contraseña'),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          haySesion ? 'Cancelar' : 'Volver al inicio',
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

  /// El recuadro de error, con el tono del tema.
  ///
  /// Antes usaba tres literales —`#7F1D1D` de fondo, `#EF4444` de borde y
  /// `#FCA5A5` de texto— que estaban calculados para leerse **sólo** sobre
  /// fondo oscuro. En claro, el texto rosado sobre blanco quedaba casi
  /// invisible: el error existía y no se leía.
  Widget _avisoDeError(ThemeData theme, String mensaje) {
    final tono = theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tono.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
        border: Border.all(color: tono.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: tono),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: theme.textTheme.bodySmall?.copyWith(color: tono),
            ),
          ),
        ],
      ),
    );
  }
}
