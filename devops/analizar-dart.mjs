#!/usr/bin/env node
// Verificador de TIPOS de Dart, local y sin `dart.exe`.
//
// ---------------------------------------------------------------------------
// POR QUE EXISTE
// ---------------------------------------------------------------------------
// En el equipo de desarrollo de este proyecto `dart analyze` y `flutter analyze`
// mueren SIEMPRE con:
//
//     CreateFile failed 231 (Todas las instancias de canalizacion estan en uso)
//     ProcessException: ... (at ../../runtime/bin/process_win.cc:744)
//     Command: ...\dartaotruntime.exe ...\snapshots\analysis_server_aot.dart.snapshot
//
// No es un fallo del analizador: es que `dart.exe` **no puede crear NINGUN proceso
// hijo**, porque construye la tuberia *nombrada* del hijo en `process_win.cc:744` y
// el espacio de nombres de tuberias de la maquina esta agotado. Medido: el mismo
// comando ejecutado FUERA del sandbox falla identico, asi que no es el sandbox y no
// se arregla escalando permisos ni limpiando `.dart_tool`.
//
// La clave para salir del paso: **el servidor de analisis no necesita ninguna tuberia
// nombrada**. Es un proceso normal que habla por stdin/stdout. Si se lanza
// *directamente* con `dartaotruntime.exe` —sin `dart.exe` de por medio— y alguien le
// habla su protocolo, funciona. Node si puede crear procesos aqui.
//
// Resultado medido en este proyecto: **un par de minutos como mucho, y sin
// diagnosticos de ningun nivel** (el mismo veredicto que el «No issues found!» de
// `flutter analyze`).
//
// Es el unico verificador de TIPOS que hay en local. Ojo con la diferencia, que costo
// un CI rojo: `dart format --output=none` comprueba **SINTAXIS, no tipos**, y un
// identificador inexistente lo atraviesa entero.
//
// ---------------------------------------------------------------------------
// LOS TRES NIVELES CUENTAN, Y ESTO COSTO UN CI ROJO
// ---------------------------------------------------------------------------
// `flutter analyze` **falla tambien por `info`**, no solo por errores y avisos. Este
// script afirmaba lo contrario en un comentario —«las infos no lo tumban»— y filtraba
// los `info` con un `if (nivel === 'INFO') continue;`. Resultado medido el 2026-09-30
// sobre el commit `aca179d`: local «sin errores ni avisos», `Flutter CI` **rojo** por
// dos lints `prefer_initializing_formals`. El comentario no era una imprecision: era
// una afirmacion falsa que se citaba a si misma como prueba.
//
// Un verificador que da verde mientras el CI da rojo es peor que no tenerlo, porque su
// verde se usa para decidir que ya se puede empujar. Ahora se cuentan los tres niveles.
//
// ---------------------------------------------------------------------------
// EL PROTOCOLO: `analyzer`, NO LSP, Y SIN CABECERAS Content-Length
// ---------------------------------------------------------------------------
// Esto es lo que hay que saber y no se adivina; las dos trampas se midieron:
//
//   1. `analysis_server --help` dice que el protocolo por defecto es **`analyzer`**
//      (el propio del servidor de Dart); `lsp` hay que pedirlo. Se probo LSP primero
//      y **no sirve para esto**: el servidor completa el `initialize`, analiza 41 s y
//      **no publica ni un diagnostico, ni vacio**, y el cliente se queda colgado para
//      siempre. No es un bug que haya que depurar: es el protocolo equivocado.
//
//   2. El protocolo `analyzer` **NO lleva cabeceras `Content-Length`**. Es **JSON
//      delimitado por saltos de linea**, un mensaje por linea. Mandarlo con el formato
//      de LSP hace que el servidor lea «Content-Length: 193» como si fuera un mensaje
//      y conteste `INVALID_REQUEST` con `id` vacio. Se descubrio leyendo su propio
//      `--protocol-traffic-log`, que registra los dos sentidos de la conversacion.
//
// Con eso, la conversacion es de peticion/respuesta y no hay que adivinar cuando
// termino nada: `analysis.setAnalysisRoots` una vez, y `analysis.getErrors` por
// archivo.
//
// ---------------------------------------------------------------------------
// USO
// ---------------------------------------------------------------------------
//     node devops/analizar-dart.mjs [raizDelProyecto] [archivo.dart ...]
//
// Sin archivos analiza todo `lib/**` y `test/**` de la raiz (por defecto, el
// directorio padre de este script). Codigo de salida 1 si hay diagnosticos de
// **cualquier** nivel —error, aviso o info—, 0 si esta limpio: exactamente el mismo
// liston que `flutter analyze`, que tambien falla por los tres.
//
// Opciones:
//   --help          esto
//   --sdk <ruta>    forzar la raiz del SDK de Flutter
//
// Variables de entorno:
//   FLUTTER_ROOT    raiz del SDK de Flutter (si no, se busca `flutter` en el PATH)
//   VERBOSO=1       muestra el stderr del servidor de analisis
//
// ---------------------------------------------------------------------------
// PROBADO POR MUTACION
// ---------------------------------------------------------------------------
// Un verificador que dice «limpio» a todo no vale nada. Este se estreno rompiendo
// algo a proposito: se reintrodujo un fallo real en un mutante temporal y lo cazo con
// su codigo (`undefined_identifier`, salida 1). Si algun dia se toca este script, hay
// que volver a hacer eso antes de confiar en el.

