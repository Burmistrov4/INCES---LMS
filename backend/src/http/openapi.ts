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

const RespuestaPerfil = z.object({ perfil: Perfil }).openapi('RespuestaPerfil');

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
    ],
  });
}
