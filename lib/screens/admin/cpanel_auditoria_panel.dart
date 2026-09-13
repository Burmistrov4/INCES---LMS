import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/config_audit_entry.dart';
import '../../repositories/modulo_repository.dart';
import '../../widgets/comunes.dart';

/// Historial de cambios de configuración.
///
/// Sin esto, el Poder Absoluto del Administrador sería un agujero negro: apagar
/// el módulo de asistencia el día del cierre de notas no dejaría rastro. Los
/// registros los escribe un trigger de PostgreSQL, no la aplicación, así que no
/// se pueden omitir ni falsificar desde el cliente.
class CpanelAuditoriaPanel extends StatefulWidget {
  const CpanelAuditoriaPanel({super.key, this.repositorio, this.limite = 50});

  final ModuloRepository? repositorio;
  final int limite;

  @override
  State<CpanelAuditoriaPanel> createState() => _CpanelAuditoriaPanelState();
}

class _CpanelAuditoriaPanelState extends State<CpanelAuditoriaPanel> {
  late final ModuloRepository _repo = widget.repositorio ?? ModuloRepository();

  bool _cargando = true;
  String? _error;
  List<ConfigAuditEntry> _entradas = const [];

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

    final resultado = await _repo.obtenerAuditoria(limite: widget.limite);
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final entradas):
          _entradas = entradas;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return EstadoPanel(
      cargando: _cargando,
      error: _error,
      onReintentar: _cargar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Últimos ${widget.limite} cambios de configuración',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _cargar,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _entradas.isEmpty
                ? const Center(
                    child: Text('Todavía no hay cambios registrados.'),
                  )
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView.separated(
                      itemCount: _entradas.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, indice) =>
                          _fila(context, _entradas[indice]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _fila(BuildContext context, ConfigAuditEntry entrada) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          entrada.tabla == 'system_modules'
              ? Icons.toggle_on_outlined
              : Icons.tune_outlined,
          size: 17,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        entrada.descripcionCorta,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${entrada.tabla} · ${entrada.usuarioEmail ?? 'desconocido'} · '
        '${formatearFechaHora(entrada.creadoEn)}',
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}
