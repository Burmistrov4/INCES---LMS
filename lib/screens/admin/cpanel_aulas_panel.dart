import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/errors/app_exception.dart';
import '../../core/gateways/cuadrante_gateway.dart';
import '../../core/reglas_cuadrante.dart';
import '../../models/cuadrante.dart';
import '../../repositories/cuadrante_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Panel del catálogo de espacios del centro (Módulo 3).
///
/// Un **único** concepto de espacio con dos formas (R-18): un aula o taller
/// tiene capacidad y puede ser taller; una zona de custodia —un pasillo— tiene
/// capacidad 0. No hay una tabla `zones` aparte **a propósito**: la guardia
/// anti-colisión vigila un solo sitio, y con dos tablas habría que duplicar el
/// chequeo y mantener las dos copias de acuerdo.
///
/// **No hay semilla de aulas, y es deliberado.** Sembrar «Taller de Soldadura
/// Cabina A» habría sido inventar el inventario del centro. Hasta que el
/// administrador lo cargue la lista sale vacía, y el cuadrante **no se puede
/// usar**, porque una clase sin aula no existe: por eso el vacío lo dice en vez
/// de dejar un desplegable mudo en la otra pantalla.
///
/// **Ninguna acción borra.** Archivar es `activa: false`, y las tablas del
/// cuadrante están en `on delete restrict` para que borrar un aula en uso no sea
/// posible ni por accidente.
class CpanelAulasPanel extends StatefulWidget {
  const CpanelAulasPanel({super.key, this.repositorio});

  final CuadranteRepository? repositorio;

  @override
  State<CpanelAulasPanel> createState() => _CpanelAulasPanelState();
}

class _CpanelAulasPanelState extends State<CpanelAulasPanel> {
  late final CuadranteRepository _repo =
      widget.repositorio ?? CuadranteRepository();

  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;

  TipoAula? _tipo;
  bool? _activa;
  int _desplazamiento = 0;

  List<Aula> _aulas = const [];
  int _total = 0;
  bool _cargando = true;
  String? _error;

  /// Identificador del espacio cuya escritura está en curso. Se bloquea sólo esa
  /// fila: guardar uno no debe impedir mirar los demás.
  String? _guardandoId;

  static const int _limite = CuadranteRepository.limitePorPagina;

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

    final resultado = await _repo.listarAulas(
      tipo: _tipo,
      activa: _activa,
      busqueda: _busquedaCtrl.text,
      limite: _limite,
      desplazamiento: _desplazamiento,
    );

    // El estado de carga se libera antes del `return` por desmontaje: al revés,
    // un desmontaje durante la petición dejaría el indicador girando para
    // siempre en la siguiente visita a esta sección.
    if (!mounted) return;

