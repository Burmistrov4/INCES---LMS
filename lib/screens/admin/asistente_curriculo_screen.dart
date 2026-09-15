import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/gateways/curriculo_gateway.dart';
import '../../core/reglas_curriculo.dart';
import '../../models/materia.dart';
import '../../models/pensum.dart';
import '../../models/programa.dart';
import '../../repositories/curriculo_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// «1 materia» y «2 materias», no «1 materias».
///
/// Un pensum de curso libre casi siempre tiene una sola materia, así que el
/// singular no es un caso raro: es el habitual.
String _plural(int cantidad, String singular, String plural) =>
    '$cantidad ${cantidad == 1 ? singular : plural}';

/// Asistente de currículo y pensum (Módulo 2).
///
/// Crea un programa académico con su pensum en tres pasos, o reemplaza el
/// pensum de uno existente. Los dos caminos comparten el constructor de pensum
/// a propósito: duplicarlo sería la forma más rápida de que los dos se
/// desviaran.
///
/// **La creación es una sola operación, no tres.** El backend la ejecuta dentro
/// de una transacción (`crear_programa_con_pensum`), así que un fallo a mitad no
/// deja un programa a medio armar. El asistente acumula el estado en memoria y
/// sólo escribe al final, en el paso 3: no hay un «programa en borrador» que
/// limpiar si el administrador cierra la pestaña.
///
/// ## Por qué el paso 1 se puede saltar en modo edición
///
/// El código y el tipo de un programa **no se pueden cambiar**: son su
/// identidad, y `sections` (M3) apunta a él. Ofrecer un paso de datos que no
/// puede escribir nada sería un paso decorativo, así que en modo edición el
/// asistente empieza directamente en el pensum.
class AsistenteCurriculoScreen extends StatefulWidget {
  const AsistenteCurriculoScreen({
    super.key,
    this.repositorio,
    this.detalleInicial,
  });

  final CurriculoRepository? repositorio;

  /// Si viene, el asistente trabaja sobre un programa existente y guarda con
  /// `reemplazarPensum` en vez de crear.
  final DetallePrograma? detalleInicial;

  bool get esEdicion => detalleInicial != null;

  @override
  State<AsistenteCurriculoScreen> createState() =>
      _AsistenteCurriculoScreenState();
}

class _AsistenteCurriculoScreenState extends State<AsistenteCurriculoScreen> {
  late final CurriculoRepository _repo =
      widget.repositorio ?? CurriculoRepository();

  // --- Paso 1: datos del programa ------------------------------------------
  final _formKeyDatos = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  TipoPrograma _tipo = TipoPrograma.carrera;
  bool _requierePasantia = false;
  bool _publicar = true;

  // --- Paso 2: pensum -------------------------------------------------------
  /// Borrador del pensum. Vive en memoria hasta el paso 3: el backend recibe el
  /// estado final completo, no una secuencia de cambios.
  final List<EntradaPensum> _pensum = [];

  /// Datos de las materias ya elegidas, para poder pintar el nombre sin volver
  /// a consultar el banco. La clave es el identificador de la materia.
  final Map<String, Materia> _catalogo = {};

  /// Período al que se añaden las materias nuevas.
  int _periodoDestino = 1;

  /// Último período ofrecido. No se inventan períodos: el pensum de un curso
  /// libre suele tener uno, y el de una carrera, los que el administrador
  /// declare.
  int _topePeriodos = 1;

  // --- Banco de materias ----------------------------------------------------
  final _busquedaCtrl = TextEditingController();
  List<Materia> _materias = const [];
  int _totalMaterias = 0;
  bool _cargandoMaterias = false;
  String? _errorMaterias;
  Timer? _debounce;

  // --- Guardado -------------------------------------------------------------
  bool _guardando = false;
  String? _errorGuardar;

  /// El paso visible. Se indexa sobre [_indicesPasos], no sobre 0..2, porque en
  /// modo edición la lista de pasos es más corta.
  int _posicion = 0;

  List<int> get _indicesPasos =>
      widget.esEdicion ? const [1, 2] : const [0, 1, 2];

  int get _paso => _indicesPasos[_posicion];

