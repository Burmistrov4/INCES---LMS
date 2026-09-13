import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import {
  conToken,
  crearArnés,
  ID_ADMIN,
  ID_ALUMNO,
  PERFIL_ADMIN,
  PERFIL_ALUMNO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
} from './support/arnes.js';

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

describe('control de acceso a las rutas de administración', () => {
  const rutas = [
    { method: 'GET' as const, url: '/api/v1/admin/modulos' },
    { method: 'GET' as const, url: '/api/v1/admin/parametros' },
    { method: 'GET' as const, url: '/api/v1/admin/auditoria' },
  ];

  it('exige sesión en todas ellas', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const ruta of rutas) {
      const respuesta = await app.inject({ ...ruta, headers: conToken(null) });
      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
    }
  });

  it('rechaza a un usuario autenticado que no es administrador', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const ruta of rutas) {
      const respuesta = await app.inject({ ...ruta, headers: conToken(TOKEN_ALUMNO) });
      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(403);
      expect(respuesta.json()).toMatchObject({ error: { codigo: 'SOLO_ADMIN' } });
    }
  });
});

describe('gestión de módulos', () => {
  it('el administrador ve también los módulos apagados', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/modulos',
      headers: conToken(TOKEN_ADMIN),
    });

    const claves = (respuesta.json() as { modulos: { clave: string }[] }).modulos.map(
      (m) => m.clave,
    );

    expect(claves).toContain('m4_inscripciones');
  });

  it('enciende un módulo apagado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m4_inscripciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { habilitado: true },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ modulo: { clave: 'm4_inscripciones', habilitado: true } });
    expect(arnés.estado.modulos.find((m) => m.clave === 'm4_inscripciones')?.habilitado).toBe(true);
  });

  it('permite reordenar y restringir por rol', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m1_onboarding',
      headers: conToken(TOKEN_ADMIN),
      payload: { orden: 5, rolesPermitidos: ['admin', 'docente'] },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({
      modulo: { orden: 5, rolesPermitidos: ['admin', 'docente'] },
    });
  });

  it('impide apagar el módulo del cPanel, con un mensaje que explica por qué', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m0_cpanel',
      headers: conToken(TOKEN_ADMIN),
      payload: { habilitado: false },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'MODULO_CRITICO' } });
    // Y no se ha tocado nada.
    expect(arnés.estado.modulos.find((m) => m.clave === 'm0_cpanel')?.habilitado).toBe(true);
  });

  it('sí permite otros cambios sobre el módulo del cPanel', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m0_cpanel',
      headers: conToken(TOKEN_ADMIN),
      payload: { orden: 1 },
    });

    expect(respuesta.statusCode).toBe(200);
  });

  it('rechaza campos desconocidos en lugar de ignorarlos', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m1_onboarding',
      headers: conToken(TOKEN_ADMIN),
      payload: { habilitado: true, es_critico: true },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });

  it('rechaza un cuerpo vacío', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m1_onboarding',
      headers: conToken(TOKEN_ADMIN),
      payload: {},
    });

    expect(respuesta.statusCode).toBe(400);
  });

  it('devuelve 404 si el módulo no existe', async () => {
    const arnés = crearArnés();
    app = arnés.app;
    arnés.fallos['modulos.actualizar'] = Object.assign(
      new Error('no existe'),
      { name: 'ErrorApi' },
    );

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m9_certificados',
      headers: conToken(TOKEN_ADMIN),
      payload: { habilitado: true },
    });

    // Un fallo del repositorio no debe convertirse en un 200 optimista.
    expect(respuesta.statusCode).toBeGreaterThanOrEqual(400);
  });
});

