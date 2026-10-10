/**
 * Reglas de vida de una invitación de docente, como función pura.
 *
 * Igual que `reglas-admin.ts`: la lógica de negocio vive fuera del manejador de
 * la ruta para poder probarse sin montar HTTP ni repositorios. La base de datos
 * también impone `expires_at > created_at` y la API espeja el resto, pero el
 * mensaje que recibe el profesor lo decide esta función.
 */
import type { EstadoInvitacion, InvitacionDocente } from './tipos.js';

/**
 * Decide si una invitación sigue usable.
 *
 * **El orden importa y es una decisión de negocio:** revocada > usada >
 * caducada > válida. Una invitación revocada **no revive** aunque después se
 * marque usada o su fecha siga en el futuro; una usada sigue siendo usada aunque
 * además haya caducado. Devuelve un valor y no lanza: quien llama elige el
 * código de error, porque 409 (usada), 410 (caducada) y 403 (revocada) son
 * distintos y el profesor debe saber cuál es su caso.
 */
export function estadoDeInvitacion(
  invitacion: Pick<InvitacionDocente, 'isUsed' | 'expiresAt' | 'revokedAt'>,
  ahora: Date = new Date(),
): EstadoInvitacion {
  if (invitacion.revokedAt !== null && invitacion.revokedAt !== undefined) {
    return 'revocada';
  }

  if (invitacion.isUsed) return 'usada';

  // `expires_at` es el instante en que deja de servir. Si ya pasó, caducada.
  if (new Date(invitacion.expiresAt).getTime() <= ahora.getTime()) return 'expirada';

  return 'valida';
}
