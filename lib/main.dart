import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'providers/role_provider.dart';
import 'screens/admin_dashboard.dart';
import 'screens/aspirante_dashboard.dart';
import 'screens/aspirante_form_screen.dart';
import 'screens/docente_dashboard.dart';
import 'screens/login_screen.dart';
import 'screens/restablecer_password_screen.dart';
import 'services/auth_service.dart';

SupabaseClient get supabase => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(const IncesLmsApp());
}

class IncesLmsApp extends StatelessWidget {
  const IncesLmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoleProvider(),
      child: MaterialApp(
        title: 'INCES LMS - cPanel',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F172A),
            brightness: Brightness.light,
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F172A),
            brightness: Brightness.dark,
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        ),
        themeMode: ThemeMode.system,

        // `home` define la ruta raíz. Por eso NO se incluye '/' en `routes`:
        // Flutter lanza una aserción si ambos existen y la app no arranca.
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/inscripcion': (_) => const AspiranteFormScreen(),
          '/restablecer': (_) => const RestablecerPasswordScreen(),
        },
      ),
    );
  }
}

/// Decide qué mostrar según la sesión y el rol del usuario.
///
/// Escucha `onAuthStateChange`, así que al registrarse o iniciar sesión la
/// pantalla cambia sola: no hace falta navegar manualmente.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<bool>? _authSubscription;
  StreamSubscription<AuthState>? _recuperacionSubscription;
  final AuthService _authService = AuthService();
  bool _isInitializing = true;

  /// `true` mientras el usuario llega desde el enlace del correo de
  /// recuperación. Tiene **prioridad sobre el rol**: hay una sesión válida, pero
  /// es temporal y su único propósito es cambiar la contraseña. Si no se
  /// intercepta, el enrutado por rol lo llevaría al dashboard sin dejarlo
  /// completar el trámite.
  bool _enRecuperacion = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = _authService.cambiosDeSesion.listen(_onSesionCambia);
    _recuperacionSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((estado) {
      if (estado.event == AuthChangeEvent.passwordRecovery) {
        if (mounted) setState(() => _enRecuperacion = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarRol());
  }

  Future<void> _cargarRol() async {
    if (!mounted) return;

    final roleProvider = context.read<RoleProvider>();
    roleProvider.setLoading(true);

    final role = await _authService.obtenerRolActual();

    if (!mounted) return;
    roleProvider.setRole(role);
    roleProvider.setLoading(false);
    setState(() => _isInitializing = false);
  }

  Future<void> _onSesionCambia(bool autenticado) async {
    if (!autenticado) {
      if (!mounted) return;
      context.read<RoleProvider>().reset();
      setState(() => _isInitializing = false);
      return;
    }

    await _cargarRol();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _recuperacionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleProvider = context.watch<RoleProvider>();

    if (_isInitializing || roleProvider.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, color: Color(0xFF2563EB), size: 48),
              SizedBox(height: 16),
              CircularProgressIndicator(color: Color(0xFF2563EB)),
              SizedBox(height: 16),
              Text(
                'Inicializando sesión...',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
      );
    }

    if (!_authService.tieneSesion) {
      return const LoginScreen();
    }

    // La recuperación gana al rol: hay sesión, pero es temporal y sólo sirve
    // para definir la contraseña nueva.
    if (_enRecuperacion) {
      return const RestablecerPasswordScreen();
    }

    switch (roleProvider.role) {
      case UserRole.admin:
        return const AdminDashboardScreen();
      case UserRole.docente:
        return const DocenteDashboardScreen();
      case UserRole.estudiante:
      case UserRole.desconocido:
        return const AspiranteDashboardScreen();
    }
  }
}
