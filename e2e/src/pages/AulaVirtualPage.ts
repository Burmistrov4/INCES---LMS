// Page Object del Aula Virtual (M6).
//
// **Los localizadores no son CSS ni `getByRole`.** La app es Flutter Web sobre
// CanvasKit: no hay nodos HTML que consultar, y lo que Flutter publica en el DOM
// son elementos `flt-semantics` cuya etiqueta puede venir de tres sitios
// distintos —`aria-label`, un `<span>` hijo, o el `textContent` propio— según
// midió `FlutterApp.nodos()`. `getByRole` sólo computa el nombre por ARIA y
// **perdería el tercer caso**, que es el que usan los encabezados de paso. Por
// eso se usa la capa del repositorio, que ya resuelve los tres.
//
// **Los rótulos están medidos, no supuestos** (2026-10-02, con la sonda sobre el
// aprendiz sembrado). Los tres que gobiernan esta pantalla:
//
//   · La tarjeta de «Mis aulas» es **un solo nodo `button`** cuya etiqueta es la
//     concatenación `materia · sección · programa`
//     —«Soldadura por Arco [SEMILLA] · SA · Soldadura [SEMILLA]»—, así que basta
//     con buscar por un fragmento del título de la materia.
//   · Dentro, el aula publica un `tablist` con dos pestañas por **rol**
//     (`role="tab"`): «Tablón» y «Trabajo de Clase».
//   · El anuncio del tablón llega en el `tabpanel`.

import { expect, type Page, type Response } from '@playwright/test';

import { FlutterApp } from './FlutterApp.js';

/** Ruta que sirve el listado de secciones de quien mira. */
const RUTA_LISTADO = '/api/v1/mi-horario';

/** Prefijo de todas las rutas del aula. */
const RUTA_AULA = '/api/v1/aula/';

/** Las dos pestañas del aula, con el rótulo que publican. */
export const PESTANA_TABLON = 'Tablón';
export const PESTANA_TRABAJO = 'Trabajo de Clase';

/**
 * Rótulos del ciclo de la tarea — **los tres están medidos**.
 *
 *   · `Nueva tarea` y `Calificar` — del volcado del panel de trabajo del
 *     docente, 2026-10-02.
 *   · `Listo` — del volcado del modal de éxito tras publicar, 2026-10-03. Es el
 *     que cierra el modal; sin él, `Calificar` queda **detrás** y el caso
 *     siguiente falla con «No hay ningún widget pulsable».
 *
 * Aquí vivieron cinco constantes **inferidas** —`BOTON_PUBLICAR`,
 * `BOTON_CONFIRMAR`, `BOTON_CALIFICAR_CONFIRMAR`, `BOTON_DEVOLVER`,
 * `CAMPO_NOTA`— y se retiraron el 2026-10-03. La razón queda escrita para que
 * nadie las reintroduzca por comodidad: **una constante inferida con nombre de
 * contrato se lee como un hecho.** `BOTON_CONFIRMAR` decía «Aceptar» y el botón
 * real es «Crear y publicar»; quien leyera este archivo habría construido sobre
 * una invención.
 *
 * Los que faltan se añaden cuando se midan, con su evidencia en el comentario.
 */
export const BOTON_NUEVA_TAREA = 'Nueva tarea'; // medido
export const BOTON_CALIFICAR = 'Calificar'; // medido
export const BOTON_CERRAR_MODAL = 'Listo'; // medido — cierra el modal de éxito tras publicar

// **NO hay más constantes, y es deliberado.** Aquí vivieron `BOTON_PUBLICAR`,
// `BOTON_CONFIRMAR`, `BOTON_CALIFICAR_CONFIRMAR`, `BOTON_DEVOLVER` y `CAMPO_NOTA`
// como valores **inferidos**. Se retiraron el 2026-10-03 porque una constante
// inferida con nombre de contrato **se lee como un hecho**: `BOTON_CONFIRMAR`
// decía «Aceptar» y el botón real es «Crear y publicar», así que cualquiera que
// leyera el archivo habría construido sobre una invención.
//
// Los que faltan se añaden **cuando se midan**, y su comentario dirá cómo:
//   · `CAMPO_NOTA`, `BOTON_DEVOLVER`, `BOTON_CALIFICAR_CONFIRMAR` — requieren
//     abrir una entrega concreta dentro del libro de calificaciones, y ese paso
//     todavía no se ha medido. El libro abre con las 3 entregas ya generadas
//     —lo confirma el modal al publicar— pero **no las lista en la vista de
//     entrada**: hay un paso intermedio que aún no se conoce.

