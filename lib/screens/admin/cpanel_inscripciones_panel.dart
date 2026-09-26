import 'package:flutter/material.dart';

import '../../core/gateways/selector_archivos.dart';
import '../../core/result.dart';
import '../../models/inscripcion.dart';
import '../../repositories/exportacion_hacer_repository.dart';
import '../../repositories/inscripcion_repository.dart';
import '../../services/hacer_export_service.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';
import 'cpanel_inscripciones_cola_dialog.dart';

/// Panel de ocupación y cupos del administrador (Módulo 4).
///
/// Muestra la ocupación de cada sección (`v_ocupacion_secciones`) con sus
/// acciones de cupo:
///
///  · **Expirar ofertas** — vence las ofertas caducadas (idempotente).
///  · **Reincorporar** — da de alta a alguien dado de baja en esa sección; puede
///    dejar la sección por encima de su capacidad, por eso lleva aviso. El
///    diálogo ofrece los `DROPPED` **de esa sección**: son los únicos que el
///    backend acepta (a quien nunca cursó le responde 404
///    `SIN_HISTORIAL_EN_SECCION`).
///  · **Promover siguiente** — sube al primero de la cola a `ENROLLED`. Está
///    pensado para usarse **tras ampliar la capacidad**: si la sección está
///    llena o ya tiene una oferta en el aire, la RPC no promueve a nadie y el
///    repositorio lo devuelve como `Failure` de validación, no como error.
///  · **Exportar Planilla HACER (.csv)** — descarga la nómina de la sección (una
///    fila por matriculado) desde `v_exportacion_hacer`, lista para la
///    plataforma del INCES.
///
/// **Por qué las acciones de sección van en la tarjeta y no en la cabecera.**
/// El panel no tiene un selector de sección: pinta **una tarjeta por sección**, y
/// cada tarjeta es ya el contexto de su sección. Un botón global tendría que
/// preguntar «¿cuál?» en un diálogo, que es un paso de más para algo que la
/// pantalla ya sabe. Las acciones de sección —«Ver cola», «Exportar»,
/// «Reincorporar» y «Promover siguiente»— van donde está la sección.
///
/// «Reincorporar» nació en la cabecera, y el resultado se lee en lo que pedía:
/// dos **UUIDs escritos a mano**, porque un botón global no tiene la sección y no
/// había de dónde sacarla. Un control que no puede funcionar es peor que uno
/// ausente: ocupa sitio y promete algo.
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

  /// La exportación completa —consultar, serializar y entregar— vive en el
  /// servicio, no aquí. El panel sólo traduce su desenlace a un aviso: la
  /// secuencia no debería estar mezclada con `setState`, y así se puede probar
  /// sin montar una pantalla.
  late final HacerExportService _exportacion = HacerExportService(
    repositorio: widget.exportacion,
    selector: widget.selector,
  );

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

  /// Abre el diálogo de reincorporación para **una** sección.
  ///
  /// Recibe la sección en vez de pedirla en el diálogo: la tarjeta que se pulsó
  /// ya es el contexto, y es además lo que permite listar sólo a los `DROPPED`
  /// de esa sección —los únicos que el backend acepta reincorporar—.
  Future<void> _abrirReincorporar(OcupacionSeccion o) async {
    final hecho = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoReincorporar(
        repo: _repo,
        seccionId: o.seccionId,
        seccionNombre: o.materiaNombre ?? o.nombre,
      ),
    );
    if (hecho != true || !mounted) return;
    _cargar();
  }

  /// Descarga la nómina de una sección como CSV, listo para HACER.
  ///
  /// **El panel no exporta: traduce un desenlace a un aviso.** Consultar la
  /// vista, serializar el archivo y entregarlo son tres pasos que viven en
  /// [HacerExportService]; aquí sólo se convierte su resultado en el mensaje que
  /// el administrador lee. Antes esa secuencia estaba escrita dentro de este
  /// método, mezclada con `setState`, y por eso no se podía probar sin montar la
  /// pantalla entera.
  ///
  /// **Sobre el estado de carga.** Se libera al volver la exportación completa,
  /// no sólo la consulta. La convención del proyecto —que el botón nunca quede
  /// girando para siempre— se conserva por otra vía: `descargarTexto` **no hace
  /// trabajo de red** (crea el `Blob`, pulsa el enlace y revoca la URL, todo
  /// local) y su único modo de fallo es lanzar, que el servicio captura y
  /// convierte en [DescargaFallida]. Lo que de verdad hace girar el botón es la
  /// espera de la red, y esa sigue cubierta. **Si algún día el servicio gana un
  /// paso que espere a algo externo —una subida, un diálogo—, la bandera tendrá
  /// que liberarse antes de ese paso y no después.**
  Future<void> _exportar(OcupacionSeccion o) async {
    setState(() => _exportando.add(o.seccionId));

    final resultado = await _exportacion.exportarSeccion(
      seccionId: o.seccionId,
      periodo: o.periodo,
      seccion: o.nombre,
      materia: o.materiaNombre,
    );

    if (!mounted) return;
    setState(() => _exportando.remove(o.seccionId));

    // `switch` sobre un `sealed`: si el servicio gana un desenlace nuevo, esto
    // deja de compilar en vez de dejar caer el caso al vacío.
    switch (resultado) {
      case ConsultaFallida(mensaje: final mensaje):
        mostrarAviso(context, mensaje, error: true);

      case DescargaFallida():
        // No se muestra el `toString()` del error del navegador: al
        // administrador no le dice nada y no puede hacer nada con él.
        mostrarAviso(
          context,
          'No se pudo descargar el archivo. Inténtalo de nuevo.',
          error: true,
        );

      // Una sección sin matriculados no es un error: es una sección recién
      // abierta. Se dice con esas palabras en vez de descargar un archivo con
      // sólo la cabecera, que el administrador leería como «se exportó bien».
      case NadaQueExportar(seccion: final seccion):
        mostrarAviso(
          context,
          'La sección «$seccion» no tiene matriculados todavía: no hay '
          'nómina que exportar.',
        );

      case NominaDescargada(
          nombreArchivo: final nombre,
          matriculados: final total,
        ):
        mostrarAviso(
          context,
          'Nómina exportada: $total matriculado(s) en «$nombre».',
          exito: true,
        );
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
        // «Reincorporar» ya NO vive aquí. Era el único botón global y por eso
        // tenía que preguntar en un diálogo cuál era la sección —y, al no tener
        // el contexto, acabó pidiendo el uuid a mano—. Ahora va en la tarjeta de
        // la sección, junto a «Ver cola» y «Promover siguiente», que es la regla
        // que este mismo archivo declara para la exportación.
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
                // Reincorporar va aquí, con la sección delante, y no en la
                // cabecera: la tarjeta ya sabe de qué sección se trata, así que
                // el diálogo no tiene que preguntarlo y puede listar sólo a los
                // dados de baja DE ESTA sección —los únicos que el backend
                // acepta—. Va antes de «Promover siguiente» para que la acción
                // más consecuente siga siendo la última.
                OutlinedButton.icon(
                  onPressed: () => _abrirReincorporar(o),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                  label: const Text('Reincorporar'),
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
/// Diálogo para reincorporar a alguien dado de baja en **una** sección.
///
/// **Antes pedía dos UUIDs por teclado** («ID del estudiante», «ID de la
/// sección»). Existía, compilaba, pasaba sus pruebas y **no se podía usar**:
/// ningún administrador conoce el uuid de un estudiante. Un control que no puede
/// funcionar es peor que uno ausente, porque ocupa sitio y promete algo.
///
/// Ahora se **elige**, y la lista de candidatos no es una comodidad: es la única
/// que puede funcionar. `reincorporar_inscripcion` exige que el estudiante
/// **tenga historial en esa sección** —a quien nunca cursó se le responde 404
/// `SIN_HISTORIAL_EN_SECCION`—, así que los únicos elegibles son los `DROPPED`
/// de la sección que el administrador ya tenía delante. Un buscador libre de
/// estudiantes habría invitado a un error que el backend rechaza por diseño.
///
/// La sección **no se pregunta**: llega por parámetro desde la tarjeta que se
/// pulsó. Es la misma razón por la que la exportación va por tarjeta —un diálogo
/// que preguntara «¿cuál sección?» sería un paso de más para algo que la pantalla
/// ya sabe— y, además, es lo que permite acotar los candidatos a esa sección.
class _DialogoReincorporar extends StatefulWidget {
  const _DialogoReincorporar({
    required this.repo,
    required this.seccionId,
    required this.seccionNombre,
  });

  final AdminInscripcionesRepository repo;
  final String seccionId;
  final String seccionNombre;

  @override
  State<_DialogoReincorporar> createState() => _DialogoReincorporarState();
}

class _DialogoReincorporarState extends State<_DialogoReincorporar> {
  List<InscripcionDetallada> _candidatos = const [];
  String? _estudianteId;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCandidatos();
  }

  /// Los únicos reincorporables de la sección: los que ya cursaron y se dieron
  /// de baja. `ENROLLED` ya está dentro, `WAITLISTED` nunca entró y `PENDING_BID`
  /// tiene una oferta viva; ninguno de los tres tiene una baja que revertir.
  static List<InscripcionDetallada> _bajasDe(List<InscripcionDetallada> todas) =>
      todas.where((i) => i.estado == EstadoInscripcion.dropped).toList();

  Future<void> _cargarCandidatos() async {
    final resultado =
        await widget.repo.obtenerInscripcionesDeSeccion(widget.seccionId);
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final todas):
          _candidatos = _bajasDe(todas);
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _guardar() async {
    if (_guardando || _estudianteId == null) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = await widget.repo.reincorporar(
      estudianteId: _estudianteId!,
      seccionId: widget.seccionId,
    );
    if (!mounted) return;
    setState(() => _guardando = false);

    resultado.when(
      success: (_) => Navigator.of(context).pop(true),
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  /// Etiqueta de un candidato: el nombre si lo hay, el correo si no, y el id
  /// sólo como último recurso —nunca como primera opción, que es justo lo que
  /// este diálogo viene a quitar de encima—.
  static String _etiquetaCandidato(InscripcionDetallada i) =>
      i.estudianteNombre ?? i.estudianteEmail ?? i.estudianteId;

  @override
  Widget build(BuildContext context) {
    final puedeGuardar = !_guardando && _estudianteId != null;

    return AlertDialog(
      title: const Text('Reincorporar estudiante'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
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
              Text(
                'Sección: ${widget.seccionNombre}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _selectorCandidato(),
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
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: puedeGuardar ? _guardar : null,
          child: Text(_guardando ? 'Guardando…' : 'Reincorporar'),
        ),
      ],
    );
  }

  Widget _selectorCandidato() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    if (_candidatos.isEmpty) {
      // No es un error: es la respuesta. Una sección sin bajas no tiene a quién
      // reincorporar, y el botón de confirmar queda deshabilitado —mejor eso que
      // un desplegable vacío que parece una avería—.
      return const AvisoEnLinea(
        texto: 'En esta sección no hay nadie dado de baja, así que no hay a '
            'quién reincorporar.',
        icono: Icons.info_outline,
        tono: TonoAviso.info,
      );
    }

    // `DropdownButton` y no `DropdownButtonFormField`: el primero recibe el
    // valor por `value` y se repinta al cambiarlo, mientras que el segundo lo
    // toma como `initialValue` de un `FormField` y **no propaga un cambio**
    // posterior. Con `DropdownButtonFormField` la selección no se vería hasta
    // cerrar y reabrir, que es la trampa documentada de `TextFormField`.
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Estudiante dado de baja',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _estudianteId,
          isExpanded: true,
          isDense: true,
          hint: const Text('Elige a quién reincorporar'),
          items: [
            for (final candidato in _candidatos)
              DropdownMenuItem(
                value: candidato.estudianteId,
                child: Text(
                  _etiquetaCandidato(candidato),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _guardando
              ? null
              : (valor) => setState(() => _estudianteId = valor),
        ),
      ),
    );
  }
}
