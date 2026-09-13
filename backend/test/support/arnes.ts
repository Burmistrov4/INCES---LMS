import type { FastifyInstance } from 'fastify';
import { construirApp } from '../../src/app.js';
import { cargarEnv, type Env } from '../../src/config/env.js';
import type {
  PuertaAuditoria,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../../src/dominio/puertos.js';
import { ErrorApi } from '../../src/dominio/errores.js';
import type {
  CambiosModulo,
  EntradaAuditoria,
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

// --- repositorios en memoria ------------------------------------------------

export interface EstadoFalso {
  perfiles: Perfil[];
  modulos: ModuloSistema[];
  parametros: ParametroSistema[];
  auditoria: EntradaAuditoria[];
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

/** Construye el arnés completo con la API ya montada. */
export function crearArnés(opciones: OpcionesArnés = {}): Arnés {
  const estado: EstadoFalso = {
    perfiles: opciones.perfiles ?? [PERFIL_ADMIN, PERFIL_ALUMNO],
    modulos: opciones.modulos ?? [...MODULOS_POR_DEFECTO],
    parametros: opciones.parametros ?? [...PARAMETROS_POR_DEFECTO],
    auditoria: opciones.auditoria ?? [],
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

  const repos: Repositorios = { perfiles, modulos, parametros, auditoria };

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
  });

  return { app, estado, llamadas, fallos, env };
}

/** Cabeceras con el token indicado. */
export function conToken(token: string | null): Record<string, string> {
  return token ? { authorization: `Bearer ${token}` } : {};
}
