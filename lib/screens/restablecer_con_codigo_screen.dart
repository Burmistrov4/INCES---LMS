import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/errors/app_exception.dart';
import '../repositories/recuperacion_repository.dart';
import '../theme/inces_theme.dart';

/// Canje del código de recuperación (ruta `/restablecer-codigo`).
///
/// ## Por qué existe esta pantalla y no un enlace por correo
///
/// El restablecimiento por correo depende de un proveedor externo (Resend) que
/// hoy devuelve 401 sin dominio verificado. La decisión de producto es que
/// **recuperar una cuenta no dependa de un proveedor de correo**: el
/// administrador del centro verifica la identidad por el procedimiento
/// institucional —presencial, con la cédula a la vista—, emite un código
/// temporal de un solo uso y se lo entrega a la persona.
///
/// Esta pantalla es el otro extremo de ese trámite: donde el titular trae el
/// código y **elige su propia contraseña**. El administrador no la ve ni puede
/// elegirla, y el sistema no la guarda en ninguna tabla: la aplica el backend
/// contra el proveedor de identidad.
class RestablecerConCodigoScreen extends StatefulWidget {
  const RestablecerConCodigoScreen({super.key, this.repositorio});

  /// Inyectable para las pruebas.
  final RecuperacionRepository? repositorio;

  @override
  State<RestablecerConCodigoScreen> createState() =>
      _RestablecerConCodigoScreenState();
}

class _RestablecerConCodigoScreenState extends State<RestablecerConCodigoScreen> {
  late final RecuperacionRepository _repo =
      widget.repositorio ?? RecuperacionRepository();

  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repetirController = TextEditingController();
  final _codigoFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _repetirFocus = FocusNode();

  bool _isLoading = false;
  bool _obscure = true;
  String? _error;
  bool _listo = false;

  @override
  void dispose() {
    _codigoController.dispose();
    _passwordController.dispose();
    _repetirController.dispose();
    _codigoFocus.dispose();
    _passwordFocus.dispose();
    _repetirFocus.dispose();
    super.dispose();
  }

  Future<void> _canjear() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final resultado = await _repo.canjearCodigo(
      codigo: _codigoController.text,
      password: _passwordController.text,
    );

    // El estado de carga se libera ANTES de comprobar `mounted`: al revés, un
    // desmontaje durante la petición dejaría el botón bloqueado para siempre.
    if (mounted) setState(() => _isLoading = false);
    if (!mounted) return;

    resultado.when(
      success: (_) => setState(() => _listo = true),
      failure: (AppException fallo) => setState(() => _error = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parError = PaletaInces.de(context).etiquetaDe(TonoEstado.error);

    return Scaffold(
      appBar: AppBar(title: const Text('Restablecer contraseña')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _listo ? _exito(theme) : _formulario(theme, parError),
          ),
        ),
      ),
    );
  }

  Widget _exito(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 56, color: IncesTheme.exito),
        const SizedBox(height: 16),
        Text(
          'Contraseña actualizada',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'Ya puedes iniciar sesión con tu contraseña nueva. Por seguridad, se '
          'cerraron las sesiones que estuvieran abiertas.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Ir a iniciar sesión'),
        ),
      ],
    );
  }

  Widget _formulario(ThemeData theme, ParDeEtiqueta parError) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Restablecer contraseña', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Escribe el código temporal que te entregó el personal del centro y '
            'elige tu contraseña nueva.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _codigoController,
            focusNode: _codigoFocus,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              labelText: 'Código de recuperación',
              prefixIcon: Icon(Icons.key_outlined, size: 20),
              hintText: 'ABCD-EFGH-JKMN',
            ),
            validator: (valor) {
              final limpio = (valor ?? '').replaceAll(RegExp(r'[\s-]'), '');
              if (limpio.isEmpty) return 'Escribe el código que te entregaron.';
              if (limpio.length < 8) return 'El código está incompleto.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _repetirFocus.requestFocus(),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: 'Contraseña nueva',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (valor) {
              final texto = valor ?? '';
              if (texto.isEmpty) return 'Elige una contraseña.';
              if (texto.length < 8) {
                return 'Usa al menos 8 caracteres.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _repetirController,
            focusNode: _repetirFocus,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _canjear(),
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              labelText: 'Repite la contraseña',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
            ),
            validator: (valor) {
              if ((valor ?? '').isEmpty) return 'Repite la contraseña.';
              if (valor != _passwordController.text) {
                return 'Las contraseñas no coinciden.';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: parError.fondo,
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
                border: Border.all(color: parError.texto.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: parError.texto, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(fontSize: 13, color: parError.texto),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _isLoading ? null : _canjear,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Cambiar contraseña'),
            ),
          ),
        ],
      ),
    );
  }
}
