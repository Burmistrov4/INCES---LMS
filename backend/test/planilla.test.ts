import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import type { CampoInscripcion, PlanillaInscripcion } from '../src/dominio/tipos.js';
import {
  conToken,
  crearArnés,
  CAMPOS_POR_DEFECTO,
  ID_ADMIN,
  ID_ALUMNO,
  ID_ALUMNO_2,
  MODULOS_POR_DEFECTO,
  PERFIL_ALUMNO_2,
  PERFILES_POR_DEFECTO,
  TOKEN_ADMIN,
  TOKEN_ALUMNO,
  TOKEN_ALUMNO_2,
  type Arnés,
} from './support/arnes.js';

/**
 * El catálogo de campos y la planilla de inscripción.
 *
 * Lo que se comprueba aquí es el **contrato HTTP**, y hay tres decisiones que
 * estas pruebas existen para fijar, porque las tres son fáciles de deshacer sin
 * querer:
 *
 * 1. **La asimetría de visibilidad.** El catálogo se lee **sin sesión** —el
 *    formulario tiene que saber qué preguntar antes de que exista una cuenta— y
 *    la escritura exige sesión. Si alguien cerrara la lectura, el registro
 *    dejaría de poder pintarse; si alguien abriera la escritura, cualquiera
 *    podría escribir la planilla de cualquiera.
 * 2. **El id sale de la sesión, nunca del cuerpo.** No hay parámetro por el que
 *    pedir la planilla de otro, y el sobre `.strict()` lo garantiza: mandar un
 *    `usuarioId` es un 400, no un campo ignorado.
 * 3. **`PUT` reemplaza, no fusiona.** Quien guarda manda el documento entero; un
 *    campo opcional que se omite desaparece, y eso es la semántica de `PUT`, no
 *    un descuido.
 *
 * **La frontera de la validación también se fija aquí.** Esta API comprueba que
 * la planilla sea un objeto y que traiga los obligatorios del catálogo; **no**
 * comprueba los tipos de los valores, y hay una prueba que lo deja escrito. No
 * es una omisión: la forma la deciden `inscripcion_campos` y el trigger, y una
 * tercera copia de la regla —SQL, Zod y formulario— se desincroniza en cuanto el
 * CFS marque un campo como obligatorio desde el panel.
 *
 * Lo que **no** se puede ver desde aquí: que el `23514` de `validar_planilla()`
 * se traduzca bien contra la base real. Eso es `supabase/tests/validate.mjs` y el
 * humo contra Supabase, donde la guardia se prueba escribiendo **como
 * `authenticated`**, que es la única forma de que la prueba valga (el dueño de la
 * tabla se salta los privilegios y pasaría siempre).
 */

let app: FastifyInstance | null = null;

afterEach(async () => {
  await app?.close();
  app = null;
});

const RUTA_CAMPOS = '/api/v1/inscripcion/campos';
const RUTA_PLANILLA = '/api/v1/yo/planilla';

/** Una planilla que cumple los cuatro obligatorios del catálogo por defecto. */
const PLANILLA_COMPLETA: PlanillaInscripcion = {
  primer_nombre: 'Lorenzo',
  primer_apellido: 'Roca',
  cedula: 'V-12345678',
  nacionalidad: 'V',
};

/** Arma el arnés con dos alumnos, los dos con ficha, y el catálogo que se pida. */
function arnesConDosFichas(camposInscripcion?: CampoInscripcion[]) {
  return crearArnés({
    perfiles: [...PERFILES_POR_DEFECTO, PERFIL_ALUMNO_2],
    identidades: { [TOKEN_ALUMNO_2]: ID_ALUMNO_2 },
    planillas: { [ID_ALUMNO]: {}, [ID_ALUMNO_2]: {} },
    ...(camposInscripcion ? { camposInscripcion } : {}),
  });
}

/** Guarda una planilla como el alumno y devuelve la respuesta cruda. */
function guardarComoAlumno(planilla: unknown) {
  return app!.inject({
    method: 'PUT',
    url: RUTA_PLANILLA,
    headers: conToken(TOKEN_ALUMNO),
    payload: { planilla },
  });
}

