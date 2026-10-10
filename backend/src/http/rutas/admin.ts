import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorApi } from '../../dominio/errores.js';
import { revisarCambioDeRol } from '../../dominio/reglas-admin.js';
import { estadoDeInvitacion } from '../../dominio/reglas-invitaciones.js';
import type { DependenciasRutas } from '../dependencias.js';
import {
  esquemaCambioRol,
  esquemaCambiosModulo,
  esquemaCorreoInvitacion,
  esquemaIdInvitacion,
  esquemaIdPerfil,
  esquemaListadoAcceso,
  esquemaListadoAuditoria,
  esquemaListadoInvitaciones,
  esquemaListadoUsuarios,
  esquemaValorParametro,
  validarValorSegunTipo,
} from '../esquemas.js';
import { exigirAdmin, reposDe } from '../plugins/autenticacion.js';
import type { PuertaInvitacionesDocente } from '../../dominio/puertos.js';
import {
  generarCodigoRecuperacion,
  generarToken,
  hashearToken,
  normalizarCodigo,
} from '../../infra/tokens.js';

/**
 * Cuerpo del correo de invitación.
 *
 * El enlace es generado por el servidor (token de un solo uso + huella en la base
 * de datos), así que es seguro interpolarlo: no viene del cliente. No se mete
 * nada más del cliente en el HTML.
 */
function htmlInvitacion(enlace: string): string {
  return [
    '<div style="font-family:Inter,Arial,sans-serif;max-width:520px;margin:0 auto">',
    '  <h2>Invitación al LMS del INCES</h2>',
    '  <p>Ha sido invitado a formar parte del sistema como <strong>docente</strong>.</p>',
    '  <p>Active su cuenta en las próximas 48 horas usando el siguiente enlace:</p>',
    `  <p><a href="${enlace}" style="color:#1d4ed8">${enlace}</a></p>`,
    '  <p>Si no esperaba esta invitación, puede ignorar este mensaje.</p>',
    '</div>',
  ].join('\n');
}

/**
 * Envuelve el esquema del identificador para el `params` de Fastify.
 *
 * Fastify tipa `params` como un objeto, y el esquema se declara sobre el valor
 * suelto. Este envoltorio mantiene el esquema reutilizable y legible, en vez de
 * duplicar el `.uuid()` aquí dentro.
 */
const esquemaRutaIdPerfil = z.object({ id: esquemaIdPerfil });

/** Igual que el anterior, para las rutas que llevan el id de una invitación. */
const esquemaRutaIdInvitacion = z.object({ id: esquemaIdInvitacion });

/**
 * Emite una invitación: token nuevo, huella en la base, enlace y correo.
 *
 * Existe porque invitar y **renovar** necesitan exactamente lo mismo, y
 * duplicarlo haría que un cambio en la vigencia (hoy 48 h) se aplicara a una
 * ruta y no a la otra sin que nada avisara. El puerto de invitaciones se pasa
 * explícitamente —y no se usa `deps.reposAdmin`— para que la escritura siga
 * pasando por el cliente **del administrador** y la RLS siga siendo la frontera
 * de autorización (ADR-003), no un detalle que este helper se salte.
 */
