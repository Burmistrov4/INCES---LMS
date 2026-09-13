import '../../models/entrada_acceso.dart';

/// Contrato de lectura de la traza de accesos (Módulo 1).
///
/// Separa la fuente de datos (el backend Fastify) de la capa de aplicación,
/// igual que [InvitacionGateway]. Las implementaciones **lanzan**
/// `AppException` en fallo; el repositorio las envuelve en [Result]. Para los
/// tests se inyecta un doble sin red ni credenciales.
abstract interface class AuditoriaAccesoGateway {
  /// Pide una página de la traza, aplicando los filtros que se indiquen.
  ///
  /// El filtro y el recorte los hace la base de datos; aquí sólo se transportan.
  Future<PaginaAcceso> listarAccesos({
    EstadoAcceso? estado,
    String? email,
    String? userId,
    int limite,
    int desplazamiento,
  });
}
