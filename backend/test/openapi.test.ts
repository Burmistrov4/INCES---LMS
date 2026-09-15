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
 * que las **rutas** documentadas sean exactamente las que existen. Eso no lo
 * puede saber el generador, porque las rutas se registran llamando a Fastify.
 *
 * Estas pruebas cierran esa mitad comparando las dos listas, en las dos
 * direcciones.
 */

const AQUI = dirname(fileURLToPath(import.meta.url));
const RUTA_ARTEFACTO = join(AQUI, '..', 'openapi.json');

let app: Arnés['app'] | undefined;

afterEach(async () => {
  await app?.close();
  app = undefined;
});

/**
 * Enumera las rutas que la aplicación tiene registradas de verdad.
 *
 * Se lee el árbol de `printRoutes({ commonPrefix: false })`, que sólo está
 * completo **después de `await app.ready()`**: las rutas de M2 y M3 se montan
 * dentro de un `app.register(...)`, y hasta que Fastify no resuelve el árbol
 * asíncrono no aparecen. Sin el `ready()`, el árbol muestra sólo las cinco rutas
 * registradas directamente sobre la instancia y la comparación daría un verde
 * hueco sobre dos listas incompletas.
 *
 * El formato de cada línea es `<sangría>[├|└]── <ruta> (MÉTODO, MÉTODO)`, y la
 * profundidad la da el número de grupos de cuatro caracteres de la sangría; cada
 * nivel continúa la ruta del anterior. Se depende de ese formato a propósito: si
 * una versión de Fastify lo cambiara, la prueba falla en vez de comparar dos
 * listas vacías y pasar sin haber mirado nada.
 *
 * `HEAD` lo añade Fastify solo y `OPTIONS` es el comodín del 404 y del CORS:
 * ninguno de los dos se documenta ni lo pide un cliente, así que se filtran. El
 * comodín `*` tampoco es una ruta.
 */
function rutasRegistradas(aplicacion: Arnés['app']): string[] {
  const arbol = aplicacion.printRoutes({ commonPrefix: false });
  const rutas: string[] = [];
  /** La ruta completa de cada nivel, para que un hijo sepa a quién colgarse. */
  const completas: string[] = [];

  for (const linea of arbol.split('\n')) {
    const coincidencia = /^([│\s]*)[├└]─+ (.*)$/.exec(linea);
    if (!coincidencia) continue;

    const nivel = (coincidencia[1] ?? '').length / 4;
    const contenido = coincidencia[2] ?? '';

    const separador = contenido.lastIndexOf(' (');
    if (separador < 0) continue;

    const segmento = contenido.slice(0, separador);
    if (segmento === '*') continue;

    const metodos = contenido
      .slice(separador + 2, -1)
      .split(', ')
      .filter((metodo) => metodo !== 'HEAD' && metodo !== 'OPTIONS');

    completas[nivel] = nivel === 0 ? segmento : `${completas[nivel - 1] ?? ''}${segmento}`;

    for (const metodo of metodos) {
      // Fastify escribe `:param`; OpenAPI, `{param}`.
      const ruta = (completas[nivel] ?? '').replace(/:([A-Za-z0-9_]+)/g, '{$1}');
      rutas.push(`${metodo} ${ruta}`);
    }
  }

  return rutas.sort();
}

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

  it('el documento y la aplicación registran exactamente las mismas rutas', async () => {
    // Se comparan las dos direcciones a la vez: una ruta documentada que la
    // aplicación no conoce, y una ruta que la aplicación registra y el documento
    // no menciona.
    //
    // La versión anterior de esta prueba cotejaba contra una lista escrita a
    // mano, y eso **sólo detectaba el primer caso**: añadir una ruta y olvidar
    // documentarla pasaba inadvertido, que es justo el fallo que la deuda D6
    // existe para evitar. Comparar contra las rutas reales cierra las dos.
    const arnés = crearArnés();
    app = arnés.app;
    await arnés.app.ready();

    const documento = construirDocumentoOpenApi();
    const documentadas = Object.entries(documento.paths ?? {})
      .flatMap(([ruta, operaciones]) =>
        Object.keys(operaciones)
          .filter((metodo) => metodo !== 'parameters')
          .map((metodo) => `${metodo.toUpperCase()} ${ruta}`),
      )
      .sort();

    const reales = rutasRegistradas(arnés.app);

    // Un mínimo sensato: si el árbol se dejara de parsear, `reales` quedaría
    // vacía y una comparación entre dos listas vacías sería un verde hueco.
    // `documentadas` no puede estar vacía (hay una prueba que lo comprueba).
    expect(reales.length).toBeGreaterThan(20);
    expect(documentadas).toEqual(reales);
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
