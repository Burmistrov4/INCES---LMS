import type { FastifyInstance } from 'fastify';
import type { DependenciasRutas } from '../dependencias.js';
import {
  esquemaCalificar,
  esquemaCrearAnuncio,
  esquemaCrearTarea,
  esquemaRutaEntrega,
  esquemaRutaSeccion,
  esquemaRutaTarea,
} from '../esquemas.js';
import { exigirSesion, reposDe } from '../plugins/autenticacion.js';
import { exigirModulo } from '../plugins/modulos.js';

/**
 * Rutas del Módulo 6 — Aula Virtual.
 *
 * El «Google Classroom a la medida del INCES»: un docente publica anuncios en el
 * Tablón y trabajo en «Trabajo de clase»; los alumnos matriculados lo ven,
 * entregan y reciben nota.
 *
 * **La autorización la hace la base, no estas rutas.** Las lecturas van por
 * PostgREST y las filtra la RLS; las escrituras van por RPC `security definer`
 * que comprueban `auth.uid()`. Repetir esa comprobación aquí sería una segunda
 * copia de la regla, y dos copias se desvían — es la decisión ADR-003, la misma
 * que siguen M4 y M5.
 *
 * **La guardia de módulo es la excepción, y no contradice lo anterior.** Que el
 * módulo esté encendido no lo sabe la base: no hay política RLS ni RPC que
 * consulte `system_modules`. Es una regla que sólo existe aquí, así que
 * comprobarla aquí no duplica nada, y por eso apagar `m6_aula_virtual` desde el
 * cPanel surte efecto de verdad y no sólo esconde el ítem del menú.
 *
 * **Las diez rutas reparten el mismo camino que la UI de Google**: leer el
 * tablón y el trabajo, publicar, entregar, calificar y devolver. El «des-
 * entregar» (`m6_reclamar_entrega`) existe en la base y en el puerto, pero
 * todavía no tiene ruta: el contrato HTTP del diseño no lo expone, y añadirlo
 * sería inventar superficie que ninguna pantalla usa.
 */
