/**
 * Tipos del dominio del INCES LMS.
 *
 * Se declaran a mano y en `camelCase`, en vez de reutilizar los tipos generados
 * de Supabase, por dos razones:
 *   1. La API expone un contrato propio: si mañana cambia una columna, el
 *      cambio se resuelve en el repositorio y no se filtra a los clientes.
 *   2. Los dobles de prueba pueden construirlos sin arrastrar el SDK.
 */

export type Rol = 'admin' | 'docente' | 'estudiante';

export const ROLES: readonly Rol[] = ['admin', 'docente', 'estudiante'];

export function esRol(valor: unknown): valor is Rol {
  return typeof valor === 'string' && (ROLES as readonly string[]).includes(valor);
}

export interface Perfil {
  id: string;
  email: string;
  cedula: string | null;
  nombres: string;
  apellidos: string;
  rol: Rol;
  activo: boolean;
}

export interface ModuloSistema {
  clave: string;
  nombre: string;
  descripcion: string | null;
  habilitado: boolean;
  orden: number;
  icono: string | null;
  /** Lista vacía = visible para todos los roles. */
  rolesPermitidos: Rol[];
  categoria: string;
  actualizadoEn: string | null;
}

export type TipoParametro = 'number' | 'boolean' | 'string' | 'json';

export interface ParametroSistema {
  clave: string;
  valor: unknown;
  tipo: TipoParametro;
  descripcion: string | null;
  categoria: string;
  esPublico: boolean;
  actualizadoEn: string | null;
}

export interface EntradaAuditoria {
  id: string;
  tabla: string;
  clave: string;
  valorAnterior: unknown;
  valorNuevo: unknown;
  usuarioEmail: string | null;
  creadoEn: string | null;
}

/** Invitación de docente por token. El token en claro nunca se guarda: sólo su hash. */
export interface InvitacionDocente {
  id: string;
  email: string;
  /** Nombre(s) del docente, capturado por el administrador al invitar (R-21). */
  nombres: string;
  /** Apellido(s) del docente, capturado por el administrador al invitar (R-21). */
  apellidos: string;
  tokenHash: string;
  isUsed: boolean;
  createdAt: string;
  /** Instante ISO tras el cual la invitación ya no sirve (48 h desde su creación). */
  expiresAt: string;
}

/** Resultado de comprobar si una invitación sigue usable. */
export type EstadoInvitacion = 'valida' | 'usada' | 'expirada';

export type EstadoAcceso = 'SUCCESS' | 'FAILED';

/** Entrada de la traza de acceso (auth_logs). */
export interface EntradaAcceso {
  id: string;
  userId: string | null;
  email: string | null;
  ip: string | null;
  estado: EstadoAcceso;
  createdAt: string;
}

export interface CambiosModulo {
  habilitado?: boolean;
  orden?: number;
  rolesPermitidos?: Rol[];
}

/** Identidad resuelta de la petición, tras verificar el token. */
export interface UsuarioAutenticado {
  id: string;
  email: string;
  rol: Rol;
  perfil: Perfil;
}

/**
 * ¿Este rol puede ver el módulo?
 *
 * Lista vacía significa "todos". Se centraliza aquí para que la API y el
 * frontend apliquen exactamente la misma regla.
 */
export function moduloPermiteRol(modulo: ModuloSistema, rol: Rol): boolean {
  return modulo.rolesPermitidos.length === 0 || modulo.rolesPermitidos.includes(rol);
}

/** Módulos habilitados y visibles para un rol, ordenados para el menú. */
export function modulosVisibles(modulos: ModuloSistema[], rol: Rol): ModuloSistema[] {
  return modulos
    .filter((m) => m.habilitado && moduloPermiteRol(m, rol))
    .sort((a, b) => a.orden - b.orden || a.clave.localeCompare(b.clave));
}

// --- Módulo 2: currículo y pensum -------------------------------------------

