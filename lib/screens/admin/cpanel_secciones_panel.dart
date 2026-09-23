import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/seccion.dart';
import '../../repositories/secciones_repository.dart';
import '../../widgets/comunes.dart';

/// Panel de CRUD de secciones (Módulo 4: Inscripciones y Cupos).
///
/// El catálogo es la base de todo lo demás: sin secciones no hay cupos que
/// gestionar. Aquí el administrador da de alta los grupos del lapso
/// (programa + materia + nombre corto + capacidad) y archiva los que ya no
/// se ofrecen. El archivado es reversible (PATCH con `activa: true`); no
/// hay borrado, porque una sección borrada se llevaría el historial de
/// inscripciones.
///
/// Los formularios piden IDs en crudo (`programaId`, `materiaId`) en vez
/// de desplegables. Es deliberado: el centro aún no carga el catálogo
/// completo de programas y materias con permisos de admin (R-17, R-18), y
/// derivar nombres del id en una entrada manual ahorra una pantalla que
/// terminaría vacía la mitad del tiempo. El wire a catálogos ricos queda
/// pendiente del cierre de esos dos riesgos.
class CpanelSeccionesPanel extends StatefulWidget {
  const CpanelSeccionesPanel({super.key, this.repositorio});

  final SeccionesRepository? repositorio;

  @override
  State<CpanelSeccionesPanel> createState() => _CpanelSeccionesPanelState();
}

class _CpanelSeccionesPanelState extends State<CpanelSeccionesPanel> {
  late final SeccionesRepository _repo =
      widget.repositorio ?? SeccionesRepository();

