import type { FastifyInstance } from 'fastify';
import { WebSocket } from 'ws';
import { afterEach, describe, expect, it } from 'vitest';
import {
  codigoAsistenciaEnVentana,
  conToken,
  crearArnés,
  ID_ALUMNO,
  ID_ALUMNO_2,
  ID_DOCENTE,
  ID_DOCENTE_2,
  ID_SECCION_SA,
  ID_SESION_ASISTENCIA,
  MODULOS_POR_DEFECTO,
  PERFIL_ALUMNO_2,
  PERFIL_DOCENTE_2,
  PERFILES_POR_DEFECTO,
  SECRETO_SESION,
  SESIONES_ASISTENCIA_POR_DEFECTO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
  TOKEN_ALUMNO_2,
  TOKEN_DOCENTE,
  VENTANA_SEG_POR_DEFECTO,
  ventanaDeAsistencia,
} from './support/arnes.js';

/**
 * M7 — la asistencia concurrente, de punta a punta sobre el arnés en memoria.
 *
 * **Por qué este archivo existe (D18).** Hasta el 2026-09-27 el módulo no tenía
 * una sola prueba de comportamiento: la barrera anti-trampas estaba cubierta por
 * la vía fuerte —la política RLS—, el verificador de esquema comprobaba contra la
 * nube que las tablas, las cinco políticas y las tres funciones existieran, y
 * `openapi.test.ts` exigía 401 sin token en cada ruta. Nada de eso mira lo que el
 * módulo **hace**. Aquí se prueba abrir una sesión, marcar, que un código
 * caducado se rechace, que la marca llegue al canal en vivo y que cerrar una
 * sesión ajena falle.
 *
 * **La arquitectura en dos canales se prueba en los dos canales.** REST guarda
 * (la marca es un hecho y vive en la base) y el WebSocket avisa (el tablero del
 * docente no hace polling). Un archivo que sólo probara REST dejaría el canal
 * del aviso —la mitad del diseño— sin ejercitar, y es justo la mitad que el
 * 2026-09-27 resultó estar **rota** (ver el bloque «el canal en vivo»).
 *
 * **Lo que estas pruebas NO pueden demostrar, y conviene tenerlo escrito:**
 *
 *   · Que la RLS rechace de verdad un código caducado. El doble del arnés
 *     reproduce la política para que la ruta trate bien lo que le llega, pero
 *     quien la aplica es Postgres. Eso lo mide `supabase/tests/validate.mjs`
 *     contra un PostgreSQL real, y `supabase/verificar-esquema.mjs` contra la
 *     nube.
 *   · Que `qr_secret` no salga por la vista ni que `asistencia_codigo_actual`
 *     sea `security definer`. Son propiedades del catálogo, y se miden ahí.
 */

let app: FastifyInstance | null = null;
let sockets: WebSocket[] = [];

afterEach(async () => {
  for (const socket of sockets) {
    if (socket.readyState === socket.OPEN || socket.readyState === socket.CONNECTING) {
      socket.terminate();
    }
  }
  sockets = [];
  await app?.close();
  app = null;
});

/** Las cuatro rutas REST del módulo, con ids válidos. */
const RUTAS = [
  { method: 'POST' as const, url: '/api/v1/asistencia/sesiones' },
  { method: 'GET' as const, url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/marcas` },
  { method: 'POST' as const, url: '/api/v1/asistencia/marcar' },
  { method: 'PATCH' as const, url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/cerrar` },
];

/**
 * El código que el docente está proyectando **ahora**.
 *
 * Se deriva con la misma función que el doble usa para validar, así que una
 * prueba que quiera un código válido no depende del reloj ni de un valor escrito
 * a mano que envejecería. El margen de la ventana está cubierto por el propio
 * doble: acepta la ventana actual **y la anterior**, igual que
 * `asistencia_codigo_vigente`, así que un cambio de ventana entre que la prueba
 * calcula el código y el servidor lo valida no la hace fallar.
 */
function codigoVigente(): string {
  return codigoAsistenciaEnVentana(
    SECRETO_SESION,
    ID_SESION_ASISTENCIA,
    ventanaDeAsistencia(VENTANA_SEG_POR_DEFECTO),
  );
}

