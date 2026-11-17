import 'dart:typed_data';
import 'package:msgpack_dart/msgpack_dart.dart';
import 'payload_codec.dart';

/// MessagePack codec. Не предполагает схему конкретного opcode.
final class MessagePackPayloadCodec implements PayloadCodec {
  const MessagePackPayloadCodec();
  @override
  Uint8List encode(Object? payload) => serialize(payload);
  @override
  Object? decode(Uint8List bytes) => bytes.isEmpty ? null : deserialize(bytes);
}
