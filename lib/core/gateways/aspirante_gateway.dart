import '../../models/aspirante_model.dart';
import '../../models/inscripcion_campo.dart';

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

  /// La oferta formativa abierta a la inscripción pública.
  ///
  /// D14: devuelve `valor` = uuid del programa y `etiqueta` = su nombre, leídos
  /// de `public.programs`. Antes devolvía una lista de nombres, y el nombre era
  /// lo que acababa guardado en la ficha.
  ///
  /// La vista `cursos` que hacía de puente ya no existe: se retiró en
  /// `202609250002`, al comprobarse que esta capa era su último consumidor.
  Future<List<OpcionCampo>> programasDisponibles();

  Future<bool> existeEmail(String email);
}
