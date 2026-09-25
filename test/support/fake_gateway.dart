import 'package:inces_lms_app/core/gateways/aspirante_gateway.dart';
import 'package:inces_lms_app/core/gateways/auth_gateway.dart';
import 'package:inces_lms_app/core/gateways/modules_gateway.dart';
import 'package:inces_lms_app/models/aspirante_model.dart';
import 'package:inces_lms_app/models/config_audit_entry.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/models/system_setting.dart';

/// Doble de prueba que cumple los tres gateways.
///
/// Existe gracias a la resolución de la deuda D1: antes `SupabaseService` tenía
/// constructor privado y era imposible simular el camino de red.
///
/// Uso: se asigna el resultado deseado y, si se quiere forzar un fallo, se
/// coloca la excepción en el campo `error*` correspondiente.
class FakeGateway implements AuthGateway, AspiranteGateway, ModulesGateway {
  // --- AuthGateway ---------------------------------------------------------

  @override
  String? userId = 'user-1';

  @override
  String? userEmail = 'aspirante@example.com';

  @override
  String? rolMetadata;

  @override
  bool tieneSesion = false;

  @override
  Stream<bool> cambiosDeSesion = const Stream<bool>.empty();

  /// Resultado devuelto por `registrarConPassword`.
  SesionAuth sesionRegistro = const SesionAuth(
    userId: 'user-1',
    tieneSesion: true,
  );

  /// Código devuelto por `precheck`.
  String precheckResultado = 'OK';

  /// La metadata que recibió `registrarConPassword`, si la hubo.
  ///
  /// Se guarda **entera** y no un resumen: es la única forma de comprobar de
  /// punta a punta lo que el formulario manda a `auth.users` —que `nombres` y
  /// `apellidos` viajan ya sintetizados, que `datos_planilla` va, y que
  /// `mision_ribaras` **no** va—. Comprobar eso en el modelo por separado no
  /// probaría que la pantalla lo llama bien.
  Map<String, dynamic>? ultimaMetadata;

  /// El correo con el que se llamó a `registrarConPassword`.
  String? ultimoEmailRegistro;

  /// La contraseña con la que se llamó a `registrarConPassword`.
  String? ultimaPasswordRegistro;

  String? emailDeCedula;
  String? rolDelPerfil;

  Object? errorAlIniciar;
  Object? errorAlRegistrar;
  Object? errorAlPrecheck;
  Object? errorAlVincular;
  Object? errorAlActualizarPassword;

  // --- AspiranteGateway ----------------------------------------------------

  AspiranteModel? ficha;
  List<AspiranteModel> fichas = const [];

  /// La oferta formativa que devuelve [programasDisponibles].
  ///
  /// **Son `OpcionCampo` y no `String`, y el uuid es falso pero distinto del
  /// nombre a propósito.** Con D14 lo que viaja a la ficha es el identificador
  /// del programa, no su nombre; un doble que devolviera el nombre en los dos
  /// campos dejaría pasar un fallo real —que la pantalla guardara la etiqueta en
  /// vez del valor— porque las dos cosas serían iguales.
  List<OpcionCampo> programas = const [
    OpcionCampo(valor: 'uuid-herreria', etiqueta: 'Herrería'),
  ];

  bool existeEmailResultado = false;

  Object? errorAlListar;
  Object? errorAlObtener;
  Object? errorAlCrear;
  Object? errorAlProgramas;

  // --- ModulesGateway ------------------------------------------------------

  List<SystemModule> listaModulos = const [];
  List<SystemSetting> listaSettings = const [];
  List<ConfigAuditEntry> listaAuditoria = const [];

  Object? errorAlListarModulos;
  Object? errorAlActualizarModulo;
  Object? errorAlListarSettings;
  Object? errorAlActualizarSetting;
  Object? errorAlListarAuditoria;

  // --- Registro de llamadas (para verificar el ORDEN del flujo) ------------

  final List<String> llamadas = [];

  void limpiarLlamadas() => llamadas.clear();

  // --- Implementación AuthGateway ------------------------------------------

  @override
  Future<void> iniciarConPassword({
    required String email,
    required String password,
  }) async {
    llamadas.add('iniciarConPassword');
    _lanzarSi(errorAlIniciar);
    tieneSesion = true;
  }

