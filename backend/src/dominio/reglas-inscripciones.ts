/**
 * Reglas de inscripciones y cupos (M4), como funciones puras.
 *
 * Viven aquí y no dentro de los manejadores de ruta por la misma razón que
 * `esChoqueDeAgenda` en M3 y `esBloqueoPorPensumEnUso` en M2: una regla enterrada
 * en un manejador sólo se prueba levantando HTTP y montando repositorios. Como
 * función pura se prueban todos los casos —incluidos los que la API casi nunca
 * alcanza— sin montar nada.
 *
 * **La barrera de verdad está en PostgreSQL**, no aquí. Las RPC
 * `security definer`, el cerrojo por sección y el trigger anti-acaparamiento son
 * los que deciden. Lo de este archivo es la misma decisión tomada antes de
 * llamar a la base, para dar un mensaje que nombre el problema en vez de un error
 * de restricción genérico — y para que la interfaz no ofrezca algo que la base va
 * a rechazar.
 */
import type { EstadoInscripcion } from './tipos.js';
import { ESTADOS_INSCRIPCION } from './tipos.js';

/** ¿Es uno de los cuatro estados válidos? */
export function esEstadoInscripcion(valor: unknown): valor is EstadoInscripcion {
  return typeof valor === 'string' && (ESTADOS_INSCRIPCION as readonly string[]).includes(valor);
}

/**
 * Texto legible de un estado, para mensajes de error y para la interfaz.
 *
 * Se nombra aquí y no en cada pantalla porque el mismo estado aparece en tres
 * sitios (mis inscripciones, la cola del admin y los mensajes de error), y tres
 * copias del mismo texto es cómo se acaba arreglando una y olvidando las otras.
 */
export function descripcionDeEstado(estado: EstadoInscripcion): string {
  switch (estado) {
    case 'ENROLLED':
      return 'Inscrito';
    case 'WAITLISTED':
      return 'En lista de espera';
    case 'PENDING_BID':
      return 'Con una oferta de cupo pendiente';
    case 'DROPPED':
      return 'Dado de baja';
  }
}

/**
 * ¿El estado actual permite **pedir** un asiento?
 *
 * `null` significa «no tiene fila en esta sección» y es el caso normal: puede
 * pedir. Un `DROPPED` **no** puede pedir por la vía normal —volver a entrar es
 * una excepción de administración (`reincorporar_inscripcion`)— y un `ENROLLED`,
 * `WAITLISTED` o `PENDING_BID` tampoco, porque ya está dentro, en la cola o con
 * una oferta viva.
 *
 * La base lo rechaza igual con un `23514`; esto existe para que el mensaje diga
 * **por qué**, y para que la interfaz deshabilite el botón antes de que el
 * usuario choque.
 */
export function puedeSolicitar(estado: EstadoInscripcion | null): boolean {
  return estado === null;
}

/**
 * ¿Está vencida una oferta?
 *
 * Es el espejo exacto del predicado SQL `bid_expires_at is null or
 * bid_expires_at > now()` de `existe_oferta_vigente()`, negado.
 *
 * **`null` significa «no vence»**, no «vencida»: una oferta sin fecha de
 * vencimiento está viva. Confundir las dos cosas entregaría el asiento a la vía
 * directa mientras la oferta sigue en el aire.
 *
 * Si la fecha no se puede interpretar se devuelve `false` —tratarla como viva—
 * porque el error seguro es no ofrecer el asiento de más, nunca de menos.
 */
export function ofertaVencida(venceEn: string | null, ahora: Date): boolean {
  if (venceEn === null) return false;

  const vencimiento = new Date(venceEn).getTime();
  if (Number.isNaN(vencimiento)) return false;

  return vencimiento <= ahora.getTime();
}

/**
 * ¿Hay un asiento disponible de verdad?
 *
 * **Esta es la regla que evita la doble venta**, y no es la resta del contador.
 * Como `cupos_ocupados` cuenta **sólo `ENROLLED`**, el contador puede decir «hay
 * hueco» mientras una oferta está en el aire. La condición completa, que es la
 * que aplica `solicitar_inscripcion` dentro de su cerrojo, es:
 *
 *   hay hueco  **Y**  no hay oferta vigente
 *
 * Sin la segunda mitad, la traza es:
 *
 *   ```
 *   cupo = 1 · A renuncia          → 0/1, hueco libre
 *   B promovido (PENDING_BID)      → ocupados = 0   ← B ya no cuenta
 *   C entra directo                → ENROLLED       ← 1/1
 *   B acepta su oferta             → ENROLLED       ← 2/1  💥 dos en un asiento
 *   ```
 *
 * Está probado en `supabase/tests/validate.mjs` §17.5. **No simplifiques esta
 * función a la resta**: es la única copia de esa conjunción fuera de la base.
 */
export function hayAsientoDisponible(
  cupoEfectivo: number,
  cuposOcupados: number,
  ofertaVigente: boolean,
): boolean {
  return cuposOcupados < cupoEfectivo && !ofertaVigente;
}

