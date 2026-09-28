import 'package:flutter/material.dart';

import '../core/gateways/aula_gateway.dart';
import '../models/archivo.dart';
import '../repositories/modulo_repository.dart';
import '../services/auth_service.dart';
import '../services/aula_service.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import '../widgets/modulos_del_menu.dart';
import 'docente/asistencia_qr_panel.dart';
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
/// Las secciones apagadas se muestran atenuadas y **no pulsables**, y su tooltip
/// explica por qué: así quien usa el panel entiende qué falta, en vez de
/// sospechar que la aplicación está rota.
///
/// Ese tooltip era **genérico** —«pendiente de construir»— y sobre
/// «Calificaciones» era, además, **falso**: calificar existe desde M6 y está a
/// un clic, dentro de cada aula (`aula_virtual_dashboard.dart`, botón
/// «Calificar» de cada tarea). El texto sale ahora de `ItemNavegacion.pendiente`
/// y para esa sección dice dónde está. Una sección gris sin explicación no se
/// distingue de una plataforma incompleta, y el docente que la mira concluye que
/// el sistema no califica.
class DocenteDashboardScreen extends StatefulWidget {
  const DocenteDashboardScreen({
    super.key,
    this.auth,
    this.aulaGateway,
    this.aulasPropias,
    this.modulos,
  });

  final AuthService? auth;

  /// De dónde sale el estado de `system_modules` que gobierna el menú.
  ///
  /// Opcional **sólo para las pruebas**, como el resto de puertas de este
  /// dashboard: en producción no se inyecta y se resuelve [ModuloRepository], que
  /// lee por PostgREST. Ver `lib/widgets/modulos_del_menu.dart` para por qué esa
  /// lectura la puede hacer un docente y no sólo un administrador.
  final ModuloRepository? modulos;

  /// La puerta del **contenido** del Aula Virtual (M6).
  ///
  /// Opcional **sólo para las pruebas**: en producción no se inyecta y el
  /// dashboard cae al servicio real (ver [_aulaContenido]). Se inyecta cuando una
  /// prueba quiere un doble en lugar de la red, o cuando quiere el listado **sin**
  /// aula abrible —para eso último basta con inyectar [aulasPropias] y dejar esta
  /// en `null`—.
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

class _DocenteDashboardScreenState extends State<DocenteDashboardScreen>
    with CargaDeModulos<DocenteDashboardScreen> {
  late final AuthService _auth = widget.auth ?? AuthService();

  /// El estado real de `system_modules`, para que el menú no afirme que hay una
  /// sección al otro lado cuando el administrador apagó su módulo.
  late final ModuloRepository _modulosRepo =
      widget.modulos ?? ModuloRepository();

  @override
  ModuloRepository get repositorioDeModulos => _modulosRepo;

  /// El listado de aulas de «Mis aulas».
  ///
  /// Cae al gateway de contenido cuando se inyecta —un [AulaGateway] **es** un
  /// [AulasPropiasGateway], así que vale como fuente del listado— y si no, a la
  /// implementación real contra `/mi-horario`.
  late final AulasPropiasGateway _aulasPropias =
      widget.aulasPropias ?? widget.aulaGateway ?? BackendAulaGateway();

  /// La puerta del **contenido** del aula que recibe `PanelMisAulas`.
  ///
  /// Es lo que hace que en producción —sin inyectar nada— la tarjeta del aula se
  /// pueda pulsar. **No es `widget.aulaGateway ?? BackendAulaGateway()`**: ver
  /// [resolverPuertaDeContenido], que explica por qué ese `??` rompería las
  /// pruebas de widget que piden un listado sin aula abrible.
  late final AulaGateway? _aulaContenido = resolverPuertaDeContenido(
    inyectada: widget.aulaGateway,
    listadoInyectado: widget.aulasPropias,
  );

  int _seleccionada = 0;

  static const List<ItemNavegacion> _items = [
    ItemNavegacion(
      icono: Icons.dashboard_outlined,
      titulo: 'Mis aulas',
      categoria: 'Control de aulas',
      modulo: 'm6_aula_virtual',
    ),
    ItemNavegacion(
      icono: Icons.fact_check_outlined,
      titulo: 'Asistencia',
      categoria: 'Control de aulas',
      disponible: true,
      modulo: 'm7_asistencia',
    ),
    // Apagada **y con motivo**, porque «pendiente de construir» aquí sería
    // falso: el libro de calificaciones existe desde M6 y se abre desde cada
    // aula. Lo que no hay es una sección suelta de notas, y crear una sería una
    // segunda puerta al mismo sitio. El texto lleva al docente a la que sí hay,
    // que es lo único que convierte un ítem gris en algo accionable.
    //
    // **Sin `modulo:`**, y es deliberado: encender `m7_calificaciones` no puede
    // encender esta sección porque no hay pantalla detrás. La bandera de aquí es
    // un hecho del código —no existe—, no del servidor, y atarla al módulo
    // prometería algo que el módulo no puede cumplir.
    ItemNavegacion(
      icono: Icons.grading_outlined,
      titulo: 'Calificaciones',
      categoria: 'Control de aulas',
      disponible: false,
      pendiente: 'Se califica dentro de cada aula. Abre Mis aulas, elige la '
          'sección y entra en Trabajo de Clase.',
    ),
    ItemNavegacion(
      icono: Icons.folder_open_outlined,
      titulo: 'Material de apoyo',
      categoria: 'Recursos',
      disponible: true,
      modulo: 'm5_archivos',
    ),
    ItemNavegacion(
      icono: Icons.calendar_month_outlined,
      titulo: 'Mi horario',
      categoria: 'Recursos',
      disponible: true,
      modulo: 'm3_cuadrante',
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
      // `menuConModulos` y no `_items`: el menú sale con el estado real de
      // `system_modules` aplicado encima, así que apagar `m6_aula_virtual` o
      // `m7_asistencia` desde el cPanel se refleja aquí en vez de llevar a un
      // 403.
      items: menuConModulos(_items),
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
  ///
  /// La lista que se consulta aquí es la **efectiva** —con los módulos
  /// aplicados—, no `_items`: si el administrador apaga un módulo mientras el
  /// docente está dentro de esa sección, el contenido tiene que dejar de
  /// pintarse. El menú ya no deja volver a pulsarla, pero quedarse dentro es
  /// posible, y pintar el panel de un módulo apagado haría parecer que el
  /// interruptor no sirvió.
  Widget _contenido() {
    final item = menuConModulos(_items)[_seleccionada];

    if (!item.disponible) {
      return ContenidoSeccion(
        migas: ['Inicio', item.categoria, item.titulo],
        child: PanelVacio(
          titulo: item.titulo,
          mensaje: item.pendiente ?? 'Esta sección no está disponible.',
          icono: item.icono,
        ),
      );
    }

    switch (item.titulo) {
      case 'Mis aulas':
        // El Aula Virtual (M6) es el destino de «Mis aulas». El listado de
        // secciones es real —sale de `/mi-horario`, la misma ruta que alimenta
        // «Mi horario»— y cada tarjeta abre el tablón y el trabajo de clase de
        // esa sección.
        //
        // `_aulaContenido` —y no `widget.aulaGateway`— es lo que hace que en
        // producción la tarjeta se pueda pulsar: sin inyectar nada resuelve el
        // servicio real, y con algo inyectado respeta lo que pidió la prueba.
        return PanelMisAulas(
          gateway: _aulasPropias,
          aulaGateway: _aulaContenido,
        );

      case 'Asistencia':
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: const AsistenciaQrPanel(),
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
