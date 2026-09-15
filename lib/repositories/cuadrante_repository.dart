import '../core/errors/app_exception.dart';
import '../core/gateways/cuadrante_gateway.dart';
import '../core/reglas_cuadrante.dart';
import '../core/result.dart';
import '../models/cuadrante.dart';
import '../services/cuadrante_service.dart';

/// Repositorio del Módulo 3 — Cuadrante, Horarios, Aulas y Guardias.
///
/// Devuelve [Result]: la capa de datos lanza, aquí se captura. Las validaciones
/// viven aquí y no en el widget para que los tests las cubran sin montar la
/// interfaz, y son **las mismas reglas que aplica el backend**: comprobarlas
/// antes evita un viaje de red para recibir un 400 que ya se podía prever.
///
/// No son la única barrera, y conviene tenerlo presente al leerlo. El backend
/// valida con Zod y la base tiene sus propias restricciones; esta capa existe
/// para dar el mensaje antes y **nombrar el campo culpable**. La regla que de
/// verdad protege la agenda —que un docente no esté en dos sitios a la vez— no
/// está aquí ni puede estarlo: cruza dos tablas y sólo el trigger las ve.
class CuadranteRepository {
  CuadranteRepository({CuadranteGateway? gateway})
      : _gateway = gateway ?? BackendCuadranteGateway();

  final CuadranteGateway _gateway;

  /// Tamaño de página por defecto. El backend admite hasta 100.
  static const int limitePorPagina = 25;

  /// Longitud máxima de las notas de una guardia.
  static const int largoMaximoNotas = 500;

  /// Un identificador con la forma de un UUID.
  ///
  /// No se comprueba la versión ni la variante: el backend usa `string().uuid()`
  /// y lo que se quiere aquí es atrapar el caso corriente —un `id` vacío o el
  /// nombre de un recurso pegado por error— antes de gastar una petición.
  static final RegExp patronUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  // ---------------------------------------------------------------------------
  // Aulas
  // ---------------------------------------------------------------------------

  Future<Result<PaginaAulas>> listarAulas({
    TipoAula? tipo,
    bool? activa,
    String? busqueda,
    int limite = limitePorPagina,
    int desplazamiento = 0,
  }) {
    return Result.guard(() async {
      _validarPaginacion(limite: limite, desplazamiento: desplazamiento);
      _validarBusqueda(busqueda);

      return _gateway.listarAulas(
        tipo: tipo,
        activa: activa,
        busqueda: _textoONulo(busqueda),
        limite: limite,
        desplazamiento: desplazamiento,
      );
    });
  }

  Future<Result<Aula>> crearAula(EntradaCrearAula entrada) {
    return Result.guard(() async {
      final nombre = entrada.nombre.trim();

      _validarNombreDeAula(nombre);
      _validarCapacidad(entrada.capacidad);

      return _gateway.crearAula(
        EntradaCrearAula(
          nombre: nombre,
          capacidad: entrada.capacidad,
          esTaller: entrada.esTaller,
        ),
      );
    });
  }

