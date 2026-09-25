import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/errors/app_exception.dart';
import '../models/aspirante_model.dart';
import '../models/inscripcion_campo.dart';
import '../models/registro_resultado.dart';
import '../repositories/aspirante_repository.dart';
import '../repositories/planilla_repository.dart';
import '../services/auth_service.dart';
import '../widgets/campos_planilla/campo_planilla.dart';
import '../widgets/campos_planilla/estilos_campo.dart';
import 'registro_exitoso_screen.dart';

/// Los campos del representante legal, por su código del catálogo.
///
/// Se nombran aquí y **no** se deducen del grupo del catálogo («Representante
/// legal») a propósito: el nombre de un grupo es texto que el CFS puede
/// renombrar desde el panel, y el día que lo renombrara la regla de edad se
/// caería en silencio, sin que nada avisara. El código de un campo, en cambio,
/// es su identidad: renombrarlo es una migración de datos.
///
/// Que esta lista exista es deuda asumida, la misma que ya asume
/// `sintetizarClavesPlanas` y que ya asumía `AuthService._validarPlanilla`.
const List<String> _codigosDelRepresentante = [
  'numero_identidad_tutor',
  'nombre_tutor',
  'parentesco_tutor',
  'telefono_tutor',
  'correo_tutor',
];

/// El formulario de inscripción, **conducido por el catálogo**.
///
/// La pantalla no conoce los campos. Los lee de `inscripcion_campos` a través de
/// [PlanillaRepository] y los pinta: un paso por grupo del catálogo, en el orden
/// que el catálogo declare. Añadir una pregunta al formulario es insertar una
/// fila; reordenarlo es cambiar `orden`; añadir un paso es añadir un `grupo`.
///
/// Antes de esto la pantalla era lo contrario: 1137 líneas con cada campo
/// escrito a mano, sus validaciones y sus cuatro pasos cableados. La planilla de
/// papel tiene 44 campos y el formulario cubría 18, así que la distancia entre
/// lo que el CFS pide y lo que el sistema pregunta sólo se podía cerrar
/// desplegando código. Ahora se cierra con un `insert`.
///
/// **Lo que esta pantalla sigue sabiendo, y por qué.** El catálogo describe
/// *qué* preguntar; no describe ni la contraseña (que no es un dato de la
/// planilla, es la credencial de la cuenta), ni la regla de edad del
/// representante legal (que es una condición sobre la edad, y la columna
/// `condicion` del catálogo compara un campo contra otro). Esas dos cosas viven
/// aquí, con el motivo escrito al lado.
class AspiranteFormScreen extends StatefulWidget {
  const AspiranteFormScreen({
    super.key,
    this.planillaRepository,
    this.aspiranteRepository,
    this.authService,
  });

  /// Inyectables para las pruebas.
  ///
  /// Sin esto la pantalla instancia el gateway real, que va por HTTP, y ninguna
  /// prueba podría montarla sin red. Es el mismo patrón que ya usan los paneles
  /// del cPanel (`repositorio:`), y por el mismo motivo: un widget que sólo se
  /// puede montar contra producción no se prueba.
  final PlanillaRepository? planillaRepository;
  final AspiranteRepository? aspiranteRepository;
  final AuthService? authService;

  @override
  State<AspiranteFormScreen> createState() => _AspiranteFormScreenState();
}

class _AspiranteFormScreenState extends State<AspiranteFormScreen> {
  late final PlanillaRepository _planillaRepo;
  late final AspiranteRepository _aspiranteRepo;
  late final AuthService _authService;

  /// La planilla en curso: código de campo → valor.
  ///
  /// **Una sola fuente de verdad.** Los campos bajan su valor por `valor` y lo
  /// suben por `onCambio`; nadie guarda una copia. Por eso una pregunta que se
  /// oculta y se vuelve a mostrar conserva lo que el aspirante había escrito: el
  /// dato nunca vivió en el widget.
  final PlanillaInscripcion _valores = {};

  /// Errores por campo, para pintarlos **bajo el campo que falla**.
  ///
  /// Un `SnackBar` dice que algo falló; esto dice cuál. Con 44 campos, la
  /// diferencia entre las dos cosas es la diferencia entre poder corregir y
  /// tener que adivinar.
  final Map<String, String> _errores = {};

