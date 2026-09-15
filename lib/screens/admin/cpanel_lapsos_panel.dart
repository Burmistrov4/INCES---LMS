import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/errors/app_exception.dart';
import '../../core/gateways/cuadrante_gateway.dart';
import '../../core/reglas_cuadrante.dart';
import '../../models/cuadrante.dart';
import '../../repositories/cuadrante_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Panel del catálogo de lapsos académicos (Módulo 3).
///
/// La pantalla existe para hacer visible una distinción que en el lenguaje
/// diario se pierde (R-19), y que es la causa de la mitad de las confusiones con
/// el período:
///
/// | Concepto | Qué significa |
/// | --- | --- |
/// | **Abierto** (`is_active`) | «se puede planificar en él» |
/// | **Vigente** (`periodo_activo`) | «es el que el sistema considera en curso» |
///
/// Puede haber varios abiertos y **sólo uno vigente**, y ése es el caso real: al
/// cerrar un lapso se prepara el siguiente mientras el vigente sigue dictándose.
/// Un solo campo no podría expresarlo, y por eso son dos columnas y dos insignias
/// distintas en la lista.
///
/// **Las fechas se enseñan como «sin fechas cargadas» cuando faltan**, nunca como
/// un rango inventado: el centro no las ha cargado y fabricarlas sería inventar
/// un dato institucional (R-17).
class CpanelLapsosPanel extends StatefulWidget {
  const CpanelLapsosPanel({super.key, this.repositorio});

  final CuadranteRepository? repositorio;

  @override
  State<CpanelLapsosPanel> createState() => _CpanelLapsosPanelState();
}

class _CpanelLapsosPanelState extends State<CpanelLapsosPanel> {
  late final CuadranteRepository _repo =
      widget.repositorio ?? CuadranteRepository();

  List<Periodo> _periodos = const [];
  bool _cargando = true;
  String? _error;

  /// Identificador del lapso cuya escritura está en curso.
  String? _guardandoId;

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

    final resultado = await _repo.listarPeriodos();

    if (!mounted) return;