  Future<Result<Aula>> actualizarAula(String id, CambiosAula cambios) {
    return Result.guard(() async {
      _validarId(id, 'el espacio');

      if (cambios.vacio) {
        throw const AppException.validacion('No hay ningún cambio que guardar.');
      }

      final nombre = cambios.nombre?.trim();
      if (cambios.nombre != null) _validarNombreDeAula(nombre!);
      if (cambios.capacidad != null) _validarCapacidad(cambios.capacidad!);

      return _gateway.actualizarAula(
        id.trim(),
        CambiosAula(
          nombre: nombre,
          capacidad: cambios.capacidad,
          esTaller: cambios.esTaller,
          activa: cambios.activa,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Períodos
  // ---------------------------------------------------------------------------

  Future<Result<List<Periodo>>> listarPeriodos() {
    return Result.guard(() => _gateway.listarPeriodos());
  }

  Future<Result<Periodo>> crearPeriodo(EntradaCrearPeriodo entrada) {
    return Result.guard(() async {
      final codigo = entrada.codigo.trim();
      final nombre = entrada.nombre?.trim();

      _validarCodigoDeLapso(codigo);
      if (nombre != null) _validarNombreDeLapso(nombre);
      _validarFechas(
        inicio: entrada.fechaInicio,
        fin: entrada.fechaFin,
      );

      return _gateway.crearPeriodo(
        EntradaCrearPeriodo(
          codigo: codigo,
          nombre: (nombre == null || nombre.isEmpty) ? null : nombre,
          fechaInicio: entrada.fechaInicio,
          fechaFin: entrada.fechaFin,
        ),
      );
    });
  }

  Future<Result<Periodo>> actualizarPeriodo(
    String id,
    CambiosPeriodo cambios,
  ) {
    return Result.guard(() async {
      _validarId(id, 'el lapso');

      if (cambios.vacio) {
        throw const AppException.validacion('No hay ningún cambio que guardar.');
      }

      final nombre = cambios.nombre?.trim();
      if (nombre != null) _validarNombreDeLapso(nombre);

      if (!cambios.borrarFechas) {
        _validarFechas(inicio: cambios.fechaInicio, fin: cambios.fechaFin);
      }

      return _gateway.actualizarPeriodo(
        id.trim(),
        CambiosPeriodo(
          nombre: nombre,
          fechaInicio: cambios.fechaInicio,
          fechaFin: cambios.fechaFin,
          activo: cambios.activo,
          borrarFechas: cambios.borrarFechas,
        ),
      );
    });
  }

  Future<Result<Periodo>> marcarVigente(String id) {
    return Result.guard(() {
      _validarId(id, 'el lapso');
      return _gateway.marcarVigente(id.trim());
    });
  }

  // ---------------------------------------------------------------------------
  // Guardias
  // ---------------------------------------------------------------------------

  Future<Result<PaginaGuardias>> listarGuardias({
    String? periodo,
    String? docenteId,
    String? aulaId,
    int? dia,
    int? bloque,
    bool? activa,
    int limite = limitePorPagina,
    int desplazamiento = 0,
  }) {
    return Result.guard(() async {
      _validarPaginacion(limite: limite, desplazamiento: desplazamiento);
      if (dia != null) _validarDia(dia);
      if (bloque != null) _validarBloque(bloque);
      if (docenteId != null && docenteId.isNotEmpty) {
        _validarUuid(docenteId, 'el docente');
      }
      if (aulaId != null && aulaId.isNotEmpty) {
        _validarUuid(aulaId, 'el espacio');
      }

      return _gateway.listarGuardias(
        periodo: _textoONulo(periodo),
        docenteId: _textoONulo(docenteId),
        aulaId: _textoONulo(aulaId),
        dia: dia,
        bloque: bloque,
        activa: activa,
        limite: limite,
        desplazamiento: desplazamiento,
      );
    });
  }

  Future<Result<Guardia>> crearGuardia(EntradaCrearGuardia entrada) {
    return Result.guard(() async {
      _validarUuid(entrada.docenteId, 'el docente');
      _validarUuid(entrada.aulaId, 'el espacio');
      _validarPeriodo(entrada.periodo);
      _validarDia(entrada.dia);
      _validarBloque(entrada.bloque);

      final notas = entrada.notas?.trim();

      return _gateway.crearGuardia(
        EntradaCrearGuardia(
          docenteId: entrada.docenteId.trim(),
          aulaId: entrada.aulaId.trim(),
          periodo: entrada.periodo.trim(),
          dia: entrada.dia,
          bloque: entrada.bloque,
          notas: _notasONulo(notas),
        ),
      );
    });
  }

  Future<Result<Guardia>> actualizarGuardia(
    String id,
    CambiosGuardia cambios,
  ) {
    return Result.guard(() async {
      _validarId(id, 'la guardia');

      if (cambios.vacio) {
        throw const AppException.validacion('No hay ningún cambio que guardar.');
      }

      if (cambios.docenteId != null) {
        _validarUuid(cambios.docenteId!, 'el docente');
      }
      if (cambios.aulaId != null) _validarUuid(cambios.aulaId!, 'el espacio');
      if (cambios.periodo != null) _validarPeriodo(cambios.periodo!);
      if (cambios.dia != null) _validarDia(cambios.dia!);
      if (cambios.bloque != null) _validarBloque(cambios.bloque!);

      final notas = cambios.notas?.trim();

      return _gateway.actualizarGuardia(
        id.trim(),
        CambiosGuardia(
          docenteId: cambios.docenteId?.trim(),
          aulaId: cambios.aulaId?.trim(),
          periodo: cambios.periodo?.trim(),
          dia: cambios.dia,
          bloque: cambios.bloque,
          notas: _notasONulo(notas),
          borrarNotas: cambios.borrarNotas,
          activa: cambios.activa,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Cuadrante
  // ---------------------------------------------------------------------------

  Future<Result<RejillaCuadrante>> rejilla({
    String? periodo,
    String? seccionId,
    String? docenteId,
    String? aulaId,
    bool incluirInactivas = false,
  }) {
    return Result.guard(() async {
      if (periodo != null && periodo.trim().isNotEmpty) {
        _validarPeriodo(periodo);
      }

      return _gateway.rejilla(
        periodo: _textoONulo(periodo),
        seccionId: _textoONulo(seccionId),
        docenteId: _textoONulo(docenteId),
        aulaId: _textoONulo(aulaId),
        incluirInactivas: incluirInactivas,
      );
    });
  }

  Future<Result<ClaseCuadrante>> crearClase(EntradaCrearClase entrada) {
    return Result.guard(() async {
      _validarUuid(entrada.seccionId, 'la sección');
      _validarUuid(entrada.docenteId, 'el docente');
      _validarUuid(entrada.aulaId, 'el espacio');
      _validarDia(entrada.dia);
      _validarBloque(entrada.bloque);

      return _gateway.crearClase(
        EntradaCrearClase(
          seccionId: entrada.seccionId.trim(),
          docenteId: entrada.docenteId.trim(),
          aulaId: entrada.aulaId.trim(),
          dia: entrada.dia,
          bloque: entrada.bloque,
        ),
      );
    });
  }

  Future<Result<ClaseCuadrante>> actualizarClase(
    String id,
    CambiosClase cambios,
  ) {
    return Result.guard(() async {
      _validarId(id, 'la clase');

      if (cambios.vacio) {
        throw const AppException.validacion('No hay ningún cambio que guardar.');
      }

      if (cambios.docenteId != null) {
        _validarUuid(cambios.docenteId!, 'el docente');
      }
      if (cambios.aulaId != null) _validarUuid(cambios.aulaId!, 'el espacio');
      if (cambios.dia != null) _validarDia(cambios.dia!);
      if (cambios.bloque != null) _validarBloque(cambios.bloque!);

      return _gateway.actualizarClase(
        id.trim(),
        CambiosClase(
          docenteId: cambios.docenteId?.trim(),
          aulaId: cambios.aulaId?.trim(),
          dia: cambios.dia,
          bloque: cambios.bloque,
          activa: cambios.activa,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Horario por rol
  // ---------------------------------------------------------------------------

  Future<Result<MiHorario>> miHorario({String? periodo}) {
    return Result.guard(() async {
      if (periodo != null && periodo.trim().isNotEmpty) {
        _validarPeriodo(periodo);
      }

      return _gateway.miHorario(periodo: _textoONulo(periodo));
    });
  }

  // ---------------------------------------------------------------------------
  // Validaciones
  // ---------------------------------------------------------------------------

  void _validarId(String id, String que) {
    if (id.trim().isEmpty) {
      throw AppException.validacion('Falta el identificador de $que.');
    }
  }

  void _validarUuid(String valor, String que) {
    final limpio = valor.trim();
    if (limpio.isEmpty) {
      throw AppException.validacion('Elige $que.');
    }
    if (!patronUuid.hasMatch(limpio)) {
      throw AppException.validacion(
        'El identificador de $que no tiene el formato esperado.',
      );
    }
  }

  void _validarNombreDeAula(String nombre) {
    if (nombre.isEmpty) {
      throw const AppException.validacion('Ingresa el nombre del espacio.');
    }
    if (nombre.length > largoMaximoNombreAula) {
      throw const AppException.validacion(
        'El nombre no puede pasar de $largoMaximoNombreAula caracteres.',
      );
    }
  }

  void _validarCapacidad(int capacidad) {
    if (!capacidadValida(capacidad)) {
      // Cero es válido y significa «sin cupo declarado»: una zona, un pasillo.
      throw const AppException.validacion(
        'La capacidad no puede ser negativa. Usa 0 para una zona sin cupo '
        'declarado.',
      );
    }
  }

  void _validarCodigoDeLapso(String codigo) {
    if (codigo.isEmpty) {
      throw const AppException.validacion('Ingresa el código del lapso.');
    }
    if (codigo.length > largoMaximoCodigoLapso) {
      throw const AppException.validacion(
        'El código no puede pasar de $largoMaximoCodigoLapso caracteres.',
      );
    }
    if (!esCodigoDeLapso(codigo)) {
      throw const AppException.validacion(
        'El código sólo admite letras, dígitos y guiones, y debe empezar por '
        'letra o dígito.',
      );
    }
  }

  void _validarNombreDeLapso(String nombre) {
    if (nombre.length > largoMaximoNombreLapso) {
      throw const AppException.validacion(
        'El nombre no puede pasar de $largoMaximoNombreLapso caracteres.',
      );
    }
  }

  void _validarFechas({String? inicio, String? fin}) {
    final desde = inicio?.trim();
    final hasta = fin?.trim();

    if (desde != null && desde.isNotEmpty && !esFechaISO(desde)) {
      throw const AppException.validacion(
        'La fecha de inicio no es una fecha válida (formato AAAA-MM-DD).',
      );
    }
    if (hasta != null && hasta.isNotEmpty && !esFechaISO(hasta)) {
      throw const AppException.validacion(
        'La fecha de fin no es una fecha válida (formato AAAA-MM-DD).',
      );
    }
    if (!rangoDeFechasValido(inicio: desde, fin: hasta)) {
      throw const AppException.validacion(
        'La fecha de fin tiene que ser posterior a la de inicio.',
      );
    }
  }

  void _validarPeriodo(String periodo) {
    final limpio = periodo.trim();
    if (limpio.isEmpty) {
      throw const AppException.validacion('Elige el lapso.');
    }
    if (limpio.length > largoMaximoCodigoLapso) {
      throw const AppException.validacion(
        'El código del lapso no puede pasar de $largoMaximoCodigoLapso '
        'caracteres.',
      );
    }
  }

  void _validarDia(int dia) {
    if (!diaValido(dia)) {
      throw const AppException.validacion(
        'El día tiene que estar entre el lunes y el sábado.',
      );
    }
  }

  void _validarBloque(int bloque) {
    if (!bloqueValido(bloque)) {
      throw const AppException.validacion(
        'El bloque tiene que estar entre 1 y $bloqueMaximo.',
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
    if (busqueda != null && busqueda.length > largoMaximoNombreAula) {
      throw const AppException.validacion(
        'La búsqueda no puede pasar de $largoMaximoNombreAula caracteres.',
      );
    }
  }

  /// Un filtro de texto en blanco equivale a **no filtrar**.
  ///
  /// La normalización va aquí y no en el adaptador porque es ésta la capa que
  /// posee la validación: si dependiera del adaptador, un doble de prueba —o
  /// cualquier otro adaptador futuro— recibiría `'   '` donde el puerto dice
  /// «sin filtro», y cada implementación tendría que acordarse de limpiarlo.
  /// Lo destapó una prueba que esperaba `null` y recibió la cadena con espacios.
  static String? _textoONulo(String? texto) {
    final limpio = texto?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }

  /// Unas notas en blanco se guardan como `null`, no como cadena vacía.
  ///
  /// La columna distingue «no hay notas» de «hay una nota vacía», y sólo la
  /// primera es útil: una cadena vacía hace que la guardia parezca tener un
  /// comentario que al abrirla no dice nada.
  static String? _notasONulo(String? notas) {
    if (notas == null || notas.isEmpty) return null;
    if (notas.length > largoMaximoNotas) {
      throw const AppException.validacion(
        'Las notas no pueden pasar de $largoMaximoNotas caracteres.',
      );
    }
    return notas;
  }
}
