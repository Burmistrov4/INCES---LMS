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

// --- Módulo 4: catálogo de la planilla de inscripción -----------------------

/**
 * Qué clase de control pinta el formulario para un campo.
 *
 * La unión es la del `check` de `inscripcion_campos.tipo` (`202609240001`). Se
 * escribe a mano y no derivada de un arreglo `as const` porque el catálogo la
 * usa como *entrada* de un `switch` en el renderizador, y ahí conviene que el
 * compilador enumere los nueve casos.
 *
 * **`tipo` no es cosmético.** Decide qué widget se pinta y, con él, **qué forma
 * tiene el valor que se guarda**: `seleccion` guarda una cadena, `multiseleccion`
 * un arreglo, `tabla` un arreglo de objetos con las columnas de `opciones`, y
 * `rejilla` un objeto ítem→valor. Pintar el widget equivocado no es un fallo
 * estético: escribe un valor de forma equivocada en `datos_planilla`, que es la
 * columna que después lee la exportación hacia HACER.
 */
export const TIPOS_CAMPO_INSCRIPCION = [
  'texto',
  'email',
  'numero',
  'fecha',
  'seleccion',
  'multiseleccion',
  'booleano',
  'tabla',
  'rejilla',
] as const;

/**
 * La unión se **deriva del arreglo**, igual que `TipoTarea` de `TIPOS_TAREA`, y
 * no al revés. La consecuencia práctica es que `z.enum(TIPOS_CAMPO_INSCRIPCION)`
 * compila y el documento OpenAPI no puede mentir sobre los tipos que la API
 * acepta: si mañana una migración añadiera uno, el contrato lo recoge solo.
 */
export type TipoCampoInscripcion = (typeof TIPOS_CAMPO_INSCRIPCION)[number];

export function esTipoCampoInscripcion(valor: unknown): valor is TipoCampoInscripcion {
  return (
    typeof valor === 'string' && (TIPOS_CAMPO_INSCRIPCION as readonly string[]).includes(valor)
  );
}

/**
 * El contenido de `inscripcion_campos.opciones`, que **no tiene una forma única**.
 *
 * Depende del `tipo` del campo, y son cuatro formas distintas:
 *
 *   · `seleccion` / `multiseleccion` → `{ opciones: [{ valor, etiqueta }] }`
 *   · `tabla`      → `{ columnas: [{ codigo, etiqueta, tipo, obligatorio, opciones? }] }`
 *   · `rejilla`    → `{ items: [{ valor, etiqueta }], etiqueta_desde, multiple }`
 *
 * Se transporta **tal cual**, sin normalizar a un esquema común, y esa es una
 * decisión de diseño con una consecuencia deliberada: añadir una clave nueva a
 * una de esas formas —o una forma nueva para un `tipo` nuevo— **no exige tocar
 * el backend**. Forzarlas a un tipo con campos opcionales habría convertido cada
 * ampliación del catálogo en un cambio de backend, que es justo lo que
 * `datos_planilla` existe para evitar.
 *
 * Quien interpreta esta forma es el renderizador, que conoce el `tipo`.
 */
export type OpcionesCampoInscripcion = Record<string, unknown>;

/**
 * Visibilidad condicional de un campo, p. ej. `{ campo: 'pueblo_indigena', igual: true }`.
 *
 * Sólo afecta a la **presentación**: el campo existe siempre en el catálogo y su
 * valor se puede guardar siempre. Es la forma que `202609240001` documenta en el
 * comentario de la columna `condicion`.
 */
export interface CondicionCampoInscripcion {
  campo: string;
  igual: unknown;
}

/**
 * Un campo del catálogo de la planilla de inscripción.
 *
 * Es la **fuente de verdad del formulario**: la pantalla lo renderiza y el
 * administrador marca obligatorio/opcional en la tabla, sin tocar código. Por eso
 * el backend lo expone entero en vez de una proyección «útil»: cualquier campo
 * que se dejara fuera obligaría a un cambio de backend para que la pantalla
 * pudiera pintarlo, y eso devolvería el problema que el catálogo resuelve.
 */
