import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/inscripcion_campo.dart';

/// Un campo `tabla`: filas repetibles, cada una con las columnas que declara el
/// catálogo.
///
/// Es lo que la planilla de papel trae para los familiares y para las
/// formaciones complementarias: una tabla con cabecera, no un campo.
///
/// **El valor guardado es `List<Map<String, dynamic>>`**: una entrada por fila,
/// con el `codigo` de cada columna como clave. Un arreglo vacío significa «sin
/// filas», que es lo que `validar_planilla()` entiende por vacío.
///
/// **Por qué no reutiliza `CampoPlanilla` para las celdas.** Podría —una columna
/// es casi un campo—, pero una celda es otro problema visual: no lleva etiqueta
/// propia (la lleva la cabecera de la columna), y repetirla en cada fila
/// convertiría una tabla de ocho columnas y tres filas en veinticuatro etiquetas
/// iguales. El despacho por `tipo` se repite aquí a conciencia, y es más corto
/// que la configuración que haría falta para parametrizar el campo de arriba.
class CampoTabla extends StatefulWidget {
  const CampoTabla({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;

  @override
  State<CampoTabla> createState() => _CampoTablaState();
}

class _CampoTablaState extends State<CampoTabla> {
  /// Un identificador **estable** por fila.
  ///
  /// Vive aquí y no en el valor porque no es un dato: es la identidad del widget.
  /// Con claves por índice, quitar la primera fila haría que el estado de la
  /// segunda se reutilizara para la que ahora ocupa el índice 0, y el aspirante
  /// vería los datos de un familiar en el lugar de otro. Guardar el id dentro de
  /// la planilla obligaría además a limpiarlo antes de enviarla y a explicar por
  /// qué hay una clave que no está en el catálogo.
  List<int> _ids = [];
  int _siguienteId = 0;

  List<Map<String, dynamic>> get _filas {
    final v = widget.valor;
    if (v is! List) return const [];
    return v.whereType<Map<String, dynamic>>().toList();
  }

  @override
  void initState() {
    super.initState();
    _sincronizarIds(_filas.length);
  }

  @override
  void didUpdateWidget(covariant CampoTabla anterior) {
    super.didUpdateWidget(anterior);
    // El padre es quien manda sobre el número de filas: aquí sólo se mantiene la
    // lista de ids del mismo tamaño. No hace falta `setState` porque ya estamos
    // dentro de una reconstrucción.
    _sincronizarIds(_filas.length);
  }

  /// Ajusta la lista de ids al número de filas.
  ///
  /// **Sólo añade por el final.** Recortar por el final sería lo único que se
  /// podría hacer aquí sin saber *qué* fila se fue, y estaría mal: quitar la
  /// primera de dos filas dejaría el id de la primera para la segunda, Flutter
  /// reutilizaría su estado y el aspirante vería los datos de un familiar en el
  /// sitio de otro. Por eso [quitar] retira el id en su índice, y esta función
  /// sólo rellena el caso de que la lista haya crecido.
  void _sincronizarIds(int cuantas) {
    while (_ids.length < cuantas) {
      _ids.add(_siguienteId++);
    }
    // Si hay más ids que filas, alguien recortó la lista desde fuera. Se recorta
    // por el final como último recurso, y se acepta que en ese caso las claves
    // pueden quedar desalineadas: no hay información para hacerlo mejor.
    if (_ids.length > cuantas) _ids = _ids.sublist(0, cuantas);
  }

  void _publicar(List<Map<String, dynamic>> filas) {
    // Se copian las filas y los mapas: publicar la misma referencia que ya está
    // en el mapa del padre haría que el cambio se diera por hecho antes de
    // reconstruir, y una comparación por identidad no vería diferencia.
    widget.onCambio([for (final fila in filas) Map<String, dynamic>.from(fila)]);
  }

  void _agregar() {
    final filas = _filas;
    _publicar([...filas, <String, dynamic>{}]);
  }

  void _quitar(int indice) {
    final filas = _filas;
    if (indice < 0 || indice >= filas.length) return;

    final copia = [...filas]..removeAt(indice);
    // El id se retira **en su índice**, que es lo que mantiene las claves de las
    // filas que quedan apuntando a las filas que son.
    if (indice < _ids.length) _ids.removeAt(indice);

    _publicar(copia);
  }

  void _celda(int indice, String codigo, Object? valor) {
    final filas = _filas;
    if (indice < 0 || indice >= filas.length) return;
    final fila = Map<String, dynamic>.from(filas[indice]);
    if (valor == null || (valor is String && valor.trim().isEmpty)) {
      fila.remove(codigo);
    } else {
      fila[codigo] = valor;
    }
    final copia = [...filas];
    copia[indice] = fila;
    _publicar(copia);
  }

  @override
  Widget build(BuildContext context) {
    final columnas = widget.campo.columnasTabla;
    final filas = _filas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.campo.etiqueta,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0F172A),
          ),
        ),
        if (widget.campo.ayuda != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.campo.ayuda!,
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
          ),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < filas.length; i++)
          Padding(
            // La clave lleva el id estable, no el índice.
            key: ValueKey('tabla-${widget.campo.codigo}-${_ids[i]}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: _Fila(
              campo: widget.campo,
              columnas: columnas,
              indice: i,
              fila: filas[i],
              onCelda: _celda,
              onQuitar: () => _quitar(i),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _agregar,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Añadir fila'),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.campo,
    required this.columnas,
    required this.indice,
    required this.fila,
    required this.onCelda,
    required this.onQuitar,
  });

  final CampoInscripcion campo;
  final List<ColumnaTabla> columnas;
  final int indice;
  final Map<String, dynamic> fila;
  final void Function(int indice, String codigo, Object? valor) onCelda;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                for (final columna in columnas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Celda(
                      key: ValueKey('celda-${campo.codigo}-$indice-${columna.codigo}'),
                      columna: columna,
                      valor: fila[columna.codigo],
                      onCambio: (v) => onCelda(indice, columna.codigo, v),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Quitar esta fila',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onQuitar,
          ),
        ],
      ),
    );
  }
}

