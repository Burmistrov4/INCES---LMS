import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { ErrorApi } from '../src/dominio/errores.js';
import type { PuertaModulos } from '../src/dominio/puertos.js';
import type { CambiosModulo, ModuloSistema } from '../src/dominio/tipos.js';
import { CacheModulos } from '../src/infra/cache.js';
import { comprobarModulo } from '../src/http/plugins/modulos.js';
import {
  conToken,
  crearArnés,
  modulo,
  parametro,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
} from './support/arnes.js';

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

/** Puerta que cuenta cuántas veces se ha consultado el catálogo. */
class PuertaModulosContadora implements PuertaModulos {
  llamadas = 0;

  constructor(public modulos: ModuloSistema[]) {}

  async todos(): Promise<ModuloSistema[]> {
    this.llamadas++;
    return [...this.modulos];
  }

  async porClave(clave: string): Promise<ModuloSistema | null> {
    this.llamadas++;
    return this.modulos.find((m) => m.clave === clave) ?? null;
  }

  async actualizar(_clave: string, _cambios: CambiosModulo): Promise<ModuloSistema> {
    throw new Error('no se usa en estos tests');
  }
}

describe('guardián de módulos (regla pura)', () => {
  function cacheCon(modulos: ModuloSistema[]): CacheModulos {
    return new CacheModulos(new PuertaModulosContadora(modulos), 0);
  }

  it('deja pasar un módulo encendido y abierto a todos', async () => {
    const cache = cacheCon([modulo({ clave: 'm1_onboarding' })]);

    await expect(comprobarModulo(cache, 'm1_onboarding', 'estudiante')).resolves.toBeUndefined();
  });

  it('rechaza un módulo apagado con 403 y código explícito', async () => {
    const cache = cacheCon([modulo({ clave: 'm4_inscripciones', habilitado: false })]);

    await expect(comprobarModulo(cache, 'm4_inscripciones', 'admin')).rejects.toMatchObject({
      estado: 403,
      codigo: 'MODULO_DESHABILITADO',
    });
  });

  it('un módulo apagado lo está incluso para el administrador', async () => {
    // El administrador puede encenderlo desde el cPanel, pero mientras esté
    // apagado el módulo no atiende a nadie. Si no, "apagado" no significaría nada.
    const cache = cacheCon([modulo({ clave: 'm6_asistencia', habilitado: false })]);

    await expect(comprobarModulo(cache, 'm6_asistencia', 'admin')).rejects.toMatchObject({
      codigo: 'MODULO_DESHABILITADO',
    });
  });

  it('rechaza un módulo restringido a otro rol', async () => {
    const cache = cacheCon([modulo({ clave: 'm0_cpanel', rolesPermitidos: ['admin'] })]);

    await expect(comprobarModulo(cache, 'm0_cpanel', 'estudiante')).rejects.toMatchObject({
      estado: 403,
      codigo: 'MODULO_NO_AUTORIZADO',
    });
  });

  it('rechaza un módulo restringido cuando no hay sesión', async () => {
    const cache = cacheCon([modulo({ clave: 'm0_cpanel', rolesPermitidos: ['admin'] })]);

    await expect(comprobarModulo(cache, 'm0_cpanel', null)).rejects.toMatchObject({
      codigo: 'MODULO_NO_AUTORIZADO',
    });
  });

  it('avisa con 404 si el módulo no está registrado', async () => {
    const cache = cacheCon([]);

    await expect(comprobarModulo(cache, 'm9_certificados', 'admin')).rejects.toMatchObject({
      estado: 404,
      codigo: 'MODULO_DESCONOCIDO',
    });
  });

  it('el error es un ErrorApi, no un Error suelto', async () => {
    const cache = cacheCon([]);

    await expect(comprobarModulo(cache, 'x', 'admin')).rejects.toBeInstanceOf(ErrorApi);
  });
});

describe('caché de módulos', () => {
  it('consulta la base de datos una sola vez mientras el TTL está vigente', async () => {
    const puerta = new PuertaModulosContadora([modulo({ clave: 'm1_onboarding' })]);
    const cache = new CacheModulos(puerta, 60_000);

    await cache.todos();
    await cache.todos();
    await cache.porClave('m1_onboarding');

    expect(puerta.llamadas).toBe(1);
  });

  it('vuelve a consultar tras invalidar (lo que hace el cPanel al cambiar un módulo)', async () => {
    const puerta = new PuertaModulosContadora([modulo({ clave: 'm1_onboarding' })]);
    const cache = new CacheModulos(puerta, 60_000);

    await cache.todos();
    cache.invalidar();
    await cache.todos();

    expect(puerta.llamadas).toBe(2);
  });

  it('con TTL 0 nunca cachea: cada lectura va a la base de datos', async () => {
    const puerta = new PuertaModulosContadora([modulo({ clave: 'm1_onboarding' })]);
    const cache = new CacheModulos(puerta, 0);

    await cache.todos();
    await cache.todos();

    expect(puerta.llamadas).toBe(2);
  });

  it('con la caché fría, varias peticiones simultáneas producen una sola consulta', async () => {
    // Sin anti-estampida, un reinicio del contenedor lanzaría N consultas
    // idénticas a la vez contra la base de datos.
    const puerta = new PuertaModulosContadora([modulo({ clave: 'm1_onboarding' })]);
    const cache = new CacheModulos(puerta, 60_000);

    await Promise.all([cache.todos(), cache.todos(), cache.todos(), cache.todos()]);

    expect(puerta.llamadas).toBe(1);
  });
});

describe('modo mantenimiento', () => {
  const mantenimientoActivo = [
    parametro({ clave: 'modo_mantenimiento', valor: true, tipo: 'boolean', esPublico: true }),
  ];

  it('bloquea a un usuario normal con 503', async () => {
    const arnés = crearArnés({ parametros: mantenimientoActivo });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(503);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'SERVICIO_NO_DISPONIBLE' },
    });
  });

  it('deja pasar al administrador: si no, no podría desactivarlo', async () => {
    const arnés = crearArnés({ parametros: mantenimientoActivo });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
  });

  it('no bloquea las sondas de salud', async () => {
    const arnés = crearArnés({ parametros: mantenimientoActivo });
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: '/salud' });

    expect(respuesta.statusCode).toBe(200);
  });

  it('no bloquea el preflight CORS (rompería el navegador)', async () => {
    const arnés = crearArnés({ parametros: mantenimientoActivo });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'OPTIONS',
      url: '/api/v1/yo',
      headers: { origin: 'http://localhost:8080', 'access-control-request-method': 'GET' },
    });

    expect(respuesta.statusCode).not.toBe(503);
  });
});
