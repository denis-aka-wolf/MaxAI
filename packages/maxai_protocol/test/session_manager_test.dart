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

  const mobileUserAgent = MaxUserAgent(
    deviceType: DeviceType.android,
    appVersion: '1.2.3',
    osVersion: 'Android 15',
    timezone: 'Europe/Helsinki',
    screen: '1080x2400',
    locale: 'ru',
    deviceName: 'Android Test Device',
    deviceLocale: 'ru_RU',
    arch: 'arm64',
    buildNumber: 123,
  );

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

  Future<Map<String, Object?>> sentPayload() async {
    await Future<void>.delayed(Duration.zero);
    final frame = codec.decode(transport.sent.single)!;
    expect(frame.command, ProtocolCommand.request.value);
    expect(frame.opcode, SessionManager.sessionInitOpcode);
    final decoded = codec.decodePayload(frame);
    return (decoded as Map<Object?, Object?>).cast<String, Object?>();
  }

  void replyWithHandshake({
    int sequence = 0,
    Object? payload = const <String, Object?>{
      'callsSeed': 987654,
      'app-update-type': 2,
    },
    int command = 1,
    int opcode = SessionManager.sessionInitOpcode,
  }) {
    transport.controller.add(codec.encode(
      command: command,
      sequence: sequence,
      opcode: opcode,
      payload: payload,
    ));
  }

  test('mobile SESSION_INIT uses PyMax payload field names', () async {
    await connection.connect();
    final manager = SessionManager(connection: connection);

    final future = manager.startMobile(
      mtInstanceId: 'mt-instance',
      userAgent: mobileUserAgent,
      deviceId: 'device-123',
      clientSessionId: 17,
    );

    final payload = await sentPayload();
    expect(payload['mt_instanceid'], 'mt-instance');
    expect(payload['deviceId'], 'device-123');
    expect(payload['clientSessionId'], 17);
    expect(payload['userAgent'], <String, Object?>{
      'deviceType': 'ANDROID',
      'appVersion': '1.2.3',
      'osVersion': 'Android 15',
      'timezone': 'Europe/Helsinki',
      'screen': '1080x2400',
      'locale': 'ru',
      'deviceName': 'Android Test Device',
      'deviceLocale': 'ru_RU',
      'arch': 'arm64',
      'buildNumber': 123,
    });

    replyWithHandshake();
    final result = await future;
    expect(result.callsSeed, 987654);
    expect(result.appUpdateType, 2);
    expect(manager.state, SessionState.ready);
    expect(manager.isReady, isTrue);
  });

  test('web SESSION_INIT sends restricted web user-agent fields', () async {
    await connection.connect();
    final manager = SessionManager(connection: connection);
    const webAgent = MaxUserAgent(
      deviceType: DeviceType.web,
      appVersion: 'web-version',
      osVersion: 'Linux',
      timezone: 'Europe/Helsinki',
      screen: '1920x1080',
      locale: 'en',
      deviceName: 'Chrome',
      deviceLocale: 'en_US',
    );

    final future = manager.startWeb(
      userAgent: webAgent,
      deviceId: 'web-device',
    );
    final payload = await sentPayload();
    expect(payload.keys.toSet(), <String>{'userAgent', 'deviceId'});
    expect(payload['deviceId'], 'web-device');
    final userAgent = (payload['userAgent'] as Map<Object?, Object?>).cast<String, Object?>();
    expect(userAgent.keys.toSet(), <String>{
      'deviceType',
      'locale',
      'deviceLocale',
      'osVersion',
      'deviceName',
      'headerUserAgent',
      'appVersion',
      'screen',
      'timezone',
    });
    expect(userAgent['headerUserAgent'], contains('Mozilla/5.0'));

    replyWithHandshake();
    await future;
    expect(manager.state, SessionState.ready);
  });

  test('does not send handshake before protocol connection is open', () async {
    final manager = SessionManager(connection: connection);
    await expectLater(
      manager.startMobile(
        mtInstanceId: 'mt',
        userAgent: mobileUserAgent,
        deviceId: 'device',
        clientSessionId: 1,
      ),
      throwsStateError,
    );
    expect(transport.sent, isEmpty);
    expect(manager.state, SessionState.idle);
  });

  test('ERROR response fails handshake and moves session to failed', () async {
    await connection.connect();
    final manager = SessionManager(connection: connection);

    final future = manager.startMobile(
      mtInstanceId: 'mt',
      userAgent: mobileUserAgent,
      deviceId: 'device',
      clientSessionId: 1,
    );
    await sentPayload();
    replyWithHandshake(
      command: ProtocolCommand.error.value,
      payload: const <String, Object?>{'error': 'SESSION_REJECTED'},
    );

    await expectLater(future, throwsA(isA<SessionHandshakeException>()));
    expect(manager.state, SessionState.failed);
    expect(manager.handshakeResponse, isNull);
  });

  test('invalid handshake response payload fails validation', () async {
    await connection.connect();
    final manager = SessionManager(connection: connection);

    final future = manager.startMobile(
      mtInstanceId: 'mt',
      userAgent: mobileUserAgent,
      deviceId: 'device',
      clientSessionId: 1,
    );
    await sentPayload();
    replyWithHandshake(payload: 'not-a-map');

    await expectLater(future, throwsFormatException);
    expect(manager.state, SessionState.failed);
  });

  test('concurrent start calls share the in-flight handshake', () async {
    await connection.connect();
    final manager = SessionManager(connection: connection);

    final first = manager.startMobile(
      mtInstanceId: 'mt',
      userAgent: mobileUserAgent,
      deviceId: 'device',
      clientSessionId: 1,
    );
    final second = manager.startMobile(
      mtInstanceId: 'mt',
      userAgent: mobileUserAgent,
      deviceId: 'device',
      clientSessionId: 2,
    );

    expect(identical(first, second), isTrue);
    await sentPayload();
    expect(transport.sent, hasLength(1));

    replyWithHandshake();
    await Future.wait([first, second]);
    expect(manager.state, SessionState.ready);
  });

  test('close is rejected during handshake and closed manager requires reset', () async {
    await connection.connect();
    final manager = SessionManager(connection: connection);

    final future = manager.startMobile(
      mtInstanceId: 'mt',
      userAgent: mobileUserAgent,
      deviceId: 'device',
      clientSessionId: 1,
    );
    await sentPayload();

    expect(manager.close, throwsStateError);
    replyWithHandshake();
    await future;

    manager.close();
    expect(manager.state, SessionState.closed);
    await expectLater(
      manager.startMobile(
        mtInstanceId: 'mt',
        userAgent: mobileUserAgent,
        deviceId: 'device',
        clientSessionId: 1,
      ),
      throwsStateError,
    );

    manager.reset();
    expect(manager.state, SessionState.idle);
  });
}
