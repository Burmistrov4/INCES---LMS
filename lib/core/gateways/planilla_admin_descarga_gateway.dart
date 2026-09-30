import 'dart:typed_data';

/// Contrato de la descarga de la planilla de **otro** aspirante, para el
/// administrador.
///
/// **Por qué no vive en `PlanillaGateway`.** Aquél es la ruta del aspirante, y
/// sus dos métodos de lectura no dicen *de quién* es la planilla: `campos()`
/// viaja **sin token** porque el formulario tiene que poder pintarse antes de
/// que exista una cuenta, y `descargarPdf()` saca el usuario **del JWT** —quien
/// llama no puede querer más planilla que la suya—. Aquí es lo contrario: el
/// UUID de la persona **llega por parámetro**, y la ruta que lo sirve exige rol
/// de administrador.
///
/// Meterlo en `PlanillaGateway` dejaría en una sola superficie dos reglas de
/// autorización que no se parecen —«el backend saca el usuario del token» y «el
/// backend confía en el UUID que le mandan, previa guardia de rol»— y obligaría
/// al formulario de inscripción a cargar con un método que sólo usa el panel.
/// Es la misma razón por la que `PlanillaAdminGateway` existe aparte para el
/// catálogo, y por la que `SupabasePlanillaAdminGateway` declara en su nombre el
/// transporte en vez de llamarse `Backend`.
///
/// Las implementaciones **lanzan**; el repositorio las envuelve en `Result`.
abstract interface class PlanillaAdminDescargaGateway {
  /// Descarga la planilla de [usuarioId] como PDF, en bytes en crudo.
  ///
  /// [usuarioId] es el **id de usuario** (`auth.users.id`, que es también
  /// `profiles.id`) y **no** el `id` de la fila de `aspirantes`: el backend
  /// resuelve la ficha con `.eq('user_id', usuarioId)`. Es exactamente el mismo
  /// valor que `InscripcionDetallada.estudianteId` —que sale de
  /// `enrollments.student_id`—, y por eso el panel puede pasarlo sin traducirlo.
  ///
  /// Falla con `SIN_FICHA_DE_ASPIRANTE` (404) si esa persona no tiene ficha. No
  /// es un caso teórico: un estudiante puede estar matriculado y no haber
  /// rellenado nunca la planilla de identidad —los tres estudiantes sembrados
  /// están así—, y entonces no hay nada que imprimir. También puede fallar con
  /// `permisos` (401/403) si quien llama no es administrador o el módulo
  /// `m4_inscripciones` está apagado.
  Future<Uint8List> descargarPdfDe(String usuarioId);
}
