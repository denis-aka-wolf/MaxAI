import 'dart:typed_data';

import '../codec/payload_codec.dart';
import 'protocol_frame.dart';

/// Кодек TCP frame из PyMax: struct >BBHHI.
final class TcpFrameCodec {
  const TcpFrameCodec({required this.payloadCodec, this.version = 10});

  static const int headerLength = 10;
  static const int _maxDecompressedPayload = 5 * 1024 * 1024;
  static const int _zstdFlag = 0xFF;

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

  /// MAX: flags=0 означает отсутствие сжатия, flags=1..254 означает LZ4,
  /// flags=255 означает Zstandard.
  Object? decodePayload(ProtocolFrame frame) {
    final payloadBytes = switch (frame.flags) {
      0 => frame.payload,
      _ when frame.flags == _zstdFlag => throw const UnsupportedError(
          'Zstandard-compressed MAX payload is not supported yet.',
        ),
      _ => _decompressLz4Block(frame.payload),
    };
    return payloadCodec.decode(payloadBytes);
  }

  /// Декодирует raw LZ4 block без дополнительного frame-контейнера.
  Uint8List _decompressLz4Block(Uint8List source) {
    final output = <int>[];
    var position = 0;

    while (position < source.length) {
      final token = source[position++];
      var literalLength = token >> 4;

      if (literalLength == 15) {
        while (true) {
          if (position >= source.length) {
            throw const FormatException('Truncated LZ4 literal length extension.');
          }
          final extension = source[position++];
          literalLength += extension;
          if (extension != 255) break;
        }
      }

      if (literalLength > source.length - position) {
        throw const FormatException('LZ4 literal length exceeds input.');
      }
      if (output.length + literalLength > _maxDecompressedPayload) {
        throw const FormatException('LZ4 output exceeds the 5 MiB limit.');
      }

      output.addAll(source.sublist(position, position + literalLength));
      position += literalLength;

      if (position == source.length) break;

      if (source.length - position < 2) {
        throw const FormatException('Truncated LZ4 match offset.');
      }
      final offset = source[position] | (source[position + 1] << 8);
      position += 2;

      if (offset == 0 || offset > output.length) {
        throw const FormatException('Invalid LZ4 match offset.');
      }

      var matchLength = (token & 0x0F) + 4;
      if ((token & 0x0F) == 15) {
        while (true) {
          if (position >= source.length) {
            throw const FormatException('Truncated LZ4 match length extension.');
          }
          final extension = source[position++];
          matchLength += extension;
          if (extension != 255) break;
        }
      }

      if (output.length + matchLength > _maxDecompressedPayload) {
        throw const FormatException('LZ4 output exceeds the 5 MiB limit.');
      }

      for (var index = 0; index < matchLength; index++) {
        output.add(output[output.length - offset]);
      }
    }

    return Uint8List.fromList(output);
  }
}
