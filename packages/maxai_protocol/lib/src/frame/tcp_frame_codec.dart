import 'dart:typed_data';
import '../codec/payload_codec.dart';
import 'protocol_frame.dart';

/// Кодек header из PyMax TcpPacketFramer: struct >BBHHI.
final class TcpFrameCodec {
  const TcpFrameCodec({required this.payloadCodec, this.version = 10});
  static const int headerLength = 10;
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
    final frame = ProtocolFrame(
      version: version, command: command, sequence: sequence,
      opcode: opcode, flags: flags, payload: payloadBytes,
    )..validate();

    final result = Uint8List(headerLength + payloadBytes.length);
    final data = ByteData.sublistView(result);
    data.setUint8(0, frame.version);
    data.setUint8(1, frame.command);
    data.setUint16(2, frame.sequence, Endian.big);
    data.setUint16(4, frame.opcode, Endian.big);
    data.setUint32(6, (frame.flags << 24) | frame.payload.length, Endian.big);
    result.setRange(headerLength, result.length, payloadBytes);
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

  Object? decodePayload(ProtocolFrame frame) => payloadCodec.decode(frame.payload);
}
