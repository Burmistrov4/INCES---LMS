import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  OpcionesListadoAcceso,
  OpcionesListadoUsuarios,
  PaginaAcceso,
  PaginaUsuarios,
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaInvitacionesDocente,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../dominio/puertos.js';
import { ErrorApi } from '../dominio/errores.js';
import {
  esRol,
  type CambiosModulo,
  type EntradaAcceso,
  type EntradaAuditoria,
  type EstadoAcceso,
  type InvitacionDocente,
  type ModuloSistema,
  type ParametroSistema,
  type Perfil,
  type Rol,
  type TipoParametro,
} from '../dominio/tipos.js';
import { desenvolver, esRangoNoSatisfacible, traducirError } from './traducir-error.js';

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

function aInvitacion(fila: Fila): InvitacionDocente {
  return {
    id: textoObligatorio(fila.id),
    email: textoObligatorio(fila.email),
    tokenHash: textoObligatorio(fila.token_hash),
    isUsed: booleano(fila.is_used, false),
    createdAt: textoObligatorio(fila.created_at),
    expiresAt: textoObligatorio(fila.expires_at),
  };
}

function aAcceso(fila: Fila): EntradaAcceso {
  // `estado` sólo admite dos valores en el CHECK de la base; si por cualquier
  // motivo llegara otro, se degrada a SUCCESS (el más benigno) en vez de reventar
  // el mapeo. Un valor raro aquí no debe tumbar la pantalla de auditoría.
  const estado = fila.estado === 'FAILED' ? 'FAILED' : 'SUCCESS';
  return {
    id: textoObligatorio(fila.id),
    userId: texto(fila.user_id),
    email: texto(fila.email),
    ip: texto(fila.ip_address),
    estado,
    createdAt: textoObligatorio(fila.created_at),
  };
}

// --- repositorios -----------------------------------------------------------

const TABLA_PERFILES = 'profiles';
const TABLA_MODULOS = 'system_modules';
const TABLA_PARAMETROS = 'system_settings';
const TABLA_AUDITORIA = 'config_audit_log';
const TABLA_INVITACIONES = 'teacher_invitations';
const TABLA_ACCESO = 'auth_logs';

/**
 * Columnas de `profiles` que necesita el mapeador `aPerfil`.
 *
 * Se nombran una sola vez porque aparecen en tres consultas (`porId`,
 * `listar`, `cambiarRol`) y una columna que falte en una de ellas no da error
 * de tipos: `aPerfil` la leería como `undefined` y la degradaría en silencio a
 * cadena vacía. Mejor una lista y un único sitio donde equivocarse.
 */
const COLUMNAS_PERFIL = 'id, email, cedula, nombres, apellidos, rol, active';

/**
 * Convierte un texto de búsqueda en un filtro `or(...)` de PostgREST.
 *
 * Función pura y aparte porque aquí está el único riesgo real de la consulta.
 * PostgREST interpreta `,` y `()` como sintaxis de su propio filtro: un texto
 * como `Pérez, Ana` rompería el filtro —o peor, lo cambiaría sin avisar— si se
 * interpolara a lo bruto. Las comillas dobles convierten el valor en literal, y
 * una comilla doble dentro del texto se neutraliza duplicándola.
 *
 * Se comprobó contra la base real: `?busqueda=a,b` y `?busqueda=o"brien`
 * responden sin error en vez de romper la sintaxis.
 */
function filtroDeBusqueda(texto: string): string {
  const literal = `"${texto.replaceAll('"', '""')}"`;
  return [
    `nombres.ilike.${literal}`,
    `apellidos.ilike.${literal}`,
    `email.ilike.${literal}`,
    `cedula.ilike.${literal}`,
  ].join(',');
}

class PerfilesSupabase implements PuertaPerfiles {
  constructor(private readonly cliente: SupabaseClient) {}

  async porId(id: string): Promise<Perfil | null> {
    const respuesta = await this.cliente
      .from(TABLA_PERFILES)
      .select(COLUMNAS_PERFIL)
      .eq('id', id)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer perfil');
    if (!respuesta.data) return null;

    return aPerfil(respuesta.data as Fila);
  }

