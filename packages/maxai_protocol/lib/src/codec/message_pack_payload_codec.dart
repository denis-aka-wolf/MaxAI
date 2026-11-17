import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart';

import 'payload_codec.dart';

/// MessagePack Extension, который протокол пока не умеет интерпретировать.
final class MessagePackExtension {
  MessagePackExtension({
    required this.type,
    required Uint8List data,
  }) : data = Uint8List.fromList(data);

  final int type;
  final Uint8List data;

  @override
  String toString() =>
      'MessagePackExtension(type: $type, dataLength: ${data.length})';
}

/// Декодер расширений MAX.
///
/// В ответах MAX extension type 1 содержит ещё одно MessagePack-значение.
/// Например, числовые expiresAt, pollingInterval и ttl обёрнуты именно так.
final class MaxMessagePackExtDecoder extends ExtDecoder {
  MaxMessagePackExtDecoder();

  @override
  Object? decodeObject(int extType, Uint8List data) {
    if (extType == 1) {
      if (data.isEmpty) {
        throw const FormatException(
          'MAX MessagePack extension type 1 has an empty payload.',
        );
      }
      return deserialize(data, extDecoder: this);
    }

    // Не теряем неизвестные расширения. Они сохраняются как opaque value,
    // чтобы будущие типы MAX не превращались незаметно в null.
    return MessagePackExtension(type: extType, data: data);
  }
}

/// MessagePack codec с поддержкой вложенного MAX extension type 1.
final class MessagePackPayloadCodec implements PayloadCodec {
  const MessagePackPayloadCodec();

  static final MaxMessagePackExtDecoder _extDecoder =
      MaxMessagePackExtDecoder();

  @override
  Uint8List encode(Object? payload) => serialize(payload);

  @override
  Object? decode(Uint8List bytes) => bytes.isEmpty
      ? null
      : deserialize(bytes, extDecoder: _extDecoder);
}
