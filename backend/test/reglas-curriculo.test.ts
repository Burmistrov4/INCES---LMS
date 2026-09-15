import { describe, expect, it } from 'vitest';
import {
  agruparPensum,
  esBloqueoPorPensumEnUso,
  materiaRepetida,
  pensumEditable,
} from '../src/dominio/reglas-curriculo.js';
import type { EntradaPensum } from '../src/dominio/tipos.js';

/**
 * Las reglas del currículo de M2, sin montar HTTP ni repositorios.
 *
 * Se prueban aquí los casos que la API casi nunca alcanza —un pensum con
 * huecos, uno con 40 materias y una repetida al final— porque son exactamente
 * los que aparecen el día que alguien pega una lista desde una hoja de cálculo.
 */

const entrada = (materiaId: string, periodo = 1): EntradaPensum => ({ materiaId, periodo });

describe('agruparPensum', () => {
  it('agrupa por período y los ordena', () => {
    const grupos = agruparPensum([
      entrada('c', 3),
      entrada('a', 1),
      entrada('b', 2),
    ]);

    expect(grupos.map((g) => g.periodo)).toEqual([1, 2, 3]);
    expect(grupos[0]?.materias.map((m) => m.materiaId)).toEqual(['a']);
  });

  it('NO rellena los períodos que faltan: [1, 2, 5] son tres grupos, no cinco', () => {
    // Es el caso que importa. Rellenar los huecos haría que la pantalla pintara
    // un «Período 3» y un «Período 4» vacíos, como si al pensum le faltara algo.
    const grupos = agruparPensum([
      entrada('a', 1),
      entrada('b', 2),
      entrada('c', 5),
    ]);

    expect(grupos).toHaveLength(3);
    expect(grupos.map((g) => g.periodo)).toEqual([1, 2, 5]);
  });

  it('un CURSO_LIBRE de un solo período devuelve un solo grupo', () => {
    expect(agruparPensum([entrada('a', 1), entrada('b', 1)])).toEqual([
      { periodo: 1, materias: [entrada('a', 1), entrada('b', 1)] },
    ]);
  });

  it('conserva el orden de llegada dentro de cada período', () => {
    // El servidor no reordena lo que el administrativo escribió: si puso
    // Algorítmica antes que Matemática, así se queda.
    const grupos = agruparPensum([
      entrada('algoritmica', 1),
      entrada('matematica', 1),
      entrada('fisica', 1),
    ]);

    expect(grupos[0]?.materias.map((m) => m.materiaId)).toEqual([
      'algoritmica',
      'matematica',
      'fisica',
    ]);
  });

  it('un pensum vacío devuelve cero grupos, no uno vacío', () => {
    expect(agruparPensum([])).toEqual([]);
  });

  it('no muta el arreglo que recibe', () => {
    const original = [entrada('a', 2), entrada('b', 1)];
    const copia = [...original];
    agruparPensum(original);
    expect(original).toEqual(copia);
  });
});

describe('materiaRepetida', () => {
  it('devuelve null cuando no hay repetidas', () => {
    expect(materiaRepetida([entrada('a', 1), entrada('b', 1), entrada('c', 2)])).toBeNull();
  });

  it('devuelve el id repetido, no un booleano', () => {
    // El mensaje tiene que nombrar la materia: un administrador con 40 materias
    // en el pensum necesita saber cuál se repite.
    expect(materiaRepetida([entrada('a', 1), entrada('b', 1), entrada('a', 2)])).toBe('a');
  });

  it('la repetición cuenta aunque estén en períodos distintos', () => {
    // La misma materia en dos períodos es un error de captura, no un pensum
    // válido: la base tiene `unique (program_id, subject_id)`.
    expect(materiaRepetida([entrada('a', 1), entrada('a', 4)])).toBe('a');
  });

  it('detecta la repetición al final de una lista larga', () => {
    const larga = Array.from({ length: 40 }, (_, i) => entrada(`m${i}`, 1));
    larga.push(entrada('m7', 2));
    expect(materiaRepetida(larga)).toBe('m7');
  });

  it('un pensum vacío no tiene repetidas', () => {
    expect(materiaRepetida([])).toBeNull();
  });
});

describe('pensumEditable (Regla 2)', () => {
  it('sin secciones activas, el pensum se puede tocar', () => {
    expect(pensumEditable(0)).toBe(true);
  });

  it('con una sola sección activa, ya no', () => {
    expect(pensumEditable(1)).toBe(false);
  });

  it('con muchas, tampoco', () => {
    expect(pensumEditable(12)).toBe(false);
  });
});

describe('esBloqueoPorPensumEnUso', () => {
  it('reconoce el mensaje real del trigger de la Regla 2', () => {
    // Este texto está copiado del `raise` de
    // `202609160001_resolucion_d12_d13.sql`, con el `%` ya sustituido por los
    // valores que PostgreSQL interpola. Si alguien cambia el mensaje en la
    // migración, esta prueba falla y obliga a actualizar el detector.
    const mensajeReal =
      'No se puede modificar el pensum: el programa tiene 2 sección(es) activa(s) ' +
      'en el período 2026-1. Archive esas secciones primero, o clone el programa y ' +
      'cree una versión nueva del pensum.';

    expect(esBloqueoPorPensumEnUso(mensajeReal)).toBe(true);
  });

  it('NO confunde la Regla 1 con la Regla 2', () => {
    // Los dos triggers lanzan 23514. Si esto devolviera `true`, publicar un
    // programa vacío daría 409 en vez de 400, y el cliente mostraría el
    // mensaje equivocado.
    const mensajeRegla1 =
      'Una carrera activa no puede quedarse sin materias. Añada al menos una al ' +
      'pensum o póngala en borrador (is_active = false).';

    expect(esBloqueoPorPensumEnUso(mensajeRegla1)).toBe(false);
  });

  it('no se dispara con un mensaje vacío ni con ruido', () => {
    expect(esBloqueoPorPensumEnUso('')).toBe(false);
    expect(esBloqueoPorPensumEnUso('duplicate key value violates unique constraint')).toBe(false);
  });

  it('toleraría el mensaje sin tilde, por si la colación cambia', () => {
    expect(esBloqueoPorPensumEnUso('tiene 1 seccion(es) activa(s) en el período 2026-1')).toBe(true);
  });
});
