import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../models/inscripcion.dart';
import '../../repositories/inscripcion_repository.dart';
import '../../services/planilla_admin_pdf_service.dart';
import '../../widgets/comunes.dart';

/// Diálogo con los inscritos vivos de una sección y la descarga de su planilla
/// (Módulo 4, vista del administrador).
///
/// **Qué resuelve, y qué no existía.** La ruta
/// `GET /api/v1/inscripcion/planilla/{usuarioId}/pdf` estaba construida desde el
/// 2026-09-25 —en el contrato OpenAPI, con `exigirAdmin()` + `exigirModulo` y con
/// la RLS `aspirantes_admin_all` autorizándola— y **ningún código Dart la
/// llamaba**: el panel de inscripciones sólo tenía «Ver cola» y «Reincorporar».
/// El administrador no tenía forma de imprimir la planilla de nadie, que es
/// justo lo que necesita para entregársela al aspirante que llega al centro.
///
/// **Por qué un diálogo por sección y no una pantalla nueva.** Las personas se
/// listan donde ya se listan: la tarjeta de la sección es el contexto, y
/// `AdminInscripcionesRepository.obtenerInscripcionesDeSeccion` ya devuelve sus
/// inscripciones no abandonadas —lo usa el diálogo de reincorporar—. Una pantalla
/// de «Aspirantes» habría exigido una sección nueva en el menú, con su guardia y
/// su conteo, para mostrar exactamente la misma lista.
///
/// **Por qué aquí y no en `ColaSeccionDialog`.** Aquél muestra **sólo** la cola
/// (`WAITLISTED`), que es la pregunta «¿quién espera y a qué distancia del
/// asiento?». Éste muestra a **todos** los que siguen en la sección, que es la
/// pregunta «¿de quién puedo imprimir la planilla?». Son dos preguntas distintas
/// y mezclarlas dejaría a los matriculados fuera de la única pantalla donde se
/// descargan planillas.
///
/// Diseñado como widget top-level (no método del panel) para poder probarlo
/// aislado, siguiendo el mismo criterio que el resto de paneles del cPanel.
class InscritosSeccionDialog extends StatefulWidget {
  const InscritosSeccionDialog({
    super.key,
    required this.repo,
    required this.planilla,
    required this.seccionId,
    required this.seccionNombre,
  });

  final AdminInscripcionesRepository repo;

  /// La descarga de la planilla ajena. Se inyecta porque la implementación real
  /// es del navegador y no compila en la VM — ver `selector_archivos.dart` —, y
  /// porque el servicio es quien traduce los códigos de error.
  final PlanillaAdminPdfService planilla;

  final String seccionId;
  final String seccionNombre;

  @override
  State<InscritosSeccionDialog> createState() => _InscritosSeccionDialogState();
}

class _InscritosSeccionDialogState extends State<InscritosSeccionDialog> {
  late Future<Result<List<InscripcionDetallada>>> _futuro =
      widget.repo.obtenerInscripcionesDeSeccion(widget.seccionId);

  /// Los ids cuya planilla se está descargando ahora mismo.
  ///
  /// Es un conjunto y no un booleano porque cada fila tiene su propio botón: con
  /// una sola bandera, pulsar la descarga de una persona deshabilitaría la de
  /// todas las demás, y el administrador que imprime cinco planillas seguidas no
  /// podría encadenarlas.
  final Set<String> _descargando = {};

  void _reintentar() {
    setState(() {
      _futuro = widget.repo.obtenerInscripcionesDeSeccion(widget.seccionId);
    });
  }

  /// Descarga la planilla de [inscripcion] y traduce el desenlace a un aviso.
  ///
  /// El diálogo **no descarga**: pide la secuencia al servicio y convierte su
  /// resultado en el mensaje que el administrador lee. Así la secuencia se prueba
  /// sin montar el diálogo, y los códigos de error no se interpretan en dos
  /// sitios.
  Future<void> _descargar(InscripcionDetallada inscripcion) async {
    final estudiante = _etiqueta(inscripcion);
    setState(() => _descargando.add(inscripcion.estudianteId));

    final resultado = await widget.planilla.descargarPlanillaDe(
      usuarioId: inscripcion.estudianteId,
      estudiante: estudiante,
    );

    if (!mounted) return;
    setState(() => _descargando.remove(inscripcion.estudianteId));

    // `switch` sobre un `sealed`: si el servicio gana un desenlace nuevo, esto
    // deja de compilar en vez de dejar caer el caso al vacío.
    switch (resultado) {
      case PlanillaAdminDescargada(nombreArchivo: final nombre):
        mostrarAviso(
          context,
          'Planilla de $estudiante descargada ($nombre).',
          exito: true,
        );

      // No es un error y no se pinta como tal: que alguien esté matriculado y no
      // haya rellenado nunca la planilla de identidad es una situación real del
      // centro. Pero **sí** es algo que el administrador tiene que saber —es a
      // quien le falta el papel—, así que se nombra a la persona en vez de decir
      // «no se pudo».
      case AspiranteSinFicha(:final estudiante):
        mostrarAviso(
          context,
          '$estudiante todavía no tiene ficha de aspirante, así que no hay '
          'planilla que imprimir. Se crea cuando la persona completa la '
          'inscripción.',
        );

      case ConsultaAdminFallida(mensaje: final mensaje):
        mostrarAviso(context, mensaje, error: true);

      case DescargaAdminFallida():
        // No se muestra el `toString()` del error del navegador: al
        // administrador no le dice nada y no puede hacer nada con él.
        mostrarAviso(
          context,
          'El PDF se generó pero el navegador no pudo guardarlo. '
          'Inténtalo de nuevo.',
          error: true,
        );
    }
  }

