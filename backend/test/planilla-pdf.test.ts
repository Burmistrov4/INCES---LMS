import type { FastifyInstance } from 'fastify';
import { inflateSync } from 'node:zlib';
import { afterEach, describe, expect, it } from 'vitest';
import { renderizarPlanillaPdf } from '../src/infra/planilla-pdf.js';
import type { CampoInscripcion, PlanillaInscripcion } from '../src/dominio/tipos.js';
import {
  conToken,
  crearArnés,
  CAMPOS_POR_DEFECTO,
  ID_ALUMNO,
  ID_ALUMNO_2,
  PERFIL_ALUMNO_2,
  PERFILES_POR_DEFECTO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
  TOKEN_ALUMNO_2,
} from './support/arnes.js';

/**
 * La generación de la planilla de inscripción del INCES en PDF (Fase 3).
 *
 * Lo que se fija aquí es el **contrato HTTP** del endpoint y que el renderizador
 * produce un PDF válido y **lleno**. Tres decisiones que conviene clavar:
 *
 * 1. **La ruta propia exige sesión y toma el id de la sesión**, igual que
 *    `PUT /api/v1/yo/planilla`: nadie imprime la planilla de otro por aquí.
 * 2. **La ruta de administrador toma un UUID en la ruta y exige rol admin**: es
 *    quien sí puede generar la planilla de cualquier aspirante (impresión masiva,
 *    mostrador). La RLS `aspirantes_admin_all` es la que autoriza leer la fila.
 * 3. **El contenido es binario `application/pdf`** y empieza por `%PDF`: es lo
 *    que el frontend necesita para descargarlo, y lo que distingue esta ruta de
 *    las que devuelven JSON.
 *
 * `pdf-lib` comprime los flujos de contenido (FlateDecode), así que el texto
 * pintado no está en claro en los bytes: para afirmar qué se imprimió se
 * descomprime cada flujo con `zlib.inflateSync` y se busca en el resultado.
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

const RUTA_PROPIA = '/api/v1/yo/planilla/pdf';
const rutaAdmin = (id: string) => `/api/v1/inscripcion/planilla/${id}/pdf`;

/** Descomprime los flujos de un PDF y devuelve el texto pintado en claro. */
function textoDelPdf(pdf: Uint8Array): string {
  const latin1 = Buffer.from(pdf).toString('latin1');
  const flujos = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
  let salida = '';
  let m: RegExpExecArray | null;
  while ((m = flujos.exec(latin1)) !== null) {
    try {
      let out = inflateSync(Buffer.from(m[1] ?? '', 'latin1')).toString('latin1');
      // `pdf-lib` escribe el texto como cadenas hexadecimales `<...> Tj`; las
      // decodificamos a caracteres para poder buscar el contenido en claro.
      out = out.replace(/<([0-9A-Fa-f]+)>/g, (_t, hex: string) => {
        let texto = '';
        for (let i = 0; i < hex.length; i += 2) {
          texto += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16));
        }
        return texto;
      });
      salida += out;
    } catch {
      // Flujo no comprimido o con otro filtro: lo ignoramos.
    }
  }
  return salida;
}

function pedirPropio(token: string) {
  return app!.inject({ method: 'GET', url: RUTA_PROPIA, headers: conToken(token) });
}

describe('ruta propia GET /api/v1/yo/planilla/pdf', () => {
  it('exige sesión: sin token es 401', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_PROPIA });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
  });

  it('devuelve un PDF válido (application/pdf que empieza por %PDF)', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await pedirPropio(TOKEN_ALUMNO);

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-type']).toMatch(/application\/pdf/);
    const bytes = Buffer.from(respuesta.rawPayload);
    expect(bytes.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(textoDelPdf(new Uint8Array(bytes))).toContain('PLANILLA DE INSCRIPCION');
    expect(respuesta.headers['content-disposition']).toContain(`planilla-inscripcion-${ID_ALUMNO}.pdf`);
  });

  it('imprime los valores rellenados, no sólo las etiquetas', async () => {
    // El arnés arranca con la ficha vacía; aquí la sembramos para probar el
    // pintado de un valor real (nacionalidad -> "Venezolano/a", misión marcada).
    const planilla: PlanillaInscripcion = {
      primer_nombre: 'Lorenzo',
      primer_apellido: 'Roca',
      cedula: 'V-12345678',
      nacionalidad: 'V',
      misiones: { MISION_RIBAS: '2020' },
    };
    const arnés = crearArnés({
      perfiles: [...PERFILES_POR_DEFECTO, PERFIL_ALUMNO_2],
      identidades: { [TOKEN_ALUMNO_2]: ID_ALUMNO_2 },
      planillas: { [ID_ALUMNO]: planilla },
    });
    app = arnés.app;

    const respuesta = await pedirPropio(TOKEN_ALUMNO);
    const texto = textoDelPdf(new Uint8Array(respuesta.rawPayload));

    expect(respuesta.statusCode).toBe(200);
    expect(texto).toContain('Venezolano/a');
    expect(texto).toContain('Misión Ribas');
    expect(texto).toContain('2020');
  });

  it('un usuario sin ficha recibe 404, no un PDF vacío', async () => {
    // El administrador no tiene fila en `aspirantes`, así que su propio PDF no existe.
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await pedirPropio(TOKEN_ADMIN);

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SIN_FICHA_DE_ASPIRANTE');
  });
});

