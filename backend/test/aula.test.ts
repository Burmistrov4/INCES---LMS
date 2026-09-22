import type { SupabaseClient } from '@supabase/supabase-js';
import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { ErrorApi } from '../src/dominio/errores.js';
import { crearRepositorios } from '../src/infra/repos-supabase.js';
import {
  ANUNCIOS_POR_DEFECTO,
  conToken,
  crearArnés,
  ENTREGAS_POR_DEFECTO,
  ID_ALUMNO,
  ID_ANUNCIO_SA,
  ID_DOCENTE,
  ID_ENTREGA_SA,
  ID_SECCION_SA,
  ID_TAREA_BORRADOR,
  ID_TAREA_SA,
  MODULOS_POR_DEFECTO,
  TAREAS_POR_DEFECTO,
  TOKEN_ALUMNO,
  TOKEN_DOCENTE,
  type Arnés,
} from './support/arnes.js';

/**
 * M6 — el aula virtual, de punta a punta sobre el arnés en memoria.
 *
 * Se comprueba el **contrato HTTP**: control de acceso, validación, códigos de
 * estado, forma de las respuestas y la frontera de la nota en borrador.
 *
 * **Lo que estas pruebas NO pueden demostrar, y conviene tenerlo escrito:**
 *
 *   · Que la RLS deje de ver el anuncio o la entrega de otro. El doble reproduce
 *     las políticas para que las rutas traten bien lo que dejan pasar, pero quien
 *     las aplica es Postgres: eso sólo se comprueba contra la nube (lección
 *     R-23).
 *   · Que las RPC sean `security definer` y hagan su propia autorización. Aquí
 *     las llama un objeto en memoria.
 *
 * Lo que **sí** se prueba aquí, además del contrato, es lo que vive en este
 * repositorio: que `misEntregas` seleccione sólo las columnas concedidas —nunca
 * `nota_borrador`—, que las escrituras vayan por `rpc(...)` con los nombres de
 * argumento exactos, y que la traducción de `42501` y `23514` conserve el
 * mensaje de la RPC. Eso último se ejercita contra un cliente de Supabase
 * **falso** (un doble del cliente, no del repositorio): el arnés sustituye el
 * repositorio entero, así que no puede ver lo que ocurre dentro de él.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

/** Las once rutas del módulo, con ids válidos, para las pruebas de acceso. */
const RUTAS = [
  { method: 'GET' as const, url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tablon` },
  { method: 'POST' as const, url: `/api/v1/aula/secciones/${ID_SECCION_SA}/anuncios` },
  { method: 'GET' as const, url: `/api/v1/aula/secciones/${ID_SECCION_SA}/trabajo` },
  { method: 'POST' as const, url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tareas` },
  { method: 'POST' as const, url: `/api/v1/aula/tareas/${ID_TAREA_SA}/publicar` },
  { method: 'GET' as const, url: `/api/v1/aula/tareas/${ID_TAREA_SA}/entregas` },
  { method: 'GET' as const, url: '/api/v1/aula/mis-entregas' },
  { method: 'POST' as const, url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar` },
  { method: 'POST' as const, url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/reclamar` },
  { method: 'POST' as const, url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/calificar` },
  { method: 'POST' as const, url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/devolver` },
];

/** Un anuncio en borrador, del docente, que el alumno **no** debe ver. */
const ID_ANUNCIO_BORRADOR = 'a6a6a6a6-0002-4002-8002-000000000002';

/** El arnés con `m6_aula_virtual` apagado, como si el administrador lo apagara. */
function conModuloApagado(): Arnés {
  return crearArnés({
    modulos: MODULOS_POR_DEFECTO.map((m) =>
      m.clave === 'm6_aula_virtual' ? { ...m, habilitado: false } : m,
    ),
  });
}

