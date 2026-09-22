import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/gateways/aula_gateway.dart';
import '../core/gateways/selector_archivos.dart';
import '../core/result.dart';
import '../models/archivo.dart';
import '../repositories/archivos_repository.dart';
import '../theme/inces_theme.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import 'crear_anuncio_panel.dart';
import 'crear_tarea_panel.dart';
import 'gestor_documental_panel.dart';
import 'libro_calificaciones_panel.dart';

/// Aula Virtual de una sección (Módulo 6).
///
/// Una sección de M3 —con su roster de M4 y sus docentes de M3— es el «curso»
/// (D-1). Esta pantalla le da dos pestañas:
///
///  * **Tablón** — el feed de anuncios, más reciente primero.
///  * **Trabajo de clase** — las tareas y materiales, y para el estudiante el
///    estado de **su** entrega en cada una.
///
/// ## El punto de esta pantalla
///
/// Para el estudiante, abrir una tarea muestra el [GestorDocumentalPanel] de M5
/// atado a **su** entrega: el `entidadId` es el `m6_entregas.id`. Ésa es la
/// unión que M5 no podía expresar —`files_metadata.entidad_id` era un UUID sin
/// tabla que lo respaldara— y que M6 cierra (§3.3, D-8). El estudiante sube su
/// trabajo **desde el aula**, sin salir a otra pantalla.
///
/// ## Qué decide el rol, y qué no
///
/// [esDocente] sólo decide **presentación**: qué se pide y qué se pinta. **No es
/// autorización.** Quien puede ver o escribir lo decide la RLS y las RPC
/// `security definer` en la base (ADR-003). Si el docente no viera el panel de
/// entrega del alumno sólo por este booleano, la regla viviría en el cliente —y
/// un cliente se cambia—.
///
/// ## El puerto, no el servicio
///
/// La pantalla consume [AulaGateway]. La implementación HTTP está pendiente a
/// propósito (ver la cabecera del puerto): el JSON del backend no está cerrado y
/// adivinarlo daría una pantalla vacía sin error. Hoy se le pasa el doble de
/// `test/support/fake_aula_gateway.dart`.
class AulaVirtualDashboardScreen extends StatefulWidget {
  const AulaVirtualDashboardScreen({
    super.key,
    required this.seccionId,
    required this.seccionNombre,
    required this.gateway,
    this.esDocente = false,
    this.archivosRepositorio,
    this.selectorArchivos,
  });

  final String seccionId;

  /// Nombre visible de la sección (materia + lapso), ya resuelto por quien la
  /// abre. La pantalla no lo deduce: no conoce el catálogo de M2/M3.
  final String seccionNombre;

  final AulaGateway gateway;

  /// `true` ⇒ vista del docente. Ver la nota de la clase: es presentación, no
  /// autorización.
  final bool esDocente;

  /// El gestor documental de M5 que se incrusta en el detalle de la tarea.
  ///
  /// Se inyecta —y no se construye dentro— por la misma razón que en M5: la
  /// implementación real hace red y el doble de pruebas no. Sin este hueco, la
  /// prueba del `entidadId` sería imposible.
  final ArchivosRepository? archivosRepositorio;

  /// El diálogo de archivos del navegador. Se inyecta porque su implementación
  /// real no compila en la VM de `flutter test`.
  final SelectorDeArchivos? selectorArchivos;

  @override
  State<AulaVirtualDashboardScreen> createState() =>
      _AulaVirtualDashboardScreenState();
}

