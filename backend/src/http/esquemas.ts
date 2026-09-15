import { z } from 'zod';
import { ErrorApi } from '../dominio/errores.js';
import { materiaRepetida } from '../dominio/reglas-curriculo.js';

/**
 * Esquemas de validación de entrada.
 *
 * Todo lo que llega del cliente pasa por Zod antes de tocar la base de datos.
 * `.strict()` rechaza campos desconocidos a propósito: si alguien intenta colar
 * `{"habilitado": true, "es_critico": false}`, se entera de que `es_critico` no
 * existe, en vez de que se ignore en silencio.
 */

/**
 * Los roles se escriben literales (no derivados de `ROLES`) para que Zod
 * conserve la unión exacta y `z.infer` dé `'admin' | 'docente' | 'estudiante'`.
 * El test comprueba que esta lista y `ROLES` siguen coincidiendo.
 */
export const rolSchema = z.enum(['admin', 'docente', 'estudiante']);

/** Valores JSON admitidos en `system_settings.valor`. */
const valorJsonSchema = z.union([
  z.string(),
  z.number(),
  z.boolean(),
  z.null(),
  z.array(z.unknown()),
  z.record(z.unknown()),
]);

export const esquemaCambiosModulo = z
  .object({
    habilitado: z.boolean().optional(),
    orden: z.number().int().min(0).max(9999).optional(),
    rolesPermitidos: z.array(rolSchema).max(3).optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio (habilitado, orden o rolesPermitidos).',
  });

export const esquemaValorParametro = z
  .object({
    valor: valorJsonSchema,
  })
  .strict();

export const esquemaCambioRol = z
  .object({
    rol: rolSchema,
  })
  .strict();

/**
 * Un identificador de perfil que viene por la URL.
 *
 * Existe porque sin esto un valor como `/usuarios/me/rol` viaja tal cual hasta
 * Postgres, que responde `22P02 invalid input syntax for type uuid: "me"`. Ese
 * error se traducía a un `500 ERROR_BASE_DE_DATOS` genérico: un `500` para lo
 * que en realidad es una URL mal escrita. Validar aquí convierte el problema en
 * un `400` que nombra el parámetro, y evita un viaje a la base de datos para
 * tirar la petición.
 *
 * No se acepta el atajo `/usuarios/me/...`: el `id` del llamante ya viaja en
 * `request.usuario.id`, así que el atajo sólo añadiría una forma más de
 * equivocarse. Si algún día hace falta, se resolverá antes de llegar aquí.
 */
export const esquemaIdPerfil = z.string().uuid({
  message: 'El identificador de usuario debe ser un UUID válido.',
});

export const esquemaListadoAuditoria = z.object({
  limite: z.coerce.number().int().min(1).max(200).default(50),
});

/**
 * Listado paginado de usuarios.
 *
 * `desplazamiento` en vez de `pagina` porque el cliente ya sabe cuántas filas
 * mostró: convertirlo a número de página y de vuelta obliga a fijar un tamaño de
 * página en dos sitios a la vez, y basta con que uno cambie para que las cuentas
 * dejen de cuadrar.
 *
 * Los tres filtros van en el mismo objeto porque la pantalla los combina: rol
 * + estado + texto. Un `activo` como cadena (`"true"`/`"false"`) se acepta y se
 * convierte, porque en la URL todo llega como texto; una cadena que no sea
 * ninguno de los dos se rechaza con 400 en vez de interpretarse como `true`.
 */