describe('invalidación de la caché al cambiar un módulo', () => {
  it('el cambio surte efecto de inmediato, sin esperar al TTL', async () => {
    // TTL alto a propósito: si la invalidación no funcionara, la segunda lectura
    // seguiría viendo la caché vieja y este test fallaría.
    const arnés = crearArnés({ moduleCacheTtlMs: 60_000 });
    app = arnés.app;

    const antes = await app.inject({
      method: 'GET',
      url: '/api/v1/modulos',
      headers: conToken(TOKEN_ADMIN),
    });
    const clavesAntes = (antes.json() as { modulos: { clave: string }[] }).modulos.map(
      (m) => m.clave,
    );
    expect(clavesAntes).not.toContain('m4_inscripciones');

    await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m4_inscripciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { habilitado: true },
    });

    const despues = await app.inject({
      method: 'GET',
      url: '/api/v1/modulos',
      headers: conToken(TOKEN_ADMIN),
    });
    const clavesDespues = (despues.json() as { modulos: { clave: string }[] }).modulos.map(
      (m) => m.clave,
    );

    expect(clavesDespues).toContain('m4_inscripciones');
  });

  it('mientras nada cambie, la caché evita consultas repetidas', async () => {
    const arnés = crearArnés({ moduleCacheTtlMs: 60_000 });
    app = arnés.app;

    await app.inject({ method: 'GET', url: '/api/v1/yo', headers: conToken(TOKEN_ADMIN) });
    const trasPrimera = arnés.llamadas.filter((l) => l === 'modulos.todos').length;

    await app.inject({ method: 'GET', url: '/api/v1/yo', headers: conToken(TOKEN_ADMIN) });
    const trasSegunda = arnés.llamadas.filter((l) => l === 'modulos.todos').length;

    expect(trasPrimera).toBe(1);
    expect(trasSegunda).toBe(1);
  });
});

describe('gestión de parámetros', () => {
  it('lista todos los parámetros, incluidos los privados', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/parametros',
      headers: conToken(TOKEN_ADMIN),
    });

    const claves = (respuesta.json() as { parametros: { clave: string }[] }).parametros.map(
      (p) => p.clave,
    );

    expect(claves).toContain('max_faltas_consecutivas');
    expect(claves).toContain('modo_mantenimiento');
  });

  it('actualiza un parámetro numérico', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/parametros/max_faltas_consecutivas',
      headers: conToken(TOKEN_ADMIN),
      payload: { valor: 5 },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ parametro: { valor: 5 } });
  });

  it('rechaza un valor que no encaja con el tipo declarado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/parametros/max_faltas_consecutivas',
      headers: conToken(TOKEN_ADMIN),
      payload: { valor: 'cinco' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'PETICION_INVALIDA' },
    });
  });

  it('devuelve 404 si el parámetro no existe', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/parametros/parametro_inventado',
      headers: conToken(TOKEN_ADMIN),
      payload: { valor: 1 },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({
      error: { codigo: 'PARAMETRO_DESCONOCIDO' },
    });
  });

  it('activar el mantenimiento surte efecto sin esperar al TTL', async () => {
    const arnés = crearArnés({ settingsCacheTtlMs: 60_000 });
    app = arnés.app;

    const antes = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(antes.statusCode).toBe(200);

    await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/parametros/modo_mantenimiento',
      headers: conToken(TOKEN_ADMIN),
      payload: { valor: true },
    });

    const despues = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });
    expect(despues.statusCode).toBe(503);
  });
});

describe('auditoría', () => {
  it('devuelve las entradas con el límite por defecto', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/modulos/m4_inscripciones',
      headers: conToken(TOKEN_ADMIN),
      payload: { habilitado: true },
    });

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/auditoria',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { entradas: { clave: string; tabla: string }[] };
    expect(cuerpo.entradas).toHaveLength(1);
    expect(cuerpo.entradas[0]).toMatchObject({
      clave: 'm4_inscripciones',
      tabla: 'system_modules',
    });
  });

  it('respeta el parámetro `limite`', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const clave of ['m1_onboarding', 'm4_inscripciones']) {
      await app.inject({
        method: 'PATCH',
        url: `/api/v1/admin/modulos/${clave}`,
        headers: conToken(TOKEN_ADMIN),
        payload: { orden: 3 },
      });
    }

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/auditoria?limite=1',
      headers: conToken(TOKEN_ADMIN),
    });

    expect((respuesta.json() as { entradas: unknown[] }).entradas).toHaveLength(1);
  });

  it('rechaza un límite fuera de rango', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/auditoria?limite=9999',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
  });
});

