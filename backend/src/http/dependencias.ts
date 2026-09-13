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
}
