import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/inscripcion_campo.dart';
import '../../repositories/planilla_admin_repository.dart';
import '../../widgets/comunes.dart';

/// Administración del catálogo de campos de la planilla de inscripción.
///
/// **Por qué este panel existe.** Hasta ahora, marcar un campo como opcional
/// era un `update` en la base de datos escrito a mano. Eso deja el objetivo del
/// formulario conducido por datos a medio camino: la pantalla ya no conoce los
/// campos, pero el CFS no puede cambiarlos sin alguien que sepa SQL. Aquí se
/// cierra el círculo.
///
/// **Lo que se puede hacer, y lo que no.** El panel edita lo que cambia con el
/// uso —etiqueta, ayuda, obligatoriedad, grupo, orden y encendido— y **muestra**
/// lo que cambiaría la forma del dato: `codigo` y `tipo` son inmutables después
/// de la creación (renombrar el código es una migración de datos, y cambiar el
/// tipo cambiaría la forma del valor ya guardado), y `condicion` y `aplica_a` se
/// enseñan como insignias pero no se editan. La inmutabilidad no depende de que
/// este archivo se acuerde: `PlanillaAdminGateway.actualizar` no tiene esos
/// parámetros, así que no hay forma de mandarlos.
///
/// **Por qué los apagados siguen en la lista.** Es la razón de que el gateway
/// administrativo sea distinto del público: aquél filtra `activo = true`, y con
/// ese filtro apagar un campo lo haría desaparecer de la pantalla justo al
/// apagarlo, así que no habría forma de volver a encenderlo.
class CpanelInscripcionCamposPanel extends StatefulWidget {
  const CpanelInscripcionCamposPanel({super.key, this.repositorio});

  final PlanillaAdminRepository? repositorio;

  @override
  State<CpanelInscripcionCamposPanel> createState() =>
      _CpanelInscripcionCamposPanelState();
}