describe('catálogo de campos (M4, público)', () => {
  it('se lee sin sesión, porque el formulario pregunta qué preguntar antes de tener cuenta', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().campos).toHaveLength(CAMPOS_POR_DEFECTO.length);
  });

  it('no devuelve nada de nadie: sólo las definiciones de los campos', async () => {
    // La ruta es pública, así que la prueba importa: lo que sale por aquí es el
    // catálogo —qué se pregunta— y no las respuestas de ningún aspirante. Si
    // alguna vez se colara un dato de alguien, sería en esta respuesta.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });

    expect(Object.keys(respuesta.json())).toEqual(['campos']);
  });

  it('devuelve el catálogo ordenado aunque la semilla venga desordenada', async () => {
    // El orden real lo hace Postgres con un `order by`; el doble lo replica para
    // que una prueba que siembre en otro orden reciba lo mismo que producción.
    const arnes = crearArnés({
      camposInscripcion: [...CAMPOS_POR_DEFECTO].reverse(),
    });
    app = arnes.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });
    const ordenes = respuesta.json().campos.map((campo: CampoInscripcion) => campo.orden);

    expect(ordenes).toEqual([...ordenes].sort((a, b) => a - b));
  });

  it('transporta las opciones tal cual, sin interpretarlas', async () => {
    // Es la decisión que permite ampliar el catálogo sin tocar el backend: una
    // forma nueva dentro de `opciones` (o un `tipo` nuevo) no puede exigir un
    // cambio aquí, y eso sólo se sostiene si el backend no las mira. Esta prueba
    // fija esa ausencia de interpretación sobre las dos formas del catálogo.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });
    const campos: CampoInscripcion[] = respuesta.json().campos;

    const rejilla = campos.find((campo) => campo.codigo === 'misiones');
    expect(rejilla?.tipo).toBe('rejilla');
    expect(rejilla?.opciones).toEqual({
      items: [
        { valor: 'MISION_RIBAS', etiqueta: 'Misión Ribas' },
        { valor: 'MISION_SUCRE', etiqueta: 'Misión Sucre' },
      ],
      multiple: true,
    });

    const seleccion = campos.find((campo) => campo.codigo === 'nacionalidad');
    expect(seleccion?.opciones).toEqual({
      opciones: [
        { valor: 'V', etiqueta: 'Venezolano/a' },
        { valor: 'E', etiqueta: 'Extranjero/a' },
      ],
    });
  });

  it('marca la obligatoriedad, para que el formulario no dependa de un viaje de ida y vuelta', async () => {
    // Es un espejo informativo: la autoridad es el trigger de la base. Pero si el
    // espejo no viajara, la pantalla no podría marcar los campos antes de enviar
    // y el usuario descubriría qué faltaba sólo al recibir el 400.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });
    const campos: CampoInscripcion[] = respuesta.json().campos;
    const obligatorios = campos.filter((campo) => campo.obligatorio).map((c) => c.codigo);

    expect(obligatorios).toEqual(['primer_nombre', 'primer_apellido', 'cedula', 'nacionalidad']);
  });
});

