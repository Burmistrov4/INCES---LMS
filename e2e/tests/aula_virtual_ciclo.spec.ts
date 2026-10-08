import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { AulaVirtualPage, PESTANA_TRABAJO } from '../src/pages/AulaVirtualPage.js';
import { LoginPage, SENAL_DE_SESION_ALUMNO } from '../src/pages/LoginPage.js';

const DOCENTE = process.env.E2E_DOCENTE_EMAIL ?? '';
const CLAVE_DOCENTE = process.env.E2E_DOCENTE_PASSWORD ?? '';
const ALUMNO = process.env.E2E_ALUMNO_EMAIL ?? '';
const CLAVE_ALUMNO = process.env.E2E_ALUMNO_PASSWORD ?? '';
const SECCION = process.env.E2E_SECCION ?? '';

const TAREA_E2E = `Tarea E2E [ciclo] ${Date.now()}`;
const EXCLUSIVO_DE_TRABAJO = 'Nueva tarea';

test.describe.serial('Ciclo de la Tarea — docente y aprendiz', () => {
  let ctxDocente: BrowserContext;
  let pgDocente: Page;
  let tareaId = '';
  let estudianteId = '';
  let ctxCalificador: BrowserContext;
  let pgCalificador: Page;

  test.beforeAll(async ({ browser }) => {
    test.skip(
      DOCENTE === '' || CLAVE_DOCENTE === '' || ALUMNO === '' || CLAVE_ALUMNO === '',
      'Faltan E2E_DOCENTE_* o E2E_ALUMNO_*.',
    );
    test.skip(SECCION === '', 'Falta E2E_SECCION.');

    ctxDocente = await browser.newContext();
    pgDocente = await ctxDocente.newPage();

    const login = new LoginPage(pgDocente);
    await login.abrir();
    await login.entrar(DOCENTE, CLAVE_DOCENTE, 'Mis aulas');
  });

  test.afterAll(async () => {
    await ctxDocente?.close();
    await ctxCalificador?.close();
  });

  async function abrirTrabajoDocente(esperarTarea = true): Promise<AulaVirtualPage> {
    const aula = new AulaVirtualPage(pgDocente);
    await aula.irAMisAulas();
    await aula.abrirAula(SECCION);
    await aula.esperarAula();
    await aula.abrirPestana(PESTANA_TRABAJO, EXCLUSIVO_DE_TRABAJO);
    if (esperarTarea) {
      await expect
        .poll(async () => await aula.cuantos(TAREA_E2E), {
          timeout: 30_000,
          message: `«${TAREA_E2E}» todavía no aparece en Trabajo de Clase.\n${await aula.diagnostico()}`,
        })
        .toBeGreaterThan(0);
    }
    return aula;
  }

  async function pulsarBotonDeFila(
    aula: AulaVirtualPage,
    idEstudiante: string,
    textoBoton: string,
  ): Promise<void> {
    const nodos = await aula.app.nodos();
    const fila = nodos.find((n) => n.etiqueta === idEstudiante);
    if (!fila) {
      throw new Error(
        `No se encontró la fila del estudiante «${idEstudiante}».\\n${await aula.diagnostico()}`,
      );
    }

    const centroY = fila.y + fila.alto / 2;
    const candidatos = nodos.filter(
      (n) =>
        n.rol === 'button' &&
        n.etiqueta.toLowerCase().includes(textoBoton.toLowerCase()),
    );
    const boton = candidatos.sort(
      (a, b) =>
        Math.abs(a.y + a.alto / 2 - centroY) -
        Math.abs(b.y + b.alto / 2 - centroY),
    )[0];

    if (!boton) {
      throw new Error(
        `No se encontró «${textoBoton}» para la fila «${idEstudiante}».\\n${await aula.diagnostico()}`,
      );
    }

    const indice = candidatos.findIndex((n) => n === boton);
    await aula.app.pulsar(textoBoton, {
      ignorarMayusculas: true,
      indice,
    });
  }

  async function idUsuarioAutenticado(page: Page): Promise<string> {
    const id = await page.evaluate(() => {
      const key = Object.keys(localStorage).find(
        (k) => k.startsWith('sb-') && k.endsWith('-auth-token'),
      );
      if (!key) return '';
      const raw = localStorage.getItem(key);
      if (!raw) return '';
      try {
        const sesion = JSON.parse(raw);
        return sesion?.user?.id ?? '';
      } catch {
        return '';
      }
    });
    expect(id).toMatch(/^[0-9a-f-]{36}$/i);
    return id;
  }

  test('C1 — el docente entra y abre Trabajo de Clase', async () => {
    await abrirTrabajoDocente(false);
  });

  test('C2 — crea y publica su propia tarea', async () => {
    const aula = new AulaVirtualPage(pgDocente);

    await aula.app.pulsarReal(EXCLUSIVO_DE_TRABAJO, { ignorarMayusculas: true });
    await expect
      .poll(async () => await aula.cuantos('Crear y publicar'), {
        timeout: 20_000,
        message: `el modal de creación no montó.\\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);

    await aula.app.escribirEn('Título', TAREA_E2E);

    const creacion = pgDocente.waitForResponse(
      (r) => r.url().includes('/aula/') && r.request().method() === 'POST',
      { timeout: 30_000 },
    );
    await aula.app.pulsar('Crear y publicar', { ignorarMayusculas: true });
    const r = await creacion;
    expect(r.status()).toBeLessThan(300);

    const body = await r.json();
    tareaId = body?.tarea?.id ?? '';
    expect(tareaId).toMatch(/^[0-9a-f-]{36}$/i);

    await expect
      .poll(async () => await aula.cuantos(TAREA_E2E), { timeout: 25_000 })
      .toBeGreaterThan(0);

    await aula.app.pulsarReal('Listo', { ignorarMayusculas: true });
  });

  test('C5 — el aprendiz abre exactamente la tarea creada', async ({ browser }) => {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    try {
      const login = new LoginPage(page);
      await login.abrir();
      await login.entrar(ALUMNO, CLAVE_ALUMNO, SENAL_DE_SESION_ALUMNO);

      const aula = new AulaVirtualPage(page);
      await aula.irAMisAulas();
      await aula.abrirAula(SECCION);
      await aula.esperarAula();
      await aula.app.pulsarPestana(PESTANA_TRABAJO, { ignorarMayusculas: true });

      await expect
        .poll(async () => await aula.cuantos(TAREA_E2E), { timeout: 30_000 })
        .toBeGreaterThan(0);

      await aula.app.pulsarReal(TAREA_E2E, { exacto: false });
      await expect
        .poll(async () => await aula.cuantos('Entregar tarea'), { timeout: 20_000 })
        .toBeGreaterThan(0);
    } finally {
      await ctx.close();
    }
  });

  test('C6 — el aprendiz entrega la tarea', async ({ browser }) => {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    try {
      const login = new LoginPage(page);
      await login.abrir();
      await login.entrar(ALUMNO, CLAVE_ALUMNO, SENAL_DE_SESION_ALUMNO);

      const aula = new AulaVirtualPage(page);
      estudianteId = await idUsuarioAutenticado(page);
      await aula.irAMisAulas();
      await aula.abrirAula(SECCION);
      await aula.esperarAula();

      await aula.app.pulsarPestana(PESTANA_TRABAJO, { ignorarMayusculas: true });
      await expect.poll(async () => await aula.cuantos(TAREA_E2E), { timeout: 30_000 }).toBeGreaterThan(0);
      await aula.app.pulsarReal(TAREA_E2E, { exacto: false });
      await expect.poll(async () => await aula.cuantos('Entregar tarea'), { timeout: 20_000 }).toBeGreaterThan(0);

      const entrega = page.waitForResponse(
        (r) =>
          r.url().includes('/api/v1/aula/entregas/') &&
          r.url().endsWith('/entregar') &&
          r.request().method() === 'POST',
        { timeout: 30_000 },
      );
      await aula.app.pulsarReal('Entregar tarea', { ignorarMayusculas: true });
      const entregaResponse = await entrega;
      expect(entregaResponse.status()).toBe(200);

      await expect
        .poll(async () => await aula.cuantos('Entregada.'), { timeout: 20_000 })
        .toBeGreaterThan(0);
    } finally {
      await ctx.close();
    }
  });

  test('C7 — el docente abre el libro de la tarea entregada', async ({ browser }) => {
    ctxCalificador = await browser.newContext();
    pgCalificador = await ctxCalificador.newPage();

    const login = new LoginPage(pgCalificador);
    await login.abrir();
    await login.entrar(DOCENTE, CLAVE_DOCENTE, 'Mis aulas');

    const aula = new AulaVirtualPage(pgCalificador);
    await aula.irAMisAulas();
    await aula.abrirAula(SECCION);
    await aula.esperarAula();
    await aula.app.pulsarPestana(PESTANA_TRABAJO, { ignorarMayusculas: true });
    await expect.poll(async () => await aula.cuantos('Calificar'), { timeout: 30_000 }).toBeGreaterThan(0);

    await aula.app.pulsarReal('Calificar', { ignorarMayusculas: true });

    await expect
      .poll(async () => await aula.cuantos('LIBRO DE CALIFICACIONES'), {
        timeout: 30_000,
        message: `el libro no abrió.\\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);

    await expect
      .poll(async () => await aula.cuantos('Calificar'), {
        timeout: 30_000,
        message: `el libro abrió pero no montó sus acciones.\\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);

    await expect
      .poll(async () => await aula.cuantos(estudianteId), {
        timeout: 20_000,
        message: `el libro no muestra la fila de «${estudianteId}».\\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);
  });

  test('C8 — el docente califica y devuelve la entrega', async () => {
    const aula = new AulaVirtualPage(pgCalificador);

    const notaDialogo = aula.app.campo('Nota (0–20)');
    await expect
      .poll(async () => await notaDialogo.count(), { timeout: 5_000 })
      .toBe(0);

    await pulsarBotonDeFila(aula, estudianteId, 'Calificar');

    await expect
      .poll(async () => await aula.app.campo('Nota (0–20)').count(), { timeout: 10_000 })
      .toBeGreaterThan(0);

    await aula.app.escribirEn('Nota (0–20)', '18');

    const calificacion = pgCalificador.waitForResponse(
      (r) =>
        r.url().includes('/api/v1/aula/entregas/') &&
        r.url().endsWith('/calificar') &&
        r.request().method() === 'POST',
      { timeout: 30_000 },
    );
    await aula.app.pulsarReal('Guardar nota', { ignorarMayusculas: true });
    const calificacionResponse = await calificacion;
    expect(calificacionResponse.status()).toBe(200);

    await expect
      .poll(async () => await aula.cuantos('18,0'), {
        timeout: 30_000,
        message: `la nota 18 no apareció en el libro.\\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);

    const devolucion = pgCalificador.waitForResponse(
      (r) =>
        r.url().includes('/api/v1/aula/entregas/') &&
        r.url().endsWith('/devolver') &&
        r.request().method() === 'POST',
      { timeout: 30_000 },
    );
    await pulsarBotonDeFila(aula, estudianteId, 'Devolver');
    const devolucionResponse = await devolucion;
    expect(devolucionResponse.status()).toBe(200);

    await expect
      .poll(async () => await aula.cuantos('Devuelta'), {
        timeout: 30_000,
        message: `la fila no pasó a Devuelta.\\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);
  });

  test('C9/C10 — el aprendiz ve la entrega devuelta y la nota 18', async ({ browser }) => {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    try {
      const login = new LoginPage(page);
      await login.abrir();
      await login.entrar(ALUMNO, CLAVE_ALUMNO, SENAL_DE_SESION_ALUMNO);

      const aula = new AulaVirtualPage(page);
      await aula.irAMisAulas();
      await aula.abrirAula(SECCION);
      await aula.esperarAula();
      await aula.app.pulsarPestana(PESTANA_TRABAJO, { ignorarMayusculas: true });

      await expect.poll(async () => await aula.cuantos(TAREA_E2E), { timeout: 30_000 }).toBeGreaterThan(0);
      await aula.app.pulsarReal(TAREA_E2E, { exacto: false });

      await expect
        .poll(async () => await aula.cuantos('Devuelta por el docente.'), { timeout: 30_000 })
        .toBeGreaterThan(0);

      await expect
        .poll(async () => await aula.cuantos('Nota: 18 pts.'), { timeout: 30_000 })
        .toBeGreaterThan(0);
    } finally {
      await ctx.close();
    }
  });
});
