import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorApi } from '../../dominio/errores.js';
import {
  esquemaActualizarPrograma,
  esquemaCrearMateria,
  esquemaCrearPrograma,
  esquemaIdPrograma,
  esquemaListadoMaterias,
  esquemaListadoProgramas,
  esquemaReemplazarPensum,
} from '../esquemas.js';
import { exigirAdmin, reposDe } from '../plugins/autenticacion.js';

/**
 * Rutas del Módulo 2 — Currículo y Pensum.
 *
 * Todas exigen rol `admin`, comprobado en la API **y** en las políticas RLS de
 * Postgres (los repositorios viajan con el token del llamante). Ninguna de las
 * dos barreras se apoya en la otra.
 *
 * **Ninguna ruta borra.** Archivar es `isActive: false`. Un `DELETE` sobre un
 * programa se llevaría por delante el histórico, y
 * `program_subjects.subject_id` está en `on delete restrict` precisamente para
 * que borrar una materia en uso no sea posible ni por accidente.
 *
 * Las dos escrituras que necesitan atomicidad —crear el programa con su pensum
 * y reemplazar el pensum— van por las funciones `crear_programa_con_pensum` y
 * `reemplazar_pensum`. Aquí no se ve: el manejador pide la intención al puerto
 * y el repositorio decide cómo cumplirla. Ver `docs/CONTRATO_API_MODULO2.md`.
 */

/**
 * Envuelve el esquema del identificador para el `params` de Fastify.
 *
 * Mismo motivo que `esquemaRutaIdPerfil` en `admin.ts`: Fastify tipa `params`
 * como un objeto y el esquema se declara sobre el valor suelto. El envoltorio
 * mantiene el esquema reutilizable en vez de duplicar el `.uuid()` aquí.
 */
const esquemaRutaIdPrograma = z.object({ id: esquemaIdPrograma });

/**
 * Código del error de programa inexistente.
 *
 * Se nombra porque aparece en dos rutas: el `PATCH` de metadatos y el de
 * pensum. Un literal repetido es una errata esperando a ocurrir.
 */
const PROGRAMA_INEXISTENTE = 'PROGRAMA_INEXISTENTE';

/**
 * Registra las rutas de currículo.
 *
 * No recibe dependencias: este módulo no usa cachés, ni correo, ni la URL del
 * frontend. Se declara sin parámetro en vez de aceptar uno vacío, para que se
 * vea de un vistazo que no necesita nada inyectado.
 */
export function rutasCurriculo(app: FastifyInstance): void {
  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());

      // --- Programas --------------------------------------------------------

      admin.get('/programas', async (request) => {
        const { tipo, activo, busqueda, limite, desplazamiento } =
          esquemaListadoProgramas.parse(request.query);

        const { programas, total } = await reposDe(request).curriculo.listarProgramas({
          tipo,
          activo,
          busqueda,
          limite,
          desplazamiento,
        });

        // El eco de la paginación se devuelve junto a las filas, igual que en
        // /usuarios y /acceso: la pantalla pinta «1 a 25 de 12» con él, sin
        // tener que conservar su propia copia de lo que pidió.
        return { programas, total, limite, desplazamiento };
      });

      admin.get<{ Params: { id: string } }>('/programas/:id', async (request) => {
        // Se valida ANTES de tocar la base. Sin esto, un `id` que no sea UUID
        // llegaba a Postgres, reventaba con `22P02` y salía como 500 genérico:
        // un error del cliente disfrazado de fallo del servidor.
        const { id } = esquemaRutaIdPrograma.parse(request.params);

        const detalle = await reposDe(request).curriculo.detallePrograma(id);
        if (!detalle) {
          throw ErrorApi.noEncontrado(
            PROGRAMA_INEXISTENTE,
            'Ese programa no existe.',
          );
        }

        // El detalle ya trae `seccionesActivas` y `editable`, que es lo que la
        // UI necesita para deshabilitar el reordenamiento antes de que el
        // usuario lo intente, en vez de dejarlo chocar contra el 409.
        return detalle;
      });

      admin.post('/programas', async (request, reply) => {
        const entrada = esquemaCrearPrograma.parse(request.body);

        const detalle = await reposDe(request).curriculo.crearPrograma(entrada);

        // 201 y no 200: se creó un recurso y la respuesta trae su identificador.
        return reply.status(201).send(detalle);
      });

      admin.patch<{ Params: { id: string } }>('/programas/:id', async (request) => {
        const { id } = esquemaRutaIdPrograma.parse(request.params);
        const cambios = esquemaActualizarPrograma.parse(request.body);

        // No se comprueba la existencia antes: si el `id` no existe, el
        // `update` no toca ninguna fila y PostgREST responde `PGRST116`, que el
        // traductor convierte en un 404 limpio. Comprobar antes costaría tres
        // consultas —el detalle lee pensum y secciones— para adelantar un error
        // que la propia escritura ya sabe dar.
        //
        // Publicar (`activo: true`) sobre un programa sin materias es un 400
        // RESTRICCION_VIOLADA desde el constraint trigger diferido: es el caso
        // real que el trigger existe para atrapar.
        const programa = await reposDe(request).curriculo.actualizarPrograma(id, cambios);

        return { programa };
      });

      admin.patch<{ Params: { id: string } }>(
        '/programas/:id/pensum',
        async (request) => {
          const { id } = esquemaRutaIdPrograma.parse(request.params);
          const { pensum } = esquemaReemplazarPensum.parse(request.body);

          // Aquí SÍ se comprueba la existencia antes, y no por simetría: sin
          // esta comprobación, un `program_id` inexistente haría que la función
          // insertara el pensum contra un programa que no existe, y el error
          // sería un `23503` traducido a REFERENCIA_INVALIDA —«se hace
          // referencia a un registro que no existe»— apuntando al sitio
          // equivocado. El administrador leería que una materia es inválida
          // cuando el que no existe es el programa.
          const detalle = await reposDe(request).curriculo.detallePrograma(id);
          if (!detalle) {
            throw ErrorApi.noEncontrado(PROGRAMA_INEXISTENTE, 'Ese programa no existe.');
          }

          // Si la Regla 2 bloquea, el repositorio traduce el `23514` del
          // trigger a un 409 PENSUM_EN_USO. La operación se rechaza entera: la
          // función se deshace y el pensum queda como estaba.
          return reposDe(request).curriculo.reemplazarPensum(id, pensum);
        },
      );

      // --- Banco de materias ------------------------------------------------

      admin.get('/materias', async (request) => {
        const { busqueda, limite, desplazamiento } = esquemaListadoMaterias.parse(
          request.query,
        );

        const { materias, total } = await reposDe(request).curriculo.listarMaterias({
          busqueda,
          limite,
          desplazamiento,
        });

        return { materias, total, limite, desplazamiento };
      });

      admin.post('/materias', async (request, reply) => {
        const entrada = esquemaCrearMateria.parse(request.body);

        // Un código repetido da 409 REGISTRO_DUPLICADO (el `unique` de la
        // tabla, traducido). Es el caso frecuente: la materia ya estaba en el
        // banco. La UI debe ofrecer seleccionar la existente, no sólo un error.
        const materia = await reposDe(request).curriculo.crearMateria(entrada);

        return reply.status(201).send({ materia });
      });
    },
    { prefix: '/api/v1/admin' },
  );
}
