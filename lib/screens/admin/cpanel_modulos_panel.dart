import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/config_audit_entry.dart';
import '../../models/system_module.dart';
import '../../repositories/modulo_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';
import '../admin_dashboard.dart';

/// Módulo que da acceso a este mismo panel.
///
/// La base de datos impide apagarlo (trigger `proteger_modulo_critico`) y la API
/// también. La UI lo refleja bloqueando el interruptor y explicando por qué, en
/// vez de dejar que el usuario pulse y reciba un error.
const String claveModuloCpanel = 'm0_cpanel';

const Map<String, String> etiquetasRol = {
  'admin': 'Administrador',
  'docente': 'Docente',
  'estudiante': 'Estudiante',
};

/// Iconos por módulo.
///
/// Se declaran aquí y no se leen de `system_modules.icono` —que ya existe en la
/// base— porque ese campo guarda un nombre (`menu_book`) que hay que mapear a un
/// `IconData` de todos modos, y el mapeo a un `Map` constante permite que un
/// nombre desconocido tenga un icono por defecto en vez de romper el panel.
const Map<String, IconData> _iconosModulo = {
  'm0_cpanel': Icons.tune_outlined,
  'm1_onboarding': Icons.badge_outlined,
  'm2_curriculo': Icons.menu_book_outlined,
  'm3_cuadrante': Icons.calendar_month_outlined,
  'm4_inscripciones': Icons.how_to_reg_outlined,
  'm5_archivos': Icons.folder_open_outlined,
  'm6_asistencia': Icons.fact_check_outlined,
  'm7_calificaciones': Icons.grading_outlined,
  'm8_pasantias': Icons.work_outline,
};

