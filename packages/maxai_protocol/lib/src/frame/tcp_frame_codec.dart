import 'dart:typed_data';

import '../codec/payload_codec.dart';
import 'protocol_frame.dart';

/// Кодек TCP frame из PyMax: struct >BBHHI.
final class TcpFrameCodec {
  const TcpFrameCodec({required this.payloadCodec, this.version = 10});

  static const int headerLength = 10;
  static const int _leadingIntsFlag = 0x01;
  static const int _leadingIntsCount = 2;

  final PayloadCodec payloadCodec;
  final int version;

  Uint8List encode({
    required int command,
    required int sequence,
    required int opcode,
    required Object? payload,
    int flags = 0,
  }) {
    final payloadBytes = payloadCodec.encode(payload);
    return encodeFrame(
      ProtocolFrame(
        version: version,
        command: command,
        sequence: sequence,
        opcode: opcode,
        flags: flags,
        payload: payloadBytes,
      ),
    );
  }

  /// Кодирует frame, payload которого уже представлен сериализованными байтами.
  Uint8List encodeFrame(ProtocolFrame frame) {
    frame.validate();
    final result = Uint8List(headerLength + frame.payload.length);
    final data = ByteData.sublistView(result);
    data.setUint8(0, frame.version);
    data.setUint8(1, frame.command);
    data.setUint16(2, frame.sequence, Endian.big);
    data.setUint16(4, frame.opcode, Endian.big);
    data.setUint32(
      6,
      (frame.flags << 24) | frame.payload.length,
      Endian.big,
    );
    result.setRange(headerLength, result.length, frame.payload);
    return result;
  }

  /// null означает, что буфер пока содержит неполный frame.
  /// Метод ожидает ровно один frame, без хвостовых байтов.
  ProtocolFrame? decode(Uint8List bytes) {
    if (bytes.length < headerLength) return null;
    final data = ByteData.sublistView(bytes);
    final packedLength = data.getUint32(6, Endian.big);
    final payloadLength = packedLength & 0xFFFFFF;
    final totalLength = headerLength + payloadLength;
    if (bytes.length < totalLength) return null;
    if (bytes.length > totalLength) {
      throw FormatException('Buffer contains trailing bytes.');
    }
    return ProtocolFrame(
      version: data.getUint8(0),
      command: data.getUint8(1),
      sequence: data.getUint16(2, Endian.big),
      opcode: data.getUint16(4, Endian.big),
      flags: (packedLength >> 24) & 0xFF,
      payload: Uint8List.fromList(bytes.sublist(headerLength, totalLength)),
    );
  }

  /// Декодирует payload с учётом служебного префикса MAX.
  ///
  /// При установленном flags bit 0 сервер добавляет перед MessagePack
  /// объектом два MessagePack integer. Например, SESSION_INIT содержит
  /// префикс F0 4B, то есть (-16, 75). Эти числа не являются payload API.
  Object? decodePayload(ProtocolFrame frame) {
    if ((frame.flags & _leadingIntsFlag) == 0) {
      return payloadCodec.decode(frame.payload);
    }

    final offset = _skipLeadingIntegers(
      frame.payload,
      count: _leadingIntsCount,
    );
    if (offset == frame.payload.length) {
      throw const FormatException(
        'MAX frame contains leading integers but no MessagePack payload.',
      );
    }

    return payloadCodec.decode(
      Uint8List.sublistView(frame.payload, offset),
    );
  }

  /// Возвращает позицию сразу после указанного количества MessagePack int.
  int _skipLeadingIntegers(Uint8List bytes, {required int count}) {
    var offset = 0;
    for (var index = 0; index < count; index++) {
      if (offset >= bytes.length) {
        throw FormatException(
          'MAX frame has fewer than $count leading integers.',
        );
      }
      offset = _skipInteger(bytes, offset);
    }
    return offset;
  }

  int _skipInteger(Uint8List bytes, int offset) {
    final marker = bytes[offset];

    // Positive fixint и negative fixint.
    if (marker <= 0x7F || marker >= 0xE0) {
      return offset + 1;
    }

    switch (marker) {
      case 0xCC: // uint 8
      case 0xD0: // int 8
        return _requireBytes(bytes, offset, 2);
      case 0xCD: // uint 16
      case 0xD1: // int 16
        return _requireBytes(bytes, offset, 3);
      case 0xCE: // uint 32
      case 0xD2: // int 32
        return _requireBytes(bytes, offset, 5);
      case 0xCF: // uint 64
      case 0xD3: // int 64
        return _requireBytes(bytes, offset, 9);
      default:
        throw FormatException(
          'MAX leading value is not a MessagePack integer: '
          '0x${marker.toRadixString(16).padLeft(2, '0')}.',
        );
    }
  }

  int _requireBytes(Uint8List bytes, int offset, int encodedLength) {
    if (bytes.length - offset < encodedLength) {
      throw const FormatException(
        'Truncated MessagePack integer in MAX leading prefix.',
      );
    }
    return offset + encodedLength;
  }
}
