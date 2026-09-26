import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/network/api_client.dart';

/// El objeto que la app espera y la base no tiene todavía: **falta una
/// migración**.
///
/// Los códigos NO se inventaron. Se midieron contra la nube el 2026-09-26 con la
/// clave anónima:
///
/// ```
/// GET /rest/v1/tabla_que_no_existe_xyz          → 404 PGRST205
///       "Could not find the table 'public.X' in the schema cache"
/// GET /rest/v1/programs?select=columna_fantasma → 400 42703
///       "column programs.columna_fantasma does not exist"
/// ```
///
/// Se prueba contra la **forma real** del error —y no contra un doble— porque lo
/// que se verifica es justo eso: que el código sea el que PostgREST emite de
/// verdad. Un código inventado probaría que el `catch` funciona, no que la rama
/// sea alcanzable, y ese es el fallo que se cuela en silencio: si el código no
/// coincide, la traducción **no falla**, cae al mensaje genérico y nadie se
/// entera.
void main() {
  AppException desdePostgrest(String code, String message) =>
      AppException.from(PostgrestException(code: code, message: message));

  group('objeto ausente por PostgREST', () {
    test('PGRST205 (tabla sin migrar) es esquema desactualizado', () {
      final error = desdePostgrest(
        'PGRST205',
        "Could not find the table 'public.v_exportacion_hacer' in the schema cache",
      );

      expect(error.type, AppErrorType.esquemaDesactualizado);
      expect(error.code, 'PGRST205');
    });

    test('42703 (columna sin migrar) es esquema desactualizado', () {
      final error = desdePostgrest(
        '42703',
        'column programs.columna_fantasma_xyz does not exist',
      );

      expect(error.type, AppErrorType.esquemaDesactualizado);
      expect(error.code, '42703');
    });

    test('NO es recuperable: reintentar daría exactamente el mismo resultado', () {
      // Éste es el motivo de que el tipo exista. Con `servidor` —que sí es
      // recuperable— la UI ofrece «Reintentar» y el usuario pulsa un botón que
      // no puede funcionar, porque el objeto seguirá faltando.
      expect(desdePostgrest('PGRST205', 'x').esRecuperable, isFalse);
      expect(desdePostgrest('42703', 'x').esRecuperable, isFalse);
    });

    test('el mensaje no miente: no dice que se estaba guardando', () {
      // Antes caía al `servidor` del final, cuyo texto es «No pudimos guardar la
      // información» —falso para una LECTURA— y encima invita a reintentar.
      final error = desdePostgrest('PGRST205', 'x');

      expect(error.message.toLowerCase(), isNot(contains('guardar')));
      expect(error.message, contains('administrador'));
    });

    test('los códigos que ya se traducían no se tragan', () {
      // Regresión: la rama nueva se insertó dentro del mismo `switch`, así que
      // hay que comprobar que las anteriores siguen respondiendo.
      expect(desdePostgrest('23502', 'x').type, AppErrorType.validacion);
      expect(desdePostgrest('23505', 'x').type, AppErrorType.duplicado);
      expect(desdePostgrest('42501', 'x').type, AppErrorType.permisos);
      expect(desdePostgrest('PGRST116', 'x').type, AppErrorType.validacion);
    });
  });

  group('el backend marca el esquema desactualizado con HTTP 500', () {
    /// Un `ApiClient` que siempre responde lo mismo, sin red.
    ApiClient clienteQueResponde(int estado, Map<String, dynamic> cuerpo) {
      return ApiClient(
        baseUrl: 'http://localhost:3001',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(cuerpo),
            estado,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
    }

    /// Ejecuta una lectura y devuelve el [AppException] que lanzó.
    Future<AppException> capturar(ApiClient cliente) async {
      try {
        await cliente.get('/api/v1/ofertas');
      } on AppException catch (error) {
        return error;
      }
      fail('se esperaba un AppException y la llamada devolvió un valor');
    }

    test('ApiClient NO lo degrada a `servidor`', () async {
      // El backend traduce «falta una migración» a ESQUEMA_DESACTUALIZADO, pero
      // lo hace con un **500**. Un 500 a secas se clasifica como `servidor`, que
      // es recuperable: la traducción cuidadosa del backend se perdía justo en
      // el cliente. Esta prueba fija que no vuelva a perderse.
      final cliente = clienteQueResponde(500, {
        'error': {
          'codigo': 'ESQUEMA_DESACTUALIZADO',
          'mensaje': 'Falta aplicar una migración en la base de datos.',
        },
      });

      final error = await capturar(cliente);

      expect(error.type, AppErrorType.esquemaDesactualizado);
      expect(error.esRecuperable, isFalse);
      // El `mensaje` del servidor se reenvía tal cual: ya viene en español.
      expect(error.message, contains('migración'));
    });

    test('un 500 sin ese código sigue siendo `servidor` y recuperable', () async {
      // El contraste, que es lo que impide que la comprobación nueva convierta
      // en «no recuperable» cualquier 500: sólo el que el backend marca.
      final cliente = clienteQueResponde(500, {
        'error': {'codigo': 'ERROR_INTERNO', 'mensaje': 'Ocurrió un error inesperado.'},
      });

      final error = await capturar(cliente);

      expect(error.type, AppErrorType.servidor);
      expect(error.esRecuperable, isTrue);
    });
  });
}
