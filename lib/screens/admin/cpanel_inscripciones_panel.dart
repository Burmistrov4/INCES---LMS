import 'package:flutter/material.dart';

import '../../core/gateways/selector_archivos.dart';
import '../../core/result.dart';
import '../../models/exportacion_hacer.dart';
import '../../models/inscripcion.dart';
import '../../repositories/exportacion_hacer_repository.dart';
import '../../repositories/inscripcion_repository.dart';
import '../../services/selector_archivos_navegador.dart';
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
///  · **Exportar Planilla HACER (.csv)** — descarga la nómina de la sección (una
///    fila por matriculado) desde `v_exportacion_hacer`, lista para la
///    plataforma del INCES.
///
/// **Por qué la exportación va por sección y no en un botón de la cabecera.**
/// El panel no tiene un selector de sección: pinta **una tarjeta por sección**, y
/// cada tarjeta es ya el contexto de su sección. Un botón global tendría que
/// preguntar «¿cuál?» en un diálogo, que es un paso de más para algo que la
/// pantalla ya sabe. El botón va donde está la sección, junto a «Ver cola» y
/// «Promover siguiente».
class CpanelInscripcionesPanel extends StatefulWidget {
  const CpanelInscripcionesPanel({
    super.key,
    this.repositorio,
    this.exportacion,
    this.selector,
  });

  final AdminInscripcionesRepository? repositorio;

  /// La nómina exportable. Se inyecta en pruebas.
  final ExportacionHacerRepository? exportacion;

  /// La descarga. Se inyecta porque la implementación real es del navegador y no
  /// compila en la VM — ver `selector_archivos.dart`.
  final SelectorDeArchivos? selector;

  @override
  State<CpanelInscripcionesPanel> createState() =>
      _CpanelInscripcionesPanelState();
}

class _CpanelInscripcionesPanelState extends State<CpanelInscripcionesPanel> {
  late final AdminInscripcionesRepository _repo =
      widget.repositorio ?? AdminInscripcionesRepository();
  late final ExportacionHacerRepository _exportacion =
      widget.exportacion ?? ExportacionHacerRepository();
  late final SelectorDeArchivos _selector =
      widget.selector ?? SelectorDeArchivosDelNavegador();

  List<OcupacionSeccion> _secciones = const [];
  bool _cargando = true;
  String? _error;

  final Set<String> _promoviendo = {};
  final Set<String> _exportando = {};
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