describe('control de acceso a la escritura', () => {
  it('exige sesión para guardar la planilla', async () => {
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: RUTA_PLANILLA,
      payload: { planilla: PLANILLA_COMPLETA },
    });

    expect(respuesta.statusCode).toBe(401);
    expect(respuesta.json().error.codigo).toBe('NO_AUTENTICADO');
  });

  it('un usuario sin ficha de aspirante recibe 404, no un 500', async () => {
    // El administrador se registró por otra vía, así que el trigger de alta no le
    // creó fila en `aspirantes`. Es el caso real del docente que intenta rellenar
    // el formulario, y la respuesta tiene que explicarlo en vez de reventar.
    const arnes = crearArnés();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: RUTA_PLANILLA,
      headers: conToken(TOKEN_ADMIN),
      payload: { planilla: PLANILLA_COMPLETA },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('SIN_FICHA_DE_ASPIRANTE');
    expect(respuesta.json().error.mensaje).toMatch(/ficha de aspirante/i);
  });

  it('no hay forma de escribir la planilla de otro: el id sale de la sesión', async () => {
    const arnes = arnesConDosFichas();
    app = arnes.app;

    // Cada uno escribe la suya…
    const comoAlumno = await guardarComoAlumno({ ...PLANILLA_COMPLETA, primer_nombre: 'Lorenzo' });
    expect(comoAlumno.statusCode).toBe(200);

    const comoAlumno2 = await app.inject({
      method: 'PUT',
      url: RUTA_PLANILLA,
      headers: conToken(TOKEN_ALUMNO_2),
      payload: { planilla: { ...PLANILLA_COMPLETA, primer_nombre: 'Sleither' } },
    });
    expect(comoAlumno2.statusCode).toBe(200);

    // …y cada planilla quedó en su sitio, sin pisarse.
    expect(arnes.estado.planillas[ID_ALUMNO]?.primer_nombre).toBe('Lorenzo');
    expect(arnes.estado.planillas[ID_ALUMNO_2]?.primer_nombre).toBe('Sleither');
  });

  it('no acepta un `usuarioId` en el cuerpo: el sobre es estricto', async () => {
    // El `.strict()` no es cosmético. Es lo que convierte «no se puede escribir la
    // planilla de otro» en una garantía estructural: no hay parámetro por el que
    // pedirlo, y si alguien lo añadiera creyendo que se ignora, esto lo delata.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: RUTA_PLANILLA,
      headers: conToken(TOKEN_ALUMNO),
      payload: { planilla: PLANILLA_COMPLETA, usuarioId: ID_ALUMNO_2 },
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    expect(JSON.stringify(respuesta.json().error.detalles)).toContain('usuarioId');
  });
});

