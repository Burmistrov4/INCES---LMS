/**
 * Renderizador de la planilla de inscripción del INCES a PDF.
 *
 * ============================================================================
 *  POR QUÉ EXISTE ESTE ARCHIVO
 * ============================================================================
 * La Fase 3 pide un endpoint que, dado un UUID de usuario, devuelva la
 * planilla de inscripción del INCES **llena**, lista para imprimir. El dato ya
 * vive en la base —`aspirantes.datos_planilla` (jsonb) y el catálogo de campos
 * `inscripcion_campos`—, así que lo único que falta es **pintarlo**. Esta
 * función es esa pintura: recibe el catálogo (etiquetas, grupos, tipos) y el
 * jsonb relleno, y produce un `Uint8Array` con un PDF de una o varias páginas.
 *
 * ============================================================================
 *  LA FUENTE DE VERDAD ES EL CATÁLOGO, NO UN DISEÑO A MANO
 * ============================================================================
 * El PDF no tiene los campos hardcodeados. Los lee del catálogo que le pasa el
 * adaptador, igual que el formulario Flutter. Por eso, si el CFS añade un campo
 * desde el panel de administración, la planilla impresa lo trae sin tocar este
 * archivo (la misma propiedad que `datos_planilla` le da al formulario). Lo que
 * sí es fijo es la **forma de cada tipo**: cómo se pinta un `tabla`, un
 * `rejilla`, un `seleccion`. Esa lógica vive aquí y es la que el catálogo no
 * puede describir.
 *
 * ============================================================================
 *  CODIFICACIÓN
 * ============================================================================
 * `pdf-lib` con las fuentes estándar de Helvetica usa WinAnsi (Latin-1). Cualquier
 * carácter fuera de ese rango —un emoji, un guioncillo curioso— hace que
 * `drawText` lanze. Como el contenido es entrada del usuario, se sanea a
 * Latin-1 antes de pintar: lo que no cabe se sustituye por `?`. El alfabeto
 * español (á é í ó ú ñ ü ¿ ¡) sí cabe.
 */

import { PDFDocument, StandardFonts, type PDFFont, type PDFPage, rgb } from 'pdf-lib';
import type { CampoInscripcion } from '../dominio/tipos.js';

