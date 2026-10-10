import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { SupabaseClient } from '@supabase/supabase-js';
import { describe, expect, it } from 'vitest';
import { ErrorApi } from '../src/dominio/errores.js';
import { esBloqueoPorPensumEnUso } from '../src/dominio/reglas-curriculo.js';
import { crearRepositorios } from '../src/infra/repos-supabase.js';

/**
 * El repositorio de currículo, contra un cliente de Supabase **falso**.
 *
 * El arnés en memoria sustituye el repositorio entero, así que no puede probar
 * nada de lo que ocurre dentro de él. Y dentro de él están las dos decisiones
 * que más importan de M2:
 *
 *   1. Que las escrituras del asistente van por `supabase.rpc(...)` y **nunca**
 *      por un `insert` directo. Si alguien cambiara una por un insert, la
 *      atomicidad desaparecería sin que ninguna prueba de ruta se enterara: el
 *      caso feliz sigue funcionando igual.
 *   2. Que el `23514` de la Regla 2 se traduce a un `409 PENSUM_EN_USO`, y el
 *      de la Regla 1 a un `400 RESTRICCION_VIOLADA`.
 *
 * Un doble del *cliente* (no del repositorio) es lo que permite ver las dos
 * cosas sin red y sin credenciales.
 */

const AQUI = dirname(fileURLToPath(import.meta.url));
const RUTA_MIGRACION_REGLA_2 = join(
  AQUI,
  '..',
  '..',
  'supabase',
  'migrations',
  '202609160001_resolucion_d12_d13.sql',
);

const PROGRAMA_ID = '11111111-1111-4111-8111-111111111111';
const MATERIA_ID = 'aaaaaaaa-1111-4111-8111-111111111111';

/**
 * El texto real del trigger de la Regla 2, copiado de la migración.
 *
 * `%` ya sustituido por los valores que PostgreSQL interpola. Una prueba de
 * abajo comprueba que el fragmento sigue estando en el archivo de la
 * migración, así que esto no es una copia que se queda atrás en silencio.
 */
const MENSAJE_REGLA_2 =
  'No se puede modificar el pensum: el programa tiene 2 sección(es) activa(s) ' +
  'en el período 2026-1. Archive esas secciones primero, o clone el programa y ' +
  'cree una versión nueva del pensum.';

const MENSAJE_REGLA_1 =
  'Una carrera activa no puede quedarse sin materias. Añada al menos una al ' +
  'pensum o póngala en borrador (is_active = false).';

/** Una fila de `programs` tal como la devuelve PostgREST: en inglés y en snake_case. */
const FILA_PROGRAMA = {
  id: PROGRAMA_ID,
  code: 'SIST-02',
  name: 'Análisis de Sistemas',
  type: 'CARRERA',
  requires_internship: true,
  is_active: false,
  created_at: '2026-09-15T10:00:00.000Z',
  updated_at: '2026-09-15T10:00:00.000Z',
};

interface RespuestaFalsa {
  data: unknown;
  error: unknown;
  count?: number | null;
}

/**
 * Un *builder* de PostgREST mínimo: encadenable y esperable.
 *
 * `insert` y `update` no devuelven el builder en silencio: avisan por el
 * llamante, que es como esta prueba detecta una escritura directa.
 */
