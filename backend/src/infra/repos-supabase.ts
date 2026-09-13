import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  PuertaAuditoria,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../dominio/puertos.js';
import { ErrorApi } from '../dominio/errores.js';
import {
  esRol,
  type CambiosModulo,
  type EntradaAuditoria,
  type ModuloSistema,
  type ParametroSistema,
  type Perfil,
  type Rol,
  type TipoParametro,
} from '../dominio/tipos.js';
import { desenvolver, traducirError } from './traducir-error.js';

/**
 * Implementación de los puertos sobre Supabase.
 *
 * Todo lo que entra de la base de datos es `unknown` y pasa por los ayudantes de
 * normalización de abajo. Supabase devuelve `any`; confiar en él haría que una
 * columna nula o de otro tipo reventara en un punto lejano, con un stack trace
 * que no dice nada. Aquí se estrecha el tipo en la frontera.
 */

// --- normalizadores ---------------------------------------------------------

type Fila = Record<string, unknown>;

function texto(valor: unknown): string | null {
  return typeof valor === 'string' && valor.length > 0 ? valor : null;
}

function textoObligatorio(valor: unknown, porDefecto = ''): string {
  return typeof valor === 'string' ? valor : porDefecto;
}

function entero(valor: unknown, porDefecto = 0): number {
  return typeof valor === 'number' && Number.isFinite(valor) ? valor : porDefecto;
}

function booleano(valor: unknown, porDefecto = false): boolean {
  return typeof valor === 'boolean' ? valor : porDefecto;
}

function listaDeRoles(valor: unknown): Rol[] {
  if (!Array.isArray(valor)) return [];
  return valor.filter(esRol);
}

const TIPOS_VALIDOS: readonly TipoParametro[] = ['number', 'boolean', 'string', 'json'];

function tipoParametro(valor: unknown): TipoParametro {
  return TIPOS_VALIDOS.includes(valor as TipoParametro)
    ? (valor as TipoParametro)
    : 'json';
}

/**
 * Rol leído de la base de datos.
 *
 * Si llegara un valor desconocido se degrada a `estudiante`, el rol con menos
 * privilegios. Un `throw` aquí tumbaría el login de todo el mundo por un typo en
 * una fila; degradar es la opción segura.
 */
function rolSeguro(valor: unknown): Rol {
  return esRol(valor) ? valor : 'estudiante';
}

// --- mapeadores -------------------------------------------------------------

function aPerfil(fila: Fila): Perfil {
  return {
    id: textoObligatorio(fila.id),
    email: textoObligatorio(fila.email),
    cedula: texto(fila.cedula),
    nombres: textoObligatorio(fila.nombres),
    apellidos: textoObligatorio(fila.apellidos),
    rol: rolSeguro(fila.rol),
    activo: booleano(fila.active, true),
  };
}

function aModulo(fila: Fila): ModuloSistema {
  return {
    clave: textoObligatorio(fila.clave),
    nombre: textoObligatorio(fila.nombre),
    descripcion: texto(fila.descripcion),
    habilitado: booleano(fila.habilitado, false),
    orden: entero(fila.orden, 0),
    icono: texto(fila.icono),
    rolesPermitidos: listaDeRoles(fila.roles_permitidos),
    categoria: textoObligatorio(fila.categoria, 'general'),
    actualizadoEn: texto(fila.updated_at),
  };
}

function aParametro(fila: Fila): ParametroSistema {
  return {
    clave: textoObligatorio(fila.clave),
    valor: fila.valor ?? null,
    tipo: tipoParametro(fila.tipo),
    descripcion: texto(fila.descripcion),
    categoria: textoObligatorio(fila.categoria, 'general'),
    esPublico: booleano(fila.es_publico, false),
    actualizadoEn: texto(fila.updated_at),
  };
}

function aAuditoria(fila: Fila): EntradaAuditoria {
  return {
    id: textoObligatorio(fila.id),
    tabla: textoObligatorio(fila.tabla),
    clave: textoObligatorio(fila.clave),
    valorAnterior: fila.valor_anterior ?? null,
    valorNuevo: fila.valor_nuevo ?? null,
    usuarioEmail: texto(fila.usuario_email),
    creadoEn: texto(fila.created_at),
  };
}

// --- repositorios -----------------------------------------------------------

const TABLA_PERFILES = 'profiles';
const TABLA_MODULOS = 'system_modules';
const TABLA_PARAMETROS = 'system_settings';
const TABLA_AUDITORIA = 'config_audit_log';

class PerfilesSupabase implements PuertaPerfiles {
  constructor(private readonly cliente: SupabaseClient) {}

  async porId(id: string): Promise<Perfil | null> {
    const respuesta = await this.cliente
      .from(TABLA_PERFILES)
      .select('id, email, cedula, nombres, apellidos, rol, active')
      .eq('id', id)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer perfil');
    if (!respuesta.data) return null;

    return aPerfil(respuesta.data as Fila);
  }

  async cambiarRol(id: string, rol: Rol): Promise<Perfil> {
    const respuesta = await this.cliente
      .from(TABLA_PERFILES)
      .update({ rol })
      .eq('id', id)
      .select('id, email, cedula, nombres, apellidos, rol, active')
      .single();

    return aPerfil(desenvolver(respuesta, 'cambiar rol') as Fila);
  }

