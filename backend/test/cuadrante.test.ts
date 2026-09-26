import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import {
  AULA_TALLER,
  AULA_TEORICA,
  AULA_ZONA,
  CLASE_MIERCOLES,
  conToken,
  crearArnés,
  GUARDIA_LUNES,
  ID_AULA_TALLER,
  ID_AULA_TEORICA,
  ID_AULA_ZONA,
  ID_DOCENTE,
  ID_DOCENTE_2,
  ID_GUARDIA_LUNES,
  ID_PERIODO_2026_1,
  ID_PERIODO_2026_2,
  ID_SECCION_SA,
  ID_SECCION_SC,
  MODULOS_POR_DEFECTO,
  PERFIL_DOCENTE_2,
  PERFILES_POR_DEFECTO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
  TOKEN_DOCENTE,
  type Arnés,
} from './support/arnes.js';

/**
 * Las catorce rutas del Módulo 3, de punta a punta sobre el arnés en memoria.
 *
 * Lo que se comprueba aquí es el **contrato HTTP**: control de acceso, códigos
 * de estado, validación de Zod, forma de las respuestas y —lo que más importa—
 * el 409 CHOQUE_DE_AGENDA en sus cuatro cruces posibles: docente contra clase,
 * docente contra guardia, espacio contra clase y espacio contra guardia. Esos
 * cuatro casos son exactamente lo que un `unique` no habría podido expresar, así
 * que son los que hay que ejercitar por el camino real.
 *
 * El arnés sustituye el repositorio entero: lo que ocurre *dentro* —que el
 * `23514` del trigger se traduzca bien contra la base real— no se puede ver
 * desde aquí y le corresponde al humo contra Supabase.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

/** Un UUID válido que no existe en ningún estado del arnés. */
const ID_INEXISTENTE = 'ffffffff-0000-4000-8000-000000000000';

const RUTAS_ADMIN = [
  { method: 'GET' as const, url: '/api/v1/admin/aulas' },
  { method: 'POST' as const, url: '/api/v1/admin/aulas' },
  { method: 'PATCH' as const, url: `/api/v1/admin/aulas/${ID_AULA_TALLER}` },
  { method: 'GET' as const, url: '/api/v1/admin/periodos' },
  { method: 'POST' as const, url: '/api/v1/admin/periodos' },
  { method: 'PATCH' as const, url: `/api/v1/admin/periodos/${ID_PERIODO_2026_1}` },
  { method: 'PUT' as const, url: `/api/v1/admin/periodos/${ID_PERIODO_2026_1}/vigente` },
  { method: 'GET' as const, url: '/api/v1/admin/guardias' },
  { method: 'POST' as const, url: '/api/v1/admin/guardias' },
  { method: 'PATCH' as const, url: `/api/v1/admin/guardias/${ID_GUARDIA_LUNES}` },
  { method: 'GET' as const, url: '/api/v1/admin/cuadrante' },
  { method: 'POST' as const, url: '/api/v1/admin/cuadrante' },
  { method: 'PATCH' as const, url: `/api/v1/admin/cuadrante/${CLASE_MIERCOLES.id}` },
];

describe('control de acceso a las rutas del cuadrante', () => {
  it('exige sesión en las trece rutas de administración', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const ruta of RUTAS_ADMIN) {
      const respuesta = await app.inject({ ...ruta, headers: conToken(null) });
      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
    }
  });

  it('rechaza a un usuario autenticado que no es administrador', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const ruta of RUTAS_ADMIN) {
      const respuesta = await app.inject({ ...ruta, headers: conToken(TOKEN_ALUMNO) });
      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(403);
      expect(respuesta.json()).toMatchObject({ error: { codigo: 'SOLO_ADMIN' } });
    }
  });

  it('el horario propio exige sesión pero no rol de administrador', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const sinToken = await app.inject({ method: 'GET', url: '/api/v1/mi-horario' });
    expect(sinToken.statusCode).toBe(401);

    // Un estudiante entra: es justo el rol que más lo usa.
    const conAlumno = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(conAlumno.statusCode).toBe(200);
  });
});

// --- Aulas ------------------------------------------------------------------