/**
 * Cuántos asientos puede ofrecer la interfaz **sin mentir**.
 *
 * No es `cupos_disponibles` de la vista. Con una oferta en el aire la vista
 * informa `> 0` (porque `PENDING_BID` no cuenta) pero el asiento ya está
 * comprometido: ofrecerlo sería prometer algo que la base va a negar. Devuelve 0
 * en ese caso.
 *
 * `cupos_disponibles` se sigue exponiendo para que la pantalla pueda explicar
 * «hay 1 libre, pero comprometido»; lo que no puede es usarlo como semáforo.
 */
export function cuposOfrecibles(
  cupoEfectivo: number,
  cuposOcupados: number,
  ofertaVigente: boolean,
): number {
  if (ofertaVigente) return 0;
  return Math.max(cupoEfectivo - cuposOcupados, 0);
}

/**
 * ¿El mensaje delata un intento de acaparar dos secciones de la misma materia?
 *
 * El trigger `enrollments_seccion_unica_por_materia` lanza `23514`, **el mismo
 * código que un `check` corriente**, y `traducirError` convierte los dos en un
 * `400 RESTRICCION_VIOLADA`. Para un `check` eso es correcto; para esto no: los
 * datos están bien y lo que no admite la operación es el **estado actual** del
 * estudiante, y eso es un `409` —justo lo que la interfaz necesita para decir
 * «ya estás en otra sección de esta materia»—.
 *
 * Se distinguen por el texto porque es lo único que llega: cambiar el `errcode`
 * habría exigido una migración nueva sobre triggers ya aplicados, y una migración
 * aplicada no se edita nunca. Es la misma técnica —y el mismo reparto— que
 * `esChoqueDeAgenda` en M3.
 *
 * El patrón está copiado del `raise exception` de `202609190001`:
 *   · «El estudiante % ya tiene una sección de la materia % en el lapso %.»
 */
export function esAcaparamientoDeMateria(mensaje: string): boolean {
  return /ya tiene una secci[oó]n de la materia/i.test(mensaje);
}

/**
 * ¿La sección está archivada?
 *
 *   · «La sección % está archivada y no admite inscripciones.»
 */
export function esSeccionArchivada(mensaje: string): boolean {
  return /est[aá] archivada y no admite inscripciones/i.test(mensaje);
}

/**
 * ¿La sección no existe?
 *
 *   · «La sección % no existe.»
 *
 * Se comprueba antes que el archivado porque el mensaje de inexistente es un
 * subconjunto literal del otro (`"La sección X no existe"` no contiene
 * «archivada», pero un patrón descuidado sobre «La sección» los confundiría).
 */
export function esSeccionInexistente(mensaje: string): boolean {
  return /la secci[oó]n .* no existe/i.test(mensaje);
}

/**
 * ¿La oferta ya venció?
 *
 *   · «La oferta de cupo para la sección % ya venció.»
 *
 * Es un `410 RECURSO_CADUCADO`, no un `400`: la petición era válida cuando se
 * hizo y dejó de serlo por el paso del tiempo. La interfaz debe recargar el
 * estado, no pedirle al usuario que corrija nada.
 */
export function esOfertaVencida(mensaje: string): boolean {
  return /la oferta de cupo para la secci[oó]n .* ya venci[oó]/i.test(mensaje);
}

/**
 * ¿Ya tiene una solicitud activa en esa sección?
 *
 *   · «Ya tienes una solicitud activa (%) para la sección %.»
 *   · «Tu inscripción en la sección % ya estaba dada de baja.»
 *   · «No tienes ninguna inscripción en la sección %.»
 */
export function esSolicitudYaExistente(mensaje: string): boolean {
  return (
    /ya tienes una solicitud activa/i.test(mensaje) ||
    /ya estaba dada de baja/i.test(mensaje)
  );
}

/**
 * ¿Se le pidió volver a una sección que ya cursó?
 *
 *   · «Ya cursaste la sección %: un administrador debe reincorporarte
 *      explícitamente.»
 *
 * Es el caso que el `unique (student_id, section_id)` protege a propósito: un
 * `DROPPED` conserva su fila como historial, así que volver a entrar **no** es
 * una reinscripción libre. Merece un `409` con su propio código para que la
 * interfaz pueda ofrecer «solicitar reincorporación» en vez de un error opaco.
 */
export function esRequiereReincorporacion(mensaje: string): boolean {
  return /ya cursaste la secci[oó]n|un administrador debe reincorporarte/i.test(mensaje);
}

/**
 * ¿No hay nada que promover?
 *
 *   · «No existe una inscripción previa del estudiante % en la sección %.»
 *
 * Éste es el mensaje que `reincorporar_inscripcion` lanza cuando el estudiante
 * nunca estuvo ahí. No es un fallo del servidor ni una petición mal formada: es
 * una petición **bien formada sobre una fila que no existe**, y por eso un 404
 * con código propio.
 */
export function esReincorporacionSinHistorial(mensaje: string): boolean {
  return /no existe una inscripci[oó]n previa del estudiante/i.test(mensaje);
}