  /// Un `Form` por paso, y no uno solo para toda la pantalla.
  ///
  /// El `Stepper` deja en el árbol el contenido de **todos** los pasos a la vez
  /// (sólo cambia cuál se ve). Con un `Form` único, `validate()` validaría
  /// también los campos que el aspirante todavía no ha visto: un correo mal
  /// escrito en el paso 4 bloquearía el «Continuar» del paso 1, y el error
  /// estaría en una pantalla que no se está mirando. Acotado por paso, cada
  /// validación mira exactamente lo que el aspirante tiene delante.
  final Map<int, GlobalKey<FormState>> _clavesDePaso = {};

  CatalogoInscripcion? _catalogo;
  List<GrupoPlanilla> _grupos = const [];

  int _currentStep = 0;

  bool _cargandoCatalogo = true;

  /// Por qué no se pudo leer el catálogo, si no se pudo.
  ///
  /// **No se degrada a un formulario vacío.** Un catálogo vacío y uno que no se
  /// pudo leer pintan lo mismo —una pantalla sin campos—, y sólo el `Result` del
  /// repositorio los distingue. Mostrar un formulario vacío ante un fallo de red
  /// haría creer que la inscripción no tiene preguntas.
  String? _errorCatalogo;

  bool _cargandoCursos = true;
  List<String> _cursosDisponibles = const [];
  String? _avisoCursos;

