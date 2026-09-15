import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  CambiosAula,
  CambiosClase,
  CambiosGuardia,
  CambiosPeriodo,
  CambiosPrograma,
  EntradaCrearAula,
  EntradaCrearClase,
  EntradaCrearGuardia,
  EntradaCrearMateria,
  EntradaCrearPeriodo,
  EntradaCrearPrograma,
  OpcionesListadoAcceso,
  OpcionesListadoAulas,
  OpcionesListadoGuardias,
  OpcionesListadoMaterias,
  OpcionesListadoProgramas,
  OpcionesListadoUsuarios,
  OpcionesRejilla,
  PaginaAcceso,
  PaginaAulas,
  PaginaGuardias,
  PaginaMaterias,
  PaginaProgramas,
  PaginaUsuarios,
  PuertaAuditoria,
  PuertaAuditoriaAcceso,
  PuertaCuadrante,
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
import { esChoqueDeAgenda, turnoDeBloque } from '../dominio/reglas-cuadrante.js';
import {
  esRol,
  esTipoPrograma,
  esTurno,
  type Aula,
  type CambiosModulo,
  type ClaseCuadrante,
  type DetallePrograma,
  type DocenteResumen,
  type EntradaAcceso,
  type EntradaAuditoria,
  type EntradaPensum,
  type EstadoAcceso,
  type Guardia,
  type InvitacionDocente,
  type Materia,
  type MateriaEnPensum,
  type MiHorario,
  type ModuloSistema,
  type ParametroSistema,
  type Perfil,
  type Periodo,
  type Programa,
  type ProgramaConTotales,
  type RejillaCuadrante,
  type Rol,
  type RolDeHorario,
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

/**
 * Turno leído de la base.
 *
 * `turno` es una columna generada, así que la base siempre devuelve `MAÑANA` o
 * `TARDE` y esto no debería degradar nunca. Se degrada igualmente, y **se
 * recalcula a partir del bloque** en vez de caer a un valor fijo: si algún día
 * la columna cambiara de forma, un turno recalculado sigue siendo coherente con
 * el bloque que lo produjo, mientras que un `'MAÑANA'` fijo mentiría en todos
 * los bloques de la tarde. Misma razón que `rolSeguro` y `aPrograma`.
 */
function turnoSeguro(valor: unknown, bloque: number): Guardia['turno'] {
  return esTurno(valor) ? valor : turnoDeBloque(bloque);
}

function aAula(fila: Fila): Aula {
  return {
    id: textoObligatorio(fila.id),
    nombre: textoObligatorio(fila.name),
    capacidad: entero(fila.capacity, 0),
    esTaller: booleano(fila.is_workshop, false),
    activa: booleano(fila.is_active, true),
    creadoEn: textoObligatorio(fila.created_at),
    actualizadoEn: textoObligatorio(fila.updated_at),
  };
}

/**
 * Período leído de la base, con `vigente` resuelto contra el código en curso.
 *
 * `vigente` **no es una columna**: sale de comparar `code` con
 * `system_settings.periodo_activo`. Se recibe ya resuelto en vez de leerlo aquí
 * para que una lista de veinte lapsos no dispare veinte consultas al parámetro.
 */
function aPeriodo(fila: Fila, codigoVigente: string | null): Periodo {
  const codigo = textoObligatorio(fila.code);
  return {
    id: textoObligatorio(fila.id),
    codigo,
    nombre: texto(fila.name),
    fechaInicio: texto(fila.start_date),
    fechaFin: texto(fila.end_date),
    activo: booleano(fila.is_active, false),
    vigente: codigoVigente !== null && codigo === codigoVigente,
    creadoEn: textoObligatorio(fila.created_at),
    actualizadoEn: textoObligatorio(fila.updated_at),
  };
}

function aGuardia(fila: Fila): Guardia {
  const bloque = entero(fila.block, 1);
  return {
    id: textoObligatorio(fila.id),
    docenteId: textoObligatorio(fila.teacher_id),
    aulaId: textoObligatorio(fila.classroom_id),
    periodo: textoObligatorio(fila.period_code),
    dia: entero(fila.day_of_week, 1),
    bloque,
    turno: turnoSeguro(fila.turno, bloque),
    notas: texto(fila.notes),
    activa: booleano(fila.is_active, true),
    creadoEn: textoObligatorio(fila.created_at),
    actualizadoEn: textoObligatorio(fila.updated_at),
  };
}

/**
 * Clase del cuadrante, leída de `v_cuadrante_clases`.
 *
 * La vista ya trae los nombres resueltos: la materia, el nombre de la sección,
 * el del aula y el del docente. El del docente lo resuelve la vista con
 * `nombre_para_mostrar()`, no un `join` contra `profiles`, porque para un
 * estudiante la política `profiles_read_own` haría que el `join` devolviera
 * `NULL` y el horario saldría sin profesor.
 */
function aClaseCuadrante(fila: Fila): ClaseCuadrante {
  const bloque = entero(fila.block, 1);
  return {
    id: textoObligatorio(fila.id),
    seccionId: textoObligatorio(fila.section_id),
    docenteId: textoObligatorio(fila.teacher_id),
    aulaId: textoObligatorio(fila.classroom_id),
    dia: entero(fila.day_of_week, 1),
    bloque,
    turno: turnoSeguro(fila.turno, bloque),
    activa: booleano(fila.is_active, true),
    periodo: textoObligatorio(fila.period_code),
    programaId: textoObligatorio(fila.program_id),
    programa: textoObligatorio(fila.program_name),
    materiaId: textoObligatorio(fila.subject_id),
    materia: textoObligatorio(fila.subject_name),
    seccion: textoObligatorio(fila.section_name),
    aula: textoObligatorio(fila.classroom_name),
    docente: textoObligatorio(fila.teacher_name),
  };
}

function aDocenteResumen(fila: Fila): DocenteResumen {
  const nombre = [textoObligatorio(fila.nombres), textoObligatorio(fila.apellidos)]
    .filter((parte) => parte.length > 0)
    .join(' ');
  return { id: textoObligatorio(fila.id), nombre };
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

// --- M3 ---------------------------------------------------------------------

const TABLA_AULAS = 'classrooms';
const TABLA_PERIODOS = 'academic_periods';
const TABLA_GUARDIAS = 'teacher_duties';
const TABLA_CUADRANTE = 'schedule_slots';

/** La vista que resuelve los nombres de una clase sin abrir `profiles`. */
const VISTA_CLASES = 'v_cuadrante_clases';

/** Clave del parámetro que dice cuál es el período académico vigente. */
const CLAVE_PERIODO_ACTIVO = 'periodo_activo';

/**
 * Columnas de cada tabla de M3 que necesita su mapeador.
 *
 * Se nombran una sola vez por la misma razón que `COLUMNAS_PERFIL`: aparecen en
 * varias consultas —la página, el `insert`, el `update`— y una columna que falte
 * en una de ellas no da error de tipos, se degrada en silencio a cadena vacía.
 * Mejor una lista y un único sitio donde equivocarse.
 */
const COLUMNAS_AULA = 'id,name,capacity,is_workshop,is_active,created_at,updated_at';

const COLUMNAS_PERIODO =
  'id,code,name,start_date,end_date,is_active,created_at,updated_at';

/**
 * `turno` va en la lista aunque sea una columna generada.
 *
 * Se podría recalcular desde `block` y ahorrarse la columna, pero leerla es lo
 * que garantiza que el backend y la base dicen lo mismo: si el corte entre
 * turnos cambiara en `turno_de_bloque()` y aquí se recalculase con una copia, el
 * desacuerdo no se vería. `turnoSeguro` recae en el cálculo sólo si la columna
 * llegara con una forma inesperada.
 */
const COLUMNAS_GUARDIA =
  'id,teacher_id,classroom_id,period_code,day_of_week,block,turno,notes,is_active,created_at,updated_at';

/**
 * Las columnas de `v_cuadrante_clases` que consume `aClaseCuadrante`.
 *
 * Va en **una sola línea y sin concatenar** a propósito. El SDK de Supabase
 * deduce el tipo de la respuesta a partir del literal del `select`, y con una
 * cadena construida con `+` el tipo se degrada a un error genérico: el
 * compilador deja de poder comprobar las conversiones y hay que forzarlas. Con
 * el literal entero, el `select` conserva su forma y los `as Fila` del
 * repositorio siguen siendo comprobables.
 */
const COLUMNAS_CLASE =
  'id,period_code,program_id,program_name,subject_id,subject_name,section_id,section_name,teacher_id,teacher_name,classroom_id,classroom_name,day_of_week,block,turno,is_active';

/** Columnas de `profiles` que bastan para pintar una fila de la rejilla. */
const COLUMNAS_DOCENTE_RESUMEN = 'id,nombres,apellidos';

/** Roles que pueden aparecer como docente en la rejilla. */
const ROLES_DOCENTES: readonly Rol[] = ['docente', 'admin'];

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

/** Códigos de «no existe» por recurso, para no repetir literales sueltos. */
type Recurso = { codigo: string; mensaje: string };

const RECURSO_AULA: Recurso = {
  codigo: 'AULA_INEXISTENTE',
  mensaje: 'Ese espacio no existe.',
};

const RECURSO_PERIODO: Recurso = {
  codigo: 'PERIODO_INEXISTENTE',
  mensaje: 'Ese lapso no existe.',
};

const RECURSO_GUARDIA: Recurso = {
  codigo: 'GUARDIA_INEXISTENTE',
  mensaje: 'Esa guardia no existe.',
};

const RECURSO_CLASE: Recurso = {
  codigo: 'CLASE_INEXISTENTE',
  mensaje: 'Esa clase no existe en el cuadrante.',
};

/**
 * Cuadrante, aulas y guardias (Módulo 3).
 *
 * **Aquí no hay ninguna función de base de datos.** A diferencia de
 * `CurriculoSupabase`, cada escritura de M3 es una fila en una tabla: no hay
 * agregado que crear de golpe y PostgREST basta. Las dos escrituras que
 * necesitan atomicidad en M2 —crear un programa con su pensum y reemplazarlo—
 * existen porque PostgREST no admite insertar un padre con sus hijos; aquí no
 * hay hijos.
 *
 * Lo que sí vive en la base es la **guarda anti-colisión**. El repositorio no
 * pregunta «¿está libre?» antes de escribir: preguntar y luego escribir es una
 * carrera, y la respuesta buena la da la propia escritura a través del trigger.
 * El único trabajo de esta capa con esa guarda es **traducirla**: un `23514`
 * cuyo mensaje habla de un docente o un espacio ocupado no es una restricción
 * violada, es un `409 CHOQUE_DE_AGENDA`.
 */
class CuadranteSupabase implements PuertaCuadrante {
  constructor(private readonly cliente: SupabaseClient) {}

  // --- Aulas ----------------------------------------------------------------

  async listarAulas(opciones: OpcionesListadoAulas): Promise<PaginaAulas> {
    // El total primero, como en todo el proyecto: es lo que permite recortar el
    // rango y no llegar nunca al 416 de PostgREST, y lo que deja que la pantalla
    // diga «1 a 25 de 9» sin una consulta de más.
    const total = await this.contarAulas(opciones);

    if (opciones.desplazamiento >= total) {
      return { aulas: [], total };
    }

    const respuesta = await this.consultaDeAulas(opciones)
      .order('name', { ascending: true })
      .order('id', { ascending: true })
      .range(
        opciones.desplazamiento,
        Math.min(opciones.desplazamiento + opciones.limite - 1, total - 1),
      );

    if (respuesta.error) {
      // Defensa en profundidad ante una carrera entre el recuento y la página.
      if (esRangoNoSatisfacible(respuesta.error)) {
        return { aulas: [], total: await this.contarAulas(opciones) };
      }
      throw traducirError(respuesta.error, 'listar aulas');
    }

    const filas = (respuesta.data ?? []) as Fila[];
    return { aulas: filas.map(aAula), total };
  }

  /**
   * La consulta base del listado de aulas, con los filtros ya aplicados.
   *
   * El filtro `tipo` se traduce a las dos columnas que lo componen. Las tres
   * formas son excluyentes y cubren todos los casos, así que ninguna aula se
   * queda fuera del listado sin que el filtro lo diga.
   */
  private consultaDeAulas(opciones: OpcionesListadoAulas, contar = false) {
    let consulta = contar
      ? this.cliente.from(TABLA_AULAS).select('id', { count: 'exact', head: true })
      : this.cliente.from(TABLA_AULAS).select(COLUMNAS_AULA);

    if (opciones.tipo === 'TALLER') {
      consulta = consulta.eq('is_workshop', true);
    }
    if (opciones.tipo === 'ZONA') {
      consulta = consulta.eq('is_workshop', false).eq('capacity', 0);
    }
    if (opciones.tipo === 'AULA') {
      consulta = consulta.eq('is_workshop', false).gt('capacity', 0);
    }

    if (opciones.activa !== undefined) consulta = consulta.eq('is_active', opciones.activa);
    if (opciones.busqueda) consulta = consulta.or(filtroIlike(['name'], opciones.busqueda));

    return consulta;
  }

  private async contarAulas(opciones: OpcionesListadoAulas): Promise<number> {
    const respuesta = await this.consultaDeAulas(opciones, true);

    if (respuesta.error) throw traducirError(respuesta.error, 'contar aulas');

    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno('La base de datos no devolvió el total de espacios.');
    }

    return respuesta.count;
  }

  async crearAula(entrada: EntradaCrearAula): Promise<Aula> {
    const respuesta = await this.cliente
      .from(TABLA_AULAS)
      .insert({
        name: entrada.nombre,
        capacity: entrada.capacidad,
        is_workshop: entrada.esTaller,
      })
      .select(COLUMNAS_AULA)
      .single();

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'crear aula');
    return aAula(respuesta.data as Fila);
  }

  async actualizarAula(id: string, cambios: CambiosAula): Promise<Aula> {
    const parche: Record<string, unknown> = {};
    if (cambios.nombre !== undefined) parche.name = cambios.nombre;
    if (cambios.capacidad !== undefined) parche.capacity = cambios.capacidad;
    if (cambios.esTaller !== undefined) parche.is_workshop = cambios.esTaller;
    if (cambios.activa !== undefined) parche.is_active = cambios.activa;

    if (Object.keys(parche).length === 0) {
      throw ErrorApi.peticionInvalida('No se indicó ningún cambio para el espacio.');
    }

    const respuesta = await this.cliente
      .from(TABLA_AULAS)
      .update(parche)
      .eq('id', id)
      .select(COLUMNAS_AULA)
      .single();

    if (respuesta.error) {
      throw this.traducirEscritura(respuesta.error, 'actualizar aula', RECURSO_AULA);
    }

    return aAula(respuesta.data as Fila);
  }

  // --- Períodos -------------------------------------------------------------

  async listarPeriodos(): Promise<Periodo[]> {
    const vigente = await this.leerPeriodoVigente();

    // Descendente: el lapso más reciente arriba es el que se está usando. El
    // vigente se marca igualmente con `vigente`, así que el orden es comodidad
    // y no información.
    const respuesta = await this.cliente
      .from(TABLA_PERIODOS)
      .select(COLUMNAS_PERIODO)
      .order('code', { ascending: false });

    const filas = desenvolver(respuesta, 'listar períodos') as Fila[];
    return filas.map((fila) => aPeriodo(fila, vigente));
  }

  async crearPeriodo(entrada: EntradaCrearPeriodo): Promise<Periodo> {
    const respuesta = await this.cliente
      .from(TABLA_PERIODOS)
      .insert({
        code: entrada.codigo,
        name: entrada.nombre,
        start_date: entrada.fechaInicio,
        end_date: entrada.fechaFin,
      })
      .select(COLUMNAS_PERIODO)
      .single();

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'crear período');

    // Un lapso recién creado **nunca** es el vigente, y no hace falta
    // preguntarlo: el trigger `exigir_periodo_registrado()` garantiza que
    // `periodo_activo` nombra un lapso que ya existe, así que insertar su código
    // chocaría antes con el `unique` y saldría como 409. Preguntarlo costaría
    // una consulta para confirmar algo que la base ya garantiza.
    return aPeriodo(respuesta.data as Fila, null);
  }

  async actualizarPeriodo(id: string, cambios: CambiosPeriodo): Promise<Periodo> {
    const parche: Record<string, unknown> = {};
    if (cambios.nombre !== undefined) parche.name = cambios.nombre;
    if (cambios.fechaInicio !== undefined) parche.start_date = cambios.fechaInicio;
    if (cambios.fechaFin !== undefined) parche.end_date = cambios.fechaFin;
    if (cambios.activo !== undefined) parche.is_active = cambios.activo;

    if (Object.keys(parche).length === 0) {
      throw ErrorApi.peticionInvalida('No se indicó ningún cambio para el lapso.');
    }

    const respuesta = await this.cliente
      .from(TABLA_PERIODOS)
      .update(parche)
      .eq('id', id)
      .select(COLUMNAS_PERIODO)
      .single();

    if (respuesta.error) {
      throw this.traducirEscritura(respuesta.error, 'actualizar período', RECURSO_PERIODO);
    }

    // Aquí sí hay que leer el vigente: el código del lapso no cambia, así que su
    // condición de vigente tampoco, pero no viaja en la fila.
    return aPeriodo(respuesta.data as Fila, await this.leerPeriodoVigente());
  }

  async declararPeriodoVigente(id: string): Promise<Periodo> {
    // Se lee primero porque hace falta el `code`: `periodo_activo` guarda el
    // código, no el id, y es el código lo que citan las secciones.
    const periodo = await this.periodoPorId(id);
    if (!periodo) {
      throw ErrorApi.noEncontrado(RECURSO_PERIODO.codigo, RECURSO_PERIODO.mensaje);
    }

    const respuesta = await this.cliente
      .from(TABLA_PARAMETROS)
      .update({ valor: periodo.codigo })
      .eq('clave', CLAVE_PERIODO_ACTIVO)
      .select('clave')
      .maybeSingle();

    if (respuesta.error) {
      throw this.traducirEscritura(respuesta.error, 'declarar el período vigente');
    }

    // Sin la fila del parámetro no hay dónde escribir. No es un 404 del cliente:
    // es que falta una migración, y decirlo así ahorra una tarde de búsqueda.
    if (!respuesta.data) {
      throw ErrorApi.interno(
        'No existe el parámetro "periodo_activo". Aplica las migraciones del sistema.',
      );
    }

    return { ...periodo, vigente: true };
  }

  /** El código del lapso vigente, o `null` si no hay ninguno declarado. */
  private async leerPeriodoVigente(): Promise<string | null> {
    const respuesta = await this.cliente
      .from(TABLA_PARAMETROS)
      .select('valor')
      .eq('clave', CLAVE_PERIODO_ACTIVO)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer el período vigente');
    if (!respuesta.data) return null;

    // `valor` es jsonb: un lapso guardado como número devolvería `2026`, no
    // `"2026"`. Se acepta sólo texto porque la comparación es por igualdad
    // exacta de cadena y `2026 !== '2026'` haría que nada fuera vigente sin
    // avisar. Misma decisión que en `CurriculoSupabase.leerPeriodoActivo`.
    return texto((respuesta.data as Fila).valor);
  }

  private async periodoPorId(id: string): Promise<Periodo | null> {
    const respuesta = await this.cliente
      .from(TABLA_PERIODOS)
      .select(COLUMNAS_PERIODO)
      .eq('id', id)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer período');
    if (!respuesta.data) return null;

    return aPeriodo(respuesta.data as Fila, await this.leerPeriodoVigente());
  }

  // --- Guardias -------------------------------------------------------------

  async listarGuardias(opciones: OpcionesListadoGuardias): Promise<PaginaGuardias> {
    const total = await this.contarGuardias(opciones);

    if (opciones.desplazamiento >= total) {
      return { guardias: [], total };
    }

    // Orden cronológico ascendente: período, día y bloque. Es el orden en el que
    // se lee una guardia («el lunes a primera hora»), y el `id` desempata para
    // que dos filas idénticas no intercambien posiciones entre páginas.
    const respuesta = await this.consultaDeGuardias(opciones)
      .order('period_code', { ascending: true })
      .order('day_of_week', { ascending: true })
      .order('block', { ascending: true })
      .order('id', { ascending: true })
      .range(
        opciones.desplazamiento,
        Math.min(opciones.desplazamiento + opciones.limite - 1, total - 1),
      );

    if (respuesta.error) {
      if (esRangoNoSatisfacible(respuesta.error)) {
        return { guardias: [], total: await this.contarGuardias(opciones) };
      }
      throw traducirError(respuesta.error, 'listar guardias');
    }

    const filas = (respuesta.data ?? []) as Fila[];
    return { guardias: filas.map(aGuardia), total };
  }

  private consultaDeGuardias(opciones: OpcionesListadoGuardias, contar = false) {
    let consulta = contar
      ? this.cliente.from(TABLA_GUARDIAS).select('id', { count: 'exact', head: true })
      : this.cliente.from(TABLA_GUARDIAS).select(COLUMNAS_GUARDIA);

    if (opciones.periodo) consulta = consulta.eq('period_code', opciones.periodo);
    if (opciones.docenteId) consulta = consulta.eq('teacher_id', opciones.docenteId);
    if (opciones.aulaId) consulta = consulta.eq('classroom_id', opciones.aulaId);
    if (opciones.dia !== undefined) consulta = consulta.eq('day_of_week', opciones.dia);
    if (opciones.bloque !== undefined) consulta = consulta.eq('block', opciones.bloque);
    if (opciones.activa !== undefined) consulta = consulta.eq('is_active', opciones.activa);

    return consulta;
  }

  private async contarGuardias(opciones: OpcionesListadoGuardias): Promise<number> {
    const respuesta = await this.consultaDeGuardias(opciones, true);

    if (respuesta.error) throw traducirError(respuesta.error, 'contar guardias');

    if (respuesta.count === null || respuesta.count === undefined) {
      throw ErrorApi.interno('La base de datos no devolvió el total de guardias.');
    }

    return respuesta.count;
  }

  async crearGuardia(entrada: EntradaCrearGuardia): Promise<Guardia> {
    // `turno` NO se manda: es una columna generada a partir de `block`. Enviarla
    // sería un error de Postgres, y es justo lo que el `.strict()` de Zod impide
    // que llegue hasta aquí.
    const respuesta = await this.cliente
      .from(TABLA_GUARDIAS)
      .insert({
        teacher_id: entrada.docenteId,
        classroom_id: entrada.aulaId,
        period_code: entrada.periodo,
        day_of_week: entrada.dia,
        block: entrada.bloque,
        notes: entrada.notas,
      })
      .select(COLUMNAS_GUARDIA)
      .single();

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'crear guardia');
    return aGuardia(respuesta.data as Fila);
  }

  async actualizarGuardia(id: string, cambios: CambiosGuardia): Promise<Guardia> {
    const parche: Record<string, unknown> = {};
    if (cambios.docenteId !== undefined) parche.teacher_id = cambios.docenteId;
    if (cambios.aulaId !== undefined) parche.classroom_id = cambios.aulaId;
    if (cambios.periodo !== undefined) parche.period_code = cambios.periodo;
    if (cambios.dia !== undefined) parche.day_of_week = cambios.dia;
    if (cambios.bloque !== undefined) parche.block = cambios.bloque;
    if (cambios.notas !== undefined) parche.notes = cambios.notas;
    if (cambios.activa !== undefined) parche.is_active = cambios.activa;

    if (Object.keys(parche).length === 0) {
      throw ErrorApi.peticionInvalida('No se indicó ningún cambio para la guardia.');
    }

    // Mover una guardia sobre su propio hueco no la rechaza a sí misma: el
    // trigger excluye la fila que se está actualizando (`not (origen = … and
    // id = p_id)`). Esa exclusión vive en la función SQL, no aquí.
    const respuesta = await this.cliente
      .from(TABLA_GUARDIAS)
      .update(parche)
      .eq('id', id)
      .select(COLUMNAS_GUARDIA)
      .single();

    if (respuesta.error) {
      throw this.traducirEscritura(respuesta.error, 'actualizar guardia', RECURSO_GUARDIA);
    }

    return aGuardia(respuesta.data as Fila);
  }

  // --- Cuadrante ------------------------------------------------------------

  async rejilla(opciones: OpcionesRejilla): Promise<RejillaCuadrante> {
    const periodo = opciones.periodo ?? (await this.leerPeriodoVigente());

    // Las aulas y los docentes no dependen del lapso, así que se piden siempre
    // —también cuando no hay ninguno vigente—. Con eso la pantalla puede mostrar
    // el catálogo y decir «no hay lapso vigente» en vez de quedarse en blanco,
    // que es indistinguible de «no hay nada configurado».
    const [aulas, docentes] = await Promise.all([
      this.listarTodasLasAulas(),
      this.listarDocentes(),
    ]);

    if (!periodo) {
      return { periodo: null, clases: [], guardias: [], aulas, docentes };
    }

    const [clases, guardias] = await Promise.all([
      this.clasesDeRejilla(periodo, opciones),
      this.guardiasDeRejilla(periodo, opciones),
    ]);

    return { periodo, clases, guardias, aulas, docentes };
  }

  private async clasesDeRejilla(
    periodo: string,
    opciones: OpcionesRejilla,
  ): Promise<ClaseCuadrante[]> {
    let consulta = this.cliente
      .from(VISTA_CLASES)
      .select(COLUMNAS_CLASE)
      .eq('period_code', periodo);

    if (opciones.seccionId) consulta = consulta.eq('section_id', opciones.seccionId);
    if (opciones.docenteId) consulta = consulta.eq('teacher_id', opciones.docenteId);
    if (opciones.aulaId) consulta = consulta.eq('classroom_id', opciones.aulaId);
    if (!opciones.incluirInactivas) consulta = consulta.eq('is_active', true);

    const filas = desenvolver(
      await consulta.order('day_of_week').order('block').order('id'),
      'leer el cuadrante de clases',
    ) as Fila[];

    return filas.map(aClaseCuadrante);
  }

  /**
   * Las guardias de la rejilla.
   *
   * `seccionId` no se aplica: una guardia no pertenece a ninguna sección, es una
   * presencia en un espacio. Filtrarlas por sección dejaría fuera guardias que
   * sí ocupan el mismo hueco, y la rejilla volvería a mostrar un cuadro que
   * parece libre sin estarlo.
   */
  private async guardiasDeRejilla(
    periodo: string,
    opciones: OpcionesRejilla,
  ): Promise<Guardia[]> {
    let consulta = this.cliente
      .from(TABLA_GUARDIAS)
      .select(COLUMNAS_GUARDIA)
      .eq('period_code', periodo);

    if (opciones.docenteId) consulta = consulta.eq('teacher_id', opciones.docenteId);
    if (opciones.aulaId) consulta = consulta.eq('classroom_id', opciones.aulaId);
    if (!opciones.incluirInactivas) consulta = consulta.eq('is_active', true);

    const filas = desenvolver(
      await consulta.order('day_of_week').order('block').order('id'),
      'leer las guardias del cuadrante',
    ) as Fila[];

    return filas.map(aGuardia);
  }

  async crearClase(entrada: EntradaCrearClase): Promise<ClaseCuadrante> {
    // El período no se manda: lo deriva el trigger de la sección. Mandarlo desde
    // aquí abriría la puerta a una fila cuya sección es de un lapso y cuya
    // rejilla se dibuja en otro.
    const respuesta = await this.cliente
      .from(TABLA_CUADRANTE)
      .insert({
        section_id: entrada.seccionId,
        teacher_id: entrada.docenteId,
        classroom_id: entrada.aulaId,
        day_of_week: entrada.dia,
        block: entrada.bloque,
      })
      .select('id')
      .single();

    if (respuesta.error) throw this.traducirEscritura(respuesta.error, 'crear clase');

    const id = texto((respuesta.data as Fila).id);
    if (!id) {
      throw ErrorApi.interno('La creación de la clase no devolvió un identificador.');
    }

    // Se vuelve a leer de la VISTA, no de la tabla: la respuesta tiene que traer
    // los nombres (materia, sección, aula, docente) para que la pantalla pinte
    // la celda sin una consulta por clase.
    return this.claseObligatoria(id);
  }

  async actualizarClase(id: string, cambios: CambiosClase): Promise<ClaseCuadrante> {
    const parche: Record<string, unknown> = {};
    if (cambios.seccionId !== undefined) parche.section_id = cambios.seccionId;
    if (cambios.docenteId !== undefined) parche.teacher_id = cambios.docenteId;
    if (cambios.aulaId !== undefined) parche.classroom_id = cambios.aulaId;
    if (cambios.dia !== undefined) parche.day_of_week = cambios.dia;
    if (cambios.bloque !== undefined) parche.block = cambios.bloque;
    if (cambios.activa !== undefined) parche.is_active = cambios.activa;

    if (Object.keys(parche).length === 0) {
      throw ErrorApi.peticionInvalida('No se indicó ningún cambio para la clase.');
    }

    // La escritura va contra la TABLA y no contra la vista: `v_cuadrante_clases`
    // une cuatro tablas, así que no es auto-actualizable y un `update` sobre
    // ella sería un error. La lectura de la respuesta sí va contra la vista.
    const respuesta = await this.cliente
      .from(TABLA_CUADRANTE)
      .update(parche)
      .eq('id', id)
      .select('id')
      .single();

    if (respuesta.error) {
      throw this.traducirEscritura(respuesta.error, 'actualizar clase', RECURSO_CLASE);
    }

    return this.claseObligatoria(id);
  }

  /**
   * Una clase que se acaba de escribir.
   *
   * Si la escritura devolvió un `id`, la clase existe: un `null` aquí sería una
   * violación de invariante —o un problema de permisos sobre la vista—, no un
   * caso a contemplar. Se falla ruidosamente en vez de devolver un cuerpo vacío
   * que el cliente tendría que interpretar.
   */
  private async claseObligatoria(id: string): Promise<ClaseCuadrante> {
    const respuesta = await this.cliente
      .from(VISTA_CLASES)
      .select(COLUMNAS_CLASE)
      .eq('id', id)
      .maybeSingle();

    if (respuesta.error) throw traducirError(respuesta.error, 'leer la clase');
    if (!respuesta.data) {
      throw ErrorApi.interno(
        'La clase se guardó pero no se pudo volver a leer. Revisa los permisos de la vista.',
      );
    }

    return aClaseCuadrante(respuesta.data as Fila);
  }

  // --- Lectura por rol ------------------------------------------------------

  async miHorario(
    rol: RolDeHorario,
    usuarioId: string,
    periodo?: string,
  ): Promise<MiHorario> {
    const lapso = periodo ?? (await this.leerPeriodoVigente());

    // Sin lapso no hay horario que mostrar, pero tampoco es un error: es un
    // sistema sin lapso vigente declarado. Se devuelve el rol y `periodo: null`
    // para que la pantalla pueda decir qué pasa.
    if (!lapso) return { rol, periodo: null, clases: [], guardias: [] };

    // Para un docente «lo mío» es una columna —`teacher_id = yo`—, así que se
    // filtra explícitamente: expresa la intención y usa el índice. Para un
    // estudiante «lo mío» son las secciones en las que está matriculado, que es
    // una subconsulta que la política `schedule_slots_read_estudiante` ya
    // resuelve; repetirla aquí sería una segunda copia de la misma regla, y la
    // segunda copia es la que se desvía.
    let consultaClases = this.cliente
      .from(VISTA_CLASES)
      .select(COLUMNAS_CLASE)
      .eq('period_code', lapso);

    if (rol === 'docente') consultaClases = consultaClases.eq('teacher_id', usuarioId);

    const clases = (
      desenvolver(
        await consultaClases.order('day_of_week').order('block').order('id'),
        'leer el horario de clases',
      ) as Fila[]
    ).map(aClaseCuadrante);

    // Un estudiante no tiene guardias: `teacher_duties` no tiene política para su
    // rol, así que la consulta devolvería cero filas de todos modos. Se responde
    // sin ir a la base para que «siempre vacío» sea una decisión del contrato y
    // no una consecuencia de la RLS.
    if (rol === 'estudiante') {
      return { rol, periodo: lapso, clases, guardias: [] };
    }

    const respuesta = await this.cliente
      .from(TABLA_GUARDIAS)
      .select(COLUMNAS_GUARDIA)
      .eq('period_code', lapso)
      .eq('teacher_id', usuarioId)
      .order('day_of_week')
      .order('block')
      .order('id');

    const guardias = (
      desenvolver(respuesta, 'leer el horario de guardias') as Fila[]
    ).map(aGuardia);

    return { rol, periodo: lapso, clases, guardias };
  }

  // --- Piezas internas ------------------------------------------------------

  /**
   * Todas las aulas, activas primero.
   *
   * Se devuelven también las archivadas a propósito: una clase o una guardia
   * pueden apuntar a un aula que se archivó **después** de asignarla, y si la
   * rejilla no devolviera esa columna, la celda quedaría huérfana sin que nadie
   * supiera por qué. Con el aula presente, la pantalla puede pintarla como
   * inactiva y el administrador ve el estado real.
   */
  private async listarTodasLasAulas(): Promise<Aula[]> {
    const respuesta = await this.cliente
      .from(TABLA_AULAS)
      .select(COLUMNAS_AULA)
      .order('is_active', { ascending: false })
      .order('name', { ascending: true })
      .order('id', { ascending: true });

    const filas = desenvolver(respuesta, 'listar los espacios de la rejilla') as Fila[];
    return filas.map(aAula);
  }

  /**
   * Los docentes que pueden aparecer en la rejilla.
   *
   * Se leen de `profiles` y no de `nombre_para_mostrar()` porque esta ruta es
   * sólo de administración y el administrador **sí** puede leer las filas ajenas
   * (`profiles_admin_all`). La función estrecha existe para el horario del
   * estudiante, donde `profiles_read_own` bloquearía el `join` y el horario
   * saldría sin profesor. Aquí se proyectan sólo `id`, `nombres` y `apellidos`:
   * la RLS es por fila, no por columna, así que pedir la fila entera traería
   * cédula y correo de todo el claustro sin que nadie los necesite.
   */
  private async listarDocentes(): Promise<DocenteResumen[]> {
    const respuesta = await this.cliente
      .from(TABLA_PERFILES)
      .select(COLUMNAS_DOCENTE_RESUMEN)
      .in('rol', ROLES_DOCENTES as string[])
      .eq('active', true)
      .order('apellidos', { ascending: true })
      .order('nombres', { ascending: true })
      .order('id', { ascending: true });

    const filas = desenvolver(respuesta, 'listar los docentes') as Fila[];
    return filas.map(aDocenteResumen);
  }

  /**
   * Traduce un fallo de escritura, distinguiendo el **choque de agenda**.
   *
   * El trigger lanza `23514`, el mismo código que un `check` corriente, así que
   * `traducirError` los convertiría a los dos en un `400 RESTRICCION_VIOLADA`.
   * Para un choque eso no sirve: los datos están bien y lo que no admite la
   * operación es el estado de la agenda, y el cliente necesita un `409` para
   * poder decir «ese docente ya está ocupado a esa hora».
   *
   * El mensaje del `409` **es el del trigger**, no uno escrito aquí. No es
   * pereza: el trigger nombra el día y el bloque («…el lunes en el bloque 3»), y
   * reconstruirlo en TypeScript sería una segunda copia del mensaje que se
   * desviaría en cuanto alguien retocara la migración. El texto no lleva ningún
   * dato sensible: lo escribimos nosotros.
   *
   * `recurso` convierte el 404 genérico de PostgREST (`PGRST116`, que es lo que
   * responde un `update` que no toca ninguna fila) en el código concreto del
   * recurso. Cuesta cero consultas y le dice al cliente qué se equivocó.
   */
  private traducirEscritura(
    error: unknown,
    contexto: string,
    recurso?: Recurso,
  ): ErrorApi {
    const mensaje = mensajeDe(error);

    if (esChoqueDeAgenda(mensaje)) {
      return ErrorApi.conflicto('CHOQUE_DE_AGENDA', mensaje, { contexto });
    }

    const traducido = traducirError(error, contexto);

    if (recurso && traducido.codigo === 'NO_ENCONTRADO') {
      return ErrorApi.noEncontrado(recurso.codigo, recurso.mensaje);
    }

    return traducido;
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
    cuadrante: new CuadranteSupabase(cliente),
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
