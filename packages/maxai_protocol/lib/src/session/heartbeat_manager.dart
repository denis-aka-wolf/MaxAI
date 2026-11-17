import 'dart:async';

import '../connection/protocol_command.dart';
import '../connection/protocol_connection.dart';
import '../connection/protocol_connection_state.dart';
import 'heartbeat_state.dart';

typedef HeartbeatFailureHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Периодически отправляет MAX PING (opcode 1).
///
/// Первый ping отправляется сразу после start(), последующие — с заданным
/// интервалом после получения успешного ответа. Параллельные ping не создаются.
final class HeartbeatManager {
  HeartbeatManager({
    required this.connection,
    this.interval = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 20),
    this.interactive = true,
    this.onFailure,
    this.onStateChanged,
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive.');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive.',
      );
    }
  }

  static const int pingOpcode = 1;

  final ProtocolConnection connection;
  final Duration interval;
  final Duration requestTimeout;
  final bool interactive;
  final HeartbeatFailureHandler? onFailure;
  final void Function(HeartbeatState state)? onStateChanged;

  HeartbeatState _state = HeartbeatState.stopped;
  bool _running = false;
  Future<void>? _loopFuture;
  Timer? _waitTimer;
  Completer<void>? _waitCompleter;
  DateTime? _lastSuccessAt;

  HeartbeatState get state => _state;
  bool get isRunning => _running;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  void _setState(HeartbeatState value) {
    if (_state == value) return;
    _state = value;
    onStateChanged?.call(value);
  }

  Future<void> start() async {
    if (_running) return;
    if (connection.state != ProtocolConnectionState.connected ||
        !connection.isConnected) {
      throw StateError('ProtocolConnection must be connected before heartbeat.');
    }

    _running = true;
    _setState(HeartbeatState.running);
    final loop = _runLoop();
    _loopFuture = loop;
    unawaited(loop);
  }

  Future<void> _runLoop() async {
    while (_running) {
      try {
        final response = await connection.request(
          opcode: pingOpcode,
          payload: <String, Object?>{'interactive': interactive},
          timeout: requestTimeout,
        );

        if (response.commandType == ProtocolCommand.error) {
          throw HeartbeatException(
            'MAX returned ERROR for PING.',
            response.payload,
          );
        }
        if (response.commandType != ProtocolCommand.response ||
            response.opcode != pingOpcode) {
          throw HeartbeatException(
            'Unexpected PING response command/opcode.',
            response.payload,
          );
        }

        _lastSuccessAt = DateTime.now();
      } catch (error, stackTrace) {
        _running = false;
        _setState(HeartbeatState.failed);
        try {
          onFailure?.call(error, stackTrace);
        } catch (_) {
          // Ошибка внешнего обработчика не должна создавать unhandled error.
        }
        return;
      }

      if (!_running) return;
      _waitCompleter = Completer<void>();
      _waitTimer = Timer(interval, () {
        final completer = _waitCompleter;
        _waitCompleter = null;
        _waitTimer = null;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      });
      await _waitCompleter!.future;
    }
  }

  Future<void> stop() async {
    if (!_running && _loopFuture == null) {
      _setState(HeartbeatState.stopped);
      return;
    }

    _running = false;
    _waitTimer?.cancel();
    _waitTimer = null;
    final completer = _waitCompleter;
    _waitCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    final loop = _loopFuture;
    _loopFuture = null;
    if (loop != null) await loop;

    if (_state != HeartbeatState.failed) {
      _setState(HeartbeatState.stopped);
    }
  }
}

final class HeartbeatException implements Exception {
  const HeartbeatException(this.message, this.payload);

  final String message;
  final Object? payload;

  @override
  String toString() => 'HeartbeatException: $message';
}
