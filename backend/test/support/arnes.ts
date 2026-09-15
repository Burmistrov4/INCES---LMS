import type { FastifyInstance } from 'fastify';
import { construirApp } from '../../src/app.js';
import { cargarEnv, type Env } from '../../src/config/env.js';
import type {
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaCuadrante,
  PuertaCurriculo,
  PuertaInvitacionesDocente,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../../src/dominio/puertos.js';
import { ErrorApi } from '../../src/dominio/errores.js';
import { agruparPensum, pensumEditable } from '../../src/dominio/reglas-curriculo.js';
import { diaLegible, turnoDeBloque } from '../../src/dominio/reglas-cuadrante.js';
import type { EnvioCorreo } from '../../src/infra/correo.js';
import type {
  Aula,
  CambiosModulo,
  ClaseCuadrante,
  DetallePrograma,
  EntradaAcceso,
  EntradaAuditoria,
  EntradaPensum,
  Guardia,
  InvitacionDocente,
  Materia,
  MateriaEnPensum,
  ModuloSistema,
  ParametroSistema,
  Perfil,
  Periodo,
  Programa,
  Rol,
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

/** Una matrícula: qué estudiante está en qué sección. */
export interface InscripcionFalsa {
  estudianteId: string;
  seccionId: string;
}

/**
 * El alumno de ejemplo está matriculado en la sección SA.
 *
 * Sin esta fila, el horario del estudiante saldría vacío y una prueba de
 * `mi-horario` pasaría sin haber comprobado nada.
 */
export const INSCRIPCIONES_POR_DEFECTO: InscripcionFalsa[] = [
  { estudianteId: ID_ALUMNO, seccionId: ID_SECCION_SA },
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
}

export interface Arnés {
  app: FastifyInstance;
  estado: EstadoFalso;
  /** Nombres de las operaciones invocadas, en orden. */
  llamadas: string[];
  /** Errores a lanzar en la próxima llamada, por operación. */
  fallos: Partial<Record<string, unknown>>;
  env: Env;
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
  moduleCacheTtlMs?: number;
  settingsCacheTtlMs?: number;
}

const MODULOS_POR_DEFECTO: ModuloSistema[] = [
  modulo({ clave: 'm0_cpanel', nombre: 'Administrador Maestro', orden: 0, rolesPermitidos: ['admin'] }),
  modulo({ clave: 'm1_onboarding', nombre: 'Autenticación', orden: 10 }),
  modulo({ clave: 'm4_inscripciones', nombre: 'Inscripciones', orden: 40, habilitado: false }),
];

const PARAMETROS_POR_DEFECTO: ParametroSistema[] = [
  parametro({ clave: 'modo_mantenimiento', valor: false, tipo: 'boolean', esPublico: true }),
  parametro({ clave: 'max_faltas_consecutivas', valor: 3, tipo: 'number' }),
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
    async crearUsuarioDocente(email) {
      revisar('invitaciones.crearUsuarioDocente');
      const id = `usr-${estado.perfiles.length + 1}-${estado.invitaciones.length}`;
      const perfil: Perfil = {
        id,
        email,
        cedula: null,
        nombres: '',
        apellidos: '',
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

  const repos: Repositorios = {
    perfiles,
    modulos,
    parametros,
    auditoria,
    invitaciones,
    acceso,
    curriculo,
    cuadrante,
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

  const identidades: Record<string, string> = {
    [TOKEN_ADMIN]: ID_ADMIN,
    [TOKEN_ALUMNO]: ID_ALUMNO,
    [TOKEN_DOCENTE]: ID_DOCENTE,
  };

  const app = construirApp(env, {
    verificarToken: async (token) => {
      const id = identidades[token];
      if (!id) return null;
      const perfil = estado.perfiles.find((p) => p.id === id);
      return { id, email: perfil?.email ?? null };
    },
    reposAdmin: repos,
    reposDePeticion: () => repos,
    enviarCorreo,
  });

  return { app, estado, llamadas, fallos, env };
}

/** Cabeceras con el token indicado. */
export function conToken(token: string | null): Record<string, string> {
  return token ? { authorization: `Bearer ${token}` } : {};
}