export interface CampoInscripcion {
  /** Identificador estable del campo. Es también la clave en `datos_planilla`. */
  codigo: string;
  /** Texto que ve el aspirante. */
  etiqueta: string;
  /** Paso del formulario al que pertenece. Los grupos se ordenan por `orden`. */
  grupo: string;
  tipo: TipoCampoInscripcion;
  obligatorio: boolean;
  /** Orden **global**, no por grupo: el renderizador ordena sin conocer los grupos. */
  orden: number;
  /** Lista cerrada, columnas de una tabla o ítems de una rejilla. Ver el tipo. */
  opciones: OpcionesCampoInscripcion | null;
  /**
   * Origen **dinámico** de las opciones, o `null` si están en `opciones`.
   *
   * Hoy el único valor es `'programas'`: la oferta formativa cambia y no puede
   * quedar congelada dentro del catálogo. La pantalla consulta esa fuente en vivo.
   */
  fuente: string | null;
  condicion: CondicionCampoInscripcion | null;
  /** Aclaración para el aspirante, o `null`. */
  ayuda: string | null;
}

/**
 * La planilla rellena: código de campo → valor.
 *
 * **El backend no valida esta forma, y no es un olvido.** Quién decide qué
 * campos son obligatorios es `inscripcion_campos`, que vive en la base, y la
 * regla la aplica `public.validar_planilla()` — la misma función que dispara el
 * trigger `handle_new_user()` y la guardia de escritura de `aspirantes`. Zod sólo
 * comprueba que sea un objeto: repetir aquí la lista de obligatorios sería una
 * **tercera** copia de la regla (SQL, Zod y formulario) y las tres se desviarían
 * en cuanto el CFS marcara un campo como obligatorio desde el panel.
 */
export type PlanillaInscripcion = Record<string, unknown>;

// --- Módulo 5: archivos (Cloudflare R2) -------------------------------------

/**
 * A qué clase de entidad se adjunta un archivo.
 *
 * Se escribe como unión de literales, no como `enum`, por la misma razón que
 * `Rol` y `TipoPrograma`: la base guarda `text` con un `check`, y la unión es
 * lo que `z.infer` devuelve tal cual.
 */
export type TipoEntidadArchivo = 'TASK_SUBMISSION' | 'TEACHER_GUIDE';

export const TIPOS_ENTIDAD_ARCHIVO: readonly TipoEntidadArchivo[] = [
  'TASK_SUBMISSION',
  'TEACHER_GUIDE',
];

export function esTipoEntidadArchivo(valor: unknown): valor is TipoEntidadArchivo {
  return (
    typeof valor === 'string' &&
    (TIPOS_ENTIDAD_ARCHIVO as readonly string[]).includes(valor)
  );
}

/**
 * Ciclo de vida de un archivo.
 *
 * `PENDING` (fila reservada, objeto aún sin verificar) → `CONFIRMED` (el
 * backend comprobó con HeadObject que el objeto llegó) → `DELETED` (borrado
 * lógico). No hay vuelta atrás: los tres estados de destino son terminales, y
 * por eso las RPC que los aplican rechazan una transición ya hecha.
 */
export type EstadoArchivo = 'PENDING' | 'CONFIRMED' | 'DELETED';

export const ESTADOS_ARCHIVO: readonly EstadoArchivo[] = [
  'PENDING',
  'CONFIRMED',
  'DELETED',
];

export function esEstadoArchivo(valor: unknown): valor is EstadoArchivo {
  return (
    typeof valor === 'string' && (ESTADOS_ARCHIVO as readonly string[]).includes(valor)
  );
}

/**
 * Los metadatos de un archivo, tal como viven en `files_metadata`.
 *
 * En `camelCase` y con nombres en español, como el resto del dominio: la
 * traducción desde las columnas de la base ocurre en el repositorio, en un solo
 * sitio. La clave real de R2 (`r2Key`) se expone porque el backend la necesita
 * para firmar la descarga; **nunca** viaja al cliente como ruta del bucket.
 */
export interface ArchivoMetadata {
  id: string;
  propietarioId: string;
  /** Clave del objeto en R2. La construye siempre el servidor. */
  r2Key: string;
  nombreOriginal: string;
  tipoContenido: string;
  /**
   * Tamaño real del objeto. `null` mientras está `PENDING`: una subida a medias
   * no tiene tamaño, y el valor definitivo lo sella la confirmación.
   */
  tamanoBytes: number | null;
  entityType: TipoEntidadArchivo;
  /** Id de la tarea o guía concreta. `null` si la entidad aún no existe. */
  entidadId: string | null;
  estado: EstadoArchivo;
  creadoEn: string;
  confirmadoEn: string | null;
  borradoEn: string | null;
}

// --- Módulo 6: aula virtual -------------------------------------------------

