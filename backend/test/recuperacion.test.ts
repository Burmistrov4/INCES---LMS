import { afterEach, describe, expect, it } from 'vitest';
import { crearArnés, conToken, ID_ALUMNO, TOKEN_ADMIN, TOKEN_ALUMNO, type Arnés } from './support/arnes.js';
import { estadoDeCodigoRecuperacion } from '../src/dominio/reglas-recuperacion.js';
import { generarCodigoRecuperacion, normalizarCodigo } from '../src/infra/tokens.js';

/**
 * Recuperación interna de contraseña (sin correo externo).
 *
 * El recorrido es: un administrador autorizado verifica la identidad por el
 * procedimiento institucional, emite un código temporal de un solo uso y lo
 * entrega por el canal interno; el titular lo canjea y **fija su propia
 * contraseña**. El administrador nunca la ve.
 *
 * Lo que estas pruebas demuestran: que el código es de un solo uso, que caduca,
 * que emitir uno nuevo anula el anterior, que un no-admin no puede emitir, que
 * la contraseña llega al proveedor de identidad, que las sesiones se cierran y
 * que hay límite de intentos. Lo que **no** demuestran —y no pueden— es que la
 * contraseña sirva para iniciar sesión: eso lo prueba el login real contra
 * Supabase, no un doble.
 */

let arnés: Arnés | undefined;

afterEach(async () => {
  await arnés?.app.close();
  arnés = undefined;
});

/** Emite un código para el alumno y devuelve el código en claro. */
async function emitirCodigo(a: Arnés): Promise<string> {
  const respuesta = await a.app.inject({
    method: 'POST',
    url: `/api/v1/admin/usuarios/${ID_ALUMNO}/restablecer`,
    headers: conToken(TOKEN_ADMIN),
  });
  expect(respuesta.statusCode).toBe(200);
  return (respuesta.json() as { codigo: string }).codigo;
}

describe('emisión del código — administrador', () => {
  it('emite un código de un solo uso y guarda SÓLO su huella', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/${ID_ALUMNO}/restablecer`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      email: string;
      codigo: string;
      expiraEn: string;
      entrega: string;
    };
    expect(cuerpo.email).toBe('alumno@inces.test');
    expect(cuerpo.entrega).toBe('manual');
    // 30 minutos: el código se entrega en mano, no vive 48 h como la invitación.
    const margen = new Date(cuerpo.expiraEn).getTime() - Date.now();
    expect(margen).toBeGreaterThan(28 * 60 * 1000);
    expect(margen).toBeLessThan(31 * 60 * 1000);

    // **El código en claro NO se persiste.** Ni en la fila ni en ningún otro
    // sitio del estado: lo que queda es su SHA-256.
    const guardado = arnés.estado.recuperaciones[0]!;
    expect(guardado.codeHash).toMatch(/^[0-9a-f]{64}$/);
    expect(guardado.codeHash).not.toBe(cuerpo.codigo);
    expect(JSON.stringify(arnés.estado.recuperaciones)).not.toContain(cuerpo.codigo);
    expect(guardado.createdBy).toBe('11111111-1111-1111-1111-111111111111');
  });

  it('un alumno (no admin) no puede emitir códigos: 403', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/${ID_ALUMNO}/restablecer`,
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(respuesta.statusCode).toBe(403);
    expect(arnés.estado.recuperaciones).toHaveLength(0);
  });

  it('un usuario inexistente devuelve 404', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/99999999-9999-4999-8999-999999999999/restablecer',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(respuesta.statusCode).toBe(404);
  });
});

