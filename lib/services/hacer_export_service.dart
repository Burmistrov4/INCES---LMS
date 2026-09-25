import '../core/gateways/selector_archivos.dart';
import '../core/result.dart';
import '../models/exportacion_hacer.dart';
import '../repositories/exportacion_hacer_repository.dart';
import 'selector_archivos_navegador.dart';

/// El desenlace de una exportación, con los tres casos que la UI distingue.
///
/// **Por qué un resultado propio y no un `Result<ExportacionHacer>`.** La
/// exportación tiene **tres** finales legítimos, y sólo uno es un error:
///
///  · [NadaQueExportar] — la sección está recién abierta. No hay nada roto que
///    reintentar, así que no puede viajar como `Failure`: si viajara así, el
///    panel mostraría un error rojo por una situación normal, y el
///    administrador aprendería a ignorar los rojos.
///  · [NominaDescargada] — salió bien.
///  · [ConsultaFallida] / [DescargaFallida] — sí son fallos, y **de sitios
///    distintos**: la consulta es la red y la descarga es el navegador. El
///    administrador no puede hacer nada con el `toString()` de un error de
///    JavaScript, pero sí con saber cuál de las dos mitades falló.
///
/// Es `sealed` para que el `switch` del panel sea **exhaustivo**: si mañana se
/// añade un desenlace, el compilador obliga a tratarlo en vez de dejar caer un
/// caso al vacío.
sealed class ResultadoExportacionHacer {
  const ResultadoExportacionHacer();
}

/// La sección no tiene ninguna inscripción `ENROLLED`. No es un error.
final class NadaQueExportar extends ResultadoExportacionHacer {
  const NadaQueExportar({required this.seccion});

  /// El nombre de la sección, para que el aviso pueda nombrarla.
  final String seccion;
}

/// El archivo se generó y se entregó al navegador.
final class NominaDescargada extends ResultadoExportacionHacer {
  const NominaDescargada({
    required this.nombreArchivo,
    required this.matriculados,
  });

  final String nombreArchivo;
  final int matriculados;
}

/// La consulta a la vista falló: red, permisos o la vista misma.
final class ConsultaFallida extends ResultadoExportacionHacer {
  const ConsultaFallida(this.mensaje);

  /// El mensaje ya traducido de `AppException`, listo para mostrar.
  final String mensaje;
}

/// La consulta trajo la nómina pero el navegador no pudo entregar el archivo.
final class DescargaFallida extends ResultadoExportacionHacer {
  const DescargaFallida();
}

/// Genera y entrega el archivo de la planilla hacia HACER.
///
/// **Qué es y qué no es.** No consulta la base ni serializa el CSV por su
/// cuenta: **compone** las piezas que ya existen y que están probadas cada una
/// por separado —`ExportacionHacerRepository` trae las filas,
/// `csvDeExportacionHacer` las convierte en el archivo, y `SelectorDeArchivos`
/// lo entrega—. Lo que aporta es la **secuencia**, que hasta ahora vivía dentro
/// del `State` del panel mezclada con `setState` y avisos, y que por eso no se
/// podía probar sin montar una pantalla.
///
/// **Por qué no consulta directamente a Supabase.** La frontera de autorización
/// de `v_exportacion_hacer` es la RLS (ADR-003): la vista es `security_invoker`
/// y las políticas de `enrollments`, `sections`, `aspirantes` y `schedule_slots`
/// deciden qué filas ve cada rol. Este servicio no añade ni repite esa regla: se
/// apoya en el JWT de la sesión activa que ya usa el cliente de Supabase. Un
/// `service_role` aquí —o una ruta en Fastify— sería una segunda copia de la
/// regla, y de las dos copias la que se desvía siempre es la de fuera.
///
/// **El archivo se descarga, no se sube.** Es lo que HACER consume: un archivo
/// para importar. La tentación de subirlo a Cloudflare R2 desde el navegador
/// choca con una regla del proyecto, y no es de estilo: **el frontend no puede
/// tener credenciales de R2**. Cuando M5 necesita subir algo, el backend firma
/// una URL y el navegador hace el `PUT` contra ella; esa es la única vía por la
/// que el navegador toca el bucket, y aquí no hace falta ninguna.
class HacerExportService {
  /// Los dos colaboradores se inyectan para poder probar el servicio sin red y
  /// sin navegador. En producción se resuelven solos.
  HacerExportService({
    ExportacionHacerRepository? repositorio,
    SelectorDeArchivos? selector,
  })  : _repositorio = repositorio ?? ExportacionHacerRepository(),
        _selector = selector ?? SelectorDeArchivosDelNavegador();

  final ExportacionHacerRepository _repositorio;
  final SelectorDeArchivos _selector;

  /// Consulta la nómina de [seccionId] y entrega el archivo al navegador.
  ///
  /// [periodo], [seccion] y [materia] sólo se usan para **nombrar** el archivo;
  /// no filtran la consulta. El filtro es [seccionId] y nada más, porque es la
  /// clave que la vista indexa y la única que no puede cambiar de forma.
  ///
  /// **Nunca lanza.** Devuelve siempre uno de los cuatro desenlaces. Un fallo de
  /// red y un fallo del navegador llegan como valores distintos, para que la UI
  /// pueda decir cuál de las dos cosas pasó.
  Future<ResultadoExportacionHacer> exportarSeccion({
    required String seccionId,
    required String periodo,
    required String seccion,
    String? materia,
  }) async {
    final resultado = await _repositorio.deSeccion(seccionId);

    switch (resultado) {
      case Failure(error: final fallo):
        return ConsultaFallida(fallo.message);

      case Success(value: final exportacion):
        // Cero filas no es un fallo: es una sección recién abierta. Se dice con
        // esas palabras en vez de descargar un archivo con sólo la cabecera,
        // que el administrador leería como «se exportó bien».
        if (exportacion.vacia) return NadaQueExportar(seccion: seccion);

        final nombre = nombreArchivoHacer(
          periodo: periodo,
          seccion: seccion,
          materia: materia,
        );

        try {
          await _selector.descargarTexto(
            nombre: nombre,
            contenido: exportacion.aCsv(),
          );
        } catch (_) {
          // No se propaga el error del navegador: al administrador no le dice
          // nada y no puede hacer nada con él. Lo que sí importa es que el
          // desenlace quede distinguido del fallo de la consulta.
          return const DescargaFallida();
        }

        return NominaDescargada(
          nombreArchivo: nombre,
          matriculados: exportacion.total,
        );
    }
  }
}
