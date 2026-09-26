import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/inscripcion_campo.dart';
import '../repositories/aspirante_repository.dart';
import '../theme/inces_theme.dart';

/// Página pública de aterrizaje: la raíz `/` cuando **no** hay sesión.
///
/// Es la cara institucional del sistema. Antes, quien abría la aplicación sin
/// sesión caía de golpe en el login; ahora ve la identidad del centro, la oferta
/// formativa real (Módulo 2) y dos caminos: inscribirse o entrar al portal
/// académico.
///
/// **No es una ruta propia.** La muestra [AuthGate] como su hijo cuando no hay
/// sesión. Registrar además `'/'` en `routes` rompería el arranque: `MaterialApp`
/// lanza una aserción si `home` y `routes['/']` coexisten.
///
/// La oferta se lee de `AspiranteRepository.obtenerProgramasDisponibles()`, que
/// va por PostgREST **anónimo** (la RLS deja ver los programas activos), así que
/// no hace falta sesión para pintarla.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key, this.aspiranteRepository});

  /// Inyectable para las pruebas. En producción se resuelve solo.
  ///
  /// Sin esto, montar la Landing en una prueba dispararía una consulta real a
  /// Supabase en `initState`, y ninguna prueba podría montarla sin red.
  final AspiranteRepository? aspiranteRepository;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  late final AspiranteRepository _aspiranteRepo;

  bool _cargando = true;

  /// La oferta formativa: `valor` = uuid del programa, `etiqueta` = su nombre.
  List<OpcionCampo> _cursos = const [];

  /// Por qué no hay cursos que mostrar, si no los hay. `null` cuando sí hay.
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _aspiranteRepo = widget.aspiranteRepository ?? AspiranteRepository();
    _cargarOferta();
  }

  Future<void> _cargarOferta() async {
    setState(() {
      _cargando = true;
      _aviso = null;
    });

    final resultado = await _aspiranteRepo.obtenerProgramasDisponibles();
    if (!mounted) return;

    setState(() {
      final cursos = resultado.valueOrNull;
      if (cursos != null && cursos.isNotEmpty) {
        _cursos = cursos;
        _aviso = null;
      } else {
        // Un fallo de red y un catálogo vacío se ven igual —sin tarjetas—, y
        // sólo el `Result` los distingue. El mensaje dice cuál de los dos pasó,
        // en vez de degradar los dos al mismo «no hay cursos».
        _cursos = const [];
        _aviso = cursos == null
            ? 'No pudimos cargar la oferta formativa. Revisa tu conexión e '
                'inténtalo de nuevo.'
            : 'Todavía no hay cursos abiertos a inscripción. Vuelve pronto.';
      }
      _cargando = false;
    });
  }

  void _irAInscripcion() {
    Navigator.of(context).pushNamed('/inscripcion');
  }

  void _irAlPortalAcademico() {
    Navigator.of(context).pushNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _construirHero(),
            _construirOferta(),
            _construirPie(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hero institucional
  // ---------------------------------------------------------------------------

  Widget _construirHero() {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: IncesTheme.degradadoAzul),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _construirMarca(),
                const SizedBox(height: 32),
                Text(
                  'Sistema de Gestión\nAcadémica',
                  style: GoogleFonts.inter(
                    fontSize: 40,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 18),
                // Acento rojo institucional: la misma franja que ya usa el
                // panel de marca del login, para que la Landing y el acceso se
                // lean como el mismo producto.
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: IncesTheme.rojoInces,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'CFS Nacional de Soldadura\n«Rafael Urdaneta»',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'INCES La Isabelica',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 36),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _irAInscripcion,
                      icon: const Icon(Icons.assignment_outlined, size: 18),
                      label: const Text('Inscribirse'),
                      // Sobre el degradado azul, el botón primario del tema
                      // (azul) se perdería. Se invierte: blanco con texto azul.
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: IncesTheme.azulPrimario,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _irAlPortalAcademico,
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Portal Académico'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirMarca() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          ),
          child: Text(
            'I',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'INCES LMS',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Oferta formativa (dinámica)
  // ---------------------------------------------------------------------------

  Widget _construirOferta() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Oferta formativa', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Cursos abiertos a inscripción en el centro.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _construirEstadoOferta(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirEstadoOferta() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final aviso = _aviso;
    if (aviso != null) return _construirAviso(aviso);

    return _construirRejilla();
  }

  Widget _construirAviso(String mensaje) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensaje,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: _cargarOferta,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _construirRejilla() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const separacion = 16.0;
        // El número de columnas sale del ancho disponible, no de un valor fijo:
        // así la rejilla no desborda en móvil ni deja tarjetas diminutas en
        // escritorio. El techo es 3 para que la tarjeta no se estire sin fin.
        final columnas = (constraints.maxWidth / 300).floor().clamp(1, 3);
        final ancho =
            (constraints.maxWidth - separacion * (columnas - 1)) / columnas;
        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [
            for (final curso in _cursos)
              SizedBox(
                width: ancho,
                child: _TarjetaCurso(
                  curso: curso,
                  onInscribir: _irAInscripcion,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _construirPie() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          'INCES · CFS Nacional de Soldadura «Rafael Urdaneta» · La Isabelica',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de un curso de la oferta formativa.
///
/// Muestra sólo el **nombre** del programa: es lo único que expone
/// `programasDisponibles()` (`id` + `name`). Enriquecerla con código o duración
/// exigiría otra lectura del Módulo 2, que es trabajo aparte.
class _TarjetaCurso extends StatelessWidget {
  const _TarjetaCurso({required this.curso, required this.onInscribir});

  final OpcionCampo curso;
  final VoidCallback onInscribir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(IncesTheme.radioControl),
              ),
              child: Icon(
                Icons.handyman_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(curso.etiqueta, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Curso de formación continua',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onInscribir,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Inscribirme'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