/// Una celda, según el tipo que declare la columna.
class _Celda extends StatelessWidget {
  const _Celda({super.key, required this.columna, required this.valor, required this.onCambio});

  final ColumnaTabla columna;
  final Object? valor;
  final ValueChanged<Object?> onCambio;

  InputDecoration get _decoracion => InputDecoration(
        labelText: columna.etiqueta + (columna.obligatorio ? ' *' : ''),
        labelStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    switch (columna.tipo) {
      case TipoCampoInscripcion.booleano:
        final marcado = valor == true;
        return Row(
          children: [
            Checkbox(value: marcado, onChanged: (v) => onCambio(v ?? false)),
            Expanded(
              child: Text(columna.etiqueta, style: GoogleFonts.inter(fontSize: 12)),
            ),
          ],
        );

      case TipoCampoInscripcion.seleccion:
        final actual = valor?.toString();
        final seleccionado =
            actual != null && columna.opciones.any((o) => o.valor == actual)
                ? actual
                : null;
        return DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: seleccionado,
          decoration: _decoracion,
          items: [
            for (final opcion in columna.opciones)
              DropdownMenuItem(value: opcion.valor, child: Text(opcion.etiqueta)),
          ],
          onChanged: (v) => onCambio(v),
        );

      case TipoCampoInscripcion.numero:
        return TextFormField(
          initialValue: valor?.toString() ?? '',
          keyboardType: TextInputType.number,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _decoracion,
          onChanged: (texto) {
            final limpio = texto.trim();
            if (limpio.isEmpty) return onCambio(null);
            onCambio(num.tryParse(limpio) ?? limpio);
          },
        );

      case TipoCampoInscripcion.fecha:
        // Fecha en texto y no con selector: en una celda de 375 px el calendario
        // tapa la tabla entera y el aspirante pierde de vista la fila que está
        // rellenando. Se documenta como el compromiso que es.
        return TextFormField(
          initialValue: valor?.toString() ?? '',
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _decoracion.copyWith(hintText: 'AAAA-MM-DD'),
          onChanged: (texto) => onCambio(texto.trim().isEmpty ? null : texto.trim()),
        );

      case TipoCampoInscripcion.multiseleccion:
      case TipoCampoInscripcion.tabla:
      case TipoCampoInscripcion.rejilla:
      case TipoCampoInscripcion.texto:
      case TipoCampoInscripcion.email:
        return TextFormField(
          initialValue: valor?.toString() ?? '',
          keyboardType: columna.tipo == TipoCampoInscripcion.email
              ? TextInputType.emailAddress
              : TextInputType.text,
          autocorrect: columna.tipo != TipoCampoInscripcion.email,
          style: GoogleFonts.inter(fontSize: 13),
          decoration: _decoracion,
          onChanged: (texto) => onCambio(texto.trim().isEmpty ? null : texto.trim()),
        );
    }
  }
}
