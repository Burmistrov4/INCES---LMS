import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import type { SupabaseClient } from '@supabase/supabase-js';
import { crearRepositorios } from '../src/infra/repos-supabase.js';

const ID_ALUMNO = '22222222-2222-2222-2222-222222222222';

function crearClienteSupabaseFalso(): SupabaseClient {
  const aspirante = {
    datos_planilla: {
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
      proyecto: 'Curso de prueba',
      espacio_integral_socialista: 'INCES LA ISABELICA',
      horario: 'DIURNO',
    },
    cedula: 'V-12345678',
    nombres: 'Lorenzo Alexander',
    apellidos: 'Roca Burmistrow',
    email: 'alumno@ejemplo.com',
    fecha_nac: '2001-08-20',
    sexo: 'M',
    telefono: '04141234567',
    direccion: 'Direccion de prueba',
    nivel_educativo: 'BACHILLER',
    program_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    programs: { name: 'Curso de prueba' },
  };

  const campos = [
    {
      codigo: 'primer_nombre',
      etiqueta: '1er. Nombre',
      grupo: 'identidad',
      tipo: 'texto',
      obligatorio: true,
      orden: 1,
      opciones: null,
      fuente: null,
      condicion: null,
      ayuda: null,
    },
  ];

  const builder = (table: string) => {
    const state = {
      table,
      result: table === 'aspirantes'
        ? { data: aspirante, error: null }
        : { data: campos, error: null },
    };
    const chain: Record<string, unknown> = {};
    chain.select = () => chain;
    chain.eq = () => chain;
    chain.order = () => chain;
    chain.single = async () => state.result;
    chain.maybeSingle = async () => state.result;
    chain.then = (resolve: (value: unknown) => unknown) => Promise.resolve(state.result).then(resolve);
    return chain;
  };

  return {
    from: (table: string) => builder(table),
  } as unknown as SupabaseClient;
}

describe('PlanillaSupabase.generarPdf — composición oficial', () => {
  it('usa la entrada persistida y entrega el PDF institucional 612 × 792 de una página', async () => {
    const repos = crearRepositorios(crearClienteSupabaseFalso());
    const pdf = await repos.planilla.generarPdf(ID_ALUMNO);

    const doc = await PDFDocument.load(pdf);
    expect(doc.getPageCount()).toBe(1);
    expect(doc.getPage(0).getWidth()).toBe(612);
    expect(doc.getPage(0).getHeight()).toBe(792);
    expect(pdf.length).toBeGreaterThan(500_000);
  });
});