/**
 * Los dos tipos de oferta formativa.
 *
 * Se escribe como unión de literales y no como `enum` por la misma razón que
 * `Rol`: la base guarda `text` con un `check`, no un tipo enumerado de
 * Postgres, y una unión de literales es lo que `z.infer` devuelve tal cual.
 */
export type TipoPrograma = 'CARRERA' | 'CURSO_LIBRE';

export const TIPOS_PROGRAMA: readonly TipoPrograma[] = ['CARRERA', 'CURSO_LIBRE'];

export function esTipoPrograma(valor: unknown): valor is TipoPrograma {
  return typeof valor === 'string' && (TIPOS_PROGRAMA as readonly string[]).includes(valor);
}

/**
 * Un programa de la oferta formativa.
 *
 * Los nombres van en español, aunque la base los tenga en inglés (`code`,
 * `name`, `requires_internship`). La traducción ocurre en el repositorio, en un
 * solo sitio: es la misma decisión que con `auth_logs`, donde el campo es
 * `createdAt` en la base y `creadoEn` en el dominio.
 */
export interface Programa {
  id: string;
  codigo: string;
  nombre: string;
  tipo: TipoPrograma;
  requierePasantia: boolean;
  activo: boolean;
  creadoEn: string;
  actualizadoEn: string;
}

/** Un programa con los totales que la pantalla necesita para avisar. */
export interface ProgramaConTotales extends Programa {
  /** Cuántas materias tiene el pensum. Cero = no se puede publicar (Regla 1). */
  totalMaterias: number;
  /** Cuántos períodos distintos cubre el pensum. */
  totalPeriodos: number;
}

