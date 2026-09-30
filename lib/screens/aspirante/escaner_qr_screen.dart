import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/inces_theme.dart';

/// El escáner de QR de la asistencia (M7 · D21, segunda mitad).
///
/// **Qué es esta pantalla y qué no es.** Devuelve **texto** y nada más: no sabe
/// qué es una asistencia, no habla con el servicio y no importa `ParseQr`. El
/// panel del alumno le pasa un [ValidadorDeQr] —su propia regla— y recibe el
/// contenido del código como `String`, o `null` si el alumno decidió escribir.
/// Esa frontera es deliberada: si el escáner conociera el par `<uuid>:<dígitos>`
/// habría dos sitios que saben qué es un QR de asistencia, y el día que cambie
/// el formato habría que acordarse de los dos.
///
/// **El antirrebote son tres capas, y la primera no la escribimos nosotros.**
/// El usuario pidió que no se disparen lecturas repetidas si el código se queda
/// delante de la cámara. Se resuelve así, de más barata a más explícita:
///
/// 1. **`DetectionSpeed.noDuplicates`**, del propio paquete: *«the scanner will
///    only scan a barcode once, and never again until another barcode has been
///    scanned»* —leído en su `detection_speed.dart`—. La repetición se corta en
///    el lado nativo, **antes** de cruzar a Dart, que es donde de verdad importa
///    cuando el bucle analiza cada fotograma. Se mide en el código del paquete y
///    no se supone, porque el valor por defecto es `normal`, no éste.
/// 2. **[AntirreboteDeLectura]**, un objeto con estado: en cuanto una lectura es
///    válida, todo lo que llegue después se ignora. Cubre el hueco entre aceptar
///    y que el `pop` desmonte la pantalla —en ese intervalo `onDetect` puede
///    volver a dispararse—, y cubre también que aparezca un código **distinto**.
///    Está fuera del `State` para que se pueda probar sin cámara.
/// 3. **`_avisar` no repite el mismo aviso.** Un código que no sirve no puede
///    hacer parpadear el mensaje: si el texto es el mismo que ya está pintado, no
///    se toca el estado. Sin relojes y sin temporizadores, que es lo que se
///    quiere: un `Timer` aquí sería un temporizador más que cancelar en `dispose`
///    y una razón más para que una prueba se caiga por «A Timer is still pending».
///
/// **La puerta es de tiempo de ejecución, no un *export* condicional, y eso está
/// medido.** El paquete declara `android`, `ios`, `macos` y `web` en su
/// `flutter.plugin.platforms`; Windows y Linux no existen ni como carpeta. Pero su
/// API en Dart es Dart normal: se comprobó que **no tiene un solo import
/// condicional** y que `lib/src/web/**` —lo único que importa `dart:js_interop` y
/// `package:web`— **no lo referencia nada fuera de sí mismo**: lo carga el
/// registrante generado, y sólo en compilaciones web. Por eso importar
/// `package:mobile_scanner` **compila en la VM** de `flutter test` y no hace falta
/// el patrón de `selector_archivos_navegador.dart`, que existe porque allí
/// `package:web` **no existe** en la VM. Son dos problemas distintos y copiar el
/// patrón del vecino habría sido ruido.
///
/// **Por qué NO se usa `scanWindow`.** El paquete lo documenta como no soportado
/// en web («the scanner does not expose size information for the barcodes»), así
/// que en web se ignora. Ponerlo daría un marco que **recorta de verdad** en
/// móvil y **no recorta nada** en web: el mismo dibujo prometiendo dos cosas
/// distintas, y en móvil rechazando un código que el alumno ve perfectamente en
/// pantalla. El marco se queda como **guía de puntería** y no como promesa. Un
/// recuadro que no miente vale más que una ventana que miente en una plataforma.
///
/// **Los mensajes de error se escriben para el alumno, no para el log.** «Cámara
/// tapada o código roto» tiene que leerse como algo que se arregla moviendo el
/// teléfono, y el plan B —escribir los seis dígitos— se nombra en el propio
/// mensaje, porque es la salida que el alumno necesita en ese momento. Ver
/// [_mensajeDe], donde cada `MobileScannerErrorCode` tiene su frase y ninguna dice
/// «error inesperado».
class EscanerQrScreen extends StatefulWidget {
  const EscanerQrScreen({super.key, required this.validador});

