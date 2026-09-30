#!/usr/bin/env node
/**
 * generar-qr-y4m.mjs — convierte un texto en un vídeo Y4M que contiene su QR.
 *
 * POR QUÉ EXISTE
 * --------------
 * Para probar el escáner del LMS contra una cámara hace falta que esa cámara
 * «vea» un código QR. Chromium sabe sustituir la cámara por un fichero de vídeo
 * (`--use-file-for-fake-video-capture`), así que la pieza que falta es fabricar
 * ese fichero de forma reproducible. Esto es esa pieza.
 *
 * POR QUÉ Y4M Y NO UN PNG
 * -----------------------
 * Y4M es vídeo **sin comprimir**: una cabecera de texto y luego los planos Y, U
 * y V en crudo. Un QR es blanco y negro puro, así que no hace falta ningún
 * codificador de imagen ni `ffmpeg`: se calcula la matriz de módulos y se
 * escriben los planos a mano. Cero dependencias de binarios externos — lo que
 * importa, porque esto tiene que poder correr también en un runner de CI.
 *
 * POR QUÉ SE AUTOVERIFICA
 * -----------------------
 * Un vídeo que «se generó bien» pero que ningún lector puede decodificar no
 * sirve para nada, y el fallo aparecería más tarde y disfrazado (como «el
 * escáner no lee», que es justo lo que se quería medir). Así que el script
 * rasteriza, **vuelve a decodificar su propia rejilla con un lector
 * independiente** y aborta si el texto no coincide. Un generador que no se
 * comprueba a sí mismo es una promesa, no una herramienta.
 *
 * Uso:
 *   node devops/generar-qr-y4m.mjs "<texto del QR>" [salida.y4m] [opciones]
 *
 * Opciones:
 *   --lado N      ancho en píxeles            (por defecto 640)
 *   --alto N      alto en píxeles             (por defecto 480)
 *   --fps N       fotogramas por segundo      (por defecto 10)
 *   --segundos N  duración en segundos        (por defecto 1)
 *   --ec L|M|Q|H  corrección de errores       (por defecto M)
 *   --margen N    zona de silencio, en módulos (por defecto 4)
 *   --ayuda       esto mismo
 *
 * Los dos paquetes que necesita viven en el espacio de trabajo gestionado de
 * Node y se resuelven solos; si faltan, el error dice el comando exacto.
 */

import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { resolve } from 'node:path';

const require = createRequire(import.meta.url);

/** Espacio de trabajo gestionado: donde viven `qrcode-generator` y `jsqr`. */
const ESPACIO = resolve(homedir(), '.workbuddy-ai', 'binaries', 'node', 'workspace', 'node_modules');

//  Luma en rango de vídeo (16–235), que es lo que espera un lector YUV→RGB.
//  Usar 0/255 «porque es más contraste» daría un negro por debajo del rango y
//  algunos decodificadores recortan: se pierde justo el contraste que se quería.
const CLARO = 235;
const OSCURO = 16;
const CROMA_NEUTRA = 128;

/**
 * Resuelve un paquete del espacio de trabajo gestionado.
 *
 * Se intentan tres formas y no una porque el nombre y la ruta no coinciden: un
 * paquete se resuelve por su directorio (y entonces manda su `main`), pero si el
 * `main` está mal declarado hay que ir al archivo. Antes de fallar se dice el
 * comando que lo arregla, en vez de un `MODULE_NOT_FOUND` a secas.
 */
function cargar(nombre, archivo) {
  const intentos = [nombre, resolve(ESPACIO, nombre)];
  if (archivo) intentos.push(resolve(ESPACIO, nombre, archivo));
  for (const intento of intentos) {
    try {
      return require(intento);
    } catch (error) {
      if (error.code !== 'MODULE_NOT_FOUND') throw error;
    }
  }
  throw new Error(
    `No encuentro el paquete «${nombre}».\n` +
      `  Instálalo con:  cd "${ESPACIO}" && npm install ${nombre}\n` +
      `  O define el espacio con la variable de entorno NODE_PATH.`,
  );
}

