import type { FastifyInstance } from 'fastify';
import { construirApp } from '../../src/app.js';
import { cargarEnv, type Env } from '../../src/config/env.js';
import type {
  EntradaRegistrarArchivo,
  PuertaAlmacenamiento,
  PuertaArchivos,
  PuertaAula,
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaCuadrante,
  PuertaCurriculo,
  PuertaInscripciones,
  PuertaInvitacionesDocente,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  PuertaSecciones,
  Repositorios,
} from '../../src/dominio/puertos.js';
import { ErrorApi } from '../../src/dominio/errores.js';
import {
  construirClave,
  extensionDe,
  tipoContenidoDe,
  validarClave,
} from '../../src/dominio/almacenamiento.js';
import { agruparPensum, pensumEditable } from '../../src/dominio/reglas-curriculo.js';
import { diaLegible, turnoDeBloque } from '../../src/dominio/reglas-cuadrante.js';
import { ofertaVencida } from '../../src/dominio/reglas-inscripciones.js';
import type { EnvioCorreo } from '../../src/infra/correo.js';
import type {
  Aula,
  ArchivoMetadata,
  Anuncio,
  CambiosModulo,
  ClaseCuadrante,
  DetallePrograma,
  EntradaAcceso,
  EntradaAuditoria,
  EntradaPensum,
  Entrega,
  EntregaCalificada,
  EstadoArchivo,
  EstadoAnuncio,
  EstadoEntrega,
  EstadoInscripcion,
  EstadoTarea,
  Guardia,
  InscripcionDetallada,
  InvitacionDocente,
  LibroEntrega,
  Materia,
  MateriaEnPensum,
  ModuloSistema,
  OcupacionSeccion,
  ParametroSistema,
  Perfil,
  Periodo,
  Programa,
  PublicacionTarea,
  Rol,
  Seccion,
  Tarea,
  TipoEntidadArchivo,
  TipoTarea,
} from '../../src/dominio/tipos.js';

/**
 * Arnés de pruebas.
 *
 * Monta la API completa con repositorios en memoria: sin red, sin Supabase y
 * sin credenciales. Es la contrapartida backend de `FakeGateway` en Flutter, y
 * existe por la misma razón: sin puertos inyectables, este camino no se podría
 * probar en absoluto.
 */

// --- datos de ejemplo -------------------------------------------------------

export const ID_ADMIN = '11111111-1111-1111-1111-111111111111';
export const ID_ALUMNO = '22222222-2222-2222-2222-222222222222';

export const TOKEN_ADMIN = 'token-admin';
export const TOKEN_ALUMNO = 'token-alumno';
/** Token del docente de ejemplo. Lo estrena M3: es el rol con horario propio. */
export const TOKEN_DOCENTE = 'token-docente';

export const PERFIL_ADMIN: Perfil = {
  id: ID_ADMIN,
  email: 'admin@inces.test',
  cedula: '11111111',
  nombres: 'Ada',
  apellidos: 'Administradora',
  rol: 'admin',
  activo: true,
};

export const PERFIL_ALUMNO: Perfil = {
  id: ID_ALUMNO,
  email: 'alumno@inces.test',
  cedula: '87654321',
  nombres: 'Ana',
  apellidos: 'Pérez',
  rol: 'estudiante',
  activo: true,
};

/**
 * Un segundo estudiante, **fuera de los perfiles por defecto**.
 *
 * Las pruebas de cupo necesitan dos personas distintas: el cupo sólo se pone a
 * prueba cuando alguien ocupa el asiento y otro lo pide. Meterlo en
 * `PERFILES_POR_DEFECTO` habría cambiado el total de usuarios y roto las pruebas
 * de paginación de M1, así que se opta por él explícitamente:
 *
 * ```ts
 * crearArnés({
 *   perfiles: [...PERFILES_POR_DEFECTO, PERFIL_ALUMNO_2],
 *   identidades: { [TOKEN_ALUMNO_2]: ID_ALUMNO_2 },
 * })
 * ```
 */
export const ID_ALUMNO_2 = '22222222-2222-2222-2222-222222222223';
export const TOKEN_ALUMNO_2 = 'token-alumno-2';

export const PERFIL_ALUMNO_2: Perfil = {
  id: ID_ALUMNO_2,
  email: 'iris@inces.test',
  cedula: '11223344',
  nombres: 'Iris',
  apellidos: 'Vega',
  rol: 'estudiante',
  activo: true,
};

export const ID_DOCENTE = '33333333-3333-3333-3333-333333333333';

export const PERFIL_DOCENTE: Perfil = {
  id: ID_DOCENTE,
  email: 'docente@inces.test',
  cedula: '12345678',
  nombres: 'Carlos',
  apellidos: 'Rondón',
  rol: 'docente',
  activo: true,
};

/**
 * Un alumno inactivo, con apellido que ordena **antes** que «Pérez».
 *
 * Existe para que las pruebas de paginación y de filtro tengan algo que
 * distinguir: con dos perfiles activos siempre cabe todo en una página, y una
 * prueba de paginación que nunca pagina no prueba nada.
 */
export const PERFIL_ALUMNO_INACTIVO: Perfil = {
  id: '55555555-5555-5555-5555-555555555555',
  email: 'inactivo@inces.test',
  cedula: '99887766',
  nombres: 'Bruno',
  apellidos: 'Aguilar',
  rol: 'estudiante',
  activo: false,
};

export const PERFILES_POR_DEFECTO: Perfil[] = [
  PERFIL_ADMIN,
  PERFIL_ALUMNO,
  PERFIL_DOCENTE,
  PERFIL_ALUMNO_INACTIVO,
];

export function modulo(
  parcial: Partial<ModuloSistema> & { clave: string },
): ModuloSistema {
  return {
    nombre: parcial.clave,
    descripcion: null,
    habilitado: true,
    orden: 0,
    icono: null,
    rolesPermitidos: [],
    categoria: 'general',
    actualizadoEn: null,
    ...parcial,
  };
}

export function parametro(
  parcial: Partial<ParametroSistema> & { clave: string },
): ParametroSistema {
  return {
    valor: null,
    tipo: 'string',
    descripcion: null,
    categoria: 'general',
    esPublico: false,
    actualizadoEn: null,
    ...parcial,
  };
}

/**
 * Entrada de la traza de accesos.
 *
 * `createdAt` es obligatorio porque el orden es justo lo que se está probando:
 * dejarlo al valor de `new Date()` haría que dos filas registradas en el mismo
 * milisegundo compartieran marca de tiempo y el orden descendente dejara de ser
 * determinista, convirtiendo una prueba de paginación en una ruleta.
 */
export function entradaAcceso(
  parcial: Partial<EntradaAcceso> & { id: string; email: string; createdAt: string },
): EntradaAcceso {
  return {
    userId: null,
    ip: null,
    estado: 'SUCCESS',
    ...parcial,
  };
}

// --- datos de ejemplo de M2 -------------------------------------------------

/**
 * Identificadores de M2.
 *
 * Se escriben con la forma de un UUID v4 real (`-4xxx-8xxx-`) y no con el
 * `1111-1111-1111` de los perfiles, porque **estos sí pasan por el `.uuid()` de
 * Zod** en las rutas: el esquema de Zod rechaza las versiones que no existen, y
 * un fixture con forma inválida haría fallar la prueba por el motivo
 * equivocado.
 */
export const ID_PROGRAMA_SISTEMAS = '11111111-1111-4111-8111-111111111111';
export const ID_PROGRAMA_HERRERIA = '22222222-2222-4222-8222-222222222222';
export const ID_PROGRAMA_VACIO = '33333333-3333-4333-8333-333333333333';

export const ID_MATERIA_ALGORITMICA = 'aaaaaaaa-1111-4111-8111-111111111111';
export const ID_MATERIA_BASEDATOS = 'aaaaaaaa-2222-4222-8222-222222222222';
export const ID_MATERIA_INGLES = 'aaaaaaaa-3333-4333-8333-333333333333';
export const ID_MATERIA_MATEMATICA = 'aaaaaaaa-4444-4444-8444-444444444444';

