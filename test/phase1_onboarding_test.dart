import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/result.dart';
import 'package:inces_lms_app/models/aspirante_model.dart';
import 'package:inces_lms_app/models/registro_resultado.dart';
import 'package:inces_lms_app/screens/registro_exitoso_screen.dart';
import 'package:inces_lms_app/services/auth_service.dart';

/// Aspirante válido y mayor de edad, base para los casos de prueba.
AspiranteModel _aspiranteAdulto() => AspiranteModel(
      nombres: 'Ana',
      apellidos: 'Pérez',
      cedula: '12345678',
      fechaNacimiento: DateTime(DateTime.now().year - 20, 1, 15),
      sexo: 'F',
      telefono: '04141234567',
      email: 'ana.perez@example.com',
      direccion: 'Calle Principal, casa 1',
      nivelEducativo: 'Secundario',
      programId: 'uuid-herreria',
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoyMDAwMDAwMDAwfQ.test',
    );
  });

  // ---------------------------------------------------------------------------
  group('AspiranteModel · serialización', () {
    test('toMetadata NO envía el rol (evita auto-promoción a admin)', () {
      final metadata = _aspiranteAdulto().toMetadata();

      expect(
        metadata.containsKey('rol'),
        isFalse,
        reason: 'El rol lo fija el trigger de PostgreSQL, nunca el cliente.',
      );
      // Tampoco debe poder colarse por otra clave.
      expect(metadata.values.where((v) => v == 'admin'), isEmpty);
    });

    test('la fecha de nacimiento viaja como YYYY-MM-DD, sin hora', () {
      final aspirante = AspiranteModel(
        nombres: 'Luis',
        apellidos: 'Gómez',
        cedula: '87654321',
        fechaNacimiento: DateTime(2005, 3, 7, 23, 45),
        sexo: 'M',
        telefono: '04240000000',
        email: 'luis@example.com',
        direccion: 'Av. Bolívar',
        nivelEducativo: 'Técnico',
        programId: 'uuid-oratoria',
      );

      expect(aspirante.toMetadata()['fecha_nac'], '2005-03-07');
      expect(aspirante.toJson()['fecha_nac'], '2005-03-07');
    });

    test('D14 · `toJson` manda `program_id` y ya no `curso_seleccionado`', () {
      // La columna `curso_seleccionado` se eliminó con la migración de D14, así
      // que mandarla en una escritura directa sobre `aspirantes` daba `42703`
      // —y `PGRST204` si PostgREST la filtraba por su caché de esquema—. Es la
      // mitad de D14 que se rompe en silencio: el error no aparece hasta que
      // alguien guarda una ficha.
      final json = _aspiranteAdulto().toJson();

      expect(json.containsKey('curso_seleccionado'), isFalse);
      expect(json['program_id'], 'uuid-herreria');
    });

    test('D14 · sin programa, `toJson` omite `program_id` en vez de mandarlo vacío', () {
      // Condicional y no incondicional: `''` no es un uuid válido y Postgres lo
      // rechazaría con `22P02`. Si la clave falta, la guardia de escritura lo
      // deriva de `datos_planilla`, que es justo para lo que existe.
      final sinPrograma = AspiranteModel(
        nombres: 'Ana',
        apellidos: 'Pérez',
        cedula: '12345678',
        fechaNacimiento: DateTime(DateTime.now().year - 20, 1, 15),
        sexo: 'F',
        telefono: '04141234567',
        email: 'ana.perez@example.com',
        direccion: 'Calle Principal, casa 1',
        nivelEducativo: 'Secundario',
      );

      expect(sinPrograma.toJson().containsKey('program_id'), isFalse);
    });

    test('D14 · la metadata conserva la clave `curso_seleccionado`', () {
      // La clave NO se renombró, y es deliberado: es la que lee
      // `handle_new_user()` y la que el catálogo usa como código del campo. Lo
      // que cambió es el VALOR, que antes era el nombre del curso y ahora es su
      // uuid. Renombrar la clave obligaría a migrar el catálogo para no ganar
      // nada.
      expect(_aspiranteAdulto().toMetadata()['curso_seleccionado'], 'uuid-herreria');
    });

    test('omite los datos del tutor cuando el aspirante es mayor de edad', () {
      final metadata = _aspiranteAdulto().toMetadata();

      expect(metadata.containsKey('nombre_tutor'), isFalse);
      expect(metadata.containsKey('telefono_tutor'), isFalse);
    });

    test('marca requiresLegalTutor para un menor de edad', () {
      final menor = AspiranteModel(
        nombres: 'Niño',
        apellidos: 'Ejemplo',
        cedula: '11111111',
        fechaNacimiento: DateTime(DateTime.now().year - 16, 1, 1),
        sexo: 'M',
        telefono: '04120000000',
        email: 'menor@example.com',
        direccion: 'Calle 2',
        nivelEducativo: 'Secundario',
        programId: 'uuid-oratoria',
      );

      expect(menor.esMenorDeEdad, isTrue);
      expect(menor.requiresLegalTutor, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('AspiranteModel · la planilla completa', () {
    /// Una planilla con la forma que produce el catálogo: el nombre desglosado y
    /// la rejilla de misiones, que son las dos cosas que no tienen columna.
    Map<String, dynamic> planillaDeEjemplo() => {
          'primer_nombre': 'Lorenzo',
          'segundo_nombre': 'José',
          'primer_apellido': 'Roca',
          'misiones': {'RIBAS': '2019'},
        };

    test('`datos_planilla` viaja en la metadata y en el JSON de escritura', () {
      final aspirante = _aspiranteAdulto();
      final conPlanilla = AspiranteModel(
        nombres: aspirante.nombres,
        apellidos: aspirante.apellidos,
        cedula: aspirante.cedula,
        fechaNacimiento: aspirante.fechaNacimiento,
        sexo: aspirante.sexo,
        telefono: aspirante.telefono,
        email: aspirante.email,
        direccion: aspirante.direccion,
        nivelEducativo: aspirante.nivelEducativo,
        programId: aspirante.programId,
        datosPlanilla: planillaDeEjemplo(),
      );

      expect(conPlanilla.toMetadata()['datos_planilla'], isA<Map<String, dynamic>>());
      expect(conPlanilla.toJson()['datos_planilla'], isA<Map<String, dynamic>>());
      // Es la clave que hace que el trigger llame a `validar_planilla()`: sin
      // ella el trigger no valida, que es la asimetría deliberada que permitió
      // desplegar la migración sin romper al formulario viejo.
      expect(
        (conPlanilla.toMetadata()['datos_planilla'] as Map)['primer_nombre'],
        'Lorenzo',
      );
    });

    test('sin planilla, la clave no se manda', () {
      // Ausente y no nula: mandar `datos_planilla: null` haría que el trigger
      // encontrara la clave y validara contra un `null`.
      final metadata = _aspiranteAdulto().toMetadata();

      expect(metadata.containsKey('datos_planilla'), isFalse);
    });

    test('`fromJson` lee `datos_planilla` si viene como mapa', () {
      final leido = AspiranteModel.fromJson({
        'nombres': 'Lorenzo',
        'apellidos': 'Roca',
        'cedula': '20123456',
        'datos_planilla': planillaDeEjemplo(),
      });

      expect(leido.datosPlanilla, isNotNull);
      expect(leido.datosPlanilla!['segundo_nombre'], 'José');
    });

    test('una `datos_planilla` con otra forma se descarta en vez de reventar', () {
      // La planilla es un dato accesorio de la ficha: no poder leerla no debe
      // impedir mostrar al aspirante.
      final leido = AspiranteModel.fromJson({
        'nombres': 'Lorenzo',
        'apellidos': 'Roca',
        'cedula': '20123456',
        'datos_planilla': 'esto no es un mapa',
      });

      expect(leido.datosPlanilla, isNull);
      expect(leido.nombres, 'Lorenzo');
    });

    test('`toMetadata` NO manda `mision_ribaras`, aunque el modelo lo tenga', () {
      // El modelo conserva el campo para **leer** la columna y para las
      // escrituras de administración, pero el formulario nuevo manda la rejilla
      // `misiones` dentro de `datos_planilla`. Mandar los dos sería guardar lo
      // mismo dos veces con dos formas distintas.
      final aspirante = AspiranteModel(
        nombres: 'Lorenzo',
        apellidos: 'Roca',
        cedula: '20123456',
        fechaNacimiento: DateTime(DateTime.now().year - 20, 1, 1),
        sexo: 'M',
        telefono: '04141234567',
        email: 'lorenzo@example.com',
        direccion: 'Valencia',
        nivelEducativo: 'Secundario',
        programId: 'uuid-herreria',
        misionRibaras: 'Ribas',
      );

      expect(aspirante.toMetadata().containsKey('mision_ribaras'), isFalse);
      // Pero sí se conserva para escribir la columna directamente.
      expect(aspirante.toJson()['mision_ribaras'], 'Ribas');
    });
  });

  // ---------------------------------------------------------------------------
  group('AspiranteModel · mayoría de edad', () {
    // La regla tiene que ser la misma que el CHECK de la base
    // (`fecha_nac > current_date - interval '18 years'`), porque la pantalla la
    // usa para decidir si pide los datos del representante legal **antes** de
    // enviar. Dos copias de una regla de edad se desvían en el borde exacto de
    // los 18 años, que es justo donde importa.
    final hoy = DateTime.now();

    test('sin fecha no se presume menor', () {
      // Un formulario a medio rellenar no puede quedar marcado como menor: eso
      // exigiría un representante legal que quizá no haga falta.
      expect(AspiranteModel.esMenorDeEdadCon(null), isFalse);
    });

    test('el día que cumple 18 ya no es menor', () {
      expect(
        AspiranteModel.esMenorDeEdadCon(DateTime(hoy.year - 18, hoy.month, hoy.day)),
        isFalse,
      );
    });

    test('un día antes de cumplir 18 sí lo es', () {
      // El borde por el otro lado. Se construye con el día +1 y se deja que
      // `DateTime` normalice el desborde de mes: escribir `hoy.day + 1` a mano
      // reventaría el último día de cada mes, que es cuando menos se prueba.
      expect(
        AspiranteModel.esMenorDeEdadCon(
          DateTime(hoy.year - 18, hoy.month, hoy.day + 1),
        ),
        isTrue,
      );
    });

    test('17 años es menor y 19 no', () {
      expect(
        AspiranteModel.esMenorDeEdadCon(DateTime(hoy.year - 17, 1, 1)),
        isTrue,
      );
      expect(
        AspiranteModel.esMenorDeEdadCon(DateTime(hoy.year - 19, 1, 1)),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('AppException · traducción de errores', () {
    test('cédula duplicada (23505) se traduce a error de duplicado', () {
      final error = AppException.from(
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint "aspirantes_cedula_key"',
          code: '23505',
        ),
      );

      expect(error.type, AppErrorType.duplicado);
      expect(error.message.toLowerCase(), contains('cédula'));
      expect(error.code, '23505');
    });

    test('correo duplicado (23505) se distingue de la cédula', () {
      final error = AppException.from(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint "email_key"',
          code: '23505',
        ),
      );

      expect(error.type, AppErrorType.duplicado);
      expect(error.message.toLowerCase(), contains('correo'));
    });

    test('check_violation (23514) se traduce a error de validación', () {
      final error = AppException.from(
        const PostgrestException(
          message: 'new row violates check constraint',
          code: '23514',
        ),
      );

      expect(error.type, AppErrorType.validacion);
    });

    test('permiso denegado por RLS (42501) se traduce a permisos', () {
      final error = AppException.from(
        const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
      );

      expect(error.type, AppErrorType.permisos);
      expect(error.esRecuperable, isFalse);
    });

    test('credenciales inválidas se traducen correctamente', () {
      final error = AppException.from(
        const AuthException('Invalid login credentials'),
      );

      expect(error.type, AppErrorType.credenciales);
    });

    test('correo sin confirmar se detecta', () {
      final error = AppException.from(
        const AuthException('Email not confirmed'),
      );

      expect(error.type, AppErrorType.correoNoConfirmado);
    });

    test(
      'el rechazo del trigger ("Database error saving new user") da un '
      'mensaje accionable en lugar del genérico de Supabase',
      () {
        final error = AppException.from(
          const AuthException('Database error saving new user'),
        );

        expect(error.type, AppErrorType.validacion);
        expect(error.message, contains('cédula'));
        // El detalle técnico se conserva para depurar, pero no se muestra.
        expect(error.technical, 'Database error saving new user');
      },
    );

    test('un fallo de red se clasifica como red', () {
      final error = AppException.from(Exception('Failed to fetch'));

      expect(error.type, AppErrorType.red);
      expect(error.esRecuperable, isTrue);
    });

    test('un error desconocido no se disfraza de éxito', () {
      final error = AppException.from(StateError('algo raro'));

      expect(error.type, AppErrorType.desconocido);
      expect(error.message, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('Result', () {
    test('when despacha al caso exitoso', () {
      const resultado = Success<int>(42);

      final texto = resultado.when(
        success: (valor) => 'ok:$valor',
        failure: (error) => 'error',
      );

      expect(texto, 'ok:42');
    });

    test('when despacha al caso de error', () {
      const resultado = Failure<int>(
        AppException.validacion('dato inválido'),
      );

      final texto = resultado.when(
        success: (valor) => 'ok',
        failure: (error) => 'error:${error.message}',
      );

      expect(texto, 'error:dato inválido');
    });

    test('guard convierte una excepción en Failure, no en null', () async {
      final resultado = await Result.guard<int>(
        () async => throw StateError('boom'),
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.valueOrNull, isNull);
      expect(resultado.errorOrNull, isNotNull);
    });

    test('guard conserva el valor en el caso exitoso', () async {
      final resultado = await Result.guard<int>(() async => 7);

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull, 7);
      expect(resultado.errorOrNull, isNull);
    });

    test('map transforma sólo el éxito', () {
      const exito = Success<int>(2);
      const fallo = Failure<int>(AppException.desconocido());

      expect(exito.map((v) => v * 10).valueOrNull, 20);
      expect(fallo.map((v) => v * 10).errorOrNull, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('AuthService · validación local antes de tocar la red', () {
    // Estos casos deben fallar SIN llamadas de red: la validación ocurre antes
    // del signUp. Si algún día se reordena el flujo, estos tests lo detectan.

    test('rechaza una contraseña de menos de 8 caracteres', () async {
      final resultado = await AuthService().registrarAspirante(
        aspirante: _aspiranteAdulto(),
        password: '123',
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull!.type, AppErrorType.validacion);
      expect(resultado.errorOrNull!.message, contains('8 caracteres'));
    });

    test('rechaza una planilla incompleta indicando los campos que faltan',
        () async {
      final incompleto = AspiranteModel(
        nombres: '',
        apellidos: 'Pérez',
        cedula: '',
        fechaNacimiento: DateTime(DateTime.now().year - 20, 1, 1),
        sexo: 'F',
        telefono: '',
        email: 'correo-invalido',
        direccion: '',
        nivelEducativo: 'Secundario',
        programId: '',
      );

      final resultado = await AuthService().registrarAspirante(
        aspirante: incompleto,
        password: 'contrasena-valida',
      );

      expect(resultado.isFailure, isTrue);
      final mensaje = resultado.errorOrNull!.message;
      expect(mensaje, contains('nombres'));
      expect(mensaje, contains('cédula'));
      expect(mensaje, contains('correo electrónico'));
      expect(mensaje, contains('propuesta formativa'));
    });

    test('un menor de edad sin representante legal es rechazado', () async {
      final menorSinTutor = AspiranteModel(
        nombres: 'Niño',
        apellidos: 'Ejemplo',
        cedula: '11111111',
        fechaNacimiento: DateTime(DateTime.now().year - 16, 1, 1),
        sexo: 'M',
        telefono: '04120000000',
        email: 'menor@example.com',
        direccion: 'Calle 2',
        nivelEducativo: 'Secundario',
        programId: 'uuid-oratoria',
      );

      final resultado = await AuthService().registrarAspirante(
        aspirante: menorSinTutor,
        password: 'contrasena-valida',
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull!.message, contains('menor de edad'));
      expect(
        resultado.errorOrNull!.message,
        contains('representante'),
      );
    });

    test('un menor de edad con representante completo pasa la validación',
        () async {
      final menorConTutor = AspiranteModel(
        nombres: 'Niño',
        apellidos: 'Ejemplo',
        cedula: '11111111',
        fechaNacimiento: DateTime(DateTime.now().year - 16, 1, 1),
        sexo: 'M',
        telefono: '04120000000',
        email: 'menor@example.com',
        direccion: 'Calle 2',
        nivelEducativo: 'Secundario',
        programId: 'uuid-oratoria',
        numeroIdentidadTutor: '99999999',
        nombreTutor: 'Madre Ejemplo',
        parentescoTutor: 'Madre',
        telefonoTutor: '04140000000',
        correoTutor: 'madre@example.com',
      );

      // No puede llegar a red en el entorno de test, así que el fallo esperado
      // NO debe ser de validación local.
      final resultado = await AuthService().registrarAspirante(
        aspirante: menorConTutor,
        password: 'contrasena-valida',
      );

      expect(
        resultado.errorOrNull?.type,
        isNot(AppErrorType.validacion),
        reason: 'La planilla es válida; el fallo debe venir de la capa de red.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('RegistroResultado', () {
    test('sin sesión implica que hay que confirmar el correo', () {
      const resultado = RegistroResultado(
        email: 'a@b.com',
        sesionIniciada: false,
        fichaCreada: true,
        requiereTutorLegal: false,
      );

      expect(resultado.requiereConfirmacionEmail, isTrue);
    });

    test('con sesión iniciada no hace falta confirmar', () {
      const resultado = RegistroResultado(
        email: 'a@b.com',
        sesionIniciada: true,
        fichaCreada: true,
        requiereTutorLegal: false,
      );

      expect(resultado.requiereConfirmacionEmail, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('RegistroExitosoScreen', () {
    testWidgets('con sesión iniciada invita a entrar al panel', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegistroExitosoScreen(
            email: 'ana@example.com',
            requiereTutorLegal: false,
            sesionIniciada: true,
            requiereConfirmacionEmail: false,
          ),
        ),
      );

      expect(find.text('Inscripción completada'), findsOneWidget);
      expect(find.text('Ir a mi panel'), findsOneWidget);
      expect(find.text('Ir al inicio de sesión'), findsNothing);
      expect(
        find.text('Tu cuenta ya está activa y con sesión iniciada.'),
        findsOneWidget,
      );
    });

    testWidgets('sin sesión pide confirmar el correo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegistroExitosoScreen(
            email: 'ana@example.com',
            requiereTutorLegal: false,
          ),
        ),
      );

      expect(find.text('Inscripción registrada'), findsOneWidget);
      expect(find.text('Ir al inicio de sesión'), findsOneWidget);
      expect(
        find.text(
          'Confirma tu correo electrónico para activar la cuenta.',
        ),
        findsOneWidget,
      );
    });
  });
}
