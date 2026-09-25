import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/planilla_admin_gateway.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';

/// Doble de [PlanillaAdminGateway] con el estilo del resto de dobles del
/// proyecto: se le asigna lo que debe devolver y, para forzar un fallo, la
/// excepción en el campo `error*` correspondiente. Registra las llamadas y sus
/// argumentos para que una prueba pueda comprobar que el panel delegó de verdad.
///
/// **Implementa la mutación sobre su propia lista, y no es un lujo.** El panel
/// relee el catálogo después de un intercambio de orden y después de un alta, así
/// que un doble que devolviera siempre lo mismo dejaría esas dos rutas sin
/// ejercitar: la prueba pasaría y la pantalla seguiría pintando el catálogo
/// viejo, que es exactamente el fallo que se quiere detectar. Aquí `campos` es el
/// estado, y `crear`/`actualizar`/`intercambiarOrden` lo modifican como lo haría
/// la base.
///
/// Las mutaciones **reproducen el rechazo**, no sólo la respuesta: un `codigo`
/// repetido lanza `23505` igual que lo haría el `unique` de la tabla, porque un
/// doble que aceptara todo convertiría una validación ausente en un verde.
class FakePlanillaAdminGateway implements PlanillaAdminGateway {
  /// El estado del catálogo. Se asigna antes de montar el panel.
  List<CampoInscripcion> campos = const [];

  Object? errorAlLeer;
  Object? errorAlCrear;
  Object? errorAlActualizar;
  Object? errorAlIntercambiar;

  final List<String> llamadas = [];

  /// El campo que llegó a [crear], tal cual.
  CampoInscripcion? ultimoCreado;

  /// El código y los cambios que llegaron a [actualizar].
  String? codigoActualizado;
  Map<String, dynamic>? cambiosActualizados;

  /// Los dos campos que llegaron a [intercambiarOrden].
  (CampoInscripcion, CampoInscripcion)? ultimoIntercambio;

  @override
  Future<CatalogoInscripcion> catalogoCompleto() async {
    llamadas.add('catalogoCompleto');
    final error = errorAlLeer;
    if (error != null) throw error;

    // Se ordena como lo hace la consulta real: por `orden` y, como `orden` no
    // tiene `unique`, desempatando por `codigo`. Sin el desempate, dos campos
    // recién intercambiados podrían salir en cualquier orden y la prueba de
    // reordenación sería inestable.
    final ordenados = [...campos]..sort((a, b) {
        final porOrden = a.orden.compareTo(b.orden);
        return porOrden != 0 ? porOrden : a.codigo.compareTo(b.codigo);
      });

    return CatalogoInscripcion(ordenados);
  }

  @override
  Future<CampoInscripcion> crear(CampoInscripcion campo) async {
    llamadas.add('crear');
    ultimoCreado = campo;
    final error = errorAlCrear;
    if (error != null) throw error;

    if (campos.any((c) => c.codigo == campo.codigo)) {
      throw AppException.duplicado(
        'Ya existe un campo con ese código en el catálogo.',
        code: '23505',
      );
    }

    campos = [...campos, campo];
    return campo;
  }

  @override
  Future<CampoInscripcion> actualizar({
    required String codigo,
    String? etiqueta,
    String? ayuda,
    String? grupo,
    bool? obligatorio,
    bool? activo,
    int? orden,
  }) async {
    llamadas.add('actualizar');
    codigoActualizado = codigo;
    cambiosActualizados = {
      'etiqueta': ?etiqueta,
      'ayuda': ?ayuda,
      'grupo': ?grupo,
      'obligatorio': ?obligatorio,
      'activo': ?activo,
      'orden': ?orden,
    };

    final error = errorAlActualizar;
    if (error != null) throw error;

    final indice = campos.indexWhere((c) => c.codigo == codigo);
    if (indice < 0) {
      throw AppException.validacion(
        'No encontramos ese campo en el catálogo.',
        code: 'PGRST116',
      );
    }

    final actualizado = _copia(
      campos[indice],
      etiqueta: etiqueta,
      grupo: grupo,
      obligatorio: obligatorio,
      activo: activo,
      orden: orden,
      // La base guarda `''` y el modelo lo normaliza a `null` al leer: borrar la
      // ayuda es mandar cadena vacía, no mandar `null` (que significa «no toques
      // esta columna»). El doble tiene que reproducir esa normalización o la
      // prueba de borrado no probaría lo que dice probar.
      ayuda: ayuda,
    );

    campos = [
      for (final c in campos)
        if (c.codigo == codigo) actualizado else c,
    ];
    return actualizado;
  }

  @override
  Future<void> intercambiarOrden({
    required CampoInscripcion actual,
    required CampoInscripcion vecino,
  }) async {
    llamadas.add('intercambiarOrden');
    ultimoIntercambio = (actual, vecino);
    final error = errorAlIntercambiar;
    if (error != null) throw error;

    campos = [
      for (final c in campos)
        if (c.codigo == actual.codigo)
          _copia(c, orden: vecino.orden)
        else if (c.codigo == vecino.codigo)
          _copia(c, orden: actual.orden)
        else
          c,
    ];
  }
}

/// Copia un campo cambiando sólo lo que se le pasa.
///
/// Existe porque el modelo es inmutable y no tiene `copyWith`: en el doble la
/// construcción explícita es preferible, porque obliga a decidir qué pasa con
/// cada campo en vez de arrastrar un default que podría no coincidir con el de
/// la base.
CampoInscripcion _copia(
  CampoInscripcion base, {
  String? etiqueta,
  String? grupo,
  int? orden,
  bool? obligatorio,
  bool? activo,
  String? ayuda,
}) {
  return CampoInscripcion(
    codigo: base.codigo,
    etiqueta: etiqueta ?? base.etiqueta,
    grupo: grupo ?? base.grupo,
    tipo: base.tipo,
    orden: orden ?? base.orden,
    obligatorio: obligatorio ?? base.obligatorio,
    activo: activo ?? base.activo,
    opciones: base.opciones,
    fuente: base.fuente,
    condicion: base.condicion,
    // Tres casos, no dos: `null` es «no toques esta columna», `''` es «bórrala» y
    // cualquier otra cosa es el texto nuevo. Colapsar los dos primeros en uno
    // —que es lo que hace un `ayuda ?? base.ayuda`— dejaría el borrado sin
    // implementar y la prueba de borrado pasaría sin borrar nada.
    ayuda: ayuda == null ? base.ayuda : (ayuda.isEmpty ? null : ayuda),
    aplicaA: base.aplicaA,
  );
}