  /// Decide si el texto leído es un código que esta app acepta.
  ///
  /// **Se inyecta, y es lo que impide un ciclo.** El panel del alumno es quien
  /// sabe qué es un QR de asistencia (`ParseQr.de`), y vive en
  /// `marcar_asistencia_panel.dart`; si esta pantalla lo importara, el panel
  /// tendría que importar al escáner para abrirlo y el escáner al panel para
  /// validar. Con el validador inyectado el escáner no importa a nadie y la
  /// regla vive en un solo sitio.
  ///
  /// El usuario pidió que el validador **confirme el formato antes de devolver el
  /// control al panel**, y por eso se llama aquí y no allí: un código que no
  /// sirve se queda en la cámara con un aviso, en vez de cerrar la pantalla y
  /// aparecer como un error del panel —que es donde el alumno ya no puede hacer
  /// nada—.
  final ValidadorDeQr validador;

  @override
  State<EscanerQrScreen> createState() => _EscanerQrScreenState();
}

/// Dice si un texto es un código que la app acepta.
typedef ValidadorDeQr = bool Function(String texto);

/// El primer código con contenido de una captura.
///
/// Una captura puede traer **varios** códigos —el paquete entrega una lista— y
/// cualquiera puede venir con `rawValue` nulo. Se recorre en vez de tomar el
/// primero: `captura.barcodes.first.rawValue` sobre una lista cuyo primer
/// elemento viene vacío devuelve `null` y la lectura se pierde sin decir nada,
/// que es exactamente el fallo silencioso que esta pantalla existe para no tener.
///
/// **Es una función pública y sin dependencias para poder probarla.** `flutter
/// test` no tiene cámara, así que si esto viviera dentro del `State` el caso que
/// de verdad falla —varios códigos, el primero vacío— no se podría ejercitar.
/// No forma parte de la API de la pantalla.
String? textoDeLaCaptura(BarcodeCapture captura) {
  for (final codigo in captura.barcodes) {
    final valor = codigo.rawValue;
    if (valor != null && valor.trim().isNotEmpty) return valor;
  }
  return null;
}

/// El antirrebote de la lectura: acepta **una vez** y después ignora todo.
///
/// **Es un objeto con estado y no un `bool` suelto dentro del `State`, y la razón
/// es que así se puede probar.** El usuario pidió expresamente que el código no
/// se lea veinte veces por segundo si se queda delante de la cámara, y en
/// `flutter test` no hay cámara con la que comprobarlo: sacarlo aquí permite
/// ejercitar el antirrebote de verdad —varias lecturas, una sola aceptación— en
/// vez de dejar la garantía escrita en un comentario.
///
/// Es la **capa 2** de las tres que se describen en la cabecera del archivo: la
/// capa 1 la pone el paquete (`DetectionSpeed.noDuplicates`) y la 3 es no repetir
/// el mismo aviso.
class AntirreboteDeLectura {
  bool _resuelto = false;

  /// ¿Ya se aceptó una lectura?
  ///
  /// Es de sólo lectura y **a propósito**: quien pregunta «¿ya está resuelto?» no
  /// puede marcarlo como resuelto de paso. Y existe en vez de un `bool` aparte en
  /// el `State` porque dos banderas que dicen lo mismo acaban diciendo cosas
  /// distintas —la de `_alFallar` se olvidaría de actualizarse y un error tardío
  /// pintaría un aviso encima de una lectura que ya salió bien—.
  bool get resuelto => _resuelto;

  /// Registra una lectura: `true` la primera vez, `false` en todas las demás.
  bool aceptar() {
    if (_resuelto) return false;
    _resuelto = true;
    return true;
  }
}

