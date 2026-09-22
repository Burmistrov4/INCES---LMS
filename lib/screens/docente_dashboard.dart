import 'package:flutter/material.dart';

import '../core/gateways/aula_gateway.dart';
import '../models/archivo.dart';
import '../services/auth_service.dart';
import '../services/aula_service.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import 'gestor_documental_panel.dart';
import 'mi_horario_panel.dart';
import 'mis_aulas_panel.dart';

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
  const DocenteDashboardScreen({
    super.key,
    this.auth,
    this.aulaGateway,
    this.aulasPropias,
  });

  final AuthService? auth;

  /// La puerta del **contenido** del Aula Virtual (M6).
  ///
  /// Opcional a propósito: el JSON del contenido de M6 todavía no está cerrado
  /// (ver `lib/core/gateways/aula_gateway.dart`), así que hoy sólo la implementa
  /// el doble de pruebas. Se inyecta en las pruebas de widget; sin ella, el
  /// listado de «Mis aulas» sigue siendo real y lo explica en pantalla en vez de
  /// abrir un aula que no puede cargar nada.
  final AulaGateway? aulaGateway;

  /// De dónde sale el listado de secciones de «Mis aulas».
  ///
  /// Opcional para las pruebas. Sin él se usa [BackendAulaGateway], que lee
  /// `GET /api/v1/mi-horario`: es la misma ruta que alimenta «Mi horario», y
  /// para un docente trae sus secciones además de sus guardias. Las guardias
  /// **no** se listan como aulas: una guardia es una presencia de custodia, no
  /// una clase con tablón ni trabajo de clase.
  final AulasPropiasGateway? aulasPropias;

  @override
  State<DocenteDashboardScreen> createState() => _DocenteDashboardScreenState();
}

class _DocenteDashboardScreenState extends State<DocenteDashboardScreen> {
  late final AuthService _auth = widget.auth ?? AuthService();

  /// El listado de aulas de «Mis aulas».
  ///
  /// Cae al gateway de contenido cuando se inyecta —un [AulaGateway] **es** un
  /// [AulasPropiasGateway], así que vale como fuente del listado— y si no, a la
  /// implementación real contra `/mi-horario`.
  late final AulasPropiasGateway _aulasPropias =
      widget.aulasPropias ?? widget.aulaGateway ?? BackendAulaGateway();

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
        // El Aula Virtual (M6) es el destino de «Mis aulas». El listado de
        // secciones es real —sale de `/mi-horario`, la misma ruta que alimenta
        // «Mi horario»— y cada tarjeta abre el tablón y el trabajo de clase de
        // esa sección. El contenido del aula todavía no tiene servicio HTTP,
        // así que sólo se inyecta en pruebas.
        return PanelMisAulas(
          gateway: _aulasPropias,
          aulaGateway: widget.aulaGateway,
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
