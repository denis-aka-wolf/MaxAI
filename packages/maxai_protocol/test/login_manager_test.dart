import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

final class _JsonCodec implements PayloadCodec {
  const _JsonCodec();
  @override
  Uint8List encode(Object? payload) =>
      Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  @override
  Object? decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
}

final class _Transport implements ProtocolTransport {
  final controller = StreamController<dynamic>();
  final sent = <Uint8List>[];
  bool connected = false;
  @override
  bool get isConnected => connected;
  @override
  Stream<dynamic> get stream => controller.stream;
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> send(Uint8List bytes) async => sent.add(Uint8List.fromList(bytes));
  @override
  Future<void> close([int? code, String? reason]) async {
    connected = false;
    if (!controller.isClosed) await controller.close();
  }
}

final class _Fingerprint implements FingerprintProvider {
  @override
  Uint8List generate({
    required String deviceId,
    required int callsSeed,
    required String architecture,
  }) => Uint8List.fromList([callsSeed & 0xff, deviceId.length, architecture.length]);
}

void main() {
  const codec = TcpFrameCodec(payloadCodec: _JsonCodec());
  const agent = MaxUserAgent(
    deviceType: DeviceType.android,
    appVersion: '2.5.0',
    osVersion: 'Android 15',
    timezone: 'Europe/Helsinki',
    screen: '1080x2400',
    locale: 'ru',
    deviceName: 'Test Android',
    deviceLocale: 'ru_RU',
  );

  late _Transport transport;
  late ProtocolConnection connection;
  late SessionManager session;

  setUp(() async {
    transport = _Transport();
    connection = ProtocolConnection(transport: transport, codec: codec);
    await connection.connect();
    session = SessionManager(connection: connection);
    final handshake = session.startMobile(
      mtInstanceId: 'mt',
      userAgent: agent,
      deviceId: 'device-id',
      clientSessionId: 1,
    );
    await Future<void>.delayed(Duration.zero);
    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: 0,
      opcode: SessionManager.sessionInitOpcode,
      payload: {'callsSeed': 12345},
    ));
    await handshake;
  });

  tearDown(() async {
    await connection.close();
  });

  Map<String, Object?> requestPayload(int index) {
    final frame = codec.decode(transport.sent[index])!;
    final payload = codec.decodePayload(frame) as Map<Object?, Object?>;
    return payload.cast<String, Object?>();
  }

  void reply({
    required int sequence,
    required int opcode,
    required Map<String, Object?> payload,
  }) {
    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: sequence,
      opcode: opcode,
      payload: payload,
    ));
  }

  test('mobile LOGIN performs LOGIN2 only when one of its flags is enabled', () async {
    final manager = LoginManager(
      connection: connection,
      sessionManager: session,
      deviceType: DeviceType.android,
      userAgent: agent,
      deviceId: 'device-id',
      fingerprintProvider: _Fingerprint(),
    );

    final future = manager.login(token: 'auth-token');
    await Future<void>.delayed(Duration.zero);
    final loginFrame = codec.decode(transport.sent[1])!;
    expect(loginFrame.opcode, LoginManager.loginOpcode);
    expect(requestPayload(1).keys, containsAll([
      'userAgent',
      'token',
      'chatCacheFingerprint',
      'chatsSync',
      'contactsSync',
      'draftsSync',
      'interactive',
      'presenceSync',
      'exp',
      'configHash',
    ]));

    reply(
      sequence: 1,
      opcode: LoginManager.loginOpcode,
      payload: {
        'profile': {'id': 7},
        'token': '',
        'time': 500,
        'login2Flags': {
          'configEnabled': false,
          'contactEnabled': true,
          'profileEnabled': false,
        },
      },
    );
    await Future<void>.delayed(Duration.zero);
    final login2Frame = codec.decode(transport.sent[2])!;
    expect(login2Frame.opcode, LoginManager.login2Opcode);
    expect(requestPayload(2), {
      'needProfile': false,
      'contactsSync': 500,
      'configHash': defaultConfigHash,
    });

    reply(
      sequence: 2,
      opcode: LoginManager.login2Opcode,
      payload: {
        'contactInfos': [{'id': 8}],
        'config': {'hash': 'new-config'},
      },
    );
    final result = await future;
    expect(result.effectiveToken, 'auth-token');
    expect(result.syncState.chatsSync, 500);
    expect(result.syncState.configHash, 'new-config');
    expect(result.contacts, [{'id': 8}]);
    expect(result.login2, isNotNull);
  });

  test('does not call LOGIN2 when all server flags are false', () async {
    final manager = LoginManager(
      connection: connection,
      sessionManager: session,
      deviceType: DeviceType.android,
      userAgent: agent,
      deviceId: 'device-id',
      fingerprintProvider: _Fingerprint(),
    );
    final future = manager.login(token: 'auth-token');
    await Future<void>.delayed(Duration.zero);
    reply(
      sequence: 1,
      opcode: LoginManager.loginOpcode,
      payload: {
        'profile': {'id': 7},
        'login2Flags': {
          'configEnabled': false,
          'contactEnabled': false,
          'profileEnabled': false,
        },
      },
    );
    final result = await future;
    expect(result.login2, isNull);
    expect(transport.sent, hasLength(2));
  });

  test('web LOGIN omits mobile fingerprint and presenceSync', () async {
    const webAgent = MaxUserAgent(
      deviceType: DeviceType.web,
      appVersion: 'web',
      osVersion: 'Linux',
      timezone: 'Europe/Helsinki',
      screen: '1920x1080',
      locale: 'ru',
      deviceName: 'Browser',
      deviceLocale: 'ru_RU',
    );
    // Reuse the completed handshake, only the LOGIN device mode differs here.
    final manager = LoginManager(
      connection: connection,
      sessionManager: session,
      deviceType: DeviceType.web,
      userAgent: webAgent,
      deviceId: 'web-device',
    );
    final future = manager.login(token: 'web-token');
    await Future<void>.delayed(Duration.zero);
    final payload = requestPayload(1);
    expect(payload.keys, containsAll(['token', 'chatsCount', 'interactive']));
    expect(payload.containsKey('chatCacheFingerprint'), isFalse);
    expect(payload['presenceSync'], -1);
    reply(
      sequence: 1,
      opcode: LoginManager.loginOpcode,
      payload: {'profile': {'id': 1}},
    );
    final result = await future;
    expect(result.profile, {'id': 1});
  });

  test('rejects mobile LOGIN without fingerprint provider', () async {
    final manager = LoginManager(
      connection: connection,
      sessionManager: session,
      deviceType: DeviceType.android,
      userAgent: agent,
      deviceId: 'device-id',
    );
    await expectLater(
      manager.login(token: 'auth-token'),
      throwsStateError,
    );
    expect(transport.sent, hasLength(1)); // только SESSION_INIT
  });
}
