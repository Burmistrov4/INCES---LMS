/**
 * Reglas del cuadrante de M3, como funciones puras.
 *
 * Viven aquí y no dentro de los manejadores de ruta por la misma razón que
 * `esBloqueoPorPensumEnUso` en M2: una regla enterrada en un manejador sólo se
 * prueba levantando HTTP y montando repositorios. Como función pura se prueban
 * todos los casos —incluidos los que la API casi nunca alcanza— sin montar nada.
 *
 * La barrera de verdad sigue estando en PostgreSQL: los `check` de las tablas,
 * la función `exigir_agenda_libre()` y sus dos triggers. Lo de aquí es la misma
 * decisión tomada antes de abrir una transacción, para dar un mensaje que nombre
 * el problema en vez de un error de restricción genérico.
 */
import type { Turno } from './tipos.js';

/**
 * Día máximo admitido: 6 = sábado.
 *
 * El domingo queda fuera **a propósito**: el requisito habla de lunes a sábado.
 * Coincide con el `check (day_of_week between 1 and 6)` de `teacher_duties` y de
 * `schedule_slots`, y hay una prueba que comprueba que los dos siguen de acuerdo.
 */
export const DIA_MAXIMO = 6;

/**
 * Bloque máximo admitido.
 *
 * Doce es un techo holgado para turnos de mañana y tarde. Coincide con el
 * `check (block between 1 and 12)` de las dos tablas.
 */
export const BLOQUE_MAXIMO = 12;

/**
 * Turno de un bloque horario.
 *
 * **Es la traducción al backend de `public.turno_de_bloque()`**, la función
 * `immutable` de la que se derivan las columnas generadas `teacher_duties.turno`
 * y `schedule_slots.turno`. Existe aquí por una razón concreta: el `turno` es
 * una columna generada, así que **no se puede insertar** y en los tests en
 * memoria no lo calcula nadie. Sin esta función, el doble en memoria tendría que
 * inventarse su propia fórmula y una prueba podría pasar con un turno que la
 * base nunca produciría.
 *
 * El corte (1–6 mañana, 7–12 tarde) es PROVISIONAL y está pendiente de decisión
 * de coordinación (R-16). Cuando se decida, se cambia en la función SQL y aquí;
 * la prueba de esta función es la que avisa de que los dos sitios se separaron.
 */
export function turnoDeBloque(bloque: number): Turno {
  return bloque <= 6 ? 'MAÑANA' : 'TARDE';
}

/** Nombres de día, indexados por `day_of_week` ISO (1 = lunes). */
const DIAS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'] as const;

/**
 * Nombre del día a partir de `day_of_week`.
 *
 * Refleja `public.dia_legible()`: para un valor fuera de 1–6 devuelve
 * `"día N"` en vez de `undefined`, porque el `check` de la base ya lo impide y
 * un `undefined` que se colara a un mensaje de error lo dejaría a medias.
 */
export function diaLegible(dia: number): string {
  return DIAS[dia - 1] ?? `día ${dia}`;
}

/**
 * ¿Este fallo de la base es un choque de agenda, y no otra restricción?
 *
 * **Por qué hace falta distinguirlo.** El trigger `exigir_agenda_libre()` lanza
 * `23514`, exactamente el mismo código que un `check` corriente, y
 * `traducirError` convierte los dos en un `400 RESTRICCION_VIOLADA`. Para un
 * `check` eso es correcto: los datos no cumplen una regla. Para un choque no: los
 * datos están bien y lo que no admite la operación es el **estado actual** de la
 * agenda, y eso es un `409` —justo lo que el contrato pide para que la UI pueda
 * decir «ese docente ya está en el taller a esa hora»—.
 *
 * Se distinguen por el texto del mensaje porque es lo único que llega: cambiar
 * el `errcode` habría exigido una migración nueva sobre triggers ya aplicados, y
 * una migración aplicada no se edita nunca. Es la misma técnica —y el mismo
 * reparto— que `esBloqueoPorPensumEnUso` en M2.
 *
 * Los dos patrones están copiados de los `raise exception` de
 * `202609180001_mod3_cuadrante_aulas.sql`:
 *
 *   · «Ese docente ya tiene una clase o guardia asignada el % en el bloque %.»
 *   · «Ese espacio ya está ocupado el % en el bloque %.»
 *
 * Se escribe `est[aá]` para no depender del acento: si alguien reescribiera el
 * mensaje sin tilde, la detección seguiría funcionando.
 *
 * **Si esto fallara, el peor caso es un `400` en vez de un `409`**: la operación
 * se sigue bloqueando, porque la invariante la impone el trigger. El `409` existe
 * para que el cliente pueda ser útil, no para proteger nada.
 */
export function esChoqueDeAgenda(mensaje: string): boolean {
  return /ya tiene una clase o guardia asignada|ya est[aá] ocupado el /i.test(mensaje);
}

/**
 * ¿Es una fecha real en formato `AAAA-MM-DD`?
 *
 * Se comprueba con la aritmética del calendario y no con una expresión regular
 * sola, porque `2026-02-30` tiene la forma correcta y no existe. Zod no lo
 * detecta por sí solo si se valida con un patrón, y el error acabaría llegando a
 * Postgres, que responde `22007`, un código que el traductor no reconoce y que
 * saldría como un `500` por un dato que el cliente escribió mal.
 */
export function esFechaISO(valor: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(valor)) return false;

  const [anio, mes, dia] = valor.split('-').map(Number) as [number, number, number];
  const fecha = new Date(Date.UTC(anio, mes - 1, dia));

  return (
    fecha.getUTCFullYear() === anio &&
    fecha.getUTCMonth() === mes - 1 &&
    fecha.getUTCDate() === dia
  );
}

/**
 * ¿El rango de fechas de un lapso es coherente?
 *
 * Refleja el `check` `academic_periods_fechas_coherentes`: con las dos fechas
 * presentes, el fin tiene que ser **posterior** al inicio. Cuando falta alguna
 * —o las dos— no hay nada que ordenar y el rango es válido, que es exactamente
 * lo que hace el `check` con `is null or`.
 *
 * Se comparan las cadenas tal cual: en `AAAA-MM-DD` el orden lexicográfico es el
 * orden cronológico, y convertirlas a `Date` sólo añadiría una zona horaria
 * donde no hace falta ninguna.
 *
 * En un `PATCH` esto sólo se puede comprobar cuando el cliente manda las dos
 * fechas. Con una sola, la otra vive en la fila y el `check` de la base es el
 * que decide. La regla es la misma en los dos sitios; lo que cambia es cuánto se
 * ve desde aquí.
 */
export function rangoDeFechasValido(
  inicio: string | null | undefined,
  fin: string | null | undefined,
): boolean {
  if (!inicio || !fin) return true;
  return fin > inicio;
}