class _CpanelInscripcionCamposPanelState
    extends State<CpanelInscripcionCamposPanel> {
  late final PlanillaAdminRepository _repo =
      widget.repositorio ?? PlanillaAdminRepository();

  bool _cargando = true;
  String? _error;
  List<CampoInscripcion> _campos = const [];

  /// Códigos con una petición en vuelo. Bloquea **sólo** los controles de esa
  /// fila: apagar un campo no debe impedir reordenar otro.
  final Set<String> _ocupados = {};

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

    final resultado = await _repo.obtenerCatalogo();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final catalogo):
          _campos = catalogo.campos;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  /// Relee el catálogo **sin** pasar por el estado de carga.
  ///
  /// Se usa después de un intercambio de orden, y no por comodidad: el
  /// intercambio son dos `update` y no es atómico, así que la única forma de
  /// saber qué quedó de verdad en la base es volver a preguntarlo. Actualizar la
  /// lista a mano mostraría lo que *debía* pasar, que no es lo mismo que lo que
  /// pasó.
  Future<void> _refrescar() async {
    final resultado = await _repo.obtenerCatalogo();
    if (!mounted) return;

    switch (resultado) {
      case Success(value: final catalogo):
        setState(() => _campos = catalogo.campos);
      case Failure(error: final fallo):
        mostrarAviso(context, fallo.message, error: true);
    }
  }

  /// Marca una fila como ocupada mientras corre [accion], y la libera siempre.
  Future<void> _conGuardia(String codigo, Future<void> Function() accion) async {
    setState(() => _ocupados.add(codigo));
    try {
      await accion();
    } finally {
      if (mounted) setState(() => _ocupados.remove(codigo));
    }
  }

  Future<void> _alternarActivo(CampoInscripcion campo, bool activo) {
    return _conGuardia(campo.codigo, () async {
      final resultado = await _repo.alternarActivo(
        codigo: campo.codigo,
        activo: activo,
      );
      if (!mounted) return;

      switch (resultado) {
        case Success(value: final actualizado):
          // La fila se sustituye por lo que devolvió el servidor y no por lo que
          // se pidió: si la base normalizó algo, la pantalla lo enseña.
          setState(() {
            _campos = [
              for (final c in _campos)
                if (c.codigo == actualizado.codigo) actualizado else c,
            ];
          });
          mostrarAviso(
            context,
            actualizado.activo
                ? '«${actualizado.etiqueta}» se preguntará en el formulario'
                : '«${actualizado.etiqueta}» deja de preguntarse',
            exito: true,
          );
        case Failure(error: final fallo):
          mostrarAviso(context, fallo.message, error: true);
      }
    });
  }

  /// Sube o baja un campo un puesto, intercambiándolo con su vecino del grupo.
  ///
  /// El vecino se busca **dentro del grupo** y no en la lista global: es lo que
  /// el admin ve. Como `orden` es global, el intercambio cambia el valor de las
  /// dos filas y ninguna otra se mueve, así que el resultado es exactamente «los
  /// dos se cambiaron de sitio».
  Future<void> _mover(CampoInscripcion campo, int delta) {
    return _conGuardia(campo.codigo, () async {
      final hermanos = _grupoDe(campo.codigo);
      final indice = hermanos.indexWhere((c) => c.codigo == campo.codigo);
      final destino = indice + delta;

      if (indice < 0 || destino < 0 || destino >= hermanos.length) return;

      final resultado = await _repo.intercambiarOrden(
        actual: campo,
        vecino: hermanos[destino],
      );
      if (!mounted) return;

      switch (resultado) {
        case Success():
          await _refrescar();
        case Failure(error: final fallo):
          mostrarAviso(context, fallo.message, error: true);
      }
    });
  }

  /// Los campos del mismo grupo que [codigo], ya ordenados.
  List<CampoInscripcion> _grupoDe(String codigo) {
    for (final grupo in CatalogoInscripcion(_campos).grupos) {
      if (grupo.campos.any((c) => c.codigo == codigo)) return grupo.campos;
    }
    return const [];
  }

  /// El orden con el que nace un campo nuevo: después del último.
  int get _siguienteOrden => _campos.isEmpty
      ? 10
      : _campos.map((c) => c.orden).reduce((a, b) => a > b ? a : b) + 10;

  List<String> get _gruposExistentes =>
      CatalogoInscripcion(_campos).grupos.map((g) => g.nombre).toList();

  Future<void> _abrirNuevo() async {
    final editado = await showDialog<_ResultadoDialogo>(
      context: context,
      builder: (_) => _DialogoCampo(
        gruposExistentes: _gruposExistentes,
        grupoPorDefecto: _gruposExistentes.isEmpty
            ? 'Datos personales'
            : _gruposExistentes.first,
      ),
    );
    if (editado == null || !mounted) return;

    setState(() => _ocupados.add(editado.codigo));
    try {
      final resultado = await _repo.crear(
        CampoInscripcion(
          codigo: editado.codigo,
          etiqueta: editado.etiqueta,
          grupo: editado.grupo,
          tipo: editado.tipo,
          orden: _siguienteOrden,
          obligatorio: editado.obligatorio,
          ayuda: editado.ayuda.isEmpty ? null : editado.ayuda,
        ),
      );
      if (!mounted) return;

      switch (resultado) {
        case Success(value: final nuevo):
          // Se relee en vez de añadirlo a la lista: el orden lo calculó este
          // lado y el servidor manda.
          await _refrescar();
          if (!mounted) return;
          mostrarAviso(context, '«${nuevo.etiqueta}» añadido al catálogo',
              exito: true);
        case Failure(error: final fallo):
          mostrarAviso(context, fallo.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _ocupados.remove(editado.codigo));
    }
  }

  Future<void> _abrirEditar(CampoInscripcion campo) async {
    final editado = await showDialog<_ResultadoDialogo>(
      context: context,
      builder: (_) => _DialogoCampo(
        campo: campo,
        gruposExistentes: _gruposExistentes,
        grupoPorDefecto: campo.grupo,
      ),
    );
    if (editado == null || !mounted) return;

    // Nada cambió: no se gasta una petición en confirmar lo que ya está.
    if (editado.etiqueta == campo.etiqueta &&
        editado.grupo == campo.grupo &&
        editado.obligatorio == campo.obligatorio &&
        editado.ayuda == (campo.ayuda ?? '')) {
      return;
    }

    await _conGuardia(campo.codigo, () async {
      final resultado = await _repo.actualizar(
        codigo: campo.codigo,
        etiqueta: editado.etiqueta,
        grupo: editado.grupo,
        obligatorio: editado.obligatorio,
        // Cadena vacía y no `null`: es lo que borra la ayuda. `null` significa
        // «no toques esta columna», que aquí no es lo que se quiere.
        ayuda: editado.ayuda,
      );
      if (!mounted) return;

      switch (resultado) {
        case Success(value: final actualizado):
          setState(() {
            _campos = [
              for (final c in _campos)
                if (c.codigo == actualizado.codigo) actualizado else c,
            ];
          });
          mostrarAviso(context, '«${actualizado.etiqueta}» actualizado',
              exito: true);
        case Failure(error: final fallo):
          mostrarAviso(context, fallo.message, error: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return EstadoPanel(
      cargando: _cargando,
      error: _error,
      onReintentar: _cargar,
      child: _construirCatalogo(context),
    );
  }

  Widget _construirCatalogo(BuildContext context) {
    if (_campos.isEmpty) {
      return PanelVacio(
        titulo: 'El catálogo está vacío',
        mensaje:
            'No hay ningún campo declarado, así que el formulario de inscripción '
            'no preguntaría nada.',
        icono: Icons.playlist_add_outlined,
        nota: 'Un catálogo vacío y un catálogo que no se pudo leer se ven igual; '
            'este mensaje es el del vacío de verdad.',
      );
    }

    final grupos = CatalogoInscripcion(_campos).grupos;
    final obligatorios = _campos.where((c) => c.obligatorio).length;
    final apagados = _campos.where((c) => !c.activo).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        TituloSeccion(
          'Campos de la planilla',
          subtitulo:
              '${_campos.length} campos · $obligatorios obligatorios · '
              '$apagados apagados',
          acciones: [
            FilledButton.icon(
              onPressed: _abrirNuevo,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Añadir campo'),
            ),
          ],
        ),
        const AvisoEnLinea(
          texto:
              'El formulario de inscripción se construye con esta lista: añadir '
              'una pregunta es añadir una fila aquí, sin tocar código. Un campo '
              'apagado deja de preguntarse pero conserva las respuestas que ya '
              'recibió.',
        ),
        const SizedBox(height: 20),
        for (final grupo in grupos)
          _SeccionGrupo(
            grupo: grupo,
            ocupados: _ocupados,
            onAlternar: _alternarActivo,
            onMover: _mover,
            onEditar: _abrirEditar,
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Un grupo del catálogo
// -----------------------------------------------------------------------------

/// Un grupo plegable —lo que el formulario pinta como un paso—.
///
/// Va plegado/desplegado con `ExpansionTile` y **arranca desplegado**: un
/// catálogo cuya primera impresión son nueve títulos cerrados no dice qué
/// contiene, y el admin tendría que abrir los nueve para saber qué hay.
class _SeccionGrupo extends StatelessWidget {
  const _SeccionGrupo({
    required this.grupo,
    required this.ocupados,
    required this.onAlternar,
    required this.onMover,
    required this.onEditar,
  });

  final GrupoPlanilla grupo;
  final Set<String> ocupados;
  final Future<void> Function(CampoInscripcion campo, bool activo) onAlternar;
  final Future<void> Function(CampoInscripcion campo, int delta) onMover;
  final Future<void> Function(CampoInscripcion campo) onEditar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apagados = grupo.campos.where((c) => !c.activo).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          grupo.nombre,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          '${grupo.campos.length} '
          '${grupo.campos.length == 1 ? 'campo' : 'campos'}'
          '${apagados > 0 ? ' · $apagados apagado${apagados == 1 ? '' : 's'}' : ''}',
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        children: [
          for (var i = 0; i < grupo.campos.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _FilaCampo(
              // Clave estable por código: es lo que permite que una prueba
              // apunte a «el interruptor de `talla_camisa`» en vez de a «el
              // interruptor número 6». Un índice se rompe en cuanto alguien
              // añade un campo al catálogo, que es justo lo que este panel
              // existe para permitir.
              key: ValueKey('fila-${grupo.campos[i].codigo}'),
              campo: grupo.campos[i],
              ocupado: ocupados.contains(grupo.campos[i].codigo),
              puedeSubir: i > 0,
              puedeBajar: i < grupo.campos.length - 1,
              onAlternar: (activo) => onAlternar(grupo.campos[i], activo),
              onSubir: () => onMover(grupo.campos[i], -1),
              onBajar: () => onMover(grupo.campos[i], 1),
              onEditar: () => onEditar(grupo.campos[i]),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Una fila del catálogo
// -----------------------------------------------------------------------------

/// Una fila del catálogo: identidad del campo a la izquierda, controles a la
/// derecha.
///
/// **El `LayoutBuilder` no es decorativo.** A 375 px la columna de identidad y
/// los cuatro controles no caben en la misma línea: la `Row` desbordaría, o
/// —peor, porque no se ve— el `Expanded` de la identidad se quedaría con ancho
/// cero y el texto envolvería una letra por línea. Es la misma trampa que ya
/// pagaron `TituloSeccion` y el encabezado institucional, así que se resuelve
/// igual: por debajo de 640 px los controles bajan a su propia línea.
class _FilaCampo extends StatelessWidget {
  const _FilaCampo({
    super.key,
    required this.campo,
    required this.ocupado,
    required this.puedeSubir,
    required this.puedeBajar,
    required this.onAlternar,
    required this.onSubir,
    required this.onBajar,
    required this.onEditar,
  });

  final CampoInscripcion campo;
  final bool ocupado;
  final bool puedeSubir;
  final bool puedeBajar;
  final ValueChanged<bool> onAlternar;
  final VoidCallback onSubir;
  final VoidCallback onBajar;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // Un campo apagado se atenúa pero **no se oculta**: sigue siendo editable
      // y reordenable, y es la única forma de volver a encenderlo.
      opacity: campo.activo ? 1 : 0.62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, restricciones) {
            final identidad = _identidad(context);
            final controles = _controles(context);

            const anchoMinimoParaFila = 640.0;
            if (restricciones.maxWidth >= anchoMinimoParaFila) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identidad),
                  const SizedBox(width: 12),
                  ...controles,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identidad,
                const SizedBox(height: 10),
                // `Wrap` y no `Row`: si los controles no caben ni en su propia
                // línea, envuelven en vez de desbordar.
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: controles,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _identidad(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(campo.etiqueta, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          campo.codigo,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (campo.ayuda != null) ...[
          const SizedBox(height: 6),
          Text(
            campo.ayuda!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Etiqueta(texto: _etiquetaTipo(campo.tipo)),
            if (campo.obligatorio) Etiqueta(texto: 'Obligatorio', destacada: true),
            if (!campo.activo) const Etiqueta(texto: 'Apagado'),
            // `condicion` y `aplica_a` no se editan en esta versión: se enseñan
            // para que quien administra sepa que existen y por qué un campo
            // puede no aparecer aunque esté encendido.
            if (campo.condicion != null)
              Etiqueta(texto: 'Depende de ${campo.condicion!.campo}'),
            if (campo.aplicaA.isNotEmpty)
              Etiqueta(
                texto: 'Sólo ${campo.aplicaA.length} '
                    '${campo.aplicaA.length == 1 ? 'programa' : 'programas'}',
              ),
            if (campo.tieneFuenteExterna)
              Etiqueta(texto: 'Opciones en vivo'),
          ],
        ),
      ],
    );
  }

  List<Widget> _controles(BuildContext context) {
    if (ocupado) {
      return const [
        Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ];
    }

    return [
      _BotonIcono(
        icono: Icons.arrow_upward_rounded,
        tooltip: 'Subir un puesto',
        onPressed: puedeSubir ? onSubir : null,
      ),
      _BotonIcono(
        icono: Icons.arrow_downward_rounded,
        tooltip: 'Bajar un puesto',
        onPressed: puedeBajar ? onBajar : null,
      ),
      _BotonIcono(
        icono: Icons.edit_outlined,
        tooltip: 'Editar etiqueta, ayuda y obligatoriedad',
        onPressed: onEditar,
      ),
      const SizedBox(width: 4),
      Tooltip(
        message: campo.activo
            ? 'Se pregunta en el formulario'
            : 'No se pregunta en el formulario',
        child: Switch(value: campo.activo, onChanged: onAlternar),
      ),
    ];
  }
}

/// Botón de icono compacto.
///
/// El `IconButton` por defecto mide 48 px y con cuatro controles por fila eso
/// empuja la identidad del campo a un ancho inservible a 375 px. Se le fijan
/// las restricciones en vez de dejar que el tema decida.
class _BotonIcono extends StatelessWidget {
  const _BotonIcono({
    required this.icono,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icono),
      iconSize: 18,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

/// Nombre legible de un tipo de campo.
///
/// El `enum` es el contrato con la base (`tipo.name` viaja tal cual), pero
/// `multiseleccion` no es una palabra que nadie lea de corrido.
String _etiquetaTipo(TipoCampoInscripcion tipo) => switch (tipo) {
      TipoCampoInscripcion.texto => 'Texto',
      TipoCampoInscripcion.email => 'Correo',
      TipoCampoInscripcion.numero => 'Número',
      TipoCampoInscripcion.fecha => 'Fecha',
      TipoCampoInscripcion.seleccion => 'Selección',
      TipoCampoInscripcion.multiseleccion => 'Selección múltiple',
      TipoCampoInscripcion.booleano => 'Sí / No',
      TipoCampoInscripcion.tabla => 'Tabla repetible',
      TipoCampoInscripcion.rejilla => 'Rejilla',
    };

// -----------------------------------------------------------------------------
//  Diálogo de alta y edición
// -----------------------------------------------------------------------------

/// Lo que el diálogo devuelve.
///
/// [codigo] y [tipo] sólo tienen efecto al **crear**: en edición el diálogo los
/// muestra como texto y devuelve los del campo original, que el repositorio
/// ignora porque su `actualizar` no los acepta.
class _ResultadoDialogo {
  const _ResultadoDialogo({
    required this.codigo,
    required this.etiqueta,
    required this.grupo,
    required this.ayuda,
    required this.obligatorio,
    required this.tipo,
  });

  final String codigo;
  final String etiqueta;
  final String grupo;
  final String ayuda;
  final bool obligatorio;
  final TipoCampoInscripcion tipo;
}

/// Alta o edición de un campo del catálogo.
///
/// En edición, `codigo` y `tipo` **no se pintan como campos de formulario**: se
/// pintan como texto. Un campo deshabilitado invita a intentar cambiarlo, y
/// además un `TextFormField` de sólo lectura se traga un `enterText` sin decir
/// nada —así que una prueba que lo intentara pasaría escribiendo en el vacío—.
class _DialogoCampo extends StatefulWidget {
  const _DialogoCampo({
    this.campo,
    required this.gruposExistentes,
    required this.grupoPorDefecto,
  });

  final CampoInscripcion? campo;
  final List<String> gruposExistentes;
  final String grupoPorDefecto;

  @override
  State<_DialogoCampo> createState() => _DialogoCampoState();
}

class _DialogoCampoState extends State<_DialogoCampo> {
  final _formulario = GlobalKey<FormState>();

  late final TextEditingController _codigo =
      TextEditingController(text: widget.campo?.codigo ?? '');
  late final TextEditingController _etiqueta =
      TextEditingController(text: widget.campo?.etiqueta ?? '');
  late final TextEditingController _ayuda =
      TextEditingController(text: widget.campo?.ayuda ?? '');
  late final TextEditingController _grupo =
      TextEditingController(text: widget.grupoPorDefecto);

  late bool _obligatorio = widget.campo?.obligatorio ?? false;
  late TipoCampoInscripcion _tipo =
      widget.campo?.tipo ?? TipoCampoInscripcion.texto;

  bool get _esNuevo => widget.campo == null;

  @override
  void dispose() {
    _codigo.dispose();
    _etiqueta.dispose();
    _ayuda.dispose();
    _grupo.dispose();
    super.dispose();
  }

  void _enviar() {
    if (!(_formulario.currentState?.validate() ?? false)) return;

    Navigator.of(context).pop(
      _ResultadoDialogo(
        codigo: _codigo.text.trim(),
        etiqueta: _etiqueta.text.trim(),
        grupo: _grupo.text.trim(),
        ayuda: _ayuda.text.trim(),
        obligatorio: _obligatorio,
        tipo: _tipo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Un campo con `condicion` no puede ser obligatorio: el formulario lo oculta
    // y lo omite de la planilla cuando la condición no se cumple, así que
    // exigirlo sería exigir algo que el aspirante no puede ver ni rellenar. Aquí
    // se deshabilita el interruptor; la regla de fondo la aplica
    // `validar_planilla()` en la base (migración 202609250003), y esto es lo que
    // la hace evidente en la pantalla en vez de dejar que el admin marque algo
    // que no puede funcionar. Un campo nuevo nunca trae condición, así que el
    // caso sólo se da en edición.
    final condicional = widget.campo?.condicion != null;

    return AlertDialog(
      title: Text(_esNuevo ? 'Añadir campo' : 'Editar campo'),
      // El contenido va en un `SingleChildScrollView`: con seis controles y un
      // teclado abierto, un diálogo de alto fijo desborda en vertical, y el
      // desborde vertical de un `Column` **lanza** en pruebas.
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formulario,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_esNuevo)
                  TextFormField(
                    key: const ValueKey('dialogo-codigo'),
                    controller: _codigo,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      helperText:
                          'Minúsculas, números y guion bajo. Es la clave con la '
                          'que viaja el dato, así que no se puede cambiar luego.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (valor) {
                      final texto = (valor ?? '').trim();
                      if (texto.isEmpty) return 'El código es obligatorio.';
                      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(texto)) {
                        return 'Sólo minúsculas, números y guion bajo, '
                            'empezando por una letra.';
                      }
                      return null;
                    },
                  )
                else
                  _DatoFijo(etiqueta: 'Código', valor: widget.campo!.codigo),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('dialogo-etiqueta'),
                  controller: _etiqueta,
                  decoration: const InputDecoration(
                    labelText: 'Etiqueta',
                    helperText: 'Lo que el aspirante lee en el formulario.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (valor) => (valor ?? '').trim().isEmpty
                      ? 'La etiqueta es obligatoria.'
                      : null,
                ),
                const SizedBox(height: 16),
                if (_esNuevo)
                  DropdownButtonFormField<TipoCampoInscripcion>(
                    key: const ValueKey('dialogo-tipo'),
                    initialValue: _tipo,
                    // `isExpanded` es obligatorio, no cosmético: sin él la `Row`
                    // interna del `DropdownButton` mide por su contenido y
                    // desborda a ancho de móvil (`dropdown.dart:1650`).
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      helperText:
                          'Decide el widget y la forma del valor guardado. '
                          'Tampoco se puede cambiar luego.',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final tipo in TipoCampoInscripcion.values)
                        DropdownMenuItem(
                          value: tipo,
                          child: Text(
                            _etiquetaTipo(tipo),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (tipo) {
                      if (tipo != null) setState(() => _tipo = tipo);
                    },
                  )
                else
                  _DatoFijo(
                    etiqueta: 'Tipo',
                    valor: _etiquetaTipo(widget.campo!.tipo),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('dialogo-grupo'),
                  controller: _grupo,
                  decoration: const InputDecoration(
                    labelText: 'Grupo',
                    helperText: 'Cada grupo es un paso del formulario.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (valor) => (valor ?? '').trim().isEmpty
                      ? 'El grupo es obligatorio.'
                      : null,
                ),
                if (widget.gruposExistentes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // Chips en vez de un desplegable: el grupo es texto libre en
                  // la base, así que un desplegable impediría crear uno nuevo.
                  // Esto sugiere los que ya existen sin cerrar la puerta.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final grupo in widget.gruposExistentes)
                        ActionChip(
                          label: Text(grupo),
                          onPressed: () => setState(() => _grupo.text = grupo),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('dialogo-ayuda'),
                  controller: _ayuda,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Ayuda (opcional)',
                    helperText: 'Aclaración que aparece bajo la pregunta. '
                        'Dejarlo vacío la borra.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const ValueKey('dialogo-obligatorio'),
                  value: _obligatorio,
                  // `onChanged: null` es la forma que tiene Flutter de decir
                  // «este control no se toca aquí»: lo deja visible pero
                  // deshabilitado, sin ocultar el estado actual del campo.
                  onChanged: condicional
                      ? null
                      : (valor) => setState(() => _obligatorio = valor),
                  contentPadding: EdgeInsets.zero,
                  title: Text('Obligatorio', style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    condicional
                        ? 'No se puede marcar: su obligatoriedad la decide la '
                            'respuesta previa del aspirante.'
                        : 'El formulario no dejará enviar sin responderlo.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (condicional) ...[
                  const SizedBox(height: 8),
                  // Antes esto era una advertencia sobre algo que el panel SÍ
                  // permitía hacer y que rompía la inscripción al final —el
                  // aspirante rellenaba los nueve pasos y el alta fallaba con un
                  // 23514 nombrando un campo que nunca vio—. Ahora describe lo
                  // que ocurre, porque ya no se puede provocar.
                  const AvisoEnLinea(
                    texto:
                        'Este campo depende de otro: sólo se muestra cuando la '
                        'condición se cumple, y sólo se exige mientras está '
                        'visible. Si el aspirante no activa la condición, el '
                        'campo no aparece y no se le pide.',
                    tono: TonoAviso.info,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviar,
          child: Text(_esNuevo ? 'Añadir' : 'Guardar'),
        ),
      ],
    );
  }
}

/// Un valor que no se puede cambiar, mostrado como dato y no como campo.
class _DatoFijo extends StatelessWidget {
  const _DatoFijo({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                valor,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Text(
              'no editable',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