describe('GET /api/v1/admin/aulas', () => {
  it('lista las aulas ordenadas por nombre y con el eco de la paginación', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      aulas: { nombre: string; capacidad: number; esTaller: boolean }[];
      total: number;
      limite: number;
      desplazamiento: number;
    };

    expect(cuerpo.total).toBe(3);
    expect(cuerpo.limite).toBe(25);
    expect(cuerpo.desplazamiento).toBe(0);
    expect(cuerpo.aulas.map((a) => a.nombre)).toEqual([
      'Aula Teórica 2',
      'Pasillo de talleres',
      'Taller de Soldadura Cabina A',
    ]);
  });

  it('el filtro por tipo separa taller, aula y zona sin solaparse', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const pedir = async (tipo: string): Promise<string[]> => {
      const respuesta = await app!.inject({
        method: 'GET',
        url: `/api/v1/admin/aulas?tipo=${tipo}`,
        headers: conToken(TOKEN_ADMIN),
      });
      expect(respuesta.statusCode).toBe(200);
      const cuerpo = respuesta.json() as { aulas: { nombre: string }[]; total: number };
      expect(cuerpo.total).toBe(cuerpo.aulas.length);
      return cuerpo.aulas.map((a) => a.nombre);
    };

    // Las tres formas son excluyentes y juntas cubren las tres aulas: si una se
    // solapara con otra, la suma no daría el total y el desplegable del
    // cuadrante ofrecería la misma aula en dos sitios.
    expect(await pedir('TALLER')).toEqual(['Taller de Soldadura Cabina A']);
    expect(await pedir('AULA')).toEqual(['Aula Teórica 2']);
    expect(await pedir('ZONA')).toEqual(['Pasillo de talleres']);
  });

  it('pagina de verdad: la segunda página trae lo que sobra, no todo otra vez', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/aulas?limite=2&desplazamiento=2',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { aulas: { nombre: string }[]; total: number };
    expect(cuerpo.total).toBe(3);
    expect(cuerpo.aulas.map((a) => a.nombre)).toEqual(['Taller de Soldadura Cabina A']);
  });

  it('busca por nombre sin distinguir mayúsculas', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/aulas?busqueda=CABINA',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { aulas: { nombre: string }[]; total: number };
    expect(cuerpo.total).toBe(1);
    expect(cuerpo.aulas[0]?.nombre).toBe('Taller de Soldadura Cabina A');
  });

  it('un tipo que no existe da 400 en vez de una lista vacía', async () => {
    // Devolver cero filas haría creer al administrativo que no hay talleres.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/aulas?tipo=TALLERES',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('POST /api/v1/admin/aulas', () => {
  it('crea un espacio y lo devuelve con 201', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Taller de Soldadura Cabina B', capacidad: 10, esTaller: true },
    });

    expect(respuesta.statusCode).toBe(201);
    const cuerpo = respuesta.json() as { aula: { id: string; nombre: string; activa: boolean } };
    expect(cuerpo.aula.nombre).toBe('Taller de Soldadura Cabina B');
    expect(cuerpo.aula.activa).toBe(true);
    expect(arnés.estado.aulas).toHaveLength(4);
  });

  it('la capacidad y el taller son opcionales: una zona se crea sin cupo', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Entrada del taller' },
    });

    expect(respuesta.statusCode).toBe(201);
    const cuerpo = respuesta.json() as { aula: { capacidad: number; esTaller: boolean } };
    expect(cuerpo.aula.capacidad).toBe(0);
    expect(cuerpo.aula.esTaller).toBe(false);
  });

  it('un nombre repetido da 409: dos espacios iguales son indistinguibles', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: AULA_TALLER.nombre },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'REGISTRO_DUPLICADO' } });
  });

  it('rechaza una capacidad negativa y un nombre vacío', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const negativa = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Sótano', capacidad: -3 },
    });
    expect(negativa.statusCode).toBe(400);

    const vacio = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: '   ' },
    });
    expect(vacio.statusCode).toBe(400);
  });

  it('rechaza campos desconocidos en lugar de ignorarlos', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Aula 9', cupo: 20 },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('PATCH /api/v1/admin/aulas/:id', () => {
  it('archiva un espacio con activa=false en vez de borrarlo', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/aulas/${ID_AULA_ZONA}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activa: false },
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { aula: { activa: boolean; nombre: string } };
    expect(cuerpo.aula.activa).toBe(false);
    // Archivar no borra: el nombre sigue ahí porque las clases históricas lo
    // citan y borrarlo dejaría el cuadrante con celdas sin referencia.
    expect(cuerpo.aula.nombre).toBe(AULA_ZONA.nombre);
    expect(arnés.estado.aulas).toHaveLength(3);
  });

  it('un cuerpo sin cambios da 400 en vez de un 200 que no hizo nada', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/aulas/${ID_AULA_ZONA}`,
      headers: conToken(TOKEN_ADMIN),
      payload: {},
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('un id que no existe da 404 con el recurso nombrado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/aulas/${ID_INEXISTENTE}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Aula fantasma' },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'AULA_INEXISTENTE' } });
  });

  it('un id que no es UUID da 400 y no llega a Postgres', async () => {
    // Sin el `.uuid()` de Zod, esto viajaría a Postgres, reventaría con `22P02`
    // y saldría como un 500: un error del cliente disfrazado de fallo del
    // servidor.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/aulas/no-soy-un-uuid',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Aula 1' },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

// --- Períodos ---------------------------------------------------------------

describe('GET /api/v1/admin/periodos', () => {
  it('devuelve los lapsos del más reciente al más antiguo, con el vigente marcado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/periodos',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      periodos: { codigo: string; vigente: boolean; activo: boolean }[];
    };

    expect(cuerpo.periodos.map((p) => p.codigo)).toEqual(['2026-2', '2026-1']);
    // `activo` y `vigente` son cosas distintas: los dos lapsos están abiertos,
    // pero sólo uno es el vigente. Es la distinción de R-19.
    expect(cuerpo.periodos.map((p) => p.activo)).toEqual([true, true]);
    expect(cuerpo.periodos.map((p) => p.vigente)).toEqual([false, true]);
  });
});

describe('POST /api/v1/admin/periodos', () => {
  it('crea un lapso cerrado y no vigente, y lo devuelve con 201', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/periodos',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        codigo: '2027-1',
        nombre: 'Lapso 2027-1',
        fechaInicio: '2027-02-20',
        fechaFin: '2027-07-30',
      },
    });

    expect(respuesta.statusCode).toBe(201);
    const cuerpo = respuesta.json() as {
      periodo: { codigo: string; activo: boolean; vigente: boolean };
    };
    expect(cuerpo.periodo.codigo).toBe('2027-1');
    // Nace cerrado: el vigente ya existe, y abrir un lapso es una decisión
    // aparte de declararlo vigente.
    expect(cuerpo.periodo.activo).toBe(false);
    expect(cuerpo.periodo.vigente).toBe(false);
  });

  it('un código repetido da 409', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/periodos',
      headers: conToken(TOKEN_ADMIN),
      payload: { codigo: '2026-1' },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'REGISTRO_DUPLICADO' } });
  });

  it('rechaza un código con formato inválido antes de abrir una transacción', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    // Duplica el `check` de `academic_periods`. Zod da el mensaje nombrando el
    // campo; el `check` es la invariante y sigue ahí.
    for (const codigo of ['2026/1', '01234567890', '', '-2026', 'a b']) {
      const respuesta = await app.inject({
        method: 'POST',
        url: '/api/v1/admin/periodos',
        headers: conToken(TOKEN_ADMIN),
        payload: { codigo },
      });
      expect(respuesta.statusCode, `código "${codigo}"`).toBe(400);
    }
  });

  it('rechaza un rango de fechas invertido o inexistente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const invertido = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/periodos',
      headers: conToken(TOKEN_ADMIN),
      payload: { codigo: '2027-2', fechaInicio: '2027-08-01', fechaFin: '2027-02-01' },
    });
    expect(invertido.statusCode).toBe(400);

    // El 30 de febrero tiene la forma correcta y no existe: sin `esFechaISO`
    // llegaría a Postgres, que responde `22007`, y saldría como un 500.
    const imposible = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/periodos',
      headers: conToken(TOKEN_ADMIN),
      payload: { codigo: '2027-3', fechaInicio: '2027-02-30' },
    });
    expect(imposible.statusCode).toBe(400);
  });
});

describe('PATCH /api/v1/admin/periodos/:id', () => {
  it('abre un lapso sin declararlo vigente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/periodos/${ID_PERIODO_2026_2}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activo: true },
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { periodo: { activo: boolean; vigente: boolean } };
    expect(cuerpo.periodo.activo).toBe(true);
    // Abrir no es declarar vigente. Son dos botones distintos a propósito.
    expect(cuerpo.periodo.vigente).toBe(false);
  });

  it('permite vaciar las fechas con null explícito', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/periodos/${ID_PERIODO_2026_2}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { fechaInicio: null, fechaFin: null },
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { periodo: { fechaInicio: null; fechaFin: null } };
    expect(cuerpo.periodo.fechaInicio).toBeNull();
    expect(cuerpo.periodo.fechaFin).toBeNull();
  });

  it('un id que no existe da 404 PERIODO_INEXISTENTE', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/periodos/${ID_INEXISTENTE}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activo: true },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PERIODO_INEXISTENTE' } });
  });
});

describe('PUT /api/v1/admin/periodos/:id/vigente', () => {
  it('mueve el lapso vigente y el cambio se ve en el listado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: `/api/v1/admin/periodos/${ID_PERIODO_2026_2}/vigente`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { periodo: { codigo: string; vigente: boolean } };
    expect(cuerpo.periodo.codigo).toBe('2026-2');
    expect(cuerpo.periodo.vigente).toBe(true);

    // Y no queda como una bandera suelta: el listado, que lo recalcula, lo
    // confirma. Si el repositorio devolviera `vigente` sin mover el parámetro,
    // esta segunda lectura lo destaparía.
    const listado = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/periodos',
      headers: conToken(TOKEN_ADMIN),
    });
    const periodos = (listado.json() as { periodos: { codigo: string; vigente: boolean }[] })
      .periodos;
    expect(periodos.map((p) => p.vigente)).toEqual([true, false]);
  });

  it('un id que no existe da 404 PERIODO_INEXISTENTE', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: `/api/v1/admin/periodos/${ID_INEXISTENTE}/vigente`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PERIODO_INEXISTENTE' } });
  });
});

// --- Guardias ---------------------------------------------------------------

describe('GET /api/v1/admin/guardias', () => {
  it('lista las guardias con el turno ya derivado del bloque', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      guardias: { turno: string; dia: number; bloque: number }[];
      total: number;
    };

    expect(cuerpo.total).toBe(1);
    expect(cuerpo.guardias[0]).toMatchObject({ turno: 'MAÑANA', dia: 1, bloque: 1 });
  });

  it('filtra por lapso, docente, espacio, día y bloque', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const pedir = async (consulta: string): Promise<number> => {
      const respuesta = await app!.inject({
        method: 'GET',
        url: `/api/v1/admin/guardias?${consulta}`,
        headers: conToken(TOKEN_ADMIN),
      });
      expect(respuesta.statusCode, consulta).toBe(200);
      return (respuesta.json() as { total: number }).total;
    };

    expect(await pedir(`docenteId=${ID_DOCENTE}`)).toBe(1);
    expect(await pedir(`aulaId=${ID_AULA_ZONA}`)).toBe(1);
    expect(await pedir('periodo=2026-1')).toBe(1);
    expect(await pedir('dia=1&bloque=1')).toBe(1);

    // Y los que no deben traer nada.
    expect(await pedir('periodo=2026-2')).toBe(0);
    expect(await pedir('dia=2')).toBe(0);
    expect(await pedir(`docenteId=${ID_DOCENTE_2}`)).toBe(0);
  });
});

describe('POST /api/v1/admin/guardias — el alta normal', () => {
  it('crea una guardia y deriva el turno del bloque', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        periodo: '2026-1',
        dia: 4,
        bloque: 8,
        notas: 'Custodia del pasillo',
      },
    });

    expect(respuesta.statusCode).toBe(201);
    const cuerpo = respuesta.json() as {
      guardia: { turno: string; dia: number; bloque: number; activa: boolean };
    };
    // El turno lo calcula la base a partir del bloque; aquí llega ya derivado.
    expect(cuerpo.guardia.turno).toBe('TARDE');
    expect(cuerpo.guardia.activa).toBe(true);
  });

  it('rechaza que el cliente mande el turno en vez de ignorarlo', async () => {
    // El `turno` es una columna generada. Aceptarlo permitiría una guardia que
    // dice «MAÑANA» en el bloque 9: una agenda que miente. Con `.strict()` da un
    // 400 que nombra el campo.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        periodo: '2026-1',
        dia: 4,
        bloque: 8,
        turno: 'MAÑANA',
      },
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('el período es obligatorio: sin él la guardia chocaría entre lapsos', async () => {
    // R-15. Sin período, una guardia del lunes a primera hora chocaría con las
    // clases de cualquier lapso, presente y futuro.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: { docenteId: ID_DOCENTE, aulaId: ID_AULA_TEORICA, dia: 4, bloque: 8 },
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('rechaza el día 7 y el bloque 13', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const domingo = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        periodo: '2026-1',
        dia: 7,
        bloque: 1,
      },
    });
    expect(domingo.statusCode).toBe(400);

    const bloqueTrece = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        periodo: '2026-1',
        dia: 2,
        bloque: 13,
      },
    });
    expect(bloqueTrece.statusCode).toBe(400);
  });

  it('una referencia que no existe da 400 REFERENCIA_INVALIDA', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const casos = [
      { docenteId: ID_INEXISTENTE, aulaId: ID_AULA_TEORICA, periodo: '2026-1' },
      { docenteId: ID_DOCENTE, aulaId: ID_INEXISTENTE, periodo: '2026-1' },
      { docenteId: ID_DOCENTE, aulaId: ID_AULA_TEORICA, periodo: '2099-9' },
    ];

    for (const caso of casos) {
      const respuesta = await app.inject({
        method: 'POST',
        url: '/api/v1/admin/guardias',
        headers: conToken(TOKEN_ADMIN),
        payload: { ...caso, dia: 2, bloque: 3 },
      });
      expect(respuesta.statusCode, JSON.stringify(caso)).toBe(400);
      expect(respuesta.json()).toMatchObject({ error: { codigo: 'REFERENCIA_INVALIDA' } });
    }
  });
});

describe('POST /api/v1/admin/guardias — el choque de agenda', () => {
  /**
   * El arnés con un segundo docente.
   *
   * Sin él, el chequeo del docente salta primero y la comprobación del espacio
   * nunca se llega a ejercitar: se probaría una vez el mismo camino y se creería
   * que los dos están cubiertos.
   */
  const arnésConDosDocentes = () =>
    crearArnés({ perfiles: [...PERFILES_POR_DEFECTO, PERFIL_DOCENTE_2] });

  it('un docente ya ocupado da 409 y el mensaje nombra el día y el bloque', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        periodo: '2026-1',
        dia: 1,
        bloque: 1,
      },
    });

    expect(respuesta.statusCode).toBe(409);
    const cuerpo = respuesta.json() as { error: { codigo: string; mensaje: string } };
    expect(cuerpo.error.codigo).toBe('CHOQUE_DE_AGENDA');
    // El mensaje viene del trigger, no se reconstruye en TypeScript: nombra el
    // día y el bloque, que es justo lo que la pantalla necesita mostrar.
    expect(cuerpo.error.mensaje).toContain('ya tiene una clase o guardia asignada el lunes');
    expect(cuerpo.error.mensaje).toContain('bloque 1');
  });

  it('un espacio ya ocupado da 409 aunque el docente esté libre', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE_2,
        aulaId: ID_AULA_ZONA,
        periodo: '2026-1',
        dia: 1,
        bloque: 1,
      },
    });

    expect(respuesta.statusCode).toBe(409);
    const cuerpo = respuesta.json() as { error: { codigo: string; mensaje: string } };
    expect(cuerpo.error.codigo).toBe('CHOQUE_DE_AGENDA');
    expect(cuerpo.error.mensaje).toContain('ya está ocupado el lunes');
  });

  it('el mismo hueco en OTRO lapso sí se permite', async () => {
    // Es el caso que demuestra por qué un `unique (teacher_id, day_of_week,
    // block)` habría sido incorrecto: prohibiría planificar el lapso siguiente
    // mientras el actual sigue en curso. El choque se comprueba **dentro** del
    // lapso.
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_ZONA,
        periodo: '2026-2',
        dia: 1,
        bloque: 1,
      },
    });

    expect(respuesta.statusCode).toBe(201);
  });

  it('archivar una guardia libera el hueco que ocupaba', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const archivar = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/guardias/${ID_GUARDIA_LUNES}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activa: false },
    });
    expect(archivar.statusCode).toBe(200);

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/guardias',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_ZONA,
        periodo: '2026-1',
        dia: 1,
        bloque: 1,
      },
    });

    expect(respuesta.statusCode).toBe(201);
  });
});

