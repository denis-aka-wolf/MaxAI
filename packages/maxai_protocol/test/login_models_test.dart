import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('LoginResponse', () {
    test('parses login data and login2 flags', () {
      final response = LoginResponse.fromPayload({
        'chats': <Object?>[
          {'id': 10}
        ],
        'profile': {'id': 1},
        'messages': <Object?, Object?>{
          10: <Object?>[
            {'id': 100}
          ]
        },
        'contacts': <Object?>[
          {'id': 2}
        ],
        'token': 'rotated-token',
        'time': 123456,
        'config': {'hash': 'cfg-v2'},
        'updates': 7,
        'login2Flags': {
          'configEnabled': true,
          'contactEnabled': false,
          'profileEnabled': true,
        },
      });

      expect(response.chats, hasLength(1));
      expect(response.profile, {'id': 1});
      expect(response.messages[10], hasLength(1));
      expect(response.contacts, hasLength(1));
      expect(response.token, 'rotated-token');
      expect(response.login2Flags?.enabled, isTrue);
      expect(response.login2Flags?.profileEnabled, isTrue);
      expect(response.updateSyncState(const SyncState()).chatsSync, 123456);
      expect(response.updateSyncState(const SyncState()).configHash, 'cfg-v2');
    });

    test('preserves existing sync markers when response omits time/config', () {
      const sync = SyncState(
        chatsSync: 1,
        contactsSync: 2,
        draftsSync: 3,
        presenceSync: 4,
        configHash: 'saved-config',
      );
      final updated = LoginResponse.fromPayload({}).updateSyncState(sync);
      expect(updated.chatsSync, 1);
      expect(updated.contactsSync, 2);
      expect(updated.draftsSync, 3);
      expect(updated.presenceSync, 4);
      expect(updated.configHash, 'saved-config');
    });

    test('rejects invalid login2 flag types', () {
      expect(
        () => LoginResponse.fromPayload({
          'login2Flags': {'contactEnabled': 'yes'},
        }),
        throwsFormatException,
      );
    });
  });

  test('LOGIN2 reads contactInfos and updates only config hash', () {
    final response = Login2Response.fromPayload({
      'profile': {'id': 5},
      'contactInfos': <Object?>[
        {'id': 6}
      ],
      'config': {'hash': 42},
    });
    expect(response.contacts, hasLength(1));
    expect(
      response.updateSyncState(const SyncState(
        chatsSync: 10,
        contactsSync: 11,
        draftsSync: 12,
        presenceSync: 13,
        configHash: 'old',
      )),
      const SyncState(
        chatsSync: 10,
        contactsSync: 11,
        draftsSync: 12,
        presenceSync: 13,
        configHash: 42,
      ),
    );
  });

  test('selects LOGIN2 profile/contacts only when corresponding flags are set',
      () {
    final login = LoginResponse.fromPayload({
      'profile': {'id': 'login'},
      'contacts': <Object?>[
        {'id': 'login-contact'}
      ],
      'login2Flags': {
        'profileEnabled': true,
        'contactEnabled': true,
      },
    });
    final login2 = Login2Response.fromPayload({
      'profile': {'id': 'login2'},
      'contactInfos': <Object?>[
        {'id': 'login2-contact'}
      ],
    });
    final result = LoginBootstrapResult(
      login: login,
      login2: login2,
      syncState: const SyncState(),
      effectiveToken: 'token',
    );
    expect(result.profile, {'id': 'login2'});
    expect(result.contacts.single, {'id': 'login2-contact'});
  });
}