describe('guardado de la planilla', () => {
  it('guarda una planilla completa y devuelve lo almacenado', async () => {
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await guardarComoAlumno(PLANILLA_COMPLETA);

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().planilla).toEqual(PLANILLA_COMPLETA);
    expect(arnes.estado.planillas[ID_ALUMNO]).toEqual(PLANILLA_COMPLETA);
  });

  it('rechaza una planilla sin los obligatorios y **nombra los que faltan**', async () => {
    // El mensaje es el producto de la ruta, no un detalle: es el único sitio
    // donde el `23514` de la base —que nombra los campos en un texto de
    // PostgreSQL— se convierte en algo que el usuario puede accionar.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await guardarComoAlumno({ primer_nombre: 'Lorenzo' });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_INCOMPLETA');
    expect(respuesta.json().error.mensaje).toContain('primer_apellido');
    expect(respuesta.json().error.mensaje).toContain('cedula');
    expect(respuesta.json().error.mensaje).toContain('nacionalidad');
  });

  it('nombra los que faltan en el orden del catálogo, no en el que se le ocurra', async () => {
    const arnes = arnesConDosFichas();
    app = arnes.app;

    // La planilla es **no vacía a propósito**: una del todo vacía la corta antes
    // el esquema —porque reemplazaría el documento por nada—, y entonces el
    // mensaje que llega no es el de los campos que faltan sino el de «viene
    // vacía». Con un campo presente se llega a la regla de obligatoriedad, que es
    // la que aquí se quiere leer.
    const respuesta = await guardarComoAlumno({ nacionalidad: 'V' });
    const mensaje: string = respuesta.json().error.mensaje;

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_INCOMPLETA');

    // El orden del catálogo es el del formulario, así que el mensaje se lee en el
    // mismo orden en que el usuario ve los campos.
    expect(mensaje.indexOf('primer_nombre')).toBeLessThan(mensaje.indexOf('primer_apellido'));
    expect(mensaje.indexOf('primer_apellido')).toBeLessThan(mensaje.indexOf('cedula'));

    // Y no nombra el que sí vino: un mensaje que listara todo sería ruido.
    expect(mensaje).not.toContain('nacionalidad');
  });

  it('un obligatorio en blanco no cuenta como presente', async () => {
    // La regla de la base distingue «la clave está» de «la clave trae algo». Sin
    // esa mitad, mandar `cedula: ''` pasaría la validación y la planilla quedaría
    // «completa» con un dato que no sirve.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await guardarComoAlumno({ ...PLANILLA_COMPLETA, cedula: '   ' });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PLANILLA_INCOMPLETA');
    expect(respuesta.json().error.mensaje).toContain('cedula');
    expect(respuesta.json().error.mensaje).not.toContain('primer_nombre');
  });

  it('rechaza una planilla vacía: reemplazaría el documento por nada', async () => {
    // El `PUT` reemplaza, así que `{}` no significa «no cambies nada» sino
    // «bórralo todo». El esquema lo corta antes de que llegue a la base, y por eso
    // el error es de validación (PETICION_INVALIDA) y no de negocio.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await guardarComoAlumno({});

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
    expect(JSON.stringify(respuesta.json().error.detalles)).toMatch(/vacía/i);
  });

  it('exige que la planilla venga en el cuerpo', async () => {
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: RUTA_PLANILLA,
      headers: conToken(TOKEN_ALUMNO),
      payload: {},
    });

    expect(respuesta.statusCode).toBe(400);
    expect(respuesta.json().error.codigo).toBe('PETICION_INVALIDA');
  });

  it('acepta campos que el catálogo todavía no conoce', async () => {
    // El contenido de la planilla es **abierto**: añadir un campo es una fila en
    // `inscripcion_campos`, y no puede exigir un despliegue del backend. Si Zod
    // validara el contenido, cada ampliación del formulario sería un cambio de
    // API, que es justo lo que `datos_planilla` existe para evitar.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await guardarComoAlumno({
      ...PLANILLA_COMPLETA,
      campo_que_el_cfs_anadira: 'algo',
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().planilla.campo_que_el_cfs_anadira).toBe('algo');
  });

  it('reemplaza la planilla entera: lo que no se manda, desaparece', async () => {
    // Es la semántica de `PUT` y conviene que esté fijada: el cliente manda el
    // documento completo y no tiene que saber qué había antes para decidir qué
    // borrar. Un `PATCH` habría obligado a la pantalla a calcular la diferencia.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    await guardarComoAlumno({ ...PLANILLA_COMPLETA, fecha_nacimiento: '2003-05-14' });

    const segunda = await guardarComoAlumno(PLANILLA_COMPLETA);

    expect(segunda.statusCode).toBe(200);
    expect(segunda.json().planilla).not.toHaveProperty('fecha_nacimiento');
    expect(arnes.estado.planillas[ID_ALUMNO]).not.toHaveProperty('fecha_nacimiento');
  });

  it('un `false` o un `0` **no** cuentan como vacío', async () => {
    // El error clásico: escribir la comprobación de vacío con `if (!valor)` y
    // rechazar un `false` o un `0` legítimos. En una planilla real hay campos
    // booleanos («¿tiene alguna diversidad funcional?») donde `false` es una
    // respuesta, no una ausencia, y un `0` puede ser un número válido.
    const arnes = arnesConDosFichas([
      ...CAMPOS_POR_DEFECTO,
      {
        codigo: 'hijos',
        etiqueta: 'Número de hijos',
        grupo: 'Datos personales',
        tipo: 'numero',
        obligatorio: true,
        orden: 80,
        opciones: null,
        fuente: null,
        condicion: null,
        ayuda: null,
      },
      {
        codigo: 'acepta_terminos',
        etiqueta: 'Acepta los términos',
        grupo: 'Datos personales',
        tipo: 'booleano',
        obligatorio: true,
        orden: 90,
        opciones: null,
        fuente: null,
        condicion: null,
        ayuda: null,
      },
    ]);
    app = arnes.app;

    const respuesta = await guardarComoAlumno({
      ...PLANILLA_COMPLETA,
      hijos: 0,
      acepta_terminos: false,
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().planilla).toMatchObject({ hijos: 0, acepta_terminos: false });
  });

  it('no valida los tipos de los valores, y eso es deliberado', async () => {
    // Fija la **frontera de responsabilidad**, que es tan parte del contrato como
    // lo que sí se valida. Aquí se comprueba que la planilla es un objeto y que
    // trae los obligatorios; qué forma tiene cada valor lo deciden el `tipo` del
    // campo y quien lee la planilla. Validarlo también en la API sería una tercera
    // copia de la regla, y las tres se desviarían en cuanto el CFS tocara el
    // catálogo desde el panel.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await guardarComoAlumno({
      ...PLANILLA_COMPLETA,
      fecha_nacimiento: 'no-es-una-fecha',
    });

    expect(respuesta.statusCode).toBe(200);
    expect(respuesta.json().planilla.fecha_nacimiento).toBe('no-es-una-fecha');
  });

  it('no deja la planilla a medias cuando la rechaza', async () => {
    // Un 400 no puede haber escrito nada: si la escritura fallara a mitad, el
    // usuario perdería lo que ya tenía por mandar un documento incompleto.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    await guardarComoAlumno(PLANILLA_COMPLETA);
    const respuesta = await guardarComoAlumno({ primer_nombre: 'Otro' });

    expect(respuesta.statusCode).toBe(400);
    expect(arnes.estado.planillas[ID_ALUMNO]).toEqual(PLANILLA_COMPLETA);
  });

  it('el administrador tampoco puede escribir la planilla de un alumno por esta ruta', async () => {
    // La ruta es «la mía», no «la de quien diga el cuerpo». Si el admin tuviera
    // que corregir la planilla de alguien, sería otra ruta con su propio permiso,
    // y esta prueba deja claro que no es ésta.
    const arnes = arnesConDosFichas();
    app = arnes.app;

    const respuesta = await app.inject({
      method: 'PUT',
      url: RUTA_PLANILLA,
      headers: conToken(TOKEN_ADMIN),
      payload: { planilla: PLANILLA_COMPLETA },
    });

    expect(respuesta.statusCode).toBe(404);
    expect(arnes.estado.planillas[ID_ALUMNO]).toEqual({});
    expect(arnes.estado.planillas[ID_ADMIN]).toBeUndefined();
  });
});

