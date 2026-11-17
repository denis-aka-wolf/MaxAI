/// Возможные результаты промежуточного этапа авторизации.
enum AuthStage {
  smsCodeRequested,
  passwordRequired,
  registrationRequired,
  authenticated,
  qrPending,
  qrReady,
}

/// Результат этапа авторизации. Токены никогда не включаются в toString().
final class AuthResult {
  const AuthResult({
    required this.stage,
    this.token,
    this.challenge,
    this.registrationToken,
    this.hint,
  });

  final AuthStage stage;
  final String? token;
  final PasswordChallenge? challenge;
  final String? registrationToken;
  final String? hint;

  bool get isAuthenticated => stage == AuthStage.authenticated && token != null;

  @override
  String toString() => 'AuthResult(stage: $stage, tokenSet: ${token != null}, '
      'challengeSet: ${challenge != null}, '
      'registrationTokenSet: ${registrationToken != null})';
}

final class PasswordChallenge {
  const PasswordChallenge({required this.trackId, this.hint});

  final String trackId;
  final String? hint;

  factory PasswordChallenge.fromPayload(Object? value) {
    final map = _stringMap(value, 'passwordChallenge');
    return PasswordChallenge(
      trackId: _requiredString(map, 'trackId'),
      hint: _optionalString(map, 'hint'),
    );
  }
}

final class SmsCodeRequest {
  const SmsCodeRequest({
    required this.token,
    required this.codeLength,
    required this.requestMaxDuration,
    required this.requestCountLeft,
    required this.altActionDuration,
  });

  final String token;
  final int codeLength;
  final int requestMaxDuration;
  final int requestCountLeft;
  final int altActionDuration;

  factory SmsCodeRequest.fromPayload(Object? value) {
    final map = _stringMap(value, 'AUTH_REQUEST');
    return SmsCodeRequest(
      token: _requiredString(map, 'token'),
      codeLength: _requiredInt(map, 'codeLength'),
      requestMaxDuration: _requiredInt(map, 'requestMaxDuration'),
      requestCountLeft: _requiredInt(map, 'requestCountLeft'),
      altActionDuration: _requiredInt(map, 'altActionDuration'),
    );
  }

  @override
  String toString() => 'SmsCodeRequest(codeLength: $codeLength, '
      'requestCountLeft: $requestCountLeft)';
}

final class QrLoginRequest {
  const QrLoginRequest({
    required this.expiresAt,
    required this.pollingInterval,
    required this.qrLink,
    required this.trackId,
    required this.ttl,
  });

  /// Unix timestamp в миллисекундах, как в ответе PyMax.
  final int expiresAt;
  /// Интервал опроса в миллисекундах, как в ответе PyMax.
  final int pollingInterval;
  final String qrLink;
  final String trackId;
  final int ttl;

  DateTime get expiresAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt);

  factory QrLoginRequest.fromPayload(Object? value) {
    final map = _stringMap(value, 'GET_QR');
    final result = QrLoginRequest(
      expiresAt: _requiredInt(map, 'expiresAt'),
      pollingInterval: _requiredInt(map, 'pollingInterval'),
      qrLink: _requiredString(map, 'qrLink'),
      trackId: _requiredString(map, 'trackId'),
      ttl: _requiredInt(map, 'ttl'),
    );
    if (result.pollingInterval <= 0) {
      throw const FormatException('QR pollingInterval must be positive.');
    }
    return result;
  }

  @override
  String toString() => 'QrLoginRequest(expiresAt: $expiresAt, '
      'pollingInterval: $pollingInterval, ttl: $ttl, qrLinkSet: true)';
}

final class QrLoginStatus {
  const QrLoginStatus({required this.expiresAt, this.loginAvailable});

  final int expiresAt;
  final bool? loginAvailable;

  factory QrLoginStatus.fromPayload(Object? value) {
    final map = _stringMap(value, 'GET_QR_STATUS');
    final status = _stringMap(map['status'], 'GET_QR_STATUS.status');
    final loginAvailable = status['loginAvailable'];
    if (loginAvailable != null && loginAvailable is! bool) {
      throw const FormatException('status.loginAvailable must be bool or null.');
    }
    return QrLoginStatus(
      expiresAt: _requiredInt(status, 'expiresAt'),
      loginAvailable: loginAvailable as bool?,
    );
  }
}

final class AuthRegistrationRequest {
  const AuthRegistrationRequest({
    required this.firstName,
    this.lastName,
    required this.registrationToken,
  });

  final String firstName;
  final String? lastName;
  final String registrationToken;
}

Map<String, Object?> _stringMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field payload must be a map.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$field contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid "$key" in auth response.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Invalid "$key" in auth response.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  final safeValue = switch (value) {
    null => 'null',
    num() || bool() => value.toString(),
    String() => value.length <= 80 ? '"$value"' : '<string length=${value.length}>',
    _ => '<${value.runtimeType}>',
  };
  throw FormatException(
    'Missing or invalid "$key" in auth response '
    '(type: ${value.runtimeType}, value: $safeValue).',
  );
}

/// Извлекает LOGIN / REGISTER токены из tokenAttrs, не выводя их в логи.
AuthResult authResultFromPayload(Object? value) {
  final map = _stringMap(value, 'AUTH');
  final attrsValue = map['tokenAttrs'];
  final attrs = attrsValue == null
      ? <String, Object?>{}
      : _stringMap(attrsValue, 'tokenAttrs');

  final loginValue = attrs['LOGIN'];
  if (loginValue != null) {
    final login = _stringMap(loginValue, 'tokenAttrs.LOGIN');
    final token = _requiredString(login, 'token');
    return AuthResult(stage: AuthStage.authenticated, token: token);
  }

  final challengeValue = map['passwordChallenge'];
  if (challengeValue != null) {
    final challenge = PasswordChallenge.fromPayload(challengeValue);
    return AuthResult(
      stage: AuthStage.passwordRequired,
      challenge: challenge,
      hint: challenge.hint,
    );
  }

  final registrationValue = attrs['REGISTER'];
  if (registrationValue != null) {
    final registration = _stringMap(registrationValue, 'tokenAttrs.REGISTER');
    final token = _requiredString(registration, 'token');
    return AuthResult(
      stage: AuthStage.registrationRequired,
      registrationToken: token,
    );
  }

  throw const FormatException(
    'Auth response contains no login token, password challenge or registration token.',
  );
}
