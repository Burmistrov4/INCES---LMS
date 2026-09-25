// Suite E2E de la exportación CSV hacia HACER.
//
// **Qué cubre que no cubra `flutter test`.** Todo lo que hay debajo de
// `SelectorDeArchivos`: el `Blob`, la URL de objeto, el `<a download>` y el
// clic. Ese código vive en `lib/services/selector_archivos_web.dart` y usa
// `package:web` + `dart:js_interop`, que **no compilan en la VM de Dart** — por
// eso la suite de widget lo dobla con un doble y la ruta real queda sin cubrir.
// Ésta es la única prueba que la recorre de verdad, en un navegador de verdad.
//
// **El flujo es el real y no una atajo**: se entra con credenciales reales
// contra el Supabase real, se navega pulsando el menú y se pulsa el botón. No
// hay mocks de JavaScript en el navegador ni sesión sembrada a mano: el JWT que
// la vista `security_invoker` usa para decidir qué filas devuelve lo emite
// `supabase_flutter` al autenticar, y una sesión inyectada probaría un estado
// que la app no produce sola.

import { readFileSync } from 'node:fs';
import { expect, test, type BrowserContext, type Download, type Page } from '@playwright/test';

import { LoginPage } from '../src/pages/LoginPage.js';
import { InscripcionesPage } from '../src/pages/InscripcionesPage.js';
import {
  COLUMNAS_HACER,
  analizarArchivoHacer,
  asertaArchivoHacer,
  type InformeArchivoHacer,
} from '../src/fixtures/csv.js';

/** Credenciales reales, por entorno. Nunca escritas en el repositorio. */
const USUARIO = process.env.E2E_ADMIN_EMAIL ?? '';
const CLAVE = process.env.E2E_ADMIN_PASSWORD ?? '';

/**
 * El nombre (o un fragmento) de la sección cuya planilla se exporta.
 *
 * Tiene que ser una sección **con matriculados**: si está vacía, la app avisa
 * «no tiene matriculados todavía» y no descarga nada —que es el comportamiento
 * correcto, pero no lo que esta suite mide—.
 */
const SECCION = process.env.E2E_SECCION ?? '';

test.describe.serial('Exportación de la planilla hacia HACER', () => {
  let contexto: BrowserContext;
  let pagina: Page;
  let descarga: Download;
  let bytes: Buffer;
  let informe: InformeArchivoHacer;

  test.beforeAll(async ({ browser }) => {
    test.skip(
      USUARIO === '' || CLAVE === '',
      'Faltan E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD: son credenciales reales y no viven en el repositorio.',
    );
    test.skip(
      SECCION === '',
      'Falta E2E_SECCION: hay que decir qué sección exportar, y tiene que tener matriculados.',
    );

    // El contexto se crea a mano, así que hay que pedir las descargas aquí
    // también: el `acceptDownloads` de la configuración sólo aplica a los
    // contextos que abre el propio runner. Sin esto, `waitForEvent('download')`
    // nunca resuelve y el fallo apunta al botón en vez de a esta línea.
    contexto = await browser.newContext({ acceptDownloads: true });
    pagina = await contexto.newPage();

    const login = new LoginPage(pagina);
    await login.abrir();
    await login.entrar(USUARIO, CLAVE);

    const panel = new InscripcionesPage(pagina);
    await panel.abrir();
    descarga = await panel.exportarSeccion(SECCION);

    const ruta = await descarga.path();
    bytes = readFileSync(ruta);
    informe = analizarArchivoHacer(bytes);
  });

  test.afterAll(async () => {
    await contexto?.close();
  });

  test('el navegador entrega el archivo y la descarga no falla', async () => {
    expect(await descarga.failure()).toBeNull();
    expect(bytes.length).toBeGreaterThan(0);
  });

  test('el archivo lleva el nombre que HACER espera', async () => {
    expect(descarga.suggestedFilename()).toMatch(/^planilla-hacer-.*\.csv$/);
  });

  // Las dos precondiciones van PRIMERO, y no es cuestión de gusto: en modo
  // `serial`, una prueba que falla **salta todas las siguientes**. Una
  // precondición colocada al final se salta justo cuando hace falta —cuando algo
  // falló antes— y el informe dice «no se comprobó» en vez de «la sección estaba
  // vacía». Se descubrió ejecutando la suite, no compilándola.
  test('la nómina trae al menos un matriculado', () => {
    expect(
      informe.filas.length,
      'la sección elegida no tiene matriculados: elige otra con E2E_SECCION. ' +
        'La app avisa «no tiene matriculados todavía» y no descarga nada, que es el ' +
        'comportamiento correcto pero no lo que esta suite mide.',
    ).toBeGreaterThan(0);
  });

  test('empieza por el BOM UTF-8 (EF BB BF)', () => {
    expect(informe.tieneBom, 'sin el BOM, Excel abre el CSV con la codificación del sistema y los acentos salen rotos').toBe(true);
    expect([...bytes.subarray(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
  });

  test('todos los finales de línea son CRLF', () => {
    expect(informe.lfSueltos, 'hay LF sin su CR: HACER espera CRLF en todos').toBe(0);
  });

  test('la cabecera coincide con el esquema de 62 columnas', () => {
    expect(informe.cabecera.length).toBe(COLUMNAS_HACER.length);
    expect(informe.cabecera).toEqual([...COLUMNAS_HACER]);
  });

  test('ninguna fila tiene un número de columnas distinto al de la cabecera', () => {
    expect(informe.anchosAnomalos).toEqual([]);
  });

  test('el separador de campos es el punto y coma', () => {
    const primeraLinea = bytes.subarray(3).toString('utf8').split('\r\n')[0] ?? '';
    expect(primeraLinea).toContain(';');
    expect(primeraLinea.split(';').length).toBe(COLUMNAS_HACER.length);
  });

  test('el documento de identidad es nacionalidad + cédula con relleno de ceros', () => {
    const columna = informe.cabecera.indexOf('documento_identidad');
    expect(columna, 'la columna documento_identidad no está en la cabecera').toBeGreaterThan(-1);

    for (const fila of informe.filas) {
      const valor = fila[columna] ?? '';
      // Vacío es legítimo: una inscripción sin ficha de aspirante no tiene
      // identidad, y el serializador escribe `""`. Lo que no puede es salir con
      // una forma que HACER no entienda.
      if (valor === '') continue;
      expect(valor, `«${valor}» no es una letra más 9 dígitos`).toMatch(/^[A-Z]{1,2}\d{9}$/);
    }
  });

  // Y el agregado va al final, a propósito: una sola aserción que recorre TODAS
  // las comprobaciones del helper y, si falla, las enumera juntas en vez de
  // parar en la primera. Las pruebas de arriba dicen cuál falló; ésta dice
  // cuántas cosas fallaron.
  test('el informe completo del archivo no tiene problemas', () => {
    expect(() => asertaArchivoHacer(bytes, { filasEsperadas: informe.filas.length })).not.toThrow();
  });
});
