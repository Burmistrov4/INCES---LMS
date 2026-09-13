import '../../models/config_audit_entry.dart';
import '../../models/system_module.dart';
import '../../models/system_setting.dart';

/// Contrato del núcleo del Administrador Maestro (Fase 3).
///
/// Toda escritura aquí exige rol `admin`: la RLS de PostgreSQL lo impone del
/// lado del servidor, no la UI.
abstract interface class ModulesGateway {
  Future<List<SystemModule>> modulos();

  Future<SystemModule> actualizarModulo({
    required String clave,
    bool? habilitado,
    int? orden,
    List<String>? rolesPermitidos,
  });

  Future<List<SystemSetting>> settings();

  Future<SystemSetting> actualizarSetting({
    required String clave,
    required Object? valor,
  });

  Future<List<ConfigAuditEntry>> auditoria({int limite});
}
