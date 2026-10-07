import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import {
  conToken,
  crearArnés,
  ID_ALUMNO,
  TOKEN_ALUMNO,
  type Arnés,
} from './support/arnes.js';

let app: FastifyInstance | null = null;
let arnes: Arnés | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
  arnes = null;
});

const RUTA_ENVIAR = '/api/v1/yo/planilla/enviar';
const RUTA_REENVIAR = '/api/v1/yo/planilla/reenviar';
const RUTA_VERSIONES = '/api/v1/yo/planilla/versiones';
const PLANILLA_COMPLETA = {
  primer_nombre: 'Lorenzo',
  primer_apellido: 'Roca',
  cedula: 'V-12345678',
  nacionalidad: 'V',
};

function iniciar(planilla: Record<string, unknown> = PLANILLA_COMPLETA) {
  arnes = crearArnés({ planillas: { [ID_ALUMNO]: planilla } });
  app = arnes.app;
}

async function enviar() {
  return app!.inject({
    method: 'POST',
    url: RUTA_ENVIAR,
    headers: conToken(TOKEN_ALUMNO),
  });
}

async function versiones() {
  return app!.inject({
    method: 'GET',
    url: RUTA_VERSIONES,
    headers: conToken(TOKEN_ALUMNO),
  });
}

describe('workflow de envío de planilla', () => {
  it('envía una planilla completa y crea exactamente una versión ENVIADA', async () => {
    iniciar();

    const respuesta = await enviar();

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().version.estado).toBe('ENVIADA');
    expect(respuesta.json().version.numero).toBe(1);

    const historial = await versiones();
    expect(historial.statusCode).toBe(200);
    expect(historial.json().versiones).toHaveLength(1);
  });

  it('rechaza una planilla incompleta y no crea versión', async () => {
    iniciar({ primer_nombre: 'Lorenzo' });

    const respuesta = await enviar();

    expect(respuesta.statusCode).toBe(422);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_INCOMPLETA');

    const historial = await versiones();
    expect(historial.json().versiones).toHaveLength(0);
  });

  it('rechaza una planilla vacía y no crea versión', async () => {
    iniciar({});

    const respuesta = await enviar();

    expect(respuesta.statusCode).toBe(422);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_INCOMPLETA');

    const historial = await versiones();
    expect(historial.json().versiones).toHaveLength(0);
  });

  it('permite reenviar una planilla completa después de OBSERVADA y toma el snapshot actual', async () => {
    iniciar();

    const primera = await enviar();
    const versionId = primera.json().version.id;
    const observar = await app!.inject({
      method: 'POST',
      url: `/api/v1/inscripcion/planilla/${versionId}/observar`,
      headers: conToken('token-admin'),
      payload: { motivo: 'Corrija el dato indicado.' },
    });

    expect(observar.statusCode).toBe(200);

    const segunda = await app!.inject({
      method: 'POST',
      url: RUTA_REENVIAR,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(segunda.statusCode).toBe(200);
    expect(segunda.json().version.estado).toBe('REENVIADA');
    expect(segunda.json().version.numero).toBe(2);
    expect(segunda.json().version.datosSnapshot).toEqual(PLANILLA_COMPLETA);
  });

  it('rechaza reenviar una planilla incompleta y no crea una segunda versión', async () => {
    iniciar();

    const primera = await enviar();
    const versionId = primera.json().version.id;
    const observar = await app!.inject({
      method: 'POST',
      url: `/api/v1/inscripcion/planilla/${versionId}/observar`,
      headers: conToken('token-admin'),
      payload: { motivo: 'Corrija el dato indicado.' },
    });
    expect(observar.statusCode).toBe(200);

    arnes!.estado.planillas[ID_ALUMNO] = { primer_nombre: 'Lorenzo' };

    const segunda = await app!.inject({
      method: 'POST',
      url: RUTA_REENVIAR,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(segunda.statusCode).toBe(422);
    expect(segunda.json().error.codigo).toBe('PLANILLA_INCOMPLETA');

    const historial = await versiones();
    expect(historial.json().versiones).toHaveLength(1);
    expect(historial.json().versiones[0].estado).toBe('OBSERVADA');
  });

  it('bloquea reenviar si la última versión no está OBSERVADA', async () => {
    iniciar();

    await enviar();

    const respuesta = await app!.inject({
      method: 'POST',
      url: RUTA_REENVIAR,
      headers: conToken(TOKEN_ALUMNO),
    });

    expect(respuesta.statusCode).toBe(409);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_NO_OBSERVADA');
  });

  it('la traducción de la validación canónica conserva los códigos faltantes', async () => {
    iniciar({ primer_nombre: 'Lorenzo' });

    const respuesta = await enviar();

    expect(respuesta.statusCode).toBe(422);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_INCOMPLETA');
    expect(respuesta.json().error.mensaje).toContain('primer_apellido');
    expect(respuesta.json().error.mensaje).toContain('cedula');
    expect(respuesta.json().error.mensaje).toContain('nacionalidad');
  });
});
