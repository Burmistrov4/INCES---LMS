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
  Anuncio,
  ArchivoMetadata,
  Aula,
  CambiosModulo,
  ClaseCuadrante,
  DetallePrograma,
  EntradaAcceso,
  EntradaAuditoria,
  EntradaPensum,
  Entrega,
  EntregaCalificada,
  EstadoAcceso,
  EstadoInscripcion,
  Guardia,
  Inscripcion,
  InscripcionDetallada,
  InvitacionDocente,
  LibroEntrega,
  Materia,
  MiHorario,
  ModuloSistema,
  OcupacionSeccion,
  ParametroSistema,
  Perfil,
  Periodo,
  Programa,
  ProgramaConTotales,
  PublicacionTarea,
  RejillaCuadrante,
  Rol,
  RolDeHorario,
  Seccion,
  Tarea,
  TipoAula,
  TipoEntidadArchivo,
  TipoPrograma,
  TipoTarea,
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
    /** Nombre(s) del docente, capturado por el administrador (R-21). */
    nombres: string;
    /** Apellido(s) del docente, capturado por el administrador (R-21). */
    apellidos: string;
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
   *
   * `nombres`/`apellidos` se pasan en `user_metadata` para que `handle_new_user`
   * los vuelque a `profiles` y `nombre_para_mostrar()` deje de devolver NULL
   * (R-21). Sin ellos, el docente quedaría sin nombre en el cuadrante.
   */
  crearUsuarioDocente(
    email: string,
    password: string,
    nombres: string,
    apellidos: string,
  ): Promise<string>;
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
  /**
   * Metadatos del objeto en el almacén, o `null` si no existe.
   *
   * Devuelve el **tamaño**, y no un simple sí/no, porque la regla de tamaño de
   * M5 no se puede comprobar antes de subir: una URL PUT prefirmada no admite
   * `content-length-range`, así que el tamaño real sólo se conoce con el
   * `HeadObject` posterior. Un `existe()` booleano obligaría a un segundo viaje
   * al almacén para leer el `ContentLength`, y ese segundo viaje es justo el que
   * se quiere evitar.
   *
   * Que el objeto no exista es una respuesta legítima —una subida interrumpida
   * deja la fila `PENDING` sin objeto—, no un fallo: por eso `null` y no una
   * excepción.
   */
  estadisticas(clave: string): Promise<{ tamanoBytes: number } | null>;
  /** Borra un objeto. El backend decide *cuándo*; R2 sólo ejecuta. */
  eliminar(clave: string): Promise<void>;
}

/**
 * Los metadatos de los archivos de M5.
 *
 * **Toda escritura pasa por RPC.** `files_metadata` tiene `INSERT`, `UPDATE` y
 * `DELETE` revocados para `anon` y `authenticated`: la escritura directa da
 * `42501`. No es una limitación que haya que rodear, es la decisión de diseño —
 * si se pudiera insertar a mano, cualquiera se registraría como propietario de
 * un objeto que no subió, o marcaría como confirmado lo que no existe.
 *
 * Las RPC son `security definer` y **hacen su propia autorización** con
 * `auth.uid()`: al ser `definer`, la RLS ya no las protege (lección R-20). Por
 * eso este puerto no declara ninguna operación «¿es tuyo?»: preguntar antes de
 * escribir sería una segunda copia de la regla, y la respuesta buena la da la
 * propia escritura.
 */
export interface PuertaArchivos {
  /**
   * Reserva un archivo en estado `PENDING`, antes de que el objeto exista.
   *
   * La fila nace primero porque **no hay transacción que abarque R2 y
   * PostgreSQL**. Un `PENDING` huérfano es visible y barrible; un objeto sin
   * fila sería un archivo fantasma que nadie puede autorizar ni limpiar.
   */
  registrarPendiente(entrada: EntradaRegistrarArchivo): Promise<ArchivoMetadata>;

  /**
   * Sella el tamaño real y pasa a `CONFIRMED`. Sólo acepta filas `PENDING`:
   * reconfirmar un `CONFIRMED` o resucitar un `DELETED` es un error, no un
   * `update` silencioso que reescriba un tamaño ya sellado.
   */
  confirmar(id: string, tamanoBytes: number): Promise<ArchivoMetadata>;

