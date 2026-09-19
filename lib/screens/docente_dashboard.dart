import 'package:flutter/material.dart';

import '../models/archivo.dart';
import '../services/auth_service.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import 'gestor_documental_panel.dart';
import 'mi_horario_panel.dart';

/// Panel del docente.
///
/// Comparte el andamiaje con el panel del administrador —mismo encabezado,
/// mismo menú, mismas migas— en lugar de montar su propio `Scaffold`. Es lo que
/// hace que la aplicación se lea como **una** plataforma con distintos permisos,
/// y no como pantallas sueltas cosidas.
///
/// Las secciones siguen siendo marcadores: dependen de los módulos M2
/// (currículo), M3 (cuadrante) y M6/M7 (asistencia y calificaciones), que
/// todavía no existen. Se muestran atenuadas y **no pulsables**, con el módulo
/// del que dependen en el tooltip: así quien usa el panel entiende que falta
/// algo concreto, en vez de sospechar que la aplicación está rota.
class DocenteDashboardScreen extends StatefulWidget {
  const DocenteDashboardScreen({super.key, this.auth});

  final AuthService? auth;

  @override
  State<DocenteDashboardScreen> createState() => _DocenteDashboardScreenState();
}

class _DocenteDashboardScreenState extends State<DocenteDashboardScreen> {
  late final AuthService _auth = widget.auth ?? AuthService();

  int _seleccionada = 0;

  static const List<ItemNavegacion> _items = [
    ItemNavegacion(
      icono: Icons.dashboard_outlined,
      titulo: 'Mis aulas',
      categoria: 'Control de aulas',
    ),
    ItemNavegacion(
      icono: Icons.fact_check_outlined,
      titulo: 'Asistencia',
      categoria: 'Control de aulas',
      disponible: false,
    ),
    ItemNavegacion(
      icono: Icons.grading_outlined,
      titulo: 'Calificaciones',
      categoria: 'Control de aulas',
      disponible: false,
    ),
    ItemNavegacion(
      icono: Icons.folder_open_outlined,
      titulo: 'Material de apoyo',
      categoria: 'Recursos',
      disponible: true,
    ),
    ItemNavegacion(
      icono: Icons.calendar_month_outlined,
      titulo: 'Mi horario',
      categoria: 'Recursos',
      disponible: true,
    ),
  ];

  static const String _periodoActivo = 'SA26-2';

  Future<void> _cerrarSesion() async {
    await _auth.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return AndamiajeApp(
      items: _items,
      seleccionado: _seleccionada,
      onSeleccionar: (indice) => setState(() => _seleccionada = indice),
      rolEtiqueta: 'Docente',
      correoUsuario: _auth.emailActual,
      periodoActivo: _periodoActivo,
      onCerrarSesion: _cerrarSesion,
      contenido: _contenido(),
    );
  }

  /// Contenido de la sección seleccionada.
  ///
  /// **`switch` por TÍTULO y no por índice**, igual que el cPanel. El índice ata
  /// la rama a la POSICIÓN del ítem: insertar una sección en medio desplaza
  /// todas las siguientes y el `case 3` pasa a abrir otro panel sin que nada
  /// avise. Con el título, mover un ítem no cambia a dónde lleva.
  ///
  /// Es además lo que permite que `test/menu_alcanzable_test.dart` compruebe el
  /// contrato leyendo este archivo: compara las ramas `case 'X'` con las
  /// secciones que tienen `disponible: true`, y esa comparación sólo se puede
  /// hacer si las ramas nombran los títulos. Es la red que faltaba cuando R-22.
  Widget _contenido() {
    final item = _items[_seleccionada];

    switch (item.titulo) {
      case 'Mis aulas':
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: const PanelVacio(
            titulo: 'Todavía no tienes aulas asignadas',
            mensaje:
                'Cuando la coordinación del centro te asigne secciones, '
                'aparecerán aquí con su horario y su lista de estudiantes.',
            icono: Icons.class_outlined,
            nota:
                'Depende del módulo Currículo y Cuadrante, que está apagado. '
                'El Administrador Maestro lo activa desde su panel.',
          ),
        );

      case 'Mi horario':
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: MiHorarioPanel(),
        );

      case 'Material de apoyo':
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: const GestorDocumentalPanel(
            entityType: TipoEntidadArchivo.teacherGuide,
            subtitulo: 'Sube guías y material para tus estudiantes. Quedarán '
                'guardados en el almacenamiento del centro.',
          ),
        );

      default:
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: PanelVacio(
            titulo: item.titulo,
            mensaje: 'Esta sección está pendiente de construir.',
            icono: item.icono,
          ),
        );
    }
  }
}
