import 'package:inces_lms_app/core/gateways/exportacion_hacer_gateway.dart';
import 'package:inces_lms_app/models/exportacion_hacer.dart';

/// Doble de prueba de [ExportacionHacerGateway].
///
/// Cumple el puerto sin red ni Supabase. Registra **qué sección se pidió**, que
/// es el contrato que importa: el botón del panel debe exportar la sección de su
/// tarjeta, no «una sección».
class FakeExportacionHacerGateway implements ExportacionHacerGateway {
  /// Lo que devuelve [filasDeSeccion]. Vacío por defecto: una sección sin
  /// matriculados, que es un caso legítimo y hay que poder probar.
  List<FilaExportacionHacer> filasDevueltas = const [];

  /// Fuerza un fallo de la consulta.
  ///
  /// Se **lanza** y no se devuelve: un `null` o una lista vacía ya significan
  /// «no hay filas», así que señalizar un fallo con ellos haría que la prueba no
  /// distinguiera «no hay nadie» de «la vista no respondió» — y son cosas
  /// opuestas para el administrador.
  Object? errorAlConsultar;

  final List<String> llamadas = [];

  @override
  Future<List<FilaExportacionHacer>> filasDeSeccion(String seccionId) async {
    llamadas.add('filasDeSeccion:$seccionId');
    if (errorAlConsultar != null) throw errorAlConsultar!;
    return filasDevueltas;
  }
}

/// Fixture: una fila con **todas** las columnas declaradas presentes.
///
/// El valor por defecto de cada celda es el nombre de su propia columna. Así una
/// prueba puede comprobar cabecera y celdas contra la misma lista sin escribir
/// 61 literales, y —lo que importa más— el fixture no se queda corto en silencio
/// el día que se añada una columna: crece con la lista.
FilaExportacionHacer filaExportacionEjemplo({
  Map<String, dynamic> sobrescribir = const {},
}) =>
    FilaExportacionHacer({
      for (final columna in columnasExportacionHacer) columna: columna,
      ...sobrescribir,
    });
