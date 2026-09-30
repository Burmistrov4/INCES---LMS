import '../core/gateways/selector_archivos.dart';
import '../core/result.dart';
import '../repositories/planilla_admin_descarga_repository.dart';
import 'selector_archivos_navegador.dart';

/// El desenlace de la descarga de la planilla de **otro** aspirante, con los
/// cuatro casos que el panel distingue.
///
/// **Por qué un resultado propio y no un `Result<Uint8List>`.** Es la misma
/// razón que en `PlanillaPdfService`, y con un matiz que aquí pesa más: el panel
/// pinta **una fila por estudiante**, así que el desenlace tiene que poder
/// decir **de quién** habla. Un `Failure` suelto obligaría al panel a recordar
/// qué fila disparó la descarga para poder nombrarla.
///
///  · [PlanillaAdminDescargada] — salió bien, el PDF está en el navegador.
///  · [AspiranteSinFicha] — esa persona está matriculada pero **no tiene ficha**
///    (404 `SIN_FICHA_DE_ASPIRANTE`). No es un fallo de la aplicación: es una
///    situación real y frecuente —quien nunca rellenó la planilla de identidad—,
///    así que no debe pintarse como un error rojo. Lo que sí debe hacer es
///    **nombrar a la persona**, porque el administrador necesita saber a quién le
///    falta el papel.
///  · [ConsultaAdminFallida] — la red, los permisos o el servidor fallaron.
///  · [DescargaAdminFallida] — el PDF llegó pero el navegador no pudo entregarlo.
///
/// Es `sealed` para que el `switch` del panel sea **exhaustivo**: si mañana se
/// añade un desenlace, el compilador obliga a tratarlo.
///
/// **Los dos nombres de fallo llevan `Admin` a propósito, y no es cosmética.**
/// `hacer_export_service.dart` y `planilla_pdf_service.dart` ya declaran sendos
/// `ConsultaFallida` y `DescargaFallida`. Hasta hoy eso no molestaba porque los
/// importan archivos distintos —el panel de inscripciones al primero, la pantalla
/// de registro al segundo—, pero este servicio entra **en el panel de
/// inscripciones**, que ya importa el de HACER: con los nombres cortos, el
/// `switch` del panel no compilaría por ambigüedad. Repetir el nombre habría
/// creado una mina que sólo explota cuando alguien junte los dos imports, que es
/// exactamente lo que este cambio hace.
sealed class ResultadoDescargaPlanillaAdmin {
  const ResultadoDescargaPlanillaAdmin();
}

/// El PDF se generó y se entregó al navegador.
final class PlanillaAdminDescargada extends ResultadoDescargaPlanillaAdmin {
  const PlanillaAdminDescargada({
    required this.estudiante,
    required this.nombreArchivo,
  });

  /// El nombre con el que el panel conoce a la persona, tal como se pasó a
  /// [PlanillaAdminPdfService.descargarPlanillaDe]. Se devuelve para que el
  /// aviso de éxito pueda decir de quién es la planilla que se acaba de bajar,
  /// en vez de un «listo» que obligue a mirar la fila.
  final String estudiante;

  /// El nombre con el que se ofreció la descarga.
  final String nombreArchivo;
}

/// La persona no tiene ficha de aspirante (404 `SIN_FICHA_DE_ASPIRANTE`).
///
/// No es un error: es la situación normal de quien está matriculado y nunca
/// rellenó la planilla de identidad. Si viajara como [ConsultaAdminFallida], el panel
/// pintaría un rojo por algo que no está roto y —peor— mandaría al
/// administrador a «reintentar», que es lo único que **no** puede arreglarlo.
final class AspiranteSinFicha extends ResultadoDescargaPlanillaAdmin {
  const AspiranteSinFicha({required this.estudiante});

  /// A quién le falta la ficha. Sin este dato el aviso sería anónimo, y el
  /// administrador tendría que adivinar cuál de las filas pulsó.
  final String estudiante;
}

/// La consulta al backend falló: red, permisos (401/403) o el propio PDF (500).
final class ConsultaAdminFallida extends ResultadoDescargaPlanillaAdmin {
  const ConsultaAdminFallida({required this.estudiante, required this.mensaje});

  /// A quién se le estaba intentando descargar la planilla.
  final String estudiante;

  /// El mensaje ya traducido de `AppException`, listo para mostrar.
  final String mensaje;
}

/// La consulta trajo el PDF pero el navegador no pudo entregarlo.
final class DescargaAdminFallida extends ResultadoDescargaPlanillaAdmin {
  const DescargaAdminFallida({required this.estudiante});

  /// A quién se le estaba intentando descargar la planilla.
  final String estudiante;
}