  /// Envío en curso. **No** reemplaza el formulario por un spinner: eso hacía
  /// perder todo lo escrito si algo fallaba.
  bool _enviando = false;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _planillaRepo = widget.planillaRepository ?? PlanillaRepository();
    _aspiranteRepo = widget.aspiranteRepository ?? AspiranteRepository();
    _authService = widget.authService ?? AuthService();
    _cargarCatalogo();
    _cargarCursos();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Carga
  // ---------------------------------------------------------------------------

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargandoCatalogo = true;
      _errorCatalogo = null;
    });

    final resultado = await _planillaRepo.obtenerCatalogo();
    if (!mounted) return;

    setState(() {
      final catalogo = resultado.valueOrNull;

      if (catalogo == null || catalogo.campos.isEmpty) {
        _catalogo = null;
        _grupos = const [];
        _clavesDePaso.clear();
        _errorCatalogo = catalogo == null
            ? 'No pudimos cargar el formulario de inscripción. Revisa tu '
                'conexión y vuelve a intentarlo.'
            : 'El formulario de inscripción llegó vacío. Avisa al CFS: el '
                'catálogo de campos no está publicado.';
      } else {
        _catalogo = catalogo;
        _grupos = catalogo.grupos;
        _errorCatalogo = null;
        // Un `Form` por paso, más uno para la confirmación. Se crean aquí y no
        // en `build` para no mutar el estado durante la construcción.
        _clavesDePaso.clear();
        for (var i = 0; i <= _grupos.length; i++) {
          _clavesDePaso[i] = GlobalKey<FormState>();
        }
      }

      _cargandoCatalogo = false;
    });
  }

  Future<void> _cargarCursos() async {
    setState(() {
      _cargandoCursos = true;
      _avisoCursos = null;
    });

    final resultado = await _aspiranteRepo.obtenerCursosDisponibles();
    if (!mounted) return;

    setState(() {
      final cursos = resultado.valueOrNull;
      if (cursos != null && cursos.isNotEmpty) {
        _cursosDisponibles = cursos;
      } else {
        // El fallo se hace visible, pero no se bloquea al aspirante.
        _cursosDisponibles = AspiranteRepository.cursosRespaldo;
        _avisoCursos = cursos == null
            ? 'No pudimos cargar el catálogo de cursos. Se muestran los cursos '
                'conocidos; puedes reintentar.'
            : 'El catálogo llegó vacío. Se muestran los cursos conocidos.';
      }
      _cargandoCursos = false;
    });
  }

  // ---------------------------------------------------------------------------
  // El catálogo, leído como reglas
  // ---------------------------------------------------------------------------

  /// El índice del paso de confirmación: el último.
  int get _pasoConfirmacion => _grupos.length;

  /// ¿Algún campo del catálogo pide sus opciones a otra fuente?
  ///
  /// Hoy sí —`curso_seleccionado` declara `fuente: 'programas'`—, y mientras sea
  /// así el formulario no puede pintarse sin la oferta formativa. Se pregunta en
  /// vez de darlo por hecho para que el día que el CFS deje de usar `fuente`, el
  /// formulario no siga esperando una petición que ya no hace falta.
  bool get _necesitaCursos =>
      _catalogo?.campos.any((campo) => campo.tieneFuenteExterna) ?? false;

  List<CampoInscripcion> _camposDePaso(int paso) =>
      paso >= 0 && paso < _grupos.length ? _grupos[paso].campos : const [];

  /// El paso que contiene ese campo, o `null` si el catálogo no lo tiene.
  int? _pasoDeCampo(String codigo) {
    for (var i = 0; i < _grupos.length; i++) {
      if (_grupos[i].campos.any((campo) => campo.codigo == codigo)) return i;
    }
    return null;
  }

  bool _esMenorDeEdad() {
    final crudo = _valores['fecha_nac'];
    if (crudo is! String) return false;
    return AspiranteModel.esMenorDeEdadCon(DateTime.tryParse(crudo));
  }

  /// ¿Hay que exigir este campo con los valores actuales?
  ///
  /// Es `obligatorioCon` del catálogo **más una regla que el catálogo no puede
  /// expresar**: los datos del representante legal. Ahí la condición es la
  /// EDAD, y la columna `condicion` compara un campo contra otro, así que no
  /// sirve. La autoridad es `requires_legal_tutor`, que el trigger calcula en
  /// SQL desde `fecha_nac`.
  ///
  /// Se replica aquí por el mismo motivo por el que ya lo replica
  /// `AuthService._validarPlanilla`: sin esto, un aspirante menor de edad
  /// recorre diez pasos y se entera al final, con un mensaje del servidor.
  bool _hayQueExigirlo(CampoInscripcion campo) {
    if (_esMenorDeEdad() && _codigosDelRepresentante.contains(campo.codigo)) {
      return true;
    }
    return campo.obligatorioCon(_valores);
  }

  /// Los campos del paso que hay que exigir y aún están vacíos.
  List<CampoInscripcion> _faltantesDelPaso(int paso) {
    final faltan = <CampoInscripcion>[];
    for (final campo in _camposDePaso(paso)) {
      if (!campo.visibleCon(_valores)) continue;
      if (!_hayQueExigirlo(campo)) continue;
      if (valorDeCampoVacio(_valores[campo.codigo])) faltan.add(campo);
    }
    return faltan;
  }

  // ---------------------------------------------------------------------------
  // Estado del formulario
  // ---------------------------------------------------------------------------

  void _cambiarValor(CampoInscripcion campo, Object? valor) {
    setState(() {
      // `null` y vacío se guardan igual —sin la clave—, para que el mapa tenga
      // una sola forma de decir «sin respuesta». Un `false` o un `0` **no** son
      // vacío: son respuestas, y borrarlas sería borrar lo que el aspirante
      // contestó.
      if (valorDeCampoVacio(valor)) {
        _valores.remove(campo.codigo);
      } else {
        _valores[campo.codigo] = valor;
      }
      _errores.remove(campo.codigo);
    });
  }

  /// Las opciones de un campo con `fuente`, resueltas.
  ///
  /// Hoy el único valor es `'programas'`. Una `fuente` desconocida devuelve
  /// `null` y el campo cae a las opciones del catálogo —que no tiene—, así que
  /// se vería vacío. Es preferible eso a inventar opciones que no existen.
  List<OpcionCampo>? _opcionesDeFuente(CampoInscripcion campo) {
    if (campo.fuente != 'programas') return null;
    return [
      for (final curso in _cursosDisponibles)
        OpcionCampo(valor: curso, etiqueta: curso),
    ];
  }

  // ---------------------------------------------------------------------------
  // Validación
  // ---------------------------------------------------------------------------

  bool _validarPaso(int paso) {
    final esConfirmacion = paso == _pasoConfirmacion;

    if (!esConfirmacion) {
      final faltan = _faltantesDelPaso(paso);
      if (faltan.isNotEmpty) {
        setState(() {
          for (final campo in faltan) {
            _errores[campo.codigo] = 'Campo obligatorio';
          }
        });
        _mostrarError(
          'Faltan datos obligatorios: '
          '${faltan.map((campo) => campo.etiqueta.toLowerCase()).join(', ')}.',
        );
        return false;
      }
    }

    // Los validadores del propio renderizador: el formato del correo, el del
    // número, y la obligatoriedad de los tipos que la declaran. Es un segundo
    // paso y no el primero porque el catálogo es la autoridad sobre *qué* es
    // obligatorio —y cubre tipos que no tienen validador, como la rejilla y la
    // tabla—, mientras que el renderizador es la autoridad sobre *la forma* del
    // valor.
    final formatoOk = _clavesDePaso[paso]?.currentState?.validate() ?? true;

    if (!formatoOk) {
      _mostrarError(
        esConfirmacion
            ? 'La contraseña debe tener al menos 8 caracteres y coincidir con '
                'la confirmación.'
            : 'Revisa los campos marcados en rojo antes de continuar.',
      );
    }

    return formatoOk;
  }

  // ---------------------------------------------------------------------------
  // Construcción del envío
  // ---------------------------------------------------------------------------

  /// La planilla que se envía: sólo lo visible y sólo lo respondido.
  ///
  /// **Un campo oculto no se manda**, aunque el aspirante lo haya rellenado y
  /// después lo haya ocultado al cambiar la respuesta de la que depende. Si se
  /// mandara, `datos_planilla` guardaría una contradicción —un
  /// `tipo_discapacidad` junto a un `discapacidad: false`— y nadie sabría
  /// después cuál de las dos cosas es la respuesta.
  ///
  /// **Un campo vacío tampoco**: la base lo trata igual (`validar_planilla()`
  /// usa esta misma regla) y así la metadata no engorda con claves que no dicen
  /// nada.
  PlanillaInscripcion _construirPlanilla() {
    final catalogo = _catalogo;
    if (catalogo == null) return <String, dynamic>{};

    return {
      for (final campo in catalogo.campos)
        if (campo.visibleCon(_valores) &&
            !valorDeCampoVacio(_valores[campo.codigo]))
          campo.codigo: _valores[campo.codigo],
    };
  }

  /// El modelo que consume [AuthService], con las claves planas ya sintetizadas.
  ///
  /// **La síntesis ocurre aquí, en el controlador de la vista**, y es la pieza
  /// que no se puede saltar: el catálogo pide el nombre desglosado
  /// (`primer_nombre` + `segundo_nombre`) y el trigger de PostgreSQL lee
  /// `nombres` ya concatenado. Son vocabularios distintos y el mapeo no es 1 a 1.
  /// Si esto se olvidara, el trigger dejaría `v_nombres` en NULL, la condición
  /// `v_es_aspirante` fallaría y **la ficha no se crearía, sin error**: el
  /// aspirante vería «registro exitoso» y no tendría ficha.
  AspiranteModel _construirModelo(PlanillaInscripcion planilla) {
    final planas = sintetizarClavesPlanas(planilla);

    String? texto(String clave) {
      final valor = planas[clave];
      if (valor == null) return null;
      final limpio = valor.toString().trim();
      return limpio.isEmpty ? null : limpio;
    }

    return AspiranteModel(
      nombres: texto('nombres') ?? '',
      apellidos: texto('apellidos') ?? '',
      cedula: texto('cedula') ?? '',
      fechaNacimiento: DateTime.tryParse(texto('fecha_nac') ?? ''),
      sexo: texto('sexo') ?? '',
      telefono: texto('telefono') ?? '',
      // El correo de la cuenta **no** viaja en la metadata —lo pone
      // `auth.users`—, pero el modelo sí lo necesita: `AuthService` lo usa para
      // el prechequeo de duplicados y para la pantalla de éxito. Se lee de la
      // planilla, que es donde el aspirante lo escribió.
      email: (planilla['email'] ?? '').toString().trim().toLowerCase(),
      direccion: texto('direccion') ?? '',
      nivelEducativo: texto('nivel_educativo') ?? '',
      cursoSeleccionado: texto('curso_seleccionado') ?? '',
      discapacidad: planas['discapacidad'] == true,
      tipoDiscapacidad: _listaATexto(planilla['tipo_discapacidad']),
      numeroIdentidadTutor: texto('numero_identidad_tutor'),
      nombreTutor: texto('nombre_tutor'),
      parentescoTutor: texto('parentesco_tutor'),
      telefonoTutor: texto('telefono_tutor'),
      correoTutor: texto('correo_tutor'),
      datosPlanilla: planilla,
    );
  }

  /// Una multiselección viaja al trigger como texto.
  ///
  /// El catálogo guarda `tipo_discapacidad` como lista y el trigger lo lee con
  /// `->>`, que sobre una lista devuelve su JSON (`["FISICA_MANO"]`) — que no es
  /// lo que nadie quiere leer en una columna de texto. La planilla completa
  /// conserva la lista; la columna plana recibe el texto.
  static String? _listaATexto(Object? valor) {
    if (valor is List) {
      final partes = valor
          .map((elemento) => elemento.toString().trim())
          .where((elemento) => elemento.isNotEmpty);
      return partes.isEmpty ? null : partes.join(', ');
    }
    final texto = valor?.toString().trim();
    return texto == null || texto.isEmpty ? null : texto;
  }

  Future<void> _enviarFormulario() async {
    if (_enviando) return;
    if (!_validarPaso(_pasoConfirmacion)) return;

    setState(() => _enviando = true);

    final planilla = _construirPlanilla();
    final modelo = _construirModelo(planilla);

    // Registro de punta a punta: el trigger de PostgreSQL crea el perfil y la
    // ficha de aspirante de forma atómica dentro del propio signUp.
    final resultado = await _authService.registrarAspirante(
      aspirante: modelo,
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    resultado.when(
      success: (RegistroResultado registro) => _irARegistroExitoso(registro),
      failure: _manejarErrorRegistro,
    );
  }

  void _irARegistroExitoso(RegistroResultado registro) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RegistroExitosoScreen(
          email: registro.email,
          requiereTutorLegal: registro.requiereTutorLegal,
          requiereConfirmacionEmail: registro.requiereConfirmacionEmail,
          sesionIniciada: registro.sesionIniciada,
        ),
      ),
    );
  }

  void _manejarErrorRegistro(AppException error) {
    // Si el problema es de identidad, se devuelve al aspirante al paso donde
    // está el campo, en vez de dejarlo atascado en la confirmación mirando un
    // mensaje sobre un dato que no tiene delante.
    if (error.type == AppErrorType.duplicado) {
      final esCedula = (error.code == 'CEDULA_DUPLICADA') ||
          error.message.toLowerCase().contains('cédula');
      if (esCedula) {
        setState(() => _currentStep = _pasoDeCampo('cedula') ?? 0);
      }
    }

    _mostrarError(error.message);
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(mensaje)),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Construcción de la UI
  // ---------------------------------------------------------------------------

  /// El contenido de un paso que es un grupo del catálogo.
  Widget _construirGrupo(GrupoPlanilla grupo) {
    final visibles = [
      for (final campo in grupo.campos)
        if (campo.visibleCon(_valores)) campo,
    ];

    final pideFuenteExterna = visibles.any((campo) => campo.tieneFuenteExterna);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pideFuenteExterna && _avisoCursos != null) ...[
          _construirAvisoCursos(),
          const SizedBox(height: 16),
        ],
        for (final campo in visibles)
          CampoPlanilla(
            // La clave ata el estado al **código** del campo y no a su posición.
            // Cuando una pregunta condicional aparece, los campos de debajo
            // cambian de sitio; sin clave, Flutter reutilizaría el estado del
            // que estaba en esa posición y el aspirante vería el texto de otra
            // pregunta en el campo nuevo.
            key: ValueKey('campo-${campo.codigo}'),
            campo: campo,
            valor: _valores[campo.codigo],
            opciones: campo.tieneFuenteExterna ? _opcionesDeFuente(campo) : null,
            error: _errores[campo.codigo],
            onCambio: (valor) => _cambiarValor(campo, valor),
          ),
      ],
    );
  }

  Widget _construirAvisoCursos() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _avisoCursos!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF78350F),
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: _cargandoCursos ? null : _cargarCursos,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  /// El resumen del paso final, construido desde el catálogo.
  ///
  /// Antes era una lista de once `MapEntry` escrita a mano que nombraba cada
  /// campo; con el catálogo eso sería una segunda lista que mantener en paralelo
  /// y que se desviaría en cuanto el CFS añadiera un campo. Aquí se recorre el
  /// catálogo en su orden y se muestra lo que tenga respuesta.
  Widget _construirResumen() {
    final catalogo = _catalogo;
    final filas = <MapEntry<String, String>>[];

    if (catalogo != null) {
      final ordenados = [...catalogo.campos]
        ..sort((a, b) => a.orden.compareTo(b.orden));

      for (final campo in ordenados) {
        if (!campo.visibleCon(_valores)) continue;
        final texto = textoDeValor(campo, _valores[campo.codigo]);
        if (texto.isEmpty) continue;
        filas.add(MapEntry(campo.etiqueta, texto));
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revisa tus datos antes de enviar',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          for (final fila in filas)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      fila.key,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      fila.value,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _construirConfirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _construirResumen(),
        const SizedBox(height: 24),
        Text(
          'Crea tu contraseña de acceso',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'Con tu cédula o correo y esta contraseña entrarás al aula virtual.',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: decoracionDeCampo(
            etiqueta: 'Contraseña (mínimo 8 caracteres)',
            icono: Icons.lock_outline,
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: const Color(0xFF64748B),
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) {
            final texto = value ?? '';
            if (texto.isEmpty) return 'Campo obligatorio';
            if (texto.length < 8) return 'Mínimo 8 caracteres';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordConfirmController,
          obscureText: _obscureConfirm,
          autocorrect: false,
          enableSuggestions: false,
          decoration: decoracionDeCampo(
            etiqueta: 'Confirmar contraseña',
            icono: Icons.lock_reset_outlined,
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: const Color(0xFF64748B),
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Campo obligatorio';
            if (value != _passwordController.text) {
              return 'Las contraseñas no coinciden';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _construirErrorDeCatalogo(String mensaje) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 44,
                color: Color(0xFFB45309),
              ),
              const SizedBox(height: 12),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargarCatalogo,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      appBar: AppBar(
        title: const Text('Inscripción - INCES La Isabelica'),
        backgroundColor: Colors.blue[900],
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_enviando) const LinearProgressIndicator(minHeight: 3),
          Expanded(child: _construirCuerpo()),
        ],
      ),
    );
  }

  Widget _construirCuerpo() {
    // El catálogo es lo que define el formulario: sin él no hay nada que pintar.
    // La oferta formativa sólo bloquea si algún campo la pide.
    if (_cargandoCatalogo || (_necesitaCursos && _cargandoCursos)) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _errorCatalogo;
    if (error != null) return _construirErrorDeCatalogo(error);

    return AbsorbPointer(
      // Bloquea la interacción durante el envío sin desmontar el formulario: los
      // datos escritos nunca se pierden.
      absorbing: _enviando,
      child: LayoutBuilder(
        builder: (context, constraints) => _construirStepper(constraints),
      ),
    );
  }

  Widget _construirStepper(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth > 800 ? 800.0 : constraints.maxWidth;
    final padding =
        isSmallScreen ? const EdgeInsets.all(16) : const EdgeInsets.all(32);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return SingleChildScrollView(
      child: Center(
        child: Container(
          width: maxWidth,
          padding: padding,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stepper(
            type: StepperType.vertical,
            currentStep: _currentStep,
            physics: const ClampingScrollPhysics(),
            onStepContinue: () {
              if (_currentStep < _pasoConfirmacion) {
                if (_validarPaso(_currentStep)) {
                  setState(() => _currentStep += 1);
                }
              } else {
                _enviarFormulario();
              }
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() => _currentStep -= 1);
              }
            },
            controlsBuilder: (context, details) {
              final esUltimo = details.stepIndex == _pasoConfirmacion;
              return Padding(
                padding: const EdgeInsets.only(top: 20),
                // Wrap y no Row: en móvil angosto el botón principal baja a la
                // línea siguiente en lugar de desbordar.
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    if (details.stepIndex > 0)
                      TextButton(
                        onPressed: _enviando ? null : details.onStepCancel,
                        child: const Text('Atrás'),
                      ),
                    FilledButton(
                      onPressed: _enviando ? null : details.onStepContinue,
                      child: _enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              esUltimo
                                  ? 'Finalizar inscripción'
                                  : 'Continuar',
                            ),
                    ),
                  ],
                ),
              );
            },
            steps: [
              // Un paso por grupo del catálogo, en su orden. El título es el
              // nombre del grupo: el CFS lo controla desde la tabla.
              for (var i = 0; i < _grupos.length; i++)
                Step(
                  title: Text(
                    _grupos[i].nombre,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  content: Form(
                    key: _clavesDePaso[i],
                    child: _construirGrupo(_grupos[i]),
                  ),
                  isActive: _currentStep >= i,
                  state: _currentStep > i
                      ? StepState.complete
                      : StepState.indexed,
                ),
              // Y el paso que no viene del catálogo, porque la contraseña no es
              // un dato de la planilla: es la credencial de la cuenta.
              Step(
                title: const Text('Confirmación y Contraseña'),
                content: Form(
                  key: _clavesDePaso[_pasoConfirmacion],
                  child: _construirConfirmacion(),
                ),
                isActive: _currentStep >= _pasoConfirmacion,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get isSmallScreen => MediaQuery.of(context).size.width < 600;
}
