import '../core/errors/app_exception.dart';
import '../core/gateways/curriculo_gateway.dart';
import '../core/reglas_curriculo.dart';
import '../core/result.dart';
import '../models/materia.dart';
import '../models/pensum.dart';
import '../models/programa.dart';
import '../services/curriculo_service.dart';

/// Repositorio del Módulo 2 — Currículo y Pensum.
///
/// Devuelve [Result]: la capa de datos lanza, aquí se captura. Las validaciones
/// viven en el dominio y no en el widget para que los tests las cubran sin
/// montar la interfaz, y son **las mismas reglas que aplica el backend**:
/// comprobarlas antes evita un viaje de red para recibir un 400 que ya se podía
/// prever.
///
/// No son la única barrera. El backend valida con Zod y la base tiene sus
/// propias restricciones; esta capa existe para dar el mensaje antes y nombrar
/// el campo culpable.
class CurriculoRepository {
  CurriculoRepository({CurriculoGateway? gateway})
      : _gateway = gateway ?? BackendCurriculoGateway();

  final CurriculoGateway _gateway;

  /// Tamaño de página por defecto. El backend admite hasta 100.
  static const int limitePorPagina = 25;

  /// Formato de un código de catálogo, idéntico al del backend.
  ///
  /// Empieza por letra o dígito y sigue con letras, dígitos o guiones, hasta 12
  /// caracteres. Es la identidad de un programa y de una materia: cambiarla
  /// rompería cualquier documento que la cite.
  static final RegExp patronCodigo = RegExp(r'^[A-Z0-9][A-Z0-9-]{0,11}$');

  static const int largoMaximoCodigo = 12;
  static const int largoMaximoNombre = 100;

  // ---------------------------------------------------------------------------
  // Programas
  // ---------------------------------------------------------------------------

  Future<Result<PaginaProgramas>> listarProgramas({
    TipoPrograma? tipo,
    bool? activo,
    String? busqueda,
    int limite = limitePorPagina,
    int desplazamiento = 0,
  }) {
    return Result.guard(() async {
      _validarPaginacion(limite: limite, desplazamiento: desplazamiento);
      _validarBusqueda(busqueda);

      return _gateway.listarProgramas(
        tipo: tipo,
        activo: activo,
        busqueda: busqueda,
        limite: limite,
        desplazamiento: desplazamiento,
      );
    });
  }

  Future<Result<DetallePrograma>> detallePrograma(String id) {
    return Result.guard(() async {
      if (id.trim().isEmpty) {
        throw const AppException.validacion(
          'Falta el identificador del programa.',
        );
      }
      return _gateway.detallePrograma(id.trim());
    });
  }

  Future<Result<DetallePrograma>> crearPrograma(EntradaCrearPrograma entrada) {
    return Result.guard(() async {
      final codigo = entrada.codigo.trim().toUpperCase();
      final nombre = entrada.nombre.trim();

      _validarCodigo(codigo);
      _validarNombre(nombre);
      _validarPensum(entrada.pensum);

      return _gateway.crearPrograma(
        EntradaCrearPrograma(
          codigo: codigo,
          nombre: nombre,
          tipo: entrada.tipo,
          pensum: entrada.pensum,
          requierePasantia: entrada.requierePasantia,
          publicar: entrada.publicar,
        ),
      );
    });
  }

  Future<Result<Programa>> actualizarPrograma(
    String id,
    CambiosPrograma cambios,
  ) {
    return Result.guard(() async {
      if (id.trim().isEmpty) {
        throw const AppException.validacion(
          'Falta el identificador del programa.',
        );
      }
      if (cambios.vacio) {
        throw const AppException.validacion(
          'No hay ningún cambio que guardar.',
        );
      }

      final nombre = cambios.nombre?.trim();
      if (cambios.nombre != null) _validarNombre(nombre!);

      return _gateway.actualizarPrograma(
        id.trim(),
        CambiosPrograma(
          nombre: nombre,
          requierePasantia: cambios.requierePasantia,
          activo: cambios.activo,
        ),
      );
    });
  }

  Future<Result<DetallePrograma>> reemplazarPensum(
    String id,
    List<EntradaPensum> pensum,
  ) {
    return Result.guard(() async {
      if (id.trim().isEmpty) {
        throw const AppException.validacion(
          'Falta el identificador del programa.',
        );
      }
      _validarPensum(pensum);

      return _gateway.reemplazarPensum(id.trim(), pensum);
    });
  }

  // ---------------------------------------------------------------------------
  // Materias
  // ---------------------------------------------------------------------------

  Future<Result<PaginaMaterias>> listarMaterias({
    String? busqueda,
    int limite = limitePorPagina,
    int desplazamiento = 0,
  }) {
    return Result.guard(() async {
      _validarPaginacion(limite: limite, desplazamiento: desplazamiento);
      _validarBusqueda(busqueda);

      return _gateway.listarMaterias(
        busqueda: busqueda,
        limite: limite,
        desplazamiento: desplazamiento,
      );
    });
  }

  Future<Result<Materia>> crearMateria(EntradaCrearMateria entrada) {
    return Result.guard(() async {
      final codigo = entrada.codigo.trim().toUpperCase();
      final nombre = entrada.nombre.trim();

      _validarCodigo(codigo);
      _validarNombre(nombre);

      if (entrada.horasAcademicas <= 0) {
        throw const AppException.validacion(
          'Las horas académicas deben ser mayores que cero.',
        );
      }

      return _gateway.crearMateria(
        EntradaCrearMateria(
          codigo: codigo,
          nombre: nombre,
          horasAcademicas: entrada.horasAcademicas,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Validaciones
  // ---------------------------------------------------------------------------

  void _validarCodigo(String codigo) {
    if (codigo.isEmpty) {
      throw const AppException.validacion('Ingresa el código.');
    }
    if (codigo.length > largoMaximoCodigo) {
      throw const AppException.validacion(
        'El código no puede pasar de $largoMaximoCodigo caracteres.',
      );
    }
    if (!patronCodigo.hasMatch(codigo)) {
      throw const AppException.validacion(
        'El código sólo admite mayúsculas, dígitos y guiones, y debe empezar '
        'por letra o dígito.',
      );
    }
  }

  void _validarNombre(String nombre) {
    if (nombre.isEmpty) {
      throw const AppException.validacion('Ingresa el nombre.');
    }
    if (nombre.length > largoMaximoNombre) {
      throw const AppException.validacion(
        'El nombre no puede pasar de $largoMaximoNombre caracteres.',
      );
    }
  }

  void _validarPensum(List<EntradaPensum> pensum) {
    if (pensum.isEmpty) {
      throw const AppException.validacion(
        'El pensum necesita al menos una materia.',
      );
    }

    for (final entrada in pensum) {
      if (entrada.periodo < 1) {
        throw const AppException.validacion(
          'Los períodos del pensum empiezan en 1.',
        );
      }
    }

    final repetida = materiaRepetida(pensum);
    if (repetida != null) {
      throw const AppException.validacion(
        'Hay una materia repetida en el pensum. Cada materia aparece una sola '
        'vez.',
        code: 'MATERIA_REPETIDA',
      );
    }
  }

  void _validarPaginacion({required int limite, required int desplazamiento}) {
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
  }

  void _validarBusqueda(String? busqueda) {
    if (busqueda != null && busqueda.length > largoMaximoNombre) {
      throw const AppException.validacion(
        'La búsqueda no puede pasar de $largoMaximoNombre caracteres.',
      );
    }
  }
}
