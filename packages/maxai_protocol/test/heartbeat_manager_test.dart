import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

final class _JsonPayloadCodec implements PayloadCodec {
  const _JsonPayloadCodec();

  @override
  Uint8List encode(Object? payload) =>
      Uint8List.fromList(utf8.encode(jsonEncode(payload)));

  @override
  Object? decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
}

final class _FakeTransport implements ProtocolTransport {
  final StreamController<dynamic> controller =
      StreamController<dynamic>();
  final List<Uint8List> sent = <Uint8List>[];
  bool connected = false;

  @override
  bool get isConnected => connected;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (!connected) throw StateError('Transport is disconnected.');
    sent.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    connected = false;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  const codec = TcpFrameCodec(payloadCodec: _JsonPayloadCodec());
  late _FakeTransport transport;
  late ProtocolConnection connection;

  setUp(() {
    transport = _FakeTransport();
    connection = ProtocolConnection(
      transport: transport,
      codec: codec,
    );
  });

  tearDown(() async {
    await connection.close();
  });

  test('sends immediate PING and waits for the response', () async {
    await connection.connect();
    final manager = HeartbeatManager(
      connection: connection,
      interval: const Duration(hours: 1),
      requestTimeout: const Duration(seconds: 1),
      interactive: false,
    );

    await manager.start();
    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, hasLength(1));

    final ping = codec.decode(transport.sent.single)!;
    expect(ping.command, ProtocolCommand.request.value);
    expect(ping.opcode, HeartbeatManager.pingOpcode);
    expect(codec.decodePayload(ping), <String, Object?>{
      'interactive': false,
    });

    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: ping.sequence,
      opcode: HeartbeatManager.pingOpcode,
      payload: <String, Object?>{},
    ));

    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(manager.lastSuccessAt, isNotNull);
    expect(manager.state, HeartbeatState.running);

    await manager.stop();
    expect(manager.state, HeartbeatState.stopped);
    expect(manager.isRunning, isFalse);
  });

  test('stops after ERROR response and reports failure', () async {
    await connection.connect();
    final failure = Completer<Object>();
    final manager = HeartbeatManager(
      connection: connection,
      interval: const Duration(hours: 1),
      onFailure: (error, stackTrace) {
        if (!failure.isCompleted) failure.complete(error);
      },
    );

    await manager.start();
    await Future<void>.delayed(Duration.zero);
    final ping = codec.decode(transport.sent.single)!;

    transport.controller.add(codec.encode(
      command: ProtocolCommand.error.value,
      sequence: ping.sequence,
      opcode: HeartbeatManager.pingOpcode,
      payload: <String, Object?>{'error': 'PING_REJECTED'},
    ));

    final error = await failure.future;
    expect(error, isA<HeartbeatException>());
    expect(manager.state, HeartbeatState.failed);
    expect(manager.isRunning, isFalse);
    await manager.stop();
    expect(manager.state, HeartbeatState.failed);
  });

  test('cannot start before ProtocolConnection is connected', () async {
    final manager = HeartbeatManager(connection: connection);
    await expectLater(manager.start(), throwsStateError);
    expect(transport.sent, isEmpty);
  });
  test('sends the next PING only after interval and prior response', () async {
    await connection.connect();
    final manager = HeartbeatManager(
      connection: connection,
      interval: const Duration(milliseconds: 10),
      requestTimeout: const Duration(seconds: 1),
    );

    await manager.start();
    await Future<void>.delayed(Duration.zero);
    final first = codec.decode(transport.sent.first)!;
    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: first.sequence,
      opcode: HeartbeatManager.pingOpcode,
      payload: <String, Object?>{},
    ));

    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(transport.sent, hasLength(2));
    final second = codec.decode(transport.sent[1])!;
    expect(second.sequence, isNot(first.sequence));

    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: second.sequence,
      opcode: HeartbeatManager.pingOpcode,
      payload: <String, Object?>{},
    ));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await manager.stop();
  });

}