/** Lo que el adaptador entrega al renderizador. */
export interface EntradaPlanillaPdf {
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

const ANCHO = 595.28; // A4
const ALTO = 841.89;
const IZQ = 40;
const DER = 40;
const SUP = 40;
const INF = 44;
const CONTENIDO = ANCHO - IZQ - DER;

const NEGRO = rgb(0.1, 0.1, 0.1);
const GRIS = rgb(0.4, 0.4, 0.4);
const AZUL = rgb(0.1, 0.22, 0.42);
const BLANCO = rgb(1, 1, 1);
const LINEA = rgb(0.78, 0.78, 0.78);

interface Ctx {
  doc: PDFDocument;
  page: PDFPage;
  font: PDFFont;
  bold: PDFFont;
  y: number;
}

function aLatin1(texto: string): string {
  let salida = '';
  for (const caracter of texto) {
    const codigo = caracter.codePointAt(0) ?? 0;
    if (codigo <= 0x7f) salida += caracter;
    else if (codigo === 0xa0) salida += ' ';
    else if (codigo >= 0xa1 && codigo <= 0xff) salida += caracter;
    else salida += '?';
  }
  return salida;
}

function nuevaPagina(ctx: Ctx): void {
  ctx.page = ctx.doc.addPage([ANCHO, ALTO]);
  ctx.y = ALTO - SUP;
}

function asegurar(ctx: Ctx, alto: number): void {
  if (ctx.y - alto < INF) nuevaPagina(ctx);
}

/** Escribe en la línea actual y baja el cursor. */
function escribir(ctx: Ctx, texto: string, x: number, size: number, font: PDFFont, color = NEGRO): void {
  ctx.page.drawText(aLatin1(texto), { x, y: ctx.y, size, font, color });
}

/** Ancho de un texto en la fuente dada. */
function ancho(texto: string, size: number, font: PDFFont): number {
  return font.widthOfTextAtSize(aLatin1(texto), size);
}

/** Particiona un texto en líneas que caben en `maxAncho`. */
function ajustar(texto: string, size: number, font: PDFFont, maxAncho: number): string[] {
  const palabras = aLatin1(texto).split(/\s+/).filter(Boolean);
  const lineas: string[] = [];
  let linea = '';
  for (const palabra of palabras) {
    const candidata = linea ? `${linea} ${palabra}` : palabra;
    if (ancho(candidata, size, font) <= maxAncho) {
      linea = candidata;
      continue;
    }
    if (linea) lineas.push(linea);
    if (ancho(palabra, size, font) <= maxAncho) {
      linea = palabra;
    } else {
      // Palabra más larga que el ancho: partir por caracteres.
      let trozo = '';
      for (const caracter of palabra) {
        if (ancho(trozo + caracter, size, font) <= maxAncho) trozo += caracter;
        else {
          lineas.push(trozo);
          trozo = caracter;
        }
      }
      linea = trozo;
    }
  }
  if (linea) lineas.push(linea);
  return lineas.length ? lineas : [''];
}

// --- Formato de valores por tipo -------------------------------------------------

type OpcionItem = { valor: string; etiqueta: string };

function opcionesLista(opciones: Record<string, unknown> | null): OpcionItem[] {
  if (!opciones) return [];
  const lista = opciones.opciones;
  return Array.isArray(lista) ? (lista as OpcionItem[]) : [];
}

function etiquetaDe(opciones: Record<string, unknown> | null, valor: string): string | null {
  return opcionesLista(opciones).find((o) => o.valor === valor)?.etiqueta ?? null;
}

function esVerdadero(valor: unknown): boolean {
  return valor === true || valor === 'true' || valor === 1 || valor === '1';
}

function formatearFecha(valor: unknown): string {
  if (valor == null) return '';
  const texto = String(valor);
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(texto);
  if (m) return `${m[3]}/${m[2]}/${m[1]}`;
  return texto;
}

function valorPlano(campo: CampoInscripcion, datos: Record<string, unknown>, identidad: Record<string, string | null>): string {
  let valor: unknown = datos[campo.codigo];
  if (valor === undefined || valor === null || valor === '') valor = identidad[campo.codigo] ?? null;
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

// --- Bloques de dibujo ----------------------------------------------------------

function dibujarEncabezado(ctx: Ctx, entrada: EntradaPlanillaPdf): void {
  // Banda superior del CFS.
  ctx.page.drawRectangle({ x: IZQ, y: ctx.y - 34, width: CONTENIDO, height: 34, color: AZUL });
  escribir(ctx, 'PLANILLA DE INSCRIPCION', IZQ + 10, 13, ctx.bold, BLANCO);
  const nombre = `${entrada.nombres ?? ''} ${entrada.apellidos ?? ''}`.trim() || 'ASPIRANTE';
  escribir(ctx, aLatin1(`CFS NAC. SOLDADURA "RAFAEL URDANETA" - LA ISABELICA`), IZQ + 10, 8, ctx.font, BLANCO);
  escribir(ctx, aLatin1(` ${nombre}`), IZQ + 10, 8, ctx.font, BLANCO);
  ctx.y -= 42;

  // Datos de cabecera del formulario fisico.
  const cedula = entrada.cedula ?? (entrada.datosPlanilla['cedula'] as string | undefined) ?? '';
  const fecha = formatearFecha(entrada.generadoEn.toISOString());
  escribir(ctx, `Cedula: ${aLatin1(cedula || '-')}`, IZQ, 9, ctx.bold);
  escribir(ctx, `Fecha de emision: ${fecha}`, IZQ + 260, 9, ctx.bold);
  ctx.y -= 14;
  const preimpreso = entrada.datosPlanilla['numero_preimpreso'];
  if (preimpreso) {
    escribir(ctx, `N. preimpreso: ${aLatin1(String(preimpreso))}`, IZQ, 9, ctx.bold);
    ctx.y -= 14;
  }
  // Linea separadora.
  ctx.page.drawLine({ start: { x: IZQ, y: ctx.y }, end: { x: ANCHO - DER, y: ctx.y }, thickness: 0.6, color: LINEA });
  ctx.y -= 12;
}

function dibujarSeccion(ctx: Ctx, nombre: string): void {
  asegurar(ctx, 22);
  ctx.y -= 4;
  ctx.page.drawRectangle({ x: IZQ, y: ctx.y - 16, width: CONTENIDO, height: 16, color: AZUL });
  escribir(ctx, aLatin1(nombre.toUpperCase()), IZQ + 8, 10, ctx.bold, BLANCO);
  ctx.y -= 22;
}

function dibujarCampo(ctx: Ctx, campo: CampoInscripcion, datos: Record<string, unknown>, identidad: Record<string, string | null>): void {
  const etiqueta = campo.obligatorio ? `${campo.etiqueta} *` : campo.etiqueta;
  const valor = valorPlano(campo, datos, identidad);

  // Etiqueta en negrita.
  const lineasEtiqueta = ajustar(etiqueta, 9.5, ctx.bold, CONTENIDO);
  asegurar(ctx, lineasEtiqueta.length * 12 + 14);
  for (const linea of lineasEtiqueta) {
    escribir(ctx, aLatin1(linea), IZQ, 9.5, ctx.bold, NEGRO);
    ctx.y -= 12;
  }

  // Valor en texto normal, sangrado.
  if (valor) {
    const lineasValor = ajustar(valor, 9.5, ctx.font, CONTENIDO - 12);
    for (const linea of lineasValor) {
      escribir(ctx, aLatin1(linea), IZQ + 12, 9.5, ctx.font, NEGRO);
      ctx.y -= 12;
    }
  } else {
    escribir(ctx, '........................................', IZQ + 12, 9.5, ctx.font, GRIS);
    ctx.y -= 12;
  }
  ctx.y -= 4;
}

function dibujarRejilla(ctx: Ctx, campo: CampoInscripcion, datos: Record<string, unknown>, _identidad: Record<string, string | null>): void {
  const items = (campo.opciones?.items as OpcionItem[] | undefined) ?? [];
  const marcados = datos[campo.codigo];
  // El formulario guarda un objeto { valor: "desde" } o un arreglo de valores.
  const mapa: Record<string, string> = {};
  if (Array.isArray(marcados)) {
    for (const v of marcados as string[]) mapa[v] = '';
  } else if (marcados && typeof marcados === 'object') {
    for (const [k, v] of Object.entries(marcados as Record<string, unknown>)) mapa[k] = v == null ? '' : String(v);
  }

  const columnas = 2;
  const anchoCol = CONTENIDO / columnas;
  let col = 0;
  // `yFila` es la altura donde arranca la fila de dos columnas; `fondoCol0` es
  // el fondo de la columna 0. Al terminar la fila, el cursor baja al fondo de la
  // columna más profunda de las dos.
  let yFila = ctx.y;
  let fondoCol0 = ctx.y;
  for (const item of items) {
    if (col === 0) {
      asegurar(ctx, 16);
      yFila = ctx.y;
      fondoCol0 = ctx.y;
    }
    const esta = item.valor in mapa;
    const texto = esta ? `[X] ${item.etiqueta}${mapa[item.valor] ? ` (desde ${mapa[item.valor]})` : ''}` : `[ ] ${item.etiqueta}`;
    const lineas = ajustar(texto, 9, ctx.font, anchoCol - 8);
    if (col === 0) {
      let yy = ctx.y;
      for (const linea of lineas) {
        escribir(ctx, aLatin1(linea), IZQ, 9, ctx.font, esta ? NEGRO : GRIS);
        yy -= 11;
      }
      ctx.y = yy;
      fondoCol0 = yy;
    } else {
      // Columna 2: se pinta a la MISMA altura que la columna 1 de la fila
      // (`yFila`), bajando desde ahí, no a la altura ya avanzada por la col. 1.
      let yy = yFila;
      for (const linea of lineas) {
        ctx.y = yy;
        escribir(ctx, aLatin1(linea), IZQ + anchoCol, 9, ctx.font, esta ? NEGRO : GRIS);
        yy -= 11;
      }
      ctx.y = Math.min(fondoCol0, yy);
    }
    col = (col + 1) % columnas;
    if (col === 0) ctx.y -= 2;
  }
  ctx.y -= 4;
}

function dibujarTabla(ctx: Ctx, campo: CampoInscripcion, datos: Record<string, unknown>, identidad: Record<string, string | null>): void {
  const columnas = (campo.opciones?.columnas as Array<{ codigo: string; etiqueta: string; tipo?: string; opciones?: Record<string, unknown> }> | undefined) ?? [];
  const filas = Array.isArray(datos[campo.codigo]) ? (datos[campo.codigo] as Record<string, unknown>[]) : [];

  if (columnas.length === 0) return;

  // Encabezado de la tabla.
  asegurar(ctx, 14);
  for (const col of columnas) {
    escribir(ctx, aLatin1(col.etiqueta), IZQ, 8.5, ctx.bold, AZUL);
    ctx.y -= 11;
    break; // La etiqueta de columnas la repetimos por fila para legibilidad.
  }
  ctx.y += 11;

  if (filas.length === 0) {
    escribir(ctx, 'Sin registros.', IZQ + 12, 9, ctx.font, GRIS);
    ctx.y -= 12;
    ctx.y -= 4;
    return;
  }

  filas.forEach((fila, indice) => {
    asegurar(ctx, 14);
    escribir(ctx, aLatin1(`Fila ${indice + 1}`), IZQ, 9, ctx.bold, AZUL);
    ctx.y -= 12;
    for (const col of columnas) {
      let celda: unknown;
      if (col.codigo in fila) celda = fila[col.codigo];
      else celda = identidad[`${campo.codigo}.${col.codigo}`] ?? null;

      let texto = '';
      if (col.tipo === 'booleano') texto = esVerdadero(celda) ? 'Si' : 'No';
      else if (col.tipo === 'seleccion' && col.opciones) texto = etiquetaDe(col.opciones, String(celda ?? '')) ?? String(celda ?? '');
      else texto = celda == null ? '' : String(celda);

      const lineas = ajustar(`${col.etiqueta}: ${texto || '-'}`, 9, ctx.font, CONTENIDO - 12);
      for (const linea of lineas) {
        escribir(ctx, aLatin1(linea), IZQ + 12, 9, ctx.font, NEGRO);
        ctx.y -= 11;
      }
    }
    ctx.y -= 3;
  });
  ctx.y -= 4;
}

// --- Entrada -------------------------------------------------------------------

export async function renderizarPlanillaPdf(entrada: EntradaPlanillaPdf): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);