class _AulaVirtualDashboardScreenState
    extends State<AulaVirtualDashboardScreen> {
  // --- Tablón ---------------------------------------------------------------
  bool _cargandoTablon = true;
  String? _errorTablon;
  List<Anuncio> _anuncios = const [];

  // --- Trabajo de clase -----------------------------------------------------
  bool _cargandoTrabajo = true;
  String? _errorTrabajo;
  List<TareaDeClase> _tareas = const [];

  /// La entrega del estudiante por `tareaId`. Es el cruce que pinta el estado en
  /// cada tarjeta: `misEntregas()` no viene indexado, así que se indexa aquí.
  Map<String, Entrega> _entregasPorTarea = const {};

  bool _cargandoEntregas = false;
  String? _errorEntregas;

  /// La tarea abierta, si la hay. `null` ⇒ se ven las pestañas; no `null` ⇒ se
  /// ve el detalle. Se resuelve con estado y no empujando una ruta para que el
  /// detalle herede la altura acotada de [ContenidoSeccion] y el gestor
  /// documental (que es un `ListView`) reciba un alto finito sin trucos.
  TareaDeClase? _tareaAbierta;

  /// Ids de entrega con una acción en curso. Es un conjunto y no una bandera:
  /// dos entregas podrían estar ocupadas a la vez y cada botón debe reflejar
  /// sólo la suya.
  final Set<String> _ocupadas = <String>{};

  /// ¿Sigue cargando lo que la pestaña de trabajo necesita?
  ///
  /// Se mezclan tarea y entregas **para el estudiante**: pintar una tarjeta sin
  /// su estado de entrega y luego cambiarlo es peor que esperar un instante. El
  /// docente no pide entregas (esa ruta es del alumno), así que para él sólo
  /// cuenta la tarea.
  bool get _cargandoClase =>
      _cargandoTrabajo || (!widget.esDocente && _cargandoEntregas);

  @override
  void initState() {
    super.initState();
    _cargarTablon();
    _cargarTrabajo();
    // El docente no llama a `mis-entregas`: la ruta es del alumno y devolvería
    // 403. No es una optimización, es respetar el contrato de §6.
    if (!widget.esDocente) _cargarEntregas();
  }

  // ── Carga ──────────────────────────────────────────────────────────────────

  Future<void> _cargarTablon() async {
    setState(() {
      _cargandoTablon = true;
      _errorTablon = null;
    });

    final resultado =
        await Result.guard(() => widget.gateway.tablon(widget.seccionId));
    if (!mounted) return;

    setState(() {
      _cargandoTablon = false;
      resultado.when(
        success: (lista) => _anuncios = lista,
        failure: (fallo) => _errorTablon = fallo.message,
      );
    });
  }

  Future<void> _cargarTrabajo() async {
    setState(() {
      _cargandoTrabajo = true;
      _errorTrabajo = null;
    });

    final resultado =
        await Result.guard(() => widget.gateway.trabajoDeClase(widget.seccionId));
    if (!mounted) return;

    setState(() {
      _cargandoTrabajo = false;
      resultado.when(
        success: (lista) => _tareas = lista,
        failure: (fallo) => _errorTrabajo = fallo.message,
      );
    });
  }

  Future<void> _cargarEntregas() async {
    setState(() {
      _cargandoEntregas = true;
      _errorEntregas = null;
    });

    final resultado = await Result.guard(() => widget.gateway.misEntregas());
    if (!mounted) return;

    setState(() {
      _cargandoEntregas = false;
      resultado.when(
        success: (lista) => _entregasPorTarea = {
          for (final entrega in lista) entrega.tareaId: entrega,
        },
        failure: (fallo) => _errorEntregas = fallo.message,
      );
    });
  }

  // ── Acciones del estudiante ────────────────────────────────────────────────

  Future<void> _entregar(Entrega entrega) async {
    if (_ocupadas.contains(entrega.id)) return;

    setState(() => _ocupadas.add(entrega.id));

    final resultado =
        await Result.guard(() => widget.gateway.entregar(entrega.id));

    // El estado de carga se libera **antes** del `return` por desmontaje: al
    // revés, un desmontaje durante la petición dejaría el botón bloqueado para
    // siempre en la siguiente visita.
    if (!mounted) {
      _ocupadas.remove(entrega.id);
      return;
    }

    setState(() {
      _ocupadas.remove(entrega.id);
      resultado.when(
        success: (actualizada) =>
            _entregasPorTarea = {..._entregasPorTarea, actualizada.tareaId: actualizada},
        failure: (_) {},
      );
    });

    resultado.when(
      success: (_) => mostrarAviso(context, 'Tarea entregada.', exito: true),
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  Future<void> _reclamar(Entrega entrega) async {
    if (_ocupadas.contains(entrega.id)) return;

    setState(() => _ocupadas.add(entrega.id));

    final resultado =
        await Result.guard(() => widget.gateway.reclamar(entrega.id));

    if (!mounted) {
      _ocupadas.remove(entrega.id);
      return;
    }

    setState(() {
      _ocupadas.remove(entrega.id);
      resultado.when(
        success: (actualizada) =>
            _entregasPorTarea = {..._entregasPorTarea, actualizada.tareaId: actualizada},
        failure: (_) {},
      );
    });

    resultado.when(
      success: (_) => mostrarAviso(
        context,
        'Entrega reclamada: ya puedes volver a subir tu trabajo.',
        exito: true,
      ),
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  // ── Acciones del docente ────────────────────────────────────────────────────

  Future<void> _crearAnuncio() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearAnuncioPanel(
          seccionId: widget.seccionId,
          gateway: widget.gateway,
          onGuardado: _cargarTablon,
        ),
      ),
    );
    if (creado == true && mounted) _cargarTablon();
  }

  Future<void> _crearTarea() async {
    final creada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearTareaPanel(
          seccionId: widget.seccionId,
          gateway: widget.gateway,
          onGuardado: _cargarTrabajo,
        ),
      ),
    );
    if (creada == true && mounted) _cargarTrabajo();
  }

  Future<void> _abrirLibro(TareaDeClase tarea) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibroCalificacionesPanel(
          tareaId: tarea.id,
          tareaTitulo: tarea.titulo,
          gateway: widget.gateway,
          onCambio: _cargarTrabajo,
        ),
      ),
    );
  }

  // ── Interfaz ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tarea = _tareaAbierta;

    return ContenidoSeccion(
      migas: const ['Inicio', 'Académico', 'Aula Virtual'],
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TituloSeccion(
              widget.seccionNombre,
              subtitulo: 'Aula Virtual · tablón y trabajo de clase',
            ),
            const SizedBox(height: 8),
            if (tarea == null) ...[
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Tablón'),
                  Tab(text: 'Trabajo de Clase'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [_tablon(), _trabajoDeClase()],
                ),
              ),
            ] else
              Expanded(child: _detalleDeTarea(tarea)),
          ],
        ),
      ),
    );
  }

  // ── Tablón ─────────────────────────────────────────────────────────────────

  Widget _tablon() {
    final contenido = _contenidoTablon();
    if (!widget.esDocente) return contenido;

    // El docente ve un botón de «Nuevo anuncio» sobre el feed: el tablón es suyo
    // y la acción de crear va donde está el contenido, no escondida en otro menú.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _cargandoTablon ? null : _crearAnuncio,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nuevo anuncio'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: contenido),
      ],
    );
  }

  Widget _contenidoTablon() {
    if (_cargandoTablon) {
      return const Center(child: CircularProgressIndicator());
    }

    // Un fallo de carga se cuenta **sin** vaciar la pantalla: las pestañas
    // siguen ahí y la otra sigue funcionando. Es la diferencia entre un feed
    // incompleto y una pantalla muerta.
    if (_errorTablon != null) {
      return ListView(
        children: [
          AvisoEnLinea(
            tono: TonoAviso.peligro,
            icono: Icons.cloud_off_outlined,
            texto: 'No pudimos cargar el tablón: $_errorTablon',
          ),
        ],
      );
    }

    if (_anuncios.isEmpty) {
      return ListView(
        children: const [
          PanelVacio(
            titulo: 'Todavía no hay anuncios',
            mensaje: 'Cuando el docente publique algo en el tablón de esta '
                'sección, aparecerá aquí.',
            icono: Icons.campaign_outlined,
          ),
        ],
      );
    }

    // **Sin reordenar.** El servidor ya entrega el feed de más reciente a más
    // antiguo; un segundo criterio de orden aquí sería una segunda fuente de
    // verdad que se desvía de la del feed en cuanto una cambie.
    return ListView(
      children: [for (final anuncio in _anuncios) _tarjetaAnuncio(anuncio)],
    );
  }

  Widget _tarjetaAnuncio(Anuncio anuncio) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.campaign_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(anuncio.titulo, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(anuncio.cuerpo, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Etiqueta(
              texto: formatearFechaHora(DateTime.tryParse(anuncio.publicadoEn ?? '')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Trabajo de clase ───────────────────────────────────────────────────────

  Widget _trabajoDeClase() {
    final contenido = _contenidoTrabajo();
    if (!widget.esDocente) return contenido;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _cargandoClase ? null : _crearTarea,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nueva tarea'),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: contenido),
      ],
    );
  }

  Widget _contenidoTrabajo() {
    if (_cargandoClase) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorTrabajo != null) {
      return ListView(
        children: [
          AvisoEnLinea(
            tono: TonoAviso.peligro,
            icono: Icons.cloud_off_outlined,
            texto: 'No pudimos cargar el trabajo de clase: $_errorTrabajo',
          ),
        ],
      );
    }

    return ListView(
      children: [
        // Un fallo de las entregas no impide ver las tareas: se avisa y se
        // siguen pintando, sólo que sin el estado de cada una.
        if (_errorEntregas != null) ...[
          AvisoEnLinea(
            tono: TonoAviso.advertencia,
            icono: Icons.assignment_late_outlined,
            texto: 'No pudimos cargar tus entregas: $_errorEntregas El estado de '
                'cada tarea no se puede mostrar ahora mismo.',
          ),
          const SizedBox(height: 12),
        ],
        if (_tareas.isEmpty)
          const PanelVacio(
            titulo: 'Todavía no hay trabajo de clase',
            mensaje: 'Cuando el docente publique una tarea o un material, '
                'aparecerá aquí.',
            icono: Icons.assignment_outlined,
          )
        else
          for (final tarea in _tareas) _tarjetaTarea(tarea),
      ],
    );
  }

  Widget _tarjetaTarea(TareaDeClase tarea) {
    final theme = Theme.of(context);
    final entrega = widget.esDocente ? null : _entregasPorTarea[tarea.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Abrir el detalle es lo que lleva al gestor documental del alumno.
        onTap: () => setState(() => _tareaAbierta = tarea),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_iconoTipo(tarea.tipo), size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tarea.titulo, style: theme.textTheme.titleSmall),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tarea.descripcion,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Etiqueta(texto: _etiquetaTipo(tarea.tipo)),
                  // **Un material no lleva puntos ni fecha.** El modelo trae
                  // `puntosMaximos == 0` y `fechaLimite == null` por diseño, y
                  // pintarlos sería un «0 pts» y una fecha vacía sobre material
                  // de lectura: una mentira sobre lo que la tarea es.
                  if (tarea.tipo.seCalifica) ...[
                    Etiqueta(texto: '${_formatoPuntos(tarea.puntosMaximos)} pts'),
                    if (tarea.fechaLimite != null)
                      Etiqueta(
                        texto:
                            'Vence ${formatearFechaHora(DateTime.tryParse(tarea.fechaLimite!))}',
                      ),
                  ],
                  if (entrega != null) _insigniaEntrega(entrega, tarea),
                ],
              ),
              if (widget.esDocente)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirLibro(tarea),
                      icon: const Icon(Icons.grading_outlined, size: 16),
                      label: const Text('Calificar'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Insignia del estado de la entrega del estudiante.
  ///
  /// «Faltante» —no entregó y venció— **se deriva aquí**, no se lee de un campo:
  /// el backend no guarda un estado «faltante» a propósito (§4.3), así que la UI
  /// lo compone con el reloj. Es la única forma de que un alumno que entregue
  /// tarde deje de aparecer como faltante sin que nadie reescriba una fila.
  Widget _insigniaEntrega(Entrega entrega, TareaDeClase tarea) {
    final vencidaSinEntregar = entrega.estado == EstadoEntrega.asignada &&
        tarea.fechaLimite != null &&
        DateTime.now().isAfter(DateTime.tryParse(tarea.fechaLimite!) ?? DateTime.now());

    final (color, texto) = switch (entrega.estado) {
      EstadoEntrega.asignada => (IncesTheme.advertencia, 'Pendiente'),
      EstadoEntrega.entregada => (IncesTheme.exito, 'Entregada'),
      EstadoEntrega.devuelta => (Theme.of(context).colorScheme.primary, 'Devuelta'),
      EstadoEntrega.reclamada => (
          Theme.of(context).colorScheme.onSurfaceVariant,
          'Reclamada',
        ),
    };

    final etiquetaNota = entrega.estado == EstadoEntrega.devuelta &&
            entrega.notaAsignada != null
        ? ' · ${_formatoNota(entrega.notaAsignada!)} pts'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconoEntrega(entrega.estado), size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            '$texto$etiquetaNota',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          // La tarea vencida sin entregar sigue siendo «Pendiente», pero se
          // marca: el estado real —no entregada— y el aviso de que ya venció son
          // dos cosas distintas y el alumno necesita las dos.
          if (vencidaSinEntregar) ...[
            const SizedBox(width: 6),
            Text(
              '· Vencida',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: IncesTheme.rojoInces,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Detalle de una tarea ───────────────────────────────────────────────────

  Widget _detalleDeTarea(TareaDeClase tarea) {
    final theme = Theme.of(context);
    final entrega = widget.esDocente ? null : _entregasPorTarea[tarea.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _tareaAbierta = null),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Volver al trabajo de clase'),
          ),
        ),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tarea.titulo, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                // La descripción se acota a unas líneas: el detalle comparte una
                // altura **acotada** con el gestor documental de abajo (que es
                // un `ListView`), y una cabecera que creciera sin límite lo
                // empujaría fuera de la pantalla.
                Text(
                  tarea.descripcion,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Etiqueta(texto: _etiquetaTipo(tarea.tipo)),
                    if (tarea.tipo.seCalifica) ...[
                      Etiqueta(texto: '${_formatoPuntos(tarea.puntosMaximos)} pts'),
                      if (tarea.fechaLimite != null)
                        Etiqueta(
                          texto: 'Vence ${formatearFechaHora(DateTime.tryParse(tarea.fechaLimite!))}',
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _cuerpoDetalle(tarea, entrega)),
      ],
    );
  }

  Widget _cuerpoDetalle(TareaDeClase tarea, Entrega? entrega) {
    // Docente: su panel de entrega del alumno no existe (esa vista es del
    // estudiante); en su lugar abre el libro de calificaciones de esta tarea,
    // que es donde califica y devuelve. La acción está aquí —y no sólo en la
    // tarjeta— porque desde el detalle ya tiene la tarea enfocada.
    if (widget.esDocente) {
      return ListView(
        children: [
          FilledButton.icon(
            onPressed: () => _abrirLibro(tarea),
            icon: const Icon(Icons.grading_outlined, size: 18),
            label: const Text('Ver libro de calificaciones'),
          ),
          const SizedBox(height: 12),
          const AvisoEnLinea(
            icono: Icons.info_outline,
            texto: 'Desde aquí calificas las entregas de esta tarea y las '
                'devuelves a tus estudiantes. Una vez devuelta, la nota deja de '
                'ser borrador y el alumno la ve.',
          ),
        ],
      );
    }

    // Estudiante sin entrega: no debería pasar (los placeholders se crean al
    // publicar, D-7), así que en vez de fingir un estado se dice.
    if (entrega == null) {
      return ListView(
        children: const [
          AvisoEnLinea(
            tono: TonoAviso.advertencia,
            icono: Icons.assignment_late_outlined,
            texto: 'Esta tarea todavía no tiene una entrega tuya asignada, así '
                'que aún no puedes subir el trabajo. Vuelve a intentarlo más '
                'tarde o avisa a tu docente.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _barraDeEntrega(entrega),
        const SizedBox(height: 12),
        // **Aquí está el objetivo de la fase.** El `entidadId` es el
        // `m6_entregas.id`: es la unión que deja al docente ver esta entrega
        // desde las políticas de M6 sobre `files_metadata` (§3.3). Pasar
        // cualquier otro id —el de la tarea, por ejemplo— colgaría el archivo
        // de una entidad que no existe para el docente, sin dar error.
        Expanded(
          child: GestorDocumentalPanel(
            entityType: TipoEntidadArchivo.taskSubmission,
            entidadId: entrega.id,
            titulo: 'Mi entrega',
            repositorio: widget.archivosRepositorio,
            selector: widget.selectorArchivos,
          ),
        ),
      ],
    );
  }

  /// Estado de la entrega y, si procede, la acción de entregar o reclamar.
  Widget _barraDeEntrega(Entrega entrega) {
    final ocupada = _ocupadas.contains(entrega.id);

    // La acción depende del estado: `ASIGNADA`/`RECLAMADA` se entregan,
    // `ENTREGADA` se reclama, y una `DEVUELTA` ya no admite ninguna (el docente
    // cerró el ciclo). Devolver `null` en vez de un botón deshabilitado evita
    // ofrecer una acción que no existe.
    final (accion, etiqueta) = switch (entrega.estado) {
      EstadoEntrega.asignada => (_entregar, 'Entregar tarea'),
      EstadoEntrega.reclamada => (_entregar, 'Volver a entregar'),
      EstadoEntrega.entregada => (_reclamar, 'Reclamar entrega'),
      EstadoEntrega.devuelta => (null, ''),
    };

    final nota = entrega.estado == EstadoEntrega.devuelta &&
            entrega.notaAsignada != null
        ? 'Nota: ${_formatoNota(entrega.notaAsignada!)} pts.'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvisoEnLinea(
          tono: switch (entrega.estado) {
            EstadoEntrega.asignada => TonoAviso.advertencia,
            EstadoEntrega.entregada => TonoAviso.exito,
            EstadoEntrega.devuelta => TonoAviso.info,
            EstadoEntrega.reclamada => TonoAviso.advertencia,
          },
          icono: _iconoEntrega(entrega.estado),
          texto: [
            _etiquetaEntregaLarga(entrega.estado),
            if (entrega.esTardia) 'La entregaste después de la fecha límite.',
            ?nota,
          ].join(' '),
        ),
        if (accion != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: ocupada ? null : () => accion(entrega),
              icon: ocupada
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(ocupada ? 'Procesando…' : etiqueta),
            ),
          ),
        ],
      ],
    );
  }

  // ── Etiquetas y utilidades ─────────────────────────────────────────────────

  IconData _iconoTipo(TipoTarea tipo) => switch (tipo) {
        TipoTarea.tarea => Icons.assignment_outlined,
        TipoTarea.material => Icons.menu_book_outlined,
        TipoTarea.pregunta => Icons.help_outline,
      };

  String _etiquetaTipo(TipoTarea tipo) => switch (tipo) {
        TipoTarea.tarea => 'Tarea',
        TipoTarea.material => 'Material',
        TipoTarea.pregunta => 'Pregunta',
      };

  IconData _iconoEntrega(EstadoEntrega estado) => switch (estado) {
        EstadoEntrega.asignada => Icons.schedule_outlined,
        EstadoEntrega.entregada => Icons.check_circle_outline,
        EstadoEntrega.devuelta => Icons.assignment_turned_in_outlined,
        EstadoEntrega.reclamada => Icons.undo_outlined,
      };

  String _etiquetaEntregaLarga(EstadoEntrega estado) => switch (estado) {
        EstadoEntrega.asignada => 'Pendiente de entrega.',
        EstadoEntrega.entregada => 'Entregada.',
        EstadoEntrega.devuelta => 'Devuelta por el docente.',
        EstadoEntrega.reclamada => 'Reclamada: puedes volver a subirla.',
      };

  /// Puntos sin decimales de adorno: «20 pts» y no «20,0 pts».
  String _formatoPuntos(double puntos) => _formatoNota(puntos);

  /// Nota en la escala 0–20, con coma decimal y sin ceros de relleno.
  String _formatoNota(double nota) {
    if (nota == nota.roundToDouble()) return nota.toStringAsFixed(0);
    return nota.toStringAsFixed(1).replaceAll('.', ',');
  }
}
