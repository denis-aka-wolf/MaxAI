import 'dart:io';
import 'dart:typed_data';

/// Транспортная оболочка WebSocket.
///
/// Не содержит логики MAX, frame или MessagePack. Каждый вызов send
/// передаёт отдельное бинарное WebSocket message. Это поведение нужно
/// сверить с актуальным сервером MAX перед реальной авторизацией.
final class WebSocketTransport {
  WebSocketTransport({
    required this.uri,
    this.headers,
    this.protocols,
  });

  final Uri uri;
  final Map<String, dynamic>? headers;
  final Iterable<String>? protocols;

  WebSocket? _socket;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  Stream<dynamic> get stream {
    final socket = _socket;
    if (socket == null) {
      throw StateError('WebSocket is not connected.');
    }
    return socket;
  }

  Future<void> connect() async {
    if (isConnected) return;
    _socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      protocols: protocols,
    );
  }

  void send(Uint8List bytes) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Cannot send: WebSocket is not open.');
    }
    socket.add(bytes);
  }

  Future<void> close([int? code, String? reason]) async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    await socket.close(code, reason);
  }
}
