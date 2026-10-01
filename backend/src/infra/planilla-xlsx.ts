import writeXlsxFile from 'write-excel-file/node';
import type { Cell, Row } from 'write-excel-file/node';
import type { CampoInscripcion } from '../dominio/tipos.js';
import {
  formatearFecha,
  textoDeRejilla,
  textoDeTabla,
  valorPlano,
  type EntradaPlanilla,
} from './planilla-valores.js';

/**
 * La planilla de inscripción como hoja de cálculo **editable**.
 *
 * **Por qué existe habiendo un PDF.** El PDF se imprime y se le entrega al
 * aspirante que llega al centro: eso no cambia. Lo que la administración pedía
 * es además una versión **editable** —para colocar el número de planilla, para
 * corregir un dato antes de imprimir, para trabajar con la lista— y un PDF no
 * se edita. Es la misma planilla, con los mismos valores, en un formato que se
 * puede tocar.
 *
 * **Por qué comparte `planilla-valores.ts` con el PDF.** Es la única forma de
 * que las dos salidas digan lo mismo. Si cada una formateara por su cuenta, el
 * mismo campo se leería distinto en papel que en pantalla —«Si» frente a
 * «true», una fecha en dos órdenes— y el desvío no daría ningún error. Lo que
 * **no** se comparte es el dibujo: el PDF compone párrafos con coordenadas; esto
 * escribe celdas. Dos renderizadores, un solo significado.
 *
 * **Por qué la forma es una tabla de dos columnas.** La planilla física es un
 * formulario: etiqueta a la izquierda, valor a la derecha, agrupado por
 * secciones. Reproducir esa forma es lo que hace que la hoja se lea como la
 * planilla y no como un volcado de datos. Y deja el valor en **una sola celda**,
 * que es exactamente lo que hace falta para poder escribir encima.
 */

/**
 * El tipo MIME del `.xlsx`.
 *
 * Es el largo de OOXML y **no** `application/vnd.ms-excel`: ése es el del `.xls`
 * binario antiguo, y declararlo haría que algunos navegadores abrieran el
 * archivo con la aplicación equivocada o lo guardaran con la extensión de otro
 * formato. La cadena es fea y por eso vive en una sola constante: escrita dos
 * veces, la segunda acabaría con una letra de menos.
 */
export const TIPO_XLSX =
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

const AZUL = '#1A3866';
const BLANCO = '#FFFFFF';
const GRIS = '#EEF1F6';

/** Un encabezado a ancho completo: las dos columnas fusionadas. */
function banda(texto: string, fondo: string, color: string, fontSize?: number): Cell {
  return {
    value: texto,
    fontWeight: 'bold',
    backgroundColor: fondo,
    textColor: color,
    columnSpan: 2,
    ...(fontSize === undefined ? {} : { fontSize }),
  };
}

/** Una fila etiqueta/valor. `wrap` en el valor porque una tabla ocupa varias líneas. */
function par(etiqueta: string, valor: string): Row {
  return [
    { value: etiqueta, fontWeight: 'bold', alignVertical: 'top' },
    { value: valor || '-', wrap: true, alignVertical: 'top' },
  ];
}

/**
 * Las líneas que ocupa el valor de un campo.
 *
 * `rejilla` y `tabla` no son un valor suelto sino varios: se despliegan en
 * líneas para que se lean dentro de la celda, igual que el PDF los dibuja en
 * varios renglones. Se reutilizan los mismos ayudantes que el PDF usa.
 */
function lineasDe(campo: CampoInscripcion, entrada: EntradaPlanilla): string[] {
  switch (campo.tipo) {
    case 'rejilla':
      return textoDeRejilla(campo, entrada.datosPlanilla);
    case 'tabla':
      return textoDeTabla(campo, entrada.datosPlanilla, entrada.identidad);
    default: {
      const valor = valorPlano(campo, entrada.datosPlanilla, entrada.identidad);
      return valor ? [valor] : [];
    }
  }
}

/**
 * Genera la planilla en `.xlsx` y devuelve los bytes.
 *
 * Devuelve `Uint8Array` y no `Buffer` para que la firma sea la misma que la del
 * renderizador del PDF: quien los usa los trata igual —los manda como cuerpo
 * binario— y no debería tener que recordar cuál devuelve qué.
 */
export async function renderizarPlanillaXlsx(
  entrada: EntradaPlanilla,
): Promise<Uint8Array> {
  const filas: Row[] = [];

  // --- Cabecera, igual que la del formulario impreso ---
  filas.push([banda('PLANILLA DE INSCRIPCIÓN', AZUL, BLANCO, 14)]);
  filas.push([banda('CFS NAC. SOLDADURA «RAFAEL URDANETA» — LA ISABELICA', AZUL, BLANCO)]);
  const nombre = `${entrada.nombres ?? ''} ${entrada.apellidos ?? ''}`.trim() || 'ASPIRANTE';
  filas.push([banda(nombre, AZUL, BLANCO)]);
  filas.push([]);

  const cedula =
    entrada.cedula ?? (entrada.datosPlanilla['cedula'] as string | undefined) ?? '';
  filas.push(par('Cédula', cedula));
  filas.push(par('Fecha de emisión', formatearFecha(entrada.generadoEn.toISOString())));

  // El número preimpreso se pinta sólo si existe, igual que en el PDF: una fila
  // vacía con la etiqueta puesta se leería como «falta este dato».
  const preimpreso = entrada.datosPlanilla['numero_preimpreso'];
  if (preimpreso) filas.push(par('N.º preimpreso', String(preimpreso)));

  // --- Los campos, agrupados como en la planilla física ---
  //
  // El catálogo llega ordenado por `orden` **global**, así que un grupo nuevo
  // empieza cuando cambia `campo.grupo`. Es el mismo criterio que sigue el PDF:
  // si aquí se ordenara por grupo y allí por orden, las dos planillas
  // presentarían los mismos datos en distinto orden.
  let grupoActual: string | null = null;
  for (const campo of entrada.campos) {
    if (campo.grupo !== grupoActual) {
      grupoActual = campo.grupo;
      filas.push([]);
      filas.push([banda(grupoActual, GRIS, AZUL)]);
    }
    filas.push(par(campo.etiqueta, lineasDe(campo, entrada).join('\n')));
  }

  filas.push([]);
  filas.push([
    {
      value:
        'Documento generado por el LMS del CFS. Los campos se pueden editar en esta ' +
        'hoja antes de imprimir; el PDF oficial sale del registro digital.',
      columnSpan: 2,
      wrap: true,
      textColor: '#6B7280',
      fontSize: 9,
    },
  ]);

  const buffer = await writeXlsxFile(
    filas,
    {
      sheet: 'Planilla',
      // Sin líneas de cuadrícula: la planilla tiene sus propias bandas y la
      // cuadrícula por encima las convierte en una hoja de cálculo cualquiera.
      showGridLines: false,
      columns: [{ width: 38 }, { width: 62 }],
    },
    { fontFamily: 'Calibri', fontSize: 11 },
  ).toBuffer();

  return new Uint8Array(buffer);
}
