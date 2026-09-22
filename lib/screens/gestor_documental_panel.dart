import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/errors/app_exception.dart';
import '../core/gateways/selector_archivos.dart';
import '../models/archivo.dart';
import '../repositories/archivos_repository.dart';
import '../services/selector_archivos_navegador.dart';
import '../theme/inces_theme.dart';
import '../widgets/comunes.dart';

/// Los formatos que el servidor acepta, escritos como los reconoce el usuario.
///
/// **Es un espejo, no la fuente de verdad.** La lista real vive en
/// `TIPOS_PERMITIDOS` (`backend/src/dominio/almacenamiento.ts`) y es el servidor
/// quien rechaza: esto sólo evita que alguien elija un `.zip` y se entere después
/// de subirlo entero. Si las dos listas se separan, gana la del servidor y el
/// usuario ve un error en vez de un éxito — molesto, no peligroso. Por eso no se
/// filtra el diálogo del sistema con esta lista: el filtro del navegador es
/// cosmético y confiar en él daría una falsa sensación de que aquí se valida algo.
const String _formatosAdmitidos = 'PDF, JPG, PNG, WEBP, DOCX, XLSX o PPTX';

/// Gestor documental — Capa 7 del Módulo 5.
///
/// Sube archivos a Cloudflare R2 en **tres pasos** y los deja gestionables en la
/// misma pantalla: descargar y borrar.
///
/// **Por qué orquesta los tres pasos a mano en vez de llamar a `subir()`.** El
/// gateway ofrece `subir()` —los tres pasos de una vez— pero también los pasos
/// sueltos, y aquí se usan los sueltos por dos razones que se ven en pantalla:
///
/// 1. **Progreso honesto.** «Firmando…», «Subiendo…» y «Confirmando…» son tres
///    esperas de naturaleza distinta. Con `subir()` sólo se puede decir
///    «subiendo…» durante todo el proceso, y el usuario no sabe si la aplicación
///    avanzó o se colgó.
/// 2. **Reintento barato.** Si el `PUT` a R2 se corta, la fila sigue `PENDING`
///    con su clave ya reservada. Conservando la firma, reintentar repite el paso
///    2 en vez de crear **otra** reserva y dejar la primera abandonada — que es
///    justo la basura que el barrido de `PENDING` existe para recoger.
///
/// **La lista se hidrata del servidor.** Al montarse, el panel pide los archivos
/// de la entidad y pinta los que ya estaban guardados; lo que se sube después se
/// añade arriba. Antes esto no se podía: M5 firmaba, confirmaba, daba URL de
/// lectura y borraba, pero **no listaba**, así que la lista era de sesión y al
/// recargar la página parecía que no había nada guardado.
///
/// **Cuando no hay entidad no se pide nada, y se dice por qué.** Con `entidadId`
/// nulo no existe la pregunta que esa ruta responde —«los archivos de esta
/// tarea»—, así que pedirla daría un 400. En ese caso el panel funciona en modo
/// sólo-subida y lo explica, en lugar de fingir que la lista está vacía porque no
/// hay archivos.
class GestorDocumentalPanel extends StatefulWidget {
  const GestorDocumentalPanel({
    super.key,
    required this.entityType,
    this.entidadId,
    this.titulo,
    this.subtitulo,
    this.repositorio,
    this.selector,
  });

  /// Qué clase de archivo se gestiona aquí. Decide el `CHECK` del servidor, así
  /// que no es decorativo: `TASK_SUBMISSION` para entregas, `TEACHER_GUIDE` para
  /// material de apoyo.
  final TipoEntidadArchivo entityType;

  /// Tarea o guía concreta. `null` es legítimo y frecuente: un archivo puede
  /// subirse antes de que la entidad exista, y entonces el servidor no aplica el
  /// tope por entidad.
  final String? entidadId;

  final String? titulo;
  final String? subtitulo;

  final ArchivosRepository? repositorio;

  /// El diálogo de archivos. Se inyecta porque la implementación real es del
  /// navegador y no compila en la VM — ver `selector_archivos.dart`.
  final SelectorDeArchivos? selector;

  @override
  State<GestorDocumentalPanel> createState() => _GestorDocumentalPanelState();
}

