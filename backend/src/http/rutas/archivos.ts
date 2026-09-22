import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  HORAS_ABANDONO_POR_DEFECTO,
  LIMITE_BARRIDO_POR_DEFECTO,
  TAMANO_MAXIMO_BYTES,
  extensionDe,
  prefijoDeArchivo,
  validarHorasDeAbandono,
  validarTamano,
} from '../../dominio/almacenamiento.js';
import { ErrorApi } from '../../dominio/errores.js';
import type { PuertaAlmacenamiento } from '../../dominio/puertos.js';
import type { ParametroSistema } from '../../dominio/tipos.js';
import type { DependenciasRutas } from '../dependencias.js';
import {
  esquemaBarrido,
  esquemaFirmarSubida,
  esquemaIdArchivo,
  esquemaRutaEntidad,
} from '../esquemas.js';
import { exigirAdmin, exigirSesion, reposDe } from '../plugins/autenticacion.js';
import { exigirModulo } from '../plugins/modulos.js';

/**
 * Rutas del Módulo 5 — Archivos en Cloudflare R2.
 *
 * **El backend no mueve un solo byte.** Firma URLs —`PUT` para subir, `GET` para
 * leer— y R2 hace el transporte. Lo que la API aporta es lo que el almacén no
 * puede decidir por sí solo: de quién es cada objeto, si llegó de verdad y si
 * pesa lo que debe.
 *
 * De ahí el ciclo en dos pasos. La fila nace `PENDING` **antes** de que el objeto
 * exista, porque no hay transacción que abarque R2 y PostgreSQL: una fila
 * huérfana es visible y barrible, mientras que un objeto sin fila sería un
 * archivo fantasma que nadie puede autorizar ni limpiar. Sólo cuando el
 * `HeadObject` confirma que el objeto llegó —y pesa lo permitido— la fila pasa a
 * `CONFIRMED`.
 *
 * **La autorización la hace la base, no estas rutas.** Las escrituras van por RPC
 * `security definer` que comprueban `auth.uid()` e `is_admin()`; las lecturas van
 * por PostgREST y las filtra la RLS. Repetir esa comprobación aquí sería una
 * segunda copia de la regla, y dos copias se desvían.
 *
 * **La guardia de módulo es la excepción, y no contradice lo anterior.** Que el
 * módulo esté encendido no lo sabe la base: no hay política RLS ni RPC que
 * consulte `system_modules`. Es una regla que sólo existe aquí, así que
 * comprobarla aquí no duplica nada. Las siete rutas llevan `exigirModulo()`, y
 * por eso apagar `m5_archivos` desde el cPanel surte efecto de verdad y no sólo
 * esconde el ítem del menú.
 */

/** Envoltorio de `params`: Fastify tipa `params` como objeto y el esquema es del valor suelto. */
const esquemaRutaIdArchivo = z.object({ id: esquemaIdArchivo });

/** Límite por archivo, en bytes. Configurable desde el panel. */
const CLAVE_MAX_BYTES = 'm5_max_bytes';

/** Cuántos archivos admite una misma entidad. Configurable desde el panel. */
const CLAVE_MAX_ARCHIVOS = 'm5_max_archivos_por_entidad';

/**
 * Tope de archivos por entidad si el parámetro no estuviera sembrado.
 *
 * Es el mismo valor que siembra la migración `202609210001`. Existe para que un
 * despliegue al que le falte la semilla no quede **sin** tope, que sería el peor
 * de los fallos posibles: el límite no se aplicaría y nadie se enteraría.
 */
const ARCHIVOS_POR_ENTIDAD_POR_DEFECTO = 10;

/**
 * Lee un parámetro numérico, con un valor por defecto si no está.
 *
 * Si el parámetro **existe pero no es un número**, se falla en alto en vez de
 * caer al valor por defecto. Degradar en silencio convertiría un límite corrupto
 * en «el límite que yo decida», y el administrador creería estar aplicando uno
 * que no se usa. Es la misma razón por la que `validarTamano` rechaza un límite
 * `NaN` en vez de comparar contra él.
 */
function limiteNumerico(
  parametro: ParametroSistema | null,
  clave: string,
  porDefecto: number,
): number {
  if (parametro === null) return porDefecto;

  const valor = parametro.valor;

  if (typeof valor !== 'number' || !Number.isFinite(valor) || valor < 0) {
    throw ErrorApi.interno(
      `El parámetro «${clave}» no es un número válido. Corrígelo desde el panel.`,
    );
  }

  return valor;
}

