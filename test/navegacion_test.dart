import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/navegacion.dart';

void main() {
  group('analizarRuta', () {
    test('separa el camino de la consulta', () {
      final destino = analizarRuta('/auth/activate?token=ABC');

      expect(destino.ruta, '/auth/activate');
      expect(destino.token, 'ABC');
    });

    test('sin consulta no hay token', () {
      final destino = analizarRuta('/auth/activate');

      expect(destino.ruta, '/auth/activate');
      expect(destino.token, isNull);
    });

    test('un token vacío cuenta como ausente, no como cadena vacía', () {
      expect(analizarRuta('/auth/activate?token=').token, isNull);
    });

    test('encuentra el token entre otros parámetros', () {
      final destino = analizarRuta('/auth/activate?otro=1&token=ABC&x=2');

      expect(destino.ruta, '/auth/activate');
      expect(destino.token, 'ABC');
    });

    test('la raíz se conserva', () {
      expect(analizarRuta('/').ruta, '/');
    });

    test('un nombre vacío, nulo o en blanco cae en la raíz', () {
      expect(analizarRuta(null).ruta, '/');
      expect(analizarRuta('').ruta, '/');
      expect(analizarRuta('   ').ruta, '/');
    });

    test('un nombre que todavía arrastra el fragmento resuelve igual', () {
      final destino = analizarRuta('/#/auth/activate?token=ABC');

      expect(destino.ruta, '/auth/activate');
      expect(destino.token, 'ABC');
    });

    test('un nombre que es sólo fragmento también resuelve', () {
      final destino = analizarRuta('#/auth/activate?token=ABC');

      expect(destino.ruta, '/auth/activate');
      expect(destino.token, 'ABC');
    });

    test('un camino real distinto de la raíz no se pisa con el fragmento', () {
      // El fragmento sólo manda cuando el camino externo es la raíz. Si el
      // navegador sirvió una ruta de verdad, esa ruta es la que vale.
      final destino = analizarRuta('/inscripcion#/auth/activate?token=ABC');

      expect(destino.ruta, '/inscripcion');
    });

    test('un nombre que no empieza por barra no se inventa una raíz', () {
      expect(analizarRuta('auth/activate').ruta, 'auth/activate');
    });
  });

  group('tokenDeUrl', () {
    test('lo encuentra en el query real (estrategia de ruta)', () {
      expect(
        tokenDeUrl(Uri.parse('http://host/auth/activate?token=ABC')),
        'ABC',
      );
    });

    test('lo encuentra dentro del fragmento (estrategia de hash)', () {
      // Esta es la forma que arma el backend para el correo del docente:
      // `FRONTEND_URL/#/auth/activate?token=…`. El token NO está en el query de
      // la página, está dentro del fragmento.
      expect(
        tokenDeUrl(Uri.parse('http://localhost:8080/#/auth/activate?token=ABC')),
        'ABC',
      );
    });

    test('sin token devuelve null', () {
      expect(tokenDeUrl(Uri.parse('http://host/#/auth/activate')), isNull);
      expect(tokenDeUrl(Uri.parse('http://host/')), isNull);
    });

    test('un token vacío cuenta como ausente', () {
      expect(tokenDeUrl(Uri.parse('http://host/#/auth/activate?token=')), isNull);
    });

    test('el query de la página manda sobre el fragmento', () {
      expect(
        tokenDeUrl(
          Uri.parse('http://host/?token=QUERY#/auth/activate?token=FRAGMENTO'),
        ),
        'QUERY',
      );
    });

    test('un fragmento que no es una ruta no rompe nada', () {
      // El enlace de recuperación de Supabase trae el token en el fragmento,
      // pero con otra forma (`access_token=…&type=recovery`). No es asunto de
      // esta función, y desde luego no debe lanzar.
      expect(
        tokenDeUrl(Uri.parse('http://host/#access_token=XYZ&type=recovery')),
        isNull,
      );
    });
  });
}
