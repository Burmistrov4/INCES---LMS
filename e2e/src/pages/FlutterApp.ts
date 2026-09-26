// El Page Object base de una app Flutter Web.
//
// **Por qué hay una clase para esto y no un `page.click()` en cada test.** Flutter
// Web con CanvasKit no pinta widgets: pinta píxeles. No hay `<button>` visible con
// el texto dentro, y el árbol semántico se estructura distinto que en dartpad. Sin
// una capa que encapsule cómo se conduce esto, cada test reinventa —y reinventa
// mal— la misma secuencia.
//
// **TODO lo que hace esta clase está medido contra LA APP REAL DE ESTE REPO**
// (Flutter 3.47, `build/web` compilado el 2026-09-26, Chromium headless,
// `playwright-core`). Medidas clave de esa sesión:
//
//   1. **El árbol semántico se enciende con `dispatchEvent('click')` sobre
//      `flt-semantics-placeholder`.** Medido de nuevo: 20 nodos aparecen al
//      instante. `click()` nativo sobre el placeholder agota el tiempo.
//
//   2. **Ningún `flt-semantics` lleva `aria-label` (0 de 20).** Las reglas que
//      salieron de dartpad (`aria-label` en el wrapper) NO valen aquí. En la app
//      real el texto vive en un `<span>` hijo del nodo hoja, y los botones
//      llevan `role="button"` + `tabindex=0` + `flt-tappable` con el texto en
//      `textContent`.
//
//   3. **Los campos de texto contienen un `<input>` REAL** — de tamaño real
//      (428×54), con `aria-label` igual a la etiqueta del campo—. Se les habla
//      como a un input nativo: `click()` sí funciona sobre ellos y el tecleo
//      sí llega. La pista visual («Cédula o Correo») NO aparece como texto
//      suelto en el árbol: existe sólo como `aria-label` de ese input.
//
//   4. **Tecleo: `pressSequentially`, no `fill()` ni `keyboard.type` a ciegas.**
//      Medido con los tres caminos: `keyboard.type` tras pulsar el wrapper
//      no llegó (el valor quedó vacío); `fill()` fue intermitente (Flutter
//      reconstruye los nodos al mover el foco y el segundo `fill` aterrizó en
//      un input que ya había muerto). El que funcionó de principio a fin —
//      login real contra Supabase, con la comprobación de que apareció
//      «Inscripciones y Cupos»— fue `input.click()` + `pressSequentially()`.
//
//   5. **Los `flt-semantics` envoltorios concatenan el texto de TODOS sus
//      descendientes.** Por eso un `hasText` sin filtrar coincide con la raíz
//      y da falsos positivos. Por eso el localizador de texto filtra a las
//      **hojas** (`not(descendant::flt-semantics)`).
//
//   6. El `<canvas>` sigue dentro del **shadow DOM** de `flt-glass-pane`, y el
//      árbol semántico **sobrevive a la navegación** por hash. Se enciende una
//      vez por carga de página.

import { expect, type Locator, type Page } from '@playwright/test';

/** Un nodo del árbol semántico, para diagnósticos y geometría. */
export interface NodoSemantico {
  rol: string;
  etiqueta: string;
  x: number;
  y: number;
  ancho: number;
  alto: number;
}

