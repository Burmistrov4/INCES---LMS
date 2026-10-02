// Suite E2E del Aula Virtual (M6).
//
// **Qué cubre que no cubra `flutter test`.** El aula está probada con dobles en
// siete archivos de widget, y esos dobles **no pueden** ver una URL mal formada,
// un `Content-Type` que no cuadra, una política RLS que devuelve cero filas o un
// módulo apagado. Aquí se entra con credenciales reales contra el Supabase real,
// se navega pulsando el menú y se lee lo que la app pinta de verdad.
//
// **Por qué la mitad del aprendiz va primero.** Es la que se puede verificar de
// extremo a extremo hoy: el sembrado deja un anuncio PUBLICADO y una tarea en
// BORRADOR, así que el alumno tiene contenido que leer. La mitad del docente
// —publicar, calificar, devolver— vive en la pestaña «Trabajo de Clase» y
// necesita una pasada de medición más antes de escribirse; escribirla contra
// rótulos supuestos es exactamente lo que esta suite existe para evitar.
//
// **Sin `waitForTimeout`.** Cada transición se sincroniza por respuesta de red o
// por condición del árbol. Un tiempo fijo acierta casi siempre, y ese «casi» es
// el que produce el rojo intermitente que nadie sabe leer.

import { expect, test, type BrowserContext, type Page } from '@playwright/test';

import { AulaVirtualPage, PESTANA_TABLON, PESTANA_TRABAJO } from '../src/pages/AulaVirtualPage.js';
import { LoginPage, SENAL_DE_SESION_ALUMNO } from '../src/pages/LoginPage.js';

const ALUMNO = process.env.E2E_ALUMNO_EMAIL ?? '';
const CLAVE = process.env.E2E_ALUMNO_PASSWORD ?? '';
const SECCION = process.env.E2E_SECCION ?? '';

/**
 * Un fragmento del anuncio que siembra `sembrar-datos.mjs`.
 *
 * Se aserta por fragmento y no por el texto entero a propósito: lo que esta
 * prueba fija es que **el anuncio del aula llega a la pantalla**, no la
 * redacción exacta del sembrado —que puede cambiar sin que nada se rompa—.
 */
const ANUNCIO_SEMBRADO = 'Bienvenidos';

test.describe.serial('Aula Virtual del aprendiz', () => {
  let contexto: BrowserContext;
  let pagina: Page;

  /**
   * Tarjetas del listado, contadas **antes** de entrar al aula.
   *
   * Se mide aquí y no en la prueba a propósito: `beforeAll` ya navegó al aula, y
   * dentro el listado no existe —el aula lo sustituye—. Asertar allí daría cero
   * y el fallo culparía al conteo en vez de al orden de la navegación, que es el
   * error que ya cometí una vez.
   */
  let tarjetasDelListado = 0;

  test.beforeAll(async ({ browser }) => {
    test.skip(
      ALUMNO === '' || CLAVE === '',
      'Faltan E2E_ALUMNO_EMAIL / E2E_ALUMNO_PASSWORD: son credenciales reales.',
    );
    test.skip(SECCION === '', 'Falta E2E_SECCION: hay que decir qué aula abrir.');

    contexto = await browser.newContext();
    pagina = await contexto.newPage();

    const login = new LoginPage(pagina);
    await login.abrir();
    await login.entrar(ALUMNO, CLAVE, SENAL_DE_SESION_ALUMNO);

    const aula = new AulaVirtualPage(pagina);
    await aula.irAMisAulas();
    tarjetasDelListado = await aula.contarTarjetas(SECCION);
    await aula.abrirAula(SECCION);
    await aula.esperarAula();
  });

  test.afterAll(async () => {
    await contexto?.close();
  });

  test('el listado trae exactamente una tarjeta por sección', async () => {
    // El gateway colapsa las franjas del cuadrante: una sección aparece una vez
    // por franja en `clases` y se reduce a UNA fila (`mis_aulas_panel.dart:19`).
    // Exigir el conteo exacto es lo que fija esa regla de negocio; un
    // `toBeGreaterThan(0)` pasaría con la duplicación puesta.
    expect(tarjetasDelListado).toBe(1);
  });

  test('el aula monta con sus dos pestañas', async () => {
    const aula = new AulaVirtualPage(pagina);

    expect(await aula.cuantos(PESTANA_TABLON)).toBeGreaterThan(0);
    expect(await aula.cuantos(PESTANA_TRABAJO)).toBeGreaterThan(0);
  });

  test('el tablón muestra el anuncio que dejó el sembrado', async () => {
    const aula = new AulaVirtualPage(pagina);

    // Es la aserción que separa «la pantalla cargó» de «la pantalla cargó con
    // datos»: un aula vacía monta igual y no sirve para nada.
    expect(await aula.cuantos(ANUNCIO_SEMBRADO)).toBeGreaterThan(0);
  });

  test('la pestaña «Trabajo de Clase» responde al cambio de pestaña', async () => {
    const aula = new AulaVirtualPage(pagina);

    await aula.abrirPestana(PESTANA_TRABAJO);

    // Se comprueba que la pestaña sigue montada y que el árbol no se vació: un
    // cambio de pestaña que dejara la pantalla en blanco pasaría una aserción
    // sobre el rótulo de la pestaña, que vive en el `tablist` y no en el panel.
    await expect
      .poll(async () => await aula.cuantos(PESTANA_TRABAJO), {
        timeout: 15_000,
        message: `la pestaña «${PESTANA_TRABAJO}» desapareció al pulsarla.\n${await aula.diagnostico()}`,
      })
      .toBeGreaterThan(0);
  });
});
