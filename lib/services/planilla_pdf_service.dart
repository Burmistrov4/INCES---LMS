import '../core/gateways/selector_archivos.dart';
import '../core/result.dart';
import '../repositories/planilla_repository.dart';
import 'selector_archivos_navegador.dart';

/// El desenlace de una descarga de la planilla propia, con los cuatro casos que
/// la UI distingue.
///
/// **Por qué un resultado propio y no un `Result<Uint8List>`.** La descarga
/// tiene **cuatro** finales legítimos, y sólo uno es un error de verdad:
///
///  · [PlanillaDescargada] — salió bien, el PDF está en el navegador.
///  · [SinFichaDeAspirante] — el llamante aún no tiene ficha. No es un fallo:
///    es la respuesta normal *antes* de inscribirse, y no debe pintarse como
///    error rojo (igual que «sección sin matriculados» en la exportación HACER).
///  · [ConsultaFallida] — la red o el servidor fallaron al producir el PDF.
///  · [DescargaFallida] — el PDF llegó pero el navegador no pudo entregarlo.
///
/// Es `sealed` para que el `switch` de la pantalla sea **exhaustivo**: si mañana
/// se añade un desenlace, el compilador obliga a tratarlo.
sealed class ResultadoDescargaPlanilla {
  const ResultadoDescargaPlanilla();
}

/// El PDF se generó y se entregó al navegador.
final class PlanillaDescargada extends ResultadoDescargaPlanilla {
  const PlanillaDescargada({required this.nombreArchivo});

  /// El nombre con el que se ofreció la descarga, para poder nombrarlo en el
  /// aviso de éxito.
  final String nombreArchivo;
}

/// El llamante no tiene ficha de aspirante todavía (404 `SIN_FICHA_DE_ASPIRANTE`).
///
/// No es un error: es la situación normal antes de inscribirse. Si viajara como
/// [ConsultaFallida], la pantalla pintaría un rojo por algo que no está roto.
final class SinFichaDeAspirante extends ResultadoDescargaPlanilla {
  const SinFichaDeAspirante();
}

/// La consulta al backend falló: red, permisos (401) o el propio PDF (503).
final class ConsultaFallida extends ResultadoDescargaPlanilla {
  const ConsultaFallida(this.mensaje);

  /// El mensaje ya traducido de `AppException`, listo para mostrar.
  final String mensaje;
}

/// La consulta trajo el PDF pero el navegador no pudo entregarlo.
final class DescargaFallida extends ResultadoDescargaPlanilla {
  const DescargaFallida();
}

/// Genera y entrega el PDF de la planilla de inscripción del llamante.
///
/// **Qué es y qué no es.** No consulta la base ni compone el PDF por su cuenta:
/// **compone** las piezas que ya existen y que están probadas cada una por
/// separado —`PlanillaRepository` trae los bytes del backend, y
/// `SelectorDeArchivos` los entrega—. Lo que aporta es la **secuencia**, que
/// hasta ahora habría vivido dentro del `State` de la pantalla mezclada con
/// `setState` y avisos, y por eso no se podría probar sin montar una pantalla.
///
/// **Por qué no consulta directamente a Supabase.** La frontera de autorización
/// de esta ruta es la RLS (ADR-003): el backend lee la ficha del llamante desde
/// su JWT. Este servicio no añade ni repite esa regla: se apoya en el token de
/// la sesión activa que ya usa el cliente. Un `service_role` aquí sería una
/// segunda copia de la regla, y de las dos copias la que se desvía siempre es la
/// de fuera.
///
/// **El archivo se descarga, no se sube.** Es lo que el aspirante guarda o
/// imprime: su planilla del INCES ya llena. El navegador es el único que toca el
/// archivo, igual que en la exportación hacia HACER.
class PlanillaPdfService {
  /// Los dos colaboradores se inyectan para poder probar el servicio sin red y
  /// sin navegador. En producción se resuelven solos.
  PlanillaPdfService({
    PlanillaRepository? repositorio,
    SelectorDeArchivos? selector,
  })  : _repositorio = repositorio ?? PlanillaRepository(),
        _selector = selector ?? SelectorDeArchivosDelNavegador();

  final PlanillaRepository _repositorio;
  final SelectorDeArchivos _selector;

  /// Descarga la planilla del llamante como PDF y la entrega al navegador.
  ///
  /// **Nunca lanza.** Devuelve siempre uno de los cuatro desenlaces. El 404
  /// `SIN_FICHA_DE_ASPIRANTE` se trata como [SinFichaDeAspirante] —no como
  /// error— porque es la respuesta esperada antes de inscribirse, y no debe
  /// pintarse como fallo. Un fallo de red y un fallo del navegador llegan como
  /// valores distintos para que la UI pueda decir cuál de las dos cosas pasó.
  Future<ResultadoDescargaPlanilla> descargarPlanillaPropia() async {
    final resultado = await _repositorio.descargarPdf();

    switch (resultado) {
      case Failure(error: final fallo):
        // El único final «no es un error» es la ausencia de ficha. Los demás
        // códigos (red, 401, 403, 503) sí son fallos de consulta y viajan como
        // [ConsultaFallida].
        if (fallo.code == 'SIN_FICHA_DE_ASPIRANTE') {
          return const SinFichaDeAspirante();
        }
        return ConsultaFallida(fallo.message);

      case Success(value: final bytes):
        final nombre = nombreArchivoPlanilla();

        try {
          await _selector.descargarBytes(
            nombre: nombre,
            contenido: bytes,
          );
        } catch (_) {
          // No se propaga el error del navegador: al usuario no le dice nada y
          // no puede hacer nada con él. Lo que sí importa es que el desenlace
          // quede distinguido del fallo de la consulta.
          return const DescargaFallida();
        }

        return PlanillaDescargada(nombreArchivo: nombre);
    }
  }
}

/// Nombre del archivo de descarga.
///
/// La ruta no devuelve la cédula del llamante —la ficha es suya, no se pide—,
/// así que el nombre usa la fecha actual para que cada descarga sea
/// distinguible. El servidor ya pone `Content-Disposition` con su propio
/// nombre; este es el que el navegador usa por defecto al guardar.
String nombreArchivoPlanilla() {
  final ahora = DateTime.now();
  final marca = '${ahora.year}${_dos(ahora.month)}${_dos(ahora.day)}';
  return 'planilla-inscripcion-$marca.pdf';
}

String _dos(int valor) => valor.toString().padLeft(2, '0');
