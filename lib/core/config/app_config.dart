import 'package:flutter/foundation.dart';

class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _rawApiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// URL base de la API Fastify.
  ///
  /// Si se ejecuta en navegador Web (`kIsWeb`) y la app fue abierta desde
  /// una dirección de red privada LAN (RFC 1918: 192.168.x.x, 10.x.x.x, 172.16-31.x.x),
  /// y la variable de compilación apunta a localhost o está vacía, se resuelve
  /// dinámicamente al host de la LAN en el puerto 3001.
  ///
  /// En dominios de producción (p. ej. Cloudflare Pages o dominios públicos),
  /// localhost, o compilaciones con URL explícita no-localhost, respeta
  /// la configuración configurada sin alteraciones.
  static String get apiBaseUrl {
    final configurada = _rawApiBaseUrl.trim();
    if (!kIsWeb) return configurada;

    final uriActual = Uri.base;
    final hostActual = uriActual.host.trim();

    // Cloudflare Pages no recibe automáticamente --dart-define desde sus
    // variables de entorno. Si API_BASE_URL no se inyectó en el bundle público,
    // usa la API de producción conocida; una definición explícita siempre gana.
    if (configurada.isEmpty && hostActual.endsWith('.pages.dev')) {
      return 'https://inces-lms-api.onrender.com';
    }

    if (esHostPrivadoLan(hostActual)) {
      if (configurada.isEmpty || configurada.contains('localhost') || configurada.contains('127.0.0.1')) {
        final esquema = uriActual.scheme.isNotEmpty ? uriActual.scheme : 'http';
        return '$esquema://$hostActual:3001';
      }
    }
    return configurada;
  }

  /// Comprueba si un host corresponde a una subred privada local (LAN / RFC 1918).
  @visibleForTesting
  static bool esHostPrivadoLan(String host) {
    if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') return false;
    if (host.endsWith('.local') || host.endsWith('.lan')) return true;
    final partes = host.split('.');
    if (partes.length == 4) {
      final p0 = int.tryParse(partes[0]);
      final p1 = int.tryParse(partes[1]);
      if (p0 != null && p1 != null) {
        if (p0 == 10) return true;
        if (p0 == 192 && p1 == 168) return true;
        if (p0 == 172 && p1 >= 16 && p1 <= 31) return true;
      }
    }
    return false;
  }

  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError(
        'Falta SUPABASE_URL. Ejecuta la app con --dart-define=SUPABASE_URL=...',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      throw StateError(
        'Falta SUPABASE_ANON_KEY. Ejecuta la app con --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  }
}
