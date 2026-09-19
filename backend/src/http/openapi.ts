/**
 * Documento OpenAPI 3.1 generado a partir de los esquemas Zod (deuda D6).
 *
 * ========================================================================
 *  POR QUÉ SE GENERA Y NO SE ESCRIBE A MANO
 * ========================================================================
 * Un `openapi.yaml` escrito a mano es un segundo contrato. El primero son los
 * esquemas Zod, que son los que de verdad validan las peticiones en tiempo de
 * ejecución. El segundo empieza siendo idéntico y se separa en la primera
 * semana: alguien añade un campo a `esquemaCambioRol`, los tests pasan, y el
 * documento sigue anunciando el contrato viejo. El cliente generado a partir
 * del YAML deja de compilar contra la API real y nadie lo nota hasta que un
 * usuario lo sufre.
 *
 * Generándolo, no hay segundo contrato: el documento es una *proyección* del
 * único contrato que existe. La deriva es imposible por construcción.
 *
 * Lo que esto NO puede adivinar son los **cuerpos de respuesta**: Zod valida
 * las entradas, no las salidas, y el backend devuelve objetos literales. Por eso
 * las respuestas se declaran aquí abajo, a mano, y existe una prueba
 * (`test/openapi.test.ts`) que comprueba que el documento generado sigue
 * conteniendo cada ruta real de la aplicación. Si alguien añade una ruta y
 * olvida documentarla, la prueba falla.
 */
import {
  OpenApiGeneratorV31,
  OpenAPIRegistry,
  extendZodWithOpenApi,
} from '@asteasolutions/zod-to-openapi';
import { z } from 'zod';
import { esquemaFirmarSubida, rolSchema } from '../http/esquemas.js';

/**
 * Añade `.openapi()` a las instancias de Zod.
 *
 * Tiene que llamarse **una sola vez** y antes de que ningún esquema llame a
 * `.openapi()`. Sin esto, la librería no parchea el prototipo de Zod y cualquier
 * `.openapi(...)` falla con «is not a function». Es un monkey-patch global, así
 * que vive en este archivo y no se repite en ningún otro sitio.
 */
extendZodWithOpenApi(z);

/** Marca un esquema de respuesta. No valida nada; sólo documenta. */
const CuerpoError = z
  .object({
    error: z.object({
      codigo: z.string(),
      mensaje: z.string(),
      detalles: z.unknown().optional(),
    }),
  })
  .openapi('CuerpoError');

const Version = z
  .object({
    version: z.string(),
    hora: z.string(),
  })
  .openapi('Sonda');

const SondaProfunda = z
  .object({
    estado: z.enum(['ok', 'degradado']),
    baseDeDatos: z.enum(['ok', 'inalcanzable']),
    version: z.string(),
    hora: z.string(),
  })
  .openapi('SondaProfunda');

const Perfil = z
  .object({
    id: z.string().uuid(),
    email: z.string().email(),
    cedula: z.string().nullable(),
    nombres: z.string(),
    apellidos: z.string(),
    rol: rolSchema,
    activo: z.boolean(),
  })
  .openapi('Perfil');

const ModuloSistema = z
  .object({
    clave: z.string(),
    nombre: z.string(),
    descripcion: z.string().nullable(),
    habilitado: z.boolean(),
    orden: z.number().int(),
    icono: z.string().nullable(),
    rolesPermitidos: z.array(rolSchema),
    categoria: z.string(),
    actualizadoEn: z.string().nullable(),
  })
  .openapi('ModuloSistema');

/** `valor` es JSON arbitrario: su forma la fija el `tipo` del parámetro. */
const ParametroSistema = z
  .object({
    clave: z.string(),
    valor: z.unknown(),
    tipo: z.enum(['number', 'boolean', 'string', 'json']),
    descripcion: z.string().nullable(),
    categoria: z.string(),
    esPublico: z.boolean(),
    actualizadoEn: z.string().nullable(),
  })
  .openapi('ParametroSistema');

const EntradaAuditoria = z
  .object({
    id: z.string(),
    tabla: z.string(),
    clave: z.string(),
    valorAnterior: z.unknown(),
    valorNuevo: z.unknown(),
    usuarioEmail: z.string().nullable(),
    creadoEn: z.string().nullable(),
  })
  .openapi('EntradaAuditoria');

const EntradaAcceso = z
  .object({
    id: z.string(),
    userId: z.string().nullable().openapi({
      description: 'UUID de auth del usuario, o null en un intento fallido sin cuenta.',
    }),
    email: z.string().nullable(),
    ip: z.string().nullable().openapi({
      description: 'Dirección IP de origen del intento.',
    }),
    estado: z.enum(['SUCCESS', 'FAILED']).openapi({
      description: 'Resultado del intento de acceso.',
    }),
    createdAt: z.string().openapi({
      description: 'Instante ISO del intento. Orden descendente en la respuesta.',
    }),
  })
  .openapi('EntradaAcceso');

const RespuestaYo = z
  .object({
    perfil: Perfil,
    rol: rolSchema,
    modulos: z.array(ModuloSistema),
  })
  .openapi('RespuestaYo');

const RespuestaModulos = z
  .object({ modulos: z.array(ModuloSistema) })
  .openapi('RespuestaModulos');

const RespuestaModulo = z
  .object({ modulo: ModuloSistema })
  .openapi('RespuestaModulo');

const RespuestaParametros = z
  .object({ parametros: z.array(ParametroSistema) })
  .openapi('RespuestaParametros');

const RespuestaParametro = z
  .object({ parametro: ParametroSistema })
  .openapi('RespuestaParametro');

const RespuestaAuditoria = z
  .object({ entradas: z.array(EntradaAuditoria) })
  .openapi('RespuestaAuditoria');

const RespuestaAcceso = z
  .object({
    entradas: z.array(EntradaAcceso),
    total: z.number().int().openapi({
      description: 'Cuántas filas cumplen el filtro en total, no cuántas se devolvieron.',
    }),
    limite: z.number().int().openapi({ description: 'Tamaño de página aplicado.' }),
    desplazamiento: z.number().int().openapi({
      description: 'Filas saltadas antes de esta página.',
    }),
  })
  .openapi('RespuestaAcceso');

const RespuestaPerfil = z.object({ perfil: Perfil }).openapi('RespuestaPerfil');

const RespuestaUsuarios = z
  .object({
    usuarios: z.array(Perfil),
    total: z.number().int().openapi({
      description:
        'Cuántas filas cumplen el filtro en total, no cuántas se devolvieron.',
    }),
    limite: z.number().int().openapi({ description: 'Tamaño de página aplicado.' }),
    desplazamiento: z.number().int().openapi({
      description: 'Filas saltadas antes de esta página.',
    }),
  })
  .openapi('RespuestaUsuarios');

const CuerpoCambiosModulo = z
  .object({
    habilitado: z.boolean().optional().openapi({
      description: 'Interruptor maestro del módulo.',
    }),
    orden: z.number().int().min(0).max(9999).optional().openapi({
      description: 'Posición en el menú. Menor primero.',
    }),
    rolesPermitidos: z.array(rolSchema).max(3).optional().openapi({
      description: 'Lista vacía significa visible para todos los roles.',
    }),
  })
  .strict()
  .openapi('CuerpoCambiosModulo');

const CuerpoValorParametro = z
  .object({
    valor: z.unknown().openapi({
      description:
        'Debe encajar con el `tipo` declarado del parámetro; si no, la API responde 400.',
    }),
  })
  .strict()
  .openapi('CuerpoValorParametro');

const CuerpoCambioRol = z
  .object({ rol: rolSchema })
  .strict()
  .openapi('CuerpoCambioRol');

const CuerpoCorreoInvitacion = z
  .object({
    email: z.string().email().openapi({
      description: 'Correo del docente invitado.',
    }),
    nombres: z.string().min(1).max(100).openapi({
      description: 'Nombre(s) del docente, capturado por el administrador (R-21).',
    }),
    apellidos: z.string().min(1).max(100).openapi({
      description: 'Apellido(s) del docente, capturado por el administrador (R-21).',
    }),
  })
  .strict()
  .openapi('CuerpoCorreoInvitacion');

const CuerpoActivarCuenta = z
  .object({
    token: z.string().min(20).openapi({
      description: 'Token de un solo uso del enlace de invitación.',
    }),
    password: z.string().min(8).openapi({
      description: 'Contraseña que el docente quiere fijar (mínimo 8 caracteres).',
    }),
  })
  .strict()
  .openapi('CuerpoActivarCuenta');

const RespuestaInvitacion = z
  .object({
    email: z.string().email(),
    expiraEn: z.string().openapi({
      description: 'Instante ISO tras el cual la invitación ya no sirve (48 h).',
    }),
    enlaceActivacion: z.string().openapi({
      description:
        'Enlace que el profesor debe abrir. Se devuelve aquí para que el flujo sea ' +
        'probable aunque el correo no llegue (sin dominio verificado en Resend).',
    }),
    correoEnviado: z.boolean().openapi({
      description: 'Si Resend aceptó el envío. Si es false, usar enlaceActivacion.',
    }),
  })
  .openapi('RespuestaInvitacion');

const RespuestaActivacion = z
  .object({
    email: z.string().email(),
    perfil: Perfil,
  })
  .openapi('RespuestaActivacion');

// --------------------------------------------------------------- módulo 2 ---

const TipoPrograma = z.enum(['CARRERA', 'CURSO_LIBRE']).openapi('TipoPrograma');