import { spawn } from 'node:child_process';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve, dirname, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Localizar el SDK de Flutter
// ---------------------------------------------------------------------------
// A proposito NO se lleva una ruta incrustada: un script de `devops/` que solo
// funciona en la maquina de quien lo escribio no es una herramienta, es una nota.

/// Ejecuta una orden y devuelve su stdout, o `null` si no se pudo.
///
/// **Con `spawn` asincrono, y NO con `spawnSync`, y esto esta medido:** en esta
/// maquina `spawnSync` falla con **`EBUSY`** —la misma familia de tuberias que tumba a
/// `dart.exe` con `ERROR_PIPE_BUSY`— mientras que `spawn` asincrono funciona sin
/// problema. Se comprobo con `where flutter`: `spawnSync` devuelve `status: null` y
/// `error.code: 'EBUSY'`; `spawn` devuelve codigo 0 y la ruta. Es el mismo motivo por
/// el que el servidor de analisis se lanza con `spawn`.
function ejecutar(cmd, args) {
  return new Promise((resolver) => {
    let salida = '';
    let p;
    try {
      p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'ignore'] });
    } catch {
      return resolver(null);
    }
    p.on('error', () => resolver(null));
    p.stdout.on('data', (d) => (salida += d));
    p.on('close', (c) => resolver(c === 0 ? salida : null));
  });
}

