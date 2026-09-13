import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import {
  conToken,
  crearArnés,
  entradaAcceso,
  ID_ADMIN,
  ID_ALUMNO,
  ID_DOCENTE,
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
    { method: 'GET' as const, url: '/api/v1/admin/acceso' },
    { method: 'GET' as const, url: '/api/v1/admin/usuarios' },
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

describe('listado de usuarios', () => {
  it('devuelve los usuarios ordenados por apellido, con el total', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);

    const cuerpo = respuesta.json() as {
      usuarios: { apellidos: string }[];
      total: number;
      limite: number;
      desplazamiento: number;
    };

    // «Administradora» antes que «Aguilar»: la comparación es por colación
    // (`en_US.UTF-8` en la nube, `localeCompare` en el doble), no byte a byte.
    // Comprobado contra la base real con `scripts/consultar-colacion.mjs`; el
    // orden no es cosmético: es lo que hace estable la paginación y hace que el
    // administrador encuentre a una persona donde espera verla.
    expect(cuerpo.usuarios.map((u) => u.apellidos)).toEqual([
      'Administradora',
      'Aguilar',
      'Pérez',
      'Rondón',
    ]);
    expect(cuerpo.total).toBe(4);
    expect(cuerpo.limite).toBe(25);
    expect(cuerpo.desplazamiento).toBe(0);
  });

  it('el total refleja el filtro, no la página', async () => {
    // El error clásico: devolver `total` como `usuarios.length` funciona con
    // pocos datos y hace que la pantalla crea que sólo hay 2 usuarios cuando en
    // realidad hay 4 y sólo caben 2 por página.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?limite=2',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { usuarios: unknown[]; total: number };

    expect(cuerpo.usuarios).toHaveLength(2);
    expect(cuerpo.total).toBe(4);
  });

  it('la segunda página no repite filas de la primera', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const primera = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?limite=2&desplazamiento=0',
      headers: conToken(TOKEN_ADMIN),
    });
    const segunda = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?limite=2&desplazamiento=2',
      headers: conToken(TOKEN_ADMIN),
    });

    const ids = (r: typeof primera): string[] =>
      (r.json() as { usuarios: { id: string }[] }).usuarios.map((u) => u.id);

    const deLaPrimera = ids(primera);
    const deLaSegunda = ids(segunda);

    expect(deLaPrimera).toHaveLength(2);
    expect(deLaSegunda).toHaveLength(2);
    expect(deLaSegunda.some((id) => deLaPrimera.includes(id))).toBe(false);
  });

  it('filtra por rol', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?rol=docente',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as {
      usuarios: { rol: string }[];
      total: number;
    };

    expect(cuerpo.total).toBe(1);
    expect(cuerpo.usuarios).toHaveLength(1);
    expect(cuerpo.usuarios[0]?.rol).toBe('docente');
  });

  it('filtra por estado de la cuenta', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const inactivos = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?activo=false',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = inactivos.json() as {
      usuarios: { apellidos: string; activo: boolean }[];
      total: number;
    };

    // Sólo «Aguilar» está inactivo. Comprobar `activo: false` en cada fila
    // evita el falso positivo de un filtro que se ignora y devuelve todo.
    expect(cuerpo.total).toBe(1);
    expect(cuerpo.usuarios).toHaveLength(1);
    expect(cuerpo.usuarios[0]).toMatchObject({ apellidos: 'Aguilar', activo: false });
  });

  it('busca por nombre, correo o cédula', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    // Se prueban los cuatro campos por los que dice buscar el contrato: si sólo
    // funcionara el nombre, el administrador que pega una cédula no encontraría
    // nada y culparía a los datos.
    const casos = [
      { termino: 'Pérez', apellidoEsperado: 'Pérez' },
      { termino: 'docente@inces', apellidoEsperado: 'Rondón' },
      { termino: '12345678', apellidoEsperado: 'Rondón' },
    ];

    for (const caso of casos) {
      const respuesta = await app.inject({
        method: 'GET',
        url: `/api/v1/admin/usuarios?busqueda=${encodeURIComponent(caso.termino)}`,
        headers: conToken(TOKEN_ADMIN),
      });

      const cuerpo = respuesta.json() as { usuarios: { apellidos: string }[] };
      expect(cuerpo.usuarios, caso.termino).toHaveLength(1);
      expect(cuerpo.usuarios[0]?.apellidos, caso.termino).toBe(caso.apellidoEsperado);
    }
  });

  it('combina filtros en vez de aplicarlos por separado', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    // «Aguilar» es estudiante e inactivo; «Pérez» es estudiante y activa. Filtrar
    // por rol y por estado a la vez debe dejar sólo a Pérez. Si los filtros se
    // aplicaran como alternativas en vez de como restricciones acumuladas, aquí
    // saldrían los dos.
    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?rol=estudiante&activo=true',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { usuarios: { apellidos: string }[]; total: number };

    expect(cuerpo.total).toBe(1);
    expect(cuerpo.usuarios[0]?.apellidos).toBe('Pérez');
  });

  it('rechaza un estado que no sea true ni false en vez de asumirlo', async () => {
    // `?activo=quizá` interpretado como `true` devolvería una lista plausible
    // pero equivocada: el peor de los errores, porque no se nota.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?activo=quizas',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });

  it('rechaza un rol desconocido', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?rol=supervisor',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });

  it('rechaza una paginación fuera de rango', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    for (const consulta of ['limite=0', 'limite=101', 'desplazamiento=-1']) {
      const respuesta = await app.inject({
        method: 'GET',
        url: `/api/v1/admin/usuarios?${consulta}`,
        headers: conToken(TOKEN_ADMIN),
      });

      expect(respuesta.statusCode, consulta).toBe(400);
    }
  });

  it('el desplazamiento más allá del final devuelve una página vacía, no un error', async () => {
    // Pedir una página que ya no existe no es un fallo del cliente: es el final
    // de la lista. Un 404 aquí obligaría a la pantalla a tratar el final como
    // un error, y el `total` es precisamente lo que le permite no llegar hasta
    // aquí en circunstancias normales.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/admin/usuarios?desplazamiento=1000',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { usuarios: unknown[]; total: number };
    expect(cuerpo.usuarios).toHaveLength(0);
    expect(cuerpo.total).toBe(4);
  });
});

