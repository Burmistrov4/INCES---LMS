import '../core/gateways/exportacion_hacer_gateway.dart';
import '../core/result.dart';
import '../models/exportacion_hacer.dart';
import '../services/supabase_exportacion_hacer_gateway.dart';

/// Repositorio de la exportación de la planilla hacia HACER (Módulo 4).
///
/// Devuelve [Result]: la capa de datos lanza, aquí se captura. El panel consume
/// con `when(success: ..., failure: ...)`.
///
/// El repositorio **no** serializa el CSV: devuelve la [ExportacionHacer] y es
/// el panel quien decide qué hacer con ella. Mantener la serialización fuera de
/// aquí es lo que permite probarla con una lista literal, sin gateway ni
/// pantalla.
class ExportacionHacerRepository {
  ExportacionHacerRepository({ExportacionHacerGateway? gateway})
      : _gateway = gateway ?? SupabaseExportacionHacerGateway();

  final ExportacionHacerGateway _gateway;

  /// La nómina de una sección, con una fila por inscripción `ENROLLED`.
  ///
  /// Una sección sin matriculados devuelve `Success` con la lista vacía, no un
  /// `Failure`: no hay nada roto que reintentar, y el panel lo dice con sus
  /// palabras.
  Future<Result<ExportacionHacer>> deSeccion(String seccionId) =>
      Result.guard(
        () async => ExportacionHacer(
          filas: await _gateway.filasDeSeccion(seccionId),
        ),
      );
}