describe('control de acceso a la asistencia', () => {
  it('exige sesión en las cuatro rutas REST y en el canal en vivo', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    for (const ruta of RUTAS) {
      const respuesta = await app.inject({ method: ruta.method, url: ruta.url });

      expect(respuesta.statusCode, `${ruta.method} ${ruta.url}`).toBe(401);
      expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
    }

    const rt = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}`,
    });

    expect(rt.statusCode).toBe(401);
    expect(rt.json().error.codigo).toBe('NO_AUTENTICADO');
  });
});

describe('la guardia de módulo que M7 NO tiene', () => {
  it('con `m7_asistencia` apagada, las rutas siguen respondiendo: no hay guardia cableada', async () => {
    // **Esta prueba fija un estado que no es el deseado, y lo hace a propósito.**
    //
    // Es D19: `m7_asistencia` está encendida y con lista blanca
    // (`['docente','admin']`), pero **ninguna** de sus rutas lleva
    // `exigirModulo('m7_asistencia')`. Ponérsela tal cual devolvería 403 al
    // estudiante en `POST /marcar` —porque la lista blanca lo excluye— y la
    // asistencia es precisamente lo que el estudiante tiene que poder hacer.
    //
    // Sin una prueba que fije el estado actual, la decisión de producto se
    // tomaría a ciegas: nadie notaría que la bandera del módulo no hace nada en
    // M7, ni que el día que se cablee el 403 aparecerá. Aquí se deja escrito y
    // medido. Cuando la decisión se tome —ensanchar la lista y proteger todo, o
    // proteger sólo las rutas del docente—, esta prueba **fallará** y obligará a
    // actualizarla, que es exactamente lo que se quiere de un cambio de contrato.
    const modulos = MODULOS_POR_DEFECTO.map((m) =>
      m.clave === 'm7_asistencia' ? { ...m, habilitado: false } : m,
    );

    // La premisa se comprueba **antes** de usarla, y no es ceremonia.
    //
    // Hasta el 2026-09-27 la semilla del arnés **no traía esta fila**: el `.map`
    // de arriba no encontraba nada que cambiar, así que la prueba pasaba **sin
    // haber apagado el módulo** —medía «la ruta responde», no «la ruta responde
    // con el módulo apagado»— y ningún rojo lo delató. Afirmar que el apagado
    // ocurrió de verdad es lo que convierte un no-op silencioso en un fallo de
    // una línea con el nombre del archivo que falta.
    const apagado = modulos.find((m) => m.clave === 'm7_asistencia');
    expect(apagado, 'la semilla del arnés no trae `m7_asistencia`').toBeDefined();
    expect(
      apagado!.habilitado,
      'el módulo no quedó apagado: la prueba no está midiendo la bandera',
    ).toBe(false);

    const arnes = crearArnés({ modulos });
    app = arnes.app;

    const marcas = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/marcas`,
      headers: conToken(TOKEN_DOCENTE),
    });

    // Ni 403 MODULO_DESHABILITADO ni 404 MODULO_DESCONOCIDO: 200. La bandera no
    // se consulta.
    expect(marcas.statusCode).toBe(200);
    expect(marcas.json()).toEqual({ marcas: [] });
  });
});

describe('validación de entrada', () => {
  it('un id de sesión que no es UUID da 400 antes de tocar nada', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const casos = [
      { method: 'GET' as const, url: '/api/v1/asistencia/sesiones/no-soy-uuid/marcas' },
      { method: 'PATCH' as const, url: '/api/v1/asistencia/sesiones/no-soy-uuid/cerrar' },
    ];

    for (const caso of casos) {
      const respuesta = await app.inject({ ...caso, headers: conToken(TOKEN_DOCENTE) });

      expect(respuesta.statusCode, `${caso.method} ${caso.url}`).toBe(400);
      expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    }
  });

  it('abrir una sesión con una sección que no es UUID da 400', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/sesiones',
      headers: conToken(TOKEN_DOCENTE),
      payload: { seccionId: 'la-seccion-de-soldadura' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
  });

  it('una ventana fuera de 5–120 s da 400, y el límite se respeta', async () => {
    // El `check (ventana_seg between 5 and 120)` de la tabla es el que manda; el
    // esquema Zod lo replica para dar un 400 que nombra el campo en vez del
    // `23514` de un check sin contexto.
    const arnes = crearArnés();
    app = arnes.app;

    for (const ventanaSeg of [4, 121, 0, -15]) {
      const respuesta = await app.inject({
        method: 'POST',
        url: '/api/v1/asistencia/sesiones',
        headers: conToken(TOKEN_DOCENTE),
        payload: { seccionId: ID_SECCION_SA, ventanaSeg },
      });

      expect(respuesta.statusCode, `ventanaSeg=${ventanaSeg}`).toBe(400);
      expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    }

    // Y el borde por dentro sí pasa: 5 es válido.
    const borde = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/sesiones',
      headers: conToken(TOKEN_DOCENTE),
      payload: { seccionId: ID_SECCION_SA, ventanaSeg: 5 },
    });

    // **200, no 201.** Se escribe a propósito porque la primera versión de esta
    // prueba esperaba 201 y falló: el manejador devuelve `reply201(sesion)`, y
    // esa función —pese al nombre— **no fija el código de estado**, sólo envuelve
    // la fila en `{ sesion }`. El contrato real es 200 y el OpenAPI lo documenta
    // como 200, así que la prueba se ajusta al contrato y no al nombre.
    expect(borde.statusCode).toBe(200);
    expect(borde.json().sesion.ventana_seg).toBe(5);
  });

  it('marcar sin código da 400: el QR sin dígitos no es una marca', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: '' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
  });
});

