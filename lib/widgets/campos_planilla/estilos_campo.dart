import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// La decoración de un campo de la planilla, en **fuente única**.
///
/// Estaba dentro de `aspirante_form_screen.dart` como método privado. Al pasar a
/// un formulario conducido por datos, los campos los pinta un widget por tipo, y
/// si cada uno llevara su propia copia de los bordes el formulario se vería
/// distinto según el tipo de la fila del catálogo —que es justo lo que el
/// catálogo no debe poder provocar—.
InputDecoration decoracionDeCampo({
  required String etiqueta,
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
    labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
    helperStyle: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
    prefixIcon:
        icono == null ? null : Icon(icono, color: const Color(0xFF64748B), size: 20),
    suffixIcon: sufijo,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
