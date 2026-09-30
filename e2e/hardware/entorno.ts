// Constantes del PUENTE DE HARDWARE, en un solo sitio.
//
// Vive aparte de la configuración porque la necesitan **los dos**: el
// `playwright.hardware.config.ts` (para los `args` de Chromium y el `webServer`)
// y el propio spec (para saber qué contenido tiene que leer el escáner). Si
// estuvieran duplicadas, el día que se regenere el vídeo con otro texto el
// runner seguiría esperando el viejo y el fallo se leería como «el escáner no
// lee» — que es justo el fallo que este puente existe para medir.

import { existsSync, readFileSync } from 'node:fs';

/**
 * El vídeo que Chromium usará **como si fuera la cámara**.
 *
 * Ruta absoluta y con barras invertidas a propósito: el flag de Chromium recibe
 * una ruta del sistema operativo, y una ruta relativa se resolvería contra el
 * directorio de trabajo del navegador —que no es el nuestro—. Es la causa más
 * habitual de que `--use-file-for-fake-video-capture` «no haga nada».
 */
export const QR_Y4M = process.env.E2E_QR_Y4M ?? 'C:\\tmp\\qr_dummy.y4m';

/** Dónde se sirve el bundle descargado del CI. */
export const DIRECTORIO_WEB = process.env.E2E_WEB_DIR ?? 'C:/tmp/web-bundle';

/** Dónde escucha la app servida. `127.0.0.1` es contexto seguro: `getUserMedia` existe. */
export const BASE_URL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8090';

/** Dónde escucha Fastify. El marcaje del alumno va por aquí. */
export const BACKEND_URL = process.env.E2E_BACKEND_URL ?? 'http://127.0.0.1:3001';

/** La URL exacta del lector de respaldo, leída del paquete. Ver [URL_ZXING_WASM]. */
export const URL_ZXING_WASM =
  'https://cdn.jsdelivr.net/npm/zxing-wasm@3.1.3/dist/iife/reader/index.js';

/**
 * Los tres flags que convierten a Chromium en una cámara que emite nuestro vídeo.
 *
 * Los tres hacen falta y ninguno es opcional:
 *
 *   · `--use-fake-device-for-media-stream` — sustituye el dispositivo de captura
 *     por uno sintético. Sin él no hay ninguna cámara (esta máquina sólo tiene
 *     «OBS Virtual Camera», que emite negro) y `getUserMedia` no tendría fuente.
 *
 *   · `--use-file-for-fake-video-capture=<ruta>` — le dice a ese dispositivo
 *     sintético que lea los fotogramas de un archivo. **Requiere que el flag
 *     anterior esté puesto**: por sí solo no hace nada. Acepta `.y4m` y
 *     `.mjpeg`.
 *
 *   · `--use-fake-ui-for-media-stream` — concede el permiso solo, sin diálogo.
 *     Sin él, Chromium abre un `prompt()` que en un test **nadie puede
 *     contestar**: el caso se queda colgado hasta agotar el tiempo, y el fallo
 *     se lee como «la cámara no arrancó» cuando lo que pasó es que se quedó
 *     esperando a una persona.
 */
export const ARGS_CAMARA_FALSA = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  `--use-file-for-fake-video-capture=${QR_Y4M}`,
];

/** De dónde salió el contenido esperado. Se imprime: saber la fuente evita dudas. */
export interface ContenidoEsperado {
  texto: string;
  origen: string;
  fiable: boolean;
}

/**
 * El contenido que el escáner **tiene** que leer, sin posibilidad de deriva.
 *
 * Se resuelve en tres escalones, de más fiable a menos:
 *
 *   1. `E2E_QR_PAYLOAD` — lo dice quien lanza la prueba.
 *   2. El **sidecar** que `devops/generar-qr-y4m.mjs` escribe junto al vídeo
 *      (`<ruta>.json`). Es el escalón que hace imposible la desincronización: la
 *      verdad del contenido viaja pegada al archivo que lo contiene.
 *   3. Un valor por defecto, marcado como **no fiable**, porque un vídeo
 *      regenerado con otro texto lo dejaría obsoleto sin que nadie se entere.
 */
export function contenidoEsperado(): ContenidoEsperado {
  const delEntorno = process.env.E2E_QR_PAYLOAD;
  if (delEntorno !== undefined && delEntorno !== '') {
    return { texto: delEntorno, origen: 'variable E2E_QR_PAYLOAD', fiable: true };
  }

  const sidecar = `${QR_Y4M}.json`;
  if (existsSync(sidecar)) {
    try {
      const datos = JSON.parse(readFileSync(sidecar, 'utf8')) as { texto?: unknown };
      if (typeof datos.texto === 'string' && datos.texto !== '') {
        return { texto: datos.texto, origen: `sidecar ${sidecar}`, fiable: true };
      }
    } catch {
      // Un sidecar ilegible no puede tumbar la prueba: se cae al escalón
      // siguiente y el `origen` lo delata.
    }
  }

  return {
    texto: '3f2a1b4c-5d6e-7f80-9a1b-2c3d4e5f6071:471212',
    origen: 'valor por defecto — NO verificado contra el vídeo',
    fiable: false,
  };
}

/** El par `<uuid>:<6 dígitos>` descompuesto, que es lo que espera la API. */
export function parDelQr(texto: string): { sesionId: string; codigo: string } | null {
  const corte = texto.indexOf(':');
  if (corte < 1) return null;
  return { sesionId: texto.slice(0, corte), codigo: texto.slice(corte + 1) };
}