/** Los módulos de un QR son cuadrados; esto los pinta como bloques de luma. */
function rasterizar(qr, { lado, alto, margen }) {
  const n = qr.getModuleCount();
  const total = n + margen * 2;
  const escala = Math.floor(Math.min(lado, alto) / total);
  if (escala < 2) {
    throw new Error(
      `Lienzo demasiado pequeño: ${lado}×${alto} no da para ${total} módulos ` +
        `(saldría a ${escala} px por módulo). Sube --lado/--alto o baja --ec.`,
    );
  }
  const ladoQr = total * escala;
  const x0 = Math.floor((lado - ladoQr) / 2);
  const y0 = Math.floor((alto - ladoQr) / 2);

  const Y = Buffer.alloc(lado * alto, CLARO);
  for (let fila = 0; fila < n; fila += 1) {
    for (let col = 0; col < n; col += 1) {
      if (!qr.isDark(fila, col)) continue;
      const py = y0 + (fila + margen) * escala;
      const px = x0 + (col + margen) * escala;
      for (let dy = 0; dy < escala; dy += 1) {
        const inicio = (py + dy) * lado + px;
        Y.fill(OSCURO, inicio, inicio + escala);
      }
    }
  }
  return { Y, escala, ladoQr, modulos: n };
}

/** Y4M: cabecera + N veces (`FRAME\n` + Y + U + V). */
function envolverY4m(Y, { lado, alto, fps, segundos }) {
  const croma = (lado >> 1) * (alto >> 1);
  const marco = Buffer.concat([Y, Buffer.alloc(croma, CROMA_NEUTRA), Buffer.alloc(croma, CROMA_NEUTRA)]);
  const etiqueta = Buffer.from('FRAME\n');
  const fotogramas = [];
  for (let i = 0; i < fps * segundos; i += 1) fotogramas.push(etiqueta, marco);

  const cabecera =
    `YUV4MPEG2 W${lado} H${alto} F${fps}:1 Ip A1:1 C420mpeg2\n`;
  return { bytes: Buffer.concat([Buffer.from(cabecera), ...fotogramas]), fotogramas: fps * segundos };
}

/**
 * Convierte el plano Y a RGBA para que un decodificador independiente lo lea.
 *
 * Esto es lo que convierte el script en una comprobación: no se afirma que el
 * vídeo «está bien» porque se escribió sin errores, sino porque **otro lector
 * recupera el texto exacto** de los píxeles que se van a enviar.
 */
function aRgba(Y, lado, alto) {
  const rgba = new Uint8ClampedArray(lado * alto * 4);
  for (let i = 0; i < lado * alto; i += 1) {
    const escala = Math.max(0, Math.min(255, Math.round(((Y[i] - 16) * 255) / 219)));
    rgba[i * 4] = escala;
    rgba[i * 4 + 1] = escala;
    rgba[i * 4 + 2] = escala;
    rgba[i * 4 + 3] = 255;
  }
  return rgba;
}

function analizarArgumentos(argv) {
  const opciones = { lado: 640, alto: 480, fps: 10, segundos: 1, ec: 'M', margen: 4, ayuda: false };
  const libres = [];
  const num = ['lado', 'alto', 'fps', 'segundos', 'margen'];
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--ayuda' || a === '-h') { opciones.ayuda = true; continue; }
    if (a === '--ec') { opciones.ec = String(argv[++i]).toUpperCase(); continue; }
    if (a.startsWith('--') && num.includes(a.slice(2))) { opciones[a.slice(2)] = Number(argv[++i]); continue; }
    if (a.startsWith('--')) throw new Error(`Opción desconocida: ${a}`);
    libres.push(a);
  }
  return { opciones, libres };
}

const { opciones, libres } = analizarArgumentos(process.argv.slice(2));

