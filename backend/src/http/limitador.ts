/**
 * Limitador de intentos en memoria, por clave (normalmente la IP).
 *
 * ¿Por qué no una dependencia? Porque lo que hace falta aquí es pequeño y muy
 * concreto —frenar la fuerza bruta contra los dos endpoints públicos que aceptan
 * un secreto: `/auth/activar` y `/auth/restablecer-codigo`—, y una dependencia
 * traería su propio modelo de configuración y su propio ciclo de vida.
 *
 * **Alcance honesto:** la ventana vive en la memoria del proceso. Con una sola
 * instancia del backend (el caso de este proyecto) es exactamente lo que se
 * necesita. Si algún día se escala a varias instancias, cada una llevaría su
 * propia cuenta y el límite efectivo se multiplicaría: en ese momento habrá que
 * mover el estado a un almacén compartido (Redis o una tabla). Queda dicho aquí
 * para que nadie lo dé por hecho.
 *
 * La ventana es **deslizante por conteo simple**: se guardan los instantes de
 * los intentos y se descartan los que salieron de la ventana. No se usa un
 * contador con reinicio fijo porque permite el doble de intentos a caballo entre
 * dos ventanas.
 */
export interface Limitador {
  /**
   * Registra un intento y dice si se permite.
   *
   * `true` = adelante; `false` = se pasó del límite y hay que responder 429.
   */
  permitir(clave: string): boolean;

  /** Cuántos intentos quedan en la ventana para esa clave (para pruebas). */
  restantes(clave: string): number;

  /** Olvida el historial de una clave (se usa tras un canje exitoso). */
  olvidar(clave: string): void;
}

export function crearLimitador(opciones: { maximo: number; ventanaMs: number }): Limitador {
  const intentos = new Map<string, number[]>();

  /** Descarta los instantes que ya salieron de la ventana y devuelve los vivos. */
  const vivos = (clave: string, ahora: number): number[] => {
    const previos = intentos.get(clave) ?? [];
    const dentro = previos.filter((t) => ahora - t < opciones.ventanaMs);
    if (dentro.length === 0) intentos.delete(clave);
    else intentos.set(clave, dentro);
    return dentro;
  };

  return {
    permitir(clave) {
      const ahora = Date.now();
      const dentro = vivos(clave, ahora);
      if (dentro.length >= opciones.maximo) return false;
      dentro.push(ahora);
      intentos.set(clave, dentro);
      return true;
    },
    restantes(clave) {
      return Math.max(0, opciones.maximo - vivos(clave, Date.now()).length);
    },
    olvidar(clave) {
      intentos.delete(clave);
    },
  };
}
