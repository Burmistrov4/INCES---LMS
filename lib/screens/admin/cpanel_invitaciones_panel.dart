import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/invitacion_docente.dart';
import '../../repositories/invitacion_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Panel de invitación de docentes (Módulo 1 del cPanel).
///
/// El administrador introduce el correo; el backend genera un token de un solo
/// uso, crea el usuario como docente al consumirlo y devuelve el enlace de
/// activación. Como el correo puede no llegar (Resend sin dominio verificado),
/// el enlace también se muestra aquí para copiarlo o reenviarlo por otro medio.
class CpanelInvitacionesPanel extends StatefulWidget {
  const CpanelInvitacionesPanel({super.key, this.repositorio});

  final InvitacionRepository? repositorio;

  @override
  State<CpanelInvitacionesPanel> createState() =>
      _CpanelInvitacionesPanelState();
}

class _CpanelInvitacionesPanelState extends State<CpanelInvitacionesPanel> {
  late final InvitacionRepository _repo =
      widget.repositorio ?? InvitacionRepository();

  final _formKey = GlobalKey<FormState>();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _emailController = TextEditingController();
  final _nombresFocus = FocusNode();
  final _apellidosFocus = FocusNode();
  final _emailFocus = FocusNode();

  bool _isLoading = false;
  bool _cargandoListado = true;
  String? _error;
  InvitacionDocente? _invitacion;
  List<InvitacionListada> _invitaciones = const [];

  @override
  void initState() {
    super.initState();
    _cargarListado();
  }

  /// Trae el listado con los estados ya resueltos por el backend.
  Future<void> _cargarListado() async {
    if (mounted) setState(() => _cargandoListado = true);
    final resultado = await _repo.listarInvitaciones();
    if (!mounted) return;
    resultado.when(
      success: (lista) => setState(() {
        _invitaciones = lista;
        _cargandoListado = false;
      }),
      // Un fallo del listado no borra el formulario: se muestra el aviso y el
      // administrador puede seguir invitando. Que la lista no cargue no debe
      // impedir la operación principal del panel.
      failure: (fallo) => setState(() {
        _cargandoListado = false;
        _error = fallo.message;
      }),
    );
  }

  /// Anula una invitación. Pide confirmación porque es irreversible desde la UI:
  /// una invitación revocada no se puede "des-revocar", hay que renovarla.
  Future<void> _revocar(InvitacionListada invitacion) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Anular invitación'),
        content: Text(
          'El enlace de ${invitacion.nombreCompleto} dejará de funcionar de '
          'inmediato. Si más adelante lo necesitas, podrás emitir uno nuevo con '
          '«Renovar».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final resultado = await _repo.revocarInvitacion(invitacion.id);
    if (!mounted) return;
    resultado.when(
      success: (_) {
        mostrarAviso(context, 'Invitación anulada.', exito: true);
        _cargarListado();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message),
    );
  }

  /// Emite un enlace nuevo y anula el anterior.
  Future<void> _renovar(InvitacionListada invitacion) async {
    final resultado = await _repo.renovarInvitacion(invitacion.id);
    if (!mounted) return;
    resultado.when(
      success: (nueva) {
        setState(() => _invitacion = nueva);
        mostrarAviso(context, 'Invitación renovada. El enlace anterior ya no sirve.', exito: true);
        _cargarListado();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message),
    );
  }

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    _emailController.dispose();
    _nombresFocus.dispose();
    _apellidosFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _invitacion = null;
    });

    final resultado = await _repo.invitarDocente(
      _emailController.text,
      _nombresController.text,
      _apellidosController.text,
    );

    // El estado de carga se libera ANTES de comprobar `mounted`: al revés, un
    // desmontaje durante la petición dejaría el botón bloqueado para siempre.
    if (mounted) setState(() => _isLoading = false);
    if (!mounted) return;

    resultado.when(
      success: (invitacion) {
        setState(() => _invitacion = invitacion);
        // **El aviso no dice «enviada».** El correo puede no haber salido (Resend
        // sin dominio verificado) y afirmar una entrega que no ocurrió es
        // exactamente el error que este panel existe para no cometer. El estado
        // real de entrega lo muestra la tarjeta del enlace.
        mostrarAviso(
          context,
          'Invitación creada. El enlace está listo para entregar.',
          exito: true,
        );
        _cargarListado();
      },
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // El aviso rojo de más abajo escribe sobre un tinte de su propio color, y ahí
    // el rojo de relleno no llega: `#DC2626` da 4.28:1 en claro y 2.92:1 en
    // oscuro. Medido el 2026-09-30.
    final parError = PaletaInces.de(context).etiquetaDe(TonoEstado.error);

    // Raíz desplazable, igual que los paneles de módulos y parámetros:
    // `ContenidoSeccion` entrega una altura acotada y este panel crece con su
    // contenido —aviso, formulario y, cuando el correo no sale, la tarjeta del
    // enlace—, así que en una ventana baja el final quedaría recortado.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TituloSeccion(
          'Invitación de docentes',
          subtitulo: 'Registra un nuevo docente por correo. El enlace de '
              'activación caduca en 48 horas.',
        ),
        const SizedBox(height: 16),
        const AvisoEnLinea(
          texto: 'El docente recibe un enlace para fijar su contraseña. Si el '
              'correo no llega, el mismo enlace se muestra abajo para '
              'reenviarlo por otro medio.',
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nombresController,
                      focusNode: _nombresFocus,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_apellidosFocus),
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        labelText: 'Nombres',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                        hintText: 'Ej. José María',
                      ),
                      validator: (valor) {
                        if ((valor?.trim() ?? '').isEmpty) {
                          return 'Ingresa el nombre del docente.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _apellidosController,
                      focusNode: _apellidosFocus,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_emailFocus),
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        labelText: 'Apellidos',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                        hintText: 'Ej. Pérez García',
                      ),
                      validator: (valor) {
                        if ((valor?.trim() ?? '').isEmpty) {
                          return 'Ingresa los apellidos del docente.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.send,
                      onFieldSubmitted: (_) => _enviar(),
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        labelText: 'Correo del docente',
                        prefixIcon: Icon(Icons.mail_outline, size: 20),
                        hintText: 'nombre@dominio.edu.ve',
                      ),
                      validator: (valor) {
                        final texto = valor?.trim() ?? '';
                        if (texto.isEmpty) {
                          return 'Ingresa el correo del docente.';
                        }
                        if (!RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$')
                            .hasMatch(texto)) {
                          return 'Formato de correo no válido.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _enviar,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_outlined, size: 18),
                      label: const Text('Enviar invitación'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: parError.texto,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_invitacion != null) _EnlaceActivacion(invitacion: _invitacion!),
        const SizedBox(height: 32),
        _ListadoInvitaciones(
          cargando: _cargandoListado,
          invitaciones: _invitaciones,
          onRevocar: _revocar,
          onRenovar: _renovar,
          onActualizar: _cargarListado,
        ),
      ],
    );
  }
}

