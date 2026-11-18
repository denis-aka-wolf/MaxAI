import 'dart:io';
import 'dart:typed_data';

import 'protocol_transport.dart';

/// TLS/TCP транспорт MAX API.
///
/// В отличие от WebSocketTransport передаёт байты непосредственно в TCP
/// stream. Разделение и склейка входящих TCP-пакетов выполняются
/// TcpFrameStreamDecoder внутри ProtocolConnection.
final class TcpSocketTransport implements ProtocolTransport {
  TcpSocketTransport({
    this.host = 'api2.oneme.ru',
    this.port = 443,
    this.connectTimeout = const Duration(seconds: 20),
    this.securityContext,
  }) {
    if (host.trim().isEmpty) {
      throw ArgumentError.value(host, 'host', 'Must not be empty.');
    }
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError.value(
        connectTimeout,
        'connectTimeout',
        'Must be positive.',
      );
    }
  }

  final String host;
  final int port;
  final Duration connectTimeout;
  final SecurityContext? securityContext;

  SecureSocket? _socket;

  @override
  bool get isConnected => _socket != null;

  @override
  Stream<dynamic> get stream {
    final socket = _socket;
    if (socket == null) {
      throw StateError('TCP/TLS socket is not connected.');
    }
    return socket;
  }

  @override
  Future<void> connect() async {
    if (isConnected) return;
    _socket = await SecureSocket.connect(
      host,
      port,
      context: securityContext,
      timeout: connectTimeout,
    );
  }

  @override
  Future<void> send(Uint8List bytes) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Cannot send: TCP/TLS socket is not connected.');
    }
    socket.add(bytes);
    await socket.flush();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    await socket.close();
  }
}
