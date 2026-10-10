import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/gateways/curriculo_gateway.dart';
import '../../core/reglas_curriculo.dart';
import '../../models/pensum.dart';
import '../../models/programa.dart';
import '../../repositories/curriculo_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';
import 'asistente_curriculo_screen.dart';

/// Panel de programas académicos (Módulo 2).
///
/// Es la puerta de entrada al asistente de tres pasos. La lista no se limita a
/// mostrar programas: avisa de los que están **vacíos**, porque un programa sin
/// materias no se puede activar —el backend lo rechaza con un 400 desde el
/// trigger diferido— y descubrirlo al pulsar el interruptor es tarde.
///
/// **Ninguna acción borra.** Archivar es desactivar: un `DELETE` se llevaría por
/// delante el histórico de secciones y notas que apunta al programa.
class CpanelProgramasPanel extends StatefulWidget {
  const CpanelProgramasPanel({super.key, this.repositorio});

  final CurriculoRepository? repositorio;

  @override
  State<CpanelProgramasPanel> createState() => _CpanelProgramasPanelState();
}

class _CpanelProgramasPanelState extends State<CpanelProgramasPanel> {
  late final CurriculoRepository _repo =
      widget.repositorio ?? CurriculoRepository();

  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;

  TipoPrograma? _tipo;
  bool? _activo;
  int _desplazamiento = 0;

  List<ProgramaConTotales> _programas = const [];
  int _total = 0;
  bool _cargando = true;
  String? _error;

  /// Identificador del programa cuya activación está en curso. Se bloquea sólo
  /// esa fila: el guardado de un programa no debe impedir mirar los demás.
  String? _guardandoId;

  static const int _limite = CurriculoRepository.limitePorPagina;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final resultado = await _repo.listarProgramas(
      tipo: _tipo,
      activo: _activo,
      busqueda: _busquedaCtrl.text,
      limite: _limite,
      desplazamiento: _desplazamiento,
    );

    if (!mounted) return;