    resultado.when(
      success: (pagina) => setState(() {
        _cargando = false;
        _aulas = pagina.aulas;
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

  void _filtrarPorTipo(TipoAula? tipo) {
    setState(() {
      _tipo = tipo;
      _desplazamiento = 0;
    });
    _cargar();
  }

  void _filtrarPorEstado(bool? activa) {
    setState(() {
      _activa = activa;
      _desplazamiento = 0;
    });
    _cargar();
  }

  int get _desde => _total == 0 ? 0 : _desplazamiento + 1;
  int get _hasta => _desplazamiento + _aulas.length > _total
      ? _total
      : _desplazamiento + _aulas.length;

  bool get _hayAnterior => _desplazamiento > 0;
  bool get _haySiguiente => _desplazamiento + _aulas.length < _total;

  Future<void> _abrirFormulario({Aula? existente}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoEspacio(repo: _repo, existente: existente),
    );

    if (guardado != true || !mounted) return;
    if (existente == null) _desplazamiento = 0;
    await _cargar();
  }

  Future<void> _alternarActiva(Aula aula) async {
    // Guarda de reentrada: dos pulsaciones rápidas lanzarían dos escrituras y la
    // segunda decidiría el estado final por azar.
    if (_guardandoId != null) return;

    setState(() => _guardandoId = aula.id);

    final resultado = await _repo.actualizarAula(
      aula.id,
      CambiosAula(activa: !aula.activa),
    );

    if (!mounted) return;
    setState(() => _guardandoId = null);

    resultado.when(
      success: (actualizada) {
        mostrarAviso(
          context,
          actualizada.activa
              ? '«${actualizada.nombre}» vuelve a estar disponible.'
              : '«${actualizada.nombre}» quedó archivado. No aparecerá en el '
                  'cuadrante.',
          exito: true,
        );
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecera(),
        const SizedBox(height: 12),
        _filtros(),
        const SizedBox(height: 16),
        // `Expanded` y no un `ListView` suelto: `ContenidoSeccion` entrega una
        // altura **acotada**, así que aquí se reparte en lugar de crecer. Es el
        // contrato de layout del cPanel, y montar el panel en un `Scaffold`
        // pelado lo escondería.
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

  Widget _cabecera() {
    return TituloSeccion(
      'Espacios del centro',
      subtitulo: 'Aulas, talleres y zonas donde se dicta clase o se hace '
          'guardia. Sin espacios registrados el cuadrante no se puede usar.',
      acciones: [
        FilledButton.icon(
          onPressed: () => _abrirFormulario(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Registrar espacio'),
        ),
      ],
    );
  }

  Widget _filtros() {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _busquedaCtrl,
            onChanged: _buscar,
            // El campo NO se deshabilita mientras carga: un campo que se
            // congela a mitad de tecleo es indistinguible de una app colgada.
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
        ),
        for (final opcion in _OpcionTipo.values)
          ChoiceChip(
            label: Text(opcion.etiqueta),
            selected: opcion.tipo == _tipo,
            onSelected: (_) => _filtrarPorTipo(opcion.tipo),
          ),
        const SizedBox(width: 4),
        ChoiceChip(
          label: const Text('Activos'),
          selected: _activa == true,
          onSelected: (elegido) => _filtrarPorEstado(elegido ? true : null),
        ),
        ChoiceChip(
          label: const Text('Archivados'),
          selected: _activa == false,
          onSelected: (elegido) => _filtrarPorEstado(elegido ? false : null),
        ),
        if (_total > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '$_desde a $_hasta de $_total',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }

  Widget _lista() {
    if (_aulas.isEmpty) {
      final filtrando =
          _tipo != null || _activa != null || _busquedaCtrl.text.trim().isNotEmpty;

      return PanelVacio(
        titulo: filtrando
            ? 'Ningún espacio coincide con el filtro'
            : 'Todavía no hay espacios registrados',
        mensaje: filtrando
            ? 'Prueba con otro tipo o quita el filtro de estado.'
            : 'Registra las aulas, los talleres y las zonas del centro. Hasta '
                'entonces no se puede armar el cuadrante: una clase necesita un '
                'sitio donde dictarse.',
        icono: filtrando ? Icons.filter_alt_off_outlined : Icons.meeting_room_outlined,
        // El centro no tiene un inventario cargado, y decirlo evita que alguien
        // crea que la lista está rota o que faltan permisos.
        nota: filtrando
            ? null
            : 'El sistema no trae espacios de ejemplo a propósito: inventar el '
                'inventario del centro sería peor que dejarlo vacío.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _aulas.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, indice) => _FilaEspacio(
              aula: _aulas[indice],
              guardando: _guardandoId == _aulas[indice].id,
              onEditar: () => _abrirFormulario(existente: _aulas[indice]),
              onAlternar: () => _alternarActiva(_aulas[indice]),
            ),
          ),
        ),
        // El pie sólo aparece cuando hay más de una página: con nueve espacios
        // —el catálogo entero del centro— unos botones muertos serían ruido.
        if (_hayAnterior || _haySiguiente) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _hayAnterior
                    ? () {
                        setState(() => _desplazamiento -= _limite);
                        _cargar();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                label: const Text('Anteriores'),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: _haySiguiente
                    ? () {
                        setState(() => _desplazamiento += _limite);
                        _cargar();
                      }
                    : null,
                // El icono va a la derecha del texto, como el gesto que
                // representa: «seguir hacia delante».
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: const Text('Siguientes'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Las tres formas de espacio, más «todos».
enum _OpcionTipo {
  todos(null, 'Todos'),
  talleres(TipoAula.taller, 'Talleres'),
  aulas(TipoAula.aula, 'Aulas'),
  zonas(TipoAula.zona, 'Zonas');

  const _OpcionTipo(this.tipo, this.etiqueta);

  final TipoAula? tipo;
  final String etiqueta;
}

/// Una fila del catálogo.
class _FilaEspacio extends StatelessWidget {
  const _FilaEspacio({
    required this.aula,
    required this.guardando,
    required this.onEditar,
    required this.onAlternar,
  });

  final Aula aula;
  final bool guardando;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final archivada = !aula.activa;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary
                    .withValues(alpha: archivada ? 0.05 : 0.12),
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              ),
              child: Icon(
                _iconoDe(aula.tipo),
                size: 19,
                color: archivada
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aula.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: archivada
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // `Wrap` y no `Row`: el tipo, el cupo y la insignia de
                  // archivado no caben en una línea en móvil.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Etiqueta(texto: aula.tipo.etiqueta),
                      _Etiqueta(
                        texto: aula.capacidad == 0
                            // Cero no es «desconocido»: es «sin cupo declarado»,
                            // y decir «0 puestos» haría pensar en un aula vacía.
                            ? 'Sin cupo declarado'
                            : '${aula.capacidad} puestos',
                      ),
                      if (archivada) const _Etiqueta(texto: 'Archivado'),
                    ],
                  ),
                ],
              ),
            ),
            if (guardando)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                tooltip: 'Editar',
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: archivada ? 'Reactivar' : 'Archivar',
                onPressed: onAlternar,
                icon: Icon(
                  archivada ? Icons.restore_rounded : Icons.archive_outlined,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconoDe(TipoAula tipo) => switch (tipo) {
        TipoAula.taller => Icons.handyman_outlined,
        TipoAula.aula => Icons.meeting_room_outlined,
        TipoAula.zona => Icons.route_outlined,
      };
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texto,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Formulario de alta y edición de un espacio.
///
/// Sirve para las dos cosas en vez de tener dos diálogos casi iguales: dos
/// copias del «mismo» formulario se desvían en cuanto alguien ajusta una, y ya
/// pasó con los azules del login.
class _DialogoEspacio extends StatefulWidget {
  const _DialogoEspacio({required this.repo, this.existente});

  final CuadranteRepository repo;
  final Aula? existente;

  @override
  State<_DialogoEspacio> createState() => _DialogoEspacioState();
}

class _DialogoEspacioState extends State<_DialogoEspacio> {
  late final TextEditingController _nombreCtrl =
      TextEditingController(text: widget.existente?.nombre ?? '');
  late final TextEditingController _capacidadCtrl = TextEditingController(
    text: (widget.existente?.capacidad ?? 0) == 0
        ? ''
        : '${widget.existente!.capacidad}',
  );

  late bool _esTaller = widget.existente?.esTaller ?? false;

  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.existente != null;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _capacidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final capacidad = _capacidadDe(_capacidadCtrl.text);
    if (capacidad == null) {
      setState(() => _error = 'La capacidad tiene que ser un número entero.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = _esEdicion
        ? await widget.repo.actualizarAula(
            widget.existente!.id,
            CambiosAula(
              nombre: _nombreCtrl.text,
              capacidad: capacidad,
              esTaller: _esTaller,
            ),
          )
        : await widget.repo.crearAula(
            EntradaCrearAula(
              nombre: _nombreCtrl.text,
              capacidad: capacidad,
              esTaller: _esTaller,
            ),
          );

    if (!mounted) return;
    setState(() => _guardando = false);

    resultado.when(
      success: (_) => Navigator.of(context).pop(true),
      failure: (fallo) => setState(() => _error = _mensajeDe(fallo)),
    );
  }

  /// Un texto vacío es capacidad 0 —una zona sin cupo—, no un error.
  static int? _capacidadDe(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return 0;
    return int.tryParse(limpio);
  }

  /// El mensaje que se enseña dentro del formulario.
  ///
  /// El nombre repetido merece uno propio: es el `unique` de la tabla, y el
  /// mensaje genérico del backend no dice **cuál** de los dos espacios está
  /// repetido ni que basta con cambiarle el nombre.
  static String _mensajeDe(AppException fallo) {
    if (fallo.code == codigoRegistroDuplicado) {
      return 'Ya existe un espacio con ese nombre. Dos espacios iguales harían '
          'imposible saber a cuál se refiere el cuadrante.';
    }
    return fallo.message;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar espacio' : 'Registrar espacio'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nombreCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Taller de Soldadura Cabina A',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _capacidadCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Capacidad',
                  hintText: '12',
                  helperText: 'Déjalo vacío o en 0 para una zona sin cupo '
                      'declarado, como un pasillo.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _esTaller,
                onChanged: (valor) => setState(() => _esTaller = valor),
                title: const Text('Es un taller'),
                subtitle: const Text(
                  'Los talleres se filtran aparte porque su cupo no los define: '
                  'lo que los define es su uso.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AvisoEnLinea(
                  texto: _error!,
                  tono: TonoAviso.peligro,
                  icono: Icons.error_outline,
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
          // Se bloquea el BOTÓN, no el campo: deshabilitar el campo mientras
          // guarda congela el texto a mitad de tecleo.
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