/// En qué paso de la subida está la pantalla.
///
/// Es un enum y no tres banderas booleanas porque los tres pasos son
/// **excluyentes**: con tres `bool` existe el estado imposible «firmando y
/// confirmando a la vez», y alguien acabará pintándolo.
enum _Paso { ninguno, firmando, subiendo, confirmando }

extension on _Paso {
  String get etiqueta => switch (this) {
        _Paso.ninguno => '',
        _Paso.firmando => 'Preparando la subida…',
        _Paso.subiendo => 'Subiendo el archivo…',
        _Paso.confirmando => 'Verificando el archivo…',
      };
}

class _GestorDocumentalPanelState extends State<GestorDocumentalPanel> {
  late final ArchivosRepository _repo =
      widget.repositorio ?? ArchivosRepository();
  late final SelectorDeArchivos _selector =
      widget.selector ?? SelectorDeArchivosDelNavegador();

  /// Lo que el usuario eligió y todavía no se ha subido.
  ArchivoElegido? _elegido;

  /// El resultado del paso 1 cuando ya se firmó pero el `PUT` no ha terminado.
  /// Se conserva entre reintentos a propósito: ver la nota de la clase.
  SubidaFirmada? _firmada;

  _Paso _paso = _Paso.ninguno;

  String? _error;

  /// Qué puede hacer el usuario, además de leer el error. Un mensaje sin salida
  /// deja la pantalla en un callejón.
  String? _sugerencia;

  /// El código del último fallo del servidor, si lo traía.
  ///
  /// Existe por una sola decisión: si «Reintentar subida» puede servir de algo.
  /// Tras un `ARCHIVO_DEMASIADO_GRANDE` el objeto ya está en R2 y su tamaño no
  /// va a cambiar, así que repetir el `PUT` y el `HeadObject` devuelve el mismo
  /// rechazo. Ofrecer ese botón sería ofrecer un botón que no funciona; lo
  /// honesto es pedir otro archivo, que es justo lo que dice la sugerencia.
  String? _codigoFallo;

  /// Los archivos de la entidad: lo que ya estaba guardado, más lo subido en esta
  /// visita. El orden es del más reciente al más antiguo, que es el que devuelve
  /// la ruta y el que espera quien acaba de subir algo.
  final List<Archivo> _archivos = [];

  /// Si la carga inicial sigue en curso.
  ///
  /// Es una bandera **distinta** de `_paso`: aquélla describe la subida y ésta la
  /// lectura. Mezclarlas haría que una carga lenta pareciera una subida en curso.
  bool _cargandoLista = false;

  /// El fallo de la carga inicial, si lo hubo.
  ///
  /// Se guarda aparte de `_error` a propósito: un fallo de lectura **no** invalida
  /// la tarjeta de subida, y volcarlo en `_error` dejaría la pantalla diciendo que
  /// algo se rompió cuando subir sigue funcionando perfectamente.
  String? _errorLista;

  /// Ids con una descarga o un borrado en curso. Es un conjunto y no una bandera
  /// única: dos filas pueden estar ocupadas a la vez y cada botón debe reflejar
  /// sólo la suya.
  final Set<String> _ocupados = <String>{};

  bool _eligiendo = false;

  bool get _subiendo => _paso != _Paso.ninguno;

  /// ¿Volver a pulsar «subir» con el mismo archivo puede cambiar algo?
  ///
  /// `false` sólo para el 413: los bytes ya viajaron y el servidor ya los midió,
  /// así que el mismo archivo da el mismo rechazo. El resto de fallos —una red
  /// que se cae, un `PUT` cortado, un 5xx al confirmar— sí pueden resolverse
  /// repitiendo, y por eso conservan el reintento.
  bool get _reintentoUtil => _codigoFallo != 'ARCHIVO_DEMASIADO_GRANDE';

  /// La etiqueta del botón principal cuando ya hay un archivo elegido.
  ///
  /// «Elegir otro archivo» no es un adorno: cambia la acción, no sólo el texto.
  /// Ver [_reintentoUtil].
  String get _etiquetaAccion {
    if (!_reintentoUtil) return 'Elegir otro archivo';
    return _firmada == null ? 'Subir' : 'Reintentar subida';
  }

