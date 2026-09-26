import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorApi } from '../../dominio/errores.js';
import type { DependenciasRutas } from '../dependencias.js';
import {
  esquemaActualizarAula,
  esquemaActualizarClase,
  esquemaActualizarGuardia,
  esquemaActualizarPeriodo,
  esquemaCrearAula,
  esquemaCrearClase,
  esquemaCrearGuardia,
  esquemaCrearPeriodo,
  esquemaIdAula,
  esquemaIdClase,
  esquemaIdGuardia,
  esquemaIdPeriodo,
  esquemaListadoAulas,
  esquemaListadoGuardias,
  esquemaMiHorario,
  esquemaRejilla,
} from '../esquemas.js';
import { exigirAdmin, exigirSesion, reposDe } from '../plugins/autenticacion.js';
import { exigirModulo } from '../plugins/modulos.js';

/**
 * Rutas del Módulo 3 — Cuadrante, Horarios, Aulas y Guardias Docentes.
 *
 * Trece rutas de administración bajo `/api/v1/admin` (guardia `exigirAdmin()`) y
 * una de lectura por rol en `/api/v1/mi-horario` (guardia `exigirSesion()`).
 *
 * **Las catorce llevan además `exigirModulo('m3_cuadrante')`** y responden 403
 * `MODULO_DESHABILITADO` si el administrador apaga el módulo desde el cPanel. Va
 * después de la guardia de rol en cada caso, y es una excepción a lo de arriba
 * que no lo contradice: que el módulo esté encendido **no lo sabe la base**
 * —ninguna política RLS consulta `system_modules`—, así que comprobarlo aquí no
 * duplica ninguna regla.
 *
 * **Ninguna ruta borra.** Archivar es `activa: false`. Las dos columnas
 * `classroom_id` de `teacher_duties` y `schedule_slots` están en `on delete
 * restrict` precisamente para que borrar un aula en uso no sea posible ni por
 * accidente.
 *
 * **Ninguna ruta pregunta «¿está libre?» antes de escribir.** La guarda
 * anti-colisión vive en un trigger que cruza las dos tablas; preguntar desde
 * aquí sería una carrera y, peor, una segunda copia de la regla que se
 * desviaría. El trabajo de la API con esa guarda es traducirla, y eso ocurre en
 * el repositorio (`CHOQUE_DE_AGENDA`, ver `docs/CONTRATO_API_MODULO3.md` §8).
 *
 * El contrato completo, con el porqué de cada decisión, está en
 * `docs/CONTRATO_API_MODULO3.md`.
 */

/** Envoltorios de `params`: Fastify tipa `params` como objeto y el esquema es del valor suelto. */
const esquemaRutaIdAula = z.object({ id: esquemaIdAula });
const esquemaRutaIdPeriodo = z.object({ id: esquemaIdPeriodo });
const esquemaRutaIdGuardia = z.object({ id: esquemaIdGuardia });
const esquemaRutaIdClase = z.object({ id: esquemaIdClase });

/**
 * Código del error de «no hay horario propio».
 *
 * Se nombra porque explica una decisión y no un fallo: un administrador **no**
 * tiene horario, y devolverle una lista vacía le haría creer que no tiene
 * ninguna clase asignada en vez de que esa pregunta no aplica a su rol.
 */
const PERFIL_SIN_ROL = 'PERFIL_SIN_ROL';

/**
 * Registra las rutas del cuadrante.
 *
 * Recibe `deps` por una sola cosa: la caché de módulos que alimenta la guardia
 * `exigirModulo('m3_cuadrante')`. Antes se declaraba sin parámetro —«este módulo
 * no necesita nada inyectado»—, y esa frase dejó de ser cierta el día que la
 * bandera del módulo pasó a imponerse en la API y no sólo en el menú del
 * frontend.
 */
