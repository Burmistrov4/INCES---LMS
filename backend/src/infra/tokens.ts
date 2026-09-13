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
import { createHash, randomBytes } from 'node:crypto';

/** Token de alta entropía, listo para ir en una URL. */
export function generarToken(): string {
  return randomBytes(32).toString('base64url');
}

/** Huella SHA-256 del token, en hexadecimal. Estable e idempotente. */
export function hashearToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