async function raizDelSdk(argumento) {
  const candidatas = [];
  if (argumento) candidatas.push(argumento);
  if (process.env.FLUTTER_ROOT) candidatas.push(process.env.FLUTTER_ROOT);

  if (candidatas.length === 0) {
    // `where` en Windows, `which` en el resto. Devuelve la ruta al ejecutable
    // `flutter`, que vive en `<sdk>/bin/flutter` (o `flutter.bat`): la raiz del SDK
    // es **un** nivel por encima de `bin`. Ojo: con dos `..` se sale del SDK y el
    // descubrimiento falla en silencio — medido.
    const buscador = process.platform === 'win32' ? 'where' : 'which';
    const salida = await ejecutar(buscador, ['flutter']);
    if (salida) {
      const primera = salida.split(/\r?\n/).map((s) => s.trim()).filter(Boolean)[0];
      if (primera) candidatas.push(resolve(dirname(primera), '..'));
    }
  }

  for (const c of candidatas) {
    const sdk = resolve(c);
    if (existsSync(join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', 'dartaotruntime.exe'))) {
      return sdk;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Argumentos
// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
if (argv.includes('--help') || argv.includes('-h')) {
  const texto = readFileSync(fileURLToPath(import.meta.url), 'utf8');
  const inicio = texto.indexOf('// USO');
  const fin = texto.indexOf('// PROBADO POR MUTACION');
  console.log(
    texto
      .slice(inicio, fin)
      .split('\n')
      .map((l) => l.replace(/^\/\/ ?/, ''))
      .join('\n'),
  );
  process.exit(0);
}

let raizSdkArg = null;
const posicionales = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--sdk') raizSdkArg = argv[++i];
  else posicionales.push(argv[i]);
}

const sdk = await raizDelSdk(raizSdkArg);
if (!sdk) {
  console.error(
    'No se encontro el SDK de Flutter.\n' +
      '  Define FLUTTER_ROOT, pasa --sdk <ruta>, o pon `flutter` en el PATH.',
  );
  process.exit(64);
}

const DARTAOT = join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', 'dartaotruntime.exe');
const SNAPSHOT = join(
  sdk,
  'bin',
  'cache',
  'dart-sdk',
  'bin',
  'snapshots',
  'analysis_server_aot.dart.snapshot',
);

const [raizArg, ...archivosArg] = posicionales;
const raiz = resolve(raizArg ?? join(AQUI, '..'));

// ---------------------------------------------------------------------------
// Que analizar
// ---------------------------------------------------------------------------
function recolectar(dir, acc = []) {
  let entradas;
  try {
    entradas = readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entradas) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === '.dart_tool' || e.name === 'build') continue;
      recolectar(p, acc);
    } else if (e.name.endsWith('.dart')) {
      acc.push(p);
    }
  }
  return acc;
}

const archivos = archivosArg.length
  ? archivosArg.map((a) => resolve(a))
  : [...recolectar(join(raiz, 'lib')), ...recolectar(join(raiz, 'test'))];

if (archivos.length === 0) {
  console.error(`No hay archivos .dart que analizar en ${raiz}.`);
  process.exit(64);
}

// ---------------------------------------------------------------------------
// Lanzar el servidor de analisis DIRECTO, sin `dart.exe`
// ---------------------------------------------------------------------------
const servidor = spawn(
  DARTAOT,
  [
    SNAPSHOT,
    '--client-id=verificador-local',
    // `--protocol=analyzer` es el valor por defecto; se escribe igual para que quede
    // claro que es una eleccion medida y no un olvido. Ver la cabecera del archivo.
    '--protocol=analyzer',
    ...(process.env.LOG_PROTOCOLO
      ? [`--protocol-traffic-log=${process.env.LOG_PROTOCOLO}`]
      : []),
    '--sdk',
    join(sdk, 'bin', 'cache', 'dart-sdk'),
  ],
  { stdio: ['pipe', 'pipe', 'pipe'] },
);

servidor.on('error', (e) => {
  console.error('No se pudo lanzar el servidor de analisis:', e.message);
  process.exit(70);
});
servidor.stderr.on('data', (d) => {
  const t = d.toString().trim();
  if (t && process.env.VERBOSO) console.error('[servidor]', t);
});

// ---------------------------------------------------------------------------
// Transporte: JSON por saltos de linea (NO Content-Length)
// ---------------------------------------------------------------------------
function enviar(msg) {
  servidor.stdin.write(`${JSON.stringify(msg)}\n`);
}

let buffer = '';
const pendientes = new Map();
let siguienteId = 1;

function pedir(method, params) {
  const id = String(siguienteId++);
  return new Promise((resolver, rechazar) => {
    pendientes.set(id, { resolver, rechazar });
    enviar({ id, method, params });
  });
}

