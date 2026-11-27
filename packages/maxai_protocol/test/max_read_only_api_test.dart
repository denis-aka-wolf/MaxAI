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

final class _FakeTransport implements ProtocolTransport {
  final StreamController<dynamic> controller = StreamController<dynamic>();
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
  const codec = TcpFrameCodec(payloadCodec: _JsonCodec());
  late _FakeTransport transport;
  late ProtocolConnection connection;
  late MaxReadOnlyApi api;

  setUp(() async {
    transport = _FakeTransport();
    connection = ProtocolConnection(transport: transport, codec: codec);
    await connection.connect();
    api = MaxReadOnlyApi(
      connection: connection,
      requestTimeout: const Duration(seconds: 1),
    );
  });

  tearDown(() async => connection.close());

  Future<Map<String, Object?>> expectRequest(
    int opcode,
    Map<String, Object?> expectedPayload,
  ) async {
    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, hasLength(1));
    final frame = codec.decode(transport.sent.single)!;
    expect(frame.command, ProtocolCommand.request.value);
    expect(frame.opcode, opcode);
    final payload = codec.decodePayload(frame) as Map<Object?, Object?>;
    expect(payload.cast<String, Object?>(), expectedPayload);
    return <String, Object?>{
      'sequence': frame.sequence,
      'opcode': frame.opcode,
    };
  }

  void reply(int sequence, int opcode, Object? payload) {
    transport.controller.add(codec.encode(
      command: ProtocolCommand.response.value,
      sequence: sequence,
      opcode: opcode,
      payload: payload,
    ));
  }

  test('CHATS_LIST uses marker and parses chats', () async {
    final future = api.getChats(marker: 123456);
    final request = await expectRequest(53, <String, Object?>{'marker': 123456});
    reply(request['sequence']! as int, 53, <String, Object?>{
      'chats': <Object?>[
        <String, Object?>{'id': 42, 'title': 'Test chat'},
      ],
    });
    final chats = await future;
    expect(chats.single['id'], 42);
    expect(chats.single['title'], 'Test chat');
  });

  test('CHAT_INFO uses chatIds', () async {
    final future = api.getChatInfo(<int>[42, 43]);
    final request = await expectRequest(48, <String, Object?>{
      'chatIds': <int>[42, 43],
    });
    reply(request['sequence']! as int, 48, <String, Object?>{
      'chats': <Object?>[
        <String, Object?>{'id': 42},
      ],
    });
    expect((await future).single['id'], 42);
  });

  test('CONTACT_INFO uses contactIds', () async {
    final future = api.getContactInfo(<int>[17]);
    final request = await expectRequest(32, <String, Object?>{
      'contactIds': <int>[17],
    });
    reply(request['sequence']! as int, 32, <String, Object?>{
      'contacts': <Object?>[
        <String, Object?>{'id': 17},
      ],
    });
    expect((await future).single['id'], 17);
  });

  test('MSG_GET uses chatId and messageIds', () async {
    final future = api.getMessages(chatId: 42, messageIds: <int>[900, 901]);
    final request = await expectRequest(71, <String, Object?>{
      'chatId': 42,
      'messageIds': <int>[900, 901],
    });
    reply(request['sequence']! as int, 71, <String, Object?>{
      'messages': <Object?>[
        <String, Object?>{'id': 900, 'text': 'first'},
        <String, Object?>{'id': 901, 'text': 'second'},
      ],
    });
    expect((await future).map((message) => message['id']), <int>[900, 901]);
  });

  test('CHAT_MEMBERS sends MEMBER page request and parses marker', () async {
    final future = api.getChatMembers(chatId: 42, marker: 9, count: 25);
    final request = await expectRequest(59, <String, Object?>{
      'type': 'MEMBER',
      'chatId': 42,
      'marker': 9,
      'count': 25,
    });
    reply(request['sequence']! as int, 59, <String, Object?>{
      'members': <Object?>[
        <String, Object?>{'id': 17},
      ],
      'marker': 10,
    });
    final result = await future;
    expect(result.members.single['id'], 17);
    expect(result.marker, 10);
  });

  test('CHAT_HISTORY sends exact PyMax history fields', () async {
    final future = api.getChatHistory(
      chatId: 42,
      forward: 0,
      backward: 20,
      backwardTime: 100,
      forwardTime: 200,
      from: 300,
    );
    final request = await expectRequest(49, <String, Object?>{
      'chatId': 42,
      'forward': 0,
      'backward': 20,
      'backwardTime': 100,
      'forwardTime': 200,
      'getChat': false,
      'from': 300,
      'itemType': 'REGULAR',
      'getMessages': true,
      'interactive': false,
    });
    reply(request['sequence']! as int, 49, <String, Object?>{
      'messages': <Object?>[
        <String, Object?>{'id': 900, 'text': 'hello'},
      ],
    });
    expect((await future).single['id'], 900);
  });

  test('PROFILE and contact snapshot come from LOGIN data, not PROFILE opcode', () {
    final login = LoginBootstrapResult(
      login: LoginResponse.fromPayload(<String, Object?>{
        'profile': <String, Object?>{
          'contact': <String, Object?>{
            'id': 1,
            'names': <Object?>[
              <String, Object?>{'firstName': 'Test', 'type': 'ONEME'},
            ],
          },
        },
        'contacts': <Object?>[
          <String, Object?>{'id': 2},
        ],
      }),
      syncState: const SyncState(),
      effectiveToken: 'test-token',
    );
    expect(api.profileFromLogin(login)?.displayName, 'Test');
    expect(api.contactsFromLogin(login).single['id'], 2);
    expect(transport.sent, isEmpty);
  });

  test('ERROR frame becomes a safe API exception', () async {
    final future = api.getChats(marker: 123);
    final request = await expectRequest(53, <String, Object?>{'marker': 123});
    transport.controller.add(codec.encode(
      command: ProtocolCommand.error.value,
      sequence: request['sequence']! as int,
      opcode: 53,
      payload: <String, Object?>{
        'error': 'AUTH_REQUIRED',
        'token': 'must-not-leak',
      },
    ));

    await expectLater(
      future,
      throwsA(
        isA<MaxReadOnlyApiException>()
            .having((error) => error.opcode, 'opcode', 53)
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('must-not-leak')),
            ),
      ),
    );
  });

  test('rejects invalid IDs before sending a request', () async {
    await expectLater(api.getChatInfo(<int>[]), throwsArgumentError);
    await expectLater(api.getContactInfo(<int>[0]), throwsArgumentError);
    await expectLater(
      api.getMessages(chatId: 42, messageIds: <int>[0]),
      throwsArgumentError,
    );
    expect(transport.sent, isEmpty);
  });
  test('CHATS_LIST accepts an empty result', () async {
    final future = api.getChats(marker: 123456);
    final request = await expectRequest(53, <String, Object?>{'marker': 123456});
    reply(
      request['sequence']! as int,
      53,
      <String, Object?>{'chats': <Object?>[]},
    );
    expect(await future, isEmpty);
  });

  test('all collection endpoints accept empty results', () async {
    var future = api.getContactInfo(<int>[17]);
    var request = await expectRequest(32, <String, Object?>{'contactIds': <int>[17]});
    reply(
      request['sequence']! as int,
      32,
      <String, Object?>{'contacts': <Object?>[]},
    );
    expect(await future, isEmpty);
    transport.sent.clear();

    future = api.getChats(marker: 123);
    request = await expectRequest(53, <String, Object?>{'marker': 123});
    reply(
      request['sequence']! as int,
      53,
      <String, Object?>{'chats': <Object?>[]},
    );
    expect(await future, isEmpty);
    transport.sent.clear();

    future = api.getChatInfo(<int>[42]);
    request = await expectRequest(48, <String, Object?>{'chatIds': <int>[42]});
    reply(
      request['sequence']! as int,
      48,
      <String, Object?>{'chats': <Object?>[]},
    );
    expect(await future, isEmpty);
    transport.sent.clear();

    final membersFuture = api.getChatMembers(chatId: 42);
    request = await expectRequest(59, <String, Object?>{
      'type': 'MEMBER',
      'chatId': 42,
      'marker': 0,
      'count': 50,
    });
    reply(request['sequence']! as int, 59, <String, Object?>{
      'members': <Object?>[],
      'marker': 0,
    });
    expect((await membersFuture).members, isEmpty);
    transport.sent.clear();

    future = api.getChatHistory(chatId: 42, from: 123);
    request = await expectRequest(49, <String, Object?>{
      'chatId': 42,
      'forward': 0,
      'backward': 40,
      'backwardTime': 0,
      'forwardTime': 0,
      'getChat': false,
      'from': 123,
      'itemType': 'REGULAR',
      'getMessages': true,
      'interactive': false,
    });
    reply(
      request['sequence']! as int,
      49,
      <String, Object?>{'messages': <Object?>[]},
    );
    expect(await future, isEmpty);
    transport.sent.clear();

    future = api.getMessages(chatId: 42, messageIds: <int>[900]);
    request = await expectRequest(71, <String, Object?>{
      'chatId': 42,
      'messageIds': <int>[900],
    });
    reply(
      request['sequence']! as int,
      71,
      <String, Object?>{'messages': <Object?>[]},
    );
    expect(await future, isEmpty);
  });

  test('rejects a RESPONSE with a mismatched opcode', () async {
    final future = api.getChats(marker: 123);
    final request = await expectRequest(53, <String, Object?>{'marker': 123});
    reply(request['sequence']! as int, 48, <String, Object?>{'chats': <Object?>[]});
    await expectLater(
      future,
      throwsA(isA<MaxReadOnlyApiException>().having(
        (error) => error.opcode,
        'requested opcode',
        53,
      )),
    );
  });

  test('rejects malformed response collection without leaking payload', () async {
    final future = api.getChats(marker: 123);
    final request = await expectRequest(53, <String, Object?>{'marker': 123});
    reply(request['sequence']! as int, 53, <String, Object?>{'chats': 'not-a-list'});
    await expectLater(future, throwsFormatException);
  });

  test('request timeout clears the pending request', () async {
    final shortTimeoutApi = MaxReadOnlyApi(
      connection: connection,
      requestTimeout: const Duration(milliseconds: 20),
    );
    final future = shortTimeoutApi.getChats(marker: 123);
    await expectRequest(53, <String, Object?>{'marker': 123});
    await expectLater(future, throwsA(isA<TimeoutException>()));
    expect(connection.pendingRequestCount, 0);
    expect(connection.isConnected, isTrue);
  });

  test('connection close fails outstanding read-only requests', () async {
    final future = api.getChats(marker: 123);
    await expectRequest(53, <String, Object?>{'marker': 123});
    await connection.close();
    await expectLater(future, throwsA(isA<StateError>()));
    expect(connection.pendingRequestCount, 0);
  });
}