const Programa = z
  .object({
    id: z.string().uuid(),
    codigo: z.string().openapi({
      description: 'Código institucional corto (máx. 12). MAYÚSCULAS, dígitos y guiones.',
    }),
    nombre: z.string(),
    tipo: TipoPrograma,
    requierePasantia: z.boolean().openapi({
      description:
        'Si es true, M8 exige el aval del tutor industrial antes de declarar EGRESADO al estudiante.',
    }),
    activo: z.boolean().openapi({
      description: 'false = borrador. Publicar es ponerlo en true, y eso dispara la Regla 1.',
    }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Programa');

const ProgramaConTotales = Programa.extend({
  totalMaterias: z.number().int().openapi({
    description:
      'Cuántas materias tiene el pensum. Cero en una CARRERA activa es un estado inválido (Regla 1).',
  }),
  totalPeriodos: z.number().int().openapi({
    description:
      'Cuántos períodos distintos cubre el pensum. Un pensum [1, 2, 5] son tres, no cinco.',
  }),
}).openapi('ProgramaConTotales');

const Materia = z
  .object({
    id: z.string().uuid(),
    codigo: z.string(),
    nombre: z.string(),
    horasAcademicas: z.number().int().openapi({ description: 'Carga horaria total. Siempre > 0.' }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Materia');

/** Lo que el cliente **manda** dentro de un pensum: sólo el id y el período. */
const EntradaPensum = z
  .object({
    materiaId: z.string().uuid(),
    periodo: z.number().int().min(1).openapi({ description: 'Período lógico. Empieza en 1.' }),
  })
  .strict()
  .openapi('EntradaPensum');

/** Lo que el cliente **recibe**: la entrada más los datos de la materia. */
const MateriaEnPensum = z
  .object({
    materiaId: z.string().uuid(),
    periodo: z.number().int(),
    codigo: z.string(),
    nombre: z.string(),
    horasAcademicas: z.number().int(),
  })
  .openapi('MateriaEnPensum');

const GrupoPensum = z
  .object({
    periodo: z.number().int(),
    materias: z.array(MateriaEnPensum),
  })
  .openapi('GrupoPensum');

const RespuestaProgramas = z
  .object({
    programas: z.array(ProgramaConTotales),
    total: z.number().int().openapi({
      description: 'Cuántas filas cumplen el filtro en total, no cuántas se devolvieron.',
    }),
    limite: z.number().int(),
    desplazamiento: z.number().int(),
  })
  .openapi('RespuestaProgramas');

const RespuestaDetallePrograma = z
  .object({
    programa: Programa,
    pensum: z.array(GrupoPensum).openapi({
      description:
        'Pensum agrupado por período. No incluye períodos vacíos: un pensum [1, 2, 5] devuelve tres grupos.',
    }),
    seccionesActivas: z.number().int().openapi({
      description: 'Secciones activas del período vigente que usan este programa.',
    }),
    editable: z.boolean().openapi({
      description:
        'false cuando la Regla 2 impide tocar el pensum (seccionesActivas > 0). La UI deshabilita el reordenamiento antes de que el usuario choque contra el 409.',
    }),
  })
  .openapi('RespuestaDetallePrograma');

const RespuestaPrograma = z.object({ programa: Programa }).openapi('RespuestaPrograma');

const RespuestaMaterias = z
  .object({
    materias: z.array(Materia),
    total: z.number().int(),
    limite: z.number().int(),
    desplazamiento: z.number().int(),
  })
  .openapi('RespuestaMaterias');

const RespuestaMateria = z.object({ materia: Materia }).openapi('RespuestaMateria');

const CuerpoCrearPrograma = z
  .object({
    codigo: z.string(),
    nombre: z.string(),
    tipo: TipoPrograma,
    requierePasantia: z.boolean().optional(),
    publicar: z.boolean().optional().openapi({
      description: 'Decide el `isActive` inicial. Por defecto false: el programa nace en borrador.',
    }),
    pensum: z.array(EntradaPensum).min(1).openapi({
      description: 'Al menos una materia, y ninguna repetida.',
    }),
  })
  .strict()
  .openapi('CuerpoCrearPrograma');

const CuerpoActualizarPrograma = z
  .object({
    nombre: z.string().optional(),
    requierePasantia: z.boolean().optional(),
    activo: z.boolean().optional(),
  })
  .strict()
  .openapi('CuerpoActualizarPrograma');

const CuerpoReemplazarPensum = z
  .object({
    pensum: z.array(EntradaPensum).min(1).openapi({
      description:
        'El estado FINAL del pensum, no un parche: la base calcula qué borrar, qué reordenar y qué añadir.',
    }),
  })
  .strict()
  .openapi('CuerpoReemplazarPensum');

const CuerpoCrearMateria = z
  .object({
    codigo: z.string(),
    nombre: z.string(),
    horasAcademicas: z.number().int().positive(),
  })
  .strict()
  .openapi('CuerpoCrearMateria');

// ------------------------------------------------------------- cuadrante ---
//
// Módulo 3: trece rutas de administración bajo `/api/v1/admin` y una de lectura
// por rol en `/api/v1/mi-horario`.
//
// **`turno` es una columna generada y sólo viaja de salida.** La calcula
// `turno_de_bloque(block)` en PostgreSQL y aparece en los esquemas de respuesta,
// en ninguno de entrada: el `.strict()` de Zod convierte enviarla en un `400`
// que nombra el campo, en vez de ignorarla. Aceptar un turno que contradiga al
// bloque sería aceptar una agenda que miente.
//
// **El período de una clase tampoco se manda**: se deriva de la sección. Sólo
// aparece en la respuesta, ya resuelto.

const NOTA_TURNO =
  'Turno del bloque. DERIVADO de `block` por `turno_de_bloque()`: sólo viaja de ' +
  'salida, enviarlo es un 400.';

const Aula = z
  .object({
    id: z.string().uuid(),
    nombre: z.string().openapi({
      description: 'Nombre del espacio. Único en todo el centro: dos iguales harían imposible saber a cuál se refiere el cuadrante.',
    }),
    capacidad: z.number().int().openapi({
      description:
        'Cupo del espacio. 0 = sin cupo declarado (zonas, pasillos), que NO es lo mismo que desconocido.',
    }),
    esTaller: z.boolean().openapi({
      description:
        'Junto con `capacidad` decide la forma del espacio: TALLER, AULA o ZONA.',
    }),
    activa: z.boolean().openapi({
      description:
        'false = archivado. Un espacio con clases o guardias no se borra (la FK es `on delete restrict`): se archiva.',
    }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Aula');

const Periodo = z
  .object({
    id: z.string().uuid(),
    codigo: z.string().openapi({
      description:
        'Identidad del lapso (p. ej. "2026-1"). Es a lo que apuntan las secciones y lo que citan los documentos impresos; no se puede cambiar después de crearlo.',
    }),
    nombre: z.string().nullable().openapi({
      description:
        'Etiqueta para humanos. Existe porque el código está en disputa (R-06): permite escribir «Lapso 2026-1 (SA26-2)» sin tocar el código.',
    }),
    fechaInicio: z.string().nullable().openapi({
      description:
        'Anulable A PROPÓSITO: el centro no ha cargado las fechas reales y no se inventan (R-17). La UI debe mostrar «sin fechas cargadas».',
    }),
    fechaFin: z.string().nullable(),
    activo: z.boolean().openapi({
      description:
        '«Este lapso está abierto: se puede planificar en él». NO es lo mismo que `vigente`.',
    }),
    vigente: z.boolean().openapi({
      description:
        '«Este es el lapso en curso». Derivado de `system_settings.periodo_activo`; no es una columna. Puede haber varios abiertos y sólo uno vigente.',
    }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Periodo');

const Guardia = z
  .object({
    id: z.string().uuid(),
    docenteId: z.string().uuid(),
    aulaId: z.string().uuid(),
    periodo: z.string().openapi({
      description:
        'Lapso de la guardia. Obligatorio: sin él, una guardia del lunes a primera hora chocaría con las clases de cualquier lapso (R-15).',
    }),
    dia: z.number().int().openapi({
      description: '1 = lunes … 6 = sábado. El domingo queda fuera por requisito.',
    }),
    bloque: z.number().int().openapi({ description: 'Bloque horario, de 1 a 12.' }),
    turno: z.enum(['MAÑANA', 'TARDE']).openapi({ description: NOTA_TURNO }),
    notas: z.string().nullable(),
    activa: z.boolean().openapi({
      description:
        'false = archivada. Una guardia archivada no ocupa a nadie: el trigger sale antes de comprobar.',
    }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Guardia');

const ClaseCuadrante = z
  .object({
    id: z.string().uuid(),
    seccionId: z.string().uuid(),
    docenteId: z.string().uuid(),
    aulaId: z.string().uuid(),
    dia: z.number().int(),
    bloque: z.number().int(),
    turno: z.enum(['MAÑANA', 'TARDE']).openapi({ description: NOTA_TURNO }),
    activa: z.boolean(),
    periodo: z.string().openapi({
      description:
        'DERIVADO de la sección: la tabla no guarda el período, para no crear una segunda fuente de verdad que pueda desviarse.',
    }),
    programaId: z.string().uuid(),
    programa: z.string().openapi({
      description:
        'Especialidad de la cabecera de la rejilla. La vista ya lo resuelve, así que la pantalla no necesita una segunda llamada.',
    }),
    materiaId: z.string().uuid(),
    materia: z.string(),
    seccion: z.string(),
    aula: z.string(),
    docente: z.string().openapi({
      description:
        'Resuelto por `nombre_para_mostrar()`, no por un `join` contra `profiles`: para un estudiante la política `profiles_read_own` haría que el join devolviera NULL y su horario saldría sin profesor (R-14).',
    }),
  })
  .openapi('ClaseCuadrante');

const DocenteResumen = z
  .object({
    id: z.string().uuid(),
    nombre: z.string(),
  })
  .openapi('DocenteResumen');

const RespuestaAula = z.object({ aula: Aula }).openapi('RespuestaAula');

const RespuestaAulas = z
  .object({
    aulas: z.array(Aula),
    total: z.number().int().openapi({
      description: 'Cuántas filas cumplen el filtro en total, no cuántas se devolvieron.',
    }),
    limite: z.number().int(),
    desplazamiento: z.number().int(),
  })
  .openapi('RespuestaAulas');

const RespuestaPeriodo = z.object({ periodo: Periodo }).openapi('RespuestaPeriodo');

const RespuestaPeriodos = z
  .object({
    periodos: z.array(Periodo).openapi({
      description:
        'Catálogo completo, sin paginar: un centro acumula unos pocos lapsos al año y el desplegable los necesita todos para ofrecer el siguiente.',
    }),
  })
  .openapi('RespuestaPeriodos');

const RespuestaGuardia = z.object({ guardia: Guardia }).openapi('RespuestaGuardia');

const RespuestaGuardias = z
  .object({
    guardias: z.array(Guardia),
    total: z.number().int(),
    limite: z.number().int(),
    desplazamiento: z.number().int(),
  })
  .openapi('RespuestaGuardias');

const RespuestaClase = z.object({ clase: ClaseCuadrante }).openapi('RespuestaClase');

const RejillaCuadrante = z
  .object({
    periodo: z.string().nullable().openapi({
      description:
        'Lapso de la rejilla. `null` cuando no hay ninguno vigente y no se pidió uno: las listas de clases y guardias salen vacías, pero `aulas` y `docentes` siguen llenas para que la pantalla pueda decir qué pasa en vez de quedarse en blanco.',
    }),
    clases: z.array(ClaseCuadrante),
    guardias: z.array(Guardia),
    aulas: z.array(Aula).openapi({
      description:
        'Todas las aulas, activas primero. Se incluyen las archivadas para que una clase asignada antes de archivar su aula no quede en una celda huérfana.',
    }),
    docentes: z.array(DocenteResumen),
  })
  .openapi('RejillaCuadrante');

const MiHorario = z
  .object({
    rol: z.enum(['docente', 'estudiante']),
    periodo: z.string().nullable().openapi({
      description: '`null` cuando no hay lapso vigente declarado. No es un error: es un sistema sin lapso en curso.',
    }),
    clases: z.array(ClaseCuadrante).openapi({
      description:
        'Docente: sus clases. Estudiante: las de las secciones en las que está matriculado. El aislamiento lo impone la RLS.',
    }),
    guardias: z.array(Guardia).openapi({
      description:
        'Docente: las suyas. Estudiante: SIEMPRE vacío — las guardias no son información del alumno, y `teacher_duties` no tiene política para su rol.',
    }),
  })
  .openapi('MiHorario');

const CuerpoCrearAula = z
  .object({
    nombre: z.string(),
    capacidad: z.number().int().min(0).optional().openapi({
      description: 'Por defecto 0, que significa «sin cupo declarado» (una zona).',
    }),
    esTaller: z.boolean().optional(),
  })
  .strict()
  .openapi('CuerpoCrearAula');

const CuerpoActualizarAula = z
  .object({
    nombre: z.string().optional(),
    capacidad: z.number().int().min(0).optional(),
    esTaller: z.boolean().optional(),
    activa: z.boolean().optional(),
  })
  .strict()
  .openapi('CuerpoActualizarAula');

const CuerpoCrearPeriodo = z
  .object({
    codigo: z.string().openapi({
      description: 'MAYÚSCULAS o minúsculas, dígitos y guiones, hasta 10 caracteres. Único.',
    }),
    nombre: z.string().optional(),
    fechaInicio: z.string().optional().openapi({
      description: 'AAAA-MM-DD. Opcional: el centro carga las fechas cuando las tiene.',
    }),
    fechaFin: z.string().optional(),
  })
  .strict()
  .openapi('CuerpoCrearPeriodo');

const CuerpoActualizarPeriodo = z
  .object({
    nombre: z.string().nullable().optional(),
    fechaInicio: z.string().nullable().optional().openapi({
      description: '`null` vacía la fecha, que es una intención legítima.',
    }),
    fechaFin: z.string().nullable().optional(),
    activo: z.boolean().optional(),
  })
  .strict()
  .openapi('CuerpoActualizarPeriodo');

const CuerpoCrearGuardia = z
  .object({
    docenteId: z.string().uuid(),
    aulaId: z.string().uuid(),
    periodo: z.string(),
    dia: z.number().int(),
    bloque: z.number().int(),
    notas: z.string().nullable().optional(),
  })
  .strict()
  .openapi('CuerpoCrearGuardia');

const CuerpoActualizarGuardia = z
  .object({
    docenteId: z.string().uuid().optional(),
    aulaId: z.string().uuid().optional(),
    periodo: z.string().optional(),
    dia: z.number().int().optional(),
    bloque: z.number().int().optional(),
    notas: z.string().nullable().optional(),
    activa: z.boolean().optional().openapi({
      description: 'false archiva la guardia y libera el hueco: no se borra.',
    }),
  })
  .strict()
  .openapi('CuerpoActualizarGuardia');

const CuerpoCrearClase = z
  .object({
    seccionId: z.string().uuid(),
    docenteId: z.string().uuid(),
    aulaId: z.string().uuid(),
    dia: z.number().int(),
    bloque: z.number().int(),
  })
  .strict()
  .openapi('CuerpoCrearClase');

const CuerpoActualizarClase = z
  .object({
    seccionId: z.string().uuid().optional(),
    docenteId: z.string().uuid().optional(),
    aulaId: z.string().uuid().optional(),
    dia: z.number().int().optional(),
    bloque: z.number().int().optional(),
    activa: z.boolean().optional(),
  })
  .strict()
  .openapi('CuerpoActualizarClase');

const ParametroIdPrograma = z.object({
  id: z.string().uuid().openapi({
    param: { name: 'id', in: 'path' },
    example: '46342064-c05a-4341-8638-f35c2541718c',
    description:
      'UUID del programa. Un valor que no sea UUID se rechaza con 400 antes de tocar la base.',
  }),
});

const parametrosListadoProgramas = z.object({
  tipo: TipoPrograma.optional().openapi({
    param: { name: 'tipo', in: 'query' },
    description: 'Filtra por tipo de oferta. Sin él, carreras y cursos libres.',
  }),
  activo: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'activo', in: 'query' },
    description:
      'Filtra publicados (true) o borradores (false). Ausente = todos. Un valor distinto se rechaza con 400.',
  }),
  busqueda: z.string().optional().openapi({
    param: { name: 'busqueda', in: 'query' },
    description: 'Texto libre sobre el código y el nombre. Insensible a mayúsculas.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

const parametrosListadoMaterias = z.object({
  busqueda: z.string().optional().openapi({
    param: { name: 'busqueda', in: 'query' },
    description: 'Texto libre sobre el código y el nombre. Insensible a mayúsculas.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

const ParametroClave = z.object({
  clave: z.string().openapi({
    param: { name: 'clave', in: 'path' },
    example: 'm0_cpanel',
    description: 'Clave del módulo o del parámetro.',
  }),
});

const ParametroIdPerfil = z.object({
  id: z.string().uuid().openapi({
    param: { name: 'id', in: 'path' },
    example: '46342064-c05a-4341-8638-f35c2541718c',
    description:
      'UUID del perfil. Un valor que no sea UUID se rechaza con 400 antes de tocar la base.',
  }),
});

const parametroLimiteAuditoria = z.object({
  limite: z.coerce.number().int().min(1).max(200).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Máximo de entradas a devolver. Por defecto 50.',
  }),
});

const parametrosListadoUsuarios = z.object({
  rol: rolSchema.optional().openapi({
    param: { name: 'rol', in: 'query' },
    description: 'Filtra por rol. Sin este parámetro, todos los roles.',
  }),
  activo: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'activo', in: 'query' },
    description:
      'Filtra por estado de la cuenta. Un valor distinto de `true` o `false` se rechaza con 400.',
  }),
  busqueda: z.string().optional().openapi({
    param: { name: 'busqueda', in: 'query' },
    description:
      'Texto libre sobre nombres, apellidos, correo y cédula. Insensible a mayúsculas.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

const parametrosListadoAcceso = z.object({
  estado: z.enum(['SUCCESS', 'FAILED']).optional().openapi({
    param: { name: 'estado', in: 'query' },
    description: 'Filtra por resultado del intento. Sin él, ambos.',
  }),
  email: z.string().optional().openapi({
    param: { name: 'email', in: 'query' },
    description: 'Filtra por correo exacto (no parcial).',
  }),
  userId: z.string().uuid().optional().openapi({
    param: { name: 'userId', in: 'query' },
    description: 'Filtra por UUID de usuario de auth. Un valor no UUID se rechaza con 400.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

/** Fábrica de parámetros de ruta para un `:id`, con el mensaje de UUID ya escrito. */
function parametroIdDeRecurso(recurso: string) {
  return z.object({
    id: z.string().uuid().openapi({
      param: { name: 'id', in: 'path' },
      example: '46342064-c05a-4341-8638-f35c2541718c',
      description: `UUID del ${recurso}. Un valor que no sea UUID se rechaza con 400 antes de tocar la base.`,
    }),
  });
}

const ParametroIdAula = parametroIdDeRecurso('espacio');
const ParametroIdPeriodo = parametroIdDeRecurso('lapso');
const ParametroIdGuardia = parametroIdDeRecurso('guardia');
const ParametroIdClase = parametroIdDeRecurso('clase del cuadrante');

const parametrosListadoAulas = z.object({
  busqueda: z.string().optional().openapi({
    param: { name: 'busqueda', in: 'query' },
    description: 'Texto libre sobre el nombre del espacio. Insensible a mayúsculas.',
  }),
  tipo: z.enum(['TALLER', 'ZONA', 'AULA']).optional().openapi({
    param: { name: 'tipo', in: 'query' },
    description:
      'Talleres, zonas o aulas. Las tres formas son excluyentes y cubren todos los espacios: ninguna queda fuera del filtro sin que se diga.',
  }),
  activa: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'activa', in: 'query' },
    description:
      'Filtra activas (true) o archivadas (false). Ausente = todas. Un valor distinto se rechaza con 400.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

const parametrosListadoGuardias = z.object({
  periodo: z.string().optional().openapi({
    param: { name: 'periodo', in: 'query' },
    description: 'Código del lapso. Sin él, las guardias de todos los lapsos.',
  }),
  docenteId: z.string().uuid().optional().openapi({
    param: { name: 'docenteId', in: 'query' },
    description: 'Sólo las guardias de ese docente.',
  }),
  aulaId: z.string().uuid().optional().openapi({
    param: { name: 'aulaId', in: 'query' },
    description: 'Sólo las guardias de ese espacio.',
  }),
  dia: z.coerce.number().int().min(1).max(6).optional().openapi({
    param: { name: 'dia', in: 'query' },
    description: '1 = lunes … 6 = sábado.',
  }),
  bloque: z.coerce.number().int().min(1).max(12).optional().openapi({
    param: { name: 'bloque', in: 'query' },
    description: 'Bloque horario.',
  }),
  activa: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'activa', in: 'query' },
    description: 'Filtra vigentes (true) o archivadas (false). Ausente = todas.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

const parametrosRejilla = z.object({
  periodo: z.string().optional().openapi({
    param: { name: 'periodo', in: 'query' },
    description: 'Lapso del que se pide la rejilla. Ausente = el vigente.',
  }),
  seccionId: z.string().uuid().optional().openapi({
    param: { name: 'seccionId', in: 'query' },
    description:
      'Sólo las clases de esa sección. NO filtra las guardias: una guardia no pertenece a ninguna sección.',
  }),
  docenteId: z.string().uuid().optional().openapi({
    param: { name: 'docenteId', in: 'query' },
    description: 'Sólo las clases y guardias de ese docente.',
  }),
  aulaId: z.string().uuid().optional().openapi({
    param: { name: 'aulaId', in: 'query' },
    description: 'Sólo las clases y guardias de ese espacio.',
  }),
  incluirInactivas: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'incluirInactivas', in: 'query' },
    description: 'Incluir clases y guardias archivadas. Por defecto false.',
  }),
});

const parametroMiHorario = z.object({
  periodo: z.string().optional().openapi({
    param: { name: 'periodo', in: 'query' },
    description:
      'Lapso del que se pide el horario. Ausente = el vigente. Se admite otro porque un docente planifica el siguiente mientras dicta el actual.',
  }),
});

// --------------------------------------------------------- inscripciones ---
//
// Módulo 4: cinco rutas de estudiante bajo `/api/v1` y ocho de administración
// bajo `/api/v1/admin`, más el catálogo de secciones.
//
// **Aquí no se documenta ninguna regla de cupo como si la decidiera la API.**
// Las decide PostgreSQL, dentro de las RPC `security definer` y de un cerrojo por
// sección. Lo que este contrato describe es lo que la API **traduce**, y por eso
// los códigos de error importan más de lo normal: `ACAPARAMIENTO_DE_MATERIA`,
// `REQUIERE_REINCORPORACION`, `SECCION_ARCHIVADA` y `OFERTA_VENCIDA` son todos
// `23514` en la base, y sin separarlos el cliente no podría decir nada útil.
//
// **`ofertaVigente` no es informativo: es la barrera contra la doble venta.**
// Como `cupos_ocupados` cuenta sólo `ENROLLED`, `cuposDisponibles` puede ser > 0
// mientras una oferta está en el aire. La interfaz debe mirar `ofertaVigente` y
// no el contador, o prometerá un asiento que la base va a negar.

const EstadoInscripcion = z
  .enum(['ENROLLED', 'WAITLISTED', 'PENDING_BID', 'DROPPED'])
  .openapi('EstadoInscripcion');

const Seccion = z
  .object({
    id: z.string().uuid(),
    programaId: z.string().uuid(),
    materiaId: z.string().uuid(),
    periodo: z.string().openapi({
      description: 'Código del lapso al que pertenece la sección.',
    }),
    nombre: z.string().openapi({
      description:
        'Identificador corto dentro del lapso ("SA", "SC"), de hasta 5 caracteres. El nombre largo de la materia vive en `subjects.name`.',
    }),
    cupoMaximo: z.number().int().nullable().openapi({
      description:
        'Cupo declarado. `null` = usa el global del centro (`cupo_maximo_por_seccion`). `0` = sección sin cupo, y NO es lo mismo: sólo `null` cae al global.',
    }),
    activa: z.boolean().openapi({
      description:
        'false = archivada. No hay borrado: el `DELETE` está revocado en la base, y una sección borrada se llevaría el historial de inscripciones.',
    }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Seccion');

const OcupacionSeccion = z
  .object({
    seccionId: z.string().uuid(),
    periodo: z.string(),
    programaId: z.string().uuid(),
    programaNombre: z.string().nullable(),
    materiaId: z.string().uuid(),
    materiaNombre: z.string().nullable(),
    nombre: z.string(),
    activa: z.boolean(),
    cupoEfectivo: z.number().int().openapi({
      description:
        '`coalesce(max_capacity, cupo_maximo_por_seccion, 0)`. Es el número contra el que se decide si hay asiento.',
    }),
    cuposOcupados: z.number().int().openapi({
      description:
        'Asientos tomados. Cuenta SÓLO `ENROLLED`: una solicitud `PENDING_BID` no reserva cupo.',
    }),
    cuposDisponibles: z.number().int().openapi({
      description:
        'Cupo efectivo menos ocupados, nunca negativo. OJO: puede ser > 0 con una oferta en el aire. Para decidir si se puede ofrecer, usa `ofertaVigente`.',
    }),
    ofertaVigente: z.boolean().openapi({
      description:
        '¿Hay una oferta de cupo viva (no vencida) en esta sección? NO es informativo: es la barrera contra la doble venta. Con `ofertaVigente: true` el asiento está comprometido aunque `cuposDisponibles` diga otra cosa, y una solicitud nueva entrará a la lista de espera.',
    }),
  })
  .openapi('OcupacionSeccion');

const Inscripcion = z
  .object({
    id: z.string().uuid(),
    estudianteId: z.string().uuid(),
    seccionId: z.string().uuid(),
    estado: EstadoInscripcion,
    ofertaVenceEn: z.string().nullable().openapi({
      description:
        'Vencimiento de la oferta. Sólo tiene valor en `PENDING_BID`. Pasada la fecha, la oferta se puede vencer con `POST /api/v1/admin/inscripciones/expirar`.',
    }),
    creadoEn: z.string(),
    actualizadoEn: z.string(),
  })
  .openapi('Inscripcion');

const InscripcionDetallada = Inscripcion.extend({
  periodo: z.string(),
  seccionNombre: z.string(),
  materiaId: z.string().uuid(),
  materiaNombre: z.string().nullable(),
  programaId: z.string().uuid(),
  programaNombre: z.string().nullable(),
  posicionEnCola: z.number().int().nullable().openapi({
    description:
      'Posición en la cola FIFO, empezando en 1. `null` si no está en la cola: un `ENROLLED` no ocupa un turno.',
  }),
  estudianteNombre: z.string().nullable().optional().openapi({
    description: 'Sólo lo recibe el administrador. La RLS de `profiles` impide al estudiante verlo.',
  }),
  estudianteEmail: z.string().nullable().optional(),
}).openapi('InscripcionDetallada');

const RespuestaSecciones = z
  .object({
    secciones: z.array(Seccion),
    total: z.number().int(),
    limite: z.number().int(),
    desplazamiento: z.number().int(),
  })
  .openapi('RespuestaSecciones');

const RespuestaSeccion = z.object({ seccion: Seccion }).openapi('RespuestaSeccion');

const RespuestaOcupacion = z
  .object({
    secciones: z.array(OcupacionSeccion),
    total: z.number().int(),
    limite: z.number().int(),
    desplazamiento: z.number().int(),
  })
  .openapi('RespuestaOcupacion');

const RespuestaInscripciones = z
  .object({ inscripciones: z.array(InscripcionDetallada) })
  .openapi('RespuestaInscripciones');

const RespuestaCola = z
  .object({ cola: z.array(InscripcionDetallada) })
  .openapi('RespuestaCola');

const RespuestaEstadoInscripcion = z
  .object({
    estado: EstadoInscripcion,
    mensaje: z.string().openapi({
      description: 'Texto legible del estado, para no duplicar el mapa estado→etiqueta en el cliente.',
    }),
  })
  .openapi('RespuestaEstadoInscripcion');

const RespuestaPromocion = z
  .object({
    promovida: Inscripcion.nullable().openapi({
      description:
        'La inscripción promovida, o `null` si no había a nadie. **Un `null` no es un error**: la cola puede estar vacía, la sección llena, o ya haber una oferta en el aire. Es un 200 con explicación, no un 404.',
    }),
    mensaje: z.string(),
  })
  .openapi('RespuestaPromocion');

const RespuestaExpiracion = z
  .object({
    vencidas: z.number().int().openapi({
      description: 'Cuántas ofertas se vencieron. Idempotente: la segunda llamada devuelve 0.',
    }),
    mensaje: z.string(),
  })
  .openapi('RespuestaExpiracion');

const CuerpoCrearSeccion = z
  .object({
    programaId: z.string().uuid(),
    materiaId: z.string().uuid(),
    periodo: z.string().openapi({
      description: 'Código de un lapso ya registrado. Debe existir: la FK es `on delete restrict`.',
    }),
    nombre: z.string().max(5).openapi({
      description: 'Identificador corto ("SA"). Único por lapso y materia.',
    }),
    cupoMaximo: z.number().int().min(0).nullable().optional().openapi({
      description: 'Ausente o `null` = usar el cupo global. `0` = sección sin cupo.',
    }),
  })
  .strict()
  .openapi('CuerpoCrearSeccion');

const CuerpoActualizarSeccion = z
  .object({
    nombre: z.string().max(5).optional(),
    cupoMaximo: z.number().int().min(0).nullable().optional(),
    activa: z.boolean().optional().openapi({
      description: 'Archivar es esto: no hay borrado.',
    }),
  })
  .strict()
  .openapi('CuerpoActualizarSeccion');

const CuerpoSolicitarInscripcion = z
  .object({ seccionId: z.string().uuid() })
  .strict()
  .openapi('CuerpoSolicitarInscripcion');

const CuerpoReincorporar = z
  .object({
    estudianteId: z.string().uuid(),
    seccionId: z.string().uuid(),
  })
  .strict()
  .openapi('CuerpoReincorporar');

const parametrosListadoSecciones = z.object({
  busqueda: z.string().optional().openapi({
    param: { name: 'busqueda', in: 'query' },
    description: 'Texto libre sobre el nombre corto de la sección.',
  }),
  periodo: z.string().optional().openapi({
    param: { name: 'periodo', in: 'query' },
    description: 'Código del lapso. Ausente = todos.',
  }),
  programaId: z.string().uuid().optional().openapi({
    param: { name: 'programaId', in: 'query' },
    description: 'Filtra por programa de formación.',
  }),
  materiaId: z.string().uuid().optional().openapi({
    param: { name: 'materiaId', in: 'query' },
    description: 'Filtra por unidad curricular.',
  }),
  activa: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'activa', in: 'query' },
    description: 'Filtra activas (true) o archivadas (false). Ausente = todas.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

const parametrosListadoOfertas = z.object({
  busqueda: z.string().optional().openapi({
    param: { name: 'busqueda', in: 'query' },
    description: 'Texto libre sobre el nombre corto de la sección.',
  }),
  periodo: z.string().optional().openapi({
    param: { name: 'periodo', in: 'query' },
    description: 'Código del lapso. Ausente = todos.',
  }),
  programaId: z.string().uuid().optional().openapi({
    param: { name: 'programaId', in: 'query' },
    description: 'Filtra por programa de formación.',
  }),
  materiaId: z.string().uuid().optional().openapi({
    param: { name: 'materiaId', in: 'query' },
    description: 'Filtra por unidad curricular.',
  }),
  soloConCupo: z.enum(['true', 'false']).optional().openapi({
    param: { name: 'soloConCupo', in: 'query' },
    description:
      'Sólo secciones con asiento realmente ofrecible: con hueco Y sin oferta viva. NO es `cuposDisponibles > 0`, que mentiría con una oferta en el aire.',
  }),
  limite: z.coerce.number().int().min(1).max(100).optional().openapi({
    param: { name: 'limite', in: 'query' },
    description: 'Tamaño de página. Por defecto 25.',
  }),
  desplazamiento: z.coerce.number().int().min(0).optional().openapi({
    param: { name: 'desplazamiento', in: 'query' },
    description: 'Filas a saltar antes de esta página. Por defecto 0.',
  }),
});

// --- Módulo 5: archivos (Cloudflare R2) --------------------------------------

/**
 * Los metadatos de un archivo.
 *
 * `r2Key` se documenta porque el contrato describe lo que la API **devuelve**, no
 * porque el cliente pueda usarla: el backend firma las descargas, así que un
 * cliente nunca construye una ruta del bucket. Publicarla no abre nada —la
 * autorización la da la firma— y ocultarla obligaría a mentir sobre la forma de
 * la respuesta.
 */
const Archivo = z
  .object({
    id: z.string().uuid(),
    propietarioId: z.string().uuid(),
    r2Key: z.string().openapi({
      description: 'Clave del objeto en R2. La construye el servidor; no es una URL.',
    }),
    nombreOriginal: z.string().openapi({
      description: 'El nombre que eligió el usuario. Se aplica al descargar.',
    }),
    tipoContenido: z.string().openapi({
      description: 'Tipo MIME derivado de la extensión, nunca del que declare el cliente.',
    }),
    tamanoBytes: z.number().int().nullable().openapi({
      description: '`null` mientras está `PENDING`: una subida a medias todavía no se midió.',
    }),
    entityType: z.enum(['TASK_SUBMISSION', 'TEACHER_GUIDE']),
    entidadId: z.string().uuid().nullable().openapi({
      description: '`null` cuando la tarea o la guía todavía no existe.',
    }),
    estado: z.enum(['PENDING', 'CONFIRMED', 'DELETED']),
    creadoEn: z.string(),
    confirmadoEn: z.string().nullable(),
    borradoEn: z.string().nullable(),
  })
  .openapi('Archivo');

const RespuestaArchivo = z.object({ archivo: Archivo }).openapi('RespuestaArchivo');

/**
 * El cuerpo de la firma de subida.
 *
 * Se **reutiliza** el esquema real en lugar de reescribirlo aquí. El propio
 * documento declara que los esquemas Zod son el único contrato y que esto es una
 * proyección suya; una segunda copia sería justo la que se desvía sin que nadie
 * lo note, porque la deuda D6 sólo compara rutas, no cuerpos.
 *
 * No lleva ni la clave del objeto ni su tamaño, y las dos ausencias son
 * deliberadas: la clave la elige el servidor —una URL `PUT` firmada es una
 * autorización de escritura y alcanzaría a cualquier objeto del bucket— y el
 * tamaño no se puede validar antes de subir.
 */
const CuerpoFirmarSubida = esquemaFirmarSubida.openapi('CuerpoFirmarSubida');

const RespuestaFirmaSubida = z
  .object({
    archivo: Archivo,
    urlDeSubida: z.string().openapi({
      description:
        'URL `PUT` prefirmada. Caduca: hay que subir antes de que pasen `expiraEnSegundos`.',
    }),
    expiraEnSegundos: z.number().int(),
  })
  .openapi('RespuestaFirmaSubida');

const RespuestaUrlLectura = z
  .object({
    urlDeLectura: z.string().openapi({
      description: 'URL `GET` prefirmada, de vida corta.',
    }),
    expiraEnSegundos: z.number().int(),
    nombreOriginal: z.string(),
  })
  .openapi('RespuestaUrlLectura');

const ParametroIdArchivo = parametroIdDeRecurso('archivo');

/** Respuestas de error reutilizables. Se documentan los códigos, no un texto. */
function error(descripcion: string) {
  return {
    description: descripcion,
    content: { 'application/json': { schema: CuerpoError } },
  };
}

const RESPUESTAS_ERROR = {
  400: error('Petición inválida. El cuerpo o los parámetros no pasan la validación.'),
  401: error('Falta la sesión o el token no es válido.'),
  403: error('La sesión es válida pero el rol no alcanza, o la cuenta está inactiva.'),
  404: error('El recurso no existe.'),
  409: error('La regla de negocio impide la operación.'),
  410: error('El recurso solicitado ha caducado.'),
  413: error('El contenido supera el tamaño máximo permitido.'),
  500: error('Fallo interno.'),
  503: error('El servicio o la base de datos no están disponibles.'),
};

/**
 * Construye el registro con todas las rutas documentadas.
 *
 * Se exporta el registro (y no sólo el documento) para que las pruebas puedan
 * inspeccionar las rutas declaradas y compararlas con las reales de Fastify.
 */
export function construirRegistro(): OpenAPIRegistry {
  const registro = new OpenAPIRegistry();

  registro.registerComponent('securitySchemes', 'bearerAuth', {
    type: 'http',
    scheme: 'bearer',
    bearerFormat: 'JWT',
    description:
      'Token de acceso de Supabase Auth. El backend lo verifica contra GoTrue en cada petición.',
  });

  // ---------------------------------------------------------------- salud ---
  registro.registerPath({
    method: 'get',
    path: '/salud',
    tags: ['Salud'],
    summary: 'Sonda de vida (liveness)',
    description:
      'No toca la base de datos. Si falla, el proceso está muerto y el orquestador debe reiniciarlo.',
    responses: {
      200: {
        description: 'El proceso responde.',
        content: { 'application/json': { schema: Version } },
      },
    },
  });

  registro.registerPath({
    method: 'get',
    path: '/salud/profundo',
    tags: ['Salud'],
    summary: 'Sonda de preparación (readiness)',
    description:
      'Comprueba la base de datos. Si falla, el proceso vive pero no debe recibir tráfico.',
    responses: {
      200: {
        description: 'La base de datos responde.',
        content: { 'application/json': { schema: SondaProfunda } },
      },
      503: {
        description: 'La base de datos no responde.',
        content: { 'application/json': { schema: SondaProfunda } },
      },
    },
  });

  registro.registerPath({
    method: 'get',
    path: '/openapi.json',
    tags: ['Salud'],
    summary: 'Este mismo documento',
    description:
      'Se genera en cada petición a partir de los esquemas Zod, así que lo servido y lo que valida la API no pueden separarse. Público: los generadores de cliente lo necesitan sin credenciales.',
    responses: {
      200: {
        description: 'Documento OpenAPI 3.1.',
        content: { 'application/json': { schema: z.object({}).passthrough() } },
      },
    },
  });

  // ------------------------------------------------------------ sesión -------
  registro.registerPath({
    method: 'get',
    path: '/api/v1/yo',
    tags: ['Sesión'],
    summary: 'Identidad y módulos visibles del llamante',
    description:
      'Es la llamada que hace el frontend al arrancar: devuelve quién es, con qué rol, y sólo los módulos que puede ver. Con esto la UI se construye sin conocer la lista de módulos.',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Perfil resuelto.',
        content: { 'application/json': { schema: RespuestaYo } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    method: 'get',
    path: '/api/v1/modulos',
    tags: ['Sesión'],
    summary: 'Módulos visibles para el rol del llamante',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Lista filtrada por rol y por estado de habilitación.',
        content: { 'application/json': { schema: RespuestaModulos } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  // --------------------------------------------------- administrador maestro --
  const admin = { tags: ['Administrador Maestro'] };

  registro.registerPath({
    ...admin,
    method: 'get',
    path: '/api/v1/admin/modulos',
    summary: 'Todos los módulos, incluidos los apagados',
    description:
      'A diferencia de `/api/v1/modulos`, no filtra por rol ni por habilitación: es la vista del panel.',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Los nueve módulos del sistema.',
        content: { 'application/json': { schema: RespuestaModulos } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'patch',
    path: '/api/v1/admin/modulos/{clave}',
    summary: 'Enciende, apaga o reordena un módulo',
    description:
      'Apagar `m0_cpanel` devuelve 409 MODULO_CRITICO: dejaría al administrador fuera del sistema. La base de datos tiene un trigger que impone la misma regla, para que no se pueda eludir desde el editor SQL.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroClave,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCambiosModulo } },
      },
    },
    responses: {
      200: {
        description: 'Módulo actualizado.',
        content: { 'application/json': { schema: RespuestaModulo } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: RESPUESTAS_ERROR[404],
      409: error('Se intentó apagar un módulo crítico.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'get',
    path: '/api/v1/admin/parametros',
    summary: 'Todos los parámetros, públicos y privados',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Listado completo de parámetros.',
        content: { 'application/json': { schema: RespuestaParametros } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'patch',
    path: '/api/v1/admin/parametros/{clave}',
    summary: 'Cambia el valor de un parámetro',
    description:
      'El valor debe encajar con el `tipo` declarado del parámetro. Sin esa comprobación, `max_faltas_consecutivas` podría quedar guardado como "tres" y el módulo de asistencia empezaría a comportarse de forma impredecible lejos del sitio donde se cometió el error.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroClave,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoValorParametro } },
      },
    },
    responses: {
      200: {
        description: 'Parámetro actualizado.',
        content: { 'application/json': { schema: RespuestaParametro } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: RESPUESTAS_ERROR[404],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'get',
    path: '/api/v1/admin/auditoria',
    summary: 'Últimas entradas del registro de auditoría',
    security: [{ bearerAuth: [] }],
    request: { query: parametroLimiteAuditoria },
    responses: {
      200: {
        description: 'Entradas más recientes primero.',
        content: { 'application/json': { schema: RespuestaAuditoria } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'get',
    path: '/api/v1/admin/acceso',
    summary: 'Traza de accesos (logins y fallos de autenticación) con filtros',
    description:
      'Lee `auth_logs` para que el administrador audite inicios de sesión, IPs y ' +
      'fallos de autenticación. Soporta filtro por resultado, correo o usuario, y ' +
      'paginación. El filtro y el recorte se aplican en la base de datos; `total` ' +
      'es el número de filas que cumplen el filtro, no las devueltas.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoAcceso },
    responses: {
      200: {
        description: 'Una página de accesos, del más reciente al más antiguo.',
        content: { 'application/json': { schema: RespuestaAcceso } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'get',
    path: '/api/v1/admin/usuarios',
    summary: 'Listado paginado de usuarios, con filtros',
    description:
      'El filtro y el recorte se aplican en la base de datos. `total` es el número de filas que cumplen el filtro, no las devueltas: sin él la pantalla no puede saber cuántas páginas quedan. La búsqueda es un `ilike` sin índices trigram; suficiente para un centro de formación y anotado por si la tabla crece.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoUsuarios },
    responses: {
      200: {
        description: 'Una página de usuarios, ordenados por apellido y nombre.',
        content: { 'application/json': { schema: RespuestaUsuarios } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'patch',
    path: '/api/v1/admin/usuarios/{id}/rol',
    summary: 'Cambia el rol de un usuario',
    description:
      'No se puede degradar al propio administrador (409 AUTO_DEGRADACION) ni al último administrador activo (409 ULTIMO_ADMIN). La regla vive en la base de datos, no sólo aquí: la API no ve el camino de `active = false`, el borrado, ni la carrera entre dos degradaciones simultáneas.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdPerfil,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCambioRol } },
      },
    },
    responses: {
      200: {
        description: 'Rol actualizado.',
        content: { 'application/json': { schema: RespuestaPerfil } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: error('Sólo el Administrador Maestro puede cambiar roles.'),
      404: error('El perfil no existe (PERFIL_INEXISTENTE).'),
      409: error('AUTO_DEGRADACION o ULTIMO_ADMIN.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...admin,
    method: 'post',
    path: '/api/v1/admin/usuarios/invitaciones',
    summary: 'Invita a un docente por correo (token de un solo uso)',
    description:
      'El administrador aporta el correo y el nombre real del docente (nombres y ' +
      'apellidos). El servidor genera un token, guarda SOLO su huella en la base y ' +
      'envía el enlace de activación. El enlace también se devuelve en la respuesta ' +
      'para poder probar el flujo aunque el correo no llegue. Los nombres viajan en ' +
      'user_metadata al activar, así el cuadrante muestra el nombre del docente (R-21).',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCorreoInvitacion } },
      },
    },
    responses: {
      200: {
        description: 'Invitación creada.',
        content: { 'application/json': { schema: RespuestaInvitacion } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    method: 'post',
    path: '/api/v1/auth/activar',
    tags: ['Sesión'],
    summary: 'Activa una invitación de docente y fija la contraseña',
    description:
      'Ruta PÚBLICA: el profesor aún no tiene sesión. La barrera es el token de un ' +
      'solo uso, no un JWT. Si el token es válido, crea la cuenta ya confirmada, la ' +
      'promueve a DOCENTE y marca la invitación como usada.',
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActivarCuenta } },
      },
    },
    responses: {
      200: {
        description: 'Cuenta activada y promovida a docente.',
        content: { 'application/json': { schema: RespuestaActivacion } },
      },
      400: RESPUESTAS_ERROR[400],
      404: error('El token no corresponde a ninguna invitación válida.'),
      409: error('INVITACION_YA_USADA: el token ya fue consumido.'),
      410: error('La invitación caducó (48 h).'),
      500: RESPUESTAS_ERROR[500],
    },
  });

  // ------------------------------------------------------------- currículo ---
  //
  // Las dos escrituras que necesitan atomicidad —crear el programa con su
  // pensum y reemplazar el pensum— van por funciones de PostgreSQL llamadas con
  // `supabase.rpc(...)`, no por un `insert` anidado. PostgREST no admite
  // insertar un padre con sus hijos en la misma petición y no expone
  // transacciones entre peticiones; se comprobó contra la base real. El
  // contrato para el cliente es el mismo que pedía el documento de
  // arquitectura: **una petición, todo o nada**.
  const curriculo = { tags: ['Currículo'] };

  registro.registerPath({
    ...curriculo,
    method: 'get',
    path: '/api/v1/admin/programas',
    summary: 'Listado paginado de programas, con los totales de cada pensum',
    description:
      '`totalMaterias` y `totalPeriodos` llegan en la misma consulta que la página, no en N+1: la pantalla necesita saber si un programa está vacío para avisar antes de que el administrador intente publicarlo. `total` es el número de filas que cumplen el filtro, no las devueltas.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoProgramas },
    responses: {
      200: {
        description: 'Una página de programas, ordenados por nombre.',
        content: { 'application/json': { schema: RespuestaProgramas } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...curriculo,
    method: 'get',
    path: '/api/v1/admin/programas/{id}',
    summary: 'Detalle de un programa con el pensum agrupado por período',
    description:
      'Devuelve además `seccionesActivas` y `editable`, que es la Regla 2 materializada: cuando hay secciones activas del período vigente, `editable` es false y la UI deshabilita el reordenamiento antes de que el usuario choque contra el 409.',
    security: [{ bearerAuth: [] }],
    request: { params: ParametroIdPrograma },
    responses: {
      200: {
        description: 'Detalle del programa.',
        content: { 'application/json': { schema: RespuestaDetallePrograma } },
      },
      400: error('El `id` no es un UUID válido (PETICION_INVALIDA).'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('El programa no existe (PROGRAMA_INEXISTENTE).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...curriculo,
    method: 'post',
    path: '/api/v1/admin/programas',
    summary: 'El asistente: crea un programa con su pensum, en una sola transacción',
    description:
      'Una sola petición con todo. Se ejecuta dentro de una función de PostgreSQL, así que un fallo no deja un programa a medio armar: o queda el programa con su pensum, o no queda nada. Publicar (`publicar: true`) sobre un pensum que la base rechace deshace la operación entera.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearPrograma } },
      },
    },
    responses: {
      201: {
        description: 'Programa creado, con su pensum ya agrupado.',
        content: { 'application/json': { schema: RespuestaDetallePrograma } },
      },
      400: error(
        'Fallo de validación (código con formato inválido, pensum vacío o materia repetida), ' +
          'referencia a una materia inexistente (REFERENCIA_INVALIDA) o Regla 1 (RESTRICCION_VIOLADA).',
      ),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error('El código del programa ya existe (REGISTRO_DUPLICADO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...curriculo,
    method: 'patch',
    path: '/api/v1/admin/programas/{id}',
    summary: 'Cambia los metadatos de un programa',
    description:
      'Sólo `nombre`, `requierePasantia` y `activo`. `codigo` y `tipo` son la identidad del programa: `sections` (M3) apunta a él y un código cambiado rompe cualquier documento impreso que lo cite. Publicar un programa sin materias es un 400 RESTRICCION_VIOLADA desde el trigger diferido de la Regla 1.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdPrograma,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActualizarPrograma } },
      },
    },
    responses: {
      200: {
        description: 'Programa actualizado.',
        content: { 'application/json': { schema: RespuestaPrograma } },
      },
      400: error('Ningún cambio indicado, o Regla 1: una carrera activa sin materias.'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: RESPUESTAS_ERROR[404],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...curriculo,
    method: 'patch',
    path: '/api/v1/admin/programas/{id}/pensum',
    summary: 'Reemplaza el pensum completo de un programa',
    description:
      'Es un reemplazo, no un parche: el cliente manda el estado final y la base calcula la diferencia (borrar lo que sobra, reordenar lo que cambia, insertar lo nuevo), todo en una transacción. Si la Regla 2 bloquea, la operación se rechaza entera y el pensum queda intacto.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdPrograma,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoReemplazarPensum } },
      },
    },
    responses: {
      200: {
        description: 'Pensum reemplazado, con el detalle ya actualizado.',
        content: { 'application/json': { schema: RespuestaDetallePrograma } },
      },
      400: error(
        'Pensum vacío o con materias repetidas (PETICION_INVALIDA), materia inexistente ' +
          '(REFERENCIA_INVALIDA) o Regla 1 (RESTRICCION_VIOLADA).',
      ),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('El programa no existe (PROGRAMA_INEXISTENTE).'),
      409: error(
        'PENSUM_EN_USO: hay secciones activas del período vigente usando el programa (Regla 2). ' +
          'Archive esas secciones primero, o clone el programa.',
      ),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...curriculo,
    method: 'get',
    path: '/api/v1/admin/materias',
    summary: 'Banco global de materias, paginado',
    description:
      'Alimenta la columna izquierda del paso 2 del asistente, con buscador en tiempo real. Una materia existe una vez y se comparte entre programas.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoMaterias },
    responses: {
      200: {
        description: 'Una página de materias, ordenadas por nombre.',
        content: { 'application/json': { schema: RespuestaMaterias } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...curriculo,
    method: 'post',
    path: '/api/v1/admin/materias',
    summary: 'Registra una materia en el banco global',
    description:
      'Es el «registrar materia en caliente» del paso 2: el administrativo descubre a mitad del asistente que falta una materia y la crea sin salir. Un código repetido da 409: la UI debe ofrecer seleccionar la existente, porque ése es el caso frecuente.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearMateria } },
      },
    },
    responses: {
      201: {
        description: 'Materia creada.',
        content: { 'application/json': { schema: RespuestaMateria } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error('El código de la materia ya existe (REGISTRO_DUPLICADO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  // ------------------------------------------------------------ cuadrante ---
  //
  // Las trece rutas de administración escriben **una fila en una tabla**: no hay
  // agregado que crear de golpe, así que ninguna pasa por una función de
  // PostgreSQL —a diferencia de M2, donde crear un programa con su pensum sí
  // necesitaba una—.
  //
  // Lo que sí vive en la base es la guarda anti-colisión, y **ninguna ruta
  // pregunta «¿está libre?» antes de escribir**: preguntar y luego escribir es
  // una carrera, y la respuesta buena la da la escritura. El `409
  // CHOQUE_DE_AGENDA` es la traducción de esa guarda.
  const cuadrante = { tags: ['Cuadrante'] };

  registro.registerPath({
    ...cuadrante,
    method: 'get',
    path: '/api/v1/admin/aulas',
    summary: 'Listado paginado de espacios (aulas, talleres y zonas)',
    description:
      'Un solo concepto de espacio con tres formas, derivadas de `esTaller` y `capacidad`. No hay una tabla de zonas aparte a propósito: la guardia anti-colisión vigila un único sitio, y con dos tablas habría que duplicar el chequeo y mantener las dos copias de acuerdo.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoAulas },
    responses: {
      200: {
        description: 'Una página de espacios, ordenados por nombre.',
        content: { 'application/json': { schema: RespuestaAulas } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'post',
    path: '/api/v1/admin/aulas',
    summary: 'Registra un espacio del centro',
    description:
      'No hay semilla de aulas y es deliberado: inventar el inventario del CFS habría sido fabricar dato institucional (R-18). Hasta que el centro cargue sus espacios, la lista sale vacía y **el cuadrante no se puede usar**, porque una clase sin aula no existe.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearAula } },
      },
    },
    responses: {
      201: {
        description: 'Espacio registrado.',
        content: { 'application/json': { schema: RespuestaAula } },
      },
      400: error('Nombre en blanco o capacidad negativa (PETICION_INVALIDA).'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error('El nombre del espacio ya existe (REGISTRO_DUPLICADO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'patch',
    path: '/api/v1/admin/aulas/{id}',
    summary: 'Cambia el nombre, el cupo, la forma o el estado de un espacio',
    description:
      'No borra: `activa: false` archiva. La FK de `classrooms` en las dos tablas de agenda es `on delete restrict`, así que borrar un espacio en uso no es posible ni por accidente.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdAula,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActualizarAula } },
      },
    },
    responses: {
      200: {
        description: 'Espacio actualizado.',
        content: { 'application/json': { schema: RespuestaAula } },
      },
      400: error('Ningún cambio indicado, o un valor fuera de rango.'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('El espacio no existe (AULA_INEXISTENTE).'),
      409: error('El nombre nuevo ya lo usa otro espacio (REGISTRO_DUPLICADO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'get',
    path: '/api/v1/admin/periodos',
    summary: 'Catálogo de lapsos, con cuál es el vigente',
    description:
      'Sin paginar: un centro acumula unos pocos lapsos al año y el desplegable los necesita todos para ofrecer el siguiente. `activo` y `vigente` son dos cosas distintas y por eso son dos campos.',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Todos los lapsos, el más reciente primero.',
        content: { 'application/json': { schema: RespuestaPeriodos } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'post',
    path: '/api/v1/admin/periodos',
    summary: 'Registra un lapso académico',
    description:
      'Da identidad al período: desde M3, `sections.period_code` es una clave ajena contra este catálogo, así que abrir una sección en un lapso inexistente falla al guardar. Eso convierte la divergencia silenciosa de R-06 en un error visible.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearPeriodo } },
      },
    },
    responses: {
      201: {
        description: 'Lapso registrado, cerrado y no vigente.',
        content: { 'application/json': { schema: RespuestaPeriodo } },
      },
      400: error(
        'Código con formato inválido, o fecha inexistente como 2026-02-30 (PETICION_INVALIDA).',
      ),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error('El código del lapso ya existe (REGISTRO_DUPLICADO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'patch',
    path: '/api/v1/admin/periodos/{id}',
    summary: 'Cambia el nombre, las fechas o el estado de un lapso',
    description:
      '`codigo` no está y no puede estarlo: es la identidad del lapso, `sections.period_code` apunta a él y los documentos impresos lo citan. Cambiar la nomenclatura (R-06) es crear un lapso nuevo y archivar el viejo.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdPeriodo,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActualizarPeriodo } },
      },
    },
    responses: {
      200: {
        description: 'Lapso actualizado.',
        content: { 'application/json': { schema: RespuestaPeriodo } },
      },
      400: error(
        'Ningún cambio indicado, fechas incoherentes, o un campo de identidad como `codigo` (PETICION_INVALIDA).',
      ),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('El lapso no existe (PERIODO_INEXISTENTE).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'put',
    path: '/api/v1/admin/periodos/{id}/vigente',
    summary: 'Declara ese lapso como el vigente',
    description:
      'La ÚNICA forma de mover `system_settings.periodo_activo`, y no se acepta por el PATCH de al lado para que no haya dos caminos que cambien lo mismo. Un trigger rechaza un valor que no corresponda a un lapso registrado: sin esa guarda, la Regla 2 de M2 compararía contra un lapso inexistente y **no protegería nada sin decir nada** (R-06).',
    security: [{ bearerAuth: [] }],
    request: { params: ParametroIdPeriodo },
    responses: {
      200: {
        description: 'Lapso declarado vigente.',
        content: { 'application/json': { schema: RespuestaPeriodo } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('El lapso no existe (PERIODO_INEXISTENTE).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'get',
    path: '/api/v1/admin/guardias',
    summary: 'Listado paginado de guardias de custodia',
    description:
      'Una guardia es una presencia, no una clase: dice quién cubre qué espacio, qué día y qué bloque, independientemente de que haya clase. Orden cronológico ascendente por lapso, día y bloque.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoGuardias },
    responses: {
      200: {
        description: 'Una página de guardias.',
        content: { 'application/json': { schema: RespuestaGuardias } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'post',
    path: '/api/v1/admin/guardias',
    summary: 'Asigna una guardia a un docente',
    description:
      '`periodo` es obligatorio, y no es un formalismo: sin él, una guardia del lunes a primera hora chocaría con las clases de cualquier lapso, incluido uno futuro que todavía no ha empezado (R-15). El `turno` lo calcula la base a partir del bloque y no se manda.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearGuardia } },
      },
    },
    responses: {
      201: {
        description: 'Guardia creada, con el turno ya derivado.',
        content: { 'application/json': { schema: RespuestaGuardia } },
      },
      400: error(
        'Día fuera de 1–6, bloque fuera de 1–12, `turno` enviado (PETICION_INVALIDA), o el docente, el espacio o el lapso no existen (REFERENCIA_INVALIDA).',
      ),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error(
        'CHOQUE_DE_AGENDA: ese docente o ese espacio ya están ocupados en ese bloque, por una clase o por otra guardia.',
      ),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'patch',
    path: '/api/v1/admin/guardias/{id}',
    summary: 'Mueve o edita una guardia',
    description:
      'Cambiar `dia` o `bloque` es un traslado: el trigger se dispara y el propio registro queda excluido del chequeo, así que mover una guardia sobre su propio hueco no se rechaza a sí misma. `activa: false` la archiva y libera el hueco.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdGuardia,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActualizarGuardia } },
      },
    },
    responses: {
      200: {
        description: 'Guardia actualizada.',
        content: { 'application/json': { schema: RespuestaGuardia } },
      },
      400: error('Ningún cambio indicado, valor fuera de rango o referencia inexistente.'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('La guardia no existe (GUARDIA_INEXISTENTE).'),
      409: error('CHOQUE_DE_AGENDA: el destino ya está ocupado.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'get',
    path: '/api/v1/admin/cuadrante',
    summary: 'La rejilla maestra de un lapso, completa en una llamada',
    description:
      'Devuelve clases, guardias, aulas y docentes **juntos**, y no por comodidad: son las cuatro dimensiones de la misma rejilla. Con cuatro peticiones la pantalla puede quedar a medio pintar mostrando una guardia junto a una clase que ya no existe, y el administrador no sabría si es un choque real o una pantalla desactualizada.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosRejilla },
    responses: {
      200: {
        description: 'La rejilla del lapso pedido, o la del vigente.',
        content: { 'application/json': { schema: RejillaCuadrante } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'post',
    path: '/api/v1/admin/cuadrante',
    summary: 'Coloca una clase en la rejilla',
    description:
      'El período no se manda: se deriva de la sección. Aceptarlo del cliente abriría la puerta a una fila cuya sección pertenece a un lapso mientras la rejilla se dibuja en otro, y el chequeo de colisiones compararía peras con manzanas. La respuesta vuelve con los nombres resueltos para que la pantalla pinte la celda sin una consulta por clase.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearClase } },
      },
    },
    responses: {
      201: {
        description: 'Clase colocada, con los nombres resueltos.',
        content: { 'application/json': { schema: RespuestaClase } },
      },
      400: error(
        'Día o bloque fuera de rango, `turno` o `periodo` enviados (PETICION_INVALIDA), o la sección, el docente o el espacio no existen (REFERENCIA_INVALIDA).',
      ),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error(
        'CHOQUE_DE_AGENDA: el docente o el espacio ya están ocupados en ese bloque — por una clase **o por una guardia**, que es lo que un `unique` no podría ver.',
      ),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...cuadrante,
    method: 'patch',
    path: '/api/v1/admin/cuadrante/{id}',
    summary: 'Mueve o edita una clase del cuadrante',
    description:
      'Cambiar `seccionId` mueve la clase de lapso, y el trigger re-deriva el período de la sección nueva. `activa: false` la archiva en vez de borrarla.',
    security: [{ bearerAuth: [] }],
    request: {
      params: ParametroIdClase,
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActualizarClase } },
      },
    },
    responses: {
      200: {
        description: 'Clase actualizada.',
        content: { 'application/json': { schema: RespuestaClase } },
      },
      400: error('Ningún cambio indicado, valor fuera de rango o referencia inexistente.'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('La clase no existe (CLASE_INEXISTENTE).'),
      409: error('CHOQUE_DE_AGENDA: el destino ya está ocupado.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    method: 'get',
    path: '/api/v1/mi-horario',
    tags: ['Cuadrante'],
    summary: 'El horario del llamante (docente o estudiante)',
    description:
      'Una sola ruta para los dos roles porque el aislamiento ya lo garantiza la RLS y lo único que cambia es qué filas sobreviven al filtro: el docente ve sus clases y sus guardias, el estudiante las de las secciones en las que está matriculado y nunca guardias. Un `admin` recibe **403 PERFIL_SIN_ROL**: su agenda no existe, y devolverle un horario vacío le haría creer que no tiene ninguna. Si quiere ver la rejilla, la ruta es `/api/v1/admin/cuadrante`.',
    security: [{ bearerAuth: [] }],
    request: { query: parametroMiHorario },
    responses: {
      200: {
        description: 'El horario del llamante en el lapso pedido o en el vigente.',
        content: { 'application/json': { schema: MiHorario } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: error('PERFIL_SIN_ROL: el rol del llamante no tiene horario propio.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  // ------------------------------------------------------- inscripciones ---

  const seccionesTag = { tags: ['Secciones'] };
  const inscripcionesTag = { tags: ['Inscripciones'] };

  registro.registerPath({
    ...seccionesTag,
    method: 'get',
    path: '/api/v1/admin/secciones',
    summary: 'Listado paginado de secciones',
    description:
      'El catálogo sobre el que se inscribe un estudiante. Hasta M4 esta tabla sólo se leía desde el cuadrante y se contaba desde el pensum: **no había forma de crear una sección**, y sin secciones el motor de cupos no tiene sobre qué operar.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoSecciones },
    responses: {
      200: {
        description: 'Una página de secciones, de lapso más reciente a más antiguo.',
        content: { 'application/json': { schema: RespuestaSecciones } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...seccionesTag,
    method: 'post',
    path: '/api/v1/admin/secciones',
    summary: 'Crea una sección',
    description:
      '`periodo`, `programaId` y `materiaId` deben existir: las tres claves ajenas son `on delete restrict`, así que una referencia inventada es un 400 REFERENCIA_INVALIDA. El nombre es único por lapso y materia (`sections_identidad_unica`): repetirlo es un 409.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoCrearSeccion } },
      },
    },
    responses: {
      201: {
        description: 'Sección creada.',
        content: { 'application/json': { schema: RespuestaSeccion } },
      },
      400: error('Referencia inexistente, nombre vacío o cupo negativo.'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      409: error('Ya existe una sección con ese nombre en ese lapso y materia (REGISTRO_DUPLICADO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...seccionesTag,
    method: 'patch',
    path: '/api/v1/admin/secciones/{id}',
    summary: 'Cambia nombre, cupo o estado de una sección',
    description:
      '**No se puede cambiar el programa, la materia ni el lapso**: los tres forman la identidad de la sección y cambiarlos no sería editarla, sería convertirla en otra llevándose por delante el historial de inscripciones que cuelga de su `id`. **Tampoco hay borrado**: archivar es `activa: false`, y el `DELETE` está revocado en la base.',
    security: [{ bearerAuth: [] }],
    request: {
      params: z.object({ id: z.string().uuid() }),
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoActualizarSeccion } },
      },
    },
    responses: {
      200: {
        description: 'Sección actualizada.',
        content: { 'application/json': { schema: RespuestaSeccion } },
      },
      400: error('Ningún cambio indicado, o cupo negativo.'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('La sección no existe (SECCION_INEXISTENTE).'),
      409: error('El nombre nuevo choca con otra sección del mismo lapso y materia.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'get',
    path: '/api/v1/ofertas',
    summary: 'Catálogo de secciones con cupo, para inscribirse',
    description:
      'Sólo secciones activas: ofrecer una archivada sería ofrecer algo que la base va a rechazar. Cada fila trae `cuposDisponibles` y `ofertaVigente` por separado a propósito — con una oferta en el aire el contador puede decir que hay hueco y el asiento NO se puede dar. **Usa `ofertaVigente`, no el contador.**',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoOfertas },
    responses: {
      200: {
        description: 'Una página de secciones con su ocupación.',
        content: { 'application/json': { schema: RespuestaOcupacion } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'get',
    path: '/api/v1/mis-inscripciones',
    summary: 'Las inscripciones del llamante',
    description:
      'Incluye las dadas de baja: `DROPPED` **no es un borrado**, la fila se conserva como historial y volver a entrar es una excepción de administración. `posicionEnCola` sólo tiene valor para quien está esperando.',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Las inscripciones propias, de la más reciente a la más antigua.',
        content: { 'application/json': { schema: RespuestaInscripciones } },
      },
      401: RESPUESTAS_ERROR[401],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'post',
    path: '/api/v1/inscripciones',
    summary: 'Solicita un asiento en una sección',
    description:
      'Devuelve el estado resultante: `ENROLLED` si entró directo, `WAITLISTED` si quedó en la cola. **No se adivina aquí** — lo decide la base dentro de un cerrojo por sección. La regla es «hay hueco **Y** no hay oferta viva»: sin la segunda mitad, el asiento se vendería dos veces.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoSolicitarInscripcion } },
      },
    },
    responses: {
      201: {
        description: 'Inscripción creada, en `ENROLLED` o en `WAITLISTED`.',
        content: { 'application/json': { schema: RespuestaEstadoInscripcion } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      404: error('La sección no existe (SECCION_INEXISTENTE).'),
      409: error(
        'ACAPARAMIENTO_DE_MATERIA (ya está en otra sección de esa materia), ' +
          'REQUIERE_REINCORPORACION (ya la cursó y necesita que un admin lo reincorpore), ' +
          'SOLICITUD_YA_EXISTE, o SECCION_ARCHIVADA.',
      ),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'post',
    path: '/api/v1/inscripciones/{id}/aceptar',
    summary: 'Acepta una oferta de cupo',
    description:
      '**`{id}` es el identificador de la SECCIÓN, no el de la inscripción.** Una inscripción no tiene identidad propia en la API: se identifica por el par (estudiante, sección), y el estudiante es siempre el de la sesión. Sólo el dueño de la oferta puede aceptarla: la de otro da 400 y la ajena queda intacta.',
    security: [{ bearerAuth: [] }],
    request: { params: z.object({ id: z.string().uuid() }) },
    responses: {
      200: {
        description: 'Oferta aceptada. El estado resultante es `ENROLLED`.',
        content: { 'application/json': { schema: RespuestaEstadoInscripcion } },
      },
      400: error('No hay una oferta pendiente para esa sección (RESTRICCION_VIOLADA).'),
      401: RESPUESTAS_ERROR[401],
      410: error('La oferta ya venció (OFERTA_VENCIDA). La interfaz debe recargar, no pedir que se corrija nada.'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'post',
    path: '/api/v1/inscripciones/{id}/renunciar',
    summary: 'Renuncia al asiento en una sección',
    description:
      'Deja la fila en `DROPPED` y **promueve al siguiente de la cola**. No borra: el historial es lo que permite que un administrador reincorpore. `{id}` es el identificador de la sección.',
    security: [{ bearerAuth: [] }],
    request: { params: z.object({ id: z.string().uuid() }) },
    responses: {
      200: {
        description: 'Baja registrada. El estado resultante es `DROPPED`.',
        content: { 'application/json': { schema: RespuestaEstadoInscripcion } },
      },
      400: error('No hay ninguna inscripción en esa sección (RESTRICCION_VIOLADA).'),
      401: RESPUESTAS_ERROR[401],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'get',
    path: '/api/v1/admin/ocupacion',
    summary: 'Panel de ocupación de todas las secciones',
    description:
      'A diferencia de `/api/v1/ofertas`, aquí **sí** se ven las secciones archivadas: el administrador necesita consultar el histórico de una cerrada.',
    security: [{ bearerAuth: [] }],
    request: { query: parametrosListadoOfertas },
    responses: {
      200: {
        description: 'Una página de secciones con su ocupación.',
        content: { 'application/json': { schema: RespuestaOcupacion } },
      },
      400: RESPUESTAS_ERROR[400],
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'get',
    path: '/api/v1/admin/secciones/{id}/cola',
    summary: 'La cola FIFO de una sección',
    description:
      'Orden de llegada: el primero que llegó es el primero. `PENDING_BID` no aparece —ya salió de la cola, se le ofreció un asiento— y `ENROLLED` tampoco. `posicionEnCola` viene ya resuelto.',
    security: [{ bearerAuth: [] }],
    request: { params: z.object({ id: z.string().uuid() }) },
    responses: {
      200: {
        description: 'La cola, en orden.',
        content: { 'application/json': { schema: RespuestaCola } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'get',
    path: '/api/v1/admin/secciones/{id}/inscripciones',
    summary: 'Quién está en una sección, en cualquier estado',
    description:
      'Incluye los `DROPPED`: es la vista de «quién pasó por aquí», que es justo lo que necesita el administrador para decidir una reincorporación. Trae el nombre y el correo del estudiante, que la RLS sí le permite ver.',
    security: [{ bearerAuth: [] }],
    request: { params: z.object({ id: z.string().uuid() }) },
    responses: {
      200: {
        description: 'Las inscripciones de la sección, de la más antigua a la más reciente.',
        content: { 'application/json': { schema: RespuestaInscripciones } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'post',
    path: '/api/v1/admin/secciones/{id}/promover',
    summary: 'Promueve al siguiente de la cola',
    description:
      'No promueve si la sección está llena ni si ya hay una oferta viva: **una oferta por asiento**. Devuelve `promovida: null` cuando no había a nadie, y eso **no es un error** — la cola puede estar vacía, la sección llena, o haber ya una oferta en el aire. Es un 200 con la explicación, no un 404.',
    security: [{ bearerAuth: [] }],
    request: { params: z.object({ id: z.string().uuid() }) },
    responses: {
      200: {
        description: 'Promoción intentada. `promovida` es `null` si no había a quién.',
        content: { 'application/json': { schema: RespuestaPromocion } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'post',
    path: '/api/v1/admin/inscripciones/reincorporar',
    summary: 'Devuelve a un dado de baja al estado de inscrito',
    description:
      '**Puede EXCEDER la capacidad de la sección, y es deliberado.** Regla institucional: «si el admin autoriza, el sistema obedece». La comprobación de cupo se quitó de la RPC a propósito; quedan el rol, el cerrojo y el trigger anti-acaparamiento. El exceso queda registrado, no es un agujero. Es la única RPC del módulo que actúa sobre otra persona.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoReincorporar } },
      },
    },
    responses: {
      200: {
        description: 'Reincorporación hecha. El estado resultante es `ENROLLED`.',
        content: { 'application/json': { schema: RespuestaEstadoInscripcion } },
      },
      400: error('La inscripción no está dada de baja (RESTRICCION_VIOLADA).'),
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('No existe una inscripción previa de ese estudiante en esa sección (SIN_HISTORIAL_EN_SECCION).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...inscripcionesTag,
    method: 'post',
    path: '/api/v1/admin/inscripciones/expirar',
    summary: 'Vence las ofertas de cupo caducadas',
    description:
      '**Idempotente**: la segunda llamada devuelve 0. Y **sin `pg_cron` a propósito** — el proyecto tiene arquitectura dual (nube + servidor local) y cortes eléctricos, así que no se puede depender de un planificador concreto. Al vencer una oferta se promueve a quien corresponda.',
    security: [{ bearerAuth: [] }],
    responses: {
      200: {
        description: 'Cuántas ofertas se vencieron.',
        content: { 'application/json': { schema: RespuestaExpiracion } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      503: RESPUESTAS_ERROR[503],
    },
  });

  // ----------------------------------------------------------- archivos -----
  const archivosTag = { tags: ['Archivos'] };

  registro.registerPath({
    ...archivosTag,
    method: 'post',
    path: '/api/v1/archivos/firmar-subida',
    summary: 'Reserva una subida y devuelve la URL firmada',
    description:
      '**El backend no mueve un solo byte**: firma una URL `PUT` y el cliente sube directo a R2. La fila nace `PENDING` **antes** de que el objeto exista, porque no hay transacción que abarque R2 y PostgreSQL: una fila huérfana es visible y barrible, mientras que un objeto sin fila sería un archivo fantasma que nadie puede autorizar ni limpiar. El `id` viaja en la respuesta porque es **lo único** que permite confirmar después. El tope de archivos por entidad sólo se aplica cuando hay entidad: una subida suelta, todavía sin tarea ni guía, no consume el cupo de nadie.',
    security: [{ bearerAuth: [] }],
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: CuerpoFirmarSubida } },
      },
    },
    responses: {
      201: {
        description: 'Reserva creada. Trae su identificador y la URL de subida.',
        content: { 'application/json': { schema: RespuestaFirmaSubida } },
      },
      400: error('El nombre no tiene extensión, o la extensión no está admitida.'),
      401: RESPUESTAS_ERROR[401],
      409: error('La entidad ya alcanzó el máximo de archivos (DEMASIADOS_ARCHIVOS).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...archivosTag,
    method: 'post',
    path: '/api/v1/archivos/{id}/confirmar',
    summary: 'Confirma que el objeto llegó y que pesa lo permitido',
    description:
      'Aquí se aplica el límite de tamaño, y **no antes**: una URL `PUT` prefirmada no admite `content-length-range`, así que el peso real sólo se conoce con este `HeadObject` posterior. Por eso el cuerpo no lleva el tamaño —pedirle al interesado que se mida no es una comprobación—. Si el archivo se pasa, se borra el objeto, se marca la fila y se responde **413**; el 400 queda para un tamaño corrupto. Si el objeto no llegó, la fila **no se toca**: se queda `PENDING` para que el barrido de abandonados la encuentre.',
    security: [{ bearerAuth: [] }],
    request: { params: ParametroIdArchivo },
    responses: {
      200: {
        description: 'El archivo quedó `CONFIRMED`, con su tamaño sellado.',
        content: { 'application/json': { schema: RespuestaArchivo } },
      },
      400: error('El tamaño medido no es un número válido: el dato está corrupto.'),
      401: RESPUESTAS_ERROR[401],
      404: error(
        'El archivo no existe, no es tuyo, o el objeto nunca llegó (OBJETO_NO_SUBIDO).',
      ),
      409: error('El archivo no está `PENDING` (ESTADO_DE_ARCHIVO).'),
      413: RESPUESTAS_ERROR[413],
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...archivosTag,
    method: 'get',
    path: '/api/v1/archivos/{id}/url-lectura',
    summary: 'URL de descarga temporal',
    description:
      'Sólo se firma lo `CONFIRMED`: un `PENDING` no tiene objeto verificado que leer y un `DELETED` ya no debería leerse. **404 y no 403 también cuando el archivo es de otro**, porque la RLS ya lo escondió y desde el backend no hay forma de distinguir «no existe» de «no es tuyo» —y no debe haberla: un 403 confirmaría que el archivo ajeno existe—. El nombre original viaja en la respuesta y se aplica como `Content-Disposition`, para que la descarga se llame «Constancia José.pdf» y no el UUID del objeto.',
    security: [{ bearerAuth: [] }],
    request: { params: ParametroIdArchivo },
    responses: {
      200: {
        description: 'URL firmada, de vida corta.',
        content: { 'application/json': { schema: RespuestaUrlLectura } },
      },
      401: RESPUESTAS_ERROR[401],
      404: error('El archivo no existe o no tienes acceso a él.'),
      409: error('El archivo todavía no está disponible para descargar (ARCHIVO_NO_DISPONIBLE).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...archivosTag,
    method: 'delete',
    path: '/api/v1/archivos/{id}',
    summary: 'Borra un archivo propio',
    description:
      'Primero el metadato y después el objeto, **al revés que en la confirmación** y por la misma razón simétrica: si fallara R2 quedaría un objeto huérfano con una fila que ya no lo cuenta —recuperable, auditable y barrible—, mientras que al revés quedaría una fila `CONFIRMED` apuntando a un objeto inexistente y el usuario vería un archivo roto sin explicación. El borrado es **lógico**: la fila se conserva con `deleted_at`. Quién puede borrar lo decide la RPC (`42501` → 403 si es de otro y quien llama no es admin), no la ruta.',
    security: [{ bearerAuth: [] }],
    request: { params: ParametroIdArchivo },
    responses: {
      200: {
        description: 'El archivo quedó `DELETED`.',
        content: { 'application/json': { schema: RespuestaArchivo } },
      },
      401: RESPUESTAS_ERROR[401],
      403: error('El archivo es de otra persona y la sesión no es de administrador (ARCHIVO_AJENO).'),
      404: error('El archivo no existe (ARCHIVO_INEXISTENTE).'),
      409: error('El archivo ya estaba borrado (ESTADO_DE_ARCHIVO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  registro.registerPath({
    ...archivosTag,
    method: 'delete',
    path: '/api/v1/admin/archivos/{id}',
    summary: 'Borra cualquier archivo (administrador)',
    description:
      'El mismo camino que el borrado del propietario, con otro portero. La RPC autoriza por `is_admin()`, así que el administrador no necesita ser el propietario: la única diferencia con la ruta anterior es la guardia, no la lógica. Mantener un solo camino es lo que garantiza que las dos formas de borrar no se desvíen.',
    security: [{ bearerAuth: [] }],
    request: { params: ParametroIdArchivo },
    responses: {
      200: {
        description: 'El archivo quedó `DELETED`.',
        content: { 'application/json': { schema: RespuestaArchivo } },
      },
      401: RESPUESTAS_ERROR[401],
      403: RESPUESTAS_ERROR[403],
      404: error('El archivo no existe (ARCHIVO_INEXISTENTE).'),
      409: error('El archivo ya estaba borrado (ESTADO_DE_ARCHIVO).'),
      503: RESPUESTAS_ERROR[503],
    },
  });

  return registro;
}

/** Documento OpenAPI 3.1 completo, listo para serializar. */
export function construirDocumentoOpenApi() {
  const registro = construirRegistro();
  const generador = new OpenApiGeneratorV31(registro.definitions);

  return generador.generateDocument({
    openapi: '3.1.0',
    info: {
      title: 'INCES LMS API',
      version: '0.1.0',
      description: [
        'API del LMS del CFS Nacional de Soldadura "Rafael Urdaneta" (INCES, La Isabelica).',
        '',
        'Este documento se **genera** a partir de los esquemas Zod en `src/http/esquemas.ts`.',
        'No se edita a mano: cualquier cambio manual se perderá en la siguiente generación.',
        'Los esquemas Zod son el único contrato; esto es una proyección suya.',
        '',
        'Todas las rutas exigen un token de Supabase Auth, salvo las sondas de salud.',
      ].join('\n'),
      license: { name: 'Uso académico — TEG IUTEPI' },
    },
    servers: [
      { url: 'http://localhost:3000', description: 'Desarrollo local' },
      { url: 'https://api.example.com', description: 'Producción (pendiente de dominio)' },
    ],
    tags: [
      { name: 'Salud', description: 'Sondas para el orquestador.' },
      { name: 'Sesión', description: 'Identidad y módulos visibles del llamante.' },
      {
        name: 'Administrador Maestro',
        description:
          'Interruptores de módulos, parámetros del sistema y auditoría. Requiere rol admin.',
      },
      {
        name: 'Currículo',
        description:
          'Módulo 2: programas de formación, banco de materias y pensum. Requiere rol admin.',
      },
      {
        name: 'Cuadrante',
        description:
          'Módulo 3: aulas, lapsos, guardias docentes y la rejilla del cuadrante. Las rutas de administración exigen rol admin; `/api/v1/mi-horario` sirve el horario propio a docentes y estudiantes.',
      },
      {
        name: 'Secciones',
        description:
          'El catálogo de secciones: el grupo concreto de una materia en un lapso. Es lo que el cuadrante usa para colgar sus clases y lo que un estudiante elige al inscribirse. Requiere rol admin.',
      },
      {
        name: 'Inscripciones',
        description:
          'Módulo 4: cupos, cola FIFO y ofertas con vencimiento. Las rutas bajo `/api/v1/admin` exigen rol admin; `/api/v1/ofertas`, `/api/v1/mis-inscripciones` y `/api/v1/inscripciones` sirven al estudiante. Toda escritura pasa por RPC `security definer`: la tabla `enrollments` tiene la escritura revocada a propósito.',
      },
    ],
  });
}
