import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../services/asistencia_service.dart';
import '../../theme/inces_theme.dart';
import 'escaner_qr_screen.dart';

/// Marcaje de asistencia del estudiante (M7 · D21).
///
/// **El campo son SEIS DÍGITOS, y eso es una decisión de producto.**
/// Hasta el 2026-09-27 esta pantalla pedía el par completo `<uuid>:<6 dígitos>`
/// —el texto que codifica el QR del docente—, y teclear un UUID a mano no es una
/// interacción: es un castigo. Ahora el alumno escribe lo que ve en la pizarra y
/// el servidor resuelve la sesión.
///
/// **El campo NO lleva `maxLength`, y es la lección de D21 aplicada.**
/// Aquella pantalla tenía `maxLength: 6` **mientras su parser exigía 43
/// caracteres**: `TextField` inserta un `LengthLimitingTextInputFormatter` en
/// cuanto `maxLength != null`, ese formateador **trunca en silencio**, y el
/// resultado fue una pantalla muerta que nadie vio porque no había ninguna prueba
/// que la ejercitara. Volver a poner un tope aquí —aunque hoy el caso común sean
/// seis dígitos— reintroduciría la misma trampa por otra puerta: el día que algo
/// meta el par del QR en este campo, el tope lo recortaría sin decir nada.
///
/// Así que el tope no está: **quien decide qué se escribió es el parser**, que
/// distingue las dos formas y explica lo demás con un mensaje. Un texto que no
/// sirve da un error legible; un texto que sirve pasa. Nunca un recorte mudo.
///
/// **Las dos formas de entrar conviven, y la segunda es para la cámara.** Si el
/// texto trae el par `<uuid>:<6 dígitos>` se usa tal cual —es lo que devolverá el
/// lector de QR, que inyecta el contenido del código sin que nadie teclee—; si
/// trae sólo seis dígitos, se manda sin sesión y la resuelve la base. Y si trae
/// cualquier otra cosa, se dice qué se esperaba en vez de gastar una petición.
///
/// **La cámara ya no es un hueco: está puesta, y con una sola regla de dónde.**
/// `accionAdyacente` se pinta al lado del campo, dentro del mismo `Row`, con el
/// campo en `Expanded`; si nadie lo pasa, el panel dibuja **su propio** botón
/// cuando la plataforma tiene cámara (`plataformaPuedeEscanearQr`: Android, iOS y
/// Web). En macOS, Windows y Linux no se dibuja nada y el campo recupera el ancho
/// entero, que es exactamente como estaba antes de que existiera el escáner.
/// `accionAdyacente` queda como **sustitución explícita** —la usan las pruebas
/// para fijar el layout sin depender de la plataforma anfitriona—, no como el
/// único camino.
///
/// **El escáner sólo rellena el campo; quien decide sigue siendo `_marcar()`.**
/// Es lo que evita una segunda implementación del marcaje: el texto que devuelve
/// la cámara entra por el mismo sitio que el que teclea el alumno, así que la vía
/// del QR y la manual **no pueden divergir**. Esa costura ya estaba descrita y
/// probada antes de que hubiera cámara —`asistencia_paneles_test.dart` inyecta el
/// par con `enterText` «el mismo camino que usará la inyección del escáner»—, de
/// modo que el cableado reutiliza un camino que ya estaba en verde.
///
/// **La ventana de 15 segundos sigue siendo el único guardián serio** y por eso
/// los mensajes de error empujan a mirar la pizarra otra vez en vez de invitar a
/// reintentar lo mismo.
class MarcarAsistenciaPanel extends StatefulWidget {
  const MarcarAsistenciaPanel({
    super.key,
    this.servicio,
    this.accionAdyacente,
    this.abrirEscaner,
  });

  /// Opcional, sólo para las pruebas: inyectar un servicio falso.
  final AsistenciaService? servicio;

  /// Sustituye al botón «Escanear QR» que el panel dibuja por su cuenta.
  ///
  /// `null` por defecto, y entonces manda la plataforma. Se pasa cuando una
  /// prueba quiere fijar el layout del `Row` con un widget conocido sin depender
  /// de qué plataforma esté corriendo el test.
  final Widget? accionAdyacente;

  /// Cómo se abre el escáner. `null` = la pantalla real ([EscanerQrScreen]).
  ///
  /// **Se inyecta porque una prueba de widgets no tiene cámara.** Abrir el
  /// escáner de verdad dentro de una prueba montaría una vista previa que nunca
  /// llega, y lo que hay que ejercitar no es la cámara —eso es del paquete y se
  /// prueba en un dispositivo— sino **qué hace el panel con lo que lee**. Con
  /// esta costura la prueba devuelve el mismo texto que devolvería la cámara y
  /// recorre el camino completo: validar, partir en sesión y código, enviar.
  final AbrirEscaner? abrirEscaner;