  /** Borrado **lógico**: `estado = 'DELETED'` y `deleted_at`. La fila se conserva. */
  marcarBorrado(id: string): Promise<ArchivoMetadata>;

  /**
   * Un archivo por su id. `null` si no existe **o si la RLS no deja verlo**.
   *
   * Las dos cosas se funden a propósito en el mismo `null`: distinguirlas
   * permitiría averiguar, por el código de respuesta, si un archivo ajeno
   * existe. Para quien pregunta, «no existe» y «no es tuyo» son lo mismo.
   */
  porId(id: string): Promise<ArchivoMetadata | null>;

  /**
   * Cuántos archivos vivos (no `DELETED`) cuelgan de una entidad.
   *
   * Existe para poder aplicar `m5_max_archivos_por_entidad`, que es un parámetro
   * configurable y no una constante. Se apoya en el índice
   * `files_metadata_entidad_idx`, así que no recorre la tabla.
   */
  contarPorEntidad(
    entityType: TipoEntidadArchivo,
    entidadId: string | null,
  ): Promise<number>;

  /**
   * Los archivos vivos que cuelgan de una entidad concreta.
   *
   * Es la lectura que le faltaba al módulo: sin ella la pantalla puede subir y
   * borrar, pero **no puede mostrar lo que ya está guardado**, así que cada vez
   * que alguien entra ve un panel vacío y vuelve a subir lo mismo. No es una
   * comodidad, es la diferencia entre un gestor documental y un formulario de
   * subida.
   *
   * **No pagina, y no es un olvido.** El número de archivos por entidad está
   * acotado por `m5_max_archivos_por_entidad` (10 por defecto), así que la lista
   * de una entidad cabe entera por construcción. Paginar aquí sería construir
   * una máquina para un caso que el propio módulo hace imposible; el día que ese
   * tope suba a un orden de magnitud, esta decisión hay que revisarla —y por eso
   * queda escrita—.
   *
   * **Se excluyen los `DELETED` pero se incluyen los `PENDING`.** Un archivo ya
   * borrado no es material de nadie; uno sin confirmar sí, y ocultarlo sería
   * peor: quien acaba de subir y falló la confirmación vería desaparecer su
   * archivo sin explicación. Se devuelve el `estado` para que la pantalla pueda
   * etiquetarlo en vez de mentir sobre él.
   *
   * `entidadId` es obligatorio —al contrario que en `contarPorEntidad`, que
   * acepta `null` porque el tope también aplica a las subidas sin entidad—:
   * aquí se pregunta por el contenido de una tarea o una guía concreta, y «los
   * archivos sin entidad» no es una pantalla que nadie abra.
   *
   * Quién ve qué lo decide la RLS, no esta firma: el propietario ve lo suyo y el
   * administrador lo ve todo. La visibilidad cruzada —que un docente vea las
   * entregas de sus alumnos— necesita saber a qué sección pertenece la entidad, y
   * eso no existe en M5: `entidad_id` es un UUID sin tabla que lo respalde hasta
   * que M6 cree las tareas. Se resuelve allí, con la política que lo haga
   * expresable, no aquí con un filtro que no puede saberlo.
   */
  listarPorEntidad(
    entityType: TipoEntidadArchivo,
    entidadId: string,
  ): Promise<ArchivoMetadata[]>;

  /**
   * Las subidas `PENDING` más antiguas que un instante, hasta un tope.
   *
   * Existe para el barrido de abandonados (deuda D9). La fila nace `PENDING`
   * **antes** de que el objeto exista, así que un `PENDING` que nunca se confirmó
   * es la única huella que queda de una subida abandonada — y es una huella que
   * sólo está en la base, no en el bucket: el ciclo de vida de R2 filtra por
   * prefijo y no sabe nada de estados.
   *
   * **Se ordena de la más vieja a la más nueva.** No es cosmético: con el tope
   * aplicado, ordenar al revés cortaría siempre por lo más reciente y el barrido
   * nunca llegaría al fondo de la cola, que es donde están las abandonadas de
   * verdad.
   *
   * El tope no es opcional a propósito. Un barrido sin límite deja de ser una
   * limpieza y pasa a ser una decisión sobre toda la tabla, y quien la toma sin
   * querer no se entera.
   *
   * Devuelve `ArchivoMetadata` completo y no un resumen porque el llamante
   * necesita la `r2Key` para borrar el objeto antes de marcar la fila.
   */
  pendientesAntiguos(antesDe: string, limite: number): Promise<ArchivoMetadata[]>;
}

