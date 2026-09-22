import { z } from 'zod';
import { ErrorApi } from '../dominio/errores.js';
import { materiaRepetida } from '../dominio/reglas-curriculo.js';
import {
  BLOQUE_MAXIMO,
  DIA_MAXIMO,
  esFechaISO,
  rangoDeFechasValido,
} from '../dominio/reglas-cuadrante.js';

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
 * Invitación de un docente: el administrador aporta el correo y el nombre real
 * del profesor. El token se genera en el servidor; el cliente nunca lo toca.
 *
 * `nombres`/`apellidos` son OBLIGATORIOS (R-21): sin ellos, `profiles` queda en
 * blanco y `nombre_para_mostrar()` devuelve NULL en el cuadrante. Con
 * `.strict()` se rechaza cualquier campo de más a propósito.
 */
export const esquemaCorreoInvitacion = z
  .object({
    email: z.string().email('El correo del docente no es válido.'),
    nombres: z
      .string()
      .trim()
      .min(1, 'El nombre del docente no puede estar vacío.')
      .max(100, 'El nombre no puede pasar de 100 caracteres.'),
    apellidos: z
      .string()
      .trim()
      .min(1, 'Los apellidos del docente no pueden estar vacíos.')
      .max(100, 'Los apellidos no pueden pasar de 100 caracteres.'),
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

// --- Módulo 3: cuadrante, aulas y guardias ----------------------------------

/**
 * Identificador de recurso que viene por la URL.
 *
 * Es una fábrica y no cuatro constantes repetidas porque M3 estrena cuatro
 * recursos —aula, período, guardia y clase— y a partir del tercero copiar el
 * mismo `.uuid()` cuatro veces deja de ser claridad y pasa a ser cuatro sitios
 * donde olvidarse del mensaje. El mensaje sigue nombrando el recurso, que es lo
 * único que cambia entre uno y otro.
 *
 * Sin esto, un `id` que no sea UUID viaja hasta Postgres, revienta con `22P02` y
 * sale como un `500` genérico: un error del cliente disfrazado de fallo del
 * servidor. Misma razón que `esquemaIdPerfil` y `esquemaIdPrograma`.
 */
function idDeRecurso(recurso: string) {
  return z.string().uuid({
    message: `El identificador de ${recurso} debe ser un UUID válido.`,
  });
}

export const esquemaIdAula = idDeRecurso('espacio');
export const esquemaIdPeriodo = idDeRecurso('lapso');
export const esquemaIdGuardia = idDeRecurso('guardia');
export const esquemaIdClase = idDeRecurso('clase');

/**
 * Código de un lapso (`varchar(10)` en la base).
 *
 * El formato duplica el `check` de `academic_periods` a propósito: Zod da el
 * mensaje antes de abrir una transacción y nombra el campo; el `check` es la
 * invariante. Se admite mayúscula y minúscula igual que en la base, porque
 * rechazar aquí una minúscula bloquearía un dato que la tabla acepta.
 */
const codigoPeriodo = z
  .string()
  .trim()
  .min(1, 'El código del lapso no puede estar vacío.')
  .max(10, 'El código del lapso no puede pasar de 10 caracteres.')
  .regex(
    /^[A-Za-z0-9][A-Za-z0-9-]{0,9}$/,
    'El código del lapso admite letras, dígitos y guiones, y debe empezar por letra o dígito.',
  );

/**
 * Una fecha en formato `AAAA-MM-DD`.
 *
 * `esFechaISO` comprueba además que la fecha **exista**: `2026-02-30` tiene la
 * forma correcta y no es un día. Sin esa comprobación el valor llegaría a
 * Postgres, que responde `22007` —un código que el traductor no reconoce— y
 * saldría como un `500` por un dato que el cliente escribió mal.
 */
const fechaIso = z
  .string()
  .trim()
  .refine(esFechaISO, {
    message: 'La fecha debe ser un día real en formato AAAA-MM-DD.',
  });

/** Las tres formas de espacio. Literales, como `rolSchema` y `tipoProgramaSchema`. */
export const tipoAulaSchema = z.enum(['TALLER', 'ZONA', 'AULA']);

/** Día de la semana, 1 = lunes … 6 = sábado. El domingo queda fuera (requisito). */
const diaSchema = z
  .number()
  .int('El día debe ser un número entero.')
  .min(1, 'El día va del 1 (lunes) al 6 (sábado).')
  .max(DIA_MAXIMO, `El día va del 1 (lunes) al ${DIA_MAXIMO} (sábado).`);

/** Bloque horario dentro de la jornada. */
const bloqueSchema = z
  .number()
  .int('El bloque debe ser un número entero.')
  .min(1, 'El bloque empieza en 1.')
  .max(BLOQUE_MAXIMO, `El bloque no puede pasar de ${BLOQUE_MAXIMO}.`);

const nombreAula = z
  .string()
  .trim()
  .min(1, 'El nombre del espacio no puede estar vacío.')
  .max(80, 'El nombre del espacio no puede pasar de 80 caracteres.');

// --- Aulas ------------------------------------------------------------------

export const esquemaListadoAulas = z.object({
  busqueda: z.string().trim().min(1).max(80).optional(),
  tipo: tipoAulaSchema.optional(),
  activa: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/**
 * Alta de un espacio.
 *
 * `capacidad` en 0 es válido y significa «sin cupo declarado»: así se registra
 * una zona de custodia (un pasillo, la entrada del taller). No es lo mismo que
 * desconocido, que sería no mandarlo — y por eso el valor por defecto es 0 y no
 * un nulo.
 */
export const esquemaCrearAula = z
  .object({
    nombre: nombreAula,
    capacidad: z
      .number()
      .int('La capacidad debe ser un número entero.')
      .min(0, 'La capacidad no puede ser negativa.')
      .default(0),
    esTaller: z.boolean().default(false),
  })
  .strict();

export const esquemaActualizarAula = z
  .object({
    nombre: nombreAula.optional(),
    capacidad: z.number().int().min(0, 'La capacidad no puede ser negativa.').optional(),
    esTaller: z.boolean().optional(),
    activa: z.boolean().optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio (nombre, capacidad, esTaller o activa).',
  });

// --- Períodos ---------------------------------------------------------------

/**
 * Alta de un lapso.
 *
 * `codigo` es la identidad y no se puede cambiar después: `sections.period_code`
 * apunta a él y los documentos impresos lo citan.
 */
export const esquemaCrearPeriodo = z
  .object({
    codigo: codigoPeriodo,
    nombre: z
      .string()
      .trim()
      .min(1, 'El nombre del lapso no puede estar vacío.')
      .max(120)
      .optional(),
    fechaInicio: fechaIso.optional(),
    fechaFin: fechaIso.optional(),
  })
  .strict()
  .refine((valor) => rangoDeFechasValido(valor.fechaInicio, valor.fechaFin), {
    path: ['fechaFin'],
    message: 'La fecha de fin debe ser posterior a la de inicio.',
  });

/**
 * Cambios de un lapso. `codigo` no está, por la misma razón que en `programs`.
 *
 * `nombre`, `fechaInicio` y `fechaFin` aceptan `null` explícito para poder
 * **vaciar** un dato: las fechas nacen nulas y el centro las carga cuando las
 * tiene, así que también tiene que poder dejarlas en blanco si se equivocó.
 *
 * La coherencia de fechas sólo se puede comprobar aquí cuando llegan las dos. Si
 * el cliente manda una sola, la otra vive en la fila y decide el `check` de la
 * base: `academic_periods_fechas_coherentes`. La regla es la misma en los dos
 * sitios; lo que cambia es cuánto se ve desde la petición.
 */
export const esquemaActualizarPeriodo = z
  .object({
    nombre: z.string().trim().min(1).max(120).nullable().optional(),
    fechaInicio: fechaIso.nullable().optional(),
    fechaFin: fechaIso.nullable().optional(),
    activo: z.boolean().optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio (nombre, fechaInicio, fechaFin o activo).',
  })
  .refine((valor) => rangoDeFechasValido(valor.fechaInicio, valor.fechaFin), {
    path: ['fechaFin'],
    message: 'La fecha de fin debe ser posterior a la de inicio.',
  });

// --- Guardias ---------------------------------------------------------------

export const esquemaCrearGuardia = z
  .object({
    docenteId: z.string().uuid({
      message: 'El docente debe referenciarse por su UUID.',
    }),
    aulaId: z.string().uuid({
      message: 'El espacio debe referenciarse por su UUID.',
    }),
    // Obligatorio, y no es un formalismo (R-15): sin período, una guardia del
    // lunes a primera hora chocaría con las clases de cualquier lapso.
    periodo: codigoPeriodo,
    dia: diaSchema,
    bloque: bloqueSchema,
    notas: z.string().trim().max(500).nullable().optional(),
  })
  .strict();

export const esquemaActualizarGuardia = z
  .object({
    docenteId: z.string().uuid().optional(),
    aulaId: z.string().uuid().optional(),
    periodo: codigoPeriodo.optional(),
    dia: diaSchema.optional(),
    bloque: bloqueSchema.optional(),
    notas: z.string().trim().max(500).nullable().optional(),
    activa: z.boolean().optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio para la guardia.',
  });

export const esquemaListadoGuardias = z.object({
  periodo: codigoPeriodo.optional(),
  docenteId: z.string().uuid().optional(),
  aulaId: z.string().uuid().optional(),
  dia: z.coerce.number().int().min(1).max(DIA_MAXIMO).optional(),
  bloque: z.coerce.number().int().min(1).max(BLOQUE_MAXIMO).optional(),
  activa: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

// --- Cuadrante --------------------------------------------------------------

export const esquemaRejilla = z.object({
  periodo: codigoPeriodo.optional(),
  seccionId: z.string().uuid().optional(),
  docenteId: z.string().uuid().optional(),
  aulaId: z.string().uuid().optional(),
  incluirInactivas: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
});

/**
 * Colocar una clase en la rejilla.
 *
 * **`turno` no está, y su ausencia es la regla.** Es una columna generada a
 * partir de `block`: mandarla sería aceptar un turno que puede contradecir al
 * bloque, es decir, una agenda que miente. Con `.strict()`, enviarla da un `400`
 * que nombra el campo en vez de ignorarla en silencio.
 *
 * **El período tampoco está**: se deriva de la sección. Aceptarlo del cliente
 * abriría la puerta a una fila cuya sección pertenece a un lapso mientras la
 * rejilla se dibuja en otro, y el chequeo de colisiones compararía peras con
 * manzanas.
 */
export const esquemaCrearClase = z
  .object({
    seccionId: z.string().uuid({
      message: 'La sección debe referenciarse por su UUID.',
    }),
    docenteId: z.string().uuid({
      message: 'El docente debe referenciarse por su UUID.',
    }),
    aulaId: z.string().uuid({
      message: 'El espacio debe referenciarse por su UUID.',
    }),
    dia: diaSchema,
    bloque: bloqueSchema,
  })
  .strict();

export const esquemaActualizarClase = z
  .object({
    seccionId: z.string().uuid().optional(),
    docenteId: z.string().uuid().optional(),
    aulaId: z.string().uuid().optional(),
    dia: diaSchema.optional(),
    bloque: bloqueSchema.optional(),
    activa: z.boolean().optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio para la clase.',
  });

/**
 * Filtro del horario propio.
 *
 * Se acepta un lapso distinto del vigente porque un docente planifica el
 * siguiente mientras dicta el actual, y esa es justo la razón de que exista el
 * catálogo de lapsos.
 */
export const esquemaMiHorario = z.object({
  periodo: codigoPeriodo.optional(),
});

// --- Módulo 4: secciones, inscripciones y cupos ------------------------------

export const esquemaIdSeccion = idDeRecurso('sección');
export const esquemaIdEstudiante = idDeRecurso('estudiante');

/**
 * Nombre de una sección (`varchar(5)` en la base).
 *
 * Los cinco caracteres no son un descuido del esquema: el nombre de una sección
 * es un **identificador corto** dentro del lapso ('SA', 'SC'), no una descripción.
 * El nombre largo de la materia vive en `subjects.name`, y la interfaz compone
 * los dos. Se replica el límite aquí para que el error diga qué pasó en vez de
 * dejar que Postgres lo trunque o lo rechace con un `22001` que el traductor no
 * reconoce y saldría como un `500`.
 */
const nombreSeccion = z
  .string()
  .trim()
  .min(1, 'El nombre de la sección no puede estar vacío.')
  .max(5, 'El nombre de la sección no puede pasar de 5 caracteres (es un identificador corto, como "SA").');

/**
 * Cupo de una sección.
 *
 * **`null` y `0` no son lo mismo, y por eso el campo es anulable.**
 * `null` = «usa el cupo global del centro» (`cupo_maximo_por_seccion`).
 * `0`    = «esta sección no admite inscripciones» → todo el mundo a la cola.
 *
 * La columna se hizo anulable precisamente para que el fallback fuera
 * alcanzable: era `not null default 0` y el global nunca se consultaba.
 */
const cupoSeccion = z
  .number()
  .int('El cupo debe ser un número entero.')
  .min(0, 'El cupo no puede ser negativo.')
  .nullable();

export const esquemaListadoSecciones = z.object({
  busqueda: z.string().trim().min(1).max(80).optional(),
  periodo: codigoPeriodo.optional(),
  programaId: z.string().uuid().optional(),
  materiaId: z.string().uuid().optional(),
  activa: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/**
 * Alta de una sección.
 *
 * El período se acepta del cliente —a diferencia de una clase del cuadrante, que
 * lo hereda de su sección— porque la sección **es** la que fija el lapso: no hay
 * nada de donde heredarlo.
 *
 * `cupoMaximo` es opcional y por defecto `null`, que significa «usa el global».
 * Mandar `0` es una decisión distinta y deliberada: una sección sin cupo.
 */
export const esquemaCrearSeccion = z
  .object({
    programaId: z.string().uuid({ message: 'El programa debe ser un UUID válido.' }),
    materiaId: z.string().uuid({ message: 'La materia debe ser un UUID válido.' }),
    periodo: codigoPeriodo,
    nombre: nombreSeccion,
    cupoMaximo: cupoSeccion.optional().default(null),
  })
  .strict();

/**
 * Cambios de una sección.
 *
 * `programaId`, `materiaId`, `periodo` **no están**: los tres forman la identidad
 * de la sección —`unique (period_code, subject_id, name)`— y `sections` está en
 * `on delete restrict` desde tres sitios. Cambiarlos no sería editar la sección,
 * sería convertirla en otra llevándose por delante el historial de inscripciones
 * que cuelga de su `id`.
 */
export const esquemaActualizarSeccion = z
  .object({
    nombre: nombreSeccion.optional(),
    cupoMaximo: cupoSeccion.optional(),
    activa: z.boolean().optional(),
  })
  .strict()
  .refine((valor) => Object.keys(valor).length > 0, {
    message: 'Indica al menos un cambio (nombre, cupoMaximo o activa).',
  });

/**
 * Filtros del catálogo de ofertas y del panel de ocupación.
 *
 * `soloConCupo` filtra por **asiento realmente ofrecible**, no por
 * `cupos_disponibles > 0`: con una oferta en el aire la vista informa que hay
 * hueco, pero el asiento está comprometido y ofrecerlo sería prometer algo que la
 * base va a negar (la doble venta de R-23).
 */
export const esquemaListadoOfertas = z.object({
  busqueda: z.string().trim().min(1).max(80).optional(),
  periodo: codigoPeriodo.optional(),
  programaId: z.string().uuid().optional(),
  materiaId: z.string().uuid().optional(),
  soloConCupo: z
    .enum(['true', 'false'])
    .transform((valor) => valor === 'true')
    .optional(),
  limite: z.coerce.number().int().min(1).max(100).default(25),
  desplazamiento: z.coerce.number().int().min(0).default(0),
});

/**
 * Solicitud de un asiento.
 *
 * La sección va en el **cuerpo** y no en la ruta porque no es un identificador de
 * recurso: se está creando una inscripción, y la sección es un dato de esa
 * creación. (En `aceptar` y `renunciar` sí es una ruta, porque ahí se opera sobre
 * una inscripción que ya existe.)
 */
export const esquemaSolicitarInscripcion = z
  .object({
    seccionId: esquemaIdSeccion,
  })
  .strict();

/**
 * Reincorporación de un estudiante dado de baja.
 *
 * Lleva **estudiante y sección** porque un administrador no se reincorpora a sí
 * mismo: la RPC `reincorporar_inscripcion(p_student_id, p_section_id)` es la
 * única del módulo que actúa sobre otra persona.
 */
export const esquemaReincorporar = z
  .object({
    estudianteId: esquemaIdEstudiante,
    seccionId: esquemaIdSeccion,
  })
  .strict();

// --- Módulo 5: archivos (Cloudflare R2) -------------------------------------

export const esquemaIdArchivo = idDeRecurso('archivo');

/**
 * A qué entidad se adjunta el archivo.
 *
 * Los dos literales duplican el `check` de `files_metadata.entity_type`, igual
 * que `tipoAulaSchema` duplica el suyo: Zod da el mensaje antes de abrir una
 * transacción y nombra el campo, y el `check` sigue siendo la invariante.
 */
export const tipoEntidadArchivoSchema = z.enum([
  'TASK_SUBMISSION',
  'TEACHER_GUIDE',
]);

/**
 * Nombre del archivo que eligió el usuario.
 *
 * Se acepta tal cual —acentos, espacios, paréntesis— porque es el nombre real de
 * un documento del INCES y no un identificador. El servidor lo usa **sólo** para
 * extraer la extensión y para el `Content-Disposition` de la descarga: la clave
 * del objeto se construye con un UUID, así que nada de esto llega a la ruta del
 * bucket. El límite de 255 replica el de un nombre de archivo habitual.
 */
const nombreDeArchivo = z
  .string()
  .trim()
  .min(1, 'El nombre del archivo no puede estar vacío.')
  .max(255, 'El nombre del archivo no puede pasar de 255 caracteres.');

/**
 * Reserva de una subida.
 *
 * **No lleva ni la clave del objeto ni su tamaño**, y las dos ausencias son
 * deliberadas:
 *
 *   · La **clave** la construye el servidor. Una URL PUT prefirmada es una
 *     autorización de escritura: si el cliente pudiera proponerla, alcanzaría a
 *     cualquier objeto del bucket.
 *   · El **tamaño** no se puede validar aquí. Una URL PUT prefirmada no admite
 *     `content-length-range`, así que el real sólo se conoce con el `HeadObject`
 *     posterior. Aceptarlo del cliente sería pedirle al sospechoso que se mida.
 *
 * `entidadId` es opcional porque la entidad —la tarea o la guía— puede crearse
 * después de subir el archivo.
 */
export const esquemaFirmarSubida = z
  .object({
    nombreOriginal: nombreDeArchivo,
    entityType: tipoEntidadArchivoSchema,
    entidadId: z.string().uuid().nullable().default(null),
  })
  .strict();

/**
 * El cuerpo del barrido de subidas abandonadas.
 *
 * **Todo es opcional, y eso es el caso normal**: quien llama a esta ruta es un
 * programador de tareas, y manda el cuerpo vacío esperando el comportamiento
 * seguro. Los valores por defecto viven en el dominio, no aquí.
 *
 * `horas` **no lleva su mínimo en este esquema**, y es deliberado. El umbral no
 * es una preferencia del llamante: sale del TTL de la URL de subida, y el mismo
 * número tiene que valer para la ruta y para el script de mantenimiento. Un
 * `min(1)` escrito aquí sería una segunda copia de esa regla —una que además no
 * lleva la explicación— y las dos se desviarían en cuanto una cambiara. Quien lo
 * comprueba es `validarHorasDeAbandono`, en `dominio/almacenamiento.ts`. Zod sólo
 * descarta lo que no es un número.
 *
 * `limite` sí se acota aquí porque no es una regla de negocio sino un tope de
 * trabajo por pasada: un valor que no sea un entero positivo no significa nada.
 */
export const esquemaBarrido = z
  .object({
    horas: z.number().optional(),
    limite: z.number().int().positive().optional(),
  })
  .strict();

/**
 * Los dos parámetros de la ruta de listado por entidad.
 *
 * `entityType` va como **enum** y no como texto libre, y la diferencia importa:
 * un tipo inventado —`TAREA`, `task_submission` en minúsculas— rechazado aquí da
 * un 400 que nombra el campo. Si se aceptara como cadena y se pasara a la
 * consulta, Postgres devolvería **cero filas sin error**, y el cliente recibiría
 * una lista vacía que es indistinguible de «esta tarea todavía no tiene
 * archivos». Eso manda a buscar el problema al sitio equivocado, que es
 * exactamente el fallo que el `check` de `entity_type` evita en la tabla.
 *
 * `entidadId` se valida como UUID por la razón de siempre en este proyecto: sin
 * esto, un id mal escrito viaja hasta Postgres, revienta con `22P02` y sale como
 * un `500` genérico por lo que en realidad es una URL mal formada.
 */
export const esquemaRutaEntidad = z.object({
  entityType: tipoEntidadArchivoSchema,
  entidadId: z.string().uuid({
    message: 'El identificador de la entidad debe ser un UUID válido.',
  }),
});

export type ListadoAulasEntrada = z.infer<typeof esquemaListadoAulas>;
export type CrearAulaEntrada = z.infer<typeof esquemaCrearAula>;
export type ActualizarAulaEntrada = z.infer<typeof esquemaActualizarAula>;
export type CrearPeriodoEntrada = z.infer<typeof esquemaCrearPeriodo>;
export type ActualizarPeriodoEntrada = z.infer<typeof esquemaActualizarPeriodo>;
export type CrearGuardiaEntrada = z.infer<typeof esquemaCrearGuardia>;
export type ActualizarGuardiaEntrada = z.infer<typeof esquemaActualizarGuardia>;
export type ListadoGuardiasEntrada = z.infer<typeof esquemaListadoGuardias>;
export type RejillaEntrada = z.infer<typeof esquemaRejilla>;
export type CrearClaseEntrada = z.infer<typeof esquemaCrearClase>;
export type ActualizarClaseEntrada = z.infer<typeof esquemaActualizarClase>;
export type MiHorarioEntrada = z.infer<typeof esquemaMiHorario>;
export type ListadoSeccionesEntrada = z.infer<typeof esquemaListadoSecciones>;
export type CrearSeccionEntrada = z.infer<typeof esquemaCrearSeccion>;
export type ActualizarSeccionEntrada = z.infer<typeof esquemaActualizarSeccion>;
export type ListadoOfertasEntrada = z.infer<typeof esquemaListadoOfertas>;
export type SolicitarInscripcionEntrada = z.infer<typeof esquemaSolicitarInscripcion>;
export type ReincorporarEntrada = z.infer<typeof esquemaReincorporar>;
export type FirmarSubidaEntrada = z.infer<typeof esquemaFirmarSubida>;
export type BarridoEntrada = z.infer<typeof esquemaBarrido>;
export type RutaEntidadEntrada = z.infer<typeof esquemaRutaEntidad>;

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