  @override
  State<MarcarAsistenciaPanel> createState() => _MarcarAsistenciaPanelState();
}

/// Abre el escáner y devuelve lo leído, o `null` si el alumno eligió escribir.
typedef AbrirEscaner = Future<String?> Function(BuildContext context);

/// El QR que el docente proyecta es `<uuid>:<6 dígitos>`. Esta parte aísla el
/// par: sin UUID válido el cliente no tiene sesión; sin dígitos no tiene código.
///
/// **Sigue viva, y ahora por dos motivos.** Es el contrato del contenido del QR
/// —lo que el lector devolverá tal cual— y `test/asistencia_service_test.dart` lo
/// fija; y desde D21 es la rama que el panel toma cuando el texto trae el par, que
/// es como entrará el escáner. Lo que cambió es quién la alimenta —antes el
/// alumno tecleando, ahora la cámara inyectando—, no lo que significa.
class ParseQr {
  ParseQr({required this.sesionId, required this.codigo});

  final String sesionId;
  final String codigo;

  static ParseQr? de(String texto) {
    final limpio = texto.trim();
    final punto = limpio.indexOf(':');
    if (punto < 1) return null;
    final sesionId = limpio.substring(0, punto);
    final codigo = limpio.substring(punto + 1);
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(sesionId)) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) return null;
    return ParseQr(sesionId: sesionId, codigo: codigo);
  }
}

/// Los seis dígitos del camino manual (D21).
///
/// Se separa de [ParseQr] porque son dos cosas distintas y el día que se añada
/// un tercer formato hay que poder leer cuál falló: [ParseQr] describe un par
/// con sesión, esto describe un código suelto. La forma se valida **también en
/// el servidor** (`asistencia_resolver_codigo` comprueba `^[0-9]{6}$`), y no es
/// duplicación inútil: aquí sirve para no gastar una petición de red en algo que
/// se ve mal a simple vista, y allí para que la regla viaje con la función si
/// alguien la llama por PostgREST de frente.
class CodigoManual {
  const CodigoManual(this.codigo);

  final String codigo;

  static CodigoManual? de(String texto) {
    final limpio = texto.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(limpio)) return null;
    return CodigoManual(limpio);
  }
}

class _MarcarAsistenciaPanelState extends State<MarcarAsistenciaPanel> {
  late final AsistenciaService _servicio = widget.servicio ?? AsistenciaService();
  final _entrada = TextEditingController();

  bool _ocupado = false;

  /// La marca entró ahora mismo.
  bool _marcada = false;

  /// La marca ya estaba: se pulsó dos veces o el alumno se adelantó a sí mismo.
  ///
  /// **No es un error y por eso tiene estado propio.** El servidor responde
  /// `duplicada: true` con un 200 —igual que en la vía del QR—, así que
  /// pintarlo de rojo sería contradecir al servidor y asustar al alumno por algo
  /// que salió bien.
  bool _yaEstaba = false;

  String? _error;

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  /// El campo y el envío comparten la decisión de qué se escribió.
  ///
  /// Las dos formas válidas y el orden importan: primero el par del QR —es más
  /// específico, y un `<uuid>:<dígitos>` nunca es «seis dígitos»— y después los
  /// seis dígitos sueltos. Cualquier otra cosa se explica en la propia pantalla
  /// en vez de mandarse a la red para recibir un «no» más lento.
  Future<void> _marcar() async {
    final texto = _entrada.text.trim();

    final par = ParseQr.de(texto);
    if (par != null) {
      await _enviar(sesionId: par.sesionId, codigo: par.codigo);
      return;
    }

    final manual = CodigoManual.de(texto);
    if (manual != null) {
      await _enviar(codigo: manual.codigo);
      return;
    }

    setState(() {
      // Dos casos, dos mensajes, y **ninguno repite la ayuda de arriba**.
      //
      // La primera versión del mensaje de campo vacío empezaba por «Escribe los
      // seis dígitos…», que es literalmente como empieza la ayuda permanente del
      // panel (la de `build()`, «Escribe los seis dígitos que el docente proyecta
      // en la pizarra»). El alumno pulsaba «Marcar» sin escribir nada y leía, en
      // rojo, casi lo mismo que ya tenía en negro dos centímetros más arriba: el
      // mensaje no le decía nada nuevo. Se midió **por accidente útil** —una
      // prueba que buscaba ese texto encontró dos coincidencias y se cayó en CI—,
      // y el «is too many» era el síntoma de una redundancia real, no del test.
      //
      // Lo que separa a los dos casos es **qué hacer a continuación**: si no hay
      // nada escrito, escribir; si hay algo que no sirve, revisarlo.
      _error = texto.isEmpty
          ? 'El campo está vacío: escribe el código de la pizarra.'
          : 'El código son seis dígitos. Revisa lo que escribiste.';
    });
  }

