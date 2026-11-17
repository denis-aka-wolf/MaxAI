import 'package:maxai_protocol/maxai_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('authResultFromPayload', () {
    test('reads LOGIN token', () {
      final result = authResultFromPayload({
        'tokenAttrs': {
          'LOGIN': {'token': 'secret-token'},
        },
      });
      expect(result.stage, AuthStage.authenticated);
      expect(result.token, 'secret-token');
      expect(result.toString(), isNot(contains('secret-token')));
    });

    test('reads password challenge', () {
      final result = authResultFromPayload({
        'passwordChallenge': {
          'trackId': 'track-1',
          'hint': 'pet name',
        },
      });
      expect(result.stage, AuthStage.passwordRequired);
      expect(result.challenge?.trackId, 'track-1');
      expect(result.hint, 'pet name');
    });

    test('reads REGISTER token separately', () {
      final result = authResultFromPayload({
        'tokenAttrs': {
          'REGISTER': {'token': 'registration-token'},
        },
      });
      expect(result.stage, AuthStage.registrationRequired);
      expect(result.registrationToken, 'registration-token');
      expect(result.token, isNull);
    });

    test('rejects response without a known next step', () {
      expect(
        () => authResultFromPayload(<String, Object?>{}),
        throwsFormatException,
      );
    });
  });

  test('parses QR timestamps and polling interval as milliseconds', () {
    final qr = QrLoginRequest.fromPayload({
      'expiresAt': 1900000000000,
      'pollingInterval': 1500,
      'qrLink': 'https://example.invalid/qr',
      'trackId': 'track-qr',
      'ttl': 120,
    });
    expect(qr.expiresAt, 1900000000000);
    expect(qr.pollingInterval, 1500);
    expect(qr.expiresAtDateTime.millisecondsSinceEpoch, 1900000000000);
  });

  test('builds exact SMS wire field names', () {
    final payload = AuthPayloads.submitSmsCode(
      token: 'request-token',
      code: '12345',
    );
    expect(payload, {
      'token': 'request-token',
      'verifyCode': '12345',
      'authTokenType': 'CHECK_CODE',
    });
  });
}
