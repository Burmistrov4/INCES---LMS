import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/errors/app_exception.dart';
import '../models/aspirante_model.dart';
import '../models/registro_resultado.dart';
import '../repositories/aspirante_repository.dart';
import '../screens/registro_exitoso_screen.dart';
import '../services/auth_service.dart';

class AspiranteFormScreen extends StatefulWidget {
  const AspiranteFormScreen({super.key});

  @override
  State<AspiranteFormScreen> createState() => _AspiranteFormScreenState();
}

class _AspiranteFormScreenState extends State<AspiranteFormScreen> {
  static const int _ultimoPaso = 3;

  int _currentStep = 0;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final AspiranteRepository _aspiranteRepo = AspiranteRepository();
  final AuthService _authService = AuthService();

  late TextEditingController _nombresController;
  late TextEditingController _apellidosController;
  late TextEditingController _cedulaController;
  late TextEditingController _telefonoController;
  late TextEditingController _correoController;
  late TextEditingController _domicilioController;
  late TextEditingController _nivelEducativoController;
  late TextEditingController _fechaNacimientoController;
  late TextEditingController _numeroIdentidadTutorController;
  late TextEditingController _nombreTutorController;
  late TextEditingController _telefonoTutorController;
  late TextEditingController _correoTutorController;
  late TextEditingController _misionEstudianteController;
  late TextEditingController _passwordController;
  late TextEditingController _passwordConfirmController;

  String _parentescoSeleccionado = '';
  String _sexoSeleccionado = '';
  String _tipoDiscapacidad = '';
  String _cursoSeleccionado = '';
  bool _tieneDiscapacidad = false;
  bool _tieneMision = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  List<String> _cursosDisponibles = [];

  /// Aviso no bloqueante cuando el catálogo de cursos vino de respaldo local.
  String? _avisoCursos;

  /// Carga inicial del catálogo (distinta del envío del formulario).
  bool _cargandoCursos = true;

  /// Envío en curso. **No** debe reemplazar el formulario por un spinner:
  /// eso hacía perder todo lo escrito si algo fallaba.
  bool _enviando = false;

  DateTime? _selectedFechaNacimiento;

