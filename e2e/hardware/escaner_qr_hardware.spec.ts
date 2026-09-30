// El puente de hardware del escáner de QR (M7 · D21) — Fase 2 del plan de QA.
//
// LA PREGUNTA QUE RESPONDE
// ------------------------
// «¿El escáner de QR funciona?» no tenía respuesta medible. En `flutter test` no
// hay cámara, y no hay JDK ≥ 17 para compilar el APK, así que la lectura y el
// permiso no los verificaba nadie: quedaba una capa entera —la cámara— afirmada
// sólo por su comentario.
//
// Aquí se sustituye la cámara por un vídeo con un QR conocido
// (`devops/generar-qr-y4m.mjs`), y se mide la cadena completa:
//
//     fotograma → decodificador → texto → ParseQr → POST /marcar
//
// DOS PRUEBAS, Y LA SEGUNDA SE SALTA SOLA
// ---------------------------------------
//   1. **El puente.** No necesita credenciales. Comprueba que la cámara falsa
//      entrega el vídeo a la página y que un lector lo decodifica hasta el texto
//      exacto. Es la mitad que depende del entorno (flags, códec, COEP, CDN).
//
//   2. **El recorrido.** Necesita credenciales **de alumno**. Recorre la
//      interfaz de verdad: entra, abre «Asistencia», pulsa el botón del escáner
//      y comprueba que el paquete lee el QR inyectado y que la app manda el
//      marcaje con el par correcto. Sin credenciales se **salta con un motivo
//      legible**, no falla: un rojo por falta de un secreto es ruido, y este
//      proyecto ya tiene D9 como para añadir otro.
//
// LO QUE ESTA PRUEBA **NO** CUBRE, Y SE DICE EN VOZ ALTA
// -----------------------------------------------------
// No ejercita la cámara física, ni el driver, ni el diálogo de permiso del
// sistema operativo: `--use-fake-ui-for-media-stream` lo concede solo. Un verde
// aquí significa «la lógica de lectura y marcaje está bien», **no** «el permiso
// del móvil está bien». Esa mitad sigue necesitando un dispositivo.

import { existsSync } from 'node:fs';

import { expect, test, type Page } from '@playwright/test';

import { FlutterApp } from '../src/pages/FlutterApp.js';
import { LoginPage, SENAL_DE_SESION_ALUMNO } from '../src/pages/LoginPage.js';
import {
  contenidoEsperado,
  parDelQr,
  QR_Y4M,
  URL_ZXING_WASM,
} from './entorno.js';

/** El contenido que el vídeo contiene. Se resuelve una vez, y se imprime. */
const ESPERADO = contenidoEsperado();

/** El par que la API espera en el cuerpo del `POST /marcar`. */
const PAR = parDelQr(ESPERADO.texto);

/** Credenciales de alumno. No viven en el repositorio. */
const ALUMNO = process.env.E2E_ESTUDIANTE_EMAIL ?? '';
const CLAVE_ALUMNO = process.env.E2E_ESTUDIANTE_PASSWORD ?? '';
const SIN_CREDENCIALES = ALUMNO === '' || CLAVE_ALUMNO === '';

/** Lo que se mide en el puente, y se publica como anotación del informe. */
interface Sonda {
  /** ¿Este Chromium expone la API nativa de códigos de barras? */
  barcodeDetector: boolean;
  /** Cuántos dispositivos de vídeo ve la página (el sintético, al menos). */
  dispositivos: number;
  /** El tamaño real de los fotogramas que entrega la cámara falsa. */
  video: { ancho: number; alto: number };
  /** El texto que devolvió el lector, o `null`. */
  leido: string | null;
  /** Por dónde se leyó: `BarcodeDetector` o el respaldo `zxing-wasm`. */
  via: 'BarcodeDetector' | 'zxing-wasm' | 'ninguna';
  /** Todo lo que se descartó por el camino, para no tener que adivinarlo. */
  notas: string[];
}