  /// ¿Esta vista puede listar lo ya guardado?
  ///
  /// Sin entidad, no: la ruta pregunta por los archivos de una tarea o una guía
  /// concreta, y un id nulo no es una pregunta válida. Se comprueba aquí en vez
  /// de intentar la petición, para no gastar un viaje en un 400 anunciado.
  bool get _puedeListar => widget.entidadId != null;

  @override
  void initState() {
    super.initState();
    // La bandera se pone **sin `setState`**: en `initState` el widget todavía no
    // se ha construido, así que no hay nada que reconstruir. Llamar a `setState`
    // aquí funcionaría por accidente hoy y empezaría a avisar de «setState
    // durante la construcción» en cuanto alguien moviera un `await` por delante.
    _cargandoLista = _puedeListar;
    _cargarLista();
  }

  /// Trae los archivos que ya estaban guardados.
  ///
  /// **No bloquea la pantalla si falla.** Perder la lista es una molestia;
  /// impedir subir sería convertir un fallo de lectura en una pantalla muerta.
  Future<void> _cargarLista() async {
    final entidadId = widget.entidadId;
    if (entidadId == null) return;

    final resultado = await _repo.listarPorEntidad(
      entityType: widget.entityType,
      entidadId: entidadId,
    );

    if (!mounted) return;

    setState(() {
      _cargandoLista = false;
      resultado.when(
        success: (archivos) {
          // Se reemplaza la lista entera en vez de añadir: lo que hubiera venía de
          // esta misma fuente, y concatenar duplicaría cada archivo en la segunda
          // carga.
          _archivos
            ..clear()
            ..addAll(archivos);
        },
        failure: (fallo) => _errorLista = fallo.message,
      );
    });
  }

  @override
  void dispose() {
    // Nada que liberar hoy —no hay controladores—, pero el panel crece con
    // estado propio: dejarlo explícito evita que el próximo que añada un
    // `TextEditingController` olvide el `dispose`.
    super.dispose();
  }

  // ── Paso 0: elegir ─────────────────────────────────────────────────────────

  Future<void> _elegir() async {
    if (_eligiendo || _subiendo) return;

    setState(() {
      _eligiendo = true;
      _error = null;
      _sugerencia = null;
      // El veredicto anterior era sobre el archivo anterior.
      _codigoFallo = null;
    });

    // Se captura el elegido y se libera el estado ANTES de comprobar `mounted`:
    // al revés, un desmontaje durante el diálogo dejaría el botón bloqueado para
    // siempre en la siguiente visita.
    ArchivoElegido? elegido;
    Object? fallo;
    try {
      elegido = await _selector.elegir();
    } catch (e) {
      fallo = e;
    }

    if (!mounted) return;
    setState(() {
      _eligiendo = false;
      if (fallo != null) {
        _error = 'No pudimos abrir el selector de archivos.';
        _sugerencia = 'Recarga la página e inténtalo de nuevo.';
      } else if (elegido != null) {
        // Elegir un archivo nuevo descarta la firma anterior: pertenecía a otro
        // nombre y a otra clave.
        _elegido = elegido;
        _firmada = null;
      }
    });
  }

  void _descartar() {
    if (_subiendo) return;
    setState(() {
      _elegido = null;
      _firmada = null;
      _error = null;
      _sugerencia = null;
      _codigoFallo = null;
    });
  }

  // ── Pasos 1-3: firmar, subir, confirmar ────────────────────────────────────