    resultado.when(
      success: (pagina) => setState(() {
        _cargando = false;
        _programas = pagina.programas;
        _total = pagina.total;
      }),
      failure: (fallo) => setState(() {
        _cargando = false;
        _error = fallo.message;
      }),
    );
  }

  void _buscar(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _desplazamiento = 0;
      _cargar();
    });
  }

  void _cambiarFiltro({TipoPrograma? tipo, bool? activo, bool limpiarTipo = false, bool limpiarActivo = false}) {
    setState(() {
      if (limpiarTipo) {
        _tipo = null;
      } else if (tipo != null) {
        _tipo = tipo;
      }
      if (limpiarActivo) {
        _activo = null;
      } else if (activo != null) {
        _activo = activo;
      }
      _desplazamiento = 0;
    });
    _cargar();
  }

  int get _desde => _total == 0 ? 0 : _desplazamiento + 1;
  int get _hasta =>
      _desplazamiento + _programas.length > _total
          ? _total
          : _desplazamiento + _programas.length;

  bool get _hayAnterior => _desplazamiento > 0;
  bool get _haySiguiente => _desplazamiento + _programas.length < _total;

  Future<void> _abrirAsistente() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AsistenteCurriculoScreen(repositorio: _repo),
      ),
    );

    if (creado != true || !mounted) return;
    _desplazamiento = 0;
    await _cargar();
  }

  Future<void> _editarPensum(ProgramaConTotales programa) async {
    final resultado = await _repo.detallePrograma(programa.id);
    if (!mounted) return;

    final detalle = resultado.valueOrNull;
    if (detalle == null) {
      mostrarAviso(
        context,
        resultado.errorOrNull?.message ?? 'No pudimos cargar el pensum.',
        error: true,
      );
      return;
    }

    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AsistenteCurriculoScreen(
          repositorio: _repo,
          detalleInicial: detalle,
        ),
      ),
    );

    if (guardado != true || !mounted) return;
    await _cargar();
  }

  Future<void> _alternarActivo(ProgramaConTotales programa) async {
    if (_guardandoId != null) return;

    final quiereActivar = !programa.activo;

    // Se comprueba aquí, con la razón a la vista, en vez de dejar que el
    // administrador pulse y reciba un 400 que ya se podía prever: publicar un
    // programa sin materias lo rechaza el trigger diferido del backend.
    if (quiereActivar && !puedeActivarse(totalMaterias: programa.totalMaterias)) {
      mostrarAviso(
        context,
        '«${programa.codigo}» no tiene materias. Añade el pensum antes de '
        'activarlo.',
        error: true,
      );
      return;
    }

    setState(() => _guardandoId = programa.id);

    final resultado = await _repo.actualizarPrograma(
      programa.id,
      CambiosPrograma(activo: quiereActivar),
    );

    if (mounted) setState(() => _guardandoId = null);
    if (!mounted) return;

    resultado.when(
      success: (actualizado) {
        setState(() {
          _programas = [
            for (final p in _programas)
              if (p.id == actualizado.id)
                ProgramaConTotales(
                  id: p.id,
                  codigo: actualizado.codigo,
                  nombre: actualizado.nombre,
                  tipo: actualizado.tipo,
                  requierePasantia: actualizado.requierePasantia,
                  activo: actualizado.activo,
                  totalMaterias: p.totalMaterias,
                  totalPeriodos: p.totalPeriodos,
                  creadoEn: p.creadoEn,
                  actualizadoEn: actualizado.actualizadoEn,
                )
              else
                p,
          ];
        });
        mostrarAviso(
          context,
          actualizado.activo
              ? '«${actualizado.codigo}» activado.'
              : '«${actualizado.codigo}» archivado.',
          exito: true,
        );
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  Future<void> _verDetalle(ProgramaConTotales programa) async {
    final resultado = await _repo.detallePrograma(programa.id);
    if (!mounted) return;

    final detalle = resultado.valueOrNull;
    if (detalle == null) {
      mostrarAviso(
        context,
        resultado.errorOrNull?.message ?? 'No pudimos cargar el programa.',
        error: true,
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _DialogoDetallePrograma(
        detalle: detalle,
        onEditarPensum: () {
          Navigator.of(context).pop();
          _editarPensum(programa);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Programas académicos',
          subtitulo: 'Carreras y cursos libres con su pensum. Ninguna acción '
              'borra: archivar es desactivar.',
          acciones: [
            FilledButton.icon(
              onPressed: _abrirAsistente,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nuevo programa'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // La ruta al pensum se dice explícitamente: el panel lo administra desde
        // la tarjeta de cada programa, y un icono con `tooltip` sólo se explica
        // al pasar el ratón. Sin esta línea, «dónde se agrega el pensum» queda a
        // la vista pero no a la lectura.
        const AvisoEnLinea(
          texto: 'Cada programa tiene su pensum: las materias y el período en que '
              'se dictan. Se administra desde la tarjeta del programa, con '
              '«Editar pensum» (el lápiz). Un programa sin materias no se puede '
              'publicar.',
        ),
        const SizedBox(height: 16),
        _filtros(),
        const SizedBox(height: 16),
        Expanded(
          child: EstadoPanel(
            cargando: _cargando,
            error: _error,
            onReintentar: _cargar,
            child: _lista(),
          ),
        ),
      ],
    );
  }

  Widget _filtros() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _busquedaCtrl,
            onChanged: _buscar,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Buscar por código o nombre',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<TipoPrograma?>(
            initialValue: _tipo,
            // `isExpanded` deja que el botón mida lo que le da el `SizedBox`.
            // Sin él, el desplegable se dimensiona por su ítem más ancho y
            // desborda el filtro en cuanto la etiqueta es larga.
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Todos')),
              DropdownMenuItem(
                value: TipoPrograma.carrera,
                child: Text('Carreras'),
              ),
              DropdownMenuItem(
                value: TipoPrograma.cursoLibre,
                child: Text('Cursos libres'),
              ),
            ],
            onChanged: (valor) {
              if (valor == null) {
                _cambiarFiltro(limpiarTipo: true);
              } else {
                _cambiarFiltro(tipo: valor);
              }
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<bool?>(
            initialValue: _activo,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Estado'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Todos')),
              DropdownMenuItem(value: true, child: Text('Publicados')),
              DropdownMenuItem(value: false, child: Text('En borrador')),
            ],
            onChanged: (valor) {
              if (valor == null) {
                _cambiarFiltro(limpiarActivo: true);
              } else {
                _cambiarFiltro(activo: valor);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _lista() {
    if (_programas.isEmpty) {
      // Desplazable y no un `Expanded` a secas: el estado vacío tiene su propia
      // altura y estirarlo hasta llenar la sección dejaría una tarjeta enorme
      // con el texto perdido arriba.
      return Center(
        child: SingleChildScrollView(
          child: PanelVacio(
            titulo: 'No hay programas que mostrar',
            mensaje: _total == 0 && _filtrosActivos
                ? 'Ningún programa coincide con los filtros aplicados. Prueba a '
                    'quitarlos.'
                : 'Todavía no se ha registrado ningún programa académico. Crea '
                    'el primero con el asistente: los datos del programa y su '
                    'pensum se guardan en una sola operación.',
            icono: Icons.menu_book_outlined,
            nota: 'Un programa sin materias no se puede activar.',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: _programas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _TarjetaPrograma(
              programa: _programas[i],
              guardando: _guardandoId == _programas[i].id,
              onVer: () => _verDetalle(_programas[i]),
              onEditarPensum: () => _editarPensum(_programas[i]),
              onAlternarActivo: () => _alternarActivo(_programas[i]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _paginacion(),
      ],
    );
  }

  bool get _filtrosActivos =>
      _tipo != null || _activo != null || _busquedaCtrl.text.trim().isNotEmpty;

  Widget _paginacion() {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          '$_desde–$_hasta de $_total',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: _hayAnterior
              ? () {
                  setState(() => _desplazamiento -= _limite);
                  _cargar();
                }
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: _haySiguiente
              ? () {
                  setState(() => _desplazamiento += _limite);
                  _cargar();
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Fila de programa
// -----------------------------------------------------------------------------

class _TarjetaPrograma extends StatelessWidget {
  const _TarjetaPrograma({
    required this.programa,
    required this.guardando,
    required this.onVer,
    required this.onEditarPensum,
    required this.onAlternarActivo,
  });

  final ProgramaConTotales programa;
  final bool guardando;
  final VoidCallback onVer;
  final VoidCallback onEditarPensum;
  final VoidCallback onAlternarActivo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Los dos tintes de esta tarjeta salen de la paleta y no del `ColorScheme`.
    // El azul primario servía en claro (8.29:1) pero **no en oscuro**: ahí el
    // primario es `#0059B3` y sobre un tinte de sí mismo da 1.99:1. Medido el
    // 2026-09-30.
    final paleta = PaletaInces.de(context);
    final parIcono = paleta.etiquetaDe(TonoEstado.info);
    final vacio = programa.estaVacio;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: parIcono.fondo,
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              ),
              child: Icon(
                programa.tipo == TipoPrograma.carrera
                    ? Icons.school_outlined
                    : Icons.auto_stories_outlined,
                size: 20,
                color: parIcono.texto,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          programa.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Etiqueta(
                        texto: programa.codigo,
                        tono: TonoEstado.neutro,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Etiqueta(
                        texto: programa.tipo.etiqueta,
                        tono: TonoEstado.info,
                      ),
                      _Etiqueta(
                        texto: programa.activo ? 'Publicado' : 'En borrador',
                        tono: programa.activo
                            ? TonoEstado.exito
                            : TonoEstado.neutro,
                      ),
                      if (programa.requierePasantia)
                        const _Etiqueta(
                          texto: 'Con pasantía',
                          tono: TonoEstado.info,
                        ),
                      Text(
                        '${programa.totalMaterias} '
                        '${programa.totalMaterias == 1 ? 'materia' : 'materias'}'
                        ' · ${programa.totalPeriodos} '
                        '${programa.totalPeriodos == 1 ? 'período' : 'períodos'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  if (vacio) ...[
                    const SizedBox(height: 10),
                    const AvisoEnLinea(
                      tono: TonoAviso.advertencia,
                      icono: Icons.warning_amber_outlined,
                      texto: 'Sin materias: no se puede activar hasta que '
                          'tenga pensum.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (guardando)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Tooltip(
                message: vacio && !programa.activo
                    ? 'Sin materias: añade el pensum primero'
                    : programa.activo
                        ? 'Archivar'
                        : 'Publicar',
                child: Switch(
                  value: programa.activo,
                  onChanged: (_) => onAlternarActivo(),
                ),
              ),
            IconButton(
              tooltip: 'Ver pensum',
              onPressed: onVer,
              icon: const Icon(Icons.visibility_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Editar pensum',
              onPressed: onEditarPensum,
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta de estado de un programa: una palabra sobre un tinte.
///
/// Recibe un **tono**, no un color. Antes recibía un `Color` y por ahí entraban
/// tanto los acentos de relleno de `IncesTheme` como el `colorScheme.primary` del
/// tema: el ámbar daba 1.81:1 sobre su propio tinte en claro y el primario de
/// oscuro, 1.99:1. Con un tono el color no se puede elegir mal — lo resuelve
/// `PaletaInces` con el brillo montado, y el 12 % del tinte se decide en un solo
/// sitio. Medido el 2026-09-30.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.tono});

  final String texto;
  final TonoEstado tono;

  @override
  Widget build(BuildContext context) {
    final par = PaletaInces.de(context).etiquetaDe(tono);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: par.fondo,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texto,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: par.texto,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Detalle del programa
// -----------------------------------------------------------------------------

class _DialogoDetallePrograma extends StatelessWidget {
  const _DialogoDetallePrograma({
    required this.detalle,
    required this.onEditarPensum,
  });

  final DetallePrograma detalle;
  final VoidCallback onEditarPensum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              detalle.programa.nombre,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _Etiqueta(
            texto: detalle.programa.codigo,
            tono: TonoEstado.neutro,
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    '${detalle.totalMaterias} materias',
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(
                    '${detalle.totalPeriodos} períodos',
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(
                    '${detalle.totalHoras} horas',
                    style: theme.textTheme.labelSmall,
                  ),
                  Text(
                    'Creado: ${formatearFechaHora(detalle.programa.creadoEn)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // `editable` viene calculado del backend y es la Regla 2 hecha
              // dato: con secciones activas del período vigente, el pensum no se
              // toca. Se explica aquí para que el administrador no crea que el
              // botón está roto.
              if (!detalle.editable) ...[
                AvisoEnLinea(
                  tono: TonoAviso.advertencia,
                  icono: Icons.lock_outline,
                  texto: 'Pensum bloqueado: hay ${detalle.seccionesActivas} '
                      'sección(es) activa(s) del período vigente cursando este '
                      'programa. Añadir materias sí está permitido; quitarlas o '
                      'reordenarlas, no.',
                ),
                const SizedBox(height: 16),
              ],

              if (detalle.pensum.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'El pensum está vacío.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final grupo in detalle.pensum) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Período ${grupo.periodo}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final materia in grupo.materias)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              materia.nombre,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            '${materia.codigo} · ${materia.horasAcademicas} h',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        OutlinedButton.icon(
          onPressed: onEditarPensum,
          icon: const Icon(Icons.edit_outlined, size: 17),
          label: const Text('Editar pensum'),
        ),
      ],
    );
  }
}
