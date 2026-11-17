import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../frame/protocol_frame.dart';
import '../frame/tcp_frame_codec.dart';
import '../frame/tcp_frame_stream_decoder.dart';
import '../requests/pending_requests.dart';
import '../sequence/sequence_manager.dart';
import '../transport/protocol_transport.dart';
import 'decoded_protocol_frame.dart';
import 'protocol_command.dart';
import 'protocol_connection_state.dart';

typedef ProtocolFrameHandler = FutureOr<void> Function(
  DecodedProtocolFrame frame,
);

/// Связывает транспорт, frame codec, sequence и ожидающие запросы.
///
/// Command значения (REQUEST=0, RESPONSE=1, EVENT=2, ERROR=3)
/// сверены с enum Command исследованной версии PyMax.
final class ProtocolConnection {
  ProtocolConnection({
    required this.transport,
    required this.codec,
    SequenceManager? sequenceManager,
    this.onEvent,
    this.onFrame,
    this.onStateChanged,
  })  : sequenceManager = sequenceManager ?? SequenceManager(),
        _streamDecoder = TcpFrameStreamDecoder(codec);

  final ProtocolTransport transport;
  final TcpFrameCodec codec;
  final SequenceManager sequenceManager;
  final ProtocolFrameHandler? onEvent;

  /// Вызывается для каждого корректно декодированного входящего frame.
  final ProtocolFrameHandler? onFrame;

  final void Function(ProtocolConnectionState state)? onStateChanged;

  final PendingRequests<DecodedProtocolFrame> _pending =
      PendingRequests<DecodedProtocolFrame>();
  final TcpFrameStreamDecoder _streamDecoder;

  StreamSubscription<dynamic>? _subscription;
  ProtocolConnectionState _state = ProtocolConnectionState.disconnected;
  Future<void>? _closeFuture;

  ProtocolConnectionState get state => _state;
  bool get isConnected =>
      _state == ProtocolConnectionState.connected && transport.isConnected;
  int get pendingRequestCount => _pending.length;

  void _setState(ProtocolConnectionState value) {
    if (_state == value) return;
    _state = value;
    onStateChanged?.call(value);
  }

  Future<void> connect() async {
    if (_state == ProtocolConnectionState.connected && transport.isConnected) {
      return;
    }
    if (_state == ProtocolConnectionState.connecting) {
      throw StateError('Connection is already connecting.');
    }
    if (_state == ProtocolConnectionState.closing) {
      throw StateError('Connection is closing.');
    }

    _closeFuture = null;
    _setState(ProtocolConnectionState.connecting);
    _streamDecoder.reset();

    try {
      await transport.connect();
      _subscription = transport.stream.listen(
        _handleChunk,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: false,
      );
      _setState(ProtocolConnectionState.connected);
    } catch (_) {
      _setState(ProtocolConnectionState.failed);
      await transport.close();
      rethrow;
    }
  }

  /// Отправляет frame без ожидания ответа. Обычно используется для событий,
  /// ping и других однонаправленных команд.
  Future<void> sendFrame(ProtocolFrame frame) async {
    _ensureConnected();
    final bytes = codec.encodeFrame(frame);
    await transport.send(bytes);
  }

  /// Отправляет REQUEST и ожидает RESPONSE или ERROR с тем же sequence.
  ///
  /// При timeout запрос удаляется из реестра. Повторная отправка здесь
  /// намеренно не выполняется: для изменяющих операций это может создать дубль.
  Future<DecodedProtocolFrame> request({
    required int opcode,
    required Object? payload,
    int flags = 0,
    Duration? timeout,
  }) async {
    _ensureConnected();
    final sequence = _allocateSequence();
    final bytes = codec.encode(
      command: ProtocolCommand.request.value,
      sequence: sequence,
      opcode: opcode,
      payload: payload,
      flags: flags,
    );
    final responseFuture = _pending.register(sequence, timeout: timeout);

    // Подписываемся на ошибку сразу: timeout/close может наступить,
    // пока transport.send ещё ожидает завершения.
    unawaited(
      responseFuture.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );

    try {
      await transport.send(bytes);
    } catch (error, stackTrace) {
      _pending.fail(sequence, error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }

    return responseFuture;
  }

  int _allocateSequence() {
    for (var attempt = 0; attempt < 0x10000; attempt++) {
      final candidate = sequenceManager.next();
      if (!_pending.contains(candidate)) return candidate;
    }
    throw StateError('All 16-bit sequence numbers are currently in use.');
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw StateError('Protocol connection is not connected.');
    }
  }