/** Una materia del banco global. Se comparte entre programas. */
export interface Materia {
  id: string;
  codigo: string;
  nombre: string;
  horasAcademicas: number;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * Una materia dentro de un pensum.
 *
 * Es lo que el asistente manda: la materia y el período en que se cursa. El
 * `periodo` es un número de orden (`period_order`), no un código: un pensum de
 * seis semestres usa 1…6, y el nombre visible del período es cosa de la UI.
 */
export interface EntradaPensum {
  materiaId: string;
  periodo: number;
}

/**
 * Una materia del pensum **con sus datos**, tal como la devuelve el detalle.
 *
 * `EntradaPensum` es lo que el cliente manda; esto es lo que recibe. Se separan
 * a propósito: el cliente no debe poder mandar el nombre de una materia, porque
 * el nombre vive en `subjects` y lo comparten cinco pensums. Si fueran el mismo
 * tipo, un reemplazo de pensum podría reescribir el nombre de una materia
 * compartida sin que nadie lo pidiera.
 *
 * Existe porque la pantalla del pensum pinta código, nombre y horas de cada
 * materia: sin esto tendría que pedir el banco de materias entero, o hacer una
 * consulta por materia.
 */
export interface MateriaEnPensum extends EntradaPensum {
  codigo: string;
  nombre: string;
  horasAcademicas: number;
}

/**
 * Un período del pensum con sus materias, para pintar el detalle agrupado.
 *
 * Es genérico sobre el tipo de entrada para que `agruparPensum` sirva tanto al
 * pensum "puro" (sólo ids, lo que se manda) como al detalle enriquecido (lo que
 * se recibe), sin duplicar la agrupación ni perder los campos extra.
 */
export interface GrupoPensum<T extends EntradaPensum = EntradaPensum> {
  periodo: number;
  materias: T[];
}

/** El pensum completo de un programa, agrupado por período. */
export interface DetallePrograma {
  programa: Programa;
  pensum: GrupoPensum<MateriaEnPensum>[];
  /** Secciones activas del período vigente. Es lo que decide `editable`. */
  seccionesActivas: number;
  /** `false` cuando la Regla 2 impide tocar el pensum. */
  editable: boolean;
}

// --- Módulo 3: cuadrante, aulas y guardias ----------------------------------

/**
 * Turno de un bloque horario.
 *
 * Es un valor **derivado**: en la base lo calcula `turno_de_bloque(block)` en una
 * columna generada, así que nunca se envía, sólo se recibe. Mandarlo en un
 * `POST`/`PATCH` es un `400` por `.strict()`, y no un campo ignorado en silencio:
 * aceptar un turno que contradiga al bloque sería aceptar una agenda que miente.
 */
export type Turno = 'MAÑANA' | 'TARDE';

export const TURNOS: readonly Turno[] = ['MAÑANA', 'TARDE'];

export function esTurno(valor: unknown): valor is Turno {
  return typeof valor === 'string' && (TURNOS as readonly string[]).includes(valor);
}

/**
 * Las tres formas que puede tener un espacio, **derivadas** de dos columnas.
 *
 * No es una columna de la base: sale de cruzar `is_workshop` con `capacity`.
 * Existe como concepto de API porque el filtro de la pantalla de aulas se elige
 * entre estas tres, y decir «taller», «aula» o «zona» es más claro que pedir al
 * usuario que combine dos casillas.
 *
 *   · `TALLER` → `is_workshop = true`            (cupo el que sea)
 *   · `ZONA`   → `is_workshop = false`, `capacity = 0`
 *   · `AULA`   → `is_workshop = false`, `capacity > 0`
 *
 * Las tres son excluyentes y cubren todos los casos, así que el filtro nunca
 * deja un espacio fuera sin decirlo.
 */
export type TipoAula = 'TALLER' | 'ZONA' | 'AULA';

export const TIPOS_AULA: readonly TipoAula[] = ['TALLER', 'ZONA', 'AULA'];

export function esTipoAula(valor: unknown): valor is TipoAula {
  return typeof valor === 'string' && (TIPOS_AULA as readonly string[]).includes(valor);
}

/**
 * Un espacio del centro: aula, taller o zona.
 *
 * `capacidad` en 0 significa «sin cupo declarado» (una zona, un pasillo), que
 * **no** es lo mismo que desconocido: por eso la columna es `not null default 0`.
 */
export interface Aula {
  id: string;
  nombre: string;
  capacidad: number;
  esTaller: boolean;
  activa: boolean;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * Un lapso académico.
 *
 * `activo` y `vigente` **no son lo mismo** y por eso son dos campos:
 * `activo` es «este lapso está abierto, se puede planificar en él», y `vigente`
 * es «este es el que el sistema considera en curso» (`system_settings.periodo_activo`).
 * Puede haber varios abiertos y sólo uno vigente: al cerrar un lapso se prepara
 * el siguiente mientras el vigente sigue dictándose.
 *
 * `vigente` es derivado: no es una columna de `academic_periods`.
 *
 * Las fechas son **anulables a propósito**: el centro no las ha cargado y
 * inventarlas sería fabricar dato institucional (R-17). La UI debe mostrar «sin
 * fechas cargadas», no un rango inventado.
 */
export interface Periodo {
  id: string;
  codigo: string;
  nombre: string | null;
  fechaInicio: string | null;
  fechaFin: string | null;
  activo: boolean;
  vigente: boolean;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * Una guardia de custodia.
 *
 * Es una **presencia**, no una clase: dice quién cubre qué espacio, qué día y
 * qué bloque, **independientemente de que haya clase**. Por eso es su propia
 * tabla y no un tipo de `schedule_slots`.
 *
 * `periodo` es obligatorio: sin él, una guardia del lunes a primera hora
 * chocaría con las clases de cualquier lapso, incluido uno futuro que todavía no
 * ha empezado (R-15).
 */
export interface Guardia {
  id: string;
  docenteId: string;
  aulaId: string;
  periodo: string;
  dia: number;
  bloque: number;
  turno: Turno;
  notas: string | null;
  activa: boolean;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * Una clase del cuadrante: sección + docente + aula + día/bloque.
 *
 * Los cinco campos de la tabla son `seccionId`, `docenteId`, `aulaId`, `dia` y
 * `bloque`. **El período no viaja en la tabla**: se deriva de la sección, y
 * duplicarlo aquí crearía una segunda fuente de verdad que puede desviarse.
 *
 * El resto lo aporta la vista `v_cuadrante_clases`, que ya resuelve los nombres.
 * Se incluyen `programaId`/`programa` y `materiaId`/`materia` aunque la tabla no
 * los tenga: la cabecera de la rejilla es «período | especialidad | sección», y
 * sin la especialidad la pantalla tendría que pedirla aparte —justo lo que el
 * argumento de «las cuatro listas en una llamada» quiere evitar—.
 *
 * **No lleva marcas de tiempo.** La vista no las proyecta y ninguna pantalla del
 * cuadrante las muestra; añadirlas habría exigido otra migración para cumplir
 * una frase del contrato, y el esquema no se toca por cosmética.
 */
export interface ClaseCuadrante {
  id: string;
  seccionId: string;
  docenteId: string;
  aulaId: string;
  dia: number;
  bloque: number;
  turno: Turno;
  activa: boolean;
  // --- resuelto por `v_cuadrante_clases` ---
  periodo: string;
  programaId: string;
  programa: string;
  materiaId: string;
  materia: string;
  seccion: string;
  aula: string;
  docente: string;
}

/** Un docente, reducido a lo que la rejilla necesita para pintar una fila. */
export interface DocenteResumen {
  id: string;
  nombre: string;
}

/**
 * La rejilla maestra de un lapso, completa en una sola respuesta.
 *
 * **Las cuatro listas juntas, y no por comodidad.** La rejilla necesita pintar
 * las clases, las guardias, las columnas de aulas y las filas de docentes a la
 * vez: son las cuatro dimensiones de la misma rejilla. Con cuatro peticiones, la
 * pantalla puede quedar a medio pintar mostrando una guardia junto a una clase
 * que ya no existe, y el administrador no sabría si eso es un choque real o una
 * pantalla desactualizada. Una sola respuesta es coherente por construcción.
 *
 * `periodo` es `null` cuando no hay lapso vigente y no se pidió ninguno. En ese
 * caso las listas de clases y guardias salen vacías pero **`aulas` y `docentes`
 * siguen llenas**: la pantalla puede decir «no hay lapso vigente» en vez de
 * aparecer en blanco, y el administrador ve que el catálogo sí tiene datos.
 */
export interface RejillaCuadrante {
  periodo: string | null;
  clases: ClaseCuadrante[];
  guardias: Guardia[];
  aulas: Aula[];
  docentes: DocenteResumen[];
}

/** Los dos roles que tienen horario propio. Un `admin` no tiene: ve la rejilla. */
export type RolDeHorario = 'docente' | 'estudiante';

/**
 * El horario del llamante.
 *
 * Una sola forma para los dos roles porque el aislamiento lo garantiza la RLS y
 * lo único que cambia es qué filas sobreviven al filtro. Un docente recibe sus
 * clases **y** sus guardias; un estudiante, las clases de las secciones en las
 * que está matriculado, y `guardias` siempre vacío.
 */
export interface MiHorario {
  rol: RolDeHorario;
  periodo: string | null;
  clases: ClaseCuadrante[];
  guardias: Guardia[];
}

// --- Módulo 4: secciones, inscripciones y cupos -----------------------------

/**
 * Los cuatro estados de una inscripción.
 *
 * El ciclo es: `WAITLISTED` (en la cola) → `PENDING_BID` (se le ofreció un
 * asiento, con vencimiento) → `ENROLLED` (dentro) → `DROPPED` (fuera, pero la
 * fila se conserva como historial).
 *
 * **`DROPPED` no es un borrado.** La fila se queda: es el historial de que ese
 * estudiante estuvo en esa sección, y volver a entrar es una excepción de
 * administración (`reincorporar_inscripcion`), no una reinscripción libre.
 */
export type EstadoInscripcion = 'ENROLLED' | 'WAITLISTED' | 'PENDING_BID' | 'DROPPED';

export const ESTADOS_INSCRIPCION: readonly EstadoInscripcion[] = [
  'ENROLLED',
  'WAITLISTED',
  'PENDING_BID',
  'DROPPED',
];

/**
 * Una sección: el grupo concreto de una materia en un lapso.
 *
 * Es la unidad sobre la que se inscribe un estudiante, y la que tiene cupo.
 */
export interface Seccion {
  id: string;
  programaId: string;
  materiaId: string;
  /** Código del lapso (`academic_periods.code`). */
  periodo: string;
  /** Nombre corto dentro del lapso ('SA', 'SC'). */
  nombre: string;
  /**
   * Cupo declarado de la sección, o `null` para «usa el global del centro».
   *
   * ⚠️ **`0` no es «sin definir»: es una sección sin cupo.** Sólo `null` cae al
   * parámetro `cupo_maximo_por_seccion`. La columna se hizo anulable justo para
   * que ese fallback fuera alcanzable: era `not null default 0` y nunca
   * disparaba.
   */
  cupoMaximo: number | null;
  activa: boolean;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * La ocupación de una sección, con los nombres ya resueltos.
 *
 * Sale de la vista `v_ocupacion_secciones`, que calcula los tres recuentos con
 * funciones `security definer` (una vista `invoker` que contara `enrollments`
 * directo mostraría a cada estudiante **sólo su propia fila** y la sección
 * parecería vacía).
 *
 * Los nombres no están en la vista: los resuelve el repositorio con una segunda
 * consulta sobre los ids de la página.
 */
export interface OcupacionSeccion {
  seccionId: string;
  periodo: string;
  programaId: string;
  programaNombre: string | null;
  materiaId: string;
  materiaNombre: string | null;
  nombre: string;
  activa: boolean;
  /** `coalesce(max_capacity, cupo_maximo_por_seccion, 0)`. */
  cupoEfectivo: number;
  /**
   * Cuántos asientos están tomados.
   *
   * **Cuenta sólo `ENROLLED`**: una solicitud `PENDING_BID` no reserva cupo. Por
   * eso `cuposDisponibles` puede ser > 0 con una oferta en el aire, y por eso
   * existe `ofertaVigente`.
   */
  cuposOcupados: number;
  cuposDisponibles: number;
  /**
   * ¿Hay una oferta de cupo viva (no vencida) en esta sección?
   *
   * **No es informativo: es la barrera contra la doble venta.** Sin esta señal,
   * el contador diría que hay hueco mientras una oferta está en el aire, y dos
   * personas acabarían en un asiento de uno. La interfaz **debe** usarla para no
   * ofrecer un asiento que no se puede dar.
   */
  ofertaVigente: boolean;
}

/** Una inscripción tal como se guarda. */
export interface Inscripcion {
  id: string;
  estudianteId: string;
  seccionId: string;
  estado: EstadoInscripcion;
  /** Vencimiento de la oferta. Sólo tiene valor en `PENDING_BID`. */
  ofertaVenceEn: string | null;
  creadoEn: string;
  actualizadoEn: string;
}

/**
 * Una inscripción con el contexto que necesita una pantalla.
 *
 * Se aplana la sección en vez de anidarla porque las dos pantallas que la usan
 * (mis inscripciones y la cola del administrador) pintan los mismos campos, y
 * anidar obligaría a desempaquetar en el cliente sin ganar nada.
 */
export interface InscripcionDetallada extends Inscripcion {
  periodo: string;
  seccionNombre: string;
  materiaId: string;
  materiaNombre: string | null;
  programaId: string;
  programaNombre: string | null;
  /** Posición en la cola FIFO, empezando en 1. `null` si no está en cola. */
  posicionEnCola: number | null;
  /** Nombre del estudiante. Sólo lo recibe el administrador (la RLS lo permite). */
  estudianteNombre?: string | null;
  estudianteEmail?: string | null;
}