  async contarAdminsActivos(): Promise<number> {
    // `head: true` pide sólo el recuento, sin traer las filas: no hace falta
    // saber *quiénes* son, sólo cuántos quedan.
    const respuesta = await this.cliente
      .from(TABLA_PERFILES)
      .select('id', { count: 'exact', head: true })
      .eq('rol', 'admin')
      .eq('active', true);

    if (respuesta.error) {
      throw traducirError(respuesta.error, 'contar administradores');
    }

    // Un recuento nulo con `count: 'exact'` no es «cero administradores»: es que
    // la respuesta no traía la cuenta. Devolver 0 aquí haría creer a la guardia
    // que el sistema está vacío y bloquearía cambios legítimos.
    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno(
        'La base de datos no devolvió el recuento de administradores.',
      );
    }

    return respuesta.count;
  }
}

class ModulosSupabase implements PuertaModulos {
  constructor(private readonly cliente: SupabaseClient) {}

  async todos(): Promise<ModuloSistema[]> {
    const respuesta = await this.cliente
      .from(TABLA_MODULOS)
      .select('*')
      .order('orden', { ascending: true })
      .order('clave', { ascending: true });

    const filas = desenvolver(respuesta, 'listar módulos') as Fila[];
    return filas.map(aModulo);
  }

  async porClave(clave: string): Promise<ModuloSistema | null> {
    const respuesta = await this.cliente
      .from(TABLA_MODULOS)
      .select('*')
      .eq('clave', clave)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer módulo');
    if (!respuesta.data) return null;

    return aModulo(respuesta.data as Fila);
  }

  async actualizar(clave: string, cambios: CambiosModulo): Promise<ModuloSistema> {
    const parche: Record<string, unknown> = {};
    if (cambios.habilitado !== undefined) parche.habilitado = cambios.habilitado;
    if (cambios.orden !== undefined) parche.orden = cambios.orden;
    if (cambios.rolesPermitidos !== undefined) {
      parche.roles_permitidos = cambios.rolesPermitidos;
    }

    if (Object.keys(parche).length === 0) {
      throw ErrorApi.peticionInvalida('No se indicó ningún cambio para el módulo.');
    }

    const respuesta = await this.cliente
      .from(TABLA_MODULOS)
      .update(parche)
      .eq('clave', clave)
      .select('*')
      .single();

    return aModulo(desenvolver(respuesta, 'actualizar módulo') as Fila);
  }
}

class ParametrosSupabase implements PuertaParametros {
  constructor(private readonly cliente: SupabaseClient) {}

  async todos(incluirPrivados: boolean): Promise<ParametroSistema[]> {
    let consulta = this.cliente
      .from(TABLA_PARAMETROS)
      .select('*')
      .order('categoria', { ascending: true })
      .order('clave', { ascending: true });

    // Con RLS activo, un usuario normal ya sólo ve los públicos; este filtro
    // explícito evita depender de ello y hace el contrato evidente.
    if (!incluirPrivados) consulta = consulta.eq('es_publico', true);

    const filas = desenvolver(await consulta, 'listar parámetros') as Fila[];
    return filas.map(aParametro);
  }

  async porClave(clave: string): Promise<ParametroSistema | null> {
    const respuesta = await this.cliente
      .from(TABLA_PARAMETROS)
      .select('*')
      .eq('clave', clave)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer parámetro');
    if (!respuesta.data) return null;

    return aParametro(respuesta.data as Fila);
  }

  async actualizar(clave: string, valor: unknown): Promise<ParametroSistema> {
    const respuesta = await this.cliente
      .from(TABLA_PARAMETROS)
      .update({ valor })
      .eq('clave', clave)
      .select('*')
      .single();

    return aParametro(desenvolver(respuesta, 'actualizar parámetro') as Fila);
  }
}

class AuditoriaSupabase implements PuertaAuditoria {
  constructor(private readonly cliente: SupabaseClient) {}

  async listar(limite: number): Promise<EntradaAuditoria[]> {
    const respuesta = await this.cliente
      .from(TABLA_AUDITORIA)
      .select('*')
      .order('created_at', { ascending: false })
      .limit(limite);

    const filas = desenvolver(respuesta, 'listar auditoría') as Fila[];
    return filas.map(aAuditoria);
  }
}

/** Construye el juego completo de repositorios sobre un cliente dado. */
export function crearRepositorios(cliente: SupabaseClient): Repositorios {
  return {
    perfiles: new PerfilesSupabase(cliente),
    modulos: new ModulosSupabase(cliente),
    parametros: new ParametrosSupabase(cliente),
    auditoria: new AuditoriaSupabase(cliente),
  };
}

/** Verificador de tokens basado en Supabase Auth. */
export function crearVerificadorDeTokens(clienteAnonimo: SupabaseClient) {
  return async function verificarToken(
    token: string,
  ): Promise<{ id: string; email: string | null } | null> {
    const { data, error } = await clienteAnonimo.auth.getUser(token);
    if (error || !data.user) return null;
    return { id: data.user.id, email: data.user.email ?? null };
  };
}
