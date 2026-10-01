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
  /// Los bytes que devuelve cualquier descarga, **sea cual sea el formato**.
  ///
  /// El nombre dice `pdf` porque nació con la salida en PDF y el doble se
  /// escribió entonces; hoy lo comparten las dos, así que una prueba del Excel
  /// debe asignarle bytes de ZIP (`PK`) si quiere comprobar algo del formato.
  /// Se deja el nombre como está a propósito: renombrarlo toca tres archivos y
  /// no cambia ninguna aserción — queda anotado como deuda menor en vez de
  /// disfrazado de mejora.
  List<int> pdfDevuelto = const [37, 80, 68, 70];

  /// Fuerza un fallo de la consulta. Se **lanza**, no se devuelve: el gateway
  /// declara que lanza, y el repositorio es quien lo convierte en `Failure`.
  ///
  /// Vale para los dos formatos, por el mismo motivo que [pdfDevuelto].
  Object? errorAlDescargarPdf;

  /// Los UUID que llegaron a [descargarPdfDe], en orden.
  final List<String> idsSolicitados = [];

  /// Los formatos pedidos, en orden: `'pdf'` o `'xlsx'`.
  ///
  /// Existe para que una prueba pueda comprobar que el panel pidió **el formato
  /// que el botón promete**. Sin esto, un botón de Excel que llamara al PDF
  /// pasaría cualquier aserción sobre los bytes.
  final List<String> formatosSolicitados = [];

  @override
  Future<Uint8List> descargarPdfDe(String usuarioId) => _devolver(usuarioId, 'pdf');

  @override
  Future<Uint8List> descargarXlsxDe(String usuarioId) => _devolver(usuarioId, 'xlsx');

  Future<Uint8List> _devolver(String usuarioId, String formato) async {
    idsSolicitados.add(usuarioId);
    formatosSolicitados.add(formato);
    final error = errorAlDescargarPdf;
    if (error != null) throw error;
    return Uint8List.fromList(pdfDevuelto);
  }
}