/**
 * La guardia de la bandera `m4_inscripciones` sobre las dos rutas de la planilla.
 *
 * Las dos rutas de este archivo son las que hacen visible que la guardia del
 * módulo y la guardia de sesión son **dos ejes distintos**, y por eso se prueban
 * juntas: una es pública y la otra exige rol admin, y las dos llevan la misma
 * bandera.
 */
describe('la guardia del módulo (m4_inscripciones)', () => {
  /** El arnés con `m4_inscripciones` apagado, como si el administrador lo apagara. */
  function conModuloApagado(): Arnés {
    return crearArnés({
      modulos: MODULOS_POR_DEFECTO.map((m) =>
        m.clave === 'm4_inscripciones' ? { ...m, habilitado: false } : m,
      ),
    });
  }

  it('con el módulo apagado, el catálogo público responde 403 aunque no haya sesión', async () => {
    // Se pregunta **sin token** a propósito. Con el módulo encendido esta misma
    // petición da 200 —lo fija el bloque de control de acceso—, así que el 403
    // sólo puede venir de la bandera. Es la prueba de que `exigirModulo()` no es
    // `exigirSesion()` disfrazada: aquí no hay identidad que comprobar y, aun
    // así, hay una barrera. Con el módulo apagado no hay formulario que pintar.
    const arnés = conModuloApagado();
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('MODULO_DESHABILITADO');
  });

  it('con el módulo apagado, la planilla en PDF del administrador también responde 403', async () => {
    const arnés = conModuloApagado();
    app = arnés.app;

    const respuesta = await app.inject({
      method: 'GET',
      url: `/api/v1/inscripcion/planilla/${ID_ALUMNO}/pdf`,
      headers: conToken(TOKEN_ADMIN),
    });

    expect(respuesta.statusCode).toBe(403);
    expect(respuesta.json().error.codigo).toBe('MODULO_DESHABILITADO');
  });

  it('sin la fila del módulo el error es 404 MODULO_DESCONOCIDO, y no 403', async () => {
    // La distinción no es cosmética. `comprobarModulo` separa «no está
    // registrado» de «está apagado» a propósito: confundirlos manda a buscar el
    // problema al sitio equivocado —a la bandera, cuando lo que falta es la
    // semilla—.
    const arnés = crearArnés({ modulos: [] });
    app = arnés.app;

    const respuesta = await app.inject({ method: 'GET', url: RUTA_CAMPOS });

    expect(respuesta.statusCode).toBe(404);
    expect(respuesta.json().error.codigo).toBe('MODULO_DESCONOCIDO');
  });
});
