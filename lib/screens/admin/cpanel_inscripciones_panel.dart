import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/inscripcion.dart';
import '../../repositories/inscripcion_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';
import 'cpanel_inscripciones_cola_dialog.dart';

/// Panel de ocupación y cupos del administrador (Módulo 4).
///
/// Muestra la ocupación de cada sección (`v_ocupacion_secciones`) con sus
/// acciones de cupo:
///
///  · **Expirar ofertas** — vence las ofertas caducadas (idempotente).
///  · **Reincorporar** — da de alta a alguien dado de baja; puede dejar la
///    sección por encima de su capacidad, por eso lleva aviso.
///  · **Promover siguiente** — sube al primero de la cola a `ENROLLED`. Está
///    pensado para usarse **tras ampliar la capacidad**: si la sección está
///    llena o ya tiene una oferta en el aire, la RPC no promueve a nadie y el
///    repositorio lo devuelve como `Failure` de validación, no como error.
class CpanelInscripcionesPanel extends StatefulWidget {
  const CpanelInscripcionesPanel({super.key, this.repositorio});

  final AdminInscripcionesRepository? repositorio;

  @override
  State<CpanelInscripcionesPanel> createState() =>
      _CpanelInscripcionesPanelState();
}

class _CpanelInscripcionesPanelState extends State<CpanelInscripcionesPanel> {
  late final AdminInscripcionesRepository _repo =
      widget.repositorio ?? AdminInscripcionesRepository();

  List<OcupacionSeccion> _secciones = const [];
  bool _cargando = true;
  String? _error;

  final Set<String> _promoviendo = {};
  bool _expirando = false;

