// Aserciones de bytes sobre el archivo que HACER recibe.
//
// **Por qué se comprueban BYTES y no cadenas.** Las reglas del sistema receptor
// son de codificación y de fin de línea, y las dos son invisibles desde una
// cadena ya decodificada: `utf8.decode` se come el BOM, y un `\r\n` normalizado
// por el editor o por el sistema se ve igual que un `\n`. Un test que afirme
// sobre `texto.includes('inscripcion_id')` pasa aunque falte el BOM. Por eso
// todo lo que sigue trabaja sobre el `Buffer` crudo.
//
// Las reglas están implementadas en `lib/models/exportacion_hacer.dart`
// (`csvDeExportacionHacer`, `_formatearCelda`, `FilaExportacionHacer
// .documentoIdentidad`) y este archivo NO las reimplementa: sólo las comprueba.
// Es a propósito — una regla escrita dos veces se desvía, y aquí el que manda
// es el Dart.

import { pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';

/** Separador de campos que exige HACER. Espeja `separadorHacer` en Dart. */
export const SEPARADOR_HACER = ';';

/** Fin de línea que exige HACER. Espeja `_finDeLinea` en Dart. */
export const FIN_DE_LINEA = '\r\n';

/** Marca de orden de bytes UTF-8, tal cual: `EF BB BF`. */
export const BOM_UTF8: readonly number[] = [0xef, 0xbb, 0xbf];

/**
 * Las 62 columnas del archivo, **en orden**.
 *
 * Espeja `columnasExportacionHacer` de `lib/models/exportacion_hacer.dart`: las
 * 61 que declara `public.v_exportacion_hacer` más `documento_identidad`, que no
 * viene de la vista sino que se deriva en el cliente.
 *
 * Si esta lista y la de Dart se separan, el E2E lo dice — y ésa es una de las
 * cosas para las que existe: la especificación de campos de HACER sigue abierta
 * (D17), así que el orden puede cambiar, y un cambio que no se refleje aquí
 * tiene que doler en CI y no en la importación del INCES.
 */
export const COLUMNAS_HACER: readonly string[] = [
  // Contexto académico.
  'inscripcion_id',
  'seccion_id',
  'lapso',
  'seccion',
  'seccion_activa',
  'programa_id',
  'programa_codigo',
  'programa_nombre',
  'materia_id',
  'materia_codigo',
  'materia_nombre',
  'docente',
  'estado',
  'inscrito_en',
  // Identidad.
  'aspirante_id',
  'cedula',
  'documento_identidad',
  'nombres',
  'apellidos',
  'fecha_nac',
  'sexo',
  'telefono',
  'email',
  'direccion',
  'nivel_educativo',
  'discapacidad',
  'tipo_discapacidad',
  'numero_identidad_tutor',
  'nombre_tutor',
  'parentesco_tutor',
  'telefono_tutor',
  'correo_tutor',
  // Planilla aplanada.
  'planilla_numero_preimpreso',
  'planilla_primer_nombre',
  'planilla_segundo_nombre',
  'planilla_primer_apellido',
  'planilla_segundo_apellido',
  'planilla_nacionalidad',
  'planilla_estado_civil',
  'planilla_pueblo_indigena',
  'planilla_pueblo_indigena_cual',
  'planilla_deporte',
  'planilla_deporte_desde',
  'planilla_actividad_cultural',
  'planilla_actividad_cultural_desde',
  'planilla_organizacion_social',
  'planilla_organizacion_social_desde',
  'planilla_estado',
  'planilla_municipio',
  'planilla_parroquia',
  'planilla_comunidad',
  'planilla_telefono_fijo',
  'planilla_twitter',
  'planilla_facebook',
  'planilla_familiares',
  'planilla_misiones',
  'planilla_nivel_avance',
  'planilla_ultimo_anio',
  'planilla_especialidad',
  'planilla_otras_formaciones',
  'planilla_experiencias',
  // La red de seguridad: el jsonb crudo, sin aplanar.
  'datos_planilla',
];

/**
 * Las columnas que el serializador NO pasa a mayúsculas.
 *
 * Espeja `columnasSinMayusculas`. Son las de tipo no textual: 5 `uuid`,
 * 1 `jsonb`, 2 `boolean`, 1 `timestamptz` y 1 `date`. Mayusculizar un uuid o un
 * `jsonb` no es cosmético: los invalida.
 */
export const COLUMNAS_SIN_MAYUSCULAS: ReadonlySet<string> = new Set([
  'inscripcion_id',
  'seccion_id',
  'programa_id',
  'materia_id',
  'aspirante_id',
  'datos_planilla',
  'seccion_activa',
  'discapacidad',
  'inscrito_en',
  'fecha_nac',
]);

/** Forma de un uuid, en cualquier caja: PostgreSQL lo emite en minúsculas. */
const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/** Forma de un `date` de PostgreSQL: `AAAA-MM-DD`. */
const FECHA = /^\d{4}-\d{2}-\d{2}$/;

/** Forma de un `timestamptz` serializado: ISO 8601 con zona. */
const MARCA_DE_TIEMPO = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}:?\d{2}|Z)?$/;