describe('ruta de administrador GET /api/v1/inscripcion/planilla/:usuarioId/pdf', () => {
  it('exige rol admin: un alumno recibe 403', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: rutaAdmin(ID_ALUMNO),
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('SOLO_ADMIN');
  });

  it('el admin genera el PDF de un aspirante existente', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: rutaAdmin(ID_ALUMNO),
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.headers['content-type']).toMatch(/application\/pdf/);
    const bytes = Buffer.from(respuesta.rawPayload);
    expect(bytes.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(textoDelPdf(new Uint8Array(bytes))).toContain('PLANILLA DE INSCRIPCION');
    expect(respuesta.headers['content-disposition']).toContain(`planilla-inscripcion-${ID_ALUMNO}.pdf`);
  });

  it('un UUID sin ficha devuelve 404 SIN_FICHA_DE_ASPIRANTE', async () => {
    const arnés = crearArnés();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: rutaAdmin('11111111-1111-1111-1111-111111111111'),
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SIN_FICHA_DE_ASPIRANTE');
  });
});

describe('renderizador de PDF (renderizarPlanillaPdf)', () => {
  it('produce un PDF válido y lleno a partir del catálogo y un jsonb relleno', async () => {
    const campos: CampoInscripcion[] = CAMPOS_POR_DEFECTO;
    const datosPlanilla: PlanillaInscripcion = {
      primer_nombre: 'Lorenzo',
      nacionalidad: 'V',
      discapacidad: true,
      misiones: { MISION_RIBAS: '2020' },
    };

    const pdf = await renderizarPlanillaPdf({
      cedula: 'V-12345678',
      nombres: 'Lorenzo',
      apellidos: 'Roca',
      email: 'lorenzo@ejemplo.com',
      campos,
      datosPlanilla,
      identidad: { cedula: 'V-12345678', primer_nombre: 'Lorenzo' },
      generadoEn: new Date('2026-09-26T00:00:00Z'),
    });

    const texto = textoDelPdf(pdf);
    expect(pdf instanceof Uint8Array).toBe(true);
    // El header `%PDF-` vive fuera de los flujos comprimidos; por eso se lee de los
    // bytes en claro y no del texto descomprimido.
    expect(Buffer.from(pdf).subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(texto).toContain('PLANILLA DE INSCRIPCION');
    expect(texto).toContain('Venezolano/a');
    expect(texto).toContain('Si'); // discapacidad = true
    expect(texto).toContain('Misión Ribas');
    expect(texto).toContain('2020');
  });

  it('no revienta con un catálogo y un jsonb vacíos', async () => {
    const pdf = await renderizarPlanillaPdf({
      cedula: null,
      nombres: null,
      apellidos: null,
      email: null,
      campos: [],
      datosPlanilla: {},
      identidad: {},
      generadoEn: new Date('2026-09-26T00:00:00Z'),
    });

    expect(Buffer.from(pdf).subarray(0, 5).toString('latin1')).toBe('%PDF-');
  });

  it('la misma llamada con distinto jsonb produce PDFs distintos (el dato llega al papel)', async () => {
    const base = {
      cedula: 'V-1' as string | null,
      nombres: 'A' as string | null,
      apellidos: 'B' as string | null,
      email: 'a@b.com' as string | null,
      campos: CAMPOS_POR_DEFECTO,
      identidad: { cedula: 'V-1' as string | null },
      generadoEn: new Date('2026-09-26T00:00:00Z'),
    };
    const vacio = await renderizarPlanillaPdf({ ...base, datosPlanilla: {} });
    const lleno = await renderizarPlanillaPdf({
      ...base,
      datosPlanilla: { nacionalidad: 'V', discapacidad: true },
    });

    expect(Buffer.from(vacio).equals(Buffer.from(lleno))).toBe(false);
    expect(textoDelPdf(lleno)).toContain('Venezolano/a');
  });
});
