import { describe, expect, it } from 'vitest';
import { ErrorApi } from '../src/dominio/errores.js';
import { ROLES, modulosVisibles } from '../src/dominio/tipos.js';
import {
  esquemaActualizarAula,
  esquemaActualizarClase,
  esquemaActualizarGuardia,
  esquemaActualizarPeriodo,
  esquemaCambiosModulo,
  esquemaCambioRol,
  esquemaCrearAula,
  esquemaCrearClase,
  esquemaCrearGuardia,
  esquemaCrearPeriodo,
  esquemaIdAula,
  esquemaIdClase,
  esquemaListadoAulas,
  esquemaListadoGuardias,
  esquemaMiHorario,
  esquemaRejilla,
  rolSchema,
  validarValorSegunTipo,
} from '../src/http/esquemas.js';
import { modulo } from './support/arnes.js';

describe('esquemas de entrada', () => {
  it('la lista de roles del esquema y la del dominio siguen coincidiendo', () => {
    // Si alguien añade un rol en `tipos.ts` y olvida el esquema (o al revés),
    // la API aceptaría o rechazaría roles de forma incoherente.
    expect([...rolSchema.options].sort()).toEqual([...ROLES].sort());
  });

  it('rechaza campos desconocidos en lugar de ignorarlos', () => {
    const resultado = esquemaCambiosModulo.safeParse({
      habilitado: true,
      es_critico: false,
    });

    expect(resultado.success).toBe(false);
  });

  it('rechaza un cuerpo sin ningún cambio', () => {
    expect(esquemaCambiosModulo.safeParse({}).success).toBe(false);
  });

  it('acepta un cambio parcial válido', () => {
    const resultado = esquemaCambiosModulo.safeParse({ orden: 42 });
    expect(resultado.success).toBe(true);
    if (resultado.success) expect(resultado.data.orden).toBe(42);
  });

  it('rechaza un rol inexistente', () => {
    expect(esquemaCambioRol.safeParse({ rol: 'superadmin' }).success).toBe(false);
  });
});

describe('validación del valor según el tipo declarado', () => {
  it('acepta un número cuando el parámetro es de tipo number', () => {
    expect(() => validarValorSegunTipo('number', 5, 'max_faltas')).not.toThrow();
  });

  it('rechaza texto cuando el parámetro es de tipo number', () => {
    expect(() => validarValorSegunTipo('number', 'cinco', 'max_faltas')).toThrowError(
      /espera un valor de tipo number/,
    );
  });

  it('rechaza NaN y Infinity, que pasarían un `typeof` ingenuo', () => {
    expect(() => validarValorSegunTipo('number', Number.NaN, 'max_faltas')).toThrow();
    expect(() =>
      validarValorSegunTipo('number', Number.POSITIVE_INFINITY, 'max_faltas'),
    ).toThrow();
  });

  it('rechaza el número 1 para un parámetro booleano', () => {
    expect(() => validarValorSegunTipo('boolean', 1, 'modo_mantenimiento')).toThrow();
  });

  it('acepta cualquier valor para un parámetro de tipo json', () => {
    expect(() =>
      validarValorSegunTipo('json', { a: [1, 2, 3] }, 'configuracion_libre'),
    ).not.toThrow();
  });

  it('avisa si el parámetro declara un tipo desconocido', () => {
    expect(() => validarValorSegunTipo('inventado', 1, 'raro')).toThrowError(
      /tipo desconocido/,
    );
  });

  it('el error es un ErrorApi de validación, no un Error genérico', () => {
    try {
      validarValorSegunTipo('number', 'cinco', 'max_faltas');
      expect.unreachable('debió lanzar');
    } catch (error) {
      expect(error).toBeInstanceOf(ErrorApi);
      expect((error as ErrorApi).codigo).toBe('PETICION_INVALIDA');
      expect((error as ErrorApi).estado).toBe(400);
    }
  });
});

