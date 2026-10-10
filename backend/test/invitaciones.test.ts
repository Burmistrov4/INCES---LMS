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
      payload: { email: 'profesor@inces.test', nombres: 'Profesor', apellidos: 'Invitado' },
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
      payload: { email: 'x@inces.test', nombres: 'Equis', apellidos: 'Usuario' },
    });
    expect(respuesta.statusCode).toBe(401);
  });

  it('un estudiante (no admin) devuelve 403', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ALUMNO),
      payload: { email: 'x@inces.test', nombres: 'Equis', apellidos: 'Usuario' },
    });
    expect(respuesta.statusCode).toBe(403);
  });

  it('un correo inválido devuelve 400', async () => {
    arnés = crearArnés();
    const respuesta = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'no-es-correo', nombres: 'No', apellidos: 'Correo' },
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
      payload: { email: 'nuevo@inces.test', nombres: 'Nuevo', apellidos: 'Docente' },
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
      expect(arnés.estado.perfiles.at(-1)?.nombres).toBe('Nuevo');
      expect(arnés.estado.perfiles.at(-1)?.apellidos).toBe('Docente');
    // Se registró un acceso exitoso.
    expect(arnés.estado.acceso.some((a) => a.estado === 'SUCCESS')).toBe(true);
  });

  it('reusar el mismo token falla con 409 (ya usada)', async () => {
    arnés = crearArnés();
    const invitacion = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'otro@inces.test', nombres: 'Otro', apellidos: 'Docente' },
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

       nombres: 'Caducado',

       apellidos: 'Invitacion',
      tokenHash: hashearToken(token),
      isUsed: false,
      createdAt: new Date(Date.now() - 49 * 3600 * 1000).toISOString(),
      expiresAt: new Date(Date.now() - 3600 * 1000).toISOString(),
      revokedAt: null,
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
  it('deriva el estado correcto según uso, caducidad y revocación', () => {
    const futuro = new Date(Date.now() + 48 * 3600 * 1000).toISOString();
    const pasado = new Date(Date.now() - 3600 * 1000).toISOString();
    const ahora = new Date().toISOString();

    expect(estadoDeInvitacion({ isUsed: false, expiresAt: futuro, revokedAt: null })).toBe('valida');
    expect(estadoDeInvitacion({ isUsed: true, expiresAt: futuro, revokedAt: null })).toBe('usada');
    expect(estadoDeInvitacion({ isUsed: false, expiresAt: pasado, revokedAt: null })).toBe('expirada');
    // Una usada sigue "usada" aunque además haya caducado: se comprueba antes.
    expect(estadoDeInvitacion({ isUsed: true, expiresAt: pasado, revokedAt: null })).toBe('usada');

    // La revocación gana a todo: una invitación anulada no revive aunque su
    // fecha siga en el futuro ni aunque después alguien la marque usada.
    expect(estadoDeInvitacion({ isUsed: false, expiresAt: futuro, revokedAt: ahora })).toBe('revocada');
    expect(estadoDeInvitacion({ isUsed: true, expiresAt: futuro, revokedAt: ahora })).toBe('revocada');
    expect(estadoDeInvitacion({ isUsed: false, expiresAt: pasado, revokedAt: ahora })).toBe('revocada');
  });
});