describe('auditoría de accesos (auth_logs)', () => {
  // Marcas de tiempo explícitas y distintas a propósito: el orden es justo lo
  // que se está probando, y `new Date()` daría la misma a varias filas creadas
  // en el mismo milisegundo, dejando el orden descendente sin definir.
  const ACCESOS = [
    entradaAcceso({
      id: 'acc-1',
      email: 'ana@inces.test',
      userId: ID_ALUMNO,
      ip: '10.0.0.1',
      estado: 'SUCCESS',
      createdAt: '2026-09-01T08:00:00.000Z',
    }),
    entradaAcceso({
      id: 'acc-2',
      email: 'ana@inces.test',
      userId: ID_ALUMNO,
      ip: '10.0.0.2',
      estado: 'FAILED',
      createdAt: '2026-09-01T09:00:00.000Z',
    }),
    entradaAcceso({
      id: 'acc-3',
      email: 'carlos@inces.test',
      userId: ID_DOCENTE,
      ip: '10.0.0.3',
      estado: 'SUCCESS',
      createdAt: '2026-09-01T10:00:00.000Z',
    }),
    entradaAcceso({
      id: 'acc-4',
      email: 'inactivo@inces.test',
      userId: null,
      ip: '10.0.0.4',
      estado: 'FAILED',
      createdAt: '2026-09-01T11:00:00.000Z',
    }),
  ];

  function arnésConAccesos() {
    const arnés = crearArnés({ acceso: ACCESOS });
    app = arnés.app;
    return arnés;
  }

  const idsDe = (respuesta: { json(): unknown }): string[] =>
    (respuesta.json() as { entradas: { id: string }[] }).entradas.map((e) => e.id);

  it('devuelve los accesos del más reciente al más antiguo, con el total', async () => {
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as {
      entradas: { id: string }[];
      total: number;
      limite: number;
      desplazamiento: number;
    };
    expect(cuerpo.entradas.map((e) => e.id)).toEqual(['acc-4', 'acc-3', 'acc-2', 'acc-1']);
    expect(cuerpo.total).toBe(4);
    expect(cuerpo.limite).toBe(25);
    expect(cuerpo.desplazamiento).toBe(0);
  });

  it('expone la IP, el correo y el resultado de cada intento', async () => {
    // Es el dato que justifica el panel: sin IP ni resultado, una bitácora de
    // accesos no sirve para investigar un intento de intrusión.
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { entradas: Record<string, unknown>[] };
    expect(cuerpo.entradas[0]).toMatchObject({
      id: 'acc-4',
      email: 'inactivo@inces.test',
      ip: '10.0.0.4',
      estado: 'FAILED',
      userId: null,
    });
  });

  it('filtra por resultado del intento', async () => {
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?estado=FAILED',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { entradas: { estado: string }[]; total: number };
    expect(idsDe(respuesta)).toEqual(['acc-4', 'acc-2']);
    expect(cuerpo.total).toBe(2);
    // Comprobar el campo en cada fila evita el falso positivo de un filtro que
    // se ignora y devuelve todo.
    expect(cuerpo.entradas.every((e) => e.estado === 'FAILED')).toBe(true);
  });

  it('filtra por correo', async () => {
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?email=ana@inces.test',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(idsDe(respuesta)).toEqual(['acc-2', 'acc-1']);
    expect((respuesta.json() as { total: number }).total).toBe(2);
  });

  it('filtra por usuario', async () => {
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: `/api/v1/admin/acceso?userId=${ID_DOCENTE}`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(idsDe(respuesta)).toEqual(['acc-3']);
    expect((respuesta.json() as { total: number }).total).toBe(1);
  });

  it('combina filtros en vez de aplicarlos por separado', async () => {
    // Ana tiene un SUCCESS y un FAILED. Pedir «SUCCESS y de Ana» debe dejar
    // sólo el éxito: si los filtros se aplicaran como alternativas en vez de
    // como restricciones acumuladas, saldrían los dos.
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?estado=SUCCESS&email=ana@inces.test',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(idsDe(respuesta)).toEqual(['acc-1']);
  });

  it('el total refleja el filtro, no la página', async () => {
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?limite=2',
      headers: conToken(TOKEN_ADMIN),
    });

    const cuerpo = respuesta.json() as { entradas: unknown[]; total: number };
    expect(cuerpo.entradas).toHaveLength(2);
    expect(cuerpo.total).toBe(4);
  });

  it('la segunda página no repite filas de la primera', async () => {
    const arnés = arnésConAccesos();

    const primera = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?limite=2&desplazamiento=0',
      headers: conToken(TOKEN_ADMIN),
    });
    const segunda = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?limite=2&desplazamiento=2',
      headers: conToken(TOKEN_ADMIN),
    });

    const deLaPrimera = idsDe(primera);
    const deLaSegunda = idsDe(segunda);

    expect(deLaPrimera).toEqual(['acc-4', 'acc-3']);
    expect(deLaSegunda).toEqual(['acc-2', 'acc-1']);
    expect(deLaSegunda.some((id) => deLaPrimera.includes(id))).toBe(false);
  });

  it('el desplazamiento más allá del final devuelve una página vacía, no un error', async () => {
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?desplazamiento=1000',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    const cuerpo = respuesta.json() as { entradas: unknown[]; total: number };
    expect(cuerpo.entradas).toHaveLength(0);
    expect(cuerpo.total).toBe(4);
  });

  it('una bitácora vacía devuelve una lista vacía, no un error', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toMatchObject({ entradas: [], total: 0 });
  });

  it('rechaza un estado que no sea SUCCESS ni FAILED', async () => {
    // `?estado=quizas` filtrado en silencio devolvería una lista plausible pero
    // equivocada: el peor de los errores, porque no se nota.
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?estado=quizas',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });

  it('rechaza un identificador de usuario que no es UUID, sin ir a la base', async () => {
    // Mismo bug que se corrigió en el cambio de rol: un valor así llegaba a
    // Postgres, reventaba con 22P02 y salía como 500. Es un error del cliente.
    const arnés = arnésConAccesos();

    const respuesta = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/acceso?userId=me',
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json()).toMatchObject({ error: { codigo: 'PETICION_INVALIDA' } });
  });

  it('rechaza una paginación fuera de rango', async () => {
    const arnés = arnésConAccesos();

    for (const consulta of ['limite=0', 'limite=101', 'desplazamiento=-1']) {
      const respuesta = await arnés.app.inject({
        method: 'GET',
        url: `/api/v1/admin/acceso?${consulta}`,
        headers: conToken(TOKEN_ADMIN),
      });

      expect(respuesta.statusCode, consulta).toBe(400);
    }
  });
});

