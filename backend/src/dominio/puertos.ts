/**
 * Puertos (interfaces) del dominio.
 *
 * Es la misma decisión arquitectónica que resolvió la deuda D1 en Flutter: las
 * capas de arriba dependen de una interfaz, no de un cliente concreto. Aquí
 * permite montar la API entera en memoria durante los tests —sin red, sin
 * Supabase, sin credenciales— y verificar el comportamiento de verdad:
 * guardias de módulo, permisos, validación y traducción de errores.
 */
import type {
  CambiosModulo,
  EntradaAuditoria,
  ModuloSistema,
  ParametroSistema,
  Perfil,
  Rol,
} from './tipos.js';
import type { PeticionUrlSubida, UrlFirmada } from './almacenamiento.js';

/** Verifica un token de Supabase y devuelve la identidad, o `null` si no vale. */
export interface PuertaAuth {
  verificar(token: string): Promise<{ id: string; email: string | null } | null>;
}

export interface PuertaPerfiles {
  porId(id: string): Promise<Perfil | null>;
  /** Operación de administrador: cambiar el rol de un usuario. */
  cambiarRol(id: string, rol: Rol): Promise<Perfil>;
  /**
   * Cuántos administradores **activos** hay ahora mismo.
   *
   * Existe para poder avisar antes de dejar el sistema sin nadie capaz de
   * gestionarlo. La barrera de verdad es un trigger en PostgreSQL, que también
   * cubre la carrera entre dos degradaciones simultáneas; esto sólo sirve para
   * dar un mensaje que se entienda en vez de un error de restricción genérico.
   */
  contarAdminsActivos(): Promise<number>;
}

export interface PuertaModulos {
  todos(): Promise<ModuloSistema[]>;
  porClave(clave: string): Promise<ModuloSistema | null>;
  actualizar(clave: string, cambios: CambiosModulo): Promise<ModuloSistema>;
}

export interface PuertaParametros {
  /** `incluirPrivados` en `false` filtra a los marcados como públicos. */
  todos(incluirPrivados: boolean): Promise<ParametroSistema[]>;
  porClave(clave: string): Promise<ParametroSistema | null>;
  actualizar(clave: string, valor: unknown): Promise<ParametroSistema>;
}

export interface PuertaAuditoria {
  listar(limite: number): Promise<EntradaAuditoria[]>;
}

/**
 * Almacenamiento pesado (Cloudflare R2).
 *
 * No forma parte de `Repositorios` a propósito: no es una tabla, es un servicio
 * externo con su propio ciclo de vida. Se mantiene como puerto independiente
 * para que una ruta de M5 pueda recibirlo inyectado y los tests puedan sustituir
 * R2 por un doble en memoria sin credenciales.
 */
export interface PuertaAlmacenamiento {
  /** Autoriza una escritura de un solo objeto, con la clave ya fijada. */
  urlDeSubida(peticion: PeticionUrlSubida): Promise<UrlFirmada>;
  /** Autoriza una lectura. `nombreDescarga` sólo afecta a `Content-Disposition`. */
  urlDeDescarga(clave: string, nombreDescarga?: string): Promise<UrlFirmada>;
  /** `true` si el objeto existe. Se usa para validar antes de emitir una descarga. */
  existe(clave: string): Promise<boolean>;
  /** Borra un objeto. El backend decide *cuándo*; R2 sólo ejecuta. */
  eliminar(clave: string): Promise<void>;
}

/** Conjunto de puertas de datos que la API necesita. */
export interface Repositorios {
  perfiles: PuertaPerfiles;
  modulos: PuertaModulos;
  parametros: PuertaParametros;
  auditoria: PuertaAuditoria;
}