    resultado.when(
      success: (periodos) => setState(() {
        _cargando = false;
        // El vigente primero y luego por código descendente: el lapso en curso
        // es lo que se viene a mirar, y el más reciente es el que se prepara.
        _periodos = [...periodos]..sort((a, b) {
            if (a.vigente != b.vigente) return a.vigente ? -1 : 1;
            return b.codigo.compareTo(a.codigo);
          });
      }),
      failure: (fallo) => setState(() {
        _cargando = false;
        _error = fallo.message;
      }),
    );
  }

  Future<void> _abrirFormulario({Periodo? existente}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoLapso(repo: _repo, existente: existente),
    );

    if (guardado != true || !mounted) return;
    await _cargar();
  }

  Future<void> _marcarVigente(Periodo periodo) async {
    if (_guardandoId != null || periodo.vigente) return;

    setState(() => _guardandoId = periodo.id);

    final resultado = await _repo.marcarVigente(periodo.id);

    if (!mounted) return;
    setState(() => _guardandoId = null);

    resultado.when(
      success: (vigente) {
        mostrarAviso(
          context,
          '«${vigente.codigo}» es el lapso vigente. El cuadrante y los horarios '
          'lo toman por defecto desde ahora.',
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
        TituloSeccion(
          'Lapsos académicos',
          subtitulo: 'Puede haber varios abiertos y sólo uno vigente: el '
              'vigente es el que el cuadrante toma por defecto.',
          acciones: [
            FilledButton.icon(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Registrar lapso'),
            ),
          ],
        ),
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

  Widget _lista() {
    if (_periodos.isEmpty) {
      return const PanelVacio(
        titulo: 'Todavía no hay lapsos registrados',
        mensaje: 'Registra el lapso en curso —y los que vienen— para poder '
            'armar el cuadrante. Un cuadrante pertenece siempre a un lapso.',
        icono: Icons.event_note_outlined,
        nota: 'El lapso vigente vive en los parámetros del sistema '
            '(`periodo_activo`), y el sistema rechaza un valor que no '
            'corresponda a un lapso registrado aquí.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _periodos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, indice) => _FilaLapso(
        periodo: _periodos[indice],
        guardando: _guardandoId == _periodos[indice].id,
        onEditar: () => _abrirFormulario(existente: _periodos[indice]),
        onMarcarVigente: () => _marcarVigente(_periodos[indice]),
      ),
    );
  }
}

/// Una fila del catálogo de lapsos.
class _FilaLapso extends StatelessWidget {
  const _FilaLapso({
    required this.periodo,
    required this.guardando,
    required this.onEditar,
    required this.onMarcarVigente,
  });

  final Periodo periodo;
  final bool guardando;
  final VoidCallback onEditar;
  final VoidCallback onMarcarVigente;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cerrado = !periodo.activo;

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
                    .withValues(alpha: periodo.vigente ? 0.14 : 0.07),
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              ),
              child: Icon(
                periodo.vigente
                    ? Icons.play_circle_outline
                    : Icons.event_outlined,
                size: 19,
                color: periodo.vigente
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    periodo.etiqueta,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cerrado
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Etiqueta(texto: 'Código ${periodo.codigo}'),
                      // Las dos insignias son distintas a propósito: son dos
                      // cosas distintas, y llamar «activo» a las dos es lo que
                      // hacía imposible saber qué lapso se está dictando.
                      if (periodo.vigente)
                        _Etiqueta(texto: 'Vigente', destacada: true),
                      _Etiqueta(texto: periodo.activo ? 'Abierto' : 'Cerrado'),
                      _Etiqueta(texto: _rangoDeFechas(periodo)),
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
              if (!periodo.vigente)
                TextButton.icon(
                  onPressed: onMarcarVigente,
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: const Text('Hacer vigente'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                tooltip: 'Editar',
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// El rango de fechas, o el aviso de que no las hay.
  ///
  /// Nunca un rango inventado: el centro no ha cargado las fechas del lapso en
  /// curso, y rellenarlas con algo plausible sería fabricar un dato (R-17).
  static String _rangoDeFechas(Periodo periodo) {
    final inicio = periodo.fechaInicio;
    final fin = periodo.fechaFin;

    if (inicio == null && fin == null) return 'Sin fechas cargadas';
    if (inicio != null && fin != null) return '$inicio → $fin';
    if (inicio != null) return 'Desde $inicio';
    return 'Hasta $fin';
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, this.destacada = false});

  final String texto;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: destacada
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : null,
        border: Border.all(
          color: destacada ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texto,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: destacada
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Formulario de alta y edición de un lapso.
class _DialogoLapso extends StatefulWidget {
  const _DialogoLapso({required this.repo, this.existente});

  final CuadranteRepository repo;
  final Periodo? existente;

  @override
  State<_DialogoLapso> createState() => _DialogoLapsoState();
}

class _DialogoLapsoState extends State<_DialogoLapso> {
  late final TextEditingController _codigoCtrl =
      TextEditingController(text: widget.existente?.codigo ?? '');
  late final TextEditingController _nombreCtrl =
      TextEditingController(text: widget.existente?.nombre ?? '');

  late String? _inicio = widget.existente?.fechaInicio;
  late String? _fin = widget.existente?.fechaFin;

  late bool _activo = widget.existente?.activo ?? true;

  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.existente != null;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esInicio}) async {
    final actual = esInicio ? _inicio : _fin;
    final inicial = (actual != null && esFechaISO(actual))
        ? DateTime.parse(actual)
        : DateTime.now();

    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: esInicio ? 'Fecha de inicio' : 'Fecha de fin',
    );

    if (elegida == null || !mounted) return;

    // Se guarda como `YYYY-MM-DD` y no como ISO completo: un timestamp desplaza
    // un día por zona horaria al ir y volver.
    final texto = '${elegida.year.toString().padLeft(4, '0')}-'
        '${elegida.month.toString().padLeft(2, '0')}-'
        '${elegida.day.toString().padLeft(2, '0')}';

    setState(() {
      if (esInicio) {
        _inicio = texto;
      } else {
        _fin = texto;
      }
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = _esEdicion
        ? await widget.repo.actualizarPeriodo(
            widget.existente!.id,
            CambiosPeriodo(
              nombre: _nombreCtrl.text,
              fechaInicio: _inicio,
              fechaFin: _fin,
              activo: _activo,
              // Si se quitaron las dos fechas, hay que mandarlas nulas de forma
              // explícita: «ausente» significa «no lo toques».
              borrarFechas: _inicio == null && _fin == null,
            ),
          )
        : await widget.repo.crearPeriodo(
            EntradaCrearPeriodo(
              codigo: _codigoCtrl.text,
              nombre: _nombreCtrl.text,
              fechaInicio: _inicio,
              fechaFin: _fin,
            ),
          );

    if (!mounted) return;
    setState(() => _guardando = false);

    resultado.when(
      success: (_) => Navigator.of(context).pop(true),
      failure: (fallo) => setState(() => _error = _mensajeDe(fallo)),
    );
  }

  /// El mensaje que se enseña dentro del formulario.
  ///
  /// El código repetido merece uno propio: es la identidad del lapso y el
  /// mensaje genérico no dice cuál está repetido.
  static String _mensajeDe(AppException fallo) {
    if (fallo.code == codigoRegistroDuplicado) {
      return 'Ya existe un lapso con ese código. Es la identidad del lapso: '
          'cambiar el de uno rompería cualquier documento que lo cite.';
    }
    return fallo.message;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar lapso' : 'Registrar lapso'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codigoCtrl,
                autofocus: true,
                // El código es la identidad del lapso y ya está citado en
                // documentos: se enseña pero no se edita.
                enabled: !_esEdicion,
                decoration: const InputDecoration(
                  labelText: 'Código',
                  hintText: '2026-1',
                  helperText: 'Letras, dígitos y guiones, hasta 10 caracteres.',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Lapso 2026-1',
                  helperText: 'Opcional. Si falta, se muestra el código.',
                ),
              ),
              const SizedBox(height: 16),
              _campoDeFecha(
                etiqueta: 'Fecha de inicio',
                valor: _inicio,
                onElegir: () => _elegirFecha(esInicio: true),
                onLimpiar: () => setState(() => _inicio = null),
              ),
              const SizedBox(height: 10),
              _campoDeFecha(
                etiqueta: 'Fecha de fin',
                valor: _fin,
                onElegir: () => _elegirFecha(esInicio: false),
                onLimpiar: () => setState(() => _fin = null),
              ),
              const SizedBox(height: 4),
              Text(
                'Las fechas son opcionales. Si el centro todavía no las ha '
                'confirmado, déjalas vacías: es preferible a un rango '
                'inventado.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (_esEdicion) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _activo,
                  onChanged: (valor) => setState(() => _activo = valor),
                  title: const Text('Lapso abierto'),
                  subtitle: const Text(
                    'Abierto significa que se puede planificar en él. No es lo '
                    'mismo que vigente: eso se cambia con «Hacer vigente».',
                  ),
                ),
              ],
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
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }

  Widget _campoDeFecha({
    required String etiqueta,
    required String? valor,
    required VoidCallback onElegir,
    required VoidCallback onLimpiar,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _guardando ? null : onElegir,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(valor ?? 'Sin fecha cargada'),
            ),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              foregroundColor:
                  valor == null ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
        ),
        if (valor != null)
          IconButton(
            tooltip: 'Quitar $etiqueta',
            onPressed: _guardando ? null : onLimpiar,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
