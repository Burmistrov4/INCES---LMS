import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/gateways/aula_gateway.dart';
import '../../core/result.dart';
import '../../services/asistencia_service.dart';
import '../../services/aula_service.dart';

/// Panel del docente «Asistencia» (M7).
///
/// Tres pasos:
///   1. elegir la sección (la lista sale de `/mi-horario`, igual que «Mis aulas»);
///   2. proyectar el QR —rota sólo, cada `ventanaSeg`, derivado LOCALMENTE
///      (sin red: la LAN puede caerse medio minuto y la pizarra sigue válida);
///   3. ver la marca llegar por WebSocket y pintar la fila en verde, sin recargar.
///
/// El listado inicial se pide UNA vez por REST; de ahí en adelante es empuje.
/// El código del QR lo deriva este dispositivo: el servidor devolvió el secreto
/// UNA vez al abrir la sesión, y sólo la base sabe validarlo.
class AsistenciaQrPanel extends StatefulWidget {
  const AsistenciaQrPanel({super.key, this.servicio, this.aulas});

  /// Opcional, sólo para las pruebas: inyectar un servicio falso.
  final AsistenciaService? servicio;

  /// El listado de secciones del docente. Opcional para las pruebas.
  final AulasPropiasGateway? aulas;

  @override
  State<AsistenciaQrPanel> createState() => _AsistenciaQrPanelState();
}

class _AsistenciaQrPanelState extends State<AsistenciaQrPanel> {
  late final AsistenciaService _servicio = widget.servicio ?? AsistenciaService();
  late final AulasPropiasGateway _aulas = widget.aulas ?? BackendAulaGateway();

  /// Las secciones del docente (una entrada por aula).
  MisAulas? _misSecciones;
  String? _aulaSeleccionada;
  String _aulaEtiqueta = '';

  Map<String, dynamic>? _sesion;
  final List<MarcaAsistencia> _marcas = [];
  StreamSubscription<EventoAsistencia>? _suscripcion;
  Timer? _rotador;

