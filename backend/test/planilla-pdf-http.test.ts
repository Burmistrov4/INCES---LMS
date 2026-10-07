import { afterEach, describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import {
  conToken,
  crearArnés,
  ID_ALUMNO,
  ID_ALUMNO_2,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
} from './support/arnes.js';

describe('HTTP de Planilla PDF — Alumno y Administrador', () => {
  afterEach(() => {
    // Cada prueba crea su propio Fastify y lo cierra explícitamente.
  });

  const planillaCompleta = {
    primer_nombre: 'Lorenzo',
    segundo_nombre: 'Alexander',
    primer_apellido: 'Roca',
    segundo_apellido: 'Burmistrow',
    cedula: 'V-12345678',
    nacionalidad: 'V',
    fecha_nac: '2001-08-20',
    sexo: 'M',
    estado_civil: 'SOLTERO',
    pueblo_indigena: false,
    discapacidad: false,
    estado: 'CARABOBO',
    municipio: 'VALENCIA',
    parroquia: 'RAFAEL URDANETA',
    comunidad: 'LA ISABELICA',
    direccion: 'Direccion de prueba',
    telefono: '04141234567',
    telefono_fijo: '02418321122',
    email: 'alumno@ejemplo.com',
    misiones: { RIBAS: '2017' },
    nivel_educativo: 'BACHILLER',
    nivel_avance: 'CULMINO',
    ultimo_anio: '5TO ANO',
    especialidad: 'CIENCIAS',
    otras_formaciones: 'Curso de prueba',
    experiencias: [{ area: 'SOLDADURA', meses: '12', portafolio: true, enlace: 'https://example.test' }],
  };

  it('Alumno descarga su propia planilla como PDF de una sola página', async () => {
    const arnes = crearArnés({ planillas: { [ID_ALUMNO]: planillaCompleta } });

    const respuesta = await arnes.app.inject({
      method: 'GET',
      url: '/api/v1/yo/planilla/pdf',
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-type']).toContain('application/pdf');
    expect(respuesta.headers['content-disposition']).toContain(`planilla-inscripcion-${ID_ALUMNO}.pdf`);

    const pdf = await PDFDocument.load(respuesta.rawPayload);
    expect(pdf.getPageCount()).toBe(1);
    expect(pdf.getPage(0).getWidth()).toBe(612);
    expect(pdf.getPage(0).getHeight()).toBe(792);
  });

  it('La ruta /yo no permite elegir otro usuario: no acepta usuarioId externo', async () => {
    const arnes = crearArnés({ planillas: { [ID_ALUMNO]: planillaCompleta } });

    const respuesta = await arnes.app.inject({
      method: 'GET',
      url: `/api/v1/yo/planilla/pdf?usuarioId=${ID_ALUMNO_2}`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-disposition']).toContain(`planilla-inscripcion-${ID_ALUMNO}.pdf`);
    // La ruta ignora cualquier usuarioId externo y toma SIEMPRE el ID de sesión.
  });

  it('Administrador puede descargar la planilla de un aspirante', async () => {
    const arnes = crearArnés({ planillas: { [ID_ALUMNO]: planillaCompleta } });

    const respuesta = await arnes.app.inject({
      method: 'GET',
      url: `/api/v1/inscripcion/planilla/${ID_ALUMNO}/pdf`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-type']).toContain('application/pdf');
    expect(respuesta.headers['content-disposition']).toContain(`planilla-inscripcion-${ID_ALUMNO}.pdf`);

    const pdf = await PDFDocument.load(respuesta.rawPayload);
    expect(pdf.getPageCount()).toBe(1);
    expect(pdf.getPage(0).getWidth()).toBe(612);
    expect(pdf.getPage(0).getHeight()).toBe(792);
  });

  it('Alumno no puede usar la ruta administrativa', async () => {
    const arnes = crearArnés({ planillas: { [ID_ALUMNO]: planillaCompleta } });

    const respuesta = await arnes.app.inject({
      method: 'GET',
      url: `/api/v1/inscripcion/planilla/${ID_ALUMNO}/pdf`,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
  });

  it('Administrador recibe 404 para un aspirante sin ficha', async () => {
    const arnes = crearArnés();

    const respuesta = await arnes.app.inject({
      method: 'GET',
      url: `/api/v1/inscripcion/planilla/${ID_ALUMNO_2}/pdf`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SIN_FICHA_DE_ASPIRANTE');
  });

  it('Petición anónima no puede descargar la planilla de ningún aspirante', async () => {
    const arnes = crearArnés({ planillas: { [ID_ALUMNO]: planillaCompleta } });

    const respuesta = await arnes.app.inject({
      method: 'GET',
      url: '/api/v1/yo/planilla/pdf',
    });

    expect(respuesta.statusCode).toBe(401);
  });
});
