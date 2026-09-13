import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';

/// Cliente HTTP del backend stateless (Fastify).
///
/// El frontend Flutter habla directo con Supabase para lo del día a día, pero las
/// operaciones que exigen privilegios de servicio —crear un docente por
/// invitación, promover roles— pasan por este backend, que sí tiene la llave
/// `service_role`. La app sólo manda el JWT de sesión del usuario; el backend
/// valida el rol admin.
///
/// El backend responde siempre `{ error: { codigo, mensaje, detalles? } }` en
/// fallo, y el `mensaje` ya viene en español, así que se reenvía tal cual.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _http;
  final String _baseUrl;

  Future<Map<String, dynamic>> post(
    String ruta, {
    Map<String, dynamic>? cuerpo,
    String? token,
    Map<String, String>? encabezadosExtra,
  }) async {
    final respuesta = await _http.post(
      _resolver(ruta),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...?encabezadosExtra,
      },
      body: cuerpo == null ? null : jsonEncode(cuerpo),
    );

    return _procesar(respuesta, ruta);
  }

  /// Lectura (GET) con parámetros de consulta opcionales.
  ///
  /// Los parámetros vacíos se descartan: así el panel de auditoría puede mandar
  /// sus filtros sin uso como cadena vacía en vez de ensuciar la URL con
  /// `estado=&email=`, que el backend rechazaría con un 400 por cadena vacía.
  Future<Map<String, dynamic>> get(
    String ruta, {
    String? token,
    Map<String, String>? parametros,
    Map<String, String>? encabezadosExtra,
  }) async {
    final respuesta = await _http.get(
      _resolver(ruta, parametros),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        ...?encabezadosExtra,
      },
    );

    return _procesar(respuesta, ruta);
  }

  /// Construye la URL completa y comprueba que hay base configurada.
  Uri _resolver(String ruta, [Map<String, String>? parametros]) {
    final base = _baseUrl.trim();
    if (base.isEmpty) {
      // No es un fallo de red: es configuración ausente. El mensaje dice qué
      // falta en vez de simular un error de conexión que confundiría al admin.
      throw const AppException(
        type: AppErrorType.servidor,
        message:
            'Falta la configuración del servidor (API_BASE_URL). No se puede '
            'contactar al backend.',
      );
    }

    final limpios = <String, String>{
      for (final entrada in (parametros ?? const <String, String>{}).entries)
        if (entrada.value.trim().isNotEmpty) entrada.key: entrada.value.trim(),
    };

    return Uri.parse('$base$ruta').replace(
      queryParameters: limpios.isEmpty ? null : limpios,
    );
  }

  Map<String, dynamic> _procesar(http.Response respuesta, String ruta) {
    final texto = respuesta.body;
    final cuerpo = texto.isNotEmpty
        ? (jsonDecode(texto) as Map<String, dynamic>)
        : <String, dynamic>{};

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return cuerpo;
    }

    final error = cuerpo['error'] as Map<String, dynamic>?;
    final mensaje = error?['mensaje'] as String? ??
        'Ocurrió un error inesperado. Inténtalo de nuevo.';
    final codigo = error?['codigo'] as String?;

    throw AppException(
      type: _clasificar(respuesta.statusCode),
      message: mensaje,
      code: codigo,
      technical: 'HTTP ${respuesta.statusCode} en $ruta',
    );
  }

  /// Traduce el código HTTP a un tipo de error del dominio.
  ///
  /// 401/403 son de permisos (la UI entonces sugiere iniciar sesión); 410
  /// (caducado) y 409 (ya usada) son del dominio y se muestran con el mensaje
  /// del servidor; el resto es error de servidor.
  AppErrorType _clasificar(int status) {
    switch (status) {
      case 400:
      case 409:
      case 410:
      case 422:
        return AppErrorType.validacion;
      case 401:
      case 403:
        return AppErrorType.permisos;
      default:
        return AppErrorType.servidor;
    }
  }
}
