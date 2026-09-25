import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/gateways/aspirante_gateway.dart';
import '../core/gateways/auth_gateway.dart';
import '../core/gateways/modules_gateway.dart';
import '../models/aspirante_model.dart';
import '../models/config_audit_entry.dart';
import '../models/inscripcion_campo.dart';
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
  Future<String?> emailPorCedula(String cedula) async {
    final respuesta = await client
        .from(_tablaPerfiles)
        .select('email')
        .eq('cedula', cedula)
        .maybeSingle();

    final email = respuesta?['email'] as String?;
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
    // relación incrustada. Es la única ruta que pide `programs(name)` porque es la
    // única que pinta el nombre —el panel del aspirante—; las demás devuelven el
    // modelo con `programaNombre` nulo, y quien lo pinte debe tener respaldo.
    //
    // Se comprobó contra la API real que PostgREST resuelve el embed por
    // `aspirantes_program_id_fkey` (un embed inventado devuelve 400 PGRST200, así
    // que el 200 no es un falso positivo).
    final respuesta = await client
        .from(_tablaAspirantes)
        .select('*, programs(name)')
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