  Future<void> _subir() async {
    if (_subiendo || _eligiendo) return;
    final elegido = _elegido;
    if (elegido == null) return;

    setState(() {
      _error = null;
      _sugerencia = null;
      // Se reintenta: el veredicto del intento anterior ya no aplica.
      _codigoFallo = null;
    });

    // Paso 1. Se salta si ya hay una firma viva: es el caso del reintento tras
    // un `PUT` cortado.
    var firmada = _firmada;
    if (firmada == null) {
      setState(() => _paso = _Paso.firmando);

      final resultado = await _repo.firmarSubida(
        nombreOriginal: elegido.nombre,
        entityType: widget.entityType,
        entidadId: widget.entidadId,
      );

      if (!mounted) return;

      final falloFirma = resultado.errorOrNull;
      if (falloFirma != null) {
        setState(() {
          _paso = _Paso.ninguno;
          _error = falloFirma.message;
          _sugerencia = _sugerenciaPara(falloFirma);
          _codigoFallo = falloFirma.code;
        });
        return;
      }

      firmada = resultado.valueOrNull!;
      setState(() => _firmada = firmada);
    }

    // Paso 2. El `PUT` va DIRECTO a R2, no al backend. El `Content-Type` es el
    // que el servidor firmó —`firmada.archivo.tipoContenido`— y no uno deducido
    // aquí: la URL prefirmada cubre ese encabezado, así que mandar otro hace que
    // R2 rechace la firma.
    setState(() => _paso = _Paso.subiendo);

    final resultadoSubida = await _repo.subirObjeto(
      urlDeSubida: firmada.urlDeSubida,
      tipoContenido: firmada.archivo.tipoContenido,
      contenido: elegido.contenido,
    );

    if (!mounted) return;

    final falloSubida = resultadoSubida.errorOrNull;
    if (falloSubida != null) {
      // La firma se conserva: la fila sigue `PENDING` y reintentar debe repetir
      // este paso, no reservar otra clave.
      setState(() {
        _paso = _Paso.ninguno;
        _error = falloSubida.message;
        _sugerencia = 'La reserva sigue hecha: pulsa «Reintentar subida».';
        _codigoFallo = falloSubida.code;
      });
      return;
    }

    // Paso 3. Aquí es donde el servidor mide el objeto de verdad y aplica el
    // límite de tamaño: una URL `PUT` prefirmada no admite `content-length-range`.
    setState(() => _paso = _Paso.confirmando);

    final resultadoConfirmar = await _repo.confirmar(firmada.archivo.id);

    if (!mounted) return;

    resultadoConfirmar.when(
      success: (archivo) {
        setState(() {
          _paso = _Paso.ninguno;
          _archivos.insert(0, archivo);
          _elegido = null;
          _firmada = null;
          _error = null;
          _sugerencia = null;
          _codigoFallo = null;
        });
        mostrarAviso(context, 'Archivo subido y verificado.', exito: true);
      },
      failure: (fallo) {
        setState(() {
          _paso = _Paso.ninguno;
          _error = fallo.message;
          _sugerencia = _sugerenciaPara(fallo);
          _codigoFallo = fallo.code;
        });
      },
    );
  }

  /// Qué puede hacer el usuario ante cada fallo concreto.
  ///
  /// El código es lo que separa los casos: «demasiado grande» y «la subida se
  /// cortó» son los dos un 4xx, y con el mensaje solo el usuario no sabe si debe
  /// elegir otro archivo o volver a intentarlo.
  String? _sugerenciaPara(AppException fallo) => switch (fallo.code) {
        'ARCHIVO_DEMASIADO_GRANDE' =>
          'Elige un archivo más pequeño y vuelve a intentarlo.',
        'OBJETO_NO_SUBIDO' =>
          'La subida no llegó a completarse. Pulsa «Reintentar subida».',
        'SUBIDA_RECHAZADA' =>
          'El almacenamiento rechazó la subida. Pulsa «Reintentar subida»; si '
              'vuelve a fallar, descarta el archivo y elígelo de nuevo.',
        'ESTADO_DE_ARCHIVO' =>
          'Ese archivo ya no admite cambios. Descártalo y elige otro.',
        // El servidor devuelve `PETICION_INVALIDA` tanto si falta la extensión
        // como si no está en la lista blanca. El nombre del archivo se elige
        // aquí, así que éste es el único 400 que el usuario puede corregir solo.
        'PETICION_INVALIDA' =>
          'Comprueba que el nombre termina en $_formatosAdmitidos.',
        _ => fallo.esRecuperable ? 'Inténtalo de nuevo.' : null,
      };

  // ── Descargar y borrar ─────────────────────────────────────────────────────

