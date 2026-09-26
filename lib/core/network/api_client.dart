import 'dart:convert';
import 'dart:typed_data';

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
        // Sólo se declara JSON si hay cuerpo. Un POST sin cuerpo con
        // `Content-Type: application/json` dispara en Fastify
        // `FST_ERR_CTP_EMPTY_JSON_BODY` (500), y es la trampa de las rutas
        // sin body del Módulo 4 (renunciar, aceptar, promover, expirar).
        if (cuerpo != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...?encabezadosExtra,
      },
      body: cuerpo == null ? null : jsonEncode(cuerpo),
    );

    return _procesar(respuesta, ruta);
  }

  /// Actualización parcial (PATCH) de un recurso.
  ///
  /// El backend trata el `PATCH` como un parche de verdad: sólo se envían los
  /// campos que cambian. Mandar el objeto entero convertiría cualquier campo
  /// ausente en un intento de escribir `null`, que el esquema `.strict()`
  /// rechazaría con un 400.
  Future<Map<String, dynamic>> patch(
    String ruta, {
    Map<String, dynamic>? cuerpo,
    String? token,
    Map<String, String>? encabezadosExtra,
  }) async {
    final respuesta = await _http.patch(
      _resolver(ruta),
      headers: {
        if (cuerpo != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...?encabezadosExtra,
      },
      body: cuerpo == null ? null : jsonEncode(cuerpo),
    );

    return _procesar(respuesta, ruta);
  }

  /// Reemplazo (PUT) de un recurso o de una de sus facetas.
  ///
  /// Existe por `PUT /admin/periodos/:id/vigente`, que **declara** un lapso como
  /// el vigente. No es un `PATCH`: la operación no edita un campo del lapso —eso
  /// sería mover `is_active`— sino que reemplaza un único valor del sistema
  /// (`system_settings.periodo_activo`). Usar `PATCH` habría sugerido que el
  /// vigente es una propiedad del lapso, y no lo es: es del centro.
  Future<Map<String, dynamic>> put(
    String ruta, {
    Map<String, dynamic>? cuerpo,
    String? token,
    Map<String, String>? encabezadosExtra,
  }) async {
    final respuesta = await _http.put(
      _resolver(ruta),
      headers: {
        if (cuerpo != null) 'Content-Type': 'application/json',
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

  /// Lectura binaria (GET) que devuelve los bytes en crudo.
  ///
  /// Sirve para descargar archivos —el PDF de la planilla de inscripción— cuyo
  /// cuerpo **no** es JSON. El `http.Response` trae los bytes en `bodyBytes`; si
  /// se usara [get] normal, `_procesar` intentaría `jsonDecode` sobre un PDF y
  /// fallaría. Por eso este método no pasa por `_procesar`: comprueba el rango
  /// 2xx y, si no, reconstruye el `AppException` a mano a partir del envoltorio
  /// de error que sí viaja en JSON.
  ///
  /// **El error sí viene como JSON.** El backend responde `application/pdf` en
  /// el éxito y `application/json` con `{ error: { codigo, mensaje } }` en el
  /// fallo, así que en la rama no-2xx se decodifica el cuerpo para rescatar el
  /// `mensaje` ya en español en vez de inventar uno.
  Future<Uint8List> getBytes(
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

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return respuesta.bodyBytes;
    }

    // Misma lógica de [_procesar] pero sin exigir JSON: el éxito ya salió por la
    // rama anterior, así que aquí sólo queda el fallo, y hay que extraer el
    // `mensaje`/`codigo` del envoltorio si el cuerpo es JSON válido.
    String mensaje = 'Ocurrió un error inesperado. Inténtalo de nuevo.';
    String? codigo;
    final texto = respuesta.body;
    if (texto.isNotEmpty) {
      try {
        final cuerpo = jsonDecode(texto);
        if (cuerpo is Map<String, dynamic>) {
          final error = cuerpo['error'];
          if (error is Map<String, dynamic>) {
            mensaje = (error['mensaje'] as String?) ?? mensaje;
            codigo = error['codigo'] as String?;
          }
        }
      } catch (_) {
        // Cuerpo no JSON (p.ej. un 503 de HTML): se queda con el mensaje
        // genérico. No se propaga: el llamador espera un `AppException`.
      }
    }

    throw AppException(
      type: _clasificar(respuesta.statusCode, codigo),
      message: mensaje,
      code: codigo,
      technical: 'HTTP ${respuesta.statusCode} en $ruta',
    );
  }

  /// Borrado (DELETE) de un recurso.
  ///
  /// Existe por M5, que es el primer módulo con borrado real: en M2 y M4 archivar
  /// es un `PATCH` (`activa: false`) y no hay DELETE. El borrado de archivos es
  /// **lógico** en la base —la fila se conserva como historial—, así que el
  /// servidor responde con el archivo ya en `DELETED` y aquí no hay que tratar
  /// un 204 sin cuerpo.
  Future<Map<String, dynamic>> delete(
    String ruta, {
    String? token,
    Map<String, String>? encabezadosExtra,
  }) async {
    final respuesta = await _http.delete(
      _resolver(ruta),
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
      type: _clasificar(respuesta.statusCode, codigo),
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
  ///
  /// **413 va con la validación, no con el servidor.** Un archivo que se pasa del
  /// límite es una condición que el usuario puede corregir —subir otro más
  /// pequeño—, no un fallo del sistema. Sin este caso caía en `default` y la UI
  /// habría mostrado «Ocurrió un error en el servidor», que manda a nadie a
  /// arreglar nada. Lo destapó M5, que es el primer módulo que puede devolverlo.
  AppErrorType _clasificar(int status, String? codigo) {
    // `codigo` no es cosmético. El backend traduce «falta aplicar una migración»
    // a `ESQUEMA_DESACTUALIZADO`, pero lo hace con HTTP **500**, y un 500 a
    // secas cae en `servidor` —que es recuperable—: sin esta comprobación la
    // traducción cuidadosa del backend se perdía justo aquí y la UI volvía a
    // ofrecer «Reintentar» para algo que no puede funcionar. Es la lección de
    // «un valor por defecto puede anularse desde arriba», una capa más arriba.
    if (codigo == 'ESQUEMA_DESACTUALIZADO') {
      return AppErrorType.esquemaDesactualizado;
    }

    switch (status) {
      case 400:
      case 409:
      case 410:
      case 413:
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