  String _error = '';
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargarSecciones();
  }

  @override
  void dispose() {
    _rotador?.cancel();
    _suscripcion?.cancel();
    super.dispose();
  }

  /// Carga las secciones que el docente tiene a nombre.
  ///
  /// Se apoya en la misma ruta que «Mis aulas» (m3), así que lo que este panel
  /// ofrece para tomar asistencia es exactamente lo que la pantalla vecina
  /// abre. No se repite la lógica de «de quién es la sección»: la RLS la hace.
  Future<void> _cargarSecciones() async {
    final resultado = await Result.guard(() => _aulas.misAulas());
    if (!mounted) return;
    resultado.when(
      success: (mis) => setState(() => _misSecciones = mis),
      failure: (e) => setState(() => _error = e.message),
    );
  }

  /// Abre sesión: una por clase. El secreto viene una vez, en la respuesta.
  Future<void> _abrir() async {
    final seccionId = _aulaSeleccionada;
    if (seccionId == null) return;

    setState(() { _cargando = true; _error = ''; });

    final creada = await _servicio.abrirSesion(seccionId: seccionId);
    creada.when(
      success: (sesion) {
        setState(() { _sesion = sesion; _cargando = false; });
        _arrancar(sesion);
      },
      failure: (e) => setState(() { _cargando = false; _error = e.message; }),
    );
  }

  /// El «servidor lógico» de la pantalla: un rotador para el QR y el canal WS.
  void _arrancar(Map<String, dynamic> sesion) {
    final sesionId = sesion['id'] as String;

    // Un tick por segundo: el QR rota sólo. La app no pregunta a la base ni al
    // servidor entre un tick y el siguiente.
    _rotador = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Un intento de canal: sin bucle de reconexión, porque la clase se acaba y
    // el panel cierra; un retry aquí sería ruido sin diagnóstico.
    _suscripcion = _servicio.enVivo(sesionId: sesionId).listen(
      (evento) {
        if (!mounted) return;
        if (evento.tipo == 'marca' && evento.marca != null) {
          setState(() => _marcas.add(evento.marca!));
        } else if (evento.tipo == 'sesion_cerrada') {
          setState(() => _sesion = {..._sesion!, 'status': 'CLOSED'});
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() =>
            _error = 'La conexión en vivo se cayó. Las marcas ya están en la base.');
      },
    );

    _servicio.marcas(sesionId: sesionId).then((resultado) {
      if (!mounted) return;
      resultado.when(
        success: (lista) => setState(() => _marcas.addAll(lista)),
        failure: (_) {},
      );
    });
  }

  Future<void> _cerrar() async {
    final sesion = _sesion;
    if (sesion == null) return;
    final id = sesion['id'] as String;

    final resultado = await _servicio.cerrarSesion(sesionId: id);
    await resultado.when(
      success: (_) async {
        setState(() => _sesion = {...sesion, 'status': 'CLOSED'});
        await _suscripcion?.cancel();
        _suscripcion = null;
        _rotador?.cancel();
        _rotador = null;
      },
      failure: (e) async => setState(() => _error = e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sesion == null) return _selector();

    final ventana = _sesion!['ventana_seg'] as int? ?? 15;
    final secreto = _sesion!['qr_secret'] as String;
    final sesionId = _sesion!['id'] as String;
    final cerrada = _sesion!['status'] == 'CLOSED';

    final qr = AsistenciaService.codigoQr(
      qrSecret: secreto,
      sesionId: sesionId,
      ventanaSeg: ventana,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '{} · Asistencia'.replaceFirst('{}', _aulaEtiqueta.isEmpty ? 'Sección' : _aulaEtiqueta),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      cerrada ? 'Sesión cerrada —las marcas se conservan.' : 'Sesión abierta',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: cerrada ? null : _cerrar,
                icon: const Icon(Icons.stop_circle),
                label: const Text('Cerrar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, limites) {
                final qrWidget = Semantics(
                  label: 'Código QR de asistencia. Caduca en ${qr.venceEnSegundos} segundos.',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: '$sesionId:${qr.codigo}',
                        version: QrVersions.auto,
                        size: 260,
                      ),
                      const SizedBox(height: 12),
                      // El contador NO es un adorno: es la única señal de que el
                      // QR que se proyecta sigue vigente. Si llega a 0 y no rota,
                      // la pantalla se congeló, y eso hay que verlo.
                      Text('Rota en ${qr.venceEnSegundos} s',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                );

                final lista = _listado();

                final enFila = limites.maxWidth >= 740;
                if (enFila) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!cerrada) Expanded(child: Center(child: qrWidget)),
                      if (!cerrada) const SizedBox(width: 24),
                      Expanded(child: lista),
                    ],
                  );
                }
                return Column(
                  children: [
                    if (!cerrada) qrWidget,
                    const SizedBox(height: 16),
                    Expanded(child: lista),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Pedazos --------------------------------------------------------------

  Widget _selector() {
    if (_error.isNotEmpty && _misSecciones == null) {
      return _Centro(icono: Icons.wifi_off, mensaje: _error, onReintentar: _cargarSecciones);
    }
    final mis = _misSecciones;
    if (mis == null) return const Center(child: CircularProgressIndicator());
    if (mis.vacio) {
      return const _Centro(
        icono: Icons.info_outline,
        mensaje: 'No tienes secciones asignadas en este lapso. La guardia del RLS es la misma: no puedes abrir asistencia en la sección de otro.',
        onReintentar: null,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Toma asistencia', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Elige la sección. El QR lo proyectas en tu pantalla y caduca cada pocos segundos.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        for (final aula in mis.aulas)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(aula.etiqueta),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                setState(() {
                  _aulaSeleccionada = aula.seccionId;
                  _aulaEtiqueta = aula.etiqueta;
                });
                _abrir();
              },
            ),
          ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_error, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }

  Widget _listado() {
    if (_marcas.isEmpty) {
      return const Center(child: Text('Aún no hay marcas.'));
    }
    return ListView.builder(
      itemCount: _marcas.length,
      itemBuilder: (context, i) {
        final m = _marcas[i];
        return ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(m.studentId, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(m.marcadaEn),
        );
      },
    );
  }
}

/// Un hueco con icono, usado por los dos fallos (sin secciones, sin conexión).
class _Centro extends StatelessWidget {
  const _Centro({required this.icono, required this.mensaje, required this.onReintentar});

  final IconData icono;
  final String mensaje;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            if (onReintentar != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}
