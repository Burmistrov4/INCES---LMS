// Page Object de la pantalla de inicio de sesión.
//
// Las etiquetas no están inventadas: salen de `lib/screens/login_screen.dart`
// —`labelText: 'Cédula o Correo'`, `labelText: 'Contraseña'` y el botón
// `Text('Ingresar al sistema')`—. Flutter deriva el `aria-label` del nodo
// semántico del texto del widget, así que ésos son los nombres que aparecen en
// el árbol.

import { expect, type Page } from '@playwright/test';
import { FlutterApp } from './FlutterApp.js';

/** La etiqueta del campo de usuario, tal como la declara el widget. */
export const CAMPO_USUARIO = 'Cédula o Correo';

/** La etiqueta del campo de contraseña. */
export const CAMPO_CLAVE = 'Contraseña';

/** La etiqueta del botón de envío. */
export const BOTON_ENTRAR = 'Ingresar al sistema';

/**
 * Un rótulo que sólo existe DESPUÉS de entrar.
 *
 * Se usa como señal de que el inicio de sesión terminó de verdad. Esperar a que
 * desaparezca el botón de entrar no sirve: Flutter reconstruye el árbol y hay un
 * instante en el que no hay ni lo uno ni lo otro.
 */
export const SENAL_DE_SESION = 'Inscripciones y Cupos';

export class LoginPage {
  readonly app: FlutterApp;

  constructor(page: Page) {
    this.app = new FlutterApp(page);
  }

  async abrir(): Promise<void> {
    await this.app.abrir('/');
  }

  /**
   * Inicia sesión con credenciales reales contra el Supabase real.
   *
   * **No hay mock ni sesión inyectada, y es deliberado.** El objetivo de la
   * suite es la ruta `package:web` de la descarga, que sólo existe si la sesión
   * la abrió el propio cliente: el JWT que la vista `security_invoker` usa para
   * decidir qué filas devuelve lo pone `supabase_flutter` al autenticar. Una
   * sesión sembrada a mano en `localStorage` probaría un estado que la app nunca
   * produce por sí sola.
   */
  async entrar(usuario: string, clave: string): Promise<void> {
    await this.app.escribirEn(CAMPO_USUARIO, usuario);
    await this.app.escribirEn(CAMPO_CLAVE, clave);
    await this.app.pulsar(BOTON_ENTRAR);

    // El panel de administración tarda en montar; la señal es un rótulo del menú.
    await expect
      .poll(async () => await this.app.cuantos(SENAL_DE_SESION), {
        message:
          'Se envió el formulario de acceso pero no apareció el panel. Revisa las ' +
          'credenciales y que la cuenta sea de administración.\n' +
          (await this.app.diagnostico()),
        timeout: 45_000,
      })
      .toBeGreaterThan(0);
  }
}