  /// Lee un QR y lo trata **como si el alumno lo hubiera escrito**.
  ///
  /// No hay una segunda implementación del marcaje: el texto entra en el campo y
  /// se llama a [_marcar], que es la función que ya elige entre las dos formas.
  /// Así la vía de la cámara y la del teclado no pueden divergir.
  ///
  /// **Se escribe en el campo aunque el par del QR sea largo y feo de ver.**
  /// Son 43 caracteres en un campo centrado y con `letterSpacing: 8`, así que se
  /// ve mal durante el instante que tarda la petición. Se acepta a cambio de no
  /// tener dos caminos de marcaje, y el caso feo de verdad —que la marca falle
  /// porque el código caducó— no deja al alumno atrapado: lo que va a hacer es
  /// volver a apuntar con la cámara, que sobrescribe el campo, no editarlo.
  Future<void> _escanear() async {
    final abrir = widget.abrirEscaner ?? _abrirEscanerPorDefecto;
    final leido = await abrir(context);
    if (!mounted || leido == null) return;

    // El panel **no se fía de la costura.** Dentro del escáner el validador ya
    // dijo que sí, pero `abrirEscaner` es inyectable —una prueba, o el día que
    // haya otra implementación, pueden devolver cualquier cosa—, y mandar a la
    // red algo que no es un par sería pedirle a la base un «no» lento por un
    // fallo del cliente.
    if (ParseQr.de(leido) == null) {
      setState(() {
        _error = 'Ese código no es un QR de asistencia del INCES.';
      });
      return;
    }

    _entrada.text = leido;
    await _marcar();
  }

