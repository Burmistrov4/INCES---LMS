import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/gateways/aspirante_gateway.dart';
import '../core/gateways/auth_gateway.dart';
import '../core/gateways/modules_gateway.dart';
import '../models/aspirante_model.dart';
import '../models/config_audit_entry.dart';
import '../models/inscripcion_campo.dart';
import '../models/perfil_usuario.dart';
import '../models/system_module.dart';
import '../models/system_setting.dart';

/// Implementación real de los gateways sobre Supabase.
///
/// Contrato de esta capa: **lanza** excepciones cuando algo falla. Nunca
/// devuelve `null` para señalar un error. La traducción a `AppException` ocurre
/// en los repositorios, vía `AppException.from`.
///
/// Al implementar las interfaces de `core/gateways`, esta clase dejó de ser un
/// singleton inalcanzable para los tests (deuda D1): basta con inyectar un doble
/// que cumpla el mismo contrato.
class SupabaseService implements AuthGateway, AspiranteGateway, ModulesGateway {
  SupabaseService._();

  static final SupabaseService _instance = SupabaseService._();
  static SupabaseService get instance => _instance;

  SupabaseClient get client => Supabase.instance.client;
  GoTrueClient get auth => client.auth;

  static const String _tablaAspirantes = 'aspirantes';
  static const String _tablaPerfiles = 'profiles';
  /// D14: la oferta formativa se lee de `programs`, no de la vista `cursos`.
  ///
  /// `cursos` se retiró en `202609250002` —esta capa era su último consumidor—,
  /// así que `programs` es ya la única fuente de la oferta formativa.
  static const String _tablaPrograms = 'programs';
  static const String _tablaModulos = 'system_modules';
  static const String _tablaSettings = 'system_settings';
  static const String _tablaAuditoria = 'config_audit_log';

  Future<void> initialize() async {
    await client.auth.refreshSession();
  }

  // ---------------------------------------------------------------------------
  // AuthGateway
  // ---------------------------------------------------------------------------

  @override
  String? get userId => auth.currentUser?.id;

  @override
  String? get userEmail => auth.currentUser?.email;

  @override
  String? get rolMetadata {
    final rol = auth.currentUser?.userMetadata?['rol'];
    return rol is String ? rol : null;
  }

  @override
  bool get tieneSesion => auth.currentSession != null;

  @override
  Stream<bool> get cambiosDeSesion =>
      auth.onAuthStateChange.map((estado) => estado.session != null);

