import { describe, expect, it } from 'vitest';
import { cargarEnv, configuracionR2, origenesCors } from '../src/config/env.js';

describe('configuración del entorno', () => {
  it('rechaza un entorno sin las claves de Supabase, indicando cuáles faltan', () => {
    expect(() => cargarEnv({})).toThrowError(/SUPABASE_URL/);
  });

  it('rechaza una URL de Supabase que no es una URL', () => {
    expect(() =>
      cargarEnv({
        SUPABASE_URL: 'no-es-una-url',
        SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
        SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
      }),
    ).toThrowError(/SUPABASE_URL/);
  });

  it('aplica valores por defecto sensatos cuando sólo hay lo imprescindible', () => {
    const env = cargarEnv({
      SUPABASE_URL: 'https://prueba.supabase.co',
      SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
      SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
    });

    expect(env.NODE_ENV).toBe('development');
    expect(env.PORT).toBe(3000);
    expect(env.MODULE_CACHE_TTL_MS).toBe(30_000);
    expect(env.LOG_LEVEL).toBe('info');
  });

  it('convierte las variables numéricas que llegan como texto', () => {
    const env = cargarEnv({
      SUPABASE_URL: 'https://prueba.supabase.co',
      SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
      SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
      PORT: '8080',
      MODULE_CACHE_TTL_MS: '0',
    });

    expect(env.PORT).toBe(8080);
    expect(env.MODULE_CACHE_TTL_MS).toBe(0);
  });

  it('normaliza la lista de orígenes CORS', () => {
    const env = cargarEnv({
      SUPABASE_URL: 'https://prueba.supabase.co',
      SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
      SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
      CORS_ORIGINS: 'https://a.test , https://b.test',
    });

    expect(origenesCors(env)).toEqual(['https://a.test', 'https://b.test']);
  });

  it('interpreta `*` como «cualquier origen»', () => {
    const env = cargarEnv({
      SUPABASE_URL: 'https://prueba.supabase.co',
      SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
      SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
      CORS_ORIGINS: '*',
    });

    expect(origenesCors(env)).toBe(true);
  });
});

describe('variables opcionales vacías', () => {
  /**
   * Regresión. `node --env-file`, Docker Compose y la mayoría de gestores
   * exportan `VACIA=` como cadena vacía, no como variable ausente. Con un
   * `.optional()` a secas, `min(1)` rechazaba esa cadena y el arranque fallaba
   * aunque el operador sólo hubiera dejado el hueco de la plantilla sin rellenar.
   */
  const BASE = {
    SUPABASE_URL: 'https://prueba.supabase.co',
    SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
    SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
  };

  it('acepta un entorno con las variables de R2 presentes pero vacías', () => {
    const env = cargarEnv({
      ...BASE,
      CLOUDFLARE_ACCOUNT_ID: '',
      R2_ACCESS_KEY_ID: '',
      R2_SECRET_ACCESS_KEY: '',
      R2_BUCKET: '',
    });

    expect(configuracionR2(env)).toBeNull();
  });

  it('trata un valor con sólo espacios como ausente', () => {
    const env = cargarEnv({ ...BASE, CLOUDFLARE_ACCOUNT_ID: '   ' });

    expect(configuracionR2(env)).toBeNull();
  });

  it('sigue exigiendo las variables obligatorias: vacío no es «no configurado»', () => {
    expect(() => cargarEnv({ ...BASE, SUPABASE_ANON_KEY: '' })).toThrowError(
      /SUPABASE_ANON_KEY/,
    );
  });

  it('detecta una configuración de R2 a medias aunque el resto esté vacío', () => {
    // `cargarEnv` sólo valida el esquema; la coherencia del conjunto la decide
    // `configuracionR2`, que es quien sabe que faltan las otras tres.
    const env = cargarEnv({ ...BASE, R2_BUCKET: 'inces-lms-archivos' });

    expect(() => configuracionR2(env)).toThrowError(/R2 incompleta/);
  });
});