if (opciones.ayuda || libres.length === 0) {
  const uso = [
    'Uso: node devops/generar-qr-y4m.mjs "<texto>" [salida.y4m] [--lado 640] [--alto 480]',
    '                                   [--fps 10] [--segundos 1] [--ec M] [--margen 4]',
    '',
    'Ejemplo (el QR del aula: uuid de la sesión + seis dígitos):',
    '  node devops/generar-qr-y4m.mjs "3f2a...:471212" C:/tmp/qr_dummy.y4m',
  ].join('\n');
  console.log(uso);
  process.exit(libres.length === 0 && !opciones.ayuda ? 1 : 0);
}

const texto = libres[0];
const salida = libres[1] ?? 'qr_dummy.y4m';

if (!['L', 'M', 'Q', 'H'].includes(opciones.ec)) {
  throw new Error(`--ec debe ser L, M, Q o H (recibido «${opciones.ec}»).`);
}
if (opciones.lado % 2 !== 0 || opciones.alto % 2 !== 0) {
  throw new Error('--lado y --alto tienen que ser pares: el plano de croma del YUV420 mide la mitad exacta.');
}
if (opciones.lado < 2 || opciones.alto < 2 || opciones.fps < 1 || opciones.segundos < 1) {
  throw new Error('--lado/--alto ≥ 2 y --fps/--segundos ≥ 1.');
}

const qrcode = cargar('qrcode-generator', 'dist/qrcode.js');
const jsQR = (() => {
  const mod = cargar('jsqr');
  return typeof mod === 'function' ? mod : mod.default;
})();

//  `0` como versión deja que el codificador elija la más pequeña que quepa: así
//  el QR usa el mínimo de módulos y, con la escala fija, cada módulo sale más
//  grande — que es lo que hace que un lector lo vea de lejos.
const qr = qrcode(0, opciones.ec);
qr.addData(texto);
qr.make();

const { Y, escala, ladoQr, modulos } = rasterizar(qr, opciones);
const { bytes, fotogramas } = envolverY4m(Y, opciones);

// --- Autocomprobación: el vídeo tiene que ser legible de vuelta ---------------
const leido = jsQR(aRgba(Y, opciones.lado, opciones.alto), opciones.lado, opciones.alto);
if (!leido) {
  throw new Error(
    'El vídeo generado NO es decodificable por el lector de comprobación. ' +
      'Suele ser margen insuficiente (--margen) o una escala demasiado baja.',
  );
}
if (leido.data !== texto) {
  throw new Error(`El lector devolvió otro texto.\n  esperado: ${texto}\n  leído   : ${leido.data}`);
}

writeFileSync(salida, bytes);

//  Un «sidecar» con el contenido, al lado del vídeo.
//
//  Existe para que el runner que consume este archivo **no pueda
//  desincronizarse**: si alguien regenera el vídeo con otro texto y el runner
//  siguiera esperando el viejo, el fallo se leería como «el escáner no lee» —
//  que es exactamente el fallo que este puente existe para medir. Con el
//  sidecar, la verdad del contenido viaja pegada al archivo que la contiene.
writeFileSync(
  `${salida}.json`,
  `${JSON.stringify(
    {
      texto,
      lado: opciones.lado,
      alto: opciones.alto,
      fps: opciones.fps,
      segundos: opciones.segundos,
      ec: opciones.ec,
      margen: opciones.margen,
      modulos,
      escala,
      generadoPor: 'devops/generar-qr-y4m.mjs',
    },
    null,
    2,
  )}\n`,
);

console.log(`QR      : ${modulos} módulos (${escala} px/módulo, ${ladoQr} px de lado)`);
console.log(`Vídeo   : ${opciones.lado}×${opciones.alto} · ${opciones.fps} fps · ${fotogramas} fotogramas`);
console.log(`Archivo : ${salida} (${(bytes.length / 1024 / 1024).toFixed(1)} MB)`);
console.log(`Sidecar : ${salida}.json (el contenido, para que el runner no lo adivine)`);
console.log(`Comprobado: un lector independiente recupera «${texto}» de los píxeles generados.`);
