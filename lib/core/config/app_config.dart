class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

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
