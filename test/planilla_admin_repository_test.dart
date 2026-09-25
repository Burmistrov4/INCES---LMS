import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/repositories/planilla_admin_repository.dart';

import 'support/catalogo_ejemplo.dart';
import 'support/fake_planilla_admin_gateway.dart';

/// El repositorio del catálogo administrativo: envuelve el gateway en `Result`.
///
/// Lo que defiende no es que los métodos existan —eso lo dice el compilador—
/// sino tres propiedades que se pueden romper sin que nada deje de compilar:
///
///  1. **Un fallo no se disfraza de lista vacía.** Un catálogo vacío y uno que
///     no se pudo leer pintan la misma pantalla —un panel sin campos— y sólo el
///     `Result` los separa. Si el fallo cayera a una lista vacía, quien
///     administra leería «el catálogo está vacío» cuando el problema era la red.
///  2. **`alternarActivo` manda una sola columna.** Si mandara el campo entero,
///     apagar un interruptor reescribiría `etiqueta` y `orden` con lo que
///     hubiera en pantalla, y una edición ajena en vuelo se perdería en
///     silencio.
///  3. **`actualizar` no manda `null`.** `null` es «no toques esta columna» y la
///     cadena vacía es «bórrala». Colapsarlos convertiría borrar la ayuda en no
///     hacer nada —el fallo clásico que un `ayuda ?? base.ayuda` esconde—.
void main() {
  group('PlanillaAdminRepository.obtenerCatalogo', () {
    test('devuelve el catálogo del gateway, incluidos los apagados', () async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.obtenerCatalogo();

      final catalogo = resultado.when(
        success: (v) => v,
        failure: (_) => const CatalogoInscripcion([]),
      );
      expect(catalogo.campos, hasLength(8));
      // El apagado viaja: es la razón de que este gateway sea distinto del
      // público, que filtra `activo = true`. Si el repositorio lo filtrara,
      // apagar un campo lo haría desaparecer y no habría forma de reencenderlo.
      expect(catalogo.porCodigo('talla_camisa')?.activo, isFalse);
      expect(gateway.llamadas, contains('catalogoCompleto'));
    });

    test('un fallo del gateway es Failure, no un catálogo vacío', () async {
      final gateway = FakePlanillaAdminGateway()
        ..campos = catalogoAdminEjemplo()
        ..errorAlLeer = const AppException.servidor();
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.obtenerCatalogo();

      expect(resultado.isFailure, isTrue);
      // Y el valor no existe: no hay una lista vacía esperando a que alguien la
      // confunda con «no hay campos».
      expect(resultado.valueOrNull, isNull);
    });

    test('conserva el código del error, para poder distinguir 503 de 404',
        () async {
      final gateway = FakePlanillaAdminGateway()
        ..errorAlLeer = const AppException(
          type: AppErrorType.servidor,
          message: 'El servicio no está disponible.',
          code: 'SERVICIO_NO_DISPONIBLE',
        );
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.obtenerCatalogo();

      expect(resultado.errorOrNull?.code, 'SERVICIO_NO_DISPONIBLE');
    });
  });

  group('PlanillaAdminRepository.crear', () {
    test('delega el campo y devuelve lo guardado', () async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.crear(
        campoCatalogo(
          'talla_zapato',
          etiqueta: 'Talla de zapato',
          orden: 210,
        ),
      );

      final creado = resultado.when(success: (v) => v, failure: (_) => null);
      expect(creado?.codigo, 'talla_zapato');
      // Llegó el campo entero, no una copia a medias: `crear` es la única
      // operación que fija `codigo` y `tipo`, así que tienen que viajar.
      expect(gateway.ultimoCreado?.etiqueta, 'Talla de zapato');
      expect(gateway.ultimoCreado?.orden, 210);
      expect(gateway.ultimoCreado?.tipo, TipoCampoInscripcion.texto);
    });

    test('un código repetido llega como Failure con su 23505', () async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();
      final repo = PlanillaAdminRepository(gateway: gateway);

      // `primer_nombre` ya está en el catálogo. El doble lanza el `23505` como
      // lo haría el `unique` de la tabla.
      final resultado = await repo.crear(
        campoCatalogo('primer_nombre', etiqueta: 'Repetido'),
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.code, '23505');
      expect(resultado.errorOrNull?.type, AppErrorType.duplicado);
    });
  });

  group('PlanillaAdminRepository.actualizar', () {
    test('manda sólo las columnas que se le pasan', () async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();
      final repo = PlanillaAdminRepository(gateway: gateway);

      await repo.actualizar(
        codigo: 'primer_nombre',
        etiqueta: 'Nombres de pila',
      );

      // Una sola clave. El resto son `null`, y `null` es «no toques esta
      // columna»: si el repositorio rellenara las ausentes, cada edición de la
      // etiqueta reescribiría `grupo`, `orden` y `activo` con lo que hubiera en
      // pantalla.
      expect(gateway.cambiosActualizados, {'etiqueta': 'Nombres de pila'});
      expect(gateway.codigoActualizado, 'primer_nombre');
    });

    test('la cadena vacía viaja, para poder borrar la ayuda', () async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();
      final repo = PlanillaAdminRepository(gateway: gateway);

      await repo.actualizar(codigo: 'talla_camisa', ayuda: '');

      // `''` y no `null`: `null` es «no toques la columna» y dejaría la ayuda
      // intacta. La clave tiene que estar presente con la cadena vacía.
      expect(gateway.cambiosActualizados, {'ayuda': ''});
    });

    test('un rechazo de la RLS llega como Failure con su 42501', () async {
      final gateway = FakePlanillaAdminGateway()
        ..campos = catalogoAdminEjemplo()
        ..errorAlActualizar = const AppException(
          type: AppErrorType.permisos,
          message: 'Sólo un administrador puede modificar el catálogo.',
          code: '42501',
        );
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.actualizar(
        codigo: 'primer_nombre',
        activo: false,
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull?.code, '42501');
      // Y no es recuperable: reintentar sin cambiar de sesión daría el mismo
      // rechazo, así que la interfaz no debe ofrecer «inténtalo otra vez».
      expect(resultado.errorOrNull?.esRecuperable, isFalse);
    });
  });

  group('PlanillaAdminRepository.alternarActivo', () {
    test('es un update de una sola columna', () async {
      final gateway = FakePlanillaAdminGateway()..campos = catalogoAdminEjemplo();
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.alternarActivo(
        codigo: 'talla_camisa',
        activo: true,
      );

      // Una columna y sólo una. Es el gesto más frecuente del panel, y mandar
      // el campo entero haría que encenderlo reescribiera su etiqueta y su
      // orden con lo que el panel tuviera pintado.
      expect(gateway.cambiosActualizados, {'activo': true});
      expect(gateway.codigoActualizado, 'talla_camisa');
      expect(resultado.valueOrNull?.activo, isTrue);
    });

    test('el rechazo no se convierte en éxito', () async {
      final gateway = FakePlanillaAdminGateway()
        ..campos = catalogoAdminEjemplo()
        ..errorAlActualizar = const AppException.duplicado(
          'Ese registro ya existe en el sistema.',
          code: '23505',
        );
      final repo = PlanillaAdminRepository(gateway: gateway);

      final resultado = await repo.alternarActivo(
        codigo: 'talla_camisa',
        activo: true,
      );

      expect(resultado.isFailure, isTrue);
    });
  });

  group('PlanillaAdminRepository.intercambiarOrden', () {
    test('delega los dos campos y no devuelve valor', () async {
      final campos = catalogoAdminEjemplo();
      final gateway = FakePlanillaAdminGateway()..campos = campos;
      final repo = PlanillaAdminRepository(gateway: gateway);

      final actual = campos.firstWhere((c) => c.codigo == 'segundo_nombre');
      final vecino = campos.firstWhere((c) => c.codigo == 'primer_nombre');

      final resultado = await repo.intercambiarOrden(
        actual: actual,
        vecino: vecino,
      );

      expect(resultado.isSuccess, isTrue);
      // Llegan los DOS campos: el intercambio es simétrico y mandar sólo uno
      // dejaría al otro con su orden viejo, que es lo que hace que el resultado
      // dependa de qué se mandó y no de lo que hay.
      expect(gateway.ultimoIntercambio?.$1.codigo, 'segundo_nombre');
      expect(gateway.ultimoIntercambio?.$2.codigo, 'primer_nombre');
    });

    test('un fallo es Failure y no un intercambio silencioso', () async {
      final gateway = FakePlanillaAdminGateway()
        ..campos = catalogoAdminEjemplo()
        ..errorAlIntercambiar = const AppException(
          type: AppErrorType.servidor,
          message: 'No pudimos reordenar el catálogo.',
        );
      final repo = PlanillaAdminRepository(gateway: gateway);

      final campos = catalogoAdminEjemplo();
      final resultado = await repo.intercambiarOrden(
        actual: campos.first,
        vecino: campos.last,
      );

      expect(resultado.isFailure, isTrue);
    });
  });
}
