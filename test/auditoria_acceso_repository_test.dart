import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/errors/app_exception.dart';
import 'package:inces_lms_app/core/gateways/auditoria_acceso_gateway.dart';
import 'package:inces_lms_app/models/entrada_acceso.dart';
import 'package:inces_lms_app/repositories/auditoria_acceso_repository.dart';

/// Doble del gateway: no toca la red ni Supabase, así el test corre en el VM de
/// `flutter test` sin dispositivo ni credenciales.
class _GatewayFalso implements AuditoriaAccesoGateway {
  bool lanzar = false;
  EstadoAcceso? estadoRecibido;
  String? emailRecibido;
  int? limiteRecibido;
  int? desplazamientoRecibido;

  @override
  Future<PaginaAcceso> listarAccesos({
    EstadoAcceso? estado,
    String? email,
    String? userId,
    int limite = 25,
    int desplazamiento = 0,
  }) async {
    if (lanzar) throw const AppException.servidor();
    estadoRecibido = estado;
    emailRecibido = email;
    limiteRecibido = limite;
    desplazamientoRecibido = desplazamiento;
    return const PaginaAcceso(entradas: [], total: 0);
  }
}

void main() {
  group('AuditoriaAccesoRepository', () {
    test('rechaza un tamaño de página fuera de rango', () async {
      final repo = AuditoriaAccesoRepository(gateway: _GatewayFalso());

      final chico = await repo.listarAccesos(limite: 0);
      final grande = await repo.listarAccesos(limite: 101);

      expect(chico.isFailure, isTrue);
      expect(grande.isFailure, isTrue);
      // Y es un error de validación, no un fallo de servidor disfrazado: el
      // mensaje tiene que decir qué se pidió mal.
      expect(chico.errorOrNull?.type, AppErrorType.validacion);
    });

    test('rechaza un desplazamiento negativo', () async {
      final repo = AuditoriaAccesoRepository(gateway: _GatewayFalso());
      final r = await repo.listarAccesos(desplazamiento: -1);
      expect(r.isFailure, isTrue);
      expect(r.errorOrNull?.type, AppErrorType.validacion);
    });

    test('recorta el correo antes de filtrar', () async {
      final g = _GatewayFalso();
      final repo = AuditoriaAccesoRepository(gateway: g);

      await repo.listarAccesos(email: '  docente@inces.gob.ve  ');

      // Sin el recorte el filtro no encontraría nada y el administrador culparía
      // a los datos en vez de al espacio que él mismo escribió.
      expect(g.emailRecibido, 'docente@inces.gob.ve');
    });

    test('un correo en blanco se manda como «sin filtro»', () async {
      final g = _GatewayFalso();
      final repo = AuditoriaAccesoRepository(gateway: g);

      await repo.listarAccesos(email: '   ');

      // Mandarlo tal cual haría que el backend lo rechazara con un 400.
      expect(g.emailRecibido, isNull);
    });

    test('pasa el filtro de estado y la paginación al gateway', () async {
      final g = _GatewayFalso();
      final repo = AuditoriaAccesoRepository(gateway: g);

      await repo.listarAccesos(
        estado: EstadoAcceso.fallo,
        limite: 10,
        desplazamiento: 20,
      );

      expect(g.estadoRecibido, EstadoAcceso.fallo);
      expect(g.limiteRecibido, 10);
      expect(g.desplazamientoRecibido, 20);
    });

    test('propaga el error del gateway como Failure', () async {
      final g = _GatewayFalso()..lanzar = true;
      final repo = AuditoriaAccesoRepository(gateway: g);

      final r = await repo.listarAccesos();

      expect(r.isFailure, isTrue);
    });
  });

  group('EntradaAcceso.fromJson', () {
    test('lee las claves camelCase del contrato del backend', () {
      final e = EntradaAcceso.fromJson({
        'id': 'acc-1',
        'userId': 'u-1',
        'email': 'ana@inces.test',
        'ip': '10.0.0.1',
        'estado': 'FAILED',
        'createdAt': '2026-09-01T08:00:00.000Z',
      });

      expect(e.id, 'acc-1');
      expect(e.userId, 'u-1');
      expect(e.email, 'ana@inces.test');
      expect(e.ip, '10.0.0.1');
      expect(e.estado, EstadoAcceso.fallo);
      expect(e.fueExitoso, isFalse);
      expect(e.creadoEn, isNotNull);
    });

    test('un estado desconocido degrada a éxito en vez de romper el panel', () {
      // Una fila con un valor imprevisto no puede tirar la pantalla entera.
      final e = EntradaAcceso.fromJson({'id': 'x', 'estado': 'RARO'});
      expect(e.estado, EstadoAcceso.exito);
    });

    test('sin correo ni usuario, el actor sigue siendo legible', () {
      final e = EntradaAcceso.fromJson({'id': 'x', 'estado': 'SUCCESS'});
      expect(e.email, isNull);
      // Un ListTile con el título vacío parece un fallo de la interfaz.
      expect(e.actor, 'desconocido');
    });
  });
}