/**
 * Enciende la cámara falsa y lee el QR de un fotograma real.
 *
 * **Replica la elección de lector del propio paquete, no la inventa.**
 * `mobile_scanner` web (`mobile_scanner_web.dart:464-485`) usa `BarcodeDetector`
 * «cuando está disponible (Chrome/Edge/Safari 17+)» y **cae a `zxing-wasm`» en
 * el resto». En escritorio Windows y Linux `BarcodeDetector` no existe, así que
 * lo que se ejerce aquí de verdad es el **respaldo** — que es el camino más
 * frágil (depende de una CDN) y el que menos se habría probado.
 *
 * Se hace en la página y no con una librería de Node a propósito: lo que hay que
 * medir es qué consigue **el navegador** con los flags puestos, no qué consigue
 * un proceso aparte.
 */
async function sondearPuente(page: Page): Promise<Sonda> {
  return page.evaluate(async (urlZxing: string): Promise<Sonda> => {
    const notas: string[] = [];

    const dispositivos = (await navigator.mediaDevices.enumerateDevices()).filter(
      (d) => d.kind === 'videoinput',
    ).length;

    const stream = await navigator.mediaDevices.getUserMedia({ video: true });
    const video = document.createElement('video');
    video.srcObject = stream;
    video.muted = true;
    video.playsInline = true;
    // Pequeño y visible: un vídeo oculto lo puede estrangular el navegador y
    // entonces no habría fotogramas que decodificar.
    video.width = 160;
    document.body.appendChild(video);
    await video.play();

    const limite = Date.now() + 10_000;
    while (video.videoWidth === 0 && Date.now() < limite) {
      await new Promise((seguir) => setTimeout(seguir, 100));
    }
    // Unos fotogramas de margen: el dispositivo sintético empieza a entregar
    // después del primer `play`, no en el mismo instante.
    for (let i = 0; i < 8; i += 1) {
      await new Promise((seguir) => requestAnimationFrame(() => seguir(null)));
    }

    const ancho = video.videoWidth;
    const alto = video.videoHeight;
    const lienzo = document.createElement('canvas');
    lienzo.width = ancho;
    lienzo.height = alto;
    const contexto = lienzo.getContext('2d', { willReadFrequently: true });
    if (contexto === null) throw new Error('No se pudo crear el contexto 2D del lienzo.');

    contexto.drawImage(video, 0, 0);
    const imagen = contexto.getImageData(0, 0, ancho, alto);

    const base = {
      barcodeDetector: typeof (globalThis as { BarcodeDetector?: unknown }).BarcodeDetector === 'function',
      dispositivos,
      video: { ancho, alto },
      notas,
    };

    // --- 1) El camino nativo, si este navegador lo tiene ----------------------
    if (base.barcodeDetector) {
      try {
        const Detector = (globalThis as unknown as {
          BarcodeDetector: new (o: { formats: string[] }) => { detect(i: ImageData): Promise<Array<{ rawValue: string }>> };
        }).BarcodeDetector;
        const detector = new Detector({ formats: ['qr_code'] });
        const hallados = await detector.detect(imagen);
        const primero = hallados.find((c) => c.rawValue !== '');
        if (primero !== undefined) {
          return { ...base, leido: primero.rawValue, via: 'BarcodeDetector' };
        }
        notas.push('BarcodeDetector está disponible pero no encontró ningún código.');
      } catch (error) {
        notas.push(`BarcodeDetector falló: ${String(error)}`);
      }
    } else {
      notas.push(
        'Este Chromium no expone BarcodeDetector — lo esperado en escritorio ' +
          'Windows/Linux. Se ejerce el respaldo, que es el camino real aquí.',
      );
    }

    // --- 2) El respaldo del paquete: zxing-wasm, desde SU MISMA URL -----------
    try {
      await new Promise<void>((seguir, romper) => {
        const etiqueta = document.createElement('script');
        etiqueta.src = urlZxing;
        etiqueta.onload = () => seguir();
        etiqueta.onerror = () => romper(new Error(`no se pudo cargar ${urlZxing}`));
        document.head.appendChild(etiqueta);
      });

      const modulo = (globalThis as unknown as {
        ZXingWASM?: { readBarcodes(i: ImageData, o: object): Promise<Array<{ text?: string }>> };
      }).ZXingWASM;
      if (modulo === undefined) {
        notas.push('El script cargó pero no expuso `window.ZXingWASM`.');
        return { ...base, leido: null, via: 'ninguna' };
      }

      const resultados = await modulo.readBarcodes(imagen, {
        formats: ['QRCode'],
        tryHarder: true,
        tryRotate: true,
        tryInvert: false,
      });
      const primero = resultados.find((r) => (r.text ?? '') !== '');
      if (primero !== undefined && primero.text !== undefined) {
        return { ...base, leido: primero.text, via: 'zxing-wasm' };
      }
      notas.push('zxing-wasm no encontró ningún código en el fotograma.');
    } catch (error) {
      notas.push(`zxing-wasm falló: ${String(error)}`);
    }

    return { ...base, leido: null, via: 'ninguna' };
  }, URL_ZXING_WASM);
}

