import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorApi } from '../../dominio/errores.js';
import { revisarCambioDeRol } from '../../dominio/reglas-admin.js';
import type { DependenciasRutas } from '../dependencias.js';
import {
  esquemaCambioRol,
  esquemaCambiosModulo,
  esquemaIdPerfil,
  esquemaListadoAuditoria,
  esquemaValorParametro,
  validarValorSegunTipo,
} from '../esquemas.js';
import { exigirAdmin, reposDe } from '../plugins/autenticacion.js';

/**
 * Envuelve el esquema del identificador para el `params` de Fastify.
 *
 * Fastify tipa `params` como un objeto, y el esquema se declara sobre el valor
 * suelto. Este envoltorio mantiene el esquema reutilizable y legible, en vez de
 * duplicar el `.uuid()` aquí dentro.
 */
const esquemaRutaIdPerfil = z.object({ id: esquemaIdPerfil });

/**
 * Módulo del propio cPanel.
 *
 * Se nombra como constante porque aparece en tres sitios: la guardia del
 * endpoint, el cortacircuitos de la base de datos y los tests. Un literal
 * repetido es una errata esperando a ocurrir.
 */
const MODULO_CPANEL = 'm0_cpanel';

/**
 * Rutas del Administrador Maestro.
 *
 * Todas exigen rol `admin`, comprobado en la API **y** en las políticas RLS de
 * Postgres (los repositorios viajan con el token del llamante). Ninguna de las
 * dos barreras se apoya en la otra.
 *
 * Toda mutación invalida la caché correspondiente: el administrador espera que
 * apagar un módulo surta efecto al instante, no dentro de 30 segundos.
 */
export function rutasAdmin(app: FastifyInstance, deps: DependenciasRutas): void {
  app.register(
    async (admin) => {
      admin.addHook('preHandler', exigirAdmin());

      // --- Módulos -----------------------------------------------------------

      admin.get('/modulos', async (request) => ({
        modulos: await reposDe(request).modulos.todos(),
      }));

      admin.patch<{ Params: { clave: string } }>(
        '/modulos/:clave',
        async (request) => {
          const { clave } = request.params;
          const cambios = esquemaCambiosModulo.parse(request.body);

          // Cortacircuitos en la API, espejo del que existe en la base de datos.
          // El trigger daría un 400 genérico de CHECK; aquí el mensaje explica
          // exactamente qué pasaría, que es lo que el administrador necesita leer.
          if (clave === MODULO_CPANEL && cambios.habilitado === false) {
            throw ErrorApi.conflicto(
              'MODULO_CRITICO',
              'El módulo del cPanel no puede deshabilitarse: perderías el acceso al sistema.',
              { modulo: clave },
            );
          }

          const modulo = await reposDe(request).modulos.actualizar(clave, cambios);

          deps.caches.modulos.invalidar();

          return { modulo };
        },
      );

      // --- Parámetros --------------------------------------------------------

      admin.get('/parametros', async (request) => ({
        parametros: await reposDe(request).parametros.todos(true),
      }));

      admin.patch<{ Params: { clave: string } }>(
        '/parametros/:clave',
        async (request) => {
          const { clave } = request.params;
          const { valor } = esquemaValorParametro.parse(request.body);

          const actual = await reposDe(request).parametros.porClave(clave);
          if (!actual) {
            throw ErrorApi.noEncontrado(
              'PARAMETRO_DESCONOCIDO',
              `El parámetro "${clave}" no existe.`,
            );
          }

          // El tipo declarado es un contrato: si no se respeta, el fallo aparece
          // mucho después y lejos de aquí.
          validarValorSegunTipo(actual.tipo, valor, clave);

          const parametro = await reposDe(request).parametros.actualizar(clave, valor);

          deps.caches.parametros.invalidar();

          return { parametro };
        },
      );

      // --- Auditoría ---------------------------------------------------------

      admin.get('/auditoria', async (request) => {
        const { limite } = esquemaListadoAuditoria.parse(request.query);
        return { entradas: await reposDe(request).auditoria.listar(limite) };
      });

      // --- Usuarios ----------------------------------------------------------

      admin.patch<{ Params: { id: string } }>(
        '/usuarios/:id/rol',
        async (request) => {
          // Se valida ANTES de tocar la base. Sin esto, un `id` que no sea UUID
          // llegaba a Postgres, reventaba con `22P02` y salía como 500 genérico:
          // un error del cliente disfrazado de fallo del servidor.
          const { id } = esquemaRutaIdPerfil.parse(request.params);
          const { rol } = esquemaCambioRol.parse(request.body);

          const usuario = request.usuario;
          if (!usuario) throw ErrorApi.noAutorizado();

          const perfiles = reposDe(request).perfiles;

          // Las dos consultas se hacen siempre, aunque una promoción no las
          // necesite: `porId` además da un `PERFIL_INEXISTENTE` limpio en vez de
          // un fallo de PostgREST sin contexto, y una acción de administrador no
          // es un camino caliente. La decisión, en cambio, vive en una función
          // pura y se prueba sin montar nada.
          const objetivo = await perfiles.porId(id);
          const adminsActivos = await perfiles.contarAdminsActivos();

          revisarCambioDeRol({
            actorId: usuario.id,
            objetivoId: id,
            nuevoRol: rol,
            objetivo,
            adminsActivos,
          });

          return { perfil: await perfiles.cambiarRol(id, rol) };
        },
      );
    },
    { prefix: '/api/v1/admin' },
  );
}
