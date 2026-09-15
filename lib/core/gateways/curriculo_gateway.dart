import '../../models/materia.dart';
import '../../models/pensum.dart';
import '../../models/programa.dart';

/// Contrato del Módulo 2 — Currículo y Pensum.
///
/// Separa la fuente de datos (el backend Fastify) de la capa de aplicación,
/// igual que [InvitacionGateway] y [AuditoriaAccesoGateway]. Las
/// implementaciones **lanzan** `AppException` en fallo; el repositorio las
/// envuelve en `Result`. Para los tests se inyecta un doble sin red ni
/// credenciales.
///
/// El puerto declara la **intención**; cómo se cumple es asunto del adaptador.
/// Crear un programa con su pensum se ejecuta en el backend dentro de una sola
/// transacción (una función `security invoker`), pero eso no se ve desde aquí:
/// si mañana cambiara el mecanismo, este contrato seguiría siendo el mismo.
abstract interface class CurriculoGateway {
  /// Pide una página del listado de programas, aplicando los filtros.
  Future<PaginaProgramas> listarProgramas({
    TipoPrograma? tipo,
    bool? activo,
    String? busqueda,
    int limite,
    int desplazamiento,
  });

  /// Detalle de un programa, con el pensum agrupado por período.
  Future<DetallePrograma> detallePrograma(String id);

  /// Crea el programa con su pensum, en una sola operación.
  Future<DetallePrograma> crearPrograma(EntradaCrearPrograma entrada);

  /// Cambia los metadatos de un programa. Ni el código ni el tipo: son su
  /// identidad.
  Future<Programa> actualizarPrograma(String id, CambiosPrograma cambios);

  /// Reemplaza el pensum completo. Es un reemplazo, no un parche: se manda el
  /// estado final y el backend calcula la diferencia.
  Future<DetallePrograma> reemplazarPensum(String id, List<EntradaPensum> pensum);

  /// Pide una página del banco global de materias.
  Future<PaginaMaterias> listarMaterias({
    String? busqueda,
    int limite,
    int desplazamiento,
  });

  /// Registra una materia en caliente, desde el asistente.
  Future<Materia> crearMateria(EntradaCrearMateria entrada);
}

/// Cuerpo de `POST /api/v1/admin/programas`.
class EntradaCrearPrograma {
  const EntradaCrearPrograma({
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.pensum,
    this.requierePasantia = false,
    this.publicar = false,
  });

  final String codigo;
  final String nombre;
  final TipoPrograma tipo;
  final bool requierePasantia;

  /// Decide el `is_active` inicial. Un programa creado sin publicar queda en
  /// borrador y no aparece en el catálogo del aspirante.
  final bool publicar;

  /// Al menos una materia: el esquema del backend lo exige.
  final List<EntradaPensum> pensum;

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        'nombre': nombre,
        'tipo': tipo.valorApi,
        'requierePasantia': requierePasantia,
        'publicar': publicar,
        'pensum': [for (final entrada in pensum) entrada.toJson()],
      };
}

/// Cambios de metadatos de un programa.
///
/// Todos los campos son opcionales, pero se envía **sólo lo que cambia**: el
/// esquema del backend es `.strict()` y rechaza los campos que no reconoce, y
/// mandar `null` donde no se quiere escribir nada sería un intento de borrar.
class CambiosPrograma {
  const CambiosPrograma({this.nombre, this.requierePasantia, this.activo});

  final String? nombre;
  final bool? requierePasantia;
  final bool? activo;

  bool get vacio =>
      nombre == null && requierePasantia == null && activo == null;

  Map<String, dynamic> toJson() => {
        if (nombre != null) 'nombre': nombre,
        if (requierePasantia != null) 'requierePasantia': requierePasantia,
        if (activo != null) 'activo': activo,
      };
}

/// Cuerpo de `POST /api/v1/admin/materias`.
class EntradaCrearMateria {
  const EntradaCrearMateria({
    required this.codigo,
    required this.nombre,
    required this.horasAcademicas,
  });

  final String codigo;
  final String nombre;
  final int horasAcademicas;

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        'nombre': nombre,
        'horasAcademicas': horasAcademicas,
      };
}
