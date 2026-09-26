import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_exception.dart';
import '../core/network/api_client.dart';
import '../core/result.dart';
import 'supabase_service.dart';

/// El código del QR, derivado de la sesión y la ventana temporal.
///
/// **Es la MISMA función que la base** (`asistencia_codigo_en_ventana`
/// de 202609260001): sha256(secreto ‖ sesionId ‖ ventana), primeros 8 hex,
/// a 6 dígitos. Si discreparan, el QR mostrado no aceptaría a nadie. El
/// docente no pide el código al servidor: lo deriva LOCALMENTE cada ventana —
/// por eso la pantalla rota sin red— y sólo la base sabe validarlo, porque la
/// barrera de propiedad (202609260002) ya no deja leer el secreto a un
//  estudiante por RPC.
class CodigoQr {
  CodigoQr({required this.codigo, required this.venceEnSegundos});

  /// 6 dígitos visibles al alumno.
  final String codigo;

  /// Segundos que le quedan al código mostrado. Cuando llega a 0 se rota.
  final int venceEnSegundos;
}

/// Una marca de asistencia, tal como llega por REST o por el canal WS.
class MarcaAsistencia {
  MarcaAsistencia({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.marcadaEn,
  });

  factory MarcaAsistencia.deJson(Map<String, dynamic> j) => MarcaAsistencia(
        id: j['id'] as String,
        sessionId: j['session_id'] as String,
        studentId: j['student_id'] as String,
        marcadaEn: j['marked_at'] as String,
      );

  final String id;
  final String sessionId;
  final String studentId;
  final String marcadaEn;
}

/// Evento que empuja el canal WS. O `marca` o `sesion_cerrada`.
class EventoAsistencia {
  EventoAsistencia._({required this.tipo, this.marca});

  factory EventoAsistencia.deJson(Map<String, dynamic> ev) {
    final tipo = ev['tipo'] as String;
    if (tipo == 'marca') {
      return EventoAsistencia._(tipo: tipo, marca: MarcaAsistencia.deJson(ev['marca'] as Map<String, dynamic>));
    }
    return EventoAsistencia._(tipo: tipo);
  }

  final String tipo;
  final MarcaAsistencia? marca;
}

/// Cliente del módulo de asistencia (M7). REST guarda; WS avisa.
class AsistenciaService {
  AsistenciaService({ApiClient? api})
      : _api = api ?? ApiClient();

  final ApiClient _api;

  static const String _ruta = '/api/v1/asistencia';

  static String _token() =>
      SupabaseService.instance.auth.currentSession?.accessToken ?? '';

  /// Abre una sesión de asistencia para esa sección. Devuelve la fila, con el
  /// `qr_secret` —el ÚNICO momento en que el secreto viaja por el aire— y el
  /// intervalo de ventana (por defecto 15 s).
  Future<Result<Map<String, dynamic>>> abrirSesion({
    required String seccionId,
    int ventanaSeg = 15,
  }) {
    return Result.guard(() async {
      final resp = await _api.post(
        '$_ruta/sesiones',
        token: _token(),
        cuerpo: {'seccionId': seccionId, 'ventanaSeg': ventanaSeg},
      );
      final sesion = resp['sesion'] as Map<String, dynamic>?;
      if (sesion == null) {
        throw const AppException.validacion(
          'La sesión no vino en la respuesta.',
        );
      }
      return sesion;
    });
  }

  /// Cierra la sesión. Está prohibido el borrado: el estado pasa a CLOSED.
  Future<Result<void>> cerrarSesion({required String sesionId}) {
    return Result.guard(() async {
      await _api.patch(
        '$_ruta/sesiones/$sesionId/cerrar',
        token: _token(),
        cuerpo: const {},
      );
    });
  }

  /// Registra la asistencia del estudiante. La RLS valida el código en la base;
  /// esta llamada sólo espera la respuesta.
  Future<Result<void>> marcar({required String sesionId, required String codigo}) {
    return Result.guard(() async {
      await _api.post(
        '$_ruta/marcar',
        token: _token(),
        cuerpo: {'sesionId': sesionId, 'codigo': codigo},
      );
    });
  }

  /// Las marcas de una sesión, en orden, para la recarga o el informe final.
  Future<Result<List<MarcaAsistencia>>> marcas({required String sesionId}) {
    return Result.guard(() async {
      final resp = await _api.get(
        '$_ruta/sesiones/$sesionId/marcas',
        token: _token(),
      );
      final lista = (resp['marcas'] as List? ?? [])
          .map((m) => MarcaAsistencia.deJson(m as Map<String, dynamic>))
          .toList();
      return lista;
    });
  }

  /**
   * En vivo: el canal WS de una sesión.
   *
   * **Unidireccional por diseño** (servidor a cliente): el estudiante marca por
   * REST y aquí sólo se empuja. El docente no hace polling: la pantalla pinta la
   * marca al llegar el evento.
   */
  Stream<EventoAsistencia> enVivo({required String sesionId}) {
    // En web lo que portan los WebSocket NO tiene encabezados de protocolo
    // personalizados: el JWT va en la query, que es lo que el servidor lee.
    final base = AppConfig.apiBaseUrl.replaceFirst(RegExp('^http', caseSensitive: false), 'ws');
    final uri = Uri.parse(
      '$base$_ruta/rt?sesion=$sesionId&token=${Uri.encodeQueryComponent(_token())}',
    );
    final canal = WebSocketChannel.connect(uri);
    return canal.stream.map((evento) => EventoAsistencia.deJson(
          jsonDecode(evento as String) as Map<String, dynamic>,
        ));
  }

  /**
   * Deriva el código QR de la sesión para la ventana ACTUAL.
   *
   * **La misma regla que la base.** si la pantalla del docente y la validación
   * RLS discreparan, el QR no aceptaría a nadie. Shaa256 del secreto, sesión y
   * ventana actual; primeros 8 caracteres hex → entero → % 1 000 000 → seis
   * dígitos.
   */
  static CodigoQr codigoQr({
    required String qrSecret,
    required String sesionId,
    required int ventanaSeg,
    DateTime? ahora,
  }) {
    final instante = (ahora ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final ventana = instante ~/ ventanaSeg;

    final digest = sha256.convert(utf8.encode('$qrSecret$sesionId$ventana'));
    final hex8 = digest.toString().substring(0, 8);
    // Conversión hex→int, misma rosca que la base.
    final valor = int.parse(hex8, radix: 16) % 1000000;

    final restante = ventanaSeg - (instante % ventanaSeg);
    return CodigoQr(
      codigo: valor.toString().padLeft(6, '0'),
      venceEnSegundos: restante,
    );
  }
}