describe('PATCH /api/v1/admin/guardias/:id', () => {
  it('mueve una guardia de bloque y recalcula el turno', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/guardias/${ID_GUARDIA_LUNES}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { bloque: 9 },
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { guardia: { bloque: number; turno: string } };
    expect(cuerpo.guardia.bloque).toBe(9);
    expect(cuerpo.guardia.turno).toBe('TARDE');
  });

  it('mover una guardia sobre su propio hueco no se rechaza a sí misma', async () => {
    // El trigger excluye el registro que se está actualizando. Sin esa
    // exclusión, guardar una guardia sin cambiarla de sitio daría un 409
    // absurdo: «ese docente ya está ocupado» señalándose a sí misma.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/guardias/${ID_GUARDIA_LUNES}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { notas: 'Apertura del taller y control de acceso' },
    });

    expect(respuesta.statusCode).toBe(200);
  });

  it('un cuerpo sin cambios da 400 y un id inexistente da 404', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const vacio = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/guardias/${ID_GUARDIA_LUNES}`,
      headers: conToken(TOKEN_ADMIN),
      payload: {},
    });
    expect(vacio.statusCode).toBe(400);

    const inexistente = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/guardias/${ID_INEXISTENTE}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { bloque: 3 },
    });
    expect(inexistente.statusCode).toBe(404);
    expect(inexistente.json()).toMatchObject({ error: { codigo: 'GUARDIA_INEXISTENTE' } });
  });
});

// --- Cuadrante --------------------------------------------------------------

describe('GET /api/v1/admin/cuadrante', () => {
  it('devuelve las cuatro listas de la rejilla en una sola respuesta', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/cuadrante',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      periodo: string | null;
      clases: { materia: string; seccion: string; docente: string; aula: string }[];
      guardias: unknown[];
      aulas: unknown[];
      docentes: { nombre: string }[];
    };

    expect(cuerpo.periodo).toBe('2026-1');
    expect(cuerpo.clases).toHaveLength(1);
    expect(cuerpo.guardias).toHaveLength(1);
    expect(cuerpo.aulas).toHaveLength(3);
    expect(cuerpo.docentes).toHaveLength(2);

    // Los nombres vienen resueltos por la vista: la pantalla no tiene que hacer
    // una petición por celda para saber a qué materia o a qué aula apunta.
    expect(cuerpo.clases[0]).toMatchObject({
      materia: 'Algorítmica I',
      seccion: 'SA',
      docente: 'Carlos Rondón',
      aula: 'Taller de Soldadura Cabina A',
    });
    expect(cuerpo.docentes.map((d) => d.nombre)).toEqual([
      'Ada Administradora',
      'Carlos Rondón',
    ]);
  });

  it('sin lapso vigente devuelve la rejilla vacía pero con el catálogo', async () => {
    // Las aulas y los docentes no dependen del lapso. Devolverlos igualmente
    // deja que la pantalla diga «no hay lapso vigente» en vez de quedarse en
    // blanco sin explicación.
    const arnés = crearArnés({ periodoCodigoVigente: null });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/cuadrante',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      periodo: null;
      clases: unknown[];
      guardias: unknown[];
      aulas: unknown[];
      docentes: unknown[];
    };

    expect(cuerpo.periodo).toBeNull();
    expect(cuerpo.clases).toEqual([]);
    expect(cuerpo.guardias).toEqual([]);
    expect(cuerpo.aulas).toHaveLength(3);
    expect(cuerpo.docentes).toHaveLength(2);
  });

  it('el filtro por lapso dibuja otro lapso sin tocar el vigente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/cuadrante?periodo=2026-2',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      periodo: string;
      clases: unknown[];
      guardias: unknown[];
      aulas: unknown[];
    };

    // El lapso siguiente está vacío porque nadie ha planificado nada en él
    // todavía, no porque el filtro esté roto: el catálogo sigue completo.
    expect(cuerpo.periodo).toBe('2026-2');
    expect(cuerpo.clases).toEqual([]);
    expect(cuerpo.guardias).toEqual([]);
    expect(cuerpo.aulas).toHaveLength(3);
  });

  it('el filtro por docente deja fuera lo que no es suyo', async () => {
    const arnés = crearArnés({ perfiles: [...PERFILES_POR_DEFECTO, PERFIL_DOCENTE_2] });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/admin/cuadrante?docenteId=${ID_DOCENTE_2}`,
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { clases: unknown[]; guardias: unknown[] };
    expect(cuerpo.clases).toEqual([]);
    expect(cuerpo.guardias).toEqual([]);
  });
});

