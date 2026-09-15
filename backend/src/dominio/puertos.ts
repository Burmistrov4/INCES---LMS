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
  DetallePrograma,
  EntradaAcceso,
  EntradaAuditoria,
  EntradaPensum,
  EstadoAcceso,
  InvitacionDocente,
  Materia,
  ModuloSistema,
  ParametroSistema,
  Perfil,
  Programa,
  ProgramaConTotales,
  Rol,
  TipoPrograma,
} from './tipos.js';
import type { PeticionUrlSubida, UrlFirmada } from './almacenamiento.js';

/** Verifica un token de Supabase y devuelve la identidad, o `null` si no vale. */
export interface PuertaAuth {
  verificar(token: string): Promise<{ id: string; email: string | null } | null>;
}

export interface PuertaPerfiles {
  porId(id: string): Promise<Perfil | null>;
  /**
   * Listado de usuarios para la pantalla «Usuarios y Roles».
   *
   * Devuelve la página pedida **y** el total de filas que cumplen el filtro,
   * no sólo las de esta página. Sin el total, la pantalla no puede decir «1 a 25
   * de 340» ni saber cuántas páginas quedan: una lista que sólo trae la página
   * actual obliga al cliente a pedir una página de más para descubrir que ya no
   * había nada, y la última página sale vacía.
   *
   * El filtro y el recorte se aplican en la base de datos, no en memoria. Traer
   * todos los perfiles para filtrarlos en Node funcionaría con 40 estudiantes y
   * dejaría de funcionar con 4.000.
   */
  listar(opciones: OpcionesListadoUsuarios): Promise<PaginaUsuarios>;
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

/** Filtros y paginación del listado de usuarios. Todos opcionales. */
export interface OpcionesListadoUsuarios {
  /** Sólo los usuarios con este rol. */
  rol?: Rol;
  /** Sólo los activos (`true`) o sólo los inactivos (`false`). */
  activo?: boolean;
  /**
   * Búsqueda libre sobre nombre, apellido, correo y cédula.
   *
   * Es un `ilike %texto%` sin índices trigram todavía: suficiente a la escala
   * de un centro de formación, y anotado aquí para que no sorprenda cuando la
   * tabla crezca.
   */
  busqueda?: string;
  limite: number;
  desplazamiento: number;
}

export interface PaginaUsuarios {
  /** Las filas de esta página, ya ordenadas por apellido y nombre. */
  usuarios: Perfil[];
  /** Cuántas filas cumplen el filtro **en total**, no cuántas se devolvieron. */
  total: number;
}

/** Filtros y paginación del listado de accesos (auth_logs). Todos opcionales salvo la paginación. */
export interface OpcionesListadoAcceso {
  /** Sólo los intentos con este resultado. */
  estado?: EstadoAcceso;
  /** Sólo los intentos con este correo exacto. */
  email?: string;
  /** Sólo los intentos de este usuario (UUID de auth). */
  userId?: string;
  limite: number;
  desplazamiento: number;
}

export interface PaginaAcceso {
  /** Las filas de esta página, ya ordenadas por fecha descendente. */
  entradas: EntradaAcceso[];
  /** Cuántas filas cumplen el filtro en total, no cuántas se devolvieron. */
  total: number;
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

export interface PuertaInvitacionesDocente {
  /**
   * Guarda una invitación. El llamante ya debe haber generado el token y su hash;
   * aquí sólo se persiste el hash, nunca el token en claro.
   */
  crear(entrada: {
    email: string;
    tokenHash: string;
    /** Instante ISO de caducidad (ahora + 48 h). */
    expiresAt: string;
  }): Promise<InvitacionDocente>;

  /** Busca por hash del token. `null` si no existe. */
  porTokenHash(tokenHash: string): Promise<InvitacionDocente | null>;

  /** Marca la invitación como consumida (token de un solo uso). */
  marcarUsada(id: string): Promise<void>;

  /**
   * Crea el usuario de autenticación ya confirmado y devuelve su id.
   *
   * Vive en este puerto porque la activación de una invitación es justo quien
   * necesita crear la cuenta; el repositorio ya viaja con el cliente de
   * service_role, que es el único con permiso para `auth.admin.createUser`.
   * El disparador `handle_new_user` crea la fila `profiles` (rol `estudiante`),
   * y el endpoint la promueve a `docente` a continuación.
   */
  crearUsuarioDocente(email: string, password: string): Promise<string>;
}

export interface PuertaAuditoriaAcceso {
  /** Registra un intento de acceso (activación de invitación, login, ...). */
  registrar(entrada: {
    userId: string | null;
    email: string | null;
    ip: string | null;
    estado: EstadoAcceso;
  }): Promise<void>;