/** Lo que hace falta para reservar un archivo antes de subirlo. */
export interface EntradaRegistrarArchivo {
  /** Dueño del archivo. El llamante sólo puede poner su propio id, salvo admin. */
  propietarioId: string;
  /** Clave del objeto, construida por el servidor con `construirClave`. */
  r2Key: string;
  nombreOriginal: string;
  /** Tipo MIME canónico, derivado de la extensión. Nunca el del cliente. */
  tipoContenido: string;
  entityType: TipoEntidadArchivo;
  entidadId: string | null;
}

/**
 * Secciones: el grupo concreto de una materia en un lapso.
 *
 * Es el catálogo que M4 necesita y que hasta ahora **no existía en la API**: la
 * tabla se leía desde el cuadrante y se contaba desde el pensum, pero nadie
 * podía crear una. Sin secciones el motor de cupos no tiene sobre qué operar.
 *
 * **Ninguna operación borra.** Archivar es `is_active = false`, y no es una
 * convención: el `DELETE` está **revocado** en la base para `authenticated`, así
 * que borrar no es una opción que se pueda tomar por descuido. Además una sección
 * borrada se llevaría por delante el historial de inscripciones, que es
 * exactamente lo que `DROPPED` existe para conservar.
 */
export interface PuertaSecciones {
  listar(opciones: OpcionesListadoSecciones): Promise<PaginaSecciones>;
  crear(entrada: EntradaCrearSeccion): Promise<Seccion>;
  /** `nombre`, `cupoMaximo` y `activa`. Nunca borra: archiva. */
  actualizar(id: string, cambios: CambiosSeccion): Promise<Seccion>;
}

export interface OpcionesListadoSecciones {
  /** Búsqueda libre sobre el nombre de la sección, insensible a mayúsculas. */
  busqueda?: string;
  periodo?: string;
  programaId?: string;
  materiaId?: string;
  activa?: boolean;
  limite: number;
  desplazamiento: number;
}

export interface PaginaSecciones {
  secciones: Seccion[];
  total: number;
}

/**
 * Una sección nueva.
 *
 * El período se acepta del cliente —a diferencia de una clase del cuadrante, que
 * lo hereda de su sección— porque la sección **es** la que fija el lapso: no hay
 * nada de donde heredarlo.
 */
export interface EntradaCrearSeccion {
  programaId: string;
  materiaId: string;
  periodo: string;
  nombre: string;
  /** `null` = usar el cupo global del centro. `0` = sección sin cupo. */
  cupoMaximo: number | null;
}

export interface CambiosSeccion {
  nombre?: string;
  cupoMaximo?: number | null;
  activa?: boolean;
}

/**
 * El motor de inscripciones y cupos.
 *
 * **Todo pasa por RPC.** La tabla `enrollments` tiene `INSERT`, `UPDATE`,
 * `DELETE` y `TRUNCATE` **revocados** para `anon` y `authenticated` (R-23): la
 * escritura directa da `42501`. Y no es una limitación que haya que rodear, es la
 * decisión de diseño — la clave publishable viaja al cliente (ADR-003), así que
 * si se pudiera escribir directo, cualquiera se auto-inscribiría en `ENROLLED` y
 * **el motor de cupos sería decorativo**.
 *
 * Las RPC son `security definer` y **hacen su propia autorización** con
 * `auth.uid()`: al ser `definer`, la RLS ya no las protege.
 */
export interface PuertaInscripciones {
  /** Catálogo de secciones con su ocupación, para poder inscribirse. */
  listarOfertas(opciones: OpcionesListadoOfertas): Promise<PaginaOcupacion>;