export function rutasAula(app: FastifyInstance, deps: DependenciasRutas): void {
  /**
   * La guardia del módulo, construida **una sola vez**.
   *
   * `exigirModulo` es una fábrica: recibe la caché y la clave y devuelve el
   * `preHandler`. Se construye aquí arriba para que la clave `m6_aula_virtual`
   * aparezca una sola vez en el archivo —si el módulo se renombrara, hay un único
   * sitio que corregir—. El hook es una función sin estado, así que compartirlo
   * entre diez rutas es seguro.
   *
   * **Va siempre en segundo lugar, después de `exigirSesion()`.** El orden no es
   * cosmético: sin sesión, `request.usuario` es `null` y la guardia no puede
   * distinguir «el módulo está apagado» de «no hay quien pregunte». Colocada
   * primero, una petición anónima recibiría 403 (o 404, si faltara la semilla) en
   * vez del **401** que le corresponde — que es justo lo que exige
   * `openapi.test.ts`, que inyecta cada ruta documentada sin token y comprueba
   * que responde 401 y no 404.
   */
  const exigirAula = exigirModulo(deps.caches.modulos, 'm6_aula_virtual');

  // --- Tablón ---------------------------------------------------------------

  /**
   * El feed de anuncios de una sección.
   *
   * Quién ve qué lo decide la RLS, no esta ruta: un docente de la sección ve
   * también los borradores, y un alumno ve los publicados **y** los programados
   * cuya hora ya llegó. La publicación diferida se resuelve en la política de
   * lectura, sin ningún proceso que la ejecute.
   */
  app.get<{ Params: { seccionId: string } }>(
    '/api/v1/aula/secciones/:seccionId/tablon',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { seccionId } = esquemaRutaSeccion.parse(request.params);

      const anuncios = await reposDe(request).aula.tablon(seccionId);

      return { anuncios };
    },
  );

  /**
   * Publica un anuncio.
   *
   * La RPC exige que el llamante **dicte** la sección (o sea administrador) y
   * lanza `42501` si no: se traduce a 403 con el mensaje de la base, sin que la
   * ruta tenga que saber quién dicta qué.
   */
  app.post<{ Params: { seccionId: string } }>(
    '/api/v1/aula/secciones/:seccionId/anuncios',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request, reply) => {
      const { seccionId } = esquemaRutaSeccion.parse(request.params);
      const entrada = esquemaCrearAnuncio.parse(request.body);

      const anuncio = await reposDe(request).aula.crearAnuncio({
        seccionId,
        titulo: entrada.titulo,
        cuerpo: entrada.cuerpo,
        programadoPara: entrada.programadoPara,
      });

      // 201: se creó el anuncio, y la respuesta trae su identificador.
      return reply.status(201).send({ anuncio });
    },
  );

  // --- Trabajo de clase -----------------------------------------------------

  /**
   * El trabajo de clase de una sección.
   *
   * Un alumno ve sólo lo publicado —o lo programado ya vencido—; el docente de la
   * sección ve también sus borradores. La lista de columnas es explícita, así que
   * la forma de la respuesta no cambia porque una migración añada una columna.
   */
  app.get<{ Params: { seccionId: string } }>(
    '/api/v1/aula/secciones/:seccionId/trabajo',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { seccionId } = esquemaRutaSeccion.parse(request.params);

      const tareas = await reposDe(request).aula.trabajoDeClase(seccionId);

      return { tareas };
    },
  );

  /**
   * Crea trabajo de clase. Nace `BORRADOR` y **sin entregas**: publicar es lo que
   * crea los placeholders, uno por matrícula `ENROLLED`.
   *
   * La coherencia MATERIAL/sin nota la comprueba la RPC —y el `CHECK` de la
   * tabla—, no esta ruta: un `MATERIAL` con puntos vuelve como 400 con el mensaje
   * de la base, que explica el porqué mejor que un `check constraint` a secas.
   */
  app.post<{ Params: { seccionId: string } }>(
    '/api/v1/aula/secciones/:seccionId/tareas',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request, reply) => {
      const { seccionId } = esquemaRutaSeccion.parse(request.params);
      const entrada = esquemaCrearTarea.parse(request.body);

      const tarea = await reposDe(request).aula.crearTarea({
        seccionId,
        titulo: entrada.titulo,
        descripcion: entrada.descripcion,
        tipo: entrada.tipo,
        puntosMaximos: entrada.puntosMaximos,
        fechaLimite: entrada.fechaLimite,
        permitirEntregaTardia: entrada.permitirEntregaTardia,
        tema: entrada.tema,
        orden: entrada.orden,
      });

      return reply.status(201).send({ tarea });
    },
  );

  /**
   * Publica una tarea y crea los placeholders de entrega.
   *
   * **Idempotente.** Publicar dos veces no duplica entregas: el
   * `unique (tarea_id, estudiante_id)` con `on conflict do nothing` lo garantiza
   * en la base. `entregasCreadas` es 0 en la segunda llamada, y eso es un 200 con
   * la verdad, no un error.
   *
   * La tarea que se devuelve es la **cabecera** —estado y fecha de publicación—
   * porque es lo que la RPC devuelve. Completar los demás campos aquí sería
   * inventarlos.
   */
  app.post<{ Params: { tareaId: string } }>(
    '/api/v1/aula/tareas/:tareaId/publicar',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { tareaId } = esquemaRutaTarea.parse(request.params);

      return reposDe(request).aula.publicarTarea(tareaId);
    },
  );

  /**
   * El libro de calificaciones de una tarea.
   *
   * Va por RPC y no por lectura directa por un motivo que conviene tener
   * escrito: `m6_entregas` protege `nota_borrador` con un `GRANT` por columna, y
   * `authenticated` no tiene privilegio de `SELECT` sobre ella. Una lectura
   * normal habría devuelto la columna en blanco **sin dar error**, y el docente
   * habría calificado a ciegas. La RPC es `security definer` y la lee como dueña
   * de la función; además deriva `faltante` al leer, que es lo que evita
   * escribir un 0 automático que quedaría congelado.
   */
  app.get<{ Params: { tareaId: string } }>(
    '/api/v1/aula/tareas/:tareaId/entregas',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { tareaId } = esquemaRutaTarea.parse(request.params);

      const entregas = await reposDe(request).aula.entregasDeTarea(tareaId);

      return { entregas };
    },
  );

  // --- Entregas del alumno --------------------------------------------------

  /**
   * Las entregas que el llamante puede ver.
   *
   * **No se filtra por el usuario aquí, y es deliberado**: lo decide la RLS. Para
   * un alumno son las suyas; añadir un filtro por `estudiante_id` sería una
   * segunda copia de la política, y la copia se desviaría en cuanto la política
   * cambiara. La selección de columnas **excluye `nota_borrador`**, así que la
   * nota sin devolver no puede viajar al alumno ni por descuido.
   */
  app.get(
    '/api/v1/aula/mis-entregas',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const entregas = await reposDe(request).aula.misEntregas();

      return { entregas };
    },
  );

  /**
   * Entrega una tarea.
   *
   * La RPC comprueba tres cosas en la misma transacción y las tres importan:
   * que la entrega sea **del alumno** (`42501` → 403), que la tarea esté
   * publicada, y si la entrega llega tarde respecto a la fecha límite —el
   * retraso se escribe ahí, no lo calcula ningún proceso después—. Si la tarea
   * cerró y no admite tardías, el 400 trae el mensaje de la base con la fecha.
   */
  app.post<{ Params: { entregaId: string } }>(
    '/api/v1/aula/entregas/:entregaId/entregar',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { entregaId } = esquemaRutaEntrega.parse(request.params);

      const entrega = await reposDe(request).aula.entregar(entregaId);

      return { entrega };
    },
  );

  /**
   * Reclama la entrega: el «des-entregar» de Google, y la única válvula de
   * escape de `MODIFIABLE_UNTIL_TURNED_IN`.
   *
   * Sin esta ruta, el botón «Reclamar entrega» de la UI no tendría a dónde
   * llamar: la RPC existe y está concedida, pero un cliente no puede invocarla
   * si no hay puerta HTTP. La entrega vuelve a `RECLAMADA` para que el alumno
   * pueda volver a entregarla.
   *
   * La RPC devuelve exactamente las mismas columnas que `entregar`
   * (`id, tarea_id, estado, es_tardia, nota_asignada, entregada_en`), así que la
   * respuesta es la misma `Entrega` en camelCase. Las dos condiciones —ser el
   * dueño y venir de `ENTREGADA`— las decide la base: una entrega ya devuelta no
   * se reabre, y eso llega como 403 o 400 con su mensaje, no como un filtro que
   * esta ruta repita.
   */
  app.post<{ Params: { entregaId: string } }>(
    '/api/v1/aula/entregas/:entregaId/reclamar',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { entregaId } = esquemaRutaEntrega.parse(request.params);

      const entrega = await reposDe(request).aula.reclamar(entregaId);

      return { entrega };
    },
  );

  // --- Calificación ---------------------------------------------------------

  /**
   * Escribe la nota **borrador**: el alumno todavía no la ve.
   *
   * Sólo el docente de la sección, sólo sobre una entrega ya entregada y nunca
   * por encima de los puntos de la tarea —las tres las comprueba la RPC y llegan
   * como 403 o 400 con su mensaje—. El 0–20 lo valida además Zod, que da el 400
   * antes de abrir una transacción.
   *
   * `nota_borrador` viaja en la respuesta a propósito: quien llama es el docente
   * y la RPC ya lo autorizó.
   */
  app.post<{ Params: { entregaId: string } }>(
    '/api/v1/aula/entregas/:entregaId/calificar',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { entregaId } = esquemaRutaEntrega.parse(request.params);
      const { nota } = esquemaCalificar.parse(request.body);

      const entrega = await reposDe(request).aula.calificar(entregaId, nota);

      return { entrega };
    },
  );

  /**
   * Devuelve la entrega: copia el borrador a la nota asignada y cierra el ciclo.
   *
   * Es el **único** momento en que el alumno ve una nota. Devolver **sin** nota
   * es legítimo —es el «devuelta sin calificar» de Google—: lo que la tabla
   * impide, con un `CHECK`, es una nota asignada sin borrador.
   */
  app.post<{ Params: { entregaId: string } }>(
    '/api/v1/aula/entregas/:entregaId/devolver',
    { preHandler: [exigirSesion(), exigirAula] },
    async (request) => {
      const { entregaId } = esquemaRutaEntrega.parse(request.params);

      const entrega = await reposDe(request).aula.devolver(entregaId);

      return { entrega };
    },
  );
}
