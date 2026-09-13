import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/entrada_acceso.dart';
import '../../repositories/auditoria_acceso_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Auditoría de accesos del cPanel (Módulo 1).
///
/// Expone la traza `auth_logs`: quién entró, desde qué IP y con qué resultado.
/// Es la contrapartida visible del registro que escribe el backend: sin esta
/// pantalla, un intento de acceso con la contraseña de otro pasaría inadvertido
/// hasta que el afectado lo contara.
///
/// Se refresca sola cada 30 segundos porque un registro de accesos que sólo se
/// actualiza cuando alguien se acuerda de mirarlo no sirve para detectar nada;
/// el interruptor permite desactivarla si el administrador prefiere consultar a
/// mano (por ejemplo, mientras revisa una página concreta).
class CpanelAuditoriaAccesosPanel extends StatefulWidget {
  const CpanelAuditoriaAccesosPanel({super.key, this.repositorio});

  /// Inyectable para los tests: sin esto, probar el panel exigiría un backend.
  final AuditoriaAccesoRepository? repositorio;

  @override
  State<CpanelAuditoriaAccesosPanel> createState() =>
      _CpanelAuditoriaAccesosPanelState();
}

class _CpanelAuditoriaAccesosPanelState
    extends State<CpanelAuditoriaAccesosPanel> {
  late final AuditoriaAccesoRepository _repo =
      widget.repositorio ?? AuditoriaAccesoRepository();

  final TextEditingController _emailController = TextEditingController();

  static const int _limite = AuditoriaAccesoRepository.limitePorPagina;

  /// Cada cuánto se refresca la traza con la actualización automática activa.
  /// 30 s deja ver un intento de intrusión en curso sin tener la pantalla
  /// consultando sin descanso.
  static const Duration _intervaloAuto = Duration(seconds: 30);

  bool _cargando = true;
  String? _error;
  List<EntradaAcceso> _entradas = const [];
  int _total = 0;
  int _desplazamiento = 0;
  EstadoAcceso? _filtroEstado;
  bool _autoActualizar = true;
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _cargar();
    _sincronizarTemporizador();
  }

  @override
  void dispose() {
    // Sin esto, el temporizador seguiría consultando después de salir del panel
    // y acabaría llamando a setState sobre un widget ya desmontado.
    _temporizador?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _sincronizarTemporizador() {
    _temporizador?.cancel();
    _temporizador = null;
    if (!_autoActualizar) return;
    _temporizador =
        Timer.periodic(_intervaloAuto, (_) => _cargar(silencioso: true));
  }

  /// `silencioso` evita el indicador de carga en la recarga automática: parpadear
  /// cada 30 s haría ilegible una lista que el administrador está leyendo.
  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    final correo = _emailController.text.trim();

    final resultado = await _repo.listarAccesos(
      estado: _filtroEstado,
      email: correo.isEmpty ? null : correo,
      limite: _limite,
      desplazamiento: _desplazamiento,
    );

    if (!mounted) return;

    switch (resultado) {
      case Success(value: final pagina):
        setState(() {
          _cargando = false;
          _error = null;
          _entradas = pagina.entradas;
          _total = pagina.total;
        });

      case Failure(error: final fallo):
        // En la recarga automática se conserva lo que ya se estaba viendo:
        // sustituir la lista por un error cada 30 s haría imposible leerla. Se
        // avisa y se mantienen los datos de la última lectura buena.
        if (silencioso && _entradas.isNotEmpty) {
          mostrarAviso(context, fallo.message, error: true);
          return;
        }
        setState(() {
          _cargando = false;
          _error = fallo.message;
        });
    }
  }

  bool get _hayFiltros =>
      _filtroEstado != null || _emailController.text.trim().isNotEmpty;

  void _aplicarFiltros() {
    // Cambiar el filtro sin volver al principio dejaría al administrador en una
    // página que quizá ya no existe con los datos nuevos.
    setState(() => _desplazamiento = 0);
    _cargar();
  }

  void _limpiarFiltros() {
    _emailController.clear();
    setState(() {
      _filtroEstado = null;
      _desplazamiento = 0;
    });
    _cargar();
  }

  void _paginaAnterior() {
    if (_desplazamiento == 0) return;
    final anterior = _desplazamiento - _limite;
    setState(() => _desplazamiento = anterior < 0 ? 0 : anterior);
    _cargar();
  }

  void _paginaSiguiente() {
    if (_desplazamiento + _entradas.length >= _total) return;
    setState(() => _desplazamiento += _limite);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return EstadoPanel(
      cargando: _cargando,
      error: _error,
      onReintentar: () => _cargar(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TituloSeccion(
            'Auditoría de accesos',
            subtitulo:
                'Inicios de sesión, direcciones IP y fallos de autenticación.',
            acciones: [
              IconButton(
                tooltip: 'Actualizar ahora',
                onPressed: () => _cargar(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          _barraFiltros(),
          const SizedBox(height: 12),
          if (_autoActualizar) ...[
            AvisoEnLinea(
              texto:
                  'Se actualiza sola cada ${_intervaloAuto.inSeconds} segundos. '
                  'Desactívalo si prefieres consultar a mano.',
              icono: Icons.autorenew_rounded,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(child: _cuerpo()),
          if (_entradas.isNotEmpty) _paginacion(context),
        ],
      ),
    );
  }

  Widget _barraFiltros() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chipEstado('Todos', null),
        _chipEstado('Sólo exitosos', EstadoAcceso.exito),
        _chipEstado('Sólo fallidos', EstadoAcceso.fallo),
        const SizedBox(width: 12),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Correo exacto',
              hintText: 'docente@inces.gob.ve',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _aplicarFiltros(),
          ),
        ),
        FilledButton.icon(
          onPressed: _aplicarFiltros,
          icon: const Icon(Icons.filter_alt_outlined, size: 18),
          label: const Text('Aplicar'),
        ),
        if (_hayFiltros)
          TextButton.icon(
            onPressed: _limpiarFiltros,
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('Limpiar'),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: _autoActualizar,
              onChanged: (valor) {
                setState(() => _autoActualizar = valor);
                _sincronizarTemporizador();
              },
            ),
            Text(
              'Auto (${_intervaloAuto.inSeconds} s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _chipEstado(String etiqueta, EstadoAcceso? valor) {
    return FilterChip(
      label: Text(etiqueta),
      selected: _filtroEstado == valor,
      onSelected: (_) {
        setState(() => _filtroEstado = valor);
        _aplicarFiltros();
      },
    );
  }

  Widget _cuerpo() {
    if (_entradas.isEmpty) {
      return PanelVacio(
        icono: Icons.fact_check_outlined,
        titulo: _hayFiltros
            ? 'Ningún acceso coincide con el filtro'
            : 'Todavía no hay accesos registrados',
        mensaje: _hayFiltros
            ? 'Ningún intento coincide con lo que has pedido. Prueba a limpiar '
                'el filtro para ver la traza completa.'
            : 'Cuando alguien inicie sesión —o falle al intentarlo— aparecerá '
                'aquí con su correo, su IP y la hora exacta.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _cargar(),
      child: ListView.separated(
        itemCount: _entradas.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, indice) => _fila(context, _entradas[indice]),
      ),
    );
  }

  Widget _fila(BuildContext context, EntradaAcceso entrada) {
    final theme = Theme.of(context);
    final exito = entrada.fueExitoso;
    final color = exito ? IncesTheme.exito : IncesTheme.rojoInces;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          exito ? Icons.login_rounded : Icons.gpp_maybe_rounded,
          size: 17,
          color: color,
        ),
      ),
      title: Text(
        entrada.actor,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${entrada.estado.etiqueta} · IP ${entrada.ip ?? 'sin IP'} · '
        '${formatearFechaHora(entrada.creadoEn)}',
        style: theme.textTheme.labelSmall,
      ),
      trailing: Icon(
        exito ? Icons.check_circle_outline : Icons.error_outline,
        size: 18,
        color: color,
      ),
    );
  }

  Widget _paginacion(BuildContext context) {
    final theme = Theme.of(context);
    final desde = _desplazamiento + 1;
    final hasta = _desplazamiento + _entradas.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('$desde–$hasta de $_total', style: theme.textTheme.bodySmall),
          const Spacer(),
          IconButton(
            tooltip: 'Anteriores',
            onPressed: _desplazamiento == 0 ? null : _paginaAnterior,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Siguientes',
            onPressed: hasta >= _total ? null : _paginaSiguiente,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
