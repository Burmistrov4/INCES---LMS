import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/result.dart';
import '../models/inscripcion.dart';
import '../repositories/inscripcion_repository.dart';
import '../theme/inces_theme.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';

/// «Mis inscripciones» del estudiante — Módulo 4, capa estudiante.
///
/// **Qué muestra.** Una tarjeta por inscripción, con su estado en el ciclo de
/// cupos del backend: `ENROLLED` (con asiento), `PENDING_BID` (el sistema le
/// ofreció un cupo y espera respuesta), `WAITLISTED` (en la cola, con su
/// posición) y `DROPPED` (renunció; la fila se conserva como historial).
///
/// **El código de color no es decorativo: es la jerarquía de urgencia.** Un
/// estado que exige una acción **con fecha límite** tiene que gritar; uno que
/// sólo informa tiene que callar. Por eso:
///
///   · `PENDING_BID` → **ámbar** (`PaletaInces.advertencia`). Es el único estado
///     que caduca: si el alumno no lo ve, pierde el cupo y vuelve a la cola.
///   · `ENROLLED` → **verde** (`PaletaInces.exito`). Resuelto, nada que hacer.
///   · `WAITLISTED` → **azul** (`PaletaInces.info`). Espera informativa: hay una
///     posición, pero no hay nada que pulsar salvo renunciar.
///   · `DROPPED` → **gris** (`ColorScheme.onSurfaceVariant`). Historial apagado.
///
/// Los tres acentos de estado son los de `PaletaInces` y **no** los de
/// `IncesTheme` porque el chip los pinta como letra sobre su propio tinte, y ahí
/// los colores de relleno no llegan a AA en ninguno de los dos brillos. Medido el
/// 2026-09-30: verde 2.65:1 en claro, ámbar 1.81:1 en claro, azul 2.54:1 en
/// oscuro.
///
/// **Por qué los colores estaban al revés, y qué costaba.** La versión anterior
/// pintaba `WAITLISTED` en ámbar y `PENDING_BID` en azul: el estado pasivo
/// gritaba y el urgente susurraba. No rompía ninguna prueba —ninguna afirmaba
/// sobre el color— pero es exactamente el fallo que cuesta un cupo, porque el
/// alumno que mira la lista no ve cuál de las filas le está pidiendo algo.
///
/// **El orden también es urgencia.** [_ordenadas] pone primero lo que exige
/// acción, y no el orden que devuelva el servidor.
///
/// **Por qué vive en su propio archivo.** El panel del estudiante
/// (`aspirante_dashboard.dart`) es navegación: un menú, un `switch` por título y
/// el cableado de cada sección. Este panel es la lógica de un ciclo de estados
/// con cuenta regresiva, acciones en vuelo y orden por urgencia. Estaban en el
/// mismo archivo y crecían por razones distintas.
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

  /// Secciones con una acción en vuelo (aceptar o renunciar). Es un conjunto de
  /// **secciones** y no un booleano global: con un booleano, pulsar «Aceptar» en
  /// una tarjeta deshabilitaba los botones de todas las demás.
  final Set<String> _actuando = {};

  /// Refresca la cuenta regresiva de las ofertas `PENDING_BID` una vez por
  /// segundo. Sólo provoca `setState` (re-pinta); no vuelve a pedir datos.
  ///
  /// **Sólo corre si hay alguna oferta viva** ([_sincronizarTemporizador]). Antes
  /// latía siempre, así que un alumno con todo `ENROLLED` repintaba el panel 60
  /// veces por minuto para no cambiar ni un píxel.
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _cargar();
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

    _sincronizarTemporizador();
  }

  /// Enciende el reloj sólo si hay algo que contar hacia atrás, y lo apaga
  /// cuando deja de haberlo. Se llama **después** de cada carga porque la lista
  /// puede haber cambiado: aceptar la última oferta viva debe apagar el reloj.
  void _sincronizarTemporizador() {
    final hayOfertaViva = _inscripciones.any((i) => i.estado.esOfertaViva);

    if (hayOfertaViva && _temporizador == null) {
      _temporizador = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hayOfertaViva && _temporizador != null) {
      _temporizador!.cancel();
      _temporizador = null;
    }
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

  /// Las inscripciones **ordenadas por urgencia**, no como llegan.
  ///
  /// `PENDING_BID` primero porque es el único estado con fecha límite:
  /// `WAITLISTED` después (espera), luego `ENROLLED` (ya resuelto) y `DROPPED`
  /// al final (historial).
  ///
  /// `List.sort` **no es estable** en Dart, así que la comparación desempata por
  /// el índice original: sin eso, dos filas del mismo estado podrían barajarse
  /// entre repintados, y con el reloj de la cuenta regresiva repintando cada
  /// segundo la lista temblaría.
  List<InscripcionDetallada> get _ordenadas {
    final conIndice = _inscripciones.indexed.toList();

    conIndice.sort((a, b) {
      final porUrgencia = _urgencia(a.$2.estado).compareTo(_urgencia(b.$2.estado));
      return porUrgencia != 0 ? porUrgencia : a.$1.compareTo(b.$1);
    });

    return [for (final (_, inscripcion) in conIndice) inscripcion];
  }

  /// Menor número = más arriba. El orden es el del comentario de [_ordenadas].
  static int _urgencia(EstadoInscripcion estado) => switch (estado) {
        EstadoInscripcion.pendingBid => 0,
        EstadoInscripcion.waitlisted => 1,
        EstadoInscripcion.enrolled => 2,
        EstadoInscripcion.dropped => 3,
      };

  /// Cuántas ofertas esperan respuesta. Alimenta el aviso de la cabecera.
  int get _ofertasPendientes =>
      _inscripciones.where((i) => i.estado.esOfertaViva).length;

  @override
  Widget build(BuildContext context) {
    return ContenidoSeccion(
      migas: const ['Inicio', 'Académico', 'Mis inscripciones'],
      // `EstadoPanel` es el manejo de error del proyecto: mientras carga, un
      // indicador; si falló, «No pudimos cargar esta sección» con un botón
      // «Reintentar»; y nunca una pantalla roja. El mensaje del fallo es el que
      // dio el backend, no un texto genérico.
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

    final pendientes = _ofertasPendientes;

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

        // Aviso de cabecera: si hay ofertas vivas, se dice **arriba y en
        // palabras**, no sólo con el color de una insignia. Es la última red
        // contra «no vi que tenía que aceptar» — el error que cuesta el cupo.
        if (pendientes > 0) ...[
          AvisoEnLinea(
            texto: pendientes == 1
                ? 'Tienes una oferta de cupo esperando respuesta. Acéptala antes '
                    'de que venza o volverás a la lista de espera.'
                : 'Tienes $pendientes ofertas de cupo esperando respuesta. '
                    'Acéptalas antes de que venzan o volverás a la lista de espera.',
            icono: Icons.notification_important_outlined,
            tono: TonoAviso.advertencia,
          ),
          const SizedBox(height: 12),
        ],

        // `Flexible` y no el scroll suelto. **En un `Column`, un hijo no
        // flexible recibe la altura del eje principal como *ilimitada***, así
        // que el `SingleChildScrollView` se dimensionaba a su contenido entero
        // en vez de a lo que sobra, y desbordaba el alto acotado que le entrega
        // `ContenidoSeccion`. Con `Flexible` (ajuste holgado, no `Expanded`)
        // recibe la altura restante y desplaza dentro.
        //
        // Medido: dos tarjetas más el aviso de cabecera desbordaban **52 px** a
        // 800×600. Lo destaparon —de rebote— las dos pruebas de urgencia, que
        // montan dos inscripciones; las de una sola pasaban. El aviso de
        // cabecera que se añadió arriba fue lo que terminó de desbordar una
        // estructura que ya estaba al límite.
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final i in _ordenadas) _tarjetaInscripcion(i),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaInscripcion(InscripcionDetallada i) {
    final theme = Theme.of(context);
    final ocupado = _actuando.contains(i.seccionId);
    final titulo = i.materiaNombre ?? i.seccionNombre;

    // La tarjeta que exige acción se distingue del resto de un vistazo: borde
    // ámbar y fondo apenas teñido. Sólo se aplica a `PENDING_BID`, así que el
    // énfasis conserva su valor — si todas las tarjetas lo llevaran, no
    // señalaría ninguna.
    final exigeAccion = i.estado.esOfertaViva;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: exigeAccion ? IncesTheme.advertencia.withValues(alpha: 0.05) : null,
      shape: exigeAccion
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
              side: BorderSide(
                color: IncesTheme.advertencia.withValues(alpha: 0.55),
                width: 1.5,
              ),
            )
          : null,
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

            // Contexto y acciones específicos de cada estado. El orden de las
            // ramas sigue la urgencia, igual que [_ordenadas].
            if (i.estado.esOfertaViva) ...[
              // La acción primero y a lo ancho: es lo único que esta tarjeta
              // pide, y el botón más grande de la pantalla debe ser el que hay
              // que pulsar.
              _CuentaRegresiva(ofertaVenceEn: i.ofertaVenceEn),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: ocupado ? null : () => _aceptar(i),
                  icon: ocupado
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(ocupado ? 'Aceptando…' : 'Aceptar cupo'),
                ),
              ),
              const SizedBox(height: 8),
              // Renunciar existe, pero es secundario: no compite en tamaño con
              // aceptar. Un alumno que renuncia por error pierde el cupo.
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _renunciar(i),
                  icon: const Icon(Icons.exit_to_app_outlined, size: 16),
                  label: const Text('Renunciar'),
                ),
              ),
            ] else if (i.estado.enCola) ...[
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
///
/// El color sale del mapa de urgencia documentado en [PanelMisInscripciones]: el
/// ámbar se reserva para `PENDING_BID`, que es el único estado con fecha límite.
class _InsigniaEstado extends StatelessWidget {
  const _InsigniaEstado(this.estado);

  final EstadoInscripcion estado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Los tres acentos de estado salen de la paleta, que sí distingue el brillo.
    // Los de `IncesTheme` son de relleno: como letra sobre su propio tinte, el
    // verde da 2.65:1 en claro, el ámbar 1.81:1 y el azul 2.54:1 en oscuro.
    // Medido el 2026-09-30. El gris se queda como estaba: `onSurfaceVariant` pasa
    // 4.62:1 en el peor de los casos —es, de hecho, el mismo valor que el rol
    // `neutro` de la paleta—, así que no hacía falta moverlo.
    final paleta = PaletaInces.de(context);
    final (color, texto, icono) = switch (estado) {
      EstadoInscripcion.enrolled =>
        (paleta.exito, 'Matriculado', Icons.check_circle_outline),
      // Ámbar y no el azul primario: es el estado que exige acción. Antes iba en
      // azul y el aviso de urgencia se perdía entre los azules de la interfaz.
      EstadoInscripcion.pendingBid =>
        (paleta.advertencia, 'Oferta en el aire', Icons.local_offer_outlined),
      // Azul informativo y no ámbar: en la cola no hay nada que hacer salvo
      // esperar (o renunciar), así que la fila no debe reclamar atención.
      EstadoInscripcion.waitlisted =>
        (paleta.info, 'En cola', Icons.people_outline),
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
/// informamos. Se repinta cada segundo gracias al reloj del panel.
class _CuentaRegresiva extends StatelessWidget {
  const _CuentaRegresiva({required this.ofertaVenceEn});

  final String? ofertaVenceEn;

  @override
  Widget build(BuildContext context) {
    final vence = ofertaVenceEn == null
        ? null
        : DateTime.tryParse(ofertaVenceEn!);

    if (vence == null) {
      return const AvisoEnLinea(
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
