/**
 * Reglas del currículo de M2, como funciones puras.
 *
 * Viven aquí y no dentro de los manejadores de ruta por la misma razón que
 * `revisarCambioDeRol`: una regla enterrada en un manejador sólo se prueba
 * levantando HTTP y montando repositorios. Como función pura se prueban todos
 * los casos —incluidos los que la API casi nunca alcanza— sin montar nada.
 *
 * La barrera de verdad sigue estando en PostgreSQL: el constraint trigger
 * diferido de la Regla 1 y el trigger de la Regla 2. Lo de aquí es la misma
 * decisión tomada antes de abrir una transacción, para dar un mensaje que
 * nombre el campo culpable en vez de un error de restricción genérico.
 */
import type { EntradaPensum, GrupoPensum } from './tipos.js';

/**
 * Agrupa un pensum por período, ordenado y **sin grupos vacíos**.
 *
 * El caso que importa: períodos `[1, 2, 5]` deben devolver **tres** grupos, no
 * cinco con dos vacíos. Rellenar los huecos con grupos vacíos haría que la
 * pantalla pintara un «Período 3» y un «Período 4» sin materias, como si al
 * pensum le faltara algo. No le falta: salta del 2 al 5, y eso es lo que hay
 * que mostrar.
 *
 * Dentro de cada período, las materias conservan el orden en que llegaron: el
 * servidor no reordena lo que el administrativo escribió.
 *
 * Es genérica sobre el tipo de entrada para servir a los dos usos sin
 * duplicarse: el pensum que se **manda** (`EntradaPensum`, sólo ids) y el que se
 * **recibe** (`MateriaEnPensum`, con código, nombre y horas). Los campos extra
 * se conservan; agrupar no los toca.
 */
export function agruparPensum<T extends EntradaPensum>(entradas: T[]): GrupoPensum<T>[] {
  const porPeriodo = new Map<number, T[]>();

  for (const entrada of entradas) {
    const actuales = porPeriodo.get(entrada.periodo);
    if (actuales) {
      actuales.push(entrada);
    } else {
      porPeriodo.set(entrada.periodo, [entrada]);
    }
  }

  return [...porPeriodo.entries()]
    .sort(([a], [b]) => a - b)
    .map(([periodo, materias]) => ({ periodo, materias }));
}

/**
 * Devuelve el `materiaId` repetido, o `null` si no hay ninguno.
 *
 * Devuelve el identificador y no un booleano a propósito: el mensaje de error
 * tiene que nombrar la materia que se repite, no decir «hay un error». Un
 * administrador que armó un pensum de 40 materias necesita saber cuál.
 *
 * Se comparan los identificadores tal cual, sin normalizar: son UUID que genera
 * la base, así que dos formas del mismo valor no existen.
 */
export function materiaRepetida(entradas: EntradaPensum[]): string | null {
  const vistas = new Set<string>();
  for (const entrada of entradas) {
    if (vistas.has(entrada.materiaId)) return entrada.materiaId;
    vistas.add(entrada.materiaId);
  }
  return null;
}

/**
 * ¿Se puede tocar el pensum de este programa?
 *
 * Es la materialización de la Regla 2 en el lado de la API: si el programa ya
 * tiene secciones activas del período vigente, reordenar o quitar materias
 * dejaría a los alumnos matriculados apuntando a un pensum que ya no es el
 * suyo. La UI deshabilita el reordenamiento **antes** de que el usuario lo
 * intente, en vez de dejarlo chocar contra un 409.
 *
 * Que la cuenta llegue a cero cuando D13 estaba abierta fue una limitación
 * temporal; ahora `sections.program_id` existe y el número es real. Aun así la
 * función se escribe aparte para que el repositorio sea lo único que cambia si
 * mañana la fuente de ese número cambia.
 */
export function pensumEditable(seccionesActivas: number): boolean {
  return seccionesActivas <= 0;
}

/**
 * ¿Este fallo de la base es la Regla 2, y no la Regla 1?
 *
 * **Por qué hace falta distinguirlas.** Los dos triggers lanzan el mismo código
 * de PostgreSQL, `23514`, y `traducirError` lo convierte en un `400
 * RESTRICCION_VIOLADA`. Para la Regla 1 eso es correcto: es un dato que no
 * cumple una regla. Para la Regla 2 no: no es que los datos estén mal, es que
 * **hay un conflicto con el estado actual del sistema** —existen secciones
 * activas—, y eso es un `409`, que es justo lo que el contrato pide y lo que el
 * cliente necesita para ofrecer «archiva las secciones primero».
 *
 * Se distinguen por el texto del mensaje porque es lo único que llega: cambiar
 * el código de error habría exigido una migración nueva sobre triggers ya
 * aplicados, que son inmutables. El texto se elige en la migración y se copia
 * aquí; la prueba de humo contra la base real comprueba que sigue coincidiendo.
 *
 * Si el mensaje cambiara y esto dejara de detectar, el peor caso es un `400` en
 * vez de un `409`: la operación se sigue bloqueando. La invariante no depende de
 * esta función — la impone el trigger.
 */
export function esBloqueoPorPensumEnUso(mensaje: string): boolean {
  return /secci[oó]n\(es\) activa\(s\)/i.test(mensaje);
}
