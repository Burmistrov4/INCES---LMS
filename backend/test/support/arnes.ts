import type { FastifyInstance } from 'fastify';
import { construirApp } from '../../src/app.js';
import { cargarEnv, type Env } from '../../src/config/env.js';
import type {
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaInvitacionesDocente,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../../src/dominio/puertos.js';
import { ErrorApi } from '../../src/dominio/errores.js';
import type { EnvioCorreo } from '../../src/infra/correo.js';
import type {
  CambiosModulo,
  EntradaAcceso,
  EntradaAuditoria,
  InvitacionDocente,
  ModuloSistema,
  ParametroSistema,
  Perfil,
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

// --- repositorios en memoria ------------------------------------------------

export interface EstadoFalso {
  perfiles: Perfil[];
  modulos: ModuloSistema[];
  parametros: ParametroSistema[];
  auditoria: EntradaAuditoria[];
  invitaciones: InvitacionDocente[];
  acceso: EntradaAcceso[];
  correos: { para: string; asunto: string }[];
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

  const repos: Repositorios = {
    perfiles,
    modulos,
    parametros,
    auditoria,
    invitaciones,
    acceso,
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
