import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/aspirante_model.dart';
import '../../theme/inces_theme.dart';
import '../../widgets/comunes.dart';

/// Panel de resumen académico del Aprendiz / Estudiante.
///
/// Presenta una visión integral de su estado formativo: programa asignado,
/// acceso instantáneo para marcar asistencia en clase mediante QR o código
/// numérico, acceso a aulas virtuales, gestor de entregas y avisos del centro.
class EstudianteResumenPanel extends StatelessWidget {
  const EstudianteResumenPanel({
    super.key,
    this.aspirante,
    this.onNavegarA,
  });

  /// Ficha del estudiante con sus datos de matrícula.
  final AspiranteModel? aspirante;

  /// Permite saltar a una pestaña del dashboard de estudiante.
  final void Function(String tituloSeccion)? onNavegarA;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;

    final nombre = aspirante?.nombres.trim().isNotEmpty == true
        ? aspirante!.nombres.trim()
        : 'Aprendiz';

    final programa = aspirante?.programaNombre?.trim().isNotEmpty == true
        ? aspirante!.programaNombre!.trim()
        : 'Programa Técnico en Asignación';

    final cedula = aspirante != null && aspirante!.cedula.isNotEmpty
        ? 'C.I. ${aspirante!.cedula}'
        : 'Ficha activa';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _construirCabecera(theme, esOscuro, nombre, programa, cedula),
          const SizedBox(height: 20),
          _construirMetricas(programa),
          const SizedBox(height: 24),
          _construirAccionesPrioritarias(theme),
          const SizedBox(height: 24),
          _construirAvisosAcademicos(theme),
          const SizedBox(height: 20),
          _construirPie(theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Cabecera
  // ---------------------------------------------------------------------------

  Widget _construirCabecera(
    ThemeData theme,
    bool esOscuro,
    String nombre,
    String programa,
    String cedula,
  ) {
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
                'ESTUDIANTE REGULAR · $cedula',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: IncesTheme.exito,
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
            '¡Bienvenido, $nombre!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Especialidad: $programa · CFS Nacional de Soldadura «Rafael Urdaneta».',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Métricas
  // ---------------------------------------------------------------------------

  Widget _construirMetricas(String programa) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final columnas = ancho > 1000
            ? 3
            : ancho > 600
                ? 2
                : 1;

        final items = [
          TarjetaMetrica(
            etiqueta: 'Programa técnico',
            valor: programa.length > 20 ? '${programa.substring(0, 18)}...' : programa,
            icono: Icons.school_rounded,
            tono: TonoEstado.info,
          ),
          const TarjetaMetrica(
            etiqueta: 'Asistencia en aula',
            valor: 'Control activo',
            icono: Icons.fact_check_rounded,
            tono: TonoEstado.exito,
          ),
          const TarjetaMetrica(
            etiqueta: 'Aula Virtual M6',
            valor: 'Activa',
            icono: Icons.devices_rounded,
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
      _EstudianteAccionData(
        titulo: 'Marcar Asistencia a Clase',
        descripcion: 'Ingresar el código de 6 dígitos de la pizarra o escanear el QR proyectado.',
        icono: Icons.fact_check_outlined,
        seccionDestino: 'Asistencia',
        color: IncesTheme.azulPrimario,
      ),
      _EstudianteAccionData(
        titulo: 'Mis Aulas Virtuales',
        descripcion: 'Consultar el tablón de anuncios, clases teóricas y tareas del docente.',
        icono: Icons.class_outlined,
        seccionDestino: 'Mis aulas',
        color: paleta.exito,
      ),
      _EstudianteAccionData(
        titulo: 'Mis Entregas y Tareas',
        descripcion: 'Gestionar y subir archivos de entrega con almacenamiento seguro en la nube.',
        icono: Icons.assignment_turned_in_outlined,
        seccionDestino: 'Mis entregas',
        color: paleta.enlace,
      ),
      _EstudianteAccionData(
        titulo: 'Mi Ficha de Inscripción',
        descripcion: 'Verificar los datos de registro y descargar la planilla oficial institucional.',
        icono: Icons.badge_outlined,
        seccionDestino: 'Mi inscripción',
        color: paleta.advertencia,
      ),
      _EstudianteAccionData(
        titulo: 'Ofertas de Cupos',
        descripcion: 'Explorar las secciones académicas abiertas e inscribirse en nuevos cursos.',
        icono: Icons.explore_outlined,
        seccionDestino: 'Ofertas de cupos',
        color: IncesTheme.azulSecundario,
      ),
      _EstudianteAccionData(
        titulo: 'Mi Perfil de Usuario',
        descripcion: 'Actualizar nombres y verificar credenciales de acceso al sistema.',
        icono: Icons.account_circle_outlined,
        seccionDestino: 'Mi Perfil',
        color: paleta.neutro,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Herramientas del Aprendiz',
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

  Widget _construirTarjetaAccion(_EstudianteAccionData data, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IncesTheme.radioTarjeta),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: () => onNavegarA?.call(data.seccionDestino),
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
                  color: data.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(IncesTheme.radioControl),
                ),
                child: Icon(data.icono, color: data.color, size: 22),
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
  // Avisos académicos
  // ---------------------------------------------------------------------------

  Widget _construirAvisosAcademicos(ThemeData theme) {
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
            Icons.info_outline_rounded,
            color: IncesTheme.azulPrimario,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compromiso Formativo y Normas del Taller',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: IncesTheme.azulPrimario,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El reglamento del INCES exige un mínimo del 75% de asistencia presencial '
                  'para la certificación oficial. Recuerde registrar su asistencia al inicio '
                  'de cada sesión y consultar en «Mis aulas» las instrucciones de seguridad '
                  'industrial correspondientes a su taller.',
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

  Widget _construirPie(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'CFS Nacional de Soldadura «Rafael Urdaneta» · Portal del Aprendiz · v0.1.0',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _EstudianteAccionData {
  const _EstudianteAccionData({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.seccionDestino,
    required this.color,
  });

  final String titulo;
  final String descripcion;
  final IconData icono;
  final String seccionDestino;
  final Color color;
}