  /// Nombre de una persona: el nombre si lo hay, el correo si no, y el id sólo
  /// como último recurso —nunca como primera opción, que es justo lo que esta
  /// pantalla viene a quitar de encima—.
  static String _etiqueta(InscripcionDetallada i) =>
      i.estudianteNombre ?? i.estudianteEmail ?? i.estudianteId;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Inscritos — ${widget.seccionNombre}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Matriculados, en cola y con oferta viva. Descarga la '
                          'planilla de cada uno para imprimirla.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<Result<List<InscripcionDetallada>>>(
                  future: _futuro,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final resultado = snap.data;
                    if (resultado == null) {
                      return const PanelVacio(
                        titulo: 'Sin respuesta',
                        mensaje: 'La consulta no devolvió datos.',
                        icono: Icons.help_outline_rounded,
                      );
                    }
                    return resultado.when(
                      success: (inscritos) {
                        if (inscritos.isEmpty) {
                          return const PanelVacio(
                            titulo: 'Nadie en la sección',
                            mensaje:
                                'Esta sección todavía no tiene inscripciones '
                                'vivas: nadie matriculado, en cola ni con '
                                'oferta de cupo.',
                            icono: Icons.people_outline_rounded,
                          );
                        }
                        return _ListaInscritos(
                          inscritos: inscritos,
                          descargando: _descargando,
                          onDescargar: _descargar,
                        );
                      },
                      failure: (fallo) => ErrorConReintento(
                        titulo: 'No se pudo cargar la lista',
                        mensaje: fallo.message,
                        onReintentar: _reintentar,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListaInscritos extends StatelessWidget {
  const _ListaInscritos({
    required this.inscritos,
    required this.descargando,
    required this.onDescargar,
  });

  final List<InscripcionDetallada> inscritos;
  final Set<String> descargando;
  final Future<void> Function(InscripcionDetallada) onDescargar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.separated(
      itemCount: inscritos.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final inscrito = inscritos[i];
        final nombre =
            inscrito.estudianteNombre ?? inscrito.estudianteId;
        final bajando = descargando.contains(inscrito.estudianteId);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(
              _iniciales(nombre),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(nombre, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              _descripcionEstado(inscrito.estado),
              if (inscrito.estudianteEmail != null) inscrito.estudianteEmail!,
            ].join(' · '),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton.filledTonal(
            // La clave ata el botón a **la persona de su fila**: una prueba
            // puede pulsar el de una fila concreta y comprobar que viaja el UUID
            // correcto, que es el error que un botón «de la lista» esconde.
            key: Key('descargar-planilla-${inscrito.estudianteId}'),
            tooltip: 'Descargar planilla (PDF)',
            onPressed: bajando ? null : () => onDescargar(inscrito),
            icon: bajando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, size: 20),
          ),
        );
      },
    );
  }
}

/// Iniciales para el avatar. Dos letras como mucho: con nombres compuestos, tres
/// o cuatro caracteres no caben en un `CircleAvatar` de 40 px y se recortan.
String _iniciales(String nombre) {
  final palabras = nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();

  if (palabras.isEmpty) return '?';
  if (palabras.length == 1) {
    final unica = palabras.first;
    return unica.length >= 2
        ? unica.substring(0, 2).toUpperCase()
        : unica.toUpperCase();
  }

  return (palabras.first[0] + palabras[1][0]).toUpperCase();
}

/// Cómo se lee el estado en pantalla. El enum guarda el valor del backend en
/// mayúsculas, que es un contrato y no un texto para el usuario.
String _descripcionEstado(EstadoInscripcion estado) => switch (estado) {
      EstadoInscripcion.enrolled => 'Matriculado',
      EstadoInscripcion.waitlisted => 'En cola',
      EstadoInscripcion.pendingBid => 'Oferta de cupo en el aire',
      EstadoInscripcion.dropped => 'Dado de baja',
    };

/// Helper para abrir el diálogo desde el panel de ocupación.
///
/// Se exporta como función para que el panel no tenga que importar
/// `InscritosSeccionDialog` y para centralizar el `showDialog`, igual que
/// `mostrarColaDeSeccion`.
Future<void> mostrarInscritosDeSeccion({
  required BuildContext context,
  required AdminInscripcionesRepository repo,
  required PlanillaAdminPdfService planilla,
  required String seccionId,
  required String seccionNombre,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => InscritosSeccionDialog(
      repo: repo,
      planilla: planilla,
      seccionId: seccionId,
      seccionNombre: seccionNombre,
    ),
  );
}
