#!/usr/bin/env node
/**
 * limpiar-marca.mjs — borra LA marca de asistencia que dejó una prueba.
 *
 * POR QUÉ EXISTE
 * --------------
 * El recorrido del puente de hardware (`escaner_qr_hardware.spec.ts`) **escribe
 * de verdad**: marca asistencia contra la nube real, porque una marca simulada
 * no probaría ni la RLS ni el `unique`. Escribir sin poder deshacer sería dejar
 * basura en la base cada vez que alguien corre la prueba, así que la prueba y su
 * limpieza van juntas.
 *
 * QUÉ TOCA Y QUÉ NO
 * -----------------
 * Toca **una sola tabla**: `attendance_marks`. Y dentro de ella, sólo las filas
 * que casan con la sesión y el código que se le pasan.
 *
 * **No toca `attendance_sessions` en absoluto.** No es una precaución de estilo:
 * hay **7 sesiones en estado `OPEN`** de una tanda del 2026-09-26 que son un
 * residuo previo, y borrarlas o cerrarlas alteraría el estado que la prueba
 * quiere medir. El script ni siquiera abre esa tabla, y si alguien le pasa
 * `--sesion` con la intención de cerrarla, no hay ninguna opción que lo haga.
 *
 * POR QUÉ CON LA CLAVE DE SERVICIO
 * --------------------------------
 * **Medido**: `attendance_marks` tiene dos políticas RLS —`SELECT` para el
 * docente e `INSERT` para el estudiante— y **ninguna de `DELETE`**. O sea que ni
 * el alumno ni el docente pueden borrar una marca, ni siquiera la suya: es una
 * tabla de sólo-añadir por diseño. La limpieza, por tanto, no puede fingir que
 * es un usuario; va por la clave de servicio, que es lo que hace el
 * administrador cuando de verdad hay que corregir algo.
 *
 * Uso:
 *   node e2e/hardware/limpiar-marca.mjs --sesion <uuid> --codigo <6 dígitos> [--alumno <uuid>]
 *   node e2e/hardware/limpiar-marca.mjs --sesion <uuid> --codigo <6 dígitos> --confirmar
 *
 * Sin `--confirmar` **no borra nada**: lista lo que borraría. Borrar es la
 * excepción, así que pedirlo tiene que ser un acto deliberado.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const RAIZ = resolve(import.meta.dirname, '..', '..');

/** Lee una variable de `backend/.env` sin imprimir su valor. */
function delEntorno(nombre) {
  const ruta = resolve(RAIZ, 'backend', '.env');
  let contenido;
  try {
    contenido = readFileSync(ruta, 'utf8');
  } catch {
    throw new Error(`No puedo leer ${ruta}. La clave de servicio vive ahí.`);
  }
  const linea = contenido.split(/\r?\n/).find((l) => l.startsWith(`${nombre}=`));
  if (linea === undefined) throw new Error(`${ruta} no define ${nombre}.`);
  return linea.slice(nombre.length + 1).trim().replace(/^["']|["']$/g, '');
}

function analizar(argv) {
  const opciones = { sesion: '', codigo: '', alumno: '', confirmar: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--confirmar') { opciones.confirmar = true; continue; }
    if (a === '--sesion') { opciones.sesion = String(argv[++i] ?? ''); continue; }
    if (a === '--codigo') { opciones.codigo = String(argv[++i] ?? ''); continue; }
    if (a === '--alumno') { opciones.alumno = String(argv[++i] ?? ''); continue; }
    throw new Error(`Opción desconocida: ${a}`);
  }
  return opciones;
}

const opciones = analizar(process.argv.slice(2));

if (opciones.sesion === '' || opciones.codigo === '') {
  console.error(
    'Uso: node e2e/hardware/limpiar-marca.mjs --sesion <uuid> --codigo <6 dígitos> [--alumno <uuid>] [--confirmar]\n' +
      '\n' +
      'Sin --confirmar sólo lista lo que borraría.\n' +
      'Toca ÚNICAMENTE attendance_marks. NO toca attendance_sessions: hay 7 sesiones\n' +
      'OPEN de un residuo previo (2026-09-26) que no se deben alterar.',
  );
  process.exit(1);
}
if (!/^[0-9]{6}$/.test(opciones.codigo)) {
  throw new Error(`--codigo tiene que ser seis dígitos (recibido «${opciones.codigo}»).`);
}

const URL_BASE = delEntorno('SUPABASE_URL').replace(/\/$/, '');
const CLAVE = delEntorno('SUPABASE_SERVICE_ROLE_KEY');

const cabeceras = {
  apikey: CLAVE,
  Authorization: `Bearer ${CLAVE}`,
  'Content-Type': 'application/json',
};

/** Filtro PostgREST: sesión + código, y el alumno si se pidió acotar. */
const filtro = [
  `session_id=eq.${encodeURIComponent(opciones.sesion)}`,
  `code=eq.${encodeURIComponent(opciones.codigo)}`,
  ...(opciones.alumno !== '' ? [`student_id=eq.${encodeURIComponent(opciones.alumno)}`] : []),
].join('&');

async function peticion(metodo, consulta, extra = {}) {
  const respuesta = await fetch(`${URL_BASE}/rest/v1/attendance_marks?${consulta}`, {
    method: metodo,
    headers: { ...cabeceras, ...extra },
  });
  const texto = await respuesta.text();
  if (!respuesta.ok) throw new Error(`${metodo} ${respuesta.status}: ${texto}`);
  return texto === '' ? [] : JSON.parse(texto);
}

const candidatas = await peticion(
  'GET',
  `select=id,student_id,code,marked_at&${filtro}&order=marked_at.asc`,
);

console.log(`Sesión   : ${opciones.sesion}`);
console.log(`Código   : ${opciones.codigo}${opciones.alumno !== '' ? `\nAlumno   : ${opciones.alumno}` : ''}`);
console.log(`Candidatas: ${candidatas.length}`);

for (const fila of candidatas) {
  console.log(`  · ${fila.id}  alumno=${fila.student_id}  marcada=${fila.marked_at}`);
}

if (candidatas.length === 0) {
  console.log('\nNo hay nada que limpiar. (Si la prueba falló antes de marcar, esto es lo esperado.)');
  process.exit(0);
}

if (!opciones.confirmar) {
  console.log('\nMODO SEGURO: no se ha borrado nada. Añade --confirmar para borrar estas filas.');
  process.exit(0);
}

// `return=representation` para que la respuesta diga exactamente qué se borró,
// en vez de un 204 que obliga a creérselo.
const borradas = await peticion('DELETE', filtro, { Prefer: 'return=representation' });

console.log(`\nBorradas: ${borradas.length}`);
for (const fila of borradas) console.log(`  · ${fila.id}  alumno=${fila.student_id}`);
console.log('\nattendance_sessions NO se ha tocado: las 7 OPEN del residuo previo siguen igual.');