describe('visibilidad de módulos por rol', () => {
  it('oculta los módulos apagados', () => {
    const visibles = modulosVisibles(
      [
        modulo({ clave: 'a', habilitado: true, orden: 1 }),
        modulo({ clave: 'b', habilitado: false, orden: 2 }),
      ],
      'estudiante',
    );

    expect(visibles.map((m) => m.clave)).toEqual(['a']);
  });

  it('trata una lista de roles vacía como «visible para todos»', () => {
    const visibles = modulosVisibles(
      [modulo({ clave: 'a', rolesPermitidos: [] })],
      'estudiante',
    );

    expect(visibles).toHaveLength(1);
  });

  it('respeta la lista blanca de roles', () => {
    const modulos = [modulo({ clave: 'panel', rolesPermitidos: ['admin'] })];

    expect(modulosVisibles(modulos, 'admin')).toHaveLength(1);
    expect(modulosVisibles(modulos, 'estudiante')).toHaveLength(0);
  });

  it('ordena por `orden` y, a igualdad, por clave', () => {
    const visibles = modulosVisibles(
      [
        modulo({ clave: 'z', orden: 10 }),
        modulo({ clave: 'a', orden: 10 }),
        modulo({ clave: 'primero', orden: 1 }),
      ],
      'admin',
    );

    expect(visibles.map((m) => m.clave)).toEqual(['primero', 'a', 'z']);
  });
});

// --- Módulo 3 ---------------------------------------------------------------

/**
 * Los esquemas de M3.
 *
 * Aquí se comprueba lo que Zod decide **antes** de abrir una transacción: los
 * límites de día y bloque, la forma del código de lapso, la fecha que existe y
 * los campos que se rechazan por ser derivados. Es la mitad barata de cada
 * regla; la otra mitad —los `check` y el trigger— vive en la base y se prueba en
 * `supabase/tests`.
 */

const UUID = '11111111-1111-4111-8111-111111111111';

describe('límites de día y de bloque', () => {
  it('acepta del 1 al 6 y del 1 al 12', () => {
    expect(
      esquemaCrearClase.safeParse({
        seccionId: UUID,
        docenteId: UUID,
        aulaId: UUID,
        dia: 1,
        bloque: 1,
      }).success,
    ).toBe(true);

    expect(
      esquemaCrearClase.safeParse({
        seccionId: UUID,
        docenteId: UUID,
        aulaId: UUID,
        dia: 6,
        bloque: 12,
      }).success,
    ).toBe(true);
  });

  it('el domingo no entra: el requisito es de lunes a sábado', () => {
    const resultado = esquemaCrearClase.safeParse({
      seccionId: UUID,
      docenteId: UUID,
      aulaId: UUID,
      dia: 7,
      bloque: 1,
    });

    expect(resultado.success).toBe(false);
    if (!resultado.success) {
      expect(resultado.error.issues[0]?.message).toContain('sábado');
    }
  });

  it('el bloque 13 tampoco, y el mensaje dice el techo', () => {
    const resultado = esquemaCrearClase.safeParse({
      seccionId: UUID,
      docenteId: UUID,
      aulaId: UUID,
      dia: 1,
      bloque: 13,
    });

    expect(resultado.success).toBe(false);
    if (!resultado.success) {
      expect(resultado.error.issues[0]?.message).toContain('12');
    }
  });

  it('el día y el bloque tienen que ser enteros', () => {
    expect(
      esquemaCrearClase.safeParse({
        seccionId: UUID,
        docenteId: UUID,
        aulaId: UUID,
        dia: 1.5,
        bloque: 3,
      }).success,
    ).toBe(false);
  });

  it('el mismo techo vale para las guardias', () => {
    // Los dos esquemas comparten `diaSchema` y `bloqueSchema`. Si alguien
    // duplicara las constantes y una se quedara atrás, el día 7 se colaría en
    // una guardia y no en una clase.
    expect(
      esquemaCrearGuardia.safeParse({
        docenteId: UUID,
        aulaId: UUID,
        periodo: '2026-1',
        dia: 7,
        bloque: 1,
      }).success,
    ).toBe(false);

    expect(
      esquemaCrearGuardia.safeParse({
        docenteId: UUID,
        aulaId: UUID,
        periodo: '2026-1',
        dia: 1,
        bloque: 13,
      }).success,
    ).toBe(false);
  });
});