/// Listado de invitaciones con su estado real y sus acciones.
///
/// Los estados que muestra son los que **resuelve el backend**, no una
/// interpretación del cliente: «Pendiente de entrega» sólo aparece si el enlace
/// todavía sirve. No hay un estado «enviada» a propósito, porque el sistema no
/// puede comprobar que el correo llegó.
class _ListadoInvitaciones extends StatelessWidget {
  const _ListadoInvitaciones({
    required this.cargando,
    required this.invitaciones,
    required this.onRevocar,
    required this.onRenovar,
    required this.onActualizar,
  });

  final bool cargando;
  final List<InvitacionListada> invitaciones;
  final Future<void> Function(InvitacionListada) onRevocar;
  final Future<void> Function(InvitacionListada) onRenovar;
  final Future<void> Function() onActualizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Invitaciones emitidas',
                  style: theme.textTheme.titleSmall),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: cargando ? null : onActualizar,
              icon: const Icon(Icons.refresh_outlined, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (cargando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (invitaciones.isEmpty)
          Text(
            'Todavía no se ha emitido ninguna invitación.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < invitaciones.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _FilaInvitacion(
                    invitacion: invitaciones[i],
                    onRevocar: onRevocar,
                    onRenovar: onRenovar,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FilaInvitacion extends StatelessWidget {
  const _FilaInvitacion({
    required this.invitacion,
    required this.onRevocar,
    required this.onRenovar,
  });

  final InvitacionListada invitacion;
  final Future<void> Function(InvitacionListada) onRevocar;
  final Future<void> Function(InvitacionListada) onRenovar;

  /// Tono del chip según el estado. Un enlace que sirve se pinta como éxito; lo
  /// demás como aviso o neutro, nunca como éxito: el panel no debe sugerir que
  /// una invitación caducada o revocada todavía vale.
  TonoEstado get _tono => switch (invitacion.estado) {
        EstadoInvitacion.valida => TonoEstado.exito,
        EstadoInvitacion.usada => TonoEstado.info,
        EstadoInvitacion.expirada => TonoEstado.advertencia,
        EstadoInvitacion.revocada => TonoEstado.error,
        EstadoInvitacion.desconocido => TonoEstado.neutro,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final par = PaletaInces.de(context).etiquetaDe(_tono);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invitacion.nombreCompleto, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  invitacion.email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: par.fondo,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              invitacion.estado.etiqueta,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: par.texto,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Renovar sirve para cualquier estado: es la forma de volver a emitir
          // un enlace cuando el anterior caducó, se perdió o se anuló.
          IconButton(
            tooltip: 'Renovar',
            onPressed: () => onRenovar(invitacion),
            icon: const Icon(Icons.autorenew_outlined, size: 20),
          ),
          // Anular sólo tiene sentido si el enlace todavía sirve.
          IconButton(
            tooltip: 'Anular',
            onPressed:
                invitacion.estado.sirve ? () => onRevocar(invitacion) : null,
            icon: const Icon(Icons.block_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EnlaceActivacion extends StatelessWidget {
  const _EnlaceActivacion({required this.invitacion});

  final InvitacionDocente invitacion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entregado = invitacion.correoEnviado;
    // El chip cae sobre un tinte de su propio color: el verde de relleno daba
    // 2.65:1 en claro y el ámbar, 1.81:1. Medido el 2026-09-30.
    final parEstado = PaletaInces.de(context)
        .etiquetaDe(entregado ? TonoEstado.exito : TonoEstado.advertencia);

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.link_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Enlace de activación', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: parEstado.fondo,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      entregado ? 'Correo enviado' : 'Correo no entregado',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: parEstado.texto,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                invitacion.enlaceActivacion,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Caduca: ${invitacion.expiraEn}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!entregado) ...[
                const SizedBox(height: 10),
                const AvisoEnLinea(
                  tono: TonoAviso.advertencia,
                  icono: Icons.warning_amber_outlined,
                  texto: 'El correo no pudo entregarse (dominio de Resend sin '
                      'verificar). Comparte este enlace por otro medio: es la '
                      'vía de activación.',
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: invitacion.enlaceActivacion),
                    );
                    if (context.mounted) {
                      mostrarAviso(context, 'Enlace copiado.', exito: true);
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copiar enlace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