export interface InformeArchivoHacer {
  bytes: number;
  tieneBom: boolean;
  /** `true` si TODOS los finales de línea son CRLF. */
  soloCrlf: boolean;
  /** Cuántos `\n` van precedidos de algo distinto de `\r`. */
  lfSueltos: number;
  cabecera: string[];
  filas: string[][];
  /** Anchos distintos de la cabecera, por fila (para localizar la que rompe). */
  anchosAnomalos: Array<{ fila: number; columnas: number }>;
  problemas: string[];
}

/**
 * Parte un CSV con separador `;`, comillas dobles y CRLF.
 *
 * Es un analizador de verdad y no un `split(';')` porque una celda puede llevar
 * el separador dentro entre comillas — una dirección con `;` es un caso real, y
 * el serializador la entrecomilla justo por eso. Partir por `;` a lo bruto daría
 * una fila más ancha que la cabecera y un fallo que señalaría al sitio
 * equivocado.
 */
export function analizarCsv(texto: string): string[][] {
  const filas: string[][] = [];
  let fila: string[] = [];
  let celda = '';
  let entreComillas = false;

  for (let i = 0; i < texto.length; i += 1) {
    const c = texto[i]!;

    if (entreComillas) {
      if (c === '"') {
        if (texto[i + 1] === '"') {
          celda += '"';
          i += 1;
        } else {
          entreComillas = false;
        }
      } else {
        celda += c;
      }
      continue;
    }

    if (c === '"') {
      entreComillas = true;
    } else if (c === SEPARADOR_HACER) {
      fila.push(celda);
      celda = '';
    } else if (c === '\r' && texto[i + 1] === '\n') {
      fila.push(celda);
      filas.push(fila);
      fila = [];
      celda = '';
      i += 1;
    } else if (c === '\n') {
      // Un LF suelto no es un fin de registro válido: se anota y se sigue, para
      // que el informe lo diga en vez de producir filas fantasma.
      fila.push(celda);
      filas.push(fila);
      fila = [];
      celda = '';
    } else {
      celda += c;
    }
  }

  if (celda.length > 0 || fila.length > 0) {
    fila.push(celda);
    filas.push(fila);
  }

  return filas;
}

/** Analiza los bytes descargados y devuelve un informe con TODOS los hallazgos. */
export function analizarArchivoHacer(bytes: Buffer): InformeArchivoHacer {
  const problemas: string[] = [];

  if (bytes.length === 0) {
    return {
      bytes: 0,
      tieneBom: false,
      soloCrlf: false,
      lfSueltos: 0,
      cabecera: [],
      filas: [],
      anchosAnomalos: [],
      problemas: ['el archivo está vacío (0 bytes)'],
    };
  }

  const tieneBom =
    bytes.length >= 3 &&
    bytes[0] === BOM_UTF8[0] &&
    bytes[1] === BOM_UTF8[1] &&
    bytes[2] === BOM_UTF8[2];

  if (!tieneBom) {
    const primeros = [...bytes.subarray(0, 3)]
      .map((b) => b.toString(16).toUpperCase().padStart(2, '0'))
      .join(' ');
    problemas.push(
      `falta el BOM UTF-8: se esperaba EF BB BF y empieza por ${primeros}`,
    );
  }

  // El BOM se quita antes de analizar; si no, la primera cabecera saldría con
  // un U+FEFF pegado y la comparación fallaría por un carácter invisible.
  const cuerpo = tieneBom ? bytes.subarray(3) : bytes;
  const texto = cuerpo.toString('utf8');

  let lfSueltos = 0;
  for (let i = 0; i < texto.length; i += 1) {
    if (texto[i] === '\n' && texto[i - 1] !== '\r') lfSueltos += 1;
  }
  if (lfSueltos > 0) {
    problemas.push(
      `hay ${lfSueltos} salto(s) LF sin su CR: HACER espera CRLF en todos`,
    );
  }

  const filas = analizarCsv(texto);
  const cabecera = filas[0] ?? [];
  const cuerpoFilas = filas.slice(1);

  if (cabecera.length !== COLUMNAS_HACER.length) {
    problemas.push(
      `la cabecera tiene ${cabecera.length} columnas y se esperaban ${COLUMNAS_HACER.length}`,
    );
  }

  const discrepantes = cabecera
    .map((c, i) => ({ i, esperada: COLUMNAS_HACER[i], real: c }))
    .filter((d) => d.esperada !== d.real);
  for (const d of discrepantes.slice(0, 5)) {
    problemas.push(
      `columna ${d.i + 1}: se esperaba «${d.esperada}» y llegó «${d.real}»`,
    );
  }
  if (discrepantes.length > 5) {
    problemas.push(`… y ${discrepantes.length - 5} discrepancias más en la cabecera`);
  }

  const anchosAnomalos = cuerpoFilas
    .map((f, i) => ({ fila: i + 1, columnas: f.length }))
    .filter((a) => a.columnas !== cabecera.length);

  for (const a of anchosAnomalos.slice(0, 3)) {
    problemas.push(
      `la fila ${a.fila} tiene ${a.columnas} columnas y la cabecera ${cabecera.length}`,
    );
  }

  // Las columnas de tipo no textual no deben salir transformadas. **La
  // comprobación es estructural y no de mayúsculas, y ese cambio tiene motivo
  // medido**: la primera versión de este archivo afirmaba «no está en
  // mayúsculas» con `valor === valor.toUpperCase()`, y señaló como fallo la
  // columna `fecha_nac` de un archivo correcto —una fecha `1990-05-12` no tiene
  // letras, así que «está en mayúsculas» es vacuamente cierto—. Lo que de verdad
  // delata que un uuid o un `jsonb` se mayusculizó es que **deje de ser válido**.
  const validadores: Record<string, { prueba: RegExp | 'json' | 'booleano'; que: string }> = {
    inscripcion_id: { prueba: UUID, que: 'uuid' },
    seccion_id: { prueba: UUID, que: 'uuid' },
    programa_id: { prueba: UUID, que: 'uuid' },
    materia_id: { prueba: UUID, que: 'uuid' },
    aspirante_id: { prueba: UUID, que: 'uuid' },
    datos_planilla: { prueba: 'json', que: 'jsonb' },
    seccion_activa: { prueba: 'booleano', que: 'booleano' },
    discapacidad: { prueba: 'booleano', que: 'booleano' },
    fecha_nac: { prueba: FECHA, que: 'date' },
    inscrito_en: { prueba: MARCA_DE_TIEMPO, que: 'timestamptz' },
  };

  for (const fila of cuerpoFilas) {
    for (const [columna, v] of Object.entries(validadores)) {
      const i = cabecera.indexOf(columna);
      if (i < 0) continue;
      const valor = fila[i] ?? '';
      // Una celda vacía es legítima: el serializador escribe `""` para los
      // nulos, y un nulo no se puede validar por forma.
      if (valor === '') continue;

      let ok: boolean;
      if (v.prueba === 'json') {
        try {
          JSON.parse(valor);
          ok = true;
        } catch {
          ok = false;
        }
      } else if (v.prueba === 'booleano') {
        ok = valor === 'true' || valor === 'false';
      } else {
        ok = v.prueba.test(valor);
      }

      if (!ok) {
        problemas.push(
          `la columna «${columna}» (${v.que}) quedó ilegible: «${valor.slice(0, 60)}» — ` +
            'probablemente se le aplicó la regla de mayúsculas',
        );
      }
    }
  }

  return {
    bytes: bytes.length,
    tieneBom,
    soloCrlf: lfSueltos === 0,
    lfSueltos,
    cabecera,
    filas: cuerpoFilas,
    anchosAnomalos,
    problemas,
  };
}

