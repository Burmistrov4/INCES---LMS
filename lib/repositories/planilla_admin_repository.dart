import '../core/gateways/planilla_admin_gateway.dart';
import '../core/result.dart';
import '../models/inscripcion_campo.dart';
import '../services/supabase_planilla_admin_gateway.dart';

/// Repositorio del catálogo de la planilla visto desde el panel de
/// administración.
///
/// Va contra Supabase por PostgREST y **no** por el backend: la frontera de
/// autorización del catálogo es la RLS (ADR-003), y las políticas
/// `inscripcion_campos_admin_lectura` y `_admin_escritura` ya están escritas para
/// este límite. Montar una ruta en Fastify sería una segunda copia de una regla
/// que ya vive en la base, y la copia es la que se desvía.
///
/// Envuelve el gateway en [Result] como el resto de repositorios, y aquí la
/// distinción importa más que en ningún sitio: un catálogo vacío y un catálogo
/// que no se pudo leer pintan la misma pantalla —un panel sin campos—, y sólo el
/// `Result` los separa.
class PlanillaAdminRepository {
  PlanillaAdminRepository({PlanillaAdminGateway? gateway})
      : _gateway = gateway ?? SupabasePlanillaAdminGateway();

  final PlanillaAdminGateway _gateway;

  /// Los 44 campos, **incluidos los apagados**.
  Future<Result<CatalogoInscripcion>> obtenerCatalogo() {
    return Result.guard(() => _gateway.catalogoCompleto());
  }

  Future<Result<CampoInscripcion>> crear(CampoInscripcion campo) {
    return Result.guard(() => _gateway.crear(campo));
  }

  Future<Result<CampoInscripcion>> actualizar({
    required String codigo,
    String? etiqueta,
    String? ayuda,
    String? grupo,
    bool? obligatorio,
    bool? activo,
    int? orden,
  }) {
    return Result.guard(
      () => _gateway.actualizar(
        codigo: codigo,
        etiqueta: etiqueta,
        ayuda: ayuda,
        grupo: grupo,
        obligatorio: obligatorio,
        activo: activo,
        orden: orden,
      ),
    );
  }

  /// Atajo del gesto más frecuente del panel: encender o apagar un campo.
  ///
  /// Existe por la misma razón que `ModuloRepository.alternarModulo`: apagar un
  /// campo es *la* operación que convierte el catálogo en algo configurable, y
  /// quien la llama no debería tener que recordar que por dentro es un
  /// `update` de una sola columna.
  Future<Result<CampoInscripcion>> alternarActivo({
    required String codigo,
    required bool activo,
  }) {
    return Result.guard(
      () => _gateway.actualizar(codigo: codigo, activo: activo),
    );
  }

  /// Sube o baja un campo un puesto, intercambiándolo con su vecino.
  Future<Result<void>> intercambiarOrden({
    required CampoInscripcion actual,
    required CampoInscripcion vecino,
  }) {
    return Result.guard(
      () => _gateway.intercambiarOrden(actual: actual, vecino: vecino),
    );
  }
}
