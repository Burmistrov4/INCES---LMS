import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import type { EstadoArchivo } from '../src/dominio/tipos.js';
import {
  ARCHIVOS_POR_DEFECTO,
  CLAVE_ARCHIVO_CONFIRMADO,
  conToken,
  crearArnés,
  ID_ADMIN,
  ID_ALUMNO,
  ID_ARCHIVO_CONFIRMADO,
  parametro,
  TAMANO_ARCHIVO_CONFIRMADO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
  type ArchivoFalso,
  type Arnés,
} from './support/arnes.js';

/**
 * M5 — archivos, de punta a punta sobre el arnés en memoria.
 *
 * Se comprueba el **contrato HTTP**: control de acceso, validación, códigos de
 * estado, forma de las respuestas y el orden de las operaciones que cruzan dos
 * sistemas (PostgreSQL y R2).
 *
 * **Lo que estas pruebas NO pueden demostrar, y conviene tenerlo escrito:**
 *
 *   · Que la RLS deje de ver el archivo de otro. El doble reproduce la política
 *     para que la ruta tenga un `null` que traducir, pero quien la aplica es
 *     Postgres. Eso sólo se comprueba contra la nube (lección R-23).
 *   · Que las RPC sean `security definer` y hagan su propia autorización. Aquí
 *     las llama un objeto en memoria.
 *   · Que R2 firme de verdad y devuelva `ContentLength`. Eso es `test/r2.test.ts`
 *     (firma real con credenciales falsas) y la sonda contra el bucket.
 *
 * Lo que sí se prueba aquí es todo lo que vive en **este** repositorio: que el
 * 413 salga sólo del tamaño y no del dato, que el tope de entidad se lea del
 * parámetro configurable, que la fila se reserve antes de que exista el objeto y
 * que el borrado toque el objeto y la fila en el orden correcto.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

/** Un id de tarea, para las pruebas del tope por entidad. */
const ID_TAREA = 'ffffffff-0000-4000-8000-000000000001';

/** Un archivo del administrador, para los casos de «es de otro». */
const ID_ARCHIVO_DEL_ADMIN = 'a1b2c3d4-0000-4000-8000-0000000000a1';
const CLAVE_ARCHIVO_DEL_ADMIN =
  `m5_archivos/${ID_ADMIN}/2026/09/${ID_ARCHIVO_DEL_ADMIN}.pdf`;

const ARCHIVO_DEL_ADMIN: ArchivoFalso = {
  id: ID_ARCHIVO_DEL_ADMIN,
  propietarioId: ID_ADMIN,
  r2Key: CLAVE_ARCHIVO_DEL_ADMIN,
  nombreOriginal: 'acta.pdf',
  tamanoBytes: 2048,
  estado: 'CONFIRMED',
  entityType: 'TEACHER_GUIDE',
};

/** Las cinco rutas, con un id válido, para las pruebas de acceso. */
const RUTAS = [
  { method: 'POST' as const, url: '/api/v1/archivos/firmar-subida' },
  { method: 'POST' as const, url: `/api/v1/archivos/${ID_ARCHIVO_CONFIRMADO}/confirmar` },
  { method: 'GET' as const, url: `/api/v1/archivos/${ID_ARCHIVO_CONFIRMADO}/url-lectura` },
  { method: 'DELETE' as const, url: `/api/v1/archivos/${ID_ARCHIVO_CONFIRMADO}` },
  { method: 'DELETE' as const, url: `/api/v1/admin/archivos/${ID_ARCHIVO_CONFIRMADO}` },
];

/** Un archivo de tarea, para sembrar el arnés en las pruebas del tope. */
function archivoDeTarea(
  id: string,
  entidadId: string | null,
  estado: EstadoArchivo = 'CONFIRMED',
): ArchivoFalso {
  return {
    id,
    propietarioId: ID_ALUMNO,
    r2Key: `m5_archivos/${ID_ALUMNO}/2026/09/${id}.pdf`,
    nombreOriginal: 'tarea.pdf',
    tamanoBytes: estado === 'CONFIRMED' ? 1024 : null,
    estado,
    entityType: 'TASK_SUBMISSION',
    entidadId,
  };
}

