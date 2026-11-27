import 'dart:async';

import '../connection/protocol_command.dart';
import '../connection/protocol_connection.dart';
import '../connection/protocol_connection_state.dart';
import 'handshake_response.dart';
import 'max_user_agent.dart';
import 'session_init_payload.dart';
import 'session_state.dart';

typedef SessionStateHandler = void Function(SessionState state);

/// Управляет handshake MAX поверх уже установленного ProtocolConnection.
///
/// Не выполняет авторизацию и не сохраняет токены: это отдельный следующий слой.
final class SessionManager {
  SessionManager({
    required this.connection,
    this.requestTimeout = const Duration(seconds: 20),
    this.onStateChanged,
  }) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive.',
      );
    }
  }

  static const int sessionInitOpcode = 6;

  final ProtocolConnection connection;
  final Duration requestTimeout;
  final SessionStateHandler? onStateChanged;

  SessionState _state = SessionState.idle;
  HandshakeResponse? _handshakeResponse;
  Future<HandshakeResponse>? _startFuture;

  SessionState get state => _state;
  HandshakeResponse? get handshakeResponse => _handshakeResponse;
  bool get isReady => _state == SessionState.ready;

  void _setState(SessionState value) {
    if (_state == value) return;
    _state = value;
    onStateChanged?.call(value);
  }

  Future<HandshakeResponse> startMobile({
    required String mtInstanceId,
    required MaxUserAgent userAgent,
    required String deviceId,
    int? clientSessionId,
  }) {
    final payload = SessionInitPayload.mobile(
      mtInstanceId: mtInstanceId,
      userAgent: userAgent,
      deviceId: deviceId,
      clientSessionId: clientSessionId,
    );
    return _start(payload);
  }

  Future<HandshakeResponse> startWeb({
    required MaxUserAgent userAgent,
    required String deviceId,
  }) {
    final payload = SessionInitPayload.web(
      userAgent: userAgent,
      deviceId: deviceId,
    );
    return _start(payload);
  }

  Future<HandshakeResponse> _start(Map<String, Object?> payload) {
    if (_state == SessionState.closed) {
      return Future<HandshakeResponse>.error(
        StateError(
            'SessionManager is closed. Call reset() before starting again.'),
      );
    }
    if (_state == SessionState.ready && _handshakeResponse != null) {
      return Future<HandshakeResponse>.value(_handshakeResponse!);
    }
    final active = _startFuture;
    if (active != null) return active;

    if (connection.state != ProtocolConnectionState.connected ||
        !connection.isConnected) {
      return Future<HandshakeResponse>.error(
        StateError('ProtocolConnection must be connected before SESSION_INIT.'),
      );
    }

    final future = _performHandshake(payload);
    _startFuture = future;
    return future;
  }

  Future<HandshakeResponse> _performHandshake(
    Map<String, Object?> payload,
  ) async {
    _setState(SessionState.initializing);
    try {
      final response = await connection.request(
        opcode: sessionInitOpcode,
        payload: payload,
        timeout: requestTimeout,
      );

      if (response.commandType == ProtocolCommand.error) {
        throw SessionHandshakeException(
          'MAX returned ERROR for SESSION_INIT.',
          response.payload,
        );
      }
      if (response.commandType != ProtocolCommand.response) {
        throw SessionHandshakeException(
          'Unexpected command for SESSION_INIT: ${response.command}.',
          response.payload,
        );
      }
      if (response.opcode != sessionInitOpcode) {
        throw SessionHandshakeException(
          'Unexpected opcode for SESSION_INIT response: ${response.opcode}.',
          response.payload,
        );
      }

      final result = HandshakeResponse.fromPayload(response.payload);
      _handshakeResponse = result;
      _setState(SessionState.ready);
      return result;
    } catch (_) {
      _handshakeResponse = null;
      _setState(SessionState.failed);
      rethrow;
    } finally {
      _startFuture = null;
    }
  }

  void reset() {
    if (_state == SessionState.initializing) {
      throw StateError('Cannot reset while SESSION_INIT is in progress.');
    }
    _handshakeResponse = null;
    _startFuture = null;
    _setState(SessionState.idle);
  }

  void close() {
    if (_state == SessionState.initializing) {
      throw StateError(
        'Cannot close SessionManager while SESSION_INIT is in progress.',
      );
    }
    _handshakeResponse = null;
    _startFuture = null;
    _setState(SessionState.closed);
  }
}

final class SessionHandshakeException implements Exception {
  const SessionHandshakeException(this.message, this.payload);

  final String message;
  final Object? payload;

  @override
  String toString() => 'SessionHandshakeException: $message';
}
