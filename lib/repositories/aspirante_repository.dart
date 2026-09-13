import '../core/errors/app_exception.dart';
import '../core/gateways/aspirante_gateway.dart';
import '../core/result.dart';
import '../models/aspirante_model.dart';
import '../services/supabase_service.dart';

/// Repositorio de aspirantes.
///
/// Antes este archivo tenía `catch (e) { return null; }` en todos sus métodos:
/// un fallo de red, de permisos o de validación era **indistinguible** de "no
/// existe". Eso ocultó el bug de registro durante semanas.
///
/// Ahora devuelve [Result]: el éxito lleva el dato, el fallo lleva un
/// [AppException] con causa y mensaje. Un `null` sólo significa "no existe".
/// Hay tests que verifican que un fallo **no** se convierta en lista vacía.
class AspiranteRepository {
  final AspiranteGateway _gateway;

  AspiranteRepository({AspiranteGateway? gateway})
      : _gateway = gateway ?? SupabaseService.instance;

  /// Catálogo local de respaldo.
  ///
  /// Sólo se usa si la consulta a `cursos` falla. La UI debe avisar que está
  /// mostrando datos locales y ofrecer reintentar; nunca ocultar el fallo.
  static const List<String> cursosRespaldo = [
    'Herrería',
    'Higiene y Manipulación de Alimentos',
    'Estética (cejas y pestañas)',
    'Oratoria',
    'Curso Introductorio (15-16 años)',
  ];

  Future<Result<AspiranteModel?>> obtenerPorCedula(String cedula) {
    return Result.guard(() => _gateway.porCedula(cedula.trim()));
  }

  Future<Result<List<AspiranteModel>>> obtenerTodos() {
    return Result.guard(() => _gateway.todos());
  }

  Future<Result<AspiranteModel?>> obtenerPorId(String id) {
    return Result.guard(() => _gateway.porId(id));
  }

  /// Ficha del usuario autenticado.
  Future<Result<AspiranteModel?>> obtenerMiFicha() {
    return Result.guard(() => _gateway.miFicha());
  }

  /// Inserción directa.
  ///
  /// El flujo normal de inscripción **no** usa este método: el trigger de
  /// `auth.users` crea la ficha. Esto queda para operaciones administrativas.
  Future<Result<AspiranteModel>> crear(AspiranteModel modelo) {
    return Result.guard(() => _gateway.crear(modelo));
  }

  Future<Result<AspiranteModel>> actualizar(
    String id,
    Map<String, dynamic> data,
  ) {
    return Result.guard(() => _gateway.actualizar(id, data));
  }

  Future<Result<bool>> eliminar(String id) {
    return Result.guard(() async {
      await _gateway.eliminar(id);
      return true;
    });
  }

  Future<Result<List<String>>> obtenerCursosDisponibles() {
    return Result.guard(() => _gateway.cursosDisponibles());
  }

  /// Verifica duplicados antes de enviar el formulario.
  Future<Result<String>> precheck({
    required String cedula,
    required String email,
  }) {
    return Result.guard(
      () => _gateway.precheck(cedula: cedula.trim(), email: email.trim()),
    );
  }

  /// Sólo tiene sentido con sesión activa (RLS). Para el formulario público
  /// usa [precheck].
  Future<Result<bool>> verificarCorreoExistente(String email) {
    return Result.guard(() => _gateway.existeEmail(email.trim()));
  }

  /// Utilidad para diagnóstico: describe el error sin exponerlo al usuario.
  static String describir(AppException error) =>
      '${error.type.name}${error.code != null ? ' (${error.code})' : ''}: '
      '${error.technical ?? error.message}';
}
