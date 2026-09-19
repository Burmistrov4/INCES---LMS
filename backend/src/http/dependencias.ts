import type { EnvioCorreo } from '../infra/correo.js';
import type { PuertaAlmacenamiento, Repositorios } from '../dominio/puertos.js';
import type { CacheModulos, CacheParametros } from '../infra/cache.js';

/**
 * Todo lo que las rutas necesitan, en un solo objeto.
 *
 * Ninguna ruta importa un singleton ni lee `process.env`: recibe esto por
 * parámetro. Es lo que permite montar la API entera con dobles en los tests.
 */
export interface DependenciasRutas {
  version: string;
  caches: {
    modulos: CacheModulos;
    parametros: CacheParametros;
  };
  /** Comprueba que la base de datos responde. Usado por `/salud/profundo`. */
  revisarBase: () => Promise<boolean>;
  /**
   * Repositorios con la service_role key. Los usa la ruta de activación de
   * invitaciones (pública): necesita saltarse RLS para consultar por el hash del
   * token y crear el usuario, cosas que el cliente anónimo no puede hacer.
   */
  reposAdmin: Repositorios;
  /** Enviador de correo transaccional (Resend). */
  enviarCorreo: EnvioCorreo;
  /**
   * Origen del frontend (Flutter web). Se usa para construir el enlace de
   * activación que se envía por correo y se devuelve en la respuesta.
   */
  urlFrente: string;
  /**
   * Almacenamiento pesado (Cloudflare R2), o `null` si no está configurado.
   *
   * Es `null` y no una excepción porque R2 es una capacidad **opcional**: el
   * backend tiene que poder arrancar sin ella, y de hecho arranca así en
   * cualquier entorno donde no se hayan definido las cuatro variables. Quien la
   * consuma decide qué hacer con ese `null` —la ruta de firmas responde 503— en
   * vez de que el proceso entero no levante por un módulo que puede no usarse.
   */
  almacenamiento: PuertaAlmacenamiento | null;
}
