import 'package:flutter/material.dart';

import '../core/gateways/aula_gateway.dart';
import '../core/result.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';

/// Creación de trabajo de clase (Centro de Mando del docente, M6).
///
/// Un formulario que distingue **visual y lógicamente** entre [TipoTarea.tarea] y
/// [TipoTarea.material]:
///
///  * **TAREA** se califica: muestra los campos de puntos y fecha límite, y los
///    envía. Si el docente los deja en blanco, el backend aplica el 20 de negocio
///    (`coalesce(p_puntos_maximos, 20)` en la RPC).
///  * **MATERIAL** es de lectura: esos campos **no existen** en la UI —un material
///    con puntos reventaría el `CHECK` de la base—, así que el gateway recibe
///    `puntosMaximos: null` y `fechaLimite: null`.
///
/// Guardar hace dos llamadas: [AulaGateway.crearTarea] (nace BORRADOR, sin
/// entregas) y [AulaGateway.publicarTarea] (crea un placeholder por estudiante
/// matriculado). El recuento de [PublicacionTarea.entregasCreadas] es la
/// confirmación de que el bucle arrancó.
class CrearTareaPanel extends StatefulWidget {
  const CrearTareaPanel({
    super.key,
    required this.seccionId,
    required this.gateway,
    this.onGuardado,
  });

  final String seccionId;
  final AulaGateway gateway;
  final VoidCallback? onGuardado;

  @override
  State<CrearTareaPanel> createState() => _CrearTareaPanelState();
}

class _CrearTareaPanelState extends State<CrearTareaPanel> {
  final _forma = GlobalKey<FormState>();
  final _controlTitulo = TextEditingController();
  final _controlDescripcion = TextEditingController();
  final _controlPuntos = TextEditingController();
  final _controlTema = TextEditingController();

  TipoTarea _tipo = TipoTarea.tarea;
  DateTime? _fechaLimite;
  bool _permitirTardia = true;
  bool _guardando = false;
  String? _error;
  PublicacionTarea? _publicada;

  @override
  void dispose() {
    _controlTitulo.dispose();
    _controlDescripcion.dispose();
    _controlPuntos.dispose();
    _controlTema.dispose();
    super.dispose();
  }

  bool get _esMaterial => !_tipo.seCalifica;

  Future<void> _guardar() async {
    if (!_forma.currentState!.validate()) return;
    if (_guardando) return;

    final puntos = _esMaterial
        ? null
        : (_controlPuntos.text.trim().isEmpty
            ? null
            : double.tryParse(_controlPuntos.text.trim()));

    setState(() {
      _guardando = true;
      _error = null;
      _publicada = null;
    });

    // Dos llamadas, una tras otra: crear (borrador) y publicar (placeholders).
    // `Result.when` **no** espera callbacks async, así que se consume con
    // `isFailure`/`valueOrNull` y se encadena con `await` explícito: si la
    // primera falla, la segunda no se ejecuta; si la segunda falla, la tarea
    // queda como borrador y el error lo dice, sin fingir éxito.
    final creada = await Result.guard(
      () => widget.gateway.crearTarea(
        seccionId: widget.seccionId,
        titulo: _controlTitulo.text.trim(),
        descripcion: _controlDescripcion.text.trim(),
        tipo: _tipo,
        puntosMaximos: puntos,
        fechaLimite: _esMaterial ? null : _fechaLimite,
        permitirEntregaTardia: _permitirTardia,
        tema: _controlTema.text.trim().isEmpty ? null : _controlTema.text.trim(),
      ),
    );
    if (!mounted) return;

    if (creada.isFailure) {
      setState(() {
        _error = creada.errorOrNull?.message;
        _guardando = false;
      });
      return;
    }

    final publicada = await Result.guard(
      () => widget.gateway.publicarTarea(creada.valueOrNull!.id),
    );
    if (!mounted) return;

    setState(() {
      _guardando = false;
      publicada.when(
        success: (resultado) {
          widget.onGuardado?.call();
          _publicada = resultado;
        },
        failure: (fallo) => _error = fallo.message,
      );
    });
  }