  async listar(opciones: OpcionesListadoUsuarios): Promise<PaginaUsuarios> {
    // El total se pide PRIMERO, y no es un lujo: es lo que hace que la petición
    // de la página nunca salga de rango. PostgREST responde 416 («Requested
    // range not satisfiable») cuando el `range()` empieza más allá de la última
    // fila, y **en ese caso no devuelve ni `data` ni `count`** — comprobado
    // contra la base real. Sin el total por adelantado, un `?desplazamiento=…`
    // que se pase un día (o la página que un cliente tenga cacheada cuando otra
    // persona borra usuarios) saldría como `500` con la petición siendo
    // perfectamente válida.
    //
    // Es una consulta `head: true` más por pantalla. Se acepta a cambio de que
    // «pedir una página de más» sea una página vacía y no un error.
    const total = await this.contarUsuarios(opciones);

    // Si el desplazamiento ya se pasó del final, no hay nada que pedir: una
    // página vacía con el total correcto es la respuesta. Se resuelve sin ir a
    // la base, porque pedirla sería justo lo que provoca el 416.
    if (opciones.desplazamiento >= total) {
      return { usuarios: [], total };
    }

    // Orden estable y con sentido para una lista de personas. El `id` desempata
    // apellidos idénticos: sin él, dos homónimos podrían intercambiar posiciones
    // entre páginas y uno saldría dos veces mientras el otro no aparece. El
    // orden lo aplica la base con SU colación (`en_US.UTF-8` en la nube, que
    // ordena «Administradora» antes que «Aguilar»), no el cliente.
    //
    // El `min` del final recorta la última página: si quedan 3 filas y se piden
    // 25, el rango termina en la última que existe y no más allá. Pedir 24
    // filas de más no es peligroso, pero sí innecesario, y deja el rango dentro
    // de los límites que la base conoce.
    const respuesta = await this.consultaDeUsuarios(opciones)
      .order('apellidos', { ascending: true })
      .order('nombres', { ascending: true })
      .order('id', { ascending: true })
      .range(
        opciones.desplazamiento,
        Math.min(opciones.desplazamiento + opciones.limite - 1, total - 1),
      );

    if (respuesta.error) {
      // Defensa en profundidad. Con el total pedido por adelantado el rango no
      // debería salirse nunca, pero entre el recuento y la página hay una
      // ventana: si otra persona borra usuarios en ese hueco, el `range()`
      // puede quedar fuera otra vez. Degradar a página vacía es mejor que un
      // `500` por una carrera que el administrador no puede ni entender.
      if (esRangoNoSatisfacible(respuesta.error)) {
        return { usuarios: [], total: await this.contarUsuarios(opciones) };
      }

      throw traducirError(respuesta.error, 'listar usuarios');
    }

    const filas = (respuesta.data ?? []) as Fila[];

    return { usuarios: filas.map(aPerfil), total };
  }

  /**
   * La consulta base de usuarios, con los tres filtros ya aplicados.
   *
   * `contar` decide si se piden filas o sólo el recuento. Se resuelve con un
   * `select` u otro, no encadenando un segundo `select`: el *builder* de
   * PostgREST sólo admite uno.
   *
   * Devuelve el *builder* del SDK tal cual, sin envolverlo en un tipo propio:
   * envolverlo obligaba a redeclarir la firma del SDK y el compilador se rendía
   * con TS2589 en cuanto se le imponía una restricción genérica.
   */
  private consultaDeUsuarios(opciones: OpcionesListadoUsuarios, contar = false) {
    let consulta = contar
      ? this.cliente.from(TABLA_PERFILES).select('id', { count: 'exact', head: true })
      : this.cliente.from(TABLA_PERFILES).select(COLUMNAS_PERFIL);

    if (opciones.rol) consulta = consulta.eq('rol', opciones.rol);
    if (opciones.activo !== undefined) consulta = consulta.eq('active', opciones.activo);
    if (opciones.busqueda) consulta = consulta.or(filtroDeBusqueda(opciones.busqueda));

    return consulta;
  }

  /**
   * Cuántos usuarios cumplen el filtro, sin traer ninguna fila.
   *
   * Se pide **antes** de la página a propósito. Ver la nota en `listar`: conocer
   * el total por adelantado es lo que permite recortar el desplazamiento y no
   * llegar nunca al 416 de PostgREST.
   */
  private async contarUsuarios(opciones: OpcionesListadoUsuarios): Promise<number> {
    // Se pide el recuento con los MISMOS filtros que la página. `head: true`
    // hace que sólo viaje la cabecera: no se transfiere ninguna fila.
    const respuesta = await this.consultaDeUsuarios(opciones, true);

    if (respuesta.error) {
      throw traducirError(respuesta.error, 'contar usuarios');
    }

    // Un recuento nulo con `count: 'exact'` no es «cero usuarios»: es que la
    // respuesta no traía la cuenta. Devolver 0 haría que la pantalla dijera
    // «no hay usuarios» mientras la base sí los tiene.
    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno(
        'La base de datos no devolvió el total de usuarios.',
      );
    }

