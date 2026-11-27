import 'dart:typed_data';
import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

final class _RawPayloadCodec implements PayloadCodec {
  const _RawPayloadCodec();
  @override
  Uint8List encode(Object? payload) =>
      Uint8List.fromList(payload! as List<int>);
  @override
  Object? decode(Uint8List bytes) => bytes;
}

void main() {
  const payloadCodec = _RawPayloadCodec();
  const codec = TcpFrameCodec(payloadCodec: payloadCodec);

  test('encodes big-endian header and flags/length word', () {
    final bytes = codec.encode(
      command: 1,
      sequence: 0x1234,
      opcode: 0x5678,
      payload: <int>[0xAA, 0xBB, 0xCC],
      flags: 2,
    );
    expect(
        bytes.sublist(0, 10), <int>[10, 1, 0x12, 0x34, 0x56, 0x78, 2, 0, 0, 3]);
    expect(bytes.sublist(10), <int>[0xAA, 0xBB, 0xCC]);
  });

  test('decodes metadata and payload', () {
    final bytes = codec.encode(
      command: 2,
      sequence: 65535,
      opcode: 19,
      payload: <int>[1, 2],
      flags: 7,
    );
    final frame = codec.decode(bytes)!;
    expect(frame.version, 10);
    expect(frame.command, 2);
    expect(frame.sequence, 65535);
    expect(frame.opcode, 19);
    expect(frame.flags, 7);
    expect(frame.payload, <int>[1, 2]);
  });

  test('decompresses MAX LZ4 payload with literal sequence', () {
    final bytes = codec.encode(
      command: 1,
      sequence: 0,
      opcode: 6,
      payload: <int>[0x50, 0x68, 0x65, 0x6C, 0x6C, 0x6F],
      flags: 1,
    );

    final frame = codec.decode(bytes)!;
    expect(codec.decodePayload(frame), <int>[0x68, 0x65, 0x6C, 0x6C, 0x6F]);
  });

  test('decompresses MAX LZ4 match sequence', () {
    final bytes = codec.encode(
      command: 1,
      sequence: 0,
      opcode: 6,
      payload: <int>[0x40, 0x61, 0x62, 0x63, 0x64, 0x04, 0x00],
      flags: 1,
    );

    final frame = codec.decode(bytes)!;
    expect(
      codec.decodePayload(frame),
      <int>[0x61, 0x62, 0x63, 0x64, 0x61, 0x62, 0x63, 0x64],
    );
  });

  test('rejects malformed MAX LZ4 payload', () {
    final bytes = codec.encode(
      command: 1,
      sequence: 0,
      opcode: 6,
      payload: <int>[0x50, 0x61],
      flags: 1,
    );

    final frame = codec.decode(bytes)!;
    expect(() => codec.decodePayload(frame), throwsFormatException);
  });

  test('returns null for incomplete header or payload', () {
    expect(codec.decode(Uint8List(9)), isNull);
    final full = codec
        .encode(command: 1, sequence: 0, opcode: 1, payload: <int>[1, 2, 3]);
    expect(codec.decode(full.sublist(0, 11)), isNull);
  });

  test('rejects trailing bytes and out-of-range fields', () {
    final full =
        codec.encode(command: 1, sequence: 0, opcode: 1, payload: <int>[1]);
    expect(() => codec.decode(Uint8List.fromList([...full, 0])),
        throwsFormatException);
    expect(
      () =>
          codec.encode(command: 256, sequence: 0, opcode: 1, payload: <int>[]),
      throwsRangeError,
    );
  });
}
