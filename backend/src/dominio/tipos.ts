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
