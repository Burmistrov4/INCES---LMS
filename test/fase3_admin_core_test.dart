import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/models/config_audit_entry.dart';
import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/models/system_setting.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';

import 'support/fake_gateway.dart';

SystemModule _modulo(
  String clave, {
  String? nombre,
  bool habilitado = false,
  int orden = 0,
  String categoria = 'general',
  List<String> roles = const [],
}) =>
    SystemModule(
      clave: clave,
      nombre: nombre ?? clave,
      habilitado: habilitado,
      orden: orden,
      categoria: categoria,
      rolesPermitidos: roles,
    );

void main() {
  // ---------------------------------------------------------------------------
  group('SystemModule', () {
    test('una lista de roles vacía significa "todos los roles"', () {
      final modulo = _modulo('m1', roles: const []);

      expect(modulo.permiteRol('estudiante'), isTrue);
      expect(modulo.permiteRol('docente'), isTrue);
      expect(modulo.permiteRol('admin'), isTrue);
    });

    test('con roles definidos, sólo esos roles pasan', () {
      final modulo = _modulo('m1', roles: const ['admin', 'docente']);

      expect(modulo.permiteRol('admin'), isTrue);
      expect(modulo.permiteRol('docente'), isTrue);
      expect(modulo.permiteRol('estudiante'), isFalse);
    });

    test('fromJson tolera valores ausentes sin romper', () {
      final modulo = SystemModule.fromJson({'clave': 'x'});

      expect(modulo.clave, 'x');
      expect(modulo.nombre, '');
      expect(modulo.habilitado, isFalse);
      expect(modulo.rolesPermitidos, isEmpty);
      expect(modulo.categoria, 'general');
    });

    test('fromJson lee roles_permitidos como lista de texto', () {
      final modulo = SystemModule.fromJson({
        'clave': 'm1',
        'nombre': 'Módulo 1',
        'habilitado': true,
        'orden': 3,
        'roles_permitidos': ['admin'],
        'categoria': 'nucleo',
      });

      expect(modulo.habilitado, isTrue);
      expect(modulo.orden, 3);
      expect(modulo.rolesPermitidos, ['admin']);
    });
  });

  // ---------------------------------------------------------------------------
  group('SystemSetting', () {
    test('convierte valores numéricos y de texto a entero', () {
      expect(const SystemSetting(clave: 'a', valor: 3).comoEntero, 3);
      expect(const SystemSetting(clave: 'a', valor: '7').comoEntero, 7);
      expect(const SystemSetting(clave: 'a', valor: 'x').comoEntero, isNull);
    });

    test('convierte booleanos de forma tolerante', () {
      expect(const SystemSetting(clave: 'a', valor: true).comoBooleano, isTrue);
      expect(
        const SystemSetting(clave: 'a', valor: 'false').comoBooleano,
        isFalse,
      );
      expect(
        const SystemSetting(clave: 'a', valor: 'otra cosa').comoBooleano,
        isNull,
      );
    });

    test('comoTexto nunca revienta con valor nulo', () {
      expect(const SystemSetting(clave: 'a', valor: null).comoTexto, '');
    });
  });

  // ---------------------------------------------------------------------------
  group('ConfigAuditEntry', () {
    test('resume un cambio de módulo como activo/inactivo', () {
      const entrada = ConfigAuditEntry(
        id: '1',
        tabla: 'system_modules',
        clave: 'm4_inscripciones',
        valorAnterior: {'habilitado': false},
        valorNuevo: {'habilitado': true},
      );

      expect(entrada.descripcionCorta, 'm4_inscripciones: inactivo → activo');
    });

    test('resume un cambio de valor simple', () {
      const entrada = ConfigAuditEntry(
        id: '2',
        tabla: 'system_settings',
        clave: 'max_faltas',
        valorAnterior: 3,
        valorNuevo: 5,
      );

      expect(entrada.descripcionCorta, 'max_faltas: 3 → 5');
    });

    test('trunca valores largos', () {
      final entrada = ConfigAuditEntry(
        id: '3',
        tabla: 'system_settings',
        clave: 'descripcion',
        valorAnterior: 'a' * 100,
        valorNuevo: 'b',
      );

      expect(entrada.descripcionCorta, contains('...'));
    });
  });

  // ---------------------------------------------------------------------------
  group('ModuloRepository · alternar módulos', () {
    test('enciende un módulo y lo devuelve actualizado', () async {
      final fake = FakeGateway()
        ..listaModulos = [_modulo('m4_inscripciones', habilitado: false)];
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.alternarModulo(
        clave: 'm4_inscripciones',
        habilitado: true,
      );

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull!.habilitado, isTrue);
      expect(fake.llamadas, contains('actualizarModulo:m4_inscripciones'));
    });

    test('apaga un módulo', () async {
      final fake = FakeGateway()
        ..listaModulos = [_modulo('m6_asistencia', habilitado: true)];
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.alternarModulo(
        clave: 'm6_asistencia',
        habilitado: false,
      );

      expect(resultado.valueOrNull!.habilitado, isFalse);
    });

    test('un fallo al alternar se expone, no se silencia', () async {
      final fake = FakeGateway()
        ..errorAlActualizarModulo = const AppException(
          type: AppErrorType.permisos,
          message: 'No tienes permisos para realizar esta acción.',
        );
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.alternarModulo(
        clave: 'm4_inscripciones',
        habilitado: true,
      );

      expect(resultado.isFailure, isTrue);
      expect(resultado.errorOrNull!.type, AppErrorType.permisos);
    });

    test('cambiar roles permitidos de un módulo', () async {
      final fake = FakeGateway()..listaModulos = [_modulo('m7_notas')];
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.cambiarRolesPermitidos(
        clave: 'm7_notas',
        roles: const ['admin', 'docente'],
      );

      expect(resultado.valueOrNull!.rolesPermitidos, ['admin', 'docente']);
    });
  });

  // ---------------------------------------------------------------------------
  group('ModuloRepository · settings', () {
    test('actualiza un parámetro y devuelve el nuevo valor', () async {
      final fake = FakeGateway()
        ..listaSettings = [
          const SystemSetting(
            clave: 'max_faltas_consecutivas',
            valor: 3,
            tipo: 'number',
          ),
        ];
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.actualizarSetting(
        clave: 'max_faltas_consecutivas',
        valor: 5,
      );

      expect(resultado.valueOrNull!.comoEntero, 5);
    });

    test('un fallo al guardar settings se expone', () async {
      final fake = FakeGateway()
        ..errorAlActualizarSetting = Exception('sin conexión');
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.actualizarSetting(
        clave: 'periodo_activo',
        valor: '2026-2',
      );

      expect(resultado.isFailure, isTrue);
    });

    test('la lista de settings vacía es Success, no Failure', () async {
      final fake = FakeGateway()..listaSettings = const [];
      final repo = ModuloRepository(gateway: fake);

      final resultado = await repo.obtenerSettings();

      expect(resultado.isSuccess, isTrue);
      expect(resultado.valueOrNull, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('ModuloRepository · agrupación para el cPanel', () {
    test('respeta el orden de categorías conocido', () {
      final agrupado = ModuloRepository.agruparPorCategoria([
        _modulo('a', categoria: 'evaluacion', orden: 1),
        _modulo('b', categoria: 'nucleo', orden: 2),
        _modulo('c', categoria: 'academico', orden: 3),
      ]);

      expect(agrupado.keys.toList(), ['nucleo', 'academico', 'evaluacion']);
    });

    test('una categoría desconocida NO desaparece: va al final', () {
      final agrupado = ModuloRepository.agruparPorCategoria([
        _modulo('a', categoria: 'nucleo'),
        _modulo('b', categoria: 'categoria_nueva'),
      ]);

      expect(agrupado.keys.toList(), ['nucleo', 'categoria_nueva']);
      expect(agrupado['categoria_nueva']!.single.clave, 'b');
    });

    test('dentro de una categoría ordena por `orden` y luego por nombre', () {
      final agrupado = ModuloRepository.agruparPorCategoria([
        _modulo('z', nombre: 'Zeta', categoria: 'nucleo', orden: 2),
        _modulo('b', nombre: 'Beta', categoria: 'nucleo', orden: 1),
        _modulo('a', nombre: 'Alfa', categoria: 'nucleo', orden: 1),
      ]);

      final claves = agrupado['nucleo']!.map((m) => m.clave).toList();
      expect(claves, ['a', 'b', 'z']);
    });

    test('etiquetaCategoria traduce a texto legible', () {
      expect(ModuloRepository.etiquetaCategoria('nucleo'), 'Núcleo');
      expect(ModuloRepository.etiquetaCategoria('academico'), 'Académico');
      expect(ModuloRepository.etiquetaCategoria('desconocida'), 'General');
    });
  });
}
