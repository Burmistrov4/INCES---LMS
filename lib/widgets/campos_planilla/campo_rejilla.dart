import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/inscripcion_campo.dart';
import '../../theme/inces_theme.dart';

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
///
/// **Los colores salen de [PaletaInces].** Tenía los suyos, fijos de modo claro,
/// y el peor era la etiqueta: `#0F172A` —casi negro— sobre la tarjeta oscura
/// `#1E293B`, **1.22:1**, medido el 2026-09-30. No es que se leyera mal: no se
/// leía. Y el relleno del «Desde» era `Colors.white`, que en oscuro dejaba texto
/// claro sobre blanco.
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
    final paleta = PaletaInces.de(context);
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
            color: paleta.textoPrincipal,
          ),
        ),
        if (campo.ayuda != null) ...[
          const SizedBox(height: 2),
          Text(
            campo.ayuda!,
            style: GoogleFonts.inter(fontSize: 11, color: paleta.textoApagado),
          ),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            // El bloque hundido. En claro era `#F8FAFC` y la paleta pone
            // `#F1F5F9`: un punto más marcado, para que coincida con el resto de
            // bloques hundidos del proyecto en vez de ser el único con su tono.
            color: paleta.superficieSutil,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: paleta.bordeDeCampo),
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
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: paleta.textoPrincipal,
                                  ),
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
                              color: paleta.textoApagado,
                            ),
                            // `isDense` y 8/8 y no los 14/16 del tema: este campo
                            // vive dentro de la fila de una casilla y tiene que
                            // caber a su lado. Es la única razón por la que este
                            // campo se aparta del relleno estándar.
                            isDense: true,
                            filled: true,
                            fillColor: paleta.rellenoDeCampo,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: paleta.bordeDeCampo),
                            ),
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: paleta.textoPrincipal,
                          ),
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
            style: GoogleFonts.inter(fontSize: 12, color: IncesTheme.error),
          ),
        ],
      ],
    );
  }
}