describe('control de acceso al aula', () => {
  it('exige sesión en las once rutas', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const ruta of RUTAS) {
      const respuesta = await app.inject({ method: ruta.method, url: ruta.url });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
      expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
    }
  });

  it('sin token responde 401 aunque el módulo esté apagado: la sesión se comprueba primero', async () => {
    // El orden del `preHandler` no es cosmético, y esta es la prueba que lo
    // fija. Con el módulo **encendido**, las dos órdenes darían 401 y la
    // inversión pasaría inadvertida. Con el módulo apagado, en cambio, la
    // guardia de módulo colocada primero respondería 403 —«el módulo está
    // apagado»— a quien ni siquiera ha dicho quién es: un mensaje que manda a
    // revisar la configuración cuando lo que falta es entrar. El 401 es del
    // llamante; el 403, del sistema, y por eso la sesión va primero.
    const arnes = conModuloApagado();
    app = arnes.app;

    for (const ruta of RUTAS) {
      const respuesta = await app.inject({ method: ruta.method, url: ruta.url });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
      expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
    }
  });
});

describe('la guardia del módulo (m6_aula_virtual)', () => {
  it('con el módulo apagado, las once rutas responden 403 y no llegan a tocar nada', async () => {
    // Ésta es la prueba que da sentido a la bandera, y sin ella la guardia sería
    // fe. El módulo arranca **encendido** en el arnés, así que una guardia
    // cableada a la clave equivocada —`m6_aula`, sin el `_virtual`— nunca se
    // notaría: todas las demás pruebas seguirían verdes. Apagarlo es la única
    // forma de distinguir «la guardia funciona» de «la guardia no se ejecuta».
    const arnes = conModuloApagado();
    app = arnes.app;

    const anunciosAntes = arnes.estado.anuncios.length;
    const tareasAntes = arnes.estado.tareas.length;
    const entregasAntes = arnes.estado.entregas.length;

    for (const ruta of RUTAS) {
      const respuesta = await app.inject({
        method: ruta.method,
        url: ruta.url,
        headers: conToken(TOKEN_DOCENTE),
      });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(403);
      expect(respuesta.json().error.codigo).toBe('MODULO_DESHABILITADO');
    }

    // Y el corte ocurre **antes** del efecto: ni un anuncio, ni una tarea, ni una
    // entrega de más. Una guardia que dejara pasar la escritura y fallara al
    // responder no sería una guardia, sería un 403 que esconde un daño ya hecho.
    expect(arnes.estado.anuncios).toHaveLength(anunciosAntes);
    expect(arnes.estado.tareas).toHaveLength(tareasAntes);
    expect(arnes.estado.entregas).toHaveLength(entregasAntes);
  });

  it('sin la fila del módulo el error es 404 MODULO_DESCONOCIDO, y no 403', async () => {
    // La distinción no es cosmética. `comprobarModulo` separa «no está
    // registrado» de «está apagado» a propósito: confundirlos manda a buscar el
    // problema al sitio equivocado —a la bandera, cuando lo que falta es la
    // semilla—.
    const arnes = crearArnés({ modulos: [] });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tablon`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('MODULO_DESCONOCIDO');
  });
});

describe('validación de entrada', () => {
  it('un id que no es UUID da 400 antes de tocar la base', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const casos = [
      { method: 'GET' as const, url: '/api/v1/aula/secciones/no-soy-uuid/tablon' },
      { method: 'POST' as const, url: '/api/v1/aula/tareas/no-soy-uuid/publicar' },
      { method: 'POST' as const, url: '/api/v1/aula/entregas/no-soy-uuid/entregar' },
    ];

    for (const caso of casos) {
      const respuesta = await app.inject({
        ...caso,
        headers: conToken(TOKEN_DOCENTE),
      });

      expect(respuesta.statusCode, `${caso.method} ${caso.url}`).toBe(400);
      expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    }
  });

  it('un tipo de trabajo inventado da 400, y no llega a crear la tarea', async () => {
    // Es el motivo de que `tipo` sea un enum y no una cadena: un valor inventado
    // rechazado aquí da un 400 que nombra el campo. Si viajara como texto libre,
    // Postgres devolvería el `23514` de un `check` sin decir cuál.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tareas`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { titulo: 'Práctica', tipo: 'EXAMEN_SORPRESA' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    expect(arnes.estado.tareas).toHaveLength(TAREAS_POR_DEFECTO.length);
  });

  it('una nota fuera de 0–20 da 400', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const nota of [-1, 21, 'diez']) {
      const respuesta = await app.inject({
        method: 'POST',
        url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/calificar`,
        headers: conToken(TOKEN_DOCENTE),
        payload: { nota },
      });

      expect(respuesta.statusCode, `nota=${String(nota)}`).toBe(400);
    }
  });

  it('un cuerpo con campos desconocidos se rechaza en vez de ignorarse', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/anuncios`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { titulo: 'Aviso', es_critico: true },
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('el tablón', () => {
  it('el alumno ve los anuncios publicados de su sección', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tablon`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);

    const { anuncios } = respuesta.json();
    expect(anuncios.map((a: { id: string }) => a.id)).toContain(ID_ANUNCIO_SA);
    expect(anuncios[0].titulo).toBe('Bienvenidos al lapso');
  });

  it('el alumno no ve los borradores; el docente de la sección sí', async () => {
    const arnes = crearArnés({
      anuncios: [
        ...ANUNCIOS_POR_DEFECTO,
        {
          id: ID_ANUNCIO_BORRADOR,
          seccionId: ID_SECCION_SA,
          autorId: ID_DOCENTE,
          titulo: 'Sin publicar',
        },
      ],
    });
    app = arnes.app;

    const delAlumno = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tablon`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(delAlumno.json().anuncios.map((a: { id: string }) => a.id)).not.toContain(
      ID_ANUNCIO_BORRADOR,
    );

    const delDocente = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tablon`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(delDocente.json().anuncios.map((a: { id: string }) => a.id)).toContain(
      ID_ANUNCIO_BORRADOR,
    );
  });
});

describe('publicar un anuncio', () => {
  it('el docente de la sección lo crea y nace BORRADOR', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/anuncios`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { titulo: 'Aviso', cuerpo: 'Traer el material el lunes.' },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json().anuncio.estado).toBe('BORRADOR');
    expect(respuesta.json().anuncio.cuerpo).toBe('Traer el material el lunes.');
    expect(respuesta.json().anuncio.autorId).toBe(ID_DOCENTE);
  });

  it('un alumno no puede publicar: 403 con el mensaje de la RPC', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/anuncios`,
      headers: conToken(TOKEN_ALUMNO),
      payload: { titulo: 'Aviso' },
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.mensaje).toContain('No dictas la sección');
    expect(arnes.estado.anuncios).toHaveLength(ANUNCIOS_POR_DEFECTO.length);
  });
});

describe('el trabajo de clase', () => {
  it('el alumno ve lo publicado, y no el borrador', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/trabajo`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);

    const ids = respuesta.json().tareas.map((t: { id: string }) => t.id);
    expect(ids).toContain(ID_TAREA_SA);
    expect(ids).not.toContain(ID_TAREA_BORRADOR);
  });

  it('el docente ve también sus borradores', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/trabajo`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.json().tareas.map((t: { id: string }) => t.id)).toContain(
      ID_TAREA_BORRADOR,
    );
  });
});

describe('crear trabajo de clase', () => {
  it('el docente crea una tarea y nace BORRADOR y sin entregas', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tareas`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { titulo: 'Práctica 3', puntosMaximos: 15 },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json().tarea.estado).toBe('BORRADOR');
    expect(respuesta.json().tarea.tipo).toBe('TAREA');
    expect(respuesta.json().tarea.puntosMaximos).toBe(15);
    // Publicar es lo que crea los placeholders, no crear.
    expect(arnes.estado.entregas).toHaveLength(ENTREGAS_POR_DEFECTO.length);
  });

  it('un MATERIAL con puntos se rechaza con 400 y el mensaje de la RPC', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    // Sin `puntosMaximos`, el valor por defecto es 20, y un MATERIAL no lleva
    // puntos: la RPC lo dice con un mensaje que se entiende.
    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tareas`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { titulo: 'Lectura', tipo: 'MATERIAL' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('RESTRICCION_VIOLADA');
    expect(respuesta.json().error.mensaje).toContain('MATERIAL');
  });

  it('un MATERIAL con cero puntos sí se crea: es de lectura', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tareas`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { titulo: 'Lectura', tipo: 'MATERIAL', puntosMaximos: 0 },
    });

    expect(respuesta.statusCode).toBe(201);
    expect(respuesta.json().tarea.tipo).toBe('MATERIAL');
  });

  it('un alumno no puede crear trabajo: 403', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/secciones/${ID_SECCION_SA}/tareas`,
      headers: conToken(TOKEN_ALUMNO),
      payload: { titulo: 'Mi tarea' },
    });

    expect(respuesta.statusCode).toBe(403);
    expect(arnes.estado.tareas).toHaveLength(TAREAS_POR_DEFECTO.length);
  });
});

describe('publicar una tarea', () => {
  it('crea un placeholder de entrega por matrícula ENROLLED', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/tareas/${ID_TAREA_BORRADOR}/publicar`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().tarea.estado).toBe('PUBLICADO');
    expect(respuesta.json().entregasCreadas).toBe(1);

    const creadas = arnes.estado.entregas.filter((e) => e.tareaId === ID_TAREA_BORRADOR);
    expect(creadas).toHaveLength(1);
    expect(creadas[0]?.estudianteId).toBe(ID_ALUMNO);
    expect(creadas[0]?.estado).toBe('ASIGNADA');
  });

  it('publicar dos veces no duplica entregas: es idempotente', async () => {
    // Un botón que se puede pulsar dos veces no puede crear dos entregas por
    // alumno. Lo garantiza el `unique (tarea_id, estudiante_id)` con
    // `on conflict do nothing` en la base; el doble lo reproduce.
    const arnes = crearArnés();
    app = arnes.app;

    const primera = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/tareas/${ID_TAREA_BORRADOR}/publicar`,
      headers: conToken(TOKEN_DOCENTE),
    });
    const segunda = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/tareas/${ID_TAREA_BORRADOR}/publicar`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(primera.json().entregasCreadas).toBe(1);
    expect(segunda.statusCode).toBe(200);
    expect(segunda.json().entregasCreadas).toBe(0);

    expect(
      arnes.estado.entregas.filter((e) => e.tareaId === ID_TAREA_BORRADOR),
    ).toHaveLength(1);
  });

  it('un alumno no puede publicar la tarea: 403', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/tareas/${ID_TAREA_BORRADOR}/publicar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(arnes.estado.entregas).toHaveLength(ENTREGAS_POR_DEFECTO.length);
  });
});