/** Pide la firma de una subida. */
function firmar(
  arnes: Arnés,
  payload: unknown = { nombreOriginal: 'tarea.pdf', entityType: 'TASK_SUBMISSION' },
  token: string | null = TOKEN_ALUMNO,
) {
  return arnes.app.inject({
    method: 'POST',
    url: '/api/v1/archivos/firmar-subida',
    headers: conToken(token),
    payload: payload as Record<string, unknown>,
  });
}

/** Simula el `PUT` del cliente: el objeto aparece en el bucket. */
function subirObjeto(arnes: Arnés, clave: string, tamanoBytes: number): void {
  arnes.almacenamiento.objetos.set(clave, tamanoBytes);
}

function confirmar(arnes: Arnés, id: string, token: string = TOKEN_ALUMNO) {
  return arnes.app.inject({
    method: 'POST',
    url: `/api/v1/archivos/${id}/confirmar`,
    headers: conToken(token),
  });
}

function leer(arnes: Arnés, id: string, token: string = TOKEN_ALUMNO) {
  return arnes.app.inject({
    method: 'GET',
    url: `/api/v1/archivos/${id}/url-lectura`,
    headers: conToken(token),
  });
}

function borrar(arnes: Arnés, id: string, token: string = TOKEN_ALUMNO) {
  return arnes.app.inject({
    method: 'DELETE',
    url: `/api/v1/archivos/${id}`,
    headers: conToken(token),
  });
}

describe('control de acceso a los archivos', () => {
  it('exige sesión en las cinco rutas', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const ruta of RUTAS) {
      const respuesta = await app.inject({ method: ruta.method, url: ruta.url });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
      expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
    }
  });

  it('el borrado administrativo exige rol admin: un estudiante recibe 403 y no 401', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'DELETE',
      url: `/api/v1/admin/archivos/${ID_ARCHIVO_CONFIRMADO}`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('SOLO_ADMIN');
  });

  it('un estudiante autenticado no puede borrar el archivo de otro: 403 y la fila intacta', async () => {
    // La guardia de sesión no basta: el archivo es del administrador, así que
    // quien autoriza es la RPC, y el fallo tiene que llegar como 403 con código
    // propio. Si la fila se tocara, el 403 estaría escondiendo un borrado hecho.
    const arnes = crearArnés({
      archivos: [...ARCHIVOS_POR_DEFECTO, ARCHIVO_DEL_ADMIN],
    });
    app = arnes.app;

    const respuesta = await borrar(arnes, ID_ARCHIVO_DEL_ADMIN, TOKEN_ALUMNO);

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_AJENO');

    const fila = arnes.estado.archivos.find((a) => a.id === ID_ARCHIVO_DEL_ADMIN);
    expect(fila?.estado).toBe('CONFIRMED');
    expect(arnes.almacenamiento.borrados).toEqual([]);
  });
});

describe('despliegue sin almacenamiento configurado', () => {
  it('las cinco rutas responden 503 y no revientan', async () => {
    const arnes = crearArnés({ sinAlmacenamiento: true });
    app = arnes.app;

    // Cada ruta va con el token que le corresponde: el borrado administrativo con
    // el de admin, porque si fuera con el del alumno el 403 de la guardia llegaría
    // antes que el 503 y la prueba no estaría comprobando lo que dice.
    for (const ruta of RUTAS) {
      const esAdmin = ruta.url.startsWith('/api/v1/admin');
      const respuesta = await app.inject({
        method: ruta.method,
        url: ruta.url,
        headers: conToken(esAdmin ? TOKEN_ADMIN : TOKEN_ALUMNO),
      });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(503);
      expect(respuesta.json().error.codigo).toBe('SERVICIO_NO_DISPONIBLE');
    }
  });

  it('el resto de la API sigue funcionando sin almacenamiento', async () => {
    // R2 es una capacidad **opcional**: que falte no puede tumbar el backend. Es
    // la razón de que `almacenamiento` sea `null` y no una excepción al arrancar.
    const arnes = crearArnés({ sinAlmacenamiento: true });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/yo',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
  });
});

