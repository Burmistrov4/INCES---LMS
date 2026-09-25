import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/gateways/planilla_admin_gateway.dart';
import '../models/inscripcion_campo.dart';

/// Implementación de [PlanillaAdminGateway] contra Supabase por PostgREST.
///
/// **Por qué por PostgREST y no por el backend Fastify.** La frontera de
/// autorización del catálogo es la RLS (ADR-003), y las políticas
/// `inscripcion_campos_admin_lectura` e `inscripcion_campos_admin_escritura` ya
/// están escritas para exactamente este límite. Añadir una ruta en Fastify sería
/// una segunda copia de una regla que ya vive en la base, y de las dos copias la
/// que se desvía siempre es la de fuera.
///
/// **Por qué es una clase aparte y no más métodos de `SupabaseService`.** No es
/// preferencia de estilo, es una restricción que el compilador ya nos hizo ver:
/// `SupabaseService` implementa `AspiranteGateway`, que declara
/// `crear(AspiranteModel)` y `actualizar(String, Map<String, dynamic>)`. Dart no
/// admite sobrecarga por tipo de parámetro, así que las dos interfaces **no
/// caben en la misma clase** sin renombrar los métodos del catálogo. La colisión
/// no es un estorbo que esquivar con un `crearCampo`: es la señal de que son dos
/// superficies distintas que no se componen.
///
/// Y al separarla, este archivo sigue la convención que ya usan los otros nueve
/// gateways del proyecto —una implementación por archivo en `lib/services/`—
/// en vez de engordar el agregado heredado con una quinta interfaz.
///
/// **El nombre dice `Supabase` y no `Backend`, a propósito.** Los otros
/// `Backend*Gateway` hablan HTTP contra Fastify; este no. Ponerle `Backend` sería
/// mentir sobre el transporte, que es justo la distinción que hace el ADR-003.
class SupabasePlanillaAdminGateway implements PlanillaAdminGateway {
  /// [client] existe para poder inyectar un cliente en pruebas. En producción se
  /// deja en `null` y se resuelve el de la sesión activa.
  SupabasePlanillaAdminGateway({SupabaseClient? client}) : _inyectado = client;

  final SupabaseClient? _inyectado;

  static const String _tabla = 'inscripcion_campos';

  /// Se resuelve **en cada uso** y no en el constructor, igual que hace
  /// `SupabaseService.client`: así construir el gateway no exige que
  /// `Supabase.initialize` haya corrido todavía.
  SupabaseClient get _client => _inyectado ?? Supabase.instance.client;

  @override
  Future<CatalogoInscripcion> catalogoCompleto() async {
    final respuesta = await _client
        .from(_tabla)
        .select()
        // `orden` NO tiene constraint de unicidad en la base, así que dos campos
        // pueden empatar —de hecho empatan mientras dura un intercambio—. El
        // segundo criterio hace la lista determinista: sin él, dos filas con el
        // mismo `orden` podrían salir en distinto orden en dos consultas seguidas
        // y la lista «saltaría» sin que nadie hubiera tocado nada.
        .order('orden')
        .order('codigo');

    return CatalogoInscripcion.fromJson(<String, dynamic>{'campos': respuesta});
  }

  @override
  Future<CampoInscripcion> crear(CampoInscripcion campo) async {
    final respuesta = await _client
        .from(_tabla)
        .insert(campo.toJson())
        .select()
        .single();

    return CampoInscripcion.fromJson(respuesta);
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
    // `?valor` omite la clave cuando es `null`. PostgREST distingue «no toques
    // esta columna» (clave ausente) de «ponla en NULL», y aquí lo primero es lo
    // que se quiere: un panel que sólo cambia `obligatorio` no debe pisar la
    // etiqueta con un `null`.
    final cambios = <String, dynamic>{
      'etiqueta': ?etiqueta,
      'ayuda': ?ayuda,
      'grupo': ?grupo,
      'obligatorio': ?obligatorio,
      'activo': ?activo,
      'orden': ?orden,
    };

    if (cambios.isEmpty) {
      throw ArgumentError('No se indicó ningún cambio para el campo $codigo.');
    }

    final respuesta = await _client
        .from(_tabla)
        .update(cambios)
        .eq('codigo', codigo)
        .select()
        .single();

    return CampoInscripcion.fromJson(respuesta);
  }

  @override
  Future<void> intercambiarOrden({
    required CampoInscripcion actual,
    required CampoInscripcion vecino,
  }) async {
    // Dos `update` secuenciales, y el orden entre ellos da igual porque `orden`
    // no tiene `unique`: no hay colisión transitoria que esquivar. Si alguien
    // añadiera un `unique (orden)` en el futuro, este intercambio empezaría a
    // fallar a mitad y habría que pasar por un valor temporal.
    //
    // No es atómico —PostgREST no da transacciones por petición— y se documenta
    // en vez de disimularse: si el segundo `update` falla, las dos filas quedan
    // con el MISMO `orden`. Eso no corrompe nada (el desempate por `codigo`
    // mantiene la lista determinista) y se arregla repitiendo el intercambio.
    await _client
        .from(_tabla)
        .update({'orden': vecino.orden}).eq('codigo', actual.codigo);

    await _client
        .from(_tabla)
        .update({'orden': actual.orden}).eq('codigo', vecino.codigo);
  }
}
