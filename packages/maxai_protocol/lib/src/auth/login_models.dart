import '../session/sync_state.dart';

final class Login2Flags {
  const Login2Flags({
    this.configEnabled = false,
    this.contactEnabled = false,
    this.profileEnabled = false,
  });

  final bool configEnabled;
  final bool contactEnabled;
  final bool profileEnabled;

  bool get enabled => configEnabled || contactEnabled || profileEnabled;

  factory Login2Flags.fromPayload(Object? value) {
    final map = _stringMap(value, 'login2Flags');
    return Login2Flags(
      configEnabled: _optionalBool(map, 'configEnabled') ?? false,
      contactEnabled: _optionalBool(map, 'contactEnabled') ?? false,
      profileEnabled: _optionalBool(map, 'profileEnabled') ?? false,
    );
  }
}

final class LoginConfig {
  const LoginConfig({this.hash});
  final ConfigHash? hash;

  factory LoginConfig.fromPayload(Object? value) {
    final map = _stringMap(value, 'config');
    final hash = map['hash'];
    if (hash != null && hash is! String && hash is! int) {
      throw const FormatException('config.hash must be a string, integer or null.');
    }
    return LoginConfig(hash: hash as ConfigHash?);
  }
}

/// Доменные сущности сохраняются как исходные MessagePack структуры,
/// чтобы не терять поля до реализации отдельных моделей MAX.
final class LoginResponse {
  const LoginResponse({
    required this.raw,
    this.chats = const <Object?>[],
    this.profile,
    this.messages = const <Object?, Object?>{},
    this.contacts = const <Object?>[],
    this.token,
    this.time,
    this.config,
    this.updates,
    this.login2Flags,
  });

  final Map<String, Object?> raw;
  final List<Object?> chats;
  final Object? profile;
  final Map<Object?, Object?> messages;
  final List<Object?> contacts;
  final String? token;
  final int? time;
  final LoginConfig? config;
  final int? updates;
  final Login2Flags? login2Flags;

  SyncState updateSyncState(SyncState current) => current.copyWith(
        chatsSync: time,
        contactsSync: time,
        draftsSync: time,
        presenceSync: time,
        configHash: config?.hash,
      );

  factory LoginResponse.fromPayload(Object? value) {
    final map = _stringMap(value, 'LOGIN');
    final token = map['token'];
    if (token != null && token is! String) {
      throw const FormatException('LOGIN token must be a string or null.');
    }
    final messagesValue = map['messages'];
    if (messagesValue != null && messagesValue is! Map) {
      throw const FormatException('LOGIN messages must be a map or null.');
    }
    final configValue = map['config'];
    final flagsValue = map['login2Flags'];
    return LoginResponse(
      raw: Map<String, Object?>.unmodifiable(map),
      chats: _optionalList(map, 'chats'),
      profile: map['profile'],
      messages: messagesValue == null
          ? const <Object?, Object?>{}
          : Map<Object?, Object?>.unmodifiable(messagesValue as Map),
      contacts: _optionalList(map, 'contacts'),
      token: token as String?,
      time: _optionalInt(map, 'time'),
      config: configValue == null ? null : LoginConfig.fromPayload(configValue),
      updates: _optionalInt(map, 'updates'),
      login2Flags: flagsValue == null ? null : Login2Flags.fromPayload(flagsValue),
    );
  }
}

final class Login2Response {
  const Login2Response({
    required this.raw,
    this.profile,
    this.contacts = const <Object?>[],
    this.config,
  });

  final Map<String, Object?> raw;
  final Object? profile;
  final List<Object?> contacts;
  final LoginConfig? config;

  SyncState updateSyncState(SyncState current) =>
      current.copyWith(configHash: config?.hash);

  factory Login2Response.fromPayload(Object? value) {
    final map = _stringMap(value, 'LOGIN2');
    final configValue = map['config'];
    return Login2Response(
      raw: Map<String, Object?>.unmodifiable(map),
      profile: map['profile'],
      contacts: _optionalList(map, 'contactInfos'),
      config: configValue == null ? null : LoginConfig.fromPayload(configValue),
    );
  }
}

final class LoginBootstrapResult {
  const LoginBootstrapResult({
    required this.login,
    required this.syncState,
    required this.effectiveToken,
    this.login2,
  });

  final LoginResponse login;
  final Login2Response? login2;
  final SyncState syncState;
  final String effectiveToken;

  Object? get profile =>
      login2?.profile != null && login.login2Flags?.profileEnabled == true
          ? login2!.profile
          : login.profile ?? login2?.profile;

  List<Object?> get contacts =>
      login2 != null && login.login2Flags?.contactEnabled == true
          ? login2!.contacts
          : login.contacts;
}

Map<String, Object?> _stringMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field response payload must be a map.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$field response contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?> _optionalList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return const <Object?>[];
  if (value is! List) {
    throw FormatException('LOGIN field "$key" must be a list or null.');
  }
  return List<Object?>.unmodifiable(value);
}

int? _optionalInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Field "$key" must be an integer or null.');
}

bool? _optionalBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! bool) {
    throw FormatException('Field "$key" must be a boolean or null.');
  }
  return value;
}
