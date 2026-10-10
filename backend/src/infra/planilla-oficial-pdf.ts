/**
 * Renderizador de la Planilla Oficial INCES fÃ­sica (612 Ã— 792 pt, 1 pÃ¡gina).
 *
 * Cumple con los requisitos de la auditorÃ­a y diseÃ±o tÃ©cnico:
 *  - 612 Ã— 792 pt (US Letter exacto).
 *  - Exactamente 1 pÃ¡gina.
 *  - Embebe o sobreimprime sobre la plantilla oficial preimpresa preservando
 *    la fidelidad institucional completa (logos, sellos, tÃ­tulos vectoriales).
 *  - Posicionamiento medido empÃ­ricamente sobre los 425 segmentos de rejilla.
 *  - SanitizaciÃ³n a Latin-1 (WinAnsi) para evitar excepciones de codificaciÃ³n.
 *  - NO modifica ni depende del renderer genÃ©rico A4 (`planilla-pdf.ts`).
 */

import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PDFDocument, StandardFonts, type PDFFont, type PDFPage, rgb } from 'pdf-lib';
import type { PlanillaOficialData } from '../dominio/planilla-oficial-tipos.js';

export const ANCHO_OFICIAL = 612.0;
export const ALTO_OFICIAL = 792.0;

const COLOR_TEXTO = rgb(0.05, 0.05, 0.15); // Azul tinta institucional oscuro
const COLOR_MARCA = rgb(0.1, 0.1, 0.1);     // Negro para casillas

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

function dibujarTexto(
  page: PDFPage,
  texto: string | null | undefined,
  x: number,
  y: number,
  size: number,
  font: PDFFont,
  maxAncho?: number,
  color = COLOR_TEXTO,
): void {
  if (!texto) return;
  let str = aLatin1(String(texto).trim());
  if (!str) return;

  if (maxAncho && maxAncho > 0) {
    while (font.widthOfTextAtSize(str, size) > maxAncho && str.length > 3) {
      str = str.slice(0, -4) + '...';
    }
  }

  page.drawText(str, {
    x,
    y,
    size,
    font,
    color,
  });
}

function dibujarMarca(
  page: PDFPage,
  x: number,
  y: number,
  size = 7.5,
  boldFont: PDFFont,
): void {
  page.drawText('X', {
    x: x - 1,
    y: y - 0.5,
    size,
    font: boldFont,
    color: COLOR_MARCA,
  });
}

/**
 * Obtiene y valida la plantilla institucional; falla explícitamente si falta o está dañada.

 */
async function obtenerDocumentoBase(): Promise<PDFDocument> {
  const rutaActual = dirname(fileURLToPath(import.meta.url));
  const posiblesRutas = [
    join(rutaActual, '../../assets/planilla-oficial-template.pdf'),
    join(rutaActual, '../assets/planilla-oficial-template.pdf'),
    join(process.cwd(), 'backend/assets/planilla-oficial-template.pdf'),
    join(process.cwd(), 'assets/planilla-oficial-template.pdf'),
  ];

  for (const ruta of posiblesRutas) {
    if (existsSync(ruta)) {
      try {
        const bytes = readFileSync(ruta);
        const doc = await PDFDocument.load(bytes);
        const paginas = doc.getPages();
        if (paginas.length !== 1) {
          throw new Error(`se esperaba 1 página y se encontraron ${paginas.length}`);
        }
        const pagina = paginas[0];
        if (
          !pagina ||
          Math.abs(pagina.getWidth() - ANCHO_OFICIAL) > 0.5 ||
          Math.abs(pagina.getHeight() - ALTO_OFICIAL) > 0.5
        ) {
          const dimensiones = pagina ? `${pagina.getWidth()} × ${pagina.getHeight()}` : 'indisponibles';
          throw new Error(`dimensiones esperadas 612 × 792 pt; recibidas ${dimensiones}`);
        }
        return doc;
      } catch (error) {
        const detalle = error instanceof Error ? error.message : String(error);
        throw new Error(`PLANTILLA_PLANILLA_OFICIAL_INVALIDA: no se pudo cargar ${ruta}: ${detalle}`);

      }
    }
  }

  // La plantilla es obligatoria; no devolver un documento vacío.
  throw new Error('PLANTILLA_PLANILLA_OFICIAL_AUSENTE: no se encontró una plantilla PDF institucional válida.');



}

