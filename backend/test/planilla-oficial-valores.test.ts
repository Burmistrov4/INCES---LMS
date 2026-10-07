import { describe, expect, it } from 'vitest';
import { adaptarAPlanillaOficial, MISIONES_OFICIALES_ORDENADAS } from '../src/infra/planilla-oficial-valores.js';
import type { EntradaPlanilla } from '../src/infra/planilla-valores.js';

describe('adaptador semántico de la Planilla Oficial INCES', () => {
  it('contiene exactamente las 20 misiones oficiales en el orden del documento físico', () => {
    expect(MISIONES_OFICIALES_ORDENADAS).toHaveLength(20);
    expect(MISIONES_OFICIALES_ORDENADAS[0]?.codigo).toBe('RIBAS');
    expect(MISIONES_OFICIALES_ORDENADAS[19]?.codigo).toBe('NINGUNA');
  });

  it('adapta una entrada completa con desglose de nombres, fechas y casillas', () => {
    const entrada: EntradaPlanilla = {
      cedula: 'V-12345678',
      nombres: 'PEDRO JOSE',
      apellidos: 'PEREZ PEREZ',
      email: 'pedro.perez@inces.gob.ve',
      campos: [],
      identidad: {},
      generadoEn: new Date('2026-10-05T12:00:00Z'),
      datosPlanilla: {
        primer_nombre: 'PEDRO',
        segundo_nombre: 'JOSE',
        primer_apellido: 'PEREZ',
        segundo_apellido: 'PEREZ',
        cedula: 'V-12345678',
        nacionalidad: 'Venezolano',
        fecha_nac: '2000-05-15',
        sexo: 'M',
        estado_civil: 'SOLTERO',
        pueblo_indigena: true,
        pueblo_indigena_cual: 'WAYUU',
        discapacidad: true,
        tipo_discapacidad: 'FISICA MANO',
        deporte: 'FUTBOL',
        deporte_desde: '2015',
        actividad_cultural: 'MUSICA',
        actividad_cultural_desde: '2018',
        organizacion_social: 'CONSEJO COMUNAL',
        organizacion_social_desde: '2021',
        estado: 'CARABOBO',
        municipio: 'VALENCIA',
        parroquia: 'RAFAEL URDANETA',
        comunidad: 'LA ISABELICA',
        direccion: 'SECTOR 3, VEREDA 5, CASA 10',
        telefono: '04121234567',
        telefono_fijo: '02418345678',
        email: 'pedro.perez@inces.gob.ve',
        twitter: '@pedroperez',
        facebook: 'pedroperezfb',
        familiares: [
          {
            cedula: 'V-87654321',
            nombres: 'MARIA',
            apellidos: 'PEREZ',
            fecha_nac: '1975-01-20',
            genero: 'F',
            parentesco: 'MADRE',
            diversidad_funcional: 'NINGUNA',
            estado_civil: 'CASADA',
          },
        ],
        misiones: {
          RIBAS: '2018',
          SUCRE: '2020',
        },
        nivel_educativo: 'BACHILLER',
        nivel_avance: 'CULMINO',
        ultimo_anio: '5TO AÑO',
        especialidad: 'CIENCIAS',
        otras_formaciones: 'CURSO DE ELECTRICIDAD BASICA',
        experiencias: [
          {
            area: 'SOLDADURA ELECTRICA',
            meses: '24',
            portafolio: true,
            enlace: 'https://ejemplo.com/portafolio',
          },
        ],
      },
    };

    const oficial = adaptarAPlanillaOficial(entrada, {
      cabecera: {
        fecha: '05/10/2026',
        numeroPreimpreso: '001245',
        proyecto: 'SOLDADURA UNIVERSAL',
        espacioIntegralSocialista: 'TALLER 1',
        horario: '7:30 AM A 12:00 PM',
      },
    });

    // Cabecera
    expect(oficial.cabecera.fecha).toBe('05/10/2026');
    expect(oficial.cabecera.numeroPreimpreso).toBe('001245');
    expect(oficial.cabecera.proyecto).toBe('SOLDADURA UNIVERSAL');
    expect(oficial.cabecera.espacioIntegralSocialista).toBe('TALLER 1');
    expect(oficial.cabecera.horario).toBe('7:30 AM A 12:00 PM');

    // Identidad
    expect(oficial.identidad.primerNombre).toBe('PEDRO');
    expect(oficial.identidad.segundoNombre).toBe('JOSE');
    expect(oficial.identidad.primerApellido).toBe('PEREZ');
    expect(oficial.identidad.segundoApellido).toBe('PEREZ');
    expect(oficial.identidad.cedula).toBe('V-12345678');
    expect(oficial.identidad.nacionalidad).toBe('Venezolano');

    // Nacimiento
    expect(oficial.nacimiento.dia).toBe('15');
    expect(oficial.nacimiento.mes).toBe('05');
    expect(oficial.nacimiento.anio).toBe('2000');
    expect(oficial.nacimiento.edad).toBeGreaterThanOrEqual(25);

    // Demografía
    expect(oficial.sexo).toBe('M');
    expect(oficial.estadoCivil).toBe('SOLTERO');
    expect(oficial.puebloIndigena.pertenece).toBe(true);
    expect(oficial.puebloIndigena.cual).toBe('WAYUU');

    // Discapacidad
    expect(oficial.discapacidad.fisicaMano).toBe(true);
    expect(oficial.discapacidad.ninguna).toBe(false);

    // Prácticas
    expect(oficial.practicas.deporte.valor).toBe('FUTBOL');
    expect(oficial.practicas.deporte.desde).toBe('2015');

    // Familiares
    expect(oficial.familiares).toHaveLength(1);
    expect(oficial.familiares[0]?.parentesco).toBe('MADRE');

    // Misiones
    expect(oficial.misiones).toHaveLength(20);
    const ribas = oficial.misiones.find((m) => m.codigo === 'RIBAS');
    expect(ribas?.marcada).toBe(true);
    expect(ribas?.desde).toBe('2018');
    const sucre = oficial.misiones.find((m) => m.codigo === 'SUCRE');
    expect(sucre?.marcada).toBe(true);
    expect(sucre?.desde).toBe('2020');
    const mercal = oficial.misiones.find((m) => m.codigo === 'MERCAL');
    expect(mercal?.marcada).toBe(false);
    expect(mercal?.desde).toBeNull();

    // Formación y Experiencia
    expect(oficial.formacion.nivelEducativo).toBe('BACHILLER');
    expect(oficial.formacion.estadoAvance).toBe('CULMINO');
    expect(oficial.experiencias).toHaveLength(1);
    expect(oficial.experiencias[0]?.area).toBe('SOLDADURA ELECTRICA');
    expect(oficial.experiencias[0]?.portafolio).toBe(true);
  });

  it('respalda datos ausentes usando el objeto identidad', () => {
    const entrada: EntradaPlanilla = {
      cedula: 'V-99999999',
      nombres: 'ANA ELENA',
      apellidos: 'GOMEZ RUIZ',
      email: 'ana@example.com',
      campos: [],
      identidad: {
        primer_nombre: 'ANA',
        primer_apellido: 'GOMEZ',
        fecha_nac: '1995-12-01',
        sexo: 'F',
        direccion: 'AV. BOLIVAR NORTE',
        nivel_educativo: 'UNIVERSITARIO',
      },
      datosPlanilla: {},
      generadoEn: new Date(),
    };

    const oficial = adaptarAPlanillaOficial(entrada);

    expect(oficial.identidad.primerNombre).toBe('ANA');
    expect(oficial.identidad.primerApellido).toBe('GOMEZ');
    expect(oficial.identidad.cedula).toBe('V-99999999');
    expect(oficial.nacimiento.anio).toBe('1995');
    expect(oficial.sexo).toBe('F');
    expect(oficial.ubicacion.direccion).toBe('AV. BOLIVAR NORTE');
    expect(oficial.formacion.nivelEducativo).toBe('UNIVERSITARIO');
    expect(oficial.familiares).toEqual([]);
    expect(oficial.misiones).toHaveLength(20);
    expect(oficial.misiones.every((m) => !m.marcada)).toBe(true);
  });
});
