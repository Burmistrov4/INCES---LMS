import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/reglas_cuadrante.dart';
import 'package:inces_lms_app/models/cuadrante.dart';

/// Pruebas de las reglas del cuadrante.
///
/// El segundo grupo es el que importa de verdad, y no es el de las funciones
/// puras: **contrasta las constantes de Dart con la migración de M3**. Sin él,
/// este archivo sólo probaría que el espejo coincide consigo mismo. Con él, si
/// alguien mueve la frontera de turnos en la base o renombra un día, la prueba
/// falla aquí en vez de que la rejilla pinte un bloque en la franja equivocada.
///
/// Es la misma técnica que `backend/test/reglas-cuadrante.test.ts` —leer la
/// migración como texto— aplicada al lado de Dart, porque son **dos** espejos
/// distintos y cada uno necesita su propia vigilancia.
void main() {
  group('turnos y bloques', () {
    test('el turno de un bloque sigue la frontera, para los doce bloques', () {
      for (var bloque = 1; bloque <= bloquesDeManana; bloque++) {
        expect(
          turnoDeBloque(bloque),
          Turno.manana,
          reason: 'el bloque $bloque es de la mañana',
        );
      }
      for (var bloque = bloquesDeManana + 1;
          bloque <= bloqueMaximo;
          bloque++) {
        expect(
          turnoDeBloque(bloque),
          Turno.tarde,
          reason: 'el bloque $bloque es de la tarde',
        );
      }
    });

    test('los bloques de los dos turnos cubren el día sin huecos ni solapes', () {
      final todos = [
        ...bloquesDelTurno(Turno.manana),
        ...bloquesDelTurno(Turno.tarde),
      ];

      // Cada bloque aparece exactamente una vez, y entre los dos turnos cubren
      // del 1 al 12. Un bloque en los dos turnos lo pintaría dos veces en la
      // rejilla; uno en ninguno desaparecería sin que nadie lo note.
      expect(todos, [for (var b = 1; b <= bloqueMaximo; b++) b]);
    });

    test('un turno desconocido en el JSON se deriva del bloque', () {
      // La columna es `generated always as (turno_de_bloque(block)) stored`, así
      // que siempre llega. Si llegara corrupta, inventar «mañana» para un bloque
      // 9 pintaría la clase en la franja equivocada (R-16).
      expect(Turno.desdeApi(null, bloque: 3), Turno.manana);
      expect(Turno.desdeApi(null, bloque: 9), Turno.tarde);
      expect(Turno.desdeApi('', bloque: 9), Turno.tarde);
      expect(Turno.desdeApi('TARDE', bloque: 1), Turno.tarde);
      expect(Turno.desdeApi('MAÑANA', bloque: 12), Turno.manana);
    });
  });

  group('los espejos, contra la migración real', () {
    // Los valores que se comprueban, leídos del SQL y no escritos aquí.
    late int corteEnSql;
    late String mananaEnSql;
    late String tardeEnSql;
    late Map<int, String> diasEnSql;
    late List<int> diasMaximosEnSql;
    late List<int> bloquesMaximosEnSql;

    setUpAll(() {
      final sql = _leerMigracion();

      // `turno_de_bloque`: la frontera y los dos nombres de turno.
      final turno = _cuerpoDeFuncion(sql, 'turno_de_bloque');
      final corte = RegExp(
        r"p_bloque\s*<=\s*(\d+)\s+then\s+'([^']+)'\s+else\s+'([^']+)'",
      ).firstMatch(turno);

      if (corte == null) {
        fail('No se encontró el corte de `turno_de_bloque` en la migración.');
      }

      corteEnSql = int.parse(corte.group(1)!);
      mananaEnSql = corte.group(2)!;
      tardeEnSql = corte.group(3)!;

      // `dia_legible`: los seis nombres.
      final dia = _cuerpoDeFuncion(sql, 'dia_legible');
      diasEnSql = {
        for (final m in RegExp(r"when (\d) then '([^']+)'").allMatches(dia))
          int.parse(m.group(1)!): m.group(2)!,
      };

      // Los `check` de rango, que aparecen una vez por tabla (`teacher_duties`
      // y `schedule_slots`).
      diasMaximosEnSql = [
        for (final m in RegExp(r'check \(day_of_week between 1 and (\d+)\)')
            .allMatches(sql))
          int.parse(m.group(1)!),
      ];
      bloquesMaximosEnSql = [
        for (final m in RegExp(r'check \(block between 1 and (\d+)\)')
            .allMatches(sql))
          int.parse(m.group(1)!),
      ];
    });

    test('el analizador encontró lo que buscaba', () {
      // Suelo explícito. Sin él, un cambio de formato en la migración dejaría
      // los conjuntos vacíos y las comprobaciones de abajo pasarían por la
      // puerta de atrás.
      expect(diasEnSql.length, 6, reason: 'los seis días de `dia_legible`');
      expect(
        diasMaximosEnSql.length,
        greaterThanOrEqualTo(2),
        reason: 'el `check` de día está en las dos tablas del cuadrante',
      );
      expect(
        bloquesMaximosEnSql.length,
        greaterThanOrEqualTo(2),
        reason: 'el `check` de bloque está en las dos tablas del cuadrante',
      );
    });

    test('la frontera de turnos es la misma que la de la base', () {
      expect(
        bloquesDeManana,
        corteEnSql,
        reason: 'la frontera de turnos se movió en la base y no en Dart',
      );
      expect(turnoDeBloque(1).valorApi, mananaEnSql);
      expect(turnoDeBloque(bloqueMaximo).valorApi, tardeEnSql);
    });

    test('los días son los mismos que los de la base, y en el mismo orden', () {
      // Se compara sin distinguir mayúsculas a propósito: el SQL escribe
      // «lunes» porque va dentro de una frase («Ese docente ya tiene… el
      // lunes»), y la interfaz escribe «Lunes» porque encabeza una columna.
      // Lo que no puede diferir es el nombre ni el orden.
      for (var dia = 1; dia <= diaMaximo; dia++) {
        expect(
          diasDeLaSemana[dia].toLowerCase(),
          diasEnSql[dia],
          reason: 'el día $dia no coincide con el de la base',
        );
      }
    });

    test('los máximos de día y bloque son los de la base', () {
      for (final maximo in diasMaximosEnSql) {
        expect(diaMaximo, maximo, reason: 'el máximo de día no coincide');
      }
      for (final maximo in bloquesMaximosEnSql) {
        expect(bloqueMaximo, maximo, reason: 'el máximo de bloque no coincide');
      }
    });

    test('las dos tablas del cuadrante usan el mismo rango', () {
      // Si una tabla admitiera el día 7 y la otra no, el mismo hueco sería
      // válido en una y rechazado en la otra, y el chequeo de colisiones
      // compararía rangos distintos.
      expect(diasMaximosEnSql.toSet(), hasLength(1));
      expect(bloquesMaximosEnSql.toSet(), hasLength(1));
    });
  });

  group('fechas', () {
    test('acepta una fecha ISO bien formada', () {
      expect(esFechaISO('2026-09-21'), isTrue);
      expect(esFechaISO('2027-02-28'), isTrue);
      expect(esFechaISO('2028-02-29'), isTrue, reason: '2028 es bisiesto');
      expect(esFechaISO('  2026-09-21  '), isTrue, reason: 'se recorta');
    });

    test('rechaza un día que no existe, no sólo un formato raro', () {
      // Éste es el caso que una comprobación de formato dejaría pasar.
      expect(esFechaISO('2027-02-30'), isFalse);
      expect(esFechaISO('2027-04-31'), isFalse);
      expect(esFechaISO('2027-02-29'), isFalse, reason: '2027 no es bisiesto');
    });

    test('rechaza formatos que no son AAAA-MM-DD', () {
      expect(esFechaISO('21/09/2026'), isFalse);
      expect(esFechaISO('2026-9-21'), isFalse);
      expect(esFechaISO('2026-09-21T00:00:00Z'), isFalse);
      expect(esFechaISO(''), isFalse);
    });

    test('un rango a medias es válido, porque las fechas son opcionales', () {
      // El centro no ha cargado las fechas del lapso en curso e inventarlas
      // sería fabricar un dato institucional (R-17).
      expect(rangoDeFechasValido(inicio: null, fin: null), isTrue);
      expect(rangoDeFechasValido(inicio: '2026-09-21', fin: null), isTrue);
      expect(rangoDeFechasValido(inicio: null, fin: '2027-02-13'), isTrue);
    });

    test('exige que el fin sea posterior al inicio', () {
      expect(
        rangoDeFechasValido(inicio: '2026-09-21', fin: '2027-02-13'),
        isTrue,
      );
      expect(
        rangoDeFechasValido(inicio: '2026-09-21', fin: '2026-09-21'),
        isFalse,
        reason: 'un lapso de un día no es un rango',
      );
      expect(
        rangoDeFechasValido(inicio: '2027-02-13', fin: '2026-09-21'),
        isFalse,
      );
    });
  });

  group('códigos, nombres y capacidades', () {
    test('acepta los códigos de lapso que usa el centro', () {
      expect(esCodigoDeLapso('2026-1'), isTrue);
      expect(esCodigoDeLapso('SA26-2'), isTrue);
      expect(esCodigoDeLapso('2026-2'), isTrue);
    });

    test('rechaza un código de lapso mal formado', () {
      expect(esCodigoDeLapso(''), isFalse);
      expect(esCodigoDeLapso('-2026'), isFalse, reason: 'empieza por guion');
      expect(esCodigoDeLapso('2026 1'), isFalse, reason: 'lleva un espacio');
      expect(esCodigoDeLapso('2026_1'), isFalse);
      expect(esCodigoDeLapso('2026-1234567'), isFalse, reason: 'pasa de 10');
    });

    test('el nombre de un espacio no puede estar en blanco', () {
      expect(nombreDeAulaValido('Taller de Soldadura'), isTrue);
      expect(nombreDeAulaValido(''), isFalse);
      expect(nombreDeAulaValido('   '), isFalse);
      expect(nombreDeAulaValido('a' * 80), isTrue);
      expect(nombreDeAulaValido('a' * 81), isFalse);
    });

    test('la capacidad cero es válida y la negativa no', () {
      // Cero significa «sin cupo declarado»: una zona, un pasillo. No es lo
      // mismo que desconocido, y por eso la columna es `not null default 0`.
      expect(capacidadValida(0), isTrue);
      expect(capacidadValida(12), isTrue);
      expect(capacidadValida(-1), isFalse);
    });

    test('el tipo de un espacio sale de sus dos columnas', () {
      expect(TipoAula.deAula(esTaller: true, capacidad: 12), TipoAula.taller);
      expect(TipoAula.deAula(esTaller: true, capacidad: 0), TipoAula.taller);
      expect(TipoAula.deAula(esTaller: false, capacidad: 12), TipoAula.aula);
      expect(TipoAula.deAula(esTaller: false, capacidad: 0), TipoAula.zona);
    });

    test('los tres tipos son excluyentes y cubren todos los casos', () {
      for (final esTaller in [true, false]) {
        for (final capacidad in [0, 1, 30]) {
          final tipo = TipoAula.deAula(
            esTaller: esTaller,
            capacidad: capacidad,
          );
          // El filtro de la pantalla se elige entre estos tres, así que ninguno
          // puede quedar fuera sin que el usuario lo sepa.
          expect(TipoAula.values, contains(tipo));
        }
      }
    });
  });

  group('días legibles', () {
    test('nombra los seis días del centro', () {
      expect(diaLegible(1), 'Lunes');
      expect(diaLegible(6), 'Sábado');
    });

    test('un día fuera de rango no se inventa un nombre', () {
      // «Día 9» se leería como un dato raro que enseñar; un `null` deja que la
      // pantalla lo trate como el error que es.
      expect(diaLegible(0), isNull);
      expect(diaLegible(7), isNull);
      expect(diaLegible(-1), isNull);
    });
  });

  group('choque de agenda', () {
    test('se reconoce por el código, no por el tipo de error', () {
      // `ApiClient` clasifica todo 409 como `AppErrorType.validacion`, así que
      // el tipo no distingue un choque de un dato mal formado. Es el código el
      // que permite dar un mensaje útil.
      expect(esChoqueDeAgenda(codigoChoqueDeAgenda), isTrue);
      expect(esChoqueDeAgenda('RESTRICCION_VIOLADA'), isFalse);
      expect(esChoqueDeAgenda('REGISTRO_DUPLICADO'), isFalse);
      expect(esChoqueDeAgenda(null), isFalse);
    });
  });

  group('el nombre de un docente sin nombre', () {
    test('se nombra el hueco en vez de dejarlo mudo', () {
      // R-21: el canal de invitación nunca captura los nombres, así que la vista
      // devuelve NULL. Un hueco en blanco se lee como un fallo de la aplicación.
      expect(nombreDeDocente('Luis Márquez'), 'Luis Márquez');
      expect(nombreDeDocente(''), 'Docente sin nombre');
      expect(nombreDeDocente('   '), 'Docente sin nombre');
      expect(nombreDeDocente(null), 'Docente sin nombre');
    });
  });
}

