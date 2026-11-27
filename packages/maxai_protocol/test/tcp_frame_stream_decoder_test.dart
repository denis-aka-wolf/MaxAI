import 'dart:typed_data';

import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

final class _BytesCodec implements PayloadCodec {
  const _BytesCodec();
  @override
  Uint8List encode(Object? payload) =>
      Uint8List.fromList(payload! as List<int>);
  @override
  Object? decode(Uint8List bytes) => bytes;
}

void main() {
  const codec = TcpFrameCodec(payloadCodec: _BytesCodec());
  test('reassembles a frame split across chunks', () {
    final bytes = codec.encode(
      command: 1,
      sequence: 12,
      opcode: 34,
      payload: <int>[1, 2, 3, 4],
    );
    final decoder = TcpFrameStreamDecoder(codec);
    expect(decoder.add(bytes.sublist(0, 4)), isEmpty);
    expect(decoder.bufferedBytes, 4);
    expect(decoder.add(bytes.sublist(4, 12)), isEmpty);
    final frames = decoder.add(bytes.sublist(12));
    expect(frames, hasLength(1));
    expect(frames.single.sequence, 12);
    expect(frames.single.payload, <int>[1, 2, 3, 4]);
    expect(decoder.bufferedBytes, 0);
  });

  test('decodes multiple frames from one chunk', () {
    final first = codec.encode(
      command: 1,
      sequence: 1,
      opcode: 10,
      payload: <int>[1],
    );
    final second = codec.encode(
      command: 1,
      sequence: 2,
      opcode: 11,
      payload: <int>[2, 3],
    );
    final decoder = TcpFrameStreamDecoder(codec);
    final frames = decoder.add(Uint8List.fromList([...first, ...second]));
    expect(frames.map((frame) => frame.sequence), <int>[1, 2]);
    expect(decoder.bufferedBytes, 0);
  });
}