/** Lanza si el archivo no cumple el contrato de HACER, con el informe completo. */
export function asertaArchivoHacer(
  bytes: Buffer,
  opciones: { filasEsperadas?: number } = {},
): InformeArchivoHacer {
  const informe = analizarArchivoHacer(bytes);

  if (informe.bytes === 0) {
    throw new Error('El archivo descargado está vacío.');
  }

  if (opciones.filasEsperadas !== undefined && informe.filas.length !== opciones.filasEsperadas) {
    informe.problemas.push(
      `se esperaban ${opciones.filasEsperadas} fila(s) de datos y hay ${informe.filas.length}`,
    );
  }

  if (informe.problemas.length > 0) {
    const detalle = [
      `El CSV descargado no cumple el formato de HACER (${informe.bytes} bytes):`,
      ...informe.problemas.map((p) => `  · ${p}`),
      '',
      `cabecera recibida (${informe.cabecera.length} columnas): ${informe.cabecera.join(' | ')}`,
    ].join('\n');
    throw new Error(detalle);
  }

  return informe;
}

// --- Ejecutable suelto, para comprobar el helper contra un archivo real -----
// Uso: node src/fixtures/csv.ts <ruta.csv>
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const ruta = process.argv[2];
  if (!ruta) {
    console.error('uso: node src/fixtures/csv.ts <ruta.csv>');
    process.exit(2);
  }
  const bytes = readFileSync(ruta);
  const informe = analizarArchivoHacer(bytes);
  console.log(`archivo          : ${ruta}`);
  console.log(`bytes            : ${informe.bytes}`);
  console.log(`BOM UTF-8        : ${informe.tieneBom ? 'sí' : 'NO'}`);
  console.log(`sólo CRLF        : ${informe.soloCrlf ? 'sí' : `NO (${informe.lfSueltos} LF sueltos)`}`);
  console.log(`columnas         : ${informe.cabecera.length}`);
  console.log(`filas de datos   : ${informe.filas.length}`);
  console.log(`anchos anómalos  : ${informe.anchosAnomalos.length}`);
  console.log(`problemas        : ${informe.problemas.length}`);
  for (const p of informe.problemas) console.log(`   · ${p}`);
  console.log(informe.problemas.length === 0 ? '\nVEREDICTO: cumple' : '\nVEREDICTO: NO cumple');
}
