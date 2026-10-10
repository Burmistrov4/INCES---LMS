/**
 * Generación y sellado de tokens de invitación.
 *
 * El token es el secreto que viaja por el enlace de activación. En la base de
 * datos sólo guardamos su huella SHA-256 (`token_hash`), nunca el token en claro:
 * si alguien volcara la tabla no obtendría tokens utilizables.
 *
 * Se usa `base64url` (sin `=` de relleno) porque va en la propia URL del enlace,
 * y `randomBytes(32)` dan 256 bits de entropía: suficiente para que un token sea
 * inadivinable.
 */
import { createHash, randomBytes, randomInt } from 'node:crypto';

/** Token de alta entropía, listo para ir en una URL. */
export function generarToken(): string {
  return randomBytes(32).toString('base64url');
}

/** Huella SHA-256 del token, en hexadecimal. Estable e idempotente. */
export function hashearToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Alfabeto del código de recuperación: sin caracteres que se confunden al
 * dictarlos o transcribirlos a mano (`0`/`O`, `1`/`I`/`L`). El código se entrega
 * en mano o por un canal interno, así que lo lee y lo teclea una persona.
 */
const ALFABETO_LEGIBLE = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** Cuántos caracteres tiene el código, sin contar los guiones de lectura. */
const LARGO_CODIGO = 12;

/**
 * Código de restablecimiento de contraseña, legible y de alta entropía.
 *
 * Se elige un código corto y dictable **en lugar del token de 32 bytes** de las
 * invitaciones porque aquí el canal es una persona: un administrador lo lee de
 * la pantalla y se lo dice al titular. 12 caracteres de un alfabeto de 31
 * símbolos son ~59 bits de entropía — inalcanzable por fuerza bruta dentro de su
 * ventana de 30 minutos, incluso sin contar el límite de intentos.
 *
 * `randomInt` (no `randomBytes % n`) evita el sesgo de módulo que haría algunos
 * caracteres más probables que otros.
 *
 * Devuelve el código **con guiones** para leerlo en grupos de cuatro. El
 * llamante debe normalizarlo antes de hashearlo (ver `normalizarCodigo`).
 */
export function generarCodigoRecuperacion(): string {
  const bruto = Array.from(
    { length: LARGO_CODIGO },
    () => ALFABETO_LEGIBLE[randomInt(ALFABETO_LEGIBLE.length)],
  ).join('');

  return bruto.match(/.{1,4}/g)?.join('-') ?? bruto;
}

/**
 * Normaliza un código tecleado por una persona: sin guiones, sin espacios y en
 * mayúsculas. Es la forma canónica con la que se calcula el hash, así que quien
 * lo teclee con o sin guiones, en minúsculas o con espacios, canjea igual.
 */
export function normalizarCodigo(codigo: string): string {
  return codigo.replace(/[\s-]/g, '').toUpperCase();
}