  /// El pensum está bloqueado cuando hay secciones activas del período vigente
  /// usando el programa. Es la Regla 2 del backend, materializada en `editable`:
  /// la interfaz deshabilita antes de que el usuario choque contra el `409`.
  bool get _bloqueado => widget.detalleInicial?.editable == false;

  static final TextInputFormatter _mayusculas =
      TextInputFormatter.withFunction(
    (_, nuevo) => nuevo.copyWith(text: nuevo.text.toUpperCase()),
  );


  @override
  void initState() {
    super.initState();

    final detalle = widget.detalleInicial;
    if (detalle != null) {
      _codigoCtrl.text = detalle.programa.codigo;
      _nombreCtrl.text = detalle.programa.nombre;
      _tipo = detalle.programa.tipo;
      _requierePasantia = detalle.programa.requierePasantia;
      _publicar = detalle.programa.activo;

      for (final grupo in detalle.pensum) {
        for (final materia in grupo.materias) {
          _pensum.add(
            EntradaPensum(materiaId: materia.materiaId, periodo: materia.periodo),
          );
          _catalogo[materia.materiaId] = Materia(
            id: materia.materiaId,
            codigo: materia.codigo,
            nombre: materia.nombre,
            horasAcademicas: materia.horasAcademicas,
          );
        }
      }

      final periodos = _pensum.map((e) => e.periodo);
      _topePeriodos = periodos.isEmpty ? 1 : periodos.reduce(math.max);
      _periodoDestino = _topePeriodos;
    }

    _cargarMaterias(reiniciar: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  Banco de materias
  // ---------------------------------------------------------------------------

  Future<void> _cargarMaterias({bool reiniciar = false}) async {
    final desplazamiento = reiniciar ? 0 : _materias.length;

    setState(() {
      _cargandoMaterias = true;
      if (reiniciar) _errorMaterias = null;
    });

    final resultado = await _repo.listarMaterias(
      busqueda: _busquedaCtrl.text,
      desplazamiento: desplazamiento,
    );

    if (!mounted) return;

    resultado.when(
      success: (pagina) => setState(() {
        _cargandoMaterias = false;
        _totalMaterias = pagina.total;
        _materias = reiniciar
            ? pagina.materias
            : [..._materias, ...pagina.materias];
        // El banco alimenta el constructor de pensum, así que lo que llega se
        // guarda también en el catálogo: sin esto, una materia recién traída no
        // tendría nombre que mostrar al añadirla.
        for (final materia in pagina.materias) {
          _catalogo.putIfAbsent(materia.id, () => materia);
        }
      }),
      failure: (fallo) => setState(() {
        _cargandoMaterias = false;
        _errorMaterias = fallo.message;
      }),
    );
  }

  void _buscar(String _) {
    // Se espera a que el usuario deje de escribir. Sin esta pausa, cada tecla
    // sería una petición y la lista parpadearía con resultados de búsquedas
    // intermedias.
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _cargarMaterias(reiniciar: true),
    );
  }

  // ---------------------------------------------------------------------------
  //  Pensum
  // ---------------------------------------------------------------------------

  void _agregar(Materia materia) {
    if (_bloqueado) return;

    if (_pensum.any((e) => e.materiaId == materia.id)) {
      mostrarAviso(
        context,
        '${materia.codigo} ya está en el pensum.',
        error: true,
      );
      return;
    }

    setState(() {
      _catalogo[materia.id] = materia;
      _pensum.add(EntradaPensum(materiaId: materia.id, periodo: _periodoDestino));
    });
  }

  void _quitar(String materiaId) {
    if (_bloqueado) return;
    setState(() => _pensum.removeWhere((e) => e.materiaId == materiaId));
  }

  void _moverA(String materiaId, int periodo) {
    if (_bloqueado) return;
    setState(() {
      final indice = _pensum.indexWhere((e) => e.materiaId == materiaId);
      if (indice < 0) return;
      _pensum[indice] = _pensum[indice].conPeriodo(periodo);
    });
  }

  void _anadirPeriodo() {
    if (_bloqueado) return;
    setState(() {
      _topePeriodos += 1;
      _periodoDestino = _topePeriodos;
    });
  }

  Future<void> _registrarMateria() async {
    final creada = await showDialog<Materia>(
      context: context,
      builder: (_) => _DialogoNuevaMateria(repositorio: _repo),
    );

    if (!mounted || creada == null) return;

    // La materia nueva entra al banco en memoria antes de añadirse al pensum:
    // así el buscador la encuentra sin recargar y el nombre se pinta bien.
    setState(() {
      _materias = [creada, ..._materias.where((m) => m.id != creada.id)];
      _totalMaterias += 1;
      _catalogo[creada.id] = creada;
    });
    _agregar(creada);
  }

  // ---------------------------------------------------------------------------
  //  Navegación y guardado
  // ---------------------------------------------------------------------------

  bool _avanzar() {
    switch (_paso) {
      case 0:
        if (!(_formKeyDatos.currentState?.validate() ?? false)) return false;
      case 1:
        if (_pensum.isEmpty) {
          mostrarAviso(
            context,
            'El pensum necesita al menos una materia.',
            error: true,
          );
          return false;
        }
    }

    setState(() => _posicion += 1);
    return true;
  }

  void _retroceder() {
    if (_posicion == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _posicion -= 1);
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() {
      _guardando = true;
      _errorGuardar = null;
    });

    final resultado = widget.esEdicion
        ? await _repo.reemplazarPensum(
            widget.detalleInicial!.programa.id,
            _pensum,
          )
        : await _repo.crearPrograma(
            EntradaCrearPrograma(
              codigo: _codigoCtrl.text,
              nombre: _nombreCtrl.text,
              tipo: _tipo,
              pensum: _pensum,
              requierePasantia: _requierePasantia,
              publicar: _publicar,
            ),
          );

    // El estado de carga se libera ANTES de comprobar `mounted`: al revés, un
    // desmontaje durante la petición dejaría el botón bloqueado para siempre.
    if (mounted) setState(() => _guardando = false);
    if (!mounted) return;

    resultado.when(
      success: (detalle) {
        mostrarAviso(
          context,
          widget.esEdicion
              ? 'Pensum actualizado.'
              : 'Programa «${detalle.programa.codigo}» creado.',
          exito: true,
        );
        Navigator.of(context).pop(true);
      },
      failure: (fallo) => setState(() => _errorGuardar = fallo.message),
    );
  }