/**
 * Ciclo de vida de un anuncio del tablón.
 *
 * Se declara como unión de literales **derivada del arreglo**, y no al revés.
 * El arreglo es la única fuente: de él salen el tipo, el guardián y el `z.enum`
 * de `esquemas.ts`, así que el contrato de la API y el `check` de
 * `m6_anuncios.estado` no pueden desviarse sin que el compilador lo diga. Es la
 * misma decisión que en `EstadoArchivo`: la base guarda `text` con un `check`, y
 * el literal de la unión es lo que `z.infer` devuelve tal cual.
 *
 * El borrado es **lógico**: `ELIMINADO` conserva la fila como historial.
 */
export const ESTADOS_ANUNCIO = ['BORRADOR', 'PUBLICADO', 'ELIMINADO'] as const;

export type EstadoAnuncio = (typeof ESTADOS_ANUNCIO)[number];

export function esEstadoAnuncio(valor: unknown): valor is EstadoAnuncio {
  return (
    typeof valor === 'string' &&
    (ESTADOS_ANUNCIO as readonly string[]).includes(valor)
  );
}

/**
 * Ciclo de vida de una tarea o un material.
 *
 * Nace `BORRADOR` **sin entregas**: publicar es lo que crea los placeholders,
 * uno por matrícula `ENROLLED`. Publicar dos veces no duplica nada.
 */
export const ESTADOS_TAREA = ['BORRADOR', 'PUBLICADO', 'ELIMINADO'] as const;

export type EstadoTarea = (typeof ESTADOS_TAREA)[number];

export function esEstadoTarea(valor: unknown): valor is EstadoTarea {
  return (
    typeof valor === 'string' &&
    (ESTADOS_TAREA as readonly string[]).includes(valor)
  );
}

/**
 * Clase de trabajo de clase.
 *
 * `MATERIAL` es el `CourseWorkMaterial` de Google: lectura, sin nota ni fecha
 * límite, y **sin entregas**. `PREGUNTA` queda como marcador —el motor de
 * preguntas de opción múltiple es un ciclo propio— y por eso la unión lo incluye
 * aunque hoy no se produzca. La coherencia por tipo la imponen los `CHECK` de la
 * tabla, no esta unión.
 */
export const TIPOS_TAREA = ['TAREA', 'MATERIAL', 'PREGUNTA'] as const;

export type TipoTarea = (typeof TIPOS_TAREA)[number];

export function esTipoTarea(valor: unknown): valor is TipoTarea {
  return typeof valor === 'string' && (TIPOS_TAREA as readonly string[]).includes(valor);
}

/**
 * Estado de una entrega.
 *
 * `ASIGNADA` es el placeholder recién creado al publicar; `ENTREGADA` sella la
 * fecha y el retraso; `DEVUELTA` cierra el ciclo con la nota ya visible; y
 * `RECLAMADA` es el «des-entregar» de Google, que vuelve a habilitar la entrega.
 */
export const ESTADOS_ENTREGA = [
  'ASIGNADA',
  'ENTREGADA',
  'DEVUELTA',
  'RECLAMADA',
] as const;

export type EstadoEntrega = (typeof ESTADOS_ENTREGA)[number];

export function esEstadoEntrega(valor: unknown): valor is EstadoEntrega {
  return (
    typeof valor === 'string' &&
    (ESTADOS_ENTREGA as readonly string[]).includes(valor)
  );
}

/**
 * Un anuncio del tablón de una sección.
 *
 * Quién lo ve lo decide la **RLS**, no la API (ADR-003): un `BORRADOR` con
 * `programadoPara` ya vencida es visible para el alumno sin que ningún proceso lo
 * haya tocado —la publicación diferida se resuelve en la lectura, porque el
 * INCES tiene cortes eléctricos y arquitectura dual—. `publicadoEn` ordena el
 * feed y es distinto de la fecha de creación del borrador.
 */
export interface Anuncio {
  id: string;
  seccionId: string;
  autorId: string;
  titulo: string;
  cuerpo: string;
  estado: EstadoAnuncio;
  /** Publicación diferida. `null` si no se programó. */
  programadoPara: string | null;
  /** Cuándo se publicó de verdad. `null` mientras es borrador. */
  publicadoEn: string | null;
}

