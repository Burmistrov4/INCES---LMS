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
