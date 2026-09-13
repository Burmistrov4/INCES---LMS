import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { extraerToken } from '../src/http/plugins/autenticacion.js';
import {
  conToken,
  crearArnés,
  ID_ALUMNO,
  PERFIL_ALUMNO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
} from './support/arnes.js';

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

describe('lectura de la cabecera Authorization', () => {
  it('extrae el token de un Bearer bien formado', () => {
    expect(extraerToken('Bearer abc.def.ghi')).toBe('abc.def.ghi');
  });

  it('acepta el esquema en minúsculas', () => {
    expect(extraerToken('bearer abc')).toBe('abc');
  });

  it('ignora esquemas que no son Bearer', () => {
    expect(extraerToken('Basic dXNlcjpwYXNz')).toBeNull();
  });

  it('rechaza una cabecera sin token o mal formada', () => {
    expect(extraerToken(undefined)).toBeNull();
    expect(extraerToken('')).toBeNull();
    expect(extraerToken('Bearer')).toBeNull();
    expect(extraerToken('Bearer   ')).toBeNull();
    expect(extraerToken('Bearer a b')).toBeNull();
  });
});

describe('resolución de la identidad', () => {
  it('sin cabecera, la petición queda anónima', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(null),
    });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'NO_AUTENTICADO' },
    });
  });

  it('con un token inválido, tampoco hay sesión', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken('token-inventado'),
    });

    expect(respuesta.statusCode).toBe(401);
  });

  it('devuelve el perfil y el rol del usuario autenticado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      rol: 'estudiante',
      perfil: { id: ID_ALUMNO, email: PERFIL_ALUMNO.email },
    });
  });

  it('una cuenta desactivada no puede entrar, aunque el token sea válido', async () => {
    const arnés = crearArnés({
      perfiles: [{ ...PERFIL_ALUMNO, activo: false }],
    });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'CUENTA_INACTIVA' },
    });
  });

  it('si falta el perfil, degrada a estudiante en vez de expulsar al usuario', async () => {
    // Ocurre con cuentas creadas antes del trigger de onboarding. Expulsarlas
    // dejaría fuera a personas legítimas; el rol mínimo es la opción segura.
    const arnés = crearArnés({ perfiles: [] });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ rol: 'estudiante' });
  });
});

describe('/api/v1/modulos', () => {
  it('exige sesión', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: '/api/v1/modulos' });

    expect(respuesta.statusCode).toBe(401);
  });

  it('no incluye los módulos apagados', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/modulos',
      headers: conToken(TOKEN_ADMIN),
    });

    const claves = (respuesta.json() as { modulos: { clave: string }[] }).modulos.map(
      (m) => m.clave,
    );

    expect(claves).toContain('m0_cpanel');
    expect(claves).not.toContain('m4_inscripciones');
  });

  it('oculta los módulos restringidos a otros roles', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/modulos',
      headers: conToken(TOKEN_ALUMNO),
    });

    const claves = (respuesta.json() as { modulos: { clave: string }[] }).modulos.map(
      (m) => m.clave,
    );

    // m0_cpanel está restringido a admin.
    expect(claves).not.toContain('m0_cpanel');
    expect(claves).toContain('m1_onboarding');
  });
});
