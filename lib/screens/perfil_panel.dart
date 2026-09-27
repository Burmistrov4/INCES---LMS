import 'package:flutter/material.dart';

import '../models/perfil_usuario.dart';
import '../services/auth_service.dart';
import '../widgets/comunes.dart';

/// Panel «Mi perfil»: el nombre y el apellido propios.
///
/// ## Por qué es uno solo y no dos
///
/// Lo usan el administrador y el aprendiz, y **no hay ninguna diferencia entre
/// los dos**: `profiles` es la misma tabla para los tres roles, y lo que se puede
/// corregir —el nombre— es lo mismo. Duplicarlo por rol habría creado dos
/// pantallas que se desincronizan en el primer arreglo que se haga en una sola.
///
/// ## Por qué sólo dos campos
///
/// La cédula y el correo son la identidad con la que la persona **se autentica**
/// y con la que aparece en la nómina que se exporta a HACER; el rol es un
/// privilegio, y se concede desde el cPanel. Los tres se **muestran** —para que
/// quien entra sepa con qué cuenta está dentro— y ninguno se edita aquí. El
/// razonamiento completo está en [PerfilUsuario].
///
/// ## La autorización no la decide esta pantalla
///
/// Ni esta pantalla ni el servicio comprueban quién puede escribir: lo hace la
/// RLS (ADR-003), que es la frontera real. `profiles_update_own` cubre al
/// aprendiz en su propia fila y `profiles_admin_all` cubre al administrador —que
/// no pasa por la primera, porque su `rol` no es `estudiante`—.
class PerfilPanel extends StatefulWidget {
  const PerfilPanel({super.key, this.auth});

  final AuthService? auth;

  @override
  State<PerfilPanel> createState() => _PerfilPanelState();
}

class _PerfilPanelState extends State<PerfilPanel> {
  late final AuthService _auth = widget.auth ?? AuthService();

  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();

  PerfilUsuario? _perfil;
  bool _cargando = true;
  String? _error;

  bool _guardando = false;

  /// El error del **guardado**, que se pinta dentro del formulario.
  ///
  /// Va separado de [_error] a propósito: [_error] es «no se pudo cargar la
  /// sección» y reemplaza al formulario entero; esto es «no se pudo guardar» y
  /// tiene que verse **con los campos delante**, sin borrar lo que la persona
  /// acaba de escribir.
  String? _errorFormulario;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _errorFormulario = null;
    });

    final resultado = await _auth.miPerfil();

    if (!mounted) return;

    resultado.when(
      success: (perfil) => setState(() {
        _cargando = false;
        _perfil = perfil;
        // Se siembra el formulario con lo que hay en la base. Para un aprendiz
        // recién registrado no es un hueco: `handle_new_user()` insertó la fila
        // con el nombre que tecleó en el formulario de inscripción.
        _nombreCtrl.text = perfil?.nombres ?? '';
        _apellidoCtrl.text = perfil?.apellidos ?? '';
      }),
      failure: (fallo) => setState(() {
        _cargando = false;
        _error = fallo.message;
      }),
    );
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() {
      _guardando = true;
      _errorFormulario = null;
    });

    final resultado = await _auth.actualizarPerfil(
      nombres: _nombreCtrl.text,
      apellidos: _apellidoCtrl.text,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    resultado.when(
      success: (perfil) {
        // Se reescriben los campos con lo que devolvió la base, no con lo que se
        // tecleó: así lo que se ve es el valor **guardado** —ya recortado— y no
        // el que quedó en el campo. Si la base hubiera normalizado algo, se ve.
        setState(() {
          _perfil = perfil;
          _nombreCtrl.text = perfil.nombres;
          _apellidoCtrl.text = perfil.apellidos;
        });
        mostrarAviso(context, 'Tus datos se guardaron.', exito: true);
      },
      failure: (fallo) => setState(() => _errorFormulario = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSeccion(
          'Mi perfil',
          subtitulo: 'El nombre y el apellido con los que apareces en el '
              'sistema. Corrígelos si están mal escritos.',
        ),
        Expanded(
          child: EstadoPanel(
            cargando: _cargando,
            error: _error,
            onReintentar: _cargar,
            child: _cuerpo(),
          ),
        ),
      ],
    );
  }

  Widget _cuerpo() {
    final perfil = _perfil;

    // Un `null` aquí no es un error de red —ése llega como `failure` y lo pinta
    // `EstadoPanel`—: es una cuenta sin fila en `profiles`. Se dice cuál de las
    // dos cosas es, en vez de dejar la pantalla en blanco.
    if (perfil == null) {
      return const PanelVacio(
        titulo: 'Tu cuenta todavía no tiene perfil',
        mensaje: 'El perfil se crea en el mismo momento del registro. Si ves '
            'esto, tu cuenta existe pero le falta la ficha de identidad: avisa '
            'a la coordinación del centro.',
        icono: Icons.person_off_outlined,
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tarjetaIdentidad(perfil),
          const SizedBox(height: 16),
          _formulario(),
        ],
      ),
    );
  }

  /// Lo que identifica la cuenta y **no** se edita, para dar contexto.
  Widget _tarjetaIdentidad(PerfilUsuario perfil) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _datoFijo(
              icono: Icons.alternate_email_rounded,
              etiqueta: 'Correo',
              valor: perfil.email,
            ),
            const SizedBox(height: 10),
            _datoFijo(
              icono: Icons.badge_outlined,
              etiqueta: 'Rol',
              valor: perfil.rolLegible,
            ),
          ],
        ),
      ),
    );
  }

  /// Una línea de dato de sólo lectura.
  ///
  /// El valor va en un `Expanded` con elipsis: un correo largo es el caso normal,
  /// y un `Row` con dos `Text` sueltos desborda a ancho de móvil. Es el patrón
  /// que este proyecto ya pagó tres veces.
  Widget _datoFijo({
    required IconData icono,
    required String etiqueta,
    required String valor,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icono, size: 17, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$etiqueta: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            valor,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _formulario() {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nombre y apellido', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Son los únicos datos que puedes corregir por tu cuenta.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreCtrl,
              enabled: !_guardando,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombres',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _apellidoCtrl,
              enabled: !_guardando,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              // Guardar con «Intro» en el último campo: es lo que uno intenta
              // después de teclear el apellido.
              onSubmitted: (_) => _guardar(),
              decoration: const InputDecoration(
                labelText: 'Apellidos',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            if (_errorFormulario != null) ...[
              const SizedBox(height: 14),
              AvisoEnLinea(
                texto: _errorFormulario!,
                tono: TonoAviso.peligro,
                icono: Icons.error_outline,
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'La cédula, el correo y el rol no se editan aquí: identifican tu '
              'cuenta y determinan lo que puedes hacer en el sistema. Si alguno '
              'está mal, avisa a la coordinación del centro.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