  void _handleChunk(dynamic data) {
    if (_state != ProtocolConnectionState.connected) return;

    try {
      final Uint8List bytes;
      if (data is Uint8List) {
        bytes = data;
      } else if (data is List<int>) {
        bytes = Uint8List.fromList(data);
      } else if (data is String) {
        // Поведение соответствует TcpProtocol.decode в PyMax.
        bytes = Uint8List.fromList(utf8.encode(data));
      } else {
        throw FormatException(
          'Unsupported transport message type: ${data.runtimeType}.',
        );
      }

      final frames = _streamDecoder.add(bytes);
      for (final frame in frames) {
        final decoded = DecodedProtocolFrame(
          frame: frame,
          payload: codec.decodePayload(frame),
        );
        _dispatch(decoded);
      }
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _dispatch(DecodedProtocolFrame decoded) {
    final command = decoded.commandType;
    if ((command == ProtocolCommand.response ||
            command == ProtocolCommand.error) &&
        _pending.resolve(decoded.sequence, decoded)) {
      // Ответ сопоставлен с ожидающим запросом. ERROR возвращается вызывающему
      // коду как frame, чтобы слой API мог разобрать payload ошибки.
    }

    final frameHandler = onFrame;
    if (frameHandler != null) {
      Future<void>.sync(() => frameHandler(decoded)).catchError((Object _) {
        // Ошибка пользовательского обработчика не должна ронять transport.
      });
    }

    if (command == ProtocolCommand.event) {
      final eventHandler = onEvent;
      if (eventHandler != null) {
        Future<void>.sync(() => eventHandler(decoded)).catchError((Object _) {
          // Ошибка обработчика события изолирована от receive loop.
        });
      }
    }
  }

  void _handleStreamError(Object error, [StackTrace? stackTrace]) {
    _fail(error, stackTrace ?? StackTrace.current);
  }

  void _handleStreamDone() {
    if (_state == ProtocolConnectionState.closing ||
        _state == ProtocolConnectionState.closed) {
      return;
    }
    _pending.cancelAll(StateError('Transport stream has been closed.'));
    _setState(ProtocolConnectionState.failed);
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_state == ProtocolConnectionState.closed ||
        _state == ProtocolConnectionState.closing ||
        _state == ProtocolConnectionState.failed) {
      return;
    }
    _pending.cancelAll(error);
    _setState(ProtocolConnectionState.failed);
    unawaited(_subscription?.cancel());
    unawaited(transport.close());
  }

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;

    _closeFuture = _close();
    return _closeFuture!;
  }

  Future<void> _close() async {
    if (_state == ProtocolConnectionState.closed ||
        _state == ProtocolConnectionState.disconnected) {
      _setState(ProtocolConnectionState.closed);
      _pending.cancelAll(StateError('Connection closed.'));
      return;
    }

    _setState(ProtocolConnectionState.closing);
    _pending.cancelAll(StateError('Connection closed.'));

    try {
      await _subscription?.cancel();
      _subscription = null;
      await transport.close();
      _streamDecoder.reset();
      _setState(ProtocolConnectionState.closed);
    } catch (_) {
      _setState(ProtocolConnectionState.failed);
      rethrow;
    }
  }
}
