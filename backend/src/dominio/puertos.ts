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
  Aula,
  CambiosModulo,
  ClaseCuadrante,
  DetallePrograma,
  EntradaAcceso,
  EntradaAuditoria,
  EntradaPensum,
  EstadoAcceso,
  Guardia,
  InvitacionDocente,
  Materia,
  MiHorario,
  ModuloSistema,
  ParametroSistema,
  Perfil,
  Periodo,
  Programa,
  ProgramaConTotales,
  RejillaCuadrante,
  Rol,
  RolDeHorario,
  TipoAula,
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

// --- Módulo 3: cuadrante, aulas y guardias ----------------------------------

/**
 * Cuadrante, aulas y guardias (Módulo 3).
 *
 * **Todo pasa por PostgREST, sin funciones de base de datos.** A diferencia de
 * M2 —donde crear un programa con su pensum exigía una función porque PostgREST
 * no admite insertar un padre con sus hijos—, aquí cada escritura es **una fila
 * en una tabla**. No hay agregado que crear de golpe, así que no hace falta RPC
 * y el puerto no declara ninguna intención transaccional.
 *
 * Lo que sí vive en la base es la **guarda anti-colisión**: un docente o un
 * espacio no pueden estar en dos sitios en el mismo bloque. Es un trigger, no
 * una regla de la API, y se comprueba **cruzando las dos tablas**
 * (`schedule_slots` y `teacher_duties`), cosa que ningún `unique` puede
 * expresar. Por eso el puerto no tiene ninguna operación «comprobar
 * disponibilidad»: preguntar antes de escribir sería una carrera, y la
 * respuesta buena la da la propia escritura.
 */
export interface PuertaCuadrante {
  // --- Aulas ----------------------------------------------------------------
  listarAulas(opciones: OpcionesListadoAulas): Promise<PaginaAulas>;
  crearAula(entrada: EntradaCrearAula): Promise<Aula>;
  /** `nombre`, `capacidad`, `esTaller` y `activa`. Nunca borra: archiva. */
  actualizarAula(id: string, cambios: CambiosAula): Promise<Aula>;

  // --- Períodos -------------------------------------------------------------
  /**
   * El catálogo completo de lapsos, con `vigente` ya resuelto.
   *
   * Sin paginar a propósito: un centro acumula unos pocos lapsos al año, y el
   * desplegable de la pantalla los necesita **todos** para poder ofrecer el
   * siguiente sin que el administrador tenga que buscarlo.
   */
  listarPeriodos(): Promise<Periodo[]>;
  crearPeriodo(entrada: EntradaCrearPeriodo): Promise<Periodo>;
  actualizarPeriodo(id: string, cambios: CambiosPeriodo): Promise<Periodo>;
  /**
   * Declara ese lapso como el vigente.
   *
   * Es la **única** forma de mover `system_settings.periodo_activo`, y no se
   * acepta por `actualizarPeriodo` para que no haya dos caminos que cambien lo
   * mismo por vías distintas. Un trigger rechaza el valor si no corresponde a un
   * lapso registrado.
   */
  declararPeriodoVigente(id: string): Promise<Periodo>;

  // --- Guardias -------------------------------------------------------------
  listarGuardias(opciones: OpcionesListadoGuardias): Promise<PaginaGuardias>;
  crearGuardia(entrada: EntradaCrearGuardia): Promise<Guardia>;
  actualizarGuardia(id: string, cambios: CambiosGuardia): Promise<Guardia>;

  // --- Cuadrante ------------------------------------------------------------
  /** La rejilla completa: clases, guardias, aulas y docentes de un lapso. */
  rejilla(opciones: OpcionesRejilla): Promise<RejillaCuadrante>;
  crearClase(entrada: EntradaCrearClase): Promise<ClaseCuadrante>;
  actualizarClase(id: string, cambios: CambiosClase): Promise<ClaseCuadrante>;

  // --- Lectura por rol ------------------------------------------------------
  /**
   * El horario del llamante.
   *
   * `usuarioId` se pasa explícitamente porque para un docente «lo mío» es
   * `teacher_id = yo`, una sola columna. Para un estudiante «lo mío» es «las
   * secciones en las que estoy matriculado», que es una subconsulta: eso lo
   * resuelve la política RLS de `schedule_slots`, no el repositorio.
   *
   * Un `admin` no llega aquí: la ruta le responde 403. Su agenda no existe, y
   * devolverle un horario vacío le haría creer que no tiene ninguna.
   */
  miHorario(rol: RolDeHorario, usuarioId: string, periodo?: string): Promise<MiHorario>;
}

