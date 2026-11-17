import 'dart:typed_data';

import 'protocol_frame.dart';
import 'tcp_frame_codec.dart';

/// Собирает полные frame из произвольно фрагментированного TCP byte stream.
///
/// Поддерживает несколько frame в одном chunk и один frame, пришедший
/// несколькими chunk. Буфер ограничен максимально допустимым frame size.
final class TcpFrameStreamDecoder {
  TcpFrameStreamDecoder(this.codec);

  final TcpFrameCodec codec;
  Uint8List _buffer = Uint8List(0);

  int get bufferedBytes => _buffer.length;

  List<ProtocolFrame> add(List<int> chunk) {
    if (chunk.isEmpty) return const [];
    final incoming = Uint8List.fromList(chunk);
    final merged = Uint8List(_buffer.length + incoming.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + incoming.length, incoming);
    _buffer = merged;

    final frames = <ProtocolFrame>[];
    while (_buffer.length >= TcpFrameCodec.headerLength) {
      final header = ByteData.sublistView(_buffer);
      final packedLength = header.getUint32(6, Endian.big);
      final payloadLength = packedLength & 0xFFFFFF;
      final frameLength = TcpFrameCodec.headerLength + payloadLength;
      if (_buffer.length < frameLength) break;

      final frameBytes = Uint8List.fromList(_buffer.sublist(0, frameLength));
      final frame = codec.decode(frameBytes);
      if (frame == null) {
        throw StateError('Complete frame unexpectedly decoded as incomplete.');
      }
      frames.add(frame);
      _buffer = Uint8List.fromList(_buffer.sublist(frameLength));
    }
    return frames;
  }

  void reset() {
    _buffer = Uint8List(0);
  }
}