  const ctx: Ctx = { doc, page: doc.addPage([ANCHO, ALTO]), font, bold, y: ALTO - SUP };

  dibujarEncabezado(ctx, entrada);

  // Agrupar por `grupo` conservando el orden de primera aparición en el catálogo.
  const ordenGrupos: string[] = [];
  const porGrupo = new Map<string, CampoInscripcion[]>();
  for (const campo of entrada.campos) {
    if (!porGrupo.has(campo.grupo)) {
      porGrupo.set(campo.grupo, []);
      ordenGrupos.push(campo.grupo);
    }
    porGrupo.get(campo.grupo)!.push(campo);
  }

  for (const grupo of ordenGrupos) {
    dibujarSeccion(ctx, grupo);
    for (const campo of porGrupo.get(grupo)!) {
      if (campo.tipo === 'tabla') dibujarTabla(ctx, campo, entrada.datosPlanilla, entrada.identidad);
      else if (campo.tipo === 'rejilla') dibujarRejilla(ctx, campo, entrada.datosPlanilla, entrada.identidad);
      else dibujarCampo(ctx, campo, entrada.datosPlanilla, entrada.identidad);
    }
  }

  // Pie de página con salto de página por si acaso.
  asegurar(ctx, 16);
  ctx.page.drawLine({ start: { x: IZQ, y: ctx.y }, end: { x: ANCHO - DER, y: ctx.y }, thickness: 0.6, color: LINEA });
  ctx.y -= 12;
  escribir(
    ctx,
    aLatin1(`Documento generado por el LMS INCES el ${formatearFecha(entrada.generadoEn.toISOString())}. Verifique los datos antes de imprimir.`),
    IZQ,
    7.5,
    ctx.font,
    GRIS,
  );

  return doc.save();
}
