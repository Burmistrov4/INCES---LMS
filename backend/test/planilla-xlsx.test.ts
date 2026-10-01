import type { FastifyInstance } from 'fastify';
import { inflateRawSync } from 'node:zlib';
import { afterEach, describe, expect, it } from 'vitest';
import type { CampoInscripcion, PlanillaInscripcion } from '../src/dominio/tipos.js';
import { renderizarPlanillaXlsx, TIPO_XLSX } from '../src/infra/planilla-xlsx.js';
import {
  CAMPOS_POR_DEFECTO,
  conToken,
  crearArnés,
  ID_ALUMNO,
  ID_ALUMNO_2,
  PERFIL_ALUMNO_2,
  PERFILES_POR_DEFECTO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
  TOKEN_ALUMNO_2,
} from './support/arnes.js';

/**
 * La planilla de inscripción en Excel **editable** (2026-09-30).
 *
 * Es la contraparte editable de `planilla-pdf.test.ts`, y fija el mismo
 * contrato: la ruta propia toma el id de la sesión, la de administrador lo toma
 * de la ruta y exige rol admin, el cuerpo es binario, y **el dato rellenado
 * llega a la celda** —no basta con que el archivo se genere.
 *
 * **Por qué hay un lector de ZIP aquí dentro.** Un `.xlsx` es un ZIP, y Node no
 * trae lector de ZIP. Sí trae `zlib`, y el directorio central de un ZIP dice
 * dónde empieza y cuánto ocupa cada entrada: con eso y `inflateRawSync` se lee
 * lo que hace falta. Se hace así —y no añadiendo una dependencia de lectura—
 * porque la prueba tiene que poder **decir qué se escribió**; una librería de
 * lectura sería otro componente que puede equivocarse en el mismo sentido que el
 * que se está probando, y entonces el verde no probaría nada.
 *
 * Se lee el **directorio central** y no la cabecera local de cada entrada: un
 * ZIP puede escribir los tamaños en un descriptor posterior (bit 3 de las
 * banderas) y entonces la cabecera local los lleva a cero. El directorio central
 * los tiene siempre.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

const RUTA_PROPIA = '/api/v1/yo/planilla/xlsx';
const rutaAdmin = (id: string) => `/api/v1/inscripcion/planilla/${id}/xlsx`;

/** Firma de una cabecera local de ZIP: `PK\x03\x04`. */
const FIRMA_LOCAL = 0x04034b50;
/** Firma de una entrada del directorio central: `PK\x01\x02`. */
const FIRMA_CENTRAL = 0x02014b50;
/** Firma del final del directorio central: `PK\x05\x06`. */
const FIRMA_EOCD = 0x06054b50;

/**
 * Todo el texto de un `.xlsx`, concatenado.
 *
 * Devuelve las entradas descomprimidas tal cual, sin interpretar el XML: para
 * afirmar «esta celda dice Lorenzo» basta con que la cadena esté en el libro, y
 * interpretar el formato sería volver a implementar la mitad de la librería que
 * se está probando.
 */