export const esquemaListadoUsuarios = z.object({
  rol: rolSchema.optional(),
  activo: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
  busqueda: z.string().trim().min(1).max(120).optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/**
 * Listado paginado de la traza de accesos (auth_logs).
 *
 * Filtra por resultado (`estado`), por correo exacto o por usuario (UUID). El
 * filtro de correo es exacto a propósito: una bitácora de inicios de sesión se
 * consulta por el correo concreto de quien investigas, no por un texto parcial
 * que podría casar con varias cuentas. La paginación usa `desplazamiento` por
 * las mismas razones que el listado de usuarios (ver `esquemaListadoUsuarios`).
 */
export const esquemaListadoAcceso = z.object({
  estado: z.enum(['SUCCESS', 'FAILED']).optional(),
  email: z.string().trim().min(1).max(320).optional(),
  userId: z.string().uuid().optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/**
 * Invitación de un docente: el administrador sólo aporta el correo. El token se
 * genera en el servidor; el cliente nunca lo toca.
 */
export const esquemaCorreoInvitacion = z
  .object({
    email: z.string().email('El correo del docente no es válido.'),
  })
  .strict();

/**
 * Activación de la invitación: el profesor entrega el token del enlace y la
 * contraseña que quiere fijar. El token es el secreto del enlace; si fuera
 * demasiado corto no puede ser uno nuestro (32 bytes en base64url).
 */
export const esquemaActivarCuenta = z
  .object({
    token: z.string().min(20, 'El token es demasiado corto.'),
    password: z.string().min(8, 'La contraseña debe tener al menos 8 caracteres.'),
  })
  .strict();

export type CambiosModuloEntrada = z.infer<typeof esquemaCambiosModulo>;
export type ValorParametroEntrada = z.infer<typeof esquemaValorParametro>;
export type CambioRolEntrada = z.infer<typeof esquemaCambioRol>;
export type CorreoInvitacionEntrada = z.infer<typeof esquemaCorreoInvitacion>;
export type ActivarCuentaEntrada = z.infer<typeof esquemaActivarCuenta>;
export type ListadoAccesoEntrada = z.infer<typeof esquemaListadoAcceso>;

// --- Módulo 2: currículo y pensum -------------------------------------------

/**
 * Los dos tipos de oferta formativa.
 *
 * Literales y no derivados de `TIPOS_PROGRAMA` para que Zod conserve la unión
 * exacta, igual que `rolSchema`. Una prueba comprueba que la lista y la
 * constante del dominio siguen coincidiendo.
 */
export const tipoProgramaSchema = z.enum(['CARRERA', 'CURSO_LIBRE']);

/**
 * Código institucional corto (`varchar(12)` en la base).
 *
 * El formato no es capricho: es un identificador que la gente teclea a mano en
 * planillas y carteleras. Si se admitiera texto libre, alguien guardaría
 * «Análisis de Sistemas» aquí y el código dejaría de identificar nada. Se
 * recorta el espacio sobrante antes de validar, porque un `" SIST-01"` pegado
 * desde una hoja de cálculo es un error de tecleo, no una intención.
 *
 * Duplica el `check` de la tabla a propósito: Zod da el mensaje antes de abrir
 * una transacción y nombra el campo; el `check` es la invariante. Dos barreras,
 * la misma decisión que con RLS.
 */
const codigoCatalogo = z
  .string()
  .trim()
  .min(1, 'El código no puede estar vacío.')
  .max(12, 'El código no puede pasar de 12 caracteres.')
  .regex(
    /^[A-Z0-9][A-Z0-9-]{0,11}$/,
    'El código admite MAYÚSCULAS, dígitos y guiones, y debe empezar por letra o dígito.',
  );

const nombreCatalogo = z.string().trim().min(1, 'El nombre no puede estar vacío.').max(100);

/**
 * Una entrada del pensum: qué materia, en qué período.
 *
 * `.strict()` también aquí, no sólo en el objeto de arriba: sin esto, un
 * `{"materiaId": …, "periodo": 1, "nombre": "Inventado"}` pasaría la validación
 * del arreglo y el campo de más se colaría hasta la función de la base. Zod
 * valida los objetos anidados por separado.
 */
const esquemaEntradaPensum = z
  .object({
    materiaId: z.string().uuid({
      message: 'Cada entrada del pensum debe referenciar una materia por su UUID.',
    }),
    periodo: z.number().int().min(1, 'El período empieza en 1.').default(1),
  })
  .strict();

/**
 * El pensum completo: al menos una materia y ninguna repetida.
 *
 * La unicidad se comprueba con `materiaRepetida`, la misma función pura que
 * usa el resto del módulo, para que el mensaje **nombre la materia** en vez de
 * decir «hay un error»: un administrativo que armó un pensum de 40 materias
 * necesita saber cuál se repite.
 *
 * `min(1)` deja fuera el pensum vacío, y el contrato lo pide así (400
 * `PETICION_INVALIDA`). El constraint trigger diferido de la Regla 1 sigue
 * estando detrás: Zod sólo ve lo que llega, el trigger ve el estado de la tabla.
 */
const esquemaPensum = z
  .array(esquemaEntradaPensum)
  .min(1, 'El pensum debe tener al menos una materia.')
  .superRefine((entradas, ctx) => {
    const repetida = materiaRepetida(entradas);
    if (repetida) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `La materia ${repetida} aparece más de una vez en el pensum.`,
      });
    }
  });

/**
 * Un identificador de programa que viene por la URL.
 *
 * Misma razón que `esquemaIdPerfil`: sin esto, `/programas/me` viaja hasta
 * Postgres, revienta con `22P02` y sale como un `500` genérico para lo que en
 * realidad es una URL mal escrita.
 */
export const esquemaIdPrograma = z.string().uuid({
  message: 'El identificador de programa debe ser un UUID válido.',
});

/**
 * Listado paginado de programas.
 *
 * `activo` se acepta como cadena y se convierte, por la misma razón que en el
 * listado de usuarios: en la URL todo llega como texto, y una cadena que no sea
 * `true` ni `false` se rechaza con 400 en vez de interpretarse como `true`.
 */
export const esquemaListadoProgramas = z.object({
  tipo: tipoProgramaSchema.optional(),
  activo: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
  busqueda: z.string().trim().min(1).max(100).optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/** Listado paginado del banco global de materias. */
export const esquemaListadoMaterias = z.object({
  busqueda: z.string().trim().min(1).max(100).optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/**
 * El cuerpo del asistente: programa + pensum en una sola petición.
 *
 * `publicar` decide el `is_active` inicial y va separado de un `activo` porque
 * crear en borrador es lo normal mientras se arma el pensum, y publicar es la
 * decisión final. Un solo campo obligaría a publicar siempre o nunca.
 */
export const esquemaCrearPrograma = z
  .object({
    codigo: codigoCatalogo,
    nombre: nombreCatalogo,
    tipo: tipoProgramaSchema,
    requierePasantia: z.boolean().default(false),
    publicar: z.boolean().default(false),
    pensum: esquemaPensum,
  })
  .strict();

/**
 * Cambios de metadatos de un programa.
 *
 * `codigo` y `tipo` no están: son la identidad del programa. `sections` (M3)
 * apuntará a él, y un código cambiado rompe cualquier documento impreso que lo
 * cite. Si alguien los manda, `.strict()` lo rechaza con un 400 que nombra el
 * campo, en vez de ignorarlos en silencio.
 */
export const esquemaActualizarPrograma = z
  .object({
    nombre: nombreCatalogo.optional(),
    requierePasantia: z.boolean().optional(),
    activo: z.boolean().optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio (nombre, requierePasantia o activo).',
  });

/**
 * Reemplazo completo del pensum.
 *
 * El cliente manda el **estado final**, no un parche: un `PATCH` incremental
 * obligaría al cliente a saber qué borrar, y esa no es su responsabilidad.
 */
export const esquemaReemplazarPensum = z
  .object({
    pensum: esquemaPensum,
  })
  .strict();

/** Alta de una materia en caliente desde el paso 2 del asistente. */
export const esquemaCrearMateria = z
  .object({
    codigo: codigoCatalogo,
    nombre: nombreCatalogo,
    horasAcademicas: z
      .number()
      .int()
      .positive('Las horas académicas deben ser mayores que cero.'),
  })
  .strict();

export type ListadoProgramasEntrada = z.infer<typeof esquemaListadoProgramas>;
export type ListadoMateriasEntrada = z.infer<typeof esquemaListadoMaterias>;
export type CrearProgramaEntrada = z.infer<typeof esquemaCrearPrograma>;
export type ActualizarProgramaEntrada = z.infer<typeof esquemaActualizarPrograma>;
export type ReemplazarPensumEntrada = z.infer<typeof esquemaReemplazarPensum>;
export type CrearMateriaEntrada = z.infer<typeof esquemaCrearMateria>;

/**
 * Comprueba que el valor encaje con el `tipo` declarado del parámetro.
 *
 * Sin esto, `max_faltas_consecutivas` podría quedar guardado como `"tres"` y el
 * módulo de asistencia empezaría a comportarse de forma impredecible mucho
 * después, lejos del sitio donde se cometió el error.
 */
export function validarValorSegunTipo(
  tipo: string,
  valor: unknown,
  clave: string,
): void {
  const espera = (esperado: string): never => {
    throw ErrorApi.peticionInvalida(
      `El parámetro "${clave}" espera un valor de tipo ${esperado}.`,
      { clave, tipo, valorRecibido: typeof valor },
    );
  };

  switch (tipo) {
    case 'number':
      if (typeof valor !== 'number' || !Number.isFinite(valor)) espera('number');
      return;
    case 'boolean':
      if (typeof valor !== 'boolean') espera('boolean');
      return;
    case 'string':
      if (typeof valor !== 'string') espera('string');
      return;
    case 'json':
      return;
    default:
      throw ErrorApi.peticionInvalida(
        `El parámetro "${clave}" declara un tipo desconocido: "${tipo}".`,
        { clave, tipo },
      );
  }
}
