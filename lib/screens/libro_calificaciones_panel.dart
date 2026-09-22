import 'package:flutter/material.dart';

import '../core/gateways/aula_gateway.dart';
import '../core/result.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';

/// Libro de calificaciones del docente (Centro de Mando, M6).
///
/// Una fila por estudiante matriculado en la tarea. Es la **única** lectura que
/// trae [LibroEntrega.notaBorrador] —por eso va por la RPC `security definer` y no
/// por una lectura directa—, y por eso el tipo es [LibroEntrega] y no [Entrega].
///
/// La rejilla reusa el patrón de `cuadrante_grid.dart`: `SingleChildScrollView`
/// horizontal dentro de uno vertical, con un `Table` de bordes. El libro puede ser
/// ancho (muchas columnas) y largo (muchos estudiantes), así que el doble scroll
/// evita cortar filas o forzar un ancho móvil incómodo en escritorio.
///
/// Cada fila ofrece **calificar** (escribe la nota borrador) y **devolver**
/// (copia el borrador a la nota asignada y cierra el ciclo: es cuando el alumno
/// por fin ve su nota). Ambas acciones recargan el libro para reflejar el cambio.
class LibroCalificacionesPanel extends StatefulWidget {
  const LibroCalificacionesPanel({
    super.key,
    required this.tareaId,
    required this.tareaTitulo,
    required this.gateway,
    this.onCambio,
  });

  final String tareaId;
  final String tareaTitulo;
  final AulaGateway gateway;

  /// Se invoca tras calificar o devolver, para que quien abrió el panel pueda
  /// reflejar el cambio en el resto del aula.
  final VoidCallback? onCambio;

  @override
  State<LibroCalificacionesPanel> createState() =>
      _LibroCalificacionesPanelState();
}

class _LibroCalificacionesPanelState extends State<LibroCalificacionesPanel> {
  bool _cargando = true;
  String? _error;
  List<LibroEntrega> _filas = const [];

  /// Ids de fila con una acción en curso. Conjunto y no bandera: dos filas pueden
  /// estar ocupadas a la vez y cada botón refleja sólo la suya.
  final Set<String> _ocupadas = <String>{};

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

    final resultado = await Result.guard(
      () => widget.gateway.libroDeCalificaciones(widget.tareaId),
    );
    if (!mounted) return;