describe('firmar una subida', () => {
  it('reserva la fila en PENDING y devuelve el id, la URL y la caducidad', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await firmar(arnes);

    expect(respuesta.statusCode).toBe(201);

    const cuerpo = respuesta.json();

    expect(cuerpo.archivo.estado).toBe('PENDING');
    // `null` y no `0`: una subida a medias no tiene tamaño, y `0` sería un
    // archivo vacío de verdad.
    expect(cuerpo.archivo.tamanoBytes).toBeNull();
    expect(cuerpo.archivo.tipoContenido).toBe('application/pdf');
    expect(cuerpo.archivo.nombreOriginal).toBe('tarea.pdf');
    expect(typeof cuerpo.archivo.id).toBe('string');
    expect(cuerpo.urlDeSubida).toContain('firma=subida');
    expect(cuerpo.expiraEnSegundos).toBe(arnes.env.R2_PUT_TTL_SEGUNDOS);

    // La fila quedó registrada y el objeto **todavía no existe**: eso es
    // exactamente el estado PENDING.
    expect(arnes.estado.archivos).toHaveLength(ARCHIVOS_POR_DEFECTO.length + 1);
    expect(arnes.almacenamiento.objetos.has(cuerpo.archivo.r2Key)).toBe(false);
  });

  it('la clave de la fila es exactamente la que se firmó', async () => {
    // La propiedad que se está protegiendo: `urlDeSubida` construye la clave por
    // dentro —prefijo, UUID y extensión—, así que la ruta **tiene que firmar
    // antes de registrar**. Si registrara primero construyendo la clave por su
    // cuenta, serían dos UUID distintos y la fila apuntaría a un objeto que nadie
    // va a subir.
    const arnes = crearArnés();
    app = arnes.app;

    const cuerpo = (await firmar(arnes)).json();

    expect(cuerpo.urlDeSubida).toContain(cuerpo.archivo.r2Key);
    expect(cuerpo.archivo.r2Key).toMatch(/\.pdf$/);
  });

  it('el prefijo lo compone el servidor a partir del usuario, no el cliente', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const delAlumno = (await firmar(arnes, undefined, TOKEN_ALUMNO)).json();
    const delAdmin = (await firmar(arnes, undefined, TOKEN_ADMIN)).json();

    expect(delAlumno.archivo.r2Key.startsWith(`m5_archivos/${ID_ALUMNO}/`)).toBe(true);
    expect(delAdmin.archivo.r2Key.startsWith(`m5_archivos/${ID_ADMIN}/`)).toBe(true);
  });

  it('el cliente no puede proponer ni la clave del objeto ni su tamaño', async () => {
    // Los dos campos ausentes del esquema son la decisión de seguridad del
    // módulo: una URL PUT prefirmada es una autorización de escritura y, si el
    // cliente eligiera la clave, alcanzaría a cualquier objeto del bucket. El
    // tamaño no se puede validar antes de subir, así que aceptarlo del cliente
    // sería pedirle al sospechoso que se mida.
    const arnes = crearArnés();
    app = arnes.app;

    const propuestas = [
      { nombreOriginal: 'tarea.pdf', entityType: 'TASK_SUBMISSION', r2Key: 'otro/x.pdf' },
      { nombreOriginal: 'tarea.pdf', entityType: 'TASK_SUBMISSION', tamanoBytes: 1 },
    ];

    for (const payload of propuestas) {
      const respuesta = await firmar(arnes, payload);

      expect(respuesta.statusCode, JSON.stringify(payload)).toBe(400);
      expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    }
  });

  it('rechaza una extensión no admitida y un nombre sin extensión', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const conExe = await firmar(arnes, {
      nombreOriginal: 'virus.exe',
      entityType: 'TASK_SUBMISSION',
    });
    expect(conExe.statusCode).toBe(400);
    expect(conExe.json().error.mensaje).toMatch(/Extensión no permitida/);

    const sinPunto = await firmar(arnes, {
      nombreOriginal: 'constancia',
      entityType: 'TASK_SUBMISSION',
    });
    expect(sinPunto.statusCode).toBe(400);
    expect(sinPunto.json().error.mensaje).toMatch(/no tiene extensión/);
  });

  it('rechaza una entidad desconocida y una entidad que no es UUID', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const entidadRara = await firmar(arnes, {
      nombreOriginal: 'tarea.pdf',
      entityType: 'TAREA',
    });
    expect(entidadRara.statusCode).toBe(400);

    const idRaro = await firmar(arnes, {
      nombreOriginal: 'tarea.pdf',
      entityType: 'TASK_SUBMISSION',
      entidadId: 'no-es-uuid',
    });
    expect(idRaro.statusCode).toBe(400);
  });

  it('conserva el nombre original con acentos y espacios', async () => {
    // El nombre real de un documento del INCES lleva acentos. Se guarda tal cual
    // porque es el que se aplica al descargar; la clave del objeto, en cambio,
    // es un UUID.
    const arnes = crearArnés();
    app = arnes.app;

    const cuerpo = (
      await firmar(arnes, {
        nombreOriginal: 'Constancia de Trabajo José.pdf',
        entityType: 'TASK_SUBMISSION',
      })
    ).json();

    expect(cuerpo.archivo.nombreOriginal).toBe('Constancia de Trabajo José.pdf');
    expect(cuerpo.archivo.r2Key).not.toContain('José');
  });
});

