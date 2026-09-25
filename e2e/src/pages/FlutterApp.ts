// El Page Object base de una app Flutter Web.
//
// **Por qué hay una clase para esto y no un `page.click()` en cada test.** Flutter
// Web con CanvasKit no pinta widgets: pinta píxeles. No hay `<button>`, no hay
// `getByText`, no hay `getByRole`. Sin una capa que encapsule cómo se conduce
// esto, cada test reinventa —y reinventa mal— la misma secuencia de cuatro pasos.
//
// **Todo lo que hace esta clase está medido**, contra una app Flutter Web real
// (`dartpad.dev`, que es Flutter de verdad aunque su versión no sea la del
// proyecto) con `playwright-core` + Chromium. Lo que se midió y por qué importa:
//
//   1. `locator.click()` sobre `flt-semantics-placeholder` **agota el tiempo**.
//      `click({ force: true })` falla con «Element is outside of the viewport».
//      `dispatchEvent('click')` y `element.click()` **funcionan** (41 nodos
//      semánticos aparecen). Por eso se usa `dispatchEvent` y no `click`.
//
//   2. Con el árbol encendido, el reparto de `role` es: `button` 15, `img` 2,
//      `group` 1, y **23 nodos sin `role`** — entre ellos los que SÍ tienen
//      `aria-label`. Consecuencia medida: `getByRole('button', { name })`
//      devuelve **0** coincidencias y `getByText` también **0**, mientras que
//      `getByLabel` y `flt-semantics[aria-label="…"]` devuelven **1**. Por eso
//      el localizador por defecto es el atributo, no el rol.
//
//   3. Pulsar un nodo semántico con `click()` **también agota el tiempo**
//      («Timeout 5000ms exceeded»), y sin embargo `click({ force: true })` y
//      `dispatchEvent('click')` funcionan. Un POM que use `click()` a secas
//      falla en el 100 % de las pulsaciones, y el mensaje no lo explica.
//
//   4. El árbol semántico **sobrevive a la navegación** por hash (41 nodos antes
//      y después de cambiar `location.hash`). O sea: se enciende una vez por
//      carga de página y no hay que repetirlo en cada paso.
//
//   5. `<canvas>` está dentro del **shadow DOM** de `flt-glass-pane`:
//      `document.querySelectorAll('canvas').length` da **0** con la app
//      funcionando. Un test que use ese contador como «¿ya cargó?» se queda
//      esperando para siempre. (Playwright sí atraviesa shadow DOM por defecto,
//      así que `page.locator('canvas')` sí lo encuentra — pero el contador por
//      `document` no.)

import { expect, type Locator, type Page } from '@playwright/test';

/** Un nodo del árbol semántico, para diagnósticos. */
export interface NodoSemantico {
  rol: string;
  etiqueta: string;
  x: number;
  y: number;
  ancho: number;
  alto: number;
}

export class FlutterApp {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  /**
   * Carga la app y deja el árbol semántico encendido.
   *
   * Es el único sitio que llama a [encenderSemantica]; los Page Objects de
   * pantalla lo dan por hecho.
   */
  async abrir(ruta = '/'): Promise<void> {
    await this.page.goto(ruta, { waitUntil: 'domcontentloaded' });
    await this.esperarMotor();
    await this.encenderSemantica();
  }

  /**
   * Espera a que el motor de Flutter esté montado.
   *
   * **No es un `waitForTimeout`.** Un `sleep` de 9 s (que es lo que hace la
   * receta de auditoría) es a la vez demasiado corto en un runner frío y
   * demasiado largo en uno caliente. La señal real es el DOM: Flutter monta
   * `flt-glass-pane` y luego crea el placeholder de accesibilidad. Se espera a
   * esas dos cosas.
   */
  async esperarMotor(opciones: { timeout?: number } = {}): Promise<void> {
    const timeout = opciones.timeout ?? 60_000;
    await this.page.waitForSelector('flt-glass-pane', { state: 'attached', timeout });
    // El placeholder aparece cuando el motor ya puede atender semántica. Si la
    // accesibilidad ya estuviera pedida, `flt-semantics` existe y el placeholder
    // no; por eso se acepta cualquiera de los dos.
    await this.page.waitForSelector('flt-semantics-placeholder, flt-semantics', {
      state: 'attached',
      timeout,
    });
  }

