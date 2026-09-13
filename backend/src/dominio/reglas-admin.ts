/**
 * Reglas del cambio de rol, como funciones puras.
 *
 * Viven aquí y no dentro del manejador de la ruta por la misma razón que
 * `comprobarModulo` en los plugins de módulos: una regla de negocio enterrada en
 * un manejador sólo se puede probar levantando HTTP y montando repositorios. Como
 * función pura se prueban todos los casos —incluidos los que la API casi nunca
 * alcanza— sin montar nada.
 *
 * Esa distinción importa aquí: el caso «dejar el sistema sin administradores» es
 * **inalcanzable desde la API** en el funcionamiento normal (ver abajo), pero la
 * regla debe existir igualmente porque:
 *
 *   · el día que se añada una ruta para desactivar o borrar usuarios, pasa a ser
 *     alcanzable sin tocar nada más;
 *   · deja escrito en un solo sitio cuál es la invariante, en vez de que cada
 *     ruta nueva tenga que redescubrirla.
 *
 * La barrera de verdad, en todo caso, no está aquí: está en el trigger
 * `proteger_ultimo_admin` de PostgreSQL, que además cubre lo que esta función no
 * puede —la carrera entre dos degradaciones simultáneas y cualquier cambio hecho
 * por fuera de la API.
 */
import { ErrorApi } from './errores.js';
import type { Perfil, Rol } from './tipos.js';

export interface CambioDeRol {
  /** Quién ejecuta la acción. Siempre es un administrador activo. */
  actorId: string;
  objetivoId: string;
  nuevoRol: Rol;
  /** Perfil actual del objetivo, o `null` si no existe. */
  objetivo: Perfil | null;
  /** Administradores activos que hay ahora mismo. */
  adminsActivos: number;
}

/**
 * Lanza si el cambio de rol dejaría el sistema sin administradores.
 *
 * El orden de las comprobaciones no es casual: primero el caso más probable y el
 * que merece el mensaje más útil, y sólo después el resto.
 */
export function revisarCambioDeRol(cambio: CambioDeRol): void {
  // 1. Quitarse el rol a uno mismo. Es el error que un administrador comete de
  //    verdad, y el mensaje debe decirle qué hacer, no describir una invariante.
  if (cambio.objetivoId === cambio.actorId && cambio.nuevoRol !== 'admin') {
    throw ErrorApi.conflicto(
      'AUTO_DEGRADACION',
      'No puedes quitarte tu propio rol de administrador. Pídeselo a otro administrador.',
    );
  }

  // 2. Promover a administrador nunca reduce el número de administradores.
  if (cambio.nuevoRol === 'admin') return;

  // 3. Un objetivo que no existe se rechaza aquí, para que el error sea
  //    `PERFIL_INEXISTENTE` y no un fallo de PostgREST sin contexto.
  if (cambio.objetivo === null) {
    throw ErrorApi.noEncontrado(
      'PERFIL_INEXISTENTE',
      `No existe el usuario "${cambio.objetivoId}".`,
    );
  }

  // 4. Sólo hay algo que proteger si el objetivo es HOY un administrador activo.
  //    A alguien que ya no lo era, quitarle el rol no reduce nada.
  if (cambio.objetivo.rol !== 'admin' || !cambio.objetivo.activo) return;

  // 5. Y sólo si es el último que queda.
  //
  //    Nota de alcance: en el funcionamiento normal esto NO puede ocurrir, porque
  //    quien ejecuta la acción es a su vez un administrador activo, así que
  //    `adminsActivos` es como mínimo 2 cuando el objetivo es otro usuario. Se
  //    mantiene porque define la invariante en un único sitio y porque una ruta
  //    futura de desactivación de usuarios sí podría alcanzarla.
  if (cambio.adminsActivos <= 1) {
    throw ErrorApi.conflicto(
      'ULTIMO_ADMIN',
      'No puedes dejar el sistema sin administradores. Promueve a otra persona antes de quitarle el rol a esta.',
      { administradoresActivos: cambio.adminsActivos },
    );
  }
}
