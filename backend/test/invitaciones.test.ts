import { afterEach, describe, expect, it } from 'vitest';
import { crearArnés, conToken, TOKEN_ADMIN, TOKEN_ALUMNO, type Arnés } from './support/arnes.js';
import { estadoDeInvitacion } from '../src/dominio/reglas-invitaciones.js';
import { hashearToken } from '../src/infra/tokens.js';

/**
 * Flujo de invitación de docentes (Módulo 1).
 *
 * Cubre las dos caras: el administrador invita (ruta protegida) y el profesor
 * activa (ruta pública). El arnés monta la API completa en memoria, así que no
 * hace falta Supabase ni Resend para probar la lógica. Los tokens se extraen del
 * `enlaceActivacion` que devuelve la propia invitación, que es justo lo que el
 * frontend enviaría.
 */

let arnés: Arnés | undefined;

afterEach(async () => {
  await arnés?.app.close();
  arnés = undefined;
});

/** Extrae el token del enlace devuelto por la invitación. */
function tokenDelEnlace(enlace: string): string {
  const url = new URL(enlace);

  // Ruta normal: el token va en el query (`?token=`).
  const tokenQuery = url.searchParams.get('token');
  if (tokenQuery) return tokenQuery;

  // Estrategia de hash de Flutter web: el token vive en el fragmento
  // (`#/auth/activate?token=`). Se parsea aparte porque `searchParams` no lo ve.
  const fragmento = url.hash.replace(/^#/, '');
  if (fragmento) {
    const paramsFragmento = new URL(`http://localhost${fragmento}`).searchParams;
    const tokenFragmento = paramsFragmento.get('token');
    if (tokenFragmento) return tokenFragmento;
  }

  throw new Error('El enlace de activación no traía token.');
}

describe('invitación de docentes — administrador', () => {
  it('el admin crea una invitación y recibe el enlace de activación', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'profesor@inces.test' },
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      email: string;
      expiraEn: string;
      enlaceActivacion: string;
      correoEnviado: boolean;
    };
    expect(cuerpo.email).toBe('profesor@inces.test');
    expect(cuerpo.correoEnviado).toBe(true);
    expect(cuerpo.enlaceActivacion).toContain('/auth/activate?token=');
    // 48 horas de margen: la expiración debe estar ~2 días en el futuro.
    expect(new Date(cuerpo.expiraEn).getTime()).toBeGreaterThan(Date.now() + 47 * 3600 * 1000);

    // Persistencia: la invitación quedó en el estado del arnés.
    expect(arnés.estado.invitaciones).toHaveLength(1);
    expect(arnés.estado.invitaciones[0]?.email).toBe('profesor@inces.test');
    expect(arnés.estado.invitaciones[0]?.isUsed).toBe(false);
    // El correo se "envió" vía el doble.
    expect(arnés.estado.correos[0]?.para).toBe('profesor@inces.test');
  });

  it('sin token devuelve 401', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      payload: { email: 'x@inces.test' },
    });
    expect(respuesta.statusCode).toBe(401);
  });

  it('un estudiante (no admin) devuelve 403', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ALUMNO),
      payload: { email: 'x@inces.test' },
    });
    expect(respuesta.statusCode).toBe(403);
  });

  it('un correo inválido devuelve 400', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'no-es-correo' },
    });
    expect(respuesta.statusCode).toBe(400);
  });
});

describe('activación de la invitación — profesor (ruta pública)', () => {
  it('un token válido crea la cuenta como DOCENTE y consume la invitación', async () => {
    arnés = crearArnés();
    const invitacion = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'nuevo@inces.test' },
    });
    const token = tokenDelEnlace((invitacion.json() as { enlaceActivacion: string }).enlaceActivacion);

    const activacion = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token, password: 'secreto123' },
    });

    expect(activacion.statusCode).toBe(200);
    const cuerpo = activacion.json() as { email: string; perfil: { rol: string } };
    expect(cuerpo.email).toBe('nuevo@inces.test');
    expect(cuerpo.perfil.rol).toBe('docente');

    // La invitación quedó marcada como usada.
    expect(arnés.estado.invitaciones[0]?.isUsed).toBe(true);
    // Se registró un acceso exitoso.
    expect(arnés.estado.acceso.some((a) => a.estado === 'SUCCESS')).toBe(true);
  });

  it('reusar el mismo token falla con 409 (ya usada)', async () => {
    arnés = crearArnés();
    const invitacion = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'otro@inces.test' },
    });
    const token = tokenDelEnlace((invitacion.json() as { enlaceActivacion: string }).enlaceActivacion);

    await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token, password: 'secreto123' },
    });

    const segunda = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token, password: 'secreto123' },
    });
    expect(segunda.statusCode).toBe(409);
    expect((segunda.json() as { error: { codigo: string } }).error.codigo).toBe('INVITACION_YA_USADA');
  });

  it('un token inexistente devuelve 404', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token: 'token-que-no-existe-0000000000', password: 'secreto123' },
    });
    expect(respuesta.statusCode).toBe(404);
    expect((respuesta.json() as { error: { codigo: string } }).error.codigo).toBe('INVITACION_INVALIDA');
  });

  it('un token caducado devuelve 410', async () => {
    arnés = crearArnés();
    const token = 'token-caducado-1234567890abcdef';
    // Inyectamos la invitación directamente en el estado, ya expirada, para no
    // depender de relojes: el endpoint fija +48h, pero la regla es pura.
    arnés.estado.invitaciones.push({
      id: 'inv-caducada',
      email: 'caducado@inces.test',
      tokenHash: hashearToken(token),
      isUsed: false,
      createdAt: new Date(Date.now() - 49 * 3600 * 1000).toISOString(),
      expiresAt: new Date(Date.now() - 3600 * 1000).toISOString(),
    });

    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token, password: 'secreto123' },
    });
    expect(respuesta.statusCode).toBe(410);
    expect((respuesta.json() as { error: { codigo: string } }).error.codigo).toBe('RECURSO_CADUCADO');
  });
});

describe('reglas puras de invitación', () => {
  it('deriva el estado correcto según uso y caducidad', () => {
    const futuro = new Date(Date.now() + 48 * 3600 * 1000).toISOString();
    const pasado = new Date(Date.now() - 3600 * 1000).toISOString();

    expect(estadoDeInvitacion({ isUsed: false, expiresAt: futuro })).toBe('valida');
    expect(estadoDeInvitacion({ isUsed: true, expiresAt: futuro })).toBe('usada');
    expect(estadoDeInvitacion({ isUsed: false, expiresAt: pasado })).toBe('expirada');
    // Una usada sigue "usada" aunque además haya caducado: se comprueba primero.
    expect(estadoDeInvitacion({ isUsed: true, expiresAt: pasado })).toBe('usada');
  });
});
