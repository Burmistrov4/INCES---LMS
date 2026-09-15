import 'package:flutter/material.dart';

import '../models/cuadrante.dart';

/// Rejilla de días × bloques, compartida por el cuadrante del administrador y el
/// horario del docente/estudiante.
///
/// Es la misma matriz en los dos sitios —filas = bloques 1–12, columnas = días
/// lunes…sábado— y por eso vive aquí y no duplicada: dos copias de la «misma»
/// rejilla se desvían en cuanto alguien ajusta una (ya pasó con los azules del
/// login). El widget sólo dibuja el esqueleto; el contenido de cada celda lo
/// aporta el panel que lo usa, en forma de *chips*.
///
/// La franja de la tarde (bloques 7–12) se marca con un divisor y un fondo
/// tenue, usando [bloquesDeManana] para no escribir la frontera en dos sitios.
class CuadranteGrid extends StatelessWidget {
  const CuadranteGrid({super.key, required this.celdas});

  /// Contenido de cada celda, por clave `'$dia-$bloque'`.
  final Map<String, List<Widget>> celdas;

  static String clave(int dia, int bloque) => '$dia-$bloque';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dias = [for (var d = 1; d <= diaMaximo; d++) d];
    final bloques = [for (var b = 1; b <= bloqueMaximo; b++) b];

    final borde = theme.colorScheme.outline.withValues(alpha: 0.25);

    final hijos = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        children: [
          const _CeldaCabecera(texto: ''),
          for (final dia in dias)
            _CeldaCabecera(texto: diasDeLaSemana[dia]),
        ],
      ),
      for (final bloque in bloques)
        TableRow(
          decoration: bloque > bloquesDeManana
              ? BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer
                      .withValues(alpha: 0.18),
                )
              : null,
          children: [
            _CeldaGutter(bloque: bloque),
            for (final dia in dias)
              _CeldaContenido(
                hijos: celdas[clave(dia, bloque)] ?? const [],
                esDivisorTurno: bloque == bloquesDeManana + 1,
                borde: borde,
              ),
          ],
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: borde, width: 1),
          defaultColumnWidth: const FixedColumnWidth(168),
          columnWidths: const {
            0: FixedColumnWidth(46),
          },
          children: hijos,
        ),
      ),
    );
  }
}

/// Cabecera de día o de la columna de bloques.
class _CeldaCabecera extends StatelessWidget {
  const _CeldaCabecera({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 38,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Gutter izquierdo: número de bloque, con el turno en el primero de cada franja.
class _CeldaGutter extends StatelessWidget {
  const _CeldaGutter({required this.bloque});

  final int bloque;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final turno = turnoDeBloque(bloque);
    final esPrimero = bloque == 1 || bloque == bloquesDeManana + 1;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$bloque',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (esPrimero)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                turno.etiqueta,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CeldaContenido extends StatelessWidget {
  const _CeldaContenido({
    required this.hijos,
    this.esDivisorTurno = false,
    required this.borde,
  });

  final List<Widget> hijos;
  final bool esDivisorTurno;
  final Color borde;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.all(5),
      // El divisor de turno es un realce visual, no una regla nueva: separa la
      // mañana de la tarde sin que el usuario tenga que contar bloques.
      decoration: esDivisorTurno
          ? BoxDecoration(
              border: Border(top: BorderSide(color: borde, width: 2)),
            )
          : null,
      child: hijos.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < hijos.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  hijos[i],
                ],
              ],
            ),
    );
  }
}

/// Chip de una celda: una clase o una guardia.
///
/// `destacado` lo usa la clase (llena el aula de la que es dueña); la guardia va
/// sin fondo para distinguirse a la vista. El `onTap` es opcional: las guardias
/// en el cuadrante son de sólo lectura (se editan en su propio panel), y un chip
/// sin `onTap` se pinta como una tarjeta muda.
class ChipCuadrante extends StatelessWidget {
  const ChipCuadrante({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.color,
    this.destacado = false,
    this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final Color? color;
  final bool destacado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acento = color ?? theme.colorScheme.primary;

    final contenido = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final tarjeta = Container(
      decoration: BoxDecoration(
        color: destacado ? acento.withValues(alpha: 0.12) : null,
        border: Border.all(
          color: destacado ? acento.withValues(alpha: 0.5) : bordeSuave(theme),
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: contenido,
    );

    if (onTap == null) return tarjeta;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: tarjeta,
      ),
    );
  }

  static Color bordeSuave(ThemeData theme) =>
      theme.colorScheme.outline.withValues(alpha: 0.35);
}

/// Agrupa las clases por celda para alimentar a [CuadranteGrid].
Map<String, List<Widget>> agruparClases(
  List<ClaseCuadrante> clases, {
  required Widget Function(ClaseCuadrante) chip,
}) {
  final mapa = <String, List<Widget>>{};
  for (final clase in clases) {
    final clave = CuadranteGrid.clave(clase.dia, clase.bloque);
    (mapa[clave] ??= []).add(chip(clase));
  }
  return mapa;
}

/// Agrupa las guardias por celda para alimentar a [CuadranteGrid].
Map<String, List<Widget>> agruparGuardias(
  List<Guardia> guardias, {
  required Widget Function(Guardia) chip,
}) {
  final mapa = <String, List<Widget>>{};
  for (final guardia in guardias) {
    final clave = CuadranteGrid.clave(guardia.dia, guardia.bloque);
    (mapa[clave] ??= []).add(chip(guardia));
  }
  return mapa;
}
