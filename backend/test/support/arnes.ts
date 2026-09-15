import type { FastifyInstance } from 'fastify';
import { construirApp } from '../../src/app.js';
import { cargarEnv, type Env } from '../../src/config/env.js';
import type {
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaCurriculo,
  PuertaInvitacionesDocente,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../../src/dominio/puertos.js';
import { ErrorApi } from '../../src/dominio/errores.js';
import { agruparPensum, pensumEditable } from '../../src/dominio/reglas-curriculo.js';
import type { EnvioCorreo } from '../../src/infra/correo.js';
import type {
  CambiosModulo,
  DetallePrograma,
  EntradaAcceso,
  EntradaAuditoria,
  EntradaPensum,
  InvitacionDocente,
  Materia,
  MateriaEnPensum,
  ModuloSistema,
  ParametroSistema,
  Perfil,
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

  const repos: Repositorios = {
    perfiles,
    modulos,
    parametros,
    auditoria,
    invitaciones,
    acceso,
    curriculo,
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
