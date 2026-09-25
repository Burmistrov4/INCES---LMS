import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/gateways/exportacion_hacer_gateway.dart';
import '../models/exportacion_hacer.dart';

/// Implementación de [ExportacionHacerGateway] contra Supabase por PostgREST.
///
/// **Por qué por PostgREST y no por el backend Fastify.** La frontera de
/// autorización de la vista es la RLS (ADR-003): `v_exportacion_hacer` es
/// `security_invoker`, así que las políticas de `enrollments`, `sections`,
/// `aspirantes` y `schedule_slots` deciden qué filas ve cada rol. Añadir una
/// ruta en Fastify sería una segunda copia de esa regla, y de las dos copias la
/// que se desvía siempre es la de fuera. Es el mismo razonamiento —y la misma
/// decisión— que documenta `SupabasePlanillaAdminGateway`.
///
/// **El nombre dice `Supabase` y no `Backend`, a propósito.** Los otros
/// `Backend*Gateway` hablan HTTP contra Fastify; este no. Ponerle `Backend`
/// mentiría sobre el transporte, que es justo la distinción que hace el ADR-003.
class SupabaseExportacionHacerGateway implements ExportacionHacerGateway {
  /// [client] existe para poder inyectar un cliente en pruebas. En producción se
  /// deja en `null` y se resuelve el de la sesión activa.
  SupabaseExportacionHacerGateway({SupabaseClient? client}) : _inyectado = client;

  final SupabaseClient? _inyectado;

  static const String _vista = 'v_exportacion_hacer';

  /// Se resuelve **en cada uso** y no en el constructor, igual que hacen
  /// `SupabaseService` y `SupabasePlanillaAdminGateway`: así construir el
  /// gateway no exige que `Supabase.initialize` haya corrido todavía.
  SupabaseClient get _client => _inyectado ?? Supabase.instance.client;

  @override
  Future<List<FilaExportacionHacer>> filasDeSeccion(String seccionId) async {
    final respuesta = await _client
        .from(_vista)
        .select()
        .eq('seccion_id', seccionId)
        // Orden por apellido para que la nómina se lea como una lista de clase y
        // para que dos exportaciones de la misma sección den el MISMO archivo.
        // `cedula` cierra los empates: dos hermanos con los mismos apellidos y
        // nombres dejarían el orden a merced del planificador, y un CSV que
        // cambia de orden entre descargas es un CSV que nadie puede comparar.
        //
        // El orden se pide aquí y no en la vista a propósito: una vista no
        // garantiza orden, y pedirlo donde no se garantiza es una promesa que la
        // base no hizo.
        .order('apellidos')
        .order('nombres')
        .order('cedula');

    return (respuesta as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(FilaExportacionHacer.new)
        .toList(growable: false);
  }
}
