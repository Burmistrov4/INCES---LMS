import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/navegacion.dart';
import 'providers/role_provider.dart';
import 'screens/admin_dashboard.dart';
import 'screens/aspirante_dashboard.dart';
import 'screens/aspirante_form_screen.dart';
import 'screens/docente_dashboard.dart';
import 'screens/login_screen.dart';
import 'screens/restablecer_password_screen.dart';
import 'screens/activar_cuenta_screen.dart';
import 'services/auth_service.dart';
import 'theme/inces_theme.dart';

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

/// Pantallas alcanzables por nombre de ruta, indexadas por **camino**.
///
/// La activación de docentes no está aquí a propósito: necesita el token del
/// enlace, y los constructores de esta tabla sólo reciben el `BuildContext`.
/// Se resuelve aparte en [_generarRuta].
final Map<String, WidgetBuilder> _pantallas = {
  '/login': (_) => const LoginScreen(),
  '/inscripcion': (_) => const AspiranteFormScreen(),
  '/restablecer': (_) => const RestablecerPasswordScreen(),
};

/// Resuelve una ruta a partir de su nombre.
///
/// Existe porque la tabla `routes` compara cadenas **exactas**: un enlace
/// profundo llega con la consulta pegada (`/auth/activate?token=…`) y no
/// encuentra destino. Cuando eso pasaba, el `Navigator` descartaba la pila
/// inicial entera y mostraba `/`, así que el docente abría el enlace del correo
/// y aterrizaba en el login: el token nunca llegaba a la pantalla.
///
/// Devuelve `null` para las rutas desconocidas **a propósito**. Al expandir un
/// enlace de varios segmentos, `Navigator` pide `/`, `/auth` y
/// `/auth/activate`; los intermedios que no existen deben quedarse en `null`
/// para que se filtren en vez de ensuciar el historial.
Route<dynamic>? _generarRuta(RouteSettings ajustes) {
  final destino = analizarRuta(ajustes.name);

  if (destino.ruta == rutaActivacion) {
    return MaterialPageRoute<dynamic>(
      settings: ajustes,
      builder: (_) => ActivarCuentaScreen(token: destino.token),
    );
  }

  final pantalla = _pantallas[destino.ruta];
  if (pantalla == null) return null;

  return MaterialPageRoute<dynamic>(settings: ajustes, builder: pantalla);
}

class IncesLmsApp extends StatelessWidget {
  const IncesLmsApp({super.key, this.rutaInicial});

  /// Ruta con la que arranca la aplicación.
  ///
  /// En web la fija la URL del navegador, así que la app real no pasa nada. Se
  /// expone para poder abrir la aplicación en un enlace profundo concreto desde
  /// las pruebas, que no tienen navegador.
  final String? rutaInicial;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoleProvider(),
      child: MaterialApp(
        title: 'INCES LMS — Sistema de Gestión Académica',
        debugShowCheckedModeBanner: false,

        // El tema se delega en `IncesTheme`. Tenerlo centralizado es lo que
        // impide que cada pantalla vuelva a inventarse sus propios colores, que
        // es exactamente lo que pasó antes: el login era `#0F172A` y los paneles
        // también, pero con azules distintos, y la aplicación no se leía como un
        // solo producto.
        theme: IncesTheme.claro(),
        darkTheme: IncesTheme.oscuro(),
        themeMode: ThemeMode.system,

        // `home` define la ruta raíz. Por eso NO se incluye '/' en `routes`:
        // Flutter lanza una aserción si ambos existen y la app no arranca.
        home: const AuthGate(),
        initialRoute: rutaInicial,

        // Las rutas simples se resuelven por tabla exacta. El deep link del
        // docente invitado (`/auth/activate?token=…`) pasa por `_generarRuta`,
        // que sí sabe leer la consulta. Al abrirse por URL, esa pantalla queda
        // encima del `AuthGate`: el docente todavía no tiene sesión, y el botón
        // de volver tiene un destino sensato.
        routes: _pantallas,
        onGenerateRoute: _generarRuta,
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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: IncesTheme.degradadoAzul,
                  borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
                ),
                child: const Text(
                  'I',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Inicializando sesión…',
                style: Theme.of(context).textTheme.bodySmall,
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