describe('POST /api/v1/admin/cuadrante', () => {
  const arnésConDosDocentes = () =>
    crearArnés({ perfiles: [...PERFILES_POR_DEFECTO, PERFIL_DOCENTE_2] });

  it('coloca una clase y deriva el lapso y el turno', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/cuadrante',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        seccionId: ID_SECCION_SC,
        docenteId: ID_DOCENTE_2,
        aulaId: ID_AULA_TEORICA,
        dia: 4,
        bloque: 7,
      },
    });

    expect(respuesta.statusCode).toBe(201);
    const cuerpo = respuesta.json() as {
      clase: {
        periodo: string;
        turno: string;
        materia: string;
        seccion: string;
        programa: string;
      };
    };

    // El período sale de la sección y no de la petición: es lo que hace que el
    // chequeo de colisiones compare dentro de un lapso y no entre lapsos.
    expect(cuerpo.clase.periodo).toBe('2026-1');
    expect(cuerpo.clase.turno).toBe('TARDE');
    expect(cuerpo.clase.materia).toBe('Bases de Datos II');
    expect(cuerpo.clase.seccion).toBe('SC');
    expect(cuerpo.clase.programa).toBe('Análisis de Sistemas');
  });

  it('rechaza que el cliente mande el período o el turno', async () => {
    // Ninguno de los dos es una columna de `schedule_slots`: el período se
    // deriva de la sección y el turno del bloque. Aceptarlos abriría la puerta a
    // una fila cuya sección pertenece a un lapso mientras la rejilla se dibuja
    // en otro.
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    for (const extra of [{ periodo: '2026-1' }, { turno: 'TARDE' }]) {
      const respuesta = await app.inject({
        method: 'POST',
        url: '/api/v1/admin/cuadrante',
        headers: conToken(TOKEN_ADMIN),
        payload: {
          seccionId: ID_SECCION_SC,
          docenteId: ID_DOCENTE_2,
          aulaId: ID_AULA_TEORICA,
          dia: 4,
          bloque: 7,
          ...extra,
        },
      });
      expect(respuesta.statusCode, JSON.stringify(extra)).toBe(400);
    }
  });

  it('una sección, un docente o un aula que no existen dan 400 REFERENCIA_INVALIDA', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const casos = [
      { seccionId: ID_INEXISTENTE, docenteId: ID_DOCENTE_2, aulaId: ID_AULA_TEORICA },
      { seccionId: ID_SECCION_SC, docenteId: ID_INEXISTENTE, aulaId: ID_AULA_TEORICA },
      { seccionId: ID_SECCION_SC, docenteId: ID_DOCENTE_2, aulaId: ID_INEXISTENTE },
    ];

    for (const caso of casos) {
      const respuesta = await app.inject({
        method: 'POST',
        url: '/api/v1/admin/cuadrante',
        headers: conToken(TOKEN_ADMIN),
        payload: { ...caso, dia: 4, bloque: 7 },
      });
      expect(respuesta.statusCode, JSON.stringify(caso)).toBe(400);
      expect(respuesta.json()).toMatchObject({ error: { codigo: 'REFERENCIA_INVALIDA' } });
    }
  });

  it('el docente ocupado por una clase da 409', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/cuadrante',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        seccionId: ID_SECCION_SC,
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        dia: 3,
        bloque: 5,
      },
    });

    expect(respuesta.statusCode).toBe(409);
    const cuerpo = respuesta.json() as { error: { codigo: string; mensaje: string } };
    expect(cuerpo.error.codigo).toBe('CHOQUE_DE_AGENDA');
    expect(cuerpo.error.mensaje).toContain('ya tiene una clase o guardia asignada el miércoles');
  });

  it('el aula ocupada por una clase da 409 aunque el docente esté libre', async () => {
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/cuadrante',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        seccionId: ID_SECCION_SC,
        docenteId: ID_DOCENTE_2,
        aulaId: ID_AULA_TALLER,
        dia: 3,
        bloque: 5,
      },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'CHOQUE_DE_AGENDA' } });
  });

  it('el docente ocupado por una GUARDIA da 409: el choque cruza las dos tablas', async () => {
    // Este es el caso central del módulo. Un `unique` sobre `schedule_slots` no
    // podría verlo nunca, porque la guardia vive en `teacher_duties`. Y es real:
    // el docente cubre la apertura del taller el lunes a primera hora y no puede
    // estar dando clase en otra aula a esa misma hora.
    const arnés = arnésConDosDocentes();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/cuadrante',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        seccionId: ID_SECCION_SC,
        docenteId: ID_DOCENTE,
        aulaId: ID_AULA_TEORICA,
        dia: 1,
        bloque: 1,
      },
    });

    expect(respuesta.statusCode).toBe(409);
    const cuerpo = respuesta.json() as { error: { codigo: string; mensaje: string } };
    expect(cuerpo.error.codigo).toBe('CHOQUE_DE_AGENDA');
    expect(cuerpo.error.mensaje).toContain('ya tiene una clase o guardia asignada el lunes');
  });
});