function textoDelXlsx(xlsx: Uint8Array): string {
  const buf = Buffer.from(xlsx);

  // 1. El final del directorio central, buscado desde atrás: es lo último del
  //    archivo y puede llevar un comentario detrás, así que no está en una
  //    posición fija.
  let eocd = -1;
  for (let i = buf.length - 22; i >= 0; i -= 1) {
    if (buf.readUInt32LE(i) === FIRMA_EOCD) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error('El archivo no tiene final de directorio central: no es un ZIP.');

  const total = buf.readUInt16LE(eocd + 10);
  let puntero = buf.readUInt32LE(eocd + 16);

  let salida = '';
  for (let n = 0; n < total; n += 1) {
    if (buf.readUInt32LE(puntero) !== FIRMA_CENTRAL) {
      throw new Error(`Entrada ${n} del directorio central sin firma: el ZIP está mal formado.`);
    }
    const metodo = buf.readUInt16LE(puntero + 10);
    const comprimido = buf.readUInt32LE(puntero + 20);
    const largoNombre = buf.readUInt16LE(puntero + 28);
    const largoExtra = buf.readUInt16LE(puntero + 30);
    const largoComentario = buf.readUInt16LE(puntero + 32);
    const offsetLocal = buf.readUInt32LE(puntero + 42);

    // El inicio de los datos hay que tomarlo de la cabecera LOCAL: su nombre y
    // su campo extra pueden medir distinto que los del directorio central.
    if (buf.readUInt32LE(offsetLocal) === FIRMA_LOCAL) {
      const nombreLocal = buf.readUInt16LE(offsetLocal + 26);
      const extraLocal = buf.readUInt16LE(offsetLocal + 28);
      const inicio = offsetLocal + 30 + nombreLocal + extraLocal;
      const datos = buf.subarray(inicio, inicio + comprimido);

      if (metodo === 0) salida += datos.toString('utf8');
      else if (metodo === 8) {
        try {
          salida += inflateRawSync(datos).toString('utf8');
        } catch {
          // Entrada ilegible: se ignora. Si el dato que se busca vivía ahí, la
          // aserción fallará —que es lo correcto—, en vez de dar un verde hueco.
        }
      }
    }

    puntero += 46 + largoNombre + largoExtra + largoComentario;
  }

  return salida;
}

function pedirPropio(token: string) {
  return app!.inject({ method: 'GET', url: RUTA_PROPIA, headers: conToken(token) });
}

describe('ruta propia GET /api/v1/yo/planilla/xlsx', () => {
  it('exige sesión: sin token es 401', async () => {
    app = crearArnés().app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_PROPIA });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
  });

  it('devuelve un libro de Excel válido, con su tipo MIME y su firma de ZIP', async () => {
    app = crearArnés().app;

    const respuesta = await pedirPropio(TOKEN_ALUMNO);

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-type']).toContain(TIPO_XLSX);
    // Un `.xlsx` es un ZIP: empieza por `PK`. Sin esta comprobación, un 200 con
    // un cuerpo vacío pasaría.
    expect(Buffer.from(respuesta.rawPayload).subarray(0, 2).toString('latin1')).toBe('PK');
    expect(textoDelXlsx(new Uint8Array(respuesta.rawPayload))).toContain(
      'PLANILLA DE INSCRIPCIÓN',
    );
    expect(respuesta.headers['content-disposition']).toContain(
      `planilla-inscripcion-${ID_ALUMNO}.xlsx`,
    );
  });

  it('escribe los valores rellenados, no sólo las etiquetas', async () => {
    // El mismo caso que la prueba del PDF, para poder comparar las dos salidas:
    // si ésta dijera otra cosa que el papel, aquí se vería.
    const planilla: PlanillaInscripcion = {
      primer_nombre: 'Lorenzo',
      primer_apellido: 'Roca',
      cedula: 'V-12345678',
      nacionalidad: 'V',
      misiones: { MISION_RIBAS: '2020' },
    };
    app = crearArnés({
      perfiles: [...PERFILES_POR_DEFECTO, PERFIL_ALUMNO_2],
      identidades: { [TOKEN_ALUMNO_2]: ID_ALUMNO_2 },
      planillas: { [ID_ALUMNO]: planilla },
    }).app;

    const respuesta = await pedirPropio(TOKEN_ALUMNO);
    const texto = textoDelXlsx(new Uint8Array(respuesta.rawPayload));

    expect(respuesta.statusCode).toBe(200);
    // `nacionalidad` se guarda como código y se lee como etiqueta: es el
    // formateador compartido con el PDF, y aquí se comprueba que de verdad se
    // aplica en la salida de Excel.
    expect(texto).toContain('Venezolano/a');
    expect(texto).toContain('Misión Ribas');
    expect(texto).toContain('2020');
    expect(texto).toContain('V-12345678');
  });

  it('un usuario sin ficha recibe 404, no un libro vacío', async () => {
    // El administrador no tiene fila en `aspirantes`, así que su planilla no existe.
    app = crearArnés().app;

    const respuesta = await pedirPropio(TOKEN_ADMIN);

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SIN_FICHA_DE_ASPIRANTE');
  });
});

