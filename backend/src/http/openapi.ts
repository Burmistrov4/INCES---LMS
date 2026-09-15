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
import { rolSchema } from '../http/esquemas.js';

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
  .object({ email: z.string().email() })
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
      'El administrador aporta el correo. El servidor genera un token, guarda SOLO su ' +
      'huella en la base y envía el enlace de activación. El enlace también se devuelve ' +
      'en la respuesta para poder probar el flujo aunque el correo no llegue.',
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
    ],
  });
}
