/// Resultado exitoso de `AuthService.registrarAspirante`.
///
/// La UI necesita distinguir dos escenarios reales:
///  - **Confirmación de correo desactivada** → Supabase devuelve sesión y el
///    aspirante entra directo a su panel.
///  - **Confirmación de correo activada** → no hay sesión; hay que pedirle que
///    revise su bandeja antes de poder entrar.
class RegistroResultado {
  final String email;

  /// Id del usuario creado en `auth.users`.
  final String? userId;

  /// `true` si ya hay sesión activa (no hace falta confirmar correo).
  final bool sesionIniciada;

  /// `true` si la ficha de aspirante quedó creada por el trigger.
  final bool fichaCreada;

  /// `true` si el aspirante es menor de edad y requiere representante legal.
  final bool requiereTutorLegal;

  const RegistroResultado({
    required this.email,
    this.userId,
    required this.sesionIniciada,
    required this.fichaCreada,
    required this.requiereTutorLegal,
  });

  /// El usuario debe confirmar su correo antes de poder iniciar sesión.
  bool get requiereConfirmacionEmail => !sesionIniciada;
}