function consultaFalsa(
  respuesta: RespuestaFalsa,
  alEscribir: (metodo: string) => void,
  alFiltrar: (metodo: string, valor: string) => void,
  alFiltrarCampo: (metodo: string, columna: string, valor: unknown) => void = () => {},
) {
  const builder: Record<string, unknown> = {};

  for (const metodo of ['select', 'order', 'limit', 'range']) {
    builder[metodo] = () => builder;
  }

  // `eq` e `in` se registran ADEMÁS de devolver el builder. Son los filtros que
  // el recuento y la página tienen que compartir para que el total corresponda
  // a las filas, y hasta ahora no había forma de observarlos. Se guardan en un
  // registro aparte para no alterar la prueba que ya cuenta llamadas a `.or(...)`.
  for (const metodo of ['eq', 'in']) {
    builder[metodo] = (columna: string, valor: unknown) => {
      alFiltrarCampo(metodo, columna, valor);
      return builder;
    };
  }

  for (const metodo of ['insert', 'update']) {
    builder[metodo] = () => {
      alEscribir(metodo);
      return builder;
    };
  }

  // `or` se registra en vez de ignorarse: es donde vive el único riesgo de
  // sintaxis de estas consultas, así que conviene poder mirarlo.
  builder.or = (valor: string) => {
    alFiltrar('or', valor);
    return builder;
  };

  builder.maybeSingle = async () => respuesta;
  builder.single = async () => respuesta;

  // Hace que `await builder` resuelva la respuesta, como el builder real.
  builder.then = (resolver: (valor: RespuestaFalsa) => unknown) =>
    Promise.resolve(respuesta).then(resolver);

  return builder;
}

function montarCliente(comportamiento: {
  rpc?: (funcion: string, argumentos: Record<string, unknown>) => RespuestaFalsa;
  tablas?: Record<string, RespuestaFalsa>;
  /**
   * Respuestas por llamada sucesiva a `from(tabla)`. Permite que el recuento y
   * la página —que ahora van en paralelo— reciban respuestas distintas: es lo
   * único que permite reproducir el 416 de PostgREST sin red.
   */
  secuencias?: Record<string, RespuestaFalsa[]>;
}) {
  const rpcLlamadas: { funcion: string; argumentos: Record<string, unknown> }[] = [];
  const escriturasDirectas: string[] = [];
  const filtros: { metodo: string; valor: string; tabla: string }[] = [];
  /** Una entrada por `from(tabla)`, con los filtros `eq`/`in` que recibió. */
  const consultas: { tabla: string; filtros: string[] }[] = [];
  const usos = new Map<string, number>();

  const cliente = {
    rpc: async (funcion: string, argumentos: Record<string, unknown>) => {
      rpcLlamadas.push({ funcion, argumentos });
      return comportamiento.rpc?.(funcion, argumentos) ?? { data: null, error: null };
    },
    from: (tabla: string) => {
      const secuencia = comportamiento.secuencias?.[tabla];
      let respuesta: RespuestaFalsa;
      if (secuencia) {
        const i = usos.get(tabla) ?? 0;
        respuesta = secuencia[Math.min(i, secuencia.length - 1)]!;
        usos.set(tabla, i + 1);
      } else {
        respuesta = comportamiento.tablas?.[tabla] ?? { data: [], error: null };
      }

      const registro = { tabla, filtros: [] as string[] };
      consultas.push(registro);

      return consultaFalsa(
        respuesta,
        (metodo) => {
          escriturasDirectas.push(`${metodo} ${tabla}`);
        },
        (metodo, valor) => {
          filtros.push({ metodo, valor, tabla });
        },
        (metodo, columna, valor) => {
          registro.filtros.push(`${metodo}:${columna}=${JSON.stringify(valor)}`);
        },
      );
    },
  } as unknown as SupabaseClient;

  return { cliente, rpcLlamadas, escriturasDirectas, filtros, consultas };
}

/**
 * Ejecuta una acción que debe fallar y devuelve el [ErrorApi].
 *
 * Falla ruidosamente si la acción termina bien: una prueba que sólo comprueba
 * «no explotó» pasaría aunque el error se hubiera tragado.
 */
async function capturarError(accion: () => Promise<unknown>): Promise<ErrorApi> {
  try {
    await accion();
  } catch (error) {
    if (error instanceof ErrorApi) return error;
    throw error;
  }
  throw new Error('Se esperaba un fallo y la operación terminó bien.');
}