describe('abrir una sesión', () => {
  it('el docente que dicta la sección la abre y recibe el secreto del QR', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/sesiones',
      headers: conToken(TOKEN_DOCENTE),
      payload: { seccionId: ID_SECCION_SA },
    });

    // 200 y no 201: ver la nota del borde de la ventana, más arriba.
    expect(respuesta.statusCode).toBe(200);

    const sesion = respuesta.json().sesion;
    expect(sesion.section_id).toBe(ID_SECCION_SA);
    expect(sesion.opened_by).toBe(ID_DOCENTE);
    expect(sesion.status).toBe('OPEN');
    // La ventana por defecto la aplica Zod, no el repositorio: el `default(15)`
    // del esquema es lo que hace que omitirla signifique «15 s» y no `undefined`.
    expect(sesion.ventana_seg).toBe(VENTANA_SEG_POR_DEFECTO);
    // El secreto viaja **una sola vez**, aquí. Es de 40 caracteres hex, como el
    // que produce `crypto.getRandomValues(new Uint8Array(20))`.
    expect(typeof sesion.qr_secret).toBe('string');
    expect(sesion.qr_secret).toMatch(/^[0-9a-f]{40}$/);
  });

  it('el docente que NO dicta la sección recibe 403 y no se abre nada', async () => {
    // El segundo docente existe para esto: con el mismo docente, la comprobación
    // de propiedad no se llega a ejercitar nunca.
    const arnes = crearArnés({
      perfiles: [...PERFILES_POR_DEFECTO, PERFIL_DOCENTE_2],
      identidades: { 'token-docente-2': ID_DOCENTE_2 },
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/sesiones',
      headers: conToken('token-docente-2'),
      payload: { seccionId: ID_SECCION_SA },
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('PERMISO_DENEGADO');
    // Ni una sesión de más: la guardia corta **antes** del efecto.
    expect(arnes.estado.sesionesAsistencia).toHaveLength(
      SESIONES_ASISTENCIA_POR_DEFECTO.length,
    );
  });

  it('una sección inexistente da 400 por clave ajena, no 403', async () => {
    // La distinción importa: `403` manda a revisar permisos, `400` manda a
    // revisar el dato. Confundirlos hace buscar el problema en el sitio
    // equivocado.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/sesiones',
      headers: conToken(TOKEN_DOCENTE),
      payload: { seccionId: '00000000-0000-4000-8000-000000000099' },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('REFERENCIA_INVALIDA');
  });
});