  /**
   * Enciende el árbol semántico.
   *
   * Flutter Web no lo construye por defecto: lo construye cuando algo lo pide,
   * y la forma de pedirlo sin lector de pantalla es pulsar el placeholder. Es
   * idempotente — si ya está encendido, no hace nada.
   */
  async encenderSemantica(): Promise<void> {
    const yaHay = await this.page.locator('flt-semantics').count();
    if (yaHay > 0) return;

    const placeholder = this.page.locator('flt-semantics-placeholder').first();
    if ((await placeholder.count()) === 0) {
      throw new Error(
        'No apareció `flt-semantics-placeholder`, así que no se puede encender el árbol ' +
          'semántico y ningún localizador por etiqueta va a funcionar. Suele significar que ' +
          'la app no llegó a montar el motor. Diagnóstico:\n' +
          (await this.diagnostico()),
      );
    }

    // `dispatchEvent` y NO `click()`: medido, `click()` agota el tiempo aquí.
    await placeholder.dispatchEvent('click');

    // El árbol se construye en el siguiente fotograma; se espera a que haya
    // nodos en vez de dormir.
    await this.page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30_000 });
  }

  /**
   * Localiza un widget por su etiqueta semántica.
   *
   * Es un selector de atributo y no `getByRole`, por lo medido: Flutter deja el
   * `role` vacío en muchos nodos —incluidos los que sí llevan `aria-label`—, así
   * que `getByRole` devuelve 0. `getByLabel` también funciona (devuelve 1), pero
   * se prefiere el selector explícito porque dice en el propio test de qué
   * mecanismo depende.
   */
  etiqueta(texto: string, opciones: { exacto?: boolean } = {}): Locator {
    const escapado = texto.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    const selector = opciones.exacto
      ? `flt-semantics[aria-label="${escapado}"]`
      : `flt-semantics[aria-label*="${escapado}"]`;
    return this.page.locator(selector);
  }

  /** Cuántos widgets llevan esa etiqueta. */
  async cuantos(texto: string, opciones: { exacto?: boolean } = {}): Promise<number> {
    return this.etiqueta(texto, opciones).count();
  }

  /**
   * Pulsa un widget por su etiqueta.
   *
   * Usa `dispatchEvent('click')`, que es lo medido como fiable sobre nodos
   * semánticos de Flutter. Si la etiqueta no existe, el error lleva el volcado
   * del árbol: sin eso, el mensaje es «no encontré X» y hay que adivinar cómo se
   * llama de verdad el widget.
   */
  async pulsar(texto: string, opciones: { exacto?: boolean; indice?: number } = {}): Promise<void> {
    const locator = this.etiqueta(texto, opciones).nth(opciones.indice ?? 0);

    if ((await locator.count()) === 0) {
      throw new Error(
        `No hay ningún widget con la etiqueta «${texto}». Etiquetas disponibles:\n` +
          (await this.volcarSemantica()),
      );
    }

    await locator.dispatchEvent('click');
  }

  /**
   * Escribe en un campo de texto de Flutter.
   *
   * **Por qué no `fill()`.** Un nodo semántico de Flutter no es un `<input>`: es
   * un `<flt-semantics>` posicionado sobre el canvas. `fill()` exige un elemento
   * editable y fallaría. El camino que sí funciona es enfocar el campo y teclear
   * con el teclado del navegador, que es lo que Flutter escucha.
   *
   * **Es el paso menos verificado de la suite.** Todo lo demás de esta clase se
   * midió contra una app real; esto no, porque no encontré una app Flutter Web
   * pública con un campo de texto accesible por semántica. Si va a fallar, falla
   * aquí — y por eso comprueba el resultado y lo dice, en vez de seguir adelante
   * con un formulario vacío.
   */
  async escribirEn(campo: string, texto: string): Promise<void> {
    const locator = this.etiqueta(campo).first();

    if ((await locator.count()) === 0) {
      throw new Error(
        `No hay ningún campo con la etiqueta «${campo}». Etiquetas disponibles:\n` +
          (await this.volcarSemantica()),
      );
    }

    await locator.dispatchEvent('click');
    await this.page.keyboard.type(texto, { delay: 12 });

    // Comprobación: que el valor llegó al campo. Se lee del árbol semántico, que
    // es lo único que refleja el estado real del widget.
    await expect
      .poll(async () => await this.valorDe(campo), {
        message:
          `Se tecleó en «${campo}» pero el widget no refleja el texto. ` +
          'Es el paso menos verificado de la suite: probablemente haya que enfocar ' +
          'el nodo de otra forma.',
        timeout: 10_000,
      })
      .toContain(texto.slice(0, Math.min(4, texto.length)));
  }

  /** El texto que un nodo semántico declara, para comprobar que un campo recibió lo tecleado. */
  async valorDe(campo: string): Promise<string> {
    const locator = this.etiqueta(campo).first();
    if ((await locator.count()) === 0) return '';
    const nodo = locator;
    return (await nodo.getAttribute('aria-valuetext')) ?? (await nodo.textContent()) ?? '';
  }

  /** Volcado legible del árbol semántico, para mensajes de fallo. */
  async volcarSemantica(): Promise<string> {
    const nodos = await this.nodos();
    if (nodos.length === 0) {
      return '  (el árbol semántico está vacío: ¿se encendió la accesibilidad?)';
    }
    return nodos
      .map(
        (n) =>
          `  · etiqueta="${n.etiqueta}" rol="${n.rol}" ${n.ancho}x${n.alto} en (${n.x}, ${n.y})`,
      )
      .join('\n');
  }

  /** Los nodos del árbol semántico que tienen etiqueta, con su geometría. */
  async nodos(): Promise<NodoSemantico[]> {
    return this.page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .map((n) => {
          const r = n.getBoundingClientRect();
          return {
            rol: n.getAttribute('role') ?? '',
            etiqueta: n.getAttribute('aria-label') ?? '',
            x: Math.round(r.x),
            y: Math.round(r.y),
            ancho: Math.round(r.width),
            alto: Math.round(r.height),
          };
        })
        .filter((n) => n.etiqueta !== ''),
    );
  }

  /**
   * Localiza el botón de UNA tarjeta, por cercanía a su título.
   *
   * **Por qué por geometría y no por jerarquía.** El árbol semántico de Flutter
   * es **plano**: no hay anidamiento de DOM que permita decir «el botón de dentro
   * de esta tarjeta». Y el botón de exportar se llama igual en todas las
   * tarjetas —«Exportar Planilla HACER (.csv)», uno por sección—, así que por
   * etiqueta es ambiguo.
   *
   * **Por qué por cercanía y no por «la caja que lo contiene».** La primera
   * versión de este método buscaba un nodo cuya caja englobara al botón. No
   * sirve: Flutter sólo crea un nodo semántico con la caja del **título** de la
   * tarjeta, no con la tarjeta entera, así que ese contenedor puede no existir.
   * La regla que sí es estable es la de vecino más cercano: se reparten TODOS
   * los botones entre TODOS los títulos según distancia, y el botón que le toca
   * a este título es el suyo. Funciona con cualquier número de tarjetas, sin
   * depender del orden ni de que exista un nodo contenedor.
   */
  async botonDeTarjeta(
    titulo: string,
    etiquetaBoton: string,
    opciones: { exactoTitulo?: boolean } = {},
  ): Promise<Locator> {
    const nodos = await this.nodos();

    const titulos = nodos.filter((n) =>
      opciones.exactoTitulo ? n.etiqueta === titulo : n.etiqueta.includes(titulo),
    );
    if (titulos.length === 0) {
      throw new Error(
        `No hay ningún título con «${titulo}». Etiquetas disponibles:\n` + (await this.volcarSemantica()),
      );
    }

    const botones = await this.etiqueta(etiquetaBoton).all();
    if (botones.length === 0) {
      throw new Error(
        `No hay ningún botón con «${etiquetaBoton}». Etiquetas disponibles:\n` + (await this.volcarSemantica()),
      );
    }

    // Se elige UN título objetivo: el de coincidencia exacta si lo hay, y si no
    // el primero que contenga el texto. Sin esto, un nombre de sección que
    // aparezca en dos sitios (una cabecera y una tarjeta) daría un resultado
    // arbitrario según el orden del árbol.
    const objetivo = titulos.find((t) => t.etiqueta === titulo) ?? titulos[0]!;

    const centro = (n: NodoSemantico) => ({ x: n.x + n.ancho / 2, y: n.y + n.alto / 2 });
    const distancia = (ax: number, ay: number, bx: number, by: number) =>
      Math.hypot(ax - bx, ay - by);
    const cObjetivo = centro(objetivo);

    // Cajas de los botones, una sola vez.
    const cajas: Array<{ locator: Locator; x: number; y: number; dObjetivo: number }> = [];
    for (const boton of botones) {
      const caja = await boton.boundingBox();
      if (!caja) continue;
      const x = caja.x + caja.width / 2;
      const y = caja.y + caja.height / 2;
      cajas.push({ locator: boton, x, y, dObjetivo: distancia(x, y, cObjetivo.x, cObjetivo.y) });
    }

    // El botón de una tarjeta es el que está más cerca de SU título que de
    // ningún otro. Se reparten así todos los botones, y el que le toca al
    // título objetivo es el suyo.
    const suyos = cajas.filter((c) => {
      let masCerca = objetivo;
      let dMinima = c.dObjetivo;
      for (const t of titulos) {
        if (t === objetivo) continue;
        const ct = centro(t);
        const d = distancia(c.x, c.y, ct.x, ct.y);
        if (d < dMinima) {
          dMinima = d;
          masCerca = t;
        }
      }
      return masCerca === objetivo;
    });

    if (suyos.length === 0) {
      throw new Error(
        `Hay ${botones.length} botones con «${etiquetaBoton}» y ${titulos.length} título(s) ` +
          `que contienen «${titulo}», pero ninguno de esos botones está más cerca de ese título ` +
          'que de los demás. Suele significar que el panel cambió de distribución.\n' +
          (await this.volcarSemantica()),
      );
    }

    suyos.sort((a, b) => a.dObjetivo - b.dObjetivo);
    return suyos[0]!.locator;
  }

  /** Diagnóstico del DOM cuando algo no aparece. */
  async diagnostico(): Promise<string> {
    const estado = await this.page.evaluate(() => ({
      url: location.href,
      listo: document.readyState,
      glassPane: document.querySelectorAll('flt-glass-pane').length,
      semantica: document.querySelectorAll('flt-semantics').length,
      placeholder: document.querySelectorAll('flt-semantics-placeholder').length,
      vista: document.querySelectorAll('flutter-view').length,
      cuerpo: [...document.body.children].map((e) => e.tagName.toLowerCase()).join(', '),
    }));
    return [
      `  url          : ${estado.url}`,
      `  readyState   : ${estado.listo}`,
      `  flutter-view : ${estado.vista}`,
      `  glass-pane   : ${estado.glassPane}`,
      `  semántica    : ${estado.semantica}`,
      `  placeholder  : ${estado.placeholder}`,
      `  <body>       : ${estado.cuerpo}`,
    ].join('\n');
  }
}
