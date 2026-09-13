import type { PuertaModulos, PuertaParametros } from '../dominio/puertos.js';
import type { ModuloSistema, ParametroSistema } from '../dominio/tipos.js';

/**
 * Caché con vencimiento por tiempo (TTL).
 *
 * El caso de uso es concreto: cada petición necesita saber si el módulo que
 * invoca está encendido. Sin caché, eso es una consulta a la base de datos por
 * petición — y el interruptor del administrador cambia como mucho unas pocas
 * veces al día.
 *
 * Dos detalles que importan:
 *  · Anti-estampida: si la caché está fría y llegan veinte peticiones a la vez,
 *    sólo una consulta. Las otras esperan la misma promesa. Sin esto, un
 *    reinicio del contenedor produce veinte consultas idénticas de golpe.
 *  · `ttlMs = 0` desactiva la caché por completo, que es lo que quieren los
 *    tests para ver el efecto inmediato de un cambio.
 */
export class CacheConTtl<T> {
  #valor: T | null = null;
  #expiraEn = 0;
  #enVuelo: Promise<T> | null = null;

  constructor(
    private readonly cargar: () => Promise<T>,
    private readonly ttlMs: number,
  ) {}

  async obtener(): Promise<T> {
    if (this.#valor !== null && Date.now() < this.#expiraEn) {
      return this.#valor;
    }

    if (this.#enVuelo) return this.#enVuelo;

    this.#enVuelo = this.cargar()
      .then((valor) => {
        this.#valor = valor;
        this.#expiraEn = Date.now() + this.ttlMs;
        return valor;
      })
      .finally(() => {
        this.#enVuelo = null;
      });

    return this.#enVuelo;
  }

  invalidar(): void {
    this.#valor = null;
    this.#expiraEn = 0;
  }
}

/** Caché del catálogo de módulos. */
export class CacheModulos {
  readonly #cache: CacheConTtl<ModuloSistema[]>;

  constructor(puerta: PuertaModulos, ttlMs: number) {
    this.#cache = new CacheConTtl(() => puerta.todos(), ttlMs);
  }

  async todos(): Promise<ModuloSistema[]> {
    return this.#cache.obtener();
  }

  async porClave(clave: string): Promise<ModuloSistema | null> {
    const modulos = await this.#cache.obtener();
    return modulos.find((m) => m.clave === clave) ?? null;
  }

  invalidar(): void {
    this.#cache.invalidar();
  }
}

/** Caché de parámetros del sistema. Siempre incluye los privados. */
export class CacheParametros {
  readonly #cache: CacheConTtl<ParametroSistema[]>;

  constructor(puerta: PuertaParametros, ttlMs: number) {
    this.#cache = new CacheConTtl(() => puerta.todos(true), ttlMs);
  }

  async porClave(clave: string): Promise<ParametroSistema | null> {
    const parametros = await this.#cache.obtener();
    return parametros.find((p) => p.clave === clave) ?? null;
  }

  /**
   * `modo_mantenimiento` activo ⇒ la API sólo atiende a administradores.
   *
   * Falla **abierto**: si no se puede leer el parámetro, devuelve `false` y la
   * petición sigue su curso. El modo mantenimiento es una comodidad operativa,
   * no un control de seguridad. Bloquear todo el tráfico cuando la lectura falla
   * daría un 503 engañoso ("estamos en mantenimiento") ocultando el problema
   * real, que es que la base de datos no responde. La petición fallará igual,
   * pero con un error que sí describe lo que pasa.
   */
  async mantenimientoActivo(): Promise<boolean> {
    try {
      const parametro = await this.porClave('modo_mantenimiento');
      return parametro?.valor === true;
    } catch {
      return false;
    }
  }

  invalidar(): void {
    this.#cache.invalidar();
  }
}