describe('ruta de administrador GET /api/v1/inscripcion/planilla/:usuarioId/xlsx', () => {
  it('exige rol admin: un alumno recibe 403', async () => {
    app = crearArnés().app;

    const respuesta = await app.inject({
      method: 'GET',
      url: rutaAdmin(ID_ALUMNO),
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('SOLO_ADMIN');
  });

  it('el admin genera el Excel de un aspirante existente', async () => {
    app = crearArnés().app;

    const respuesta = await app.inject({
      method: 'GET',
      url: rutaAdmin(ID_ALUMNO),
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-type']).toContain(TIPO_XLSX);
    expect(Buffer.from(respuesta.rawPayload).subarray(0, 2).toString('latin1')).toBe('PK');
    expect(respuesta.headers['content-disposition']).toContain(
      `planilla-inscripcion-${ID_ALUMNO}.xlsx`,
    );
  });

  it('un UUID sin ficha devuelve 404 SIN_FICHA_DE_ASPIRANTE', async () => {
    app = crearArnés().app;

    const respuesta = await app.inject({
      method: 'GET',
      url: rutaAdmin('11111111-1111-1111-1111-111111111111'),
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SIN_FICHA_DE_ASPIRANTE');
  });
});

describe('renderizador de Excel (renderizarPlanillaXlsx)', () => {
  const base = {
    cedula: 'V-12345678',
    nombres: 'Lorenzo',
    apellidos: 'Roca',
    email: 'alumno@ejemplo.com',
    identidad: { cedula: 'V-12345678' } as Record<string, string | null>,
    generadoEn: new Date('2026-09-30T00:00:00Z'),
  };

  it('produce un libro válido y lleno a partir del catálogo y un jsonb relleno', async () => {
    const campos: CampoInscripcion[] = CAMPOS_POR_DEFECTO;
    const datosPlanilla: PlanillaInscripcion = {
      primer_nombre: 'Lorenzo',
      primer_apellido: 'Roca',
      cedula: 'V-12345678',
      nacionalidad: 'V',
      sexo: 'M',
    };

    const bytes = await renderizarPlanillaXlsx({ ...base, campos, datosPlanilla });
    const texto = textoDelXlsx(bytes);

    expect(Buffer.from(bytes).subarray(0, 2).toString('latin1')).toBe('PK');
    expect(texto).toContain('PLANILLA DE INSCRIPCIÓN');
    expect(texto).toContain('Lorenzo');
    expect(texto).toContain('Venezolano/a');
    // La fecha de emisión se formatea igual que en el PDF: `dd/mm/aaaa`.
    expect(texto).toContain('30/09/2026');
  });

  it('no revienta con un catálogo y un jsonb vacíos', async () => {
    const bytes = await renderizarPlanillaXlsx({
      ...base,
      campos: [],
      datosPlanilla: {},
    });

    expect(Buffer.from(bytes).subarray(0, 2).toString('latin1')).toBe('PK');
  });

  it('la misma llamada con distinto jsonb produce libros distintos (el dato llega)', async () => {
    // Es la aserción que impide que el renderizador devuelva una plantilla fija
    // con el mismo aspecto en los dos casos.
    const campos: CampoInscripcion[] = CAMPOS_POR_DEFECTO;
    const uno = await renderizarPlanillaXlsx({
      ...base,
      campos,
      datosPlanilla: { primer_nombre: 'Lorenzo' },
    });
    const dos = await renderizarPlanillaXlsx({
      ...base,
      campos,
      datosPlanilla: { primer_nombre: 'Sleither' },
    });

    expect(textoDelXlsx(uno)).toContain('Lorenzo');
    expect(textoDelXlsx(uno)).not.toContain('Sleither');
    expect(textoDelXlsx(dos)).toContain('Sleither');
  });
});