describe('canje del código — ruta pública', () => {
  it('un código válido fija la contraseña, cierra sesiones y audita', async () => {
    arnés = crearArnés();
    const codigo = await emitirCodigo(arnés);

    const canje = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo, password: 'nuevaClave123' },
    });

    expect(canje.statusCode).toBe(200);
    expect((canje.json() as { email: string }).email).toBe('alumno@inces.test');

    // La contraseña llegó al proveedor de identidad, para el usuario correcto.
    expect(arnés.estado.passwordsCambiadas).toEqual([{ userId: ID_ALUMNO, largo: 13 }]);
    // Y se cerraron sus sesiones: cambiar la contraseña no las invalida solo.
    expect(arnés.estado.sesionesRevocadas).toEqual([ID_ALUMNO]);
    // Quedó traza del acceso.
    expect(arnés.estado.acceso.some((a) => a.estado === 'SUCCESS')).toBe(true);
    // El código quedó canjeado.
    expect(arnés.estado.recuperaciones[0]?.usedAt).not.toBeNull();
  });

  it('el mismo código no se puede canjear dos veces', async () => {
    arnés = crearArnés();
    const codigo = await emitirCodigo(arnés);

    const primera = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo, password: 'nuevaClave123' },
    });
    expect(primera.statusCode).toBe(200);

    const segunda = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo, password: 'otraClave456' },
    });
    // **Mismo 404 y mismo código que un código inventado**: decir «ya se usó» le
    // confirmaría a quien prueba códigos ajenos que acertó uno.
    expect(segunda.statusCode).toBe(404);
    expect((segunda.json() as { error: { codigo: string } }).error.codigo).toBe('CODIGO_INVALIDO');
    // Y la contraseña NO se volvió a cambiar.
    expect(arnés.estado.passwordsCambiadas).toHaveLength(1);
  });

  it('un código inventado devuelve 404', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo: 'ZZZZ-ZZZZ-ZZZZ', password: 'nuevaClave123' },
    });
    expect(respuesta.statusCode).toBe(404);
    expect(arnés.estado.passwordsCambiadas).toHaveLength(0);
  });

  it('emitir un código nuevo anula el anterior', async () => {
    arnés = crearArnés();
    const viejo = await emitirCodigo(arnés);
    const nuevo = await emitirCodigo(arnés);

    // El viejo ya no sirve…
    const conViejo = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo: viejo, password: 'nuevaClave123' },
    });
    expect(conViejo.statusCode).toBe(404);

    // …y el nuevo sí.
    const conNuevo = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo: nuevo, password: 'nuevaClave123' },
    });
    expect(conNuevo.statusCode).toBe(200);
    expect(arnés.estado.passwordsCambiadas).toHaveLength(1);
  });

  it('el código se puede teclear con guiones, espacios y minúsculas', async () => {
    arnés = crearArnés();
    const codigo = await emitirCodigo(arnés);

    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo: `  ${codigo.toLowerCase().replace(/-/g, ' ')}  `, password: 'nuevaClave123' },
    });
    expect(respuesta.statusCode).toBe(200);
  });

  it('el límite de intentos corta la fuerza bruta con 429', async () => {
    arnés = crearArnés();

    // 20 intentos fallidos: el límite de la ventana.
    for (let i = 0; i < 20; i++) {
      const r = await arnés.app.inject({
        method: 'POST',
        url: '/api/v1/auth/restablecer-codigo',
        payload: { codigo: 'ZZZZ-ZZZZ-ZZZZ', password: 'nuevaClave123' },
      });
      expect(r.statusCode).toBe(404);
    }

    // El 21 ya no llega a comprobar nada: 429.
    const bloqueado = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo: 'ZZZZ-ZZZZ-ZZZZ', password: 'nuevaClave123' },
    });
    expect(bloqueado.statusCode).toBe(429);
    expect((bloqueado.json() as { error: { codigo: string } }).error.codigo).toBe(
      'DEMASIADOS_INTENTOS',
    );
  });

  it('un cuerpo inválido devuelve 400 y no toca la base', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/restablecer-codigo',
      payload: { codigo: 'corto', password: 'corta' },
    });
    expect(respuesta.statusCode).toBe(400);
    expect(arnés.estado.passwordsCambiadas).toHaveLength(0);
  });
});

describe('reglas puras del código de recuperación', () => {
  it('deriva el estado con la misma prioridad que las invitaciones', () => {
    const futuro = new Date(Date.now() + 30 * 60 * 1000).toISOString();
    const pasado = new Date(Date.now() - 60 * 1000).toISOString();
    const ahora = new Date().toISOString();

    expect(estadoDeCodigoRecuperacion({ usedAt: null, revokedAt: null, expiresAt: futuro })).toBe(
      'valido',
    );
    expect(estadoDeCodigoRecuperacion({ usedAt: ahora, revokedAt: null, expiresAt: futuro })).toBe(
      'usado',
    );
    expect(estadoDeCodigoRecuperacion({ usedAt: null, revokedAt: null, expiresAt: pasado })).toBe(
      'expirado',
    );
    // Revocado gana a todo.
    expect(estadoDeCodigoRecuperacion({ usedAt: ahora, revokedAt: ahora, expiresAt: futuro })).toBe(
      'revocado',
    );
  });

  it('el código generado es legible y no repite caracteres ambiguos', () => {
    const codigo = generarCodigoRecuperacion();
    // Formato: 3 grupos de 4 separados por guiones.
    expect(codigo).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    // Sin caracteres que se confunden al dictar: 0/O, 1/I/L.
    expect(codigo).not.toMatch(/[01OIL]/);
    // La normalización quita guiones y espacios y sube a mayúsculas.
    expect(normalizarCodigo(codigo)).toHaveLength(12);
    expect(normalizarCodigo(` ${codigo.toLowerCase()} `)).toBe(normalizarCodigo(codigo));
    // Y no se repite: dos códigos seguidos son distintos.
    expect(generarCodigoRecuperacion()).not.toBe(codigo);
  });
});
