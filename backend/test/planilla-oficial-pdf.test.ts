import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import { renderizarPlanillaOficialPdf, ANCHO_OFICIAL, ALTO_OFICIAL } from '../src/infra/planilla-oficial-pdf.js';
import { adaptarAPlanillaOficial } from '../src/infra/planilla-oficial-valores.js';
import type { EntradaPlanilla } from '../src/infra/planilla-valores.js';

describe('renderizador de la Planilla Oficial INCES (planilla-oficial-pdf.ts)', () => {
  const entradaBase: EntradaPlanilla = {
    cedula: 'V-20123456',
    nombres: 'LORENZO ALEXANDER',
    apellidos: 'ROCA BURMISTROV',
    email: 'lorenzo@example.com',
    campos: [],
    identidad: {},
    generadoEn: new Date('2026-10-05T15:00:00Z'),
    datosPlanilla: {
      primer_nombre: 'LORENZO',
      segundo_nombre: 'ALEXANDER',
      primer_apellido: 'ROCA',
      segundo_apellido: 'BURMISTROV',
      cedula: 'V-20123456',
      nacionalidad: 'Venezolano',
      fecha_nac: '2001-08-20',
      sexo: 'M',
      estado_civil: 'SOLTERO',
      pueblo_indigena: false,
      discapacidad: false,
      deporte: 'NATACIÃ“N Y AJEDREZ',
      deporte_desde: '2016',
      actividad_cultural: 'GUITARRA CLÃSICA',
      actividad_cultural_desde: '2019',
      organizacion_social: 'MOVIMIENTO ESTUDIANTIL',
      organizacion_social_desde: '2022',
      estado: 'CARABOBO',
      municipio: 'VALENCIA',
      parroquia: 'RAFAEL URDANETA',
      comunidad: 'LA ISABELICA',
      direccion: 'URB. LA ISABELICA, SECTOR 4, VEREDA 12, NÃšMERO 5',
      telefono: '04141234567',
      telefono_fijo: '02418321122',
      email: 'lorenzo@example.com',
      twitter: '@lorenzoroca',
      facebook: 'fb.com/lorenzoroca',
      misiones: {
        RIBAS: '2017',
        IDENTIDAD: '2015',
        ROBINSON_I_Y_II: '2016',
      },
      familiares: [
        {
          cedula: 'V-10111222',
          nombres: 'ALEXANDER',
          apellidos: 'ROCA',
          fecha_nac: '1968-04-12',
          genero: 'M',
          parentesco: 'PADRE',
          diversidad_funcional: 'NINGUNA',
          estado_civil: 'CASADO',
        },
        {
          cedula: 'V-11222333',
          nombres: 'ELENA',
          apellidos: 'BURMISTROVA',
          fecha_nac: '1970-11-25',
          genero: 'F',
          parentesco: 'MADRE',
          diversidad_funcional: 'NINGUNA',
          estado_civil: 'CASADA',
        },
      ],
      nivel_educativo: 'TÃ‰CNICO MEDIO',
      nivel_avance: 'CULMINO',
      ultimo_anio: '6TO AÃ‘O',
      especialidad: 'INFORMÃTICA',
      otras_formaciones: 'DIPLOMADO EN DESARROLLO DE SOFTWARE Y GESTIÃ“N DE BASES DE DATOS',
      experiencias: [
        {
          area: 'PROGRAMACIÃ“N FULL-STACK Y ARQUITECTURA',
          meses: '36',
          portafolio: true,
          enlace: 'https://github.com/Burmistrov4',
        },
      ],
    },
  };

  it('genera un PDF vÃ¡lido de exactamente 612 Ã— 792 pt (US Letter) y 1 sola pÃ¡gina', async () => {
    const data = adaptarAPlanillaOficial(entradaBase, {
      cabecera: {
        fecha: '05/10/2026',
        numeroPreimpreso: '009876',
        proyecto: 'SOLDADURA Y CONSTRUCCIÃ“N METÃLICA',
        espacioIntegralSocialista: 'CFS RAFAEL URDANETA',
        horario: 'LUNES A VIERNES 7:30 AM - 12:30 PM',
      },
    });

    const pdfBytes = await renderizarPlanillaOficialPdf(data);
    expect(pdfBytes).toBeInstanceOf(Uint8Array);
    expect(pdfBytes.length).toBeGreaterThan(1000);

    // Cargar con pdf-lib para verificar geometrÃ­a y estructura
    const doc = await PDFDocument.load(pdfBytes);
    expect(doc.getPageCount()).toBe(1);

    const page = doc.getPages()[0]!;
    expect(page.getWidth()).toBeCloseTo(ANCHO_OFICIAL, 1);
    expect(page.getHeight()).toBeCloseTo(ALTO_OFICIAL, 1);
  });

  it('soporta datos mÃ­nimos o vacÃ­os sin lanzar excepciones ni crear pÃ¡ginas adicionales', async () => {
    const entradaVacia: EntradaPlanilla = {
      cedula: null,
      nombres: null,
      apellidos: null,
      email: null,
      campos: [],
      identidad: {},
      generadoEn: new Date(),
      datosPlanilla: {},
    };

    const data = adaptarAPlanillaOficial(entradaVacia);
    const pdfBytes = await renderizarPlanillaOficialPdf(data);

    const doc = await PDFDocument.load(pdfBytes);
    expect(doc.getPageCount()).toBe(1);
    expect(doc.getPages()[0]!.getWidth()).toBe(612);
    expect(doc.getPages()[0]!.getHeight()).toBe(792);
  });

  it('sanea texto con caracteres fuera de Latin-1 y evita desbordes de pÃ¡gina', async () => {
    const entradaCaracteresRaros: EntradaPlanilla = {
      cedula: 'V-33333333',
      nombres: 'JOSÃ‰ MARÃA ðŸš€',
      apellidos: 'PEÃ‘A-Ã‘UÃ‘EZ',
      email: 'test@inces.gob.ve',
      campos: [],
      identidad: {},
      generadoEn: new Date(),
      datosPlanilla: {
        primer_nombre: 'JOSÃ‰ ðŸŒŸ',
        primer_apellido: 'PEÃ‘A',
        direccion: 'TEXTO EXTREMADAMENTE LARGO QUE EXCEDE CON MUCHA DIFERENCIA EL ANCHO ASIGNADO DE LA CASILLA '.repeat(10),
      },
    };

    const data = adaptarAPlanillaOficial(entradaCaracteresRaros);
    const pdfBytes = await renderizarPlanillaOficialPdf(data);

    const doc = await PDFDocument.load(pdfBytes);
    expect(doc.getPageCount()).toBe(1);
  });
});
