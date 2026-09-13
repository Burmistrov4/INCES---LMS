import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { ErrorApi } from '../src/dominio/errores.js';
import type { PuertaParametros } from '../src/dominio/puertos.js';
import type { ParametroSistema } from '../src/dominio/tipos.js';
import { CacheParametros } from '../src/infra/cache.js';
import {
  pareceErrorPostgres,
  traducirError,
} from '../src/infra/traducir-error.js';
import { conToken, crearArnés, TOKEN_ALUMNO } from './support/arnes.js';

/**
 * Tests de regresión de tres fallos reales, detectados al arrancar el binario
 * compilado contra una URL de Supabase inexistente:
 *
 *   1. Un fallo de red llegaba como `{ code: '', message: 'TypeError: fetch
 *      failed' }`. La comprobación de "¿es un error de Postgres?" aceptaba el
 *      código vacío, así que se reportaba 500 en lugar de 503.
 *   2. El guardián de mantenimiento corría en `onRequest`, antes del enrutado,
 *      de modo que una ruta inexistente devolvía un error de base de datos en
 *      vez de 404.
 *   3. Si la lectura de `modo_mantenimiento` fallaba, se bloqueaba TODO el
 *      tráfico con un 503 que decía "mantenimiento" cuando el problema era otro.
 */

/** Error con la forma exacta que produce Supabase ante un fallo de transporte. */
const ERROR_DE_RED_DE_SUPABASE = {
  code: '',
  message: 'TypeError: fetch failed',
  details: '',
  hint: '',
};

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

describe('1. clasificación de errores de Supabase', () => {
  it('un código vacío NO se considera error de Postgres', () => {
    expect(pareceErrorPostgres({ code: '' })).toBe(false);
    expect(pareceErrorPostgres({ code: '23505' })).toBe(true);
    expect(pareceErrorPostgres({})).toBe(false);
    expect(pareceErrorPostgres(null)).toBe(false);
  });

  it('un fallo de transporte se traduce a 503, no a 500', () => {
    const traducido = traducirError(ERROR_DE_RED_DE_SUPABASE, 'listar módulos');

    expect(traducido.estado).toBe(503);
    expect(traducido.codigo).toBe('SUPABASE_INALCANZABLE');
  });

  it('también reconoce el fallo de red cuando llega como Error de Node', () => {
    const traducido = traducirError(new TypeError('fetch failed'), 'listar');

    expect(traducido.estado).toBe(503);
  });

  it('reconoce el fallo de red aunque el objeto no sea una instancia de Error', () => {
    const traducido = traducirError({ message: 'ECONNREFUSED 127.0.0.1:5432' }, 'listar');

    expect(traducido.estado).toBe(503);
  });

  it('los códigos reales de Postgres siguen traduciéndose bien', () => {
    // Regresión: al endurecer la detección no se debe romper lo que ya funcionaba.
    expect(traducirError({ code: '23505', message: 'duplicado' }, 'x').estado).toBe(409);
    expect(traducirError({ code: '23514', message: 'check' }, 'x').estado).toBe(400);
    expect(traducirError({ code: '42501', message: 'rls' }, 'x').estado).toBe(403);
    expect(traducirError({ code: 'PGRST116', message: 'sin filas' }, 'x').estado).toBe(404);
    expect(traducirError({ code: '42P01', message: 'no existe la tabla' }, 'x').codigo).toBe(
      'ESQUEMA_DESACTUALIZADO',
    );
  });

  it('un ErrorApi ya tipado se devuelve tal cual, sin reenvolverlo', () => {
    const original = ErrorApi.prohibido('X', 'no puedes');
    expect(traducirError(original, 'contexto')).toBe(original);
  });
});

describe('3. el modo mantenimiento falla abierto', () => {
  class PuertaParametrosQueFalla implements PuertaParametros {
    async todos(_incluirPrivados: boolean): Promise<ParametroSistema[]> {
      throw ERROR_DE_RED_DE_SUPABASE;
    }
    async porClave(_clave: string): Promise<ParametroSistema | null> {
      throw ERROR_DE_RED_DE_SUPABASE;
    }
    async actualizar(_clave: string, _valor: unknown): Promise<ParametroSistema> {
      throw ERROR_DE_RED_DE_SUPABASE;
    }
  }

  it('si no se puede leer el parámetro, NO se bloquea el tráfico', async () => {
    const cache = new CacheParametros(new PuertaParametrosQueFalla(), 0);

    await expect(cache.mantenimientoActivo()).resolves.toBe(false);
  });

  it('con la base de datos caída, una petición sin sesión sigue dando 401 y no 500', async () => {
    const arnés = crearArnés();
    app = arnés.app;
    arnés.fallos['parametros.todos'] = ERROR_DE_RED_DE_SUPABASE;

    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/yo' });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'NO_AUTENTICADO' } });
  });

  it('con la base de datos caída, un usuario con sesión recibe 503, no 500', async () => {
    const arnés = crearArnés();
    app = arnés.app;
    arnés.fallos['parametros.todos'] = ERROR_DE_RED_DE_SUPABASE;
    arnés.fallos['modulos.todos'] = ERROR_DE_RED_DE_SUPABASE;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(503);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'SUPABASE_INALCANZABLE' },
    });
  });
});

describe('2. rutas inexistentes durante una avería', () => {
  it('una ruta que no existe devuelve 404 aunque la base de datos esté caída', async () => {
    const arnés = crearArnés();
    app = arnés.app;
    arnés.fallos['parametros.todos'] = ERROR_DE_RED_DE_SUPABASE;
    arnés.fallos['modulos.todos'] = ERROR_DE_RED_DE_SUPABASE;

    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/no-existe' });

    // El fallo original: el guardián de mantenimiento lanzaba antes del 404 y
    // el cliente recibía un 500 sobre una ruta que ni siquiera existe.
    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'RUTA_NO_ENCONTRADA' },
    });
  });

  it('con el sistema en mantenimiento, una ruta inexistente también da 503', async () => {
    // Comportamiento deliberado: Fastify ejecuta los hooks `preValidation`
    // incluso cuando no hay ruta (comprobado empíricamente). Durante el
    // mantenimiento la API está cerrada por completo, así que responder 503 a
    // cualquier ruta es lo coherente. Lo que NO puede pasar es un 500.
    const arnés = crearArnés({
      parametros: [
        {
          clave: 'modo_mantenimiento',
          valor: true,
          tipo: 'boolean',
          descripcion: null,
          categoria: 'general',
          esPublico: true,
          actualizadoEn: null,
        },
      ],
    });
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/no-existe' });

    expect(respuesta.statusCode).toBe(503);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'SERVICIO_NO_DISPONIBLE' },
    });
  });
});
