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

/** Un período del pensum con sus materias, para pintar el detalle agrupado. */
export interface GrupoPensum {
  periodo: number;
  materias: EntradaPensum[];
}

/** El pensum completo de un programa, agrupado por período. */
export interface DetallePrograma {
  programa: Programa;
  pensum: GrupoPensum[];
  /** Secciones activas del período vigente. Es lo que decide `editable`. */
  seccionesActivas: number;
  /** `false` cuando la Regla 2 impide tocar el pensum. */
  editable: boolean;
}
