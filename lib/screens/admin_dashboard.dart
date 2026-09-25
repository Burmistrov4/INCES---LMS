import 'package:flutter/material.dart';

import '../repositories/modulo_repository.dart';
import '../services/auth_service.dart';
import '../theme/inces_theme.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import 'admin/cpanel_auditoria_accesos_panel.dart';
import 'admin/cpanel_auditoria_panel.dart';
import 'admin/cpanel_modulos_panel.dart';
import 'admin/cpanel_parametros_panel.dart';
import 'admin/cpanel_invitaciones_panel.dart';
import 'admin/cpanel_programas_panel.dart';
import 'admin/cpanel_cuadrante_panel.dart';
import 'admin/cpanel_inscripcion_campos_panel.dart';
import 'admin/cpanel_inscripciones_panel.dart';
import 'admin/cpanel_secciones_panel.dart';

/// cPanel del Administrador Maestro.
///
/// ## Qué cambió respecto a la versión anterior
///
/// Antes era un `Row` con una lista de secciones y un `IndexedStack`. Funcionaba,
/// pero se presentaba como un formulario: había que leer cada etiqueta para
/// saber qué se podía hacer. Ahora la estructura es la de un panel de control:
///
///  · El menú agrupa por **categoría con sentido para el usuario**
///    (*Gestión Académica*, *Control de Aulas*, *Administración del Sistema*) en
///    lugar de una lista plana. La categoría responde a «¿qué estoy intentando
///    hacer?», que es como piensa quien administra un centro.
///  · Las **migas de pan** y el **encabezado con rol y período** dan contexto
///    permanente. Antes, la única señal de dónde estabas era el título.
///  · Las secciones sin construir se marcan con un icono y **no son pulsables**.
///    Antes se podía entrar a una pantalla que sólo decía «pendiente», lo que
///    hace dudar de si la aplicación está rota.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.auth});

  final AuthService? auth;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AuthService _auth = widget.auth ?? AuthService();

  int _seleccionada = 0;

  /// Las secciones, con su categoría.
  ///
  /// El orden de esta lista es el orden del menú: primero lo construido —que es
  /// a lo que se entra—, y después lo planificado. Al revés, tres de cada cuatro
  /// clics caerían en una sección que no existe.
  static const List<ItemNavegacion> _items = [
    ItemNavegacion(
      icono: Icons.tune_outlined,
      titulo: 'Módulos del Sistema',
      categoria: 'Administración del sistema',
    ),
    ItemNavegacion(
      icono: Icons.settings_outlined,
      titulo: 'Parámetros',
      categoria: 'Administración del sistema',
    ),
    ItemNavegacion(
      icono: Icons.history_outlined,
      titulo: 'Auditoría',
      categoria: 'Administración del sistema',
    ),
    ItemNavegacion(
      icono: Icons.fingerprint_outlined,
      titulo: 'Auditoría de Accesos',
      categoria: 'Administración del sistema',
    ),
    ItemNavegacion(
      icono: Icons.people_outline,
      titulo: 'Usuarios y Roles',
      categoria: 'Administración del sistema',
    ),
    ItemNavegacion(
      icono: Icons.menu_book_outlined,
      titulo: 'Programas Académicos',
      categoria: 'Gestión académica',
    ),
    ItemNavegacion(
      icono: Icons.confirmation_number_outlined,
      titulo: 'Inscripciones y Cupos',
      categoria: 'Gestión académica',
      disponible: true,
    ),
    // Va justo después de Inscripciones y no en «Administración del sistema»
    // aunque sea configuración: quien administra el CFS llega aquí pensando en
    // el formulario de inscripción, no en los parámetros del sistema.
    ItemNavegacion(
      icono: Icons.edit_note_outlined,
      titulo: 'Campos de Inscripción',
      categoria: 'Gestión académica',
      disponible: true,
    ),
    ItemNavegacion(
      icono: Icons.class_outlined,
      titulo: 'Secciones',
      categoria: 'Gestión académica',
      disponible: true,
    ),
    ItemNavegacion(
      icono: Icons.calendar_month_outlined,
      titulo: 'Cuadrante y Horarios',
      categoria: 'Control de aulas',
      disponible: true,
    ),
    ItemNavegacion(
      icono: Icons.fact_check_outlined,
      titulo: 'Asistencia',
      categoria: 'Control de aulas',
      disponible: false,
    ),
    ItemNavegacion(
      icono: Icons.assignment_outlined,
      titulo: 'Calificaciones',
      categoria: 'Control de aulas',
      disponible: false,
    ),
  ];

  /// Período mostrado en el encabezado.
  ///
  /// Está escrito a mano a propósito y **no** leído de `system_settings`: ese
  /// parámetro existe (`periodo_activo`), pero leerlo aquí obligaría al
  /// dashboard a cargar todo el catálogo de parámetros antes de pintar. Cuando
  /// se construya el módulo de currículo, el período pasará a ser una selección
  /// real; hasta entonces un valor fijo comunica mejor que un hueco.
  /// El lapso vigente es `SA26-2` (ver system_settings.periodo_activo, fijado por
  /// la migración 202609180003). Cuando el módulo de currículo lo lea de ahí, este
  /// literal desaparece.
  static const String _periodoActivo = 'SA26-2';

  Future<void> _cerrarSesion() async {
    await _auth.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  String get _tituloSeccion => _items[_seleccionada].titulo;

  @override
  Widget build(BuildContext context) {
    return AndamiajeApp(
      items: _items,
      seleccionado: _seleccionada,
      onSeleccionar: (indice) => setState(() => _seleccionada = indice),
      rolEtiqueta: 'Administrador Maestro',
      correoUsuario: _auth.emailActual,
      periodoActivo: _periodoActivo,
      onCerrarSesion: _cerrarSesion,
      contenido: _contenido(),
    );
  }

  Widget _contenido() {
    switch (_items[_seleccionada].titulo) {
      case 'Módulos del Sistema':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Administración del sistema', 'Módulos'],
          child: CpanelModulosPanel(),
        );
      case 'Parámetros':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Administración del sistema', 'Parámetros'],
          child: CpanelParametrosPanel(),
        );
      case 'Auditoría':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Administración del sistema', 'Auditoría'],
          child: CpanelAuditoriaPanel(),
        );
      case 'Auditoría de Accesos':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Administración del sistema', 'Accesos'],
          child: CpanelAuditoriaAccesosPanel(),
        );
      case 'Usuarios y Roles':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Administración del sistema', 'Usuarios y Roles'],
          child: CpanelInvitacionesPanel(),
        );
      case 'Programas Académicos':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Gestión académica', 'Programas Académicos'],
          child: CpanelProgramasPanel(),
        );
      case 'Inscripciones y Cupos':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Gestión académica', 'Inscripciones y Cupos'],
          child: CpanelInscripcionesPanel(),
        );
      case 'Campos de Inscripción':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Gestión académica', 'Campos de Inscripción'],
          child: CpanelInscripcionCamposPanel(),
        );
      case 'Secciones':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Gestión académica', 'Secciones'],
          child: CpanelSeccionesPanel(),
        );
      case 'Cuadrante y Horarios':
        return const ContenidoSeccion(
          migas: ['Inicio', 'Control de aulas', 'Cuadrante y Horarios'],
          child: CpanelCuadrantePanel(),
        );
      default:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: MigasDePan(partes: ['Inicio', _tituloSeccion]),
        );
    }
  }
}

