import 'dart:typed_data';

import 'package:inces_lms_app/core/gateways/planilla_admin_descarga_gateway.dart';

/// Doble de [PlanillaAdminDescargaGateway] con el estilo del resto de dobles del
/// proyecto: se le asigna lo que debe devolver y, para forzar un fallo, la
/// excepción en `errorAlDescargarPdf`.
///
/// **Guarda los UUID pedidos y no sólo un contador.** El contrato de esta
/// descarga no es «se llamó al gateway»: es «se llamó **con el UUID de la
/// persona cuya fila se pulsó**». Un doble que sólo contara llamadas daría verde
/// a un panel que descargara siempre la planilla del primer estudiante de la
/// lista, que es justo el error que este doble existe para atrapar.
class FakePlanillaAdminDescargaGateway
    implements PlanillaAdminDescargaGateway {
  /// Lo que devuelve [descargarPdfDe]. Un PDF mínimo por defecto (`%PDF`).
  List<int> pdfDevuelto = const [37, 80, 68, 70];

  /// Fuerza un fallo de la consulta. Se **lanza**, no se devuelve: el gateway
  /// declara que lanza, y el repositorio es quien lo convierte en `Failure`.
  Object? errorAlDescargarPdf;

  /// Los UUID que llegaron a [descargarPdfDe], en orden.
  final List<String> idsSolicitados = [];

  @override
  Future<Uint8List> descargarPdfDe(String usuarioId) async {
    idsSolicitados.add(usuarioId);
    final error = errorAlDescargarPdf;
    if (error != null) throw error;
    return Uint8List.fromList(pdfDevuelto);
  }
}