  /// Descarga la nómina de una sección como CSV, listo para HACER.
  ///
  /// El estado de carga se libera **en cuanto vuelve la consulta**, antes de
  /// descargar. Si se liberara al final, un fallo del navegador dejaría el botón
  /// girando para siempre — el fallo que la convención del proyecto prohíbe en
  /// todos los demás paneles.
  Future<void> _exportar(OcupacionSeccion o) async {
    setState(() => _exportando.add(o.seccionId));

    final resultado = await _exportacion.deSeccion(o.seccionId);
    if (!mounted) return;
    setState(() => _exportando.remove(o.seccionId));

    switch (resultado) {
      case Failure(error: final fallo):
        mostrarAviso(context, fallo.message, error: true);

      case Success(value: final exportacion):
        // Una sección sin matriculados no es un error: es una sección recién
        // abierta. Se dice con esas palabras en vez de descargar un archivo con
        // sólo la cabecera, que el administrador leería como «se exportó bien».
        if (exportacion.vacia) {
          mostrarAviso(
            context,
            'La sección «${o.nombre}» no tiene matriculados todavía: no hay '
            'nómina que exportar.',
          );
          return;
        }

        final nombre = nombreArchivoHacer(
          periodo: o.periodo,
          seccion: o.nombre,
          materia: o.materiaNombre,
        );

        try {
          await _selector.descargarTexto(
            nombre: nombre,
            contenido: exportacion.aCsv(),
          );
          if (!mounted) return;
          mostrarAviso(
            context,
            'Nómina exportada: ${exportacion.total} matriculado(s) en '
            '«$nombre».',
            exito: true,
          );
        } catch (_) {
          // El fallo de la descarga no se traga, pero tampoco se muestra el
          // `toString()` del error del navegador: al administrador no le dice
          // nada y no puede hacer nada con él.
          if (!mounted) return;
          mostrarAviso(
            context,
            'No se pudo descargar el archivo. Inténtalo de nuevo.',
            error: true,
          );
        }
    }
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

    return LayoutBuilder(
      builder: (context, restricciones) {
        // Dos tarjetas por fila en móvil, cuatro en escritorio. Con los 220 px
        // fijos, a 375 px se apilaban las cuatro y esa columna se comía la
        // pantalla antes de llegar a la lista de secciones.
        final anchoTarjeta = restricciones.maxWidth >= 480
            ? 220.0
            : (restricciones.maxWidth - 12) / 2;

        // Todo el cuerpo en un solo scroll. Antes sólo la lista era
        // desplazable y las métricas quedaban fuera: con el móvil apilado, la
        // suma de cabecera + métricas + aviso superaba la pantalla y la
        // `Column` desbordaba por abajo.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: anchoTarjeta,
                    child: TarjetaMetrica(
                      etiqueta: 'Secciones',
                      valor: '${_secciones.length}',
                      icono: Icons.explore_outlined,
                    ),
                  ),
                  SizedBox(
                    width: anchoTarjeta,
                    child: TarjetaMetrica(
                      etiqueta: 'Con oferta en el aire',
                      valor: '$_conOfertaVigente',
                      icono: Icons.local_offer_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  SizedBox(
                    width: anchoTarjeta,
                    child: TarjetaMetrica(
                      etiqueta: 'Cupos disponibles',
                      valor: '$_cuposDisponibles',
                      icono: Icons.event_seat_outlined,
                      color: IncesTheme.exito,
                    ),
                  ),
                  SizedBox(
                    width: anchoTarjeta,
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
                texto: '«Promover siguiente» se usa tras ampliar la capacidad de '
                    'una sección: sube al primero de la cola a «matriculado». Si '
                    'la sección está llena o ya tiene una oferta en el aire, no '
                    'promueve a nadie (lo confirma el mensaje).',
                icono: Icons.info_outline,
                tono: TonoAviso.info,
              ),
              const SizedBox(height: 8),
              const AvisoEnLinea(
                texto: '«Exportar Planilla HACER (.csv)» descarga la nómina de la '
                    'sección: una fila por matriculado, con el contexto de la '
                    'sección y sus datos de la planilla. Sólo salen los que tienen '
                    'asiento confirmado — la cola de espera y las bajas no son '
                    'nómina.',
                icono: Icons.download_outlined,
                tono: TonoAviso.info,
              ),
              const SizedBox(height: 12),
              for (final o in _secciones) _filaOcupacion(o),
            ],
          ),
        );
      },
    );
  }

  Widget _filaOcupacion(OcupacionSeccion o) {
    final theme = Theme.of(context);
    final ocupado = _promoviendo.contains(o.seccionId);
    final exportando = _exportando.contains(o.seccionId);
    final titulo = o.materiaNombre ?? o.nombre;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, restricciones) {
            final informacion = Column(
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
            );

            final botones = Wrap(
              spacing: 8,
              runSpacing: 8,
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
                // La exportación va ANTES de «Promover siguiente» a propósito:
                // leer la nómina no cambia nada, promover sí. La acción que
                // escribe queda la última, que es donde el ojo la busca.
                OutlinedButton.icon(
                  onPressed: exportando ? null : () => _exportar(o),
                  icon: exportando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 16),
                  label: Text(
                    exportando
                        ? 'Exportando…'
                        : 'Exportar Planilla HACER (.csv)',
                  ),
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
            );

            // Los botones eran un hijo **no flexible** de la `Row`, así que se
            // quedaban con su ancho natural y «Promover siguiente» (~200 px) no
            // cabía junto a la información a 375 px. En estrecho se apilan: los
            // botones reciben el ancho completo de la tarjeta y envuelven entre
            // sí si aun así no caben.
            //
            // Con el tercer botón —la exportación— el ancho natural del grupo ya
            // no cabe junto a la información en un portátil, y un `Wrap` **sin
            // techo de ancho no envuelve**: se sale de la `Row` y desborda. Por
            // eso va dentro de un `Flexible`, que le pone el techo y lo obliga a
            // envolver en vez de romper la tarjeta. Y por eso el umbral sube de
            // 560 a 640: por debajo, el grupo quedaría tan estrecho que
            // envolvería en tres líneas, y apilar la tarjeta entera se lee mejor.
            //
            // `Flexible` y no `Expanded`: el grupo no tiene por qué ocupar toda
            // su mitad, y `Expanded` lo estiraría dejando botones anchos y vacíos.
            const anchoMinimoParaFila = 640.0;
            if (restricciones.maxWidth >= anchoMinimoParaFila) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: informacion),
                  const SizedBox(width: 12),
                  Flexible(child: botones),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                informacion,
                const SizedBox(height: 12),
                botones,
              ],
            );
          },
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