  Future<void> _descargar(Archivo archivo) async {
    if (_ocupados.contains(archivo.id)) return;

    setState(() => _ocupados.add(archivo.id));

    final resultado = await _repo.urlDeLectura(archivo.id);

    if (!mounted) return;

    final lectura = resultado.valueOrNull;
    if (lectura == null) {
      setState(() => _ocupados.remove(archivo.id));
      final fallo = resultado.errorOrNull!;
      mostrarAviso(context, fallo.message, error: true);
      return;
    }

    try {
      await _selector.descargar(
        url: lectura.urlDeLectura,
        nombre: lectura.nombreOriginal,
      );
    } catch (_) {
      if (mounted) {
        mostrarAviso(context, 'No pudimos abrir la descarga.', error: true);
      }
    }

    if (!mounted) return;
    setState(() => _ocupados.remove(archivo.id));
  }

  Future<void> _borrar(Archivo archivo) async {
    if (_ocupados.contains(archivo.id)) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('¿Borrar el archivo?'),
        content: Text(
          '«${archivo.nombreOriginal}» se quitará del almacenamiento. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    setState(() => _ocupados.add(archivo.id));

    final resultado = await _repo.borrar(archivo.id);

    if (!mounted) return;

    setState(() {
      _ocupados.remove(archivo.id);
      // Se marca como borrado en la lista en vez de quitarlo: el historial de la
      // sesión deja de ser un misterio cuando algo desaparece sin explicación.
      resultado.when(
        success: (borrado) {
          final indice = _archivos.indexWhere((a) => a.id == borrado.id);
          if (indice >= 0) _archivos[indice] = borrado;
        },
        failure: (_) {},
      );
    });

    resultado.when(
      success: (_) => mostrarAviso(context, 'Archivo borrado.', exito: true),
      failure: (fallo) => mostrarAviso(context, fallo.message, error: true),
    );
  }

  // ── Interfaz ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = widget.titulo ??
        switch (widget.entityType) {
          TipoEntidadArchivo.taskSubmission => 'Mis entregas',
          TipoEntidadArchivo.teacherGuide => 'Material de apoyo',
        };

    // Raíz desplazable: `ContenidoSeccion` entrega una altura **acotada**, y este
    // panel crece con su contenido (aviso, tarjeta de subida, lista). Con un
    // `Column` a secas, el final quedaría recortado en una ventana baja.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TituloSeccion(
          titulo,
          subtitulo: widget.subtitulo ??
              'Sube el archivo y quedará guardado en el almacenamiento del '
                  'centro.',
        ),
        const SizedBox(height: 16),
        // El aviso de «la lista es de sesión» se retiró al llegar la ruta de
        // listado: la lista ya no es de sesión. Sólo queda el caso en que de
        // verdad no se puede listar —una vista sin entidad—, y ahí sigue siendo
        // cierto y necesario.
        if (!_puedeListar)
          const AvisoEnLinea(
            tono: TonoAviso.advertencia,
            icono: Icons.info_outline,
            texto: 'Esta vista todavía no está atada a una tarea o una guía '
                'concreta, así que sólo muestra lo que subas ahora. Cuando el '
                'Aula Virtual publique la entidad, aparecerá aquí todo lo '
                'guardado.',
          ),
        const SizedBox(height: 20),
        _tarjetaDeSubida(theme),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _cajaDeError(theme),
        ],
        const SizedBox(height: 24),
        _listaDeArchivos(theme),
      ],
    );
  }

  Widget _tarjetaDeSubida(ThemeData theme) {
    final elegido = _elegido;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Subir un archivo', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 14),
            if (elegido == null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: (_eligiendo || _subiendo) ? null : _elegir,
                  icon: _eligiendo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Elegir archivo'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Formatos admitidos: $_formatosAdmitidos.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              _fichaDelElegido(theme, elegido),
              const SizedBox(height: 14),
              if (_subiendo)
                _progreso(theme)
              else
                Row(
                  children: [
                    FilledButton.icon(
                      // Con un 413 el botón deja de subir y pasa a elegir: el
                      // texto y la acción cambian juntos, que es lo que evita
                      // un botón que promete algo que no puede cumplir.
                      onPressed: _reintentoUtil ? _subir : _elegir,
                      icon: Icon(
                        _reintentoUtil
                            ? Icons.cloud_upload_outlined
                            : Icons.folder_open_outlined,
                        size: 18,
                      ),
                      label: Text(_etiquetaAccion),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _descartar,
                      child: const Text('Descartar'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fichaDelElegido(ThemeData theme, ArchivoElegido elegido) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  elegido.nombre,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  formatearBytes(elegido.bytes),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progreso(ThemeData theme) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          _paso.etiqueta,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _cajaDeError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IncesTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(IncesTheme.radioControl),
        border: Border.all(color: IncesTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: IncesTheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: IncesTheme.error,
                  ),
                ),
                if (_sugerencia != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _sugerencia!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaDeArchivos(ThemeData theme) {
    // La carga va primero: mientras no se sepa qué hay guardado, decir «todavía
    // no has subido archivos» sería afirmar algo que aún no se comprobó.
    if (_cargandoLista) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Un fallo de lectura se muestra **sin** sustituir la pantalla: la tarjeta de
    // subida sigue ahí y sigue funcionando. Por eso es un aviso y no un
    // `PanelVacio`: el panel no está vacío, está incompleto.
    if (_errorLista != null) {
      return AvisoEnLinea(
        tono: TonoAviso.peligro,
        icono: Icons.cloud_off_outlined,
        texto: 'No pudimos cargar los archivos ya guardados: $_errorLista '
            'Puedes seguir subiendo; la lista se completará al recargar.',
      );
    }

    if (_archivos.isEmpty) {
      return PanelVacio(
        titulo: _puedeListar
            ? 'Todavía no hay archivos aquí'
            : 'Todavía no has subido archivos',
        mensaje: 'Los archivos que subas aparecerán aquí con su tamaño y su '
            'estado, listos para descargar o borrar.',
        icono: Icons.folder_open_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Archivos guardados',
          subtitulo: '${_archivos.length} archivo(s).',
        ),
        const SizedBox(height: 4),
        for (final archivo in _archivos) _fila(theme, archivo),
      ],
    );
  }

  Widget _fila(ThemeData theme, Archivo archivo) {
    final ocupado = _ocupados.contains(archivo.id);
    final borrado = archivo.estado == EstadoArchivo.deleted;
    final legible = archivo.estado.esLegible;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              legible ? Icons.picture_as_pdf_outlined : Icons.schedule_outlined,
              size: 20,
              color: legible
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    archivo.nombreOriginal,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: borrado ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Etiqueta(
                        texto: _etiquetaEstado(archivo.estado),
                        destacada: legible,
                      ),
                      if (archivo.tamanoBytes != null)
                        Etiqueta(texto: formatearBytes(archivo.tamanoBytes!)),
                      Etiqueta(
                        texto: formatearFechaHora(
                          DateTime.tryParse(archivo.creadoEn),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (ocupado)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!borrado) ...[
              // Un `PENDING` no tiene objeto verificado que descargar: la ruta
              // de lectura exigiría una fila `CONFIRMED`. Ofrecer el botón
              // llevaría a un 404 que el usuario no puede entender.
              IconButton(
                onPressed: legible ? () => _descargar(archivo) : null,
                icon: const Icon(Icons.download_outlined, size: 20),
                tooltip: legible
                    ? 'Descargar'
                    : 'El archivo aún no está confirmado',
              ),
              IconButton(
                onPressed: () => _borrar(archivo),
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: IncesTheme.error,
                ),
                tooltip: 'Borrar',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _etiquetaEstado(EstadoArchivo estado) => switch (estado) {
        EstadoArchivo.pending => 'Sin confirmar',
        EstadoArchivo.confirmed => 'Confirmado',
        EstadoArchivo.deleted => 'Borrado',
      };
}

/// Tamaño legible sin depender de `intl`, igual que `formatearFechaHora`.
///
/// Usa 1024 y no 1000 porque es lo que el usuario ve en el explorador de
/// archivos, y comparar dos cifras que discrepan en un 2,4 % genera dudas
/// innecesarias sobre si el archivo se subió entero.
String formatearBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const unidades = ['KB', 'MB', 'GB'];
  var valor = bytes / 1024;
  var unidad = 0;
  while (valor >= 1024 && unidad < unidades.length - 1) {
    valor /= 1024;
    unidad++;
  }
  // Un decimal hasta 100, ninguno por encima: «9,8 MB» informa y «980,4 MB»
  // sólo ocupa sitio.
  final texto = valor >= 100 ? valor.round().toString() : valor.toStringAsFixed(1);
  return '${texto.replaceAll('.', ',')} ${unidades[unidad]}';
}