  /**
   * Lee la traza de accesos (auth_logs) con filtros y paginación.
   *
   * Devuelve la página pedida **y** el total que cumple el filtro, como
   * `PaginaUsuarios`: el panel necesita saber «1 a 25 de 340» y cuántas páginas
   * quedan. El recorte y el filtro se aplican en la base de datos; traer todas
   * las filas para filtrarlas en Node funcionaría con 40 accesos y dejaría de
   * funcionar con 40.000, que es justo el caso de una bitácora de inicios de
   * sesión acumulada mes a mes.
   */
  listar(opciones: OpcionesListadoAcceso): Promise<PaginaAcceso>;
}

/**
 * Currículo y pensum (Módulo 2).
 *
 * Las dos escrituras que importan —crear un programa con su pensum y reemplazar
 * el pensum completo— **no se pueden hacer con un `insert` de PostgREST**: no
 * admite insertar un padre con sus hijos en la misma petición y no expone
 * transacciones entre peticiones. Se comprobó contra la base real (ver
 * `docs/CONTRATO_API_MODULO2.md` §5 y `REPORTE_ARIA.md` R-10).
 *
 * Por eso el puerto declara la **intención** ("crea este programa con este
 * pensum, todo o nada") y el adaptador la satisface llamando a las funciones
 * `crear_programa_con_pensum` y `reemplazar_pensum` por `supabase.rpc(...)`.
 * El dominio no sabe —ni debe saber— que existen funciones en la base: eso es
 * un detalle del adaptador. Si mañana PostgreSQL se cambiara por otra cosa, el
 * puerto no cambiaría.
 */
export interface PuertaCurriculo {
  /** Listado paginado de programas, con los totales que la pantalla necesita. */
  listarProgramas(opciones: OpcionesListadoProgramas): Promise<PaginaProgramas>;

  /** Detalle con el pensum agrupado. `null` si el programa no existe. */
  detallePrograma(id: string): Promise<DetallePrograma | null>;

  /**
   * El asistente: programa + pensum en **una sola transacción**.
   *
   * Devuelve el detalle ya armado porque el cliente lo pinta al terminar el
   * asistente, y volver a pedirlo sería una petición de más justo cuando el
   * administrador espera ver el resultado.
   */
  crearPrograma(entrada: EntradaCrearPrograma): Promise<DetallePrograma>;

  /** Metadatos del programa. `codigo` y `tipo` no se pueden cambiar. */
  actualizarPrograma(id: string, cambios: CambiosPrograma): Promise<Programa>;

  /**
   * Reemplazo completo del pensum: el cliente manda el estado final y la base
   * calcula la diferencia. Es transaccional, y la Regla 2 puede bloquearlo.
   */
  reemplazarPensum(id: string, pensum: EntradaPensum[]): Promise<DetallePrograma>;

  /** Banco global de materias, paginado y con búsqueda. */
  listarMaterias(opciones: OpcionesListadoMaterias): Promise<PaginaMaterias>;

  /** Registra una materia en caliente desde el paso 2 del asistente. */
  crearMateria(entrada: EntradaCrearMateria): Promise<Materia>;
}

/** Filtros y paginación del listado de programas. Todos opcionales salvo la paginación. */
export interface OpcionesListadoProgramas {
  /** Sólo las carreras o sólo los cursos libres. */
  tipo?: TipoPrograma;
  /** Sólo los publicados (`true`) o sólo los borradores (`false`). */
  activo?: boolean;
  /** Búsqueda libre sobre `codigo` y `nombre`, insensible a mayúsculas. */
  busqueda?: string;
  limite: number;
  desplazamiento: number;
}

export interface PaginaProgramas {
  /** Las filas de esta página, ya ordenadas por nombre. */
  programas: ProgramaConTotales[];
  /** Cuántas filas cumplen el filtro **en total**, no cuántas se devolvieron. */
  total: number;
}

/** Filtros y paginación del banco de materias. */
export interface OpcionesListadoMaterias {
  /** Búsqueda libre sobre `codigo` y `nombre`, insensible a mayúsculas. */
  busqueda?: string;
  limite: number;
  desplazamiento: number;
}

export interface PaginaMaterias {
  materias: Materia[];
  /** Cuántas filas cumplen el filtro en total, no cuántas se devolvieron. */
  total: number;
}

/**
 * Lo que manda el asistente al final de sus tres pasos.
 *
 * `publicar` decide el `is_active` inicial. Va separado de `activo` a
 * propósito: crear en borrador es lo normal mientras se arma el pensum, y
 * publicar es la decisión final. Un solo campo para las dos cosas obligaría a
 * que el asistente publicara siempre o nunca.
 */
export interface EntradaCrearPrograma {
  codigo: string;
  nombre: string;
  tipo: TipoPrograma;
  requierePasantia: boolean;
  publicar: boolean;
  pensum: EntradaPensum[];
}

/**
 * Cambios de metadatos de un programa.
 *
 * No incluye `codigo` ni `tipo`: son la identidad del programa. `sections` (M3)
 * apunta a él, y un código cambiado rompe cualquier documento impreso que lo
 * cite.
 */
export interface CambiosPrograma {
  nombre?: string;
  requierePasantia?: boolean;
  activo?: boolean;
}

export interface EntradaCrearMateria {
  codigo: string;
  nombre: string;
  horasAcademicas: number;
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
  invitaciones: PuertaInvitacionesDocente;
  acceso: PuertaAuditoriaAcceso;
  curriculo: PuertaCurriculo;
}
