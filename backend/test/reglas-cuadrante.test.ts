import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
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

// --- Los espejos, comprobados contra la migración ---------------------------

/**
 * La migración de M3, leída como texto.
 *
 * Estas pruebas existen porque `turnoDeBloque`, `diaLegible` y `esChoqueDeAgenda`
 * son **espejos** de funciones y mensajes que viven en SQL. Un espejo que nadie
 * compara se desvía: es la lección de R-20 y la razón de que
 * `esBloqueoPorPensumEnUso` tenga su propia prueba con el mensaje real.
 *
 * Copiar el mensaje a mano en la prueba (como se hacía antes) demuestra que el
 * detector reconoce **la copia**, no el original. Aquí se extrae del archivo que
 * de verdad se aplica a la base, así que si alguien reescribe un `raise
 * exception` o mueve la frontera de turnos, esto falla en vez de quedarse
 * verde sobre dos textos que ya no coinciden.
 */
const AQUI = dirname(fileURLToPath(import.meta.url));
const MIGRACION_M3 = join(
  AQUI,
  '..',
  '..',
  'supabase',
  'migrations',
  '202609180001_mod3_cuadrante_aulas.sql',
);
const SQL = readFileSync(MIGRACION_M3, 'utf8');

/** El cuerpo `$$ … $$` de una función `create or replace function <nombre>`. */
function cuerpoDeFuncion(nombre: string): string {
  const patron = new RegExp(
    `create or replace function public\\.${nombre}\\b[\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$`,
    'i',
  );
  const coincidencia = patron.exec(SQL);
  if (!coincidencia) throw new Error(`no se encontró la función ${nombre} en ${MIGRACION_M3}`);
  return coincidencia[1] ?? '';
}

/** Los literales de todos los `raise exception`, sin el `%` interpolado. */
const MENSAJES_LANZADOS = [...SQL.matchAll(/raise exception\s*'((?:[^']|'')*)'/g)].map(
  (m) => (m[1] ?? '').replace(/''/g, "'"),
);

/** Sustituye los `%` en orden, como hace `raise … , valor1, valor2`. */
function interpolar(mensaje: string, valores: string[]): string {
  let i = 0;
  return mensaje.replace(/%/g, () => valores[i++] ?? '%');
}

describe('el corte de turnos del SQL y el de TypeScript son el mismo', () => {
  it('`turno_de_bloque` corta exactamente donde corta `turnoDeBloque`', () => {
    // El comentario de `turnoDeBloque` dice que «la prueba de esta función es la
    // que avisa de que los dos sitios se separaron». Antes no podía: comparaba
    // 6 y 7 contra constantes propias. Ahora el corte se lee del SQL.
    const cuerpo = cuerpoDeFuncion('turno_de_bloque');
    const corte = /p_bloque\s*<=\s*(\d+)\s+then\s+'([^']+)'\s+else\s+'([^']+)'/i.exec(cuerpo);

    expect(corte, 'no se pudo leer el corte en `turno_de_bloque`').not.toBeNull();
    const [, limite, manana, tarde] = corte as RegExpExecArray;

    expect(Number(limite)).toBe(6);
    expect(manana).toBe('MAÑANA');
    expect(tarde).toBe('TARDE');

    // Y el espejo de TypeScript coincide en TODO el rango, no sólo en la
    // frontera: si alguien cambiara el SQL a `<= 7`, esto lo caza.
    for (let bloque = 1; bloque <= BLOQUE_MAXIMO; bloque += 1) {
      const esperado = bloque <= Number(limite) ? manana : tarde;
      expect(turnoDeBloque(bloque), `bloque ${bloque}`).toBe(esperado);
    }
  });
});

describe('los nombres de día del SQL y los de TypeScript son los mismos', () => {
  it('`dia_legible` nombra los mismos seis días y el mismo respaldo', () => {
    const cuerpo = cuerpoDeFuncion('dia_legible');

    const nombres = new Map<number, string>();
    for (const coincidencia of cuerpo.matchAll(/when\s+(\d+)\s+then\s+'([^']+)'/g)) {
      nombres.set(Number(coincidencia[1]), coincidencia[2] ?? '');
    }

    expect(nombres.size).toBe(6);
    for (const [dia, nombre] of nombres) {
      expect(diaLegible(dia), `día ${dia}`).toBe(nombre);
    }

    // El respaldo del `else`: «día N», y no `undefined`. El domingo (7) es el
    // caso que lo ejercita de verdad.
    expect(cuerpo).toMatch(/else\s+'día '\s*\|\|/);
    expect(diaLegible(7)).toBe('día 7');
  });
});