// -----------------------------------------------------------------------------
//  Lectura de la migración
// -----------------------------------------------------------------------------

const String _rutaMigracion =
    'supabase/migrations/202609180001_mod3_cuadrante_aulas.sql';

/// Localiza la migración de M3 sin dar por hecho el directorio de trabajo.
///
/// `flutter test` corre desde la raíz del paquete, pero asumirlo convertiría un
/// cambio de invocación en un «fichero no encontrado» que no explica nada.
File _archivoMigracion() {
  var directorio = Directory.current;

  for (var intentos = 0; intentos < 6; intentos++) {
    final candidato = File('${directorio.path}/$_rutaMigracion');
    if (candidato.existsSync()) return candidato;

    final padre = directorio.parent;
    if (padre.path == directorio.path) break;
    directorio = padre;
  }

  fail(
    'No se encontró $_rutaMigracion subiendo desde ${Directory.current.path}',
  );
}

String _leerMigracion() => _archivoMigracion().readAsStringSync();

/// Extrae el cuerpo de una función `create or replace function public.X`.
String _cuerpoDeFuncion(String sql, String nombre) {
  final patron = RegExp(
    'create or replace function public\\.$nombre\\b[\\s\\S]*?\\\$\\\$'
    '([\\s\\S]*?)\\\$\\\$',
    caseSensitive: false,
  );
  final coincidencia = patron.firstMatch(sql);

  if (coincidencia == null) {
    fail('No se encontró la función $nombre en la migración de M3.');
  }

  return coincidencia.group(1) ?? '';
}
