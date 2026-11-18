import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('MaxUserProfile', () {
    test('parses nested contact and preferred ONEME display name', () {
      final profile = MaxUserProfile.fromPayload(<String, Object?>{
        'contact': <String, Object?>{
          'id': 123,
          'updateTime': 1700000000000,
          'registrationTime': 1690000000000,
          'photoId': 456,
          'accountStatus': 0,
          'country': 'RU',
          'names': [
            {
              'name': 'Other name',
              'firstName': 'Other',
              'type': 'OTHER',
            },
            {
              'name': 'Иван Иванов',
              'firstName': 'Иван',
              'lastName': 'Иванов',
              'type': 'ONEME',
            },
          ],
          'options': ['TT', 'ONEME'],
          'baseUrl': 'https://example.invalid/private?signature=secret',
          'baseRawUrl': 'https://example.invalid/private-raw',
        },
        'profileOptions': <Object?>[],
      });

      expect(profile.displayName, 'Иван Иванов');
      expect(profile.contact?.id, 123);
      expect(profile.contact?.country, 'RU');
      expect(profile.contact?.options, ['TT', 'ONEME']);
      expect(profile.contact?.raw['baseUrl'], contains('signature=secret'));
      expect(profile.toString(), isNot(contains('secret')));
      expect(profile.contact.toString(), isNot(contains('example.invalid')));
    });

    test('accepts absent optional profile fields', () {
      final profile = MaxUserProfile.fromPayload(<String, Object?>{
        'contact': <String, Object?>{},
      });
      expect(profile.displayName, isNull);
      expect(profile.contact?.names, isEmpty);
      expect(profile.profileOptions, isEmpty);
    });

    test('rejects malformed nested names', () {
      expect(
        () => MaxUserProfile.fromPayload({
          'contact': {'names': 'not-a-list'},
        }),
        throwsFormatException,
      );
    });
  });

  test('MaxAuthenticatedSession keeps token out of toString', () {
    final login = LoginBootstrapResult(
      login: LoginResponse.fromPayload({}),
      syncState: const SyncState(),
      effectiveToken: 'very-secret-token',
    );
    final session = MaxAuthenticatedSession.fromLogin(login);

    expect(session.token, 'very-secret-token');
    expect(session.profile, isNull);
    expect(session.toString(), isNot(contains('very-secret-token')));
  });
}