describe('el libro de calificaciones', () => {
  it('el docente lo lee con la nota borrador y el «faltante» derivado', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
          notaBorrador: 15,
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/tareas/${ID_TAREA_SA}/entregas`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);

    const entrega = respuesta.json().entregas[0];
    expect(entrega.estudianteId).toBe(ID_ALUMNO);
    expect(entrega.notaBorrador).toBe(15);
    expect(entrega.faltante).toBe(false);
  });

  it('el alumno recibe una lista vacía, no un 403: la RPC filtra por docente', async () => {
    // `m6_entregas_de_tarea` no lanza 42501 si el llamante no dicta: filtra con
    // `m6_dicta_entrega`. El contrato es una lista vacía, y el doble lo respeta.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/tareas/${ID_TAREA_SA}/entregas`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entregas).toEqual([]);
  });
});

describe('la frontera de la nota en borrador', () => {
  it('el alumno nunca recibe `notaBorrador`; el docente siempre', async () => {
    // Es la garantía de la decisión 3 y la razón de que `m6_entregas` tenga
    // `GRANT` por columna: el alumno no puede ver la nota antes de que el
    // docente devuelva. Se inspecciona el JSON serializado porque es lo que
    // viaja de verdad: comprobar el objeto tipado no vería una propiedad que se
    // colara por un `select('*')`.
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
          notaBorrador: 19,
        },
      ],
    });
    app = arnes.app;

    const delAlumno = await app.inject({
      method: 'GET',
      url: '/api/v1/aula/mis-entregas',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(delAlumno.statusCode).toBe(200);
    expect(delAlumno.body).not.toContain('notaBorrador');
    expect(delAlumno.json().entregas[0]).not.toHaveProperty('notaBorrador');

    const delDocente = await app.inject({
      method: 'GET',
      url: `/api/v1/aula/tareas/${ID_TAREA_SA}/entregas`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(delDocente.body).toContain('notaBorrador');
    expect(delDocente.json().entregas[0].notaBorrador).toBe(19);
  });
});

