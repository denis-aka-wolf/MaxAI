import 'dart:typed_data';

/// Минимальный контракт транспорта для ProtocolConnection.
abstract interface class ProtocolTransport {
  Stream<dynamic> get stream;
  bool get isConnected;

  Future<void> connect();
  Future<void> send(Uint8List bytes);
  Future<void> close([int? code, String? reason]);
}
