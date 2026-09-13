import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { crearArnés } from './support/arnes.js';

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

describe('sondas de salud', () => {
  it('/salud responde sin tocar la base de datos', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: '/salud' });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ estado: 'ok' });
    expect(arnés.llamadas).not.toContain('modulos.todos');
  });

  it('/salud/profundo confirma que la base de datos responde', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: '/salud/profundo' });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      estado: 'ok',
      baseDeDatos: 'ok',
    });
  });

  it('/salud/profundo devuelve 503 si la base de datos falla', async () => {
    const arnés = crearArnés();
    app = arnés.app;
    arnés.fallos['modulos.todos'] = new Error('sin conexión');

    const respuesta = await app.inject({ method: 'GET', url: '/salud/profundo' });

    // 503 y no 500: el proceso está vivo, lo que falla es la dependencia.
    // Distinguirlo evita que el orquestador reinicie en bucle un contenedor sano.
    expect(respuesta.statusCode).toBe(503);
    expect(respuesta.json()).toMatchObject({
      estado: 'degradado',
      baseDeDatos: 'inalcanzable',
    });
  });

  it('una ruta inexistente devuelve un error con la misma forma que el resto', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/no-existe' });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toEqual({
      error: {
        codigo: 'RUTA_NO_ENCONTRADA',
        mensaje: 'No existe GET /api/v1/no-existe.',
      },
    });
  });
});
