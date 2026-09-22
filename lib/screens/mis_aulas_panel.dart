import 'package:flutter/material.dart';

import '../core/gateways/aula_gateway.dart';
import '../core/result.dart';
import '../widgets/andamiaje.dart';
import '../widgets/comunes.dart';
import 'aula_virtual_dashboard.dart';

/// Listado «Mis aulas»: las secciones de quien mira y la puerta al Aula Virtual.
///
/// ## De dónde salen las aulas
///
/// De `GET /api/v1/mi-horario`, vía [AulasPropiasGateway]. Es la única ruta del
/// sistema que lista las secciones de **quien mira**, y sirve igual a un docente
/// y a un estudiante: el rol viene en el payload y aquí sólo decide si el aula
/// se abre en modo docente o en modo estudiante.
///
/// Una misma sección aparece en `clases` **una vez por franja** del cuadrante;
/// la reducción a una fila por sección la hace el gateway, no esta pantalla.
/// Aquí se pinta lo que llega: un [AulaResumen] ya es un aula.
///
/// ## Por qué el contenido es opcional
///
/// [aulaGateway] es la puerta del **contenido** del aula (tablón, trabajo de
/// clase, entregas). Su implementación HTTP no existe todavía —el JSON de M6 no
/// está cerrado—, así que hoy sólo la implementa el doble de pruebas. Cuando no
/// se inyecta, el listado **sigue siendo real** (viene de la ruta congelada) y
/// la pantalla lo dice, en vez de abrir un aula que no puede cargar nada.
class PanelMisAulas extends StatefulWidget {
  const PanelMisAulas({super.key, required this.gateway, this.aulaGateway});

  /// De dónde sale el listado de secciones.
  final AulasPropiasGateway gateway;

  /// La puerta del contenido del aula. Ver la nota de la clase.
  final AulaGateway? aulaGateway;

  @override
  State<PanelMisAulas> createState() => _PanelMisAulasState();
}

class _PanelMisAulasState extends State<PanelMisAulas> {
  bool _cargando = true;
  String? _error;
  MisAulas? _misAulas;

  /// La sección abierta, si la hay.
  ///
  /// Se resuelve con estado y no empujando una ruta por la misma razón que el
  /// detalle de tarea del aula: así el aula hereda la altura acotada de
  /// [ContenidoSeccion] y sus `Expanded` y `ListView` reciben un alto finito.
  /// Una ruta nueva perdería ese contrato y habría que reconstruirlo a mano.
  AulaResumen? _abierta;

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

    final resultado = await Result.guard(() => widget.gateway.misAulas());
    if (!mounted) return;

    setState(() {
      _cargando = false;
      resultado.when(
        success: (mis) => _misAulas = mis,
        failure: (fallo) => _error = fallo.message,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final abierta = _abierta;
    final puerta = widget.aulaGateway;

    // El aula abierta sustituye al listado. Sólo puede haber una abierta si hay
    // puerta de contenido: sin ella, las tarjetas no son pulsables.
    if (abierta != null && puerta != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vuelta al listado. Hace falta de verdad: volver a pulsar «Mis
          // aulas» en el menú no reinicia este estado —el widget se conserva—,
          // así que sin este botón el usuario quedaría encerrado en el aula.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _abierta = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Volver a Mis aulas'),
            ),
          ),
          Expanded(
            child: AulaVirtualDashboardScreen(
              seccionId: abierta.seccionId,
              // La misma etiqueta que la tarjeta: el título del aula y la fila
              // del listado no pueden discrepar.
              seccionNombre: abierta.etiqueta,
              gateway: puerta,
              // El rol sale del payload, no de una bandera del llamante.
              esDocente: _misAulas?.esDocente ?? false,
            ),
          ),
        ],
      );
    }

    return ContenidoSeccion(
      migas: const ['Inicio', 'Académico', 'Mis aulas'],
      child: EstadoPanel(
        cargando: _cargando,
        error: _error,
        onReintentar: _cargar,
        child: _listado(),
      ),
    );
  }

  Widget _listado() {
    final mis = _misAulas;

    if (mis == null || mis.vacio) {
      return PanelVacio(
        titulo: 'Todavía no tienes aulas activas',
        mensaje: (mis?.esDocente ?? false)
            ? 'Cuando la coordinación del centro te asigne secciones, '
                'aparecerán aquí con su tablón y su trabajo de clase.'
            : 'Cuando la coordinación active tu sección verás aquí el tablón '
                'de anuncios y el trabajo de clase, y podrás subir tus '
                'entregas sin salir del aula.',
        icono: Icons.class_outlined,
        nota: mis?.periodo != null ? 'Lapso: ${mis!.periodo}' : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          'Mis aulas',
          subtitulo: '${mis.aulas.length} sección(es) en este lapso.',
          acciones: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ),
        if (widget.aulaGateway == null) ...[
          // Sin puerta de contenido el listado es correcto pero el aula no se
          // puede abrir. Se dice antes de que el usuario pulse, no después.
          const AvisoEnLinea(
            texto: 'Estas son tus secciones reales. El contenido del aula —el '
                'tablón y el trabajo de clase— se activará cuando el centro '
                'publique el módulo.',
            icono: Icons.info_outline,
            tono: TonoAviso.info,
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: ListView(
            children: [for (final aula in mis.aulas) _tarjeta(aula)],
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(AulaResumen aula) {
    final theme = Theme.of(context);
    final abrible = widget.aulaGateway != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(
            Icons.class_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(aula.etiqueta, style: theme.textTheme.titleSmall),
        trailing:
            abrible ? const Icon(Icons.chevron_right_rounded) : null,
        // Sin puerta de contenido la tarjeta **no** se puede pulsar: un toque
        // que abre una pantalla incapaz de cargar nada es peor que un toque que
        // no hace nada, porque promete algo que no cumple.
        onTap: abrible ? () => setState(() => _abierta = aula) : null,
      ),
    );
  }
}
