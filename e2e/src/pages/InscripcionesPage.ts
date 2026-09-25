// Page Object del panel de inscripciones, donde vive el botón de exportación.
//
// Etiquetas tomadas del código, no supuestas:
//   · `lib/screens/admin_dashboard.dart` — la entrada del menú se titula
//     `'Inscripciones y Cupos'` y el panel se monta por un `switch` sobre ese
//     título, no por una ruta. Por eso se navega pulsando el menú.
//   · `lib/screens/admin/cpanel_inscripciones_panel.dart` — el botón es un
//     `OutlinedButton.icon` con `label: Text('Exportar Planilla HACER (.csv)')`,
//     y cambia a `'Exportando…'` mientras trabaja.

import { expect, type Download, type Page } from '@playwright/test';
import { FlutterApp } from './FlutterApp.js';

/** La entrada del menú lateral que abre el panel. */
export const MENU_INSCRIPCIONES = 'Inscripciones y Cupos';

/** La etiqueta del botón de exportación, en reposo. */
export const BOTON_EXPORTAR = 'Exportar Planilla HACER (.csv)';

/** La etiqueta del botón mientras exporta. */
export const BOTON_EXPORTANDO = 'Exportando…';

/**
 * Tiempo máximo para que el navegador entregue el archivo.
 *
 * **No es un número redondo elegido a ojo.** Medido con `playwright-core` +
 * Chromium contra un `Blob` real: la **primera** descarga de un proceso de
 * navegador nuevo tarda entre 4,4 s y 5,7 s, y las siguientes entre 200 y 270 ms
 * —entre 20 y 25 veces menos—. Es un coste de arranque del gestor de descargas,
 * no de la aplicación: se comprobó invirtiendo el orden de los casos y el lento
 * pasó a ser el otro. Un `timeout` de 5 s —el que uno escribiría por defecto—
 * hace fallar la suite por el sitio equivocado.
 */
export const ESPERA_DE_DESCARGA = 30_000;

export class InscripcionesPage {
  readonly app: FlutterApp;

  constructor(page: Page) {
    this.app = new FlutterApp(page);
  }

  /** Abre el panel desde el menú lateral. */
  async abrir(): Promise<void> {
    await this.app.pulsar(MENU_INSCRIPCIONES);
    // El panel existe cuando su primer botón de exportación está en el árbol.
    await expect
      .poll(async () => await this.app.cuantos(BOTON_EXPORTAR), {
        message:
          'Se pulsó «Inscripciones y Cupos» pero no apareció ningún botón de exportación. ' +
          'Puede que la cuenta no sea de administración, o que no haya secciones.\n' +
          (await this.app.diagnostico()),
        timeout: 45_000,
      })
      .toBeGreaterThan(0);
  }

  /** Cuántas tarjetas de sección hay, contadas por sus botones de exportación. */
  async tarjetas(): Promise<number> {
    return this.app.cuantos(BOTON_EXPORTAR);
  }

  /**
   * Pulsa el botón de exportación de UNA sección y devuelve la descarga.
   *
   * **La desambiguación es geométrica y no cosmética.** El botón se llama igual
   * en todas las tarjetas —«Exportar Planilla HACER (.csv)»— porque el panel
   * pinta uno por sección. El árbol semántico de Flutter es plano, así que no
   * hay forma de decir «el de esta tarjeta» por jerarquía; se resuelve buscando
   * el botón cuya caja cae dentro de la caja de la tarjeta de [nombreSeccion].
   *
   * **El `waitForEvent` se registra ANTES de pulsar**, y no es un detalle de
   * estilo: una descarga de `Blob` se dispara y se resuelve en el mismo instante
   * en que se pulsa, así que un `await click(); await waitForEvent(...)` pierde
   * el evento por una carrera.
   */
  async exportarSeccion(nombreSeccion: string): Promise<Download> {
    const boton = await this.app.botonDeTarjeta(nombreSeccion, BOTON_EXPORTAR);

    const espera = this.app.page.waitForEvent('download', { timeout: ESPERA_DE_DESCARGA });
    await boton.dispatchEvent('click');

    return espera;
  }

  /** `true` si la sección muestra el botón en estado «Exportando…». */
  async estaExportando(): Promise<boolean> {
    return (await this.app.cuantos(BOTON_EXPORTANDO)) > 0;
  }
}
