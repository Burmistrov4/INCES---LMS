import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../models/system_setting.dart';
import '../../repositories/modulo_repository.dart';
import '../../widgets/comunes.dart';

/// Editor de parámetros del sistema.
///
/// El control que se pinta depende del `tipo` declarado en la base de datos
/// (`number`, `boolean`, `string`, `json`), no de adivinar a partir del valor.
/// Así un parámetro que hoy vale `3` y mañana vale `"tres"` no rompe la UI: el
/// tipo es el contrato, y la API lo valida al guardar.
class CpanelParametrosPanel extends StatefulWidget {
  const CpanelParametrosPanel({super.key, this.repositorio});

  final ModuloRepository? repositorio;

  @override
  State<CpanelParametrosPanel> createState() => _CpanelParametrosPanelState();
}

class _CpanelParametrosPanelState extends State<CpanelParametrosPanel> {
  late final ModuloRepository _repo = widget.repositorio ?? ModuloRepository();

  bool _cargando = true;
  String? _error;
  List<SystemSetting> _parametros = const [];

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

    final resultado = await _repo.obtenerSettings();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final parametros):
          _parametros = parametros;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _guardar(SystemSetting parametro, Object? valor) async {
    final resultado = await _repo.actualizarSetting(
      clave: parametro.clave,
      valor: valor,
    );
    if (!mounted) return;

    switch (resultado) {
      case Success(value: final actualizado):
        setState(() {
          _parametros = [
            for (final p in _parametros)
              if (p.clave == actualizado.clave) actualizado else p,
          ];
        });
        mostrarAviso(context, '${actualizado.clave} actualizado');
      case Failure(error: final fallo):
        mostrarAviso(context, fallo.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EstadoPanel(
      cargando: _cargando,
      error: _error,
      onReintentar: _cargar,
      child: _construirLista(context),
    );
  }

  Widget _construirLista(BuildContext context) {
    if (_parametros.isEmpty) {
      return const Center(child: Text('No hay parámetros configurados.'));
    }

    final porCategoria = <String, List<SystemSetting>>{};
    for (final parametro in _parametros) {
      porCategoria.putIfAbsent(parametro.categoria, () => []).add(parametro);
    }

    final categorias = porCategoria.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const AvisoEnLinea(
          texto:
              'Estos valores se leen en caliente: el cambio surte efecto sin '
              'reiniciar nada. Los marcados como públicos también los ve el '
              'formulario de inscripción.',
        ),
        const SizedBox(height: 20),
        for (final categoria in categorias) ...[
          TituloSeccion(ModuloRepository.etiquetaCategoria(categoria)),
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < porCategoria[categoria]!.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _FilaParametro(
                    parametro: porCategoria[categoria]![i],
                    onGuardar: _guardar,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Fila editable de un parámetro. Es un widget con estado propio porque cada
/// campo de texto necesita su controlador y su bandera de guardado.
class _FilaParametro extends StatefulWidget {
  const _FilaParametro({required this.parametro, required this.onGuardar});

  final SystemSetting parametro;
  final Future<void> Function(SystemSetting parametro, Object? valor) onGuardar;

  @override
  State<_FilaParametro> createState() => _FilaParametroState();
}

class _FilaParametroState extends State<_FilaParametro> {
  late final TextEditingController _controlador =
      TextEditingController(text: _valorComoTexto(widget.parametro));
  bool _guardando = false;
  String? _errorLocal;

  @override
  void didUpdateWidget(_FilaParametro anterior) {
    super.didUpdateWidget(anterior);
    // Si el valor cambió fuera (o tras un guardado), el campo se sincroniza.
    if (anterior.parametro.valor != widget.parametro.valor) {
      _controlador.text = _valorComoTexto(widget.parametro);
      _errorLocal = null;
    }
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  static String _valorComoTexto(SystemSetting parametro) {
    final valor = parametro.valor;
    if (valor == null) return '';
    if (valor is String) return valor;
    if (valor is Map || valor is List) {
      return const JsonEncoder.withIndent('  ').convert(valor);
    }
    return valor.toString();
  }

  /// Convierte el texto del campo al tipo declarado.
  ///
  /// Devuelve `null` si el texto no es válido, y en ese caso deja el motivo en
  /// `_errorLocal` para que el usuario sepa qué corregir en vez de ver un
  /// mensaje genérico del servidor.
  Object? _interpretar(String texto) {
    final limpio = texto.trim();

    switch (widget.parametro.tipo) {
      case 'number':
        // En Venezuela el separador decimal es la coma. Rechazarla obligaría a
        // escribir «2.5» a alguien que teclea «2,5» de forma natural.
        final normalizado = limpio.replaceAll(',', '.');
        final comoEntero = int.tryParse(normalizado);
        if (comoEntero != null) return comoEntero;
        final comoDecimal = double.tryParse(normalizado);
        if (comoDecimal != null) return comoDecimal;
        _errorLocal = 'Escribe un número (por ejemplo 3 o 2,5).';
        return null;

      case 'boolean':
        if (limpio.toLowerCase() == 'true') return true;
        if (limpio.toLowerCase() == 'false') return false;
        _errorLocal = 'Escribe true o false.';
        return null;

      case 'string':
        return limpio;

      case 'json':
      default:
        try {
          return jsonDecode(limpio);
        } on FormatException {
          _errorLocal = 'El texto no es JSON válido.';
          return null;
        }
    }
  }

  Future<void> _guardarTexto() async {
    setState(() => _errorLocal = null);
    final valor = _interpretar(_controlador.text);

    if (_errorLocal != null) {
      setState(() {});
      return;
    }

    setState(() => _guardando = true);
    await widget.onGuardar(widget.parametro, valor);
    if (!mounted) return;
    setState(() => _guardando = false);
  }

  Future<void> _guardarBooleano(bool valor) async {
    setState(() => _guardando = true);
    await widget.onGuardar(widget.parametro, valor);
    if (!mounted) return;
    setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parametro = widget.parametro;
    final esBooleano = parametro.tipo == 'boolean';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            parametro.clave,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _chip(context, parametro),
                      ],
                    ),
                    if (parametro.descripcion != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        parametro.descripcion!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (esBooleano) ...[
                const SizedBox(width: 12),
                if (_guardando)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: parametro.comoBooleano ?? false,
                    onChanged: _guardarBooleano,
                  ),
              ],
            ],
          ),
          if (!esBooleano) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controlador,
                    enabled: !_guardando,
                    maxLines: parametro.tipo == 'json' ? 5 : 1,
                    minLines: parametro.tipo == 'json' ? 3 : 1,
                    keyboardType: parametro.tipo == 'number'
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    inputFormatters: parametro.tipo == 'number'
                        ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
                        : null,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _errorLocal,
                      suffixText: parametro.tipo,
                    ),
                    onSubmitted: (_) => _guardarTexto(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _guardando ? null : _guardarTexto,
                  child: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Actualizado: ${formatearFechaHora(parametro.updatedAt)}',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, SystemSetting parametro) {
    final theme = Theme.of(context);
    final color = parametro.esPublico
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        parametro.esPublico ? 'público' : 'privado',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