describe('mis entregas', () => {
  it('el alumno ve sus entregas con la nota ya asignada', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'DEVUELTA',
          notaBorrador: 16,
          notaAsignada: 16,
          entregadaEn: '2026-09-10T10:00:00.000Z',
          devueltaEn: '2026-09-12T10:00:00.000Z',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/aula/mis-entregas',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);

    const entrega = respuesta.json().entregas[0];
    expect(entrega.estado).toBe('DEVUELTA');
    expect(entrega.notaAsignada).toBe(16);
  });

  it('el alumno no ve la entrega de otro compañero', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: '99999999-9999-4999-8999-999999999999',
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/aula/mis-entregas',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entregas).toEqual([]);
  });
});

describe('entregar', () => {
  it('el alumno entrega su tarea y se marca a tiempo', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entrega.estado).toBe('ENTREGADA');
    expect(respuesta.json().entrega.esTardia).toBe(false);
    expect(respuesta.json().entrega.entregadaEn).not.toBeNull();
  });

  it('entregar después de la fecha límite marca `esTardia`', async () => {
    const arnes = crearArnés({
      tareas: [
        {
          id: ID_TAREA_SA,
          seccionId: ID_SECCION_SA,
          titulo: 'Práctica 1',
          estado: 'PUBLICADO',
          fechaLimite: '2020-01-01T00:00:00.000Z',
          permitirEntregaTardia: true,
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entrega.esTardia).toBe(true);
  });

  it('una tarea cerrada sin tardías da 400 con la fecha en el mensaje', async () => {
    const arnes = crearArnés({
      tareas: [
        {
          id: ID_TAREA_SA,
          seccionId: ID_SECCION_SA,
          titulo: 'Práctica 1',
          estado: 'PUBLICADO',
          fechaLimite: '2020-01-01T00:00:00.000Z',
          permitirEntregaTardia: false,
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.mensaje).toContain('no admite entregas tardías');
  });

  it('un alumno no puede entregar la entrega de otro: 403', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: '99999999-9999-4999-8999-999999999999',
          estado: 'ASIGNADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.mensaje).toContain('no es tuya');
  });

  it('no se puede volver a entregar una ya entregada sin reclamarla', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.mensaje).toContain('Reclámala');
  });
});

describe('reclamar', () => {
  it('sin token responde 401: la sesión va antes que la guardia de módulo', async () => {
    // La ruta existe para el botón «Reclamar entrega» de la UI. Si el
    // `preHandler` estuviera invertido, una petición anónima con el módulo
    // apagado recibiría 403 y el cliente creería que el problema es la bandera.
    const arnes = conModuloApagado();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/reclamar`,
    });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
  });

  it('el alumno reclama su entrega entregada y vuelve a RECLAMADA, en camelCase', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
          esTardia: false,
          entregadaEn: '2026-09-01T10:00:00.000Z',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/reclamar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);

    const { entrega } = respuesta.json();
    expect(entrega.estado).toBe('RECLAMADA');
    expect(entrega.id).toBe(ID_ENTREGA_SA);
    expect(entrega.tareaId).toBe(ID_TAREA_SA);
    // La misma `Entrega` camelCase que devuelve `entregar`: sin `nota_borrador`.
    expect(respuesta.body).not.toContain('notaBorrador');
    expect(respuesta.body).not.toContain('nota_borrador');
  });

  it('reclamar y volver a entregar cierra el ciclo', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const reclamada = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/reclamar`,
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(reclamada.statusCode).toBe(200);

    const entregada = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/entregar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(entregada.statusCode).toBe(200);
    expect(entregada.json().entrega.estado).toBe('ENTREGADA');
  });

  it('un alumno no puede reclamar la entrega de otro: 403', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: '99999999-9999-4999-8999-999999999999',
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/reclamar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.mensaje).toContain('no es tuya');
  });

  it('no se puede reclamar una entrega que no está ENTREGADA: 400', async () => {
    // El doble fiel a la RPC: reclamar una `ASIGNADA` no tiene sentido y una
    // `DEVUELTA` reabriría una nota que el alumno ya vio.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/reclamar`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.mensaje).toContain('ya entregada');
  });

  it('un id que no es UUID da 400 antes de tocar la base', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/aula/entregas/no-es-uuid/reclamar',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
  });
});

