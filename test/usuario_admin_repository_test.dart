import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:inces_lms_app/core/network/api_client.dart';
import 'package:inces_lms_app/repositories/usuario_admin_repository.dart';

void main() {
  group('UsuariosAdminRepository', () {
    test('listar usuarios serializa y parsea correctamente', () async {
      final mockHttp = MockClient((request) async {
        expect(request.url.path, '/api/v1/admin/usuarios');
        expect(request.url.queryParameters['limite'], '25');
        expect(request.url.queryParameters['desplazamiento'], '0');
        expect(request.url.queryParameters['rol'], 'docente');

        final payload = {
          'usuarios': [
            {
              'id': 'u1',
              'email': 'docente@inces.test',
              'cedula': 'V12345678',
              'nombres': 'Pedro',
              'apellidos': 'Perez',
              'rol': 'docente',
              'activo': true,
            }
          ],
          'total': 1,
          'limite': 25,
          'desplazamiento': 0,
        };

        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockHttp,
        baseUrl: 'http://127.0.0.1:3001',
      );
      final repo = UsuariosAdminRepository(api: apiClient);

      final result = await repo.listar(rol: 'docente');
      if (result.isFailure) {
        // Diagnóstico directo
        fail('Fallo listar: ${result.errorOrNull?.message} (${result.errorOrNull})');
      }
      expect(result.isSuccess, isTrue);

      final pagina = result.valueOrNull!;
      expect(pagina.total, 1);
      expect(pagina.usuarios.length, 1);
      expect(pagina.usuarios.first.email, 'docente@inces.test');
      expect(pagina.usuarios.first.nombreCompleto, 'Pedro Perez');
      expect(pagina.usuarios.first.rol, 'docente');
      expect(pagina.usuarios.first.activo, isTrue);
    });

    test('cambiarRol envía patch y actualiza el rol del usuario', () async {
      final mockHttp = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/admin/usuarios/u1/rol');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['rol'], 'admin');

        final payload = {
          'perfil': {
            'id': 'u1',
            'email': 'docente@inces.test',
            'cedula': 'V12345678',
            'nombres': 'Pedro',
            'apellidos': 'Perez',
            'rol': 'admin',
            'activo': true,
          }
        };

        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        httpClient: mockHttp,
        baseUrl: 'http://127.0.0.1:3001',
      );
      final repo = UsuariosAdminRepository(api: apiClient);

      final result = await repo.cambiarRol(id: 'u1', rol: 'admin');
      expect(result.isSuccess, isTrue);
      final actualizado = result.valueOrNull!;
      expect(actualizado.rol, 'admin');
      expect(actualizado.nombreCompleto, 'Pedro Perez');
    });
  });
}