  @override
  Future<SesionAuth> registrarConPassword({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    llamadas.add('registrarConPassword');
    ultimoEmailRegistro = email;
    ultimaPasswordRegistro = password;
    ultimaMetadata = metadata;
    _lanzarSi(errorAlRegistrar);
    return sesionRegistro;
  }

  @override
  Future<void> cerrarSesion() async {
    llamadas.add('cerrarSesion');
    tieneSesion = false;
  }

  @override
  Future<void> enviarRecuperacion(String email) async {
    llamadas.add('enviarRecuperacion');
  }

  @override
  Future<void> actualizarPassword(String password) async {
    llamadas.add('actualizarPassword');
    _lanzarSi(errorAlActualizarPassword);
  }

  @override
  Future<bool> vincularFichaPendiente() async {
    llamadas.add('vincularFichaPendiente');
    _lanzarSi(errorAlVincular);
    return false;
  }

  @override
  Future<String?> emailPorCedula(String cedula) async {
    llamadas.add('emailPorCedula');
    return emailDeCedula;
  }

  @override
  Future<String?> rolDePerfil(String userId) async {
    llamadas.add('rolDePerfil');
    return rolDelPerfil;
  }

  // --- Implementación AspiranteGateway -------------------------------------

  @override
  Future<String> precheck({
    required String cedula,
    required String email,
  }) async {
    llamadas.add('precheck');
    _lanzarSi(errorAlPrecheck);
    return precheckResultado;
  }

  @override
  Future<AspiranteModel?> porCedula(String cedula) async {
    llamadas.add('porCedula');
    _lanzarSi(errorAlObtener);
    return ficha;
  }

  @override
  Future<List<AspiranteModel>> todos() async {
    llamadas.add('todos');
    _lanzarSi(errorAlListar);
    return fichas;
  }

  @override
  Future<AspiranteModel?> porId(String id) async {
    llamadas.add('porId');
    _lanzarSi(errorAlObtener);
    return ficha;
  }

  @override
  Future<AspiranteModel?> miFicha() async {
    llamadas.add('miFicha');
    _lanzarSi(errorAlObtener);
    return ficha;
  }

  @override
  Future<AspiranteModel> crear(AspiranteModel modelo) async {
    llamadas.add('crear');
    _lanzarSi(errorAlCrear);
    return modelo;
  }

  @override
  Future<AspiranteModel> actualizar(
    String id,
    Map<String, dynamic> data,
  ) async {
    llamadas.add('actualizar');
    _lanzarSi(errorAlCrear);
    return ficha ?? _modeloVacio();
  }

  @override
  Future<void> eliminar(String id) async {
    llamadas.add('eliminar');
    _lanzarSi(errorAlCrear);
  }

  @override
  Future<List<OpcionCampo>> programasDisponibles() async {
    llamadas.add('programasDisponibles');
    _lanzarSi(errorAlProgramas);
    return programas;
  }

  @override
  Future<bool> existeEmail(String email) async {
    llamadas.add('existeEmail');
    return existeEmailResultado;
  }

  // --- Implementación ModulesGateway ---------------------------------------

  @override
  Future<List<SystemModule>> modulos() async {
    llamadas.add('modulos');
    _lanzarSi(errorAlListarModulos);
    return listaModulos;
  }

  @override
  Future<SystemModule> actualizarModulo({
    required String clave,
    bool? habilitado,
    int? orden,
    List<String>? rolesPermitidos,
  }) async {
    llamadas.add('actualizarModulo:$clave');
    _lanzarSi(errorAlActualizarModulo);

    final actual = listaModulos.firstWhere(
      (m) => m.clave == clave,
      orElse: () => SystemModule(
        clave: clave,
        nombre: clave,
        habilitado: false,
      ),
    );

    final actualizado = actual.copyWith(
      habilitado: habilitado,
      orden: orden,
      rolesPermitidos: rolesPermitidos,
    );

    listaModulos = [
      for (final m in listaModulos)
        if (m.clave == clave) actualizado else m,
    ];

    return actualizado;
  }

  @override
  Future<List<SystemSetting>> settings() async {
    llamadas.add('settings');
    _lanzarSi(errorAlListarSettings);
    return listaSettings;
  }

  @override
  Future<SystemSetting> actualizarSetting({
    required String clave,
    required Object? valor,
  }) async {
    llamadas.add('actualizarSetting:$clave');
    _lanzarSi(errorAlActualizarSetting);

    final actual = listaSettings.firstWhere(
      (s) => s.clave == clave,
      orElse: () => SystemSetting(clave: clave, valor: valor),
    );

    final actualizado = actual.copyWith(valor: valor);

    listaSettings = [
      for (final s in listaSettings)
        if (s.clave == clave) actualizado else s,
    ];

    return actualizado;
  }

  @override
  Future<List<ConfigAuditEntry>> auditoria({int limite = 50}) async {
    llamadas.add('auditoria');
    _lanzarSi(errorAlListarAuditoria);
    return listaAuditoria;
  }

  // --- Utilidades ----------------------------------------------------------

  static void _lanzarSi(Object? error) {
    if (error != null) throw error;
  }

  static AspiranteModel _modeloVacio() => AspiranteModel(
        nombres: '',
        apellidos: '',
        cedula: '',
        sexo: 'M',
        telefono: '',
        email: '',
        direccion: '',
        nivelEducativo: '',
      );
}