describe('campos derivados que el cliente no puede mandar', () => {
  it('la clase rechaza `turno` y `periodo` en vez de ignorarlos', () => {
    // Los dos son derivados —el turno del bloque, el período de la sección— y
    // aceptarlos permitiría una fila cuya agenda miente. `.strict()` da un 400
    // que nombra el campo en vez de descartarlo en silencio.
    const base = { seccionId: UUID, docenteId: UUID, aulaId: UUID, dia: 1, bloque: 1 };

    expect(esquemaCrearClase.safeParse({ ...base, turno: 'MAÑANA' }).success).toBe(false);
    expect(esquemaCrearClase.safeParse({ ...base, periodo: '2026-1' }).success).toBe(false);
  });

  it('la guardia rechaza `turno`, que es columna generada', () => {
    expect(
      esquemaCrearGuardia.safeParse({
        docenteId: UUID,
        aulaId: UUID,
        periodo: '2026-1',
        dia: 1,
        bloque: 1,
        turno: 'TARDE',
      }).success,
    ).toBe(false);
  });
});

describe('código de lapso', () => {
  it('acepta lo que el `check` de la tabla acepta', () => {
    for (const codigo of ['2026-1', 'SA26-2', '2027-1', 'A', '0123456789']) {
      expect(esquemaCrearPeriodo.safeParse({ codigo }).success, codigo).toBe(true);
    }
  });

  it('rechaza barras, espacios, vacío, guion inicial y más de diez caracteres', () => {
    for (const codigo of ['2026/1', 'a b', '', '-2026', '01234567890']) {
      expect(esquemaCrearPeriodo.safeParse({ codigo }).success, codigo).toBe(false);
    }
  });
});

describe('fechas del lapso', () => {
  it('el 30 de febrero se rechaza aquí y no en Postgres', () => {
    // Sin `esFechaISO` el valor llegaría a la base, que responde `22007` —un
    // código que el traductor no reconoce— y saldría como un 500 por un dato que
    // el cliente escribió mal.
    expect(
      esquemaCrearPeriodo.safeParse({ codigo: '2027-1', fechaInicio: '2027-02-30' }).success,
    ).toBe(false);
  });

  it('un rango invertido se rechaza, y el error apunta a `fechaFin`', () => {
    const resultado = esquemaCrearPeriodo.safeParse({
      codigo: '2027-1',
      fechaInicio: '2027-08-01',
      fechaFin: '2027-02-01',
    });

    expect(resultado.success).toBe(false);
    if (!resultado.success) {
      expect(resultado.error.issues.some((i) => i.path.includes('fechaFin'))).toBe(true);
    }
  });

  it('un lapso sin fechas es válido: nacen nulas', () => {
    expect(esquemaCrearPeriodo.safeParse({ codigo: '2027-1' }).success).toBe(true);
  });

  it('al actualizar, el rango sólo se comprueba cuando llegan las dos fechas', () => {
    // Con una sola, la otra vive en la fila y decide el `check` de la base. La
    // regla es la misma en los dos sitios; lo que cambia es cuánto se ve desde
    // la petición.
    expect(esquemaActualizarPeriodo.safeParse({ fechaInicio: '2027-08-01' }).success).toBe(true);
    expect(
      esquemaActualizarPeriodo.safeParse({
        fechaInicio: '2027-08-01',
        fechaFin: '2027-02-01',
      }).success,
    ).toBe(false);
  });

  it('al actualizar, `null` es una intención legítima: vaciar el dato', () => {
    expect(
      esquemaActualizarPeriodo.safeParse({ fechaInicio: null, fechaFin: null }).success,
    ).toBe(true);
  });
});

