import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import {
  conToken,
  crearArnés,
  ID_MATERIA_ALGORITMICA,
  ID_MATERIA_BASEDATOS,
  ID_PROGRAMA_SISTEMAS,
  ID_SECCION_SA,
  ID_SECCION_SC,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
} from './support/arnes.js';

/**
 * El CRUD de secciones, de punta a punta sobre el arnés en memoria.
 *
 * Se comprueba el **contrato HTTP**: control de acceso, validación de Zod, códigos
 * de estado y forma de las respuestas. Lo que ocurre *dentro* —que el `23505` de
 * `sections_identidad_unica` se traduzca bien contra la base real— no se puede ver
 * desde aquí y le corresponde al humo contra Supabase.
 *
 * **No hay ninguna prueba de `DELETE` porque no hay ninguna ruta de borrado.** No
 * es un olvido: el `DELETE` está revocado en la base para `authenticated`, así que
 * archivar (`activa: false`) no es una convención que se pueda incumplir, es la
 * única opción disponible. Hay una prueba que lo dice explícitamente.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

const RUTAS_ADMIN = [
  { method: 'GET' as const, url: '/api/v1/admin/secciones' },
  { method: 'POST' as const, url: '/api/v1/admin/secciones' },
  { method: 'PATCH' as const, url: `/api/v1/admin/secciones/${ID_SECCION_SA}` },
];

describe('control de acceso a las secciones', () => {
  it('exige sesión en las tres rutas de administración', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const ruta of RUTAS_ADMIN) {
      const respuesta = await app.inject({ method: ruta.method, url: ruta.url });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
      expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
    }
  });

  it('exige rol admin: un estudiante recibe 403 y no 401', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const ruta of RUTAS_ADMIN) {
      const respuesta = await app.inject({
        method: ruta.method,
        url: ruta.url,
        headers: conToken(TOKEN_ALUMNO),
      });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(403);
      expect(respuesta.json().error.codigo).toBe('SOLO_ADMIN');
    }
  });

  it('no existe ninguna ruta de borrado', async () => {
    const arnes = crearArnés();
    app = arnes.app;
    await app.ready();

    const arbol = app.printRoutes({ commonPrefix: false });

    // `DELETE` no está en el árbol porque nunca se registró. Y no se registra
    // porque la base lo tiene revocado: borrar una sección se llevaría por delante
    // el historial de inscripciones que cuelga de su id.
    expect(arbol).not.toMatch(/secciones.*\(DELETE/);
  });
});

describe('listado de secciones', () => {
  it('devuelve las secciones con el eco de la paginación', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);

    const cuerpo = respuesta.json();
    expect(cuerpo.total).toBe(2);
    expect(cuerpo.limite).toBe(25);
    expect(cuerpo.desplazamiento).toBe(0);
    expect(cuerpo.secciones.map((s: { id: string }) => s.id).sort()).toEqual(
      [ID_SECCION_SA, ID_SECCION_SC].sort(),
    );
  });

  it('una sección sin cupo declarado sale con cupoMaximo nulo, no con 0', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/admin/secciones?materiaId=${ID_MATERIA_ALGORITMICA}`,
      headers: conToken(TOKEN_ADMIN),
    });

    const [seccion] = respuesta.json().secciones;
    expect(seccion.cupoMaximo).toBeNull();
    expect(seccion.cupoMaximo).not.toBe(0);
  });

  it('filtra por materia', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/admin/secciones?materiaId=${ID_MATERIA_BASEDATOS}`,
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json();
    expect(cuerpo.total).toBe(1);
    expect(cuerpo.secciones[0].id).toBe(ID_SECCION_SC);
  });

  it('filtra por estado activa/archivada', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    // La sección SC se archiva para tener un caso de cada lado.
    const parche = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/secciones/${ID_SECCION_SC}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activa: false },
    });
    expect(parche.statusCode).toBe(200);

    const activas = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/secciones?activa=true',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(activas.json().total).toBe(1);
    expect(activas.json().secciones[0].id).toBe(ID_SECCION_SA);

    const archivadas = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/secciones?activa=false',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(archivadas.json().total).toBe(1);
    expect(archivadas.json().secciones[0].id).toBe(ID_SECCION_SC);
  });

  it('rechaza una paginación fuera de rango', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const consulta of ['limite=0', 'limite=101', 'desplazamiento=-1']) {
      const respuesta = await app.inject({
        method: 'GET',
        url: `/api/v1/admin/secciones?${consulta}`,
        headers: conToken(TOKEN_ADMIN),
      });
      expect(respuesta.statusCode, consulta).toBe(400);
    }
  });
});

describe('crear una sección', () => {
  const NUEVA = {
    programaId: ID_PROGRAMA_SISTEMAS,
    materiaId: ID_MATERIA_ALGORITMICA,
    periodo: '2026-2',
    nombre: 'SB',
    cupoMaximo: 20,
  };

  it('crea la sección y responde 201 con su identificador', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: NUEVA,
    });

    expect(respuesta.statusCode).toBe(201);

    const { seccion } = respuesta.json();
    expect(seccion.nombre).toBe('SB');
    expect(seccion.cupoMaximo).toBe(20);
    expect(seccion.activa).toBe(true);
    expect(seccion.id).toMatch(/^[0-9a-f-]{36}$/);

    // Y queda listada.
    const listado = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/secciones?periodo=2026-2',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(listado.json().total).toBe(1);
  });

  it('sin cupoMaximo, la sección nace para usar el global', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...NUEVA, cupoMaximo: undefined },
    });

    expect(respuesta.statusCode).toBe(201);
    // `null`, no 0: sólo `null` cae al cupo global del centro.
    expect(respuesta.json().seccion.cupoMaximo).toBeNull();
  });

  it('acepta cupo 0, que es una sección sin cupo y no un error', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...NUEVA, cupoMaximo: 0 },
    });

    expect(respuesta.statusCode).toBe(201);
    // 0 se conserva como 0: tratarlo como «sin definir» haría que la sección
    // cayera al global, que es justo lo contrario de lo que pidió el admin.
    expect(respuesta.json().seccion.cupoMaximo).toBe(0);
  });

  it('rechaza un nombre de más de 5 caracteres', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...NUEVA, nombre: 'SECCION-LARGA' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
  });

  it('rechaza un cupo negativo', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...NUEVA, cupoMaximo: -1 },
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('rechaza un identificador que no sea UUID', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...NUEVA, programaId: 'no-es-un-uuid' },
    });

    expect(respuesta.statusCode).toBe(400);
    // El mensaje de primer nivel es genérico a propósito (el cliente lee el
    // código), pero el campo concreto viaja en `detalles`, que es lo que permite
    // a la interfaz señalar el input que falló. Zod da ese detalle antes de abrir
    // una transacción.
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    expect(respuesta.json().error.detalles).toEqual([
      { campo: 'programaId', problema: expect.stringContaining('UUID') },
    ]);
  });

  it('rechaza un lapso que no está registrado', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    // La FK `sections_period_code_fkey` apunta a `academic_periods`. Zod no puede
    // comprobarlo —depende de la base—, así que el rechazo viene de la clave ajena.
    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { ...NUEVA, periodo: '2099-9' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('REFERENCIA_INVALIDA');
  });

  it('rechaza un nombre repetido en el mismo lapso y materia con 409', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      // 'SA' ya existe para Algorítmica en 2026-1.
      payload: { ...NUEVA, periodo: '2026-1', nombre: 'SA' },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json().error.codigo).toBe('REGISTRO_DUPLICADO');
  });

  it('rechaza campos desconocidos en lugar de ignorarlos', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/admin/secciones',
      headers: conToken(TOKEN_ADMIN),
      // `id` y `activa` no se aceptan al crear: los pone la base. El `.strict()`
      // convierte mandarlos en un 400 que nombra el campo, en vez de tragárselos.
      payload: { ...NUEVA, id: ID_SECCION_SA, activa: true },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('actualizar una sección', () => {
  it('cambia el cupo', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/secciones/${ID_SECCION_SA}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { cupoMaximo: 12 },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().seccion.cupoMaximo).toBe(12);
  });

  it('vuelve al cupo global con cupoMaximo: null explícito', async () => {
    const arnes = crearArnés({ secciones: [{ id: ID_SECCION_SA, programaId: ID_PROGRAMA_SISTEMAS, materiaId: ID_MATERIA_ALGORITMICA, periodo: '2026-1', nombre: 'SA', cupoMaximo: 15 }] });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/secciones/${ID_SECCION_SA}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { cupoMaximo: null },
    });

    expect(respuesta.statusCode).toBe(200);
    // `null` es un cambio legítimo, no la ausencia de cambio. Si el repositorio lo
    // comprobara por veracidad, este `null` se descartaría en silencio y el cupo
    // se quedaría en 15 sin que nadie se enterara.
    expect(respuesta.json().seccion.cupoMaximo).toBeNull();
  });

  it('archiva con activa: false', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/secciones/${ID_SECCION_SA}`,
      headers: conToken(TOKEN_ADMIN),
      payload: { activa: false },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().seccion.activa).toBe(false);
  });

  it('devuelve 404 si la sección no existe', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/secciones/ffffffff-0000-4000-8000-000000000000',
      headers: conToken(TOKEN_ADMIN),
      payload: { cupoMaximo: 5 },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SECCION_INEXISTENTE');
  });

  it('rechaza un cambio vacío', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/secciones/${ID_SECCION_SA}`,
      headers: conToken(TOKEN_ADMIN),
      payload: {},
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('rechaza intentar cambiar la identidad de la sección', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    // Programa, materia y lapso forman la identidad (`unique (period_code,
    // subject_id, name)`). Cambiarlos no sería editar la sección, sería
    // convertirla en otra llevándose el historial de inscripciones de su id.
    for (const campo of ['programaId', 'materiaId', 'periodo']) {
      const respuesta = await app.inject({
        method: 'PATCH',
        url: `/api/v1/admin/secciones/${ID_SECCION_SA}`,
        headers: conToken(TOKEN_ADMIN),
        payload: { [campo]: ID_PROGRAMA_SISTEMAS },
      });

      expect(respuesta.statusCode, campo).toBe(400);
    }
  });
});
