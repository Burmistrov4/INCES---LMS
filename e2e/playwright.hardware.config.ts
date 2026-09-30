// Configuración del PUENTE DE HARDWARE — Fase 2 del plan de QA.
//
// POR QUÉ ES UN ARCHIVO APARTE Y NO UN `project` MÁS
// --------------------------------------------------
// La suite de CI (`playwright.config.ts`) sirve el bundle con la cámara del
// sistema **tal cual**, y ahí no hay ninguna: esta máquina sólo tiene «OBS
// Virtual Camera». Meter aquí los flags de cámara falsa cambiaría el entorno de
// la suite que ya está en verde y que mide otra cosa (la ruta de descarga del
// CSV). Dos entornos distintos, dos archivos; y el de CI no se toca.
//
// Tampoco se recoge sola: `e2e.yml` corre `npx playwright test`, que usa
// `playwright.config.ts` (`testDir: './tests'`). Este archivo se invoca a mano:
//
//   cd e2e
//   npx playwright test -c playwright.hardware.config.ts
//
// PARA QUÉ SIRVE
// --------------
// Responde a una pregunta que hasta ahora no tenía respuesta posible: **¿el
// escáner de QR funciona de verdad?** En `flutter test` no hay cámara, y no hay
// JDK ≥ 17 para compilar el APK, así que ni la lectura ni el permiso los
// verificaba nadie. Aquí se sustituye la cámara por un vídeo que contiene un QR
// conocido, y se comprueba que el paquete lo lee y que la app hace con él lo que
// tiene que hacer.
//
// QUÉ NO ES
// ---------
// **No es una prueba del hardware real.** Un `--use-file-for-fake-video-capture`
// no ejercita el driver, ni el permiso del sistema operativo, ni la cámara
// física. Prueba la cadena «fotograma → decodificador → texto → API», que es
// toda la lógica que vive en Dart y en el paquete. La cámara física sigue
// necesitando un dispositivo, y eso se dice en el informe en vez de darlo por
// cubierto.

import { defineConfig } from '@playwright/test';

import {
  ARGS_CAMARA_FALSA,
  BACKEND_URL,
  BASE_URL,
  DIRECTORIO_WEB,
} from './hardware/entorno.js';

const ARRANCAR_BACKEND = process.env.E2E_ARRANCAR_BACKEND !== '0';

export default defineConfig({
  testDir: './hardware',

  // El motor de Flutter, una sesión real, la cámara y una lectura por sondeo:
  // el recorrido completo no cabe en menos.
  timeout: 240_000,

  // El árbol semántico se reconstruye en cada fotograma, y el lector de códigos
  // trabaja por sondeo: una aserción necesita varios intentos por diseño.
  expect: { timeout: 30_000 },

  fullyParallel: false,
  workers: 1,
  retries: 0,

  reporter: [
    ['list'],
    ['html', { outputFolder: 'informe-hardware', open: 'never' }],
  ],

  use: {
    baseURL: BASE_URL,

    // **`headless: false` no es un capricho de depuración.** Chromium sólo lee
    // `--use-file-for-fake-video-capture` cuando hay una superficie real donde
    // pintar; en modo headless sin pantalla el dispositivo sintético puede
    // arrancar sin entregar fotogramas, y el fallo se leería como «el escáner no
    // lee» cuando lo que falta es una ventana.
    headless: false,

    viewport: { width: 1440, height: 900 },

    launchOptions: {
      args: [
        // Los tres de la cámara falsa, en el orden que documenta `entorno.ts`.
        ...ARGS_CAMARA_FALSA,
        // En el sandbox de Windows Chromium no arranca con su aislamiento.
        '--no-sandbox',
        '--disable-dev-shm-usage',
      ],
    },

    // --- Grabación: apagada por defecto, y no por gusto ----------------------
    //
    // **Medido el 2026-09-29, en esta máquina.** Con la grabación encendida la
    // prueba **pasa** —7,0 s, `ok 1`— pero el proceso **no termina**: se queda
    // colgado después del caso y antes de escribir el informe. La prueba está en
    // el registro y `test-results/.playwright-artifacts-0` existe, pero
    // `informe-hardware/` no llega a crearse nunca. Un runner que no termina no
    // es un runner: hay que matarlo a mano y el código de salida se pierde, así
    // que dentro de un flujo automatizado sería inútil.
    //
    // Se encienden por variable de entorno cuando de verdad hacen falta —al
    // depurar un fallo concreto— y se apagan para el uso normal. Un vídeo del
    // recorrido es la prueba más directa de lo que pasó, pero sólo cuando hay
    // algo que mirar.
    video: process.env.E2E_VIDEO === '1' ? 'retain-on-failure' : 'off',
    trace: process.env.E2E_TRACE === '1' ? 'retain-on-failure' : 'off',
    screenshot: 'only-on-failure',
  },

  webServer: [
    {
      // Sirve el bundle **descargado del CI**. No se compila aquí: en esta
      // máquina `flutter build web` no arranca (`CreateFile failed 231`), y ese
      // es justo el motivo de haber añadido el artefacto `web-bundle` al flujo.
      command: `node serve.mjs "${DIRECTORIO_WEB}" ${new URL(BASE_URL).port}`,
      url: BASE_URL,
      reuseExistingServer: true,
      timeout: 60_000,
      stdout: 'pipe' as const,
      stderr: 'pipe' as const,
    },
    ...(ARRANCAR_BACKEND
      ? [
          {
            // El recorrido del alumno manda el marcaje por Fastify. Se levanta
            // aquí y no a mano con `&` porque `webServer` sabe esperar a `/salud`
            // y lo apaga al terminar.
            command: 'npm --prefix ../backend run start',
            url: `${BACKEND_URL}/salud`,
            reuseExistingServer: true,
            timeout: 120_000,
            stdout: 'pipe' as const,
            stderr: 'pipe' as const,
          },
        ]
      : []),
  ],
});