  @override
  void initState() {
    super.initState();
    _nombresController = TextEditingController();
    _apellidosController = TextEditingController();
    _cedulaController = TextEditingController();
    _telefonoController = TextEditingController();
    _correoController = TextEditingController();
    _domicilioController = TextEditingController();
    _nivelEducativoController = TextEditingController();
    _fechaNacimientoController = TextEditingController();
    _numeroIdentidadTutorController = TextEditingController();
    _nombreTutorController = TextEditingController();
    _telefonoTutorController = TextEditingController();
    _correoTutorController = TextEditingController();
    _misionEstudianteController = TextEditingController();
    _passwordController = TextEditingController();
    _passwordConfirmController = TextEditingController();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
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

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    _cedulaController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    _domicilioController.dispose();
    _nivelEducativoController.dispose();
    _fechaNacimientoController.dispose();
    _numeroIdentidadTutorController.dispose();
    _nombreTutorController.dispose();
    _telefonoTutorController.dispose();
    _correoTutorController.dispose();
    _misionEstudianteController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final minDate = DateTime(now.year - 80, now.month, now.day);
    final maxDate = DateTime(now.year - 15, now.month, now.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedFechaNacimiento ?? DateTime(now.year - 20),
      firstDate: minDate,
      lastDate: maxDate,
      helpText: 'Fecha de nacimiento',
    );

    if (picked != null) {
      setState(() {
        _selectedFechaNacimiento = picked;
        _fechaNacimientoController.text =
            DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  bool _validarPaso(int step) {
    switch (step) {
      case 0:
        return _nombresController.text.trim().isNotEmpty &&
            _apellidosController.text.trim().isNotEmpty &&
            _cedulaController.text.trim().isNotEmpty &&
            _selectedFechaNacimiento != null &&
            _sexoSeleccionado.isNotEmpty;
      case 1:
        return _telefonoController.text.trim().isNotEmpty &&
            _correoController.text.trim().isNotEmpty &&
            _domicilioController.text.trim().isNotEmpty &&
            _nivelEducativoController.text.trim().isNotEmpty;
      case 2:
        return _cursoSeleccionado.isNotEmpty &&
            (!_tieneDiscapacidad || _tipoDiscapacidad.isNotEmpty) &&
            (!_esMenorDeEdad() ||
                (_numeroIdentidadTutorController.text.trim().isNotEmpty &&
                    _nombreTutorController.text.trim().isNotEmpty &&
                    _parentescoSeleccionado.isNotEmpty &&
                    _telefonoTutorController.text.trim().isNotEmpty &&
                    _correoTutorController.text.trim().isNotEmpty));
      case 3:
        return _passwordController.text.length >= 8 &&
            _passwordController.text == _passwordConfirmController.text;
      default:
        return true;
    }
  }

  /// Mensaje de por qué el paso actual no permite avanzar.
  String _motivoPasoInvalido(int step) {
    switch (step) {
      case 0:
        return 'Completa nombres, apellidos, cédula, fecha de nacimiento y sexo.';
      case 1:
        return 'Completa teléfono, correo, domicilio y nivel educativo.';
      case 2:
        if (_cursoSeleccionado.isEmpty) {
          return 'Selecciona la propuesta formativa a cursar.';
        }
        if (_tieneDiscapacidad && _tipoDiscapacidad.isEmpty) {
          return 'Indica el tipo de discapacidad.';
        }
        return 'El aspirante es menor de edad: completa los datos del '
            'representante legal.';
      case 3:
        if (_passwordController.text.length < 8) {
          return 'La contraseña debe tener al menos 8 caracteres.';
        }
        return 'Las contraseñas no coinciden.';
      default:
        return 'Revisa los datos del formulario.';
    }
  }

  AspiranteModel _construirModelo() {
    return AspiranteModel(
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      cedula: _cedulaController.text.trim(),
      fechaNacimiento: _selectedFechaNacimiento,
      sexo: _sexoSeleccionado,
      telefono: _telefonoController.text.trim(),
      email: _correoController.text.trim().toLowerCase(),
      direccion: _domicilioController.text.trim(),
      nivelEducativo: _nivelEducativoController.text.trim(),
      cursoSeleccionado: _cursoSeleccionado,
      numeroIdentidadTutor: _numeroIdentidadTutorController.text.trim(),
      nombreTutor: _nombreTutorController.text.trim(),
      parentescoTutor: _parentescoSeleccionado,
      telefonoTutor: _telefonoTutorController.text.trim(),
      correoTutor: _correoTutorController.text.trim(),
      discapacidad: _tieneDiscapacidad,
      tipoDiscapacidad: _tieneDiscapacidad ? _tipoDiscapacidad : null,
      misionRibaras:
          _tieneMision ? _misionEstudianteController.text.trim() : null,
    );
  }

  Future<void> _enviarFormulario() async {
    if (_enviando) return;

    if (!_validarPaso(_ultimoPaso)) {
      _mostrarError(_motivoPasoInvalido(_ultimoPaso));
      return;
    }

    // El Form sólo valida los campos visibles; el paso de confirmación incluye
    // las contraseñas, que se validan aparte con _validarPaso.
    if (_currentStep != _ultimoPaso && !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _enviando = true);

    final modelo = _construirModelo();

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
    // Si el problema es de datos de identidad, devolvemos al aspirante al paso
    // correspondiente en vez de dejarlo atascado en la confirmación.
    if (error.type == AppErrorType.duplicado) {
      final esCedula = (error.code == 'CEDULA_DUPLICADA') ||
          error.message.toLowerCase().contains('cédula');
      if (esCedula) {
        setState(() => _currentStep = 0);
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

  Widget _buildStepContent(int step) {
    switch (step) {
      case 0:
        return _buildDatosPersonales();
      case 1:
        return _buildUbicacionContacto();
      case 2:
        return _buildFormacionMisiones();
      case 3:
        return _buildConfirmacion();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDatosPersonales() {
    return Column(
      children: [
        _buildNombreCampo(),
        const SizedBox(height: 12),
        _buildApellidoCampo(),
        const SizedBox(height: 12),
        _buildCedulaCampo(),
        const SizedBox(height: 12),
        _buildFechaNacimientoCampo(),
        const SizedBox(height: 12),
        _buildSexoCampo(),
      ],
    );
  }

  Widget _buildApellidoCampo() {
    return TextFormField(
      controller: _apellidosController,
      textCapitalization: TextCapitalization.words,
      decoration:
          _inputDecoration(label: 'Apellidos', icon: Icons.person_outline),
      validator: (value) => value!.trim().isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildNombreCampo() {
    return TextFormField(
      controller: _nombresController,
      textCapitalization: TextCapitalization.words,
      decoration:
          _inputDecoration(label: 'Nombres', icon: Icons.person_outline),
      validator: (value) => value!.trim().isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildCedulaCampo() {
    return TextFormField(
      controller: _cedulaController,
      decoration: _inputDecoration(
        label: 'Cédula de Identidad / Pasaporte',
        icon: Icons.badge_outlined,
      ),
      keyboardType: TextInputType.number,
      validator: (value) => value!.trim().isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildFechaNacimientoCampo() {
    return TextFormField(
      controller: _fechaNacimientoController,
      readOnly: true,
      onTap: _selectDate,
      decoration: _inputDecoration(
        label: 'Fecha de Nacimiento',
        icon: Icons.calendar_today,
      ).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.date_range_outlined, size: 20),
          onPressed: _selectDate,
        ),
      ),
      validator: (value) => value!.isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildSexoCampo() {
    return DropdownButtonFormField<String>(
      decoration: _inputDecoration(label: 'Sexo', icon: Icons.person_outline),
      initialValue: _sexoSeleccionado.isEmpty ? null : _sexoSeleccionado,
      items: const [
        DropdownMenuItem(value: 'F', child: Text('Femenino')),
        DropdownMenuItem(value: 'M', child: Text('Masculino')),
        DropdownMenuItem(value: 'Otro', child: Text('Otro')),
      ],
      onChanged: (value) => setState(() => _sexoSeleccionado = value ?? ''),
      validator: (value) =>
          value == null || value.isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildUbicacionContacto() {
    return Column(
      children: [
        _buildTelefonoCampo(),
        const SizedBox(height: 12),
        _buildCorreoCampo(),
        const SizedBox(height: 12),
        _buildDomicilioCampo(),
        const SizedBox(height: 12),
        _buildNivelEducativoCampo(),
      ],
    );
  }

  Widget _buildTelefonoCampo() {
    return TextFormField(
      controller: _telefonoController,
      decoration: _inputDecoration(
        label: 'Teléfono Móvil',
        icon: Icons.phone_outlined,
      ),
      keyboardType: TextInputType.phone,
      validator: (value) => value!.trim().isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildCorreoCampo() {
    return TextFormField(
      controller: _correoController,
      decoration: _inputDecoration(
        label: 'Correo Electrónico',
        icon: Icons.email_outlined,
      ),
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return 'Campo obligatorio';
        if (!RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(text)) {
          return 'Ingresa un correo válido';
        }
        return null;
      },
    );
  }

  Widget _buildDomicilioCampo() {
    return TextFormField(
      controller: _domicilioController,
      maxLines: 2,
      decoration: _inputDecoration(label: 'Domicilio', icon: Icons.home_outlined),
      validator: (value) => value!.trim().isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildNivelEducativoCampo() {
    return DropdownButtonFormField<String>(
      decoration: _inputDecoration(
        label: 'Nivel Educativo',
        icon: Icons.school_outlined,
      ),
      initialValue: _nivelEducativoController.text.isEmpty
          ? null
          : _nivelEducativoController.text,
      items: const [
        DropdownMenuItem(value: 'Primario', child: Text('Primario')),
        DropdownMenuItem(value: 'Secundario', child: Text('Secundario')),
        DropdownMenuItem(value: 'Técnico', child: Text('Técnico')),
        DropdownMenuItem(value: 'No aplicable', child: Text('No aplicable')),
      ],
      onChanged: (value) =>
          setState(() => _nivelEducativoController.text = value ?? ''),
      validator: (value) =>
          value == null || value.isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildFormacionMisiones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_avisoCursos != null) ...[
          _buildAvisoCursos(),
          const SizedBox(height: 16),
        ],
        _buildCursoDropdown(),
        const SizedBox(height: 16),
        _buildMisionCheckbox(),
        const SizedBox(height: 16),
        _buildDiscapacidadCheckbox(),
        const SizedBox(height: 16),
        _buildTutorSection(),
      ],
    );
  }

  Widget _buildAvisoCursos() {
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
            onPressed: _cargandoCursos ? null : _cargarDatosIniciales,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildCursoDropdown() {
    return DropdownButtonFormField<String>(
      decoration: _inputDecoration(
        label: 'Propuesta Formativa a Cursar',
        icon: Icons.book_outlined,
      ),
      initialValue: _cursoSeleccionado.isEmpty ? null : _cursoSeleccionado,
      isExpanded: true,
      items: _cursosDisponibles
          .map((curso) => DropdownMenuItem(value: curso, child: Text(curso)))
          .toList(),
      onChanged: (value) => setState(() => _cursoSeleccionado = value ?? ''),
      validator: (value) =>
          value == null || value.isEmpty ? 'Campo obligatorio' : null,
    );
  }

  Widget _buildMisionCheckbox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _tieneMision,
              onChanged: (value) => setState(() => _tieneMision = value ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Poseo misión educativa', style: GoogleFonts.inter()),
            ),
          ],
        ),
        if (_tieneMision) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _misionEstudianteController,
            maxLines: 2,
            decoration: _inputDecoration(
              label: 'Descripción de misión',
              icon: Icons.flag,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDiscapacidadCheckbox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _tieneDiscapacidad,
              onChanged: (value) =>
                  setState(() => _tieneDiscapacidad = value ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Tiene discapacidad', style: GoogleFonts.inter()),
            ),
          ],
        ),
        if (_tieneDiscapacidad) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: _inputDecoration(
              label: 'Tipo de discapacidad',
              icon: Icons.accessible,
            ),
            initialValue: _tipoDiscapacidad.isEmpty ? null : _tipoDiscapacidad,
            items: const [
              DropdownMenuItem(value: 'Visual', child: Text('Visual')),
              DropdownMenuItem(value: 'Auditiva', child: Text('Auditiva')),
              DropdownMenuItem(value: 'Motriz', child: Text('Motriz')),
              DropdownMenuItem(value: 'Cognitiva', child: Text('Cognitiva')),
            ],
            onChanged: (value) =>
                setState(() => _tipoDiscapacidad = value ?? ''),
            validator: (value) => _tieneDiscapacidad &&
                    (value == null || value.isEmpty)
                ? 'Indica el tipo de discapacidad'
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildTutorSection() {
    if (!_esMenorDeEdad()) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE0E7FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF6366F1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFF3730A3), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El aspirante es menor de edad: el representante legal es '
                  'obligatorio.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF312E81),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Datos del Representante Legal',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _numeroIdentidadTutorController,
          decoration: _inputDecoration(
            label: 'Cédula del Tutor',
            icon: Icons.badge_outlined,
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nombreTutorController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            label: 'Nombre Completo del Tutor',
            icon: Icons.person_outline,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue:
              _parentescoSeleccionado.isEmpty ? null : _parentescoSeleccionado,
          decoration: _inputDecoration(
            label: 'Parentesco',
            icon: Icons.family_restroom,
          ),
          items: const [
            DropdownMenuItem(value: 'Padre', child: Text('Padre')),
            DropdownMenuItem(value: 'Madre', child: Text('Madre')),
            DropdownMenuItem(value: 'Tío/a', child: Text('Tío/a')),
            DropdownMenuItem(value: 'Abuelo/a', child: Text('Abuelo/a')),
            DropdownMenuItem(value: 'Padrino/a', child: Text('Padrino/a')),
          ],
          onChanged: (value) =>
              setState(() => _parentescoSeleccionado = value ?? ''),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _telefonoTutorController,
          decoration: _inputDecoration(
            label: 'Teléfono del Tutor',
            icon: Icons.phone_outlined,
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _correoTutorController,
          decoration: _inputDecoration(
            label: 'Correo del Tutor',
            icon: Icons.email_outlined,
          ),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
        ),
      ],
    );
  }

  bool _esMenorDeEdad() {
    final fecha = _selectedFechaNacimiento;
    if (fecha == null) return false;
    final hoy = DateTime.now();
    final edad = hoy.year - fecha.year;
    final cumpleYaPaso = hoy.month > fecha.month ||
        (hoy.month == fecha.month && hoy.day >= fecha.day);
    return edad - (cumpleYaPaso ? 0 : 1) < 18;
  }

  Widget _buildConfirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildResumen(),
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
          decoration: _inputDecoration(
            label: 'Contraseña (mínimo 8 caracteres)',
            icon: Icons.lock_outline,
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
          decoration: _inputDecoration(
            label: 'Confirmar contraseña',
            icon: Icons.lock_reset_outlined,
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

  Widget _buildResumen() {
    final filas = <MapEntry<String, String>>[
      MapEntry('Nombres', _nombresController.text),
      MapEntry('Apellidos', _apellidosController.text),
      MapEntry('Cédula', _cedulaController.text),
      MapEntry(
        'Fecha de nacimiento',
        _selectedFechaNacimiento != null
            ? DateFormat('dd/MM/yyyy').format(_selectedFechaNacimiento!)
            : '—',
      ),
      MapEntry('Teléfono', _telefonoController.text),
      MapEntry('Correo', _correoController.text),
      MapEntry('Domicilio', _domicilioController.text),
      MapEntry('Nivel educativo', _nivelEducativoController.text),
      MapEntry('Propuesta formativa', _cursoSeleccionado),
      if (_tieneDiscapacidad) MapEntry('Discapacidad', _tipoDiscapacidad),
      if (_esMenorDeEdad())
        MapEntry('Representante legal', _nombreTutorController.text),
    ];

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
                      fila.value.isEmpty ? '—' : fila.value,
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          Expanded(
            child: _cargandoCursos
                ? const Center(child: CircularProgressIndicator())
                : AbsorbPointer(
                    // Bloquea la interacción durante el envío sin desmontar el
                    // formulario: los datos escritos nunca se pierden.
                    absorbing: _enviando,
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          _buildStepper(constraints),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth > 800 ? 800.0 : constraints.maxWidth;
    final padding = isSmallScreen
        ? const EdgeInsets.all(16)
        : const EdgeInsets.all(32);
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
          child: Form(
            key: _formKey,
            child: Stepper(
              type: StepperType.vertical,
              currentStep: _currentStep,
              physics: const ClampingScrollPhysics(),
              onStepContinue: () {
                if (_currentStep < _ultimoPaso) {
                  if (_validarPaso(_currentStep)) {
                    setState(() => _currentStep += 1);
                  } else {
                    _mostrarError(_motivoPasoInvalido(_currentStep));
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
                final esUltimo = details.stepIndex == _ultimoPaso;
                return Padding(
                  padding: const EdgeInsets.only(top: 20),
                  // Wrap y no Row: en móvil angosto el botón principal baja a
                  // la línea siguiente en lugar de desbordar.
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      if (details.stepIndex > 0)
                        TextButton(
                          onPressed:
                              _enviando ? null : details.onStepCancel,
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
                Step(
                  title: Text(
                    'Datos Personales',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                  content: _buildStepContent(0),
                  isActive: _currentStep >= 0,
                  state: _currentStep > 0
                      ? StepState.complete
                      : StepState.indexed,
                ),
                Step(
                  title: const Text('Ubicación y Contacto'),
                  content: _buildStepContent(1),
                  isActive: _currentStep >= 1,
                  state: _currentStep > 1
                      ? StepState.complete
                      : StepState.indexed,
                ),
                Step(
                  title: const Text('Formación y Misiones'),
                  content: _buildStepContent(2),
                  isActive: _currentStep >= 2,
                  state: _currentStep > 2
                      ? StepState.complete
                      : StepState.indexed,
                ),
                Step(
                  title: const Text('Confirmación y Contraseña'),
                  content: _buildStepContent(3),
                  isActive: _currentStep >= 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get isSmallScreen => MediaQuery.of(context).size.width < 600;
}