export function rutasCuadrante(app: FastifyInstance, deps: DependenciasRutas): void {
  /**
   * La guardia del módulo, construida **una sola vez**.
   *
   * `exigirModulo` es una fábrica: recibe la caché y la clave, y devuelve el
   * `preHandler`. Se construye aquí arriba para que la clave `m3_cuadrante`
   * aparezca una sola vez en el archivo, y porque el hook no tiene estado:
   * compartirlo entre las catorce rutas del módulo —las trece de administración
   * del bloque y `/api/v1/mi-horario`— es seguro.
   *
   * **Va después de la guardia de rol en cada caso.** En el bloque, tras
   * `exigirAdmin()`; en `/mi-horario`, tras `exigirSesion()`. El orden no es
   * cosmético: con la guardia delante, una petición anónima recibiría 403
   * `MODULO_DESHABILITADO` —o 404, si faltara la semilla— en vez del **401** que
   * le corresponde, y `openapi.test.ts` fallaría: inyecta cada ruta documentada
   * sin token y exige 401, no 404.
   */
  const exigirCuadrante = exigirModulo(deps.caches.modulos, 'm3_cuadrante');

  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());
      // Segundo a propósito: ver el porqué en la guardia de arriba.
      admin.addHook('preHandler', exigirCuadrante);

      // --- Aulas ------------------------------------------------------------

      admin.get('/aulas', async (request) => {
        const { busqueda, tipo, activa, limite, desplazamiento } =
          esquemaListadoAulas.parse(request.query);

        const { aulas, total } = await reposDe(request).cuadrante.listarAulas({
          busqueda,
          tipo,
          activa,
          limite,
          desplazamiento,
        });

        // El eco de la paginación se devuelve junto a las filas, igual que en
        // /usuarios, /acceso y /programas: la pantalla pinta «1 a 25 de 9» con
        // él, sin conservar su propia copia de lo que pidió.
        return { aulas, total, limite, desplazamiento };
      });

      admin.post('/aulas', async (request, reply) => {
        const entrada = esquemaCrearAula.parse(request.body);

        // Un nombre repetido da 409 REGISTRO_DUPLICADO (el `unique` de la tabla,
        // traducido). Dos espacios con el mismo nombre hacen imposible saber a
        // cuál se refería el cuadrante, así que no es un aviso: es un rechazo.
        const aula = await reposDe(request).cuadrante.crearAula(entrada);

        // 201 y no 200: se creó un recurso y la respuesta trae su identificador.
        return reply.status(201).send({ aula });
      });

      admin.patch<{ Params: { id: string } }>('/aulas/:id', async (request) => {
        const { id } = esquemaRutaIdAula.parse(request.params);
        const cambios = esquemaActualizarAula.parse(request.body);

        // No se comprueba la existencia antes: si el `id` no existe, el `update`
        // no toca ninguna fila y PostgREST responde `PGRST116`, que el
        // repositorio convierte en un 404 AULA_INEXISTENTE. Comprobar antes
        // costaría una consulta para adelantar un error que la escritura ya sabe
        // dar.
        const aula = await reposDe(request).cuadrante.actualizarAula(id, cambios);

        return { aula };
      });

      // --- Períodos ---------------------------------------------------------

      admin.get('/periodos', async (request) => {
        // Sin paginar: un centro acumula unos pocos lapsos al año y el
        // desplegable los necesita todos para ofrecer el siguiente.
        const periodos = await reposDe(request).cuadrante.listarPeriodos();
        return { periodos };
      });

      admin.post('/periodos', async (request, reply) => {
        const entrada = esquemaCrearPeriodo.parse(request.body);

        const periodo = await reposDe(request).cuadrante.crearPeriodo({
          codigo: entrada.codigo,
          // Los ausentes se normalizan a `null` aquí, en la frontera: la base
          // distingue «no hay fecha» de «no la mandaron», y a partir de este
          // punto esa diferencia ya no aporta nada.
          nombre: entrada.nombre ?? null,
          fechaInicio: entrada.fechaInicio ?? null,
          fechaFin: entrada.fechaFin ?? null,
        });

        return reply.status(201).send({ periodo });
      });

      admin.patch<{ Params: { id: string } }>('/periodos/:id', async (request) => {
        const { id } = esquemaRutaIdPeriodo.parse(request.params);
        const cambios = esquemaActualizarPeriodo.parse(request.body);

        const periodo = await reposDe(request).cuadrante.actualizarPeriodo(id, cambios);
        return { periodo };
      });

      /**
       * Declara ese lapso como el vigente.
       *
       * Se eligió `/periodos/:id/vigente` y no `/periodos/vigente` a propósito:
       * la segunda forma obliga a que el enrutador resuelva `vigente` contra el
       * parámetro `:id` del `PATCH` de al lado, y depende de la precedencia de
       * segmento estático sobre paramétrico. Funciona, pero es una dependencia
       * invisible que se rompe el día que alguien reorganice las rutas.
       *
       * `PUT` y no `PATCH`: el vigente es un único valor del sistema, y esta
       * llamada lo fija. No hay parche incremental que aplicar.
       */
      admin.put<{ Params: { id: string } }>('/periodos/:id/vigente', async (request) => {
        const { id } = esquemaRutaIdPeriodo.parse(request.params);

        const periodo = await reposDe(request).cuadrante.declararPeriodoVigente(id);
        return { periodo };
      });

      // --- Guardias ---------------------------------------------------------

      admin.get('/guardias', async (request) => {
        const { periodo, docenteId, aulaId, dia, bloque, activa, limite, desplazamiento } =
          esquemaListadoGuardias.parse(request.query);

        const { guardias, total } = await reposDe(request).cuadrante.listarGuardias({
          periodo,
          docenteId,
          aulaId,
          dia,
          bloque,
          activa,
          limite,
          desplazamiento,
        });

        return { guardias, total, limite, desplazamiento };
      });

      admin.post('/guardias', async (request, reply) => {
        const entrada = esquemaCrearGuardia.parse(request.body);

        // Si el docente o el espacio ya están ocupados en ese bloque, el trigger
        // lanza `23514` y el repositorio lo traduce a un 409 CHOQUE_DE_AGENDA
        // cuyo mensaje nombra el día y el bloque. El `turno` lo calcula la base
        // a partir del bloque: no se manda.
        const guardia = await reposDe(request).cuadrante.crearGuardia({
          docenteId: entrada.docenteId,
          aulaId: entrada.aulaId,
          periodo: entrada.periodo,
          dia: entrada.dia,
          bloque: entrada.bloque,
          notas: entrada.notas ?? null,
        });

        return reply.status(201).send({ guardia });
      });

      admin.patch<{ Params: { id: string } }>('/guardias/:id', async (request) => {
        const { id } = esquemaRutaIdGuardia.parse(request.params);
        const cambios = esquemaActualizarGuardia.parse(request.body);

        // Mover una guardia es un traslado: el trigger se dispara y el propio
        // registro queda excluido del chequeo, así que moverla sobre su propio
        // hueco no se rechaza a sí misma.
        const guardia = await reposDe(request).cuadrante.actualizarGuardia(id, cambios);
        return { guardia };
      });

      // --- Cuadrante --------------------------------------------------------

      admin.get('/cuadrante', async (request) => {
        const { periodo, seccionId, docenteId, aulaId, incluirInactivas } =
          esquemaRejilla.parse(request.query);

        // Las cuatro listas —clases, guardias, aulas y docentes— en una sola
        // respuesta, y no por comodidad: son las cuatro dimensiones de la misma
        // rejilla. Con cuatro peticiones la pantalla puede quedar a medio pintar
        // mostrando una guardia junto a una clase que ya no existe.
        return reposDe(request).cuadrante.rejilla({
          periodo,
          seccionId,
          docenteId,
          aulaId,
          incluirInactivas: incluirInactivas ?? false,
        });
      });

      admin.post('/cuadrante', async (request, reply) => {
        const entrada = esquemaCrearClase.parse(request.body);

        // El período no se manda: lo deriva el trigger de la sección. Si el
        // docente o el aula ya están ocupados —por una clase **o por una
        // guardia**, que es lo que un `unique` no podría ver— sale 409.
        const clase = await reposDe(request).cuadrante.crearClase(entrada);

        return reply.status(201).send({ clase });
      });

      admin.patch<{ Params: { id: string } }>('/cuadrante/:id', async (request) => {
        const { id } = esquemaRutaIdClase.parse(request.params);
        const cambios = esquemaActualizarClase.parse(request.body);

        const clase = await reposDe(request).cuadrante.actualizarClase(id, cambios);
        return { clase };
      });
    },
    { prefix: '/api/v1/admin' },
  );

  // --- Lectura por rol --------------------------------------------------------

  /**
   * El horario del llamante.
   *
   * Una sola ruta para docente y estudiante porque el aislamiento ya lo
   * garantiza la RLS y lo único que cambia es qué filas sobreviven al filtro: el
   * docente ve sus clases y sus guardias, el estudiante las clases de sus
   * secciones. No se parte en dos rutas porque serían la misma consulta con dos
   * nombres, y dos nombres para una cosa es cómo se acaba arreglando una y
   * olvidando la otra.
   */
  app.get('/api/v1/mi-horario', { preHandler: [exigirSesion(), exigirCuadrante] }, async (request) => {
    const usuario = request.usuario;
    if (!usuario) throw ErrorApi.noAutorizado();

    const rol = usuario.rol;
    if (rol === 'admin') {
      throw ErrorApi.prohibido(
        PERFIL_SIN_ROL,
        'Tu rol no tiene horario propio. La rejilla completa del centro está en el ' +
          'panel de administración.',
      );
    }

    const { periodo } = esquemaMiHorario.parse(request.query);

    return reposDe(request).cuadrante.miHorario(rol, usuario.id, periodo);
  });
}
