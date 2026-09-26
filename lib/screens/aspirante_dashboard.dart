import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/gateways/aula_gateway.dart';
import '../core/result.dart';
import '../models/archivo.dart';
import '../models/aspirante_model.dart';
import '../models/inscripcion.dart';
import '../repositories/aspirante_repository.dart';
import '../repositories/inscripcion_repository.dart';
import '../services/auth_service.dart';
import '../services/aula_service.dart';
import '../theme/inces_theme.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import 'aspirante/marcar_asistencia_panel.dart';
import 'gestor_documental_panel.dart';
import 'mis_aulas_panel.dart';

/// Panel del aspirante y del estudiante.
///
/// Sigue usando [AspiranteRepository], que devuelve `Result`. Un fallo de red se
/// muestra como error con reintento, **nunca** como "no tienes ficha": ése era
/// el bug que ocultaba datos, y es la razón de que los tres estados (cargando,
/// error, vacío) estén separados aquí.
///
/// El Módulo 4 (Inscripciones y Cupos) añade dos secciones disponibles: el
/// catálogo de ofertas y "Mis inscripciones". Ambas usan [InscripcionesRepository]
/// y respetan la regla de negocio del backend: si `ofertaVigente == true` el
/// asiento está en asignación y no se puede solicitar, **aunque** queden cupos
/// libres (es la "doble venta" que el diseño evita).
class AspiranteDashboardScreen extends StatefulWidget {
  const AspiranteDashboardScreen({
    super.key,
    this.repositorio,
    this.auth,
    this.aulaGateway,
    this.aulasPropias,
  });

  final AspiranteRepository? repositorio;
  final AuthService? auth;

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
  /// `GET /api/v1/mi-horario`: esa ruta **sí** está congelada y responde a los
  /// dos roles, así que el listado es real aunque el contenido no lo sea aún.
  final AulasPropiasGateway? aulasPropias;

  @override
  State<AspiranteDashboardScreen> createState() =>
      _AspiranteDashboardScreenState();
}

class _AspiranteDashboardScreenState extends State<AspiranteDashboardScreen> {
  late final AspiranteRepository _repo =
      widget.repositorio ?? AspiranteRepository();
  late final AuthService _auth = widget.auth ?? AuthService();
  final InscripcionesRepository _inscripciones = InscripcionesRepository();

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

  bool _cargando = true;
  AspiranteModel? _aspirante;
  String? _error;

  int _seleccionada = 0;

  static const List<ItemNavegacion> _items = [
    ItemNavegacion(
      icono: Icons.badge_outlined,
      titulo: 'Mi inscripción',
      categoria: 'Mi cuenta',
    ),
    ItemNavegacion(
      icono: Icons.explore_outlined,
      titulo: 'Ofertas de cupos',
      categoria: 'Académico',
    ),
    ItemNavegacion(
      icono: Icons.playlist_add_check_outlined,
      titulo: 'Mis inscripciones',
      categoria: 'Académico',
    ),
    // «Mis aulas» es la entrada al Aula Virtual (M6). Se enciende aquí porque
    // ya tiene su rama en el `switch` de `_contenido()`: un ítem encendido sin
    // rama abriría en blanco, y una rama sin el ítem encendido sería código
    // muerto (R-22). El listado sale de `/mi-horario` y el contenido del aula
    // del servicio real de M6: el módulo se enciende o se apaga desde el cPanel,
    // no desde este menú.
    ItemNavegacion(
      icono: Icons.class_outlined,
      titulo: 'Mis aulas',
      categoria: 'Académico',
    ),
    ItemNavegacion(
      icono: Icons.assignment_turned_in_outlined,
      titulo: 'Mis entregas',
      categoria: 'Académico',
      disponible: true,
    ),
    // M7 — el estudiante marca su asistencia tecleando o escaneando el QR.
    ItemNavegacion(
      icono: Icons.fact_check_outlined,
      titulo: 'Asistencia',
      categoria: 'Académico',
      disponible: true,
    ),
    // Se enciende al llegar la ruta de listado (D17). Lo que todavía **no**
    // puede mostrar es contenido: un estudiante no sabe qué `entidadId`
    // corresponde a las guías de su módulo hasta que el Aula Virtual (M6) ate
    // cada guía a una sección. El panel lo dice en pantalla, en vez de fingir una
    // lista vacía por no haber archivos.
    ItemNavegacion(
      icono: Icons.folder_open_outlined,
      titulo: 'Material de apoyo',
      categoria: 'Académico',
      disponible: true,
    ),
  ];

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

