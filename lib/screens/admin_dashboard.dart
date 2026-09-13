import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'admin/cpanel_auditoria_panel.dart';
import 'admin/cpanel_modulos_panel.dart';
import 'admin/cpanel_parametros_panel.dart';

/// cPanel del Administrador Maestro.
///
/// Las cuatro primeras secciones siguen siendo marcadores de posición: su
/// contenido depende de módulos (M2, M3, M6, M7) que todavía no existen. Las
/// tres últimas son el Núcleo del Administrador y están operativas.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.auth});

  final AuthService? auth;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

/// Entrada de navegación del panel.
class _Seccion {
  const _Seccion(this.icono, this.titulo, this.descripcion);

  final IconData icono;
  final String titulo;

  /// `null` ⇒ sección todavía no construida: se muestra un marcador.
  final String? descripcion;
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AuthService _auth = widget.auth ?? AuthService();

  int _seleccionada = 0;

  static const List<_Seccion> _secciones = [
    _Seccion(
      Icons.dashboard_outlined,
      'Panel Principal',
      'Métricas generales del centro de formación.',
    ),
    _Seccion(
      Icons.people_outline,
      'Usuarios y Roles',
      'Tabla global de aspirantes, estudiantes y docentes.',
    ),
    _Seccion(
      Icons.menu_book_outlined,
      'Programas Académicos',
      'Estructura de cursos y unidades curriculares (M2).',
    ),
    _Seccion(
      Icons.assignment_outlined,
      'Control de Notas',
      'Planilla de asistencia y carga de calificaciones (M6, M7).',
    ),
    _Seccion(Icons.toggle_on_outlined, 'Módulos del Sistema', null),
    _Seccion(Icons.tune_outlined, 'Parámetros', null),
    _Seccion(Icons.history_outlined, 'Auditoría', null),
  ];

  /// Ancho a partir del cual el menú lateral se muestra fijo. Por debajo, pasa a
  /// un cajón lateral: un `Row` con un ancho fijo desborda en pantallas angostas.
  static const double _anchoMinimoEscritorio = 900;

  Future<void> _cerrarSesion() async {
    await _auth.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esAngosto = MediaQuery.sizeOf(context).width < _anchoMinimoEscritorio;

    return Scaffold(
      drawer: esAngosto
          ? Drawer(
              backgroundColor: const Color(0xFF1E293B),
              child: _construirMenu(context),
            )
          : null,
      body: Row(
        children: [
          if (!esAngosto)
            SizedBox(
              width: 260,
              child: ColoredBox(
                color: const Color(0xFF1E293B),
                child: _construirMenu(context),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                _construirCabecera(context, theme, mostrarMenu: esAngosto),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(esAngosto ? 16 : 24),
                    child: IndexedStack(
                      index: _seleccionada,
                      children: [
                        for (final seccion in _secciones)
                          if (seccion.descripcion != null)
                            _marcador(theme, seccion.descripcion!)
                          else
                            _panel(seccion.titulo),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(String titulo) {
    switch (titulo) {
      case 'Módulos del Sistema':
        return const CpanelModulosPanel();
      case 'Parámetros':
        return const CpanelParametrosPanel();
      case 'Auditoría':
        return const CpanelAuditoriaPanel();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _construirCabecera(
    BuildContext context,
    ThemeData theme, {
    required bool mostrarMenu,
  }) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          if (mostrarMenu)
            Builder(
              builder: (contexto) => IconButton(
                tooltip: 'Menú',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(contexto).openDrawer(),
              ),
            ),
          Expanded(
            child: Text(
              _secciones[_seleccionada].titulo,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirMenu(BuildContext context) {
    final theme = Theme.of(context);
    final esAngosto = MediaQuery.sizeOf(context).width < _anchoMinimoEscritorio;
    final correo = _auth.emailActual ?? 'sesión no identificada';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.school_outlined,
                    color: Colors.blueAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INCES LMS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Administrador Maestro',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (var i = 0; i < _secciones.length; i++)
                  _itemMenu(
                    theme,
                    indice: i,
                    seccion: _secciones[i],
                    cerrarAlTocar: esAngosto,
                  ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: const CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: Text(
                'A',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: const Text(
              'Administrador',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              correo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            trailing: IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(
                Icons.logout_rounded,
                color: Colors.grey,
                size: 18,
              ),
              onPressed: _cerrarSesion,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemMenu(
    ThemeData theme, {
    required int indice,
    required _Seccion seccion,
    required bool cerrarAlTocar,
  }) {
    final seleccionado = _seleccionada == indice;
    final pendiente = seccion.descripcion != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() => _seleccionada = indice);
          if (cerrarAlTocar) Navigator.of(context).pop();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: seleccionado ? Colors.blueAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                seccion.icono,
                color: seleccionado ? Colors.white : Colors.grey[400],
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  seccion.titulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: seleccionado ? Colors.white : Colors.grey[400],
                    fontWeight:
                        seleccionado ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              if (pendiente)
                Tooltip(
                  message: 'Pendiente de construir',
                  child: Icon(
                    Icons.construction_outlined,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marcador(ThemeData theme, String descripcion) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              descripcion,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