/**
 * Comparación de texto del aula: subcadena e **insensible a mayúsculas**.
 *
 * El listado pinta «Soldadura por Arco [SEMILLA]» y el encabezado del aula
 * «SOLDADURA POR ARCO [SEMILLA]». Es el mismo dato con dos capitalizaciones, y
 * codificarlas por separado deja la segunda obsoleta en silencio la primera vez
 * que alguien cambie un estilo.
 */
const OPCIONES = { ignorarMayusculas: true } as const;

export class AulaVirtualPage {
  readonly app: FlutterApp;

  constructor(page: Page) {
    this.app = new FlutterApp(page);
    this.page = page;
  }

  private readonly page: Page;

  /**
   * Entra a «Mis aulas» y espera la respuesta o la tarjeta ya montada.
   *
   * El listener se registra **antes** de pulsar: si se registra después, una
   * respuesta rápida llega antes que él y la espera se agota sin que nada esté
   * mal —un fallo que apunta al menú cuando el problema es el orden de dos
   * líneas—.
   */
  async irAMisAulas(seccion?: string): Promise<Response | null> {
    // Si el login ya dejó el listado montado, no pulses el elemento seleccionado
    // ni esperes una petición que no va a repetirse. Este caso se observó en la
    // medición de rendimiento: la API había respondido, pero el helper esperaba
    // 30 s porque la respuesta ocurrió antes de registrar el listener.
    if (seccion && (await this.cuantos(seccion)) > 0) return null;

    const respuesta = this.page.waitForResponse((r) => r.url().includes(RUTA_LISTADO), {
      timeout: 30_000,
    });
    await this.app.pulsar('Mis aulas');

    try {
      if (!seccion) return await respuesta;

      // Con sección conocida, cualquiera de estas señales es suficiente: la
      // respuesta de red confirma la consulta, y la tarjeta confirma que el
      // panel ya está usable. Así no se paga el timeout completo si el listado
      // ya se cargó durante el login.
      const tarjeta = expect
        .poll(async () => await this.cuantos(seccion), {
          timeout: 30_000,
          message: `la tarjeta «${seccion}» no apareció en «Mis aulas».\\n${await this.diagnostico()}`,
        })
        .toBeGreaterThan(0)
        .then(() => null);
      return await Promise.race([respuesta, tarjeta]);
    } catch (error) {
      // Sin sección conocida conservamos la señal histórica del menú; con sección
      // conocida, sólo se acepta el fallback si la tarjeta real está montada.
      const panelMontado = seccion
        ? (await this.cuantos(seccion)) > 0
        : (await this.cuantos('Mis aulas')) > 0;
      if (panelMontado) return null;
      throw error;
    }
  }

  /**
   * Abre el aula de la sección cuyo título contenga [seccion].
   *
   * Devuelve la **primera** respuesta del aula, que es la que confirma que la
   * pantalla cargó. La tarjeta se espera antes de pulsarla: el listado llega por
   * red y pulsar sobre un árbol que aún no la tiene daría «no hay ningún
   * título», que es un mensaje que culpa al rótulo en vez de a la carrera.
   */
  async abrirAula(seccion: string): Promise<Response> {
    // `ignorarMayusculas`: la misma entidad se pinta en capitalización normal en
    // el listado y en MAYÚSCULAS dentro del aula. Sin esto habría que codificar
    // dos cadenas para el mismo dato.
    await expect
      .poll(async () => await this.cuantos(seccion), {
        timeout: 30_000,
        message: `la tarjeta «${seccion}» no apareció en «Mis aulas».\n${await this.app.diagnostico()}`,
      })
      .toBeGreaterThan(0);

    const respuesta = this.page.waitForResponse((r) => r.url().includes(RUTA_AULA), {
      timeout: 30_000,
    });
    await this.app.pulsar(seccion, OPCIONES);
    return respuesta;
  }

  /**
   * Cuenta las tarjetas del listado **esperando a que el panel pinte**.
   *
   * No basta con leer tras la respuesta de red: el panel recibe el JSON y tarda
   * alrededor de dos segundos en dibujarlo —medido en el log del backend, donde
   * `mi-horario` responde en 4,6 s y la tarjeta aparece después—. Contar justo
   * después de la respuesta devuelve **cero** y el fallo culpa al conteo cuando
   * el problema es la carrera.
   *
   * Se cuenta y se devuelve el número, en vez de asertar aquí dentro, para que la
   * prueba pueda fijar el valor exacto: lo que hay que demostrar es que el
   * gateway colapsa las franjas a **una** fila, y un `> 0` pasaría con la
   * duplicación puesta.
   */
  async contarTarjetas(seccion: string): Promise<number> {
    await expect
      .poll(async () => await this.cuantos(seccion), {
        timeout: 30_000,
        message: `la tarjeta «${seccion}» no apareció en «Mis aulas».\n${await this.app.diagnostico()}`,
      })
      .toBeGreaterThan(0);

    return this.cuantos(seccion);
  }

