import '../core/errors/app_exception.dart';
import '../core/gateways/auditoria_acceso_gateway.dart';
import '../core/result.dart';
import '../models/entrada_acceso.dart';
import '../services/auditoria_acceso_service.dart';

/// Repositorio de la auditoría de accesos (Módulo 1).
///
/// Devuelve [Result]: la capa de datos lanza, aquí se captura. Las comprobaciones
/// de rango viven en el dominio y no en el widget para que los tests las cubran
/// sin montar la interfaz.
class AuditoriaAccesoRepository {
  AuditoriaAccesoRepository({AuditoriaAccesoGateway? gateway})
      : _gateway = gateway ?? BackendAuditoriaAccesoGateway();

  final AuditoriaAccesoGateway _gateway;

  /// Tamaño de página por defecto. El backend admite hasta 100.
  static const int limitePorPagina = 25;

  Future<Result<PaginaAcceso>> listarAccesos({
    EstadoAcceso? estado,
    String? email,
    String? userId,
    int limite = limitePorPagina,
    int desplazamiento = 0,
  }) {
    return Result.guard(() async {
      // Se valida aquí y no en la pantalla: son las mismas reglas que aplica el
      // backend, y comprobarlas antes evita un viaje para recibir un 400.
      if (desplazamiento < 0) {
        throw const AppException.validacion(
          'El desplazamiento de la página no puede ser negativo.',
        );
      }
      if (limite < 1 || limite > 100) {
        throw const AppException.validacion(
          'El tamaño de página debe estar entre 1 y 100.',
        );
      }

      // El correo se recorta: sin esto, un filtro escrito con un espacio al
      // final no encontraría nada y el administrador culparía a los datos.
      final correo = email?.trim();

      return _gateway.listarAccesos(
        estado: estado,
        email: (correo == null || correo.isEmpty) ? null : correo,
        userId: userId,
        limite: limite,
        desplazamiento: desplazamiento,
      );
    });
  }
}