  PaginaSecciones _pagina = const PaginaSecciones(
    secciones: [],
    total: 0,
    limite: 50,
    desplazamiento: 0,
  );
  bool _cargando = true;
  String? _error;

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
    final resultado = await _repo.listarSecciones();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final pagina):
          _pagina = pagina;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _abrirCrear() async {
    final creada = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoCrearSeccion(repo: _repo),
    );
    if (creada == true && mounted) _cargar();
  }

  Future<void> _archivar(Seccion s) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archivar sección'),
        content: Text(
          '«${s.nombre}» quedará archivada y dejará de aceptar '
          'inscripciones nuevas. No se pierde el historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirma != true) return;

    final resultado = await _repo.actualizarSeccion(
      s.id,
      const CambiosSeccion(activa: false),
    );
    if (!mounted) return;
    resultado.when(
      success: (_) => _cargar(),
      failure: (fallo) =>
          mostrarAviso(context, fallo.message, error: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Secciones',
          subtitulo: 'Catálogo de grupos del lapso. Archivar retira la '
              'sección del catálogo sin perder su historial.',
          acciones: [
            FilledButton.icon(
              onPressed: _abrirCrear,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nueva sección'),
            ),
          ],
        ),
        Expanded(
          child: EstadoPanel(
            cargando: _cargando,
            error: _error,
            onReintentar: _cargar,
            child: _cuerpo(),
          ),
        ),
      ],
    );
  }

  Widget _cuerpo() {
    if (_pagina.secciones.isEmpty) {
      return const PanelVacio(
        titulo: 'No hay secciones registradas',
        mensaje: 'Cuando el centro registre las secciones del lapso, las '
            'verás aquí con su capacidad y su estado de archivado.',
        icono: Icons.explore_outlined,
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Total: ${_pagina.total}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in _pagina.secciones) _filaSeccion(s),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaSeccion(Seccion s) {
    final theme = Theme.of(context);
    final cupo = s.cupoMaximo == null
        ? 'Cupo: global'
        : s.cupoMaximo == 0
            ? 'Cupo: sin cupos'
            : 'Cupo: ${s.cupoMaximo}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.nombre,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lapso ${s.periodo} · programa ${_corto(s.programaId)} '
                    '· materia ${_corto(s.materiaId)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Etiqueta(texto: cupo),
                      Etiqueta(
                        texto: s.activa ? 'Activa' : 'Archivada',
                        destacada: !s.activa,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: s.activa ? 'Archivar' : 'Reactivar',
              icon: Icon(
                s.activa
                    ? Icons.archive_outlined
                    : Icons.unarchive_outlined,
                size: 20,
              ),
              onPressed: s.activa ? () => _archivar(s) : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Acorta un UUID a algo legible: los primeros 8 caracteres. Suficiente
  /// para distinguir secciones sin saturar la fila.
  String _corto(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);
}

/// Diálogo para crear una sección.
///
/// Pide los identificadores en crudo porque el catálogo con desplegables
/// depende de R-17/R-18 (fechas del lapso e inventario de aulas), aún
/// pendientes. Mantener la entrada manual ahora evita construir una pantalla
/// que va a quedar vacía la mitad del tiempo.
class _DialogoCrearSeccion extends StatefulWidget {
  const _DialogoCrearSeccion({required this.repo});

  final SeccionesRepository repo;

  @override
  State<_DialogoCrearSeccion> createState() => _DialogoCrearSeccionState();
}

class _DialogoCrearSeccionState extends State<_DialogoCrearSeccion> {
  final _forma = GlobalKey<FormState>();
  final _programa = TextEditingController();
  final _materia = TextEditingController();
  final _periodo = TextEditingController(text: 'SA26-2');
  final _nombre = TextEditingController();
  final _cupo = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _programa.dispose();
    _materia.dispose();
    _periodo.dispose();
    _nombre.dispose();
    _cupo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_forma.currentState!.validate()) return;

    final cupoTexto = _cupo.text.trim();
    int? cupoMaximo;
    if (cupoTexto.isNotEmpty) {
      cupoMaximo = int.tryParse(cupoTexto);
      if (cupoMaximo == null || cupoMaximo < 0) {
        setState(() => _error = 'El cupo debe ser un entero ≥ 0, o vacío.');
        return;
      }
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = await widget.repo.crearSeccion(Seccion.crear(
      programaId: _programa.text.trim(),
      materiaId: _materia.text.trim(),
      periodo: _periodo.text.trim(),
      nombre: _nombre.text.trim(),
      cupoMaximo: cupoMaximo,
    ));
    if (!mounted) return;

    resultado.when(
      success: (_) => Navigator.of(context).pop(true),
      failure: (fallo) => setState(() {
        _guardando = false;
        _error = fallo.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva sección'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _forma,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _campo(_programa, 'ID de programa', validadorUuid: true),
                const SizedBox(height: 10),
                _campo(_materia, 'ID de materia', validadorUuid: true),
                const SizedBox(height: 10),
                _campo(
                  _periodo,
                  'Código de lapso (p. ej. SA26-2)',
                  validadorNoVacio: true,
                  validadorLargoMax: 10,
                ),
                const SizedBox(height: 10),
                _campo(
                  _nombre,
                  'Nombre corto (≤ 5 caracteres)',
                  validadorNoVacio: true,
                  validadorLargoMax: 5,
                ),
                const SizedBox(height: 10),
                _campo(
                  _cupo,
                  'Cupo (vacío = cupo global del centro)',
                  esCupo: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AvisoEnLinea(
                    texto: _error!,
                    icono: Icons.error_outline,
                    tono: TonoAviso.peligro,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Creando…' : 'Crear sección'),
        ),
      ],
    );
  }

  Widget _campo(
    TextEditingController controlador,
    String etiqueta, {
    bool validadorUuid = false,
    bool validadorNoVacio = false,
    int? validadorLargoMax,
    bool esCupo = false,
  }) {
    return TextFormField(
      controller: controlador,
      decoration: InputDecoration(
        labelText: etiqueta,
        isDense: true,
      ),
      validator: (v) {
        final s = v?.trim() ?? '';
        if (validadorNoVacio && s.isEmpty) return 'Obligatorio.';
        if (validadorLargoMax != null && s.length > validadorLargoMax) {
          return 'Máximo $validadorLargoMax caracteres.';
        }
        if (validadorUuid && !_esUuidLargo(s)) return 'Identificador inválido.';
        if (esCupo && s.isNotEmpty && (int.tryParse(s) == null || int.parse(s) < 0)) {
          return 'Cupo debe ser un entero ≥ 0, o vacío.';
        }
        return null;
      },
    );
  }

  /// Un UUID válido mide 36 caracteres. No exigimos formato exacto, sólo
  /// una longitud razonable para no dejar pasar un texto cualquiera.
  bool _esUuidLargo(String s) => s.length >= 8;
}