/**
 * Pulsa un nodo semántico por su etiqueta, aunque no tenga texto visible.
 *
 * **Hace falta y no es un capricho.** `FlutterApp.pulsar` busca por texto
 * visible, y el botón del escáner es un `IconButton`: su única etiqueta es el
 * `tooltip` («Escanear el código QR de la pizarra»), que en el árbol semántico
 * llega como `aria-label` de un nodo **sin texto propio**. Un `hasText` no lo
 * encuentra y el fallo diría «no hay ningún widget con ese texto» sobre un botón
 * que sí está.
 *
 * Se puntúa cada candidato para no pulsar un envoltorio: los nodos contenedores
 * concatenan el texto de toda su descendencia, así que la raíz «contiene» el
 * tooltip sin ser el botón. Gana el que sea `role="button"` y `flt-tappable`.
 */
async function pulsarPorEtiqueta(app: FlutterApp, texto: string): Promise<void> {
  const indice = await app.page.evaluate((buscado: string) => {
    const nodos = [...document.querySelectorAll('flt-semantics')];
    let mejor = -1;
    let mejorPuntos = -1;

    for (let i = 0; i < nodos.length; i += 1) {
      const nodo = nodos[i];
      if (nodo === undefined) continue;

      const aria = nodo.getAttribute('aria-label') ?? '';
      const hijo = nodo.children[0];
      const propio =
        hijo instanceof HTMLElement && hijo.tagName === 'SPAN' ? (hijo.textContent ?? '') : '';
      if (!aria.includes(buscado) && !propio.includes(buscado)) continue;

      const rol = nodo.getAttribute('role') ?? '';
      const tappable = nodo.classList.contains('flt-tappable');
      const puntos = (rol === 'button' ? 4 : 0) + (tappable ? 2 : 0) + (aria.includes(buscado) ? 1 : 0);
      if (puntos > mejorPuntos) {
        mejorPuntos = puntos;
        mejor = i;
      }
    }
    return mejor;
  }, texto);

  if (indice < 0) {
    throw new Error(
      `No hay ningún nodo semántico que mencione «${texto}» —ni en su \`aria-label\` ni ` +
        `en su texto propio—. Árbol semántico:\n${await app.volcarSemantica()}`,
    );
  }

  await app.page.locator('flt-semantics').nth(indice).dispatchEvent('click');
}

