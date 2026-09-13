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
 * El orden importa: una invitación usada no "revive" aunque haya caducado;
 * por eso se comprueba `isUsed` antes que la fecha. Devuelve un valor y no lanza:
 * quien llama elige el código de error, porque el 409 (usada) y el 410 (caducada)
 * son distintos y el profesor debe saber cuál es su caso.
 */
export function estadoDeInvitacion(
  invitacion: Pick<InvitacionDocente, 'isUsed' | 'expiresAt'>,
  ahora: Date = new Date(),
): EstadoInvitacion {
  if (invitacion.isUsed) return 'usada';

  // `expires_at` es el instante en que deja de servir. Si ya pasó, caducada.
  if (new Date(invitacion.expiresAt).getTime() <= ahora.getTime()) return 'expirada';

  return 'valida';
}
