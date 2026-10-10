import { expect, test, type Page } from '@playwright/test';
import { AulaVirtualPage } from '../src/pages/AulaVirtualPage.js';
import {
  LoginPage,
  SENAL_DE_SESION_ALUMNO,
} from '../src/pages/LoginPage.js';

const ADMIN = process.env.E2E_ADMIN_EMAIL ?? '';
const ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD ?? '';
const DOCENTE = process.env.E2E_DOCENTE_EMAIL ?? '';
const DOCENTE_PASSWORD = process.env.E2E_DOCENTE_PASSWORD ?? '';
const ALUMNO = process.env.E2E_ALUMNO_EMAIL ?? '';
const ALUMNO_PASSWORD = process.env.E2E_ALUMNO_PASSWORD ?? '';
const SECCION = process.env.E2E_SECCION ?? '';

type MedicionRed = {
  metodo: string;
  ruta: string;
  estado: number;
  ms: number | null;
};

function instrumentarRed(page: Page): MedicionRed[] {
  const mediciones: MedicionRed[] = [];
  const inicioPorSolicitud = new WeakMap<object, number>();
  page.on('request', (request) => inicioPorSolicitud.set(request, Date.now()));
  page.on('response', (response) => {
    let url: URL;
    try {
      url = new URL(response.url());
    } catch {
      return;
    }

    // Sólo rutas y metadatos: nunca query strings, headers, cuerpos ni credenciales.
    if (!url.pathname.startsWith('/api/v1/') && !url.pathname.startsWith('/auth/v1/')) return;
    const solicitud = response.request();
    const inicio = inicioPorSolicitud.get(solicitud);
    mediciones.push({
      metodo: solicitud.method(),
      ruta: url.pathname,
      estado: response.status(),
      // Tiempo aproximado hasta recibir headers/respuesta, medido en el navegador.
      ms: inicio === undefined ? null : Date.now() - inicio,
    });
  });
  return mediciones;
}

async function recursosFlutter(page: Page) {
  return page.evaluate(() =>
    performance
      .getEntriesByType('resource')
      .filter((entry) => /main\.dart\.js|flutter_bootstrap\.js|canvaskit.*\.wasm/.test(entry.name))
      .map((entry) => {
        const recurso = entry as PerformanceResourceTiming;
        return {
          recurso: new URL(recurso.name).pathname,
          duracionMs: Math.round(recurso.duration),
          transferenciaBytes: recurso.transferSize || null,
        };
      }),
  );
}

function emitirResultado(
  rol: string,
  etapas: Record<string, number>,
  red: MedicionRed[],
  recursos: unknown,
) {
  console.log(
    'PERF_BASELINE ' +
      JSON.stringify({
        rol,
        fecha: new Date().toISOString(),
        etapasMs: etapas,
        peticionesApi: red,
        recursosFlutter: recursos,
      }),
  );
}

test.describe('Baseline de performance por rol (sólo lectura)', () => {
  test.skip(
    process.env.E2E_MEDIR_PERFORMANCE !== '1',
    'Opt-in: definir E2E_MEDIR_PERFORMANCE=1 para ejecutar mediciones.',
  );

  test('administrador: arranque, login y Usuarios y Roles', async ({ page }) => {
    test.skip(ADMIN === '' || ADMIN_PASSWORD === '', 'Faltan credenciales E2E de administrador.');
    const red = instrumentarRed(page);
    const etapas: Record<string, number> = {};
    let t = Date.now();
    const login = new LoginPage(page);
    await login.abrir();
    etapas.arranqueFlutter = Date.now() - t;

    t = Date.now();
    await login.entrar(ADMIN, ADMIN_PASSWORD);
    etapas.loginHastaPanel = Date.now() - t;
    const recursos = await recursosFlutter(page);

    t = Date.now();
    await login.app.pulsarReal('Usuarios y Roles', { tiempoLimiteMs: 15_000 });
    await expect
      .poll(async () => login.app.campo('Buscar usuario').count(), { timeout: 30_000 })
      .toBeGreaterThan(0);
    await expect.poll(async () => login.app.cuantos('Cambiar rol'), { timeout: 30_000 }).toBeGreaterThan(0);
    etapas.usuariosYRoles = Date.now() - t;

    emitirResultado('administrador', etapas, red, recursos);
  });

  test('docente: arranque, login y apertura de Mis Aulas', async ({ page }) => {
    test.skip(DOCENTE === '' || DOCENTE_PASSWORD === '', 'Faltan credenciales E2E de docente.');
    test.skip(SECCION === '', 'Falta E2E_SECCION.');
    const red = instrumentarRed(page);
    const etapas: Record<string, number> = {};
    let t = Date.now();
    const login = new LoginPage(page);
    await login.abrir();
    etapas.arranqueFlutter = Date.now() - t;

    t = Date.now();
    await login.entrar(DOCENTE, DOCENTE_PASSWORD, 'Mis aulas');
    etapas.loginHastaPanel = Date.now() - t;

    const aula = new AulaVirtualPage(page);
    t = Date.now();
    await aula.irAMisAulas(SECCION);
    etapas.solicitudMiHorario = Date.now() - t;

    t = Date.now();
    await aula.contarTarjetas(SECCION);
    etapas.renderTarjetaAula = Date.now() - t;

    t = Date.now();
    await aula.abrirAula(SECCION);
    etapas.abrirAulaYRespuesta = Date.now() - t;

    t = Date.now();
    await aula.esperarAula();
    etapas.montajeAula = Date.now() - t;

    t = Date.now();
    await aula.abrirPestana('Trabajo de Clase', 'Nueva tarea');
    etapas.trabajoDeClase = Date.now() - t;

    emitirResultado('docente', etapas, red, await recursosFlutter(page));
  });

  test('aprendiz: arranque, login y apertura de Aula Virtual', async ({ page }) => {
    test.skip(ALUMNO === '' || ALUMNO_PASSWORD === '', 'Faltan credenciales E2E de aprendiz.');
    test.skip(SECCION === '', 'Falta E2E_SECCION.');
    const red = instrumentarRed(page);
    const etapas: Record<string, number> = {};
    let t = Date.now();
    const login = new LoginPage(page);
    await login.abrir();
    etapas.arranqueFlutter = Date.now() - t;

    t = Date.now();
    await login.entrar(ALUMNO, ALUMNO_PASSWORD, SENAL_DE_SESION_ALUMNO);
    etapas.loginHastaPanel = Date.now() - t;

    const aula = new AulaVirtualPage(page);
    t = Date.now();
    await aula.irAMisAulas(SECCION);
    etapas.solicitudMiHorario = Date.now() - t;

    t = Date.now();
    await aula.contarTarjetas(SECCION);
    etapas.renderTarjetaAula = Date.now() - t;

    t = Date.now();
    await aula.abrirAula(SECCION);
    etapas.abrirAulaYRespuesta = Date.now() - t;

    t = Date.now();
    await aula.esperarAula();
    etapas.montajeAula = Date.now() - t;

    emitirResultado('aprendiz', etapas, red, await recursosFlutter(page));
  });
});