describe('las escrituras del asistente van por función, no por insert', () => {
  it('crearPrograma llama a la RPC con los nombres de argumento exactos', async () => {
    const { cliente, rpcLlamadas, escriturasDirectas } = montarCliente({
      rpc: () => ({ data: PROGRAMA_ID, error: null }),
      tablas: {
        programs: { data: FILA_PROGRAMA, error: null },
        program_subjects: { data: [], error: null },
        // Sin período vigente declarado: `contarSeccionesActivas` devuelve 0 sin
        // consultar `sections`, que es justo el camino que se quiere ejercitar.
        system_settings: { data: null, error: null },
      },
    });

    const detalle = await crearRepositorios(cliente).curriculo.crearPrograma({
      codigo: 'SIST-02',
      nombre: 'Análisis de Sistemas',
      tipo: 'CARRERA',
      requierePasantia: true,
      publicar: false,
      pensum: [{ materiaId: MATERIA_ID, periodo: 1 }],
    });

    expect(rpcLlamadas).toHaveLength(1);
    expect(rpcLlamadas[0]?.funcion).toBe('crear_programa_con_pensum');

    // Los nombres son los de la función en PostgreSQL: PostgREST los resuelve
    // por nombre, así que un `p_code` escrito como `codigo` daría un error de
    // función inexistente en tiempo de ejecución, no de compilación.
    expect(rpcLlamadas[0]?.argumentos).toEqual({
      p_code: 'SIST-02',
      p_name: 'Análisis de Sistemas',
      p_type: 'CARRERA',
      p_requires_internship: true,
      p_publicar: false,
      p_pensum: [{ materiaId: MATERIA_ID, periodo: 1 }],
    });

    // Y ninguna escritura directa. Es la mitad que importa: si alguien
    // sustituyera la RPC por un `insert`, la prueba de rutas seguiría verde y
    // la atomicidad habría desaparecido.
    expect(escriturasDirectas).toEqual([]);

    // El detalle se relee después de la función, para no duplicar su forma.
    expect(detalle.programa.codigo).toBe('SIST-02');
    expect(detalle.editable).toBe(true);
  });

  it('reemplazarPensum llama a reemplazar_pensum con el programa y el pensum final', async () => {
    const { cliente, rpcLlamadas, escriturasDirectas } = montarCliente({
      rpc: () => ({ data: null, error: null }),
      tablas: {
        programs: { data: FILA_PROGRAMA, error: null },
        program_subjects: { data: [], error: null },
        system_settings: { data: null, error: null },
      },
    });

    await crearRepositorios(cliente).curriculo.reemplazarPensum(PROGRAMA_ID, [
      { materiaId: MATERIA_ID, periodo: 3 },
    ]);

    expect(rpcLlamadas).toHaveLength(1);
    expect(rpcLlamadas[0]?.funcion).toBe('reemplazar_pensum');
    expect(rpcLlamadas[0]?.argumentos).toEqual({
      p_program_id: PROGRAMA_ID,
      p_pensum: [{ materiaId: MATERIA_ID, periodo: 3 }],
    });
    expect(escriturasDirectas).toEqual([]);
  });
});