/// ¿Esta plataforma puede leer un QR con la cámara?
///
/// **Android, iOS y Web sí; macOS, Windows y Linux no.** Ojo con el matiz, porque
/// no es una limitación del paquete: éste **sí soporta macOS** (lo declara en su
/// `flutter.plugin.platforms`). Lo que no cubre son Windows y Linux. Ocultar el
/// botón en macOS es una **decisión de alcance** —los tres destinos
/// institucionales son Android, iOS y la web— y no un «no se puede». Se escribe
/// así para que nadie lea esta función como un informe de compatibilidad.
///
/// Se usa `kIsWeb` **y** `defaultTargetPlatform`, nunca `dart:io`: importar
/// `dart:io` rompería la compilación web, que es uno de los tres destinos.
///
/// **En `flutter test` esto devuelve la plataforma anfitriona**, medido: el
/// `flutter_test` de este proyecto no sobrescribe `debugDefaultTargetPlatformOverride`
/// —sólo lo hace `TargetPlatformVariant`, que es opcional—, así que en el CI de
/// Linux vale `TargetPlatform.linux` y el botón **no** aparece solo. Para
/// ejercitarlo en una prueba de widget se fija con
/// `variant: TargetPlatformVariant.only(...)` y **no** con un `addTearDown`: el
/// porqué medido está en `test/escaner_qr_test.dart`.
bool get plataformaPuedeEscanearQr =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class _EscanerQrScreenState extends State<EscanerQrScreen> {
  /// `null` cuando la plataforma no puede escanear.
  ///
  /// **Se crea en `initState` y no como `late final`, y no es un capricho:** un
  /// `late final` se inicializaría en el primer acceso, y el primer acceso es
  /// `dispose()` —que lo toca para cerrarlo—. En Linux o Windows, donde la
  /// pantalla no debería tener cámara, eso crearía el controlador justo para
  /// destruirlo. Con la comprobación aquí, si no hay cámara no hay objeto.
  MobileScannerController? _camara;

  /// Capa 2 del antirrebote: el primer «sí» gana. Ver [AntirreboteDeLectura].
  final _antirrebote = AntirreboteDeLectura();

  /// El aviso que está pintado, para no repintar el mismo (capa 3).
  String? _aviso;

  @override
  void initState() {
    super.initState();
    if (!plataformaPuedeEscanearQr) return;

    _camara = MobileScannerController(
      // Capa 1 del antirrebote: el mismo código no se vuelve a reportar.
      detectionSpeed: DetectionSpeed.noDuplicates,
      // Sólo QR. El docente proyecta un QR y nada más, así que pedirle al
      // analizador que busque las veinte y pico familias de códigos de barras
      // sería gastar trabajo por fotograma en descartar lo que no vamos a usar.
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    final camara = _camara;
    if (camara != null) {
      // `dispose` no puede ser `async`: se lanza y no se espera. El cierre de la
      // cámara no necesita bloquear el desmontaje de la pantalla.
      unawaited(camara.dispose());
    }
    super.dispose();
  }

  // --- Lectura ---------------------------------------------------------------

  void _alDetectar(BarcodeCapture captura) {
    final texto = textoDeLaCaptura(captura);
    if (texto == null) return;

    if (!widget.validador(texto)) {
      _avisar(
        'Ese código no es el QR de asistencia del INCES. '
        'Apunta al que proyecta el docente.',
      );
      return;
    }

    // Capa 2: el primer «sí» gana. Si el código se queda delante de la cámara,
    // lo que llegue después se descarta aquí aunque traiga otro contenido.
    if (!_antirrebote.aceptar()) return;

    // El `pop` va después de la bandera, nunca antes: entre una cosa y la otra el
    // árbol sigue vivo, y si la bandera se pusiera después el `pop` se llamaría
    // dos veces sobre la misma ruta.
    Navigator.of(context).pop(texto);
  }

  /// Pinta un aviso, pero no el mismo dos veces (capa 3).
  void _avisar(String mensaje) {
    if (!mounted || _aviso == mensaje) return;
    setState(() => _aviso = mensaje);
  }

  void _alFallar(Object error, StackTrace pila) {
    // Si ya se aceptó una lectura, la pantalla está de salida: un error que llegue
    // en ese instante no puede pintar un aviso sobre una lectura que sí sirvió.
    if (_antirrebote.resuelto) return;
    _avisar(_mensajeDe(error));
  }

  /// Traduce el error del paquete a una frase para el alumno.
  ///
  /// **Cubre los ocho códigos del enum, uno por uno**, leídos de su
  /// `mobile_scanner_error_code.dart`. Los cinco del ciclo de vida del
  /// controlador (`controllerAlreadyInitialized`, `controllerInitializing`,
  /// `controllerNotAttached`, `controllerUninitialized`, `controllerDisposed`)
  /// son fallos de programación, no del alumno: se agrupan en una frase que
  /// invita a reintentar y **no** se les dice «error inesperado», que no es
  /// cierto —se sabe exactamente qué pasó— y que deja al alumno sin saber si
  /// volver a intentarlo sirve de algo.
  ///
  /// El caso frecuente de verdad es `permissionDenied`, y su mensaje nombra la
  /// cámara y el sitio donde se arregla. `unsupported` es el dispositivo sin
  /// cámara —o sin cámara disponible—, y ahí la frase **empuja al plan B** en vez
  /// de dejar al alumno buscando un botón que no va a funcionar.
  String _mensajeDe(Object error) {
    return switch (error) {
      MobileScannerException(:final errorCode) => switch (errorCode) {
          MobileScannerErrorCode.permissionDenied =>
            'El INCES necesita la cámara para leer el código. '
                'Actívala en los ajustes del teléfono y vuelve a intentarlo.',
          MobileScannerErrorCode.unsupported =>
            'Este dispositivo no puede leer códigos QR. '
                'Escribe los seis dígitos de la pizarra.',
          MobileScannerErrorCode.controllerAlreadyInitialized ||
          MobileScannerErrorCode.controllerInitializing ||
          MobileScannerErrorCode.controllerNotAttached ||
          MobileScannerErrorCode.controllerUninitialized ||
          MobileScannerErrorCode.controllerDisposed =>
            'La cámara no arrancó. Cierra esta pantalla y vuelve a intentarlo.',
          MobileScannerErrorCode.genericError =>
            'No se pudo abrir la cámara. '
                'Escribe los seis dígitos de la pizarra.',
        },
      MobileScannerBarcodeException() =>
        'No se pudo leer el código. Acércalo un poco y evita los reflejos.',
      _ => 'No se pudo leer el código. '
          'Escribe los seis dígitos de la pizarra.',
    };
  }

  /// Enciende o apaga la linterna.
  ///
  /// **No hay una variable propia para «la antorcha está encendida», y es a
  /// propósito.** El estado real vive en el controlador y llega por su
  /// `ValueNotifier`, así que el icono se pinta desde ahí: si la plataforma
  /// rechaza el encendido —o lo apaga ella sola por calor—, la interfaz lo refleja
  /// sin que nadie tenga que sincronizar nada. Una copia local sería un segundo
  /// sitio donde puede estar mal.
  void _alternarAntorcha() {
    final camara = _camara;
    if (camara == null) return;
    unawaited(camara.toggleTorch());
  }

  // --- Pintado ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final camara = _camara;

    if (camara == null) return _sinEscaner(theme);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear el código QR'),
        actions: [
          // La antorcha sólo se ofrece cuando existe y la cámara corre. Preguntar
          // por `torchState` antes de dibujar el botón evita el camino feo: un
          // botón que se pulsa y no hace nada, o que lanza una excepción porque
          // el controlador aún no está inicializado.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: camara,
            builder: (context, estado, _) {
              final hayAntorcha = estado.isInitialized &&
                  estado.isRunning &&
                  estado.torchState != TorchState.unavailable;
              if (!hayAntorcha) return const SizedBox.shrink();
              final encendida = estado.torchState == TorchState.on;
              return IconButton(
                onPressed: _alternarAntorcha,
                tooltip: encendida ? 'Apagar la linterna' : 'Encender la linterna',
                icon: Icon(encendida ? Icons.flashlight_on : Icons.flashlight_off),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: camara,
                  onDetect: _alDetectar,
                  onDetectError: _alFallar,
                  // El aviso de que la cámara no abre **sustituye** a la vista
                  // previa, así que tiene que explicarse solo: es lo único que el
                  // alumno ve. Se reutiliza la misma traducción de errores que
                  // `onDetectError` para que no existan dos frases para lo mismo.
                  errorBuilder: (context, error) =>
                      _camaraNoDisponible(theme, _mensajeDe(error)),
                  // El negro del visor es fijo y no un rol de tema: la vista
                  // previa de la cámara es negra en claro y en oscuro. Un rol de
                  // superficie la dejaría blanca en claro y el marco de puntería
                  // —blanco— desaparecería.
                  placeholderBuilder: (context) => const ColoredBox(
                    color: Colors.black,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  overlayBuilder: (context, constraints) =>
                      _guiaDePunteria(constraints),
                ),
                if (_aviso != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _franjaDeAviso(theme, _aviso!),
                  ),
              ],
            ),
          ),
          _pie(theme),
        ],
      ),
    );
  }

  /// La guía de puntería: oscurece lo de fuera y dibuja el recuadro.
  ///
  /// Es una **guía**, no una ventana de escaneo —ver el porqué en la cabecera del
  /// archivo—, y por eso no se pasa nada a `MobileScanner.scanWindow`.
  Widget _guiaDePunteria(BoxConstraints constraints) {
    final lado = constraints.biggest.shortestSide * 0.62;
    final ventana = Rect.fromCenter(
      center: constraints.biggest.center(Offset.zero),
      width: lado,
      height: lado,
    );
    // `SizedBox.expand` como hijo: un `CustomPaint` sin hijo se dimensiona con su
    // propio `size`, que por defecto es cero, y depender de cómo se resuelvan las
    // restricciones del `Stack` del paquete es depender de un detalle ajeno.
    return CustomPaint(
      painter: _PintorDeGuia(ventana),
      child: const SizedBox.expand(),
    );
  }

  Widget _franjaDeAviso(ThemeData theme, String mensaje) {
    return Material(
      // Blanco sobre el rojo de error: correcto en los dos brillos y no una
      // superficie del tema, así que no se sustituye por un rol.
      color: IncesTheme.error,
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mensaje,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lo que se ve cuando la cámara no abre: el mensaje y el plan B.
  Widget _camaraNoDisponible(ThemeData theme, String mensaje) {
    // Mismo negro fijo que el visor: este estado ocupa su lugar, y el texto
    // blanco de encima está pensado sobre negro. Un rol de superficie lo dejaría
    // blanco sobre blanco en modo claro.
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// El pie: la ayuda permanente y la salida hacia el camino manual.
  ///
  /// **El plan B tiene que ser obvio, no estar escondido.** El usuario lo pidió
  /// así: si la cámara falla —permiso, CDN de la web, dispositivo sin cámara— el
  /// alumno tiene que poder marcar igual, y la única forma de conseguirlo es que
  /// la salida esté a la vista desde el primer segundo, sin buscarla. Por eso es
  /// un `OutlinedButton` de ancho completo y no un enlace discreto en una esquina.
  Widget _pie(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Apunta al código que el docente proyecta en la pizarra. '
              'Se lee solo, no hay que pulsar nada.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              // `pop()` sin valor: el panel recibe `null` y entiende «el alumno
              // quiere escribir». Devolver una cadena vacía sería un valor con
              // significado, y ese significado ya lo tiene `null`.
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Prefiero escribir los seis dígitos'),
            ),
          ],
        ),
      ),
    );
  }

  /// La pantalla entera cuando la plataforma no tiene cámara.
  ///
  /// Hoy no se llega aquí desde la interfaz —el botón no se dibuja fuera de
  /// Android, iOS y Web—, y por eso mismo conviene que exista: es la red que
  /// atrapa a quien navegue a esta pantalla por otro camino, y es lo que hace que
  /// montarla en una prueba sobre Linux no reviente.
  Widget _sinEscaner(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear el código QR')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_2_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Este dispositivo no puede leer códigos QR. '
                'Escribe los seis dígitos de la pizarra.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: const Text('Escribir los seis dígitos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Oscurece todo menos el recuadro y lo perfila.
///
/// El agujero se hace con una operación de caminos en vez de pintar cuatro
/// rectángulos alrededor: con cuatro rectángulos, cualquier redondeo de esquina
/// deja costuras de un píxel que se ven como suciedad.
class _PintorDeGuia extends CustomPainter {
  const _PintorDeGuia(this.ventana);

  final Rect ventana;

  @override
  void paint(Canvas canvas, Size size) {
    final marco = RRect.fromRectAndRadius(ventana, const Radius.circular(16));
    final fuera = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(marco),
    );
    // El velo y el marco se pintan sobre la imagen viva de la cámara, no sobre
    // una superficie del tema: negro translúcido y blanco funcionan en los dos
    // brillos y son los que dejan ver el código que hay debajo.
    canvas.drawPath(fuera, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(
      marco,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_PintorDeGuia anterior) => anterior.ventana != ventana;
}