  int get _conOfertaVigente =>
      _secciones.where((o) => o.ofertaVigente).length;
  int get _cuposDisponibles =>
      _secciones.fold(0, (s, o) => s + o.cuposDisponibles);
  int get _cuposOcupados =>
      _secciones.fold(0, (s, o) => s + o.cuposOcupados);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final resultado = await _repo.obtenerOcupacion();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final secciones):
          _secciones = secciones;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _promover(OcupacionSeccion o) async {
    setState(() => _promoviendo.add(o.seccionId));
    final resultado = await _repo.promoverSiguiente(o.seccionId);
    if (!mounted) return;
    setState(() => _promoviendo.remove(o.seccionId));

    resultado.when(
      success: (promovida) {
        mostrarAviso(
          context,
          'Promovido ${promovida.estudianteId}: ya tiene su asiento.',
          exito: true,
        );
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  Future<void> _expirar() async {
    setState(() => _expirando = true);
    final resultado = await _repo.expirarOfertas();
    if (!mounted) return;
    setState(() => _expirando = false);

    resultado.when(
      success: (vencidas) {
        mostrarAviso(
          context,
          vencidas == 0
              ? 'No había ofertas caducadas pendientes.'
              : 'Se vencieron $vencidas oferta(s) de cupo.',
          exito: vencidas > 0,
        );
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  Future<void> _abrirReincorporar() async {
    final hecho = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoReincorporar(repo: _repo),
    );
    if (hecho != true || !mounted) return;
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecera(),
        const SizedBox(height: 12),
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

  Widget _cabecera() {
    return TituloSeccion(
      'Inscripciones y Cupos',
      subtitulo: 'Ocupación de cada sección, ofertas en el aire y acciones de '
          'cupo. Amplía la capacidad antes de «Promover siguiente».',
      acciones: [
        OutlinedButton.icon(
          onPressed: _expirando ? null : _expirar,
          icon: _expirando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.hourglass_disabled_outlined, size: 17),
          label: Text(_expirando ? 'Venciendo…' : 'Expirar ofertas'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _abrirReincorporar,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
          label: const Text('Reincorporar'),
        ),
      ],
    );
  }

  Widget _cuerpo() {
    if (_secciones.isEmpty) {
      return const PanelVacio(
        titulo: 'No hay secciones',
        mensaje: 'Cuando el centro registre secciones con su capacidad, las '
            'verás aquí con su ocupación en tiempo real.',
        icono: Icons.explore_outlined,
      );
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: TarjetaMetrica(
                etiqueta: 'Secciones',
                valor: '${_secciones.length}',
                icono: Icons.explore_outlined,
              ),
            ),
            SizedBox(
              width: 220,
              child: TarjetaMetrica(
                etiqueta: 'Con oferta en el aire',
                valor: '$_conOfertaVigente',
                icono: Icons.local_offer_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(
              width: 220,
              child: TarjetaMetrica(
                etiqueta: 'Cupos disponibles',
                valor: '$_cuposDisponibles',
                icono: Icons.event_seat_outlined,
                color: IncesTheme.exito,
              ),
            ),
            SizedBox(
              width: 220,
              child: TarjetaMetrica(
                etiqueta: 'Cupos ocupados',
                valor: '$_cuposOcupados',
                icono: Icons.people_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const AvisoEnLinea(
          texto: '«Promover siguiente» se usa tras ampliar la capacidad de una '
              'sección: sube al primero de la cola a «matriculado». Si la '
              'sección está llena o ya tiene una oferta en el aire, no promueve '
              'a nadie (lo confirma el mensaje).',
          icono: Icons.info_outline,
          tono: TonoAviso.info,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final o in _secciones) _filaOcupacion(o),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaOcupacion(OcupacionSeccion o) {
    final theme = Theme.of(context);
    final ocupado = _promoviendo.contains(o.seccionId);
    final titulo = o.materiaNombre ?? o.nombre;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (o.programaNombre != null) o.programaNombre!,
                      o.periodo,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Etiqueta(texto: 'Cupo ${o.resumenCupo}'),
                      Etiqueta(
                        texto: o.cuposDisponibles > 0
                            ? '${o.cuposDisponibles} disponible(s)'
                            : 'Sin cupos',
                      ),
                      if (o.ofertaVigente)
                        const Etiqueta(
                          texto: 'Oferta en el aire',
                          destacada: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => mostrarColaDeSeccion(
                    context: context,
                    repo: _repo,
                    seccionId: o.seccionId,
                    seccionNombre: titulo,
                  ),
                  icon: const Icon(Icons.list_alt_outlined, size: 16),
                  label: const Text('Ver cola'),
                ),
                FilledButton.icon(
                  onPressed: ocupado ? null : () => _promover(o),
                  icon: ocupado
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_outlined, size: 16),
                  label: Text(ocupado ? 'Promoviendo…' : 'Promover siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de reincorporación (Módulo 4, acción de admin).
///
/// Reincorpora a un estudiante dado de baja. El backend lo permite aunque la
/// sección quede por encima de su capacidad (`sobrecupo`), por eso el aviso lo
/// deja claro antes de confirmar.
class _DialogoReincorporar extends StatefulWidget {
  const _DialogoReincorporar({required this.repo});

  final AdminInscripcionesRepository repo;

  @override
  State<_DialogoReincorporar> createState() => _DialogoReincorporarState();
}

class _DialogoReincorporarState extends State<_DialogoReincorporar> {
  final _forma = GlobalKey<FormState>();
  final _estudiante = TextEditingController();
  final _seccion = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _estudiante.dispose();
    _seccion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_forma.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = await widget.repo.reincorporar(
      estudianteId: _estudiante.text.trim(),
      seccionId: _seccion.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);

    resultado.when(
      success: (_) => Navigator.of(context).pop(true),
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reincorporar estudiante'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _forma,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AvisoEnLinea(
                  texto: 'Reincorpora a alguien dado de baja. Puede dejar la '
                      'sección por encima de su capacidad: úsalo tras ampliar el '
                      'cupo o cuando la demanda lo justifica.',
                  icono: Icons.info_outline,
                  tono: TonoAviso.advertencia,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _estudiante,
                  decoration: const InputDecoration(
                    labelText: 'ID del estudiante',
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Indica el ID del estudiante.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _seccion,
                  decoration: const InputDecoration(
                    labelText: 'ID de la sección',
                    isDense: true,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Indica el ID de la sección.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AvisoEnLinea(
                    texto: _error!,
                    icono: Icons.error_outline,
                    tono: TonoAviso.peligro,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Reincorporar'),
        ),
      ],
    );
  }
}
