// Configuración de Playwright para una app Flutter Web con CanvasKit.
//
// Los tiempos NO son los de una web normal, y cada uno tiene su motivo medido:
//
//   · Flutter monta el motor **después** de cargar el JS. No hay un
//     `DOMContentLoaded` que signifique «listo»: la señal es `flt-glass-pane` y
//     el placeholder de accesibilidad. Aun así, el `timeout` de test es amplio
//     porque en un runner frío el motor tarda.
//
//   · La **primera descarga de un proceso de navegador nuevo** tarda entre 4,4 y
//     5,7 s; las siguientes, entre 200 y 270 ms. Medido con `playwright-core` +
//     Chromium sobre un `Blob` real, invirtiendo el orden de los casos para
//     descartar que fuera un arranque en frío del perfil: era del navegador, no
//     de la aplicación. Por eso la espera de descarga no baja de 30 s.
//
//   · **Un solo worker.** Dos procesos de navegador a la vez contra el mismo
//     Supabase y el mismo backend no aportan nada aquí —la suite tiene un
//     camino— y sí añaden ruido: el servidor estático es uno solo y las
//     credenciales son una cuenta.
//
// El `webServer` **no compila**: sirve `build/web`. La compilación va aparte
// (`flutter build web`) porque en el sandbox de Windows el CLI de Flutter muere
// al lanzar su primer hijo (`ERROR_PIPE_BUSY`), y separar compilar de servir es
// lo que permite que el mismo archivo sirva en local y en CI.

import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

// --- Carga del entorno local -------------------------------------------------
//
// **Playwright no lee `.env` por su cuenta.** Sin este bloque, para correr en
// local hay que exportar cinco variables a mano en cada terminal, y lo que se
// olvida no es el nombre de la sección: es la contraseña, que acaba en el
// historial del shell.
//
// **No pisa lo que ya venga del entorno.** En CI las variables llegan de los
// secretos del repositorio y este archivo no existe, así que el mismo archivo de
// configuración sirve en los dos sitios y no hay una rama distinta para local.
//
// La ruta es relativa al directorio desde el que se lanza `playwright test`, que
// es `e2e/` (los scripts de `package.json` y el `working-directory` del flujo).
// Es la misma suposición que ya hace `webServer.command` con `serve.mjs`.
const ARCHIVO_LOCAL = resolve(process.cwd(), '.env.e2e');

if (existsSync(ARCHIVO_LOCAL)) {
  for (const linea of readFileSync(ARCHIVO_LOCAL, 'utf8').split(/\r?\n/)) {
    const limpia = linea.trim();
    if (limpia === '' || limpia.startsWith('#')) continue;
    const corte = limpia.indexOf('=');
    if (corte < 1) continue;
    const clave = limpia.slice(0, corte).trim();
    const valor = limpia.slice(corte + 1).trim().replace(/^["']|["']$/g, '');
    if (process.env[clave] === undefined) process.env[clave] = valor;
  }
}

/** Dónde está la app. En CI lo pone el flujo; en local, el valor por defecto. */
const BASE_URL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8090';

/** Dónde escucha el backend. `PORT` de `backend/.env` en local, 3001. */
const BACKEND_URL = process.env.E2E_BACKEND_URL ?? 'http://127.0.0.1:3001';

/** El directorio del bundle ya compilado. */
const DIRECTORIO_WEB = process.env.E2E_WEB_DIR ?? 'build/web';

/**
 * Si hay que levantar el backend.
 *
 * **Y hay que levantarlo, aunque el login no lo use.** El inicio de sesión va
 * directo contra Supabase, pero **la lista de secciones del panel no**:
 * `AdminInscripcionesRepository` construye por defecto un
 * `BackendInscripcionGateway`, que habla con Fastify. Sin backend el panel no
 * pinta ninguna tarjeta, y sin tarjetas no hay botón de exportar — el test
 * fallaría buscando un botón que nunca iba a existir, y el mensaje señalaría al
 * botón en vez de al backend apagado.
 *
 * Se puede apagar con `E2E_ARRANCAR_BACKEND=0` cuando ya está corriendo a mano.
 */
const ARRANCAR_BACKEND = process.env.E2E_ARRANCAR_BACKEND !== '0';

const servidores = [
  {
    command: `node serve.mjs "${DIRECTORIO_WEB}" ${new URL(BASE_URL).port}`,
    url: BASE_URL,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    stdout: 'pipe' as const,
    stderr: 'pipe' as const,
  },
  ...(ARRANCAR_BACKEND
    ? [
        {
          // `npm run start` ejecuta `dist/server.js`, así que en CI hay que
          // compilar el backend antes. En local, `backend/.env` ya existe y lo
          // carga el propio script con `--env-file-if-exists`.
          command: 'npm --prefix ../backend run start',
          // `/salud` es liveness y no toca la base; se espera a esa y no a
          // `/salud/profundo`, porque lo que hace falta saber aquí es que el
          // proceso escucha, no que la nube responda.
          url: `${BACKEND_URL}/salud`,
          reuseExistingServer: !process.env.CI,
          timeout: 120_000,
          stdout: 'pipe' as const,
          stderr: 'pipe' as const,
        },
      ]
    : []),
];

export default defineConfig({
  testDir: './tests',

  // El motor de Flutter, un inicio de sesión real y una descarga: 3 minutos dan
  // margen sin esconder un cuelgue.
  timeout: 180_000,

  // Una aserción sobre el árbol semántico puede necesitar varios sondeos: el
  // árbol se reconstruye en cada fotograma.
  expect: { timeout: 20_000 },

  fullyParallel: false,
  workers: 1,

  // Un reintento en CI: el primer arranque del motor es lo bastante variable
  // como para merecer una segunda oportunidad, y un fallo real falla dos veces.
  retries: process.env.CI ? 1 : 0,

  // `list` para que el registro se lea en CI sin descargar artefactos; `html`
  // para mirar el fallo en local.
  reporter: [
    ['list'],
    ['html', { outputFolder: 'informe', open: 'never' }],
  ],

  use: {
    baseURL: BASE_URL,

    // Sin esto no hay evento `download` que capturar. Es la línea que hace
    // posible toda la suite.
    acceptDownloads: true,

    // Un panel de administración con tarjetas no cabe en el tamaño por defecto
    // de Playwright (1280x720). Con 1440x900 todas las tarjetas y sus botones
    // quedan en pantalla, y el `aria-label` no depende del tamaño —pero el
    // botón que se busca por geometría, sí—.
    viewport: { width: 1440, height: 900 },

    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',

    launchOptions: {
      // En contenedores y en el sandbox de Windows, Chromium no arranca con su
      // aislamiento por defecto.
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    },
  },

  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        // `channel` vacío = el Chromium que instala `playwright install`. Para
        // usar el Chrome del sistema: E2E_CANAL=chrome.
        ...(process.env.E2E_CANAL ? { channel: process.env.E2E_CANAL } : {}),
      },
    },
  ],

  // Sirve el bundle ya compilado y levanta el backend. En local, si ya hay algo
  // escuchando en esos puertos, se reutiliza.
  webServer: servidores,
});