  Future<void> _elegirFechaLimite() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate:
          _fechaLimite ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: _fechaLimite != null
          ? TimeOfDay.fromDateTime(_fechaLimite!)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (hora == null || !mounted) return;

    setState(() {
      _fechaLimite = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_publicada != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nueva tarea')),
        body: ContenidoSeccion(
          migas: const ['Inicio', 'Académico', 'Aula Virtual', 'Nueva tarea'],
          child: ListView(
          children: [
            const TituloSeccion('Tarea publicada'),
            const SizedBox(height: 16),
            AvisoEnLinea(
              tono: TonoAviso.exito,
              icono: Icons.check_circle_outline,
              texto: 'Se creó «${_controlTitulo.text.trim()}» y se generaron '
                  '${_publicada!.entregasCreadas} entrega(s) para los '
                  'estudiantes matriculados.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Listo'),
              ),
            ),
          ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva tarea')),
      body: ContenidoSeccion(
        migas: const ['Inicio', 'Académico', 'Aula Virtual', 'Nueva tarea'],
        child: Form(
        key: _forma,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TituloSeccion(
              'Nueva tarea o material',
              subtitulo: 'Una tarea se califica; un material es de lectura.',
            ),
            const SizedBox(height: 16),
            // `DropdownButton` controlado, no `DropdownButtonFormField`: el segundo
            // guarda su propio estado y no relee el valor desde fuera (ver
            // cpanel_cuadrante_panel.dart), así que al cambiar `_tipo` el desplegable
            // no se actualizaría. El borde lo da `InputDecorator`.
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              child: DropdownButton<TipoTarea>(
                value: _tipo,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: TipoTarea.tarea,
                    child: Text('Tarea (se califica)'),
                  ),
                  DropdownMenuItem(
                    value: TipoTarea.material,
                    child: Text('Material (de lectura)'),
                  ),
                ],
                onChanged: (valor) => setState(() => _tipo = valor!),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controlTitulo,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (valor) =>
                  (valor == null || valor.trim().isEmpty)
                      ? 'Escribe un título.'
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controlDescripcion,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            // Los campos de calificación sólo existen para una TAREA. Ocultarlos
            // para un MATERIAL no es cosmética: enviar puntos a un material
            // reventaría el `CHECK` de la base.
            if (!_esMaterial) ...[
              TextFormField(
                controller: _controlPuntos,
                decoration: const InputDecoration(
                  labelText: 'Puntos máximos (0–20, opcional)',
                  border: OutlineInputBorder(),
                  hintText: 'En blanco = 20 por defecto',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (valor) {
                  final texto = valor?.trim() ?? '';
                  if (texto.isEmpty) return null;
                  final numero = double.tryParse(texto);
                  if (numero == null) return 'Escribe un número.';
                  if (numero < 0 || numero > 20) {
                    return 'Los puntos van de 0 a 20.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Fecha límite'),
                subtitle: _fechaLimite == null
                    ? const Text('Sin fecha límite.')
                    : Text(_textoFecha(_fechaLimite!)),
                trailing: _fechaLimite == null
                    ? null
                    : IconButton(
                        tooltip: 'Quitar fecha',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _fechaLimite = null),
                      ),
                onTap: _elegirFechaLimite,
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Permitir entrega tardía'),
              value: _permitirTardia,
              onChanged: (valor) => setState(() => _permitirTardia = valor),
            ),
            TextFormField(
              controller: _controlTema,
              decoration: const InputDecoration(
                labelText: 'Tema / agrupación (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AvisoEnLinea(
                tono: TonoAviso.peligro,
                icono: Icons.error_outline,
                texto: _error!,
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_guardando ? 'Guardando…' : 'Crear y publicar'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _esMaterial
                  ? 'Un material no se califica ni tiene fecha límite: se publica '
                      'para lectura.'
                  : 'Al publicar se crea una entrega por estudiante matriculado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          ),
        ),
      ),
    ),
    );
  }

  String _textoFecha(DateTime fecha) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${fecha.year}-${pad(fecha.month)}-${pad(fecha.day)} '
        '${pad(fecha.hour)}:${pad(fecha.minute)}';
  }
}