servidor.stdout.on('data', (trozo) => {
  buffer += trozo.toString('utf8');
  for (;;) {
    const salto = buffer.indexOf('\n');
    if (salto === -1) return;
    const linea = buffer.slice(0, salto).trim();
    buffer = buffer.slice(salto + 1);
    if (!linea) continue;

    let msg;
    try {
      msg = JSON.parse(linea);
    } catch {
      continue; // mensaje ilegible: se ignora
    }

    // Peticion DEL servidor AL cliente: hay que contestar o se queda colgado.
    if (msg.id !== undefined && msg.method) {
      enviar({ id: msg.id, result: null });
      continue;
    }
    if (msg.id !== undefined && pendientes.has(String(msg.id))) {
      const { resolver, rechazar } = pendientes.get(String(msg.id));
      pendientes.delete(String(msg.id));
      if (msg.error) rechazar(new Error(JSON.stringify(msg.error)));
      else resolver(msg.result);
    }
  }
});

// ---------------------------------------------------------------------------
// Analizar
// ---------------------------------------------------------------------------
async function principal() {
  // 1) Fijar la raiz de analisis. A partir de aqui el servidor encuentra el
  //    `.dart_tool/package_config.json` y resuelve `package:flutter/...` igual que CI.
  await pedir('analysis.setAnalysisRoots', {
    included: [raiz],
    excluded: [],
    packageRoots: null,
  });

  // 2) Preguntar archivo por archivo: es de peticion/respuesta, asi que no hay que
  //    adivinar cuando termino el analisis.
  const filas = [];
  let errores = 0;
  let avisos = 0;
  let infos = 0;
  const orden = { ERROR: 'error', WARNING: 'aviso', INFO: 'info' };

  for (const a of archivos) {
    let res;
    try {
      res = await pedir('analysis.getErrors', { file: a });
    } catch (e) {
      console.error(`No se pudo analizar ${a}: ${e.message}`);
      continue;
    }
    for (const d of res?.errors ?? []) {
      const nivel = d.severity;
      // **Los tres niveles cuentan.** `flutter analyze` falla tambien por `info`, y
      // aqui habia un `if (nivel === 'INFO') continue;` que los tiraba: el script
      // decia «sin errores ni avisos» y el CI caia igual. Ver la cabecera.
      const loc = d.location ?? {};
      filas.push(
        `${orden[nivel] ?? nivel} ${relative(raiz, loc.file ?? a)}:` +
          `${(loc.startLine ?? 0) + 1}:${(loc.startColumn ?? 0) + 1} ` +
          `${d.message}` +
          (d.code ? ` [${d.code}]` : ''),
      );
      if (nivel === 'ERROR') errores++;
      else if (nivel === 'WARNING') avisos++;
      else infos++;
    }
  }

  filas.sort();
  for (const f of filas) console.log(f);
  console.log('');
  console.log(
    `Archivos analizados: ${archivos.length} · ` +
      (errores === 0 && avisos === 0 && infos === 0
        ? 'sin errores, avisos ni infos. (equivalente a «No issues found!»)'
        : `${errores} error(es), ${avisos} aviso(s), ${infos} info(s).`),
  );

  try {
    servidor.stdin.end();
  } catch {
    /* ya cerrado */
  }
  servidor.kill();
  // **Los tres niveles**, y no `errores > 0 || avisos > 0`: con ese liston, un
  // arbol con solo lints de nivel `info` salia por la puerta con codigo 0 mientras
  // `flutter analyze` lo tumbaba. El codigo de salida es lo que lee la
  // automatizacion, asi que dejarlo corto era justo el fallo que este archivo
  // documenta arriba.
  process.exit(errores > 0 || avisos > 0 || infos > 0 ? 1 : 0);
}

principal().catch((e) => {
  console.error('Fallo el verificador:', e.message);
  servidor.kill();
  process.exit(70);
});

// Tope de seguridad: si el servidor no contesta, no se queda colgado para siempre.
setTimeout(() => {
  console.error('Tiempo agotado esperando al servidor de analisis.');
  servidor.kill();
  process.exit(70);
}, 300000).unref();
