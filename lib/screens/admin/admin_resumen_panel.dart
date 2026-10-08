import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/result.dart';
import '../../models/system_module.dart';
import '../../repositories/modulo_repository.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Panel de resumen ejecutivo del Administrador Maestro.
///
/// Proporciona una vista centralizada de alto nivel sobre la salud operativa
/// del sistema, indicadores en tiempo real, alertas preventivas y accesos directos
/// rápidos a las áreas críticas de gestión académica y técnica.
class AdminResumenPanel extends StatefulWidget {
  const AdminResumenPanel({
    super.key,
    this.onNavegarA,
    this.repositorioModulos,
  });

  /// Permite saltar directamente a una sección del menú lateral.
  final void Function(String tituloSeccion)? onNavegarA;

  /// Inyectable para pruebas unitarias.
  final ModuloRepository? repositorioModulos;

  @override
  State<AdminResumenPanel> createState() => _AdminResumenPanelState();
}

class _AdminResumenPanelState extends State<AdminResumenPanel> {
  late final ModuloRepository _repo =
      widget.repositorioModulos ?? ModuloRepository();

  bool _cargando = true;
  List<SystemModule> _modulos = const [];
  String? _error;

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

    final resultado = await _repo.obtenerModulos();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final lista):
          _modulos = lista;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  int get _modulosActivos => _modulos.where((m) => m.habilitado).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _construirCabeceraEjecutiva(theme, esOscuro),
          const SizedBox(height: 20),
          _construirRejillaMetricas(),
          const SizedBox(height: 24),
          _construirAccionesPrioritarias(theme),
          const SizedBox(height: 24),
          _construirPanelAlertas(theme),
          const SizedBox(height: 20),
          _construirPieInstitucional(theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cabecera ejecutiva
  // ---------------------------------------------------------------------------

  Widget _construirCabeceraEjecutiva(ThemeData theme, bool esOscuro) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: esOscuro
            ? IncesTheme.superficieOscura
            : IncesTheme.superficieClara,
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: IncesTheme.exito,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SISTEMA EN LÍNEA · NODO PRINCIPAL',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: PaletaInces.de(context).exito,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: IncesTheme.azulPrimario.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: IncesTheme.azulPrimario.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  'Período SA26-2',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Centro de Control Maestro',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Monitoreo integral de la infraestructura académica, control de cupos '
            'y auditoría de operaciones del CFS Nacional de Soldadura «Rafael Urdaneta».',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Rejilla de métricas
  // ---------------------------------------------------------------------------

  Widget _construirRejillaMetricas() {
    final modulosTexto = _cargando
        ? '...'
        : '$_modulosActivos / ${_modulos.length}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final columnas = ancho > 1100
            ? 4
            : ancho > 600
                ? 2
                : 1;

        final items = [
          TarjetaMetrica(
            etiqueta: 'Módulos activos',
            valor: modulosTexto,
            icono: Icons.tune_rounded,
            tono: TonoEstado.exito,
          ),
          const TarjetaMetrica(
            etiqueta: 'Período académico',
            valor: 'SA26-2',
            icono: Icons.calendar_today_rounded,
            tono: TonoEstado.info,
          ),
          const TarjetaMetrica(
            etiqueta: 'Seguridad RLS',
            valor: '100% activa',
            icono: Icons.shield_rounded,
            tono: TonoEstado.exito,
          ),
          const TarjetaMetrica(
            etiqueta: 'Almacenamiento R2',
            valor: 'Cloudflare',
            icono: Icons.cloud_done_rounded,
            tono: TonoEstado.info,
          ),
        ];

        if (columnas == 1) {
          return Column(
            children: [
              for (final item in items) ...[
                item,
                const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final item in items)
              SizedBox(
                width: (ancho - (columnas - 1) * 16) / columnas,
                child: item,
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Acciones prioritarias
  // ---------------------------------------------------------------------------

  Widget _construirAccionesPrioritarias(ThemeData theme) {
    final paleta = PaletaInces.deBrillo(theme.brightness);
    final acciones = [
      _AccionRapidaData(
        titulo: 'Inscripciones y Cupos',
        descripcion: 'Supervisar cupos ofertados, inscritos y colas de espera.',
        icono: Icons.confirmation_number_outlined,
        seccionDestino: 'Inscripciones y Cupos',
        colorIcono: IncesTheme.azulPrimario,
      ),
      _AccionRapidaData(
        titulo: 'Cuadrante y Horarios',
        descripcion: 'Consultar rejilla de clases, turnos y uso de aulas.',
        icono: Icons.calendar_month_outlined,
        seccionDestino: 'Cuadrante y Horarios',
        colorIcono: paleta.exito,
      ),
      _AccionRapidaData(
        titulo: 'Usuarios y Roles',
        descripcion: 'Emitir invitaciones seguras para docentes y supervisores.',
        icono: Icons.people_outline,
        seccionDestino: 'Usuarios y Roles',
        colorIcono: paleta.enlace,
      ),
      _AccionRapidaData(
        titulo: 'Auditoría de Accesos',
        descripcion: 'Verificar trazas de inicio de sesión e intentos denegados.',
        icono: Icons.fingerprint_outlined,
        seccionDestino: 'Auditoría de Accesos',
        colorIcono: paleta.advertencia,
      ),
      _AccionRapidaData(
        titulo: 'Módulos del Sistema',
        descripcion: 'Conmutar banderas de mantenimiento e itinerarios activos.',
        icono: Icons.tune_outlined,
        seccionDestino: 'Módulos del Sistema',
        colorIcono: IncesTheme.azulSecundario,
      ),
      _AccionRapidaData(
        titulo: 'Parámetros Globales',
        descripcion: 'Ajustar configuraciones institucionales y límites.',
        icono: Icons.settings_outlined,
        seccionDestino: 'Parámetros',
        colorIcono: paleta.neutro,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Acciones Prioritarias',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Accesos directos',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            final columnas = ancho > 1000
                ? 3
                : ancho > 640
                    ? 2
                    : 1;

            if (columnas == 1) {
              return Column(
                children: [
                  for (final item in acciones) ...[
                    _construirTarjetaAccion(item, theme),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final item in acciones)
                  SizedBox(
                    width: (ancho - (columnas - 1) * 16) / columnas,
                    child: _construirTarjetaAccion(item, theme),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _construirTarjetaAccion(_AccionRapidaData data, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: () => widget.onNavegarA?.call(data.seccionDestino),
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: data.colorIcono.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(IncesTheme.radioControl),
                ),
                child: Icon(data.icono, color: data.colorIcono, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.titulo,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.descripcion,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Panel de alertas operativas
  // ---------------------------------------------------------------------------

  Widget _construirPanelAlertas(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: IncesTheme.azulPrimario.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        border: Border.all(
          color: IncesTheme.azulPrimario.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: IncesTheme.azulPrimario,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gobernanza y Reglas de Negocio Activas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: IncesTheme.azulPrimario,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El motor de asignación de cupos mantiene la protección estricta contra '
                  'sobreventa. Las políticas RLS protegen la persistencia de asistencia '
                  'y calificaciones con segregación de roles certificada.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pie institucional
  // ---------------------------------------------------------------------------

  Widget _construirPieInstitucional(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'CFS Nacional de Soldadura «Rafael Urdaneta» · INCES La Isabelica · v0.1.0',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _AccionRapidaData {
  const _AccionRapidaData({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.seccionDestino,
    required this.colorIcono,
  });

  final String titulo;
  final String descripcion;
  final IconData icono;
  final String seccionDestino;
  final Color colorIcono;
}
