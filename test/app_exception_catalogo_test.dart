import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';

/// Traducción de los errores del catálogo de inscripción a mensajes accionables.
///
/// Se prueba contra la **forma real** del error que devuelve PostgREST —y no
/// contra un doble del gateway— porque lo que se verifica es justo eso: que el
/// nombre del constraint y el de la tabla estén donde el código cree que están.
/// Un doble que lanzara una excepción inventada probaría que el `catch` funciona,
/// no que la firma del error esté bien leída, y ese es el fallo que de verdad
/// puede colarse: si el texto no está donde se busca, la traducción **no falla**,
/// cae al mensaje genérico y nadie se entera.
void main() {
  /// Un error con la forma que devuelve PostgREST de verdad.
  AppException traducir({
    required String code,
    required String message,
    String? details,
  }) {
    return AppException.from(
      PostgrestException(code: code, message: message, details: details),
    );
  }

  group('clave duplicada en el catálogo (23505)', () {
    test('el código repetido se explica como campo duplicado', () {
      final error = traducir(
        code: '23505',
        message:
            'duplicate key value violates unique constraint "inscripcion_campos_pkey"',
        details: 'Key (codigo)=(talla_camisa) already exists.',
      );

      expect(error.type, AppErrorType.duplicado);
      expect(error.message, contains('campo'));
      expect(error.code, '23505');
    });

    test('un campo llamado «email» NO se confunde con un correo duplicado', () {
      // Éste es el caso que obliga a comprobar el catálogo **antes** del `switch`
      // genérico: el detalle de Postgres nombra la columna, así que el texto
      // contiene «email» aunque el duplicado sea de un campo de la planilla. Sin
      // el orden correcto, el admin leería «ya existe una cuenta con ese correo»
      // mientras añade una pregunta al formulario.
      final error = traducir(
        code: '23505',
        message:
            'duplicate key value violates unique constraint "inscripcion_campos_pkey"',
        details: 'Key (codigo)=(email) already exists.',
      );

      expect(error.type, AppErrorType.duplicado);
      expect(
        error.message,
        isNot(contains('cuenta')),
        reason: 'no debe hablar de cuentas: el duplicado es del catálogo',
      );
    });

    test('la cédula duplicada conserva su mensaje de inscripción', () {
      // Control negativo: enriquecer la traducción no debe haberse comido las
      // ramas que ya existían.
      final error = traducir(
        code: '23505',
        message:
            'duplicate key value violates unique constraint "aspirantes_cedula_key"',
        details: 'Key (cedula)=(12345678) already exists.',
      );

      expect(error.type, AppErrorType.duplicado);
      expect(error.message, contains('cédula'));
    });
  });

  group('formato del código (23514)', () {
    test('el CHECK del formato del código explica el formato', () {
      final error = traducir(
        code: '23514',
        message:
            'new row for relation "inscripcion_campos" violates check constraint '
            '"inscripcion_campos_codigo_formato"',
      );

      expect(error.type, AppErrorType.validacion);
      expect(error.message, contains('minúsculas'));
    });

    test('un 23514 ajeno al catálogo conserva el mensaje de inscripción', () {
      final error = traducir(
        code: '23514',
        message:
            'new row for relation "aspirantes" violates check constraint '
            '"requires_legal_tutor_check"',
      );

      expect(error.type, AppErrorType.validacion);
      expect(error.message, contains('representante'));
    });
  });

  group('permisos (42501)', () {
    test('la RLS del catálogo se explica como «sólo un administrador»', () {
      final error = traducir(
        code: '42501',
        message:
            'new row violates row-level security policy for table '
            '"inscripcion_campos"',
      );

      expect(error.type, AppErrorType.permisos);
      expect(error.message, contains('administrador'));
    });
  });

  group('lo que NO se discrimina, a propósito', () {
    test('PGRST116 cae al mensaje genérico porque no nombra la tabla', () {
      // Documenta una limitación **medida**, no un descuido: el mensaje de
      // PGRST116 es siempre el mismo texto, así que no hay forma de saber que
      // venía del catálogo. Se fija en una prueba para que nadie lo «arregle»
      // con una heurística que acertaría casi siempre.
      final error = traducir(
        code: 'PGRST116',
        message: 'JSON object requested, multiple (or no) rows returned',
      );

      expect(error.type, AppErrorType.validacion);
      expect(error.message, 'No encontramos la información solicitada.');
    });
  });
}
