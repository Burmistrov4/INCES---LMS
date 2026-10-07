import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import type { EntradaPlanilla } from '../src/infra/planilla-valores.js';
import { renderizarPlanillaOficialDesdeEntrada } from '../src/infra/planilla-oficial-adaptador.js';

describe('adaptador de integración de la Planilla Oficial INCES', () => {
  it('compone EntradaPlanilla -> contrato oficial -> PDF institucional', async () => {
    const entrada: EntradaPlanilla = {
      cedula: 'V-20123456',
      nombres: 'Ana María',
      apellidos: 'Pérez González',
      email: 'ana@example.test',
      campos: [],
      datosPlanilla: {
        fecha_inscripcion: '2026-10-07',
        numero_preimpreso: '000123',
        proyecto: 'Soldadura Básica',
        primer_nombre: 'Ana',
        segundo_nombre: 'María',
        primer_apellido: 'Pérez',
        segundo_apellido: 'González',
        cedula: 'V-20123456',
        nacionalidad: 'V',
        fecha_nac: '2000-05-10',
        sexo: 'F',
        estado_civil: 'SOLTERA',
        pueblo_indigena: false,
        discapacidad: false,
        estado: 'Carabobo',
        municipio: 'San Diego',
        parroquia: 'San Diego',
        direccion: 'Dirección de prueba',
        telefono: '04140000000',
        email: 'ana@example.test',
        misiones: { RIBAS: '2025' },
        nivel_educativo: 'Bachiller',
        otras_formaciones: 'Curso de prueba',
        experiencias: [{ area: 'Soldadura', tiempo_meses: '12', portafolio: true }],
      },
      identidad: {
        cedula: 'V-20123456',
        email: 'ana@example.test',
        telefono: '04140000000',
        fecha_nac: '2000-05-10',
        sexo: 'F',
        direccion: 'Dirección de prueba',
        nivel_educativo: 'Bachiller',
        curso_seleccionado: 'Soldadura Básica',
        primer_nombre: 'Ana',
        primer_apellido: 'Pérez',
      },
      generadoEn: new Date('2026-10-07T20:00:00.000Z'),
    };

    const pdfBytes = await renderizarPlanillaOficialDesdeEntrada(entrada, {
      cabecera: {
        fecha: '07/10/2026',
        numeroPreimpreso: '000123',
        proyecto: 'Soldadura Básica',
        espacioIntegralSocialista: 'CFS RAFAEL URDANETA',
        horario: 'LUNES A VIERNES 7:30 AM - 12:30 PM',
      },
    });

    expect(pdfBytes).toBeInstanceOf(Uint8Array);
    expect(pdfBytes.length).toBeGreaterThan(1000);

    const doc = await PDFDocument.load(pdfBytes);
    expect(doc.getPageCount()).toBe(1);
    expect(doc.getPages()[0]!.getWidth()).toBe(612);
    expect(doc.getPages()[0]!.getHeight()).toBe(792);
  });
});