describe('`esChoqueDeAgenda` reconoce los mensajes REALES de la migración', () => {
  it('la migración lanza exactamente cuatro mensajes, y dos son de colisión', () => {
    // Cuatro y no más: `exigir_periodo_registrado` (23514), el docente (23514),
    // el espacio (23514) y «la sección no existe» (23503). Si alguien añade un
    // quinto `raise exception`, esta prueba lo nota y obliga a decidir si el
    // detector tiene que reconocerlo.
    expect(MENSAJES_LANZADOS).toHaveLength(4);
    expect(MENSAJES_LANZADOS.filter(esChoqueDeAgenda)).toHaveLength(2);
  });

  it('tampoco reconoce el de «la sección no existe»', () => {
    // Éste ni siquiera compite: lanza 23503, que `traducirError` ya convierte en
    // un 400 REFERENCIA_INVALIDA. Se comprueba igual para dejar constancia de
    // que el detector no lo captura por accidente.
    const mensaje = MENSAJES_LANZADOS.find((m) => /no existe/.test(m));
    expect(mensaje, 'no se encontró el `raise` de la sección').toBeDefined();

    expect(esChoqueDeAgenda(interpolar(mensaje as string, ['a1b2c3d4']))).toBe(false);
  });

  it('reconoce el del DOCENTE con el día y el bloque ya interpolados', () => {
    const mensaje = MENSAJES_LANZADOS.find((m) => /ya tiene una clase o guardia/.test(m));
    expect(mensaje, 'no se encontró el `raise` del docente').toBeDefined();

    // `raise …, v_dia, p_bloque`: el primero es el día legible, el segundo el bloque.
    const real = interpolar(mensaje as string, [diaLegible(1), '1']);

    expect(real).toContain('ya tiene una clase o guardia asignada el lunes en el bloque 1');
    expect(esChoqueDeAgenda(real)).toBe(true);
  });

  it('reconoce el del ESPACIO con el día y el bloque ya interpolados', () => {
    const mensaje = MENSAJES_LANZADOS.find((m) => /ya est[aá] ocupado/.test(m));
    expect(mensaje, 'no se encontró el `raise` del espacio').toBeDefined();

    const real = interpolar(mensaje as string, [diaLegible(6), '12']);

    expect(real).toContain('ya está ocupado el sábado en el bloque 12');
    expect(esChoqueDeAgenda(real)).toBe(true);
  });

  it('NO reconoce el del PERÍODO, que también es un 23514', () => {
    // Es la confusión más fácil de cometer: los tres lanzan 23514, y el del
    // período también habla de un lapso. Si el detector lo aceptara, declarar un
    // lapso inexistente daría 409 en vez de 400.
    const mensaje = MENSAJES_LANZADOS.find((m) => /no está registrado en el catálogo/.test(m));
    expect(mensaje, 'no se encontró el `raise` del período').toBeDefined();

    const real = interpolar(mensaje as string, ['SA26-2']);
    expect(esChoqueDeAgenda(real)).toBe(false);
  });

  it('los tres lanzan 23514, que es por lo que hay que distinguirlos por texto', () => {
    // Si alguno usara otro `errcode`, la distinción por mensaje sobraría para
    // ese caso y habría que replantearla.
    const codigos = [...SQL.matchAll(/using errcode = '(\w+)'/g)].map((m) => m[1]);
    expect(codigos.filter((c) => c === '23514').length).toBeGreaterThanOrEqual(3);
  });
});

describe('los techos del backend y los de la base siguen de acuerdo', () => {
  it('el día llega hasta el sábado y el bloque hasta doce, en los dos sitios', () => {
    // Los `check` de `teacher_duties` y `schedule_slots` llevan los mismos dos
    // números. Se leen del SQL para que no puedan separarse.
    expect(DIA_MAXIMO).toBe(6);
    expect(BLOQUE_MAXIMO).toBe(12);

    const checks = [...SQL.matchAll(/check \(day_of_week between 1 and (\d+)\)/g)].map((m) =>
      Number(m[1]),
    );
    expect(checks.length).toBeGreaterThanOrEqual(2);
    expect(checks.every((limite) => limite === DIA_MAXIMO)).toBe(true);

    const bloques = [...SQL.matchAll(/check \(block between 1 and (\d+)\)/g)].map((m) =>
      Number(m[1]),
    );
    expect(bloques.length).toBeGreaterThanOrEqual(2);
    expect(bloques.every((limite) => limite === BLOQUE_MAXIMO)).toBe(true);
  });
});
