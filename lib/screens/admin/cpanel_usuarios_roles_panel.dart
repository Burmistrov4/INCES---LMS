import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/recuperacion_password.dart';
import '../../models/usuario_admin.dart';
import '../../repositories/recuperacion_repository.dart';
import '../../repositories/usuario_admin_repository.dart';
import '../../widgets/comunes.dart';
import 'cpanel_invitaciones_panel.dart';

class CpanelUsuariosRolesPanel extends StatefulWidget {
  const CpanelUsuariosRolesPanel({
    super.key,
    this.repo,
    this.repoRecuperacion,
  });

  final UsuariosAdminRepository? repo;
  final RecuperacionRepository? repoRecuperacion;

  @override
  State<CpanelUsuariosRolesPanel> createState() =>
      _CpanelUsuariosRolesPanelState();
}

class _CpanelUsuariosRolesPanelState extends State<CpanelUsuariosRolesPanel> {
  late final _repo = widget.repo ?? UsuariosAdminRepository();
  late final _repoRecuperacion =
      widget.repoRecuperacion ?? RecuperacionRepository();
  final _busqueda = TextEditingController();
  PaginaUsuarios? _pagina;
  String? _rol;
  bool? _activo;
  bool _cargando = true;
  String? _error;
  Timer? _debounce;
  int _paginaActual = 0;
  static const _limite = 25;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
      });
    }
    final r = await _repo.listar(
      rol: _rol,
      activo: _activo,
      busqueda: _busqueda.text,
      limite: _limite,
      desplazamiento: _paginaActual * _limite,
    );
    if (!mounted) return;
    r.when(
      success: (p) => setState(() {
        _pagina = p;
        _error = null;
        _cargando = false;
      }),
      failure: (e) => setState(() {
        _error = e.message;
        _cargando = false;
      }),
    );
  }

  void _buscar(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _paginaActual = 0;
      _cargar();
    });
  }

  /// Emite un código temporal para que el usuario restablezca su contraseña.
  ///
  /// **El administrador no ve ni elige la contraseña**: sólo entrega el código.
  /// El código se muestra una sola vez porque no se guarda en claro en ninguna
  /// parte; si se pierde, se emite otro (lo que anula el anterior).
  ///
  /// La verificación de identidad es un procedimiento institucional —presencial,
  /// con la cédula— que el sistema no puede sustituir. Por eso el diálogo lo dice
  /// explícitamente en vez de dar a entender que basta con pulsar un botón.
  Future<void> _restablecer(UsuarioAdmin u) async {
    final r = await _repoRecuperacion.emitirCodigo(u.id);
    if (!mounted) return;

    r.when(
      success: (codigo) => _mostrarCodigo(u, codigo),
      failure: (fallo) => mostrarAviso(context, fallo.message),
    );
  }

  void _mostrarCodigo(UsuarioAdmin u, CodigoRecuperacion c) {
    showDialog<void>(
      context: context,
      // No se cierra al tocar fuera: el código no se puede volver a consultar y
      // un toque accidental lo perdería.
      barrierDismissible: false,
      builder: (contexto) => AlertDialog(
        title: const Text('Código de restablecimiento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para ${u.nombreCompleto} — ${c.email}'),
            const SizedBox(height: 16),
            SelectableText(
              c.codigo,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Entrégalo en persona o por el canal interno del centro. '
              'Caduca en 30 minutos y sólo sirve una vez.\n\n'
              'No se ha enviado por correo: esta pantalla es la única vez que el '
              'código es visible.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: c.codigo));
              if (contexto.mounted) {
                mostrarAviso(contexto, 'Código copiado.', exito: true);
              }
            },
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _cambiarRol(UsuarioAdmin u) async {
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoRol(actual: u.rol),
    );
    if (!mounted || nuevo == null || nuevo == u.rol) return;
    if (nuevo == 'admin') {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Otorgar administrador'),
              content: Text(
                '${u.nombreCompleto} tendrá acceso completo al cPanel. ¿Continuar?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    final r = await _repo.cambiarRol(id: u.id, rol: nuevo);
    if (!mounted) return;
    r.when(
      success: (_) {
        mostrarAviso(
          context,
          nuevo == 'admin'
              ? 'Administrador otorgado correctamente.'
              : 'Rol actualizado correctamente.',
          exito: true,
        );
        _cargar();
      },
      failure: (e) => mostrarAviso(context, e.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _pagina;
    final users = p?.usuarios ?? const <UsuarioAdmin>[];
    final pages = ((p?.total ?? 0) / _limite).ceil();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const TituloSeccion(
          'Usuarios y Roles',
          subtitulo: 'Gestiona usuarios, roles y acceso administrativo.',
        ),
        const SizedBox(height: 16),
        _ResumenUsuarios(total: p?.total ?? 0, usuarios: users),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final esEstrecho = constraints.maxWidth < 600;
                    if (esEstrecho) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _busqueda,
                            onChanged: _buscar,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Buscar usuario',
                              hintText: 'Nombre, correo o cédula',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              DropdownButton<String?>(
                                value: _rol,
                                hint: const Text('Todos los roles'),
                                items: const [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Todos los roles'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'admin',
                                    child: Text('Administradores'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'docente',
                                    child: Text('Docentes'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'estudiante',
                                    child: Text('Estudiantes'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() {
                                    _rol = v;
                                    _paginaActual = 0;
                                  });
                                  _cargar();
                                },
                              ),
                              DropdownButton<bool?>(
                                value: _activo,
                                hint: const Text('Estado'),
                                items: const [
                                  DropdownMenuItem<bool?>(
                                    value: null,
                                    child: Text('Todos'),
                                  ),
                                  DropdownMenuItem(
                                    value: true,
                                    child: Text('Activos'),
                                  ),
                                  DropdownMenuItem(
                                    value: false,
                                    child: Text('Inactivos'),
                                  ),
                                ],
                                onChanged: (v) {
                                  setState(() {
                                    _activo = v;
                                    _paginaActual = 0;
                                  });
                                  _cargar();
                                },
                              ),
                              IconButton(
                                onPressed: _cargando ? null : _cargar,
                                tooltip: 'Actualizar',
                                icon: const Icon(Icons.refresh),
                              ),
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _busqueda,
                            onChanged: _buscar,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Buscar usuario',
                              hintText: 'Nombre, correo o cédula',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String?>(
                          value: _rol,
                          hint: const Text('Todos los roles'),
                          items: const [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todos los roles'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Administradores'),
                            ),
                            DropdownMenuItem(
                              value: 'docente',
                              child: Text('Docentes'),
                            ),
                            DropdownMenuItem(
                              value: 'estudiante',
                              child: Text('Estudiantes'),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _rol = v;
                              _paginaActual = 0;
                            });
                            _cargar();
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<bool?>(
                          value: _activo,
                          hint: const Text('Estado'),
                          items: const [
                            DropdownMenuItem<bool?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            DropdownMenuItem(
                              value: true,
                              child: Text('Activos'),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text('Inactivos'),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _activo = v;
                              _paginaActual = 0;
                            });
                            _cargar();
                          },
                        ),
                        IconButton(
                          onPressed: _cargando ? null : _cargar,
                          tooltip: 'Actualizar',
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    );
                  },
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AvisoEnLinea(
                      tono: TonoAviso.peligro,
                      icono: Icons.error_outline,
                      texto: _error!,
                    ),
                  ),
                if (_cargando)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 12),
                if (users.isEmpty && !_cargando)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No hay usuarios que coincidan con los filtros.',
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Usuario')),
                        DataColumn(label: Text('Correo')),
                        DataColumn(label: Text('Rol')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Acciones')),
                      ],
                      rows: users
                          .map(
                            (u) => DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 210,
                                    child: Text(u.nombreCompleto),
                                  ),
                                ),
                                DataCell(Text(u.email)),
                                DataCell(_RolChip(u.rol)),
                                DataCell(
                                  Text(u.activo ? 'Activo' : 'Inactivo'),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Cambiar rol',
                                        onPressed: () => _cambiarRol(u),
                                        icon: const Icon(
                                          Icons.manage_accounts_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Restablecer contraseña',
                                        onPressed: () => _restablecer(u),
                                        icon: const Icon(Icons.key_outlined),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Página ${_paginaActual + 1} de ${pages < 1 ? 1 : pages}',
                    ),
                    IconButton(
                      onPressed: _paginaActual == 0 || _cargando
                          ? null
                          : () {
                              setState(() {
                                _paginaActual--;
                              });
                              _cargar();
                            },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      onPressed:
                          _cargando || pages < 1 || _paginaActual + 1 >= pages
                          ? null
                          : () {
                              setState(() {
                                _paginaActual++;
                              });
                              _cargar();
                            },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Invitar docente'),
          subtitle: const Text(
            'Crear una cuenta nueva y después gestionar su rol desde esta pantalla.',
          ),
          leading: const Icon(Icons.person_add_alt_1_outlined),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: CpanelInvitacionesPanel(),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResumenUsuarios extends StatelessWidget {
  const _ResumenUsuarios({required this.usuarios, required this.total});
  final List<UsuarioAdmin> usuarios;
  final int total;
  @override
  Widget build(BuildContext c) {
    int n(String r) => usuarios.where((u) => u.rol == r).length;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children:
          [
                ['Usuarios', total, Icons.people_outline],
                [
                  'Administradores',
                  n('admin'),
                  Icons.admin_panel_settings_outlined,
                ],
                ['Docentes', n('docente'), Icons.school_outlined],
                ['Estudiantes', n('estudiante'), Icons.person_outline],
              ]
              .map(
                (x) => SizedBox(
                  width: 180,
                  child: Card(
                    child: ListTile(
                      leading: Icon(x[2] as IconData),
                      title: Text((x[1] as int).toString()),
                      subtitle: Text(x[0] as String),
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _RolChip extends StatelessWidget {
  const _RolChip(this.rol);
  final String rol;
  @override
  Widget build(BuildContext c) => Chip(
    label: Text(switch (rol) {
      'admin' => 'Administrador',
      'docente' => 'Docente',
      _ => 'Estudiante',
    }),
  );
}

class _DialogoRol extends StatefulWidget {
  const _DialogoRol({required this.actual});
  final String actual;
  @override
  State<_DialogoRol> createState() => _DialogoRolState();
}

class _DialogoRolState extends State<_DialogoRol> {
  late String rol;
  @override
  void initState() {
    super.initState();
    rol = widget.actual;
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: const Text('Cambiar rol'),
    content: DropdownButtonFormField<String>(
      initialValue: rol,
      items: const [
        DropdownMenuItem(value: 'admin', child: Text('Administrador')),
        DropdownMenuItem(value: 'docente', child: Text('Docente')),
        DropdownMenuItem(value: 'estudiante', child: Text('Estudiante')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => rol = v);
      },
      decoration: const InputDecoration(labelText: 'Nuevo rol'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(c, rol),
        child: const Text('Guardar'),
      ),
    ],
  );
}
