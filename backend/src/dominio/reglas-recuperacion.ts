/**
 * Reglas de vida de un código de restablecimiento de contraseña, como función pura.
 *
 * Igual que `reglas-invitaciones.ts`: la decisión vive fuera del manejador para
 * poder probarse sin montar HTTP ni repositorios. El orden es el mismo criterio
 * que en las invitaciones y por el mismo motivo: **revocado > usado > expirado >
 * válido**. Un código anulado no revive, y uno canjeado sigue canjeado aunque
 * además haya caducado.
 */
import type { CodigoRecuperacion } from './tipos.js';

export type EstadoCodigoRecuperacion = 'valido' | 'usado' | 'expirado' | 'revocado';

/**
 * Decide si un código de recuperación todavía sirve.
 *
 * Devuelve un valor y no lanza: quien llama elige el código HTTP y el mensaje.
 * **Ojo con el mensaje:** hacia fuera todos los motivos de rechazo deben leerse
 * igual («el código no es válido o ya caducó») para no revelar si un código
 * existió, si estaba usado o si simplemente no coincidía.
 */
export function estadoDeCodigoRecuperacion(
  codigo: Pick<CodigoRecuperacion, 'usedAt' | 'revokedAt' | 'expiresAt'>,
  ahora: Date = new Date(),
): EstadoCodigoRecuperacion {
  if (codigo.revokedAt !== null && codigo.revokedAt !== undefined) return 'revocado';
  if (codigo.usedAt !== null && codigo.usedAt !== undefined) return 'usado';
  if (new Date(codigo.expiresAt).getTime() <= ahora.getTime()) return 'expirado';
  return 'valido';
}
