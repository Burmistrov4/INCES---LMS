// Servidor estático mínimo para el bundle de Flutter Web.
//
// Por qué existe en vez de usar `flutter run -d web-server`: en el sandbox de
// Windows el CLI de Flutter no puede lanzar su primer proceso hijo
// (`ERROR_PIPE_BUSY`, `CreateFile failed 231`), así que `flutter build web` y
// `flutter run` mueren antes de empezar. Se compila en CI y aquí sólo se sirve
// el resultado. Servir es aparte de compilar, y eso es lo que permite probar en
// local lo que se pueda probar.
//
// Uso: node serve.mjs [directorio] [puerto]
//      E2E_WEB_DIR y E2E_PORT también valen.

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, resolve, sep } from 'node:path';

const RAIZ = resolve(process.argv[2] ?? process.env.E2E_WEB_DIR ?? 'build/web');
const PUERTO = Number(process.argv[3] ?? process.env.E2E_PORT ?? 8090);

const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.csv': 'text/csv; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

/**
 * Resuelve una ruta de la URL contra la raíz del bundle.
 *
 * Devuelve `null` si la ruta se sale de la raíz. **El guardia compara con
 * `resolve` en AMBOS lados a propósito**: `join` produce `\` en Windows, así que
 * un `startsWith('C:/…')` sobre el resultado de `join` falla aunque la ruta esté
 * dentro — y un guardia que rechaza lo legítimo se acaba desactivando.
 */
function resolverSeguro(urlPath) {
  const limpio = decodeURIComponent(urlPath.split('?')[0] ?? '/');
  const destino = resolve(RAIZ, '.' + limpio);
  if (destino !== RAIZ && !destino.startsWith(RAIZ + sep)) return null;
  return destino;
}

const servidor = createServer(async (peticion, respuesta) => {
  const destino = resolverSeguro(peticion.url ?? '/');
  if (destino === null) {
    respuesta.writeHead(403).end('403 fuera de la raíz');
    return;
  }

  let archivo = destino;
  try {
    const info = await stat(archivo);
    if (info.isDirectory()) archivo = join(archivo, 'index.html');
  } catch {
    // Fallback a index.html: Flutter usa estrategia de hash y también de path;
    // una ruta como /#/auth/activate no debe dar 404, y un deep link tampoco.
    archivo = join(RAIZ, 'index.html');
  }

  try {
    const contenido = await readFile(archivo);
    respuesta.writeHead(200, {
      'Content-Type': TIPOS[extname(archivo).toLowerCase()] ?? 'application/octet-stream',
      'Cache-Control': 'no-store',
      // Flutter Web con el renderizador `skwasm` necesita aislamiento cruzado;
      // con `canvaskit` (el que produce `flutter build web` sin `--wasm`) estas
      // cabeceras no estorban, pero si algún día se compila con `--wasm` hay que
      // activarlas. Se dejan puestas y documentadas.
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    });
    respuesta.end(contenido);
  } catch (error) {
    respuesta.writeHead(404).end(`404 ${archivo} (${error.message})`);
  }
});

servidor.listen(PUERTO, '127.0.0.1', () => {
  console.log(`sirviendo ${RAIZ}`);
  console.log(`en http://127.0.0.1:${PUERTO}`);
});
