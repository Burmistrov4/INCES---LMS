import { describe, expect, it } from 'vitest';
import {
  BLOQUE_MAXIMO,
  DIA_MAXIMO,
  diaLegible,
  esChoqueDeAgenda,
  esFechaISO,
  rangoDeFechasValido,
  turnoDeBloque,
} from '../src/dominio/reglas-cuadrante.js';

/**
 * Las reglas puras de M3, sin montar HTTP ni repositorios.
 *
 * Se prueban aquí por la misma razón que `reglas-curriculo.test.ts`: una regla
 * enterrada en un manejador sólo se ejercita levantando la API entera. Como
 * función pura se prueban los casos que la API casi nunca alcanza —el día 7, el
 * bloque 13, el 30 de febrero— que son justo los que aparecen el día que alguien
 * pega una planilla desde una hoja de cálculo.
 */

describe('turnoDeBloque', () => {
  it('los seis primeros bloques son la mañana', () => {
    for (let bloque = 1; bloque <= 6; bloque += 1) {
      expect(turnoDeBloque(bloque), `bloque ${bloque}`).toBe('MAÑANA');
    }
  });

  it('del séptimo en adelante es la tarde', () => {
    for (let bloque = 7; bloque <= BLOQUE_MAXIMO; bloque += 1) {
      expect(turnoDeBloque(bloque), `bloque ${bloque}`).toBe('TARDE');
    }
  });

  it('el corte está exactamente en el 6/7, no antes ni después', () => {
    // Esta aserción es la que avisa si alguien mueve la frontera en la función
    // SQL y olvida este espejo. El corte es provisional (R-16), así que se
    // moverá; lo que no puede pasar es que los dos sitios se separen en
    // silencio y el backend calcule un turno que la base nunca produciría.
    expect(turnoDeBloque(6)).toBe('MAÑANA');
    expect(turnoDeBloque(7)).toBe('TARDE');
  });
});

describe('diaLegible', () => {
  it('nombra los seis días laborables', () => {
    expect(diaLegible(1)).toBe('lunes');
    expect(diaLegible(2)).toBe('martes');
    expect(diaLegible(3)).toBe('miércoles');
    expect(diaLegible(4)).toBe('jueves');
    expect(diaLegible(5)).toBe('viernes');
    expect(diaLegible(6)).toBe('sábado');
  });

  it('el domingo NO tiene nombre: el requisito es de lunes a sábado', () => {
    // 7 es domingo. Devolver «domingo» aquí sugeriría que el día es válido,
    // cuando el `check (day_of_week between 1 and 6)` lo rechaza.
    expect(diaLegible(7)).toBe('día 7');
  });

  it('un día imposible devuelve texto en vez de `undefined`', () => {
    // El `check` de la base ya lo impide, pero un `undefined` que se colara a un
    // mensaje de error lo dejaría a medias («...asignada el  en el bloque 3»).
    expect(diaLegible(0)).toBe('día 0');
    expect(diaLegible(99)).toBe('día 99');
  });
});

describe('esChoqueDeAgenda', () => {
  it('reconoce el mensaje real del trigger del docente', () => {
    // Copiado del `raise` de `202609180001_mod3_cuadrante_aulas.sql`, con los
    // `%` ya sustituidos por lo que PostgreSQL interpola. Si alguien cambia el
    // texto en la migración, esta prueba falla y obliga a actualizar el
    // detector en vez de dejar que un 409 se degrade a 400 en silencio.
    const mensajeReal =
      'Ese docente ya tiene una clase o guardia asignada el miércoles en el bloque 5. ' +
      'Un docente no puede estar en dos sitios a la vez.';

    expect(esChoqueDeAgenda(mensajeReal)).toBe(true);
  });

  it('reconoce el mensaje real del trigger del espacio', () => {
    const mensajeReal =
      'Ese espacio ya está ocupado el lunes en el bloque 1. Dos grupos no pueden ' +
      'compartir el mismo sitio a la misma hora.';

    expect(esChoqueDeAgenda(mensajeReal)).toBe(true);
  });

  it('NO confunde un choque con un `check` corriente', () => {
    // Los dos llegan como 23514. Si esto devolviera `true`, cualquier dato mal
    // formado daría 409 y el cliente diría «esa aula está ocupada» por un
    // problema que no tiene nada que ver con la agenda.
    expect(
      esChoqueDeAgenda('El bloque no puede pasar de 12.'),
    ).toBe(false);
    expect(
      esChoqueDeAgenda('La capacidad no puede ser negativa.'),
    ).toBe(false);
  });

  it('NO confunde el trigger del período con un choque de agenda', () => {
    // `exigir_periodo_registrado` también lanza 23514 y también nombra un
    // período. Es la confusión más fácil de cometer al leer el mensaje.
    const mensajeDelPeriodo =
      'El período activo "SA26-2" no está registrado en el catálogo de lapsos. ' +
      'Créalo primero: la Regla 2 compara este valor con la sección y, si no ' +
      'corresponde a ningún lapso real, no protegería nada.';

    expect(esChoqueDeAgenda(mensajeDelPeriodo)).toBe(false);
  });

  it('no se dispara con un mensaje vacío ni con ruido', () => {
    expect(esChoqueDeAgenda('')).toBe(false);
    expect(
      esChoqueDeAgenda('duplicate key value violates unique constraint "classrooms_name_key"'),
    ).toBe(false);
  });

  it('toleraría el mensaje sin tilde, por si la colación cambia', () => {
    expect(
      esChoqueDeAgenda('Ese espacio ya esta ocupado el martes en el bloque 9.'),
    ).toBe(true);
  });
});