/// Genera y entrega el PDF de la planilla de **cualquier** aspirante.
///
/// **Qué es y qué no es.** No consulta la base ni compone el PDF por su cuenta:
/// **compone** las piezas que ya existen y que están probadas cada una por
/// separado —`PlanillaAdminDescargaRepository` trae los bytes del backend, y
/// `SelectorDeArchivos` los entrega—. Lo que aporta es la **secuencia**, que si
/// no viviría dentro del `State` del diálogo mezclada con `setState` y avisos, y
/// por eso no se podría probar sin montar una pantalla.
///
/// **Por qué es un servicio y no una llamada del panel.** Es el mismo reparto que
/// `PlanillaPdfService` (la planilla propia) y que `HacerExportService` (la
/// nómina): la pantalla decide **cuándo** y **a quién**; el servicio decide
/// **qué significa cada desenlace**. Un panel que interpretara los códigos de
/// error tendría la regla duplicada, y de las dos copias la que se desvía es la
/// de fuera.
///
/// **Por qué no usa `service_role` ni PostgREST.** La frontera de autorización
/// de esta ruta es la RLS (ADR-003) más la guardia de rol del backend: el PDF lo
/// compone Fastify, que saca al administrador de su JWT y a la persona del UUID.
/// Este servicio no añade ni repite esa regla — se apoya en el token de la sesión
/// activa que ya usa el cliente. Un `service_role` aquí sería una segunda copia
/// de la regla, y de las dos copias la que se desvía siempre es la de fuera.
class PlanillaAdminPdfService {
  /// Los dos colaboradores se inyectan para poder probar el servicio sin red y
  /// sin navegador. En producción se resuelven solos.
  PlanillaAdminPdfService({
    PlanillaAdminDescargaRepository? repositorio,
    SelectorDeArchivos? selector,
  })  : _repositorio = repositorio ?? PlanillaAdminDescargaRepository(),
        _selector = selector ?? SelectorDeArchivosDelNavegador();

  final PlanillaAdminDescargaRepository _repositorio;
  final SelectorDeArchivos _selector;

  /// Descarga la planilla de [usuarioId] y la entrega al navegador.
  ///
  /// [estudiante] sólo se usa para **nombrar** el archivo y para que cada
  /// desenlace pueda decir de quién habla; no filtra nada. El filtro es
  /// [usuarioId] y nada más, porque es la clave que la ruta indexa.
  ///
  /// **Nunca lanza.** Devuelve siempre uno de los cuatro desenlaces. El 404
  /// `SIN_FICHA_DE_ASPIRANTE` se trata como [AspiranteSinFicha] —no como
  /// error— porque es una situación real del centro y no algo roto. Un fallo de
  /// red y un fallo del navegador llegan como valores distintos para que la UI
  /// pueda decir cuál de las dos cosas pasó.
  Future<ResultadoDescargaPlanillaAdmin> descargarPlanillaDe({
    required String usuarioId,
    required String estudiante,
  }) async {
    final resultado = await _repositorio.descargarPdfDe(usuarioId);

    switch (resultado) {
      case Failure(error: final fallo):
        // El único final «no es un error» es la ausencia de ficha: un estudiante
        // puede estar matriculado y no haber rellenado nunca la planilla. Los
        // demás códigos (red, 401, 403, 500) sí son fallos de consulta.
        if (fallo.code == 'SIN_FICHA_DE_ASPIRANTE') {
          return AspiranteSinFicha(estudiante: estudiante);
        }
        return ConsultaAdminFallida(
          estudiante: estudiante,
          mensaje: fallo.message,
        );

      case Success(value: final bytes):
        final nombre = nombreArchivoPlanillaDe(estudiante);

        try {
          await _selector.descargarBytes(nombre: nombre, contenido: bytes);
        } catch (_) {
          // No se propaga el error del navegador: al administrador no le dice
          // nada y no puede hacer nada con él. Lo que sí importa es que el
          // desenlace quede distinguido del fallo de la consulta.
          return DescargaAdminFallida(estudiante: estudiante);
        }

        return PlanillaAdminDescargada(
          estudiante: estudiante,
          nombreArchivo: nombre,
        );
    }
  }
}

/// Nombre del archivo de descarga, derivado del nombre de la persona.
///
/// **Por qué no se usa el del servidor.** La ruta responde con
/// `Content-Disposition: attachment; filename="planilla-inscripcion-<uuid>.pdf"`,
/// y ese nombre es correcto para el aspirante —que descarga una sola planilla y
/// la reconoce por la fecha—, pero inútil para el administrador, que descarga
/// varias seguidas y las distingue por el **nombre de la persona**. Como la
/// entrega se hace con un `Blob` y un `<a download>` —no abriendo la URL del
/// servidor—, el cliente puede ponerle el nombre que quiera.
///
/// Se normaliza a ASCII porque un nombre con tildes o espacios llega al disco
/// tal cual, y un `José Núñez.pdf` acaba siendo un archivo que algunas
/// herramientas no saben volver a abrir por la ruta. Se pierden las tildes y no
/// la identidad: `jose-nunez.pdf` sigue diciendo quién es.
String nombreArchivoPlanillaDe(String estudiante) {
  final base = _normalizar(estudiante);
  return 'planilla-${base.isEmpty ? 'aspirante' : base}.pdf';
}

/// Vocales acentuadas y compañía que hay que plegar antes de descartar lo que no
/// sea alfanumérico. Sin este paso, `José` daría `jos` y el nombre quedaría
/// cortado por la mitad en vez de traducido.
const Map<String, String> _equivalentes = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u', 'ç': 'c', 'ý': 'y',
};

String _normalizar(String texto) {
  final buffer = StringBuffer();

  for (final runa in texto.trim().toLowerCase().runes) {
    final caracter = String.fromCharCode(runa);
    final plegado = _equivalentes[caracter];

    if (plegado != null) {
      buffer.write(plegado);
    } else if (_esAlfanumerico(caracter)) {
      buffer.write(caracter);
    } else {
      // Todo lo demás —espacios, comas, puntos, barras— se vuelve un separador.
      // Se colapsan después para que `Núñez, José` dé `nunez-jose` y no
      // `nunez--jose`.
      buffer.write('-');
    }
  }

  return buffer
      .toString()
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

bool _esAlfanumerico(String caracter) {
  final codigo = caracter.codeUnitAt(0);
  final esDigito = codigo >= 0x30 && codigo <= 0x39; // 0-9
  final esLetra = codigo >= 0x61 && codigo <= 0x7A; // a-z, ya en minúsculas
  return esDigito || esLetra;
}