    final resultado = await _repo.obtenerMiFicha();

    // El estado de carga se libera antes del `return` por desmontaje: al revés,
    // un desmontaje durante la petición dejaría el indicador girando para
    // siempre en la siguiente visita a esta pantalla.
    if (mounted) setState(() => _cargando = false);
    if (!mounted) return;

    setState(() {
      switch (resultado) {
        case Success(value: final ficha):
          _aspirante = ficha;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

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
      rolEtiqueta: 'Estudiante',
      correoUsuario: _auth.emailActual,
      periodoActivo: 'SA26-2',
      onCerrarSesion: _cerrarSesion,
      contenido: _contenido(),
    );
  }

  /// Contenido de la sección seleccionada.
  ///
  /// **`switch` por TÍTULO y no por índice**, igual que el cPanel. Estaba por
  /// índice, y eso ata la rama a la POSICIÓN del ítem: al insertar «Mis
  /// entregas» antes de «Material de apoyo», `case 4` habría pasado a abrir una
  /// sección distinta sin que nada avisara. Con el título, insertar o mover un
  /// ítem no cambia a dónde lleva.
  ///
  /// Es además lo que permite que `test/menu_alcanzable_test.dart` compruebe el
  /// contrato leyendo este archivo. Es la red que faltaba cuando R-22.
  Widget _contenido() {
    final item = _items[_seleccionada];

    switch (item.titulo) {
      case 'Mi inscripción':
        return _panelMiInscripcion();

      case 'Ofertas de cupos':
        return PanelOfertas(repositorio: _inscripciones);

      case 'Mis inscripciones':
        return PanelMisInscripciones(repositorio: _inscripciones);

      case 'Mis aulas':
        // Aula Virtual (M6): el listado de secciones viene de `/mi-horario`
        // —ruta congelada desde M3, una fila por sección— y cada tarjeta abre
        // el tablón y el trabajo de clase de esa sección, con el gestor
        // documental incrustado para subir las entregas.
        //
        // `_aulaContenido` —y no `widget.aulaGateway`— es lo que hace que en
        // producción la tarjeta se pueda pulsar: sin inyectar nada resuelve el
        // servicio real, y con algo inyectado respeta lo que pidió la prueba.
        return PanelMisAulas(
          gateway: _aulasPropias,
          aulaGateway: _aulaContenido,
        );

      case 'Mis entregas':
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: const GestorDocumentalPanel(
            entityType: TipoEntidadArchivo.taskSubmission,
            subtitulo: 'Sube aquí los trabajos que te pida el docente.',
          ),
        );

      // (M7) El estudiante marca su asistencia tecleando el código del QR.
      case 'Asistencia':
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: const MarcarAsistenciaPanel(),
        );

      case 'Material de apoyo':
        // Sin `entidadId`: todavía no hay una guía concreta que pedir, porque
        // M6 no ha creado la tabla que las sostiene. El panel funciona en modo
        // sólo-subida y lo explica en pantalla. Se monta igualmente para que el
        // día que M6 exista sólo haya que pasarle el id.
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: const GestorDocumentalPanel(
            entityType: TipoEntidadArchivo.teacherGuide,
            titulo: 'Material de apoyo',
            subtitulo: 'Las guías y el material que publique tu docente.',
          ),
        );

