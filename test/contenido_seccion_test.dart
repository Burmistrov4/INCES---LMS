import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/gateways/auditoria_acceso_gateway.dart';
import 'package:inces_lms_app/core/gateways/invitacion_gateway.dart';
import 'package:inces_lms_app/models/entrada_acceso.dart';
import 'package:inces_lms_app/models/invitacion_docente.dart';
import 'package:inces_lms_app/models/system_module.dart';
import 'package:inces_lms_app/models/system_setting.dart';
import 'package:inces_lms_app/repositories/auditoria_acceso_repository.dart';
import 'package:inces_lms_app/repositories/curriculo_repository.dart';
import 'package:inces_lms_app/repositories/invitacion_repository.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_auditoria_accesos_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_auditoria_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_invitaciones_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_modulos_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_parametros_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_programas_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

import 'support/fake_curriculo_gateway.dart';
import 'support/fake_gateway.dart';

/// Pruebas del contrato de layout de [ContenidoSeccion].
///
/// Existen por un fallo real y silencioso: `ContenidoSeccion` envolvía a su
/// hijo en un `SingleChildScrollView`, así que le daba altura **infinita**.
/// Cualquier panel que repartiera el espacio con `Expanded` —o que usara un
/// `ListView` normal— reventaba con «incoming height constraints are
/// unbounded» al abrirse en la aplicación real.
///
/// Las pruebas de panel no lo veían porque lo montaban en el `body` acotado de
/// un `Scaffold`, que no es como se monta de verdad. La lección está en el
/// segundo grupo: **el layout se prueba montando el panel donde vive**.
void main() {
  /// Rótulo tal y como queda en pantalla.
  ///
  /// `TituloSeccion` pinta `texto.toUpperCase()` (`widgets/comunes.dart`), así
  /// que buscar el título en su forma legible nunca lo encuentra. Pasar por
  /// aquí deja el acoplamiento escrito una sola vez en vez de repartido en
  /// literales en mayúsculas por todo el archivo.
  String rotulo(String texto) => texto.toUpperCase();

  group('ContenidoSeccion · contrato de altura', () {
    Future<Object?> montarHijo(WidgetTester tester, Widget hijo) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: IncesTheme.claro(),
          home: Scaffold(
            body: ContenidoSeccion(
              migas: const ['Inicio', 'Sección'],
              child: hijo,
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.takeException();
    }

    testWidgets('un hijo que reparte el espacio con Expanded cabe',
        (tester) async {
      final error = await montarHijo(
        tester,
        Column(
          children: const [Text('arriba'), Expanded(child: Text('abajo'))],
        ),
      );

      expect(error, isNull);
      expect(find.text('abajo'), findsOneWidget);
    });

    testWidgets('un hijo con un ListView normal cabe', (tester) async {
      final error = await montarHijo(
        tester,
        ListView(children: const [Text('fila')]),
      );

      expect(error, isNull);
      expect(find.text('fila'), findsOneWidget);
    });

    testWidgets('un hijo que crece con su contenido cabe', (tester) async {
      final error = await montarHijo(
        tester,
        Column(children: const [Text('crece')]),
      );

      expect(error, isNull);
    });

    testWidgets('las migas de pan siguen presentes', (tester) async {
      await montarHijo(tester, const Text('contenido'));

      expect(find.text('Sección'), findsOneWidget);
    });
  });

  group('los paneles del cPanel se montan en su sección real', () {
    /// Monta el panel **dentro de `ContenidoSeccion`**, como en el dashboard.
    Future<void> montarEnLaSeccion(WidgetTester tester, Widget panel) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: IncesTheme.claro(),
          home: Scaffold(body: ContenidoSeccion(child: panel)),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('Módulos del Sistema', (tester) async {
      // Con el catálogo vacío el panel cae en su estado vacío y no llega a
      // montar la rejilla de métricas ni las tarjetas, que son justo la parte
      // que reparte el espacio. Un módulo basta para ejercitarla.
      final fake = FakeGateway()
        ..listaModulos = [
          const SystemModule(
            clave: 'm1_curriculo',
            nombre: 'Currículo',
            habilitado: true,
            categoria: 'academico',
          ),
        ];

      await montarEnLaSeccion(
        tester,
        CpanelModulosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Módulos totales'), findsOneWidget);
    });

    testWidgets('Parámetros', (tester) async {
      final fake = FakeGateway()
        ..listaSettings = [
          const SystemSetting(
            clave: 'inscripciones_abiertas',
            valor: true,
            tipo: 'boolean',
            categoria: 'academico',
          ),
        ];

      await montarEnLaSeccion(
        tester,
        CpanelParametrosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('se leen en caliente'), findsOneWidget);
    });

    testWidgets('Auditoría', (tester) async {
      final fake = FakeGateway();
      await montarEnLaSeccion(
        tester,
        CpanelAuditoriaPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Todavía no hay cambios registrados.'), findsOneWidget);
    });

    testWidgets('Auditoría de Accesos', (tester) async {
      await montarEnLaSeccion(
        tester,
        CpanelAuditoriaAccesosPanel(
          repositorio: AuditoriaAccesoRepository(gateway: _AccesoVacio()),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CpanelAuditoriaAccesosPanel), findsOneWidget);

      // El panel arranca con auto-refresco de 30 s; se desmonta el árbol para
      // que su `dispose` cancele el temporizador antes del cierre de la prueba.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Usuarios y Roles (invitaciones)', (tester) async {
      await montarEnLaSeccion(
        tester,
        CpanelInvitacionesPanel(
          repositorio: InvitacionRepository(gateway: _InvitacionSinUso()),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(rotulo('Invitación de docentes')), findsOneWidget);
    });

    testWidgets('Programas Académicos', (tester) async {
      final gateway = FakeCurriculoGateway()..programas = [programaSistemas()];
      await montarEnLaSeccion(
        tester,
        CpanelProgramasPanel(repositorio: CurriculoRepository(gateway: gateway)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(rotulo('Programas académicos')), findsOneWidget);
      expect(find.text('Análisis de Sistemas'), findsOneWidget);
    });

    testWidgets('Programas Académicos sin datos muestra su vacío',
        (tester) async {
      final gateway = FakeCurriculoGateway();
      await montarEnLaSeccion(
        tester,
        CpanelProgramasPanel(repositorio: CurriculoRepository(gateway: gateway)),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('No hay programas que mostrar'), findsOneWidget);
    });
  });
}

/// Doble mínimo de [AuditoriaAccesoGateway]: una traza vacía.
class _AccesoVacio implements AuditoriaAccesoGateway {
  @override
  Future<PaginaAcceso> listarAccesos({
    EstadoAcceso? estado,
    String? email,
    String? userId,
    int limite = 25,
    int desplazamiento = 0,
  }) async =>
      const PaginaAcceso(entradas: [], total: 0);
}

/// Doble de [InvitacionGateway] cuyos métodos no se llegan a usar.
///
/// La prueba es de layout: el panel no llama al gateway hasta que alguien
/// envía una invitación. Lanzar en vez de devolver algo inventado deja claro que
/// si algún día se llamara, la prueba lo diría en vez de fingir que funciona.
class _InvitacionSinUso implements InvitacionGateway {
  @override
  Future<InvitacionDocente> invitarDocente(String email) =>
      throw UnimplementedError('No se usa en una prueba de layout.');

  @override
  Future<ActivacionCuenta> activarCuenta({
    required String token,
    required String password,
  }) =>
      throw UnimplementedError('No se usa en una prueba de layout.');
}