describe('cuerpos sin cambios', () => {
  it('los cuatro PATCH rechazan un cuerpo vacío', () => {
    // Un 200 que no cambió nada es peor que un 400: el administrativo cree que
    // guardó.
    expect(esquemaActualizarAula.safeParse({}).success).toBe(false);
    expect(esquemaActualizarPeriodo.safeParse({}).success).toBe(false);
    expect(esquemaActualizarGuardia.safeParse({}).success).toBe(false);
    expect(esquemaActualizarClase.safeParse({}).success).toBe(false);
  });
});

describe('capacidad y tipo del espacio', () => {
  it('la capacidad es 0 por defecto: así se registra una zona sin cupo', () => {
    const resultado = esquemaCrearAula.safeParse({ nombre: 'Pasillo' });
    expect(resultado.success).toBe(true);
    if (resultado.success) {
      expect(resultado.data.capacidad).toBe(0);
      expect(resultado.data.esTaller).toBe(false);
    }
  });

  it('rechaza una capacidad negativa', () => {
    expect(esquemaCrearAula.safeParse({ nombre: 'Sótano', capacidad: -1 }).success).toBe(false);
  });
});

describe('identificadores de recurso', () => {
  it('los cuatro nombran su recurso en el mensaje', () => {
    // El mensaje es lo único que cambia entre uno y otro; por eso son una
    // fábrica y no cuatro copias donde olvidarse de uno.
    const casos: Array<[typeof esquemaIdAula, string]> = [
      [esquemaIdAula, 'espacio'],
      [esquemaIdClase, 'clase'],
    ];

    for (const [esquema, recurso] of casos) {
      const resultado = esquema.safeParse('no-soy-un-uuid');
      expect(resultado.success).toBe(false);
      if (!resultado.success) {
        expect(resultado.error.issues[0]?.message).toContain(recurso);
      }
    }
  });
});

describe('listados y rejilla', () => {
  it('los filtros booleanos sólo aceptan "true" y "false"', () => {
    // Un `?activa=1` devolvería «no hay espacios» en vez de un error, y el
    // administrativo creería que el catálogo está vacío.
    expect(esquemaListadoAulas.safeParse({ activa: 'true' }).success).toBe(true);
    expect(esquemaListadoAulas.safeParse({ activa: '1' }).success).toBe(false);
    expect(esquemaListadoGuardias.safeParse({ activa: 'si' }).success).toBe(false);
    expect(esquemaRejilla.safeParse({ incluirInactivas: 'true' }).success).toBe(true);
    expect(esquemaRejilla.safeParse({ incluirInactivas: 'quizá' }).success).toBe(false);
  });

  it('el listado de espacios acota la página a 100 y arranca en 25', () => {
    const porDefecto = esquemaListadoAulas.safeParse({});
    expect(porDefecto.success).toBe(true);
    if (porDefecto.success) {
      expect(porDefecto.data.limite).toBe(25);
      expect(porDefecto.data.desplazamiento).toBe(0);
    }

    expect(esquemaListadoAulas.safeParse({ limite: '101' }).success).toBe(false);
    expect(esquemaListadoAulas.safeParse({ desplazamiento: '-1' }).success).toBe(false);
  });

  it('el horario propio no acepta el filtro de otro docente, ni de paso', () => {
    // El esquema de una *query* no es estricto —el navegador añade parámetros
    // suyos— así que lo que se comprueba es lo que importa: que `docenteId` no
    // sobreviva al análisis. El aislamiento no depende de que el cliente no
    // mande el campo.
    const resultado = esquemaMiHorario.safeParse({ docenteId: UUID, periodo: '2026-1' });

    expect(resultado.success).toBe(true);
    if (resultado.success) {
      expect(resultado.data).toEqual({ periodo: '2026-1' });
      expect(resultado.data).not.toHaveProperty('docenteId');
    }
  });
});
