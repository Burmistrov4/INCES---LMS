import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/inces_theme.dart';

/// La decoración de un campo de la planilla, en **fuente única**.
///
/// Estaba dentro de `aspirante_form_screen.dart` como método privado. Al pasar a
/// un formulario conducido por datos, los campos los pinta un widget por tipo, y
/// si cada uno llevara su propia copia de los bordes el formulario se vería
/// distinto según el tipo de la fila del catálogo —que es justo lo que el
/// catálogo no debe poder provocar—.
///
/// ## Los colores salen de [PaletaInces], no de literales
///
/// Aquí vivía el peor de los contrastes del proyecto. Tenía los suyos, **todos de
/// modo claro**: relleno `#F8FAFC`, etiqueta `#94A3B8`, ayuda e iconos `#64748B`.
/// En modo claro se leían. En oscuro, el relleno seguía siendo casi blanco
/// mientras el texto que se escribe lo ponía el `ColorScheme` oscuro en
/// `#E2E8F0`: **1.18:1**, o sea que lo tecleado desaparecía dentro del campo. La
/// etiqueta quedaba en 2.45:1. Medido el 2026-09-30.
///
/// [paleta] se pide en vez de resolverse aquí dentro para que un formulario con
/// cuarenta campos la resuelva **una vez** y no una por campo, y para que la
/// función siga siendo pura y comprobable sin montar un árbol de widgets.
InputDecoration decoracionDeCampo({
  required String etiqueta,
  required PaletaInces paleta,
  IconData? icono,
  String? ayuda,
  Widget? sufijo,
  String? error,
}) {
  return InputDecoration(
    labelText: etiqueta,
    helperText: ayuda,
    helperMaxLines: 2,
    errorText: error,
    errorMaxLines: 2,
    labelStyle: GoogleFonts.inter(color: paleta.textoApagado),
    helperStyle: GoogleFonts.inter(fontSize: 11, color: paleta.textoApagado),
    prefixIcon: icono == null
        ? null
        : Icon(icono, color: paleta.textoApagado, size: 20),
    suffixIcon: sufijo,
    filled: true,
    fillColor: paleta.rellenoDeCampo,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      borderSide: BorderSide(color: paleta.bordeDeCampo),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      borderSide: const BorderSide(color: IncesTheme.info, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      borderSide: const BorderSide(color: IncesTheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(IncesTheme.radioControl),
      borderSide: const BorderSide(color: IncesTheme.error, width: 1.5),
    ),
    // 14/16, que es lo que pone el `inputDecorationTheme`. Antes eran 12 en
    // vertical: dos valores distintos para el mismo campo según quién lo pintara,
    // que es el mismo desajuste que había en los colores y se arregla igual —con
    // un solo sitio donde se decide—.
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
  );
}

/// Un icono razonable para un campo, deducido de su **código**.
///
/// El catálogo no declara iconos, y añadirlos sería otra columna que el CFS
/// tendría que mantener. Deducirlo del código da un formulario legible sin
/// inventar configuración, y un campo nuevo cae al icono genérico en vez de
/// quedarse sin ninguno.
IconData iconoDeCampo(String codigo) {
  final clave = codigo.toLowerCase();

  if (clave.contains('correo') || clave.contains('email')) return Icons.email_outlined;
  if (clave.contains('telefono') || clave.contains('celular')) return Icons.phone_outlined;
  if (clave.contains('cedula') || clave.contains('identidad')) return Icons.badge_outlined;
  if (clave.contains('fecha') || clave.contains('nac')) return Icons.calendar_today;
  if (clave.contains('nombre') || clave.contains('apellido') || clave.contains('tutor')) {
    return Icons.person_outline;
  }
  if (clave.contains('direccion') || clave.contains('domicilio') || clave.contains('comunidad')) {
    return Icons.home_outlined;
  }
  if (clave.contains('nivel') || clave.contains('educativo') || clave.contains('formacion')) {
    return Icons.school_outlined;
  }
  if (clave.contains('curso') || clave.contains('programa') || clave.contains('propuesta')) {
    return Icons.book_outlined;
  }
  if (clave.contains('discapacidad')) return Icons.accessible;
  if (clave.contains('mision')) return Icons.flag_outlined;
  if (clave.contains('deporte')) return Icons.sports_soccer;
  if (clave.contains('cultural')) return Icons.theater_comedy_outlined;
  if (clave.contains('social') || clave.contains('organizacion')) return Icons.groups_outlined;
  if (clave.contains('estado') || clave.contains('municipio')) return Icons.map_outlined;
  if (clave.contains('parentesco') || clave.contains('familia')) {
    return Icons.family_restroom;
  }
  if (clave.contains('twitter') || clave.contains('facebook')) return Icons.public;

  return Icons.edit_outlined;
}
