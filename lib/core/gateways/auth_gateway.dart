/// Resultado de un alta de credenciales.
///
/// Es un objeto propio del dominio y no un `AuthResponse` de Supabase, para que
/// los tests puedan simular el flujo sin depender de tipos del SDK.
class SesionAuth {
  final String? userId;

  /// `true` si Supabase devolvió sesión (confirmación de correo desactivada).
  final bool tieneSesion;

  const SesionAuth({required this.userId, required this.tieneSesion});

  @override
  String toString() => 'SesionAuth(userId: $userId, tieneSesion: $tieneSesion)';
}

/// Contrato de autenticación.
///
/// Existe para romper la deuda D1: antes `AuthService` dependía del singleton
/// `SupabaseService`, cuyo constructor privado impedía inyectar un doble en los
/// tests. Depender de esta interfaz hace testeable todo el camino de red.
abstract interface class AuthGateway {
  /// Id del usuario autenticado, o `null`.
  String? get userId;

  String? get userEmail;

  /// Rol declarado en la metadata del token (respaldo de `rolDePerfil`).
  String? get rolMetadata;

  bool get tieneSesion;

  /// Emite `true` al iniciar sesión y `false` al cerrarla.
  Stream<bool> get cambiosDeSesion;

  Future<void> iniciarConPassword({
    required String email,
    required String password,
  });

  Future<SesionAuth> registrarConPassword({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  });

  Future<void> cerrarSesion();

  Future<void> enviarRecuperacion(String email);

  /// Enlaza una ficha de aspirante huérfana (creada por el bug anterior) con la
  /// cuenta que acaba de autenticarse. `true` si reparó algo.
  Future<bool> vincularFichaPendiente();

  /// Correo asociado a una cédula, o `null` si no existe.
  Future<String?> emailPorCedula(String cedula);

  /// Prechequeo de duplicados **antes** de gastar una llamada a `signUp`.
  ///
  /// Devuelve `OK`, `CEDULA_DUPLICADA`, `EMAIL_DUPLICADO`, `EMAIL_INVALIDO` o
  /// `CEDULA_REQUERIDA`. Vive también en [AspiranteGateway] porque el
  /// repositorio lo expone para el formulario público; una misma
  /// implementación satisface ambas interfaces.
  Future<String> precheck({required String cedula, required String email});

  /// Rol leído del perfil, o `null` si aún no hay perfil.
  Future<String?> rolDePerfil(String userId);
}
