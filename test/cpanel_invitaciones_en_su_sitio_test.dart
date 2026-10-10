import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/result.dart';
import 'package:inces_lms_app/models/usuario_admin.dart';
import 'package:inces_lms_app/repositories/usuario_admin_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_usuarios_roles_panel.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';

/// Reproduce la incidencia «pulso *Invitar docente* y no pasa nada».
///
/// El botón es un `ExpansionTile` (`cpanel_usuarios_roles_panel.dart`) que
/// despliega `CpanelInvitacionesPanel` **dentro de su `Column`** —altura NO
/// acotada—. La versión con fallo devolvía un `ListView` con `shrinkWrap: false`,
/// que ahí lanza «Vertical viewport was given unbounded height»; en `--release`
/// eso se pinta como un recuadro gris: «no pasa nada».
///
/// El test existente (`contenido_seccion_test.dart`) montaba
/// `CpanelInvitacionesPanel` **directamente** en `ContenidoSeccion` —acotado—,
/// que no es donde vive. Éste lo monta donde vive: dentro del acordeón, que es
/// la lección que el propio `ContenidoSeccion` dejó escrita: «el layout se
/// prueba montando el panel donde vive».
void main() {
  Future<void> montar(
    WidgetTester tester,
    Widget hijo, [
    Size tamano = const Size(1280, 2400),
  ]) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ContenidoSeccion(
            migas: const [
              'Inicio',
              'Administración del sistema',
              'Usuarios y Roles',
            ],
            child: hijo,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'el acordeón «Invitar docente» despliega el formulario sin romper el layout',
    (tester) async {
      await montar(tester, CpanelUsuariosRolesPanel(repo: _RepoUsuariosVacio()));

      final acordeon = find.text('Invitar docente');
      expect(acordeon, findsOneWidget);

      // **Arranca desplegado**: el formulario debe estar visible sin tocar nada.
      // Si esto falla con «Vertical viewport was given unbounded height», es que
      // el panel volvió a enraizarse en un desplazable bajo altura infinita.
      expect(tester.takeException(), isNull);
      expect(find.text('Enviar invitación'), findsOneWidget);

      // Y sigue siendo plegable: pulsar el encabezado lo cierra…
      await tester.ensureVisible(acordeon);
      await tester.pump();
      await tester.tap(acordeon);
      // La expansión dura 200 ms. Se avanza en pasos fijos en vez de
      // `pumpAndSettle`, que colgaría por el `CircularProgressIndicator` del
      // listado de invitaciones (animación infinita).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Enviar invitación'), findsNothing);

      // …y volver a pulsarlo lo despliega otra vez, sin excepción de layout.
      await tester.tap(acordeon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Enviar invitación'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  // TEMPORAL: imprime qué `RenderFlex` desborda a 375 px dentro de esta sección.
  // Se retira en cuanto se conozca el widget culpable.
  testWidgets('DIAGNOSTICO · desborde a 375 px', (tester) async {
    final capturados = <FlutterErrorDetails>[];
    final previo = FlutterError.onError;
    FlutterError.onError = capturados.add;
    addTearDown(() => FlutterError.onError = previo);

    await montar(
      tester,
      CpanelUsuariosRolesPanel(repo: _RepoUsuariosVacio()),
      const Size(375, 2400),
    );

    debugPrint('DIAG>>> capturados=${capturados.length}');
    for (final d in capturados) {
      final e = d.exception;
      debugPrint(
        'DIAG>>> ${e is FlutterError ? e.toStringDeep() : e.toString()}',
      );
    }

    await tester.pumpWidget(const SizedBox());
  });
}

/// Doble de [UsuariosAdminRepository] con un listado vacío.
class _RepoUsuariosVacio extends UsuariosAdminRepository {
  @override
  Future<Result<PaginaUsuarios>> listar({
    String? rol,
    bool? activo,
    String? busqueda,
    int limite = 25,
    int desplazamiento = 0,
  }) async => Success(
    PaginaUsuarios(
      usuarios: const [],
      total: 0,
      limite: limite,
      desplazamiento: desplazamiento,
    ),
  );
}
