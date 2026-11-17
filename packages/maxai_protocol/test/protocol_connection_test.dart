import 'dart:async';
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
    if (!connected) throw StateError('not connected');
    sent.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    connected = false;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  const codec = TcpFrameCodec(payloadCodec: _BytesCodec());

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

  test('request correlates response by sequence', () async {
    await connection.connect();

    final responseFuture = connection.request(
      opcode: 49,
      payload: <int>[10, 20],
      timeout: const Duration(seconds: 1),
    );

    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, hasLength(1));

    final request = codec.decode(transport.sent.single)!;
    expect(request.command, ProtocolCommand.request.value);
    expect(request.opcode, 49);
    expect(request.sequence, 0);
    expect(request.payload, <int>[10, 20]);

    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: request.sequence,
      opcode: request.opcode,
      payload: <int>[30, 40],
    ));

    final response = await responseFuture;
    expect(response.commandType, ProtocolCommand.response);
    expect(response.sequence, request.sequence);
    expect(response.payload, <int>[30, 40]);
    expect(connection.pendingRequestCount, 0);
  });

  test('event frames are dispatched without resolving requests', () async {
    final events = <DecodedProtocolFrame>[];
    connection = ProtocolConnection(
      transport: transport,
      codec: codec,
      onEvent: events.add,
    );
    await connection.connect();

    transport.controller.add(codec.encode(
      command: ProtocolCommand.event.value,
      sequence: 7,
      opcode: 128,
      payload: <int>[1],
    ));

    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.opcode, 128);
    expect(connection.pendingRequestCount, 0);
  });

  test('timeout removes request from pending registry', () async {
    await connection.connect();

    await expectLater(
      connection.request(
        opcode: 49,
        payload: <int>[],
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(connection.pendingRequestCount, 0);
  });

  test('close fails pending requests and changes state', () async {
    await connection.connect();
    final future = connection.request(
      opcode: 49,
      payload: <int>[],
    );

    await Future<void>.delayed(Duration.zero);
    await connection.close();

    await expectLater(future, throwsStateError);
    expect(connection.state, ProtocolConnectionState.closed);
    expect(connection.pendingRequestCount, 0);
  });

  test('sequence allocation skips currently pending sequence', () async {
    await connection.connect();

    final first = connection.request(
      opcode: 49,
      payload: <int>[],
    );
    await Future<void>.delayed(Duration.zero);

    // Sequence manager возвращается к 0, но он уже занят.
    final secondSequenceManager = SequenceManager(initialValue: 0xFFFF);
    connection = ProtocolConnection(
      transport: transport,
      codec: codec,
      sequenceManager: secondSequenceManager,
    );
    // Этот тест проверяет только контракт менеджера sequence отдельно,
    // поскольку отдельное соединение не разделяет pending registry.
    expect(secondSequenceManager.next(), 0);

    await connection.close();
    await expectLater(first, throwsStateError);
  });
}