  /**
   * Las inscripciones del llamante, con su sección y su posición en la cola.
   *
   * `estudianteId` se pasa **explícitamente** y no se deduce de la sesión, por la
   * misma razón que en `miHorario`: la RLS deja a un administrador leer todas las
   * filas, así que «lo mío» no se puede dejar al filtro de la base. Sin el
   * parámetro, un administrador que abriera su pantalla de inscripciones vería
   * las de todo el centro.
   */
  misInscripciones(estudianteId: string): Promise<InscripcionDetallada[]>;

  /**
   * Pide un asiento. Devuelve el estado resultante: `ENROLLED` si entró directo,
   * `WAITLISTED` si quedó en la cola.
   *
   * **No devuelve un booleano ni una inscripción**: el estado lo decide la base
   * dentro de su cerrojo, y adivinarlo aquí sería una segunda copia de la regla.
   */
  solicitar(seccionId: string): Promise<EstadoInscripcion>;

  /** Acepta una oferta viva. Rechaza las vencidas. */
  aceptar(seccionId: string): Promise<EstadoInscripcion>;

  /** Renuncia al asiento. Deja la fila en `DROPPED`, no la borra. */
  renunciar(seccionId: string): Promise<EstadoInscripcion>;

  // --- Administración -------------------------------------------------------

  /** Panel de ocupación de todas las secciones. */
  listarOcupacion(opciones: OpcionesListadoOfertas): Promise<PaginaOcupacion>;

  /** La cola FIFO de una sección, en orden de llegada. */
  colaDeSeccion(seccionId: string): Promise<InscripcionDetallada[]>;

  /** Quién está inscrito en una sección (cualquier estado). */
  inscritosDeSeccion(seccionId: string): Promise<InscripcionDetallada[]>;

  /**
   * Promueve al siguiente de la cola.
   *
   * Devuelve `null` cuando **no había nadie a quien promover**, que no es un
   * error: una cola vacía es un estado normal, no un fallo. La ruta lo traduce a
   * un 200 explicativo en vez de a un 404.
   */
  promover(seccionId: string): Promise<Inscripcion | null>;

  /**
   * Devuelve a un `DROPPED` al estado `ENROLLED`. **Puede exceder la capacidad.**
   *
   * «Si el admin autoriza, el sistema obedece»: la comprobación de cupo se quitó
   * de esta RPC a propósito. El exceso queda deliberado y auditable.
   */
  reincorporar(estudianteId: string, seccionId: string): Promise<EstadoInscripcion>;

  /** Vence las ofertas caducadas. **Idempotente**: devuelve cuántas venció. */
  expirarOfertas(): Promise<number>;
}

export interface OpcionesListadoOfertas {
  periodo?: string;
  programaId?: string;
  materiaId?: string;
  /** Sólo las secciones con asiento disponible de verdad (sin oferta viva). */
  soloConCupo?: boolean;
  busqueda?: string;
  limite: number;
  desplazamiento: number;
}

export interface PaginaOcupacion {
  secciones: OcupacionSeccion[];
  total: number;
}

/**
 * El aula virtual: tablón, trabajo de clase, entregas y calificaciones.
 *
 * **Quién ve qué y quién puede escribir lo decide la base, no la API.** Las
 * lecturas van por PostgREST y las filtra la RLS; las escrituras van por RPC
 * `security definer` que hacen su propia autorización con `auth.uid()`. Repetir
 * esa comprobación aquí sería una segunda copia de la regla, y dos copias se
 * desvían (ADR-003).
 *
 * De ahí que ningún método reciba un «actor» ni filtre por propietario «por si
 * acaso»: la frontera es la RLS. La única excepción es la guardia de módulo, y
 * no contradice nada —que el módulo esté encendido no lo sabe la base—.
 *
 * El **libro de calificaciones** va por RPC y no por lectura directa por un
 * motivo concreto: `m6_entregas` tiene privilegios por columna, y
 * `nota_borrador` **no** está concedida a `authenticated`. Un `select` normal la
 * devolvería en blanco sin dar error, y el docente calificaría a ciegas. La RPC
 * `m6_entregas_de_tarea` la lee como dueña de la función.
 */
export interface PuertaAula {
  /** El feed de anuncios de una sección, del más nuevo al más viejo. */
  tablon(seccionId: string): Promise<Anuncio[]>;