describe('PATCH /api/v1/admin/cuadrante/:id', () => {
  it('mueve una clase de bloque y el turno se recalcula', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/cuadrante/${CLASE_MIERCOLES.id}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { bloque: 7 },
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { clase: { bloque: number; turno: string } };
    expect(cuerpo.clase.bloque).toBe(7);
    expect(cuerpo.clase.turno).toBe('TARDE');
  });

  it('un cuerpo sin cambios da 400 y un id inexistente da 404', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const vacio = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/cuadrante/${CLASE_MIERCOLES.id}`,
      headers: conToken(TOKEN_ADMIN),
      payload: {},
    });
    expect(vacio.statusCode).toBe(400);

    const inexistente = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/cuadrante/${ID_INEXISTENTE}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { bloque: 3 },
    });
    expect(inexistente.statusCode).toBe(404);
    expect(inexistente.json()).toMatchObject({ error: { codigo: 'CLASE_INEXISTENTE' } });
  });
});

// --- Mi horario -------------------------------------------------------------

describe('GET /api/v1/mi-horario', () => {
  it('un docente ve sus clases y sus guardias del lapso vigente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      rol: string;
      periodo: string;
      clases: { materia: string }[];
      guardias: { notas: string | null }[];
    };

    expect(cuerpo.rol).toBe('docente');
    expect(cuerpo.periodo).toBe('2026-1');
    expect(cuerpo.clases).toHaveLength(1);
    expect(cuerpo.clases[0]?.materia).toBe('Algorítmica I');
    // Las guardias son la mitad del horario de un docente: sin ellas vería su
    // jornada a medias.
    expect(cuerpo.guardias).toHaveLength(1);
    expect(cuerpo.guardias[0]?.notas).toBe(GUARDIA_LUNES.notas);
  });

  it('un estudiante ve las clases de sus secciones y ninguna guardia', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      rol: string;
      clases: { seccion: string }[];
      guardias: unknown[];
    };

    expect(cuerpo.rol).toBe('estudiante');
    expect(cuerpo.clases).toHaveLength(1);
    expect(cuerpo.clases[0]?.seccion).toBe('SA');
    // Las guardias de custodia no son asunto de un estudiante: no se le
    // devuelven, y no se le devuelve una lista vacía por casualidad sino porque
    // la consulta ni se hace.
    expect(cuerpo.guardias).toEqual([]);
  });

  it('un administrador recibe 403 con un código propio', async () => {
    // No es un fallo: un administrador no tiene horario. Devolverle una lista
    // vacía le haría creer que no tiene ninguna clase asignada, en vez de que la
    // pregunta no aplica a su rol.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PERFIL_SIN_ROL' } });
  });

  it('acepta planificar un lapso distinto del vigente', async () => {
    // Un docente prepara el lapso siguiente mientras dicta el actual: es la
    // razón de que exista el catálogo de lapsos.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario?periodo=2026-2',
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { periodo: string; clases: unknown[]; guardias: unknown[] };
    expect(cuerpo.periodo).toBe('2026-2');
    expect(cuerpo.clases).toEqual([]);
    expect(cuerpo.guardias).toEqual([]);
  });

  it('sin lapso vigente devuelve un horario vacío, no un error', async () => {
    const arnés = crearArnés({ periodoCodigoVigente: null });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { periodo: null; clases: unknown[] };
    expect(cuerpo.periodo).toBeNull();
    expect(cuerpo.clases).toEqual([]);
  });

  it('el horario del docente no incluye las clases de otro docente', async () => {
    // El aislamiento lo garantiza la RLS en la base; el doble la refleja. Sin
    // esta prueba, una consulta sin filtro pasaría desapercibida y el docente
    // vería la rejilla entera del centro.
    const arnés = crearArnés({
      perfiles: [...PERFILES_POR_DEFECTO, PERFIL_DOCENTE_2],
      clases: [
        ...arnésClases(),
        {
          id: 'dddddddd-0003-4003-8003-000000000003',
          seccionId: ID_SECCION_SC,
          docenteId: ID_DOCENTE_2,
          aulaId: ID_AULA_TEORICA,
          dia: 2,
          bloque: 2,
          activa: true,
        },
      ],
    });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_DOCENTE),
    });

    const cuerpo = respuesta.json() as { clases: { id: string }[] };
    expect(cuerpo.clases).toHaveLength(1);
    expect(cuerpo.clases[0]?.id).toBe(CLASE_MIERCOLES.id);
  });
});

/** Las clases por defecto del arnés, para poder añadir una sin repetirla. */
function arnésClases() {
  return [{ ...CLASE_MIERCOLES }];
}

// --- Coherencia con el catálogo ---------------------------------------------

describe('los espacios de ejemplo y sus tipos', () => {
  it('el taller es taller, el aula tiene cupo y la zona no tiene ninguno', () => {
    // Es la invariante que el filtro `tipo` traduce a SQL. Si un fixture dejara
    // de cumplirla, las pruebas de filtro pasarían por casualidad y no por la
    // regla.
    expect(AULA_TALLER.esTaller).toBe(true);
    expect(AULA_TEORICA.esTaller).toBe(false);
    expect(AULA_TEORICA.capacidad).toBeGreaterThan(0);
    expect(AULA_ZONA.esTaller).toBe(false);
    expect(AULA_ZONA.capacidad).toBe(0);
    expect(ID_SECCION_SA).not.toBe(ID_SECCION_SC);
    expect(ID_PERIODO_2026_1).not.toBe(ID_PERIODO_2026_2);
  });
});

/**
 * La guardia de la bandera `m3_cuadrante`.
 *
 * Va aparte del bloque de control de acceso porque comprueba **otra pregunta**:
 * allí se pregunta quién llama; aquí, si el módulo está encendido. Separarlos
 * hace que un fallo diga cuál de las dos se rompió.
 */
describe('la guardia del módulo (m3_cuadrante)', () => {
  /** El arnés con `m3_cuadrante` apagado, como si el administrador lo apagara. */
  function conModuloApagado(): Arnés {
    return crearArnés({
      modulos: MODULOS_POR_DEFECTO.map((m) =>
        m.clave === 'm3_cuadrante' ? { ...m, habilitado: false } : m,
      ),
    });
  }

  it('con el módulo apagado, las catorce rutas responden 403 y no llegan a tocar nada', async () => {
    // Ésta es la prueba que da sentido a la bandera, y sin ella la guardia sería
    // fe. El módulo arranca **encendido**, así que una guardia cableada a la clave
    // equivocada —una errata en `m3_cuadrante`— nunca se notaría: todas las demás
    // pruebas seguirían verdes. Apagarlo es la única forma de distinguir «la
    // guardia funciona» de «la guardia no se ejecuta».
    const arnés = conModuloApagado();
    app = arnés.app;

    const aulasAntes = arnés.estado.aulas.length;
    const periodosAntes = arnés.estado.periodos.length;
    const guardiasAntes = arnés.estado.guardias.length;
    const clasesAntes = arnés.estado.clases.length;

    for (const ruta of RUTAS_ADMIN) {
      const respuesta = await app.inject({ ...ruta, headers: conToken(TOKEN_ADMIN) });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(403);
      expect(respuesta.json().error.codigo, `${ruta.method} ${ruta.url}`).toBe(
        'MODULO_DESHABILITADO',
      );
    }

    // La lectura por rol va aparte: su guardia de rol es otra —`exigirSesion()`,
    // no `exigirAdmin()`— y por tanto su token también. Es justamente la ruta que
    // demuestra que la guardia de módulo se comparte entre los dos patrones de
    // registro sin cablearse dos veces.
    const miHorario = await app.inject({
      method: 'GET',
      url: '/api/v1/mi-horario',
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(miHorario.statusCode).toBe(403);
    expect(miHorario.json().error.codigo).toBe('MODULO_DESHABILITADO');

    // Y el corte ocurre **antes** del efecto: ni un aula, ni un lapso, ni una
    // guardia, ni una clase de más. Una guardia que dejara pasar la escritura y
    // fallara al responder no sería una guardia, sería un 403 que esconde un daño
    // ya hecho.
    expect(arnés.estado.aulas).toHaveLength(aulasAntes);
    expect(arnés.estado.periodos).toHaveLength(periodosAntes);
    expect(arnés.estado.guardias).toHaveLength(guardiasAntes);
    expect(arnés.estado.clases).toHaveLength(clasesAntes);
  });

  it('sin la fila del módulo el error es 404 MODULO_DESCONOCIDO, y no 403', async () => {
    // La distinción no es cosmética. `comprobarModulo` separa «no está
    // registrado» de «está apagado» a propósito: confundirlos manda a buscar el
    // problema al sitio equivocado —a la bandera, cuando lo que falta es la
    // semilla—.
    const arnés = crearArnés({ modulos: [] });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/aulas',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('MODULO_DESCONOCIDO');
  });
});
