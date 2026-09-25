import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/inscripcion_campo.dart';
import 'campo_rejilla.dart';
import 'campo_tabla.dart';
import 'estilos_campo.dart';

/// Pinta **un** campo del catálogo, sea del tipo que sea.
///
/// Es el corazón del formulario conducido por datos: la pantalla no decide qué
/// widget usar, lo decide el `tipo` de la fila del catálogo. Añadir un campo al
/// formulario es insertar una fila en `inscripcion_campos`; añadir un **tipo**
/// nuevo es el único cambio que exige tocar este archivo.
///
/// El widget es **sin estado**: el valor vive en el mapa de la pantalla y sube
/// por [onCambio]. Así la planilla tiene una sola fuente de verdad, y una
/// pregunta que se oculta y se vuelve a mostrar conserva lo que el aspirante
/// había escrito.
class CampoPlanilla extends StatelessWidget {
  const CampoPlanilla({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
    this.opciones,
    this.error,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;

  /// Opciones que sustituyen a las del catálogo. Sólo se usa con los campos que
  /// declaran `fuente` —hoy `curso_seleccionado`—, cuyas opciones se consultan
  /// en vivo porque la oferta formativa cambia.
  final List<OpcionCampo>? opciones;

  /// Error del campo, si lo tiene. Se pinta bajo el campo en vez de con un
  /// `SnackBar` para que el aspirante vea **cuál** falla y no sólo que algo
  /// falla.
  final String? error;

  /// La clave de estado del **widget de dentro**, la que guarda el valor.
  ///
  /// No es cosmética. Cuando una pregunta condicional aparece o desaparece, los
  /// campos de debajo **cambian de posición** en la lista, y sin clave Flutter
  /// reutilizaría el estado del `FormField` que había en esa posición: el
  /// aspirante vería el texto de otra pregunta en el campo nuevo. Con la clave
  /// atada al código del campo, el estado viaja con el campo y no con el hueco.
  ///
  /// Y lleva un prefijo **distinto** al que le pone quien monta este widget
  /// (`campo-`), a propósito: dos claves iguales a distinta profundidad no son
  /// un error para Flutter —no son hermanas—, pero dejan `find.byKey` devolviendo
  /// dos elementos y vuelven ambigua cualquier prueba que busque un campo. Una
  /// prueba que tiene que desambiguar a mano es una prueba que se escribe mal.
  Key get claveDeEstado => ValueKey('entrada-${campo.codigo}');

  @override
  Widget build(BuildContext context) {
    final etiqueta = campo.etiqueta;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: switch (campo.tipo) {
        TipoCampoInscripcion.texto => _Texto(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            etiqueta: etiqueta,
            error: error,
          ),
        TipoCampoInscripcion.email => _Texto(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            etiqueta: etiqueta,
            error: error,
            tipoTeclado: TextInputType.emailAddress,
            validadorDeFormato: _validarCorreo,
          ),
        TipoCampoInscripcion.numero => _Numero(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            etiqueta: etiqueta,
            error: error,
          ),
        TipoCampoInscripcion.fecha => _Fecha(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            etiqueta: etiqueta,
            error: error,
          ),
        TipoCampoInscripcion.booleano => _Booleano(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            error: error,
          ),
        TipoCampoInscripcion.seleccion => _Seleccion(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            etiqueta: etiqueta,
            opciones: opciones,
            error: error,
          ),
        TipoCampoInscripcion.multiseleccion => _Multiseleccion(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            error: error,
          ),
        TipoCampoInscripcion.rejilla => CampoRejilla(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
            error: error,
          ),
        TipoCampoInscripcion.tabla => CampoTabla(
            key: claveDeEstado,
            campo: campo,
            valor: valor,
            onCambio: onCambio,
          ),
      },
    );
  }
}

/// El texto legible de un valor, para la pantalla de revisión.
///
/// Un `bool` se muestra como «Sí»/«No» y una rejilla o una tabla como un
/// resumen, en vez de volcar el `toString()` de un `Map` —que es lo que saldría
/// sin esto— y que el aspirante no podría leer.
String textoDeValor(CampoInscripcion campo, Object? valor) {
  if (valorDeCampoVacio(valor)) return '';

  switch (campo.tipo) {
    case TipoCampoInscripcion.booleano:
      return valor == true ? 'Sí' : 'No';

    case TipoCampoInscripcion.seleccion:
      final opciones = campo.opcionesCerradas;
      for (final opcion in opciones) {
        if (opcion.valor == valor.toString()) return opcion.etiqueta;
      }
      return valor.toString();

    case TipoCampoInscripcion.multiseleccion:
      final elegidos = (valor as List).map((v) => v.toString()).toList();
      final etiquetas = <String>[];
      for (final elegido in elegidos) {
        var etiqueta = elegido;
        for (final opcion in campo.opcionesCerradas) {
          if (opcion.valor == elegido) etiqueta = opcion.etiqueta;
        }
        etiquetas.add(etiqueta);
      }
      return etiquetas.join(', ');

    case TipoCampoInscripcion.rejilla:
      if (valor is Map) {
        final marcados = valor.keys.map((k) => k.toString()).toList();
        return '${marcados.length} marcada(s)';
      }
      return valor.toString();

    case TipoCampoInscripcion.tabla:
      if (valor is List) return '${valor.length} fila(s)';
      return valor.toString();

    case TipoCampoInscripcion.fecha:
      final crudo = valor.toString();
      final fecha = DateTime.tryParse(crudo);
      return fecha == null ? crudo : DateFormat('dd/MM/yyyy').format(fecha);

    case TipoCampoInscripcion.texto:
    case TipoCampoInscripcion.email:
    case TipoCampoInscripcion.numero:
      return valor.toString();
  }
}

/// El formato de correo que ya usaba el formulario escrito a mano.
String? _validarCorreo(String texto) {
  if (texto.isEmpty) return null;
  if (!RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(texto)) {
    return 'Ingresa un correo válido';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Campos simples
// ---------------------------------------------------------------------------

class _Texto extends StatelessWidget {
  const _Texto({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
    required this.etiqueta,
    this.error,
    this.tipoTeclado,
    this.validadorDeFormato,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;
  final String etiqueta;
  final String? error;
  final TextInputType? tipoTeclado;
  final String? Function(String texto)? validadorDeFormato;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: valor?.toString() ?? '',
      textCapitalization: TextCapitalization.words,
      keyboardType: tipoTeclado,
      autocorrect: tipoTeclado != TextInputType.emailAddress,
      decoration: decoracionDeCampo(
        etiqueta: etiqueta,
        icono: iconoDeCampo(campo.codigo),
        ayuda: campo.ayuda,
        error: error,
      ),
      validator: (texto) {
        final limpio = (texto ?? '').trim();
        if (campo.obligatorio && limpio.isEmpty) return 'Campo obligatorio';
        return validadorDeFormato?.call(limpio);
      },
      onChanged: (texto) => onCambio(texto.trim().isEmpty ? null : texto.trim()),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
    required this.etiqueta,
    this.error,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;
  final String etiqueta;
  final String? error;

  @override
  Widget build(BuildContext context) {
    // El error se deduce del propio valor: si sigue siendo texto es que no se
    // pudo interpretar como número. Así no hace falta guardar el texto crudo en
    // otro sitio sólo para poder avisar.
    final noEsNumero = valor is String && (valor as String).isNotEmpty;

    return TextFormField(
      initialValue: valor?.toString() ?? '',
      keyboardType: TextInputType.number,
      decoration: decoracionDeCampo(
        etiqueta: etiqueta,
        icono: iconoDeCampo(campo.codigo),
        ayuda: campo.ayuda,
        error: error ?? (noEsNumero ? 'Escribe sólo números' : null),
      ),
      validator: (texto) {
        final limpio = (texto ?? '').trim();
        if (campo.obligatorio && limpio.isEmpty) return 'Campo obligatorio';
        if (limpio.isNotEmpty && num.tryParse(limpio) == null) {
          return 'Escribe sólo números';
        }
        return null;
      },
      onChanged: (texto) {
        final limpio = texto.trim();
        if (limpio.isEmpty) return onCambio(null);
        // Un número se guarda como número; lo que aún no se puede interpretar se
        // guarda tal cual para no borrarle el texto a quien está escribiendo.
        onCambio(num.tryParse(limpio) ?? limpio);
      },
    );
  }
}

class _Fecha extends StatefulWidget {
  const _Fecha({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
    required this.etiqueta,
    this.error,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;
  final String etiqueta;
  final String? error;

  @override
  State<_Fecha> createState() => _FechaState();
}

/// La fecha es el **único** campo que tiene estado propio, y no por gusto.
///
/// Es el único cuyo valor cambia desde fuera del widget: lo elige un calendario,
/// no el teclado. Y un `TextFormField` **no** propaga un `initialValue` que
/// cambie —su `didUpdateWidget` sólo reacciona a un controlador distinto
/// (`text_form_field.dart:394`), y `_initialValue` es `late final`, capturado en
/// `initState`—. Sin controlador propio, el aspirante elegía una fecha y el
/// campo se quedaba **vacío**: el dato viajaba bien y no se veía nada, que es la
/// peor forma de fallar porque parece que el calendario no funcionó.
class _FechaState extends State<_Fecha> {
  late final TextEditingController _controlador;

  @override
  void initState() {
    super.initState();
    _controlador = TextEditingController(text: _comoTexto(widget.valor));
  }

  @override
  void didUpdateWidget(_Fecha oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valor != oldWidget.valor) {
      final texto = _comoTexto(widget.valor);
      if (_controlador.text != texto) _controlador.text = texto;
    }
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  DateTime? get _fecha => DateTime.tryParse(widget.valor?.toString() ?? '');

  /// El valor guardado (`YYYY-MM-DD`) como se le enseña al aspirante.
  static String _comoTexto(Object? valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '');
    return fecha == null ? '' : DateFormat('dd/MM/yyyy').format(fecha);
  }

  /// El rango del selector.
  ///
  /// Es el mismo que usaba el formulario escrito a mano: entre 15 y 80 años. El
  /// mínimo de 15 no es arbitrario —el CFS tiene un «Curso Introductorio» para
  /// 15 y 16 años—, y el máximo de 80 sólo evita que el selector abra en 1900.
  ///
  /// **No se pasa `locale`.** El proyecto no registra
  /// `GlobalMaterialLocalizations`, así que pedir el selector en español
  /// lanzaría en tiempo de ejecución por una localización que no está cargada.
  /// Traducir el calendario es una tarea propia —con sus `localizationsDelegates`
  /// en `MaterialApp`—, no un parámetro suelto.
  Future<void> _elegir(BuildContext context) async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha ?? DateTime(hoy.year - 20),
      firstDate: DateTime(hoy.year - 80, hoy.month, hoy.day),
      lastDate: DateTime(hoy.year - 15, hoy.month, hoy.day),
      helpText: widget.etiqueta,
    );

    if (elegida != null) {
      // Se guarda en `YYYY-MM-DD` y no como instante: es lo que el trigger
      // convierte a `date`, y un timestamp con hora local podía desplazar un día
      // y romper el CHECK de mayoría de edad.
      final anio = elegida.year.toString().padLeft(4, '0');
      final mes = elegida.month.toString().padLeft(2, '0');
      final dia = elegida.day.toString().padLeft(2, '0');
      widget.onCambio('$anio-$mes-$dia');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controlador,
      readOnly: true,
      onTap: () => _elegir(context),
      decoration: decoracionDeCampo(
        etiqueta: widget.etiqueta,
        icono: iconoDeCampo(widget.campo.codigo),
        ayuda: widget.campo.ayuda,
        error: widget.error,
        sufijo: IconButton(
          icon: const Icon(Icons.date_range_outlined, size: 20),
          onPressed: () => _elegir(context),
        ),
      ),
      validator: (texto) =>
          widget.campo.obligatorio && (texto ?? '').trim().isEmpty
              ? 'Campo obligatorio'
              : null,
    );
  }
}

class _Booleano extends StatelessWidget {
  const _Booleano({
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

  @override
  Widget build(BuildContext context) {
    // Un booleano **siempre** tiene valor: sin tocar es `false`, que es una
    // respuesta y no una ausencia. Por eso no se escribe `null` aquí: si lo
    // hiciera, un campo obligatorio de este tipo no se podría cumplir nunca.
    final marcado = valor == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onCambio(!marcado),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Checkbox(value: marcado, onChanged: (v) => onCambio(v ?? false)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    campo.etiqueta,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (campo.ayuda != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              campo.ayuda!,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              error!,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFDC2626)),
            ),
          ),
      ],
    );
  }
}

class _Seleccion extends StatelessWidget {
  const _Seleccion({
    super.key,
    required this.campo,
    required this.valor,
    required this.onCambio,
    required this.etiqueta,
    this.opciones,
    this.error,
  });

  final CampoInscripcion campo;
  final Object? valor;
  final ValueChanged<Object?> onCambio;
  final String etiqueta;
  final List<OpcionCampo>? opciones;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final disponibles = opciones ?? campo.opcionesCerradas;
    final actual = valor?.toString();
    final seleccionado =
        actual != null && disponibles.any((o) => o.valor == actual) ? actual : null;

    return DropdownButtonFormField<String>(
      // `isExpanded` y el recorte de una sola línea son obligatorios, no gusto:
      // medido a 375 px, la ranura del campo mide 165 px y una opción larga
      // —«Higiene y Manipulación de Alimentos»— se parte en cuatro líneas que no
      // caben en los 24 px de alto, así que el aspirante no puede leer lo que
      // acaba de elegir. El recorte silencioso no lanza y ninguna auditoría de
      // `RenderFlex` lo ve.
      isExpanded: true,
      selectedItemBuilder: (context) => [
        for (final opcion in disponibles)
          Text(opcion.etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
      initialValue: seleccionado,
      decoration: decoracionDeCampo(
        etiqueta: etiqueta,
        icono: iconoDeCampo(campo.codigo),
        ayuda: campo.ayuda,
        error: error,
      ),
      items: [
        for (final opcion in disponibles)
          DropdownMenuItem(value: opcion.valor, child: Text(opcion.etiqueta)),
      ],
      onChanged: (v) => onCambio(v),
      validator: (v) => campo.obligatorio && (v == null || v.isEmpty)
          ? 'Campo obligatorio'
          : null,
    );
  }
}

class _Multiseleccion extends StatelessWidget {
  const _Multiseleccion({
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

  List<String> get _elegidos {
    final v = valor;
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final elegidos = _elegidos;

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
        const SizedBox(height: 8),
        // `Wrap` y no `Row`: con seis opciones, una fila desborda a 375 px.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final opcion in campo.opcionesCerradas)
              FilterChip(
                label: Text(opcion.etiqueta, style: GoogleFonts.inter(fontSize: 12)),
                selected: elegidos.contains(opcion.valor),
                onSelected: (marcado) {
                  final siguiente = [...elegidos];
                  if (marcado) {
                    siguiente.add(opcion.valor);
                  } else {
                    siguiente.remove(opcion.valor);
                  }
                  onCambio(siguiente);
                },
              ),
          ],
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