describe('marcar asistencia', () => {
  it('el alumno matriculado marca con el código vigente', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toEqual({ ok: true, duplicada: false });

    expect(arnes.estado.marcasAsistencia).toHaveLength(1);
    const marca = arnes.estado.marcasAsistencia[0]!;
    expect(marca.sesionId).toBe(ID_SESION_ASISTENCIA);
    expect(marca.estudianteId).toBe(ID_ALUMNO);
    // Se guarda **el código que el alumno presentó**, no el que la base esperaba:
    // la columna `code` es de auditoría y sirve para reconstruir qué se escaneó.
    expect(marca.codigo).toBe(codigoVigente());
  });

  it('el mismo alumno marcando otra vez no duplica: responde `duplicada` y no un error', async () => {
    // Es la decisión del contrato y no un detalle: el cliente **no** debe cambiar
    // su UI cuando la marca ya está. Un 409 aquí haría que el alumno viera un
    // error por haber pulsado dos veces, con la asistencia ya registrada.
    const arnes = crearArnés();
    app = arnes.app;

    const primera = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });
    const segunda = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });

    expect(primera.json().duplicada).toBe(false);
    expect(segunda.statusCode).toBe(200);
    expect(segunda.json()).toEqual({ ok: true, duplicada: true });
    expect(arnes.estado.marcasAsistencia).toHaveLength(1);
  });

  it('volver a marcar con un código ya caducado sigue siendo `duplicada`, no un 403', async () => {
    // El orden de las comprobaciones **es** el contrato: el `unique
    // (session_id, student_id)` salta antes que cualquier validación de código,
    // así que un alumno que ya está contado no debe recibir un 403 —que le haría
    // creer que no marcó— por haber tardado en volver a pulsar.
    const arnes = crearArnés();
    app = arnes.app;

    await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });

    const caducado = codigoAsistenciaEnVentana(
      SECRETO_SESION,
      ID_SESION_ASISTENCIA,
      ventanaDeAsistencia(VENTANA_SEG_POR_DEFECTO) - 100,
    );

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: caducado },
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().duplicada).toBe(true);
  });

  it('un código caducado se rechaza con el 42501 de la RLS', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const caducado = codigoAsistenciaEnVentana(
      SECRETO_SESION,
      ID_SESION_ASISTENCIA,
      ventanaDeAsistencia(VENTANA_SEG_POR_DEFECTO) - 100,
    );

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: caducado },
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('PERMISO_DENEGADO');
    expect(arnes.estado.marcasAsistencia).toHaveLength(0);
  });

  it('un código inventado se rechaza igual que uno caducado', async () => {
    // `000000` es un código perfectamente formado: seis dígitos, como pide el
    // `ParseQr` del cliente. Lo que lo rechaza no es su forma sino que no
    // coincide con la derivación, y esa distinción es la que separa «validación
    // de entrada» (que no protege de nada) de «barrera anti-trampas».
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: '000000' },
    });

    expect(respuesta.statusCode).toBe(403);
    expect(arnes.estado.marcasAsistencia).toHaveLength(0);
  });

  it('el mensaje del 403 NO dice que el código caducó, y eso se deja escrito', async () => {
    // Hallazgo medido, no corregido. `traducirError` mapea el `42501` de la RLS a
    // un 403 genérico —«No tienes permisos para realizar esta acción.»— porque el
    // código de error de Postgres no distingue *por qué* la política rechazó: el
    // mismo `42501` cubre «código caducado», «no estás matriculado» y «la sesión
    // está cerrada». El alumno que llega dos segundos tarde lee un mensaje sobre
    // permisos, que le manda a buscar el problema donde no está.
    //
    // Se fija el texto **real** a propósito: una prueba que afirmara un mensaje
    // más útil estaría describiendo una API que no existe. Arreglarlo es una
    // decisión de producto —hace falta que la política emita un código distinto,
    // o que la API traduzca por contexto— y no se toma aquí.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: '000000' },
    });

    expect(respuesta.json().error.mensaje).toBe(
      'No tienes permisos para realizar esta acción.',
    );
  });

  it('un alumno NO matriculado en la sección no puede marcar, aunque el código sea válido', async () => {
    // El caso real: alguien pasa el código a un compañero de otro curso. El
    // código es correcto —lo vio en la pizarra— pero la política exige
    // `enrollments.status = 'ENROLLED'` en **esa** sección.
    //
    // El segundo alumno del arnés no está en `INSCRIPCIONES_POR_DEFECTO` —sólo el
    // de ejemplo está matriculado en SA—, así que sirve sin inventar perfiles.
    const arnes = crearArnés({
      perfiles: [...PERFILES_POR_DEFECTO, PERFIL_ALUMNO_2],
      identidades: { [TOKEN_ALUMNO_2]: ID_ALUMNO_2 },
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO_2),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });

    expect(respuesta.statusCode).toBe(403);
    expect(arnes.estado.marcasAsistencia).toHaveLength(0);
  });

  it('una sesión cerrada no acepta marcas nuevas', async () => {
    // Cerrar conserva las marcas, pero no admite más: el `status = 'OPEN'` es
    // parte del `with check` de la política.
    const arnes = crearArnés({
      sesionesAsistencia: [{ ...SESIONES_ASISTENCIA_POR_DEFECTO[0]!, status: 'CLOSED' }],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });

    expect(respuesta.statusCode).toBe(403);
  });

  it('marcar en una sesión que no existe da 403, no 404: así lo hace la RLS', async () => {
    // Es incómodo y es fiel. La política no encuentra la fila, no la deja pasar, y
    // Postgres responde `42501` — no un `PGRST116` que la ruta pudiera traducir a
    // un 404. Inventar aquí un 404 más «correcto» fijaría un contrato que la base
    // no produce.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: {
        sesionId: '00000000-0000-4000-8000-000000000099',
        codigo: codigoVigente(),
      },
    });

    expect(respuesta.statusCode).toBe(403);
  });
});

