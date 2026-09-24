import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/inscripcion_campo.dart';

/// Un campo `rejilla`: una lista de casillas donde cada ítem marcado lleva su
/// propio valor.
///
/// Es lo que la planilla de papel trae para las misiones —20 casillas, cada una
/// con su «Desde»— y por eso es `rejilla` y no `multiseleccion`: una
/// multiselección guarda sólo *cuáles*, y aquí hace falta *cuáles y desde
/// cuándo*.
///
/// **El valor guardado es `Map<String, String>`**: código del ítem → texto del
/// «desde». Sólo aparecen los ítems marcados, así que un mapa vacío significa
/// «ninguna marcada», que es exactamente lo que `validar_planilla()` entiende
/// por vacío. Una lista de marcados y un mapa aparte para los «desde» serían dos
/// estructuras que podrían discrepar; una sola no puede.
class CampoRejilla extends StatelessWidget {
  const CampoRejilla({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
    this.error,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;
  final String? error;

  /// Los ítems marcados, con su «desde».
  Map<String, String> get _marcados {
    final v = valor;
    if (v is! Map) return const {};
    return {
      for (final entrada in v.entries)
        entrada.key.toString(): (entrada.value ?? '').toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final marcados = _marcados;
    final items = campo.itemsRejilla;
    final etiquetaDesde = campo.etiquetaDesde;

    void alternar(String codigo, bool marcado) {
      final siguiente = Map<String, String>.from(marcados);
      if (marcado) {
        siguiente[codigo] = siguiente[codigo] ?? '';
      } else {
        siguiente.remove(codigo);
      }
      onCambio(siguiente);
    }

    void cambiarDesde(String codigo, String texto) {
      final siguiente = Map<String, String>.from(marcados);
      siguiente[codigo] = texto;
      onCambio(siguiente);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          campo.etiqueta,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0F172A),
          ),
        ),
        if (campo.ayuda != null) ...[
          const SizedBox(height: 2),
          Text(
            campo.ayuda!,
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
          ),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Column(
            children: [
              for (final item in items) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // La casilla y su rótulo son un solo blanco táctil: marcar
                    // el texto tiene que marcar la casilla, o en móvil el
                    // aspirante toca el texto y no pasa nada.
                    Expanded(
                      child: InkWell(
                        onTap: () => alternar(item.valor, !marcados.containsKey(item.valor)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Checkbox(
                                value: marcados.containsKey(item.valor),
                                onChanged: (v) => alternar(item.valor, v ?? false),
                              ),
                              Expanded(
                                child: Text(
                                  item.etiqueta,
                                  style: GoogleFonts.inter(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (etiquetaDesde != null && marcados.containsKey(item.valor))
                      SizedBox(
                        width: 108,
                        child: TextFormField(
                          // La clave lleva el código del ítem: si se marca una
                          // casilla nueva, los campos de debajo cambian de
                          // posición y sin clave Flutter reutilizaría el estado
                          // del que había ahí.
                          key: ValueKey('rejilla-${campo.codigo}-${item.valor}'),
                          initialValue: marcados[item.valor] ?? '',
                          decoration: InputDecoration(
                            hintText: etiquetaDesde,
                            hintStyle: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF94A3B8),
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                          ),
                          style: GoogleFonts.inter(fontSize: 12),
                          onChanged: (texto) => cambiarDesde(item.valor, texto.trim()),
                        ),
                      ),
                  ],
                ),
                if (item != items.last) const Divider(height: 1),
              ],
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626)),
          ),
        ],
      ],
    );
  }
}