describe('la búsqueda se escapa para PostgREST', () => {
  it('el filtro va SIN paréntesis: los añade supabase-js', async () => {
    // El valor que se le pasa a `.or(...)` no lleva paréntesis porque el SDK
    // envuelve: `.or(f)` hace `append('or', `(${f})`)`. Si alguien "arreglara"
    // esto añadiéndolos aquí, el valor que viajaría sería `((…))` y PostgREST
    // respondería `PGRST100 unexpected "("`. Comprobado contra la base real.
    const { cliente, filtros } = montarCliente({
      tablas: { programs: { data: [], error: null, count: 0 } },
    });

    await crearRepositorios(cliente).curriculo.listarProgramas({
      busqueda: 'o,o',
      limite: 25,
      desplazamiento: 0,
    });

    // El listado y el recuento se ejecutan en paralelo; ambos deben aplicar
    // exactamente el mismo filtro para que el total corresponda a las filas.
    expect(filtros).toHaveLength(2);
    for (const filtro of filtros) {
      expect(filtro).toMatchObject({
        metodo: 'or',
        tabla: 'programs',
        valor: 'code.ilike."o,o",name.ilike."o,o"',
      });
      expect(filtro.valor.startsWith('(')).toBe(false);
    }
  });

  it('una comilla doble dentro del texto se neutraliza duplicándola', async () => {
    const { cliente, filtros } = montarCliente({
      tablas: { subjects: { data: [], error: null, count: 0 } },
    });

    await crearRepositorios(cliente).curriculo.listarMaterias({
      busqueda: 'o"brien',
      limite: 25,
      desplazamiento: 0,
    });

    expect(filtros[0]?.valor).toBe('code.ilike."o""brien",name.ilike."o""brien"');
  });
});

describe('contrato del listado paginado', () => {
  it('el recuento y la página aplican LOS MISMOS filtros', async () => {
    // Es la invariante de la que depende que «1 a 25 de N» sea verdad: si el
    // recuento filtrara distinto que la página, el total no correspondería a las
    // filas. Desde que ambos van en paralelo, además, hay que comprobar que
    // siguen construyéndose con los mismos `eq`/`or`.
    const { cliente, consultas } = montarCliente({
      tablas: { programs: { data: [], error: null, count: 0 } },
    });

    await crearRepositorios(cliente).curriculo.listarProgramas({
      tipo: 'CARRERA',
      activo: true,
      busqueda: 'sis',
      limite: 25,
      desplazamiento: 0,
    });

    const deProgramas = consultas.filter((c) => c.tabla === 'programs');
    expect(deProgramas).toHaveLength(2);
    // Mismos filtros en las dos consultas, en el mismo orden.
    expect(deProgramas[0]!.filtros).toEqual(deProgramas[1]!.filtros);
    expect(deProgramas[0]!.filtros).toEqual([
      'eq:type="CARRERA"',
      'eq:is_active=true',
    ]);
  });

  it('un desplazamiento más allá del total devuelve página vacía con el total, no un error', async () => {
    const { cliente } = montarCliente({
      tablas: { programs: { data: null, error: null, count: 3 } },
    });

    const pagina = await crearRepositorios(cliente).curriculo.listarProgramas({
      limite: 25,
      desplazamiento: 100,
    });

    expect(pagina.programas).toEqual([]);
    expect(pagina.total).toBe(3);
  });

  it('si la página responde 416 con el desplazamiento DENTRO del total, degrada a página vacía', async () => {
    // La carrera real: el recuento ve 3 filas y, antes de que llegue la página,
    // alguien borra filas y el rango queda fuera. PostgREST responde 416
    // («Requested range not satisfiable»). El contrato es página vacía con el
    // total —nunca un 500—, y es la rama que quedó como ÚNICA guarda cuando el
    // recuento dejó de pedirse por adelantado para poder paralelizarlo.
    //
    // `desplazamiento: 2` es menor que el total (3), así que NO lo atrapa la
    // guarda de desplazamiento: tiene que atraparlo el reconocimiento del 416.
    const { cliente } = montarCliente({
      secuencias: {
        programs: [
          { data: null, error: null, count: 3 }, // recuento
          {
            data: null,
            error: { status: 416, message: 'Requested range not satisfiable' },
          }, // página
          { data: null, error: null, count: 3 }, // recuento de respaldo
        ],
      },
    });

    const pagina = await crearRepositorios(cliente).curriculo.listarProgramas({
      limite: 25,
      desplazamiento: 2,
    });

    expect(pagina.programas).toEqual([]);
    expect(pagina.total).toBe(3);
  });

  it('control negativo: un error de página que NO es 416 sí se propaga', async () => {
    // Sin esto, la prueba de arriba no demostraría que el 416 se reconoce: podría
    // pasar porque el repositorio se traga CUALQUIER error de la página. Aquí un
    // fallo distinto tiene que seguir saliendo.
    const { cliente } = montarCliente({
      secuencias: {
        programs: [
          { data: null, error: null, count: 3 },
          { data: null, error: { code: 'XX000', message: 'fallo interno del motor' } },
        ],
      },
    });

    await expect(
      crearRepositorios(cliente).curriculo.listarProgramas({
        limite: 25,
        desplazamiento: 0,
      }),
    ).rejects.toThrow();
  });
});

