import '../core/gateways/aula_gateway.dart';
import '../core/network/api_client.dart';
import '../models/cuadrante.dart';
import 'supabase_service.dart';

/// Implementación de [AulaGateway] contra el backend Fastify.
///
/// Cubre el listado de aulas y el contenido del aula, que son las seis
/// operaciones que la UI usa hoy:
///
/// | Método | Ruta |
/// |---|---|
/// | [misAulas] | `GET /api/v1/mi-horario` (heredada de [AulasPropiasGateway]) |
/// | [tablon] | `GET /api/v1/aula/secciones/:seccionId/tablon` |
/// | [trabajoDeClase] | `GET /api/v1/aula/secciones/:seccionId/trabajo` |
/// | [misEntregas] | `GET /api/v1/aula/mis-entregas` |
/// | [entregar] | `POST /api/v1/aula/entregas/:entregaId/entregar` |
/// | [reclamar] | `POST /api/v1/aula/entregas/:entregaId/reclamar` |
///
/// **La forma de las respuestas no está adivinada.** Sale de los mapeadores
/// `a*` de `backend/src/infra/repos-supabase.ts`: ninguna ruta declara un
/// esquema Zod de respuesta, así que Fastify serializa el objeto del mapeador
/// tal cual, y las diez rutas emiten **camelCase**. El detalle de dónde sale
/// cada clave está en la cabecera de `lib/core/gateways/aula_gateway.dart`.
///
/// **La autorización la hace la base, no este cliente** (ADR-003). Las cinco
/// rutas de M6 llevan `exigirSesion()` y la guardia del módulo `m6_aula_virtual`;
/// quién ve qué lo decide la RLS. Por eso el token de sesión viaja en **cada**
/// petición: es lo que deja al servidor resolver el rol y a `auth.uid()` decidir
/// de quién es la entrega.
///
/// Las implementaciones del puerto **lanzan** [AppException]; envolverlas en
/// `Result` es cosa del consumidor (hoy las pantallas, vía `Result.guard`).
class BackendAulaGateway implements AulaGateway {
  /// [tokenSesion] es un parámetro y no una llamada directa a `SupabaseService`
  /// por la misma razón que en M5: `SupabaseService.instance.auth` llega hasta
  /// `Supabase.instance`, que **lanza** si Supabase no está inicializado, y
  /// leerlo dentro haría que el gateway no se pudiera construir en una prueba.
  BackendAulaGateway({ApiClient? api, String? Function()? tokenSesion})
      : _api = api ?? ApiClient(),
        _tokenSesion = tokenSesion ?? _tokenDeSupabase;

  final ApiClient _api;

  /// De dónde sale el JWT de la sesión actual.
  final String? Function() _tokenSesion;

  /// El token de la sesión de Supabase. Es lo que se inyecta en producción.
  static String? _tokenDeSupabase() =>
      SupabaseService.instance.auth.currentSession?.accessToken;

  /// El prefijo común de las rutas de contenido.
  ///
  /// Va en una constante y no repetido en cada método para que el día que el
  /// prefijo cambie haya un solo sitio que tocar. La ruta del horario **no**
  /// cuelga de aquí: es de M3 y vive en su propia constante.
  static const String _rutaAula = '/api/v1/aula';

  /// La ruta del horario propio.
  ///
  /// Es la **misma** que usa `BackendCuadranteGateway`: no son dos rutas, son
  /// dos lecturas de la misma respuesta. El listado de aulas necesita la
  /// sección, la materia y el programa; el panel de horario necesita además el
  /// día y el bloque. Compartir la ruta evita que las dos se desvíen.
  static const String _rutaMiHorario = '/api/v1/mi-horario';

  // --- Listado de aulas -----------------------------------------------------

  @override
  Future<MisAulas> misAulas({String? periodo}) async {
    final respuesta = await _api.get(
      _rutaMiHorario,
      token: _tokenSesion(),
      // Un período en blanco se omite: `ApiClient` descarta los parámetros
      // vacíos, así que `null` y `''` acaban en la misma URL limpia y el
      // backend no recibe un `periodo=` que rechazaría.
      parametros: {'periodo': ?_limpiar(periodo)},
    );

    return _reducir(MiHorario.fromJson(respuesta));
  }

