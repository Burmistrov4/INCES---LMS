import '../../models/exportacion_hacer.dart';

/// Contrato de la exportación de la planilla hacia HACER (Módulo 4).
///
/// **Por qué es una interfaz aparte y no más métodos de `InscripcionGateway`.**
/// Son dos fronteras con dos transportes y dos audiencias:
///
///  * `InscripcionGateway` habla HTTP contra el backend Fastify y sirve tanto al
///    estudiante como al administrador (solicitar, renunciar, promover).
///  * Este lee **una vista** y su frontera de autorización es la RLS
///    (`v_exportacion_hacer` es `security_invoker`, ADR-003). Meterlo en
///    `InscripcionGateway` obligaría a que el estudiante cargara con un método
///    que sólo el panel de administración usa, y a que un fallo de permisos de
///    la exportación se leyera como un fallo de la inscripción.
///
/// Es el mismo reparto que ya existe entre `PlanillaGateway` (pública, por
/// Fastify) y `PlanillaAdminGateway` (administrativa, por PostgREST).
///
/// La implementación **lanza** [AppException]; el repositorio la envuelve en
/// `Result`.
abstract interface class ExportacionHacerGateway {
  /// Las filas de la nómina de una sección: una por inscripción `ENROLLED`.
  ///
  /// Devuelve la lista vacía cuando la sección no tiene matriculados, que **no
  /// es un error**: es una sección recién abierta y el panel debe poder decir
  /// «no hay nadie a quien exportar» sin fingir un fallo técnico.
  ///
  /// No pagina: la nómina de una sección de un CFS es de decenas de filas, y una
  /// exportación partida en páginas sería un archivo incompleto que parece
  /// completo. Si algún día deja de ser cierto, se verá como una descarga lenta,
  /// no como un CSV al que le faltan alumnos.
  Future<List<FilaExportacionHacer>> filasDeSeccion(String seccionId);
}
