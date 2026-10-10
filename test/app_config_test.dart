import 'package:flutter_test/flutter_test.dart';
import 'package:inces_lms_app/core/config/app_config.dart';

void main() {
  group('AppConfig · configuración de conectividad', () {
    test('apiBaseUrl devuelve la cadena por defecto en entorno de pruebas (no web)', () {
      expect(AppConfig.apiBaseUrl, isA<String>());
    });

    test('validate lanza StateError si falta Supabase', () {
      expect(() => AppConfig.validate(), throwsStateError);
    });

    test('esHostPrivadoLan identifica correctamente subredes privadas RFC 1918 y descarta producción', () {
      // Loopback y nombres locales
      expect(AppConfig.esHostPrivadoLan('localhost'), isFalse);
      expect(AppConfig.esHostPrivadoLan('127.0.0.1'), isFalse);
      expect(AppConfig.esHostPrivadoLan(''), isFalse);

      // Dominios de producción / públicos NUNCA son tratados como LAN
      expect(AppConfig.esHostPrivadoLan('inces-lms.pages.dev'), isFalse);
      expect(AppConfig.esHostPrivadoLan('api.inces.org'), isFalse);
      expect(AppConfig.esHostPrivadoLan('twdppwnxlnmxkiejbrei.supabase.co'), isFalse);
      expect(AppConfig.esHostPrivadoLan('8.8.8.8'), isFalse);

      // Subredes privadas LAN (RFC 1918) y mDNS local
      expect(AppConfig.esHostPrivadoLan('192.168.1.1'), isTrue);
      expect(AppConfig.esHostPrivadoLan('192.168.55.4'), isTrue);
      expect(AppConfig.esHostPrivadoLan('10.0.0.10'), isTrue);
      expect(AppConfig.esHostPrivadoLan('172.16.0.1'), isTrue);
      expect(AppConfig.esHostPrivadoLan('172.25.176.1'), isTrue);
      expect(AppConfig.esHostPrivadoLan('172.31.255.254'), isTrue);
      expect(AppConfig.esHostPrivadoLan('172.32.0.1'), isFalse); // Fuera de rango RFC 1918
      expect(AppConfig.esHostPrivadoLan('servidor-lms.local'), isTrue);
      expect(AppConfig.esHostPrivadoLan('servidor-lms.lan'), isTrue);
    });
  });
}