describe('tope de archivos por entidad', () => {
  it('rechaza con 409 cuando la entidad ya alcanzó el máximo', async () => {
    const arnes = crearArnés({
      parametros: [parametro({ clave: 'm5_max_archivos_por_entidad', valor: 2, tipo: 'number' })],
      archivos: [
        archivoDeTarea('bbbbbbbb-0000-4000-8000-000000000001', ID_TAREA),
        archivoDeTarea('bbbbbbbb-0000-4000-8000-000000000002', ID_TAREA),
      ],
    });
    app = arnes.app;

    const respuesta = await firmar(arnes, {
      nombreOriginal: 'tarea.pdf',
      entityType: 'TASK_SUBMISSION',
      entidadId: ID_TAREA,
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json().error.codigo).toBe('DEMASIADOS_ARCHIVOS');
    expect(respuesta.json().error.detalles).toMatchObject({ yaHay: 2, maxArchivos: 2 });
  });

  it('una subida sin entidad no consume el cupo de nadie', async () => {
    // La entidad —la tarea o la guía— puede crearse después de subir el archivo.
    // Aplicar el tope a una subida suelta dejaría al usuario sin poder adjuntar
    // nada por culpa de archivos que aún no pertenecen a ningún sitio.
    const arnes = crearArnés({
      parametros: [parametro({ clave: 'm5_max_archivos_por_entidad', valor: 1, tipo: 'number' })],
      archivos: [
        archivoDeTarea('bbbbbbbb-0000-4000-8000-000000000001', null),
        archivoDeTarea('bbbbbbbb-0000-4000-8000-000000000002', null),
      ],
    });
    app = arnes.app;

    const respuesta = await firmar(arnes, {
      nombreOriginal: 'tarea.pdf',
      entityType: 'TASK_SUBMISSION',
      entidadId: null,
    });

    expect(respuesta.statusCode).toBe(201);
  });

  it('un archivo borrado libera su cupo', async () => {
    // Si un borrado siguiera ocupando sitio, borrar y volver a subir sería
    // imposible: el usuario quedaría encerrado sin entender por qué.
    const arnes = crearArnés({
      parametros: [parametro({ clave: 'm5_max_archivos_por_entidad', valor: 2, tipo: 'number' })],
      archivos: [
        archivoDeTarea('bbbbbbbb-0000-4000-8000-000000000001', ID_TAREA),
        archivoDeTarea('bbbbbbbb-0000-4000-8000-000000000002', ID_TAREA, 'DELETED'),
      ],
    });
    app = arnes.app;

    const respuesta = await firmar(arnes, {
      nombreOriginal: 'tarea.pdf',
      entityType: 'TASK_SUBMISSION',
      entidadId: ID_TAREA,
    });

    expect(respuesta.statusCode).toBe(201);
  });

  it('un tope corrupto falla en alto en vez de no aplicar tope', async () => {
    // Degradar en silencio convertiría un límite roto en «el límite que yo
    // decida», y el administrador creería estar aplicando uno que no se usa.
    const arnes = crearArnés({
      parametros: [
        parametro({ clave: 'm5_max_archivos_por_entidad', valor: 'diez', tipo: 'number' }),
      ],
    });
    app = arnes.app;

    const respuesta = await firmar(arnes, {
      nombreOriginal: 'tarea.pdf',
      entityType: 'TASK_SUBMISSION',
      entidadId: ID_TAREA,
    });

    expect(respuesta.statusCode).toBe(500);
    expect(respuesta.json().error.codigo).toBe('ERROR_INTERNO');
  });
});

describe('confirmar una subida', () => {
  it('confirma el archivo y sella el tamaño real cuando el objeto llegó', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    subirObjeto(arnes, firmada.archivo.r2Key, 2048);

    const respuesta = await confirmar(arnes, firmada.archivo.id);

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().archivo.estado).toBe('CONFIRMED');
    expect(respuesta.json().archivo.tamanoBytes).toBe(2048);
    expect(respuesta.json().archivo.confirmadoEn).not.toBeNull();
  });

  it('si el objeto no llegó responde 404 y deja la fila PENDING', async () => {
    // La subida se interrumpió. La fila **no se toca**: se queda `PENDING` para
    // que el barrido de abandonados la encuentre, que es justo para lo que existe
    // ese estado. Marcarla borrada aquí dejaría sin rastro una subida fallida.
    const arnes = crearArnés();
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    const respuesta = await confirmar(arnes, firmada.archivo.id);

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('OBJETO_NO_SUBIDO');

    const fila = arnes.estado.archivos.find((a) => a.id === firmada.archivo.id);
    expect(fila?.estado).toBe('PENDING');
    expect(arnes.almacenamiento.borrados).toEqual([]);
  });

  it('no se puede confirmar dos veces', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    subirObjeto(arnes, firmada.archivo.r2Key, 2048);

    expect((await confirmar(arnes, firmada.archivo.id)).statusCode).toBe(200);

    const segunda = await confirmar(arnes, firmada.archivo.id);
    expect(segunda.statusCode).toBe(409);
    expect(segunda.json().error.codigo).toBe('ESTADO_DE_ARCHIVO');
  });

  it('rechaza con 413 cuando el archivo se pasa del límite, y borra el objeto', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    subirObjeto(arnes, firmada.archivo.r2Key, 11 * 1024 * 1024);

    const respuesta = await confirmar(arnes, firmada.archivo.id);

    // 413 y no 400: el dato es correcto y el problema es el tamaño. El 400 queda
    // para un tamaño corrupto, que es otra cosa.
    expect(respuesta.statusCode).toBe(413);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_DEMASIADO_GRANDE');

    // El objeto se borra **antes** de marcar la fila: si fallara R2, la fila
    // sigue viva y el archivo sigue siendo reclamable; al revés quedaría un
    // objeto ocupando sitio que ya nadie conoce.
    expect(arnes.almacenamiento.borrados).toEqual([firmada.archivo.r2Key]);
    expect(arnes.almacenamiento.objetos.has(firmada.archivo.r2Key)).toBe(false);

    const fila = arnes.estado.archivos.find((a) => a.id === firmada.archivo.id);
    expect(fila?.estado).toBe('DELETED');
  });

  it('el límite sale del parámetro configurable, no de la constante', async () => {
    // Es la razón de que sea un parámetro y no una constante: el administrador lo
    // cambia desde el panel y debe surtir efecto sin desplegar. Con un límite de
    // 1 KB, un archivo de 2 KB se rechaza aunque esté muy por debajo de los 10 MB
    // del valor por defecto.
    const arnes = crearArnés({
      parametros: [parametro({ clave: 'm5_max_bytes', valor: 1024, tipo: 'number' })],
    });
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    subirObjeto(arnes, firmada.archivo.r2Key, 2048);

    const respuesta = await confirmar(arnes, firmada.archivo.id);

    expect(respuesta.statusCode).toBe(413);
    expect(respuesta.json().error.detalles).toMatchObject({
      tamanoBytes: 2048,
      maximoBytes: 1024,
    });
  });

  it('sin el parámetro sembrado cae al valor por defecto de 10 MB', async () => {
    // El caso del despliegue al que le falta la semilla. Se prueban los dos
    // lados del borde porque el fallo peligroso sería no tener tope alguno.
    const arnes = crearArnés({ parametros: [] });
    app = arnes.app;

    const justo = (await firmar(arnes)).json();
    subirObjeto(arnes, justo.archivo.r2Key, 10 * 1024 * 1024);
    expect((await confirmar(arnes, justo.archivo.id)).statusCode).toBe(200);

    const pasadizo = (await firmar(arnes)).json();
    subirObjeto(arnes, pasadizo.archivo.r2Key, 10 * 1024 * 1024 + 1);
    expect((await confirmar(arnes, pasadizo.archivo.id)).statusCode).toBe(413);
  });

  it('un límite corrupto falla en alto en vez de dejar pasar todo', async () => {
    // Un límite no numérico haría que `tamanoBytes > maximoBytes` fuera siempre
    // falso y cualquier archivo entraría. Es el agujero que este guard cierra.
    const arnes = crearArnés({
      parametros: [parametro({ clave: 'm5_max_bytes', valor: 'diez', tipo: 'number' })],
    });
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    subirObjeto(arnes, firmada.archivo.r2Key, 1);

    const respuesta = await confirmar(arnes, firmada.archivo.id);

    expect(respuesta.statusCode).toBe(500);
    expect(respuesta.json().error.codigo).toBe('ERROR_INTERNO');
  });

  it('un id que no es UUID se rechaza con 400 antes de tocar la base', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await confirmar(arnes, 'no-es-un-uuid');

    expect(respuesta.statusCode).toBe(400);
    expect(arnes.llamadas).not.toContain('archivos.porId');
  });

  it('un archivo de otro no se puede confirmar: 404', async () => {
    const arnes = crearArnés({
      archivos: [...ARCHIVOS_POR_DEFECTO, ARCHIVO_DEL_ADMIN],
    });
    app = arnes.app;

    const respuesta = await confirmar(arnes, ID_ARCHIVO_DEL_ADMIN, TOKEN_ALUMNO);

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_INEXISTENTE');
  });
});

