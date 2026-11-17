/// Разобранный ответ на SESSION_INIT.
final class HandshakeResponse {
  const HandshakeResponse({
    this.callsSeed,
    this.appUpdateType,
    required this.raw,
  });

  final int? callsSeed;
  final int? appUpdateType;
  final Map<String, Object?> raw;

  factory HandshakeResponse.fromPayload(Object? payload) {
    if (payload is! Map<Object?, Object?>) {
      throw FormatException(
        'SESSION_INIT response payload must be a map, got ${payload.runtimeType}.',
      );
    }

    final normalized = <String, Object?>{};
    for (final entry in payload.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'SESSION_INIT response contains a non-string key.',
        );
      }
      normalized[entry.key as String] = entry.value;
    }

    return HandshakeResponse(
      callsSeed: _readOptionalInt(normalized, 'callsSeed'),
      appUpdateType: _readOptionalInt(normalized, 'app-update-type'),
      raw: Map<String, Object?>.unmodifiable(normalized),
    );
  }

  static int? _readOptionalInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw FormatException('SESSION_INIT field "$key" must be numeric.');
  }
}