/** `texto` escapado para meterlo en un selector entre comillas dobles. */
function paraSelector(texto: string): string {
  return texto.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

/** `texto` escapado para meterlo en un `RegExp`. */
function paraRegExp(texto: string): RegExp {
  return new RegExp('^' + texto.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$');
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
   * **No es un `waitForTimeout`.** La señal real es el DOM: Flutter monta
   * `flt-glass-pane` y luego crea el placeholder de accesibilidad. Medido en la
   * app real: ~3 s en caliente.
   */
  async esperarMotor(opciones: { timeout?: number } = {}): Promise<void> {
    const timeout = opciones.timeout ?? 60_000;
    await this.page.waitForSelector('flt-glass-pane', { state: 'attached', timeout });
    await this.page.waitForSelector('flt-semantics-placeholder, flt-semantics', {
      state: 'attached',
      timeout,
    });
  }

  /**
   * Enciende el árbol semántico.
   *
   * Usa `dispatchEvent('click')`, medido contra la app real. Es idempotente.
   * No se espera a que haya «suficientes» nodos: el árbol aparece en el primer
   * fotograma tras el click; quien busca un widget concreto lo hace con
   * `expect.poll`, que es la forma honesta de esperar contenido.
   */
  async encenderSemantica(): Promise<void> {
    if ((await this.page.locator('flt-semantics').count()) > 0) return;

    const placeholder = this.page.locator('flt-semantics-placeholder').first();
    if ((await placeholder.count()) === 0) {
      throw new Error(
        'No apareció `flt-semantics-placeholder`, así que no se puede encender el árbol ' +
          'semántico y ningún localizador va a funcionar. Suele significar que la app no ' +
          'llegó a montar el motor. Diagnóstico:\n' +
          (await this.diagnostico()),
      );
    }

    await placeholder.dispatchEvent('click');
    await this.page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30_000 });
  }

  /**
   * Los `flt-semantics` **hoja** — los que no contienen otros — con ese texto
   * visible.
   *
   * **Por qué hojas y no todos.** Los envoltorios de la app real concatetan el
   * texto de toda su descendencia: la raíz contiene literalmente el texto
   * completo de la pantalla. Un `hasText` sin filtrar «encuentra» esa raíz y
   * devuelve candidatos absurdos, y además Tap en ella no pulsa nada. Las
   * hojas son los nodos que realmente pintan texto: botones (role=`button`,
   * con su span) y textos sueltos (`Text` de Flutter).
   */
  etiqueta(texto: string, opciones: { exacto?: boolean } = {}): Locator {
    const hojas = this.page.locator(
      'xpath=//flt-semantics[not(descendant::flt-semantics)]',
    );
    return opciones.exacto
      ? hojas.filter({ hasText: paraRegExp(texto) })
      : hojas.filter({ hasText: texto });
  }

  /**
   * Los widgets **con interacción** (rol) que llevan ese texto.
   *
   * Los botones y entradas de menú de la app real llevan `role="button"`,
   * `tabindex="0"` y la clase `flt-tappable`. Este localizador los prefiere
   * por encima del de texto porque son los que de verdad responden a un click.
   */
  controles(texto: string, opciones: { exacto?: boolean } = {}): Locator {
    const conRol = this.page.locator(
      'flt-semantics[role="button"], flt-semantics[role="link"], flt-semantics[role="tab"], flt-semantics[role="menuitem"]',
    );
    return opciones.exacto
      ? conRol.filter({ hasText: paraRegExp(texto) })
      : conRol.filter({ hasText: texto });
  }

  /** Cuántos widgets llevan ese texto visible (hojas) o lo muestran como control. */
  async cuantos(texto: string, opciones: { exacto?: boolean } = {}): Promise<number> {
    // Se cuentan los controles y las hojas de texto; un widget que sea ambas
    // cosas se descuenta para no inflar. Para señales de «apareció X» importa
    // `> 0`, así que la unión es lo correcto.
    const total = this.controles(texto, opciones)
      .or(this.etiqueta(texto, opciones));
    return total.count();
  }

  /**
   * Pulsa un widget por su texto visible.
   *
   * Prefiere los controles con rol (botones, entradas de menú); si no hay
   * ninguno con ese texto, cae a la hoja de texto (los `InkWell` a veces no
   * declaran rol). Ambos caminos usan `dispatchEvent('click')`, medido en la
   * app real sobre botones y sobre el placeholder.
   */
  async pulsar(texto: string, opciones: { exacto?: boolean; indice?: number } = {}): Promise<void> {
    let locator = this.controles(texto, opciones);
    if ((await locator.count()) === 0) locator = this.etiqueta(texto, opciones);

    if ((await locator.count()) === 0) {
      throw new Error(
        `No hay ningún widget pulsable con el texto «${texto}». Árbol semántico:\n` +
          (await this.volcarSemantica()),
      );
    }

    await locator.nth(opciones.indice ?? 0).dispatchEvent('click');
  }

  /**
   * Escribe en un campo de texto de Flutter.
   *
   * **Medido el 2026-09-26 contra la app real.** Un campo de Flutter Web es un
   * `<input>` de verdad dentro del `flt-semantics`, con `aria-label` igual a la
   * etiqueta del campo. Se trata como un input nativo:
   *
   *   1. `click()` — sí funciona, porque el input es DOM real de tamaño real.
   *   2. `pressSequentially` — lo que llega letra a letra. `fill()` medido:
   *      intermitente (los nodos se reconstruyen al enfocar); `keyboard.type`
   *      sobre el wrapper medido: no llega.
   *   3. Se lee el `input.value` y se rompe si no llegó — el error lleva el
   *      volcado del árbol para que se vea de qué se dispone.
   */
  async escribirEn(campo: string, texto: string): Promise<void> {
    const entrada = this.campo(campo).first();

    if ((await entrada.count()) === 0) {
      throw new Error(
        `No hay ningún campo con la etiqueta «${campo}». ` +
          'Los campos de la app real son `input` con `aria-label`; si no está, o la ' +
          'etiqueta no es la del widget, o no estamos en la pantalla esperada.\n' +
          (await this.volcarSemantica()),
      );
    }

    await entrada.click();
    await entrada.pressSequentially(texto, { delay: 12 });

    // El valor real del widget es el del input que lo respalda.
    await expect
      .poll(async () => await entrada.inputValue(), {
        message:
          `Se tecleó en «${campo}» pero el input no refleja el texto — ` +
          'el tecleo no llegó al widget. Diagnóstico:\n' +
          (await this.diagnostico()),
        timeout: 10_000,
      })
      .toBe(texto);
  }

  /** Devuelve el `<input>` real de un campo, localizado por su etiqueta. */
  campo(etiqueta: string): Locator {
    const escapado = paraSelector(etiqueta);
    return this.page.locator(
      `flt-semantics input[aria-label="${escapado}"], flt-semantics textarea[aria-label="${escapado}"]`,
    );
  }

  /** El valor visible de un campo (lo que tecleó el usuario o el test). */
  async valorDe(campo: string): Promise<string> {
    const entrada = this.campo(campo).first();
    if ((await entrada.count()) === 0) return '';
    try {
      return await entrada.inputValue();
    } catch {
      return (await entrada.getAttribute('aria-valuetext')) ?? (await entrada.textContent()) ?? '';
    }
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

  /**
   * Los nodos del árbol semántico, con su geometría.
   *
   * La «etiqueta» es lo que el nodo muestra de verdad: su `aria-label` si lo
   * lleva (los inputs) y, si no, el texto del `<span>` que tiene por hijo
   * directo — que es donde la app real pone el texto visible—. Los envoltorios
   * también tienen `textContent`, pero es la concatenación de toda su
   * descendencia y aquí sólo se quiere el texto PROPIO.
   */
  async nodos(): Promise<NodoSemantico[]> {
    return this.page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .map((n) => {
          const r = n.getBoundingClientRect();
          let etiqueta = n.getAttribute('aria-label') ?? '';
          if (etiqueta === '') {
            // Un nodo hoja cuyo único hijo es un span: ese span ES su texto.
            const hijo = n.children[0];
            if (hijo && hijo instanceof HTMLElement && hijo.tagName === 'SPAN') {
              etiqueta = (hijo.textContent ?? '').trim();
            }
          }
          return {
            rol: n.getAttribute('role') ?? '',
            etiqueta,
            x: Math.round(r.x),
            y: Math.round(r.y),
            ancho: Math.round(r.width),
            alto: Math.round(r.height),
          };
        })
        .filter((n) => n.etiqueta !== '' || n.rol !== ''),
    );
  }

  /**
   * Localiza el botón de UNA tarjeta, por cercanía a su título.
   *
   * **Por qué por geometría y no por jerarquía.** El árbol semántico de Flutter
   * es **plano**: no hay anidamiento de DOM que permita decir «el botón de
   * dentro de esta tarjeta». Y el botón de exportar se llama igual en todas
   * las tarjetas —«Exportar Planilla HACER (.csv)», uno por sección—, así que
   * por etiqueta es ambiguo.
   *
   * **Por qué por cercanía y no por «la caja que lo contiene».** Flutter crea
   * un nodo semántico con la caja del **título**, no con la tarjeta entera, así
   * que ese contenedor puede no existir. La regla estable es la de vecino más
   * cercano: se reparten TODOS los botones entre TODOS los títulos según
   * distancia, y el botón que le toca a este título es el suyo. Funciona con
   * cualquier número de tarjetas, sin depender del orden del árbol.
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
        `No hay ningún título con «${titulo}». Árbol semántico:\n` + (await this.volcarSemantica()),
      );
    }

    const botones = await this.controles(etiquetaBoton).all();
    if (botones.length === 0) {
      throw new Error(
        `No hay ningún botón con «${etiquetaBoton}». Árbol semántico:\n` + (await this.volcarSemantica()),
      );
    }

    // Se elige UN título objetivo: el de coincidencia exacta si lo hay, y si no
    // el primero que contenga el texto.
    const objetivo = titulos.find((t) => t.etiqueta === titulo) ?? titulos[0]!;

    const centro = (n: NodoSemantico) => ({ x: n.x + n.ancho / 2, y: n.y + n.alto / 2 });
    const distancia = (ax: number, ay: number, bx: number, by: number) =>
      Math.hypot(ax - bx, ay - by);
    const cObjetivo = centro(objetivo);

    const cajas: Array<{ locator: Locator; x: number; y: number; dObjetivo: number }> = [];
    for (const boton of botones) {
      const caja = await boton.boundingBox();
      if (!caja) continue;
      const x = caja.x + caja.width / 2;
      const y = caja.y + caja.height / 2;
      cajas.push({ locator: boton, x, y, dObjetivo: distancia(x, y, cObjetivo.x, cObjetivo.y) });
    }

    // El botón de una tarjeta es el que está más cerca de SU título que de
    // ningún otro.
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
          `que contienen «${titulo}», pero ninguno está más cerca de ese título que de los ` +
          'demás. Suele significar que el panel cambió de distribución.\n' +
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