describe('url de lectura', () => {
  it('firma la descarga de un archivo confirmado, con su nombre original', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await leer(arnes, ID_ARCHIVO_CONFIRMADO);

    expect(respuesta.statusCode).toBe(200);

    const cuerpo = respuesta.json();
    expect(cuerpo.urlDeLectura).toContain(CLAVE_ARCHIVO_CONFIRMADO);
    expect(cuerpo.urlDeLectura).toContain('firma=lectura');
    expect(cuerpo.expiraEnSegundos).toBe(arnes.env.R2_GET_TTL_SEGUNDOS);
    // El nombre viaja para que la descarga se llame «constancia.pdf» y no el
    // UUID del objeto: el adaptador lo convierte en `Content-Disposition`.
    expect(cuerpo.nombreOriginal).toBe('constancia.pdf');
  });

  it('un archivo todavía no confirmado no se puede leer: 409', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    const respuesta = await leer(arnes, firmada.archivo.id);

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_NO_DISPONIBLE');
    expect(respuesta.json().error.detalles).toMatchObject({ estado: 'PENDING' });
  });

  it('un archivo de otro responde 404 y NO 403', async () => {
    // La RLS ya lo escondió, así que desde el backend no hay forma de distinguir
    // «no existe» de «no es tuyo». Y no debe haberla: un 403 confirmaría que el
    // archivo ajeno existe, que es información que no le toca a quien pregunta.
    const arnes = crearArnés({
      archivos: [...ARCHIVOS_POR_DEFECTO, ARCHIVO_DEL_ADMIN],
    });
    app = arnes.app;

    const respuesta = await leer(arnes, ID_ARCHIVO_DEL_ADMIN, TOKEN_ALUMNO);

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.statusCode).not.toBe(403);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_INEXISTENTE');
  });

  it('un id inexistente responde 404', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await leer(arnes, 'a1b2c3d4-1111-4111-8111-999999999999');

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_INEXISTENTE');
  });
});

