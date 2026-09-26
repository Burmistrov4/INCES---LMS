import 'dart:typed_data';

import '../../models/inscripcion_campo.dart';

/// Contrato de acceso al catálogo de campos y a la planilla de inscripción.
///
/// Las implementaciones **lanzan** `AppException`; el repositorio las envuelve
/// en `Result`. `null` no aparece aquí: el catálogo vacío es una lista vacía, y
/// «sin ficha de aspirante» es un fallo con su código, no un `null`.
abstract interface class PlanillaGateway {
  /// El catálogo de campos activos, ya ordenado.
  ///
  /// Es la ruta **pública** del backend: el formulario tiene que poder saber qué
  /// preguntar antes de que exista una cuenta, así que no lleva token.
  Future<CatalogoInscripcion> campos();

  /// Guarda la planilla del llamante y devuelve la que quedó almacenada.
  ///
  /// Es un reemplazo, no una fusión: lo que no viaje en [planilla] desaparece.
  /// Requiere sesión —el backend saca el usuario del token, no del cuerpo— y
  /// puede fallar con `PLANILLA_INCOMPLETA` (400, nombrando los campos que
  /// faltan) o con `SIN_FICHA_DE_ASPIRANTE` (404).
  Future<PlanillaInscripcion> guardar(PlanillaInscripcion planilla);

  /// Descarga la planilla del llamante como PDF (bytes en crudo).
  ///
  /// Requiere sesión —el backend saca el usuario del token— y falla con
  /// `SIN_FICHA_DE_ASPIRANTE` (404) si el llamante aún no tiene ficha de
  /// aspirante. Devuelve `Uint8List` porque el cuerpo ya es binario: la pantalla
  /// lo pasa directo al selector de descarga, sin tocar JSON.
  Future<Uint8List> descargarPdf();
}