  /** Publica un anuncio. Nace `BORRADOR`; el alumno lo verá cuando toque. */
  crearAnuncio(entrada: EntradaCrearAnuncio): Promise<Anuncio>;

  /** El trabajo de clase de una sección, en el orden que puso el docente. */
  trabajoDeClase(seccionId: string): Promise<Tarea[]>;

  /** Crea trabajo de clase. Nace `BORRADOR` y **sin entregas**. */
  crearTarea(entrada: EntradaCrearTarea): Promise<Tarea>;

  /**
   * Publica una tarea y crea un placeholder de entrega por matrícula `ENROLLED`.
   *
   * **Idempotente**: republicar no duplica entregas. Lo garantiza el
   * `unique (tarea_id, estudiante_id)` con `on conflict do nothing` en la base,
   * no esta firma —un botón que se puede pulsar dos veces no puede crear dos
   * entregas por alumno—.
   */
  publicarTarea(tareaId: string): Promise<PublicacionTarea>;

  /** El libro de calificaciones de una tarea, con la nota borrador incluida. */
  entregasDeTarea(tareaId: string): Promise<LibroEntrega[]>;

  /**
   * Las entregas que la RLS deja ver al llamante.
   *
   * Para un alumno es lo suyo; **no se filtra aquí por propietario** a propósito
   * (ADR-003): añadir un `.eq('estudiante_id', ...)` sería una segunda copia de
   * la política, y la copia se desviaría en cuanto la política cambiara. La
   * selección de columnas es explícita y **no incluye `nota_borrador`**, que el
   * `GRANT` por columna esconde de todos modos.
   */
  misEntregas(): Promise<Entrega[]>;

  /** Marca la entrega como `ENTREGADA`. Sólo el alumno dueño. */
  entregar(entregaId: string): Promise<Entrega>;

  /**
   * El «des-entregar»: vuelve la entrega a `RECLAMADA` para poder rehacerla.
   *
   * Sólo el alumno dueño y sólo desde `ENTREGADA`. Una entrega ya devuelta no se
   * reabre: en ese momento la nota ya es del alumno y el ciclo está cerrado.
   */
  reclamar(entregaId: string): Promise<Entrega>;

  /** Escribe la nota **borrador**: el alumno todavía no la ve. */
  calificar(entregaId: string, nota: number): Promise<EntregaCalificada>;

  /**
   * Copia el borrador a `notaAsignada` y cierra el ciclo.
   *
   * Es el **único** momento en que el alumno ve una nota. Devolver sin nota es
   * legítimo: es el «devuelta sin calificar» de Google.
   */
  devolver(entregaId: string): Promise<EntregaCalificada>;
}

/**
 * Lo que hace falta para publicar un anuncio.
 *
 * `programadoPara` es la publicación diferida: un borrador con esta fecha ya
 * vencida es visible para el alumno sin que ningún proceso lo publique. La
 * coherencia —un programado sin fecha no significa nada— la impone un `CHECK` de
 * la tabla, no esta firma.
 */
export interface EntradaCrearAnuncio {
  seccionId: string;
  titulo: string;
  cuerpo: string;
  /** `null` = sin programar: lo publica el docente cuando quiera. */
  programadoPara: string | null;
}

/**
 * Lo que hace falta para crear trabajo de clase.
 *
 * `tipo` decide las reglas: un `MATERIAL` no lleva puntos ni fecha límite, y la
 * RPC lo rechaza con un mensaje legible si se los dan. La coherencia por tipo es
 * un `CHECK` de la tabla, y este puerto no la repite.
 */
export interface EntradaCrearTarea {
  seccionId: string;
  titulo: string;
  descripcion: string;
  tipo: TipoTarea;
  /** Puntos sobre 20. Debe ser 0 para un `MATERIAL`. */
  puntosMaximos: number;
  fechaLimite: string | null;
  permitirEntregaTardia: boolean;
  tema: string | null;
  orden: number;
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
  secciones: PuertaSecciones;
  inscripciones: PuertaInscripciones;
  archivos: PuertaArchivos;
  aula: PuertaAula;
}