    return respuesta.count;
  }

  async cambiarRol(id: string, rol: Rol): Promise<Perfil> {
    const respuesta = await this.cliente
      .from(TABLA_PERFILES)
      .update({ rol })
      .eq('id', id)
      .select(COLUMNAS_PERFIL)
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

class InvitacionesSupabase implements PuertaInvitacionesDocente {
  constructor(private readonly cliente: SupabaseClient) {}

  async crear(
    entrada: { email: string; tokenHash: string; expiresAt: string },
  ): Promise<InvitacionDocente> {
    const respuesta = await this.cliente
      .from(TABLA_INVITACIONES)
      .insert({
        email: entrada.email,
        token_hash: entrada.tokenHash,
        expires_at: entrada.expiresAt,
      })
      .select('*')
      .single();

    return aInvitacion(desenvolver(respuesta, 'crear invitación') as Fila);
  }

  async porTokenHash(tokenHash: string): Promise<InvitacionDocente | null> {
    const respuesta = await this.cliente
      .from(TABLA_INVITACIONES)
      .select('*')
      .eq('token_hash', tokenHash)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer invitación');
    if (!respuesta.data) return null;
    return aInvitacion(respuesta.data as Fila);
  }

  async marcarUsada(id: string): Promise<void> {
    const respuesta = await this.cliente
      .from(TABLA_INVITACIONES)
      .update({ is_used: true })
      .eq('id', id);

    if (respuesta.error) throw traducirError(respuesta.error, 'marcar invitación usada');
  }

  async crearUsuarioDocente(email: string, password: string): Promise<string> {
    // `auth.admin.createUser` usa la service_role (el cliente que viaja aquí en el
    // camino de activación). `email_confirm: true` deja la cuenta activa de una:
    // el profesor fija su contraseña en este mismo paso, no necesita otro correo.
    const { data, error } = await this.cliente.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (error) {
      // El caso más común: el correo ya tiene cuenta (se auto-registró como
      // estudiante, por ejemplo). Se dice claro en vez de un 500 crudo de GoTrue.
      if (/already/i.test(error.message)) {
        throw ErrorApi.conflicto(
          'CORREO_YA_REGISTRADO',
          'Ese correo ya tiene una cuenta en el sistema.',
        );
      }
      throw ErrorApi.interno(`No se pudo crear el usuario: ${error.message}`);
    }

    if (!data.user) {
      throw ErrorApi.interno('La creación del usuario no devolvió un identificador.');
    }

    return data.user.id;
  }
}

class AuditoriaAccesoSupabase implements PuertaAuditoriaAcceso {
  constructor(private readonly cliente: SupabaseClient) {}

  async registrar(entrada: {
    userId: string | null;
    email: string | null;
    ip: string | null;
    estado: EstadoAcceso;
  }): Promise<void> {
    const respuesta = await this.cliente.from(TABLA_ACCESO).insert({
      user_id: entrada.userId,
      email: entrada.email,
      ip_address: entrada.ip,
      estado: entrada.estado,
    });

    if (respuesta.error) throw traducirError(respuesta.error, 'registrar acceso');
  }

  async listar(opciones: OpcionesListadoAcceso): Promise<PaginaAcceso> {
    // El total se pide PRIMERO, igual que en `PerfilesSupabase.listar`: evita el
    // 416 de PostgREST cuando el `range()` empieza más allá de la última fila, y
    // permite que el panel pinte «1 a 25 de 340» sin una consulta adicional.
    const total = await this.contar(opciones);

    // Si el desplazamiento ya se pasó del final, página vacía con el total
    // correcto. Pedir la página de todos modos provocaría el 416.
    if (opciones.desplazamiento >= total) {
      return { entradas: [], total };
    }

    let consulta = this.cliente.from(TABLA_ACCESO).select('*');
    if (opciones.estado) consulta = consulta.eq('estado', opciones.estado);
    if (opciones.email) consulta = consulta.eq('email', opciones.email);
    if (opciones.userId) consulta = consulta.eq('user_id', opciones.userId);

    const respuesta = await consulta
      .order('created_at', { ascending: false })
      .range(
        opciones.desplazamiento,
        Math.min(opciones.desplazamiento + opciones.limite - 1, total - 1),
      );

    if (respuesta.error) {
      // Defensa en profundidad ante una carrera que deje el rango fuera tras el
      // recuento: mejor página vacía que un 500 por una petición válida.
      if (esRangoNoSatisfacible(respuesta.error)) {
        return { entradas: [], total: await this.contar(opciones) };
      }
      throw traducirError(respuesta.error, 'listar accesos');
    }

    const filas = (respuesta.data ?? []) as Fila[];
    return { entradas: filas.map(aAcceso), total };
  }

  /** Recuento exacto de filas que cumplen el filtro, sin traer los datos. */
  private async contar(opciones: OpcionesListadoAcceso): Promise<number> {
    let consulta = this.cliente
      .from(TABLA_ACCESO)
      .select('*', { count: 'exact', head: true });
    if (opciones.estado) consulta = consulta.eq('estado', opciones.estado);
    if (opciones.email) consulta = consulta.eq('email', opciones.email);
    if (opciones.userId) consulta = consulta.eq('user_id', opciones.userId);

    const respuesta = await consulta;
    if (respuesta.error) throw traducirError(respuesta.error, 'contar accesos');
    return respuesta.count ?? 0;
  }
}

/** Construye el juego completo de repositorios sobre un cliente dado. */
export function crearRepositorios(cliente: SupabaseClient): Repositorios {
  return {
    perfiles: new PerfilesSupabase(cliente),
    modulos: new ModulosSupabase(cliente),
    parametros: new ParametrosSupabase(cliente),
    auditoria: new AuditoriaSupabase(cliente),
    invitaciones: new InvitacionesSupabase(cliente),
    acceso: new AuditoriaAccesoSupabase(cliente),
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