/**
 * Renderiza la Planilla Oficial fÃ­sica a un buffer PDF de exactamente 1 pÃ¡gina (612 Ã— 792 pt).
 */
export async function renderizarPlanillaOficialPdf(
  data: PlanillaOficialData,
): Promise<Uint8Array> {
  const doc = await obtenerDocumentoBase();
  const page = doc.getPages()[0] ?? doc.addPage([ANCHO_OFICIAL, ALTO_OFICIAL]);
  page.setSize(ANCHO_OFICIAL, ALTO_OFICIAL);

  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);

  // 1. Encabezado
  dibujarTexto(page, data.cabecera.fecha, 250.0, 709.0, 7.0, font, 75);
  dibujarTexto(page, data.cabecera.numeroPreimpreso, 395.0, 709.0, 7.5, bold, 185);
  dibujarTexto(page, data.cabecera.proyecto, 275.0, 683.0, 7.0, font, 305);
  dibujarTexto(page, data.cabecera.espacioIntegralSocialista, 145.0, 658.0, 7.0, font, 180);
  dibujarTexto(page, data.cabecera.horario, 375.0, 658.0, 7.0, font, 205);

  // 2. Datos Personales: IdentificaciÃ³n (LÃ­nea de nombres)
  dibujarTexto(page, data.identidad.primerNombre, 31.2, 585.0, 7.5, font, 102);
  dibujarTexto(page, data.identidad.segundoNombre, 141.0, 585.0, 7.5, font, 102);
  dibujarTexto(page, data.identidad.primerApellido, 250.0, 585.0, 7.5, font, 102);
  dibujarTexto(page, data.identidad.segundoApellido, 360.0, 585.0, 7.5, font, 102);
  dibujarTexto(page, data.identidad.cedula, 470.0, 585.0, 7.5, font, 108);

  // 3. DemografÃ­a y Nacimiento
  dibujarTexto(page, data.identidad.nacionalidad, 32.0, 544.0, 7.5, font, 125);
  dibujarTexto(page, data.nacimiento.dia, 171.0, 544.0, 7.5, font, 20);
  dibujarTexto(page, data.nacimiento.mes, 198.0, 544.0, 7.5, font, 20);
  dibujarTexto(page, data.nacimiento.anio, 221.0, 544.0, 7.5, font, 22);
  if (data.nacimiento.edad !== null && data.nacimiento.edad !== undefined) {
    dibujarTexto(page, String(data.nacimiento.edad), 251.0, 544.0, 7.5, font, 25);
  }

  // GÃ©nero
  if (data.sexo === 'F') dibujarMarca(page, 304.0, 552.0, 7.5, bold);
  if (data.sexo === 'M') dibujarMarca(page, 325.5, 552.0, 7.5, bold);

  // Estado Civil
  if (data.estadoCivil === 'SOLTERO') dibujarMarca(page, 352.0, 557.5, 7.5, bold);
  if (data.estadoCivil === 'CASADO') dibujarMarca(page, 387.5, 557.5, 7.5, bold);
  if (data.estadoCivil === 'DIVORCIADO') dibujarMarca(page, 428.5, 557.5, 7.5, bold);
  if (data.estadoCivil === 'VIUDO') dibujarMarca(page, 371.5, 548.0, 7.5, bold);
  if (data.estadoCivil === 'CONCUBINATO') dibujarMarca(page, 400.0, 548.0, 7.5, bold);

  // Pueblo IndÃ­gena
  if (data.puebloIndigena.pertenece === true) {
    dibujarMarca(page, 508.0, 557.5, 7.5, bold);
    dibujarTexto(page, data.puebloIndigena.cual, 530.0, 544.0, 6.5, font, 50);
  } else if (data.puebloIndigena.pertenece === false) {
    dibujarMarca(page, 523.5, 557.5, 7.5, bold);
  }

  // 4. Diversidad Funcional
  if (data.discapacidad.fisicaMano) dibujarMarca(page, 32.0, 505.0, 7.5, bold);
  if (data.discapacidad.sensorialCeguera) dibujarMarca(page, 95.0, 505.0, 7.5, bold);
  if (data.discapacidad.fisicaPiernas) dibujarMarca(page, 32.0, 495.5, 7.5, bold);
  if (data.discapacidad.debilidadIntelectual) dibujarMarca(page, 95.0, 495.5, 7.5, bold);
  if (data.discapacidad.sensorialAuditiva) dibujarMarca(page, 32.0, 486.0, 7.5, bold);
  if (data.discapacidad.ninguna) dibujarMarca(page, 95.0, 486.0, 7.5, bold);
  dibujarTexto(page, data.discapacidad.indiqueCual, 85.0, 468.0, 6.0, font, 75);

  // PrÃ¡cticas
  dibujarTexto(page, data.practicas.deporte.valor, 166.0, 475.0, 6.5, font, 90);
  dibujarTexto(page, data.practicas.deporte.desde, 262.0, 475.0, 6.5, font, 35);
  dibujarTexto(page, data.practicas.cultural.valor, 304.0, 475.0, 6.5, font, 90);
  dibujarTexto(page, data.practicas.cultural.desde, 397.0, 475.0, 6.5, font, 40);
  dibujarTexto(page, data.practicas.organizacion.valor, 445.0, 475.0, 6.5, font, 90);
  dibujarTexto(page, data.practicas.organizacion.desde, 539.0, 475.0, 6.5, font, 40);

  // 5. UbicaciÃ³n y Contacto
  dibujarTexto(page, data.ubicacion.estado, 65.0, 418.0, 7.0, font, 70);
  dibujarTexto(page, data.ubicacion.municipio, 185.0, 418.0, 7.0, font, 85);
  dibujarTexto(page, data.ubicacion.parroquia, 330.0, 418.0, 7.0, font, 110);
  dibujarTexto(page, data.ubicacion.comunidad, 495.0, 418.0, 7.0, font, 85);

  dibujarTexto(page, data.ubicacion.direccion, 31.2, 391.0, 7.0, font, 390);
  dibujarTexto(page, data.ubicacion.telefonoCelular, 429.0, 391.0, 7.0, font, 70);
  dibujarTexto(page, data.ubicacion.telefonoFijo, 507.0, 391.0, 7.0, font, 72);

  dibujarTexto(page, data.ubicacion.email, 115.0, 366.0, 7.0, font, 165);
  dibujarTexto(page, data.ubicacion.twitter, 315.0, 366.0, 7.0, font, 100);
  dibujarTexto(page, data.ubicacion.facebook, 460.0, 366.0, 7.0, font, 120);

  // 6. Familiares (hasta 5 filas, cada una separada por 17.5 pt)
  const yFilasFamiliares = [320.0, 302.5, 285.0, 267.5, 250.0];
  data.familiares.slice(0, 5).forEach((fam, idx) => {
    const yRow = yFilasFamiliares[idx];
    if (yRow === undefined) return;
    dibujarTexto(page, fam.cedula, 31.2, yRow, 6.5, font, 74);
    dibujarTexto(page, fam.nombres, 110.0, yRow, 6.5, font, 76);
    dibujarTexto(page, fam.apellidos, 190.0, yRow, 6.5, font, 82);
    dibujarTexto(page, fam.fechaNac, 276.0, yRow, 6.5, font, 67);
    dibujarTexto(page, fam.genero, 357.0, yRow, 6.5, font, 20);
    dibujarTexto(page, fam.parentesco, 381.0, yRow, 6.5, font, 62);
    dibujarTexto(page, fam.diversidadFuncional, 446.0, yRow, 6.5, font, 71);
    dibujarTexto(page, fam.estadoCivil, 521.0, yRow, 6.5, font, 60);
  });

  // 7. Misiones (Matriz 5 columnas x 4 filas)
  const coordenadasMisiones: Array<{ xCheck: number; xDesde: number; y: number }> = [
    // Columna 1
    { xCheck: 32.0, xDesde: 95.2, y: 217.5 },  // Ribas
    { xCheck: 32.0, xDesde: 95.2, y: 203.5 },  // Mercal
    { xCheck: 32.0, xDesde: 95.2, y: 189.5 },  // Madres del Barrio
    { xCheck: 32.0, xDesde: 95.2, y: 175.5 },  // HÃ¡bitat
    // Columna 2
    { xCheck: 143.0, xDesde: 202.1, y: 217.5 }, // PIAR
    { xCheck: 143.0, xDesde: 202.1, y: 203.5 }, // Negra HipÃ³lita
    { xCheck: 143.0, xDesde: 202.1, y: 189.5 }, // Barrio Adentro
    { xCheck: 143.0, xDesde: 202.1, y: 175.5 }, // Miranda
    // Columna 3
    { xCheck: 254.0, xDesde: 321.7, y: 217.5 }, // Identidad
    { xCheck: 254.0, xDesde: 321.7, y: 203.5 }, // Casa de AlimentaciÃ³n
    { xCheck: 254.0, xDesde: 321.7, y: 189.5 }, // Guaicaipuro
    { xCheck: 254.0, xDesde: 321.7, y: 175.5 }, // Robinson I y II
    // Columna 4
    { xCheck: 365.0, xDesde: 432.7, y: 217.5 }, // Hijos de Vzla
    { xCheck: 365.0, xDesde: 432.7, y: 203.5 }, // Sucre
    { xCheck: 365.0, xDesde: 432.7, y: 189.5 }, // Vuelvan Caras
    { xCheck: 365.0, xDesde: 432.7, y: 175.5 }, // V.C. JÃ³venes
    // Columna 5
    { xCheck: 476.0, xDesde: 541.2, y: 217.5 }, // GM Vivienda
    { xCheck: 476.0, xDesde: 541.2, y: 203.5 }, // GM Agrovenezuela
    { xCheck: 476.0, xDesde: 541.2, y: 189.5 }, // GM Saber y Trabajo
    { xCheck: 476.0, xDesde: 541.2, y: 175.5 }, // Ninguna
  ];

  data.misiones.slice(0, 20).forEach((mis, idx) => {
    const coords = coordenadasMisiones[idx];
    if (coords && mis.marcada) {
      dibujarMarca(page, coords.xCheck, coords.y, 7.5, bold);
      if (mis.desde) {
        dibujarTexto(page, mis.desde, coords.xDesde, coords.y - 0.5, 6.0, font, 40);
      }
    }
  });

  // 8. FormaciÃ³n
  dibujarTexto(page, data.formacion.nivelEducativo, 31.2, 125.0, 7.0, font, 122);
  if (data.formacion.estadoAvance === 'CULMINO') dibujarMarca(page, 161.0, 129.5, 7.5, bold);
  if (data.formacion.estadoAvance === 'NO_COMPLETO') dibujarMarca(page, 202.0, 129.5, 7.5, bold);
  if (data.formacion.estadoAvance === 'EN_PROGRESO') dibujarMarca(page, 257.0, 129.5, 7.5, bold);
  dibujarTexto(page, data.formacion.ultimoAnio, 312.0, 125.0, 7.0, font, 130);
  dibujarTexto(page, data.formacion.especialidad, 448.0, 125.0, 7.0, font, 132);

  // 9. Otras Formaciones
  const descOtras = data.otrasFormaciones.map((o) => o.descripcion).filter(Boolean).join('; ');
  dibujarTexto(page, descOtras, 31.2, 86.0, 7.0, font, 550);

  // 10. Experiencias EmpÃ­ricas (Fila 1)
  const exp = data.experiencias[0];
  if (exp) {
    dibujarTexto(page, exp.area, 31.2, 36.0, 7.0, font, 133);
    dibujarTexto(page, exp.tiempoMeses, 170.0, 36.0, 7.0, font, 133);
    dibujarTexto(page, exp.portafolio ? 'SI' : 'NO', 309.0, 36.0, 7.0, font, 133);
    dibujarTexto(page, exp.enlace, 448.0, 36.0, 7.0, font, 133);
  }

  return await doc.save();
}