  // --- Contenido del aula ---------------------------------------------------

  @override
  Future<List<Anuncio>> tablon(String seccionId) async {
    final respuesta = await _api.get(
      '$_rutaAula/secciones/$seccionId/tablon',
      token: _tokenSesion(),
    );

    // El servidor envuelve la lista en `{ anuncios: [...] }`, no la devuelve
    // desnuda: es el sobre de todas las rutas de lectura de M6 y por eso se
    // desempaqueta aquí y no en la pantalla.
    return _listaDe(respuesta, 'anuncios', Anuncio.fromJson);
  }

  @override
  Future<List<TareaDeClase>> trabajoDeClase(String seccionId) async {
    final respuesta = await _api.get(
      '$_rutaAula/secciones/$seccionId/trabajo',
      token: _tokenSesion(),
    );

    return _listaDe(respuesta, 'tareas', TareaDeClase.fromJson);
  }

  @override
  Future<List<Entrega>> misEntregas() async {
    // Sin parámetro de usuario a propósito: el «yo» lo pone `auth.uid()` en el
    // servidor. Mandarlo desde aquí sería una segunda fuente de verdad sobre
    // quién es el llamante.
    final respuesta = await _api.get(
      '$_rutaAula/mis-entregas',
      token: _tokenSesion(),
    );

    return _listaDe(respuesta, 'entregas', Entrega.fromJson);
  }

  @override
  Future<Entrega> entregar(String entregaId) =>
      _accionDeEntrega(entregaId, 'entregar');

  @override
  Future<Entrega> reclamar(String entregaId) =>
      _accionDeEntrega(entregaId, 'reclamar');

  /// Las dos acciones que devuelven la entrega mutada.
  ///
  /// `entregar` y `reclamar` comparten forma de respuesta **a propósito**: las
  /// dos RPC devuelven `id, tarea_id, estado, es_tardia, nota_asignada,
  /// entregada_en`, y el mapeador `aEntrega` las reduce igual. Escribir dos
  /// métodos casi idénticos invitaría a que uno se desviara del otro cuando sólo
  /// cambia el verbo.
  ///
  /// POST **sin cuerpo**: el id va en la ruta. `ApiClient` omite
  /// `Content-Type` cuando no hay cuerpo, que es justo lo que evita el
  /// `FST_ERR_CTP_EMPTY_JSON_BODY` de Fastify.
  ///
  /// Un 400 aquí es del dominio y trae su mensaje: la tarea cerró y no admite
  /// tardías (§4.4), o la entrega no está en un estado desde el que se pueda
  /// reclamar. No se reinterpreta: se deja subir tal cual.
  Future<Entrega> _accionDeEntrega(String entregaId, String accion) async {
    final respuesta = await _api.post(
      '$_rutaAula/entregas/$entregaId/$accion',
      token: _tokenSesion(),
    );

    return Entrega.fromJson(respuesta['entrega'] as Map<String, dynamic>);
  }

