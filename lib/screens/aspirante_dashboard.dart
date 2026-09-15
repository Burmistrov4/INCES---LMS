import 'package:flutter/material.dart';

import '../core/result.dart';
import '../models/aspirante_model.dart';
import '../repositories/aspirante_repository.dart';
import '../services/auth_service.dart';
import '../theme/inces_theme.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';

/// Panel del aspirante y del estudiante.
///
/// Sigue usando [AspiranteRepository], que devuelve `Result`. Un fallo de red se
/// muestra como error con reintento, **nunca** como "no tienes ficha": ése era
/// el bug que ocultaba datos, y es la razón de que los tres estados (cargando,
/// error, vacío) estén separados aquí.
class AspiranteDashboardScreen extends StatefulWidget {
  const AspiranteDashboardScreen({super.key, this.repositorio, this.auth});

  final AspiranteRepository? repositorio;
  final AuthService? auth;

  @override
  State<AspiranteDashboardScreen> createState() =>
      _AspiranteDashboardScreenState();
}

class _AspiranteDashboardScreenState extends State<AspiranteDashboardScreen> {
  late final AspiranteRepository _repo =
      widget.repositorio ?? AspiranteRepository();
  late final AuthService _auth = widget.auth ?? AuthService();

  bool _cargando = true;
  AspiranteModel? _aspirante;
  String? _error;

  int _seleccionada = 0;

  static const List<ItemNavegacion> _items = [
    ItemNavegacion(
      icono: Icons.badge_outlined,
      titulo: 'Mi inscripción',
      categoria: 'Mi cuenta',
    ),
    ItemNavegacion(
      icono: Icons.class_outlined,
      titulo: 'Mis aulas',
      categoria: 'Académico',
      disponible: false,
    ),
    ItemNavegacion(
      icono: Icons.folder_open_outlined,
      titulo: 'Material de apoyo',
      categoria: 'Académico',
      disponible: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final resultado = await _repo.obtenerMiFicha();

    // El estado de carga se libera antes del `return` por desmontaje: al revés,
    // un desmontaje durante la petición dejaría el indicador girando para
    // siempre en la siguiente visita a esta pantalla.
    if (mounted) setState(() => _cargando = false);
    if (!mounted) return;

    setState(() {
      switch (resultado) {
        case Success(value: final ficha):
          _aspirante = ficha;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _cerrarSesion() async {
    await _auth.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return AndamiajeApp(
      items: _items,
      seleccionado: _seleccionada,
      onSeleccionar: (indice) => setState(() => _seleccionada = indice),
      rolEtiqueta: 'Estudiante',
      correoUsuario: _auth.emailActual,
      periodoActivo: 'SA26-2',
      onCerrarSesion: _cerrarSesion,
      contenido: _contenido(),
    );
  }

  Widget _contenido() {
    if (_seleccionada != 0) {
      final item = _items[_seleccionada];
      return ContenidoSeccion(
        migas: ['Inicio', item.categoria, item.titulo],
        child: PanelVacio(
          titulo: item.titulo,
          mensaje: 'Esta sección se habilitará cuando tu curso esté activo.',
          icono: item.icono,
        ),
      );
    }

    return ContenidoSeccion(
      migas: const ['Inicio', 'Mi cuenta', 'Mi inscripción'],
      child: _cargando
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
              ? _panelError(_error!)
              : _aspirante == null
                  ? _panelVacio()
                  : _panelFicha(_aspirante!),
    );
  }

  Widget _panelError(String mensaje) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 30,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No pudimos cargar tu ficha',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelVacio() {
    return const PanelVacio(
      titulo: 'Tu inscripción está en revisión',
      mensaje:
          'Cuando el centro formativo apruebe tu solicitud verás aquí tu curso '
          'y tu estado.',
      icono: Icons.pending_actions_outlined,
      nota:
          'Recibirás un correo cuando tu inscripción sea confirmada. Si no '
          'llega, revisa la carpeta de spam: el envío depende del dominio de '
          'correo configurado por el centro.',
    );
  }

  Widget _panelFicha(AspiranteModel aspirante) {
    final theme = Theme.of(context);

    final curso = aspirante.cursoSeleccionado.isEmpty
        ? 'Por asignar'
        : aspirante.cursoSeleccionado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tarjeta de identidad con la cabecera de marca. Es la versión de
        // «perfil» del lenguaje visual que usan las tarjetas de módulo.
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 6,
                decoration: const BoxDecoration(
                  gradient: IncesTheme.degradadoMarca,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      child: Text(
                        _iniciales(aspirante),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${aspirante.nombres} ${aspirante.apellidos}'
                                .trim(),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: IncesTheme.advertencia
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'En revisión',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: IncesTheme.advertencia,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TituloSeccion('Datos de la solicitud'),
                _FilaDato(etiqueta: 'Cédula', valor: aspirante.cedula),
                _FilaDato(etiqueta: 'Nombres', valor: aspirante.nombres),
                _FilaDato(etiqueta: 'Apellidos', valor: aspirante.apellidos),
                _FilaDato(
                  etiqueta: 'Curso solicitado',
                  valor: curso,
                  esUltima: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Iniciales para el avatar. Si no hay nombre, cae a un icono genérico.
  static String _iniciales(AspiranteModel aspirante) {
    final nombre = aspirante.nombres.trim();
    final apellido = aspirante.apellidos.trim();

    final a = nombre.isEmpty ? '' : nombre[0];
    final b = apellido.isEmpty ? '' : apellido[0];

    final combinadas = '$a$b'.toUpperCase();
    return combinadas.isEmpty ? '?' : combinadas;
  }
}

/// Fila de dato etiqueta/valor.
class _FilaDato extends StatelessWidget {
  const _FilaDato({
    required this.etiqueta,
    required this.valor,
    this.esUltima = false,
  });

  final String etiqueta;
  final String valor;
  final bool esUltima;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ancho mínimo de la etiqueta: sin él, «Cédula» y «Curso
              // solicitado» dejan los valores desalineados entre filas y la
              // lectura en columna se pierde.
              SizedBox(
                width: 150,
                child: Text(
                  etiqueta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  valor.isEmpty ? '—' : valor,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (!esUltima) const Divider(height: 1),
      ],
    );
  }
}
