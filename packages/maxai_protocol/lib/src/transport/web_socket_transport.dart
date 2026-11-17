import 'dart:io';
import 'dart:typed_data';

import 'protocol_transport.dart';

/// WebSocket транспортная оболочка без логики MAX, frame или MessagePack.
final class WebSocketTransport implements ProtocolTransport {
  WebSocketTransport({
    required this.uri,
    this.headers,
    this.protocols,
  });

  final Uri uri;
  final Map<String, dynamic>? headers;
  final Iterable<String>? protocols;

  WebSocket? _socket;

  @override
  bool get isConnected => _socket?.readyState == WebSocket.open;

  @override
  Stream<dynamic> get stream {
    final socket = _socket;
    if (socket == null) {
      throw StateError('WebSocket is not connected.');
    }
    return socket;
  }

  @override
  Future<void> connect() async {
    if (isConnected) return;
    _socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
      protocols: protocols,
    );
  }

  @override
  Future<void> send(Uint8List bytes) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Cannot send: WebSocket is not open.');
    }
    socket.add(bytes);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    await socket.close(code, reason);
  }
}