export const PROGRAMA_SISTEMAS: Programa = {
  id: ID_PROGRAMA_SISTEMAS,
  codigo: 'SIST-01',
  nombre: 'Análisis de Sistemas',
  tipo: 'CARRERA',
  requierePasantia: true,
  activo: true,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

export const PROGRAMA_HERRERIA: Programa = {
  id: ID_PROGRAMA_HERRERIA,
  codigo: 'CUR-HER-01',
  nombre: 'Herrería',
  tipo: 'CURSO_LIBRE',
  requierePasantia: false,
  activo: true,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

/**
 * Una carrera **en borrador y sin materias**.
 *
 * Existe para poder probar la Regla 1: publicarla (`activo: true`) debe dar 400,
 * y es el caso real que el constraint trigger diferido existe para atrapar.
 * Sin un programa así en los datos, esa prueba no tendría nada que publicar.
 */
export const PROGRAMA_VACIO: Programa = {
  id: ID_PROGRAMA_VACIO,
  codigo: 'SIST-99',
  nombre: 'Carrera sin pensum',
  tipo: 'CARRERA',
  requierePasantia: false,
  activo: false,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

export const MATERIA_ALGORITMICA: Materia = {
  id: ID_MATERIA_ALGORITMICA,
  codigo: 'ALG-I',
  nombre: 'Algorítmica I',
  horasAcademicas: 96,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

export const MATERIA_BASEDATOS: Materia = {
  id: ID_MATERIA_BASEDATOS,
  codigo: 'BD-II',
  nombre: 'Bases de Datos II',
  horasAcademicas: 120,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

export const MATERIA_INGLES: Materia = {
  id: ID_MATERIA_INGLES,
  codigo: 'ING-TEC',
  nombre: 'Inglés Técnico',
  horasAcademicas: 48,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

/**
 * Una cuarta materia que **no está en ningún pensum por defecto**.
 *
 * Existe para poder probar el único caso en que la Regla 2 **no** bloquea:
 * añadir una materia a un pensum que ya está en uso. Sin una materia libre, esa
 * prueba no tendría nada que añadir y el reparto del trigger quedaría sin
 * comprobar.
 */
export const MATERIA_MATEMATICA: Materia = {
  id: ID_MATERIA_MATEMATICA,
  codigo: 'MAT-I',
  nombre: 'Matemática I',
  horasAcademicas: 96,
  creadoEn: '2026-09-01T10:00:00.000Z',
  actualizadoEn: '2026-09-01T10:00:00.000Z',
};

export const PROGRAMAS_POR_DEFECTO: Programa[] = [
  PROGRAMA_SISTEMAS,
  PROGRAMA_HERRERIA,
  PROGRAMA_VACIO,
];

export const MATERIAS_POR_DEFECTO: Materia[] = [
  MATERIA_ALGORITMICA,
  MATERIA_BASEDATOS,
  MATERIA_INGLES,
  MATERIA_MATEMATICA,
];

/**
 * Pensum de los programas de ejemplo.
 *
 * El de Sistemas usa períodos `[1, 1, 4]` **a propósito**: saltar del 1 al 4
 * deja el hueco de los períodos 2 y 3, y así cualquier prueba que pase por el
 * detalle comprueba de paso que la agrupación no inventa períodos vacíos.
 */
export const PENSUM_POR_DEFECTO: Record<string, EntradaPensum[]> = {
  [ID_PROGRAMA_SISTEMAS]: [
    { materiaId: ID_MATERIA_ALGORITMICA, periodo: 1 },
    { materiaId: ID_MATERIA_BASEDATOS, periodo: 1 },
    { materiaId: ID_MATERIA_INGLES, periodo: 4 },
  ],
  [ID_PROGRAMA_HERRERIA]: [],
  [ID_PROGRAMA_VACIO]: [],
};

// --- datos de ejemplo de M3 -------------------------------------------------

/**
 * Identificadores de M3, con forma de UUID v4 real.
 *
 * Estos **sí pasan por el `.uuid()` de Zod** en las rutas, así que llevan la
 * versión (`-4xxx-`) y la variante (`-8xxx-`) que el esquema exige. Un fixture
 * con forma inválida haría fallar la prueba por el motivo equivocado.
 */
export const ID_AULA_TALLER = 'aaaaaaaa-0001-4001-8001-000000000001';
export const ID_AULA_TEORICA = 'aaaaaaaa-0002-4002-8002-000000000002';
export const ID_AULA_ZONA = 'aaaaaaaa-0003-4003-8003-000000000003';

export const ID_PERIODO_2026_1 = 'bbbbbbbb-0001-4001-8001-000000000001';
export const ID_PERIODO_2026_2 = 'bbbbbbbb-0002-4002-8002-000000000002';

export const ID_SECCION_SA = 'cccccccc-0001-4001-8001-000000000001';
export const ID_SECCION_SC = 'cccccccc-0002-4002-8002-000000000002';

export const ID_CLASE_MIERCOLES = 'dddddddd-0001-4001-8001-000000000001';
export const ID_CLASE_LUNES = 'dddddddd-0002-4002-8002-000000000002';

export const ID_GUARDIA_LUNES = 'eeeeeeee-0001-4001-8001-000000000001';

/** Un segundo docente, **fuera de `PERFILES_POR_DEFECTO` a propósito**. */
export const ID_DOCENTE_2 = '44444444-4444-4444-4444-444444444444';

/**
 * Un segundo docente.
 *
 * **No está en `PERFILES_POR_DEFECTO` y no debe estarlo.** Añadirlo cambiaría el
 * recuento de perfiles y rompería las pruebas de paginación de `admin.test.ts`,
 * que fijan «1 a 25 de 4». Las pruebas que lo necesitan lo pasan explícitamente
 * en las opciones del arnés.
 *
 * Existe por una razón concreta: para probar que **el espacio** está ocupado hace
 * falta un segundo docente. Con el mismo docente, el chequeo del docente salta
 * primero y la comprobación del aula nunca se llega a ejercitar.
 */
export const PERFIL_DOCENTE_2: Perfil = {
  id: ID_DOCENTE_2,
  email: 'docente2@inces.test',
  cedula: '11223344',
  nombres: 'Luisa',
  apellidos: 'Márquez',
  rol: 'docente',
  activo: true,
};

export const AULA_TALLER: Aula = {
  id: ID_AULA_TALLER,
  nombre: 'Taller de Soldadura Cabina A',
  capacidad: 12,
  esTaller: true,
  activa: true,
  creadoEn: '2026-09-15T10:00:00.000Z',
  actualizadoEn: '2026-09-15T10:00:00.000Z',
};

export const AULA_TEORICA: Aula = {
  id: ID_AULA_TEORICA,
  nombre: 'Aula Teórica 2',
  capacidad: 30,
  esTaller: false,
  activa: true,
  creadoEn: '2026-09-15T10:00:00.000Z',
  actualizadoEn: '2026-09-15T10:00:00.000Z',
};

/** Una zona de custodia: cupo 0, no es taller. */
export const AULA_ZONA: Aula = {
  id: ID_AULA_ZONA,
  nombre: 'Pasillo de talleres',
  capacidad: 0,
  esTaller: false,
  activa: true,
  creadoEn: '2026-09-15T10:00:00.000Z',
  actualizadoEn: '2026-09-15T10:00:00.000Z',
};

export const AULAS_POR_DEFECTO: Aula[] = [AULA_TALLER, AULA_TEORICA, AULA_ZONA];

/**
 * El lapso vigente, `2026-1`.
 *
 * Es el valor real que hay en `system_settings.periodo_activo` en producción, y
 * el que la migración de M3 sembró leyéndolo de ahí.
 *
 * `vigente` se pone en `false` **a propósito** aunque este sea el vigente: el
 * doble recalcula ese campo en cada lectura a partir de `periodoCodigoVigente`,
 * igual que el repositorio real. Si se guardara, un test podría fijar un estado
 * que la base no puede producir.
 */
export const PERIODO_2026_1: Periodo = {
  id: ID_PERIODO_2026_1,
  codigo: '2026-1',
  nombre: 'Lapso 2026-1',
  fechaInicio: null,
  fechaFin: null,
  activo: true,
  vigente: false,
  creadoEn: '2026-09-15T10:00:00.000Z',
  actualizadoEn: '2026-09-15T10:00:00.000Z',
};

/** El lapso siguiente: abierto para planificar, todavía no vigente. */
export const PERIODO_2026_2: Periodo = {
  id: ID_PERIODO_2026_2,
  codigo: '2026-2',
  nombre: 'Lapso 2026-2',
  fechaInicio: '2026-09-21',
  fechaFin: '2027-02-13',
  activo: true,
  vigente: false,
  creadoEn: '2026-09-15T10:00:00.000Z',
  actualizadoEn: '2026-09-15T10:00:00.000Z',
};

export const PERIODOS_POR_DEFECTO: Periodo[] = [PERIODO_2026_1, PERIODO_2026_2];

/** Código del lapso vigente por defecto en el arnés. */
export const PERIODO_VIGENTE_POR_DEFECTO = '2026-1';

/**
 * Una sección, reducida a lo que el cuadrante necesita.
 *
 * No se modela la tabla `sections` entera: el cuadrante sólo la usa para dos
 * cosas —derivar el período y resolver el nombre—, y fingir el resto daría una
 * sensación de cobertura que no aporta nada.
 *
 * El `periodo` vive aquí y **no** en la clase, igual que en la base: es lo que
 * hace que el chequeo de colisiones compare dentro de un lapso y no entre lapsos.
 */
export interface SeccionFalsa {
  id: string;
  programaId: string;
  materiaId: string;
  /** Código del lapso al que pertenece la sección. */
  periodo: string;
  /** Identificador corto dentro del período ('SA', 'SC'). */
  nombre: string;
  /**
   * Cupo declarado de la sección, o `null` para «usa el global del centro».
   *
   * Se deja opcional y por defecto `null` para no reescribir las secciones que ya
   * existían antes de M4: ninguna de ellas declaraba cupo, así que `null` es
   * además el valor históricamente correcto.
   */
  cupoMaximo?: number | null;
  activa?: boolean;
}

export const SECCION_SA: SeccionFalsa = {
  id: ID_SECCION_SA,
  programaId: ID_PROGRAMA_SISTEMAS,
  materiaId: ID_MATERIA_ALGORITMICA,
  periodo: '2026-1',
  nombre: 'SA',
};

export const SECCION_SC: SeccionFalsa = {
  id: ID_SECCION_SC,
  programaId: ID_PROGRAMA_SISTEMAS,
  materiaId: ID_MATERIA_BASEDATOS,
  periodo: '2026-1',
  nombre: 'SC',
};

export const SECCIONES_POR_DEFECTO: SeccionFalsa[] = [SECCION_SA, SECCION_SC];

/**
 * Una clase del cuadrante tal como se **guarda**: sin período y sin nombres.
 *
 * El período se deriva de la sección y los nombres los resuelve la vista. El
 * doble hace lo mismo en cada lectura, así que una prueba no puede construir una
 * clase cuyo período contradiga al de su sección —un estado que la base no
 * admite—.
 */
export interface ClaseFalsa {
  id: string;
  seccionId: string;
  docenteId: string;
  aulaId: string;
  dia: number;
  bloque: number;
  activa: boolean;
}

/** Una guardia con el `turno` ya derivado del bloque, como la columna generada. */
export function guardiaFalsa(
  parcial: Partial<Guardia> & {
    id: string;
    docenteId: string;
    aulaId: string;
    periodo: string;
    dia: number;
    bloque: number;
  },
): Guardia {
  return {
    notas: null,
    activa: true,
    creadoEn: '2026-09-15T10:00:00.000Z',
    actualizadoEn: '2026-09-15T10:00:00.000Z',
    ...parcial,
    // Después del `spread` a propósito: el turno se **deriva** del bloque y no se
    // acepta de quien construye el fixture, igual que en la columna generada.
    turno: turnoDeBloque(parcial.bloque),
  };
}

/**
 * La guardia por defecto: el docente de ejemplo cubre el pasillo el lunes a
 * primera hora.
 *
 * Existe para que el chequeo de colisiones tenga algo contra lo que chocar sin
 * que cada prueba tenga que montarlo. Es el caso real del requisito: una guardia
 * ocupa al docente **aunque no haya clase**.
 */
export const GUARDIA_LUNES: Guardia = guardiaFalsa({
  id: ID_GUARDIA_LUNES,
  docenteId: ID_DOCENTE,
  aulaId: ID_AULA_ZONA,
  periodo: '2026-1',
  dia: 1,
  bloque: 1,
  notas: 'Apertura del taller',
});

export const GUARDIAS_POR_DEFECTO: Guardia[] = [GUARDIA_LUNES];

/** La clase por defecto: el miércoles, quinto bloque, en el taller. */
export const CLASE_MIERCOLES: ClaseFalsa = {
  id: ID_CLASE_MIERCOLES,
  seccionId: ID_SECCION_SA,
  docenteId: ID_DOCENTE,
  aulaId: ID_AULA_TALLER,
  dia: 3,
  bloque: 5,
  activa: true,
};

export const CLASES_POR_DEFECTO: ClaseFalsa[] = [CLASE_MIERCOLES];

/**
 * Una matrícula: qué estudiante está en qué sección.
 *
 * `estado` es opcional y por defecto `ENROLLED` para no reescribir la fila que ya
 * existía antes de M4 —el alumno de ejemplo está matriculado, no en cola—.
 *
 * `llegada` es el ordinal de inscripción y es lo que hace determinista la cola
 * FIFO. Usar la marca de tiempo real haría que dos filas creadas en el mismo
 * milisegundo pudieran ordenarse de dos formas distintas entre dos ejecuciones, y
 * una prueba de «el primero de la cola» pasaría o fallaría al azar.
 */
export interface InscripcionFalsa {
  id?: string;
  estudianteId: string;
  seccionId: string;
  estado?: EstadoInscripcion;
  /** Vencimiento de la oferta. Sólo tiene sentido con `PENDING_BID`. */
  ofertaVenceEn?: string | null;
  llegada?: number;
}

/**
 * El alumno de ejemplo está matriculado en la sección SA.
 *
 * Sin esta fila, el horario del estudiante saldría vacío y una prueba de
 * `mi-horario` pasaría sin haber comprobado nada.
 */
export const INSCRIPCIONES_POR_DEFECTO: InscripcionFalsa[] = [
  { estudianteId: ID_ALUMNO, seccionId: ID_SECCION_SA, llegada: 1 },
];

// --- datos de ejemplo de M5 -------------------------------------------------

/**
 * Un archivo de `files_metadata`, en memoria.
 *
 * `tamanoBytes` es `null` mientras el archivo está `PENDING`, y la distinción se
 * conserva igual que en la tabla: `0` sería un archivo vacío de verdad, que es
 * otra cosa que «todavía no se midió».
 *
 * La `r2Key` se declara explícitamente en vez de derivarla de `prefijoDeArchivo`
 * porque el doble necesita que sea **estable**: es la clave con la que el test
 * pone —o deja de poner— un objeto en el almacén falso.
 */
export interface ArchivoFalso {
  id?: string;
  propietarioId: string;
  r2Key: string;
  nombreOriginal: string;
  tipoContenido?: string;
  tamanoBytes?: number | null;
  entityType?: TipoEntidadArchivo;
  entidadId?: string | null;
  estado?: EstadoArchivo;
  creadoEn?: string;
  confirmadoEn?: string | null;
  borradoEn?: string | null;
}

/** Id del archivo confirmado por defecto. Es un UUID válido: viaja en la URL. */
export const ID_ARCHIVO_CONFIRMADO = 'a1b2c3d4-0000-4000-8000-000000000001';

/**
 * Clave del objeto confirmado por defecto, con la forma canónica que produce
 * `prefijoDeArchivo`: `m5_archivos/<propietario>/<año>/<mes>/<uuid>.<ext>`.
 *
 * Se escribe a mano y no se deriva, porque el prefijo lleva la fecha del reloj y
 * el id sale de un `randomUUID`: derivarla haría que la clave cambiara entre dos
 * ejecuciones y ninguna prueba podría referirse a ella.
 */
export const CLAVE_ARCHIVO_CONFIRMADO =
  'm5_archivos/22222222-2222-2222-2222-222222222222/2026/09/a1b2c3d4-0000-4000-8000-000000000001.pdf';

/** Tamaño del archivo confirmado por defecto: 1 KB, muy por debajo del tope. */
export const TAMANO_ARCHIVO_CONFIRMADO = 1024;

/**
 * Un archivo ya confirmado, del alumno de ejemplo, cuyo objeto **sí existe** en
 * el almacén falso.
 *
 * Se siembra confirmado a propósito: sin un archivo en ese estado, una prueba de
 * `url-lectura` sólo podría comprobar el 409 de «todavía no está disponible», y
 * el camino que sí firma la descarga —que es el que usa el usuario real— no se
 * ejercitaría nunca.
 */
export const ARCHIVOS_POR_DEFECTO: ArchivoFalso[] = [
  {
    id: ID_ARCHIVO_CONFIRMADO,
    propietarioId: ID_ALUMNO,
    r2Key: CLAVE_ARCHIVO_CONFIRMADO,
    nombreOriginal: 'constancia.pdf',
    tamanoBytes: TAMANO_ARCHIVO_CONFIRMADO,
    estado: 'CONFIRMED',
    entityType: 'TASK_SUBMISSION',
  },
];

// --- datos de ejemplo de M6 -------------------------------------------------

/**
 * Un anuncio del tablón, en memoria.
 *
 * `estado` y `publicadoEn` son opcionales y por defecto `BORRADOR` y `null`: así
 * una prueba que sólo quiere un borrador no tiene que escribir los dos campos, y
 * una que quiera el feed tiene que decir explícitamente que está publicado.
 */
export interface AnuncioFalso {
  id?: string;
  seccionId: string;
  autorId: string;
  titulo: string;
  cuerpo?: string;
  estado?: EstadoAnuncio;
  programadoPara?: string | null;
  publicadoEn?: string | null;
}

/** Una tarea o material de clase, en memoria. */
export interface TareaFalsa {
  id?: string;
  seccionId: string;
  titulo: string;
  descripcion?: string;
  tipo?: TipoTarea;
  puntosMaximos?: number;
  fechaLimite?: string | null;
  permitirEntregaTardia?: boolean;
  tema?: string | null;
  orden?: number;
  estado?: EstadoTarea;
  /** Publicación diferida: un borrador con esta fecha vencida es visible al alumno. */
  programadoPara?: string | null;
  publicadoEn?: string | null;
}

/**
 * Una entrega, en memoria.
 *
 * `notaBorrador` y `notaAsignada` son opcionales y por defecto `null`: la
 * ausencia **es** información —un ciclo que no ha avanzado— y confundirla con un
 * `0` inventaría una calificación.
 */
export interface EntregaFalso {
  id?: string;
  tareaId: string;
  estudianteId: string;
  estado?: EstadoEntrega;
  esTardia?: boolean;
  notaBorrador?: number | null;
  notaAsignada?: number | null;
  entregadaEn?: string | null;
  devueltaEn?: string | null;
}

/** UUIDs válidos: viajan por el `.uuid()` de las rutas, así que llevan forma v4. */
export const ID_ANUNCIO_SA = 'a6a6a6a6-0001-4001-8001-000000000001';
export const ID_TAREA_SA = 'b7b7b7b7-0001-4001-8001-000000000001';
export const ID_TAREA_BORRADOR = 'b7b7b7b7-0002-4002-8002-000000000002';
export const ID_ENTREGA_SA = 'c8c8c8c8-0001-4001-8001-000000000001';

/**
 * Un anuncio ya publicado en la sección del alumno de ejemplo.
 *
 * Sin un anuncio publicado, la prueba del tablón sólo comprobaría que la lista
 * viene vacía, y el camino que sí devuelve algo no se ejercitaría.
 */
export const ANUNCIOS_POR_DEFECTO: AnuncioFalso[] = [
  {
    id: ID_ANUNCIO_SA,
    seccionId: ID_SECCION_SA,
    autorId: ID_DOCENTE,
    titulo: 'Bienvenidos al lapso',
    cuerpo: 'El taller abre el lunes.',
    estado: 'PUBLICADO',
    publicadoEn: '2026-09-01T10:00:00.000Z',
  },
];

/**
 * Dos tareas en la sección del alumno: una publicada y una en borrador.
 *
 * La publicada trae un placeholder `ASIGNADA` para el alumno, que es lo que
 * permite recorrer el ciclo entero —entregar, calificar, devolver— sin sembrar
 * una entrega ya entregada. La de borrador existe para poder publicar algo de
 * verdad: sobre una ya publicada, `entregasCreadas` sería 0 y la prueba del
 * botón no probaría nada.
 */
export const TAREAS_POR_DEFECTO: TareaFalsa[] = [
  {
    id: ID_TAREA_SA,
    seccionId: ID_SECCION_SA,
    titulo: 'Práctica 1',
    tipo: 'TAREA',
    estado: 'PUBLICADO',
    publicadoEn: '2026-09-02T10:00:00.000Z',
  },
  {
    id: ID_TAREA_BORRADOR,
    seccionId: ID_SECCION_SA,
    titulo: 'Práctica 2',
    tipo: 'TAREA',
    estado: 'BORRADOR',
  },
];

/** El placeholder de entrega del alumno para la tarea publicada. */
export const ENTREGAS_POR_DEFECTO: EntregaFalso[] = [
  {
    id: ID_ENTREGA_SA,
    tareaId: ID_TAREA_SA,
    estudianteId: ID_ALUMNO,
    estado: 'ASIGNADA',
  },
];

// --- repositorios en memoria ------------------------------------------------

export interface EstadoFalso {
  perfiles: Perfil[];
  modulos: ModuloSistema[];
  parametros: ParametroSistema[];
  auditoria: EntradaAuditoria[];
  invitaciones: InvitacionDocente[];
  acceso: EntradaAcceso[];
  correos: { para: string; asunto: string }[];
  programas: Programa[];
  materias: Materia[];
  /** El pensum de cada programa, por id. Es la única fuente de los totales. */
  pensum: Record<string, EntradaPensum[]>;
  /**
   * Secciones activas del período vigente, por programa.
   *
   * Es el dato que decide la Regla 2. Se modela como un número y no como filas
   * de `sections` porque lo único que M2 hace con ellas es contarlas; fingir la
   * tabla entera daría una sensación de cobertura que no aporta nada.
   */
  seccionesActivas: Record<string, number>;

  // --- M3 ---
  aulas: Aula[];
  periodos: Periodo[];
  /** Código del lapso vigente, o `null` si no hay ninguno declarado. */
  periodoCodigoVigente: string | null;
  guardias: Guardia[];
  clases: ClaseFalsa[];
  secciones: SeccionFalsa[];
  inscripciones: InscripcionFalsa[];

  // --- M5 ---
  /**
   * Las filas de `files_metadata`.
   *
   * El doble **no** reproduce el ciclo de vida por sí solo: la fila avanza de
   * estado cuando la ruta llama a `confirmar` o `marcarBorrado`, igual que en la
   * base, donde el avance lo produce la RPC y no una convención del cliente.
   */
  archivos: ArchivoFalso[];

  // --- M6 ---
  /**
   * Las filas del aula virtual.
   *
   * El doble **no** reproduce el ciclo de vida por sí solo: la entrega avanza de
   * estado cuando la ruta llama a `entregar` o `calificar`, igual que en la base,
   * donde el avance lo produce la RPC y no una convención del cliente.
   */
  anuncios: AnuncioFalso[];
  tareas: TareaFalsa[];
  entregas: EntregaFalso[];

  /**
   * Id del usuario de la petición en curso, o `null` si va anónima.
   *
   * Los repositorios reales reciben un cliente de Supabase atado al JWT, así que
   * «quién llama» lo resuelve Postgres con `auth.uid()`. El doble no tiene JWT:
   * `reposDePeticion` fija este campo en cada petición y las operaciones de M4 lo
   * leen como si fuera `auth.uid()`.
   *
   * **Vale porque las pruebas inyectan peticiones de una en una.** Con dos
   * peticiones concurrentes de usuarios distintos, este campo sería el último que
   * escribiera y el doble atribuiría la operación al usuario equivocado. Es una
   * limitación del doble, no del código de producción — que sí es seguro, porque
   * cada petición tiene su propio cliente.
   */
  usuarioActual: string | null;
}

/**
 * El almacén falso, con su bucket a la vista.
 *
 * A diferencia de los repositorios, este doble **no** se limita a devolver datos:
 * expone el contenido del bucket para que una prueba pueda simular la subida
 * —poner el objeto— o comprobar que se borró. Sin esa puerta, el ciclo de dos
 * pasos de M5 no se podría recorrer entero, porque el objeto que el `HeadObject`
 * busca lo crea el cliente con un `PUT` que el backend nunca ve.
 */
export interface AlmacenamientoFalso extends PuertaAlmacenamiento {
  /** Objetos que «están» en el bucket: clave → tamaño en bytes. */
  objetos: Map<string, number>;
  /** Claves cuya eliminación se pidió, en orden. */
  borrados: string[];
}

export interface Arnés {
  app: FastifyInstance;
  estado: EstadoFalso;
  /** Nombres de las operaciones invocadas, en orden. */
  llamadas: string[];
  /** Errores a lanzar en la próxima llamada, por operación. */
  fallos: Partial<Record<string, unknown>>;
  env: Env;
  /**
   * El almacén inyectado en la app.
   *
   * Cuando el arnés se construye con `sinAlmacenamiento`, `construirApp` recibe
   * `null` en vez de este objeto y las rutas de M5 responden 503. El doble se
   * devuelve igualmente para que una prueba pueda inspeccionar sus llamadas sin
   * tener que comprobar antes si existe.
   */
  almacenamiento: AlmacenamientoFalso;
}

export interface OpcionesArnés {
  perfiles?: Perfil[];
  modulos?: ModuloSistema[];
  parametros?: ParametroSistema[];
  auditoria?: EntradaAuditoria[];
  /** Traza de accesos inicial (auth_logs), para las pruebas de auditoría. */
  acceso?: EntradaAcceso[];
  programas?: Programa[];
  materias?: Materia[];
  pensum?: Record<string, EntradaPensum[]>;
  /** Secciones activas por programa, para ejercitar la Regla 2. */
  seccionesActivas?: Record<string, number>;
  // --- M3 ---
  aulas?: Aula[];
  periodos?: Periodo[];
  /** Código del lapso vigente. `null` = ninguno declarado. */
  periodoCodigoVigente?: string | null;
  guardias?: Guardia[];
  clases?: ClaseFalsa[];
  secciones?: SeccionFalsa[];
  inscripciones?: InscripcionFalsa[];
  // --- M5 ---
  /** Filas de `files_metadata`. El bucket se siembra desde las `CONFIRMED`. */
  archivos?: ArchivoFalso[];
  // --- M6 ---
  /** Anuncios del tablón. Por defecto, uno publicado en la sección del alumno. */
  anuncios?: AnuncioFalso[];
  /** Trabajo de clase. Por defecto, una tarea publicada y una en borrador. */
  tareas?: TareaFalsa[];
  /** Entregas. Por defecto, el placeholder del alumno para la tarea publicada. */
  entregas?: EntregaFalso[];
  /**
   * Arranca el arnés **sin** almacenamiento, como un despliegue sin R2.
   *
   * Es la única forma de ejercitar el 503: el entorno del arnés no define las
   * variables de R2, así que en producción ese caso lo produciría
   * `crearAlmacenamiento`, pero aquí el arnés inyecta el almacén explícitamente y
   * sin esta opción siempre habría uno.
   */
  sinAlmacenamiento?: boolean;
  /**
   * Identidades extra: token → id de perfil.
   *
   * El arnés trae tres tokens fijos (admin, alumno, docente). Las pruebas que
   * necesitan una cuarta persona —las de cupo, que necesitan dos estudiantes—
   * añaden la suya aquí sin tocar los perfiles por defecto, que son el punto de
   * apoyo de las pruebas de paginación de M1.
   */
  identidades?: Record<string, string>;
  moduleCacheTtlMs?: number;
  settingsCacheTtlMs?: number;
}

/**
 * La semilla de `system_modules` del arnés.
 *
 * Se exporta para que una prueba pueda **variar una sola fila** —apagar un
 * módulo, como haría el administrador desde el cPanel— sin reescribir la lista
 * entera. Copiar la semilla en la prueba para cambiar un booleano es la forma
 * segura de que las dos copias se desvíen.
 */
export const MODULOS_POR_DEFECTO: ModuloSistema[] = [
  modulo({ clave: 'm0_cpanel', nombre: 'Administrador Maestro', orden: 0, rolesPermitidos: ['admin'] }),
  modulo({ clave: 'm1_onboarding', nombre: 'Autenticación', orden: 10 }),
  modulo({ clave: 'm4_inscripciones', nombre: 'Inscripciones', orden: 40, habilitado: false }),
  // M5 se siembra **encendido**, como queda en la nube tras `202609210002`.
  //
  // Y no basta con «ponerlo en true»: la fila **no existía** en esta semilla. Eso
  // importa porque las cinco rutas de archivos llevan la guardia
  // `exigirModulo('m5_archivos')` y `comprobarModulo` distingue tres fallos, no
  // uno: sin la fila el error sería **404 `MODULO_DESCONOCIDO`** («no está
  // registrado»), no 403 `MODULO_DESHABILITADO` («está apagado»). Las 34 pruebas
  // de `archivos.test.ts` habrían fallado por un motivo que no es el suyo y el
  // diagnóstico habría apuntado al sitio equivocado.
  //
  // El `habilitado: true` se escribe explícito aunque `modulo()` ya lo ponga por
  // defecto: es la mitad del asunto de esta fila y conviene que se lea.
  modulo({ clave: 'm5_archivos', nombre: 'Almacenamiento de Archivos', orden: 50, habilitado: true }),
  // M6 se siembra **encendido**, y es una decisión del arnés, no de la nube: la
  // migración `202609220001` lo deja en `false` a propósito y lo encenderá
  // `202609220002` cuando exista la UI. Aquí se enciende porque las rutas del
  // aula llevan `exigirModulo('m6_aula_virtual')` y `comprobarModulo` distingue
  // «no está registrado» (404) de «está apagado» (403): sin la fila, las diez
  // pruebas fallarían por un motivo que no es el suyo. El camino «apagado» tiene
  // su propia prueba, que pasa esta lista con la fila en `false`.
  modulo({ clave: 'm6_aula_virtual', nombre: 'Aula Virtual', orden: 55, habilitado: true }),
];

const PARAMETROS_POR_DEFECTO: ParametroSistema[] = [
  parametro({ clave: 'modo_mantenimiento', valor: false, tipo: 'boolean', esPublico: true }),
  parametro({ clave: 'max_faltas_consecutivas', valor: 3, tipo: 'number' }),
  // Cupo global del centro. Es el valor al que cae una sección con
  // `max_capacity = null`; `0` significaría «ninguna sección admite a nadie», que
  // dejaría todas las pruebas de inscripción en la cola por el motivo equivocado.
  parametro({ clave: 'cupo_maximo_por_seccion', valor: 30, tipo: 'number' }),
  // El motor de bids nace apagado (decisión de producto). El doble lo respeta
  // para que una prueba no dé por buena una oferta con vencimiento que la base no
  // produciría con la configuración por defecto.
  parametro({ clave: 'habilitar_sistema_bids', valor: false, tipo: 'boolean' }),
  parametro({ clave: 'bid_ttl_horas', valor: 24, tipo: 'number' }),

  // --- M5 ---
  // Los dos límites del módulo de archivos. Se siembran porque la migración
  // `202609210001` los siembra: el arnés tiene que parecerse a la nube, no a un
  // despliegue incompleto. El camino «falta la semilla» —el único que ejerce los
  // valores por defecto del código— tiene su propia prueba, que construye el
  // arnés con `parametros` explícitos.
  parametro({ clave: 'm5_max_bytes', valor: 10 * 1024 * 1024, tipo: 'number' }),
  parametro({ clave: 'm5_max_archivos_por_entidad', valor: 10, tipo: 'number' }),
];

/**
 * Ordena la traza de accesos del más reciente al más antiguo.
 *
 * Es el mismo criterio del repositorio real (`order created_at desc`). El
 * desempate por posición de inserción no es cosmético: sin él, dos filas con la
 * misma marca de tiempo podrían aparecer en distinto orden entre dos páginas y
 * una saldría dos veces mientras la otra no aparece.
 */
function accesosMasRecientesPrimero(entradas: EntradaAcceso[]): EntradaAcceso[] {
  return entradas
    .map((entrada, indice) => ({ entrada, indice }))
    .sort((a, b) => {
      const porFecha = b.entrada.createdAt.localeCompare(a.entrada.createdAt);
      if (porFecha !== 0) return porFecha;
      return b.indice - a.indice;
    })
    .map((conIndice) => conIndice.entrada);
}

/**
 * Copia un pensum por programa sin compartir referencias.
 *
 * Un arreglo compartido entre el valor por defecto y el estado del arnés haría
 * que un test que reemplaza un pensum modificara el de los siguientes: el
 * arnés entero pasaría a depender del orden en que corren las pruebas, que es
 * la clase de fallo que sólo aparece cuando la suite crece.
 */
function clonarPensum(origen: Record<string, EntradaPensum[]>): Record<string, EntradaPensum[]> {
  const copia: Record<string, EntradaPensum[]> = {};
  for (const [programaId, entradas] of Object.entries(origen)) {
    copia[programaId] = entradas.map((entrada) => ({ ...entrada }));
  }
  return copia;
}

/**
 * Copia sólo las claves definidas.
 *
 * Un `undefined` explícito no debe borrar un campo: en el dominio, «no lo
 * mandaron» y «mándalo vacío» son cosas distintas, y el repositorio real lo
 * resuelve con `if (cambios.x !== undefined)`. El `null` sí pasa, porque vaciar
 * un dato —unas fechas, unas notas— es una intención legítima.
 */
function soloDefinidos<T extends object>(cambios: T): Partial<T> {
  const limpio: Record<string, unknown> = {};
  for (const [clave, valor] of Object.entries(cambios)) {
    if (valor !== undefined) limpio[clave] = valor;
  }
  return limpio as Partial<T>;
}

/** El 400 que la base produce al violar una clave ajena (`23503`). */
function referenciaInvalida(): ErrorApi {
  return new ErrorApi(
    400,
    'REFERENCIA_INVALIDA',
    'Se hace referencia a un registro que no existe.',
  );
}

/** Orden cronológico de una rejilla: día, bloque y desempate estable por id. */
function porDiaBloque<T extends { dia: number; bloque: number; id: string }>(
  a: T,
  b: T,
): number {
  return a.dia - b.dia || a.bloque - b.bloque || a.id.localeCompare(b.id);
}

/** Construye el arnés completo con la API ya montada. */
export function crearArnés(opciones: OpcionesArnés = {}): Arnés {
  const estado: EstadoFalso = {
    perfiles: opciones.perfiles ?? [...PERFILES_POR_DEFECTO],
    modulos: opciones.modulos ?? [...MODULOS_POR_DEFECTO],
    parametros: opciones.parametros ?? [...PARAMETROS_POR_DEFECTO],
    auditoria: opciones.auditoria ?? [],
    invitaciones: [],
    acceso: opciones.acceso ?? [],
    correos: [],
    programas: opciones.programas ?? [...PROGRAMAS_POR_DEFECTO],
    materias: opciones.materias ?? [...MATERIAS_POR_DEFECTO],
    // Se copia en profundidad: el pensum es un objeto anidado, y compartir el
    // arreglo con el valor por defecto haría que un test que reemplaza un
    // pensum contaminara el siguiente. Es el fallo clásico de los dobles que
    // guardan estado por referencia.
    pensum: clonarPensum(opciones.pensum ?? PENSUM_POR_DEFECTO),
    seccionesActivas: { ...(opciones.seccionesActivas ?? {}) },
    // Los arreglos se copian con `map` y no se comparten con el valor por
    // defecto: un test que crea un aula no debe contaminar al siguiente. Es el
    // fallo clásico de los dobles que guardan estado por referencia.
    aulas: (opciones.aulas ?? AULAS_POR_DEFECTO).map((aula) => ({ ...aula })),
    periodos: (opciones.periodos ?? PERIODOS_POR_DEFECTO).map((periodo) => ({ ...periodo })),
    periodoCodigoVigente:
      opciones.periodoCodigoVigente === undefined
        ? PERIODO_VIGENTE_POR_DEFECTO
        : opciones.periodoCodigoVigente,
    guardias: (opciones.guardias ?? GUARDIAS_POR_DEFECTO).map((guardia) => ({ ...guardia })),
    clases: (opciones.clases ?? CLASES_POR_DEFECTO).map((clase) => ({ ...clase })),
    secciones: (opciones.secciones ?? SECCIONES_POR_DEFECTO).map((seccion) => ({ ...seccion })),
    inscripciones: (opciones.inscripciones ?? INSCRIPCIONES_POR_DEFECTO).map((i) => ({ ...i })),
    archivos: (opciones.archivos ?? ARCHIVOS_POR_DEFECTO).map((a) => ({ ...a })),
    anuncios: (opciones.anuncios ?? ANUNCIOS_POR_DEFECTO).map((a) => ({ ...a })),
    tareas: (opciones.tareas ?? TAREAS_POR_DEFECTO).map((t) => ({ ...t })),
    entregas: (opciones.entregas ?? ENTREGAS_POR_DEFECTO).map((e) => ({ ...e })),
    usuarioActual: null,
  };

  const llamadas: string[] = [];
  const fallos: Partial<Record<string, unknown>> = {};

  const revisar = (operacion: string): void => {
    llamadas.push(operacion);
    const fallo = fallos[operacion];
    if (fallo) throw fallo;
  };

  const perfiles: PuertaPerfiles = {
    async porId(id) {
      revisar('perfiles.porId');
      return estado.perfiles.find((p) => p.id === id) ?? null;
    },
    async listar(opciones) {
      revisar('perfiles.listar');

      const { rol, activo, busqueda, limite, desplazamiento } = opciones;

      // Se replica el comportamiento del repositorio real —filtrar, ordenar y
      // recortar— para que las pruebas ejerciten el contrato y no una versión
      // simplificada que devuelva todo y oculte un fallo de paginación.
      const aguja = busqueda?.toLowerCase();
      const coincide = (p: Perfil): boolean => {
        if (rol && p.rol !== rol) return false;
        if (activo !== undefined && p.activo !== activo) return false;
        if (!aguja) return true;
        return [p.nombres, p.apellidos, p.email, p.cedula ?? '']
          .join(' ')
          .toLowerCase()
          .includes(aguja);
      };

      const filtrados = estado.perfiles
        .filter(coincide)
        .sort((a, b) => {
          const porApellido = a.apellidos.localeCompare(b.apellidos);
          if (porApellido !== 0) return porApellido;
          const porNombre = a.nombres.localeCompare(b.nombres);
          if (porNombre !== 0) return porNombre;
          return a.id.localeCompare(b.id);
        });

      return {
        usuarios: filtrados.slice(desplazamiento, desplazamiento + limite),
        total: filtrados.length,
      };
    },
    async cambiarRol(id, rol) {
      revisar('perfiles.cambiarRol');
      const actual = estado.perfiles.find((p) => p.id === id);
      if (!actual) {
        throw ErrorApi.noEncontrado('PERFIL_INEXISTENTE', 'No existe ese usuario.');
      }
      const actualizado: Perfil = { ...actual, rol };
      estado.perfiles = estado.perfiles.map((p) => (p.id === id ? actualizado : p));
      return actualizado;
    },
    async contarAdminsActivos() {
      revisar('perfiles.contarAdminsActivos');
      return estado.perfiles.filter((p) => p.rol === 'admin' && p.activo).length;
    },
  };

  const modulos: PuertaModulos = {
    async todos() {
      revisar('modulos.todos');
      return [...estado.modulos];
    },
    async porClave(clave) {
      revisar('modulos.porClave');
      return estado.modulos.find((m) => m.clave === clave) ?? null;
    },
    async actualizar(clave, cambios: CambiosModulo) {
      revisar('modulos.actualizar');
      const anterior = estado.modulos.find((m) => m.clave === clave);
      if (!anterior) {
        throw ErrorApi.noEncontrado('MODULO_DESCONOCIDO', `No existe ${clave}.`);
      }
      const actualizado: ModuloSistema = {
        ...anterior,
        ...(cambios.habilitado === undefined ? {} : { habilitado: cambios.habilitado }),
        ...(cambios.orden === undefined ? {} : { orden: cambios.orden }),
        ...(cambios.rolesPermitidos === undefined
          ? {}
          : { rolesPermitidos: cambios.rolesPermitidos as Rol[] }),
      };
      estado.modulos = estado.modulos.map((m) => (m.clave === clave ? actualizado : m));
      estado.auditoria = [
        {
          id: `aud-${estado.auditoria.length + 1}`,
          tabla: 'system_modules',
          clave,
          valorAnterior: { habilitado: anterior.habilitado },
          valorNuevo: { habilitado: actualizado.habilitado },
          usuarioEmail: PERFIL_ADMIN.email,
          creadoEn: new Date().toISOString(),
        },
        ...estado.auditoria,
      ];
      return actualizado;
    },
  };

  const parametros: PuertaParametros = {
    async todos(incluirPrivados) {
      revisar('parametros.todos');
      return incluirPrivados
        ? [...estado.parametros]
        : estado.parametros.filter((p) => p.esPublico);
    },
    async porClave(clave) {
      revisar('parametros.porClave');
      return estado.parametros.find((p) => p.clave === clave) ?? null;
    },
    async actualizar(clave, valor) {
      revisar('parametros.actualizar');
      const anterior = estado.parametros.find((p) => p.clave === clave);
      if (!anterior) {
        throw ErrorApi.noEncontrado('PARAMETRO_DESCONOCIDO', `No existe ${clave}.`);
      }
      const actualizado: ParametroSistema = { ...anterior, valor };
      estado.parametros = estado.parametros.map((p) =>
        p.clave === clave ? actualizado : p,
      );
      return actualizado;
    },
  };

  const auditoria: PuertaAuditoria = {
    async listar(limite) {
      revisar('auditoria.listar');
      return estado.auditoria.slice(0, limite);
    },
  };

  const invitaciones: PuertaInvitacionesDocente = {
    async crear(entrada) {
      revisar('invitaciones.crear');
      const invitacion: InvitacionDocente = {
        id: `inv-${estado.invitaciones.length + 1}`,
        email: entrada.email,
        nombres: entrada.nombres,
        apellidos: entrada.apellidos,
        tokenHash: entrada.tokenHash,
        isUsed: false,
        createdAt: new Date().toISOString(),
        expiresAt: entrada.expiresAt,
      };
      estado.invitaciones = [...estado.invitaciones, invitacion];
      return invitacion;
    },
    async porTokenHash(tokenHash) {
      revisar('invitaciones.porTokenHash');
      return estado.invitaciones.find((i) => i.tokenHash === tokenHash) ?? null;
    },
    async marcarUsada(id) {
      revisar('invitaciones.marcarUsada');
      estado.invitaciones = estado.invitaciones.map((i) =>
        i.id === id ? { ...i, isUsed: true } : i,
      );
    },
    async crearUsuarioDocente(email, _password, nombres, apellidos) {
      revisar('invitaciones.crearUsuarioDocente');
      const id = `usr-${estado.perfiles.length + 1}-${estado.invitaciones.length}`;
      const perfil: Perfil = {
        id,
        email,
        cedula: null,
        nombres,
        apellidos,
        rol: 'estudiante',
        activo: true,
      };
      estado.perfiles = [...estado.perfiles, perfil];
      return id;
    },
  };

  const acceso: PuertaAuditoriaAcceso = {
    async registrar(entrada) {
      revisar('acceso.registrar');
      estado.acceso = [
        ...estado.acceso,
        {
          id: `acc-${estado.acceso.length + 1}`,
          userId: entrada.userId,
          email: entrada.email,
          ip: entrada.ip,
          estado: entrada.estado,
          createdAt: new Date().toISOString(),
        },
      ];
    },

    async listar(opciones) {
      revisar('acceso.listar');

      const { estado: filtroEstado, email, userId, limite, desplazamiento } = opciones;

      // Se replica el comportamiento del repositorio real —filtrar, ordenar y
      // recortar— para que las pruebas ejerciten el contrato y no una versión
      // simplificada que devuelva todo y oculte un fallo de paginación.
      const coincide = (e: EntradaAcceso): boolean => {
        if (filtroEstado && e.estado !== filtroEstado) return false;
        if (email && e.email !== email) return false;
        if (userId && e.userId !== userId) return false;
        return true;
      };

      const filtrados = accesosMasRecientesPrimero(estado.acceso).filter(coincide);

      return {
        entradas: filtrados.slice(desplazamiento, desplazamiento + limite),
        total: filtrados.length,
      };
    },
  };

  // --- Módulo 2 ------------------------------------------------------------

  /** Secuencias para los identificadores que se crean durante una prueba. */
  let secuenciaProgramas = 0;
  let secuenciaMaterias = 0;

  const nuevoId = (prefijo: string, secuencia: number): string =>
    `${prefijo}-0000-4000-8000-${String(secuencia).padStart(12, '0')}`;

  const pensumDe = (programaId: string): EntradaPensum[] => estado.pensum[programaId] ?? [];

  /**
   * Arma el detalle del programa.
   *
   * Usa las **funciones puras reales** (`agruparPensum`, `pensumEditable`) en
   * vez de reimplementarlas: un doble que agrupara a su manera podría pasar una
   * prueba que el código de producción no pasaría, y el fallo aparecería en
   * producción en lugar de aquí.
   */
  const armarDetalle = (programa: Programa): DetallePrograma => {
    const materias: MateriaEnPensum[] = pensumDe(programa.id).map((entrada) => {
      const materia = estado.materias.find((m) => m.id === entrada.materiaId);
      return {
        materiaId: entrada.materiaId,
        periodo: entrada.periodo,
        codigo: materia?.codigo ?? '',
        nombre: materia?.nombre ?? '',
        horasAcademicas: materia?.horasAcademicas ?? 0,
      };
    });

    const secciones = estado.seccionesActivas[programa.id] ?? 0;

    return {
      programa,
      pensum: agruparPensum(materias),
      seccionesActivas: secciones,
      editable: pensumEditable(secciones),
    };
  };

  /**
   * Comprueba que las materias del pensum existen.
   *
   * En la base lo impone el FK `program_subjects.subject_id`. Un doble que no
   * lo comprobara dejaría pasar un pensum con materias inventadas y la prueba
   * daría verde sobre un estado imposible.
   */
  const exigirMateriasExistentes = (pensum: EntradaPensum[]): void => {
    for (const entrada of pensum) {
      if (!estado.materias.some((m) => m.id === entrada.materiaId)) {
        throw new ErrorApi(
          400,
          'REFERENCIA_INVALIDA',
          'Se hace referencia a un registro que no existe.',
        );
      }
    }
  };

  const curriculo: PuertaCurriculo = {
    async listarProgramas(opciones) {
      revisar('curriculo.listarProgramas');

      const { tipo, activo, busqueda, limite, desplazamiento } = opciones;
      const aguja = busqueda?.toLowerCase();

      const coincide = (p: Programa): boolean => {
        if (tipo && p.tipo !== tipo) return false;
        if (activo !== undefined && p.activo !== activo) return false;
        if (!aguja) return true;
        return `${p.codigo} ${p.nombre}`.toLowerCase().includes(aguja);
      };

      const filtrados = estado.programas
        .filter(coincide)
        .sort((a, b) => a.nombre.localeCompare(b.nombre) || a.id.localeCompare(b.id))
        .map((programa) => ({
          ...programa,
          totalMaterias: pensumDe(programa.id).length,
          totalPeriodos: new Set(pensumDe(programa.id).map((e) => e.periodo)).size,
        }));

      return {
        programas: filtrados.slice(desplazamiento, desplazamiento + limite),
        total: filtrados.length,
      };
    },

    async detallePrograma(id) {
      revisar('curriculo.detallePrograma');
      const programa = estado.programas.find((p) => p.id === id);
      return programa ? armarDetalle(programa) : null;
    },

    async crearPrograma(entrada) {
      revisar('curriculo.crearPrograma');

      if (estado.programas.some((p) => p.codigo === entrada.codigo)) {
        throw ErrorApi.conflicto('REGISTRO_DUPLICADO', 'Ese registro ya existe.');
      }
      exigirMateriasExistentes(entrada.pensum);

      const ahora = new Date().toISOString();
      const programa: Programa = {
        id: nuevoId('77777777', ++secuenciaProgramas),
        codigo: entrada.codigo,
        nombre: entrada.nombre,
        tipo: entrada.tipo,
        requierePasantia: entrada.requierePasantia,
        activo: entrada.publicar,
        creadoEn: ahora,
        actualizadoEn: ahora,
      };

      estado.programas = [...estado.programas, programa];
      estado.pensum[programa.id] = entrada.pensum.map((e) => ({ ...e }));

      return armarDetalle(programa);
    },

    async actualizarPrograma(id, cambios) {
      revisar('curriculo.actualizarPrograma');

      const actual = estado.programas.find((p) => p.id === id);
      // Mismo código que produce el repositorio real cuando el `update` no
      // toca ninguna fila (PostgREST `PGRST116`). Si el doble usara un código
      // propio, la prueba fijaría un contrato que la API no cumple.
      if (!actual) {
        throw ErrorApi.noEncontrado('NO_ENCONTRADO', 'El recurso solicitado no existe.');
      }

      const actualizado: Programa = {
        ...actual,
        ...(cambios.nombre === undefined ? {} : { nombre: cambios.nombre }),
        ...(cambios.requierePasantia === undefined
          ? {}
          : { requierePasantia: cambios.requierePasantia }),
        ...(cambios.activo === undefined ? {} : { activo: cambios.activo }),
        actualizadoEn: new Date().toISOString(),
      };

      // Regla 1, como el constraint trigger diferido de la base: publicar una
      // CARRERA sin materias es un error del administrativo, no un estado
      // válido. Es el camino que la base atrapa y Zod no puede ver, porque
      // depende del estado de la tabla y no de lo que llega en la petición.
      if (
        actualizado.activo &&
        actualizado.tipo === 'CARRERA' &&
        pensumDe(id).length === 0
      ) {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          'Una carrera activa no puede quedarse sin materias.',
        );
      }

      estado.programas = estado.programas.map((p) => (p.id === id ? actualizado : p));
      return actualizado;
    },

    async reemplazarPensum(id, pensum) {
      revisar('curriculo.reemplazarPensum');

      const programa = estado.programas.find((p) => p.id === id);
      if (!programa) {
        throw ErrorApi.noEncontrado('NO_ENCONTRADO', 'El recurso solicitado no existe.');
      }

      exigirMateriasExistentes(pensum);

      const nuevoPorMateria = new Map(pensum.map((e) => [e.materiaId, e.periodo]));

      // Regla 2, como el trigger de la base: quitar o reordenar una materia es
      // estructural y se bloquea si el programa ya tiene secciones activas del
      // período vigente. **Añadir no**: `create trigger ... before update of
      // period_order, program_id or delete` no mira los insert.
      const estructural = pensumDe(id).some((entrada) => {
        const periodoNuevo = nuevoPorMateria.get(entrada.materiaId);
        return periodoNuevo === undefined || periodoNuevo !== entrada.periodo;
      });

      if (estructural && (estado.seccionesActivas[id] ?? 0) > 0) {
        throw ErrorApi.conflicto(
          'PENSUM_EN_USO',
          'No se puede modificar el pensum: el programa ya tiene secciones activas en el período vigente.',
        );
      }

      estado.pensum[id] = pensum.map((e) => ({ ...e }));
      return armarDetalle(programa);
    },

    async listarMaterias(opciones) {
      revisar('curriculo.listarMaterias');

      const { busqueda, limite, desplazamiento } = opciones;
      const aguja = busqueda?.toLowerCase();

      const filtradas = estado.materias
        .filter((m) => !aguja || `${m.codigo} ${m.nombre}`.toLowerCase().includes(aguja))
        .sort((a, b) => a.nombre.localeCompare(b.nombre) || a.id.localeCompare(b.id));

      return {
        materias: filtradas.slice(desplazamiento, desplazamiento + limite),
        total: filtradas.length,
      };
    },

    async crearMateria(entrada) {
      revisar('curriculo.crearMateria');

      if (estado.materias.some((m) => m.codigo === entrada.codigo)) {
        throw ErrorApi.conflicto('REGISTRO_DUPLICADO', 'Ese registro ya existe.');
      }

      const ahora = new Date().toISOString();
      const materia: Materia = {
        id: nuevoId('88888888', ++secuenciaMaterias),
        codigo: entrada.codigo,
        nombre: entrada.nombre,
        horasAcademicas: entrada.horasAcademicas,
        creadoEn: ahora,
        actualizadoEn: ahora,
      };

      estado.materias = [...estado.materias, materia];
      return materia;
    },
  };

  // --- Módulo 3 ------------------------------------------------------------

  let secuenciaCuadrante = 0;

  /** El período de una clase, derivado de su sección —igual que el trigger—. */
  const periodoDeClase = (clase: ClaseFalsa): string | null =>
    estado.secciones.find((s) => s.id === clase.seccionId)?.periodo ?? null;

  /**
   * Enriquece una clase igual que lo hace `v_cuadrante_clases`.
   *
   * Se resuelve en la lectura y no se guarda, por la misma razón que en la base:
   * el período pertenece a la sección y los nombres a sus tablas. Si el doble
   * guardara la clase ya enriquecida, una prueba podría construir una clase cuyo
   * período contradijera al de su sección —un estado que la base no admite— y el
   * chequeo de colisiones compararía dentro del lapso equivocado.
   */
  const enriquecerClase = (clase: ClaseFalsa): ClaseCuadrante => {
    const seccion = estado.secciones.find((s) => s.id === clase.seccionId);
    if (!seccion) {
      throw ErrorApi.interno(`La clase ${clase.id} apunta a una sección que no existe.`);
    }

    const programa = estado.programas.find((p) => p.id === seccion.programaId);
    const materia = estado.materias.find((m) => m.id === seccion.materiaId);
    const aula = estado.aulas.find((a) => a.id === clase.aulaId);
    const docente = estado.perfiles.find((p) => p.id === clase.docenteId);

    return {
      id: clase.id,
      seccionId: clase.seccionId,
      docenteId: clase.docenteId,
      aulaId: clase.aulaId,
      dia: clase.dia,
      bloque: clase.bloque,
      turno: turnoDeBloque(clase.bloque),
      activa: clase.activa,
      periodo: seccion.periodo,
      programaId: seccion.programaId,
      programa: programa?.nombre ?? '',
      materiaId: seccion.materiaId,
      materia: materia?.nombre ?? '',
      seccion: seccion.nombre,
      aula: aula?.nombre ?? '',
      docente: docente ? `${docente.nombres} ${docente.apellidos}`.trim() : '',
    };
  };

  /**
   * El chequeo anti-colisión, con los **mismos mensajes** que el trigger.
   *
   * Es la parte del doble que más importa: si el doble no comprobara nada, una
   * prueba de «crear una guardia donde ya hay clase» pasaría sin haber
   * ejercitado la regla, y el 409 CHOQUE_DE_AGENDA nunca se probaría. Y los
   * mensajes van copiados literalmente de `202609180001`, porque son justo lo
   * que `esChoqueDeAgenda` reconoce: un mensaje inventado aquí haría que la
   * prueba del traductor pasara sobre un texto que la base nunca produce.
   *
   * `origen` e `id` permiten actualizar una fila sobre su propio hueco sin que se
   * rechace a sí misma, igual que en la función SQL.
   */
  const exigirAgendaLibre = (
    periodo: string,
    dia: number,
    bloque: number,
    docenteId: string,
    aulaId: string,
    origen: 'guardia' | 'clase',
    id: string,
  ): void => {
    const diaTexto = diaLegible(dia);

    const docenteOcupado =
      estado.guardias.some(
        (g) =>
          g.activa &&
          g.periodo === periodo &&
          g.dia === dia &&
          g.bloque === bloque &&
          g.docenteId === docenteId &&
          !(origen === 'guardia' && g.id === id),
      ) ||
      estado.clases.some(
        (c) =>
          c.activa &&
          c.dia === dia &&
          c.bloque === bloque &&
          c.docenteId === docenteId &&
          periodoDeClase(c) === periodo &&
          !(origen === 'clase' && c.id === id),
      );

    if (docenteOcupado) {
      throw ErrorApi.conflicto(
        'CHOQUE_DE_AGENDA',
        `Ese docente ya tiene una clase o guardia asignada el ${diaTexto} en el bloque ` +
          `${bloque}. Un docente no puede estar en dos sitios a la vez.`,
      );
    }

    const aulaOcupada =
      estado.guardias.some(
        (g) =>
          g.activa &&
          g.periodo === periodo &&
          g.dia === dia &&
          g.bloque === bloque &&
          g.aulaId === aulaId &&
          !(origen === 'guardia' && g.id === id),
      ) ||
      estado.clases.some(
        (c) =>
          c.activa &&
          c.dia === dia &&
          c.bloque === bloque &&
          c.aulaId === aulaId &&
          periodoDeClase(c) === periodo &&
          !(origen === 'clase' && c.id === id),
      );

    if (aulaOcupada) {
      throw ErrorApi.conflicto(
        'CHOQUE_DE_AGENDA',
        `Ese espacio ya está ocupado el ${diaTexto} en el bloque ${bloque}. Dos grupos ` +
          'no pueden compartir el mismo sitio a la misma hora.',
      );
    }
  };

  /** Las claves ajenas de una guardia: docente, espacio y lapso tienen que existir. */
  const exigirReferenciasDeGuardia = (
    docenteId: string,
    aulaId: string,
    periodo: string,
  ): void => {
    if (!estado.perfiles.some((p) => p.id === docenteId)) throw referenciaInvalida();
    if (!estado.aulas.some((a) => a.id === aulaId)) throw referenciaInvalida();
    if (!estado.periodos.some((p) => p.codigo === periodo)) throw referenciaInvalida();
  };

  const cuadrante: PuertaCuadrante = {
    async listarAulas(opciones) {
      revisar('cuadrante.listarAulas');

      const { busqueda, tipo, activa, limite, desplazamiento } = opciones;
      const aguja = busqueda?.toLowerCase();

      const coincide = (a: Aula): boolean => {
        // Las tres formas son excluyentes y cubren todos los casos, igual que en
        // el repositorio real: una zona tiene cupo 0 y no es taller, un aula
        // tiene cupo y no es taller, y un taller lo es con el cupo que sea.
        if (tipo === 'TALLER' && !a.esTaller) return false;
        if (tipo === 'ZONA' && (a.esTaller || a.capacidad !== 0)) return false;
        if (tipo === 'AULA' && (a.esTaller || a.capacidad <= 0)) return false;
        if (activa !== undefined && a.activa !== activa) return false;
        if (aguja && !a.nombre.toLowerCase().includes(aguja)) return false;
        return true;
      };

      const filtradas = estado.aulas
        .filter(coincide)
        .sort((a, b) => a.nombre.localeCompare(b.nombre) || a.id.localeCompare(b.id));

      return {
        aulas: filtradas.slice(desplazamiento, desplazamiento + limite),
        total: filtradas.length,
      };
    },

    async crearAula(entrada) {
      revisar('cuadrante.crearAula');

      if (estado.aulas.some((a) => a.nombre === entrada.nombre)) {
        throw ErrorApi.conflicto('REGISTRO_DUPLICADO', 'Ese registro ya existe.');
      }

      const ahora = new Date().toISOString();
      const aula: Aula = {
        id: nuevoId('99999999', ++secuenciaCuadrante),
        nombre: entrada.nombre,
        capacidad: entrada.capacidad,
        esTaller: entrada.esTaller,
        activa: true,
        creadoEn: ahora,
        actualizadoEn: ahora,
      };

      estado.aulas = [...estado.aulas, aula];
      return aula;
    },

    async actualizarAula(id, cambios) {
      revisar('cuadrante.actualizarAula');

      const actual = estado.aulas.find((a) => a.id === id);
      if (!actual) {
        throw ErrorApi.noEncontrado('AULA_INEXISTENTE', 'Ese espacio no existe.');
      }

      if (
        cambios.nombre !== undefined &&
        estado.aulas.some((a) => a.id !== id && a.nombre === cambios.nombre)
      ) {
        throw ErrorApi.conflicto('REGISTRO_DUPLICADO', 'Ese registro ya existe.');
      }

      const actualizada: Aula = {
        ...actual,
        ...soloDefinidos(cambios),
        actualizadoEn: new Date().toISOString(),
      };

      estado.aulas = estado.aulas.map((a) => (a.id === id ? actualizada : a));
      return actualizada;
    },

    async listarPeriodos() {
      revisar('cuadrante.listarPeriodos');

      // `vigente` se recalcula en cada lectura, como en el repositorio real: no
      // es una columna y guardarlo permitiría un estado que la base no produce.
      return estado.periodos
        .map((periodo) => ({
          ...periodo,
          vigente: periodo.codigo === estado.periodoCodigoVigente,
        }))
        .sort((a, b) => b.codigo.localeCompare(a.codigo));
    },

    async crearPeriodo(entrada) {
      revisar('cuadrante.crearPeriodo');

      if (estado.periodos.some((p) => p.codigo === entrada.codigo)) {
        throw ErrorApi.conflicto('REGISTRO_DUPLICADO', 'Ese registro ya existe.');
      }

      const ahora = new Date().toISOString();
      const periodo: Periodo = {
        id: nuevoId('99999998', ++secuenciaCuadrante),
        codigo: entrada.codigo,
        nombre: entrada.nombre,
        fechaInicio: entrada.fechaInicio,
        fechaFin: entrada.fechaFin,
        // Nace cerrado y no vigente: es el `default false` de la columna, y el
        // trigger `exigir_periodo_registrado` garantiza que el vigente ya existe,
        // así que un lapso nuevo no puede serlo.
        activo: false,
        vigente: false,
        creadoEn: ahora,
        actualizadoEn: ahora,
      };

      estado.periodos = [...estado.periodos, periodo];
      return periodo;
    },

    async actualizarPeriodo(id, cambios) {
      revisar('cuadrante.actualizarPeriodo');

      const actual = estado.periodos.find((p) => p.id === id);
      if (!actual) {
        throw ErrorApi.noEncontrado('PERIODO_INEXISTENTE', 'Ese lapso no existe.');
      }

      const actualizado: Periodo = {
        ...actual,
        ...soloDefinidos(cambios),
        actualizadoEn: new Date().toISOString(),
      };
      actualizado.vigente = actualizado.codigo === estado.periodoCodigoVigente;

      estado.periodos = estado.periodos.map((p) => (p.id === id ? actualizado : p));
      return actualizado;
    },

    async declararPeriodoVigente(id) {
      revisar('cuadrante.declararPeriodoVigente');

      const periodo = estado.periodos.find((p) => p.id === id);
      if (!periodo) {
        throw ErrorApi.noEncontrado('PERIODO_INEXISTENTE', 'Ese lapso no existe.');
      }

      estado.periodoCodigoVigente = periodo.codigo;
      return { ...periodo, vigente: true };
    },

    async listarGuardias(opciones) {
      revisar('cuadrante.listarGuardias');

      const { periodo, docenteId, aulaId, dia, bloque, activa, limite, desplazamiento } =
        opciones;

      const filtradas = estado.guardias
        .filter((g) => {
          if (periodo && g.periodo !== periodo) return false;
          if (docenteId && g.docenteId !== docenteId) return false;
          if (aulaId && g.aulaId !== aulaId) return false;
          if (dia !== undefined && g.dia !== dia) return false;
          if (bloque !== undefined && g.bloque !== bloque) return false;
          if (activa !== undefined && g.activa !== activa) return false;
          return true;
        })
        .sort(
          (a, b) =>
            a.periodo.localeCompare(b.periodo) ||
            a.dia - b.dia ||
            a.bloque - b.bloque ||
            a.id.localeCompare(b.id),
        );

      return {
        guardias: filtradas.slice(desplazamiento, desplazamiento + limite),
        total: filtradas.length,
      };
    },

    async crearGuardia(entrada) {
      revisar('cuadrante.crearGuardia');

      exigirReferenciasDeGuardia(entrada.docenteId, entrada.aulaId, entrada.periodo);

      const id = nuevoId('99999997', ++secuenciaCuadrante);
      exigirAgendaLibre(
        entrada.periodo,
        entrada.dia,
        entrada.bloque,
        entrada.docenteId,
        entrada.aulaId,
        'guardia',
        id,
      );

      const ahora = new Date().toISOString();
      const guardia: Guardia = {
        id,
        docenteId: entrada.docenteId,
        aulaId: entrada.aulaId,
        periodo: entrada.periodo,
        dia: entrada.dia,
        bloque: entrada.bloque,
        turno: turnoDeBloque(entrada.bloque),
        notas: entrada.notas,
        activa: true,
        creadoEn: ahora,
        actualizadoEn: ahora,
      };

      estado.guardias = [...estado.guardias, guardia];
      return guardia;
    },

    async actualizarGuardia(id, cambios) {
      revisar('cuadrante.actualizarGuardia');

      const actual = estado.guardias.find((g) => g.id === id);
      if (!actual) {
        throw ErrorApi.noEncontrado('GUARDIA_INEXISTENTE', 'Esa guardia no existe.');
      }

      const actualizada: Guardia = {
        ...actual,
        ...soloDefinidos(cambios),
        actualizadoEn: new Date().toISOString(),
      };
      actualizada.turno = turnoDeBloque(actualizada.bloque);

      exigirReferenciasDeGuardia(
        actualizada.docenteId,
        actualizada.aulaId,
        actualizada.periodo,
      );

      // La salida temprana del trigger: una guardia archivada no ocupa a nadie.
      // Sin ella, desactivar una guardia seguiría bloqueando el hueco que ya no
      // usa, y la prueba de archivar pasaría por el motivo equivocado.
      if (actualizada.activa) {
        exigirAgendaLibre(
          actualizada.periodo,
          actualizada.dia,
          actualizada.bloque,
          actualizada.docenteId,
          actualizada.aulaId,
          'guardia',
          id,
        );
      }

      estado.guardias = estado.guardias.map((g) => (g.id === id ? actualizada : g));
      return actualizada;
    },

    async rejilla(opciones) {
      revisar('cuadrante.rejilla');

      const periodo = opciones.periodo ?? estado.periodoCodigoVigente;

      // Aulas y docentes no dependen del lapso, así que se devuelven siempre,
      // también cuando no hay ninguno vigente: la pantalla puede mostrar el
      // catálogo y decir «no hay lapso vigente» en vez de quedarse en blanco.
      const aulas = [...estado.aulas].sort(
        (a, b) =>
          Number(b.activa) - Number(a.activa) ||
          a.nombre.localeCompare(b.nombre) ||
          a.id.localeCompare(b.id),
      );

      const docentes = estado.perfiles
        .filter((p) => (p.rol === 'docente' || p.rol === 'admin') && p.activo)
        .map((p) => ({ id: p.id, nombre: `${p.nombres} ${p.apellidos}`.trim() }))
        .sort((a, b) => a.nombre.localeCompare(b.nombre) || a.id.localeCompare(b.id));

      if (!periodo) {
        return { periodo: null, clases: [], guardias: [], aulas, docentes };
      }

      const clases = estado.clases
        .filter((c) => periodoDeClase(c) === periodo)
        .filter((c) => opciones.incluirInactivas || c.activa)
        .filter((c) => !opciones.seccionId || c.seccionId === opciones.seccionId)
        .filter((c) => !opciones.docenteId || c.docenteId === opciones.docenteId)
        .filter((c) => !opciones.aulaId || c.aulaId === opciones.aulaId)
        .map(enriquecerClase)
        .sort(porDiaBloque);

      // `seccionId` no filtra las guardias: una guardia no pertenece a ninguna
      // sección, y dejaría fuera guardias que sí ocupan el mismo hueco.
      const guardias = estado.guardias
        .filter((g) => g.periodo === periodo)
        .filter((g) => opciones.incluirInactivas || g.activa)
        .filter((g) => !opciones.docenteId || g.docenteId === opciones.docenteId)
        .filter((g) => !opciones.aulaId || g.aulaId === opciones.aulaId)
        .sort(porDiaBloque);

      return { periodo, clases, guardias, aulas, docentes };
    },

    async crearClase(entrada) {
      revisar('cuadrante.crearClase');

      const seccion = estado.secciones.find((s) => s.id === entrada.seccionId);
      if (!seccion) throw referenciaInvalida();
      if (!estado.perfiles.some((p) => p.id === entrada.docenteId)) throw referenciaInvalida();
      if (!estado.aulas.some((a) => a.id === entrada.aulaId)) throw referenciaInvalida();

      const id = nuevoId('99999996', ++secuenciaCuadrante);

      // El período sale de la sección, no de la petición: es lo que hace que el
      // chequeo compare dentro de un lapso y no entre lapsos.
      exigirAgendaLibre(
        seccion.periodo,
        entrada.dia,
        entrada.bloque,
        entrada.docenteId,
        entrada.aulaId,
        'clase',
        id,
      );

      const clase: ClaseFalsa = {
        id,
        seccionId: entrada.seccionId,
        docenteId: entrada.docenteId,
        aulaId: entrada.aulaId,
        dia: entrada.dia,
        bloque: entrada.bloque,
        activa: true,
      };

      estado.clases = [...estado.clases, clase];
      return enriquecerClase(clase);
    },

    async actualizarClase(id, cambios) {
      revisar('cuadrante.actualizarClase');

      const actual = estado.clases.find((c) => c.id === id);
      if (!actual) {
        throw ErrorApi.noEncontrado('CLASE_INEXISTENTE', 'Esa clase no existe en el cuadrante.');
      }

      const actualizada: ClaseFalsa = { ...actual, ...soloDefinidos(cambios) };

      const seccion = estado.secciones.find((s) => s.id === actualizada.seccionId);
      if (!seccion) throw referenciaInvalida();
      if (!estado.perfiles.some((p) => p.id === actualizada.docenteId)) throw referenciaInvalida();
      if (!estado.aulas.some((a) => a.id === actualizada.aulaId)) throw referenciaInvalida();

      if (actualizada.activa) {
        exigirAgendaLibre(
          seccion.periodo,
          actualizada.dia,
          actualizada.bloque,
          actualizada.docenteId,
          actualizada.aulaId,
          'clase',
          id,
        );
      }

      estado.clases = estado.clases.map((c) => (c.id === id ? actualizada : c));
      return enriquecerClase(actualizada);
    },

    async miHorario(rol, usuarioId, periodo) {
      revisar('cuadrante.miHorario');

      const lapso = periodo ?? estado.periodoCodigoVigente;
      if (!lapso) return { rol, periodo: null, clases: [], guardias: [] };

      const seccionesPropias =
        rol === 'estudiante'
          ? estado.inscripciones
              .filter((i) => i.estudianteId === usuarioId)
              .map((i) => i.seccionId)
          : [];

      const clases = estado.clases
        .filter((c) => periodoDeClase(c) === lapso)
        .filter((c) =>
          rol === 'docente' ? c.docenteId === usuarioId : seccionesPropias.includes(c.seccionId),
        )
        .map(enriquecerClase)
        .sort(porDiaBloque);

      if (rol === 'estudiante') return { rol, periodo: lapso, clases, guardias: [] };

      const guardias = estado.guardias
        .filter((g) => g.periodo === lapso && g.docenteId === usuarioId)
        .sort(porDiaBloque);

      return { rol, periodo: lapso, clases, guardias };
    },
  };

  // --- M4: secciones e inscripciones ----------------------------------------

  let secuenciaSeccion = 3000;
  let secuenciaInscripcion = 4000;

  /** El parámetro global de cupo, con el mismo `coalesce(..., 0)` que la base. */
  const cupoGlobal = (): number => {
    const encontrado = estado.parametros.find((p) => p.clave === 'cupo_maximo_por_seccion');
    return typeof encontrado?.valor === 'number' ? encontrado.valor : 0;
  };

  /**
   * Cupo efectivo de una sección.
   *
   * Es la traducción de `cupo_efectivo()`: `max_capacity` manda, y **sólo `null`
   * cae al global**. Un `0` es una sección sin cupo y se respeta como tal; tratarlo
   * como «sin definir» haría que la prueba del cupo global pasara por el motivo
   * equivocado.
   */
  const cupoEfectivo = (seccion: SeccionFalsa): number =>
    seccion.cupoMaximo === null || seccion.cupoMaximo === undefined
      ? cupoGlobal()
      : seccion.cupoMaximo;

  const estadoDe = (fila: InscripcionFalsa): EstadoInscripcion => fila.estado ?? 'ENROLLED';

  /** Orden de llegada: el ordinal declarado, o la posición en el arreglo. */
  const llegada = (fila: InscripcionFalsa): number =>
    fila.llegada ?? estado.inscripciones.indexOf(fila);

  const inscripcionesDe = (seccionId: string): InscripcionFalsa[] =>
    estado.inscripciones
      .filter((i) => i.seccionId === seccionId)
      .sort((a, b) => llegada(a) - llegada(b));

  /**
   * Asientos ocupados: **sólo `ENROLLED`**.
   *
   * Es la regla institucional, y es exactamente lo que introduce la doble venta
   * que `hayOfertaVigente` viene a cerrar. Si el doble contara `PENDING_BID` como
   * ocupado, la prueba de la doble venta pasaría sin ejercitar el camino real.
   */
  const ocupadosDe = (seccionId: string): number =>
    inscripcionesDe(seccionId).filter((i) => estadoDe(i) === 'ENROLLED').length;

  /**
   * ¿Hay una oferta de cupo viva?
   *
   * Es el espejo de `existe_oferta_vigente()`, y usa **la función pura real**
   * `ofertaVencida` en vez de reimplementar la comparación: un doble que decidiera
   * a su manera podría pasar una prueba que el código de producción no pasaría.
   */
  const hayOfertaVigente = (seccionId: string, ahora: Date): boolean =>
    inscripcionesDe(seccionId).some(
      (i) => estadoDe(i) === 'PENDING_BID' && !ofertaVencida(i.ofertaVenceEn ?? null, ahora),
    );

  const aSeccionFalsa = (fila: SeccionFalsa): Seccion => ({
    id: fila.id,
    programaId: fila.programaId,
    materiaId: fila.materiaId,
    periodo: fila.periodo,
    nombre: fila.nombre,
    cupoMaximo: fila.cupoMaximo ?? null,
    activa: fila.activa ?? true,
    creadoEn: new Date(0).toISOString(),
    actualizadoEn: new Date(0).toISOString(),
  });

  const aOcupacionFalsa = (fila: SeccionFalsa, ahora: Date): OcupacionSeccion => {
    const efectivo = cupoEfectivo(fila);
    const ocupados = ocupadosDe(fila.id);
    return {
      seccionId: fila.id,
      periodo: fila.periodo,
      programaId: fila.programaId,
      programaNombre: estado.programas.find((p) => p.id === fila.programaId)?.nombre ?? null,
      materiaId: fila.materiaId,
      materiaNombre: estado.materias.find((m) => m.id === fila.materiaId)?.nombre ?? null,
      nombre: fila.nombre,
      activa: fila.activa ?? true,
      cupoEfectivo: efectivo,
      cuposOcupados: ocupados,
      cuposDisponibles: Math.max(efectivo - ocupados, 0),
      ofertaVigente: hayOfertaVigente(fila.id, ahora),
    };
  };

  const aInscripcionDetallada = (
    fila: InscripcionFalsa,
    conEstudiante: boolean,
  ): InscripcionDetallada => {
    const seccion = estado.secciones.find((s) => s.id === fila.seccionId);
    const perfil = estado.perfiles.find((p) => p.id === fila.estudianteId);
    const enCola = inscripcionesDe(fila.seccionId).filter((i) => estadoDe(i) === 'WAITLISTED');
    const posicion = enCola.findIndex((i) => i === fila) + 1;

    return {
      id: fila.id ?? `inscripcion-${llegada(fila)}`,
      estudianteId: fila.estudianteId,
      seccionId: fila.seccionId,
      estado: estadoDe(fila),
      ofertaVenceEn: fila.ofertaVenceEn ?? null,
      creadoEn: new Date(0).toISOString(),
      actualizadoEn: new Date(0).toISOString(),
      periodo: seccion?.periodo ?? '',
      seccionNombre: seccion?.nombre ?? '',
      materiaId: seccion?.materiaId ?? '',
      materiaNombre: estado.materias.find((m) => m.id === seccion?.materiaId)?.nombre ?? null,
      programaId: seccion?.programaId ?? '',
      programaNombre: estado.programas.find((p) => p.id === seccion?.programaId)?.nombre ?? null,
      // Sólo quien espera ocupa un turno de la cola.
      posicionEnCola: estadoDe(fila) === 'WAITLISTED' && posicion > 0 ? posicion : null,
      ...(conEstudiante
        ? {
            estudianteNombre: perfil
              ? [perfil.nombres, perfil.apellidos].filter((p) => p.length > 0).join(' ')
              : null,
            estudianteEmail: perfil?.email ?? null,
          }
        : {}),
    };
  };

  const secciones: PuertaSecciones = {
    async listar(opciones) {
      revisar('secciones.listar');

      const aguja = opciones.busqueda?.toLowerCase();
      const filtradas = estado.secciones.filter((s) => {
        if (opciones.periodo && s.periodo !== opciones.periodo) return false;
        if (opciones.programaId && s.programaId !== opciones.programaId) return false;
        if (opciones.materiaId && s.materiaId !== opciones.materiaId) return false;
        if (opciones.activa !== undefined && (s.activa ?? true) !== opciones.activa) return false;
        if (aguja && !s.nombre.toLowerCase().includes(aguja)) return false;
        return true;
      });

      return {
        secciones: filtradas
          .slice(opciones.desplazamiento, opciones.desplazamiento + opciones.limite)
          .map(aSeccionFalsa),
        total: filtradas.length,
      };
    },

    async crear(entrada) {
      revisar('secciones.crear');

      if (!estado.programas.some((p) => p.id === entrada.programaId)) {
        throw referenciaInvalida();
      }
      if (!estado.materias.some((m) => m.id === entrada.materiaId)) {
        throw referenciaInvalida();
      }
      if (!estado.periodos.some((p) => p.codigo === entrada.periodo)) {
        throw referenciaInvalida();
      }

      // `unique (period_code, subject_id, name)`.
      const repetida = estado.secciones.some(
        (s) =>
          s.periodo === entrada.periodo &&
          s.materiaId === entrada.materiaId &&
          s.nombre === entrada.nombre,
      );
      if (repetida) {
        throw new ErrorApi(409, 'REGISTRO_DUPLICADO', 'Ese registro ya existe.', {
          contexto: 'crear sección',
        });
      }

      const nueva: SeccionFalsa = {
        // `nuevoId` arma el UUID completo (`<prefijo>-0000-4000-8000-<12>`), así
        // que el prefijo son los 8 primeros dígitos y nada más: pasarle un
        // `cccccccc-9000` produciría una cadena de 41 caracteres que no es un UUID.
        id: nuevoId('cccccccc', ++secuenciaSeccion),
        programaId: entrada.programaId,
        materiaId: entrada.materiaId,
        periodo: entrada.periodo,
        nombre: entrada.nombre,
        cupoMaximo: entrada.cupoMaximo,
        activa: true,
      };

      estado.secciones = [...estado.secciones, nueva];
      return aSeccionFalsa(nueva);
    },

    async actualizar(id, cambios) {
      revisar('secciones.actualizar');

      const actual = estado.secciones.find((s) => s.id === id);
      if (!actual) {
        throw ErrorApi.noEncontrado('SECCION_INEXISTENTE', 'Esa sección no existe.');
      }

      if (cambios.nombre !== undefined) actual.nombre = cambios.nombre;
      // `null` explícito es un cambio legítimo —volver al cupo global—, así que se
      // comprueba contra `undefined` y no por veracidad.
      if (cambios.cupoMaximo !== undefined) actual.cupoMaximo = cambios.cupoMaximo;
      if (cambios.activa !== undefined) actual.activa = cambios.activa;

      return aSeccionFalsa(actual);
    },
  };

  const inscripciones: PuertaInscripciones = {
    async listarOfertas(opciones) {
      revisar('inscripciones.listarOfertas');
      return listarOcupacionCon(opciones, true);
    },

    async listarOcupacion(opciones) {
      revisar('inscripciones.listarOcupacion');
      return listarOcupacionCon(opciones, false);
    },

    async misInscripciones(estudianteId) {
      revisar('inscripciones.misInscripciones');
      return estado.inscripciones
        .filter((i) => i.estudianteId === estudianteId)
        .map((i) => aInscripcionDetallada(i, false));
    },

    async solicitar(seccionId) {
      revisar('inscripciones.solicitar');
      return inscribir(seccionId);
    },

    async aceptar(seccionId) {
      revisar('inscripciones.aceptar');

      const actor = usuarioActual();
      const fila = estado.inscripciones.find(
        (i) => i.seccionId === seccionId && i.estudianteId === actor,
      );

      if (!fila || estadoDe(fila) !== 'PENDING_BID') {
        throw new ErrorApi(400, 'RESTRICCION_VIOLADA', 'No tienes una oferta de cupo pendiente para la sección.', {
          contexto: 'aceptar un cupo',
        });
      }

      if (ofertaVencida(fila.ofertaVenceEn ?? null, new Date())) {
        throw new ErrorApi(410, 'OFERTA_VENCIDA', 'La oferta de cupo para la sección ya venció.');
      }

      fila.estado = 'ENROLLED';
      fila.ofertaVenceEn = null;
      return 'ENROLLED';
    },

    async renunciar(seccionId) {
      revisar('inscripciones.renunciar');

      const actor = usuarioActual();
      const fila = estado.inscripciones.find(
        (i) => i.seccionId === seccionId && i.estudianteId === actor,
      );

      if (!fila) {
        throw new ErrorApi(400, 'RESTRICCION_VIOLADA', 'No tienes ninguna inscripción en la sección.', {
          contexto: 'renunciar a un cupo',
        });
      }

      fila.estado = 'DROPPED';
      fila.ofertaVenceEn = null;

      // Renunciar libera un asiento: se promueve al siguiente de la cola.
      promoverEn(seccionId);
      return 'DROPPED';
    },

    async colaDeSeccion(seccionId) {
      revisar('inscripciones.colaDeSeccion');
      return inscripcionesDe(seccionId)
        .filter((i) => estadoDe(i) === 'WAITLISTED')
        .map((i) => aInscripcionDetallada(i, true));
    },

    async inscritosDeSeccion(seccionId) {
      revisar('inscripciones.inscritosDeSeccion');
      return inscripcionesDe(seccionId).map((i) => aInscripcionDetallada(i, true));
    },

    async promover(seccionId) {
      revisar('inscripciones.promover');

      const promovida = promoverEn(seccionId);
      // `null` no es un error: significa que no había nadie a quien promover.
      if (!promovida) return null;

      return {
        id: promovida.id ?? `inscripcion-${llegada(promovida)}`,
        estudianteId: promovida.estudianteId,
        seccionId: promovida.seccionId,
        estado: estadoDe(promovida),
        ofertaVenceEn: promovida.ofertaVenceEn ?? null,
        creadoEn: new Date(0).toISOString(),
        actualizadoEn: new Date(0).toISOString(),
      };
    },

    async reincorporar(estudianteId, seccionId) {
      revisar('inscripciones.reincorporar');

      const fila = estado.inscripciones.find(
        (i) => i.seccionId === seccionId && i.estudianteId === estudianteId,
      );

      if (!fila) {
        throw new ErrorApi(
          404,
          'SIN_HISTORIAL_EN_SECCION',
          'No existe una inscripción previa del estudiante en la sección.',
        );
      }

      if (estadoDe(fila) !== 'DROPPED') {
        throw new ErrorApi(400, 'RESTRICCION_VIOLADA', 'La inscripción del estudiante no está dada de baja.');
      }

      // **Sin comprobación de cupo A PROPÓSITO**: el administrador puede exceder
      // la capacidad. Si el doble la comprobara, la prueba de la regla
      // institucional pasaría sin ejercitar la decisión real.
      fila.estado = 'ENROLLED';
      fila.ofertaVenceEn = null;
      return 'ENROLLED';
    },

    async expirarOfertas() {
      revisar('inscripciones.expirarOfertas');

      const ahora = new Date();
      let vencidas = 0;

      for (const fila of estado.inscripciones) {
        if (estadoDe(fila) !== 'PENDING_BID') continue;
        if (!ofertaVencida(fila.ofertaVenceEn ?? null, ahora)) continue;

        fila.estado = 'DROPPED';
        fila.ofertaVenceEn = null;
        vencidas += 1;
        promoverEn(fila.seccionId);
      }

      return vencidas;
    },
  };

  /** Filtra y pagina la ocupación, con el mismo contrato que el repositorio real. */
  function listarOcupacionCon(
    opciones: { periodo?: string; programaId?: string; materiaId?: string; soloConCupo?: boolean; busqueda?: string; limite: number; desplazamiento: number },
    soloActivas: boolean,
  ): { secciones: OcupacionSeccion[]; total: number } {
    const ahora = new Date();
    const aguja = opciones.busqueda?.toLowerCase();

    let filtradas = estado.secciones.filter((s) => {
      if (soloActivas && !(s.activa ?? true)) return false;
      if (opciones.periodo && s.periodo !== opciones.periodo) return false;
      if (opciones.programaId && s.programaId !== opciones.programaId) return false;
      if (opciones.materiaId && s.materiaId !== opciones.materiaId) return false;
      if (aguja && !s.nombre.toLowerCase().includes(aguja)) return false;
      return true;
    });

    if (opciones.soloConCupo) {
      // El asiento ofrecible no es la resta del contador: con una oferta en el
      // aire el contador dice que hay hueco y el asiento está comprometido.
      filtradas = filtradas.filter((s) => {
        const efectivo = cupoEfectivo(s);
        return ocupadosDe(s.id) < efectivo && !hayOfertaVigente(s.id, ahora);
      });
    }

    return {
      secciones: filtradas
        .slice(opciones.desplazamiento, opciones.desplazamiento + opciones.limite)
        .map((s) => aOcupacionFalsa(s, ahora)),
      total: filtradas.length,
    };
  }

  /**
   * Inscribe al llamante, replicando la condición completa de
   * `solicitar_inscripcion` **incluida la guarda de oferta viva**.
   */
  function inscribir(seccionId: string): EstadoInscripcion {
    const actor = usuarioActual();
    const seccion = estado.secciones.find((s) => s.id === seccionId);

    if (!seccion) {
      throw new ErrorApi(404, 'SECCION_INEXISTENTE', 'La sección no existe.');
    }
    if (!(seccion.activa ?? true)) {
      throw new ErrorApi(409, 'SECCION_ARCHIVADA', 'La sección está archivada y no admite inscripciones.');
    }

    const previa = estado.inscripciones.find(
      (i) => i.seccionId === seccionId && i.estudianteId === actor,
    );

    if (previa) {
      if (estadoDe(previa) === 'DROPPED') {
        throw new ErrorApi(
          409,
          'REQUIERE_REINCORPORACION',
          'Ya cursaste la sección: un administrador debe reincorporarte explícitamente.',
        );
      }
      throw new ErrorApi(
        409,
        'SOLICITUD_YA_EXISTE',
        `Ya tienes una solicitud activa (${estadoDe(previa)}) para la sección.`,
      );
    }

    // Anti-acaparamiento: no dos secciones vivas de la misma materia en el lapso.
    const acapara = estado.inscripciones.some((i) => {
      if (i.estudianteId !== actor) return false;
      if (estadoDe(i) === 'DROPPED') return false;
      const otra = estado.secciones.find((s) => s.id === i.seccionId);
      return (
        otra !== undefined &&
        otra.materiaId === seccion.materiaId &&
        otra.periodo === seccion.periodo
      );
    });

    if (acapara) {
      throw new ErrorApi(
        409,
        'ACAPARAMIENTO_DE_MATERIA',
        'El estudiante ya tiene una sección de la materia en el lapso.',
      );
    }

    const ahora = new Date();
    const cabe = ocupadosDe(seccionId) < cupoEfectivo(seccion);
    const ofertaEnAire = hayOfertaVigente(seccionId, ahora);

    // La conjunción completa. Sin `!ofertaEnAire` se vendería dos veces el mismo
    // asiento: es la regla que la prueba de la doble venta ejercita.
    const estadoFinal: EstadoInscripcion = cabe && !ofertaEnAire ? 'ENROLLED' : 'WAITLISTED';

    estado.inscripciones = [
      ...estado.inscripciones,
      {
        id: nuevoId('ffffffff', ++secuenciaInscripcion),
        estudianteId: actor,
        seccionId,
        estado: estadoFinal,
        ofertaVenceEn: null,
        llegada: estado.inscripciones.length + 1,
      },
    ];

    return estadoFinal;
  }

  /**
   * Promueve al primero de la cola, con las dos condiciones de
   * `promover_siguiente_de_cola`: hay hueco **y** no hay oferta viva.
   *
   * Devuelve la fila promovida, o `null` si no había a quién.
   */
  function promoverEn(seccionId: string): InscripcionFalsa | null {
    const seccion = estado.secciones.find((s) => s.id === seccionId);
    if (!seccion) return null;

    const ahora = new Date();
    if (hayOfertaVigente(seccionId, ahora)) return null;
    if (ocupadosDe(seccionId) >= cupoEfectivo(seccion)) return null;

    const siguiente = estado.inscripciones
      .filter((i) => i.seccionId === seccionId && estadoDe(i) === 'WAITLISTED')
      .sort((a, b) => llegada(a) - llegada(b))[0];

    if (!siguiente) return null;

    const conBids = estado.parametros.find((p) => p.clave === 'habilitar_sistema_bids');
    const ttl = estado.parametros.find((p) => p.clave === 'bid_ttl_horas');

    if (conBids?.valor === true) {
      siguiente.estado = 'PENDING_BID';
      const horas = typeof ttl?.valor === 'number' ? ttl.valor : 24;
      siguiente.ofertaVenceEn = new Date(Date.now() + horas * 3_600_000).toISOString();
    } else {
      // Con los bids apagados el primero de la cola pasa directo a ENROLLED.
      siguiente.estado = 'ENROLLED';
      siguiente.ofertaVenceEn = null;
    }

    return siguiente;
  }

  /**
   * El id del llamante, leído de la última petición autenticada.
   *
   * El doble no tiene sesión propia: `reposDePeticion` devuelve siempre el mismo
   * objeto, así que el actor se resuelve desde `estado.usuarioActual`, que el
   * arnés fija por petición. Es el precio de montar la API entera en memoria y es
   * preferible a fingir un cliente de Supabase con JWT.
   */
  function usuarioActual(): string {
    return estado.usuarioActual ?? ID_ALUMNO;
  }

  /** ¿El llamante es administrador? */
  function esAdmin(): boolean {
    const actor = estado.usuarioActual;
    if (actor === null) return false;
    return estado.perfiles.find((p) => p.id === actor)?.rol === 'admin';
  }

  /**
   * Las filas de `files_metadata` que el llamante **puede ver**.
   *
   * Reproduce la política de lectura: el propietario ve lo suyo y el admin lo ve
   * todo. **Esto no prueba la RLS** —la aplica Postgres y sólo se comprueba
   * contra la nube (lección R-23)—; lo que prueba es que la ruta traduce bien el
   * `null` que deja una fila invisible, que es lo que sí vive en este código.
   */
  function archivosVisibles(): ArchivoFalso[] {
    const actor = estado.usuarioActual;
    if (actor === null) return [];
    if (esAdmin()) return estado.archivos;
    return estado.archivos.filter((archivo) => archivo.propietarioId === actor);
  }

  /**
   * Fecha fija de creación.
   *
   * El doble no lee el reloj: una marca de tiempo real haría que dos ejecuciones
   * produjeran respuestas distintas y una prueba que comparara el objeto completo
   * pasaría o fallaría al azar.
   */
  const CREADO_EN_FALSO = '2026-09-18T12:00:00.000Z';

  let contadorArchivos = 0;

  /**
   * Un id de archivo nuevo, determinista.
   *
   * Determinista y no aleatorio para que un fallo se pueda reproducir: la ruta
   * devuelve este id al firmar y la prueba lo reutiliza para confirmar. Con
   * `randomUUID` el id cambiaría en cada ejecución y el fallo no se podría volver
   * a provocar igual.
   *
   * El bloque `1111-4111-8111` lo separa del id sembrado en `ARCHIVOS_POR_DEFECTO`
   * (`0000-4000-8000`). Sin esa separación el primer archivo creado chocaría con
   * el de la semilla y `porId` devolvería el equivocado. Los dos son UUID válidos,
   * así que atraviesan el esquema de ruta sin problemas.
   */
  function idDeArchivoNuevo(): string {
    contadorArchivos += 1;
    return `a1b2c3d4-1111-4111-8111-${String(contadorArchivos).padStart(12, '0')}`;
  }

  function archivoInexistente(id: string): ErrorApi {
    return ErrorApi.noEncontrado('ARCHIVO_INEXISTENTE', `El archivo ${id} no existe.`);
  }

  /** Un archivo en memoria, en la forma que devuelve el repositorio. */
  function aArchivoFalso(fila: ArchivoFalso): ArchivoMetadata {
    const id = fila.id;

    if (id === undefined) {
      // Sólo alcanzable con una semilla mal escrita: el doble siempre crea con
      // id. Fallar aquí evita devolver un `undefined` que reventaría mucho más
      // lejos, al construir la clave de un objeto.
      throw ErrorApi.interno('El arnés tiene un archivo sin id.');
    }

    return {
      id,
      propietarioId: fila.propietarioId,
      r2Key: fila.r2Key,
      nombreOriginal: fila.nombreOriginal,
      tipoContenido:
        fila.tipoContenido ?? tipoContenidoDe(extensionDe(fila.nombreOriginal)),
      tamanoBytes: fila.tamanoBytes ?? null,
      entityType: fila.entityType ?? 'TASK_SUBMISSION',
      entidadId: fila.entidadId ?? null,
      estado: fila.estado ?? 'PENDING',
      creadoEn: fila.creadoEn ?? CREADO_EN_FALSO,
      confirmadoEn: fila.confirmadoEn ?? null,
      borradoEn: fila.borradoEn ?? null,
    };
  }

  /**
   * Los archivos, en memoria.
   *
   * Las escrituras reproducen las tres RPC y, sobre todo, **cómo fallan**: de eso
   * depende el código de estado que ve el usuario. La RPC de borrado distingue
   * «no es tuyo» (403) de «no existe» (404), y esa distinción no la puede inventar
   * la ruta —tiene que venir del puerto—, así que el doble la produce.
   */
  const archivos: PuertaArchivos = {
    async registrarPendiente(
      entrada: EntradaRegistrarArchivo,
    ): Promise<ArchivoMetadata> {
      revisar('archivos.registrarPendiente');

      const fila: ArchivoFalso = {
        id: idDeArchivoNuevo(),
        propietarioId: entrada.propietarioId,
        r2Key: entrada.r2Key,
        nombreOriginal: entrada.nombreOriginal,
        tipoContenido: entrada.tipoContenido,
        tamanoBytes: null,
        entityType: entrada.entityType,
        entidadId: entrada.entidadId,
        estado: 'PENDING',
        creadoEn: CREADO_EN_FALSO,
      };

      estado.archivos.push(fila);

      return aArchivoFalso(fila);
    },

    async confirmar(id: string, tamanoBytes: number): Promise<ArchivoMetadata> {
      revisar('archivos.confirmar');

      // Se busca entre **todas** las filas y no entre las visibles, porque la RPC
      // es `security definer`: decide por `auth.uid()` y falla con 403 si el
      // archivo es de otro. Buscar sólo entre las visibles confundiría «es de
      // otro» con «no existe».
      const fila = estado.archivos.find((archivo) => archivo.id === id);
      if (!fila) throw archivoInexistente(id);

      if (fila.propietarioId !== estado.usuarioActual && !esAdmin()) {
        throw ErrorApi.prohibido('ARCHIVO_AJENO', 'El archivo no es tuyo.', {
          contexto: 'confirmar un archivo',
        });
      }

      if ((fila.estado ?? 'PENDING') !== 'PENDING') {
        throw ErrorApi.conflicto(
          'ESTADO_DE_ARCHIVO',
          'El archivo no está pendiente: ya se confirmó o ya se borró.',
          { contexto: 'confirmar un archivo' },
        );
      }

      fila.estado = 'CONFIRMED';
      fila.tamanoBytes = tamanoBytes;
      fila.confirmadoEn = CREADO_EN_FALSO;

      return aArchivoFalso(fila);
    },

    async marcarBorrado(id: string): Promise<ArchivoMetadata> {
      revisar('archivos.marcarBorrado');

      const fila = estado.archivos.find((archivo) => archivo.id === id);
      if (!fila) throw archivoInexistente(id);

      if (fila.propietarioId !== estado.usuarioActual && !esAdmin()) {
        throw ErrorApi.prohibido('ARCHIVO_AJENO', 'El archivo no es tuyo.', {
          contexto: 'borrar un archivo',
        });
      }

      if ((fila.estado ?? 'PENDING') === 'DELETED') {
        throw ErrorApi.conflicto('ESTADO_DE_ARCHIVO', 'El archivo ya estaba borrado.', {
          contexto: 'borrar un archivo',
        });
      }

      fila.estado = 'DELETED';
      fila.borradoEn = CREADO_EN_FALSO;

      return aArchivoFalso(fila);
    },

    async porId(id: string): Promise<ArchivoMetadata | null> {
      revisar('archivos.porId');

      const fila = archivosVisibles().find((archivo) => archivo.id === id);

      // `null` funde «no existe» y «no es tuyo», igual que el repositorio real:
      // distinguirlos revelaría, por el código de respuesta, si un archivo ajeno
      // existe.
      return fila ? aArchivoFalso(fila) : null;
    },

    async contarPorEntidad(
      entityType: TipoEntidadArchivo,
      entidadId: string | null,
    ): Promise<number> {
      revisar('archivos.contarPorEntidad');

      // Se cuenta sobre lo **visible**, no sobre el total, porque el repositorio
      // real cuenta con PostgREST y por tanto bajo RLS: para un estudiante el tope
      // es por propietario y para un admin es global. Contar el total aquí haría
      // que el doble fuese más estricto que la base, y una prueba daría por bueno
      // un 409 que en producción no ocurre.
      return archivosVisibles().filter(
        (archivo) =>
          (archivo.entityType ?? 'TASK_SUBMISSION') === entityType &&
          (archivo.entidadId ?? null) === entidadId &&
          (archivo.estado ?? 'PENDING') !== 'DELETED',
      ).length;
    },

    async listarPorEntidad(
      entityType: TipoEntidadArchivo,
      entidadId: string,
    ): Promise<ArchivoMetadata[]> {
      revisar('archivos.listarPorEntidad');

      // Se lee sobre lo **visible**, como `contarPorEntidad` y
      // `pendientesAntiguos`: el repositorio real va por PostgREST bajo RLS. Usar
      // `estado.archivos` aquí haría que el doble fuese más permisivo que la base
      // y una prueba daría por bueno que un alumno ve el archivo de otro —que es
      // justo lo que estas pruebas existen para impedir.
      //
      // El orden reproduce el `order('created_at', { ascending: false })` real, y
      // compara con `Date` y no con `<` entre cadenas: la base compara
      // `timestamptz`, y dos cadenas ISO equivalentes pero escritas distinto
      // —`Z` contra `+00:00`— ordenan distinto como texto.
      return archivosVisibles()
        .filter(
          (archivo) =>
            (archivo.entityType ?? 'TASK_SUBMISSION') === entityType &&
            (archivo.entidadId ?? null) === entidadId &&
            (archivo.estado ?? 'PENDING') !== 'DELETED',
        )
        .sort(
          (a, b) =>
            new Date(b.creadoEn ?? CREADO_EN_FALSO).getTime() -
            new Date(a.creadoEn ?? CREADO_EN_FALSO).getTime(),
        )
        .map(aArchivoFalso);
    },

    async pendientesAntiguos(
      antesDe: string,
      limite: number,
    ): Promise<ArchivoMetadata[]> {
      revisar('archivos.pendientesAntiguos');

      // Se mira sobre lo **visible**, como `contarPorEntidad`: el repositorio
      // real lee por PostgREST bajo RLS, así que para un administrador el barrido
      // alcanza toda la tabla y para cualquier otro alcanzaría sólo lo suyo. Usar
      // `estado.archivos` aquí haría que el doble fuese más permisivo que la base
      // y una prueba daría por bueno un barrido global que en producción no
      // ocurre.
      const corte = new Date(antesDe).getTime();

      // La comparación se hace con `Date` y no con `<` entre cadenas, porque la
      // base compara `timestamptz` y no texto: dos cadenas ISO equivalentes pero
      // escritas distinto —`Z` contra `+00:00`, con o sin milisegundos— ordenan
      // distinto como texto y darían un barrido que no coincide con el real.
      return archivosVisibles()
        .filter(
          (archivo) =>
            (archivo.estado ?? 'PENDING') === 'PENDING' &&
            new Date(archivo.creadoEn ?? CREADO_EN_FALSO).getTime() < corte,
        )
        .sort(
          (a, b) =>
            new Date(a.creadoEn ?? CREADO_EN_FALSO).getTime() -
            new Date(b.creadoEn ?? CREADO_EN_FALSO).getTime(),
        )
        .slice(0, limite)
        .map(aArchivoFalso);
    },
  };

  // --- M6: el aula virtual --------------------------------------------------

  /**
   * ¿El llamante dicta esta sección?
   *
   * Reproduce `m6_dicta_seccion`: cierto para el administrador —que supervisa
   * todo— o para quien tiene una clase activa en la sección. Es la pregunta de
   * la que cuelgan todas las escrituras del docente.
   */
  function dictaSeccion(seccionId: string): boolean {
    if (esAdmin()) return true;
    const actor = estado.usuarioActual;
    if (actor === null) return false;
    return estado.clases.some(
      (clase) => clase.seccionId === seccionId && clase.docenteId === actor && clase.activa,
    );
  }

  /** Reproduce `m6_matriculado_en`: ¿el llamante está `ENROLLED` en la sección? */
  function matriculadoEn(seccionId: string): boolean {
    const actor = estado.usuarioActual;
    if (actor === null) return false;
    return estado.inscripciones.some(
      (i) =>
        i.seccionId === seccionId &&
        i.estudianteId === actor &&
        (i.estado ?? 'ENROLLED') === 'ENROLLED',
    );
  }

  /**
   * Reproduce `m6_tarea_publicada_para_mi`.
   *
   * Cierto si la tarea está `PUBLICADO`, o si es un `BORRADOR` con
   * `programadoPara` ya vencida —la publicación diferida sin planificador—. La
   * comparación usa el reloj de verdad porque la política de la base también lo
   * usa; una prueba que ejercite este camino debe sembrar una fecha pasada.
   */
  function tareaPublicadaParaMi(tarea: TareaFalsa): boolean {
    if ((tarea.estado ?? 'BORRADOR') === 'ELIMINADO') return false;
    if (!matriculadoEn(tarea.seccionId)) return false;
    if ((tarea.estado ?? 'BORRADOR') === 'PUBLICADO') return true;
    return (
      !!tarea.programadoPara &&
      new Date(tarea.programadoPara).getTime() <= Date.now()
    );
  }

  /** Reproduce `m6_dicta_entrega`: el docente de la sección a la que cuelga. */
  function dictaEntrega(entregaId: string): boolean {
    const entrega = estado.entregas.find((e) => e.id === entregaId);
    if (!entrega) return false;
    const tarea = estado.tareas.find((t) => t.id === entrega.tareaId);
    return tarea !== undefined && dictaSeccion(tarea.seccionId);
  }

  /**
   * Las filas de `m6_anuncios` que el llamante puede ver.
   *
   * Reproduce `m6_anuncios_visible`. **No prueba la RLS** —la aplica Postgres y
   * sólo se comprueba contra la nube (lección R-23)—; lo que prueba es que la
   * ruta y el repositorio tratan bien lo que la política deja pasar.
   */
  function anunciosVisibles(): AnuncioFalso[] {
    const actor = estado.usuarioActual;
    if (actor === null) return [];

    return estado.anuncios.filter((anuncio) => {
      const est = anuncio.estado ?? 'BORRADOR';
      if (est === 'ELIMINADO') return false;
      if (dictaSeccion(anuncio.seccionId) || anuncio.autorId === actor) return true;
      return (
        matriculadoEn(anuncio.seccionId) &&
        (est === 'PUBLICADO' ||
          (!!anuncio.programadoPara &&
            new Date(anuncio.programadoPara).getTime() <= Date.now()))
      );
    });
  }

  /** Las filas de `m6_tareas` que el llamante puede ver. */
  function tareasVisibles(): TareaFalsa[] {
    return estado.tareas.filter(
      (tarea) =>
        (tarea.estado ?? 'BORRADOR') !== 'ELIMINADO' &&
        (dictaSeccion(tarea.seccionId) || tareaPublicadaParaMi(tarea)),
    );
  }

  /** Las filas de `m6_entregas` que el llamante puede ver. */
  function entregasVisibles(): EntregaFalso[] {
    const actor = estado.usuarioActual;
    if (actor === null) return [];
    return estado.entregas.filter(
      (e) => esAdmin() || e.estudianteId === actor || dictaEntrega(e.id ?? ''),
    );
  }

  /** ¿La tarea tiene una fecha límite ya vencida? Mitad derivada de `faltante`. */
  function plazoVencido(tareaId: string): boolean {
    const limite = estado.tareas.find((t) => t.id === tareaId)?.fechaLimite ?? null;
    return limite !== null && new Date(limite).getTime() < Date.now();
  }

  /** Un id obligatorio del arnés. Falla en alto en vez de devolver `undefined`. */
  function idDeFila(id: string | undefined, recurso: string): string {
    if (id === undefined) throw ErrorApi.interno(`El arnés tiene ${recurso} sin id.`);
    return id;
  }

  let contadorAnuncios = 0;
  let contadorTareas = 0;

  function idDeAnuncioNuevo(): string {
    contadorAnuncios += 1;
    return `a6a6a6a6-1001-4001-8001-${String(contadorAnuncios).padStart(12, '0')}`;
  }

  function idDeTareaNueva(): string {
    contadorTareas += 1;
    return `b7b7b7b7-1001-4001-8001-${String(contadorTareas).padStart(12, '0')}`;
  }

  /** El 404 de una RPC sobre una fila que no existe. */
  function aulaInexistente(recurso: string, id: string): ErrorApi {
    return ErrorApi.noEncontrado('RECURSO_INEXISTENTE', `${recurso} ${id} no existe.`);
  }

  /** El 403 de una RPC cuando el llamante no dicta la sección. */
  function noDictaSeccion(accion: string): ErrorApi {
    return ErrorApi.prohibido(
      'SIN_PERMISO_EN_EL_AULA',
      `No dictas la sección: no puedes ${accion}.`,
      { contexto: accion },
    );
  }

  /** El 403 del alumno cuando la entrega no es suya. */
  function entregaAjena(entregaId: string): ErrorApi {
    return ErrorApi.prohibido(
      'SIN_PERMISO_EN_EL_AULA',
      `La entrega ${entregaId} no es tuya.`,
      { contexto: 'entregar una entrega ajena' },
    );
  }

  function aAnuncioFalso(fila: AnuncioFalso): Anuncio {
    return {
      id: idDeFila(fila.id, 'un anuncio'),
      seccionId: fila.seccionId,
      autorId: fila.autorId,
      titulo: fila.titulo,
      cuerpo: fila.cuerpo ?? '',
      estado: fila.estado ?? 'BORRADOR',
      programadoPara: fila.programadoPara ?? null,
      publicadoEn: fila.publicadoEn ?? null,
    };
  }

  function aTareaFalsa(fila: TareaFalsa): Tarea {
    return {
      id: idDeFila(fila.id, 'una tarea'),
      seccionId: fila.seccionId,
      titulo: fila.titulo,
      descripcion: fila.descripcion ?? '',
      tipo: fila.tipo ?? 'TAREA',
      puntosMaximos: fila.puntosMaximos ?? 20,
      fechaLimite: fila.fechaLimite ?? null,
      permitirEntregaTardia: fila.permitirEntregaTardia ?? true,
      tema: fila.tema ?? null,
      orden: fila.orden ?? 0,
      estado: fila.estado ?? 'BORRADOR',
      publicadoEn: fila.publicadoEn ?? null,
    };
  }

  /**
   * La entrega vista por el alumno.
   *
   * **No tiene `notaBorrador`, igual que el repositorio real**: el doble devuelve
   * la misma forma que el `select` de columnas concedidas, así que la prueba de
   * la frontera del borrador comprueba lo mismo aquí que en producción.
   */
  function aEntregaFalsa(fila: EntregaFalso): Entrega {
    return {
      id: idDeFila(fila.id, 'una entrega'),
      tareaId: fila.tareaId,
      estado: fila.estado ?? 'ASIGNADA',
      esTardia: fila.esTardia ?? false,
      notaAsignada: fila.notaAsignada ?? null,
      entregadaEn: fila.entregadaEn ?? null,
    };
  }

  function aLibroEntregaFalso(fila: EntregaFalso): LibroEntrega {
    const estadoEntrega = fila.estado ?? 'ASIGNADA';
    return {
      id: idDeFila(fila.id, 'una entrega'),
      estudianteId: fila.estudianteId,
      estado: estadoEntrega,
      esTardia: fila.esTardia ?? false,
      notaBorrador: fila.notaBorrador ?? null,
      notaAsignada: fila.notaAsignada ?? null,
      entregadaEn: fila.entregadaEn ?? null,
      devueltaEn: fila.devueltaEn ?? null,
      // Derivada como en la RPC: `ASIGNADA` con la fecha límite ya vencida.
      faltante: estadoEntrega === 'ASIGNADA' && plazoVencido(fila.tareaId),
    };
  }

  function aEntregaCalificadaFalsa(
    fila: EntregaFalso,
    conDevolucion: boolean,
  ): EntregaCalificada {
    const base: EntregaCalificada = {
      id: idDeFila(fila.id, 'una entrega'),
      tareaId: fila.tareaId,
      estudianteId: fila.estudianteId,
      estado: fila.estado ?? 'ASIGNADA',
      esTardia: fila.esTardia ?? false,
      notaBorrador: fila.notaBorrador ?? null,
      notaAsignada: fila.notaAsignada ?? null,
    };
    // `calificar` no toca `devuelta_en`, así que la propiedad llega ausente; sólo
    // `devolver` la sella. Es la misma distinción que hace el repositorio real.
    return conDevolucion ? { ...base, devueltaEn: fila.devueltaEn ?? null } : base;
  }

  /**
   * El aula virtual, en memoria.
   *
   * Reproduce el reparto real: las lecturas filtran por la política —vía
   * `anunciosVisibles`, `tareasVisibles` y `entregasVisibles`— y las escrituras
   * reproducen **cómo fallan** las RPC, porque de eso depende el código de estado
   * que ve el usuario. Un doble que dejara pasar todo daría por buenas
   * operaciones que la base rechaza.
   */
  const aula: PuertaAula = {
    async tablon(seccionId) {
      revisar('aula.tablon');

      return anunciosVisibles()
        .filter((anuncio) => anuncio.seccionId === seccionId)
        .sort((a, b) => {
          // Del más nuevo al más viejo, con los sin publicar al final: es el
          // `publicado_en desc nulls last` del índice real.
          const fa = a.publicadoEn ?? null;
          const fb = b.publicadoEn ?? null;
          if (fa === null && fb === null) return 0;
          if (fa === null) return 1;
          if (fb === null) return -1;
          return fb.localeCompare(fa);
        })
        .map(aAnuncioFalso);
    },

    async crearAnuncio(entrada) {
      revisar('aula.crearAnuncio');

      if (!dictaSeccion(entrada.seccionId)) throw noDictaSeccion('publicar en su tablón');

      const fila: AnuncioFalso = {
        id: idDeAnuncioNuevo(),
        seccionId: entrada.seccionId,
        autorId: usuarioActual(),
        titulo: entrada.titulo,
        cuerpo: entrada.cuerpo,
        estado: 'BORRADOR',
        programadoPara: entrada.programadoPara,
        publicadoEn: null,
      };

      estado.anuncios.push(fila);

      return aAnuncioFalso(fila);
    },

    async trabajoDeClase(seccionId) {
      revisar('aula.trabajoDeClase');

      return tareasVisibles()
        .filter((tarea) => tarea.seccionId === seccionId)
        .sort((a, b) => {
          const ta = a.tema ?? null;
          const tb = b.tema ?? null;
          if (ta !== tb) {
            if (ta === null) return -1;
            if (tb === null) return 1;
            return ta.localeCompare(tb);
          }
          return (a.orden ?? 0) - (b.orden ?? 0);
        })
        .map(aTareaFalsa);
    },

    async crearTarea(entrada) {
      revisar('aula.crearTarea');

      if (!dictaSeccion(entrada.seccionId)) throw noDictaSeccion('crear trabajo en ella');

      // La RPC comprueba la coherencia MATERIAL/sin nota antes que el `CHECK`,
      // para dar un mensaje que se entienda. El doble reproduce ese 23514.
      if (
        entrada.tipo === 'MATERIAL' &&
        (entrada.puntosMaximos !== 0 || entrada.fechaLimite !== null)
      ) {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          'Un MATERIAL es de lectura: no lleva puntos ni fecha límite.',
          { contexto: 'crear una tarea' },
        );
      }

      const fila: TareaFalsa = {
        id: idDeTareaNueva(),
        seccionId: entrada.seccionId,
        titulo: entrada.titulo,
        descripcion: entrada.descripcion,
        tipo: entrada.tipo,
        puntosMaximos: entrada.puntosMaximos,
        fechaLimite: entrada.fechaLimite,
        permitirEntregaTardia: entrada.permitirEntregaTardia,
        tema: entrada.tema,
        orden: entrada.orden,
        estado: 'BORRADOR',
        publicadoEn: null,
      };

      estado.tareas.push(fila);

      return aTareaFalsa(fila);
    },

    async publicarTarea(tareaId): Promise<PublicacionTarea> {
      revisar('aula.publicarTarea');

      const tarea = estado.tareas.find((t) => t.id === tareaId);
      if (!tarea) throw aulaInexistente('La tarea', tareaId);
      if (!dictaSeccion(tarea.seccionId)) throw noDictaSeccion('publicarla');
      if ((tarea.estado ?? 'BORRADOR') === 'ELIMINADO') {
        throw new ErrorApi(400, 'RESTRICCION_VIOLADA', 'La tarea está eliminada.', {
          contexto: 'publicar una tarea',
        });
      }

      // Idempotente: sólo se crean los placeholders que faltan. Un alumno que ya
      // entregó no puede perder su entrega al republicar —las entregas cuelgan
      // de la fila en cascada—.
      let creadas = 0;

      for (const inscripcion of estado.inscripciones) {
        if (inscripcion.seccionId !== tarea.seccionId) continue;
        if ((inscripcion.estado ?? 'ENROLLED') !== 'ENROLLED') continue;

        const yaHay = estado.entregas.some(
          (e) => e.tareaId === tareaId && e.estudianteId === inscripcion.estudianteId,
        );
        if (yaHay) continue;

        estado.entregas.push({
          tareaId,
          estudianteId: inscripcion.estudianteId,
          estado: 'ASIGNADA',
        });
        creadas += 1;
      }

      tarea.estado = 'PUBLICADO';
      tarea.publicadoEn = tarea.publicadoEn ?? CREADO_EN_FALSO;

      return {
        tarea: {
          id: idDeFila(tarea.id, 'una tarea'),
          seccionId: tarea.seccionId,
          titulo: tarea.titulo,
          estado: 'PUBLICADO',
          publicadoEn: tarea.publicadoEn ?? null,
        },
        entregasCreadas: creadas,
      };
    },

    async entregasDeTarea(tareaId) {
      revisar('aula.entregasDeTarea');

      // La RPC no lanza 403 si el llamante no dicta: **filtra** con
      // `m6_dicta_entrega`, así que un alumno recibe una lista vacía. El doble
      // hace lo mismo para no ser más estricto que la base.
      return estado.entregas
        .filter((e) => e.tareaId === tareaId && dictaEntrega(e.id ?? ''))
        .sort((a, b) => a.estudianteId.localeCompare(b.estudianteId))
        .map(aLibroEntregaFalso);
    },

    async misEntregas() {
      revisar('aula.misEntregas');

      return entregasVisibles()
        .sort((a, b) => {
          const fa = a.entregadaEn ?? null;
          const fb = b.entregadaEn ?? null;
          if (fa === null && fb === null) return 0;
          if (fa === null) return 1;
          if (fb === null) return -1;
          return fb.localeCompare(fa);
        })
        .map(aEntregaFalsa);
    },

    async entregar(entregaId) {
      revisar('aula.entregar');

      const entrega = estado.entregas.find((e) => e.id === entregaId);
      if (!entrega) throw aulaInexistente('La entrega', entregaId);

      // El dueño, no el docente: entregar es del alumno. Ni siquiera el
      // administrador entrega en nombre de otro.
      if (entrega.estudianteId !== estado.usuarioActual) throw entregaAjena(entregaId);

      const tarea = estado.tareas.find((t) => t.id === entrega.tareaId);
      if (!tarea) throw aulaInexistente('La tarea', entrega.tareaId);

      if ((tarea.estado ?? 'BORRADOR') !== 'PUBLICADO') {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          'La tarea no está publicada: no se puede entregar.',
          { contexto: 'entregar una tarea' },
        );
      }

      const estadoActual = entrega.estado ?? 'ASIGNADA';

      if (estadoActual === 'DEVUELTA') {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          'La entrega ya fue devuelta: no se puede volver a entregar.',
          { contexto: 'entregar una tarea' },
        );
      }

      // `MODIFIABLE_UNTIL_TURNED_IN` es el defecto: una vez entregada, el alumno
      // no cambia los adjuntos hasta que el docente se la devuelva.
      if (estadoActual === 'ENTREGADA') {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          'La tarea ya está entregada. Reclámala antes de volver a entregarla.',
          { contexto: 'entregar una tarea' },
        );
      }

      const limite = tarea.fechaLimite ?? null;
      const tarde = limite !== null && new Date(limite).getTime() < Date.now();

      if (tarde && !(tarea.permitirEntregaTardia ?? true)) {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          `La tarea cerró el ${limite} y no admite entregas tardías.`,
          { contexto: 'entregar una tarea' },
        );
      }

      entrega.estado = 'ENTREGADA';
      entrega.esTardia = tarde;
      entrega.entregadaEn = CREADO_EN_FALSO;

      return aEntregaFalsa(entrega);
    },

    async reclamar(entregaId) {
      revisar('aula.reclamar');

      const entrega = estado.entregas.find((e) => e.id === entregaId);
      if (!entrega) throw aulaInexistente('La entrega', entregaId);
      if (entrega.estudianteId !== estado.usuarioActual) throw entregaAjena(entregaId);

      const estadoActual = entrega.estado ?? 'ASIGNADA';

      if (estadoActual !== 'ENTREGADA') {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          `Sólo se puede reclamar una entrega ya entregada (estado actual: ${estadoActual}).`,
          { contexto: 'reclamar una entrega' },
        );
      }

      entrega.estado = 'RECLAMADA';

      return aEntregaFalsa(entrega);
    },

    async calificar(entregaId, nota) {
      revisar('aula.calificar');

      if (!(nota >= 0 && nota <= 20)) {
        throw new ErrorApi(400, 'RESTRICCION_VIOLADA', 'La nota debe estar entre 0 y 20.', {
          contexto: 'calificar una entrega',
        });
      }

      const entrega = estado.entregas.find((e) => e.id === entregaId);
      if (!entrega) throw aulaInexistente('La entrega', entregaId);
      if (!dictaEntrega(entregaId)) throw noDictaSeccion('calificarla');

      const tarea = estado.tareas.find((t) => t.id === entrega.tareaId);
      if (!tarea) throw aulaInexistente('La tarea', entrega.tareaId);

      const maximo = tarea.puntosMaximos ?? 20;
      if (nota > maximo) {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          `La nota ${nota} supera el máximo de la tarea (${maximo}).`,
          { contexto: 'calificar una entrega' },
        );
      }

      const estadoActual = entrega.estado ?? 'ASIGNADA';
      if (estadoActual !== 'ENTREGADA' && estadoActual !== 'RECLAMADA') {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          `No hay nada que calificar todavía (estado actual: ${estadoActual}).`,
          { contexto: 'calificar una entrega' },
        );
      }

      entrega.notaBorrador = nota;

      return aEntregaCalificadaFalsa(entrega, false);
    },

    async devolver(entregaId) {
      revisar('aula.devolver');

      const entrega = estado.entregas.find((e) => e.id === entregaId);
      if (!entrega) throw aulaInexistente('La entrega', entregaId);
      if (!dictaEntrega(entregaId)) throw noDictaSeccion('devolverla');

      const estadoActual = entrega.estado ?? 'ASIGNADA';
      if (estadoActual !== 'ENTREGADA' && estadoActual !== 'RECLAMADA') {
        throw new ErrorApi(
          400,
          'RESTRICCION_VIOLADA',
          `No hay una entrega que devolver (estado actual: ${estadoActual}).`,
          { contexto: 'devolver una entrega' },
        );
      }

      entrega.estado = 'DEVUELTA';
      // Copia el borrador a la asignada: es el único momento en que el alumno ve
      // una nota. Devolver sin nota es legítimo y deja `null`.
      entrega.notaAsignada = entrega.notaBorrador ?? null;
      entrega.devueltaEn = CREADO_EN_FALSO;

      return aEntregaCalificadaFalsa(entrega, true);
    },
  };

  const repos: Repositorios = {
    perfiles,
    modulos,
    parametros,
    auditoria,
    invitaciones,
    acceso,
    curriculo,
    cuadrante,
    secciones,
    inscripciones,
    archivos,
    aula,
  };

  const enviarCorreo: EnvioCorreo = {
    async enviar(mensaje) {
      estado.correos.push({ para: mensaje.para, asunto: mensaje.asunto });
      return { entregado: true };
    },
  };

  const env = cargarEnv({
    NODE_ENV: 'test',
    SUPABASE_URL: 'https://prueba.supabase.co',
    SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
    SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
    MODULE_CACHE_TTL_MS: String(opciones.moduleCacheTtlMs ?? 0),
    SETTINGS_CACHE_TTL_MS: String(opciones.settingsCacheTtlMs ?? 0),
  });

  /**
   * El bucket falso: clave → tamaño en bytes.
   *
   * Se siembra con los archivos **confirmados**, porque un archivo confirmado es,
   * por definición, uno cuyo objeto llegó y se midió: el `HeadObject` tiene que
   * encontrarlo o el arnés mentiría sobre su propio estado inicial. Los `PENDING`
   * no se siembran a propósito —ése es justo el caso de la subida interrumpida—,
   * y una prueba que quiera simular una subida completa pone el objeto a mano.
   */
  const objetos = new Map<string, number>();

  for (const fila of estado.archivos) {
    const tamano = fila.tamanoBytes;
    if (fila.estado === 'CONFIRMED' && typeof tamano === 'number') {
      objetos.set(fila.r2Key, tamano);
    }
  }

  /** Claves cuya eliminación se pidió, en orden. */
  const borrados: string[] = [];

  const almacenamiento: AlmacenamientoFalso = {
    objetos,
    borrados,

    async urlDeSubida(peticion) {
      revisar('almacenamiento.urlDeSubida');

      // La clave la construye el doble con la **misma función pura** que el
      // adaptador real, no con una copia. Es lo que permite comprobar que la ruta
      // firma antes de registrar la fila: si el doble inventara la clave, la que
      // guardara la fila y la que devolviera la firma serían distintas y la
      // comprobación no probaría nada.
      const clave = construirClave(peticion.prefijo, peticion.nombreOriginal);

      return {
        clave,
        url: `https://r2.falso/${clave}?firma=subida`,
        expiraEnSegundos: env.R2_PUT_TTL_SEGUNDOS,
        tipoContenido: tipoContenidoDe(extensionDe(peticion.nombreOriginal)),
      };
    },

    async urlDeDescarga(clave, _nombreDescarga) {
      revisar('almacenamiento.urlDeDescarga');

      const limpia = validarClave(clave);

      return {
        clave: limpia,
        url: `https://r2.falso/${limpia}?firma=lectura`,
        expiraEnSegundos: env.R2_GET_TTL_SEGUNDOS,
        // El tipo se deriva de la **clave**, no del nombre de descarga, igual que
        // el adaptador real: el nombre legible es cosmético y no debe poder
        // cambiar el `Content-Type` con el que se sirve el objeto.
        tipoContenido: tipoContenidoDe(extensionDe(limpia)),
      };
    },

    async estadisticas(clave) {
      revisar('almacenamiento.estadisticas');

      const limpia = validarClave(clave);
      const tamano = objetos.get(limpia);

      // Ausente es `null` y no un error: es la subida interrumpida, que la ruta
      // traduce a un 404 con código propio.
      return tamano === undefined ? null : { tamanoBytes: tamano };
    },

    async eliminar(clave) {
      revisar('almacenamiento.eliminar');

      const limpia = validarClave(clave);

      borrados.push(limpia);
      objetos.delete(limpia);
    },
  };

  const identidades: Record<string, string> = {
    [TOKEN_ADMIN]: ID_ADMIN,
    [TOKEN_ALUMNO]: ID_ALUMNO,
    [TOKEN_DOCENTE]: ID_DOCENTE,
    ...(opciones.identidades ?? {}),
  };

  const app = construirApp(env, {
    verificarToken: async (token) => {
      const id = identidades[token];
      if (!id) return null;
      const perfil = estado.perfiles.find((p) => p.id === id);
      return { id, email: perfil?.email ?? null };
    },
    reposAdmin: repos,
    // Fija «quién llama» antes de que corra el manejador: es el sustituto del
    // `auth.uid()` que en producción resuelve Postgres desde el JWT.
    reposDePeticion: (token) => {
      estado.usuarioActual = token ? (identidades[token] ?? null) : null;
      return repos;
    },
    enviarCorreo,
    // El arnés inyecta el almacén en vez de dejar que `construirApp` lo derive de
    // `env`: firmar es puro y funcionaría sin red, pero `HeadObject` y
    // `DeleteObject` saldrían a internet. `sinAlmacenamiento` reproduce el
    // despliegue que no tiene R2 configurado.
    almacenamiento: opciones.sinAlmacenamiento ? null : almacenamiento,
  });

  return { app, estado, llamadas, fallos, env, almacenamiento };
}

/** Cabeceras con el token indicado. */
export function conToken(token: string | null): Record<string, string> {
  return token ? { authorization: `Bearer ${token}` } : {};
}
