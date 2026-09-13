import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/result.dart';
import '../models/aspirante_model.dart';
import '../repositories/aspirante_repository.dart';
import '../services/auth_service.dart';

/// Panel del aspirante.
///
/// Ya no habla con `SupabaseService` directamente: usa [AspiranteRepository],
/// que devuelve `Result`. Un fallo de red se muestra como error con reintento,
/// **nunca** como "no tienes ficha" (ese era el bug que ocultaba datos).
class AspiranteDashboardScreen extends StatefulWidget {
  const AspiranteDashboardScreen({super.key, this.repositorio, this.auth});

  final AspiranteRepository? repositorio;
  final AuthService? auth;

  @override
  State<AspiranteDashboardScreen> createState() =>
      _AspiranteDashboardScreenState();
}

class _AspiranteDashboardScreenState extends State<AspiranteDashboardScreen> {
  late final AspiranteRepository _repo = widget.repositorio ?? AspiranteRepository();
  late final AuthService _auth = widget.auth ?? AuthService();

  bool _cargando = true;
  AspiranteModel? _aspirante;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final resultado = await _repo.obtenerMiFicha();
    if (!mounted) return;

    setState(() {
      _cargando = false;
      switch (resultado) {
        case Success(value: final ficha):
          _aspirante = ficha;
        case Failure(error: final fallo):
          _error = fallo.message;
      }
    });
  }

  Future<void> _cerrarSesion() async {
    await _auth.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Panel del Aspirante'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _cerrarSesion,
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: _buildContenido(),
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF2563EB)),
        ),
      );
    }

    if (_error != null) {
      return _buildError(_error!);
    }

    final aspirante = _aspirante;
    return aspirante == null ? _buildEmptyState() : _buildInfo(aspirante);
  }

  Widget _buildError(String mensaje) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 48, color: Color(0xFFF87171)),
        const SizedBox(height: 16),
        Text(
          'No pudimos cargar tu ficha',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.pending_actions_outlined,
          size: 48,
          color: Color(0xFF2563EB),
        ),
        const SizedBox(height: 16),
        Text(
          'Tu inscripción está en revisión',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Cuando el centro formativo apruebe tu solicitud verás aquí tu curso y estado.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  Widget _buildInfo(AspiranteModel aspirante) {
    final curso = aspirante.cursoSeleccionado.isEmpty
        ? 'Por asignar'
        : aspirante.cursoSeleccionado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ficha del aspirante',
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        _fila('Nombre', aspirante.nombres),
        _fila('Apellido', aspirante.apellidos),
        _fila('Cédula', aspirante.cedula),
        _fila('Curso solicitado', curso),
      ],
    );
  }

  Widget _fila(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
