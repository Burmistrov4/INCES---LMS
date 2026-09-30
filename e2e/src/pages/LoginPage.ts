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

/**
 * Un rótulo que sólo existe en el panel del **alumno**.
 *
 * Hace falta porque [SENAL_DE_SESION] es un rótulo del panel de administración
 * —«Inscripciones y Cupos» es una sección suya— y usarlo para comprobar un
 * acceso de alumno da un fallo con el mensaje equivocado: diría «revisa las
 * credenciales» cuando lo que pasa es que la señal no es de ese rol.
 *
 * `Mi inscripción` es la **primera** sección del menú del alumno y no depende de
 * ningún módulo conmutable (`aspirante_dashboard.dart`: no lleva `modulo:`), así
 * que aparece aunque el administrador haya apagado medio cPanel. Es la señal más
 * estable que hay para decir «este alumno ya entró».
 */
export const SENAL_DE_SESION_ALUMNO = 'Mi inscripción';

export class LoginPage {
  readonly app: FlutterApp;

  constructor(page: Page) {
    this.app = new FlutterApp(page);
  }

  async abrir(): Promise<void> {
    // **`/#/login`, no `/`.** Hasta el 2026-09-27 la raíz sin sesión caía en la
    // pantalla de acceso, así que abrir `/` bastaba. Al completarse la **portada
    // pública**, `AuthGate` empezó a devolver `LandingPage` para `/` (el bundle
    // que dio 10/10 el 2026-09-27 era del 26 a la 01:40, es decir **anterior** a
    // la portada), y la suite se quedó tecleando en un formulario que ya no
    // estaba en pantalla.
    //
    // Cómo se veía: «No hay ningún campo con la etiqueta «Cédula o Correo»», con
    // el diagnóstico imprimiendo la **portada entera** —oferta formativa y
    // tarjetas de curso— como si fueran los campos de la app. Y no se podía leer
    // desde fuera, porque la anotación del check-run sólo decía «exit code 1»
    // (arreglado en `b624628`).
    //
    // La ruta va **directa y no pulsando «Iniciar sesión»** a propósito: lo que
    // esta suite mide es la ruta de descarga del CSV, no la portada, y un clic de
    // más mete su propio fallo en la ecuación. Flutter Web usa la estrategia de
    // **hash**, así que la ruta vive en el fragmento —`/login` a secas pediría
    // `index.html` sin fragmento y volvería a caer en `/`—.
    await this.app.abrir('/#/login');
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
  async entrar(usuario: string, clave: string, senal: string = SENAL_DE_SESION): Promise<void> {
    await this.app.escribirEn(CAMPO_USUARIO, usuario);
    await this.app.escribirEn(CAMPO_CLAVE, clave);
    await this.app.pulsar(BOTON_ENTRAR);

    // El panel tarda en montar; la señal es un rótulo del menú.
    //
    // La señal se recibe por parámetro y **no se deduce del rol** porque el
    // cliente no sabe el rol hasta después de entrar: lo único observable desde
    // fuera es qué rótulos aparecen. Pasar el rótulo equivocado no da un falso
    // verde —da un rojo con el rótulo en el mensaje—, que es el modo de fallo
    // correcto.
    await expect
      .poll(async () => await this.app.cuantos(senal), {
        message:
          `Se envió el formulario de acceso pero no apareció «${senal}». Revisa las ` +
          'credenciales y que la cuenta tenga el rol al que corresponde esa señal.\n' +
          (await this.app.diagnostico()),
        timeout: 45_000,
      })
      .toBeGreaterThan(0);
  }
}