// -----------------------------------------------------------------------------
//  Tarjetas de acceso rápido
// -----------------------------------------------------------------------------

/// Tarjeta de una sección del sistema, con su categoría como contexto.
///
/// Reutilizable cuando el resto de secciones tengan contenido propio y el
/// dashboard pueda mostrar un resumen en lugar de una sección concreta.
class TarjetaAccesoSeccion extends StatelessWidget {
  const TarjetaAccesoSeccion({
    super.key,
    required this.item,
    required this.onAbrir,
  });

  final ItemNavegacion item;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disponible = item.disponible;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disponible ? onAbrir : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: disponible
                    ? IncesTheme.degradadoMarca
                    : LinearGradient(
                        colors: [
                          theme.colorScheme.outline,
                          theme.colorScheme.outline,
                        ],
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.icono,
                        size: 20,
                        color: disponible
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                      ),
                      const Spacer(),
                      if (!disponible)
                        Icon(
                          Icons.construction_outlined,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.titulo,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: disponible
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    disponible ? item.categoria : 'Pendiente de construir',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rejilla adaptativa de tarjetas.
///
/// El número de columnas se calcula por ancho disponible y no por un `breakpoint`
/// fijo: así funciona en móvil, tableta y monitor sin tres ramas distintas.
class RejillaTarjetas extends StatelessWidget {
  const RejillaTarjetas({
    super.key,
    required this.children,
    this.anchoMinimo = 260,
    this.espaciado = 16,
  });

  final List<Widget> children;
  final double anchoMinimo;
  final double espaciado;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = (restricciones.maxWidth / anchoMinimo)
            .floor()
            .clamp(1, 4);

        return Wrap(
          spacing: espaciado,
          runSpacing: espaciado,
          children: [
            for (final hijo in children)
              SizedBox(
                // Se resta el espaciado que consumen los huecos entre columnas,
                // no sólo el ancho de las tarjetas: sin eso la última columna
                // desborda por unos píxeles y el `Wrap` baja una tarjeta de más.
                width: (restricciones.maxWidth -
                        (espaciado * (columnas - 1))) /
                    columnas,
                child: hijo,
              ),
          ],
        );
      },
    );
  }
}