      default:
        // Secciones aún no construidas: se muestran atenuadas en el menú y, si
        // alguien llega aquí, un panel vacío que explica por qué.
        return ContenidoSeccion(
          migas: ['Inicio', item.categoria, item.titulo],
          child: PanelVacio(
            titulo: item.titulo,
            mensaje: 'Esta sección se habilitará cuando tu curso esté activo.',
            icono: item.icono,
          ),
        );
    }
  }

  Widget _panelMiInscripcion() {
    return ContenidoSeccion(
      migas: const ['Inicio', 'Mi cuenta', 'Mi inscripción'],
      child: _cargando
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
              ? _panelError(_error!)
              : _aspirante == null
                  ? _panelVacio()
                  : _panelFicha(_aspirante!),
    );
  }

  Widget _panelError(String mensaje) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 30,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No pudimos cargar tu ficha',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelVacio() {
    return const PanelVacio(
      titulo: 'Tu inscripción está en revisión',
      mensaje:
          'Cuando el centro formativo apruebe tu solicitud verás aquí tu curso '
          'y tu estado.',
      icono: Icons.pending_actions_outlined,
      nota:
          'Recibirás un correo cuando tu inscripción sea confirmada. Si no '
          'llega, revisa la carpeta de spam: el envío depende del dominio de '
          'correo configurado por el centro.',
    );
  }

  Widget _panelFicha(AspiranteModel aspirante) {
    final theme = Theme.of(context);

    // D14: el nombre del programa ya no vive en la ficha —la columna se eliminó
    // y quedó `program_id` con clave foránea—, así que llega resuelto por JOIN
    // desde `miFicha()` (`select('*, programs(name)')`).
    //
    // `programaNombre` es nulo en cualquier ruta que no pida la relación
    // incrustada, y por eso hay respaldo: un nombre ausente no debe romper la
    // ficha, pero tampoco debe pasar por «no eligió nada».
    final nombrePrograma = aspirante.programaNombre;
    final curso = nombrePrograma == null || nombrePrograma.isEmpty
        ? 'Por asignar'
        : nombrePrograma;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tarjeta de identidad con la cabecera de marca. Es la versión de
        // «perfil» del lenguaje visual que usan las tarjetas de módulo.
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 6,
                decoration: const BoxDecoration(
                  gradient: IncesTheme.degradadoMarca,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Text(
                        _iniciales(aspirante),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${aspirante.nombres} ${aspirante.apellidos}'
                                .trim(),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: IncesTheme.advertencia
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'En revisión',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: IncesTheme.advertencia,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TituloSeccion('Datos de la solicitud'),
                _FilaDato(etiqueta: 'Cédula', valor: aspirante.cedula),
                _FilaDato(etiqueta: 'Nombres', valor: aspirante.nombres),
                _FilaDato(etiqueta: 'Apellidos', valor: aspirante.apellidos),
                _FilaDato(
                  etiqueta: 'Curso solicitado',
                  valor: curso,
                  esUltima: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Iniciales para el avatar. Si no hay nombre, cae a un icono genérico.
  static String _iniciales(AspiranteModel aspirante) {
    final nombre = aspirante.nombres.trim();
    final apellido = aspirante.apellidos.trim();

    final a = nombre.isEmpty ? '' : nombre[0];
    final b = apellido.isEmpty ? '' : apellido[0];

    final combinadas = '$a$b'.toUpperCase();
    return combinadas.isEmpty ? '?' : combinadas;
  }
}

/// Catálogo de ofertas de cupo del estudiante (Módulo 4, capa estudiante).
///
/// Regla de negocio visible en la UI: si `ofertaVigente == true` el asiento está
/// en asignación automática y el botón "Inscribirme" queda deshabilitado con la
/// etiqueta "Asiento en asignación", **aunque** `cuposDisponibles > 0`. No se
/// puede "robar" un cupo que el backend está asignando a quien viene de la cola.
class PanelOfertas extends StatefulWidget {
  const PanelOfertas({super.key, required this.repositorio});

  final InscripcionesRepository repositorio;

  @override
  State<PanelOfertas> createState() => _PanelOfertasState();
}

class _PanelOfertasState extends State<PanelOfertas> {
  bool _cargando = true;
  String? _error;
  List<OcupacionSeccion> _secciones = const [];
  final Set<String> _inscribiendo = {};

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

    final resultado = await widget.repositorio.obtenerOfertas();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final secciones):
          _secciones = secciones;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _inscribirse(OcupacionSeccion o) async {
    setState(() => _inscribiendo.add(o.seccionId));
    final resultado = await widget.repositorio.inscribirse(o.seccionId);
    if (!mounted) return;
    setState(() => _inscribiendo.remove(o.seccionId));

    resultado.when(
      success: (estado) {
        mostrarAviso(
          context,
          'Solicitud enviada. Estado: ${_etiquetaEstado(estado)}.',
          exito: true,
        );
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContenidoSeccion(
      migas: const ['Inicio', 'Académico', 'Ofertas de cupos'],
      child: EstadoPanel(
        cargando: _cargando,
        error: _error,
        onReintentar: _cargar,
        child: _contenido(),
      ),
    );
  }

  Widget _contenido() {
    if (_secciones.isEmpty) {
      return const PanelVacio(
        titulo: 'No hay secciones abiertas',
        mensaje:
            'Cuando el centro formativo habilite secciones con cupo las '
            'verás listadas aquí, con su disponibilidad en tiempo real.',
        icono: Icons.explore_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Ofertas de cupos',
          subtitulo: '${_secciones.length} sección(es) en este período.',
          acciones: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const AvisoEnLinea(
          texto:
              'Si una sección dice «Asiento en asignación» no puedes pedirla: '
              'el sistema está dando ese cupo a quien viene de la lista de '
              'espera, aunque aparezcan cupos libres. Vuelve a mirar más tarde.',
          icono: Icons.hourglass_empty_outlined,
          tono: TonoAviso.info,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in _secciones) _tarjetaOferta(o),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tarjetaOferta(OcupacionSeccion o) {
    final theme = Theme.of(context);
    final enAsignacion = o.ofertaVigente;
    final conCupo = o.cuposDisponibles > 0;
    final puedeInscribirse = !enAsignacion && conCupo;
    final ocupado = _inscribiendo.contains(o.seccionId);

    final titulo = o.materiaNombre ?? o.nombre;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (o.programaNombre != null) o.programaNombre!,
                      o.periodo,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Etiqueta(texto: 'Cupo ${o.resumenCupo}'),
                      Etiqueta(
                        texto: conCupo
                            ? '${o.cuposDisponibles} disponible(s)'
                            : 'Sin cupos',
                      ),
                      if (enAsignacion)
                        const Etiqueta(
                          texto: 'Asiento en asignación',
                          destacada: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (enAsignacion)
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.hourglass_empty_outlined, size: 16),
                label: const Text('Asiento en\nasignación'),
              )
            else if (puedeInscribirse)
              FilledButton.icon(
                onPressed: ocupado ? null : () => _inscribirse(o),
                icon: ocupado
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_outlined, size: 16),
                label: Text(ocupado ? 'Enviando…' : 'Inscribirme'),
              )
            else
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.block_outlined, size: 16),
                label: const Text('Sin cupos'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Mis inscripciones" del estudiante (Módulo 4, capa estudiante).
///
/// Honra el ciclo de estados: `WAITLISTED` (en cola, muestra `posicionEnCola` y
/// permite renunciar), `PENDING_BID` (oferta en el aire, muestra cuenta regresiva
/// desde `ofertaVenceEn` y permite aceptar o renunciar) y `ENROLLED` (adentro).
class PanelMisInscripciones extends StatefulWidget {
  const PanelMisInscripciones({super.key, required this.repositorio});

  final InscripcionesRepository repositorio;

  @override
  State<PanelMisInscripciones> createState() => _PanelMisInscripcionesState();
}

class _PanelMisInscripcionesState extends State<PanelMisInscripciones> {
  bool _cargando = true;
  String? _error;
  List<InscripcionDetallada> _inscripciones = const [];
  final Set<String> _actuando = {};

  /// Refresca la cuenta regresiva de las ofertas `PENDING_BID` una vez por
  /// segundo. Solo provoca `setState` (re-pinta); no vuelve a pedir datos.
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _cargar();
    _temporizador = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final resultado = await widget.repositorio.obtenerMisInscripciones();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final lista):
          _inscripciones = lista;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _aceptar(InscripcionDetallada i) async {
    setState(() => _actuando.add(i.seccionId));
    final resultado = await widget.repositorio.aceptarOferta(i.seccionId);
    if (!mounted) return;
    setState(() => _actuando.remove(i.seccionId));

    resultado.when(
      success: (_) {
        mostrarAviso(context, '¡Cupo aceptado! Ya tienes tu asiento.', exito: true);
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  Future<void> _renunciar(InscripcionDetallada i) async {
    setState(() => _actuando.add(i.seccionId));
    final resultado = await widget.repositorio.renunciar(i.seccionId);
    if (!mounted) return;
    setState(() => _actuando.remove(i.seccionId));

    resultado.when(
      success: (_) {
        mostrarAviso(context, 'Renunciaste a este cupo.', exito: true);
        _cargar();
      },
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContenidoSeccion(
      migas: const ['Inicio', 'Académico', 'Mis inscripciones'],
      child: EstadoPanel(
        cargando: _cargando,
        error: _error,
        onReintentar: _cargar,
        child: _contenido(),
      ),
    );
  }

  Widget _contenido() {
    if (_inscripciones.isEmpty) {
      return const PanelVacio(
        titulo: 'Aún no tienes inscripciones',
        mensaje:
            'Cuando solicites un cupo —o el sistema te asigne uno desde la '
            'lista de espera— lo verás aquí, con su estado en tiempo real.',
        icono: Icons.playlist_add_check_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Mis inscripciones',
          subtitulo: '${_inscripciones.length} inscripción(es).',
          acciones: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in _inscripciones) _tarjetaInscripcion(i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tarjetaInscripcion(InscripcionDetallada i) {
    final theme = Theme.of(context);
    final ocupado = _actuando.contains(i.seccionId);
    final titulo = i.materiaNombre ?? i.seccionNombre;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      Text(titulo, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        [if (i.programaNombre != null) i.programaNombre!, i.periodo]
                            .join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _InsigniaEstado(i.estado),
              ],
            ),
            const SizedBox(height: 12),

            // Contexto específico por estado.
            if (i.estado.enCola) ...[
              if (i.posicionEnCola != null)
                Etiqueta(texto: 'Lugar ${i.posicionEnCola} en la cola')
              else
                const Etiqueta(texto: 'En lista de espera'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _renunciar(i),
                  icon: ocupado
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.exit_to_app_outlined, size: 16),
                  label: Text(ocupado ? 'Renunciando…' : 'Renunciar'),
                ),
              ),
            ] else if (i.estado.esOfertaViva) ...[
              _CuentaRegresiva(ofertaVenceEn: i.ofertaVenceEn),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: ocupado ? null : () => _renunciar(i),
                    icon: const Icon(Icons.exit_to_app_outlined, size: 16),
                    label: const Text('Renunciar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: ocupado ? null : () => _aceptar(i),
                    icon: ocupado
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(ocupado ? 'Aceptando…' : 'Aceptar cupo'),
                  ),
                ],
              ),
            ] else if (i.estado.estaAdentro) ...[
              const AvisoEnLinea(
                texto: 'Tienes tu asiento confirmado en esta sección.',
                icono: Icons.check_circle_outline,
                tono: TonoAviso.exito,
              ),
            ] else ...[
              // DROPPED: se conserva la fila como historial, sin acción.
              const AvisoEnLinea(
                texto: 'Renunciaste a este cupo. La fila se conserva como '
                    'historial.',
                icono: Icons.info_outline,
                tono: TonoAviso.info,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Insignia de color del estado de una inscripción.
class _InsigniaEstado extends StatelessWidget {
  const _InsigniaEstado(this.estado);

  final EstadoInscripcion estado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, texto, icono) = switch (estado) {
      EstadoInscripcion.enrolled =>
        (IncesTheme.exito, 'Matriculado', Icons.check_circle_outline),
      EstadoInscripcion.waitlisted =>
        (IncesTheme.advertencia, 'En cola', Icons.people_outline),
      EstadoInscripcion.pendingBid => (
        theme.colorScheme.primary,
        'Oferta en el aire',
        Icons.local_offer_outlined,
      ),
      EstadoInscripcion.dropped => (
        theme.colorScheme.onSurfaceVariant,
        'Renunciado',
        Icons.do_not_disturb_on_outlined,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuenta regresiva para una oferta `PENDING_BID`.
///
/// `ofertaVenceEn` viene en ISO 8601. Si no se puede parsear, se muestra la
/// fecha tal cual: la regla de negocio (caducidad) vive en el backend; aquí solo
/// informamos.
class _CuentaRegresiva extends StatelessWidget {
  const _CuentaRegresiva({required this.ofertaVenceEn});

  final String? ofertaVenceEn;

  @override
  Widget build(BuildContext context) {
    final vence = ofertaVenceEn == null
        ? null
        : DateTime.tryParse(ofertaVenceEn!);

    if (vence == null) {
      return AvisoEnLinea(
        texto: 'Tienes una oferta de cupo. Acepta antes de que venza.',
        icono: Icons.local_offer_outlined,
        tono: TonoAviso.advertencia,
      );
    }

    final restante = vence.difference(DateTime.now());
    final vencida = restante.isNegative;

    final texto = vencida
        ? 'Esta oferta ya venció.'
        : 'Oferta por ${_formatoHumano(restante)}. Acepta antes de que venza.';

    return AvisoEnLinea(
      texto: texto,
      icono: vencida ? Icons.timer_off_outlined : Icons.timer_outlined,
      tono: vencida ? TonoAviso.peligro : TonoAviso.advertencia,
    );
  }

  /// «2 h 5 min», «3 min 12 s», «45 s». Omite partes en cero salvo la última.
  static String _formatoHumano(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    final horas = total.inHours;
    final minutos = total.inMinutes.remainder(60);
    final segundos = total.inSeconds.remainder(60);

    if (horas > 0) return '$horas h ${minutos.toString().padLeft(2, '0')} min';
    if (minutos > 0) return '$minutos min ${segundos.toString().padLeft(2, '0')} s';
    return '$segundos s';
  }
}

/// Etiqueta en español de un estado, para los avisos de acción.
String _etiquetaEstado(EstadoInscripcion estado) => switch (estado) {
      EstadoInscripcion.enrolled => 'Matriculado',
      EstadoInscripcion.waitlisted => 'En lista de espera',
      EstadoInscripcion.pendingBid => 'Oferta en el aire',
      EstadoInscripcion.dropped => 'Renunciado',
    };

/// Fila de dato etiqueta/valor.
class _FilaDato extends StatelessWidget {
  const _FilaDato({
    required this.etiqueta,
    required this.valor,
    this.esUltima = false,
  });

  final String etiqueta;
  final String valor;
  final bool esUltima;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ancho mínimo de la etiqueta: sin él, «Cédula» y «Curso
              // solicitado» dejan los valores desalineados entre filas y la
              // lectura en columna se pierde.
              SizedBox(
                width: 150,
                child: Text(
                  etiqueta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  valor.isEmpty ? '—' : valor,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (!esUltima) const Divider(height: 1),
      ],
    );
  }
}
