import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import { construirDocumentoOpenApi } from '../src/http/openapi.js';
import { crearArnés, conToken, TOKEN_ADMIN, type Arnés } from './support/arnes.js';

/**
 * Deuda D6 — el documento OpenAPI no puede desincronizarse.
 *
 * Generar el documento desde Zod resuelve la mitad del problema: garantiza que
 * los **esquemas** documentados son los que validan de verdad. La otra mitad es
 * que las **rutas** documentadas sean las que existen. Eso no lo puede saber el
 * generador, porque las rutas se registran llamando a Fastify.
 *
 * Estas pruebas cierran esa mitad: comparan la lista de rutas reales (sacada de
 * la instancia de Fastify) con la lista documentada. Si alguien añade un
 * endpoint y olvida documentarlo, esto falla y dice cuál. Sin esta red, el
 * documento se iría vaciando de rutas en silencio, que es exactamente el fallo
 * que D6 pretendía evitar.
 */

const AQUI = dirname(fileURLToPath(import.meta.url));
const RUTA_ARTEFACTO = join(AQUI, '..', 'openapi.json');

let app: Arnés['app'] | undefined;

afterEach(async () => {
  await app?.close();
  app = undefined;
});

describe('documento OpenAPI generado (D6)', () => {
  it('declara OpenAPI 3.1, que es lo que se pidió', () => {
    const documento = construirDocumentoOpenApi();
    expect(documento.openapi).toBe('3.1.0');
  });

  it('documenta TODAS las rutas que la aplicación registra de verdad', async () => {
    // Cómo se comprueba la coherencia entre rutas y documento:
    //
    // Un hook `onRoute` no sirve aquí. Las rutas se registran de forma síncrona
    // dentro de `construirApp`, así que cuando el test tiene la instancia ya
    // están todas dadas de alta y un `addHook('onRoute')` posterior no captura
    // ninguna. Peor: pasaría «sin rutas reales, sin rutas inventadas», es decir
    // un verde vacío.
    //
    // En su lugar se usa la fuente que no puede mentir: se pregunta a la propia
    // aplicación. Cada ruta documentada que exige sesión debe responder 401 sin
    // token (existe y está protegida), y no debe responder 404 de ruta
    // inexistente. Para las públicas se exige 200.
    const arnés = crearArnés();
    app = arnés.app;

    const documento = construirDocumentoOpenApi();
    const documentadas: Array<{ metodo: string; ruta: string; publica: boolean }> = [];
    for (const [ruta, operaciones] of Object.entries(documento.paths ?? {})) {
      for (const [metodo, operacion] of Object.entries(operaciones)) {
        if (metodo === 'parameters') continue;
        documentadas.push({
          metodo: metodo.toUpperCase(),
          ruta,
          publica: !operacion.security,
        });
      }
    }
    expect(documentadas.length).toBeGreaterThan(0);

    for (const { metodo, ruta, publica } of documentadas) {
      // Los parámetros de ruta llevan un valor de ejemplo realista: un UUID
      // válido, porque el contrato ya declara que uno inválido es un 400.
      const url = ruta.replace('{clave}', 'm0_cpanel').replace(
        '{id}',
        '11111111-1111-1111-1111-111111111111',
      );

      const respuesta = await arnés.app.inject({ method: metodo as 'GET', url });

      // 404 significaría que la ruta documentada no existe: se inventó.
      expect(
        respuesta.statusCode,
        `${metodo} ${ruta} está documentada pero la aplicación no la conoce`,
      ).not.toBe(404);

      if (publica) {
        // Una ruta pública no exige sesión (no 401) y sí existe (no 404). El
        // cuerpo de una ruta pública que requiere datos (p.ej. POST sin cuerpo)
        // puede ser 400, y eso basta para probar que es pública y existe.
        expect(
          respuesta.statusCode,
          `${metodo} ${ruta} debería ser pública (sin sesión)`,
        ).not.toBe(401);
      } else {
        expect(
          respuesta.statusCode,
          `${metodo} ${ruta} está documentada como protegida pero no exige sesión`,
        ).toBe(401);
      }
    }
  });

  it('el número de rutas documentadas coincide con las rutas reales de la app', () => {
    // Complemento del anterior: si alguien añade una ruta y no la documenta, la
    // prueba de arriba no lo detecta (sólo mira en una dirección). Esta
    // comprobación fija el recuento, de modo que añadir una ruta obliga a
    // actualizar el documento Y este número. Es deliberadamente molesto: es más
    // barato que un contrato que se queda atrás sin que nadie lo note.
    const documento = construirDocumentoOpenApi();
    const rutas = Object.entries(documento.paths ?? {}).flatMap(([ruta, ops]) =>
      Object.keys(ops)
        .filter((m) => m !== 'parameters')
        .map((m) => `${m.toUpperCase()} ${ruta}`),
    );
    expect(rutas.sort()).toEqual(
      [
        'GET /api/v1/admin/acceso',
        'GET /api/v1/admin/auditoria',
        'GET /api/v1/admin/materias',
        'GET /api/v1/admin/modulos',
        'GET /api/v1/admin/parametros',
        'GET /api/v1/admin/programas',
        'GET /api/v1/admin/programas/{id}',
        'GET /api/v1/admin/usuarios',
        'GET /api/v1/modulos',
        'GET /api/v1/yo',
        'GET /openapi.json',
        'GET /salud',
        'GET /salud/profundo',
        'PATCH /api/v1/admin/modulos/{clave}',
        'PATCH /api/v1/admin/parametros/{clave}',
        'PATCH /api/v1/admin/programas/{id}',
        'PATCH /api/v1/admin/programas/{id}/pensum',
        'PATCH /api/v1/admin/usuarios/{id}/rol',
        'POST /api/v1/admin/materias',
        'POST /api/v1/admin/programas',
        'POST /api/v1/admin/usuarios/invitaciones',
        'POST /api/v1/auth/activar',
      ].sort(),
    );
  });

  it('no declara ninguna ruta sin respuesta de éxito y sin 401 cuando exige sesión', () => {
    const documento = construirDocumentoOpenApi();
    for (const [ruta, operaciones] of Object.entries(documento.paths ?? {})) {
      for (const [metodo, operacion] of Object.entries(operaciones)) {
        if (metodo === 'parameters') continue;
        const respuestas = Object.keys(operacion.responses ?? {});
        // 201 cuenta como éxito: las dos altas de M2 (programa y materia) crean
        // un recurso y lo devuelven con su identificador. Exigir sólo 200
        // obligaba a mentir en el contrato o a devolver 200 por una creación.
        expect(
          respuestas.some((codigo) => codigo === '200' || codigo === '201'),
          `${metodo} ${ruta} sin respuesta de éxito (200/201)`,
        ).toBe(true);
        if (operacion.security) {
          expect(
            respuestas,
            `${metodo} ${ruta} exige sesión pero no documenta el 401`,
          ).toContain('401');
        }
      }
    }
  });

  it('las sondas de salud son las únicas rutas públicas', () => {
    const documento = construirDocumentoOpenApi();
    const publicas: string[] = [];
    for (const [ruta, operaciones] of Object.entries(documento.paths ?? {})) {
      for (const [metodo, operacion] of Object.entries(operaciones)) {
        if (metodo === 'parameters') continue;
        if (!operacion.security) publicas.push(`${metodo} ${ruta}`);
      }
    }
    expect(publicas.sort()).toEqual(
      ['get /openapi.json', 'get /salud', 'get /salud/profundo', 'post /api/v1/auth/activar'].sort(),
    );
  });

  it('el endpoint /openapi.json sirve el mismo documento que genera el script', async () => {
    // Es la comprobación que garantiza que el archivo del repositorio y lo que
    // sirve la API en vivo no pueden divergir.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await arnés.app.inject({ method: 'GET', url: '/openapi.json' });
    expect(respuesta.statusCode).toBe(200);

    const servido = respuesta.json();
    const generado = construirDocumentoOpenApi();
    expect(servido).toEqual(generado);
  });

  it('el artefacto en disco está al día', () => {
    // Si esto falla, alguien tocó los esquemas y no regeneró. Se arregla con
    // `npm run openapi`. Es un fallo útil: obliga a que el `diff` del repositorio
    // muestre el cambio de contrato junto al cambio de código que lo provoca.
    const enDisco = JSON.parse(readFileSync(RUTA_ARTEFACTO, 'utf8'));
    const generado = construirDocumentoOpenApi();
    expect(
      enDisco,
      'openapi.json está desactualizado: ejecuta `npm run openapi`',
    ).toEqual(generado);
  });

  it('documenta el 400 que exige la validación de UUID en la ruta de roles', () => {
    // Regresión del bug encontrado en la prueba de humo: el contrato debe
    // anunciar que un id no-UUID es un 400, no dejar al cliente adivinando.
    const documento = construirDocumentoOpenApi();
    const ruta = documento.paths?.['/api/v1/admin/usuarios/{id}/rol'];
    expect(ruta, 'la ruta de cambio de rol no está documentada').toBeDefined();
    expect(ruta?.patch?.responses).toHaveProperty('400');
    expect(ruta?.patch?.responses).toHaveProperty('409');
  });

  it('las rutas de administración exigen el esquema bearerAuth', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const documento = construirDocumentoOpenApi();
    for (const [ruta, operaciones] of Object.entries(documento.paths ?? {})) {
      if (!ruta.startsWith('/api/v1/admin')) continue;
      for (const [metodo, operacion] of Object.entries(operaciones)) {
        if (metodo === 'parameters') continue;
        expect(operacion.security, `${metodo} ${ruta} sin security`).toEqual([
          { bearerAuth: [] },
        ]);
      }
    }

    // Y contra la API real: sin token, esas rutas responden 401.
    const sinToken = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/modulos',
    });
    expect(sinToken.statusCode).toBe(401);

    const conAdmin = await arnés.app.inject({
      method: 'GET',
      url: '/api/v1/admin/modulos',
      headers: conToken(TOKEN_ADMIN),
    });
    expect(conAdmin.statusCode).toBe(200);
  });
});