describe('traducción del 23514: Regla 2 y Regla 1 comparten código', () => {
  it('la Regla 2 se traduce a 409 PENSUM_EN_USO', async () => {
    const { cliente } = montarCliente({
      rpc: () => ({
        data: null,
        error: { code: '23514', message: MENSAJE_REGLA_2, details: null, hint: null },
      }),
    });

    const fallo = await capturarError(() =>
      crearRepositorios(cliente).curriculo.reemplazarPensum(PROGRAMA_ID, [
        { materiaId: MATERIA_ID, periodo: 5 },
      ]),
    );

    // 409 y no 400: la petición no tiene nada inválido, hay un conflicto con el
    // estado actual del sistema. El cliente necesita la distinción para poder
    // ofrecer «archiva esas secciones primero».
    expect(fallo.estado).toBe(409);
    expect(fallo.codigo).toBe('PENSUM_EN_USO');
  });

  it('la Regla 1 se queda en 400 RESTRICCION_VIOLADA', async () => {
    const { cliente } = montarCliente({
      rpc: () => ({
        data: null,
        error: { code: '23514', message: MENSAJE_REGLA_1, details: null, hint: null },
      }),
    });

    const fallo = await capturarError(() =>
      crearRepositorios(cliente).curriculo.crearPrograma({
        codigo: 'SIST-03',
        nombre: 'Carrera vacía',
        tipo: 'CARRERA',
        requierePasantia: false,
        publicar: true,
        pensum: [{ materiaId: MATERIA_ID, periodo: 1 }],
      }),
    );

    expect(fallo.estado).toBe(400);
    expect(fallo.codigo).toBe('RESTRICCION_VIOLADA');
  });

  it('el resto de códigos sigue traduciéndose como antes', async () => {
    // La traducción de la Regla 2 no puede haberse comido las demás: el mismo
    // método envuelve todos los fallos de escritura del módulo.
    const { cliente } = montarCliente({
      rpc: () => ({
        data: null,
        error: {
          code: '23505',
          message: 'duplicate key value violates unique constraint "programs_code_key"',
          details: null,
          hint: null,
        },
      }),
    });

    const fallo = await capturarError(() =>
      crearRepositorios(cliente).curriculo.crearPrograma({
        codigo: 'SIST-01',
        nombre: 'Repetido',
        tipo: 'CARRERA',
        requierePasantia: false,
        publicar: false,
        pensum: [{ materiaId: MATERIA_ID, periodo: 1 }],
      }),
    );

    expect(fallo.estado).toBe(409);
    expect(fallo.codigo).toBe('REGISTRO_DUPLICADO');
  });

  it('el detector sigue coincidiendo con el texto que la migración lanza', () => {
    // Esta prueba es la que hace que el ancla sea viva y no una copia: lee la
    // migración de verdad. Si alguien reescribe el `raise` de la Regla 2, esto
    // falla y obliga a revisar el detector en vez de dejar una prueba verde
    // anclando un texto que ya no existe en la base.
    const sql = readFileSync(RUTA_MIGRACION_REGLA_2, 'utf8');

    expect(sql).toContain('sección(es) activa(s)');
    expect(MENSAJE_REGLA_2).toContain('sección(es) activa(s)');
    expect(esBloqueoPorPensumEnUso(MENSAJE_REGLA_2)).toBe(true);
  });
});