async function crearInvitacionConEnlace(
  invitaciones: PuertaInvitacionesDocente,
  deps: DependenciasRutas,
  datos: { email: string; nombres: string; apellidos: string },
) {
  // El token se genera en el servidor; el cliente sólo manda el correo. Se
  // guarda SU HUELLA en la base, nunca el token en claro.
  const token = generarToken();
  const expiraEn = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();

  const invitacion = await invitaciones.crear({
    email: datos.email,
    nombres: datos.nombres,
    apellidos: datos.apellidos,
    tokenHash: hashearToken(token),
    expiresAt: expiraEn,
  });

  // Hash strategy (por defecto en Flutter web): el token viaja en el fragmento,
  // nunca en el path, así el servidor siempre entrega el index.html y la app
  // enruta en cliente. Por eso el enlace lleva `#`.
  const enlace = `${deps.urlFrente}/#/auth/activate?token=${token}`;

  // El correo es la vía de lujo. Sin dominio verificado en Resend el mensaje
  // sólo llega a la cuenta dueña del proyecto, así que el enlace también se
  // devuelve en la respuesta: el administrador puede usarlo o reenviarlo aunque
  // el correo no llegue. **La activación nunca depende del correo.**
  const correo = await deps.enviarCorreo.enviar({
    para: datos.email,
    asunto: 'Invitación al LMS del INCES — Active su cuenta de docente',
    html: htmlInvitacion(enlace),
  });

  return { invitacion, enlace, correoEnviado: correo.entregado };
}

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

      // --- Auditoría de accesos (auth_logs) --------------------------------

      admin.get('/acceso', async (request) => {
        const { estado, email, userId, limite, desplazamiento } =
          esquemaListadoAcceso.parse(request.query);

        const { entradas, total } = await reposDe(request).acceso.listar({
          estado,
          email,
          userId,
          limite,
          desplazamiento,
        });

        // El eco de la paginación se devuelve junto a las filas por la misma
        // razón que en /usuarios: la pantalla pinta «1 a 25 de 340» con él.
        return { entradas, total, limite, desplazamiento };
      });

      // --- Usuarios ----------------------------------------------------------

      admin.get('/usuarios', async (request) => {
        const { rol, activo, busqueda, limite, desplazamiento } =
          esquemaListadoUsuarios.parse(request.query);

        const { usuarios, total } = await reposDe(request).perfiles.listar({
          rol,
          activo,
          busqueda,
          limite,
          desplazamiento,
        });

        // El eco de la paginación se devuelve junto a las filas. El cliente
        // podría deducir `limite` y `desplazamiento` de lo que envió, pero
        // devolverlos evita que la pantalla tenga que conservar su propia copia
        // de lo que pidió para poder pintar «1 a 25 de 340».
        return { usuarios, total, limite, desplazamiento };
      });

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

      // --- Invitaciones de docentes -------------------------------------------

      admin.post('/usuarios/invitaciones', async (request) => {
        const { email, nombres, apellidos } = esquemaCorreoInvitacion.parse(request.body);

        const { invitacion, enlace, correoEnviado } = await crearInvitacionConEnlace(
          reposDe(request).invitaciones,
          deps,
          { email, nombres, apellidos },
        );

        return {
          email: invitacion.email,
          expiraEn: invitacion.expiresAt,
          enlaceActivacion: enlace,
          correoEnviado,
        };
      });

      // --- Ciclo de vida de las invitaciones ---------------------------------

      /**
       * Listado para el panel. Devuelve el estado **ya resuelto por el dominio**:
       * el panel no reimplementa la regla «revocada > usada > caducada > válida»,
       * la recibe calculada, así que no puede pintar algo distinto de lo que el
       * endpoint de activación decide.
       */
      admin.get('/usuarios/invitaciones', async (request) => {
        const { limite } = esquemaListadoInvitaciones.parse(request.query);
        const invitaciones = await reposDe(request).invitaciones.listar({ limite });

        return {
          // Se enumeran los campos a propósito: `tokenHash` **no** sale de aquí.
          // Es una huella SHA-256 de 256 bits de entropía —irreversible en la
          // práctica—, pero el panel no la usa para nada y lo que no se envía no
          // se filtra. La lista es explícita para que añadir una columna al
          // modelo no la publique sin querer.
          invitaciones: invitaciones.map((invitacion) => ({
            id: invitacion.id,
            email: invitacion.email,
            nombres: invitacion.nombres,
            apellidos: invitacion.apellidos,
            isUsed: invitacion.isUsed,
            createdAt: invitacion.createdAt,
            expiresAt: invitacion.expiresAt,
            revokedAt: invitacion.revokedAt,
            estado: estadoDeInvitacion(invitacion),
          })),
        };
      });

      admin.post<{ Params: { id: string } }>(
        '/usuarios/invitaciones/:id/revocar',
        async (request) => {
          const { id } = esquemaRutaIdInvitacion.parse(request.params);
          const usuario = request.usuario;
          if (!usuario) throw ErrorApi.noAutorizado();

          const repos = reposDe(request);
          const invitacion = await repos.invitaciones.porId(id);
          if (!invitacion) {
            throw ErrorApi.noEncontrado('INVITACION_INEXISTENTE', 'Esa invitación no existe.');
          }

          const revocada = await repos.invitaciones.revocar(id, usuario.id);
          if (!revocada) {
            throw ErrorApi.conflicto(
              'INVITACION_YA_REVOCADA',
              'Esa invitación ya estaba anulada.',
            );
          }

          // No se borra: el panel sigue mostrándola como revocada.
          return { id, estado: 'revocada' };
        },
      );

      /**
       * Renueva una invitación: revoca la anterior y emite otra.
       *
       * **Revocar es parte de renovar**, no un efecto secundario: si sólo se
       * creara un token nuevo, el viejo seguiría activando la misma cuenta y
       * habría dos credenciales válidas circulando. Renovar sobre una invitación
       * ya revocada o caducada es legítimo y no da error.
       */
      admin.post<{ Params: { id: string } }>(
        '/usuarios/invitaciones/:id/renovar',
        async (request) => {
          const { id } = esquemaRutaIdInvitacion.parse(request.params);
          const usuario = request.usuario;
          if (!usuario) throw ErrorApi.noAutorizado();

          const repos = reposDe(request);
          const previa = await repos.invitaciones.porId(id);
          if (!previa) {
            throw ErrorApi.noEncontrado('INVITACION_INEXISTENTE', 'Esa invitación no existe.');
          }

          await repos.invitaciones.revocar(id, usuario.id);

          const { invitacion, enlace, correoEnviado } = await crearInvitacionConEnlace(
            repos.invitaciones,
            deps,
            { email: previa.email, nombres: previa.nombres, apellidos: previa.apellidos },
          );

          return {
            email: invitacion.email,
            expiraEn: invitacion.expiresAt,
            enlaceActivacion: enlace,
            correoEnviado,
            // La invitación anterior queda anulada: el panel debe refrescar.
            reemplazaA: id,
          };
        },
      );

      // --- Recuperación interna de contraseña --------------------------------

      /**
       * Emite un código temporal de un solo uso para que el titular fije su
       * contraseña. **El administrador nunca la ve ni la elige.**
       *
       * La verificación de identidad es un procedimiento institucional
       * presencial (el administrador conoce a la persona o comprueba su cédula):
       * el sistema no puede inventarse esa verificación, y por eso no se acepta
       * ningún dato personal como sustituto. Lo que sí garantiza el sistema es
       * que el código sea aleatorio, de un solo uso, de vida corta y revocable.
       *
       * El código se devuelve **una sola vez** en esta respuesta. No se guarda en
       * claro en ninguna parte y no se envía por correo: se entrega por el canal
       * interno que la institución apruebe.
       */
      admin.post<{ Params: { id: string } }>(
        '/usuarios/:id/restablecer',
        async (request) => {
          const { id } = esquemaRutaIdPerfil.parse(request.params);
          const usuario = request.usuario;
          if (!usuario) throw ErrorApi.noAutorizado();

          const repos = reposDe(request);
          const objetivo = await repos.perfiles.porId(id);
          if (!objetivo) {
            throw ErrorApi.noEncontrado('PERFIL_INEXISTENTE', 'Ese usuario no existe.');
          }

          const codigo = generarCodigoRecuperacion();
          // 30 minutos: el código se entrega en mano o por canal interno, así que
          // no necesita la vida larga de la invitación (48 h), que se envía por
          // correo y puede leerse días después.
          const expiraEn = new Date(Date.now() + 30 * 60 * 1000).toISOString();

          // **La escritura va por `reposAdmin` (service_role), no por los repos de
          // la petición.** `password_resets` sólo concede `SELECT` a
          // `authenticated` y no tiene política de escritura: el único camino de
          // entrada es el backend con service_role, por diseño (un admin no debe
          // poder fabricar códigos desde el cliente saltándose el endpoint). La
          // lectura del perfil sí va por RLS, para que la barrera de la base
          // confirme que ese usuario es visible para quien emite. La autorización
          // de la operación la impone `exigirAdmin` en la API.
          const registro = await deps.reposAdmin.recuperacion.emitir({
            userId: id,
            codeHash: hashearToken(normalizarCodigo(codigo)),
            expiresAt: expiraEn,
            createdBy: usuario.id,
          });

          return {
            email: objetivo.email,
            codigo,
            expiraEn: registro.expiresAt,
            // El administrador debe entregarlo por el canal institucional. No se
            // afirma que se haya enviado por correo: no se ha enviado.
            entrega: 'manual',
          };
        },
      );
    },
    { prefix: '/api/v1/admin' },
  );
}
