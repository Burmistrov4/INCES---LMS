import '../../models/aspirante_model.dart';

/// Contrato de acceso a los datos de aspirantes.
///
/// Los métodos **lanzan** excepciones si algo falla; la traducción a
/// `AppException` la hace el repositorio. `null` significa "no existe".
abstract interface class AspiranteGateway {
  /// `OK` | `CEDULA_DUPLICADA` | `EMAIL_DUPLICADO` | `EMAIL_INVALIDO` |
  /// `CEDULA_REQUERIDA`
  Future<String> precheck({required String cedula, required String email});

  Future<AspiranteModel?> porCedula(String cedula);

  Future<List<AspiranteModel>> todos();

  Future<AspiranteModel?> porId(String id);

  /// Ficha del usuario autenticado.
  Future<AspiranteModel?> miFicha();

  Future<AspiranteModel> crear(AspiranteModel modelo);

  Future<AspiranteModel> actualizar(String id, Map<String, dynamic> data);

  Future<void> eliminar(String id);

  Future<List<String>> cursosDisponibles();

  Future<bool> existeEmail(String email);
}