describe('las marcas de una sesión', () => {
  it('vuelven en orden cronológico', async () => {
    const arnes = crearArnés({
      marcasAsistencia: [
        {
          id: 'f6f6f6f6-0000-4000-8000-000000000002',
          sesionId: ID_SESION_ASISTENCIA,
          estudianteId: 'est-2',
          marcadaEn: '2026-09-26T10:05:00.000Z',
        },
        {
          id: 'f6f6f6f6-0000-4000-8000-000000000001',
          sesionId: ID_SESION_ASISTENCIA,
          estudianteId: 'est-1',
          marcadaEn: '2026-09-26T10:00:00.000Z',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/marcas`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);

    // El orden de llegada **es** la información: el docente lee la lista de
    // arriba abajo mientras la clase entra. Se pasan desordenadas a propósito.
    expect(respuesta.json().marcas.map((m: { student_id: string }) => m.student_id)).toEqual([
      'est-1',
      'est-2',
    ]);
  });

  it('las marcas de otra sesión no se mezclan', async () => {
    const arnes = crearArnés({
      marcasAsistencia: [
        {
          id: 'f6f6f6f6-0000-4000-8000-000000000001',
          sesionId: ID_SESION_ASISTENCIA,
          estudianteId: 'est-1',
          marcadaEn: '2026-09-26T10:00:00.000Z',
        },
        {
          id: 'f6f6f6f6-0000-4000-8000-000000000002',
          sesionId: '00000000-0000-4000-8000-000000000099',
          estudianteId: 'est-9',
          marcadaEn: '2026-09-26T10:01:00.000Z',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/marcas`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.json().marcas).toHaveLength(1);
    expect(respuesta.json().marcas[0].student_id).toBe('est-1');
  });
});

describe('cerrar una sesión', () => {
  it('el docente que la abrió la cierra, y las marcas se conservan', async () => {
    const arnes = crearArnés({
      marcasAsistencia: [
        {
          id: 'f6f6f6f6-0000-4000-8000-000000000001',
          sesionId: ID_SESION_ASISTENCIA,
          estudianteId: ID_ALUMNO,
          marcadaEn: '2026-09-26T10:00:00.000Z',
        },
      ],
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/cerrar`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json()).toEqual({ ok: true });

    expect(arnes.estado.sesionesAsistencia[0]!.status).toBe('CLOSED');
    // Cerrar **no** borra: borrar mataría el historial, y el `on delete cascade`
    // de la tabla sólo actúa si alguien borra la sesión, cosa que esta ruta no
    // hace.
    expect(arnes.estado.marcasAsistencia).toHaveLength(1);
  });

  it('cerrar la sesión de otro da 403 NO_ES_TUYA', async () => {
    // El `update ... eq('opened_by', ...)` del repositorio no toca ninguna fila y
    // la ruta lo traduce. Es la frontera de «cerrar la clase de otro».
    const arnes = crearArnés({
      perfiles: [...PERFILES_POR_DEFECTO, PERFIL_DOCENTE_2],
      identidades: { 'token-docente-2': ID_DOCENTE_2 },
    });
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/cerrar`,
      headers: conToken('token-docente-2'),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('NO_ES_TUYA');
    expect(arnes.estado.sesionesAsistencia[0]!.status).toBe('OPEN');
  });

  it('el administrador tampoco puede cerrar la sesión de un docente', async () => {
    // Se mide y se deja escrito porque **no es obvio**: el administrador ve todo
    // por RLS, pero `cerrarSesion` no pasa por una política de `all` —hace un
    // `update` filtrado por `opened_by = auth.uid()`—, así que ni el admin cierra
    // una sesión ajena. Puede ser lo deseado (la sesión es del docente) o no;
    // hasta hoy nadie lo había medido.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PATCH',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/cerrar`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('NO_ES_TUYA');
  });
});

describe('la promoción del token por query', () => {
  it('`?token=` autentica TAMBIÉN una ruta REST, y eso se deja medido', async () => {
    // El `onRequest` de `app.ts` que hace posible el WebSocket del navegador
    // promueve `?token=` a la cabecera **sin mirar la ruta ni el método**. Así que
    // el token en la query no es una puerta del canal en vivo: es una puerta de
    // toda la API.
    //
    // Se fija aquí porque es una decisión con consecuencia y hasta hoy no estaba
    // escrita en ninguna prueba. El riesgo es de filtración, no de autenticación:
    // una URL con el JWT dentro acaba en los registros de acceso del servidor, en
    // el `Referer` de un enlace saliente y en el historial del navegador, sitios
    // donde una cabecera nunca llega. El cliente de Flutter **no** lo usa por esta
    // vía —manda `Authorization` en todo lo que no sea el handshake del WS—, así
    // que el riesgo es latente, no activo.
    //
    // Acotarlo al WebSocket (o aceptarlo sólo en el `upgrade`) es un cambio de
    // seguridad y no se hace sin decisión; lo que no se puede es no saberlo.
    const arnes = crearArnés();
    app = arnes.app;

    const conQuery = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/marcas?token=${TOKEN_DOCENTE}`,
    });
    const sinNada = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/marcas`,
    });

    expect(conQuery.statusCode).toBe(200);
    expect(sinNada.statusCode).toBe(401);
  });
});

// ---------------------------------------------------------------------------
//  El canal en vivo
// ---------------------------------------------------------------------------
//
//  El WebSocket no es un adorno de M7: es la mitad del diseño. REST guarda la
//  marca y el WS **avisa** para que el tablero del docente no haga polling. Un
//  archivo de pruebas que sólo mirara REST dejaría esa mitad sin ejercitar, y es
//  justo la mitad que estaba rota.

/** Abre el socket contra el servidor real y acumula lo que llegue. */
function abrirRt(
  url: string,
  opciones: { headers?: Record<string, string> },
): {
  socket: WebSocket;
  mensajes: unknown[];
  errores: string[];
  cerrado: Promise<{ codigo: number; motivo: string }>;
} {
  const socket = new WebSocket(url, opciones);
  sockets.push(socket);

  const mensajes: unknown[] = [];
  socket.on('message', (datos) => {
    mensajes.push(JSON.parse(String(datos)));
  });

  // El manejador de `error` **no es opcional**: sin él, un handshake rechazado
  // —un 401, por ejemplo— emite un `error` sin escuchar y vitest lo reporta como
  // excepción no capturada, tumbando la suite entera por un caso que la prueba
  // esperaba. Se acumulan para poder afirmar sobre ellos, que es lo que hace
  // distinguible «me rechazaron el handshake» de «no llegó nada».
  const errores: string[] = [];
  socket.on('error', (error) => {
    errores.push(error.message);
  });

  const cerrado = new Promise<{ codigo: number; motivo: string }>((resolver) => {
    socket.on('close', (codigo, motivo) => resolver({ codigo, motivo: String(motivo) }));
  });

  return { socket, mensajes, errores, cerrado };
}

/** Espera a que llegue al menos un mensaje, o falla por tiempo. */
async function esperarMensaje(mensajes: unknown[], milisegundos = 3000): Promise<void> {
  const limite = Date.now() + milisegundos;
  while (mensajes.length === 0 && Date.now() < limite) {
    await new Promise((seguir) => setTimeout(seguir, 25));
  }
  if (mensajes.length === 0) {
    throw new Error(`No llegó ningún mensaje por el canal en ${milisegundos} ms.`);
  }
}

describe('el canal en vivo (WebSocket)', () => {
  it('el GET plano sin `?sesion` responde 400 y explica qué falta', async () => {
    // El `wsHandler` convive con un `handler` HTTP normal a propósito: si la
    // ruta declarara `websocket: true`, el GET plano daría un 404 fijo y el
    // contrato de OpenAPI —que exige a cada ruta documentada responder algo
    // distinto de 404— reprobaría.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: '/api/v1/asistencia/rt',
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('SESION_REQUERIDA');
  });

  it('con `?sesion` y el token en la CABECERA, el GET responde 200 y describe el canal', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}`,
      headers: conToken(TOKEN_DOCENTE),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().canal).toBe('websocket');
    expect(respuesta.json().sesion).toBe(ID_SESION_ASISTENCIA);
  });

  it('la marca llega al canal en vivo sin recargar nada', async () => {
    // La prueba de integración de verdad: se levanta el servidor en un puerto
    // efímero, se conecta un socket real como el docente, y se marca por REST
    // como el alumno. Lo que se comprueba es **el empuje**, que es lo que ningún
    // `inject` puede ver.
    const arnes = crearArnés();
    app = arnes.app;

    const direccion = await app.listen({ port: 0, host: '127.0.0.1' });
    const base = direccion.replace(/^http/, 'ws');

    const { mensajes } = abrirRt(
      `${base}/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}`,
      { headers: conToken(TOKEN_DOCENTE) },
    );

    await esperarMensaje(mensajes);
    expect(mensajes[0]).toEqual({ tipo: 'conectado', sesionId: ID_SESION_ASISTENCIA });

    // El alumno marca por REST, como en producción.
    const marcado = await app.inject({
      method: 'POST',
      url: '/api/v1/asistencia/marcar',
      headers: conToken(TOKEN_ALUMNO),
      payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
    });
    expect(marcado.statusCode).toBe(200);

    // Y el tablero del docente lo recibe sin haber preguntado.
    const limite = Date.now() + 3000;
    while (mensajes.length < 2 && Date.now() < limite) {
      await new Promise((seguir) => setTimeout(seguir, 25));
    }

    expect(mensajes).toHaveLength(2);
    const evento = mensajes[1] as {
      tipo: string;
      sesionId: string;
      marca: { student_id: string };
    };
    expect(evento.tipo).toBe('marca');
    expect(evento.sesionId).toBe(ID_SESION_ASISTENCIA);
    expect(evento.marca.student_id).toBe(ID_ALUMNO);
  });

  it('una marca duplicada NO se difunde: el docente no ve la fila dos veces', async () => {
    // El `difundir` está **fuera** del `if (resultado !== 'duplicada')` a
    // propósito. Si se difundiera igual, el tablero del docente pintaría dos
    // filas del mismo alumno por haber pulsado dos veces, que es el fallo que la
    // marca duplicada existe para evitar.
    const arnes = crearArnés();
    app = arnes.app;

    const direccion = await app.listen({ port: 0, host: '127.0.0.1' });
    const base = direccion.replace(/^http/, 'ws');

    const { mensajes } = abrirRt(
      `${base}/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}`,
      { headers: conToken(TOKEN_DOCENTE) },
    );

    await esperarMensaje(mensajes);

    for (let intento = 0; intento < 2; intento++) {
      await app.inject({
        method: 'POST',
        url: '/api/v1/asistencia/marcar',
        headers: conToken(TOKEN_ALUMNO),
        payload: { sesionId: ID_SESION_ASISTENCIA, codigo: codigoVigente() },
      });
    }

    // Un instante para que un evento de más tuviera tiempo de llegar.
    await new Promise((seguir) => setTimeout(seguir, 300));

    // `conectado` + **una sola** marca.
    expect(mensajes).toHaveLength(2);
  });

  it('cerrar la sesión avisa al canal con `sesion_cerrada`', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const direccion = await app.listen({ port: 0, host: '127.0.0.1' });
    const base = direccion.replace(/^http/, 'ws');

    const { mensajes } = abrirRt(
      `${base}/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}`,
      { headers: conToken(TOKEN_DOCENTE) },
    );

    await esperarMensaje(mensajes);

    await app.inject({
      method: 'PATCH',
      url: `/api/v1/asistencia/sesiones/${ID_SESION_ASISTENCIA}/cerrar`,
      headers: conToken(TOKEN_DOCENTE),
    });

    const limite = Date.now() + 3000;
    while (mensajes.length < 2 && Date.now() < limite) {
      await new Promise((seguir) => setTimeout(seguir, 25));
    }

    expect(mensajes[1]).toEqual({
      tipo: 'sesion_cerrada',
      sesionId: ID_SESION_ASISTENCIA,
    });
  });

  it('el handshake que hace el cliente Flutter —token en la QUERY— se acepta', async () => {
    // **Éste es el camino de producción, y hasta hoy no lo probaba nadie.**
    //
    // El cliente (`lib/services/asistencia_service.dart`, `enVivo`) construye la
    // URL con el JWT en la query:
    //
    //   '$base/api/v1/asistencia/rt?sesion=$sesionId&token=$jwt'
    //
    // y **no puede hacer otra cosa**: en un navegador la API de WebSocket no
    // admite cabeceras personalizadas, así que `Authorization` es imposible en el
    // handshake. Eso significa que si este camino se rompiera, la mitad «avisa»
    // de M7 —el tablero en vivo del docente— moriría entera y sin ruido: el
    // socket no abre, la pantalla se queda con la lista vacía y ningún error
    // visible, porque un fallo de WebSocket no pasa por el manejador de errores
    // de la aplicación.
    //
    // **Aquí me equivoqué, y queda escrito para que no se repita.** Leyendo sólo
    // `exigirSesion` y `extraerToken` —que sí miran únicamente
    // `Authorization: Bearer`— concluí que esto estaba roto y estuve a punto de
    // declararlo deuda. No lo estaba: `src/app.ts` registra un `onRequest`
    // **antes** del plugin de autenticación que promueve `?token=` a la cabecera,
    // justo con esta razón. La medición —esta prueba— lo desmintió en la primera
    // ejecución. Es la lección de siempre: una lectura parcial de un lado de la
    // frontera no es una medición.
    const arnes = crearArnés();
    app = arnes.app;

    const direccion = await app.listen({ port: 0, host: '127.0.0.1' });
    const base = direccion.replace(/^http/, 'ws');

    // Exactamente lo que manda el cliente: el token en la query, y **ninguna**
    // cabecera de autorización.
    const { mensajes } = abrirRt(
      `${base}/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}&token=${TOKEN_DOCENTE}`,
      {},
    );

    // Lo que se espera del canal es un **mensaje**, no que el socket abra: un
    // socket puede abrir y cerrarse acto seguido —`manejarSuscripcion` cierra con
    // el código 4001 cuando no hay usuario—, y comprobar el evento `open` daría
    // por bueno un canal que no entrega nada.
    await esperarMensaje(mensajes, 3000);

    expect(mensajes[0]).toEqual({ tipo: 'conectado', sesionId: ID_SESION_ASISTENCIA });
  });

  it('sin token el handshake se rechaza con 401 antes de abrir el canal', async () => {
    // El contrapeso de la prueba anterior. **Medido, porque no era lo que yo
    // esperaba:** el `preHandler` `exigirSesion()` corre antes del `upgrade`, así
    // que sin token el servidor responde **401 y no completa el handshake** — no
    // es un socket que abre y se cierra acto seguido.
    //
    // Y de ahí sale un hallazgo que se deja escrito: la guardia
    // `if (!request.usuario) socket.close(4001, 'sin sesión')` de
    // `manejarSuscripcion` es **inalcanzable**. `exigirSesion` lanza exactamente
    // cuando `!request.usuario`, así que el manejador nunca se ejecuta en ese
    // caso. No se toca —una defensa que no estorba y que protege si alguien
    // reordena los hooks— pero conviene saber que no es ella la que está
    // protegiendo el canal.
    const arnes = crearArnés();
    app = arnes.app;

    const direccion = await app.listen({ port: 0, host: '127.0.0.1' });
    const base = direccion.replace(/^http/, 'ws');

    const { mensajes, errores, cerrado } = abrirRt(
      `${base}/api/v1/asistencia/rt?sesion=${ID_SESION_ASISTENCIA}`,
      {},
    );

    const resultado = await Promise.race([
      esperarMensaje(mensajes, 2000).then(() => 'mensaje'),
      cerrado.then(({ codigo }) => `cerrado:${codigo}`),
    ]);

    // El cliente ve un error de handshake con el 401 del servidor, y ninguna
    // marca de que fuera un problema de sesión salvo el número.
    expect(errores.join(' ')).toContain('401');
    expect(resultado).not.toBe('mensaje');
    expect(mensajes).toHaveLength(0);
  });

  it('con token pero sin `?sesion` válido, el canal abre y se cierra con 4000', async () => {
    // El otro cierre de `manejarSuscripcion`, y éste **sí** es alcanzable: el
    // token pasa la guardia, el upgrade se completa, y el manejador rechaza el
    // identificador de sesión antes de suscribir a nadie. Es lo que ocurre si un
    // cliente construye mal la URL —y es la única señal que tendría—.
    const arnes = crearArnés();
    app = arnes.app;

    const direccion = await app.listen({ port: 0, host: '127.0.0.1' });
    const base = direccion.replace(/^http/, 'ws');

    const { mensajes, cerrado } = abrirRt(
      `${base}/api/v1/asistencia/rt?sesion=no-soy-un-uuid&token=${TOKEN_DOCENTE}`,
      {},
    );

    const { codigo, motivo } = await cerrado;

    expect(codigo).toBe(4000);
    expect(motivo).toBe('sesión inválida');
    expect(mensajes).toHaveLength(0);
  });
});