    setState(() {
      _cargando = false;
      resultado.when(
        success: (lista) => _filas = lista,
        failure: (fallo) => _error = fallo.message,
      );
    });
  }

  Future<void> _calificar(LibroEntrega fila) async {
    final nota = await _pedirNota(fila);
    if (nota == null || !mounted) return;

    if (_ocupadas.contains(fila.estudianteId)) return;
    setState(() => _ocupadas.add(fila.estudianteId));

    final resultado = await Result.guard(
      () => widget.gateway.calificar(fila.estudianteId, nota),
    );
    if (!mounted) {
      _ocupadas.remove(fila.estudianteId);
      return;
    }
    setState(() => _ocupadas.remove(fila.estudianteId));

    resultado.when(
      success: (_) {
        widget.onCambio?.call();
        _cargar();
      },
      failure: (fallo) =>
          mostrarAviso(context, fallo.message, error: true),
    );
  }

  Future<void> _devolver(LibroEntrega fila) async {
    if (_ocupadas.contains(fila.estudianteId)) return;
    setState(() => _ocupadas.add(fila.estudianteId));

    final resultado = await Result.guard(
      () => widget.gateway.devolver(fila.estudianteId),
    );
    if (!mounted) {
      _ocupadas.remove(fila.estudianteId);
      return;
    }
    setState(() => _ocupadas.remove(fila.estudianteId));

    resultado.when(
      success: (_) {
        widget.onCambio?.call();
        mostrarAviso(context, 'Entrega devuelta al estudiante.', exito: true);
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  /// Diálogo con un único campo de nota (0–20). Devuelve `null` si se cancela.
  Future<double?> _pedirNota(LibroEntrega fila) async {
    final control = TextEditingController(
      text: fila.notaBorrador?.toStringAsFixed(1) ?? '',
    );
    final forma = GlobalKey<FormState>();

    final resultado = await showDialog<double>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Calificar entrega'),
        content: Form(
          key: forma,
          child: TextFormField(
            controller: control,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nota (0–20)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (valor) {
              final texto = valor?.trim() ?? '';
              if (texto.isEmpty) return 'Escribe una nota.';
              final numero = double.tryParse(texto);
              if (numero == null) return 'Escribe un número.';
              if (numero < 0 || numero > 20) return 'La nota va de 0 a 20.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (forma.currentState!.validate()) {
                Navigator.of(dialogo)
                    .pop(double.parse(control.text.trim()));
              }
            },
            child: const Text('Guardar nota'),
          ),
        ],
      ),
    );

    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold propio: el panel se abre como ruta aparte (lo empuja el detalle
    // de la tarea y el botón «Calificar»), y `MaterialPageRoute` no inyecta
    // Material. Sin esto, el `IconButton` de actualizar y los de calificar/
    // devolver revientan con «No Material widget found».
    return Scaffold(
      appBar: AppBar(title: const Text('Calificaciones')),
      body: ContenidoSeccion(
        migas: const ['Inicio', 'Académico', 'Aula Virtual', 'Calificaciones'],
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TituloSeccion(
            'Libro de calificaciones',
            subtitulo: widget.tareaTitulo,
            acciones: [
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _cargando ? null : _cargar,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cargando)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            AvisoEnLinea(
              tono: TonoAviso.peligro,
              icono: Icons.cloud_off_outlined,
              texto: _error!,
            )
          else if (_filas.isEmpty)
            const PanelVacio(
              titulo: 'Todavía no hay entregas',
              mensaje: 'Publica la tarea para que se creen los lugares de cada '
                  'estudiante.',
              icono: Icons.grading_outlined,
            )
          else
            Expanded(child: _tabla()),
        ],
      ),
    ),
    );
  }

  Widget _tabla() {
    final theme = Theme.of(context);
    final borde = theme.colorScheme.outline.withValues(alpha: 0.25);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: borde, width: 1),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              children: [
                _celdaCabecera('Estudiante'),
                _celdaCabecera('Estado'),
                _celdaCabecera('Borrador'),
                _celdaCabecera('Asignada'),
                _celdaCabecera('Devuelta'),
                _celdaCabecera('Acción'),
              ],
            ),
            for (final fila in _filas) _fila(fila, theme, borde),
          ],
        ),
      ),
    );
  }

  TableRow _fila(LibroEntrega fila, ThemeData theme, Color borde) {
    final ocupada = _ocupadas.contains(fila.estudianteId);

    return TableRow(
      children: [
        _celda(fila.estudianteId),
        _celda(_etiquetaEstado(fila.estado)),
        _celda(fila.notaBorrador == null
            ? '—'
            : _formatoNota(fila.notaBorrador!)),
        _celda(fila.notaAsignada == null
            ? '—'
            : _formatoNota(fila.notaAsignada!)),
        _celda(fila.devueltaEn == null ? '—' : 'Sí'),
        _celdaAccion(
          ocupada,
          fila,
        ),
      ],
    );
  }

  Widget _celdaCabecera(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          texto,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _celda(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(texto),
      );

  Widget _celdaAccion(bool ocupada, LibroEntrega fila) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 6,
          children: [
            FilledButton.icon(
              // La nota borrador se puede escribir sobre cualquier entrega ya
              // entregada; la RPC lo impide si no es así y el error sube.
              onPressed: ocupada ? null : () => _calificar(fila),
              icon: ocupada
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Calificar'),
            ),
            OutlinedButton.icon(
              onPressed: ocupada ? null : () => _devolver(fila),
              icon: const Icon(Icons.assignment_returned_outlined, size: 16),
              label: const Text('Devolver'),
            ),
          ],
        ),
      );

  String _etiquetaEstado(EstadoEntrega estado) => switch (estado) {
        EstadoEntrega.asignada => 'Pendiente',
        EstadoEntrega.entregada => 'Entregada',
        EstadoEntrega.devuelta => 'Devuelta',
        EstadoEntrega.reclamada => 'Reclamada',
      };

  /// Nota en la escala 0–20, con coma decimal, igual que el resto del Aula
  /// (`_formatoNota` en el dashboard). Un `16.0` de `toStringAsFixed` sería un
  /// punto, y el resto de la app pinta coma: mantenerlo evita dos formatos.
  String _formatoNota(double nota) => nota
      .toStringAsFixed(1)
      .replaceAll('.', ',');
}