describe('borrado', () => {
  it('el propietario borra su archivo: la fila queda DELETED y el objeto desaparece', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await borrar(arnes, ID_ARCHIVO_CONFIRMADO);

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().archivo.estado).toBe('DELETED');
    expect(respuesta.json().archivo.borradoEn).not.toBeNull();

    // Borrado lógico: la fila se conserva, el objeto no.
    expect(arnes.estado.archivos.some((a) => a.id === ID_ARCHIVO_CONFIRMADO)).toBe(true);
    expect(arnes.almacenamiento.borrados).toEqual([CLAVE_ARCHIVO_CONFIRMADO]);
    expect(arnes.almacenamiento.objetos.has(CLAVE_ARCHIVO_CONFIRMADO)).toBe(false);
  });

  it('borrar dos veces responde 409', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    expect((await borrar(arnes, ID_ARCHIVO_CONFIRMADO)).statusCode).toBe(200);

    const segunda = await borrar(arnes, ID_ARCHIVO_CONFIRMADO);
    expect(segunda.statusCode).toBe(409);
    expect(segunda.json().error.codigo).toBe('ESTADO_DE_ARCHIVO');
  });

  it('un id inexistente responde 404', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await borrar(arnes, 'a1b2c3d4-1111-4111-8111-999999999999');

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('ARCHIVO_INEXISTENTE');
  });

  it('el administrador sí puede borrar el archivo de otro', async () => {
    // Mismo camino que el borrado del propietario, con otro portero: la RPC
    // autoriza por `is_admin()`. Que sea el mismo camino es lo que garantiza que
    // las dos formas de borrar no se desvíen.
    const arnes = crearArnés({
      archivos: [...ARCHIVOS_POR_DEFECTO, ARCHIVO_DEL_ADMIN],
    });
    app = arnes.app;

    const respuesta = await arnes.app.inject({
      method: 'DELETE',
      url: `/api/v1/admin/archivos/${ID_ARCHIVO_DEL_ADMIN}`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().archivo.estado).toBe('DELETED');
    expect(arnes.almacenamiento.borrados).toEqual([CLAVE_ARCHIVO_DEL_ADMIN]);
  });
});

describe('el tamaño sellado y el del bucket', () => {
  it('lo que la confirmación sella es lo que midió el almacén, no lo que dijo el cliente', async () => {
    // El cliente no manda tamaño en ningún momento; el único número que entra en
    // la fila es el `ContentLength` del `HeadObject`. Se comprueba con un tamaño
    // que no se parece a nada que el test haya declarado antes.
    const arnes = crearArnés();
    app = arnes.app;

    const firmada = (await firmar(arnes)).json();
    subirObjeto(arnes, firmada.archivo.r2Key, TAMANO_ARCHIVO_CONFIRMADO + 777);

    const confirmado = (await confirmar(arnes, firmada.archivo.id)).json();

    expect(confirmado.archivo.tamanoBytes).toBe(TAMANO_ARCHIVO_CONFIRMADO + 777);
  });
});