  /**
   * Espera a que el aula esté montada.
   *
   * La señal es la pestaña «Tablón» por **rol**, no el título: el título viene
   * del listado y ya estaba antes de que el aula cargara, así que esperarlo
   * daría por buena una pantalla que todavía no existe.
   */
  async esperarAula(): Promise<void> {
    await expect
      .poll(async () => await this.app.cuantos(PESTANA_TABLON, OPCIONES), {
        timeout: 30_000,
        message: `el aula no montó la pestaña «${PESTANA_TABLON}».\n${await this.app.diagnostico()}`,
      })
      .toBeGreaterThan(0);
  }

  /**
   * Cambia de pestaña y **espera a que el cambio ocurra de verdad**.
   *
   * [esperarPor] es un rótulo que **sólo existe en la vista destino**. Es
   * obligatorio y no tiene valor por defecto a propósito: sin él, la única forma
   * de saber que la pestaña conmutó sería comparar la firma del árbol, y **eso se
   * satisface con ruido de repintado** —un nodo que se re-renderiza cambia la
   * firma sin que la pestaña se haya movido—. Medido el 2026-10-02: la misma
   * conmutación pasó por firma en una corrida y falló en la siguiente.
   *
   * Un nodo exclusivo no admite esa ambigüedad: `Nueva tarea` no puede aparecer
   * sin que el panel de trabajo esté montado.
   */
  async abrirPestana(rotulo: string, esperarPor: string): Promise<void> {
    await this.app.pulsarPestana(rotulo, OPCIONES);
    await expect
      .poll(async () => await this.cuantos(esperarPor), {
        timeout: 20_000,
        message:
          `la pestaña «${rotulo}» no conmutó: «${esperarPor}» no apareció.\n` +
          (await this.app.diagnostico()),
      })
      .toBeGreaterThan(0);

    // **Y después, esperar a que la pantalla TERMINE de montar.**
    //
    // Medido el 2026-10-05: el rótulo exclusivo aparece pronto —el árbol va por
    // ~39 nodos— pero la pantalla completa tiene **56**. Pulsar en ese hueco hace
    // que el modal no monte: con 56 nodos monta con los dos gestos, con 39 no
    // monta con ninguno. **El fallo no era el gesto, era pulsar sobre una
    // pantalla a medio pintar.**
    //
    // La condición es «el árbol deja de crecer», no «aparece un nodo»: un nodo
    // puede aparecer antes de que el resto esté listo, y ése fue el error que
    // convirtió esto en intermitente. Dos muestras consecutivas con el mismo
    // número de nodos significan que el montaje terminó.
    await expect
      .poll(
        async () => {
          const a = (await this.app.nodos()).length;
          const b = (await this.app.nodos()).length;
          return a === b ? a : -1;
        },
        {
          timeout: 20_000,
          intervals: [200, 200, 300, 300, 400],
          message:
            `el árbol del aula no se estabilizó tras «${rotulo}».\n` +
            (await this.app.diagnostico()),
        },
      )
      .toBeGreaterThan(0);
  }

  /** Cuántos nodos del árbol contienen [texto]. Sirve para aserciones de estado. */
  async cuantos(texto: string): Promise<number> {
    return this.app.cuantos(texto, OPCIONES);
  }

  /**
   * Firma del árbol: rol y etiqueta de cada nodo, ordenados.
   *
   * Es la condición de salida de «cambió de pantalla», y existe porque un
   * **conteo no discrimina**: esperar «más de dos botones» se satisface con la
   * pantalla anterior, así que una prueba así pasa sin que ocurra lo que dice
   * medir. Comparar la firma entera no se puede satisfacer sin un cambio real, y
   * no exige conocer de antemano los rótulos del panel nuevo.
   */
  async firmaDelArbol(): Promise<string> {
    const nodos = await this.app.nodos();
    return nodos
      .map((n) => `${n.rol}:${n.etiqueta}`)
      .sort()
      .join('|');
  }

  /** Volcado del árbol, para mensajes de fallo. */
  async diagnostico(): Promise<string> {
    return this.app.diagnostico();
  }

}