  // ---------------------------------------------------------------------------
  //  Construcción
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.esEdicion
              ? 'Pensum de ${widget.detalleInicial!.programa.codigo}'
              : 'Nuevo programa académico',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, decoration:
              const BoxDecoration(gradient: IncesTheme.degradadoMarca)),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _IndicadorPasos(
                  etiquetas: _etiquetasPasos,
                  actual: _posicion,
                  onIr: (destino) {
                    // Sólo se puede volver a un paso ya visitado. Saltar hacia
                    // adelante se hace con «Siguiente», que valida: dejar pulsar
                    // el paso 3 desde el 1 permitiría guardar sin pensum.
                    if (destino < _posicion) setState(() => _posicion = destino);
                  },
                ),
              ),
              Expanded(child: _cuerpo()),
              _pie(theme),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _etiquetasPasos => widget.esEdicion
      ? const ['Pensum', 'Revisión']
      : const ['Datos del programa', 'Pensum', 'Revisión'];

  Widget _cuerpo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: switch (_paso) {
        0 => _pasoDatos(),
        1 => _pasoPensum(),
        _ => _pasoRevision(),
      },
    );
  }

  Widget _pie(ThemeData theme) {
    final esUltimo = _posicion == _indicesPasos.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _guardando ? null : _retroceder,
            icon: const Icon(Icons.arrow_back_rounded, size: 17),
            label: Text(_posicion == 0 ? 'Cancelar' : 'Atrás'),
          ),
          const Spacer(),
          if (esUltimo && _errorGuardar != null) ...[
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  _errorGuardar!,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
          if (!esUltimo)
            FilledButton.icon(
              onPressed: _avanzar,
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: const Text('Siguiente'),
            )
          else if (_bloqueado)
            const Chip(label: Text('Pensum bloqueado'))
          else
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 17),
              label: Text(
                widget.esEdicion ? 'Guardar pensum' : 'Crear programa',
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  Paso 1 — Datos del programa
  // ---------------------------------------------------------------------------

  Widget _pasoDatos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSeccion(
          'Identidad del programa',
          subtitulo: 'El código y el tipo no se podrán cambiar después: son la '
              'identidad del programa y los citan los documentos impresos.',
        ),
        Form(
          key: _formKeyDatos,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codigoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        _mayusculas,
                        LengthLimitingTextInputFormatter(
                          CurriculoRepository.largoMaximoCodigo,
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Código',
                        hintText: 'SIST-01',
                        helperText: 'Mayúsculas, dígitos y guiones.',
                      ),
                      validator: (valor) {
                        final codigo = (valor ?? '').trim().toUpperCase();
                        if (codigo.isEmpty) return 'Ingresa el código.';
                        if (!CurriculoRepository.patronCodigo
                            .hasMatch(codigo)) {
                          return 'Sólo mayúsculas, dígitos y guiones, '
                              'empezando por letra o dígito.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        hintText: 'Análisis de Sistemas',
                      ),
                      validator: (valor) {
                        final nombre = (valor ?? '').trim();
                        if (nombre.isEmpty) return 'Ingresa el nombre.';
                        if (nombre.length >
                            CurriculoRepository.largoMaximoNombre) {
                          return 'Máximo '
                              '${CurriculoRepository.largoMaximoNombre} '
                              'caracteres.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SelectorTipo(
                valor: _tipo,
                onCambio: (tipo) => setState(() => _tipo = tipo),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _requierePasantia,
                      onChanged: (v) => setState(() => _requierePasantia = v),
                      title: const Text('Requiere pasantía'),
                      subtitle: const Text(
                        'El programa exige un período de pasantía para '
                        'egresar.',
                      ),
                      secondary: const Icon(Icons.work_outline, size: 20),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _publicar,
                      onChanged: (v) => setState(() => _publicar = v),
                      title: const Text('Publicar al crear'),
                      subtitle: const Text(
                        'Publicado aparece en el catálogo del aspirante. Si lo '
                        'dejas sin publicar, queda en borrador y se activa '
                        'después.',
                      ),
                      secondary: const Icon(Icons.public_outlined, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AvisoEnLinea(
          tono: TonoAviso.info,
          texto: _tipo == TipoPrograma.carrera
              ? 'Una carrera activa no puede quedarse sin materias: el sistema '
                  'lo impide. El pensum se arma en el paso siguiente.'
              : 'Un curso libre suele tener un solo período. Puedes añadir más '
                  'si el curso lo necesita.',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  //  Paso 2 — Pensum
  // ---------------------------------------------------------------------------

  Widget _pasoPensum() {
    final theme = Theme.of(context);
    final ancho = MediaQuery.sizeOf(context).width;
    final enColumnas = ancho >= 900;

    final banco = _BancoMaterias(
      controlador: _busquedaCtrl,
      materias: _materias,
      total: _totalMaterias,
      cargando: _cargandoMaterias,
      error: _errorMaterias,
      yaEnPensum: _pensum.map((e) => e.materiaId).toSet(),
      habilitado: !_bloqueado,
      onBuscar: _buscar,
      onCargarMas: () => _cargarMaterias(),
      onReintentar: () => _cargarMaterias(reiniciar: true),
      onAgregar: _agregar,
      onRegistrar: _registrarMateria,
    );

    final constructor = _ConstructorPensum(
      pensum: _pensum,
      catalogo: _catalogo,
      periodoDestino: _periodoDestino,
      topePeriodos: _topePeriodos,
      habilitado: !_bloqueado,
      onCambiarPeriodoDestino: (p) => setState(() => _periodoDestino = p),
      onAnadirPeriodo: _anadirPeriodo,
      onMover: _moverA,
      onQuitar: _quitar,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSeccion(
          'Pensum',
          subtitulo: 'Elige materias del banco y asígnalas a un período.',
        ),
        if (_bloqueado) ...[
          AvisoEnLinea(
            tono: TonoAviso.advertencia,
            icono: Icons.lock_outline,
            texto: 'Este pensum no se puede modificar: hay '
                '${widget.detalleInicial!.seccionesActivas} sección(es) activa(s) '
                'del período vigente cursando el programa. Archívalas primero.',
          ),
          const SizedBox(height: 16),
        ],
        if (enColumnas)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: banco),
              const SizedBox(width: 20),
              Expanded(flex: 6, child: constructor),
            ],
          )
        else ...[
          banco,
          const SizedBox(height: 20),
          constructor,
        ],
        const SizedBox(height: 8),
        Text(
          'Añadir una materia a un pensum en uso es legítimo; quitarla o '
          'reordenarla, no.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  //  Paso 3 — Revisión
  // ---------------------------------------------------------------------------

  Widget _pasoRevision() {
    final theme = Theme.of(context);
    final grupos = agruparPensum(_pensum);
    final totalHoras = grupos.fold<int>(0, (suma, g) => suma + _horasDe(g));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSeccion(
          'Revisión',
          subtitulo: 'Esto es exactamente lo que se va a guardar.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _nombreCtrl.text.trim(),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    _Insignia(
                      texto: _tipo.etiqueta,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _codigoCtrl.text.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _DatoResumen(
                      etiqueta: 'Materias',
                      valor: '${_pensum.length}',
                      icono: Icons.menu_book_outlined,
                    ),
                    _DatoResumen(
                      etiqueta: 'Períodos',
                      valor: '${grupos.length}',
                      icono: Icons.calendar_month_outlined,
                    ),
                    _DatoResumen(
                      etiqueta: 'Horas',
                      valor: '$totalHoras',
                      icono: Icons.schedule_outlined,
                    ),
                    _DatoResumen(
                      etiqueta: 'Pasantía',
                      valor: _requierePasantia ? 'Sí' : 'No',
                      icono: Icons.work_outline,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.esEdicion)
          AvisoEnLinea(
            tono: TonoAviso.info,
            texto: 'Se reemplaza el pensum completo. Las materias que ya no '
                'estén se quitan, las que cambien de período se reordenan y las '
                'nuevas se añaden, todo en una sola operación.',
          )
        else
          AvisoEnLinea(
            tono: _publicar ? TonoAviso.exito : TonoAviso.advertencia,
            icono: _publicar ? Icons.public_outlined : Icons.drafts_outlined,
            texto: _publicar
                ? 'El programa se crea publicado: quedará visible en el '
                    'catálogo del aspirante.'
                : 'El programa se crea en borrador. No aparecerá en el catálogo '
                    'hasta que lo actives desde el listado.',
          ),
        const SizedBox(height: 20),
        for (final grupo in grupos) ...[
          _GrupoRevisado(
            grupo: grupo,
            catalogo: _catalogo,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  int _horasDe(GrupoPensum<EntradaPensum> grupo) {
    var total = 0;
    for (final entrada in grupo.materias) {
      total += _catalogo[entrada.materiaId]?.horasAcademicas ?? 0;
    }
    return total;
  }
}

// -----------------------------------------------------------------------------
//  Indicador de pasos
// -----------------------------------------------------------------------------

class _IndicadorPasos extends StatelessWidget {
  const _IndicadorPasos({
    required this.etiquetas,
    required this.actual,
    required this.onIr,
  });

  final List<String> etiquetas;
  final int actual;
  final ValueChanged<int> onIr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < etiquetas.length; i++) ...[
          if (i > 0)
            Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          _Paso(
            numero: i + 1,
            etiqueta: etiquetas[i],
            estado: i == actual
                ? _EstadoPaso.actual
                : i < actual
                    ? _EstadoPaso.hecho
                    : _EstadoPaso.pendiente,
            onTap: i < actual ? () => onIr(i) : null,
          ),
        ],
      ],
    );
  }
}

enum _EstadoPaso { hecho, actual, pendiente }

class _Paso extends StatelessWidget {
  const _Paso({
    required this.numero,
    required this.etiqueta,
    required this.estado,
    this.onTap,
  });

  final int numero;
  final String etiqueta;
  final _EstadoPaso estado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final color = switch (estado) {
      _EstadoPaso.actual => theme.colorScheme.primary,
      _EstadoPaso.hecho => IncesTheme.exito,
      _EstadoPaso.pendiente => theme.colorScheme.onSurfaceVariant,
    };

    final contenido = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: estado == _EstadoPaso.pendiente
                ? Colors.transparent
                : color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: estado == _EstadoPaso.hecho
              ? Icon(Icons.check_rounded, size: 14, color: color)
              : Text(
                  '$numero',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          etiqueta,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight:
                estado == _EstadoPaso.actual ? FontWeight.w700 : FontWeight.w500,
            color: estado == _EstadoPaso.pendiente
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );

    if (onTap == null) return contenido;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: contenido,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Paso 1 — Selector de tipo
// -----------------------------------------------------------------------------

class _SelectorTipo extends StatelessWidget {
  const _SelectorTipo({required this.valor, required this.onCambio});

  final TipoPrograma valor;
  final ValueChanged<TipoPrograma> onCambio;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TipoPrograma>(
      segments: const [
        ButtonSegment(
          value: TipoPrograma.carrera,
          label: Text('Carrera'),
          icon: Icon(Icons.school_outlined, size: 17),
        ),
        ButtonSegment(
          value: TipoPrograma.cursoLibre,
          label: Text('Curso libre'),
          icon: Icon(Icons.auto_stories_outlined, size: 17),
        ),
      ],
      selected: {valor},
      onSelectionChanged: (seleccion) => onCambio(seleccion.first),
    );
  }
}

// -----------------------------------------------------------------------------
//  Paso 2 — Banco de materias
// -----------------------------------------------------------------------------

class _BancoMaterias extends StatelessWidget {
  const _BancoMaterias({
    required this.controlador,
    required this.materias,
    required this.total,
    required this.cargando,
    required this.error,
    required this.yaEnPensum,
    required this.habilitado,
    required this.onBuscar,
    required this.onCargarMas,
    required this.onReintentar,
    required this.onAgregar,
    required this.onRegistrar,
  });

  final TextEditingController controlador;
  final List<Materia> materias;
  final int total;
  final bool cargando;
  final String? error;
  final Set<String> yaEnPensum;
  final bool habilitado;
  final ValueChanged<String> onBuscar;
  final VoidCallback onCargarMas;
  final VoidCallback onReintentar;
  final ValueChanged<Materia> onAgregar;
  final VoidCallback onRegistrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quedan = total - materias.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.library_books_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Banco de materias', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '$total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controlador,
              onChanged: onBuscar,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Buscar por código o nombre',
                prefixIcon: Icon(Icons.search_rounded, size: 19),
              ),
            ),
            const SizedBox(height: 12),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onReintentar,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (materias.isEmpty && !cargando)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No hay materias que coincidan. Regístrala abajo y quedará '
                  'en el banco.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: materias.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final materia = materias[i];
                    final yaEsta = yaEnPensum.contains(materia.id);

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        materia.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        '${materia.codigo} · ${materia.horasAcademicas} h',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      trailing: yaEsta
                          ? Icon(
                              Icons.check_circle_outline,
                              size: 19,
                              color: IncesTheme.exito,
                            )
                          : IconButton(
                              tooltip: 'Añadir al pensum',
                              onPressed: habilitado
                                  ? () => onAgregar(materia)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 19),
                            ),
                    );
                  },
                ),
              ),
            if (cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (quedan > 0)
              TextButton(
                onPressed: onCargarMas,
                child: Text('Cargar más ($quedan restantes)'),
              ),
            const Divider(height: 24),
            OutlinedButton.icon(
              onPressed: habilitado ? onRegistrar : null,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Registrar materia'),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Paso 2 — Constructor de pensum
// -----------------------------------------------------------------------------

class _ConstructorPensum extends StatelessWidget {
  const _ConstructorPensum({
    required this.pensum,
    required this.catalogo,
    required this.periodoDestino,
    required this.topePeriodos,
    required this.habilitado,
    required this.onCambiarPeriodoDestino,
    required this.onAnadirPeriodo,
    required this.onMover,
    required this.onQuitar,
  });

  final List<EntradaPensum> pensum;
  final Map<String, Materia> catalogo;
  final int periodoDestino;
  final int topePeriodos;
  final bool habilitado;
  final ValueChanged<int> onCambiarPeriodoDestino;
  final VoidCallback onAnadirPeriodo;
  final void Function(String materiaId, int periodo) onMover;
  final ValueChanged<String> onQuitar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grupos = agruparPensum(pensum);

    // El rango de períodos ofrecidos nunca puede quedarse por debajo del mayor
    // que ya esté en uso: un `DropdownButton` cuyo valor no esté entre sus
    // opciones lanza una aserción en tiempo de ejecución.
    final mayorEnUso =
        pensum.isEmpty ? 1 : pensum.map((e) => e.periodo).reduce(math.max);
    final tope = math.max(topePeriodos, mayorEnUso);
    final periodos = [for (var p = 1; p <= tope; p++) p];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Pensum', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${_plural(pensum.length, 'materia', 'materias')} · '
                  '${_plural(grupos.length, 'período', 'períodos')}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Añadir al período',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: periodoDestino,
                  isDense: true,
                  onChanged: habilitado
                      ? (p) {
                          if (p != null) onCambiarPeriodoDestino(p);
                        }
                      : null,
                  items: [
                    for (final periodo in periodos)
                      DropdownMenuItem(
                        value: periodo,
                        child: Text('$periodo'),
                      ),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: habilitado ? onAnadirPeriodo : null,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Período'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pensum.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.playlist_add_outlined,
                      size: 34,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'El pensum está vacío. Añade materias desde el banco.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final grupo in grupos) ...[
                _CabeceraPeriodo(grupo: grupo, catalogo: catalogo),
                for (final entrada in grupo.materias)
                  _FilaMateria(
                    entrada: entrada,
                    materia: catalogo[entrada.materiaId],
                    periodos: periodos,
                    habilitado: habilitado,
                    onMover: (periodo) => onMover(entrada.materiaId, periodo),
                    onQuitar: () => onQuitar(entrada.materiaId),
                  ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _CabeceraPeriodo extends StatelessWidget {
  const _CabeceraPeriodo({required this.grupo, required this.catalogo});

  final GrupoPensum<EntradaPensum> grupo;
  final Map<String, Materia> catalogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    var horas = 0;
    for (final entrada in grupo.materias) {
      horas += catalogo[entrada.materiaId]?.horasAcademicas ?? 0;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              'Período ${grupo.periodo}',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_plural(grupo.totalMaterias, 'materia', 'materias')} · $horas h',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaMateria extends StatelessWidget {
  const _FilaMateria({
    required this.entrada,
    required this.materia,
    required this.periodos,
    required this.habilitado,
    required this.onMover,
    required this.onQuitar,
  });

  final EntradaPensum entrada;
  final Materia? materia;
  final List<int> periodos;
  final bool habilitado;
  final ValueChanged<int> onMover;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  materia?.nombre ?? 'Materia desconocida',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${materia?.codigo ?? entrada.materiaId}'
                  '${materia == null ? '' : ' · ${materia!.horasAcademicas} h'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: entrada.periodo,
            isDense: true,
            underline: const SizedBox.shrink(),
            onChanged: habilitado
                ? (p) {
                    if (p != null) onMover(p);
                  }
                : null,
            items: [
              for (final periodo in periodos)
                DropdownMenuItem(value: periodo, child: Text('P$periodo')),
            ],
          ),
          IconButton(
            tooltip: 'Quitar del pensum',
            onPressed: habilitado ? onQuitar : null,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Paso 3 — Resumen por período
// -----------------------------------------------------------------------------

class _GrupoRevisado extends StatelessWidget {
  const _GrupoRevisado({required this.grupo, required this.catalogo});

  final GrupoPensum<EntradaPensum> grupo;
  final Map<String, Materia> catalogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Período ${grupo.periodo}',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  _plural(grupo.totalMaterias, 'materia', 'materias'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final entrada in grupo.materias)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        catalogo[entrada.materiaId]?.nombre ??
                            entrada.materiaId,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      catalogo[entrada.materiaId]?.codigo ?? '',
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

class _DatoResumen extends StatelessWidget {
  const _DatoResumen({
    required this.etiqueta,
    required this.valor,
    required this.icono,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(valor, style: theme.textTheme.titleSmall),
        const SizedBox(width: 4),
        Text(
          etiqueta,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        texto,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Diálogo de registro de materia
// -----------------------------------------------------------------------------

/// Registra una materia en caliente y la devuelve.
///
/// Si el código ya existe, el backend responde `409 REGISTRO_DUPLICADO`. Ése es
/// el caso **frecuente** —la materia ya estaba en el banco y alguien la escribió
/// con otro nombre—, así que la pantalla no se limita a mostrar el error:
/// ofrece buscar la existente y usarla. Mostrar sólo un error obligaría al
/// administrador a cancelar, buscar a mano y volver a empezar.
class _DialogoNuevaMateria extends StatefulWidget {
  const _DialogoNuevaMateria({required this.repositorio});

  final CurriculoRepository repositorio;

  @override
  State<_DialogoNuevaMateria> createState() => _DialogoNuevaMateriaState();
}

class _DialogoNuevaMateriaState extends State<_DialogoNuevaMateria> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _horasCtrl = TextEditingController(text: '96');

  bool _guardando = false;
  String? _error;
  bool _puedeBuscarExistente = false;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _horasCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_guardando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _guardando = true;
      _error = null;
      _puedeBuscarExistente = false;
    });

    final resultado = await widget.repositorio.crearMateria(
      EntradaCrearMateria(
        codigo: _codigoCtrl.text,
        nombre: _nombreCtrl.text,
        horasAcademicas: int.tryParse(_horasCtrl.text.trim()) ?? 0,
      ),
    );

    if (mounted) setState(() => _guardando = false);
    if (!mounted) return;

    resultado.when(
      success: (materia) => Navigator.of(context).pop(materia),
      failure: (fallo) => setState(() {
        _error = fallo.message;
        // Sólo se ofrece reutilizar la existente cuando el fallo es por código
        // repetido. Ofrecerlo ante un error de red haría perder el tiempo.
        _puedeBuscarExistente = fallo.code == 'REGISTRO_DUPLICADO';
      }),
    );
  }

  Future<void> _usarExistente() async {
    setState(() {
      _guardando = true;
      _error = null;
    });

    final codigo = _codigoCtrl.text.trim().toUpperCase();
    final resultado = await widget.repositorio.listarMaterias(busqueda: codigo);

    if (mounted) setState(() => _guardando = false);
    if (!mounted) return;

    resultado.when(
      success: (pagina) {
        // Se busca el código exacto y no se toma la primera coincidencia: el
        // filtro del backend es un `ilike`, así que `BD-II` también devuelve
        // `BD-III`, y quedarse con la primera añadiría la materia equivocada.
        Materia? existente;
        for (final materia in pagina.materias) {
          if (materia.codigo.toUpperCase() == codigo) {
            existente = materia;
            break;
          }
        }

        // Copia local: garantiza que el tipo quede promovido a no nulo, sin
        // depender de cómo analice el compilador una variable asignada dentro
        // de un bucle.
        final encontrada = existente;

        if (encontrada == null) {
          setState(() {
            _error = 'El código $codigo ya existe, pero no pudimos recuperar '
                'la materia. Búscala en el banco por su nombre.';
            _puedeBuscarExistente = false;
          });
          return;
        }

        Navigator.of(context).pop(encontrada);
      },
      failure: (fallo) => setState(() => _error = fallo.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar materia'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codigoCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (_, nuevo) => nuevo.copyWith(text: nuevo.text.toUpperCase()),
                  ),
                  LengthLimitingTextInputFormatter(
                    CurriculoRepository.largoMaximoCodigo,
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Código',
                  hintText: 'BD-II',
                ),
                validator: (valor) {
                  final codigo = (valor ?? '').trim().toUpperCase();
                  if (codigo.isEmpty) return 'Ingresa el código.';
                  if (!CurriculoRepository.patronCodigo.hasMatch(codigo)) {
                    return 'Sólo mayúsculas, dígitos y guiones.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Bases de Datos II',
                ),
                validator: (valor) {
                  final nombre = (valor ?? '').trim();
                  if (nombre.isEmpty) return 'Ingresa el nombre.';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _horasCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Horas académicas',
                  suffixText: 'h',
                ),
                validator: (valor) {
                  final horas = int.tryParse((valor ?? '').trim());
                  if (horas == null || horas <= 0) {
                    return 'Las horas deben ser mayores que cero.';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: IncesTheme.error.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(IncesTheme.radioControl),
                    border: Border.all(
                      color: IncesTheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: IncesTheme.error,
                    ),
                  ),
                ),
              ],
              if (_puedeBuscarExistente) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _guardando ? null : _usarExistente,
                    icon: const Icon(Icons.search_rounded, size: 16),
                    label: const Text('Usar la materia existente'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _registrar,
          child: _guardando
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Registrar'),
        ),
      ],
    );
  }
}