describe('calificar', () => {
  it('el docente escribe la nota borrador y el alumno todavía no la ve', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/calificar`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { nota: 17.5 },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entrega.notaBorrador).toBe(17.5);
    // Todavía no hay nota asignada: el ciclo no se ha cerrado.
    expect(respuesta.json().entrega.notaAsignada).toBeNull();
  });

  it('una nota por encima del máximo de la tarea da 400 con el mensaje de la RPC', async () => {
    const arnes = crearArnés({
      tareas: [
        {
          id: ID_TAREA_SA,
          seccionId: ID_SECCION_SA,
          titulo: 'Práctica 1',
          estado: 'PUBLICADO',
          puntosMaximos: 10,
        },
      ],
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/calificar`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { nota: 15 },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.mensaje).toContain('supera el máximo');
  });

  it('calificar un placeholder vacío da 400: no hay nada que calificar', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/calificar`,
      headers: conToken(TOKEN_DOCENTE),
      payload: { nota: 10 },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.mensaje).toContain('No hay nada que calificar');
  });

  it('un alumno no puede calificar: 403', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/calificar`,
      headers: conToken(TOKEN_ALUMNO),
      payload: { nota: 20 },
    });

    expect(respuesta.statusCode).toBe(403);
  });
});

describe('devolver', () => {
  it('copia el borrador a la nota asignada y cierra el ciclo', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
          notaBorrador: 16,
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/devolver`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entrega.estado).toBe('DEVUELTA');
    expect(respuesta.json().entrega.notaAsignada).toBe(16);

    // Y ahora sí, el alumno la ve en «mis entregas».
    const misEntregas = await app.inject({
      method: 'GET',
      url: '/api/v1/aula/mis-entregas',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(misEntregas.json().entregas[0].notaAsignada).toBe(16);
  });

  it('devolver sin nota es legítimo: es el «devuelta sin calificar» de Google', async () => {
    const arnes = crearArnés({
      entregas: [
        {
          id: ID_ENTREGA_SA,
          tareaId: ID_TAREA_SA,
          estudianteId: ID_ALUMNO,
          estado: 'ENTREGADA',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/devolver`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().entrega.estado).toBe('DEVUELTA');
    expect(respuesta.json().entrega.notaAsignada).toBeNull();
  });

  it('no hay nada que devolver en un placeholder: 400', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: `/api/v1/aula/entregas/${ID_ENTREGA_SA}/devolver`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.mensaje).toContain('No hay una entrega que devolver');
  });
});