  @override
  Future<void> iniciarConPassword({
    required String email,
    required String password,
  }) async {
    await auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<SesionAuth> registrarConPassword({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    final respuesta = await auth.signUp(
      email: email,
      password: password,
      data: metadata,
    );

    return SesionAuth(
      userId: respuesta.user?.id,
      tieneSesion: respuesta.session != null,
    );
  }

  @override
  Future<void> cerrarSesion() async {
    await auth.signOut();
  }

  @override
  Future<void> enviarRecuperacion(String email) async {
    await auth.resetPasswordForEmail(email);
  }

  @override
  Future<void> actualizarPassword(String password) async {
    await auth.updateUser(UserAttributes(password: password));
  }

  @override
  /// El correo de la ficha cuya cédula coincida, o `null`.
  ///
  /// **Va por RPC y no por consulta directa, y el motivo es que la consulta
  /// directa no podía funcionar.** El login ocurre **sin sesión**, así que la
  /// lectura la decide la RLS, y son dos causas apiladas medidas el 2026-10-01:
  ///
  ///   1. `profiles.cedula` está rellena en **1 de 6** perfiles —la cédula real
  ///      vive en `aspirantes`—.
  ///   2. Las tres políticas de `profiles` son **todas para `authenticated`**.
  ///      Ninguna incluye `anon`, así que la consulta devolvía **cero filas** y
  ///      esto lo leía como «la cédula no existe».
  ///
  /// `email_por_cedula` es `security definer` y devuelve **un `text`**: el correo,
  /// o `NULL` si no hay ficha. No expone el padrón —`anon` gana `EXECUTE` sobre
  /// esa función y nada más— y **normaliza por dígitos en ambos lados**, así que
  /// `V-12345678` y `12345678` resuelven igual. Esa normalización vive en la base
  /// a propósito: un solo sitio decide qué cédulas son iguales, y el cliente no
  /// puede olvidarse de aplicarla.
  ///
  /// El contrato de salida **no cambia** respecto de la versión anterior —correo
  /// o `null`—, así que `AuthService` sigue igual: si la RPC devuelve `null`, o
  /// una cadena vacía, esto devuelve `null` y el servicio lanza su mensaje
  /// genérico de credenciales.
  @override
  Future<String?> emailPorCedula(String cedula) async {
    final limpia = cedula.trim();
    if (limpia.isEmpty) return null;

    // `rpc` devuelve `dynamic`: la función declara `returns text`, así que un
    // `as String?` es correcto, pero un `null` de SQL llega como `null` de Dart
    // y no como la cadena "null".
    final email = await client.rpc(
      'email_por_cedula',
      params: {'p_cedula': limpia},
    ) as String?;

    if (email == null || email.isEmpty) return null;
    return email;
  }

  @override
  Future<String?> rolDePerfil(String userId) async {
    final perfil = await client
        .from(_tablaPerfiles)
        .select('rol')
        .eq('id', userId)
        .maybeSingle();

    final rol = perfil?['rol'] as String?;
    if (rol == null || rol.isEmpty) return null;
    return rol;
  }

  @override
  Future<PerfilUsuario?> miPerfil() async {
    final id = userId;
    if (id == null) return null;

    final fila = await client
        .from(_tablaPerfiles)
        .select('id, email, nombres, apellidos, rol')
        .eq('id', id)
        .maybeSingle();

    if (fila == null) return null;
    return PerfilUsuario.fromJson(fila);
  }

  @override
  Future<PerfilUsuario> actualizarPerfil({
    required String nombres,
    required String apellidos,
  }) async {
    final id = userId;
    if (id == null) {
      // Sin sesión no hay a quién editarle el perfil. Se lanza en vez de
      // devolver un perfil inventado: el contrato de esta capa es que un fallo
      // se señala lanzando, y un `PerfilUsuario` de mentira se pintaría en la
      // pantalla como si el guardado hubiera funcionado.
      throw StateError('No hay sesión activa para actualizar el perfil.');
    }

    // `select()` + `single()` y no un `update` a secas, por una razón concreta:
    // así lo que se devuelve es la fila que quedó **en la base**, no la que
    // creemos haber mandado. Si una política de RLS filtrara la escritura,
    // PostgREST devuelve **cero filas** y `single()` falla (`PGRST116`) en vez de
    // dar por bueno un cambio que nunca ocurrió.
    //
    // `updated_at` no viaja: lo pone el trigger `profiles_set_updated_at`. Mandarlo
    // desde aquí sería una segunda fuente de verdad para la misma columna.
    final fila = await client
        .from(_tablaPerfiles)
        .update({'nombres': nombres, 'apellidos': apellidos})
        .eq('id', id)
        .select('id, email, nombres, apellidos, rol')
        .single();

    return PerfilUsuario.fromJson(fila);
  }

  // ---------------------------------------------------------------------------
  // AspiranteGateway
  // ---------------------------------------------------------------------------

  @override
  Future<String> precheck({
    required String cedula,
    required String email,
  }) async {
    final respuesta = await client.rpc(
      'precheck_aspirante',
      params: {'p_cedula': cedula, 'p_email': email},
    );
    return (respuesta as String?) ?? 'OK';
  }

  @override
  Future<bool> vincularFichaPendiente() async {
    final respuesta = await client.rpc('link_pending_aspirante');
    return (respuesta as bool?) ?? false;
  }

  @override
  Future<AspiranteModel?> porCedula(String cedula) async {
    final respuesta = await client
        .from(_tablaAspirantes)
        .select()
        .eq('cedula', cedula)
        .maybeSingle();

    if (respuesta == null) return null;
    return AspiranteModel.fromJson(respuesta);
  }

  @override
  Future<List<AspiranteModel>> todos() async {
    final respuesta = await client.from(_tablaAspirantes).select();
    return respuesta.map(AspiranteModel.fromJson).toList();
  }

  @override
  Future<AspiranteModel?> porId(String id) async {
    final respuesta = await client
        .from(_tablaAspirantes)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (respuesta == null) return null;
    return AspiranteModel.fromJson(respuesta);
  }

  @override
  Future<AspiranteModel?> miFicha() async {
    final id = userId;
    if (id == null) return null;

    // D14: la ficha ya no guarda el NOMBRE del programa, así que se trae por la
    // relación incrustada. La proyección es explícita y contiene exactamente los
    // campos que `AspiranteModel` consume, incluida `datos_planilla`: una columna
    // nueva en `aspirantes` no debe aumentar silenciosamente el payload de cada
    // apertura del dashboard.
    // `programs(name)` es la única relación incrustada porque es la única que pinta
    // el nombre —las demás devuelven el modelo con `programaNombre` nulo, y quien
    // lo pinte debe tener respaldo.
    //
    // Se comprobó contra la API real que PostgREST resuelve el embed por
    // `aspirantes_program_id_fkey` (un embed inventado devuelve 400 PGRST200, así
    // que el 200 no es un falso positivo).
    final respuesta = await client
        .from(_tablaAspirantes)
        .select('id, user_id, nombres, apellidos, cedula, fecha_nac, sexo, telefono, email, direccion, nivel_educativo, program_id, mision_ribaras, discapacidad, tipo_discapacidad, numero_identidad_tutor, nombre_tutor, parentesco_tutor, telefono_tutor, correo_tutor, requires_legal_tutor, datos_planilla, created_at, updated_at, programs(name)')
        .eq('user_id', id)
        .maybeSingle();

    if (respuesta == null) return null;
    return AspiranteModel.fromJson(respuesta);
  }

  @override
  Future<AspiranteModel> crear(AspiranteModel modelo) async {
    final respuesta = await client
        .from(_tablaAspirantes)
        .insert(modelo.toJson())
        .select()
        .single();
    return AspiranteModel.fromJson(respuesta);
  }

  @override
  Future<AspiranteModel> actualizar(
    String id,
    Map<String, dynamic> data,
  ) async {
    final respuesta = await client
        .from(_tablaAspirantes)
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return AspiranteModel.fromJson(respuesta);
  }

  @override
  Future<void> eliminar(String id) async {
    await client.from(_tablaAspirantes).delete().eq('id', id);
  }

  @override
  Future<List<OpcionCampo>> programasDisponibles() async {
    // Los dos filtros son la Decisión 1, y viven también aquí y no sólo en la
    // base: `type = CURSO_LIBRE` porque la inscripción pública es de formación
    // continua —las carreras tienen otro ciclo de admisión—, y `is_active` porque
    // un borrador no debe asomar en el formulario.
    //
    // La RLS ya limita `programs` a `anon` con `using (is_active)`, pero eso sólo
    // cubre a quien consulta sin sesión. El filtro explícito hace que el resultado
    // sea el mismo para `anon` y para `authenticated`, que sí ve los borradores.
    final respuesta = await client
        .from(_tablaPrograms)
        .select('id, name')
        .eq('type', 'CURSO_LIBRE')
        .eq('is_active', true)
        .order('name');

    return respuesta
        .map(
          (fila) => OpcionCampo(
            // D14: el VALOR es el uuid y la ETIQUETA el nombre. Es el cambio que
            // hace que renombrar un programa no toque ninguna ficha.
            valor: (fila['id'] ?? '').toString(),
            etiqueta: (fila['name'] ?? '').toString(),
          ),
        )
        // Una fila sin id o sin nombre no es una opción: pintarla daría una
        // casilla que el aspirante no puede identificar y que enviaría un uuid
        // vacío. Se descarta en vez de propagar el problema al envío.
        .where((opcion) => opcion.valor.isNotEmpty && opcion.etiqueta.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<bool> existeEmail(String email) async {
    final respuesta = await client
        .from(_tablaPerfiles)
        .select('cedula')
        .eq('email', email)
        .maybeSingle();
    return respuesta != null;
  }

  // ---------------------------------------------------------------------------
  // ModulesGateway (Fase 3)
  // ---------------------------------------------------------------------------

  @override
  Future<List<SystemModule>> modulos() async {
    final respuesta =
        await client.from(_tablaModulos).select().order('orden').order('clave');
    return respuesta.map(SystemModule.fromJson).toList(growable: false);
  }

  @override
  Future<SystemModule> actualizarModulo({
    required String clave,
    bool? habilitado,
    int? orden,
    List<String>? rolesPermitidos,
  }) async {
    final cambios = <String, dynamic>{
      'habilitado': ?habilitado,
      'orden': ?orden,
      'roles_permitidos': ?rolesPermitidos,
    };

    if (cambios.isEmpty) {
      throw ArgumentError('No se indicó ningún cambio para el módulo $clave.');
    }

    final respuesta = await client
        .from(_tablaModulos)
        .update(cambios)
        .eq('clave', clave)
        .select()
        .single();

    return SystemModule.fromJson(respuesta);
  }

  @override
  Future<List<SystemSetting>> settings() async {
    final respuesta = await client
        .from(_tablaSettings)
        .select()
        .order('categoria')
        .order('clave');
    return respuesta.map(SystemSetting.fromJson).toList(growable: false);
  }

  @override
  Future<SystemSetting> actualizarSetting({
    required String clave,
    required Object? valor,
  }) async {
    final respuesta = await client
        .from(_tablaSettings)
        .update({'valor': valor})
        .eq('clave', clave)
        .select()
        .single();

    return SystemSetting.fromJson(respuesta);
  }

  @override
  Future<List<ConfigAuditEntry>> auditoria({int limite = 50}) async {
    final respuesta = await client
        .from(_tablaAuditoria)
        .select()
        .order('created_at', ascending: false)
        .limit(limite);

    return respuesta.map(ConfigAuditEntry.fromJson).toList(growable: false);
  }
}