describe('ciclo de vida de la invitación — revocación y renovación', () => {
  it('el admin revoca una invitación y su token deja de activar (403)', async () => {
    arnés = crearArnés();
    const perfilesAntes = arnés.estado.perfiles.length;
    const creada = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'revoca@inces.test', nombres: 'Revoca', apellidos: 'Prueba' },
    });
    const token = tokenDelEnlace(
      (creada.json() as { enlaceActivacion: string }).enlaceActivacion,
    );
    const id = arnés.estado.invitaciones[0]!.id;

    const revocacion = await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/invitaciones/${id}/revocar`,
      headers: conToken(TOKEN_ADMIN),
    });
    expect(revocacion.statusCode).toBe(200);
    expect(arnés.estado.invitaciones[0]?.revokedAt).not.toBeNull();

    // El token, que era válido, ya no activa nada.
    const activacion = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token, password: 'secreto123' },
    });
    expect(activacion.statusCode).toBe(403);
    expect((activacion.json() as { error: { codigo: string } }).error.codigo).toBe(
      'INVITACION_REVOCADA',
    );
    // Y no se creó ninguna cuenta nueva.
    expect(arnés.estado.perfiles).toHaveLength(perfilesAntes);
  });

  it('revocar dos veces da 409 y un no-admin da 403', async () => {
    arnés = crearArnés();
    await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'doble@inces.test', nombres: 'Doble', apellidos: 'Revoca' },
    });
    const id = arnés.estado.invitaciones[0]!.id;

    const prohibido = await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/invitaciones/${id}/revocar`,
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(prohibido.statusCode).toBe(403);
    expect(arnés.estado.invitaciones[0]?.revokedAt).toBeNull();

    await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/invitaciones/${id}/revocar`,
      headers: conToken(TOKEN_ADMIN),
    });
    const segunda = await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/invitaciones/${id}/revocar`,
      headers: conToken(TOKEN_ADMIN),
    });
    expect(segunda.statusCode).toBe(409);
  });

  it('renovar revoca la anterior y emite una nueva que sí activa', async () => {
    arnés = crearArnés();
    const creada = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'renueva@inces.test', nombres: 'Renueva', apellidos: 'Prueba' },
    });
    const tokenViejo = tokenDelEnlace(
      (creada.json() as { enlaceActivacion: string }).enlaceActivacion,
    );
    const id = arnés.estado.invitaciones[0]!.id;

    const renovada = await arnés.app.inject({
      method: 'POST',
      url: `/api/v1/admin/usuarios/invitaciones/${id}/renovar`,
      headers: conToken(TOKEN_ADMIN),
    });
    expect(renovada.statusCode).toBe(200);
    const cuerpo = renovada.json() as { enlaceActivacion: string; reemplazaA: string };
    expect(cuerpo.reemplazaA).toBe(id);

    // **Dos tokens, un solo válido.** La anterior quedó revocada…
    expect(arnés.estado.invitaciones).toHaveLength(2);
    expect(arnés.estado.invitaciones[0]?.revokedAt).not.toBeNull();

    const conViejo = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token: tokenViejo, password: 'secreto123' },
    });
    expect(conViejo.statusCode).toBe(403);

    // …y la nueva sí activa, conservando el nombre de la anterior.
    const tokenNuevo = tokenDelEnlace(cuerpo.enlaceActivacion);
    const conNuevo = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/auth/activar',
      payload: { token: tokenNuevo, password: 'secreto123' },
    });
    expect(conNuevo.statusCode).toBe(200);
    expect(arnés.estado.perfiles.at(-1)?.nombres).toBe('Renueva');
  });

  it('el listado devuelve el estado ya resuelto por el dominio', async () => {
    arnés = crearArnés();
    await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'estado@inces.test', nombres: 'Estado', apellidos: 'Prueba' },
    });

    const listado = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(listado.statusCode).toBe(200);
    const { invitaciones } = listado.json() as {
      invitaciones: { email: string; estado: string }[];
    };
    expect(invitaciones).toHaveLength(1);
    expect(invitaciones[0]?.estado).toBe('valida');

    const sinToken = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios/invitaciones',
    });
    expect(sinToken.statusCode).toBe(401);
  });

  it('dos activaciones simultáneas del mismo token: exactamente una crea la cuenta', async () => {
    arnés = crearArnés();
    const perfilesAntes = arnés.estado.perfiles.length;
    const creada = await arnés.app.inject({
      method: 'POST',
      url: '/api/v1/admin/usuarios/invitaciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { email: 'carrera@inces.test', nombres: 'Carrera', apellidos: 'Prueba' },
    });
    const token = tokenDelEnlace(
      (creada.json() as { enlaceActivacion: string }).enlaceActivacion,
    );

    // Las dos leen la invitación como válida; sólo una gana el reclamo atómico.
    // Sin el reclamo antes de crear el usuario, las dos llegarían a
    // `crearUsuarioDocente` y quedarían DOS cuentas para el mismo correo.
    const [a, b] = await Promise.all([
      arnés.app.inject({
        method: 'POST',
        url: '/api/v1/auth/activar',
        payload: { token, password: 'secreto123' },
      }),
      arnés.app.inject({
        method: 'POST',
        url: '/api/v1/auth/activar',
        payload: { token, password: 'secreto123' },
      }),
    ]);

    expect([a.statusCode, b.statusCode].sort((x, y) => x - y)).toEqual([200, 409]);
    // Exactamente UNA cuenta nueva, no dos.
    expect(arnés.estado.perfiles).toHaveLength(perfilesAntes + 1);
  });
});