// ---------------------------------------------------------------------------
//  El repositorio, contra un cliente de Supabase falso
// ---------------------------------------------------------------------------
//
//  El arnés sustituye el repositorio entero, así que no puede ver nada de lo que
//  ocurre dentro de él. Y dentro de él están dos cosas que ninguna prueba de ruta
//  puede comprobar: que las escrituras van por `rpc(...)` con los nombres de
//  argumento exactos —PostgREST los resuelve por nombre, así que un `p_codigo`
//  escrito como `codigo` sería un error de función inexistente en tiempo de
//  ejecución, no de compilación— y que la traducción de los errores conserva el
//  mensaje de la RPC.

interface RespuestaFalsa {
  data: unknown;
  error: unknown;
}

/** Un *builder* de PostgREST mínimo: encadenable y esperable. */
function consultaFalsa(
  respuesta: RespuestaFalsa,
  registrar: {
    alSeleccionar: (columnas: string) => void;
    alEscribir: (metodo: string) => void;
  },
) {
  const builder: Record<string, unknown> = {};

  builder.select = (columnas: string) => {
    registrar.alSeleccionar(columnas);
    return builder;
  };

  for (const metodo of ['eq', 'order', 'limit']) {
    builder[metodo] = () => builder;
  }

  // `insert` y `update` avisan por el llamante: es como esta prueba detecta una
  // escritura directa, que es lo que la RLS prohíbe en la base.
  for (const metodo of ['insert', 'update', 'delete']) {
    builder[metodo] = () => {
      registrar.alEscribir(metodo);
      return builder;
    };
  }

  builder.single = async () => respuesta;
  builder.maybeSingle = async () => respuesta;

  // Hace que `await builder` resuelva la respuesta, como el builder real.
  builder.then = (resolver: (valor: RespuestaFalsa) => unknown) =>
    Promise.resolve(respuesta).then(resolver);

  return builder;
}