/** Filtros y paginación del listado de aulas. Todos opcionales salvo la paginación. */
export interface OpcionesListadoAulas {
  /** Búsqueda libre sobre `nombre`, insensible a mayúsculas. */
  busqueda?: string;
  /** Talleres, zonas o aulas. Las tres formas son excluyentes y cubren todo. */
  tipo?: TipoAula;
  /** Sólo las activas (`true`) o sólo las archivadas (`false`). */
  activa?: boolean;
  limite: number;
  desplazamiento: number;
}

export interface PaginaAulas {
  /** Las filas de esta página, ya ordenadas por nombre. */
  aulas: Aula[];
  /** Cuántas filas cumplen el filtro **en total**, no cuántas se devolvieron. */
  total: number;
}

/** Filtros y paginación del listado de guardias. */
export interface OpcionesListadoGuardias {
  periodo?: string;
  docenteId?: string;
  aulaId?: string;
  /** 1 = lunes … 6 = sábado. */
  dia?: number;
  bloque?: number;
  activa?: boolean;
  limite: number;
  desplazamiento: number;
}

export interface PaginaGuardias {
  guardias: Guardia[];
  /** Cuántas filas cumplen el filtro en total, no cuántas se devolvieron. */
  total: number;
}

/** Filtros de la rejilla. Sin `periodo`, se usa el vigente. */
export interface OpcionesRejilla {
  /** Lapso del que se pide la rejilla. Ausente = el vigente. */
  periodo?: string;
  seccionId?: string;
  docenteId?: string;
  aulaId?: string;
  /**
   * Incluir clases y guardias archivadas.
   *
   * Por defecto `false`: la rejilla muestra lo que está en vigor. Se pone en
   * `true` para ver el histórico de un hueco concreto.
   */
  incluirInactivas: boolean;
}

export interface EntradaCrearAula {
  nombre: string;
  /** 0 = sin cupo declarado (zonas, pasillos). */
  capacidad: number;
  esTaller: boolean;
}

export interface CambiosAula {
  nombre?: string;
  capacidad?: number;
  esTaller?: boolean;
  activa?: boolean;
}

export interface EntradaCrearPeriodo {
  codigo: string;
  nombre: string | null;
  fechaInicio: string | null;
  fechaFin: string | null;
}

/**
 * Cambios de un lapso. `codigo` no está: es su identidad.
 *
 * `sections.period_code` apunta a él y los documentos impresos lo citan, así que
 * renombrarlo rompería la referencia. Cambiar la nomenclatura (R-06) es crear un
 * lapso nuevo y archivar el viejo, no reescribir el código de uno en uso.
 */
export interface CambiosPeriodo {
  nombre?: string | null;
  fechaInicio?: string | null;
  fechaFin?: string | null;
  activo?: boolean;
}

export interface EntradaCrearGuardia {
  docenteId: string;
  aulaId: string;
  periodo: string;
  dia: number;
  bloque: number;
  notas: string | null;
}

export interface CambiosGuardia {
  docenteId?: string;
  aulaId?: string;
  periodo?: string;
  dia?: number;
  bloque?: number;
  notas?: string | null;
  activa?: boolean;
}

/**
 * Una clase nueva del cuadrante.
 *
 * **No lleva período.** Se deriva de la sección: aceptarlo del cliente abriría
 * la puerta a una fila cuya sección pertenece al lapso `2026-1` mientras la
 * rejilla se dibuja en el `2026-2`, y el chequeo de colisiones compararía peras
 * con manzanas.
 */
export interface EntradaCrearClase {
  seccionId: string;
  docenteId: string;
  aulaId: string;
  dia: number;
  bloque: number;
}

export interface CambiosClase {
  seccionId?: string;
  docenteId?: string;
  aulaId?: string;
  dia?: number;
  bloque?: number;
  activa?: boolean;
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
  cuadrante: PuertaCuadrante;
}
