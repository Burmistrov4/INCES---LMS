import type { CampoInscripcion } from '../dominio/tipos.js';

/**
 * Lo que comparten las **dos salidas** de la planilla de inscripción: el PDF que
 * se imprime y el Excel que la administración edita.
 *
 * Hasta el 2026-09-30 esto vivía dentro de `planilla-pdf.ts`, y mientras hubo
 * una sola salida era lo correcto. Con la segunda, la tentación era copiarlo
 * —son cuarenta líneas— y habría sido la peor opción posible: la planilla
 * impresa y la editable mostrarían **el mismo campo con distinto texto** en
 * cuanto una de las dos copias se tocara, y el desvío no daría ningún error.
 * Se vería como una planilla que dice «Si» donde la otra dice «No».
 *
 * Lo que **no** se comparte es el dibujo: el PDF compone párrafos con
 * coordenadas y el Excel escribe celdas. Son dos renderizadores distintos y
 * mezclarlos sería peor que separarlos. Lo compartido es el **contrato de
 * entrada** y el **significado** de cada valor.
 */

/**
 * Lo que el adaptador entrega a un renderizador de la planilla.
 *
 * Se llamaba `EntradaPlanillaPdf` y se llamó así mientras el PDF era la única
 * salida. El nombre dejó de ser cierto en cuanto hubo una segunda, y un nombre
 * que miente se paga cada vez que alguien lo lee.
 */
export interface EntradaPlanilla {
  /** Cabecera del formulario físico: el CFS rellena FECHA/PROYECTO/HORARIO; aquí va la emisión. */
  cedula: string | null;
  nombres: string | null;
  apellidos: string | null;
  email: string | null;
  /** Catálogo activo, ya ordenado. Es la fuente de verdad de qué se pinta y cómo. */
  campos: CampoInscripcion[];
  /** El jsonb relleno del aspirante (`aspirantes.datos_planilla`). */
  datosPlanilla: Record<string, unknown>;
  /**
   * Valores de respaldo tomados de las columnas de identidad de `aspirantes`
   * (cédula, correo, teléfono, fecha de nacimiento, sexo, dirección, nivel,
   * curso). Se usan sólo cuando `datosPlanilla` no trae el campo, porque el
   * formulario puede haber escrito las mismas claves con otro nombre.
   */
  identidad: Record<string, string | null>;
  generadoEn: Date;
}

/** Una opción de un campo `seleccion`/`multiseleccion`, tal como viaja en el catálogo. */
export interface OpcionItem {
  valor: string;
  etiqueta: string;
}

export function opcionesLista(opciones: Record<string, unknown> | null): OpcionItem[] {
  if (!opciones) return [];
  const lista = opciones.opciones;
  return Array.isArray(lista) ? (lista as OpcionItem[]) : [];
}

export function etiquetaDe(opciones: Record<string, unknown> | null, valor: string): string | null {
  return opcionesLista(opciones).find((o) => o.valor === valor)?.etiqueta ?? null;
}

export function esVerdadero(valor: unknown): boolean {
  return valor === true || valor === 'true' || valor === 1 || valor === '1';
}

/** `2026-09-30` → `30/09/2026`. Lo que no tenga esa forma se devuelve tal cual. */
export function formatearFecha(valor: unknown): string {
  if (valor == null) return '';
  const texto = String(valor);
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(texto);
  if (m) return `${m[3]}/${m[2]}/${m[1]}`;
  return texto;
}

/**
 * El valor de un campo escalar, ya listo para leer.
 *
 * El respaldo por `identidad` existe porque el formulario puede haber guardado
 * la misma información con otra clave: una ficha escrita antes de que el
 * catálogo tuviera `cedula` la tiene igualmente en su columna.
 */
export function valorPlano(
  campo: CampoInscripcion,
  datos: Record<string, unknown>,
  identidad: Record<string, string | null>,
): string {
  let valor: unknown = datos[campo.codigo];
  if (valor === undefined || valor === null || valor === '') {
    valor = identidad[campo.codigo] ?? null;
  }
  if (valor === undefined || valor === null || valor === '') return '';

  switch (campo.tipo) {
    case 'booleano':
      return esVerdadero(valor) ? 'Si' : 'No';
    case 'seleccion': {
      const etiqueta = etiquetaDe(campo.opciones, String(valor));
      return etiqueta ?? String(valor);
    }
    case 'multiseleccion': {
      const arr = Array.isArray(valor) ? (valor as unknown[]) : [valor];
      return arr
        .map((v) => etiquetaDe(campo.opciones, String(v)) ?? String(v))
        .filter(Boolean)
        .join(', ');
    }
    case 'fecha':
      return formatearFecha(valor);
    default:
      return String(valor);
  }
}

/**
 * Un campo `rejilla` como líneas de texto: una por casilla, marcada o no.
 *
 * Se listan **todas** las casillas y no sólo las marcadas, porque en una
 * rejilla «lo que no está marcado» es tan informativo como lo que sí: la
 * planilla impresa lo hace así y el Excel tiene que decir lo mismo.
 */
export function textoDeRejilla(
  campo: CampoInscripcion,
  datos: Record<string, unknown>,
): string[] {
  const items = (campo.opciones?.items as OpcionItem[] | undefined) ?? [];
  const marcados = datos[campo.codigo];

  // El formulario guarda un objeto `{ valor: "desde" }` o un arreglo de valores.
  const mapa: Record<string, string> = {};
  if (Array.isArray(marcados)) {
    for (const v of marcados as string[]) mapa[v] = '';
  } else if (marcados && typeof marcados === 'object') {
    for (const [k, v] of Object.entries(marcados as Record<string, unknown>)) {
      mapa[k] = v == null ? '' : String(v);
    }
  }

  return items.map((item) => {
    const esta = item.valor in mapa;
    const desde = mapa[item.valor] ? ` (desde ${mapa[item.valor]})` : '';
    return `${esta ? '[X]' : '[ ]'} ${item.etiqueta}${esta ? desde : ''}`;
  });
}

/**
 * Un campo `tabla` como líneas de texto: un bloque por fila, con sus columnas.
 *
 * El respaldo por `identidad` de cada celda usa la clave compuesta
 * `campo.columna` —igual que el PDF—, que es como el formulario guarda una
 * tabla que se rellenó por partes.
 */
export function textoDeTabla(
  campo: CampoInscripcion,
  datos: Record<string, unknown>,
  identidad: Record<string, string | null>,
): string[] {
  const columnas =
    (campo.opciones?.columnas as
      | Array<{ codigo: string; etiqueta: string; tipo?: string; opciones?: Record<string, unknown> }>
      | undefined) ?? [];
  const filas = Array.isArray(datos[campo.codigo])
    ? (datos[campo.codigo] as Record<string, unknown>[])
    : [];

  if (columnas.length === 0) return [];
  if (filas.length === 0) return ['Sin registros.'];

  const lineas: string[] = [];
  filas.forEach((fila, indice) => {
    lineas.push(`Fila ${indice + 1}`);
    for (const col of columnas) {
      const celda = col.codigo in fila
        ? fila[col.codigo]
        : identidad[`${campo.codigo}.${col.codigo}`] ?? null;

      let texto: string;
      if (col.tipo === 'booleano') texto = esVerdadero(celda) ? 'Si' : 'No';
      else if (col.tipo === 'seleccion' && col.opciones) {
        texto = etiquetaDe(col.opciones, String(celda ?? '')) ?? String(celda ?? '');
      } else texto = celda == null ? '' : String(celda);

      lineas.push(`  ${col.etiqueta}: ${texto || '-'}`);
    }
  });
  return lineas;
}