function montarCliente(comportamiento: {
  rpc?: (funcion: string, argumentos: Record<string, unknown>) => RespuestaFalsa;
  tablas?: Record<string, RespuestaFalsa>;
}) {
  const rpcLlamadas: { funcion: string; argumentos: Record<string, unknown> }[] = [];
  const selecciones: { tabla: string; columnas: string }[] = [];
  const escriturasDirectas: string[] = [];

  const cliente = {
    rpc: async (funcion: string, argumentos: Record<string, unknown>) => {
      rpcLlamadas.push({ funcion, argumentos });
      return comportamiento.rpc?.(funcion, argumentos) ?? { data: null, error: null };
    },
    from: (tabla: string) =>
      consultaFalsa(comportamiento.tablas?.[tabla] ?? { data: [], error: null }, {
        alSeleccionar: (columnas) => selecciones.push({ tabla, columnas }),
        alEscribir: (metodo) => escriturasDirectas.push(`${metodo} ${tabla}`),
      }),
  } as unknown as SupabaseClient;

  return { cliente, rpcLlamadas, selecciones, escriturasDirectas };
}

/** Ejecuta una acción que debe fallar y devuelve el [ErrorApi]. */
async function capturarError(accion: () => Promise<unknown>): Promise<ErrorApi> {
  try {
    await accion();
  } catch (error) {
    if (error instanceof ErrorApi) return error;
    throw error;
  }
  throw new Error('Se esperaba un fallo y la operación terminó bien.');
}

const UUID_SECCION = 'cccccccc-0001-4001-8001-000000000001';
const UUID_TAREA = 'b7b7b7b7-0001-4001-8001-000000000001';
const UUID_ENTREGA = 'c8c8c8c8-0001-4001-8001-000000000001';
const UUID_ESTUDIANTE = '22222222-2222-4222-8222-222222222222';

/** Una fila de `m6_tareas` como la devuelve la RPC: en snake_case. */
const FILA_TAREA = {
  id: UUID_TAREA,
  seccion_id: UUID_SECCION,
  titulo: 'Práctica',
  descripcion: '',
  tipo: 'TAREA',
  puntos_maximos: 20,
  fecha_limite: null,
  permitir_entrega_tardia: true,
  tema: null,
  orden: 0,
  estado: 'BORRADOR',
  publicado_en: null,
};

const FILA_ENTREGA_CALIFICADA = {
  id: UUID_ENTREGA,
  tarea_id: UUID_TAREA,
  estudiante_id: UUID_ESTUDIANTE,
  estado: 'ENTREGADA',
  es_tardia: false,
  nota_borrador: 17.5,
  nota_asignada: null,
};