/// Métricas rápidas del panel de módulos.
///
/// Se calcula aquí, a partir de la lista cargada, en lugar de pedir un endpoint
/// de estadísticas: son cuatro cifras derivadas de datos que ya están en
/// memoria, y una petición extra para contarlos sería trabajo redundante.
///
/// La cuarta tarjeta no es «Protegidos» sino **«Auditoría hoy»**, y no es un
/// capricho: el requisito del Command Center pedía cuatro cifras de un vistazo,
/// y las otras tres (totales, activos, apagados) se derivan del mismo dato, así
/// que una cuarta del mismo tipo no añadía nada. `Últimos cambios` sí aporta:
/// responde a «¿alguien tocó algo últimamente?», que es la pregunta que se hace
/// al abrir el panel sospechando un problema.
class MetricasModulos extends StatelessWidget {
  const MetricasModulos({
    super.key,
    required this.total,
    required this.activos,
    required this.criticos,
    required this.cambiosRecientes,
  });

  final int total;
  final int activos;

  /// Módulos con candado (hoy, sólo `m0_cpanel`). Se muestra en el subtítulo de
  /// la tarjeta de protegidos.
  final int criticos;

  /// Cambios de configuración registrados en la auditoría reciente.
  final int cambiosRecientes;

  @override
  Widget build(BuildContext context) {
    return RejillaTarjetas(
      anchoMinimo: 200,
      children: [
        TarjetaMetrica(
          etiqueta: 'Módulos totales',
          valor: '$total',
          icono: Icons.widgets_outlined,
        ),
        TarjetaMetrica(
          etiqueta: 'Activos',
          valor: '$activos',
          icono: Icons.toggle_on_outlined,
          color: IncesTheme.exito,
        ),
        TarjetaMetrica(
          etiqueta: 'Apagados',
          valor: '${total - activos}',
          icono: Icons.toggle_off_outlined,
          color: const Color(0xFF64748B),
        ),
        TarjetaMetrica(
          etiqueta: 'Auditoría hoy',
          valor: '$cambiosRecientes',
          icono: Icons.history_outlined,
          color: IncesTheme.rojoInces,
        ),
      ],
    );
  }
}

/// Etiqueta legible de un módulo del núcleo, usada en las migas de pan.
String categoriaLegible(String categoria) =>
    ModuloRepository.etiquetaCategoria(categoria);
