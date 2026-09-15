import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  CambiosPrograma,
  EntradaCrearMateria,
  EntradaCrearPrograma,
  OpcionesListadoAcceso,
  OpcionesListadoMaterias,
  OpcionesListadoProgramas,
  OpcionesListadoUsuarios,
  PaginaAcceso,
  PaginaMaterias,
  PaginaProgramas,
  PaginaUsuarios,
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaCurriculo,
  PuertaInvitacionesDocente,
  PuertaModulos,
  PuertaParametros,
  PuertaPerfiles,
  Repositorios,
} from '../dominio/puertos.js';
import { ErrorApi } from '../dominio/errores.js';
import {
  agruparPensum,
  esBloqueoPorPensumEnUso,
  pensumEditable,
} from '../dominio/reglas-curriculo.js';
import {
  esRol,
  esTipoPrograma,
  type CambiosModulo,
  type DetallePrograma,
  type EntradaAcceso,
  type EntradaAuditoria,
  type EntradaPensum,
  type EstadoAcceso,
  type InvitacionDocente,
  type Materia,
  type MateriaEnPensum,
  type ModuloSistema,
  type ParametroSistema,
  type Perfil,
  type Programa,
  type ProgramaConTotales,
  type Rol,
  type TipoParametro,
} from '../dominio/tipos.js';
import {
  desenvolver,
  esRangoNoSatisfacible,
  mensajeDe,
  traducirError,
} from './traducir-error.js';

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

/**
 * Programa leído de la base de datos.
 *
 * El `type` se degrada a `CURSO_LIBRE` si llegara un valor desconocido, por la
 * misma razón que el rol se degrada a `estudiante`: es el tipo que acarrea
 * **menos obligaciones** (un curso libre puede no tener pensum), así que
 * degradar nunca hace que el sistema exija de más ni que dé por buena una
 * carrera vacía. Un `throw` aquí tumbaría el listado entero por una fila rara.
 */
function aPrograma(fila: Fila): Programa {
  return {
    id: textoObligatorio(fila.id),
    codigo: textoObligatorio(fila.code),
    nombre: textoObligatorio(fila.name),
    tipo: esTipoPrograma(fila.type) ? fila.type : 'CURSO_LIBRE',
    requierePasantia: booleano(fila.requires_internship, false),
    activo: booleano(fila.is_active, false),
    creadoEn: textoObligatorio(fila.created_at),
    actualizadoEn: textoObligatorio(fila.updated_at),
  };
}

function aMateria(fila: Fila): Materia {
  return {
    id: textoObligatorio(fila.id),
    codigo: textoObligatorio(fila.code),
    nombre: textoObligatorio(fila.name),
    horasAcademicas: entero(fila.academic_hours, 0),
    creadoEn: textoObligatorio(fila.created_at),
    actualizadoEn: textoObligatorio(fila.updated_at),
  };
}

/**
 * Lee el agregado `count` que PostgREST devuelve incrustado.
 *
 * La forma es `[{ count: N }]`, y una relación **sin filas también llega como
 * `[{ count: 0 }]`** — comprobado contra la base real, no supuesto. Se acepta
 * `[]` además porque significa lo mismo y no cuesta nada; lo que no se hace es
 * tratar un valor ausente como un número: si la forma cambiara, el total que
 * vería el administrador sería cero y le diría que un programa está vacío
 * cuando no lo está.
 */
function contarIncrustado(valor: unknown): number {
  if (!Array.isArray(valor)) return 0;
  const primero = valor[0] as Fila | undefined;
  if (!primero) return 0;
  return entero(primero.count, 0);
}

/** Cuántos períodos distintos cubre un pensum, a partir de las filas incrustadas. */
function periodosDistintos(valor: unknown): number {
  if (!Array.isArray(valor)) return 0;
  const periodos = new Set<number>();
  for (const fila of valor as Fila[]) {
    const periodo = fila.period_order;
    if (typeof periodo === 'number' && Number.isFinite(periodo)) periodos.add(periodo);
  }
  return periodos.size;
}

function aProgramaConTotales(fila: Fila): ProgramaConTotales {
  return {
    ...aPrograma(fila),
    totalMaterias: contarIncrustado(fila.total),
    totalPeriodos: periodosDistintos(fila.periodos),
  };
}

// --- repositorios -----------------------------------------------------------

