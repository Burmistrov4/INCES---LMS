import '../../models/perfil_usuario.dart';

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

  /// Cambia la contraseña del usuario con sesión activa.
  ///
  /// Sirve para los dos caminos de restablecimiento: el enlace del correo (que
  /// deja una sesión temporal) y el cambio voluntario desde dentro de la app.
  Future<void> actualizarPassword(String password);

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

  /// El perfil propio —la fila de `profiles`—, o `null` si todavía no existe.
  ///
  /// `profiles` se crea en el mismo instante del alta: el trigger
  /// `handle_new_user()` la inserta junto con la ficha, en una sola transacción
  /// (migración `202609120001`). Por eso, para un aprendiz que acaba de
  /// registrarse, esto devuelve una fila **con su nombre ya cargado** y no un
  /// hueco que haya que rellenar.
  ///
  /// Devolver `null` significa «no hay perfil», no «falló la consulta»: un fallo
  /// de red o de RLS **lanza**, como el resto de esta capa.
  Future<PerfilUsuario?> miPerfil();

  /// Corrige el nombre y el apellido del perfil propio y devuelve el perfil
  /// actualizado.
  ///
  /// **Sólo estos dos campos**, y es deliberado: la cédula y el correo son la
  /// identidad con la que la persona se autentica y con la que aparece en la
  /// nómina, y el rol es un privilegio que se concede desde el cPanel. Ver
  /// [PerfilUsuario].
  ///
  /// La autorización no la decide esta capa sino la RLS (ADR-003): `profiles`
  /// tiene `profiles_update_own` para el propio aprendiz y `profiles_admin_all`
  /// para el administrador, que es quien cubre el caso del admin editándose a sí
  /// mismo —su `rol` no es `estudiante`, así que la política de «el propio» no le
  /// aplica—.
  Future<PerfilUsuario> actualizarPerfil({
    required String nombres,
    required String apellidos,
  });
}
