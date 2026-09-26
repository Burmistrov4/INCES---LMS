import 'dart:typed_data';

import 'package:inces_lms_app/core/gateways/planilla_gateway.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';

/// Doble de [PlanillaGateway] con el estilo del resto de dobles del proyecto:
/// se le asigna lo que debe devolver y, para forzar un fallo, la excepción en el
/// campo `error*` correspondiente. Registra las llamadas para que una prueba
/// pueda comprobar que el repositorio delegó de verdad.
class FakePlanillaGateway implements PlanillaGateway {
  CatalogoInscripcion catalogo = const CatalogoInscripcion([]);
  PlanillaInscripcion planillaGuardada = <String, dynamic>{};

  Object? errorAlLeerCatalogo;
  Object? errorAlGuardar;

  /// Lo que devuelve [descargarPdf]. Un PDF mínimo por defecto (`%PDF`).
  List<int> pdfDevuelto = const [37, 80, 68, 70];
  Object? errorAlDescargarPdf;

  /// La última planilla que llegó a [guardar].
  PlanillaInscripcion? ultimaPlanilla;

  final List<String> llamadas = [];

  @override
  Future<CatalogoInscripcion> campos() async {
    llamadas.add('campos');
    final error = errorAlLeerCatalogo;
    if (error != null) throw error;
    return catalogo;
  }

  @override
  Future<PlanillaInscripcion> guardar(PlanillaInscripcion planilla) async {
    llamadas.add('guardar');
    ultimaPlanilla = planilla;
    final error = errorAlGuardar;
    if (error != null) throw error;
    return planillaGuardada.isEmpty ? planilla : planillaGuardada;
  }

  @override
  Future<Uint8List> descargarPdf() async {
    llamadas.add('descargarPdf');
    final error = errorAlDescargarPdf;
    if (error != null) throw error;
    return Uint8List.fromList(pdfDevuelto);
  }
}