const TABLA_PERFILES = 'profiles';
const TABLA_MODULOS = 'system_modules';
const TABLA_PARAMETROS = 'system_settings';
const TABLA_AUDITORIA = 'config_audit_log';
const TABLA_INVITACIONES = 'teacher_invitations';
const TABLA_ACCESO = 'auth_logs';
const TABLA_PROGRAMAS = 'programs';
const TABLA_MATERIAS = 'subjects';
const TABLA_PENSUM = 'program_subjects';
const TABLA_SECCIONES = 'sections';

/** Clave del parámetro que dice cuál es el período académico vigente. */
const CLAVE_PERIODO_ACTIVO = 'periodo_activo';

/**
 * Columnas de `programs` que necesita `aPrograma`. Se nombran una sola vez por
 * la misma razón que `COLUMNAS_PERFIL`: aparecen en cuatro consultas y una
 * columna que falte en una de ellas no da error de tipos, se degrada en
 * silencio a cadena vacía.
 */
const COLUMNAS_PROGRAMA =
  'id,code,name,type,requires_internship,is_active,created_at,updated_at';

const COLUMNAS_MATERIA = 'id,code,name,academic_hours,created_at,updated_at';

/**
 * Columnas del listado de programas, con los dos totales incrustados.
 *
 * Los alias (`total:`, `periodos:`) **no son cosmética**: sin ellos, incrustar
 * dos veces la misma relación en un `select` de PostgREST falla con
 * `42803 aggregate functions are not allowed in FROM clause of their own query
 * level`. Con alias, las dos conviven y los dos totales llegan en la misma
 * consulta que la página, sin N+1. Comprobado contra la base real el 2026-09-15.
 *
 * `count` es el agregado del lado del servidor (`[{count: N}]`), así que
 * `totalMaterias` no cuesta ni una fila de payload. `periodos` sí trae una fila
 * por materia del pensum —hace falta para contarlos distintos, porque
 * PostgREST **no admite** `count(distinct)`: `program_subjects.period_order
 * .count()` responde `PGRST100`— y por eso se pide la columna suelta y no `*`.
 */
const SELECT_LISTADO_PROGRAMA =
  `${COLUMNAS_PROGRAMA},` +
  'total:program_subjects(count),periodos:program_subjects(period_order)';

/** Columnas de búsqueda del catálogo de programas y del banco de materias. */
const COLUMNAS_BUSQUEDA_CATALOGO = ['code', 'name'];

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
 * Convierte un texto de búsqueda en el cuerpo de un filtro `or(...)` de
 * PostgREST sobre una o varias columnas.
 *
 * **Sin paréntesis, a propósito.** `supabase-js` ya envuelve el valor:
 * `.or(filtros)` hace `searchParams.append('or', `(${filtros})`)`. Añadirlos
 * aquí produciría `or=((…))` y PostgREST respondería `PGRST100 unexpected "("`.
 * Se comprobó contra la base real: la forma doblada falla y esta no.
 *
 * Función pura y aparte porque aquí está el único riesgo real de estas
 * consultas. PostgREST interpreta `,`, `()` y `"` como sintaxis de su propio
 * filtro: un texto como `Pérez, Ana` rompería el filtro —o peor, lo cambiaría
 * sin avisar— si se interpolara a lo bruto. Las comillas dobles convierten el
 * valor en literal, y una comilla doble dentro del texto se neutraliza
 * duplicándola.
 *
 * Comprobado contra la base real con textos que contienen coma, comilla doble y
 * paréntesis: los tres responden 200 en vez de romper la sintaxis.
 */
function filtroIlike(columnas: readonly string[], texto: string): string {
  const literal = `"${texto.replaceAll('"', '""')}"`;
  return columnas.map((columna) => `${columna}.ilike.${literal}`).join(',');
}

/** Columnas de `profiles` que cubre la búsqueda del listado de usuarios. */
const COLUMNAS_BUSQUEDA_PERFIL = ['nombres', 'apellidos', 'email', 'cedula'];

