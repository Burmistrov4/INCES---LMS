import '../core/errors/app_exception.dart';
import '../core/gateways/aspirante_gateway.dart';
import '../core/result.dart';
import '../models/aspirante_model.dart';
import '../models/inscripcion_campo.dart';
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

  /// **`cursosRespaldo` se eliminó con D14, y conviene decir por qué.**
  ///
  /// Era una lista de cinco nombres de curso escrita a mano, que se mostraba si la
  /// consulta fallaba. Con la columna convertida en clave foránea dejó de poder
  /// funcionar por dos motivos, y ninguno se arregla añadiendo ids a mano:
  ///
  ///   1. **No puede saber los uuid.** Son los de `public.programs`, y cambian. Una
  ///      lista fija de ids sería una copia del catálogo que envejece en silencio.
  ///   2. **Dependía de la tolerancia transitoria.** Si se dejaban los nombres,
  ///      funcionaba sólo porque `resolver_programa_inscripcion()` acepta el
  ///      vocabulario viejo. El día que esa tolerancia se retire —que es lo
  ///      previsto— el respaldo empezaría a fallar en el momento del envío, con un
  ///      `23503` que el aspirante no puede resolver.
  ///
  /// Y además apenas cubría un caso que ocurre: si falla la red, `_cargarCatalogo()`
  /// falla también y el formulario ya muestra su propio error con reintento. Lo
  /// único que el respaldo tapaba era un fallo **sólo** de `programs` —permisos,
  /// RLS—, que es justo el caso donde enseñar opciones inventadas es peor que no
  /// enseñar ninguna.
  ///
  /// El hueco que deja lo cubre la pantalla: aviso visible, lista vacía y reintento.
  Future<Result<List<OpcionCampo>>> obtenerProgramasDisponibles() {
    return Result.guard(() => _gateway.programasDisponibles());
  }

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