describe('las escrituras del aula van por RPC con los nombres exactos', () => {
  it('crearTarea llama a m6_crear_tarea con los nueve argumentos y ninguno directo', async () => {
    const { cliente, rpcLlamadas, escriturasDirectas } = montarCliente({
      rpc: () => ({ data: [FILA_TAREA], error: null }),
    });

    await crearRepositorios(cliente).aula.crearTarea({
      seccionId: UUID_SECCION,
      titulo: 'Práctica',
      descripcion: '',
      tipo: 'TAREA',
      puntosMaximos: 20,
      fechaLimite: null,
      permitirEntregaTardia: true,
      tema: null,
      orden: 0,
    });

    expect(rpcLlamadas).toEqual([
      {
        funcion: 'm6_crear_tarea',
        argumentos: {
          p_seccion_id: UUID_SECCION,
          p_titulo: 'Práctica',
          p_descripcion: '',
          p_tipo: 'TAREA',
          p_puntos_maximos: 20,
          p_fecha_limite: null,
          p_permitir_entrega_tardia: true,
          p_tema: null,
          p_orden: 0,
        },
      },
    ]);

    // Y ninguna escritura directa: la RLS prohíbe insertar en `m6_tareas`, así
    // que un `insert` colado daría 42501 en producción.
    expect(escriturasDirectas).toEqual([]);
  });

  it('calificar llama a m6_calificar_entrega con la entrega y la nota', async () => {
    const { cliente, rpcLlamadas } = montarCliente({
      rpc: () => ({ data: [FILA_ENTREGA_CALIFICADA], error: null }),
    });

    await crearRepositorios(cliente).aula.calificar(UUID_ENTREGA, 17.5);

    expect(rpcLlamadas[0]).toEqual({
      funcion: 'm6_calificar_entrega',
      argumentos: { p_entrega_id: UUID_ENTREGA, p_nota: 17.5 },
    });
  });

  it('devolver llama a m6_devolver_entrega con el id de la entrega', async () => {
    const { cliente, rpcLlamadas } = montarCliente({
      rpc: () => ({
        data: [{ ...FILA_ENTREGA_CALIFICADA, estado: 'DEVUELTA', devuelta_en: '2026-09-12T10:00:00.000Z' }],
        error: null,
      }),
    });

    await crearRepositorios(cliente).aula.devolver(UUID_ENTREGA);

    expect(rpcLlamadas[0]).toEqual({
      funcion: 'm6_devolver_entrega',
      argumentos: { p_entrega_id: UUID_ENTREGA },
    });
  });

  it('misEntregas lee las columnas concedidas y nunca `nota_borrador`', async () => {
    // Es la mitad del repositorio que el arnés no puede ver. Un `select('*')`
    // sobre `m6_entregas` no daría la columna en blanco: daría `42501`, porque
    // `authenticated` no tiene privilegio de SELECT sobre `nota_borrador`.
    const { cliente, selecciones } = montarCliente({
      tablas: { m6_entregas: { data: [], error: null } },
    });

    await crearRepositorios(cliente).aula.misEntregas();

    const seleccion = selecciones.find((s) => s.tabla === 'm6_entregas');
    expect(seleccion).toBeDefined();
    expect(seleccion?.columnas).not.toContain('*');
    expect(seleccion?.columnas).not.toContain('nota_borrador');
    expect(seleccion?.columnas).toContain('nota_asignada');
    expect(seleccion?.columnas).toContain('entregada_en');
  });
});

describe('traducción de los errores de las RPC', () => {
  it('un 42501 de autorización se traduce a 403 conservando el mensaje', async () => {
    const mensaje = 'No dictas la sección de la tarea: no puedes publicarla.';
    const { cliente } = montarCliente({
      rpc: () => ({ data: null, error: { code: '42501', message: mensaje } }),
    });

    const error = await capturarError(() =>
      crearRepositorios(cliente).aula.publicarTarea(UUID_TAREA),
    );

    expect(error.estado).toBe(403);
    expect(error.codigo).toBe('SIN_PERMISO_EN_EL_AULA');
    expect(error.message).toBe(mensaje);
  });

  it('un 42501 sin sesión se traduce a 401, no a 403', async () => {
    // La RPC lo dice con su propio texto. Confundirlo con un 403 mandaría al
    // usuario a revisar permisos cuando lo que le falta es entrar.
    const { cliente } = montarCliente({
      rpc: () => ({
        data: null,
        error: { code: '42501', message: 'Se requiere una sesión para publicar una tarea.' },
      }),
    });

    const error = await capturarError(() =>
      crearRepositorios(cliente).aula.publicarTarea(UUID_TAREA),
    );

    expect(error.estado).toBe(401);
    expect(error.codigo).toBe('NO_AUTENTICADO');
  });

  it('un 23514 se traduce a 400 conservando el mensaje de la RPC', async () => {
    const mensaje = 'Un MATERIAL es de lectura: no lleva puntos ni fecha límite.';
    const { cliente } = montarCliente({
      rpc: () => ({ data: null, error: { code: '23514', message: mensaje } }),
    });

    const error = await capturarError(() =>
      crearRepositorios(cliente).aula.crearTarea({
        seccionId: UUID_SECCION,
        titulo: 'Lectura',
        descripcion: '',
        tipo: 'MATERIAL',
        puntosMaximos: 20,
        fechaLimite: null,
        permitirEntregaTardia: true,
        tema: null,
        orden: 0,
      }),
    );

    expect(error.estado).toBe(400);
    expect(error.codigo).toBe('RESTRICCION_VIOLADA');
    expect(error.message).toBe(mensaje);
  });
});