function filtroDeBusqueda(texto: string): string {
  return filtroIlike(COLUMNAS_BUSQUEDA_PERFIL, texto);
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

/**
 * Currículo y pensum (Módulo 2).
 *
 * **Las dos escrituras van por función, no por `insert`.** PostgREST no admite
 * insertar un padre con sus hijos en la misma petición ni expone transacciones
 * entre peticiones, y el contrato pide que el asistente sea atómico. Se
 * comprobó contra la base real (ver el encabezado de
 * `supabase/migrations/202609170001_mod2_rpc_curriculo.sql`): un
 * `POST /programs` con `program_subjects: [...]` responde `PGRST204`, y el
 * error es idéntico tras recargar la caché de esquema. Las lecturas y el
 * `PATCH` de metadatos sí van por PostgREST normal: no necesitan atomicidad.
 *
 * Este repositorio **nunca** hace un `insert` sobre `programs` ni sobre
 * `program_subjects`. Si lo hiciera, se saltaría la atomicidad que las
 * funciones existen para dar, y el fallo aparecería como un programa a medio
 * armar en la base, no como un test en rojo.
 */
class CurriculoSupabase implements PuertaCurriculo {
  constructor(private readonly cliente: SupabaseClient) {}

  // --- Programas ------------------------------------------------------------

  async listarProgramas(opciones: OpcionesListadoProgramas): Promise<PaginaProgramas> {
    // El total primero, como en `PerfilesSupabase.listar`: es lo que permite
    // recortar el rango y no llegar nunca al 416 de PostgREST, y lo que deja
    // que la pantalla diga «1 a 25 de 12».
    const total = await this.contarProgramas(opciones);

    if (opciones.desplazamiento >= total) {
      return { programas: [], total };
    }

    const respuesta = await this.consultaDeProgramas(opciones)
      .order('name', { ascending: true })
      .order('id', { ascending: true })
      .range(
        opciones.desplazamiento,
        Math.min(opciones.desplazamiento + opciones.limite - 1, total - 1),
      );

    if (respuesta.error) {
      // Defensa en profundidad ante una carrera entre el recuento y la página.
      if (esRangoNoSatisfacible(respuesta.error)) {
        return { programas: [], total: await this.contarProgramas(opciones) };
      }
      throw traducirError(respuesta.error, 'listar programas');
    }

    const filas = (respuesta.data ?? []) as Fila[];
    return { programas: filas.map(aProgramaConTotales), total };
  }

  /**
   * La consulta base del listado, con los filtros ya aplicados.
   *
   * `contar` decide si se piden filas o sólo el recuento. Se resuelve con un
   * `select` u otro, no encadenando un segundo `select`: el *builder* de
   * PostgREST sólo admite uno.
   */
  private consultaDeProgramas(opciones: OpcionesListadoProgramas, contar = false) {
    let consulta = contar
      ? this.cliente.from(TABLA_PROGRAMAS).select('id', { count: 'exact', head: true })
      : this.cliente.from(TABLA_PROGRAMAS).select(SELECT_LISTADO_PROGRAMA);

    if (opciones.tipo) consulta = consulta.eq('type', opciones.tipo);
    if (opciones.activo !== undefined) consulta = consulta.eq('is_active', opciones.activo);
    if (opciones.busqueda) {
      consulta = consulta.or(filtroIlike(COLUMNAS_BUSQUEDA_CATALOGO, opciones.busqueda));
    }

    return consulta;
  }

  private async contarProgramas(opciones: OpcionesListadoProgramas): Promise<number> {
    const respuesta = await this.consultaDeProgramas(opciones, true);

    if (respuesta.error) {
      throw traducirError(respuesta.error, 'contar programas');
    }

    // Un recuento nulo con `count: 'exact'` no es «cero programas»: es que la
    // respuesta no traía la cuenta. Devolver 0 haría que la pantalla dijera que
    // no hay oferta formativa mientras la base sí la tiene.
    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno('La base de datos no devolvió el total de programas.');
    }

    return respuesta.count;
  }

  async detallePrograma(id: string): Promise<DetallePrograma | null> {
    const respuesta = await this.cliente
      .from(TABLA_PROGRAMAS)
      .select(COLUMNAS_PROGRAMA)
      .eq('id', id)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer programa');
    if (!respuesta.data) return null;

    return this.armarDetalle(aPrograma(respuesta.data as Fila));
  }

  async crearPrograma(entrada: EntradaCrearPrograma): Promise<DetallePrograma> {
    // Los nombres de los argumentos (`p_code`, `p_pensum`, …) son los de la
    // función en PostgreSQL y no se pueden renombrar desde aquí: PostgREST los
    // resuelve por nombre. `p_pensum` viaja como JSON con la forma
    // `[{materiaId, periodo}]`, que es lo que la función recorre con
    // `jsonb_array_elements`.
    const respuesta = await this.cliente.rpc('crear_programa_con_pensum', {
      p_code: entrada.codigo,
      p_name: entrada.nombre,
      p_type: entrada.tipo,
      p_requires_internship: entrada.requierePasantia,
      p_publicar: entrada.publicar,
      p_pensum: entrada.pensum,
    });

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'crear programa');

    const id = texto(respuesta.data);
    if (!id) {
      throw ErrorApi.interno('La creación del programa no devolvió un identificador.');
    }

    return this.detalleObligatorio(id);
  }

  async actualizarPrograma(id: string, cambios: CambiosPrograma): Promise<Programa> {
    const parche: Record<string, unknown> = {};
    if (cambios.nombre !== undefined) parche.name = cambios.nombre;
    if (cambios.requierePasantia !== undefined) {
      parche.requires_internship = cambios.requierePasantia;
    }
    if (cambios.activo !== undefined) parche.is_active = cambios.activo;

    if (Object.keys(parche).length === 0) {
      throw ErrorApi.peticionInvalida('No se indicó ningún cambio para el programa.');
    }

    const respuesta = await this.cliente
      .from(TABLA_PROGRAMAS)
      .update(parche)
      .eq('id', id)
      .select(COLUMNAS_PROGRAMA)
      .single();

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'actualizar programa');
    return aPrograma(respuesta.data as Fila);
  }

  async reemplazarPensum(id: string, pensum: EntradaPensum[]): Promise<DetallePrograma> {
    const respuesta = await this.cliente.rpc('reemplazar_pensum', {
      p_program_id: id,
      p_pensum: pensum,
    });

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'reemplazar pensum');

    return this.detalleObligatorio(id);
  }

  // --- Materias -------------------------------------------------------------

  async listarMaterias(opciones: OpcionesListadoMaterias): Promise<PaginaMaterias> {
    const total = await this.contarMaterias(opciones);

    if (opciones.desplazamiento >= total) {
      return { materias: [], total };
    }

    const respuesta = await this.consultaDeMaterias(opciones)
      .order('name', { ascending: true })
      .order('id', { ascending: true })
      .range(
        opciones.desplazamiento,
        Math.min(opciones.desplazamiento + opciones.limite - 1, total - 1),
      );

    if (respuesta.error) {
      if (esRangoNoSatisfacible(respuesta.error)) {
        return { materias: [], total: await this.contarMaterias(opciones) };
      }
      throw traducirError(respuesta.error, 'listar materias');
    }

    const filas = (respuesta.data ?? []) as Fila[];
    return { materias: filas.map(aMateria), total };
  }

  private consultaDeMaterias(opciones: OpcionesListadoMaterias, contar = false) {
    let consulta = contar
      ? this.cliente.from(TABLA_MATERIAS).select('id', { count: 'exact', head: true })
      : this.cliente.from(TABLA_MATERIAS).select(COLUMNAS_MATERIA);

    if (opciones.busqueda) {
      consulta = consulta.or(filtroIlike(COLUMNAS_BUSQUEDA_CATALOGO, opciones.busqueda));
    }

    return consulta;
  }

  private async contarMaterias(opciones: OpcionesListadoMaterias): Promise<number> {
    const respuesta = await this.consultaDeMaterias(opciones, true);

    if (respuesta.error) throw traducirError(respuesta.error, 'contar materias');

    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno('La base de datos no devolvió el total de materias.');
    }

    return respuesta.count;
  }

  async crearMateria(entrada: EntradaCrearMateria): Promise<Materia> {
    const respuesta = await this.cliente
      .from(TABLA_MATERIAS)
      .insert({
        code: entrada.codigo,
        name: entrada.nombre,
        academic_hours: entrada.horasAcademicas,
      })
      .select(COLUMNAS_MATERIA)
      .single();

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'crear materia');
    return aMateria(respuesta.data as Fila);
  }

  // --- Piezas internas ------------------------------------------------------

  /** Arma el detalle a partir del programa ya leído. */
  private async armarDetalle(programa: Programa): Promise<DetallePrograma> {
    const pensum = await this.leerPensum(programa.id);
    const seccionesActivas = await this.contarSeccionesActivas(programa.id);

    return {
      programa,
      pensum: agruparPensum(pensum),
      seccionesActivas,
      // La decisión no se toma aquí: se delega en la regla pura, que se prueba
      // sin base de datos. El repositorio sólo aporta el número.
      editable: pensumEditable(seccionesActivas),
    };
  }

  /**
   * El pensum con los datos de cada materia, en una sola consulta.
   *
   * La incrustación de dos niveles (`program_subjects → subjects`) es lectura
   * anidada, que PostgREST sí admite —a diferencia de la escritura anidada—.
   * Sin ella, pintar el pensum exigiría una consulta por materia.
   */
  private async leerPensum(programId: string): Promise<MateriaEnPensum[]> {
    const respuesta = await this.cliente
      .from(TABLA_PENSUM)
      .select('period_order,subjects(id,code,name,academic_hours)')
      .eq('program_id', programId)
      .order('period_order', { ascending: true });

    const filas = desenvolver(respuesta, 'leer pensum') as Fila[];

    return filas.map((fila) => {
      const materia = (fila.subjects ?? {}) as Fila;
      return {
        materiaId: textoObligatorio(materia.id),
        periodo: entero(fila.period_order, 1),
        codigo: textoObligatorio(materia.code),
        nombre: textoObligatorio(materia.name),
        horasAcademicas: entero(materia.academic_hours, 0),
      };
    });
  }

  /**
   * Secciones activas del período vigente que usan este programa.
   *
   * Es el dato que decide la Regla 2. Se cuenta con `head: true` porque sólo
   * hace falta el número, no quiénes son.
   *
   * Sin período vigente declarado devuelve 0, y es coherente: el trigger de la
   * Regla 2 **falla abierto** cuando falta el parámetro, así que tampoco
   * bloquearía nada. Devolver un número inventado aquí haría que la UI
   * deshabilitara el reordenamiento por una guarda que no existe.
   */
  private async contarSeccionesActivas(programId: string): Promise<number> {
    const periodo = await this.leerPeriodoActivo();
    if (!periodo) return 0;

    const respuesta = await this.cliente
      .from(TABLA_SECCIONES)
      .select('id', { count: 'exact', head: true })
      .eq('program_id', programId)
      .eq('is_active', true)
      .eq('period_code', periodo);

    if (respuesta.error) throw traducirError(respuesta.error, 'contar secciones activas');

    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno(
        'La base de datos no devolvió el número de secciones activas.',
      );
    }

    return respuesta.count;
  }

  private async leerPeriodoActivo(): Promise<string | null> {
    const respuesta = await this.cliente
      .from(TABLA_PARAMETROS)
      .select('valor')
      .eq('clave', CLAVE_PERIODO_ACTIVO)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer el período vigente');
    if (!respuesta.data) return null;

    // `valor` es jsonb: un período guardado como número devolvería `2026`, no
    // `"2026"`. Se acepta sólo texto porque la comparación de la Regla 2 es por
    // igualdad exacta de cadena, y `2026 !== '2026'` haría que la guarda no
    // disparara nunca sin avisar.
    return texto((respuesta.data as Fila).valor);
  }

  /**
   * Detalle de un programa que se acaba de escribir.
   *
   * Si la escritura devolvió un `id`, el programa existe: un `null` aquí sería
   * una violación de invariante, no un caso a contemplar. Se falla ruidosamente
   * en vez de devolver un cuerpo vacío que el cliente tendría que interpretar.
   */
  private async detalleObligatorio(id: string): Promise<DetallePrograma> {
    const detalle = await this.detallePrograma(id);
    if (!detalle) {
      throw ErrorApi.interno(
        'El programa se guardó pero no se pudo volver a leer. Revisa los permisos de la tabla.',
      );
    }
    return detalle;
  }

  /**
   * Traduce un fallo de escritura, distinguiendo la **Regla 2** de la Regla 1.
   *
   * Los dos triggers de M2 lanzan el mismo código, `23514`, así que
   * `traducirError` los convierte a los dos en un `400 RESTRICCION_VIOLADA`.
   * Para la Regla 1 es correcto: los datos no cumplen una regla del sistema.
   * Para la Regla 2 no: la petición no tiene nada inválido, hay un **conflicto
   * con el estado actual** —existen secciones activas del período vigente— y
   * eso es un `409`. El cliente necesita la distinción para ofrecer «archiva
   * esas secciones primero» en vez de un error genérico.
   *
   * Se distinguen por el texto del trigger porque cambiar el código de error
   * habría exigido una migración nueva sobre triggers ya aplicados, y una
   * migración aplicada no se edita nunca. Si el texto cambiara y la detección
   * fallara, el peor caso es un `400` en vez de un `409`: **la operación se
   * sigue bloqueando**, porque la invariante la impone el trigger, no esto.
   */
  private traducirEscritura(error: unknown, contexto: string): ErrorApi {
    if (esBloqueoPorPensumEnUso(mensajeDe(error))) {
      return ErrorApi.conflicto(
        'PENSUM_EN_USO',
        'No se puede modificar el pensum: el programa ya tiene secciones activas ' +
          'en el período vigente. Archive esas secciones primero, o clone el programa ' +
          'y cree una versión nueva del pensum.',
        { contexto },
      );
    }

    return traducirError(error, contexto);
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
    curriculo: new CurriculoSupabase(cliente),
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
