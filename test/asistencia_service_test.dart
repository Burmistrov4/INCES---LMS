import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/screens/aspirante/marcar_asistencia_panel.dart';
import 'package:inces_lms_app/services/asistencia_service.dart';

/// El código del QR de M7: la paridad entre la app y la base.
///
/// **Por qué este archivo existe (D18).** Hasta el 2026-09-27 el módulo de
/// asistencia no tenía una sola prueba en Flutter. Lo que se prueba aquí es la
/// pieza que sostiene todo el anti-trampas: **el código que el docente proyecta
/// tiene que ser el mismo que la base acepta**. Si las dos derivaciones se
/// separan, el QR se pinta, el alumno lo escanea, y la base lo rechaza — sin que
/// nada avise, y sin que nadie pueda distinguirlo de «llegaste tarde».
///
/// **La duplicación es el riesgo, y por eso hay vectores dorados.** La regla está
/// escrita dos veces a propósito —una en `plpgsql` para la política RLS, otra en
/// Dart para que la pantalla rote sin red—, así que la única forma de que no se
/// desvíen es fijarlas contra una lista de valores calculados **por la base**. Los
/// de abajo los generó PostgreSQL (PGlite) ejecutando
/// `asistencia_codigo_en_ventana`, la misma función que la política llama.
///
/// **Y una duda que se midió en vez de suponerla.** El SQL hace
/// `('x' || hex8)::bit(32)::bigint % 1000000`. Si ese cast fuera **con signo**,
/// la mitad de los valores daría un resto negativo, `lpad` produciría cosas como
/// `00-123`, y las dos derivaciones discreparían en silencio. Se midió contra
/// PGlite: `('x' || 'ffffffff')::bit(32)::bigint` devuelve **4294967295** — sin
/// signo —, y sobre 500 ventanas consecutivas, 258 con el bit alto, las dos
/// coincidieron en las 500. **Cinco** de los vectores de abajo tienen el bit alto
/// (`f56cae82`, `f42980dc`, `a071cb9c`, `b2bf58da`, `c958920e`): son los que
/// fallarían si alguien cambiara el cast. Los cuatro primeros se buscaron a
/// propósito; el quinto salió así —es la ventana de 30 s— y se cuenta igual,
/// porque el comentario se corrigió midiendo, no releyendo. La cifra se puede
/// volver a comprobar con `supabase/tests/vectores-codigo-qr.mjs`.
void main() {
  group('paridad Dart ↔ Postgres del código del QR', () {
    // Generados por PostgreSQL. `instanteSegundos` es el instante exacto que hace
    // caer la ventana en el valor que se calculó, así que la prueba no depende del
    // reloj.
    final vectores = <({
      String secreto,
      String sesion,
      int ventanaSeg,
      int instanteSegundos,
      String esperado,
    })>[
      // La sesión sembrada del arnés, ventanas con el bit bajo.
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000030,
        esperado: '115283',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000060,
        esperado: '316167',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000075,
        esperado: '685195',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000090,
        esperado: '979775',
      ),
      // Y ventanas con el bit ALTO: las que distinguen un cast sin signo de uno
      // con signo.
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000000,
        esperado: '540482',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000015,
        esperado: '360668',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000045,
        esperado: '812252',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 15,
        instanteSegundos: 1785000120,
        esperado: '884570',
      ),
      // Otras ventanas de rotación: el docente puede abrir con 5, 30 o 120 s, y
      // el divisor cambia la ventana resultante.
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 5,
        instanteSegundos: 1785000000,
        esperado: '875654',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 30,
        instanteSegundos: 1785000000,
        esperado: '024974',
      ),
      (
        secreto: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesion: 'e5e5e5e5-0001-4001-8001-000000000001',
        ventanaSeg: 120,
        instanteSegundos: 1785000000,
        esperado: '212700',
      ),
      // Otro secreto y otra sesión: la derivación no puede depender de los valores
      // sembrados. El `024974` de arriba lleva el cero a la izquierda, que es el
      // caso que un `toString()` sin `padLeft` perdería.
      (
        secreto: 'ffffffffffffffffffffffffffffffffffffffff',
        sesion: '00000000-0000-4000-8000-000000000000',
        ventanaSeg: 15,
        instanteSegundos: 1785000015,
        esperado: '488846',
      ),
      (
        secreto: '0000000000000000000000000000000000000000',
        sesion: 'abcdefab-1234-4567-89ab-cdefabcdefab',
        ventanaSeg: 15,
        instanteSegundos: 1785000030,
        esperado: '666128',
      ),
    ];

    for (final vector in vectores) {
      test(
        'ventanaSeg=${vector.ventanaSeg} instante=${vector.instanteSegundos} → '
        '${vector.esperado} (lo que calcula Postgres)',
        () {
          final qr = AsistenciaService.codigoQr(
            qrSecret: vector.secreto,
            sesionId: vector.sesion,
            ventanaSeg: vector.ventanaSeg,
            ahora: DateTime.fromMillisecondsSinceEpoch(
              vector.instanteSegundos * 1000,
              isUtc: true,
            ),
          );

          expect(qr.codigo, vector.esperado);
        },
      );
    }

    test('el código es siempre de seis dígitos, también con el bit alto', () {
      // La propiedad que los vectores sólo muestrean. Un `%` sobre un entero con
      // signo devolvería un negativo, y `padLeft` sobre `-123` daría `-00123`:
      // seis caracteres, pero no seis dígitos. Esta prueba recorre 600 ventanas
      // consecutivas —unas 300 con el bit alto— y exige la forma.
      final formato = RegExp(r'^\d{6}$');

      for (var ventana = 119000000; ventana < 119000600; ventana++) {
        final qr = AsistenciaService.codigoQr(
          qrSecret: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
          sesionId: 'e5e5e5e5-0001-4001-8001-000000000001',
          ventanaSeg: 15,
          ahora: DateTime.fromMillisecondsSinceEpoch(ventana * 15 * 1000, isUtc: true),
        );

        expect(qr.codigo, matches(formato), reason: 'ventana $ventana → ${qr.codigo}');
      }
    });

    test('el código cambia al cambiar la ventana, y es estable dentro de ella', () {
      // Las dos mitades de la rotación. Sin la primera, un código constante
      // pasaría los vectores si los vectores fueran de una sola ventana; sin la
      // segunda, la pantalla parpadearía cada segundo y el alumno no podría
      // escanear nada.
      const secreto = '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7';
      const sesion = 'e5e5e5e5-0001-4001-8001-000000000001';

      String en(int instanteSegundos) => AsistenciaService.codigoQr(
            qrSecret: secreto,
            sesionId: sesion,
            ventanaSeg: 15,
            ahora: DateTime.fromMillisecondsSinceEpoch(instanteSegundos * 1000, isUtc: true),
          ).codigo;

      expect(en(1785000000), en(1785000001));
      expect(en(1785000014), en(1785000000));
      expect(en(1785000015), isNot(en(1785000000)));
      expect(en(1785000030), isNot(en(1785000000)));
    });

    test('`venceEnSegundos` cuenta lo que le queda a la ventana, no lo que pasó', () {
      // El contador de la pantalla del docente es la única señal de que el QR
      // proyectado sigue vigente. Si devolviera el tiempo transcurrido en vez del
      // restante, el número subiría y no bajaría — y una pantalla congelada se
      // vería igual que una viva.
      CodigoQr en(int instanteSegundos) => AsistenciaService.codigoQr(
            qrSecret: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
            sesionId: 'e5e5e5e5-0001-4001-8001-000000000001',
            ventanaSeg: 15,
            ahora: DateTime.fromMillisecondsSinceEpoch(instanteSegundos * 1000, isUtc: true),
          );

      expect(en(1785000000).venceEnSegundos, 15);
      expect(en(1785000005).venceEnSegundos, 10);
      expect(en(1785000014).venceEnSegundos, 1);
    });
  });

  group('ParseQr · el par que separa la sesión del código', () {
    test('lee `<uuid>:<6 dígitos>`', () {
      final par = ParseQr.de('e5e5e5e5-0001-4001-8001-000000000001:471212');

      expect(par, isNotNull);
      expect(par!.sesionId, 'e5e5e5e5-0001-4001-8001-000000000001');
      expect(par.codigo, '471212');
    });

    test('tolera espacios alrededor, porque el alumno pega lo que copió', () {
      final par = ParseQr.de('  e5e5e5e5-0001-4001-8001-000000000001:471212  ');

      expect(par!.sesionId, 'e5e5e5e5-0001-4001-8001-000000000001');
      expect(par.codigo, '471212');
    });

    test('rechaza lo que no tiene la forma del QR', () {
      // Se rechaza en el cliente **antes** de gastar una petición, y el mensaje
      // de la pantalla dice exactamente qué se esperaba. Ninguno de estos casos
      // protege de nada por sí solo —la barrera es la base—, pero evitan que el
      // alumno mande basura y lea un error sobre permisos.
      const invalidos = [
        '',
        '471212', // sin sesión
        'e5e5e5e5-0001-4001-8001-000000000001', // sin código
        'e5e5e5e5-0001-4001-8001-000000000001:', // código vacío
        ':471212', // sin sesión
        'no-soy-uuid:471212', // sesión con forma inválida
        'e5e5e5e5-0001-4001-8001-000000000001:12345', // cinco dígitos
        'e5e5e5e5-0001-4001-8001-000000000001:1234567', // siete
        'e5e5e5e5-0001-4001-8001-000000000001:47a212', // no son dígitos
      ];

      for (final texto in invalidos) {
        expect(ParseQr.de(texto), isNull, reason: 'debería rechazar «$texto»');
      }
    });
  });

  group('los eventos del canal en vivo', () {
    test('una marca se desempaqueta con los nombres de la base', () {
      // El `deJson` lee snake_case porque lo que llega es la fila de
      // `attendance_marks` tal cual, serializada por `difundir`. Una clave
      // camelCase aquí devolvería `null` y el tablero del docente pintaría una
      // fila con el nombre en blanco.
      final evento = EventoAsistencia.deJson({
        'tipo': 'marca',
        'sesionId': 'e5e5e5e5-0001-4001-8001-000000000001',
        'marca': {
          'id': 'f6f6f6f6-0000-4000-8000-000000000001',
          'session_id': 'e5e5e5e5-0001-4001-8001-000000000001',
          'student_id': '22222222-2222-2222-2222-222222222222',
          'marked_at': '2026-09-27T10:00:00.000Z',
        },
      });

      expect(evento.tipo, 'marca');
      expect(evento.marca, isNotNull);
      expect(evento.marca!.studentId, '22222222-2222-2222-2222-222222222222');
      expect(evento.marca!.marcadaEn, '2026-09-27T10:00:00.000Z');
    });

    test('`sesion_cerrada` llega sin marca y no revienta al parsear', () {
      // El evento de cierre no trae `marca`. Un `deJson` que exigiera el objeto
      // reventaría justo cuando la clase termina, que es cuando más se usa.
      final evento = EventoAsistencia.deJson({
        'tipo': 'sesion_cerrada',
        'sesionId': 'e5e5e5e5-0001-4001-8001-000000000001',
      });

      expect(evento.tipo, 'sesion_cerrada');
      expect(evento.marca, isNull);
    });

    test('el saludo `conectado` tampoco trae marca', () {
      final evento = EventoAsistencia.deJson({
        'tipo': 'conectado',
        'sesionId': 'e5e5e5e5-0001-4001-8001-000000000001',
      });

      expect(evento.tipo, 'conectado');
      expect(evento.marca, isNull);
    });
  });

  group('la costura entre el panel del docente y el del alumno', () {
    test('el par que codifica el docente es el que el alumno sabe leer', () {
      // **Por qué esta prueba existe, y es la más barata de las importantes.**
      //
      // El docente pinta `'$sesionId:${qr.codigo}'` (`asistencia_qr_panel.dart`) y
      // el alumno lo vuelve a partir con `ParseQr.de()`
      // (`marcar_asistencia_panel.dart`). Son dos piezas en dos archivos
      // distintos, y si la forma se separa el QR **se pinta igual** y la base lo
      // rechaza. Es el patrón exacto de **D21**: un defecto que vive en la costura
      // y que ninguna de las dos mitades revela por su lado.
      //
      // No se puede comprobar desde el árbol de widgets: medido en el paquete,
      // `QrImageView` guarda el texto en un campo **privado** (`final String?
      // _data`) y no expone getter, así que el contenido codificado no es legible.
      // Por eso la costura se fija aquí, con la **misma expresión** que usa el
      // panel. Es una copia, y una copia puede desviarse: la prueba lo dice en voz
      // alta en vez de fingir que lee el widget.
      const sesionId = 'e5e5e5e5-0001-4001-8001-000000000001';

      final qr = AsistenciaService.codigoQr(
        qrSecret: '3f2a9c1e5b7d8042a6c9e1f3b5d70842a1c3e5f7',
        sesionId: sesionId,
        ventanaSeg: 15,
        ahora: DateTime.fromMillisecondsSinceEpoch(
          1785000030 * 1000,
          isUtc: true,
        ),
      );

      final par = ParseQr.de('$sesionId:${qr.codigo}');

      expect(
        par,
        isNotNull,
        reason: 'el docente codifica algo que el panel del alumno no sabe leer',
      );
      expect(par!.sesionId, sesionId);
      expect(par.codigo, qr.codigo);
    });
  });
}