/// Command Center de módulos.
///
/// Antes era una lista de filas con un `Switch` a la derecha: funcional, pero
/// obligaba a leer cada línea para saber qué estaba encendido. Ahora cada módulo
/// es una tarjeta con badge de estado, roles visibles y una cabecera que
/// identifica su categoría, de modo que el estado se reconoce de un vistazo.
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

  /// Cambios de configuración registrados hoy.
  ///
  /// Se pide en paralelo con los módulos y **no** es crítico: si falla, la
  /// tarjeta muestra 0 y el panel sigue usable. Convertir esta cifra en un
  /// requisito de carga haría que un problema en la tabla de auditoría dejara
  /// al administrador sin poder gestionar módulos, que es lo que de verdad ha
  /// venido a hacer.
  int _cambiosHoy = 0;

  /// Claves con una operación de guardado en curso. Mientras una clave está
  /// aquí, **sólo su** interruptor se sustituye por un indicador: el resto del
  /// panel sigue operable, porque el guardado de un módulo no debe bloquear el
  /// trabajo con los demás.
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

    // Las dos peticiones viajan juntas: la auditoría no se espera a que terminen
    // los módulos, así que no alarga la carga.
    final resultados = await Future.wait([
      _repo.obtenerModulos(),
      _repo.obtenerAuditoria(limite: 50),
    ]);
    if (!mounted) return;

    final resultadoModulos = resultados[0] as Result<List<SystemModule>>;
    final resultadoAuditoria = resultados[1] as Result<List<ConfigAuditEntry>>;

    setState(() {
      _cargando = false;
      switch (resultadoModulos) {
        case Success(value: final modulos):
          _modulos = modulos;
        case Failure(error: final fallo):
          _error = fallo.message;
      }

      // La auditoría es informativa: un fallo aquí no se propaga al panel.
      if (resultadoAuditoria case Success(value: final entradas)) {
        final hoy = DateTime.now();
        _cambiosHoy = entradas
            .where(
              (e) =>
                  e.creadoEn != null &&
                  e.creadoEn!.toLocal().year == hoy.year &&
                  e.creadoEn!.toLocal().month == hoy.month &&
                  e.creadoEn!.toLocal().day == hoy.day,
            )
            .length;
      }
    });
  }

  Future<void> _alternar(SystemModule modulo, bool habilitado) async {
    setState(() => _guardando.add(modulo.clave));

    final resultado = await _repo.alternarModulo(
      clave: modulo.clave,
      habilitado: habilitado,
    );

    // El estado de guardado se libera ANTES de comprobar `mounted`. Al revés,
    // un desmontaje durante la petición dejaría la clave en `_guardando` para
    // siempre y ese módulo mostraría un indicador de carga eterno.
    if (mounted) setState(() => _guardando.remove(modulo.clave));
    if (!mounted) return;

    switch (resultado) {
      case Success(value: final actualizado):
        // Sólo ahora se refleja el cambio: si el guardado falla, la tarjeta
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
          exito: actualizado.habilitado,
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

    if (mounted) setState(() => _guardando.remove(modulo.clave));
    if (!mounted) return;

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
          exito: true,
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
      child: _construirPanel(context),
    );
  }

  Widget _construirPanel(BuildContext context) {
    if (_modulos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: Text('No hay módulos registrados.')),
      );
    }

    final agrupados = ModuloRepository.agruparPorCategoria(_modulos);
    final activos = _modulos.where((m) => m.habilitado).length;
    final criticos = _modulos.where((m) => m.clave == claveModuloCpanel).length;

    // El contenido va dentro de su propio scrollable.
    //
    // No es decorativo: la lista de módulos crece con el catálogo, y este panel
    // se monta tanto en el `SingleChildScrollView` de `ContenidoSeccion`
    // (altura infinita, el caso normal) como en espacios de altura acotada
    // (una vista embebida, una prueba). Sin el `Scrollbar`+`ListView` propio,
    // la primera situación funciona y la segunda desborda; con él, las dos se
    // comportan igual y el panel no depende de quién lo aloja. Se elige
    // `shrinkWrap` para que, cuando la altura sí es infinita, la columna mida
    // sólo lo que mide su contenido en vez de reclamar todo el espacio.
    return ListView(
      shrinkWrap: true,
      // El scroll físico se desactiva cuando la altura es ilimitada: si no, el
      // `ListView` intentaría competir con el `SingleChildScrollView` exterior
      // y el gesto de rueda quedaría ambiguo entre los dos.
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        // --- Command Center: las cifras primero ----------------------------
        // Van arriba y no al final porque responden a «¿cómo está el sistema?»
        // antes de que el usuario tenga que buscar nada.
        MetricasModulos(
          total: _modulos.length,
          activos: activos,
          criticos: criticos,
          cambiosRecientes: _cambiosHoy,
        ),
        const SizedBox(height: 20),
        AvisoEnLinea(
          texto:
              'Al desactivar un módulo, su API deja de atender de inmediato y '
              'desaparece del menú de todos los usuarios. Cada cambio queda '
              'registrado en la auditoría con la fecha.',
        ),
        const SizedBox(height: 24),

        // --- Módulos, por categoría, en rejilla ----------------------------
        for (final entrada in agrupados.entries) ...[
          TituloSeccion(
            ModuloRepository.etiquetaCategoria(entrada.key),
            subtitulo: _subtituloCategoria(entrada.key),
          ),
          RejillaTarjetas(
            anchoMinimo: 320,
            children: [
              for (final modulo in entrada.value) _tarjetaDe(modulo),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ],
    );
  }

  Widget _tarjetaDe(SystemModule modulo) {
    final esCritico = modulo.clave == claveModuloCpanel;

    return TarjetaModulo(
      titulo: modulo.nombre,
      descripcion: modulo.descripcion,
      icono: _iconosModulo[modulo.clave] ?? Icons.widgets_outlined,
      estado: EstadoModulo.para(
        habilitado: modulo.habilitado,
        esCritico: esCritico,
      ),
      habilitado: modulo.habilitado,
      guardando: _guardando.contains(modulo.clave),
      rolesEtiquetas: [
        for (final rol in modulo.rolesPermitidos) etiquetasRol[rol] ?? rol,
      ],
      candadoRazon: esCritico
          ? 'Módulo crítico: da acceso a este panel. No puede desactivarse.'
          : null,
      onAlternar: esCritico ? null : (valor) => _alternar(modulo, valor),
      onEditarRoles: () => _editarRoles(modulo),
    );
  }

  /// Explica para qué sirve la categoría, no sólo cómo se llama.
  ///
  /// El nombre suelto («Académico») no ayuda a decidir dónde está un módulo; la
  /// frase sí.
  static String? _subtituloCategoria(String categoria) {
    switch (categoria) {
      case 'nucleo':
        return 'El núcleo del sistema. Sin esto no hay nada más.';
      case 'academico':
        return 'Currículo, horarios, inscripciones y asistencia.';
      case 'recursos':
        return 'Almacenamiento y material de apoyo.';
      case 'evaluacion':
        return 'Calificaciones y actas.';
      case 'avanzado':
        return 'Pasantías y procesos de egreso.';
      case 'operacion':
        return 'Parámetros operativos del centro.';
      default:
        return null;
    }
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
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sin ningún rol marcado, el módulo es visible para todos. '
              'Con roles marcados, sólo ellos lo ven.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 4),
            for (final rol in etiquetasRol.entries)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _seleccion.contains(rol.key),
                title: Text(
                  rol.value,
                  style: theme.textTheme.bodyMedium,
                ),
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
            if (_seleccion.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: AvisoEnLinea(
                  texto: 'Sin roles marcados: todos los usuarios verán este módulo.',
                  icono: Icons.public_outlined,
                ),
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
