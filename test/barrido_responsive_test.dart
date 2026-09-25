import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/core/gateways/invitacion_gateway.dart';
import 'package:inces_lms_app/models/archivo.dart';
import 'package:inces_lms_app/models/cuadrante.dart';
import 'package:inces_lms_app/models/inscripcion_campo.dart';
import 'package:inces_lms_app/models/invitacion_docente.dart';
import 'package:inces_lms_app/models/seccion.dart';
import 'package:inces_lms_app/models/system_setting.dart';
import 'package:inces_lms_app/repositories/archivos_repository.dart';
import 'package:inces_lms_app/repositories/aspirante_repository.dart';
import 'package:inces_lms_app/repositories/cuadrante_repository.dart';
import 'package:inces_lms_app/repositories/inscripcion_repository.dart';
import 'package:inces_lms_app/repositories/invitacion_repository.dart';
import 'package:inces_lms_app/repositories/modulo_repository.dart';
import 'package:inces_lms_app/repositories/planilla_repository.dart';
import 'package:inces_lms_app/repositories/secciones_repository.dart';
import 'package:inces_lms_app/screens/admin/cpanel_aulas_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_guardias_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_invitaciones_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_lapsos_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_parametros_panel.dart';
import 'package:inces_lms_app/screens/admin/cpanel_secciones_panel.dart';
import 'package:inces_lms_app/screens/aspirante_dashboard.dart';
import 'package:inces_lms_app/screens/aspirante_form_screen.dart';
import 'package:inces_lms_app/screens/gestor_documental_panel.dart';
import 'package:inces_lms_app/services/auth_service.dart';
import 'package:inces_lms_app/theme/inces_theme.dart';
import 'package:inces_lms_app/widgets/andamiaje.dart';
import 'package:inces_lms_app/widgets/comunes.dart';

import 'support/catalogo_ejemplo.dart';
import 'support/fake_archivos_gateway.dart';
import 'support/fake_cuadrante_gateway.dart';
import 'support/fake_gateway.dart';
import 'support/fake_inscripcion_gateway.dart';
import 'support/fake_planilla_gateway.dart';
import 'support/fake_secciones_gateway.dart';
import 'support/fake_selector_archivos.dart';
import 'support/formulario_inscripcion.dart';

