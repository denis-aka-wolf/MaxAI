import 'dart:typed_data';

import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  const mobileAgent = MaxUserAgent(
    deviceType: DeviceType.android,
    appVersion: '1.2.3',
    osVersion: 'Android 15',
    timezone: 'Europe/Helsinki',
    screen: '1080x2400',
    locale: 'ru',
    deviceName: 'Test device',
    deviceLocale: 'ru_RU',
  );

  test('mobile LOGIN contains PyMax SyncPayload fields', () {
    final payload = LoginPayloads.mobile(
      userAgent: mobileAgent,
      token: 'auth-token',
      sync: const SyncState(
        chatsSync: 1,
        contactsSync: 2,
        draftsSync: 3,
        presenceSync: 4,
        configHash: 'cfg',
      ),
      chatCacheFingerprint: Uint8List.fromList(const [1, 2, 3]),
      interactive: false,
    );
    expect(payload.keys.toSet(), <String>{
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
    });
    expect(payload['chatsSync'], 1);
    expect(payload['presenceSync'], 4);
    expect(payload['configHash'], 'cfg');
    expect(payload['chatCacheFingerprint'], [1, 2, 3]);
    final exp = payload['exp'] as Map<String, Object?>;
    expect(exp['chatsCountGroups'], [0x0a, 0x32]);
  });

  test('web LOGIN matches actual WebSyncPayload.from_sync_state output', () {
    final payload = LoginPayloads.web(
      token: 'web-token',
      sync: const SyncState(
        chatsSync: 10,
        contactsSync: 20,
        draftsSync: 30,
        presenceSync: 40,
      ),
    );
    expect(payload, {
      'token': 'web-token',
      'chatsCount': 40,
      'interactive': true,
      'chatsSync': 10,
      'contactsSync': 20,
      'draftsSync': 30,
      'presenceSync': -1,
    });
    expect(payload['presenceSync'], -1);
  });

  test('LOGIN2 disables contact sync when contact flag is false', () {
    expect(
      LoginPayloads.login2(
        sync: const SyncState(contactsSync: 55, configHash: 123),
        profileEnabled: true,
        contactEnabled: false,
      ),
      {
        'needProfile': true,
        'contactsSync': -1,
        'configHash': 123,
      },
    );
  });
}
