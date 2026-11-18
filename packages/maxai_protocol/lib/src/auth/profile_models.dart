import 'login_models.dart';

/// Типизированный профиль MAX.
///
/// Неизвестные поля сохраняются в raw, чтобы расширять модель без потери
/// данных при изменениях серверного протокола.
final class MaxUserProfile {
  const MaxUserProfile({
    required this.raw,
    this.contact,
    this.profileOptions = const <Object?>[],
  });

  final Map<String, Object?> raw;
  final MaxUserContact? contact;
  final List<Object?> profileOptions;

  factory MaxUserProfile.fromPayload(Object? value) {
    final map = _profileMap(value, 'profile');
    final contactValue = map['contact'];
    return MaxUserProfile(
      raw: Map<String, Object?>.unmodifiable(map),
      contact: contactValue == null
          ? null
          : MaxUserContact.fromPayload(contactValue),
      profileOptions: _profileList(map, 'profileOptions'),
    );
  }

  String? get displayName {
    final names = contact?.names ?? const <MaxUserName>[];
    if (names.isEmpty) return null;
    final preferred = names.firstWhere(
      (item) => item.type == 'ONEME',
      orElse: () => names.first,
    );
    final fullName = <String>[
      if ((preferred.firstName ?? '').isNotEmpty) preferred.firstName!,
      if ((preferred.lastName ?? '').isNotEmpty) preferred.lastName!,
    ].join(' ').trim();
    return fullName.isNotEmpty ? fullName : preferred.name;
  }

  @override
  String toString() =>
      'MaxUserProfile(contact: ${contact != null}, '
      'profileOptions: ${profileOptions.length})';
}

/// Контакт владельца профиля. Ссылки на изображения и URL не раскрываются
/// в toString и не должны попадать в диагностические логи.
final class MaxUserContact {
  const MaxUserContact({
    required this.raw,
    this.id,
    this.updateTime,
    this.registrationTime,
    this.photoId,
    this.accountStatus,
    this.country,
    this.names = const <MaxUserName>[],
    this.options = const <String>[],
  });

  final Map<String, Object?> raw;
  final int? id;
  final int? updateTime;
  final int? registrationTime;
  final int? photoId;
  final int? accountStatus;
  final String? country;
  final List<MaxUserName> names;
  final List<String> options;

  factory MaxUserContact.fromPayload(Object? value) {
    final map = _profileMap(value, 'profile.contact');
    return MaxUserContact(
      raw: Map<String, Object?>.unmodifiable(map),
      id: _profileInt(map, 'id'),
      updateTime: _profileInt(map, 'updateTime'),
      registrationTime: _profileInt(map, 'registrationTime'),
      photoId: _profileInt(map, 'photoId'),
      accountStatus: _profileInt(map, 'accountStatus'),
      country: _profileString(map, 'country'),
      names: _profileList(map, 'names')
          .map(MaxUserName.fromPayload)
          .toList(growable: false),
      options: _profileList(map, 'options')
          .whereType<String>()
          .toList(growable: false),
    );
  }

  @override
  String toString() =>
      'MaxUserContact(id: ${id == null ? "unset" : "set"}, '
      'names: ${names.length}, options: ${options.length})';
}

final class MaxUserName {
  const MaxUserName({
    this.name,
    this.firstName,
    this.lastName,
    this.type,
  });

  final String? name;
  final String? firstName;
  final String? lastName;
  final String? type;

  factory MaxUserName.fromPayload(Object? value) {
    final map = _profileMap(value, 'profile.contact.names[]');
    return MaxUserName(
      name: _profileString(map, 'name'),
      firstName: _profileString(map, 'firstName'),
      lastName: _profileString(map, 'lastName'),
      type: _profileString(map, 'type'),
    );
  }
}

/// Авторизованная сессия приложения. Токен существует только в памяти.
///
/// Не сериализуется автоматически и никогда не раскрывается через toString.
final class MaxAuthenticatedSession {
  const MaxAuthenticatedSession({
    required this.token,
    required this.login,
    required this.profile,
    required this.createdAt,
  });

  final String token;
  final LoginBootstrapResult login;
  final MaxUserProfile? profile;
  final DateTime createdAt;

  factory MaxAuthenticatedSession.fromLogin(LoginBootstrapResult result) {
    final rawProfile = result.profile;
    return MaxAuthenticatedSession(
      token: result.effectiveToken,
      login: result,
      profile: rawProfile == null
          ? null
          : MaxUserProfile.fromPayload(rawProfile),
      createdAt: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'MaxAuthenticatedSession(tokenSet: ${token.isNotEmpty}, '
      'profileSet: ${profile != null}, createdAt: $createdAt)';
}

Map<String, Object?> _profileMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be a map.');
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

List<Object?> _profileList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return const <Object?>[];
  if (value is! List) throw FormatException('$key must be a list or null.');
  return List<Object?>.unmodifiable(value);
}

String? _profileString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string or null.');
  return value;
}

int? _profileInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('$key must be an integer or null.');
}