test.describe('Puente de hardware del escáner de QR', () => {
  test.beforeAll(() => {
    if (!existsSync(QR_Y4M)) {
      throw new Error(
        `No existe el vídeo de la cámara falsa: ${QR_Y4M}\n` +
          'Genéralo con:\n' +
          `  node devops/generar-qr-y4m.mjs "${ESPERADO.texto}" "${QR_Y4M}"\n` +
          'Sin él, Chromium arranca con un dispositivo sintético que no entrega ' +
          'fotogramas y el fallo se leería como «el escáner no lee».',
      );
    }
    test
      .info()
      .annotations.push(
        { type: 'cámara falsa', description: QR_Y4M },
        { type: 'contenido esperado', description: `${ESPERADO.texto} (${ESPERADO.origen})` },
      );
  });

  test('1 · el puente: la cámara falsa entrega el vídeo y un lector lee el QR', async ({ page }) => {
    // Se abre la app de verdad para que el origen sea el que sirve el bundle y
    // para que la petición de abajo mida el bundle que CI acaba de compilar.
    await page.goto('/', { waitUntil: 'domcontentloaded' });

    // --- El bundle tiene que ser el fresco, no uno viejo ----------------------
    //
    // Esta comprobación existe porque el fallo que más costaría diagnosticar es
    // medir un bundle obsoleto: `build/web` local está congelado desde el
    // 2026-09-27 (aquí `flutter build web` no arranca), y un escáner que «no
    // funciona» sobre un bundle sin escáner es un falso negativo perfecto.
    const js = await (await page.request.get('/main.dart.js')).text();
    expect(js, 'El bundle servido no contiene el escáner: ¿es un build viejo?').toContain(
      'BarcodeDetector',
    );
    expect(js, 'El bundle servido no contiene el respaldo zxing.').toContain('zxing');

    await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60_000 });

    const sonda = await sondearPuente(page);

    // Se imprime **además** de anotarse, y no es duplicación: el reporter `list`
    // no muestra las anotaciones, y saber por qué camino se leyó —la API nativa
    // o el respaldo que baja de una CDN— es la mitad del dato que esta prueba
    // existe para dar. Sin esto habría que abrir el informe HTML para saberlo.
    console.log(
      `[puente] leído por ${sonda.via} · fotogramas ${sonda.video.ancho}×${sonda.video.alto} · ` +
        `BarcodeDetector ${sonda.barcodeDetector ? 'presente' : 'ausente'} · ` +
        `${sonda.dispositivos} dispositivo(s) de vídeo` +
        (sonda.notas.length > 0 ? `\n[puente] notas: ${sonda.notas.join(' | ')}` : ''),
    );

    // Se publica todo lo medido, no sólo el veredicto: cuando esto falle, el
    // informe tiene que decir por dónde se intentó y qué dijo el navegador.
    test.info().annotations.push(
      { type: 'lector usado', description: sonda.via },
      { type: 'BarcodeDetector', description: sonda.barcodeDetector ? 'presente' : 'ausente' },
      {
        type: 'fotogramas',
        description: `${sonda.video.ancho}×${sonda.video.alto}, ${sonda.dispositivos} dispositivo(s) de vídeo`,
      },
      ...(sonda.notas.length > 0 ? [{ type: 'notas', description: sonda.notas.join(' | ') }] : []),
    );

    expect(sonda.video.ancho, 'La cámara falsa no entregó fotogramas con tamaño.').toBeGreaterThan(0);
    expect(sonda.dispositivos, 'La página no ve ningún dispositivo de vídeo.').toBeGreaterThan(0);
    expect(
      sonda.leido,
      `Ningún lector recuperó el contenido del vídeo.\n${JSON.stringify(sonda, null, 2)}`,
    ).toBe(ESPERADO.texto);
  });

  test('2 · el recorrido: el botón del escáner lee el QR y la app manda el marcaje', async ({
    page,
  }) => {
    test.skip(
      SIN_CREDENCIALES,
      'Faltan E2E_ESTUDIANTE_EMAIL / E2E_ESTUDIANTE_PASSWORD. La segunda mitad del ' +
        'recorrido —pulsar el botón del escáner dentro de la app— exige una sesión de ' +
        'ALUMNO: el panel vive en `aspirante_dashboard.dart` y el administrador no lo ' +
        'tiene. No se crean cuentas ni se cambian contraseñas para rellenar el hueco.',
    );
    if (PAR === null) {
      throw new Error(`El contenido esperado no tiene forma «<uuid>:<6 dígitos>»: ${ESPERADO.texto}`);
    }

    // --- Se instrumenta `getUserMedia` ANTES de que cargue la app -------------
    //
    // Es la señal directa de que **el paquete arrancó la cámara**. Sin esto,
    // «el escáner se abrió» y «el escáner se abrió y encontró cámara» se ven
    // igual desde fuera, y esa diferencia es justo la que puede fallar en web.
    await page.addInitScript(() => {
      const registro = { llamadas: 0, restricciones: null as unknown };
      (globalThis as { __camara?: unknown }).__camara = registro;
      const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
      navigator.mediaDevices.getUserMedia = async (restricciones?: MediaStreamConstraints) => {
        registro.llamadas += 1;
        registro.restricciones = restricciones ?? null;
        return original(restricciones);
      };
    });

    const peticiones: string[] = [];
    page.on('request', (peticion) => {
      if (peticion.url().includes('/api/v1/asistencia/marcar')) {
        peticiones.push(peticion.postData() ?? '');
      }
    });

    const app = new FlutterApp(page);
    const login = new LoginPage(page);

    await login.abrir();
    await login.entrar(ALUMNO, CLAVE_ALUMNO, SENAL_DE_SESION_ALUMNO);

    // --- Autenticación → navegación ------------------------------------------
    await app.pulsar('Asistencia');
    await expect
      .poll(async () => await app.cuantos('Marca tu asistencia'), {
        message: 'Se pulsó «Asistencia» pero no apareció el panel del alumno.\n' + (await app.diagnostico()),
        timeout: 30_000,
      })
      .toBeGreaterThan(0);

    // --- El botón del escáner -------------------------------------------------
    await pulsarPorEtiqueta(app, 'Escanear el código QR de la pizarra');

    await expect
      .poll(async () => await app.cuantos('Escanear el código QR'), {
        message:
          'Se pulsó el botón del escáner pero no se abrió su pantalla.\n' + (await app.volcarSemantica()),
        timeout: 30_000,
      })
      .toBeGreaterThan(0);

    // --- El paquete inicializó la cámara --------------------------------------
    await expect
      .poll(
        async () => await page.evaluate(() => (globalThis as { __camara?: { llamadas: number } }).__camara?.llamadas ?? 0),
        {
          message:
            'La pantalla del escáner se abrió pero `mobile_scanner` no pidió la cámara: ' +
            'o el controlador no llegó a arrancar, o falló antes de `getUserMedia`.',
          timeout: 30_000,
        },
      )
      .toBeGreaterThan(0);

    // --- El QR inyectado se lee, y el panel manda el marcaje ------------------
    //
    // Ésta es la aserción que de verdad importa, y es la más fuerte de las dos:
    // el cuerpo de la petición sólo puede contener ese `sesionId` y esos seis
    // dígitos si el paquete **leyó el QR del vídeo**, `ParseQr` lo aceptó y el
    // panel eligió la rama del par completo. Ninguna otra cosa los produce.
    await expect
      .poll(() => peticiones.length, {
        message:
          'El escáner no produjo ningún `POST /api/v1/asistencia/marcar`. ' +
          `Contenido esperado: ${ESPERADO.texto}. Árbol semántico:\n` +
          (await app.volcarSemantica()),
        timeout: 90_000,
      })
      .toBeGreaterThan(0);

    const cuerpo = JSON.parse(peticiones[0] ?? '{}') as { sesionId?: string; codigo?: string };
    expect(cuerpo.sesionId, 'El marcaje no llevaba la sesión del QR leído.').toBe(PAR.sesionId);
    expect(cuerpo.codigo, 'El marcaje no llevaba los seis dígitos del QR leído.').toBe(PAR.codigo);
  });
});
