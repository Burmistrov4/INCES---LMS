import '../core/gateways/modules_gateway.dart';
import '../core/result.dart';
import '../models/config_audit_entry.dart';
import '../models/system_module.dart';
import '../models/system_setting.dart';
import '../services/supabase_service.dart';

/// Repositorio del núcleo del Administrador Maestro (Fase 3).
///
/// Sigue el mismo contrato que el resto de capas de datos: devuelve [Result] y
/// nunca convierte un fallo en un valor vacío.
class ModuloRepository {
  final ModulesGateway _gateway;

  ModuloRepository({ModulesGateway? gateway})
      : _gateway = gateway ?? SupabaseService.instance;

  /// Categorías conocidas, en orden de presentación en el cPanel.
  static const List<String> ordenCategorias = [
    'nucleo',
    'academico',
    'operacion',
    'evaluacion',
    'avanzado',
    'general',
  ];

  Future<Result<List<SystemModule>>> obtenerModulos() {
    return Result.guard(() => _gateway.modulos());
  }

  /// Enciende o apaga un módulo. Es la operación central del cPanel.
  Future<Result<SystemModule>> alternarModulo({
    required String clave,
    required bool habilitado,
  }) {
    return Result.guard(
      () => _gateway.actualizarModulo(clave: clave, habilitado: habilitado),
    );
  }

  Future<Result<SystemModule>> cambiarRolesPermitidos({
    required String clave,
    required List<String> roles,
  }) {
    return Result.guard(
      () => _gateway.actualizarModulo(
        clave: clave,
        rolesPermitidos: roles,
      ),
    );
  }

  Future<Result<List<SystemSetting>>> obtenerSettings() {
    return Result.guard(() => _gateway.settings());
  }

  Future<Result<SystemSetting>> actualizarSetting({
    required String clave,
    required Object? valor,
  }) {
    return Result.guard(
      () => _gateway.actualizarSetting(clave: clave, valor: valor),
    );
  }

  Future<Result<List<ConfigAuditEntry>>> obtenerAuditoria({int limite = 50}) {
    return Result.guard(() => _gateway.auditoria(limite: limite));
  }

  /// Agrupa módulos por categoría respetando [ordenCategorias].
  ///
  /// Las categorías desconocidas van al final en orden alfabético, para que un
  /// módulo nuevo creado en la base nunca desaparezca del panel.
  static Map<String, List<SystemModule>> agruparPorCategoria(
    List<SystemModule> modulos,
  ) {
    final agrupado = <String, List<SystemModule>>{};

    for (final modulo in modulos) {
      agrupado.putIfAbsent(modulo.categoria, () => []).add(modulo);
    }

    for (final lista in agrupado.values) {
      lista.sort((a, b) {
        final porOrden = a.orden.compareTo(b.orden);
        return porOrden != 0 ? porOrden : a.nombre.compareTo(b.nombre);
      });
    }

    final categoriasConocidas =
        ordenCategorias.where(agrupado.containsKey).toList();
    final categoriasExtra = agrupado.keys
        .where((c) => !ordenCategorias.contains(c))
        .toList()
      ..sort();

    return {
      for (final categoria in [...categoriasConocidas, ...categoriasExtra])
        categoria: agrupado[categoria]!,
    };
  }

  /// Etiqueta legible de una categoría para la UI.
  static String etiquetaCategoria(String categoria) {
    switch (categoria) {
      case 'nucleo':
        return 'Núcleo';
      case 'academico':
        return 'Académico';
      case 'operacion':
        return 'Operación';
      case 'evaluacion':
        return 'Evaluación';
      case 'avanzado':
        return 'Avanzado';
      default:
        return 'General';
    }
  }
}
