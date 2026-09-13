import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/system_module.dart';
import '../../repositories/modulo_repository.dart';
import 'cpanel_estado.dart';

/// Módulo que da acceso a este mismo panel.
///
/// La base de datos impide apagarlo (trigger `proteger_modulo_critico`) y la API
/// también. La UI lo refleja desactivando el interruptor y explicando por qué,
/// en vez de dejar que el usuario pulse y reciba un error.
const String claveModuloCpanel = 'm0_cpanel';

const Map<String, String> etiquetasRol = {
  'admin': 'Administrador',
  'docente': 'Docente',
  'estudiante': 'Estudiante',
};

/// Interruptores de módulos: el núcleo del Poder Absoluto del Administrador.
class CpanelModulosPanel extends StatefulWidget {
  const CpanelModulosPanel({super.key, this.repositorio});

  final ModuloRepository? repositorio;

  @override
  State<CpanelModulosPanel> createState() => _CpanelModulosPanelState();
}

class _CpanelModulosPanelState extends State<CpanelModulosPanel> {
  late final ModuloRepository _repo = widget.repositorio ?? ModuloRepository();

  bool _cargando = true;
  String? _error;
  List<SystemModule> _modulos = const [];

  /// Claves con una operación de guardado en curso. Mientras una clave está
  /// aquí, su interruptor se deshabilita: evita que dos pulsaciones rápidas
  /// generen peticiones contradictorias.
  final Set<String> _guardando = {};

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

    final resultado = await _repo.obtenerModulos();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final modulos):
          _modulos = modulos;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _alternar(SystemModule modulo, bool habilitado) async {
    setState(() => _guardando.add(modulo.clave));

    final resultado = await _repo.alternarModulo(
      clave: modulo.clave,
      habilitado: habilitado,
    );
    if (!mounted) return;

    setState(() => _guardando.remove(modulo.clave));

    switch (resultado) {
      case Success(value: final actualizado):
        // Sólo ahora se refleja el cambio: si el guardado falla, el interruptor
        // sigue mostrando la verdad y no una intención.
        setState(() {
          _modulos = [
            for (final m in _modulos)
              if (m.clave == actualizado.clave) actualizado else m,
          ];
        });
        mostrarAviso(
          context,
          '${actualizado.nombre}: '
          '${actualizado.habilitado ? 'activado' : 'desactivado'}',
        );
      case Failure(error: final fallo):
        mostrarAviso(context, fallo.message, error: true);
    }
  }

  Future<void> _editarRoles(SystemModule modulo) async {
    final seleccion = await showDialog<List<String>>(
      context: context,
      builder: (_) => _DialogoRoles(modulo: modulo),
    );

    if (seleccion == null || !mounted) return;

    setState(() => _guardando.add(modulo.clave));
    final resultado = await _repo.cambiarRolesPermitidos(
      clave: modulo.clave,
      roles: seleccion,
    );
    if (!mounted) return;
    setState(() => _guardando.remove(modulo.clave));

    switch (resultado) {
      case Success(value: final actualizado):
        setState(() {
          _modulos = [
            for (final m in _modulos)
              if (m.clave == actualizado.clave) actualizado else m,
          ];
        });
        mostrarAviso(
          context,
          actualizado.rolesPermitidos.isEmpty
              ? '${actualizado.nombre}: visible para todos los roles'
              : '${actualizado.nombre}: acceso restringido',
        );
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
    if (_modulos.isEmpty) {
      return const Center(child: Text('No hay módulos registrados.'));
    }

    final agrupados = ModuloRepository.agruparPorCategoria(_modulos);
    final activos = _modulos.where((m) => m.habilitado).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Aviso(
          texto:
              '$activos de ${_modulos.length} módulos activos. Al desactivar un '
              'módulo, su API deja de atender de inmediato y desaparece del menú '
              'de todos los usuarios. Cada cambio queda registrado en la auditoría.',
        ),
        const SizedBox(height: 20),
        for (final entrada in agrupados.entries) ...[
          TituloSeccion(ModuloRepository.etiquetaCategoria(entrada.key)),
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entrada.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _filaModulo(context, entrada.value[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _filaModulo(BuildContext context, SystemModule modulo) {
    final theme = Theme.of(context);
    final esCritico = modulo.clave == claveModuloCpanel;
    final guardando = _guardando.contains(modulo.clave);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
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
                        modulo.nombre,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _chipEstado(context, modulo.habilitado),
                    if (esCritico) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message:
                            'Módulo crítico: da acceso a este panel. No puede '
                            'desactivarse.',
                        child: Icon(
                          Icons.lock_outline,
                          size: 15,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
                if (modulo.descripcion != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    modulo.descripcion!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                _filaRoles(context, modulo),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (guardando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Switch(
              value: modulo.habilitado,
              onChanged: esCritico
                  ? null
                  : (valor) => _alternar(modulo, valor),
            ),
        ],
      ),
    );
  }

  Widget _chipEstado(BuildContext context, bool habilitado) {
    final theme = Theme.of(context);
    final color = habilitado ? Colors.green : theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        habilitado ? 'activo' : 'inactivo',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _filaRoles(BuildContext context, SystemModule modulo) {
    final theme = Theme.of(context);
    final restringido = modulo.rolesPermitidos.isNotEmpty;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          restringido ? 'Acceso:' : 'Visible para todos los roles',
          style: theme.textTheme.labelSmall,
        ),
        if (restringido)
          for (final rol in modulo.rolesPermitidos)
            Chip(
              label: Text(etiquetasRol[rol] ?? rol),
              labelStyle: theme.textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        TextButton.icon(
          onPressed: _guardando.contains(modulo.clave)
              ? null
              : () => _editarRoles(modulo),
          icon: const Icon(Icons.group_outlined, size: 15),
          label: const Text('Cambiar'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ],
    );
  }
}

/// Diálogo para elegir qué roles pueden ver un módulo.
class _DialogoRoles extends StatefulWidget {
  const _DialogoRoles({required this.modulo});

  final SystemModule modulo;

  @override
  State<_DialogoRoles> createState() => _DialogoRolesState();
}

class _DialogoRolesState extends State<_DialogoRoles> {
  late final Set<String> _seleccion = {...widget.modulo.rolesPermitidos};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('Acceso a ${widget.modulo.nombre}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sin ningún rol marcado, el módulo es visible para todos. '
              'Con roles marcados, sólo ellos lo ven.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final rol in etiquetasRol.entries)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _seleccion.contains(rol.key),
                title: Text(rol.value),
                onChanged: (marcado) {
                  setState(() {
                    if (marcado == true) {
                      _seleccion.add(rol.key);
                    } else {
                      _seleccion.remove(rol.key);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_seleccion.toList()..sort()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