/**
 * Registra las rutas de archivos.
 *
 * A diferencia de M3 y M4, este módulo **sí recibe dependencias**: necesita el
 * almacenamiento, que es un servicio externo con su propio ciclo de vida y no
 * una tabla. Recibirlo inyectado es lo que permite montar la API en los tests
 * sin credenciales de R2.
 */
export function rutasArchivos(
  app: FastifyInstance,
  deps: DependenciasRutas,
): void {
  /**
   * La guardia del módulo, construida **una sola vez**.
   *
   * `exigirModulo` es una fábrica: recibe la caché y la clave, y devuelve el
   * `preHandler`. Se construye aquí arriba, y no dentro de cada ruta, para que la
   * clave `m5_archivos` aparezca una sola vez en el archivo: si el módulo se
   * renombrara, hay un único sitio que corregir. El hook devuelto es una función
   * sin estado, así que compartirlo entre siete rutas es seguro.
   *
   * **Va siempre en segundo lugar, después de `exigirSesion()`.** El orden no es
   * cosmético: sin sesión, `request.usuario` es `null` y la guardia no puede
   * distinguir «el módulo está apagado» de «no hay quien pregunte». Colocada
   * primero, una petición anónima recibiría 403 (o 404, si la semilla faltara) en
   * vez del **401** que le corresponde — que es justo lo que exige
   * `openapi.test.ts`, que inyecta cada ruta documentada sin token y comprueba
   * que responde 401 y no 404.
   */
  const exigirArchivos = exigirModulo(deps.caches.modulos, 'm5_archivos');

  /**
   * El almacenamiento, o un 503 si R2 no está configurado.
   *
   * Se comprueba al atender la petición y no al arrancar: R2 es una capacidad
   * opcional a propósito, así que el backend tiene que levantar sin él y decir
   * con claridad que el módulo no está disponible, en vez de morir en el arranque
   * por algo que puede que nadie use.
   */
  function almacenamiento(): PuertaAlmacenamiento {
    if (deps.almacenamiento === null) {
      throw ErrorApi.servicioNoDisponible(
        'El almacenamiento de archivos no está configurado en este servidor.',
      );
    }

    return deps.almacenamiento;
  }

  /**
   * El límite por archivo, leído del parámetro configurable.
   *
   * Se lee **en cada petición**, no al arrancar: el administrador lo cambia desde
   * el panel y debe surtir efecto sin desplegar, que es exactamente la razón de
   * que sea un parámetro y no una constante. La caché de parámetros evita que eso
   * se traduzca en una consulta por petición.
   */
  async function maxBytes(): Promise<number> {
    const parametro = await deps.caches.parametros.porClave(CLAVE_MAX_BYTES);

    return limiteNumerico(parametro, CLAVE_MAX_BYTES, TAMANO_MAXIMO_BYTES);
  }

  /**
   * Borra un archivo: primero el metadato, después el objeto.
   *
   * **El orden es el inverso al de la confirmación, y es deliberado.** Aquí se
   * marca primero la fila (`DELETED`, con `deleted_at`) y luego se borra el objeto
   * en R2. Si fallara el borrado en el almacén, quedaría un objeto huérfano con
   * una fila que dice que ya no cuenta: recuperable, auditable y barrible. Al
   * revés quedaría una fila `CONFIRMED` apuntando a un objeto que ya no existe, y
   * el usuario vería un archivo roto sin ninguna explicación.
   *
   * Quién puede borrar lo decide la RPC (`42501` → 403 si el archivo es de otro y
   * quien llama no es admin). No se comprueba aquí: sería la segunda copia de una
   * regla que ya existe.
   */
  async function borrar(
    request: FastifyRequest<{ Params: { id: string } }>,
  ) {
    const almacen = almacenamiento();
    const { id } = esquemaRutaIdArchivo.parse(request.params);

    const archivo = await reposDe(request).archivos.marcarBorrado(id);

    await almacen.eliminar(archivo.r2Key);

    return { archivo };
  }

  // --- Administración --------------------------------------------------------

  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());

      // La guardia de módulo va **después** de `exigirAdmin()`: primero se
      // comprueba quién llama —401 sin sesión, 403 si no es admin— y sólo
      // entonces si el módulo está encendido. Al revés, una petición anónima a
      // esta ruta recibiría el error del módulo en lugar del 401 que le toca.
      admin.addHook('preHandler', exigirArchivos);

      // El administrador borra cualquier archivo. La RPC lo autoriza por
      // `is_admin()`, así que la única diferencia con la ruta del propietario es
      // la guardia: el mismo camino, con otro portero.
      admin.delete<{ Params: { id: string } }>('/archivos/:id', async (request) =>
        borrar(request),
      );

      /**
       * Barre las subidas abandonadas: borra el objeto y marca la fila.
       *
       * ── Por qué es una ruta y no un `cron` ────────────────────────────────────
       * El barrido tiene que borrar objetos de R2, y **`pg_cron` no puede**: corre
       * dentro de PostgreSQL, que no habla con el bucket. El proceso que sí tiene
       * las credenciales es este backend, así que el disparador vive aquí y quien
       * llame no necesita ninguna credencial de R2 — sólo una sesión de
       * administrador—. Es el mismo reparto que en M4, donde el vencimiento de
       * ofertas se dispara con una ruta en vez de con un planificador, porque el
       * proyecto tiene arquitectura dual (nube + servidor local) y cortes
       * eléctricos: no se puede depender de un planificador concreto.
       *
       * ── Por qué es idempotente ────────────────────────────────────────────────
       * Barrer dos veces no hace daño. La primera pasada deja las filas en
       * `DELETED`, así que la segunda ya no las encuentra y devuelve
       * `barridas: 0`. Y si una pasada se corta a la mitad, la siguiente retoma
       * donde quedó: el objeto se borra antes que la fila, así que una fila que
       * no llegó a marcarse sigue siendo `PENDING` y vuelve a salir en la
       * consulta. `DeleteObject` sobre una clave ausente tampoco falla.
       *
       * ── Por qué el orden es objeto-primero ────────────────────────────────────
       * Al revés que en el borrado normal, y por la misma razón simétrica que en
       * el rechazo por tamaño: si fallara R2, la fila sigue `PENDING` y la
       * próxima pasada la vuelve a encontrar. Marcando primero, la fila diría
       * `DELETED` y el objeto seguiría ocupando sitio sin que nadie lo supiera
       * —justo el residuo que el modo `--revisar-borrados` del script va a
       * buscar.
       *
       * ── Qué NO hace ───────────────────────────────────────────────────────────
       * No toca los objetos que ninguna fila referencia (el script los busca con
       * `--huerfanos`). Ahí la fila ya no existe —la borró un `CASCADE` o nunca
       * llegó a insertarse—, así que no hay nada que consultar y el barrido no
       * puede verlos por definición.
       */
      admin.post('/archivos/limpiar', async (request) => {
        const almacen = almacenamiento();
        const entrada = esquemaBarrido.parse(request.body ?? {});

        const horas = validarHorasDeAbandono(
          entrada.horas ?? HORAS_ABANDONO_POR_DEFECTO,
        );
        const limite = entrada.limite ?? LIMITE_BARRIDO_POR_DEFECTO;

        // El corte se calcula **aquí** y no se acepta del cliente. Una marca de
        // tiempo absoluta dejaría al llamante fijar el umbral en el futuro y
        // barrer subidas en vuelo sin que ningún número cantara.
        const corte = new Date(
          Date.now() - horas * 60 * 60 * 1000,
        ).toISOString();

        const candidatas = await reposDe(request).archivos.pendientesAntiguos(
          corte,
          limite,
        );

        let barridas = 0;
        const fallidas: string[] = [];

        for (const archivo of candidatas) {
          try {
            await almacen.eliminar(archivo.r2Key);
            await reposDe(request).archivos.marcarBorrado(archivo.id);
            barridas += 1;
          } catch (error) {
            // Una pasada concurrente que ya marcó esta fila no es un fallo: el
            // estado al que se quería llegar ya está puesto. Contarla como error
            // ensuciaría el resumen de un barrido que salió bien, y el resumen es
            // lo único que mira quien programa la tarea.
            if (error instanceof ErrorApi && error.codigo === 'ESTADO_DE_ARCHIVO') {
              barridas += 1;
              continue;
            }

            // No se aborta el barrido entero por una fila. Se cuenta, se
            // registra y se sigue: las que fallan quedan `PENDING` y la siguiente
            // llamada las vuelve a encontrar, así que el fallo es recuperable
            // —pero no silencioso.
            fallidas.push(archivo.id);
            request.log.error(
              { err: error, archivoId: archivo.id },
              'no se pudo barrer una subida abandonada',
            );
          }
        }

        return {
          revisadas: candidatas.length,
          barridas,
          fallidas: fallidas.length,
          idsFallidas: fallidas,
          mensaje:
            candidatas.length === 0
              ? 'No había subidas abandonadas.'
              : `Se revisaron ${candidatas.length} subida(s) de más de ${horas} h: ` +
                `${barridas} barrida(s)` +
                (fallidas.length === 0
                  ? '.'
                  : ` y ${fallidas.length} con error, que se reintentarán en la próxima pasada.`),
        };
      });
    },
    { prefix: '/api/v1/admin' },
  );

  // --- Firma de subida -------------------------------------------------------

  /**
   * Reserva el archivo y devuelve la URL con la que el cliente lo sube.
   *
   * **Se firma antes de registrar la fila, y no al revés.** La clave canónica la
   * construye el adaptador dentro de `urlDeSubida` —prefijo, UUID y extensión—,
   * y es la única que vale: construirla aparte con `construirClave` generaría
   * **otro** UUID y la fila apuntaría a un objeto que nadie va a subir. De paso,
   * la firma ya devuelve el tipo MIME canónico, así que no hay que derivarlo dos
   * veces ni hay riesgo de que las dos derivaciones discrepen.
   *
   * El `id` viaja en la respuesta porque es **lo único** que permite confirmar
   * después: la ruta de confirmación lo necesita y no hay otra forma de obtenerlo.
   */
  app.post(
    '/api/v1/archivos/firmar-subida',
    { preHandler: [exigirSesion(), exigirArchivos] },
    async (request, reply) => {
      const almacen = almacenamiento();

      const usuario = request.usuario;
      if (!usuario) throw ErrorApi.noAutorizado();

      const entrada = esquemaFirmarSubida.parse(request.body);

      // La extensión se valida antes de tocar la base: es la comprobación más
      // barata y descarta la petición mala sin una sola consulta. El adaptador la
      // vuelve a validar al firmar —y de ahí sale el tipo MIME—, así que esto no
      // es la única barrera, sólo la primera.
      extensionDe(entrada.nombreOriginal);

      // El tope de archivos por entidad sólo aplica cuando hay entidad: una
      // subida suelta, todavía sin tarea ni guía, no consume cupo de nadie.
      if (entrada.entidadId !== null) {
        const maxArchivos = limiteNumerico(
          await deps.caches.parametros.porClave(CLAVE_MAX_ARCHIVOS),
          CLAVE_MAX_ARCHIVOS,
          ARCHIVOS_POR_ENTIDAD_POR_DEFECTO,
        );

        const yaHay = await reposDe(request).archivos.contarPorEntidad(
          entrada.entityType,
          entrada.entidadId,
        );

        if (yaHay >= maxArchivos) {
          throw ErrorApi.conflicto(
            'DEMASIADOS_ARCHIVOS',
            `Esta entidad ya tiene ${yaHay} archivos y el máximo son ${maxArchivos}. ` +
              'Borra alguno antes de subir otro.',
            { yaHay, maxArchivos },
          );
        }
      }

      // El prefijo lo compone el servidor a partir del usuario autenticado, nunca
      // el cliente: es lo que reparte los objetos por propietario.
      const firmada = await almacen.urlDeSubida({
        prefijo: prefijoDeArchivo(usuario.id),
        nombreOriginal: entrada.nombreOriginal,
      });

      const archivo = await reposDe(request).archivos.registrarPendiente({
        propietarioId: usuario.id,
        r2Key: firmada.clave,
        nombreOriginal: entrada.nombreOriginal,
        tipoContenido: firmada.tipoContenido,
        entityType: entrada.entityType,
        entidadId: entrada.entidadId,
      });

      // 201 y no 200: se creó la reserva, y la respuesta trae su identificador.
      return reply.status(201).send({
        archivo,
        urlDeSubida: firmada.url,
        expiraEnSegundos: firmada.expiraEnSegundos,
      });
    },
  );

  // --- Confirmación ----------------------------------------------------------

  /**
   * Comprueba que el objeto llegó y que pesa lo permitido; si sí, lo confirma.
   *
   * Aquí es donde se aplica el límite de tamaño, y **no antes**, por una razón
   * que no depende de este código: una URL `PUT` prefirmada no admite
   * `content-length-range`, así que el servidor no puede imponer el peso en el
   * momento de firmar. El tamaño real sólo se conoce con este `HeadObject`
   * posterior. Por eso el cliente no manda el tamaño y el esquema no lo acepta:
   * pedirle al interesado que se mida no es una comprobación.
   */
  app.post<{ Params: { id: string } }>(
    '/api/v1/archivos/:id/confirmar',
    { preHandler: [exigirSesion(), exigirArchivos] },
    async (request) => {
      const almacen = almacenamiento();
      const { id } = esquemaRutaIdArchivo.parse(request.params);

      const archivo = await reposDe(request).archivos.porId(id);

      if (archivo === null) {
        throw ErrorApi.noEncontrado(
          'ARCHIVO_INEXISTENTE',
          'El archivo no existe o no es tuyo.',
        );
      }

      const estadisticas = await almacen.estadisticas(archivo.r2Key);

      if (estadisticas === null) {
        // La fila existe pero el objeto no: la subida se interrumpió. **No se
        // toca la fila**: se queda `PENDING` para que el barrido de abandonados
        // la encuentre, que es justo para lo que existe ese estado.
        throw ErrorApi.noEncontrado(
          'OBJETO_NO_SUBIDO',
          'El archivo no llegó al almacenamiento. Vuelve a subirlo.',
        );
      }

      const maximo = await maxBytes();

      if (estadisticas.tamanoBytes > maximo) {
        // Objeto primero, fila después — al revés que en el borrado normal, y por
        // la misma razón simétrica: aquí lo que no debe quedar es un objeto que
        // ya se decidió rechazar. Si fallara el borrado en R2, la fila sigue
        // viva y el archivo sigue siendo reclamable; si se marcara primero y
        // fallara R2, quedaría un objeto ocupando sitio que ya nadie conoce.
        await almacen.eliminar(archivo.r2Key);
        await reposDe(request).archivos.marcarBorrado(id);

        // `validarTamano` lanza **siempre** aquí —el `if` de arriba ya comprobó
        // el exceso—, y se usa en vez de construir el error a mano para que el
        // código `413` y su mensaje salgan de un solo sitio.
        validarTamano(estadisticas.tamanoBytes, maximo);
      }

      const confirmado = await reposDe(request).archivos.confirmar(
        id,
        estadisticas.tamanoBytes,
      );

      return { archivo: confirmado };
    },
  );

  // --- Lectura ---------------------------------------------------------------

  /**
   * Los archivos vivos de una tarea o una guía.
   *
   * Es la lectura que le faltaba al módulo (deuda D17). Sin ella el gestor
   * documental podía subir y borrar pero **no recordaba nada**: cada vez que
   * alguien abría el panel lo veía vacío y volvía a subir lo mismo. Un gestor
   * documental que no lista no es un gestor, es un formulario de subida.
   *
   * ── Quién ve qué ────────────────────────────────────────────────────────────
   * Lo decide la **RLS**, no esta ruta: `files_metadata_read_own` deja al
   * propietario ver lo suyo y `files_metadata_admin_read` deja al administrador
   * verlo todo. Aquí no hay ningún filtro por propietario, y es deliberado: sería
   * una segunda copia de una regla que ya vive en la base, y la copia se
   * desviaría en cuanto la política cambiara.
   *
   * **La visibilidad cruzada del docente todavía no es expresable, y conviene
   * que quede escrito.** El requisito pide que un docente vea las entregas de sus
   * alumnos. Hoy no se puede: `files_metadata.entidad_id` es un UUID **sin tabla
   * que lo respalde** —las tareas no existen hasta M6—, así que no hay forma de
   * saber a qué sección pertenece una entrega ni, por tanto, qué docente la
   * dicta. Un filtro aquí no podría calcularlo, y una política RLS tampoco,
   * porque no hay nada que unir. Se resuelve en M6, cuando exista la tabla de
   * tareas y la política pueda decir «las entregas de las tareas de mis
   * secciones». Hasta entonces esta ruta es honesta: devuelve lo que la RLS deja
   * ver, que hoy es lo propio —y todo, si quien pregunta es administrador—.
   *
   * ── Por qué no pagina ───────────────────────────────────────────────────────
   * Porque `m5_max_archivos_por_entidad` (10 por defecto) acota la lista por
   * construcción: la respuesta cabe entera. El día que ese tope suba a un orden
   * de magnitud, esta decisión hay que revisarla —y por eso queda escrita—.
   *
   * Se excluyen los `DELETED` y se incluyen los `PENDING`. Un archivo borrado no
   * es material de nadie; uno sin confirmar sí, y esconderlo sería peor: quien
   * acaba de subir y no llegó a confirmar vería desaparecer su archivo sin
   * explicación. El `estado` viaja en la respuesta para que la pantalla pueda
   * etiquetarlo en vez de mentir sobre él.
   */
  app.get<{ Params: { entityType: string; entidadId: string } }>(
    '/api/v1/archivos/entidad/:entityType/:entidadId',
    { preHandler: [exigirSesion(), exigirArchivos] },
    async (request) => {
      // El listado **exige** que el almacenamiento esté configurado, aunque no
      // firme nada. No es un formalismo: sin R2 cada archivo listado sería un
      // enlace que nadie puede abrir, así que un panel que lista es un panel
      // roto. Se prefiere el 503 que dice la verdad —«el módulo no está
      // disponible»— a un 200 que promete archivos inaccesibles. Además mantiene
      // la invariante de que las siete rutas se comportan igual cuando falta R2.
      almacenamiento();

      const { entityType, entidadId } = esquemaRutaEntidad.parse(request.params);

      const archivos = await reposDe(request).archivos.listarPorEntidad(
        entityType,
        entidadId,
      );

      // `total` repite lo que ya dice la longitud del arreglo, y aun así se
      // manda: la pantalla lo usa para decidir si el tope de la entidad está
      // cerca, y calcularlo allí obligaría al cliente a conocer el parámetro.
      return { archivos, total: archivos.length };
    },
  );

  /**
   * Devuelve una URL de descarga temporal.
   *
   * **404 y no 403 también cuando el archivo es de otro.** La RLS ya lo escondió
   * —el propietario ve lo suyo, el admin lo ve todo—, así que desde aquí no hay
   * forma de distinguir «no existe» de «no es tuyo». Y no debe haberla: un 403
   * confirmaría que el archivo ajeno existe, que es información que no le toca.
   *
   * Sólo se firma lo `CONFIRMED`. Un `PENDING` no tiene objeto verificado que
   * leer, y un `DELETED` ya no debería leerse.
   */
  app.get<{ Params: { id: string } }>(
    '/api/v1/archivos/:id/url-lectura',
    { preHandler: [exigirSesion(), exigirArchivos] },
    async (request) => {
      const almacen = almacenamiento();
      const { id } = esquemaRutaIdArchivo.parse(request.params);

      const archivo = await reposDe(request).archivos.porId(id);

      if (archivo === null) {
        throw ErrorApi.noEncontrado(
          'ARCHIVO_INEXISTENTE',
          'El archivo no existe o no tienes acceso a él.',
        );
      }

      if (archivo.estado !== 'CONFIRMED') {
        throw ErrorApi.conflicto(
          'ARCHIVO_NO_DISPONIBLE',
          'El archivo todavía no está disponible para descargar.',
          { estado: archivo.estado },
        );
      }

      // El nombre original es lo que hace que la descarga se llame «Constancia
      // José.pdf» y no el UUID del objeto: el adaptador lo convierte en la
      // cabecera `Content-Disposition`, con la forma ASCII y la RFC 5987 para no
      // perder los acentos.
      const firmada = await almacen.urlDeDescarga(
        archivo.r2Key,
        archivo.nombreOriginal,
      );

      return {
        urlDeLectura: firmada.url,
        expiraEnSegundos: firmada.expiraEnSegundos,
        nombreOriginal: archivo.nombreOriginal,
      };
    },
  );

  // --- Borrado por el propietario --------------------------------------------

  app.delete<{ Params: { id: string } }>(
    '/api/v1/archivos/:id',
    { preHandler: [exigirSesion(), exigirArchivos] },
    async (request) => borrar(request),
  );
}