/// Auditoría empírica del patrón de desborde que este proyecto ya pagó dos veces.
///
/// Un barrido estático (`~/.workbuddy-ai/binaries/node/workspace/barrido-rows.mjs`)
/// señaló 14 `Row` con un `Expanded` y un hermano ancho no flexible. Un barrido
/// **señala sospechosos; no dicta sentencia**. Lo que dicta sentencia es el
/// `RenderFlex overflowed` a 375 px: en `flutter test` esa aserción **lanza**, así
/// que montar el widget a ancho de móvil *es* la auditoría. (En `--release` no
/// avisa, y CanvasKit no expone los widgets al navegador: por eso no vale una
/// captura.)
///
/// Cada panel se monta **dentro de `ContenidoSeccion`**, que es su padre real y
/// quien le entrega el ancho y el scroll. Un `Scaffold` pelado mediría el arnés.
///
/// La ventana es **estrecha y alta a propósito**: 375 px es lo que dispara el
/// desborde, y 2400 px de alto hace que los elementos de las listas lleguen a
/// montarse. Con la ventana por defecto (800×600) las filas de una lista quedan
/// fuera del viewport, no se pintan, y la prueba pasaría sin haber medido nada.
///
/// Los datos se siembran **no vacíos** por el mismo motivo: la `Row` sospechosa
/// vive dentro de la fila de un ítem, así que un estado vacío no la ejercita.
///
/// Un barrido y un recorrido **encuentran cosas distintas**. El desborde de
/// 29 px que localizó la prueba de «recorrido completo» —el desplegable de
/// «Nivel Educativo» del paso 2— no lo señaló ningún barrido, y no podía
/// señalarlo: el `RenderFlex` que desborda **es del propio SDK** (la `Row`
/// interna del `DropdownButton`, `dropdown.dart:1650`), no una `Row` del
/// proyecto. El barrido sólo ve el código de este repo; el recorrido ve lo que
/// el usuario provoca. Por eso están los dos.
void main() {
  /// Ancho de un móvil estrecho: el que dicta sentencia.
  const Size movil = Size(375, 2400);

  /// Monta el panel en su padre real a 375 px y devuelve la excepción, si la hay.
  ///
  /// **Desmonta el árbol antes de devolver**, para cancelar los auto-refrescos.
  /// Consecuencia: después de llamar aquí ya no se puede consultar el árbol con
  /// `find.*` — no queda nada montado. Esta auditoría mide desbordes, no pinta.
  Future<Object?> medir(WidgetTester tester, Widget panel) async {
    tester.view.physicalSize = movil;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: IncesTheme.claro(),
        home: Scaffold(
          body: ContenidoSeccion(
            migas: const ['Inicio', 'Auditoría responsive'],
            child: panel,
          ),
        ),
      ),
    );
    // Sin `pumpAndSettle`: varios paneles muestran un indicador de progreso, que
    // es una animación infinita y haría esperar para siempre.
    await tester.pump();
    await tester.pump();

    final error = tester.takeException();

    // Varios paneles arrancan un auto-refresco. Desmontar el árbol cancela el
    // temporizador en su `dispose`; si no, la prueba falla por un `Timer`
    // pendiente que no tiene nada que ver con el layout que se quiere medir.
    await tester.pumpWidget(const SizedBox());

    return error;
  }

  /// Para widgets que son **pantalla**, no panel.
  ///
  /// Su padre real es la ruta, no `ContenidoSeccion`. Meterlos en una sección les
  /// da un ancho que no tienen en producción, así que se mediría un layout que no
  /// existe — el mismo error que medir un panel en un `Scaffold` pelado, al
  /// revés.
  Future<Object?> medirPantalla(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = movil;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: IncesTheme.claro(), home: pantalla),
    );
    await tester.pump();
    await tester.pump();

    final error = tester.takeException();
    await tester.pumpWidget(const SizedBox());
    return error;
  }

  void sinDesbordes(Object? error, String pantalla) {
    expect(
      error,
      isNull,
      reason: '$pantalla desborda a ${movil.width.toInt()} px de ancho.\n'
          'Excepción capturada: $error',
    );
  }

  group('cPanel · a 375 px, en su padre real', () {
    testWidgets('Invitaciones (campo de correo + «Enviar invitación»)',
        (tester) async {
      final error = await medir(
        tester,
        CpanelInvitacionesPanel(
          repositorio: InvitacionRepository(gateway: _InvitacionSinUso()),
        ),
      );

      sinDesbordes(error, 'CpanelInvitacionesPanel');
    });

    testWidgets('Parámetros (campo + botón «Guardar»)', (tester) async {
      final fake = FakeGateway()
        ..listaSettings = const [
          SystemSetting(
            clave: 'inscripciones_abiertas',
            valor: true,
            tipo: 'boolean',
            categoria: 'academico',
          ),
          // Un valor de texto largo: es el que empuja al botón fuera del ancho.
          SystemSetting(
            clave: 'nombre_del_centro_de_formacion_profesional',
            valor: 'CFS Nacional de Soldadura Rafael Urdaneta',
            tipo: 'string',
            categoria: 'institucional',
          ),
        ];

      final error = await medir(
        tester,
        CpanelParametrosPanel(repositorio: ModuloRepository(gateway: fake)),
      );

      sinDesbordes(error, 'CpanelParametrosPanel');
    });

    testWidgets('Lapsos (fila de lapso)', (tester) async {
      final gateway = FakeCuadranteGateway()
        ..periodos = const [
          Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
          Periodo(
            id: 'p2',
            codigo: '2026-2',
            fechaInicio: '2026-09-21',
            fechaFin: '2027-02-13',
            activo: true,
            vigente: false,
          ),
        ];

      final error = await medir(
        tester,
        CpanelLapsosPanel(repositorio: CuadranteRepository(gateway: gateway)),
      );

      sinDesbordes(error, 'CpanelLapsosPanel');
    });

    testWidgets('Espacios (fila de aula)', (tester) async {
      final gateway = FakeCuadranteGateway()
        ..aulas = const [
          Aula(
            id: 'a1',
            nombre: 'Taller de Soldadura Cabina A',
            capacidad: 12,
            esTaller: true,
            activa: true,
          ),
        ]
        ..totalAulas = 1;

      final error = await medir(
        tester,
        CpanelAulasPanel(repositorio: CuadranteRepository(gateway: gateway)),
      );

      sinDesbordes(error, 'CpanelAulasPanel');
    });

    testWidgets('Guardias (fila de guardia)', (tester) async {
      final gateway = FakeCuadranteGateway()
        ..guardias = const [
          Guardia(
            id: 'g1',
            docenteId: 'd1',
            aulaId: 'a1',
            periodo: '2026-1',
            dia: 1,
            bloque: 1,
            turno: Turno.manana,
            activa: true,
          ),
        ]
        ..totalGuardias = 1;

      final error = await medir(
        tester,
        CpanelGuardiasPanel(repositorio: CuadranteRepository(gateway: gateway)),
      );

      sinDesbordes(error, 'CpanelGuardiasPanel');
    });

    testWidgets('Secciones (fila de sección)', (tester) async {
      final gateway = FakeSeccionesGateway()
        ..paginaDevuelta = PaginaSecciones(
          secciones: [
            seccionEjemplo(nombre: 'SA26-2 — Soldadura por arco eléctrico'),
          ],
          total: 1,
          limite: 50,
          desplazamiento: 0,
        );

      final error = await medir(
        tester,
        CpanelSeccionesPanel(repositorio: SeccionesRepository(gateway: gateway)),
      );

      sinDesbordes(error, 'CpanelSeccionesPanel');
    });

    testWidgets('Gestor documental (tarjeta de archivo)', (tester) async {
      // Con la lista vacía el panel cae en su estado vacío y **no monta la
      // tarjeta**, que es donde vive la `Row` sospechosa: la prueba pasaría sin
      // haber medido nada. Un archivo `CONFIRMED` es el que más hijos pinta
      // (descarga habilitada + borrado), así que es el peor caso.
      final gateway = FakeArchivosGateway()
        ..archivosListados = [
          archivoEjemplo(
            estado: EstadoArchivo.confirmed,
            tamanoBytes: 248_512,
            confirmadoEn: '2026-09-18T12:05:00.000Z',
          ),
        ];

      final error = await medir(
        tester,
        GestorDocumentalPanel(
          entityType: TipoEntidadArchivo.taskSubmission,
          repositorio: ArchivosRepository(gateway: gateway),
          selector: FakeSelectorDeArchivos(),
        ),
      );

      sinDesbordes(error, 'GestorDocumentalPanel');
    });

    testWidgets('Lapsos · el diálogo de alta a 375 px', (tester) async {
      // El candidato `cpanel_lapsos_panel.dart:515` vive dentro del diálogo, así
      // que no se alcanza montando el panel: hay que abrirlo. Medirlo importa
      // porque el diálogo es más estrecho que la pantalla (inset de `Dialog`).
      final gateway = FakeCuadranteGateway()
        ..periodos = const [
          Periodo(id: 'p1', codigo: '2026-1', activo: true, vigente: true),
        ];

      tester.view.physicalSize = movil;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: IncesTheme.claro(),
          home: Scaffold(
            body: ContenidoSeccion(
              migas: const ['Inicio', 'Auditoría responsive'],
              child: CpanelLapsosPanel(
                repositorio: CuadranteRepository(gateway: gateway),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // En una ventana estrecha el botón puede quedar fuera del viewport: sin
      // `ensureVisible` el toque no acierta y la prueba pasaría sin abrir nada,
      // que es la peor forma de aprobar.
      await tester.ensureVisible(find.text('Registrar lapso'));
      await tester.pump();
      await tester.tap(find.text('Registrar lapso'));
      await tester.pump();
      // Sin `pumpAndSettle`: basta con dejar terminar la transición del diálogo.
      await tester.pump(const Duration(seconds: 1));

      // Hay que demostrar que el diálogo se abrió: si el toque hubiera fallado,
      // la prueba mediría el panel de siempre y pasaría sin haber medido el
      // diálogo. Su título repite el rótulo del botón, así que salen dos.
      expect(find.text('Registrar lapso'), findsNWidgets(2));

      final error = tester.takeException();
      await tester.pumpWidget(const SizedBox());

      sinDesbordes(error, 'CpanelLapsosPanel · diálogo de alta');
    });

    testWidgets('Tarjeta de módulo con el botón «Roles»', (tester) async {
      // El hueco `onEditarRoles` es opcional: sin él la `Row` candidata ni
      // siquiera se pinta. Es el mismo caso que el encabezado institucional —
      // una trampa latente que sólo despierta cuando alguien usa el hueco.
      final error = await medir(
        tester,
        TarjetaModulo(
          titulo: 'Gestión de usuarios y roles del sistema',
          descripcion: 'Invita docentes, asigna roles y controla el acceso.',
          estado: EstadoModulo.activo,
          icono: Icons.people_outline,
          rolesEtiquetas: const ['admin', 'docente', 'estudiante'],
          onAlternar: (_) {},
          onEditarRoles: () {},
        ),
      );

      sinDesbordes(error, 'TarjetaModulo');
    });
  });

  group('aspirante · a 375 px, en su padre real', () {
    testWidgets('Catálogo de ofertas', (tester) async {
      final gateway = FakeInscripcionGateway()
        ..ofertasDevueltas = [ocupacionSeccionEjemplo()];

      final error = await medir(
        tester,
        PanelOfertas(repositorio: InscripcionesRepository(gateway: gateway)),
      );

      sinDesbordes(error, 'PanelOfertas');
    });

    testWidgets('Mis inscripciones (fila con dato de ancho fijo)',
        (tester) async {
      final gateway = FakeInscripcionGateway()
        ..misInscripcionesDevueltas = [
          inscripcionDetalladaEjemplo(posicionEnCola: 3),
        ];

      final error = await medir(
        tester,
        PanelMisInscripciones(
          repositorio: InscripcionesRepository(gateway: gateway),
        ),
      );

      sinDesbordes(error, 'PanelMisInscripciones');
    });

    testWidgets('Formulario de inscripción', (tester) async {
      // Se monta con el catálogo inyectado y no en pelado: sin él la pantalla
      // caería en su estado de error —«no pudimos cargar el formulario»— y esta
      // prueba mediría un mensaje en vez del formulario. Pasaría sin haber mirado
      // lo que dice que mira.
      final gateway = FakeGateway()..cursos = cursosDePrueba;

      final error = await medirPantalla(
        tester,
        AspiranteFormScreen(
          planillaRepository: PlanillaRepository(
            gateway: FakePlanillaGateway()..catalogo = catalogoEjemplo(),
          ),
          aspiranteRepository: AspiranteRepository(gateway: gateway),
          authService: AuthService(gateway: gateway),
        ),
      );

      sinDesbordes(error, 'AspiranteFormScreen');
    });

    testWidgets('Formulario de inscripción - recorrido completo para auditar desbordes',
        (tester) async {
      // El recorrido se conduce **por el catálogo** y no por etiquetas escritas a
      // mano: los pasos, las preguntas y cuáles son obligatorias salen de
      // `inscripcion_campos`, así que una prueba que los escribiera a mano
      // volvería a acoplar la prueba a la pantalla justo cuando la pantalla dejó
      // de estar acoplada al catálogo. Y de paso: si el formulario dejara de ser
      // conducido por datos, este recorrido no encontraría los campos y fallaría.
      final arnes = await montarFormulario(
        tester,
        catalogo: catalogoEjemplo(tipoFecha: TipoCampoInscripcion.texto),
        tamano: const Size(375, 2400),
      );

      // `takeException()` **consume** la excepción registrada, así que revisar en
      // cada etapa la localiza. Un único `takeException()` al final sólo dice que
      // «algo» reventó en algún punto del recorrido — y eso no sirve para
      // arreglarlo: obliga a adivinar qué `Row` fue.
      final incidencias = <String>[];
      void revisar(String etapa) {
        final e = tester.takeException();
        if (e != null) incidencias.add('$etapa → $e');
      }

      revisar('Al montar, con la carga en vuelo');

      // Paso 0 · Datos personales. Se escribe un nombre largo y un correo sin
      // espacios para presionar las filas anchas, que es donde vive el candidato
      // a desborde que este barrido busca.
      await escribir(tester, 'primer_nombre', 'Lorenzo Valentín de Jesús');
      await escribir(tester, 'segundo_nombre', 'José');
      await escribir(tester, 'primer_apellido', 'Roca Burmistrow');
      await escribir(tester, 'cedula', '20123456');
      await escribir(tester, 'fecha_nac', '2000-01-01');
      await elegirEnDesplegable(tester, 'sexo', 'Masculino');
      revisar('Paso 0 · datos personales');

      // El desplegable se abre y se cierra a 375 px: la ranura mide 165 px y una
      // opción larga se parte en cuatro líneas que no caben en 24 px de alto. El
      // recorte silencioso **no** lanza, así que lo que se audita aquí es que al
      // menos no desborde.
      await tester.tap(find.text('Continuar').at(0));
      await tester.pumpAndSettle();
      revisar('Paso 1 · ubicación y contacto');

      await escribir(tester, 'telefono', '04141234567');
      await escribir(
        tester,
        'email',
        'lorenzo.roca.martinez.desarrollo@inces.gob.ve',
      );
      await escribir(tester, 'direccion', 'Valencia, Carabobo');
      await tester.tap(find.text('Continuar').at(1));
      await tester.pumpAndSettle();
      revisar('Paso 2 · formación');

      await elegirEnDesplegable(tester, 'nivel_educativo', 'Secundaria');
      await tester.tap(find.text('Continuar').at(2));
      await tester.pumpAndSettle();
      revisar('Paso 3 · misiones');

      // La rejilla con un ítem marcado: al marcar aparece el campo «desde» al lado
      // del rótulo y los dos comparten una fila de 375 px. Es el peor caso del
      // formulario, y es justo el que el formulario viejo no tenía.
      await marcarPrimeraCasilla(tester, 'misiones');
      revisar('Paso 3 · rejilla de misiones marcada');

      await tester.tap(find.text('Continuar').at(3));
      await tester.pumpAndSettle();
      revisar('Paso 4 · representante legal');

      await tester.tap(find.text('Continuar').at(4));
      await tester.pumpAndSettle();
      revisar('Paso 5 · propuesta formativa');

      await elegirEnDesplegable(tester, 'curso_seleccionado', 'Herrería');
      await tester.tap(find.text('Continuar').at(5));
      await tester.pumpAndSettle();
      revisar('Paso 6 · resumen y contraseña');

      // Se demuestra que se llegó al final: si un toque hubiera fallado, el
      // recorrido se habría quedado a medias y la prueba habría pasado sin medir
      // los últimos pasos, que es la peor forma de aprobar.
      expect(find.text('Revisa tus datos antes de enviar'), findsOneWidget);

      // Se informan **todas** las etapas de una vez: con un `expect` por etapa, el
      // primero que falla corta la prueba y las demás nunca se evalúan. Un
      // diagnóstico que oculta la mitad de los fallos obliga a correr dos veces
      // para saber lo que ya se podía saber de una.
      expect(incidencias, isEmpty, reason: incidencias.join('\n'));

      // Y se desmonta antes de salir, para cancelar cualquier temporizador
      // pendiente del propio formulario.
      await tester.pumpWidget(const SizedBox());
      expect(arnes.planilla.llamadas, contains('campos'));
    });
  });
}

/// Doble de [InvitacionGateway] cuyos métodos no se llegan a usar.
///
/// La prueba es de layout: el panel no llama al gateway hasta que alguien envía
/// una invitación. Lanzar en vez de devolver algo inventado deja claro que si
/// algún día se llamara, la prueba lo diría en vez de fingir que funciona.
class _InvitacionSinUso implements InvitacionGateway {
  @override
  Future<InvitacionDocente> invitarDocente(
    String email,
    String nombres,
    String apellidos,
  ) =>
      throw UnimplementedError('No se usa en una prueba de layout.');

  @override
  Future<ActivacionCuenta> activarCuenta({
    required String token,
    required String password,
  }) =>
      throw UnimplementedError('No se usa en una prueba de layout.');
}
