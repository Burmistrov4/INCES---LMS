import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import {
  conToken,
  crearArnés,
  ID_MATERIA_ALGORITMICA,
  ID_MATERIA_BASEDATOS,
  ID_MATERIA_INGLES,
  ID_MATERIA_MATEMATICA,
  ID_PROGRAMA_HERRERIA,
  ID_PROGRAMA_SISTEMAS,
  ID_PROGRAMA_VACIO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
} from './support/arnes.js';

/**
 * Las siete rutas del Módulo 2, de punta a punta sobre el arnés en memoria.
 *
 * Lo que se comprueba aquí es el **contrato HTTP**: control de acceso, códigos
 * de estado, validación de Zod, forma de las respuestas y el 409 de la Regla 2.
 * Lo que ocurre *dentro* del repositorio —que las escrituras vayan por función
 * y que el `23514` se traduzca bien— se prueba aparte, en
 * `curriculo-repositorio.test.ts`: el arnés sustituye el repositorio entero, así
 * que no puede verlo.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

const RUTAS_ADMIN = [
  { method: 'GET' as const, url: '/api/v1/admin/programas' },
  { method: 'GET' as const, url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}` },
  { method: 'POST' as const, url: '/api/v1/admin/programas' },
  { method: 'PATCH' as const, url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}` },
  { method: 'PATCH' as const, url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}/pensum` },
  { method: 'GET' as const, url: '/api/v1/admin/materias' },
  { method: 'POST' as const, url: '/api/v1/admin/materias' },
];

describe('control de acceso a las rutas de currículo', () => {
  it('exige sesión en las siete', async () => {
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
});

describe('GET /api/v1/admin/programas', () => {
  it('lista con los totales del pensum en la misma respuesta', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      programas: { nombre: string; totalMaterias: number; totalPeriodos: number }[];
      total: number;
      limite: number;
      desplazamiento: number;
    };

    expect(cuerpo.total).toBe(3);
    expect(cuerpo.limite).toBe(25);
    expect(cuerpo.desplazamiento).toBe(0);

    // Ordenado por nombre.
    expect(cuerpo.programas.map((p) => p.nombre)).toEqual([
      'Análisis de Sistemas',
      'Carrera sin pensum',
      'Herrería',
    ]);

    // El pensum de Sistemas tiene 3 materias repartidas en los períodos 1, 1 y
    // 4: dos períodos, no cuatro. Es el mismo caso que cubre `agruparPensum`,
    // comprobado ahora por el camino real.
    const sistemas = cuerpo.programas[0];
    expect(sistemas?.totalMaterias).toBe(3);
    expect(sistemas?.totalPeriodos).toBe(2);
  });

  it('filtra por tipo y por estado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const carreras = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas?tipo=CARRERA',
      headers: conToken(TOKEN_ADMIN),
    });
    expect((carreras.json() as { total: number }).total).toBe(2);

    const activos = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas?activo=true',
      headers: conToken(TOKEN_ADMIN),
    });
    expect((activos.json() as { total: number }).total).toBe(2);

    const borradores = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas?activo=false',
      headers: conToken(TOKEN_ADMIN),
    });
    expect((borradores.json() as { total: number }).total).toBe(1);
  });

  it('busca por código y por nombre, sin distinguir mayúsculas', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const texto of ['herr', 'CUR-HER', 'HERRERÍA']) {
      const respuesta = await app.inject({
        method: 'GET',
        url: `/api/v1/admin/programas?busqueda=${encodeURIComponent(texto)}`,
        headers: conToken(TOKEN_ADMIN),
      });
      expect((respuesta.json() as { total: number }).total, texto).toBe(1);
    }
  });

  it('una página más allá del final es una página vacía, no un error', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas?limite=10&desplazamiento=99',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ programas: [], total: 3, desplazamiento: 99 });
  });

  it('rechaza un tipo que no existe con 400, en vez de ignorarlo', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas?tipo=TALLER',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });
});

describe('GET /api/v1/admin/programas/:id', () => {
  it('devuelve el pensum agrupado, con los datos de cada materia', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const detalle = respuesta.json() as {
      programa: { codigo: string };
      pensum: { periodo: number; materias: { codigo: string; nombre: string }[] }[];
      seccionesActivas: number;
      editable: boolean;
    };

    expect(detalle.programa.codigo).toBe('SIST-01');
    expect(detalle.pensum.map((g) => g.periodo)).toEqual([1, 4]);
    expect(detalle.pensum[0]?.materias.map((m) => m.codigo)).toEqual(['ALG-I', 'BD-II']);
    expect(detalle.pensum[0]?.materias[0]?.nombre).toBe('Algorítmica I');

    // La pantalla necesita `nombre` y `horasAcademicas` para pintar el pensum
    // sin pedir el banco de materias entero.
    expect(detalle.pensum[1]?.materias[0]).toMatchObject({
      codigo: 'ING-TEC',
      horasAcademicas: 48,
    });

    expect(detalle.seccionesActivas).toBe(0);
    expect(detalle.editable).toBe(true);
  });

  it('con secciones activas, `editable` es false (Regla 2 materializada)', async () => {
    const arnés = crearArnés({ seccionesActivas: { [ID_PROGRAMA_SISTEMAS]: 2 } });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.json()).toMatchObject({ seccionesActivas: 2, editable: false });
  });

  it('un id que no es UUID es 400, no 500', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas/no-soy-un-uuid',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });

  it('un UUID que no existe es 404 PROGRAMA_INEXISTENTE', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/programas/99999999-9999-4999-8999-999999999999',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PROGRAMA_INEXISTENTE' } });
  });
});

describe('POST /api/v1/admin/programas — el asistente', () => {
  const cuerpoValido = {
    codigo: 'SIST-02',
    nombre: 'Análisis de Sistemas (v2)',
    tipo: 'CARRERA',
    requierePasantia: true,
    publicar: true,
    pensum: [
      { materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 },
      { materiaId: ID_MATERIA_BASEDATOS, periodo: 2 },
    ],
  };

  it('crea el programa con su pensum y responde 201', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: cuerpoValido,
    });

    expect(respuesta.statusCode).toBe(201);
    const detalle = respuesta.json() as {
      programa: { codigo: string; activo: boolean; requierePasantia: boolean };
      pensum: { periodo: number }[];
    };

    expect(detalle.programa).toMatchObject({
      codigo: 'SIST-02',
      activo: true,
      requierePasantia: true,
    });
    expect(detalle.pensum.map((g) => g.periodo)).toEqual([1, 2]);

    // Y quedó guardado, no sólo devuelto.
    const creado = arnés.estado.programas.find((p) => p.codigo === 'SIST-02');
    expect(creado).toBeDefined();
    expect(arnés.estado.pensum[creado?.id ?? '']).toHaveLength(2);
  });

  it('nace en borrador si no se pide publicar', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...cuerpoValido, publicar: undefined },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json()).toMatchObject({ programa: { activo: false } });
  });

  it('un código repetido es 409, no un 500 de restricción', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...cuerpoValido, codigo: 'SIST-01' },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'REGISTRO_DUPLICADO' } });
  });

  it('un pensum vacío es 400 y nombra el campo', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...cuerpoValido, pensum: [] },
    });

    expect(respuesta.statusCode).toBe(400);
    const error = respuesta.json() as { error: { codigo: string; detalles: { campo: string }[] } };
    expect(error.error.codigo).toBe('PETICION_INVALIDA');
    expect(error.error.detalles.map((d) => d.campo)).toContain('pensum');
  });

  it('una materia repetida es 400 y el mensaje la nombra', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        ...cuerpoValido,
        pensum: [
          { materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 },
          { materiaId: ID_MATERIA_ALGORITMICA, periodo: 3 },
        ],
      },
    });

    expect(respuesta.statusCode).toBe(400);
    // El mensaje tiene que decir CUÁL se repite: con 40 materias, «hay un
    // error» no sirve de nada.
    expect(JSON.stringify(respuesta.json())).toContain(ID_MATERIA_ALGORITMICA);
  });

  it('una materia que no existe es 400 REFERENCIA_INVALIDA', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: {
        ...cuerpoValido,
        pensum: [{ materiaId: '99999999-9999-4999-8999-999999999999', periodo: 1 }],
      },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'REFERENCIA_INVALIDA' } });
  });

  it('rechaza campos desconocidos en vez de ignorarlos', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...cuerpoValido, activo: true },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(JSON.stringify(respuesta.json())).toContain('activo');
  });

  it('rechaza un código en minúsculas: el código se teclea a mano', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/programas',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...cuerpoValido, codigo: 'sist-02' },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('PATCH /api/v1/admin/programas/:id', () => {
  it('cambia los metadatos y los persiste', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Análisis de Sistemas (revisado)', requierePasantia: false },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      programa: { nombre: 'Análisis de Sistemas (revisado)', requierePasantia: false },
    });
    expect(
      arnés.estado.programas.find((p) => p.id === ID_PROGRAMA_SISTEMAS)?.requierePasantia,
    ).toBe(false);
  });

  it('no acepta `codigo` ni `tipo`: son la identidad del programa', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const cambio of [{ codigo: 'OTRO-01' }, { tipo: 'CURSO_LIBRE' }]) {
      const respuesta = await app.inject({
        method: 'PATCH',
        url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}`,
        headers: conToken(TOKEN_ADMIN),
        payload: cambio,
      });
      expect(respuesta.statusCode, JSON.stringify(cambio)).toBe(400);
    }
  });

  it('un cuerpo sin cambios es 400, no un no-op silencioso', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}`,
      headers: conToken(TOKEN_ADMIN),
      payload: {},
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('un programa que no existe es 404', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/programas/99999999-9999-4999-8999-999999999999',
      headers: conToken(TOKEN_ADMIN),
      payload: { nombre: 'Fantasma' },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'NO_ENCONTRADO' } });
  });

  it('publicar una carrera sin materias es 400 (Regla 1)', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_VACIO}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activo: true },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'RESTRICCION_VIOLADA' } });
    // Y no se publicó a medias.
    expect(arnés.estado.programas.find((p) => p.id === ID_PROGRAMA_VACIO)?.activo).toBe(false);
  });

  it('con pensum, la misma carrera sí se publica', async () => {
    // El recorrido real del asistente: primero el pensum, después publicar.
    // Sin esta prueba, la de arriba podría estar pasando por el motivo
    // equivocado (un `activo: true` que siempre falla).
    const arnés = crearArnés();
    app = arnés.app;

    const pensum = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_VACIO}/pensum`,
      headers: conToken(TOKEN_ADMIN),
      payload: { pensum: [{ materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 }] },
    });
    expect(pensum.statusCode).toBe(200);

    const publicar = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_VACIO}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activo: true },
    });

    expect(publicar.statusCode).toBe(200);
    expect(publicar.json()).toMatchObject({ programa: { activo: true } });
  });
});

describe('PATCH /api/v1/admin/programas/:id/pensum', () => {
  it('reemplaza el pensum completo', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}/pensum`,
      headers: conToken(TOKEN_ADMIN),
      payload: {
        pensum: [
          { materiaId: ID_MATERIA_INGLES, periodo: 1 },
          { materiaId: ID_MATERIA_MATEMATICA, periodo: 2 },
        ],
      },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      pensum: [{ periodo: 1 }, { periodo: 2 }],
    });
    expect(arnés.estado.pensum[ID_PROGRAMA_SISTEMAS]).toHaveLength(2);
  });

  it('con secciones activas, reordenar es 409 PENSUM_EN_USO', async () => {
    const arnés = crearArnés({ seccionesActivas: { [ID_PROGRAMA_SISTEMAS]: 2 } });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}/pensum`,
      headers: conToken(TOKEN_ADMIN),
      payload: {
        pensum: [
          { materiaId: ID_MATERIA_ALGORITMICA, periodo: 3 },
          { materiaId: ID_MATERIA_BASEDATOS, periodo: 1 },
          { materiaId: ID_MATERIA_INGLES, periodo: 4 },
        ],
      },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PENSUM_EN_USO' } });

    // Y el pensum quedó INTACTO: la operación se deshace entera, no a medias.
    expect(arnés.estado.pensum[ID_PROGRAMA_SISTEMAS]).toEqual([
      { materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 },
      { materiaId: ID_MATERIA_BASEDATOS, periodo: 1 },
      { materiaId: ID_MATERIA_INGLES, periodo: 4 },
    ]);
  });

  it('con secciones activas, quitar una materia también es 409', async () => {
    const arnés = crearArnés({ seccionesActivas: { [ID_PROGRAMA_SISTEMAS]: 1 } });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}/pensum`,
      headers: conToken(TOKEN_ADMIN),
      payload: {
        pensum: [
          { materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 },
          { materiaId: ID_MATERIA_BASEDATOS, periodo: 1 },
        ],
      },
    });

    expect(respuesta.statusCode).toBe(409);
  });

  it('con secciones activas, AÑADIR una materia sí se permite', async () => {
    // El reparto del trigger: `before update of period_order, program_id or
    // delete` no mira los insert, porque añadir a un pensum en uso es legítimo.
    // Sin esta prueba, la Regla 2 parecería bloquear cualquier guardado, que es
    // exactamente lo que haría inservible el módulo.
    const arnés = crearArnés({ seccionesActivas: { [ID_PROGRAMA_SISTEMAS]: 3 } });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_SISTEMAS}/pensum`,
      headers: conToken(TOKEN_ADMIN),
      payload: {
        pensum: [
          { materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 },
          { materiaId: ID_MATERIA_BASEDATOS, periodo: 1 },
          { materiaId: ID_MATERIA_INGLES, periodo: 4 },
          { materiaId: ID_MATERIA_MATEMATICA, periodo: 2 },
        ],
      },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(arnés.estado.pensum[ID_PROGRAMA_SISTEMAS]).toHaveLength(4);
  });

  it('un programa que no existe es 404, y no un error que culpe a la materia', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/programas/99999999-9999-4999-8999-999999999999/pensum',
      headers: conToken(TOKEN_ADMIN),
      payload: { pensum: [{ materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 }] },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PROGRAMA_INEXISTENTE' } });
  });

  it('un pensum vacío es 400', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/programas/${ID_PROGRAMA_HERRERIA}/pensum`,
      headers: conToken(TOKEN_ADMIN),
      payload: { pensum: [] },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('banco de materias', () => {
  it('lista, busca y pagina', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const listado = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/materias',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(listado.statusCode).toBe(200);
    expect(listado.json()).toMatchObject({ total: 4, limite: 25, desplazamiento: 0 });

    const busqueda = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/materias?busqueda=algor',
      headers: conToken(TOKEN_ADMIN),
    });
    const encontradas = busqueda.json() as { materias: { codigo: string }[]; total: number };
    expect(encontradas.total).toBe(1);
    expect(encontradas.materias[0]?.codigo).toBe('ALG-I');

    const vacia = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/materias?desplazamiento=500',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(vacia.json()).toMatchObject({ materias: [], total: 4 });
  });

  it('registra una materia en caliente y responde 201', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/materias',
      headers: conToken(TOKEN_ADMIN),
      payload: { codigo: 'RED-I', nombre: 'Redes I', horasAcademicas: 96 },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json()).toMatchObject({
      materia: { codigo: 'RED-I', nombre: 'Redes I', horasAcademicas: 96 },
    });
    expect(arnés.estado.materias).toHaveLength(5);
  });

  it('un código repetido es 409: la UI debe ofrecer la existente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/materias',
      headers: conToken(TOKEN_ADMIN),
      payload: { codigo: 'ALG-I', nombre: 'Algorítmica I', horasAcademicas: 96 },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'REGISTRO_DUPLICADO' } });
  });

  it('cero horas académicas es 400: descuadraría cualquier cálculo de carga', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/materias',
      headers: conToken(TOKEN_ADMIN),
      payload: { codigo: 'NUEVA-I', nombre: 'Sin horas', horasAcademicas: 0 },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});