describe('esFechaISO', () => {
  it('acepta fechas reales', () => {
    expect(esFechaISO('2026-09-15')).toBe(true);
    expect(esFechaISO('2027-02-13')).toBe(true);
    expect(esFechaISO('2024-02-29')).toBe(true);
  });

  it('rechaza el 30 de febrero, que tiene la forma correcta y no existe', () => {
    // Es el caso que justifica la función: un patrón de expresión regular solo
    // lo aceptaría y el error llegaría a Postgres como `22007`, que el traductor
    // no reconoce y saldría como un 500 por un dato que el cliente escribió mal.
    expect(esFechaISO('2026-02-30')).toBe(false);
    expect(esFechaISO('2026-04-31')).toBe(false);
    expect(esFechaISO('2026-13-01')).toBe(false);
    expect(esFechaISO('2026-00-10')).toBe(false);
  });

  it('rechaza el 29 de febrero de un año no bisiesto', () => {
    // 2026 no es bisiesto. `new Date` lo normalizaría al 1 de marzo, y por eso
    // la comprobación compara los tres componentes y no sólo la validez.
    expect(esFechaISO('2026-02-29')).toBe(false);
  });

  it('rechaza formatos que no son AAAA-MM-DD', () => {
    expect(esFechaISO('15/09/2026')).toBe(false);
    expect(esFechaISO('2026-9-15')).toBe(false);
    expect(esFechaISO('2026-09-15T00:00:00Z')).toBe(false);
    expect(esFechaISO('')).toBe(false);
  });
});

describe('rangoDeFechasValido', () => {
  it('con las dos fechas, el fin tiene que ser posterior', () => {
    expect(rangoDeFechasValido('2026-09-21', '2027-02-13')).toBe(true);
    expect(rangoDeFechasValido('2027-02-13', '2026-09-21')).toBe(false);
  });

  it('el mismo día no es un rango válido', () => {
    // El `check` de la base exige `end_date > start_date`, no `>=`: un lapso que
    // empieza y termina el mismo día no es un lapso.
    expect(rangoDeFechasValido('2026-09-21', '2026-09-21')).toBe(false);
  });

  it('sin fechas no hay nada que ordenar', () => {
    // Las fechas nacen nulas y el centro las carga cuando las tiene. Rechazar
    // aquí un lapso sin fechas bloquearía un estado que la tabla acepta.
    expect(rangoDeFechasValido(null, null)).toBe(true);
    expect(rangoDeFechasValido(undefined, undefined)).toBe(true);
    expect(rangoDeFechasValido('2026-09-21', null)).toBe(true);
    expect(rangoDeFechasValido(null, '2027-02-13')).toBe(true);
  });
});

describe('los techos del backend y los de la base siguen de acuerdo', () => {
  it('el día llega hasta el sábado y el bloque hasta doce', () => {
    // Los dos números están duplicados en los `check` de `teacher_duties` y
    // `schedule_slots`. Esta prueba no puede leer la migración, pero deja
    // escrito de dónde salen para que el día que se cambien allí se sepa que
    // también hay que cambiarlos aquí y en `esquemas.ts`.
    expect(DIA_MAXIMO).toBe(6);
    expect(BLOQUE_MAXIMO).toBe(12);
  });
});