describe('cambio de rol', () => {
  it('promueve a un estudiante a docente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/usuarios/${ID_ALUMNO}/rol`,
      headers: conToken(TOKEN_ADMIN),
      payload: { rol: 'docente' },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ perfil: { id: ID_ALUMNO, rol: 'docente' } });
  });

  it('impide que un administrador se degrade a sí mismo', async () => {
    // Sin esta guardia, el último administrador podría dejarse sin acceso al
    // sistema con un clic, y nadie podría revertirlo desde la aplicación.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/usuarios/${ID_ADMIN}/rol`,
      headers: conToken(TOKEN_ADMIN),
      payload: { rol: 'estudiante' },
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'AUTO_DEGRADACION' } });
    expect(arnés.estado.perfiles.find((p) => p.id === ID_ADMIN)?.rol).toBe('admin');
  });

  it('le permite confirmarse a sí mismo como administrador', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/usuarios/${ID_ADMIN}/rol`,
      headers: conToken(TOKEN_ADMIN),
      payload: { rol: 'admin' },
    });

    expect(respuesta.statusCode).toBe(200);
  });

  it('rechaza con 404 y código propio si el usuario no existe', async () => {
    // Antes este caso llegaba a PostgREST y volvía como un error sin contexto.
    // Ahora se comprueba antes, para que el mensaje diga qué pasó.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/usuarios/00000000-0000-0000-0000-000000000000/rol',
      headers: conToken(TOKEN_ADMIN),
      payload: { rol: 'docente' },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PERFIL_INEXISTENTE' } });
  });

  it('rechaza con 400 un identificador que no es UUID, sin ir a la base', async () => {
    // Bug encontrado en la prueba de humo contra la nube: `PATCH
    // /usuarios/me/rol` llegaba hasta Postgres, que respondía
    // `22P02 invalid input syntax for type uuid: "me"`, y eso se traducía a un
    // `500 ERROR_BASE_DE_DATOS`. Un error del cliente disfrazado de caída del
    // servidor: el administrador ve «ocurrió un error al acceder a los datos» y
    // no puede saber que la URL estaba mal escrita.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: '/api/v1/admin/usuarios/me/rol',
      headers: conToken(TOKEN_ADMIN),
      payload: { rol: 'docente' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });

    // Lo importante: no se llegó a consultar el perfil OBJETIVO. El hook
    // `onRequest` sí llama a `perfiles.porId` una vez, pero con el id del
    // llamante, que es legítimo. Distinguirlos es justo el punto: antes esta
    // petición gastaba una consulta a Postgres para tirarla con un 500.
    const consultasAlObjetivo = arnés.llamadas.filter((l) => l === 'perfiles.porId');
    expect(consultasAlObjetivo).toHaveLength(1);
    expect(arnés.llamadas).not.toContain('perfiles.contarAdminsActivos');
    expect(arnés.llamadas).not.toContain('perfiles.cambiarRol');
  });

  it('rechaza con 400 un identificador con formato de UUID inválido', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const malo of ['123', 'no-es-uuid', '00000000-0000-0000-0000-00000000000']) {
      const respuesta = await app.inject({
        method: 'PATCH',
        url: `/api/v1/admin/usuarios/${malo}/rol`,
        headers: conToken(TOKEN_ADMIN),
        payload: { rol: 'docente' },
      });

      expect(respuesta.statusCode).toBe(400);
      expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
    }
  });

  it('permite degradar a otro administrador mientras quede alguno más', async () => {
    const OTRO_ADMIN = '44444444-4444-4444-4444-444444444444';
    const arnés = crearArnés({
      perfiles: [
        PERFIL_ADMIN,
        PERFIL_ALUMNO,
        {
          id: OTRO_ADMIN,
          email: 'otro@inces.test',
          cedula: null,
          nombres: 'Otro',
          apellidos: 'Administrador',
          rol: 'admin',
          activo: true,
        },
      ],
    });
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/admin/usuarios/${OTRO_ADMIN}/rol`,
      headers: conToken(TOKEN_ADMIN),
      payload: { rol: 'docente' },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(arnés.estado.perfiles.find((p) => p.id === OTRO_ADMIN)?.rol).toBe('docente');
    // Quien actúa sigue siendo administrador: nunca se queda el sistema a cero.
    expect(arnés.estado.perfiles.filter((p) => p.rol === 'admin' && p.activo)).toHaveLength(1);
  });
});