  /// Abre la pantalla del escáner y espera su veredicto.
  ///
  /// Se le pasa [_esCodigoDeAsistencia] como validador: la regla del panel sobre
  /// qué es un código de asistencia, definida **una sola vez** y usada en los dos
  /// sitios donde hace falta —aquí y en `_marcar`—. Si el escáner aceptara algo
  /// que `_marcar` luego rechaza, el alumno leería un código y acto seguido un
  /// error del panel.
  Future<String?> _abrirEscanerPorDefecto(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => EscanerQrScreen(validador: _esCodigoDeAsistencia),
      ),
    );
  }

  /// El par del QR y nada más.
  ///
  /// **No basta con «que tenga pinta de UUID»**: un UUID suelto, sin los seis
  /// dígitos, no es un código de asistencia y el servidor no tendría código que
  /// validar. La condición es la misma que abre la rama del QR en [_marcar], y
  /// tiene que serlo — es la única forma de que el veredicto del escáner y el del
  /// panel no se contradigan.
  static bool _esCodigoDeAsistencia(String texto) => ParseQr.de(texto) != null;

  /// El botón «Escanear QR» del panel, o `null` si aquí no hay cámara.
  ///
  /// **Sólo se dibuja en Android, iOS y Web** —la regla vive en
  /// `plataformaPuedeEscanearQr`—. Fuera de ahí devuelve `null` y el campo
  /// recupera el ancho entero: en macOS, Windows y Linux esta pantalla se ve
  /// exactamente igual que antes de que existiera el escáner.
  ///
  /// **`IconButton` y no `FilledButton`, y no es estética.** El único
  /// `FilledButton` de esta pantalla es el de «Marcar», y hay una prueba que lo
  /// busca por tipo —`tester.widget<FilledButton>(find.byType(FilledButton))`,
  /// `asistencia_paneles_test.dart:575`—: un segundo `FilledButton` la haría caer
  /// por ambigüedad. Además es lo que el hueco pide: una acción secundaria pegada
  /// al campo, que no compite con la principal.
  Widget? _botonEscaner({required bool terminado}) {
    if (!plataformaPuedeEscanearQr) return null;
    return IconButton(
      onPressed: _ocupado || terminado ? null : _escanear,
      tooltip: 'Escanear el código QR de la pizarra',
      icon: const Icon(Icons.qr_code_scanner),
    );
  }

  /// Un solo envío para las dos formas; la única diferencia es si va la sesión.
  Future<void> _enviar({String? sesionId, required String codigo}) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });

    // Las dos vías devuelven cosas distintas —la manual sabe si ya estaba, la del
    // QR no—, así que se normalizan al mismo tipo antes de tratar el resultado
    // una sola vez. `when` y no `map`: `map` sobre un `Result<void>` obliga a
    // pasar un valor de tipo `void` a la transformación, y eso es pedirle al
    // analizador que confíe en nosotros.
    final Result<bool> resultado;
    if (sesionId == null) {
      resultado = await _servicio.marcarConCodigo(codigo: codigo);
    } else {
      final porQr = await _servicio.marcar(sesionId: sesionId, codigo: codigo);
      resultado = porQr.when(
        // La vía del QR nunca llega aquí «duplicada»: eso lo dice el servidor en
        // el cuerpo de una respuesta 200, y `marcar` no lo expone. Se asume
        // marca nueva, que es lo que la pantalla pinta.
        success: (_) => const Success<bool>(false),
        failure: (e) => Failure<bool>(e),
      );
    }

    if (!mounted) return;

    resultado.when(
      success: (yaEstaba) => setState(() {
        _ocupado = false;
        _yaEstaba = yaEstaba;
        _marcada = !yaEstaba;
      }),
      // El mensaje se muestra tal como lo manda el servidor. **No se traduce
      // aquí a propósito**: «código caducado», «no hay clase abierta» y «no
      // estás inscrito» los distingue la base —es la única que ve las tres
      // tablas—, y reescribirlos en el cliente crearía una segunda copia que se
      // desviaría en cuanto se afine uno de los tres.
      failure: (e) => setState(() {
        _ocupado = false;
        _error = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terminado = _marcada || _yaEstaba;
    // El icono de 48 px cae sobre la superficie de la tarjeta. Los dos acentos
    // fallaban en modo oscuro: `#16A34A` daba 2.90:1 —por debajo del 3:1 que WCAG
    // pide a un gráfico con significado— y el azul primario, 2.14:1. Medido el
    // 2026-09-30.
    final paleta = PaletaInces.de(context);

    // La sustitución explícita manda; si nadie la pasó, decide la plataforma.
    final accionAdyacente =
        widget.accionAdyacente ?? _botonEscaner(terminado: terminado);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                terminado ? Icons.check_circle : Icons.pin_outlined,
                size: 48,
                color: terminado ? paleta.exito : paleta.info,
              ),
              const SizedBox(height: 8),
              Text(
                _marcada
                    ? 'Listo. Ya cuentas.'
                    : _yaEstaba
                        ? 'Ya estabas contado.'
                        : 'Marca tu asistencia',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _marcada
                    ? 'La marca ya está guardada y el docente la ve en su pantalla.'
                    : _yaEstaba
                        ? 'Tu asistencia en esta clase ya estaba registrada. No hace falta repetirla.'
                        : 'Escribe los seis dígitos que el docente proyecta en la pizarra. Cambian cada pocos segundos.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // --- El campo, y el botón del escáner --------------------------
              //  `Expanded` en el campo y la acción al lado. Sin `Expanded` el
              //  `Row` reventaría en cuanto apareciera el botón, que es la razón
              //  de haber dejado el hueco preparado antes de tener la cámara.
              //  Hoy el botón aparece sólo en Android, iOS y Web; en el resto
              //  `accionAdyacente` es `null` y el campo ocupa todo el ancho.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _entrada,
                      enabled: !terminado && !_ocupado,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Código de la pizarra',
                        hintText: '471212',
                        border: const OutlineInputBorder(),
                        // Sin `counterText`: no hay `maxLength`, así que Material
                        // no pinta contador ninguno y anularlo aquí sería una
                        // línea que finge proteger de algo que ya no existe.
                        errorText: _error,
                      ),
                      // `number` para que en el móvil salga el teclado numérico,
                      // que es el que sirve para los seis dígitos.
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _marcar(),
                    ),
                  ),
                  if (accionAdyacente != null) ...[
                    const SizedBox(width: 8),
                    accionAdyacente,
                  ],
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _ocupado || terminado ? null : _marcar,
                icon: _ocupado
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check),
                label: Text(terminado ? 'Marcada' : 'Marcar'),
              ),
              // La salida de emergencia del que se equivocó de código o quiere
              // marcar otra vez: sin esto, el estado terminal sería una jaula.
              if (terminado) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => setState(() {
                    _marcada = false;
                    _yaEstaba = false;
                    _error = null;
                    _entrada.clear();
                  }),
                  child: const Text('Marcar otra clase'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
