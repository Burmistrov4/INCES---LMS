import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/navegacion.dart';
import '../repositories/invitacion_repository.dart';
import '../theme/inces_theme.dart';

/// Pantalla donde el docente invitado fija su contraseña.
///
/// Se abre desde el enlace `/auth/activate?token=...` (o `#/auth/activate?token=`
/// con la estrategia de URL por defecto de Flutter web). El token se lee de la
/// URL: el docente aún no tiene sesión, así que no hay JWT que pasar. Tras
/// activar, se le manda al login para que entre con su nueva contraseña.
class ActivarCuentaScreen extends StatefulWidget {
  const ActivarCuentaScreen({super.key, this.token});

  /// Token recibido por navegación directa. Si es `null`, se lee de la URL.
  final String? token;

  @override
  State<ActivarCuentaScreen> createState() => _ActivarCuentaScreenState();
}

class _ActivarCuentaScreenState extends State<ActivarCuentaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _repo = InvitacionRepository();

  bool _isLoading = false;
  bool _passwordVisible = false;
  String? _error;
  bool _activada = false;
  String? _emailActivado;

  String? _token;

  @override
  void initState() {
    super.initState();
    _token = widget.token ?? _leerTokenDeUrl();
  }

  /// Lee el token de la URL de la página.
  ///
  /// Es el respaldo de `widget.token`: en web el enrutador ya extrae el token
  /// del nombre de la ruta, pero si la pantalla se abre por un camino que no
  /// pasa por él, la URL sigue siendo la fuente de verdad. La regla vive en
  /// `core/navegacion.dart` —la misma que usa el enrutador— para poder probarla
  /// sin navegador; aquí sólo se le entrega la URL real.
  String? _leerTokenDeUrl() => tokenDeUrl(Uri.base);

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _activar() async {
    if (_isLoading) return;
    if (_token == null || _token!.isEmpty) {
      setState(() {
        _error = 'Falta el token de invitación en el enlace. Solicita una '
            'nueva invitación al administrador.';
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Se libera el estado de carga ANTES de comprobar `mounted`: si la pantalla
    // se desmonta durante la petición (el usuario cierra la pestaña), un
    // `return` temprano dejaría `_isLoading` en true para siempre.
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final resultado = await _repo.activarCuenta(
      token: _token!,
      password: _passwordController.text,
    );

    if (mounted) setState(() => _isLoading = false);
    if (!mounted) return;

    resultado.when(
      success: (activacion) {
        setState(() {
          _activada = true;
          _emailActivado = activacion.email;
        });
      },
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;
    final fondo = esOscuro ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final tarjeta = esOscuro ? const Color(0xFF1E293B) : Colors.white;
    final texto = esOscuro ? Colors.white : const Color(0xFF0F172A);
    final textoSuave =
        esOscuro ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final relleno = esOscuro ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: fondo,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: tarjeta,
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
                        Icons.person_add_alt_1_outlined,
                        color: Color(0xFF2563EB),
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _activada
                            ? 'Cuenta activada'
                            : 'Activar cuenta de docente',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: texto,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _activada
                            ? 'Tu cuenta está lista. Ya puedes iniciar sesión '
                                'con tu correo y la contraseña que acabas de fijar.'
                            : 'Define la contraseña de tu cuenta de docente. '
                                'Mínimo 8 caracteres.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 13, color: textoSuave),
                      ),
                      const SizedBox(height: 24),

                      if (_activada) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: IncesTheme.exito.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(IncesTheme.radioControl),
                            border: Border.all(
                              color: IncesTheme.exito.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  color: IncesTheme.exito, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _emailActivado ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: IncesTheme.exito,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context)
                                .pushReplacementNamed('/login'),
                            child: const Text('Ir a iniciar sesión'),
                          ),
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          style: TextStyle(color: texto),
                          decoration: InputDecoration(
                            labelText: 'Nueva contraseña',
                            labelStyle: TextStyle(color: textoSuave),
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                            ),
                            filled: true,
                            fillColor: relleno,
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
                          style: TextStyle(color: texto),
                          decoration: InputDecoration(
                            labelText: 'Confirmar contraseña',
                            labelStyle: TextStyle(color: textoSuave),
                            prefixIcon:
                                const Icon(Icons.lock_outline, size: 20),
                            filled: true,
                            fillColor: relleno,
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
                              color: IncesTheme.error.withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(IncesTheme.radioControl),
                              border: Border.all(
                                color: IncesTheme.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: IncesTheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _activar,
                            style: FilledButton.styleFrom(
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
                                : const Text('Activar cuenta'),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pushReplacementNamed('/login'),
                        child: Text(
                          'Volver al inicio',
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