  /// Reduce el horario del llamante a un aula por sección.
  ///
  /// **Una sección, una fila.** `clases` trae una fila por franja del cuadrante,
  /// así que la misma sección aparece tantas veces como días y bloques tenga: en
  /// un listado de aulas eso serían tarjetas repetidas. Se deduplica por
  /// `seccionId` conservando la **primera** aparición, que es la que fija la
  /// etiqueta.
  ///
  /// **Las guardias no son aulas.** Una guardia es una presencia de custodia, no
  /// una clase con tablón ni trabajo de clase: se ignora aunque venga en el
  /// payload. Para un estudiante ya viene vacía, así que esto sólo cambia el
  /// caso del docente.
  ///
  /// El rol sale del payload y no de una bandera del llamante: quien sabe qué es
  /// el usuario es el servidor, y una bandera del cliente sería una segunda
  /// fuente de verdad sobre permisos (ADR-003).
  static MisAulas _reducir(MiHorario horario) {
    final vistas = <String>{};
    final aulas = <AulaResumen>[];

    for (final clase in horario.clases) {
      // `add` devuelve `false` si la sección ya estaba: una sola pasada hace de
      // deduplicación y de recorrido.
      if (!vistas.add(clase.seccionId)) continue;

      aulas.add(
        AulaResumen(
          seccionId: clase.seccionId,
          materia: clase.materia,
          seccion: clase.seccion,
          // Vacío y nulo significan lo mismo aquí: la vista no resolvió el
          // programa. Se normaliza a `null` para que la etiqueta no deje un
          // separador colgando.
          programa: clase.programa.trim().isEmpty ? null : clase.programa,
        ),
      );
    }

    return MisAulas(
      esDocente: horario.rol == 'docente',
      periodo: horario.periodo,
      aulas: aulas,
    );
  }

  /// Desempaqueta la lista que el servidor deja bajo [clave] y la parsea.
  ///
  /// Los tres lectores de M6 comparten sobre (`{ anuncios }`, `{ tareas }`,
  /// `{ entregas }`), así que el desempaquetado va aquí una vez en lugar de tres.
  ///
  /// Una clave ausente o `null` se lee como **lista vacía**, no como error: el
  /// libro de calificaciones devuelve `200 { entregas: [] }` a quien no dicta la
  /// sección, y una lista vacía no es un fallo —es «no hay nada que ver»—. Tratar
  /// ese caso como error obligaría a la UI a distinguir dos vacíos que para ella
  /// son el mismo.
  static List<T> _listaDe<T>(
    Map<String, dynamic> respuesta,
    String clave,
    T Function(Map<String, dynamic>) parsear,
  ) {
    final crudo = respuesta[clave] as List?;
    if (crudo == null) return <T>[];

    return crudo.cast<Map<String, dynamic>>().map(parsear).toList();
  }

  /// Un texto de consulta en blanco equivale a no filtrar.
  static String? _limpiar(String? texto) {
    final limpio = texto?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }
}

/// Resuelve la puerta de **contenido** del aula que un dashboard entrega a
/// `PanelMisAulas`.
///
/// ## La trampa que evita (leer antes de «simplificar»)
///
/// Lo natural sería escribir `widget.aulaGateway ?? BackendAulaGateway()` en el
/// dashboard. **No sirve**, y el porqué no se ve leyendo el `??`:
///
/// Las pruebas de widget inyectan a veces **sólo** el gateway del listado
/// (`aulasPropias`) y dejan `aulaGateway` en `null` **a propósito**, justo para
/// comprobar que sin puerta de contenido la tarjeta del aula **no** se puede
/// pulsar. Con el `??` ingenuo esas pruebas recibirían un gateway real, la
/// tarjeta pasaría a ser pulsable y el toque saldría a la red: el arreglo
/// abriría por la puerta de atrás el caso que la prueba existe para proteger.
///
/// Por eso la condición no es «`aulaGateway` es `null`» sino **«no se inyectó
/// nada»**: sólo entonces estamos en producción y el aula debe abrirse con el
/// servicio real. Si el llamante inyectó cualquiera de las dos puertas, manda
/// él — y si inyectó la del listado sin la del contenido, lo que pide es un
/// listado **sin** aula abrible, y eso es lo que recibe.
///
/// Vive aquí, y no copiada en cada dashboard, porque es una regla sutil que dos
/// copias acabarían desviando.
AulaGateway? resolverPuertaDeContenido({
  required AulaGateway? inyectada,
  required AulasPropiasGateway? listadoInyectado,
}) {
  if (inyectada != null) return inyectada;

  // Listado inyectado y contenido no: quien llama quiere controlar el listado y
  // no ha pedido puerta de contenido. Devolver una real rompería su prueba.
  if (listadoInyectado != null) return null;

  // Ni una ni otra: producción.
  return BackendAulaGateway();
}