/**
 * Trabajo de clase: una tarea, un material o (a futuro) una pregunta.
 *
 * Los adjuntos no se remodelan: se reutilizan los `files_metadata` de M5, donde
 * `TEACHER_GUIDE` apunta a esta tabla y `TASK_SUBMISSION` a la entrega.
 * `puntosMaximos` está en la escala 0–20 venezolana, y vale 0 sólo para
 * `MATERIAL` —lo garantizan los `CHECK` de coherencia por tipo—.
 */
export interface Tarea {
  id: string;
  seccionId: string;
  titulo: string;
  descripcion: string;
  tipo: TipoTarea;
  /** Puntos sobre 20. `0` sólo para `MATERIAL`. */
  puntosMaximos: number;
  /** `null` = sin plazo. Es la referencia de «tardía» y de «faltante». */
  fechaLimite: string | null;
  permitirEntregaTardia: boolean;
  /** Agrupación por texto. `null` = sin tema. */
  tema: string | null;
  orden: number;
  estado: EstadoTarea;
  publicadoEn: string | null;
}

/**
 * La entrega vista por el **alumno**.
 *
 * **No lleva `notaBorrador`, y no es un olvido.** Esa columna está protegida por
 * un `GRANT` por columna —`authenticated` no tiene privilegio de `SELECT` sobre
 * ella—, así que ni siquiera puede leerse desde aquí: la nota en borrador sólo la
 * ven las RPC `security definer` del docente. `notaAsignada` es la que el alumno
 * ya puede ver, y es `null` hasta que el docente devuelve.
 */
export interface Entrega {
  id: string;
  tareaId: string;
  estado: EstadoEntrega;
  /** Se fija al entregar comparando con la fecha límite; es un hecho histórico. */
  esTardia: boolean;
  /** Nota ya devuelta al alumno. `null` mientras el ciclo no se cierra. */
  notaAsignada: number | null;
  entregadaEn: string | null;
}

/**
 * La fila del libro de calificaciones del docente.
 *
 * Sale de la RPC `m6_entregas_de_tarea`, que es `security definer` y por eso sí
 * lee `notaBorrador` —el `GRANT` por columna se lo esconde a `authenticated`—.
 * Sin esa RPC, la ruta del libro habría nacido con la columna en blanco y el
 * docente habría calificado a ciegas.
 *
 * `faltante` es **derivada al leer**, no una columna: `ASIGNADA` con la fecha
 * límite ya vencida. Escribir un 0 automático congelaría una opinión —un alumno
 * que entrega tarde seguiría con el 0 puesto— y es justo lo que la decisión 1
 * descarta.
 */
export interface LibroEntrega {
  id: string;
  estudianteId: string;
  estado: EstadoEntrega;
  esTardia: boolean;
  /** Nota del docente antes de devolver. Sólo la ve el docente. */
  notaBorrador: number | null;
  notaAsignada: number | null;
  entregadaEn: string | null;
  devueltaEn: string | null;
  /** `estado = ASIGNADA` con la fecha límite vencida. Se deriva, no se guarda. */
  faltante: boolean;
}

/**
 * La cabecera de una tarea publicada.
 *
 * La RPC `m6_publicar_tarea` no devuelve la tarea entera —sólo su estado y el
 * recuento de entregas creadas—, así que el puerto devuelve exactamente lo que la
 * base devuelve. Completar aquí los campos que faltan sería inventarlos.
 */
export interface TareaPublicada {
  id: string;
  seccionId: string;
  titulo: string;
  estado: EstadoTarea;
  publicadoEn: string | null;
}

/** Lo que devuelve publicar: la cabecera y cuántos placeholders se crearon. */
export interface PublicacionTarea {
  tarea: TareaPublicada;
  /**
   * Cuántas entregas se crearon en **esta** llamada. Republicar devuelve 0: el
   * `unique (tarea_id, estudiante_id)` con `on conflict do nothing` lo garantiza
   * en la base, no en la ruta.
   */
  entregasCreadas: number;
}

/**
 * La entrega tal como la devuelven las RPC del docente.
 *
 * `notaBorrador` viaja aquí a propósito: quien llama es el docente de la sección
 * y la RPC ya lo autorizó. `devueltaEn` sólo la sella la devolución; la
 * calificación no toca esa columna, así que llega ausente.
 */
export interface EntregaCalificada {
  id: string;
  tareaId: string;
  estudianteId: string;
  estado: EstadoEntrega;
  esTardia: boolean;
  notaBorrador: number | null;
  notaAsignada: number | null;
  /** Sólo lo trae la devolución. */
  devueltaEn?: string | null;
}
